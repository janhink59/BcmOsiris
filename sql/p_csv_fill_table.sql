/* =============================================================================
 * Verze: 2026-10-23 16:00
 * Soubor: p_csv_fill_table.sql
 * Funkce: dbo.f_csv_param
 * Procedura: dbo.p_csv_fill_table
 * Účel:   1. Funkce f_csv_param vrátí hodnotu parametru CSV balíčku z tabulky
 *            session_import_parameter pro aktuální relaci (podle @@SPID).
 *         2. Procedura p_csv_fill_table naplní cílovou (typicky #dočasnou)
 *            tabulku daty ze staging tabulek session_import_* pro aktuální relaci.
 *            Garantuje vložení přesně takového počtu řádků (row_count), jaký byl
 *            zjištěn v CSV bloku dané tabulky. Vkládá pouze data stejnojmenných
 *            sloupců (dle dbo.f_syscolumns) a kontroluje, že ostatní sloupce
 *            v cílové tabulce povolují NULL (nebo mají definovaný DEFAULT).
 *
 * Vazby na okolí:
 * - Čte kontext relace (wwwsession) z tabulky dbsession pro aktuální @@SPID.
 * - Čte rozpitvané CSV tabulky session_import_parameter, session_import_table,
 *   session_import_column a session_import_data (z table_session_import.sql).
 * - Využívá funkci dbo.f_syscolumns z HinkMSSQLLibrary.sql pro zjištění sloupců
 *   a datových typů cílové tabulky (podporuje i #dočasné tabulky v tempdb).
 * - Volána z uložených procedur jednotlivých balíčků p_csv_import_<package_code>.
 * ============================================================================= */

EXECUTE dropni 'p_csv_fill_table', 'P';
EXECUTE dropni 'f_csv_param', 'FN';
GO

/* =============================================================================
 * Funkce: dbo.f_csv_param
 * Účel:   Vrátí hodnotu parametru z tabulky session_import_parameter pro
 *         aktuální relaci (@@SPID). Pokud parametr neexistuje, vrátí @default.
 * ============================================================================= */
CREATE FUNCTION dbo.f_csv_param(
	@parameter_code varchar(80),
	@default varchar(max) = ''
)
RETURNS varchar(max)
AS
BEGIN
	DECLARE @val varchar(max);

	SELECT TOP 1 @val = p.parameter_value
	FROM dbsession s
	JOIN session_import_parameter p
		ON p.wwwsession = s.wwwsession
		AND p.parameter_code = @parameter_code
	WHERE s.spid = @@SPID;

	RETURN ISNULL(@val, @default);
END
GO

/* =============================================================================
 * Procedura: dbo.p_csv_fill_table
 * Účel:   Vloží do cílové tabulky (@target_table) přesný počet řádků zjištěný
 *         v CSV bloku (@csv_table_name). Spáruje pouze stejnojmenné sloupce
 *         a ověří, že případné další sloupce v cílové tabulce povolují NULL.
 * ============================================================================= */
