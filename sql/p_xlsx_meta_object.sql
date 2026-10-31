/* =============================================================================
 * Verze: 2026-11-01 12:15
 * Soubor: p_xlsx_meta_object.sql
 * Procedury: dbo.p_xlsx_sync_sheet, dbo.p_xlsx_meta_object
 * Účel: 1. dbo.p_xlsx_sync_sheet je sdílený synchronizační motor pro jednotlivé
 *          záložky XLSX importu metadat. Zajišťuje kontrolu neplatných 'A'
 *          záznamů v režimu překladů, replikaci zrušení (removed = 1), Delta
 *          UPDATE pomocí operátoru EXCEPT, INSERT nových 'A' a 'L' záznamů
 *          a propagaci auditní stopy z 'L' na 'A'.
 *       2. dbo.p_xlsx_meta_object řídí hromadný import systémových stránek (page),
 *          frází (phrase), navigace (menu), logických tříd (class) a sloupců
 *          metadat (column) ze staging tabulek XLSX_*$ se zápisem do service_logbook.
 *
 * Vazby na okolí:
 * - Volána z PHP třídy excel_reader (metoda run_package) a z distribučních dávek.
 * - Využívá funkce dbo.f_generate_original, dbo.f_xlsx_clean, dbo.f_string_list,
 *   proceduru insert_request_message a tabulku service_logbook.
 *
 * Změny:
 * - 2026-11-01 12:15: Vyčleněna univerzální procedura dbo.p_xlsx_sync_sheet,
 *   která nahradila 5× opakované bloky UPDATE ... EXCEPT a INSERT (zkrácení
 *   souboru z 1045 řádků na méně než polovinu při 100% zachování funkčnosti).
 * ============================================================================= */

EXECUTE dropni 'p_xlsx_meta_object', 'P';
EXECUTE dropni 'p_xlsx_sync_sheet', 'P';
GO

/* =============================================================================
 * Pomocná procedura: dbo.p_xlsx_sync_sheet
 * Účel: Provede kompletní Delta synchronizaci jedné očištěné dočasné tabulky
 *       (@clean_table) do cílové metadatové tabulky (@target_table) v režimu
 *       jádra (@is_trans_mode = 0) nebo v režimu překladů (@is_trans_mode = 1).
 * ============================================================================= */
