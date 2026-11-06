/* =============================================================================
 * Verze: 2026-11-06 14:15
 * Soubor: p_csv_import_simple_class.sql
 * Procedura: dbo.p_csv_import_simple_class
 * Účel:   Zpracování Fáze 2 dvoufázového CSV importu pro balíček "simple_class"
 *         (export a import dat jedné logické třídy v rámci organizace).
 *         - Ověří parametr same_org_only (zákaz importu do jiné organizace, pokud
 *           bylo omezení při exportu zapnuto).
 *         - Zjistí cílovou fyzickou tabulku třídy (a případnou sekundární hierarchii).
 *         - Naplní dočasnou tabulku #imp pomocí dbo.p_csv_fill_table, vynutí
 *           object_owner = @org_uuid (aktuální organizace z dbsession), přepočte
 *           deterministický identifikátor original pro cílového tenanta (včetně
 *           přemapování vnitrodávkových vazeb parent_uuid) a uloží hlavní záznamy
 *           'A' i všechny exportované jazykové mutace 'L' (L1, L2, L3...).
 *         - Podporuje jak přímý zápis schválených záznamů (@target_status = 'A')
 *           s Delta kontrolou změn přes EXCEPT, tak uložení do návrhů ke schválení
 *           (@target_status = 'F', record_type = 'D', approval_status = 'F').
 *
 * Vazby na okolí:
 * - Volána z PHP metody abstract_csv_package::run_import() při package_code = 'simple_class'.
 * - Využívá proceduru dbo.p_csv_fill_table a funkci dbo.f_csv_param (p_csv_fill_table.sql).
 * - Využívá funkce dbo.f_syscolumns, dbo.f_generate_original a tabulku meta_original_keys.
 * - Zapisuje výsledkové zprávy do tabulky request_message přes insert_request_message.
 * ============================================================================= */

EXECUTE dropni 'p_csv_import_simple_class', 'P';
GO

