/* =============================================================================
 * Verze: 2026-10-25 08:45
 * Soubor: p_csv_import_metadata.sql
 * Procedura: dbo.p_csv_import_metadata
 * Účel:   Zpracování Fáze 2 dvoufázového CSV/TSV importu pro balíček "metadata".
 *         Vytvoří dočasné tabulky (#meta_*), naplní je pomocí p_csv_fill_table
 *         ze session_import_* a s Delta kontrolou změn (EXCEPT) aktualizuje
 *         nebo vloží systémové záznamy (object_owner = 0x00, record_type A a L).
 *
 * Vazby na okolí:
 * - Volána z PHP metody abstract_csv_package::run_import() při package_code = 'metadata'.
 * - Využívá proceduru dbo.p_csv_fill_table a funkci dbo.f_csv_param (p_csv_fill_table.sql).
 * - Využívá funkci dbo.f_syscolumns (HinkMSSQLLibrary.sql) pro dynamické sestavení
 *   porovnávacích a aktualizačních seznamů sloupců.
 * - Zapisuje průběžné zprávy do tabulky request_message přes insert_request_message
 *   a registruje provedený import do tabulky service_logbook.
 *
 * Změny:
 * - 2026-10-25 08:45: Doplněn zápis o provedeném importu systémového balíčku
 *   metadat do tabulky service_logbook.
 * - 2026-10-24 11:30: Oprava chyby "Must declare the scalar variable @s_cols_prefixed"
 *   (proměnná @s_cols_prefixed řádně deklarována a naplněna před sestavením @sql).
 *   Do seznamu vynechaných technických sloupců doplněny valid_from, valid_to,
 *   is_template a template.
 * ============================================================================= */

EXECUTE dropni 'p_csv_import_metadata', 'P';
GO