CREATE PROCEDURE dbo.p_xlsx_sync_sheet
	@target_table varchar(128),                                                -- Cílová tabulka (např. 'meta_object', 'meta_class')
	@clean_table varchar(128),                                                 -- Dočasná tabulka (např. '#clean_page', '#clean_class')
	@sheet_label varchar(80),                                                  -- Název záložky v Excelu ('page', 'phrase', 'menu', 'class', 'column')
	@obj_type_label varchar(80),                                               -- Popisek typu objektu do request_message
	@a_cols_csv varchar(max),                                                  -- Seznam datových sloupců 'A' záznamu v @clean_table
	@l_cols_csv varchar(max),                                                  -- Seznam překládaných sloupců (v @clean_table mají i variantu *_l)
	@lang varchar(2),                                                          -- Primární jazyk balíčku
	@sec_lang varchar(2),                                                      -- Druhý jazyk balíčku (pro @is_trans_mode = 1)
	@is_trans_mode bit,                                                        -- 0 = Režim jádra, 1 = Režim překladů druhého jazyka
	@import_origin varchar(255),                                               -- Původ importu (měkký audit)
	@user_session uniqueidentifier,                                            -- UUID relace pro who_created / who_modified
	@extra_filter nvarchar(500) = N'',                                         -- Volitelný filtr platných řádků (např. 'AND s.storage_valid = 1')
	@protect_rem_cond nvarchar(500) = N''                                      -- Volitelná ochrana proti smazání chráněných záznamů
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- 1. Rozparsování seznamů sloupců pro 'A', symetrické 'L' a překladové 'L'
	DECLARE @a_cols TABLE (ord int PRIMARY KEY, colname varchar(128) COLLATE DATABASE_DEFAULT NOT NULL);
	INSERT INTO @a_cols (ord, colname)
	SELECT ordr, LTRIM(RTRIM(s)) FROM dbo.f_string_list(@a_cols_csv) WHERE s <> '';

	DECLARE @l_cols TABLE (ord int PRIMARY KEY, colname varchar(128) COLLATE DATABASE_DEFAULT NOT NULL);
	INSERT INTO @l_cols (ord, colname)
	SELECT ordr, LTRIM(RTRIM(s)) FROM dbo.f_string_list(@l_cols_csv) WHERE s <> '';

	-- Symetrické 'L' obsahuje všechny sloupce z @a_cols kromě 'editor_note' + případný sloupec 'svg_icon' z 'A' záznamu
	DECLARE @sym_cols TABLE (ord int IDENTITY PRIMARY KEY, colname varchar(128) COLLATE DATABASE_DEFAULT NOT NULL);
	INSERT INTO @sym_cols (colname)
	SELECT colname FROM @a_cols WHERE colname <> 'editor_note' ORDER BY ord;

	IF COL_LENGTH(@target_table, 'svg_icon') IS NOT NULL
	   AND NOT EXISTS (SELECT 1 FROM @sym_cols WHERE colname = 'svg_icon')
	BEGIN
		INSERT INTO @sym_cols (colname) VALUES ('svg_icon');
	END

	-- Sestavení dynamických částí SQL dotazů
	DECLARE @set_a nvarchar(max) = N'';
	DECLARE @t_cols_a nvarchar(max) = N'';
	DECLARE @s_cols_a nvarchar(max) = N'';
	DECLARE @ins_cols_a nvarchar(max) = N'';

	SELECT
		@set_a      = @set_a      + N', t.[' + colname + N'] = s.[' + colname + N']',
		@t_cols_a   = @t_cols_a   + N', t.[' + colname + N']',
		@s_cols_a   = @s_cols_a   + N', s.[' + colname + N']',
		@ins_cols_a = @ins_cols_a + N', [' + colname + N']'
	FROM @a_cols
	ORDER BY ord;

	DECLARE @set_sym_l nvarchar(max) = N'';
	DECLARE @t_cols_sym_l nvarchar(max) = N'';
	DECLARE @a_cols_sym_l nvarchar(max) = N'';
	DECLARE @ins_cols_sym_l nvarchar(max) = N'';
	DECLARE @ins_vals_sec_l nvarchar(max) = N'';

	SELECT
		@set_sym_l      = @set_sym_l      + N', t.[' + sc.colname + N'] = a.[' + sc.colname + N']',
		@t_cols_sym_l   = @t_cols_sym_l   + N', t.[' + sc.colname + N']',
		@a_cols_sym_l   = @a_cols_sym_l   + N', a.[' + sc.colname + N']',
		@ins_cols_sym_l = @ins_cols_sym_l + N', [' + sc.colname + N']',
		@ins_vals_sec_l = @ins_vals_sec_l + CASE
			WHEN lc.colname IS NOT NULL THEN N', s.[' + sc.colname + N'_l]'
			ELSE N', a.[' + sc.colname + N']'
		END
	FROM @sym_cols sc
	LEFT JOIN @l_cols lc ON lc.colname = sc.colname
	ORDER BY sc.ord;

	DECLARE @set_tr_l nvarchar(max) = N'';
	DECLARE @t_cols_tr_l nvarchar(max) = N'';
	DECLARE @s_cols_tr_l nvarchar(max) = N'';
	DECLARE @non_empty_tr nvarchar(max) = N'';

	SELECT
		@set_tr_l     = @set_tr_l     + N', t.[' + colname + N'] = s.[' + colname + N'_l]',
		@t_cols_tr_l  = @t_cols_tr_l  + N', t.[' + colname + N']',
		@s_cols_tr_l  = @s_cols_tr_l  + N', s.[' + colname + N'_l]',
		@non_empty_tr = @non_empty_tr + CASE WHEN @non_empty_tr = N'' THEN N'' ELSE N' OR ' END
			+ N'ISNULL(CAST(s.[' + colname + N'_l] AS nvarchar(max)), N'''') <> N'''''
	FROM @l_cols
	ORDER BY ord;

	DECLARE @sql nvarchar(max) = N'';

	IF @is_trans_mode = 0
	BEGIN
		-- REŽIM JÁDRA (@is_trans_mode = 0): Replikace zrušení + Delta UPDATE/INSERT 'A' a symetrického 'L'
		SET @sql = N'
		DECLARE @cnt_rem int = 0, @cnt_a int = 0;

		-- A.1) Replikace zrušení záznamu (removed = 1)
		UPDATE t
		SET t.removed = 1,
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @target_table + N'] t
		JOIN ' + @clean_table + N' s ON s.orig_uuid = t.original
		WHERE s.removed = 1
		  AND t.object_owner = 0x00
		  AND t.removed = 0
		  ' + @protect_rem_cond + N';

		SET @cnt_rem = @@ROWCOUNT;
		IF @cnt_rem > 0
		BEGIN
			DECLARE @msg_rem varchar(300) = ''Zreplikováno odstranění záznamů (removed=1) na záložce ' + @sheet_label + N''';
			EXEC insert_request_message @msg_rem, 1, @intvalue = @cnt_rem, @obj_type = @p_obj_type, @obj_name = @p_sheet;
		END

		-- A.2) Delta UPDATE hlavních záznamů (record_type = ''A'') včetně případné obnovy z koše (removed: 1 -> 0)
		UPDATE t
		SET t.[language] = @p_lang,
			t.removed = 0' + @set_a + N',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @target_table + N'] t
		JOIN ' + @clean_table + N' s ON s.orig_uuid = t.original
		WHERE s.removed = 0
		  ' + @extra_filter + N'
		  AND t.object_owner = 0x00
		  AND t.record_type = ''A''
		  AND EXISTS (
			SELECT t.[language], t.removed' + @t_cols_a + N'
			EXCEPT
			SELECT @p_lang, CAST(0 AS bit)' + @s_cols_a + N'
		  );

		SET @cnt_a = @@ROWCOUNT;

		-- A.3) INSERT nových hlavních záznamů (record_type = ''A'')
		INSERT INTO [' + @target_table + N'] (
			uuid, object_owner, original, record_type, approval_status, [language],
			removed, import_origin' + @ins_cols_a + N',
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			s.orig_uuid, 0x00, s.orig_uuid, ''A'', ''A'', @p_lang,
			0, @p_origin' + @s_cols_a + N',
			GETDATE(), @p_user, GETDATE(), @p_user
		FROM ' + @clean_table + N' s
		WHERE s.removed = 0
		  ' + @extra_filter + N'
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @target_table + N'] t
			WHERE t.original = s.orig_uuid AND t.object_owner = 0x00 AND t.record_type = ''A''
		  );

		SET @cnt_a = @cnt_a + @@ROWCOUNT;

		-- A.4) Symetrické ''L'' záznamy pro primární jazyk (@p_lang) s Delta kontrolou
		UPDATE t
		SET t.removed = 0' + @set_sym_l + N',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @target_table + N'] t
		JOIN [' + @target_table + N'] a ON a.original = t.original AND a.object_owner = 0x00 AND a.record_type = ''A'' AND a.removed = 0
		JOIN ' + @clean_table + N' s ON s.orig_uuid = a.original
		WHERE s.removed = 0
		  ' + @extra_filter + N'
		  AND t.object_owner = 0x00
		  AND t.record_type = ''L''
		  AND t.[language] = @p_lang
		  AND EXISTS (
			SELECT t.removed' + @t_cols_sym_l + N'
			EXCEPT
			SELECT CAST(0 AS bit)' + @a_cols_sym_l + N'
		  );

		INSERT INTO [' + @target_table + N'] (
			uuid, object_owner, original, record_type, approval_status, [language],
			removed, import_origin' + @ins_cols_sym_l + N',
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), 0x00, a.original, ''L'', ''A'', @p_lang,
			0, @p_origin' + @a_cols_sym_l + N',
			GETDATE(), @p_user, GETDATE(), @p_user
		FROM [' + @target_table + N'] a
		JOIN ' + @clean_table + N' s ON s.orig_uuid = a.original
		WHERE s.removed = 0
		  ' + @extra_filter + N'
		  AND a.object_owner = 0x00
		  AND a.record_type = ''A''
		  AND a.removed = 0
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @target_table + N'] t
			WHERE t.original = a.original AND t.object_owner = 0x00 AND t.record_type = ''L'' AND t.[language] = @p_lang
		  );

		DECLARE @msg_a varchar(300) = ''Záložka ' + @sheet_label + N' (jádro - změněné/nové záznamy)'';
		EXEC insert_request_message @msg_a, 1, @intvalue = @cnt_a, @obj_type = @p_obj_type, @obj_name = @p_sheet;';
	END
	ELSE
	BEGIN
		-- REŽIM PŘEKLADŮ (@is_trans_mode = 1): Replikace zrušení 'L' + Delta UPDATE/INSERT 'L' pro @sec_lang
		SET @sql = N'
		DECLARE @cnt_rem int = 0, @cnt_l int = 0;

		-- L.1) Replikace zrušení překladu (removed = 1) pro druhý jazyk
		UPDATE t
		SET t.removed = 1,
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @target_table + N'] t
		JOIN ' + @clean_table + N' s ON s.orig_uuid = t.original
		WHERE s.removed = 1
		  AND t.object_owner = 0x00
		  AND t.record_type = ''L''
		  AND t.[language] = @p_sec_lang
		  AND t.removed = 0;

		SET @cnt_rem = @@ROWCOUNT;
		IF @cnt_rem > 0
		BEGIN
			DECLARE @msg_rem_l varchar(300) = ''Zreplikováno odstranění překladů (removed=1) na záložce ' + @sheet_label + N''';
			EXEC insert_request_message @msg_rem_l, 1, @intvalue = @cnt_rem, @obj_type = @p_obj_type, @obj_name = @p_sec_lang;
		END

		-- L.2) Delta UPDATE překladů druhého jazyka (@p_sec_lang)
		UPDATE t
		SET t.removed = 0' + @set_tr_l + N',
			t.import_origin = ISNULL(@p_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @p_user
		FROM [' + @target_table + N'] t
		JOIN [' + @target_table + N'] a ON a.original = t.original AND a.object_owner = 0x00 AND a.record_type = ''A'' AND a.removed = 0
		JOIN ' + @clean_table + N' s ON s.orig_uuid = a.original
		WHERE s.removed = 0
		  ' + @extra_filter + N'
		  AND t.object_owner = 0x00
		  AND t.record_type = ''L''
		  AND t.[language] = @p_sec_lang
		  AND EXISTS (
			SELECT t.removed' + @t_cols_tr_l + N'
			EXCEPT
			SELECT CAST(0 AS bit)' + @s_cols_tr_l + N'
		  );

		SET @cnt_l = @@ROWCOUNT;

		-- L.3) INSERT nových překladů druhého jazyka (@p_sec_lang)
		INSERT INTO [' + @target_table + N'] (
			uuid, object_owner, original, record_type, approval_status, [language],
			removed, import_origin' + @ins_cols_sym_l + N',
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), 0x00, a.original, ''L'', ''A'', @p_sec_lang,
			0, @p_origin' + @ins_vals_sec_l + N',
			GETDATE(), @p_user, GETDATE(), @p_user
		FROM ' + @clean_table + N' s
		JOIN [' + @target_table + N'] a ON a.original = s.orig_uuid AND a.object_owner = 0x00 AND a.record_type = ''A'' AND a.removed = 0
		WHERE s.removed = 0
		  ' + @extra_filter + N'
		  AND (' + @non_empty_tr + N')
		  AND NOT EXISTS (
			SELECT 1 FROM [' + @target_table + N'] t
			WHERE t.original = a.original AND t.object_owner = 0x00 AND t.record_type = ''L'' AND t.[language] = @p_sec_lang
		  );

		SET @cnt_l = @cnt_l + @@ROWCOUNT;

		-- L.4) Jednotná auditní stopa na hlavním A záznamu při změně překladu L
		UPDATE a
		SET a.date_modified = l.date_modified,
			a.who_modified = l.who_modified
		FROM [' + @target_table + N'] a
		JOIN [' + @target_table + N'] l ON l.original = a.original AND l.object_owner = 0x00 AND l.record_type = ''L'' AND l.[language] = @p_sec_lang
		WHERE a.object_owner = 0x00
		  AND a.record_type = ''A''
		  AND l.date_modified > a.date_modified;

		DECLARE @msg_l varchar(300) = ''Záložka ' + @sheet_label + N' (překlady - změněné/nové záznamy)'';
		EXEC insert_request_message @msg_l, 1, @intvalue = @cnt_l, @obj_type = @p_obj_type, @obj_name = @p_sec_lang;';
	END

	EXEC sp_executesql
		@stmt = @sql,
		@params = N'@p_lang varchar(2), @p_sec_lang varchar(2), @p_origin varchar(255), @p_user uniqueidentifier, @p_obj_type varchar(80), @p_sheet varchar(80)',
		@p_lang = @lang,
		@p_sec_lang = @sec_lang,
		@p_origin = @import_origin,
		@p_user = @user_session,
		@p_obj_type = @obj_type_label,
		@p_sheet = @sheet_label;
