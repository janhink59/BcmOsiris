/* =============================================================================
 * Verze: 2026-10-14 22:45
 * Soubor: generate_trgo.sql
 * DÁVKA: Generátor deterministických triggerů (trgo_%)
 * Účel: Hromadné odstranění a znovuvytvoření triggerů pro vazební tabulky.
 *       Triggery nastavují deterministické identifikátory (sloupce "uuid" a "original")
 *       pro tabulky a jejich primární sloupce uvedené v tabulce "meta_original_keys"
 *
 * Vazby na okolí:
 * - Čte seznam tabulek a klíčových sloupců z tabulky meta_original_keys
 *   (plněné skriptem fillup_meta_original_keys.sql).
 * - Využívá deterministickou hashovací funkci dbo.f_generate_original.
 * - Pro tabulku [link] zakládá dedikovaný trigger trgo_link využívající
 *   funkci dbo.f_link_original se 3 klíčovými složkami.
 *
 * Změny:
 * - 2026-10-14: Oprava přepisu sloupce uuid v triggerech trgo_% a trgo_link.
 *   Deterministické přepsání sloupce uuid se nyní provádí výhradně pro
 *   záznamy s i.record_type = 'A' (když parent.uuid IS NULL), aby jazykové ('L')
 *   a historické ('H') záznamy nikdy nepřepsaly své unikátní NEWID() a nezpůsobily
 *   kolizi primárního klíče s hlavním 'A' záznamem.
 * ============================================================================= */
DECLARE @drop_sql NVARCHAR(MAX) = '';

-- 1. Odstranění všech stávajících triggerů s prefixem trgo_
SELECT	@drop_sql = @drop_sql + 'DROP TRIGGER [' + name + '];' + CHAR(13)
FROM	sys.triggers 
WHERE	name LIKE 'trgo\_%' ESCAPE '\';

IF @drop_sql <> '' 
BEGIN
	EXEC(@drop_sql);
	--PRINT 'Existující triggery trgo_% byly úspěšně odstraněny.';
END

-- 2. Kurzor načítá všechny hodnoty přímo do proměnných
DECLARE @table_name VARCHAR(128), @key1 VARCHAR(128), @key2 VARCHAR(128);
DECLARE cur_tables CURSOR FOR 
	SELECT table_name, key1_column, key2_column FROM meta_original_keys;

OPEN cur_tables;
FETCH NEXT FROM cur_tables INTO @table_name, @key1, @key2;

WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @key1_expr VARCHAR(200) = 'CAST(i.[' + @key1 + '] AS VARCHAR(MAX))';
	DECLARE @key2_expr VARCHAR(200) = CASE WHEN @key2 IS NOT NULL THEN 'CAST(i.[' + @key2 + '] AS VARCHAR(MAX))' ELSE 'NULL' END;
	DECLARE @join_expr VARCHAR(MAX) = 'parent.[' + @key1 + '] = i.[' + @key1 + ']';
	
	IF @key2 IS NOT NULL 
	BEGIN
		SET @join_expr = @join_expr + ' AND parent.[' + @key2 + '] = i.[' + @key2 + ']';
	END

	DECLARE @trg_sql NVARCHAR(MAX) = '
CREATE TRIGGER trgo_' + @table_name + '
ON [' + @table_name + ']
AFTER INSERT, UPDATE             -- ZOHLEDNĚNÍ POŽADAVKU NA MANUÁLNÍ OPRAVY
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE t
	SET 
		original = dbo.f_generate_original(
			''' + @table_name + ''',
			ISNULL(parent.object_owner, i.object_owner),
			' + @key1_expr + ',
			' + @key2_expr + '
		),
		uuid = CASE 
			WHEN i.record_type = ''A'' AND parent.uuid IS NULL THEN 
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
		ON ' + @join_expr + '
		AND (parent.object_owner = 0x00 OR parent.object_owner = i.template)
		AND parent.record_type = ''A''
		AND parent.removed = 0
		AND parent.uuid <> i.uuid
END;';

	EXEC(@trg_sql);
	--PRINT 'Vytvořen trigger: trgo_' + @table_name;

	FETCH NEXT FROM cur_tables INTO @table_name, @key1, @key2;
END

CLOSE cur_tables;
DEALLOCATE cur_tables;
GO

/* =============================================================================
 * TRIGGER: trgo_link
 * Účel: Nastavení deterministického identifikátoru vazby s využitím f_link_original.
 * ============================================================================= */
CREATE TRIGGER trgo_link
ON [link]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE t
	SET 
		original = dbo.f_link_original(
			ISNULL(parent.object_owner, i.object_owner),
			CAST(i.[link_def] AS varchar(36)),
			CAST(i.[from_object] AS varchar(36)),
			CAST(i.[to_object] AS varchar(36))
		),
		uuid = CASE 
			WHEN i.record_type = 'A' AND parent.uuid IS NULL THEN 
				dbo.f_link_original(
					i.object_owner,
					CAST(i.[link_def] AS varchar(36)),
					CAST(i.[from_object] AS varchar(36)),
					CAST(i.[to_object] AS varchar(36))
				)
			ELSE i.uuid 
		END
	FROM [link] t
	JOIN inserted i ON i.uuid = t.uuid
	LEFT JOIN [link] parent 
		ON parent.[link_def] = i.[link_def]
		AND parent.[from_object] = i.[from_object]
		AND parent.[to_object] = i.[to_object]
		AND (parent.object_owner = 0x00 OR parent.object_owner = i.template)
		AND parent.record_type = 'A'
		AND parent.removed = 0
		AND parent.uuid <> i.uuid
END;
GO