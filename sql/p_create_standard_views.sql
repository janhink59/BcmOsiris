IF OBJECT_ID('p_create_standard_views') IS NOT NULL 
	DROP PROCEDURE p_create_standard_views;
GO

/* =============================================================================
 * Procedura: p_create_standard_views
 * Účel: Automatické generování RAC/SSC pohledů pro objektové tabulky s prefixem vrepo_
 * 
 * POZNÁMKA K CHYBĚJÍCÍM METADATŮM (HISTORICKÝ KONTEXT):
 * Původní procedura p_repo_create_standard_views (z knihovny OsirisLib) spoléhala na 
 * metadatové tabulky (jako repo_attribute, php_page_column) k přesnému určení, 
 * které sloupce se mají překládat (translate) a které z nich může tenant přepsat.
 * V tomto novém projektu tyto staré metadatové tabulky zatím záměrně nejsou.
 * 
 * SOUČASNÉ ŘEŠENÍ (HEURISTIKA):
 * Abychom proceduru zcela osamostatnili a nemuseli se vracet ke starému kódu,
 * využíváme dočasnou heuristiku nad systémovým pohledem v_syscolumns.
 * - Je-li to architektonický sloupec (uuid, record_type, jazyk, vazby), označí se jako METADATA (nelze měnit/překládat).
 * - Je-li to textový varchar/ntext sloupec bez technického prefixu, označí se pro PŘEKLAD (translate).
 * - Všechny ostatní (byznysové bity, čísla) jsou standardně připraveny na OVERRIDE tenanta.
 * 
 * BUDOUCÍ ÚPRAVA:
 * Jakmile budou vytvořeny nové metadatové struktury specifikující přesně modifikovatelné 
 * a přeložitelné sloupce, stačí upravit pouze blok INSERT INTO @c, kde se heuristika
 * nahradí JOINem na tyto nové metadatové tabulky. Zbytek procedury (generování pohledů) 
 * zůstane beze změny.
 * ============================================================================= */