END
GO

/* =============================================================================
 * Hlavní procedura: dbo.p_xlsx_meta_object
 * ============================================================================= */
CREATE PROCEDURE dbo.p_xlsx_meta_object
	@import_mode varchar(1) = '1'
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @user_session uniqueidentifier;
	DECLARE @lang varchar(2) = '';
	DECLARE @sec_lang varchar(2) = '';
	DECLARE @is_trans_mode bit = 0;
	DECLARE @import_origin varchar(255) = NULL;
	DECLARE @version_date varchar(200) = '';
	DECLARE @pkg_description varchar(max) = '';
	DECLARE @bad_code varchar(200);

	-- -------------------------------------------------------------------------
	-- 0. Získání auditního kontextu a načtení řídicí tabulky XLSX_CONTENT_INFO$
	-- -------------------------------------------------------------------------
	SELECT @user_session = login_session_uuid FROM dbsession WHERE spid = @@SPID;
	IF @user_session IS NULL SET @user_session = @sys_owner;

	IF OBJECT_ID('XLSX_CONTENT_INFO$') IS NULL
	BEGIN
		EXEC insert_request_message 'Chybí řídicí tabulka XLSX_CONTENT_INFO$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_CONTENT_INFO$';
		RETURN;
	END

	SELECT TOP 1 @lang = LTRIM(RTRIM(ISNULL([language], ''))) FROM XLSX_CONTENT_INFO$;

	IF COL_LENGTH('XLSX_CONTENT_INFO$', 'second_language') IS NOT NULL
		EXEC sp_executesql N'SELECT TOP 1 @out = LTRIM(RTRIM(ISNULL(second_language, ''''))) FROM XLSX_CONTENT_INFO$', N'@out varchar(2) OUTPUT', @out = @sec_lang OUTPUT;

	IF COL_LENGTH('XLSX_CONTENT_INFO$', 'import_origin') IS NOT NULL
		EXEC sp_executesql N'SELECT TOP 1 @out = NULLIF(LTRIM(RTRIM(import_origin)), '''') FROM XLSX_CONTENT_INFO$', N'@out varchar(255) OUTPUT', @out = @import_origin OUTPUT;

	IF COL_LENGTH('XLSX_CONTENT_INFO$', 'version_date') IS NOT NULL
		EXEC sp_executesql N'SELECT TOP 1 @out = LTRIM(RTRIM(ISNULL(CAST(version_date AS varchar(200)), ''''))) FROM XLSX_CONTENT_INFO$', N'@out varchar(200) OUTPUT', @out = @version_date OUTPUT;

	IF COL_LENGTH('XLSX_CONTENT_INFO$', 'description') IS NOT NULL
		EXEC sp_executesql N'SELECT TOP 1 @out = LTRIM(RTRIM(ISNULL(CAST([description] AS varchar(max)), ''''))) FROM XLSX_CONTENT_INFO$', N'@out varchar(max) OUTPUT', @out = @pkg_description OUTPUT;

	IF @lang = '' OR NOT EXISTS (SELECT 1 FROM [language] WHERE [language] = @lang)
	BEGIN
		EXEC insert_request_message 'Neplatný nebo chybějící kód základního jazyka (language) v CONTENT_INFO', 3, @obj_type = 'Jazyk', @obj_name = @lang;
		RETURN;
	END

	IF @sec_lang <> ''
	BEGIN
		IF @sec_lang = @lang
		BEGIN
			EXEC insert_request_message 'Druhý jazyk (second_language) nesmí být shodný se základním jazykem', 3, @obj_type = 'Jazyk', @obj_name = @sec_lang;
			RETURN;
		END
		IF NOT EXISTS (SELECT 1 FROM [language] WHERE [language] = @sec_lang)
		BEGIN
			EXEC insert_request_message 'Neplatný kód druhého jazyka (second_language) v CONTENT_INFO', 3, @obj_type = 'Jazyk', @obj_name = @sec_lang;
			RETURN;
		END
		SET @is_trans_mode = 1;
		EXEC insert_request_message 'Režim importu jazykové mutace (ukládají se pouze změněné překlady druhého jazyka)', 0, @obj_type = 'Jazyk', @obj_name = @sec_lang;
	END
	ELSE
	BEGIN
		SET @is_trans_mode = 0;
		EXEC insert_request_message 'Režim importu jádra a základního jazyka (Delta kontrola změn)', 0, @obj_type = 'Jazyk', @obj_name = @lang;
	END

	-- =========================================================================
	-- 1. Zpracování záložky: page (tabulka meta_object, object_type = 'P')
	-- =========================================================================
	IF OBJECT_ID('XLSX_page$') IS NULL
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_page$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_page$';
		RETURN;
	END

	IF COL_LENGTH('XLSX_page$', 'removed') IS NULL
		ALTER TABLE XLSX_page$ ADD removed bit NOT NULL DEFAULT 0;

	IF EXISTS (SELECT 1 FROM XLSX_page$ WHERE LTRIM(RTRIM(ISNULL(builtin_code, ''))) = '')
	BEGIN
		EXEC insert_request_message 'Záložka page nesmí obsahovat prázdný builtin_code (pro globální fráze použijte global_phrase)', 3, @obj_type = 'page', @obj_name = '(prázdný builtin_code)';
		RETURN;
	END

	SET @bad_code = NULL;
	SELECT TOP 1 @bad_code = LTRIM(RTRIM(builtin_code)) FROM XLSX_page$ GROUP BY LTRIM(RTRIM(builtin_code)) HAVING COUNT(*) > 1;
	IF @bad_code IS NOT NULL
	BEGIN
		EXEC insert_request_message 'Duplicitní builtin_code na záložce page', 3, @obj_type = 'page', @obj_name = @bad_code;
		RETURN;
	END

	IF OBJECT_ID('tempdb..#clean_page') IS NOT NULL DROP TABLE #clean_page;

	SELECT
		'P' AS object_type,
		LTRIM(RTRIM(s.builtin_code)) AS builtin_code,
		dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.builtin_code))) AS orig_uuid,
		ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S') AS system_role,
		ISNULL(s.module, '') AS module,
		ISNULL(TRY_CAST(s.inactive AS bit), 0) AS inactive,
		ISNULL(TRY_CAST(s.removed AS bit), 0) AS removed,
		ISNULL(s.editor_note, '') AS editor_note,
		ISNULL(s.caption, '') AS caption,
		ISNULL(s.description, '') AS description,
		ISNULL(s.helptext, '') AS helptext,
		dbo.f_xlsx_clean(s.caption_l, 1) AS caption_l,
		dbo.f_xlsx_clean(s.description_l, 1) AS description_l,
		dbo.f_xlsx_clean(s.helptext_l, 1) AS helptext_l
	INTO #clean_page
	FROM XLSX_page$ s;

	IF @is_trans_mode = 1
	BEGIN
		INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
		SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je objekt stránky neplatný (removed=1)', 'meta_object (P)', s.builtin_code
		FROM #clean_page s
		WHERE s.removed = 0
		  AND EXISTS (SELECT 1 FROM meta_object t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
		  AND NOT EXISTS (SELECT 1 FROM meta_object t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
	END

	EXEC dbo.p_xlsx_sync_sheet
		@target_table = 'meta_object',
		@clean_table = '#clean_page',
		@sheet_label = 'page',
		@obj_type_label = 'meta_object (P)',
		@a_cols_csv = 'object_type,builtin_code,system_role,module,inactive,editor_note,caption,description,helptext',
		@l_cols_csv = 'caption,description,helptext',
		@lang = @lang,
		@sec_lang = @sec_lang,
		@is_trans_mode = @is_trans_mode,
		@import_origin = @import_origin,
		@user_session = @user_session,
		@extra_filter = N'',
		@protect_rem_cond = N'AND s.builtin_code <> ''global_phrase''';

	DROP TABLE #clean_page;

	-- =========================================================================
	-- 2. Zpracování záložky: phrase (tabulka meta_phrase – bez čtení svg_icon)
	-- =========================================================================
	IF OBJECT_ID('XLSX_phrase$') IS NULL
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_phrase$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_phrase$';
		RETURN;
	END

	IF COL_LENGTH('XLSX_phrase$', 'inactive') IS NULL ALTER TABLE XLSX_phrase$ ADD inactive bit NOT NULL DEFAULT 0;
	IF COL_LENGTH('XLSX_phrase$', 'removed') IS NULL ALTER TABLE XLSX_phrase$ ADD removed bit NOT NULL DEFAULT 0;

	SET @bad_code = NULL;
	SELECT TOP 1 @bad_code = ISNULL(LTRIM(RTRIM(source_code)), '(NULL)') + '.' + ISNULL(LTRIM(RTRIM(builtin_code)), '(NULL)')
	FROM XLSX_phrase$
	WHERE LTRIM(RTRIM(ISNULL(source_code, ''))) = '' OR LTRIM(RTRIM(ISNULL(builtin_code, ''))) = '';

	IF @bad_code IS NOT NULL
	BEGIN
		EXEC insert_request_message 'Fráze na záložce phrase nesmí mít prázdný source_code ani builtin_code (pro globální fráze použijte global_phrase)', 3, @obj_type = 'meta_phrase', @obj_name = @bad_code;
		RETURN;
	END

	SET @bad_code = NULL;
	SELECT TOP 1 @bad_code = LTRIM(RTRIM(source_code)) + '.' + LTRIM(RTRIM(builtin_code))
	FROM XLSX_phrase$
	GROUP BY LTRIM(RTRIM(source_code)), LTRIM(RTRIM(builtin_code))
	HAVING COUNT(*) > 1;

	IF @bad_code IS NOT NULL
	BEGIN
		EXEC insert_request_message 'Duplicitní kombinace (source_code, builtin_code) na záložce phrase', 3, @obj_type = 'phrase', @obj_name = @bad_code;
		RETURN;
	END

	IF OBJECT_ID('tempdb..#clean_phrase') IS NOT NULL DROP TABLE #clean_phrase;

	SELECT
		LTRIM(RTRIM(s.source_code)) AS source_code,
		LTRIM(RTRIM(s.builtin_code)) AS builtin_code,
		dbo.f_generate_original('meta_phrase', @sys_owner, LTRIM(RTRIM(s.source_code)), LTRIM(RTRIM(s.builtin_code))) AS orig_uuid,
		ISNULL(s.module, '') AS module,
		ISNULL(s.css_class, '') AS css_class,
		ISNULL(TRY_CAST(s.inactive AS bit), 0) AS inactive,
		ISNULL(TRY_CAST(s.removed AS bit), 0) AS removed,
		ISNULL(s.editor_note, '') AS editor_note,
		ISNULL(s.caption, '') AS caption,
		ISNULL(s.helptext, '') AS helptext,
		CAST(1 AS bit) AS is_final,
		CAST(1 AS bit) AS is_protected,
		dbo.f_xlsx_clean(s.caption_l, 1) AS caption_l,
		dbo.f_xlsx_clean(s.helptext_l, 1) AS helptext_l
	INTO #clean_phrase
	FROM XLSX_phrase$ s;

	SET @bad_code = NULL;
	SELECT TOP 1 @bad_code = s.source_code + ' (' + s.builtin_code + ')'
	FROM #clean_phrase s
	WHERE s.removed = 0
	  AND NOT EXISTS (
		SELECT 1 FROM meta_object mo
		WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', s.source_code)
		  AND mo.object_type = 'P' AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0
	  );

	IF @bad_code IS NOT NULL
	BEGIN
		EXEC insert_request_message 'Neexistující zdrojový objekt (source_code) na záložce phrase', 3, @obj_type = 'meta_phrase', @obj_name = @bad_code;
		RETURN;
	END

	IF @is_trans_mode = 1
	BEGIN
		INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
		SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je fráze neplatná (removed=1)', 'meta_phrase', s.source_code + '.' + s.builtin_code
		FROM #clean_phrase s
		WHERE s.removed = 0
		  AND EXISTS (SELECT 1 FROM meta_phrase t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
		  AND NOT EXISTS (SELECT 1 FROM meta_phrase t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
	END

	EXEC dbo.p_xlsx_sync_sheet
		@target_table = 'meta_phrase',
		@clean_table = '#clean_phrase',
		@sheet_label = 'phrase',
		@obj_type_label = 'meta_phrase',
		@a_cols_csv = 'source_code,builtin_code,module,css_class,inactive,editor_note,caption,helptext,is_final,is_protected',
		@l_cols_csv = 'caption,helptext',
		@lang = @lang,
		@sec_lang = @sec_lang,
		@is_trans_mode = @is_trans_mode,
		@import_origin = @import_origin,
		@user_session = @user_session;

	DROP TABLE #clean_phrase;

	-- =========================================================================
	-- 3. Zpracování záložky: menu (tabulka meta_menu – bez čtení svg_icon)
	-- =========================================================================
	IF OBJECT_ID('XLSX_menu$') IS NULL
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_menu$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_menu$';
		RETURN;
	END

	IF COL_LENGTH('XLSX_menu$', 'removed') IS NULL ALTER TABLE XLSX_menu$ ADD removed bit NOT NULL DEFAULT 0;

	SET @bad_code = NULL;
	SELECT TOP 1 @bad_code = LTRIM(RTRIM(builtin_code)) FROM XLSX_menu$ GROUP BY LTRIM(RTRIM(builtin_code)) HAVING COUNT(*) > 1;
	IF @bad_code IS NOT NULL
	BEGIN
		EXEC insert_request_message 'Duplicitní builtin_code na záložce menu', 3, @obj_type = 'menu', @obj_name = @bad_code;
		RETURN;
	END

	IF OBJECT_ID('tempdb..#clean_menu') IS NOT NULL DROP TABLE #clean_menu;

	SELECT
		LTRIM(RTRIM(s.builtin_code)) AS builtin_code,
		dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.builtin_code)), '') AS orig_uuid,
		LTRIM(RTRIM(ISNULL(s.parent_code, ''))) AS parent_code,
		CASE WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '') ELSE NULL END AS parent_uuid,
		ISNULL(s.sort_code, '') AS sort_code,
		LTRIM(RTRIM(ISNULL(s.target_page, ''))) AS target_page,
		CASE WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page))) ELSE NULL END AS target_object,
		ISNULL(s.url_parameters, '') AS url_parameters,
		ISNULL(s.target_url, '') AS target_url,
		ISNULL(s.target_window, '') AS target_window,
		ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S') AS system_role,
		ISNULL(TRY_CAST(s.permanent AS bit), 0) AS permanent,
		ISNULL(TRY_CAST(s.removed AS bit), 0) AS removed,
		ISNULL(s.css_class, '') AS css_class,
		ISNULL(s.editor_note, '') AS editor_note,
		ISNULL(s.caption, '') AS caption,
		ISNULL(s.description, '') AS description,
		ISNULL(s.helptext, '') AS helptext,
		CAST(1 AS bit) AS is_final,
		CAST(1 AS bit) AS is_protected,
		dbo.f_xlsx_clean(s.caption_l, 1) AS caption_l,
		dbo.f_xlsx_clean(s.description_l, 1) AS description_l,
		dbo.f_xlsx_clean(s.helptext_l, 1) AS helptext_l
	INTO #clean_menu
	FROM XLSX_menu$ s;

	IF @is_trans_mode = 0
	BEGIN
		-- Kontrola referenční integrity parent_code a target_page před zápisem
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.builtin_code + ' -> ' + s.parent_code
		FROM #clean_menu s
		WHERE s.removed = 0 AND s.parent_code <> ''
		  AND NOT EXISTS (SELECT 1 FROM #clean_menu p WHERE p.orig_uuid = s.parent_uuid AND p.removed = 0)
		  AND NOT EXISTS (SELECT 1 FROM meta_menu p WHERE p.original = s.parent_uuid AND p.object_owner = @sys_owner AND p.record_type = 'A' AND p.removed = 0);

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující nadřízená položka menu (parent_code)', 3, @obj_type = 'meta_menu', @obj_name = @bad_code;
			RETURN;
		END

		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.builtin_code + ' -> ' + s.target_page
		FROM #clean_menu s
		WHERE s.removed = 0 AND s.target_page <> ''
		  AND NOT EXISTS (SELECT 1 FROM meta_object mo WHERE mo.original = s.target_object AND mo.object_type = 'P' AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0);

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující cílová stránka v menu (target_page)', 3, @obj_type = 'meta_menu', @obj_name = @bad_code;
			RETURN;
		END
	END
	ELSE
	BEGIN
		INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
		SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je položka menu neplatná (removed=1)', 'meta_menu', s.builtin_code
		FROM #clean_menu s
		WHERE s.removed = 0
		  AND EXISTS (SELECT 1 FROM meta_menu t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
		  AND NOT EXISTS (SELECT 1 FROM meta_menu t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
	END

	EXEC dbo.p_xlsx_sync_sheet
		@target_table = 'meta_menu',
		@clean_table = '#clean_menu',
		@sheet_label = 'menu',
		@obj_type_label = 'meta_menu',
		@a_cols_csv = 'builtin_code,parent_uuid,sort_code,target_object,url_parameters,target_url,target_window,system_role,permanent,css_class,editor_note,caption,description,helptext,is_final,is_protected',
		@l_cols_csv = 'caption,description,helptext',
		@lang = @lang,
		@sec_lang = @sec_lang,
		@is_trans_mode = @is_trans_mode,
		@import_origin = @import_origin,
		@user_session = @user_session,
		@extra_filter = N'',
		@protect_rem_cond = N'AND s.builtin_code <> ''home''';

	DROP TABLE #clean_menu;

	-- =========================================================================
	-- 4. Zpracování volitelné záložky: class (tabulka meta_class – bez čtení svg_icon)
	-- =========================================================================
	IF OBJECT_ID('XLSX_class$') IS NOT NULL
	BEGIN
		IF COL_LENGTH('XLSX_class$', 'removed') IS NULL ALTER TABLE XLSX_class$ ADD removed varchar(10) NOT NULL DEFAULT '0';
		IF COL_LENGTH('XLSX_class$', 'days_in_trash') IS NULL ALTER TABLE XLSX_class$ ADD days_in_trash varchar(20) NOT NULL DEFAULT '365';

		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(class_name)) FROM XLSX_class$ GROUP BY LTRIM(RTRIM(class_name)) HAVING COUNT(*) > 1;
		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní class_name na záložce class', 3, @obj_type = 'class', @obj_name = @bad_code;
			RETURN;
		END

		IF OBJECT_ID('tempdb..#clean_class') IS NOT NULL DROP TABLE #clean_class;

		SELECT
			LTRIM(RTRIM(ISNULL(s.class_name, ''))) AS class_name,
			dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), LTRIM(RTRIM(ISNULL(s.class_name, ''))), '') AS orig_uuid,
			ISNULL(NULLIF(LTRIM(RTRIM(s.storage_type)), ''), 'T') AS storage_type,
			LTRIM(RTRIM(ISNULL(s.storage_code, ''))) AS storage_code,
			dbo.f_generate_original('meta_object', @sys_owner, ISNULL(NULLIF(LTRIM(RTRIM(s.storage_type)), ''), 'T'), LTRIM(RTRIM(ISNULL(s.storage_code, '')))) AS storage_object,
			LTRIM(RTRIM(ISNULL(s.ancestor_code, ''))) AS ancestor_code,
			CASE WHEN LTRIM(RTRIM(ISNULL(s.ancestor_code, ''))) <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), LTRIM(RTRIM(s.ancestor_code)), '') ELSE NULL END AS ancestor_class,
			LTRIM(RTRIM(ISNULL(s.sort_code, ''))) AS sort_code,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.days_in_trash, 0) AS smallint), 365) AS days_in_trash,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.is_final, 0) AS bit), 1) AS is_final,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.is_protected, 0) AS bit), 0) AS is_protected,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.inactive, 0) AS bit), 0) AS inactive,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.removed, 0) AS bit), 0) AS removed,
			NULLIF(dbo.f_xlsx_clean(s.editor_note, 0), '') AS editor_note,
			NULLIF(dbo.f_xlsx_clean(s.caption, 0), '') AS caption,
			NULLIF(dbo.f_xlsx_clean(s.caption_plural, 0), '') AS caption_plural,
			NULLIF(dbo.f_xlsx_clean(s.description, 0), '') AS description,
			NULLIF(dbo.f_xlsx_clean(s.helptext, 0), '') AS helptext,
			NULLIF(dbo.f_xlsx_clean(s.caption_l, 1), '') AS caption_l,
			NULLIF(dbo.f_xlsx_clean(s.caption_plural_l, 1), '') AS caption_plural_l,
			NULLIF(dbo.f_xlsx_clean(s.description_l, 1), '') AS description_l,
			NULLIF(dbo.f_xlsx_clean(s.helptext_l, 1), '') AS helptext_l,
			CAST(1 AS bit) AS storage_valid
		INTO #clean_class
		FROM XLSX_class$ s;

		UPDATE s
		SET s.storage_valid = 0
		FROM #clean_class s
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object mo
			WHERE mo.original = s.storage_object AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0
		);

		INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
		SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je úložný objekt (storage_code) neplatný nebo neexistuje (třída přeskočena)', 'meta_class', s.class_name + ' -> ' + s.storage_type + ':' + s.storage_code
		FROM #clean_class s
		WHERE s.removed = 0 AND s.storage_valid = 0;

		IF @is_trans_mode = 0
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'Primitivní třídu svázanou s existujícím fyzickým objektem nelze odstranit (removed=1 ignorováno)', 'meta_class', s.class_name
			FROM #clean_class s
			WHERE s.removed = 1 AND s.storage_valid = 1 AND s.class_name = s.storage_code
			  AND EXISTS (SELECT 1 FROM meta_class t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);

			SET @bad_code = NULL;
			SELECT TOP 1 @bad_code = s.class_name + ' -> ' + s.ancestor_code
			FROM #clean_class s
			WHERE s.removed = 0 AND s.storage_valid = 1 AND s.ancestor_code <> ''
			  AND NOT EXISTS (SELECT 1 FROM #clean_class p WHERE p.orig_uuid = s.ancestor_class AND p.removed = 0 AND p.storage_valid = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_class p WHERE p.original = s.ancestor_class AND p.object_owner = @sys_owner AND p.record_type = 'A' AND p.removed = 0);

			IF @bad_code IS NOT NULL
			BEGIN
				EXEC insert_request_message 'Neexistující nadřízená třída (ancestor_code) na záložce class', 3, @obj_type = 'meta_class', @obj_name = @bad_code;
				RETURN;
			END
		END
		ELSE
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je logická třída neplatná (removed=1)', 'meta_class', s.class_name
			FROM #clean_class s
			WHERE s.removed = 0 AND s.storage_valid = 1
			  AND EXISTS (SELECT 1 FROM meta_class t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_class t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END

		-- Normalizace zděděných hodnot přímo v #clean_class před porovnáním s DB
		UPDATE s
		SET
			s.caption = CASE WHEN ISNULL(s.caption, '') = ISNULL(COALESCE(anc_s.caption, anc_db.caption), '') THEN NULL ELSE s.caption END,
			s.caption_plural = CASE WHEN ISNULL(s.caption_plural, '') = ISNULL(COALESCE(anc_s.caption_plural, anc_db.caption_plural), '') THEN NULL ELSE s.caption_plural END,
			s.description = CASE WHEN ISNULL(s.description, '') = ISNULL(COALESCE(anc_s.description, anc_db.description), '') THEN NULL ELSE s.description END,
			s.helptext = CASE WHEN ISNULL(s.helptext, '') = ISNULL(COALESCE(anc_s.helptext, anc_db.helptext), '') THEN NULL ELSE s.helptext END,
			s.caption_l = CASE WHEN ISNULL(s.caption_l, '') = ISNULL(COALESCE(anc_s.caption_l, anc_l.caption), '') THEN NULL ELSE s.caption_l END,
			s.caption_plural_l = CASE WHEN ISNULL(s.caption_plural_l, '') = ISNULL(COALESCE(anc_s.caption_plural_l, anc_l.caption_plural), '') THEN NULL ELSE s.caption_plural_l END,
			s.description_l = CASE WHEN ISNULL(s.description_l, '') = ISNULL(COALESCE(anc_s.description_l, anc_l.description), '') THEN NULL ELSE s.description_l END,
			s.helptext_l = CASE WHEN ISNULL(s.helptext_l, '') = ISNULL(COALESCE(anc_s.helptext_l, anc_l.helptext), '') THEN NULL ELSE s.helptext_l END
		FROM #clean_class s
		LEFT JOIN #clean_class anc_s ON anc_s.orig_uuid = s.ancestor_class AND anc_s.removed = 0 AND anc_s.storage_valid = 1
		LEFT JOIN meta_class anc_db ON anc_db.original = s.ancestor_class AND anc_db.object_owner = @sys_owner AND anc_db.record_type = 'A' AND anc_db.removed = 0
		LEFT JOIN meta_class anc_l ON anc_l.original = s.ancestor_class AND anc_l.object_owner = @sys_owner AND anc_l.record_type = 'L' AND anc_l.[language] = @sec_lang AND anc_l.removed = 0 AND @is_trans_mode = 1
		WHERE s.ancestor_class IS NOT NULL;

		EXEC dbo.p_xlsx_sync_sheet
			@target_table = 'meta_class',
			@clean_table = '#clean_class',
			@sheet_label = 'class',
			@obj_type_label = 'meta_class',
			@a_cols_csv = 'class_name,storage_object,ancestor_class,sort_code,days_in_trash,is_final,is_protected,inactive,editor_note,caption,caption_plural,description,helptext',
			@l_cols_csv = 'caption,caption_plural,description,helptext',
			@lang = @lang,
			@sec_lang = @sec_lang,
			@is_trans_mode = @is_trans_mode,
			@import_origin = @import_origin,
			@user_session = @user_session,
			@extra_filter = N'AND s.storage_valid = 1',
			@protect_rem_cond = N'AND (s.class_name <> s.storage_code OR s.storage_valid = 0)';

		DROP TABLE #clean_class;
	END

	-- =========================================================================
	-- 5. Zpracování volitelné záložky: column (tabulka meta_column)
	-- =========================================================================
	IF OBJECT_ID('XLSX_column$') IS NOT NULL
	BEGIN
		IF COL_LENGTH('XLSX_column$', 'removed') IS NULL ALTER TABLE XLSX_column$ ADD removed varchar(10) NOT NULL DEFAULT '0';

		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(class_name)) + '.' + LTRIM(RTRIM(column_name))
		FROM XLSX_column$
		GROUP BY LTRIM(RTRIM(class_name)), LTRIM(RTRIM(column_name))
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní kombinace (class_name, column_name) na záložce column', 3, @obj_type = 'column', @obj_name = @bad_code;
			RETURN;
		END

		DECLARE @global_cls_uuid uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'sys_global_columns', '');

		IF OBJECT_ID('tempdb..#clean_column') IS NOT NULL DROP TABLE #clean_column;

		SELECT
			LTRIM(RTRIM(ISNULL(s.class_name, ''))) AS class_name,
			LTRIM(RTRIM(ISNULL(s.column_name, ''))) AS column_name,
			p.calc_parent_class AS parent_class,
			dbo.f_generate_original('meta_column', @sys_owner, CAST(p.calc_parent_class AS varchar(36)), LTRIM(RTRIM(ISNULL(s.column_name, '')))) AS orig_uuid,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.parent_order, 0) AS int), 0) AS parent_order,
			NULLIF(dbo.f_xlsx_clean(s.sort_code, 0), '') AS sort_code,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.list_order, 0), '') AS int) AS list_order,
			NULLIF(dbo.f_xlsx_clean(s.input_type, 0), '') AS input_type,
			NULLIF(dbo.f_xlsx_clean(s.input_width, 0), '') AS input_width,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.input_rows, 0), '') AS int) AS input_rows,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.max_length, 0), '') AS int) AS max_length,
			NULLIF(dbo.f_xlsx_clean(s.css_class, 0), '') AS css_class,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.translate, 0), '') AS bit) AS translate,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.history, 0), '') AS bit) AS history,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.is_html, 0), '') AS bit) AS is_html,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.is_mandatory, 0), '') AS bit) AS is_mandatory,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.is_url, 0), '') AS bit) AS is_url,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.is_computed, 0), '') AS bit) AS is_computed,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.show_empty, 0), '') AS bit) AS show_empty,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.hidden, 0), '') AS bit) AS hidden,
			TRY_CAST(NULLIF(dbo.f_xlsx_clean(s.customizable, 0), '') AS bit) AS customizable,
			v.ancestor_column,
			CASE WHEN LTRIM(RTRIM(ISNULL(s.class_name, ''))) <> 'sys_global_columns' AND v.ancestor_column <> '' THEN dbo.f_generate_original('meta_column', @sys_owner, CAST(@global_cls_uuid AS varchar(36)), v.ancestor_column) ELSE NULL END AS ancestor,
			ISNULL(dbo.f_xlsx_clean(s.referenced_codetable, 0), '') AS referenced_codetable,
			v.referenced_class_code,
			CASE WHEN v.referenced_class_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), v.referenced_class_code, '') ELSE NULL END AS referenced_class,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.is_final, 0) AS bit), 1) AS is_final,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.is_protected, 0) AS bit), 0) AS is_protected,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.inactive, 0) AS bit), 0) AS inactive,
			ISNULL(TRY_CAST(dbo.f_xlsx_clean(s.removed, 0) AS bit), 0) AS removed,
			NULLIF(dbo.f_xlsx_clean(s.editor_note, 0), '') AS editor_note,
			NULLIF(dbo.f_xlsx_clean(s.caption, 0), '') AS caption,
			NULLIF(dbo.f_xlsx_clean(s.caption_plural, 0), '') AS caption_plural,
			NULLIF(dbo.f_xlsx_clean(s.description, 0), '') AS description,
			NULLIF(dbo.f_xlsx_clean(s.label, 0), '') AS label,
			NULLIF(dbo.f_xlsx_clean(s.header, 0), '') AS header,
			NULLIF(dbo.f_xlsx_clean(s.helptext, 0), '') AS helptext,
			NULLIF(dbo.f_xlsx_clean(s.placeholder, 0), '') AS placeholder,
			NULLIF(dbo.f_xlsx_clean(s.caption_l, 1), '') AS caption_l,
			NULLIF(dbo.f_xlsx_clean(s.caption_plural_l, 1), '') AS caption_plural_l,
			NULLIF(dbo.f_xlsx_clean(s.description_l, 1), '') AS description_l,
			NULLIF(dbo.f_xlsx_clean(s.label_l, 1), '') AS label_l,
			NULLIF(dbo.f_xlsx_clean(s.header_l, 1), '') AS header_l,
			NULLIF(dbo.f_xlsx_clean(s.helptext_l, 1), '') AS helptext_l,
			NULLIF(dbo.f_xlsx_clean(s.placeholder_l, 1), '') AS placeholder_l,
			CAST(1 AS bit) AS class_valid,
			CAST(1 AS bit) AS can_remove_col
		INTO #clean_column
		FROM XLSX_column$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), LTRIM(RTRIM(ISNULL(s.class_name, ''))), '') AS calc_parent_class
		) p
		CROSS APPLY (
			SELECT
				dbo.f_xlsx_clean(s.ancestor_column, 0) AS ancestor_column,
				dbo.f_xlsx_clean(s.referenced_class_code, 0) AS referenced_class_code
		) v;

		UPDATE s
		SET s.class_valid = 0
		FROM #clean_column s
		WHERE NOT EXISTS (
			SELECT 1
			FROM meta_class mc
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0
			WHERE mc.original = s.parent_class AND mc.object_owner = @sys_owner AND mc.record_type = 'A' AND mc.removed = 0
		);

		INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
		SELECT @@SPID, 2, 'V Excelu je removed=0, ale nadřízená logická třída v databázi není platná (sloupec přeskočen)', 'meta_column', s.class_name + '.' + s.column_name
		FROM #clean_column s
		WHERE s.removed = 0 AND s.class_valid = 0;

		IF @is_trans_mode = 0
		BEGIN
			-- Fyzicky existující sloupec primitivní třídy nelze označit jako removed = 1
			UPDATE s
			SET s.can_remove_col = 0
			FROM #clean_column s
			JOIN meta_class mc ON mc.original = s.parent_class AND mc.object_owner = @sys_owner AND mc.record_type = 'A' AND mc.removed = 0
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0
			JOIN v_syscolumns vc ON vc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT AND vc.colname = s.column_name COLLATE DATABASE_DEFAULT
			WHERE s.removed = 1 AND mc.class_name = mo.builtin_code;

			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'Fyzicky existující sloupec databázové tabulky nelze v metadatech odstranit (removed=1 ignorováno)', 'meta_column', s.class_name + '.' + s.column_name
			FROM #clean_column s
			WHERE s.removed = 1 AND s.can_remove_col = 0
			  AND EXISTS (SELECT 1 FROM meta_column t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END
		ELSE
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je sloupec neplatný (removed=1)', 'meta_column', s.class_name + '.' + s.column_name
			FROM #clean_column s
			WHERE s.removed = 0 AND s.class_valid = 1
			  AND EXISTS (SELECT 1 FROM meta_column t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_column t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END

		-- Normalizace zděděných hodnot přímo v #clean_column před porovnáním s DB
		UPDATE s
		SET
			s.list_order = CASE WHEN s.list_order = COALESCE(gc_s.list_order, gc_db.list_order) THEN NULL ELSE s.list_order END,
			s.caption = CASE WHEN ISNULL(s.caption, '') = ISNULL(COALESCE(gc_s.caption, gc_db.caption), '') THEN NULL ELSE s.caption END,
			s.caption_plural = CASE WHEN ISNULL(s.caption_plural, '') = ISNULL(COALESCE(gc_s.caption_plural, gc_db.caption_plural), '') THEN NULL ELSE s.caption_plural END,
			s.description = CASE WHEN ISNULL(s.description, '') = ISNULL(COALESCE(gc_s.description, gc_db.description), '') THEN NULL ELSE s.description END,
			s.label = CASE WHEN ISNULL(s.label, '') = ISNULL(COALESCE(gc_s.label, gc_db.label), '') THEN NULL ELSE s.label END,
			s.header = CASE WHEN ISNULL(s.header, '') = ISNULL(COALESCE(gc_s.header, gc_db.header), '') THEN NULL ELSE s.header END,
			s.helptext = CASE WHEN ISNULL(s.helptext, '') = ISNULL(COALESCE(gc_s.helptext, gc_db.helptext), '') THEN NULL ELSE s.helptext END,
			s.placeholder = CASE WHEN ISNULL(s.placeholder, '') = ISNULL(COALESCE(gc_s.placeholder, gc_db.placeholder), '') THEN NULL ELSE s.placeholder END,
			s.input_type = CASE WHEN ISNULL(s.input_type, '') = ISNULL(COALESCE(gc_s.input_type, gc_db.input_type), '') THEN NULL ELSE s.input_type END,
			s.input_width = CASE WHEN ISNULL(s.input_width, '') = ISNULL(COALESCE(gc_s.input_width, gc_db.input_width), '') THEN NULL ELSE s.input_width END,
			s.input_rows = CASE WHEN s.input_rows = COALESCE(gc_s.input_rows, gc_db.input_rows) THEN NULL ELSE s.input_rows END,
			s.max_length = CASE WHEN s.max_length = COALESCE(gc_s.max_length, gc_db.max_length) THEN NULL ELSE s.max_length END,
			s.css_class = CASE WHEN ISNULL(s.css_class, '') = ISNULL(COALESCE(gc_s.css_class, gc_db.css_class), '') THEN NULL ELSE s.css_class END,
			s.translate = CASE WHEN s.translate = COALESCE(gc_s.translate, gc_db.translate) THEN NULL ELSE s.translate END,
			s.history = CASE WHEN s.history = COALESCE(gc_s.history, gc_db.history) THEN NULL ELSE s.history END,
			s.is_html = CASE WHEN s.is_html = COALESCE(gc_s.is_html, gc_db.is_html) THEN NULL ELSE s.is_html END,
			s.is_mandatory = CASE WHEN s.is_mandatory = COALESCE(gc_s.is_mandatory, gc_db.is_mandatory) THEN NULL ELSE s.is_mandatory END,
			s.is_url = CASE WHEN s.is_url = COALESCE(gc_s.is_url, gc_db.is_url) THEN NULL ELSE s.is_url END,
			s.is_computed = CASE WHEN s.is_computed = COALESCE(gc_s.is_computed, gc_db.is_computed) THEN NULL ELSE s.is_computed END,
			s.show_empty = CASE WHEN s.show_empty = COALESCE(gc_s.show_empty, gc_db.show_empty) THEN NULL ELSE s.show_empty END,
			s.hidden = CASE WHEN s.hidden = COALESCE(gc_s.hidden, gc_db.hidden) THEN NULL ELSE s.hidden END,
			s.customizable = CASE WHEN s.customizable = COALESCE(gc_s.customizable, gc_db.customizable) THEN NULL ELSE s.customizable END,
			s.referenced_codetable = CASE WHEN ISNULL(s.referenced_codetable, '') = ISNULL(COALESCE(gc_s.referenced_codetable, gc_db.referenced_codetable), '') THEN '' ELSE ISNULL(s.referenced_codetable, '') END,
			s.referenced_class = CASE WHEN s.referenced_class = COALESCE(gc_s.referenced_class, gc_db.referenced_class) THEN NULL ELSE s.referenced_class END,
			s.caption_l = CASE WHEN ISNULL(s.caption_l, '') = ISNULL(COALESCE(gc_s.caption_l, gc_l.caption), '') THEN NULL ELSE s.caption_l END,
			s.caption_plural_l = CASE WHEN ISNULL(s.caption_plural_l, '') = ISNULL(COALESCE(gc_s.caption_plural_l, gc_l.caption_plural), '') THEN NULL ELSE s.caption_plural_l END,
			s.description_l = CASE WHEN ISNULL(s.description_l, '') = ISNULL(COALESCE(gc_s.description_l, gc_l.description), '') THEN NULL ELSE s.description_l END,
			s.label_l = CASE WHEN ISNULL(s.label_l, '') = ISNULL(COALESCE(gc_s.label_l, gc_l.label), '') THEN NULL ELSE s.label_l END,
			s.header_l = CASE WHEN ISNULL(s.header_l, '') = ISNULL(COALESCE(gc_s.header_l, gc_l.header), '') THEN NULL ELSE s.header_l END,
			s.helptext_l = CASE WHEN ISNULL(s.helptext_l, '') = ISNULL(COALESCE(gc_s.helptext_l, gc_l.helptext), '') THEN NULL ELSE s.helptext_l END,
			s.placeholder_l = CASE WHEN ISNULL(s.placeholder_l, '') = ISNULL(COALESCE(gc_s.placeholder_l, gc_l.placeholder), '') THEN NULL ELSE s.placeholder_l END
		FROM #clean_column s
		LEFT JOIN #clean_column gc_s ON gc_s.orig_uuid = s.ancestor AND gc_s.removed = 0 AND gc_s.class_valid = 1
		LEFT JOIN meta_column gc_db ON gc_db.original = s.ancestor AND gc_db.object_owner = @sys_owner AND gc_db.record_type = 'A' AND gc_db.removed = 0
		LEFT JOIN meta_column gc_l ON gc_l.original = s.ancestor AND gc_l.object_owner = @sys_owner AND gc_l.record_type = 'L' AND gc_l.[language] = @sec_lang AND gc_l.removed = 0 AND @is_trans_mode = 1
		WHERE s.parent_class <> @global_cls_uuid
		  AND s.ancestor IS NOT NULL;

		EXEC dbo.p_xlsx_sync_sheet
			@target_table = 'meta_column',
			@clean_table = '#clean_column',
			@sheet_label = 'column',
			@obj_type_label = 'meta_column',
			@a_cols_csv = 'parent_class,column_name,parent_order,sort_code,list_order,input_type,input_width,input_rows,max_length,css_class,translate,history,is_html,is_mandatory,is_url,is_computed,show_empty,hidden,customizable,ancestor,referenced_codetable,referenced_class,is_final,is_protected,inactive,editor_note,caption,caption_plural,description,label,header,helptext,placeholder',
			@l_cols_csv = 'caption,caption_plural,description,label,header,helptext,placeholder',
			@lang = @lang,
			@sec_lang = @sec_lang,
			@is_trans_mode = @is_trans_mode,
			@import_origin = @import_origin,
			@user_session = @user_session,
			@extra_filter = N'AND s.class_valid = 1',
			@protect_rem_cond = N'AND s.can_remove_col = 1';

		DROP TABLE #clean_column;
	END

	-- =========================================================================
	-- 6. Registrace ostrého importu (@import_mode = '2') do tabulky service_logbook
	-- =========================================================================
	IF @import_mode = '2' AND OBJECT_ID('service_logbook') IS NOT NULL
	BEGIN
		DECLARE @log_name varchar(250) = 'p_xlsx_meta_object (' + CASE WHEN @is_trans_mode = 1 THEN @lang + '->' + @sec_lang ELSE @lang END + ')';
		DECLARE @log_ver varchar(200) = ISNULL(NULLIF(@version_date, ''), CONVERT(varchar(20), GETDATE(), 120));
		DECLARE @log_content varchar(max) = LTRIM(RTRIM(
			ISNULL(@import_origin, '')
			+ CASE WHEN ISNULL(@import_origin, '') <> '' AND @pkg_description <> '' THEN ': ' ELSE '' END
			+ @pkg_description
		));

		INSERT INTO service_logbook ([name], [version], content)
		VALUES (@log_name, @log_ver, NULLIF(@log_content, ''));
	END
END
GO