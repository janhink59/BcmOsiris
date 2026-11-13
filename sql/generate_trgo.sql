/* =============================================================================
 * Verze: 2026-11-13 18:30
 * Soubor: generate_trgo.sql
 * DÁVKA: Generátor deterministických triggerů (trgo_%)
 * Účel: Hromadné odstranění a znovuvytvoření triggerů pro vazební a katalogové tabulky.
 *       Triggery nastavují deterministické identifikátory (sloupce "uuid" a "original")
 *       při vložení záznamu pro tabulky uvedené v "meta_original_keys", pokud jsou
 *       klíčové sloupce vyplněny a tabulka obsahuje všechny vyžadované RAC sloupce.
 *
 * Vazby na okolí:
 * - Čte seznam tabulek a klíčových sloupců z tabulky meta_original_keys
 *   (plněné skriptem fillup_meta_original_keys.sql).
 * - Využívá deterministickou hashovací funkci dbo.f_generate_original.
 * - Pro tabulku [link] zakládá dedikovaný trigger trgo_link využívající
 *   funkci dbo.f_link_original se 4 klíčovými složkami (link_def, from_object,
 *   to_object, ancestor_link).
 *
 * Změny:
 * - 2026-11-13 18:30: Do kurzoru cur_tables doplněna strukturální kontrola přes
 *   COL_LENGTH, že cílová tabulka skutečně obsahuje všechny sloupce vyžadované
 *   triggerem (uuid, object_owner, original, record_type, removed, template
 *   a klíčové sloupce key1_column / key2_column).
 * - 2026-11-01 18:00: Doplněna podmínka neprázdnosti klíčových sloupců
 *   (@has_key_expr): pokud je builtin_code prázdný, trigger nenapojuje parent
 *   přes prázdný řetězec a nepřepisuje uuid/original deterministickým hashem
 *   prázdného řetězce, ale použije náhodný identifikátor i.uuid (NEWID()).
 * - 2026-10-30 23:35: Trigger trgo_link rozšířen o 4. klíčovou složku ancestor_link.
 * ============================================================================= */
DECLARE @drop_sql NVARCHAR(MAX) = '';

-- 1. Odstranění všech stávajících triggerů s prefixem trgo_
SELECT	@drop_sql = @drop_sql + 'DROP TRIGGER [' + name + '];' + CHAR(13)
FROM	sys.triggers 
WHERE	name LIKE 'trgo\_%' ESCAPE '\';

IF @drop_sql <> '' 
BEGIN
	EXEC(@drop_sql);
END

-- 2. Kurzor načítá pouze vyhovující fyzické tabulky, které mají všechny vyžadované RAC a klíčové sloupce
DECLARE @table_name VARCHAR(128), @key1 VARCHAR(128), @key2 VARCHAR(128);
DECLARE cur_tables CURSOR FOR 
	SELECT table_name, key1_column, key2_column
	FROM meta_original_keys
	WHERE OBJECT_ID(table_name, 'U') IS NOT NULL
	  AND COL_LENGTH(table_name, 'uuid') IS NOT NULL
	  AND COL_LENGTH(table_name, 'object_owner') IS NOT NULL
	  AND COL_LENGTH(table_name, 'original') IS NOT NULL
	  AND COL_LENGTH(table_name, 'record_type') IS NOT NULL
	  AND COL_LENGTH(table_name, 'removed') IS NOT NULL
	  AND COL_LENGTH(table_name, 'template') IS NOT NULL
	  AND COL_LENGTH(table_name, key1_column) IS NOT NULL
	  AND (key2_column IS NULL OR COL_LENGTH(table_name, key2_column) IS NOT NULL);

OPEN cur_tables;
FETCH NEXT FROM cur_tables INTO @table_name, @key1, @key2;

WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @key1_expr VARCHAR(200) = 'CAST(i.[' + @key1 + '] AS VARCHAR(MAX))';
	DECLARE @key2_expr VARCHAR(200) = CASE WHEN @key2 IS NOT NULL THEN 'CAST(i.[' + @key2 + '] AS VARCHAR(MAX))' ELSE 'NULL' END;
	DECLARE @has_key_expr VARCHAR(500) = 'LTRIM(RTRIM(ISNULL(CAST(i.[' + @key1 + '] AS VARCHAR(MAX)), ''''))) <> ''''';
	DECLARE @join_expr VARCHAR(MAX) = 'parent.[' + @key1 + '] = i.[' + @key1 + ']';
	
	IF @key2 IS NOT NULL 
	BEGIN
		SET @has_key_expr = '(' + @has_key_expr + ' AND LTRIM(RTRIM(ISNULL(CAST(i.[' + @key2 + '] AS VARCHAR(MAX)), ''''))) <> '''')';
		SET @join_expr = @join_expr + ' AND parent.[' + @key2 + '] = i.[' + @key2 + ']';
	END

	DECLARE @trg_sql NVARCHAR(MAX) = '
CREATE TRIGGER trgo_' + @table_name + '
ON [' + @table_name + ']
AFTER INSERT
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE t
	SET 
		original = CASE
			WHEN ' + @has_key_expr + ' AND (i.record_type = ''A'' OR i.original = 0x00) THEN
				dbo.f_generate_original(
					''' + @table_name + ''',
					ISNULL(parent.object_owner, i.object_owner),
					' + @key1_expr + ',
					' + @key2_expr + '
				)
			WHEN i.original = 0x00 THEN i.uuid
			ELSE i.original
		END,
		uuid = CASE 
			WHEN ' + @has_key_expr + ' AND i.record_type = ''A'' AND parent.uuid IS NULL THEN 
				dbo.f_generate_original(
					''' + @table_name + ''',
					i.object_owner,
					' + @key1_expr + ',
					' + @key2_expr + '
				)
			ELSE i.uuid 
		END
	FROM [' + @table_name + '] t
	JOIN inserted i ON i.uuid = t.uuid
	LEFT JOIN [' + @table_name + '] parent 
		ON ' + @has_key_expr + '
		AND ' + @join_expr + '
		AND (parent.object_owner = 0x00 OR parent.object_owner = i.template)
		AND parent.record_type = ''A''
		AND parent.removed = 0
		AND parent.uuid <> i.uuid;
END;';

	EXEC(@trg_sql);

	FETCH NEXT FROM cur_tables INTO @table_name, @key1, @key2;
END

CLOSE cur_tables;
DEALLOCATE cur_tables;
GO

/* =============================================================================
 * TRIGGER: trgo_link
 * Účel: Nastavení deterministického identifikátoru vazby při vložení (AFTER INSERT)
 *       s využitím f_link_original (včetně 4. klíčové složky ancestor_link).
 * ============================================================================= */
CREATE TRIGGER trgo_link
ON [link]
AFTER INSERT
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE t
	SET 
		original = CASE
			WHEN i.record_type = 'A' OR i.original = 0x00 THEN
				dbo.f_link_original(
					CAST(ISNULL(parent.object_owner, i.object_owner) AS varchar(36)),
					CAST(i.[link_def] AS varchar(36)),
					CAST(i.[from_object] AS varchar(36)),
					CAST(i.[to_object] AS varchar(36)),
					CAST(i.[ancestor_link] AS varchar(36))
				)
			ELSE i.original
		END,
		uuid = CASE 
			WHEN i.record_type = 'A' AND parent.uuid IS NULL THEN 
				dbo.f_link_original(
					CAST(i.object_owner AS varchar(36)),
					CAST(i.[link_def] AS varchar(36)),
					CAST(i.[from_object] AS varchar(36)),
					CAST(i.[to_object] AS varchar(36)),
					CAST(i.[ancestor_link] AS varchar(36))
				)
			ELSE i.uuid 
		END
	FROM [link] t
	JOIN inserted i ON i.uuid = t.uuid
	LEFT JOIN [link] parent 
		ON parent.[link_def] = i.[link_def]
		AND parent.[from_object] = i.[from_object]
		AND parent.[to_object] = i.[to_object]
		AND parent.[ancestor_link] = i.[ancestor_link]
		AND (parent.object_owner = 0x00 OR parent.object_owner = i.template)
		AND parent.record_type = 'A'
		AND parent.removed = 0
		AND parent.uuid <> i.uuid;
END;
GO