CREATE PROCEDURE p_create_standard_views
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- 1. Hromadné odstranění všech existujících pohledů s prefixem vrepo_
	DECLARE @drop_sql NVARCHAR(MAX) = '';
	SELECT @drop_sql = @drop_sql + 'DROP VIEW ' + QUOTENAME(name) + ';' + CHAR(13)
	FROM sys.views 
	WHERE name LIKE 'vrepo\_%' ESCAPE '\';
	
	IF @drop_sql <> '' 
	BEGIN
		EXEC(@drop_sql);
		PRINT 'Existující pohledy vrepo_ byly úspěšně odstraněny.';
	END

	-- 2. Zjištění všech tabulek, které podléhají RAC architektuře
	DECLARE @t TABLE (tabname VARCHAR(128) NOT NULL PRIMARY KEY);
	
	-- OPRAVA: Tabulka musí mít nejen uuid jako PK, ale i všechny 3 další definující RAC sloupce
	INSERT INTO @t (tabname)
	SELECT c_uuid.tabname 
	FROM v_syscolumns c_uuid
	JOIN v_syscolumns c_owner ON c_owner.tabname = c_uuid.tabname AND c_owner.colname = 'object_owner'
	JOIN v_syscolumns c_orig ON c_orig.tabname = c_uuid.tabname AND c_orig.colname = 'original'
	JOIN v_syscolumns c_rectype ON c_rectype.tabname = c_uuid.tabname AND c_rectype.colname = 'record_type'
	WHERE c_uuid.colname = 'uuid' AND c_uuid.typename = 'uniqueidentifier' AND c_uuid.keyno = 1;

	-- 3. Načtení sloupců a určení vlastností (metadata vs byznys, překladatelnost)
	-- ZDE SE V BUDOUCNU NAPOJÍ NOVÉ METADATOVÉ TABULKY
	DECLARE @c TABLE (
		tabname VARCHAR(128),
		colname VARCHAR(128),
		typename VARCHAR(128),
		colid INT,
		is_metadata BIT,
		translate BIT
	);
	
	INSERT INTO @c (tabname, colname, typename, colid, is_metadata, translate)
	SELECT 
		v.tabname, 
		v.colname, 
		v.typename, 
		v.colid,
		-- Heuristická detekce čistě architektonických RAC/SSC sloupců
		CASE 
			WHEN v.colname IN ('uuid', 'object_owner', 'original', 'record_type', 'approval_status', 'language', 'inactive', 'removed', 'valid_from', 'valid_to', 'is_template', 'template', 'date_created', 'who_created', 'date_modified', 'who_modified') THEN 1 
			ELSE 0 
		END,
		-- Heuristická detekce překladatelných textových sloupců
		CASE 
			WHEN v.colname IN ('uuid', 'object_owner', 'original', 'record_type', 'approval_status', 'language', 'inactive', 'removed', 'valid_from', 'valid_to', 'is_template', 'template', 'date_created', 'who_created', 'date_modified', 'who_modified') THEN 0
			WHEN v.colname IN ('code', 'sort_code', 'group_code', 'builtin_code', 'class_name', 'login_domain', 'login_name', 'email', 'external_code', 'instance_class_name', 'password_hash') THEN 0
			WHEN v.colname LIKE '%_uuid' THEN 0
			WHEN v.colname LIKE '%_code' THEN 0
			WHEN v.colname IN ('shortname', 'caption', 'description_text', 'help_text', 'note') THEN 1
			WHEN v.typename IN ('text', 'ntext') THEN 1
			WHEN v.typename IN ('varchar', 'nvarchar') AND (v.prec >= 100 OR v.prec < 0) THEN 1
			ELSE 0 
		END
	FROM @t t
	JOIN v_syscolumns v ON v.tabname = t.tabname;

	-- 4. Kurzor pro generování samotných pohledů
	DECLARE @tabname VARCHAR(128);
	DECLARE @sql NVARCHAR(MAX);
	DECLARE @select_list NVARCHAR(MAX);
	DECLARE @has_language BIT;
	
	DECLARE cur CURSOR FOR SELECT tabname FROM @t;
	OPEN cur;
	FETCH NEXT FROM cur INTO @tabname;
	
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @select_list = '';
		
		-- Zjištění, zda tabulka podporuje jazyky
		IF EXISTS (SELECT 1 FROM @c WHERE tabname = @tabname AND colname = 'language')
			SET @has_language = 1;
		ELSE
			SET @has_language = 0;

		-- 4.A Sestavení SELECT listu
		SELECT @select_list = @select_list + '
		' + 
		CASE 
			WHEN is_metadata = 1 THEN ', m.[' + colname + ']'
			WHEN translate = 1 AND @has_language = 1 THEN '
		, COALESCE(NULLIF(CAST(v.['+colname+'] AS VARCHAR(MAX)), ''''), NULLIF(CAST(l.['+colname+'] AS VARCHAR(MAX)), ''''), CAST(m.['+colname+'] AS VARCHAR(MAX)), CAST(o.['+colname+'] AS VARCHAR(MAX)), '''') AS ['+colname+']
		, CAST(l.['+colname+'] AS VARCHAR(MAX)) AS ['+colname+'_translated]
		, CAST(m.['+colname+'] AS VARCHAR(MAX)) AS ['+colname+'_original]
		, o.['+colname+'] AS ['+colname+'_system]'
			WHEN translate = 1 AND @has_language = 0 THEN '
		, CAST(m.['+colname+'] AS VARCHAR(MAX)) AS ['+colname+']
		, CAST(m.['+colname+'] AS VARCHAR(MAX)) AS ['+colname+'_original]
		, o.['+colname+'] AS ['+colname+'_system]'
			ELSE '
		, m.['+colname+']
		, o.['+colname+'] AS ['+colname+'_system]' 
		END
		FROM @c 
		WHERE tabname = @tabname
		ORDER BY colid;
		
		-- Odstranění první oddělovací čárky
		SET @select_list = STUFF(@select_list, 1, 4, '  ');
		
		-- Přidání identifikátoru původu záznamu
		SET @select_list = @select_list + '
		, m.object_is_mine';

		-- 4.B Sestavení těla pohledu (s prefixem vrepo_)
		SET @sql = '
CREATE VIEW vrepo_' + @tabname + ' AS
WITH s AS (
	SELECT organization AS organization_uuid, language 
	FROM dbsession 
	WHERE spid = @@SPID
),
sy AS (
	-- Všechny systémové záznamy
	SELECT rc.*, CAST(0 AS BIT) AS object_is_mine
	FROM s
	JOIN ' + @tabname + ' rc ON rc.object_owner = 0x00 AND rc.record_type = ''A''
),
my AS (
	-- Vlastní platné záznamy (overridy tenanta)
	SELECT rc.*, CAST(1 AS BIT) AS object_is_mine
	FROM s
	JOIN ' + @tabname + ' rc ON rc.object_owner = s.organization_uuid AND rc.record_type = ''A''
	WHERE rc.removed = 0
),
mix AS (
	-- Kombinace: systémové záznamy bez lokálního override UNION všechny vlastní
	SELECT sy.* 
	FROM sy
	LEFT JOIN my ON my.original = sy.original
	WHERE sy.removed = 0 AND my.original IS NULL
	UNION ALL
	SELECT * FROM my
)
SELECT ' + @select_list + '
FROM s
CROSS JOIN mix m
-- o = Originál systémový (0x00) pro přístup k defaultním hodnotám netextových sloupců
LEFT JOIN ' + @tabname + ' o ON o.original = m.original AND o.object_owner = 0x00 AND o.record_type = ''A''';

		-- 4.C Připojení jazykových mutací
		IF @has_language = 1
		BEGIN
			SET @sql = @sql + '
-- l = Systémový překlad
LEFT JOIN ' + @tabname + ' l ON l.original = m.original AND l.object_owner = 0x00 AND l.language = s.language AND l.record_type = ''L'' AND l.removed = 0
-- v = Vlastní překlad (tenant override překladu)
LEFT JOIN ' + @tabname + ' v ON v.original = m.original AND v.object_owner = s.organization_uuid AND v.language = s.language AND v.record_type = ''L'' AND v.removed = 0';
		END

		-- 5. Exekuce vytvoření pohledu
		EXEC (@sql);
		PRINT 'Generován standardní pohled: vrepo_' + @tabname;

		FETCH NEXT FROM cur INTO @tabname;
	END
	
	CLOSE cur;
	DEALLOCATE cur;
END
GO