CREATE PROCEDURE dbo.p_csv_import_simple_class
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @org_uuid uniqueidentifier = 0x00;
	DECLARE @user_account uniqueidentifier = 0x00;
	DECLARE @user_session uniqueidentifier = 0x00;
	DECLARE @sess_lang varchar(2) = 'cs';

	SELECT TOP 1
		@org_uuid = ISNULL(organization, 0x00),
		@user_account = ISNULL(user_account, 0x00),
		@user_session = ISNULL(login_session_uuid, 0x00),
		@sess_lang = ISNULL([language], 'cs')
	FROM dbsession
	WHERE spid = @@SPID;

	-- 1. Načtení řídicích parametrů balíčku ze session_import_parameter
	DECLARE @class_name varchar(80) = LTRIM(RTRIM(dbo.f_csv_param('class_name', '')));
	DECLARE @target_status varchar(1) = UPPER(LTRIM(RTRIM(dbo.f_csv_param('target_status', 'F'))));
	DECLARE @same_org_only varchar(10) = LTRIM(RTRIM(dbo.f_csv_param('same_org_only', '0')));
	DECLARE @source_org_str varchar(60) = LTRIM(RTRIM(dbo.f_csv_param('source_org_uuid', '')));
	DECLARE @import_origin varchar(255) = NULLIF(LTRIM(RTRIM(dbo.f_csv_param('import_origin', ''))), '');
	DECLARE @export_languages varchar(20) = LTRIM(RTRIM(dbo.f_csv_param('export_languages', 'ALL')));

	IF @target_status NOT IN ('A', 'F')
		SET @target_status = 'F';

	-- 2. Bezpečnostní kontrola omezení importu na stejnou organizaci (same_org_only = 1)
	IF @same_org_only = '1'
	BEGIN
		DECLARE @src_org_uuid uniqueidentifier = CASE
			WHEN LOWER(@source_org_str) IN ('0x00', '00000000-0000-0000-0000-000000000000') THEN CAST(0x00 AS uniqueidentifier)
			ELSE TRY_CONVERT(uniqueidentifier, @source_org_str)
		END;

		IF @src_org_uuid IS NULL OR @src_org_uuid <> @org_uuid
		BEGIN
			EXEC insert_request_message 'Import zamítnut: Balíček má nastaveno omezení importu pouze do stejné organizace (same_org_only = 1).', 3, @obj_type = 'Organizace', @obj_name = @source_org_str;
			RETURN;
		END
	END

	-- 3. Dohledání cílové logické třídy a její fyzické úložné tabulky
	IF @class_name = ''
	BEGIN
		EXEC insert_request_message 'V parametrech balíčku chybí povinný parametr class_name.', 3, @obj_type = 'Parametr', @obj_name = 'class_name';
		RETURN;
	END

	DECLARE @storage_table varchar(128) = '';
	SELECT TOP 1
		@storage_table = mo.builtin_code
	FROM meta_class mc
	JOIN meta_object mo
		ON mo.original = mc.storage_object
		AND mo.object_type = 'T'
		AND mo.record_type = 'A'
		AND mo.removed = 0
	WHERE mc.class_name = @class_name
	  AND mc.object_owner IN (0x00, @org_uuid)
	  AND mc.record_type = 'A'
	  AND mc.removed = 0
	ORDER BY CASE WHEN mc.object_owner = @org_uuid THEN 0 ELSE 1 END;

	IF @storage_table = '' OR OBJECT_ID(@storage_table, 'U') IS NULL
	BEGIN
		EXEC insert_request_message 'Cílová logická třída nebo její úložná tabulka nebyla v databázi nalezena.', 3, @obj_type = 'Třída', @obj_name = @class_name;
		RETURN;
	END

	IF @storage_table LIKE 'meta_%' OR @storage_table IN ('organization', 'user_account', 'user_organization_access')
	BEGIN
		EXEC insert_request_message 'Tuto systémovou tabulku nelze importovat balíčkem simple_class.', 3, @obj_type = 'Tabulka', @obj_name = @storage_table;
		RETURN;
	END

	-- Pokud jde o odvozenou třídu sekundární hierarchie (STI nad hierarchy_item), zjistíme její UUID
	DECLARE @hier_uuid uniqueidentifier = NULL;
	IF @storage_table = 'hierarchy_item' AND @class_name <> 'hierarchy_item'
	BEGIN
		SELECT TOP 1 @hier_uuid = original
		FROM hierarchy
		WHERE builtin_code = @class_name
		  AND object_owner IN (@org_uuid, 0x00)
		  AND record_type = 'A'
		  AND removed = 0
		ORDER BY CASE WHEN object_owner = @org_uuid THEN 0 ELSE 1 END;

		IF @hier_uuid IS NULL
		BEGIN
			EXEC insert_request_message 'Nadřazená sekundární hierarchie pro tuto třídu v cílové organizaci neexistuje.', 3, @obj_type = 'Hierarchie', @obj_name = @class_name;
			RETURN;
		END
	END

	-- 4. Zjištění klíčových sloupců z meta_original_keys a sestavení seznamů datových sloupců
	DECLARE @key1_col varchar(128) = NULL, @key2_col varchar(128) = NULL;
	SELECT @key1_col = key1_column, @key2_col = key2_column
	FROM meta_original_keys
	WHERE table_name = @storage_table;

	DECLARE @has_parent_col bit = CASE WHEN COL_LENGTH(@storage_table, 'parent_uuid') IS NOT NULL THEN 1 ELSE 0 END;
	DECLARE @has_hier_col bit = CASE WHEN COL_LENGTH(@storage_table, 'hierarchy') IS NOT NULL THEN 1 ELSE 0 END;

	DECLARE @set_list nvarchar(max) = N'';
	DECLARE @t_cols nvarchar(max) = N'';
	DECLARE @s_cols nvarchar(max) = N'';
	DECLARE @ins_cols nvarchar(max) = N'';
	DECLARE @s_cols_prefixed nvarchar(max) = N'';

	SELECT
		@set_list = @set_list + N', t.[' + colname + N'] = s.[' + colname + N']',
		@t_cols   = @t_cols   + N', t.[' + colname + N']',
		@s_cols   = @s_cols   + N', s.[' + colname + N']',
		@ins_cols = @ins_cols + N', [' + colname + N']'
	FROM dbo.f_syscolumns(@storage_table)
	WHERE iscomputed = 0
	  AND is_identity = 0
	  AND colname NOT IN (
		'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
		'draft_author', 'approval_note', 'import_origin',
		'date_created', 'who_created', 'date_modified', 'who_modified'
	  )
	ORDER BY colid;

	SET @set_list        = SUBSTRING(@set_list, 3, 2000000);
	SET @t_cols          = SUBSTRING(@t_cols, 3, 2000000);
	SET @s_cols          = SUBSTRING(@s_cols, 3, 2000000);
	SET @s_cols_prefixed = N', ' + @s_cols;

	-- Sestavení SQL bloku pro přepočet deterministického originálu v cílové organizaci a přemapování parent_uuid
	DECLARE @recalc_orig_sql nvarchar(max) = N'';
	IF @key1_col IS NOT NULL
	BEGIN
		DECLARE @k1_expr nvarchar(300) = N'CAST(s.[' + @key1_col + N'] AS varchar(max))';
		DECLARE @k2_expr nvarchar(300) = CASE WHEN @key2_col IS NOT NULL THEN N'CAST(s.[' + @key2_col + N'] AS varchar(max))' ELSE N'NULL' END;
		DECLARE @join_p_expr nvarchar(500) = N'p.[' + @key1_col + N'] = s.[' + @key1_col + N']'
			+ CASE WHEN @key2_col IS NOT NULL THEN N' AND p.[' + @key2_col + N'] = s.[' + @key2_col + N']' ELSE N'' END;

		SET @recalc_orig_sql = N'
		DECLARE @orig_map TABLE (
			old_orig uniqueidentifier NOT NULL PRIMARY KEY,
			new_orig uniqueidentifier NOT NULL
		);

		INSERT INTO @orig_map (old_orig, new_orig)
		SELECT
			s.original,
			dbo.f_generate_original(
				''' + @storage_table + N''',
				ISNULL(p.object_owner, @p_org),
				' + @k1_expr + N',
				' + @k2_expr + N'
			)
		FROM (
			SELECT original, [' + @key1_col + N']' + CASE WHEN @key2_col IS NOT NULL THEN N', [' + @key2_col + N']' ELSE N'' END + N',
				ROW_NUMBER() OVER (PARTITION BY original ORDER BY CASE WHEN record_type = ''A'' THEN 0 ELSE 1 END) AS rn
			FROM #imp
			WHERE original IS NOT NULL AND original <> 0x00
		) s
		LEFT JOIN [' + @storage_table + N'] p
			ON ' + @join_p_expr + N'
			AND p.object_owner = 0x00
			AND p.record_type = ''A''
			AND p.removed = 0
		WHERE s.rn = 1;

		' + CASE WHEN @has_parent_col = 1 THEN N'
		UPDATE s
		SET s.parent_uuid = m_par.new_orig
		FROM #imp s
		JOIN @orig_map m_par ON m_par.old_orig = s.parent_uuid
		WHERE m_par.new_orig <> m_par.old_orig;' ELSE N'' END + N'

		UPDATE s
		SET s.original = m.new_orig,
			s.uuid = CASE WHEN s.record_type = ''A'' THEN m.new_orig ELSE NEWID() END
		FROM #imp s
		JOIN @orig_map m ON m.old_orig = s.original;';
	END

	DECLARE @hier_force_sql nvarchar(300) = CASE
		WHEN @has_hier_col = 1 AND @hier_uuid IS NOT NULL THEN N'UPDATE #imp SET hierarchy = @p_hier;'
		ELSE N''
	END;

	-- 5. Sestavení a spuštění dynamické T-SQL dávky pro naplnění #imp a zápis dat (režim A nebo F)
	DECLARE @sql nvarchar(max) = N'
	SELECT TOP 0 * INTO #imp FROM [' + @storage_table + N'];

	DECLARE @rc int = 0;
	EXEC @rc = dbo.p_csv_fill_table ''#imp'', ''' + @storage_table + N''';

	IF @rc <= 0
	BEGIN
		EXEC insert_request_message ''V CSV souboru nebyly nalezeny žádné datové řádky pro import.'', 2, @obj_type = ''Tabulka'', @obj_name = @p_tab;
		RETURN;
	END

	UPDATE #imp SET object_owner = @p_org;
	' + @hier_force_sql + N'
	' + @recalc_orig_sql + N'

	-- Pokud pro některý záznam přišly v CSV pouze řádky L bez hlavního řádku A a záznam dosud v DB nemá A, vytvoříme v #imp výchozí A z prvního L
	INSERT INTO #imp (
		uuid, object_owner, original, record_type, approval_status,
		draft_author, approval_note, import_origin,
		date_created, who_created, date_modified, who_modified' + @ins_cols + N'
	)
	SELECT
		s.original, @p_org, s.original, ''A'', ''A'',
		0x00, '''', @p_origin,
		GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
	FROM (
		SELECT *, ROW_NUMBER() OVER (PARTITION BY original ORDER BY [language] ASC) AS rn
		FROM #imp
		WHERE record_type = ''L''
	) s
	WHERE s.rn = 1
	  AND NOT EXISTS (SELECT 1 FROM #imp a WHERE a.original = s.original AND a.record_type = ''A'')
	  AND NOT EXISTS (SELECT 1 FROM [' + @storage_table + N'] ex WHERE ex.original = s.original AND ex.object_owner IN (@p_org, 0x00) AND ex.record_type = ''A'');

	IF @p_status = ''A''
	BEGIN
		DECLARE @chg_a int = 0, @chg_l int = 0;

		-- A.1) Delta UPDATE existujících hlavních záznamů (record_type = ''A'') aktuální organizace
		UPDATE t
		SET ' + @set_list + N',
			t.approval_status = ''A'',
			t.draft_author = 0x00,
			t.approval_note = '''',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @storage_table + N'] t
		JOIN #imp s ON s.original = t.original AND s.record_type = ''A''
		WHERE t.object_owner = @p_org
		  AND t.record_type = ''A''
		  AND EXISTS (
			SELECT ' + @t_cols + N'
			EXCEPT
			SELECT ' + @s_cols + N'
		  );

		SET @chg_a = @@ROWCOUNT;

		-- A.2) INSERT nových hlavních záznamů (record_type = ''A'') aktuální organizace
		INSERT INTO [' + @storage_table + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			CASE WHEN EXISTS (SELECT 1 FROM [' + @storage_table + N'] ex WHERE ex.uuid = s.original) THEN NEWID() ELSE s.original END,
			@p_org, s.original, ''A'', ''A'',
			0x00, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM #imp s
		WHERE s.record_type = ''A''
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @storage_table + N'] t
			WHERE t.original = s.original AND t.object_owner = @p_org AND t.record_type = ''A''
		  );

		SET @chg_a = @chg_a + @@ROWCOUNT;

		-- L.1) Delta UPDATE všech exportovaných jazykových mutací (record_type = ''L'', L1+L2+L3...)
		UPDATE t
		SET ' + @set_list + N',
			t.approval_status = ''A'',
			t.draft_author = 0x00,
			t.approval_note = '''',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @storage_table + N'] t
		JOIN #imp s ON s.original = t.original AND s.record_type = ''L'' AND s.[language] = t.[language]
		WHERE t.object_owner = @p_org
		  AND t.record_type = ''L''
		  AND EXISTS (
			SELECT ' + @t_cols + N'
			EXCEPT
			SELECT ' + @s_cols + N'
		  );

		SET @chg_l = @@ROWCOUNT;

		-- L.2) INSERT nových jazykových mutací (record_type = ''L'', L1+L2+L3...)
		INSERT INTO [' + @storage_table + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			NEWID(), @p_org, s.original, ''L'', ''A'',
			0x00, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM #imp s
		WHERE s.record_type = ''L''
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @storage_table + N'] t
			WHERE t.original = s.original AND t.object_owner = @p_org AND t.record_type = ''L'' AND t.[language] = s.[language]
		  );

		SET @chg_l = @chg_l + @@ROWCOUNT;

		-- L.3) Pojistka symetrického L záznamu pro hlavní A záznamy, pokud v CSV nebyl řádek L pro mateřský jazyk A
		INSERT INTO [' + @storage_table + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			NEWID(), @p_org, s.original, ''L'', ''A'',
			0x00, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM #imp s
		WHERE s.record_type = ''A''
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @storage_table + N'] t
			WHERE t.original = s.original AND t.object_owner = @p_org AND t.record_type = ''L'' AND t.[language] = s.[language]
		  );

		SET @chg_l = @chg_l + @@ROWCOUNT;

		-- Jednotná auditní stopa na hlavním A záznamu při změně v L
		UPDATE a
		SET a.date_modified = l.date_modified,
			a.who_modified = l.who_modified
		FROM [' + @storage_table + N'] a
		JOIN [' + @storage_table + N'] l
			ON l.original = a.original
			AND l.object_owner = @p_org
			AND l.record_type = ''L''
		WHERE a.object_owner = @p_org
		  AND a.record_type = ''A''
		  AND l.date_modified > a.date_modified;

		DECLARE @tot_a int = @chg_a + @chg_l;
		EXEC insert_request_message ''Přímý import třídy dokončen (zpracované záznamy A + všechny jazykové mutace L)'', 1, @intvalue = @tot_a, @obj_type = ''Třída'', @obj_name = @p_cls;
	END
	ELSE
	BEGIN
		-- REŽIM NÁVRHŮ KE SCHVÁLENÍ (@p_status = ''F''):
		-- Pro každý importovaný jazyk (primární A/L i další jazykové mutace L2, L3...) vytvoříme/aktualizujeme návrh D se stavem F
		SELECT TOP 0 * INTO #draft_src FROM [' + @storage_table + N'];

		-- 1. Primární jazyk ze záznamu A
		INSERT INTO #draft_src (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			NEWID(), @p_org, s.original, ''D'', ''F'',
			@p_user_acc, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM #imp s
		WHERE s.record_type = ''A'';

		-- 2. Další jazykové mutace L (L1, L2, L3...), které ještě v #draft_src pro daný (original, language) nejsou
		INSERT INTO #draft_src (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			NEWID(), @p_org, s.original, ''D'', ''F'',
			@p_user_acc, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM #imp s
		WHERE s.record_type = ''L''
		  AND NOT EXISTS (
			SELECT 1 FROM #draft_src d
			WHERE d.original = s.original AND d.[language] = s.[language]
		  );

		DECLARE @chg_d int = 0;

		-- Aktualizace existujících návrhů D téhož autora a jazyka
		UPDATE t
		SET ' + @set_list + N',
			t.approval_status = ''F'',
			t.draft_author = @p_user_acc,
			t.approval_note = '''',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @storage_table + N'] t
		JOIN #draft_src s ON s.original = t.original AND s.[language] = t.[language]
		WHERE t.object_owner = @p_org
		  AND t.record_type = ''D''
		  AND (t.draft_author = @p_user_acc OR t.draft_author = 0x00);

		SET @chg_d = @@ROWCOUNT;

		-- Vložení nových návrhů D se stavem F (pouze pokud se liší od stávajícího schváleného stavu v DB nebo záznam v DB ještě neexistuje)
		INSERT INTO [' + @storage_table + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			NEWID(), @p_org, s.original, ''D'', ''F'',
			@p_user_acc, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM #draft_src s
		LEFT JOIN [' + @storage_table + N'] ex
			ON ex.original = s.original
			AND ex.object_owner = @p_org
			AND ex.record_type = ''L''
			AND ex.[language] = s.[language]
			AND ex.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM [' + @storage_table + N'] d
			WHERE d.original = s.original
			  AND d.object_owner = @p_org
			  AND d.record_type = ''D''
			  AND d.[language] = s.[language]
			  AND (d.draft_author = @p_user_acc OR d.draft_author = 0x00)
		  )
		  AND (
			ex.uuid IS NULL
			OR EXISTS (
				SELECT ' + REPLACE(@t_cols, 't.[', 'ex.[') + N'
				EXCEPT
				SELECT ' + @s_cols + N'
			)
		  );

		SET @chg_d = @chg_d + @@ROWCOUNT;

		DROP TABLE #draft_src;
		EXEC insert_request_message ''Import třídy uložen do návrhů ke schválení (stav F)'', 1, @intvalue = @chg_d, @obj_type = ''Třída'', @obj_name = @p_cls;
	END

	DROP TABLE #imp;';

	EXEC sp_executesql
		@stmt = @sql,
		@params = N'@p_org uniqueidentifier, @p_user uniqueidentifier, @p_user_acc uniqueidentifier, @p_origin varchar(255), @p_status varchar(1), @p_tab varchar(128), @p_cls varchar(80), @p_hier uniqueidentifier',
		@p_org = @org_uuid,
		@p_user = @user_session,
		@p_user_acc = @user_account,
		@p_origin = @import_origin,
		@p_status = @target_status,
		@p_tab = @storage_table,
		@p_cls = @class_name,
		@p_hier = @hier_uuid;
END
GO