CREATE PROCEDURE dbo.p_csv_fill_table
	@target_table varchar(250),                                                -- Jméno cílové tabulky (např. '#meta_class')
	@csv_table_name varchar(128) = '',                                         -- Jméno bloku tabulky v CSV (výchozí = @target_table bez '#')
	@debug bit = 0                                                             -- 1 = Vypíše vygenerovaný SQL příkaz přes PRINT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- 1. Odvození názvu CSV tabulky, pokud nebyl explicitně předán
	IF ISNULL(@csv_table_name, '') = ''
	BEGIN
		IF LEFT(@target_table, 1) = '#'
			SET @csv_table_name = SUBSTRING(@target_table, 2, 250);
		ELSE
			SET @csv_table_name = @target_table;
	END

	-- 2. Zjištění aktivní wwwsession z dbsession
	DECLARE @sess varchar(50);
	SELECT @sess = wwwsession FROM dbsession WHERE spid = @@SPID;

	IF @sess IS NULL
	BEGIN
		RAISERROR('p_csv_fill_table: Nelze identifikovat aktivní relaci v dbsession pro @@SPID.', 16, 1);
		RETURN -1;
	END

	-- 3. Zjištění table_id a přesného počtu řádků (row_count) v CSV bloku
	DECLARE @table_id int, @row_count int;
	SELECT
		@table_id = table_id,
		@row_count = row_count
	FROM session_import_table
	WHERE wwwsession = @sess
	  AND table_name = @csv_table_name;

	IF @table_id IS NULL
	BEGIN
		IF @debug = 1
			PRINT 'p_csv_fill_table: Tabulka "' + @csv_table_name + '" nebyla v session_import_table nalezena.';
		RETURN -1;
	END

	-- 4. Načtení struktury cílové tabulky přes f_syscolumns (funguje pro tempdb i běžné tabulky)
	IF OBJECT_ID('tempdb..#tgt_cols') IS NOT NULL DROP TABLE #tgt_cols;

	SELECT
		colid,
		colname COLLATE DATABASE_DEFAULT AS colname,
		LOWER(typename) COLLATE DATABASE_DEFAULT AS typename,
		prec_syntax COLLATE DATABASE_DEFAULT AS prec_syntax,
		LOWER(LTRIM(RTRIM(nulls))) COLLATE DATABASE_DEFAULT AS nulls,
		LOWER(LTRIM(RTRIM(ISNULL(default_syntax, 'null')))) COLLATE DATABASE_DEFAULT AS default_syntax
	INTO #tgt_cols
	FROM dbo.f_syscolumns(@target_table)
	WHERE iscomputed = 0
	  AND is_identity = 0;

	IF NOT EXISTS (SELECT 1 FROM #tgt_cols)
	BEGIN
		RAISERROR('p_csv_fill_table: Cílová tabulka "%s" neexistuje nebo neobsahuje žádné zapisovatelné sloupce.', 16, 1, @target_table);
		RETURN -1;
	END

	-- 5. Kontrola, zda všechny cílové sloupce, které NEJSOU v CSV, povolují NULL (nebo mají DEFAULT)
	DECLARE @missing_not_null varchar(250) = NULL;
	SELECT TOP 1 @missing_not_null = tc.colname
	FROM #tgt_cols tc
	LEFT JOIN session_import_column ic
		ON ic.wwwsession = @sess
		AND ic.table_id = @table_id
		AND ic.column_name COLLATE DATABASE_DEFAULT = tc.colname
	WHERE ic.column_id IS NULL
	  AND tc.nulls = 'not null'
	  AND tc.default_syntax = 'null'
	ORDER BY tc.colid;

	IF @missing_not_null IS NOT NULL
	BEGIN
		RAISERROR('p_csv_fill_table: Sloupec "%s" v cílové tabulce "%s" není v CSV bloku "%s" a nepovoluje NULL.', 16, 1, @missing_not_null, @target_table, @csv_table_name);
		RETURN -1;
	END

	-- Pokud má tabulka v CSV 0 datových řádků, neprovádíme INSERT a vrátíme 0
	IF @row_count <= 0
	BEGIN
		DROP TABLE #tgt_cols;
		RETURN 0;
	END

	-- 6. Sestavení seznamu společných sloupců a typově bezpečných konverzních výrazů
	DECLARE @insert_cols varchar(max) = '';
	DECLARE @select_exprs varchar(max) = '';
	DECLARE @col_ids_list varchar(max) = '';

	SELECT
		@insert_cols = @insert_cols + ', [' + tc.colname + ']',
		@col_ids_list = @col_ids_list + ',' + CAST(ic.column_id AS varchar(20)),
		@select_exprs = @select_exprs + ',' + CHAR(13) + CHAR(10) + CHAR(9) +
			CASE
				-- UUID / UNIQUEIDENTIFIER (včetně podpory zápisu '0x00')
				WHEN tc.typename IN ('uuid', 'uniqueidentifier') THEN
					CASE WHEN tc.nulls = 'not null'
						THEN 'ISNULL(CASE WHEN ' + v.raw_val + ' IN (''0x00'', ''00000000-0000-0000-0000-000000000000'') THEN CAST(0x00 AS uniqueidentifier) ELSE TRY_CONVERT(uniqueidentifier, NULLIF(' + v.raw_val + ', '''')) END, CAST(0x00 AS uniqueidentifier))'
						ELSE 'CASE WHEN ' + v.raw_val + ' IN (''0x00'', ''00000000-0000-0000-0000-000000000000'') THEN CAST(0x00 AS uniqueidentifier) ELSE TRY_CONVERT(uniqueidentifier, NULLIF(' + v.raw_val + ', '''')) END'
					END
				-- BIT / BOOLEAN
				WHEN tc.typename IN ('bit', 'boolean') THEN
					CASE WHEN tc.nulls = 'not null'
						THEN 'ISNULL(TRY_CONVERT(bit, NULLIF(' + v.raw_val + ', '''')), 0)'
						ELSE 'TRY_CONVERT(bit, NULLIF(' + v.raw_val + ', ''''))'
					END
				-- CELÁ A DESETINNÁ ČÍSLA
				WHEN tc.typename IN ('int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real', 'money') THEN
					CASE WHEN tc.nulls = 'not null'
						THEN 'ISNULL(TRY_CONVERT(' + tc.typename + tc.prec_syntax + ', NULLIF(REPLACE(' + v.raw_val + ', '','', ''.''), '''')), 0)'
						ELSE 'TRY_CONVERT(' + tc.typename + tc.prec_syntax + ', NULLIF(REPLACE(' + v.raw_val + ', '','', ''.''), ''''))'
					END
				-- DATUM A ČAS
				WHEN tc.typename IN ('date', 'datetime', 'datetime2', 'smalldatetime') THEN
					CASE WHEN tc.nulls = 'not null'
						THEN 'ISNULL(TRY_CONVERT(' + tc.typename + ', NULLIF(' + v.raw_val + ', '''')), ''1970-01-01'')'
						ELSE 'TRY_CONVERT(' + tc.typename + ', NULLIF(' + v.raw_val + ', ''''))'
					END
				-- BINÁRNÍ DATA (0x...)
				WHEN tc.typename IN ('varbinary', 'binary', 'image') THEN
					'TRY_CONVERT(' + CASE WHEN tc.typename = 'image' THEN 'varbinary(max)' ELSE tc.typename + tc.prec_syntax END + ', NULLIF(' + v.raw_val + ', ''''), 1)'
				-- TEXTOVÉ SLOUPCE (varchar, nvarchar, char, text...)
				ELSE
					CASE WHEN tc.nulls = 'not null'
						THEN 'ISNULL(' + v.raw_val + ', '''')'
						ELSE 'NULLIF(' + v.raw_val + ', '''')'
					END
			END + ' AS [' + tc.colname + ']'
	FROM #tgt_cols tc
	JOIN session_import_column ic
		ON ic.wwwsession = @sess
		AND ic.table_id = @table_id
		AND ic.column_name COLLATE DATABASE_DEFAULT = tc.colname
	CROSS APPLY (
		SELECT 'MAX(CASE WHEN d.column_id = ' + CAST(ic.column_id AS varchar(20)) + ' THEN d.cell_value END)' AS raw_val
	) v
	ORDER BY tc.colid;

	IF @insert_cols = ''
	BEGIN
		RAISERROR('p_csv_fill_table: Mezi cílovou tabulkou "%s" a CSV blokem "%s" nebyl nalezen žádný společný sloupec.', 16, 1, @target_table, @csv_table_name);
		RETURN -1;
	END

	SET @insert_cols = SUBSTRING(@insert_cols, 3, 2000000);
	SET @select_exprs = SUBSTRING(@select_exprs, 2, 2000000);
	SET @col_ids_list = SUBSTRING(@col_ids_list, 2, 2000000);

	-- 7. Vygenerování přesné sekvence řádků 1..@row_count, aby se vložily i případné zcela prázdné řádky z CSV
	IF OBJECT_ID('tempdb..#csv_row_seq') IS NOT NULL DROP TABLE #csv_row_seq;
	CREATE TABLE #csv_row_seq (row_id int NOT NULL PRIMARY KEY);

	;WITH nums AS (
		SELECT 1 AS n
		UNION ALL
		SELECT n + 1 FROM nums WHERE n < @row_count
	)
	INSERT INTO #csv_row_seq (row_id)
	SELECT n FROM nums
	OPTION (MAXRECURSION 0);

	-- 8. Sestavení a provedení dynamického příkazu INSERT INTO @target_table
	DECLARE @sql nvarchar(max) = N'
INSERT INTO ' + @target_table + N' (' + @insert_cols + N')
SELECT' + @select_exprs + N'
FROM #csv_row_seq r
LEFT JOIN session_import_data d
	ON d.wwwsession = @p_sess
	AND d.row_id = r.row_id
	AND d.column_id IN (' + @col_ids_list + N')
GROUP BY r.row_id
ORDER BY r.row_id;';

	IF @debug = 1
		EXEC p_print_longvarchar @sql;

	DECLARE @inserted_rows int = 0;
	EXEC sp_executesql
		@stmt = @sql,
		@params = N'@p_sess varchar(50)',
		@p_sess = @sess;

	SET @inserted_rows = @@ROWCOUNT;

	DROP TABLE #csv_row_seq;
	DROP TABLE #tgt_cols;

	RETURN @inserted_rows;
END
GO