CREATE PROCEDURE dbo.p_csv_import_metadata
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @user_session uniqueidentifier;
	DECLARE @import_origin varchar(255);
	DECLARE @version_date varchar(200);

	SELECT @user_session = login_session_uuid
	FROM dbsession
	WHERE spid = @@SPID;

	IF @user_session IS NULL
		SET @user_session = @sys_owner;

	SET @import_origin = NULLIF(LTRIM(RTRIM(dbo.f_csv_param('import_origin', ''))), '');
	SET @version_date  = NULLIF(LTRIM(RTRIM(dbo.f_csv_param('version_date', ''))), '');

	-- -------------------------------------------------------------------------
	-- 1. Vytvoření dočasných tabulek v lokálním scope a jejich naplnění z CSV
	-- -------------------------------------------------------------------------
	SELECT TOP 0 * INTO #meta_object    FROM meta_object;
	SELECT TOP 0 * INTO #meta_class     FROM meta_class;
	SELECT TOP 0 * INTO #meta_column    FROM meta_column;
	SELECT TOP 0 * INTO #meta_menu      FROM meta_menu;
	SELECT TOP 0 * INTO #meta_phrase    FROM meta_phrase;
	SELECT TOP 0 * INTO #meta_codetable FROM meta_codetable;
	SELECT TOP 0 * INTO #meta_link_def  FROM meta_link_def;

	DECLARE @rc_object int = 0, @rc_class int = 0, @rc_column int = 0;
	DECLARE @rc_menu int = 0, @rc_phrase int = 0, @rc_codetable int = 0, @rc_link_def int = 0;

	EXEC @rc_object    = dbo.p_csv_fill_table '#meta_object',    'meta_object';
	EXEC @rc_class     = dbo.p_csv_fill_table '#meta_class',     'meta_class';
	EXEC @rc_column    = dbo.p_csv_fill_table '#meta_column',    'meta_column';
	EXEC @rc_menu      = dbo.p_csv_fill_table '#meta_menu',      'meta_menu';
	EXEC @rc_phrase    = dbo.p_csv_fill_table '#meta_phrase',    'meta_phrase';
	EXEC @rc_codetable = dbo.p_csv_fill_table '#meta_codetable', 'meta_codetable';
	EXEC @rc_link_def  = dbo.p_csv_fill_table '#meta_link_def',  'meta_link_def';

	-- Ochrana proti zrušení (removed = 1) u chráněných systémových kontejnerů
	IF @rc_object > 0
		UPDATE #meta_object SET removed = 0 WHERE record_type = 'A' AND (object_type <> 'P' OR builtin_code = 'global_phrase');

	IF @rc_class > 0
		UPDATE #meta_class SET removed = 0 WHERE record_type = 'A' AND class_name = 'sys_global_columns';

	-- -------------------------------------------------------------------------
	-- 2. Seznam zpracovávaných metadatových tabulek
	-- -------------------------------------------------------------------------
	DECLARE @tables TABLE (ord int PRIMARY KEY, tabname varchar(128), row_cnt int);
	INSERT INTO @tables VALUES
		(1, 'meta_object',    @rc_object),
		(2, 'meta_class',     @rc_class),
		(3, 'meta_column',    @rc_column),
		(4, 'meta_menu',      @rc_menu),
		(5, 'meta_phrase',    @rc_phrase),
		(6, 'meta_codetable', @rc_codetable),
		(7, 'meta_link_def',  @rc_link_def);

	DECLARE @tab varchar(128), @cnt int;
	DECLARE cur_meta CURSOR LOCAL FAST_FORWARD FOR
		SELECT tabname, row_cnt FROM @tables WHERE row_cnt > 0 ORDER BY ord;

	OPEN cur_meta;
	FETCH NEXT FROM cur_meta INTO @tab, @cnt;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		DECLARE @set_list nvarchar(max) = N'';
		DECLARE @t_cols nvarchar(max) = N'';
		DECLARE @s_cols nvarchar(max) = N'';
		DECLARE @ins_cols nvarchar(max) = N'';
		DECLARE @s_cols_prefixed nvarchar(max) = N'';

		-- Sestavení seznamů datových sloupců pro Delta UPDATE (EXCEPT) a INSERT
		SELECT
			@set_list = @set_list + N', t.[' + colname + N'] = s.[' + colname + N']',
			@t_cols   = @t_cols   + N', t.[' + colname + N']',
			@s_cols   = @s_cols   + N', s.[' + colname + N']',
			@ins_cols = @ins_cols + N', [' + colname + N']'
		FROM dbo.f_syscolumns(@tab)
		WHERE iscomputed = 0
		  AND is_identity = 0
		  AND colname NOT IN (
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note', 'import_origin',
			'valid_from', 'valid_to', 'is_template', 'template',
			'date_created', 'who_created', 'date_modified', 'who_modified'
		  )
		ORDER BY colid;

		SET @set_list        = SUBSTRING(@set_list, 3, 2000000);
		SET @t_cols          = SUBSTRING(@t_cols, 3, 2000000);
		SET @s_cols          = SUBSTRING(@s_cols, 3, 2000000);
		SET @s_cols_prefixed = N', ' + @s_cols;

		DECLARE @sql nvarchar(max) = N'
		DECLARE @changed_a int = 0, @changed_l int = 0;

		-- A.1) Delta UPDATE hlavních záznamů (record_type = ''A'')
		UPDATE t
		SET ' + @set_list + N',
			t.approval_status = ''A'',
			t.draft_author = 0x00,
			t.approval_note = '''',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @tab + N'] t
		JOIN [#' + @tab + N'] s ON s.original = t.original AND s.record_type = ''A''
		WHERE t.object_owner = 0x00
		  AND t.record_type = ''A''
		  AND EXISTS (
			SELECT ' + @t_cols + N'
			EXCEPT
			SELECT ' + @s_cols + N'
		  );

		SET @changed_a = @@ROWCOUNT;

		-- A.2) INSERT nových hlavních záznamů (record_type = ''A'')
		INSERT INTO [' + @tab + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			s.original, 0x00, s.original, ''A'', ''A'',
			0x00, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM [#' + @tab + N'] s
		WHERE s.record_type = ''A''
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @tab + N'] t
			WHERE t.original = s.original AND t.object_owner = 0x00 AND t.record_type = ''A''
		  );

		SET @changed_a = @changed_a + @@ROWCOUNT;

		-- L.1) Delta UPDATE jazykových záznamů (record_type = ''L'')
		UPDATE t
		SET ' + @set_list + N',
			t.approval_status = ''A'',
			t.draft_author = 0x00,
			t.approval_note = '''',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @tab + N'] t
		JOIN [#' + @tab + N'] s ON s.original = t.original AND s.record_type = ''L'' AND s.[language] = t.[language]
		WHERE t.object_owner = 0x00
		  AND t.record_type = ''L''
		  AND EXISTS (
			SELECT ' + @t_cols + N'
			EXCEPT
			SELECT ' + @s_cols + N'
		  );

		SET @changed_l = @@ROWCOUNT;

		-- L.2) INSERT nových jazykových záznamů (record_type = ''L'')
		INSERT INTO [' + @tab + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, import_origin,
			date_created, who_created, date_modified, who_modified' + @ins_cols + N'
		)
		SELECT
			NEWID(), 0x00, s.original, ''L'', ''A'',
			0x00, '''', @p_origin,
			GETDATE(), @p_user, GETDATE(), @p_user' + @s_cols_prefixed + N'
		FROM [#' + @tab + N'] s
		WHERE s.record_type = ''L''
		  AND EXISTS (
			SELECT 1 FROM [' + @tab + N'] a
			WHERE a.original = s.original AND a.object_owner = 0x00 AND a.record_type = ''A''
		  )
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @tab + N'] t
			WHERE t.original = s.original AND t.object_owner = 0x00 AND t.record_type = ''L'' AND t.[language] = s.[language]
		  );

		SET @changed_l = @changed_l + @@ROWCOUNT;

		-- Jednotná auditní stopa na hlavním A záznamu při změně v L
		UPDATE a
		SET a.date_modified = l.date_modified,
			a.who_modified = l.who_modified
		FROM [' + @tab + N'] a
		JOIN [' + @tab + N'] l ON l.original = a.original AND l.object_owner = 0x00 AND l.record_type = ''L''
		WHERE a.object_owner = 0x00
		  AND a.record_type = ''A''
		  AND l.date_modified > a.date_modified;

		DECLARE @total_chg int = @changed_a + @changed_l;
		EXEC insert_request_message ''Tabulka metadat zpracována (změněné/nové záznamy A+L)'', 1, @intvalue = @total_chg, @obj_type = ''Tabulka'', @obj_name = @p_tab;
		';

		EXEC sp_executesql
			@stmt = @sql,
			@params = N'@p_user uniqueidentifier, @p_origin varchar(255), @p_tab varchar(128)',
			@p_user = @user_session,
			@p_origin = @import_origin,
			@p_tab = @tab;

		FETCH NEXT FROM cur_meta INTO @tab, @cnt;
	END

	CLOSE cur_meta;
	DEALLOCATE cur_meta;

	-- -------------------------------------------------------------------------
	-- 3. Registrace importu systémového balíčku do tabulky service_logbook
	-- -------------------------------------------------------------------------
	IF OBJECT_ID('service_logbook') IS NOT NULL
	BEGIN
		INSERT INTO service_logbook ([name], [version], content)
		VALUES (
			'p_csv_import_metadata',
			ISNULL(@version_date, CONVERT(varchar(20), GETDATE(), 120)),
			ISNULL(@import_origin, 'CSV Package Import (metadata)')
		);
	END
END
GO