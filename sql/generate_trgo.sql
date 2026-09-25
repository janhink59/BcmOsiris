/* =============================================================================
 * DÁVKA: Generátor deterministických triggerů (trgo_%)
 * Účel: Hromadné odstranění a znovuvytvoření triggerů pro vazební tabulky.
 * OPRAVA: Podpora pro ruční hromadné opravy přidáním AFTER INSERT, UPDATE
 * ============================================================================= */
DECLARE @drop_sql NVARCHAR(MAX) = '';

-- 1. Odstranění všech stávajících triggerů s prefixem trgo_
SELECT	@drop_sql = @drop_sql + 'DROP TRIGGER [' + name + '];' + CHAR(13)
FROM	sys.triggers 
WHERE	name LIKE 'trgo\_%' ESCAPE '\';

IF @drop_sql <> '' 
BEGIN
	EXEC(@drop_sql);
	PRINT 'Existující triggery trgo_% byly úspěšně odstraněny.';
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
			WHEN parent.uuid IS NULL THEN 
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
	PRINT 'Vytvořen trigger: trgo_' + @table_name;

	FETCH NEXT FROM cur_tables INTO @table_name, @key1, @key2;
END

CLOSE cur_tables;
DEALLOCATE cur_tables;
GO