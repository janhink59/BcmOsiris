/* =============================================================================
 * Verze: 2026-11-01 12:15
 * Soubor: page_approval.sql
 * Procedura: dbo.page_approval
 * Účel: Databázová podpora pro univerzální schvalovací obrazovku page_approval.php.
 *       Vyčleňuje rozsáhlé T-SQL dotazy s DECLARE @fl TABLE z PHP do databáze:
 *       1. @subpage = 'classes'   - Vrátí seznam logických tříd podporujících SSC.
 *       2. @subpage = 'codetable' - Vrátí lokalizovaný popisek položky číselníku.
 *       3. @subpage = 'ref_class' - Vrátí lokalizovaný záznam z odkazované třídy.
 * Vazby:
 * - Volána z PHP třídy page_approval (page_approval.php).
 * - Automaticky zařazena do buildu databáze maskou page_*.sql v BuildListDb.txt.
 * ============================================================================= */

EXECUTE dropni 'page_approval', 'P';
GO

CREATE PROCEDURE dbo.page_approval
	@subpage varchar(30),
	@codetable_name varchar(80) = '',
	@value_code varchar(80) = '',
	@ref_class_uuid uniqueidentifier = NULL,
	@target_uuid uniqueidentifier = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @org_sql uniqueidentifier = 0x00;
	DECLARE @lang_sql varchar(2) = 'cs';

	SELECT TOP 1
		@org_sql = ISNULL(organization, 0x00),
		@lang_sql = ISNULL([language], 'cs')
	FROM dbsession
	WHERE spid = @@SPID;

	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@lang_sql)
	WHERE fallback_order < 1000;

	-- 1. Seznam logických tříd podporujících schvalovací cyklus (mají sloupec draft_author)
	IF @subpage = 'classes'
	BEGIN
		SELECT
			mc.class_name,
			COALESCE(tr.caption, mc.caption, mc.class_name) AS caption,
			mo.builtin_code AS table_name
		FROM meta_class mc
		JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_type = 'T' AND mo.record_type = 'A' AND mo.removed = 0
		JOIN v_syscolumns sc ON sc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT AND sc.colname = 'draft_author'
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM meta_class l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = mc.original
				AND l.record_type = 'L'
				AND l.removed = 0
				AND l.object_owner IN (@org_sql, 0x00)
				AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE mc.object_owner IN (0x00, @org_sql)
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
		  AND mc.class_name NOT IN ('sys_global_columns', 'user_organization_access')
		  AND mo.builtin_code <> 'user_organization_access'
		ORDER BY mc.class_name;
		RETURN;
	END

	-- 2. Lokalizovaný popisek hodnoty z meta_codetable pro porovnávací tabulku
	IF @subpage = 'codetable'
	BEGIN
		SELECT TOP 1 COALESCE(tr.caption, c.caption, '') AS caption
		FROM meta_codetable c
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM meta_codetable l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = c.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE c.codetable_name = @codetable_name
		  AND c.value_code = @value_code
		  AND c.object_owner IN (@org_sql, 0x00)
		  AND c.record_type = 'A'
		  AND c.removed = 0
		ORDER BY CASE WHEN c.object_owner = @org_sql THEN 0 ELSE 1 END;
		RETURN;
	END

	-- 3. Lokalizovaný záznam z odkazované logické třídy (referenced_class) pro porovnávací tabulku
	IF @subpage = 'ref_class' AND @ref_class_uuid IS NOT NULL AND @target_uuid IS NOT NULL
	BEGIN
		DECLARE @ref_tab varchar(128) = '';
		SELECT TOP 1 @ref_tab = mo.builtin_code
		FROM meta_class mc
		JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
		WHERE mc.original = @ref_class_uuid
		  AND mc.object_owner IN (0x00, @org_sql)
		  AND mc.record_type = 'A'
		  AND mc.removed = 0;

		IF @ref_tab = '' OR OBJECT_ID(@ref_tab, 'U') IS NULL
			RETURN;

		DECLARE @sql_ref nvarchar(max) = N'
		DECLARE @fl TABLE ([language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, fallback_order int NOT NULL);
		INSERT INTO @fl ([language], fallback_order) SELECT [language], fallback_order FROM dbo.f_language_list(@p_lang) WHERE fallback_order < 1000;

		SELECT TOP 1 a.*, tr.caption AS trans_caption
		FROM [' + @ref_tab + N'] a
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM [' + @ref_tab + N'] l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = a.original
			  AND l.record_type = ''L''
			  AND l.removed = 0
			  AND (l.object_owner IN (@p_org, 0x00) OR l.object_owner = l.original)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '''') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @p_org THEN 0 ELSE 1 END ASC
		) tr
		WHERE a.original = @p_target
		  AND (a.object_owner IN (@p_org, 0x00) OR a.object_owner = a.original)
		  AND a.record_type = ''A''
		  AND a.removed = 0
		ORDER BY CASE WHEN a.object_owner = @p_org THEN 0 ELSE 1 END;';

		EXEC sp_executesql
			@stmt = @sql_ref,
			@params = N'@p_org uniqueidentifier, @p_lang varchar(2), @p_target uniqueidentifier',
			@p_org = @org_sql,
			@p_lang = @lang_sql,
			@p_target = @target_uuid;
	END
END
GO