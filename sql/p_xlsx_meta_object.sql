/* =============================================================================
 * Verze: 2026-10-14 22:36
 * Soubor: p_xlsx_meta_object.sql
 * Procedura: p_xlsx_meta_object
 * Účel: Hromadný import systémových stránek (page), globálních frází (phrase)
 *       a struktury navigace (menu) ze staging tabulek XLSX_*$ do tabulek
 *       meta_object a meta_menu.
 *
 * Vazby na okolí:
 * - Volána z PHP třídy excel_reader (metoda run_package) při testovacím ('1')
 *   nebo ostrém ('2') importu a z distribuční SQL dávky fillup_meta_object.sql.
 * - Očekává staging tabulky XLSX_CONTENT_INFO$, XLSX_page$, XLSX_menu$
 *   a XLSX_phrase$ připravené a zvalidované třídou xlsx_meta_object.
 * - Čte kontext relace (login_session_uuid) z tabulky dbsession pro @@SPID.
 * - Validuje kódy jazyků proti tabulce [language].
 * - Využívá deterministickou funkci dbo.f_generate_original pro výpočet klíčů
 *   original a převod textových odkazů (parent_code, target_page) na UUID.
 * - Zapisuje průběžné a chybové zprávy přes proceduru insert_request_message.
 *
 * Architektura zápisu:
 * - Upravuje výhradně systémové záznamy (object_owner = 0x00).
 * - Texty základního jazyka (language) zapisuje do 'A' záznamu i do
 *   symetrického 'L' záznamu. Nepřekládaný kontext editor_note ukládá do 'A'.
 * - Pokud je v CONTENT_INFO vyplněn second_language, zapisuje překlady ze
 *   sloupců *_l do 'L' záznamu druhého jazyka s fallbackem na základní jazyk.
 * ============================================================================= */

EXECUTE dropni 'p_xlsx_meta_object', 'P'
GO

CREATE PROCEDURE p_xlsx_meta_object
	@import_mode varchar(1) = '1'
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier); -- Identifikátor systémového vlastníka
	DECLARE @user_session uniqueidentifier;                               -- UUID relace pro auditní stopu
	DECLARE @lang varchar(2) = '';                                        -- Primární jazyk balíčku z CONTENT_INFO
	DECLARE @sec_lang varchar(2) = '';                                    -- Volitelný druhý jazyk z CONTENT_INFO
	DECLARE @import_origin varchar(255) = NULL;                           -- Původ importu (měkký audit)
	DECLARE @cnt_a int = 0;                                               -- Počitadlo zpracovaných 'A' záznamů
	DECLARE @cnt_l int = 0;                                               -- Počitadlo zpracovaných 'L' záznamů
	DECLARE @bad_code varchar(200);                                       -- Pomocná proměnná pro výpis chybných vazeb

	-- -------------------------------------------------------------------------
	-- 0. Získání auditního kontextu a načtení řídicí tabulky XLSX_CONTENT_INFO$
	-- -------------------------------------------------------------------------
	SELECT @user_session = login_session_uuid
	FROM dbsession
	WHERE spid = @@SPID;

	IF @user_session IS NULL
		SET @user_session = @sys_owner;                                   -- Fallback pro běh mimo standardní relaci

	IF OBJECT_ID('XLSX_CONTENT_INFO$') IS NULL
	BEGIN
		EXEC insert_request_message 'Chybí řídicí tabulka XLSX_CONTENT_INFO$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_CONTENT_INFO$';
		RETURN;
	END

	SELECT TOP 1
		@lang = LTRIM(RTRIM(ISNULL([language], '')))
	FROM XLSX_CONTENT_INFO$;

	-- Dynamické načtení volitelných sloupců z XLSX_CONTENT_INFO$ (pokud v tabulce existují)
	IF COL_LENGTH('XLSX_CONTENT_INFO$', 'second_language') IS NOT NULL
	BEGIN
		EXEC sp_executesql
			N'SELECT TOP 1 @out = LTRIM(RTRIM(ISNULL(second_language, ''''))) FROM XLSX_CONTENT_INFO$',
			N'@out varchar(2) OUTPUT',
			@out = @sec_lang OUTPUT;
	END

	IF COL_LENGTH('XLSX_CONTENT_INFO$', 'import_origin') IS NOT NULL
	BEGIN
		EXEC sp_executesql
			N'SELECT TOP 1 @out = NULLIF(LTRIM(RTRIM(import_origin)), '''') FROM XLSX_CONTENT_INFO$',
			N'@out varchar(255) OUTPUT',
			@out = @import_origin OUTPUT;
	END

	-- Kontrola platnosti primárního jazyka proti číselníku [language]
	IF @lang = '' OR NOT EXISTS (SELECT 1 FROM [language] WHERE [language] = @lang)
	BEGIN
		EXEC insert_request_message 'Neplatný nebo chybějící kód základního jazyka (language) v CONTENT_INFO', 3, @obj_type = 'Jazyk', @obj_name = @lang;
		RETURN;
	END

	-- Kontrola platnosti druhého jazyka (pokud je zadán)
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
	END

	-- =========================================================================
	-- 1. Zpracování záložky: page (tabulka meta_object, object_type = 'P')
	-- =========================================================================
	IF OBJECT_ID('XLSX_page$') IS NOT NULL
	BEGIN
		-- Kontrola duplicitních builtin_code v rámci záložky page
		SELECT TOP 1 @bad_code = builtin_code
		FROM XLSX_page$
		GROUP BY builtin_code
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní builtin_code na záložce page', 3, @obj_type = 'page', @obj_name = @bad_code;
			RETURN;
		END

		-- 1.A) Zpracování hlavních záznamů ('A') pro stránky
		UPDATE t
		SET
			t.[language] = @lang,
			t.system_role = ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'),
			t.module = ISNULL(s.module, ''),
			t.inactive = ISNULL(TRY_CAST(s.inactive AS bit), 0),
			t.editor_note = ISNULL(s.editor_note, ''),
			t.caption = ISNULL(s.caption, ''),
			t.description = ISNULL(s.description, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_object t
		JOIN XLSX_page$ s
			ON dbo.f_generate_original('meta_object', @sys_owner, 'P', s.builtin_code) = t.original
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'A'
		  AND t.removed = 0;

		SET @cnt_a = @@ROWCOUNT;

		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			inactive, import_origin,
			object_type, builtin_code, system_role, module,
			editor_note, caption, description, helptext,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.orig_uuid, @sys_owner, x.orig_uuid, 'A', 'A', @lang,
			ISNULL(TRY_CAST(s.inactive AS bit), 0), @import_origin,
			'P', s.builtin_code, ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(s.module, ''),
			ISNULL(s.editor_note, ''), ISNULL(s.caption, ''), ISNULL(s.description, ''), ISNULL(s.helptext, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_page$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_object', @sys_owner, 'P', s.builtin_code) AS orig_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND t.removed = 0
		);

		SET @cnt_a = @cnt_a + @@ROWCOUNT;

		-- 1.B) Symetrické 'L' záznamy pro primární jazyk (@lang)
		UPDATE t
		SET
			t.system_role = ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'),
			t.module = ISNULL(s.module, ''),
			t.inactive = ISNULL(TRY_CAST(s.inactive AS bit), 0),
			t.caption = ISNULL(s.caption, ''),
			t.description = ISNULL(s.description, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_object t
		JOIN XLSX_page$ s
			ON dbo.f_generate_original('meta_object', @sys_owner, 'P', s.builtin_code) = t.original
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'L'
		  AND t.[language] = @lang
		  AND t.removed = 0;

		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			inactive, import_origin,
			object_type, builtin_code, system_role, module,
			caption, description, helptext,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @lang,
			ISNULL(TRY_CAST(s.inactive AS bit), 0), @import_origin,
			'P', s.builtin_code, ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(s.module, ''),
			ISNULL(s.caption, ''), ISNULL(s.description, ''), ISNULL(s.helptext, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_page$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_object', @sys_owner, 'P', s.builtin_code) AS orig_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND t.removed = 0
		);

		-- 1.C) Jazykové 'L' záznamy pro druhý jazyk (@sec_lang), pokud je v CONTENT_INFO zadán
		IF @sec_lang <> ''
		BEGIN
			UPDATE t
			SET
				t.system_role = ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'),
				t.module = ISNULL(s.module, ''),
				t.inactive = ISNULL(TRY_CAST(s.inactive AS bit), 0),
				t.caption = ISNULL(NULLIF(s.caption_l, ''), ISNULL(s.caption, '')),
				t.description = ISNULL(NULLIF(s.description_l, ''), ISNULL(s.description, '')),
				t.helptext = ISNULL(NULLIF(s.helptext_l, ''), ISNULL(s.helptext, '')),
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN XLSX_page$ s
				ON dbo.f_generate_original('meta_object', @sys_owner, 'P', s.builtin_code) = t.original
			WHERE t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, import_origin,
				object_type, builtin_code, system_role, module,
				caption, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @sec_lang,
				ISNULL(TRY_CAST(s.inactive AS bit), 0), @import_origin,
				'P', s.builtin_code, ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(s.module, ''),
				ISNULL(NULLIF(s.caption_l, ''), ISNULL(s.caption, '')),
				ISNULL(NULLIF(s.description_l, ''), ISNULL(s.description, '')),
				ISNULL(NULLIF(s.helptext_l, ''), ISNULL(s.helptext, '')),
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM XLSX_page$ s
			CROSS APPLY (
				SELECT dbo.f_generate_original('meta_object', @sys_owner, 'P', s.builtin_code) AS orig_uuid
			) x
			WHERE NOT EXISTS (
				SELECT 1 FROM meta_object t
				WHERE t.original = x.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
				  AND t.removed = 0
			);
		END

		EXEC insert_request_message 'Záložka page byla úspěšně zpracována', 1, @intvalue = @cnt_a, @obj_type = 'meta_object (P)', @obj_name = 'page';
	END
	ELSE
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_page$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_page$';
		RETURN;
	END

	-- =========================================================================
	-- 2. Zpracování záložky: phrase (tabulka meta_object, object_type = 'G')
	-- =========================================================================
	IF OBJECT_ID('XLSX_phrase$') IS NOT NULL
	BEGIN
		SET @bad_code = NULL;

		-- Kontrola duplicitních builtin_code v rámci záložky phrase
		SELECT TOP 1 @bad_code = builtin_code
		FROM XLSX_phrase$
		GROUP BY builtin_code
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní builtin_code na záložce phrase', 3, @obj_type = 'phrase', @obj_name = @bad_code;
			RETURN;
		END

		-- 2.A) Zpracování hlavních záznamů ('A') pro globální fráze
		UPDATE t
		SET
			t.[language] = @lang,
			t.module = ISNULL(s.module, ''),
			t.editor_note = ISNULL(s.editor_note, ''),
			t.caption = ISNULL(s.caption, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_object t
		JOIN XLSX_phrase$ s
			ON dbo.f_generate_original('meta_object', @sys_owner, 'G', s.builtin_code) = t.original
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'A'
		  AND t.removed = 0;

		SET @cnt_a = @@ROWCOUNT;

		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin,
			object_type, builtin_code, system_role, module,
			editor_note, caption, description, helptext,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.orig_uuid, @sys_owner, x.orig_uuid, 'A', 'A', @lang,
			@import_origin,
			'G', s.builtin_code, 'U', ISNULL(s.module, ''),
			ISNULL(s.editor_note, ''), ISNULL(s.caption, ''), '', ISNULL(s.helptext, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_phrase$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_object', @sys_owner, 'G', s.builtin_code) AS orig_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND t.removed = 0
		);

		SET @cnt_a = @cnt_a + @@ROWCOUNT;

		-- 2.B) Symetrické 'L' záznamy pro primární jazyk (@lang)
		UPDATE t
		SET
			t.module = ISNULL(s.module, ''),
			t.caption = ISNULL(s.caption, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_object t
		JOIN XLSX_phrase$ s
			ON dbo.f_generate_original('meta_object', @sys_owner, 'G', s.builtin_code) = t.original
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'L'
		  AND t.[language] = @lang
		  AND t.removed = 0;

		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin,
			object_type, builtin_code, system_role, module,
			caption, description, helptext,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @lang,
			@import_origin,
			'G', s.builtin_code, 'U', ISNULL(s.module, ''),
			ISNULL(s.caption, ''), '', ISNULL(s.helptext, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_phrase$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_object', @sys_owner, 'G', s.builtin_code) AS orig_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND t.removed = 0
		);

		-- 2.C) Jazykové 'L' záznamy pro druhý jazyk (@sec_lang)
		IF @sec_lang <> ''
		BEGIN
			UPDATE t
			SET
				t.module = ISNULL(s.module, ''),
				t.caption = ISNULL(NULLIF(s.caption_l, ''), ISNULL(s.caption, '')),
				t.helptext = ISNULL(NULLIF(s.helptext_l, ''), ISNULL(s.helptext, '')),
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN XLSX_phrase$ s
				ON dbo.f_generate_original('meta_object', @sys_owner, 'G', s.builtin_code) = t.original
			WHERE t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, [language],
				import_origin,
				object_type, builtin_code, system_role, module,
				caption, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @sec_lang,
				@import_origin,
				'G', s.builtin_code, 'U', ISNULL(s.module, ''),
				ISNULL(NULLIF(s.caption_l, ''), ISNULL(s.caption, '')),
				'',
				ISNULL(NULLIF(s.helptext_l, ''), ISNULL(s.helptext, '')),
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM XLSX_phrase$ s
			CROSS APPLY (
				SELECT dbo.f_generate_original('meta_object', @sys_owner, 'G', s.builtin_code) AS orig_uuid
			) x
			WHERE NOT EXISTS (
				SELECT 1 FROM meta_object t
				WHERE t.original = x.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
				  AND t.removed = 0
			);
		END

		EXEC insert_request_message 'Záložka phrase byla úspěšně zpracována', 1, @intvalue = @cnt_a, @obj_type = 'meta_object (G)', @obj_name = 'phrase';
	END
	ELSE
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_phrase$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_phrase$';
		RETURN;
	END

	-- =========================================================================
	-- 3. Zpracování záložky: menu (tabulka meta_menu)
	-- =========================================================================
	IF OBJECT_ID('XLSX_menu$') IS NOT NULL
	BEGIN
		SET @bad_code = NULL;

		-- Kontrola duplicitních builtin_code v rámci záložky menu
		SELECT TOP 1 @bad_code = builtin_code
		FROM XLSX_menu$
		GROUP BY builtin_code
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní builtin_code na záložce menu', 3, @obj_type = 'menu', @obj_name = @bad_code;
			RETURN;
		END

		-- 3.A) Zpracování hlavních záznamů ('A') v tabulce meta_menu
		UPDATE t
		SET
			t.[language] = @lang,
			t.parent_uuid = x.calc_parent_uuid,
			t.sort_code = ISNULL(s.sort_code, ''),
			t.target_object = x.calc_target_object,
			t.url_parameters = ISNULL(s.url_parameters, ''),
			t.target_url = ISNULL(s.target_url, ''),
			t.target_window = ISNULL(s.target_window, ''),
			t.system_role = ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'),
			t.permanent = ISNULL(TRY_CAST(s.permanent AS bit), 0),
			t.svg_icon = ISNULL(s.svg_icon, ''),
			t.css_class = ISNULL(s.css_class, ''),
			t.editor_note = ISNULL(s.editor_note, ''),
			t.caption = ISNULL(s.caption, ''),
			t.description = ISNULL(s.description, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_menu t
		JOIN XLSX_menu$ s
			ON dbo.f_generate_original('meta_menu', @sys_owner, s.builtin_code, '') = t.original
		CROSS APPLY (
			SELECT
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '')
					ELSE NULL
				END AS calc_parent_uuid,
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page)))
					ELSE NULL
				END AS calc_target_object
		) x
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'A'
		  AND t.removed = 0;

		SET @cnt_a = @@ROWCOUNT;

		INSERT INTO meta_menu (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin,
			builtin_code, parent_uuid, sort_code,
			target_object, url_parameters, target_url, target_window,
			caption, description, helptext, editor_note,
			svg_icon, css_class, system_role, permanent,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.orig_uuid, @sys_owner, x.orig_uuid, 'A', 'A', @lang,
			@import_origin,
			s.builtin_code, x.calc_parent_uuid, ISNULL(s.sort_code, ''),
			x.calc_target_object, ISNULL(s.url_parameters, ''), ISNULL(s.target_url, ''), ISNULL(s.target_window, ''),
			ISNULL(s.caption, ''), ISNULL(s.description, ''), ISNULL(s.helptext, ''), ISNULL(s.editor_note, ''),
			ISNULL(s.svg_icon, ''), ISNULL(s.css_class, ''), ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(TRY_CAST(s.permanent AS bit), 0),
			1, 1,
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_menu$ s
		CROSS APPLY (
			SELECT
				dbo.f_generate_original('meta_menu', @sys_owner, s.builtin_code, '') AS orig_uuid,
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '')
					ELSE NULL
				END AS calc_parent_uuid,
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page)))
					ELSE NULL
				END AS calc_target_object
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_menu t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND t.removed = 0
		);

		SET @cnt_a = @cnt_a + @@ROWCOUNT;

		-- 3.B) Kontrola referenční integrity vazeb parent_code a target_page
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.builtin_code + ' -> ' + LTRIM(RTRIM(s.parent_code))
		FROM XLSX_menu$ s
		WHERE NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL
		  AND NOT EXISTS (
			SELECT 1 FROM meta_menu p
			WHERE p.original = dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '')
			  AND p.object_owner = @sys_owner
			  AND p.record_type = 'A'
			  AND p.removed = 0
		  );

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující nadřízená položka menu (parent_code)', 3, @obj_type = 'meta_menu', @obj_name = @bad_code;
			RETURN;
		END

		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.builtin_code + ' -> ' + LTRIM(RTRIM(s.target_page))
		FROM XLSX_menu$ s
		WHERE NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL
		  AND NOT EXISTS (
			SELECT 1 FROM meta_object mo
			WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page)))
			  AND mo.object_type = 'P'
			  AND mo.object_owner = @sys_owner
			  AND mo.record_type = 'A'
			  AND mo.removed = 0
		  );

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující cílová stránka v menu (target_page)', 3, @obj_type = 'meta_menu', @obj_name = @bad_code;
			RETURN;
		END

		-- 3.C) Symetrické 'L' záznamy v meta_menu pro primární jazyk (@lang)
		UPDATE t
		SET
			t.parent_uuid = x.calc_parent_uuid,
			t.sort_code = ISNULL(s.sort_code, ''),
			t.target_object = x.calc_target_object,
			t.url_parameters = ISNULL(s.url_parameters, ''),
			t.target_url = ISNULL(s.target_url, ''),
			t.target_window = ISNULL(s.target_window, ''),
			t.system_role = ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'),
			t.permanent = ISNULL(TRY_CAST(s.permanent AS bit), 0),
			t.svg_icon = ISNULL(s.svg_icon, ''),
			t.css_class = ISNULL(s.css_class, ''),
			t.caption = ISNULL(s.caption, ''),
			t.description = ISNULL(s.description, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_menu t
		JOIN XLSX_menu$ s
			ON dbo.f_generate_original('meta_menu', @sys_owner, s.builtin_code, '') = t.original
		CROSS APPLY (
			SELECT
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '')
					ELSE NULL
				END AS calc_parent_uuid,
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page)))
					ELSE NULL
				END AS calc_target_object
		) x
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'L'
		  AND t.[language] = @lang
		  AND t.removed = 0;

		INSERT INTO meta_menu (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin,
			builtin_code, parent_uuid, sort_code,
			target_object, url_parameters, target_url, target_window,
			caption, description, helptext,
			svg_icon, css_class, system_role, permanent,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @lang,
			@import_origin,
			s.builtin_code, x.calc_parent_uuid, ISNULL(s.sort_code, ''),
			x.calc_target_object, ISNULL(s.url_parameters, ''), ISNULL(s.target_url, ''), ISNULL(s.target_window, ''),
			ISNULL(s.caption, ''), ISNULL(s.description, ''), ISNULL(s.helptext, ''),
			ISNULL(s.svg_icon, ''), ISNULL(s.css_class, ''), ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(TRY_CAST(s.permanent AS bit), 0),
			1, 1,
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_menu$ s
		CROSS APPLY (
			SELECT
				dbo.f_generate_original('meta_menu', @sys_owner, s.builtin_code, '') AS orig_uuid,
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '')
					ELSE NULL
				END AS calc_parent_uuid,
				CASE
					WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL
					THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page)))
					ELSE NULL
				END AS calc_target_object
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_menu t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND t.removed = 0
		);

		-- 3.D) Jazykové 'L' záznamy v meta_menu pro druhý jazyk (@sec_lang)
		IF @sec_lang <> ''
		BEGIN
			UPDATE t
			SET
				t.parent_uuid = x.calc_parent_uuid,
				t.sort_code = ISNULL(s.sort_code, ''),
				t.target_object = x.calc_target_object,
				t.url_parameters = ISNULL(s.url_parameters, ''),
				t.target_url = ISNULL(s.target_url, ''),
				t.target_window = ISNULL(s.target_window, ''),
				t.system_role = ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'),
				t.permanent = ISNULL(TRY_CAST(s.permanent AS bit), 0),
				t.svg_icon = ISNULL(s.svg_icon, ''),
				t.css_class = ISNULL(s.css_class, ''),
				t.caption = ISNULL(NULLIF(s.caption_l, ''), ISNULL(s.caption, '')),
				t.description = ISNULL(NULLIF(s.description_l, ''), ISNULL(s.description, '')),
				t.helptext = ISNULL(NULLIF(s.helptext_l, ''), ISNULL(s.helptext, '')),
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_menu t
			JOIN XLSX_menu$ s
				ON dbo.f_generate_original('meta_menu', @sys_owner, s.builtin_code, '') = t.original
			CROSS APPLY (
				SELECT
					CASE
						WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL
						THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '')
						ELSE NULL
					END AS calc_parent_uuid,
					CASE
						WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL
						THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page)))
						ELSE NULL
					END AS calc_target_object
			) x
			WHERE t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			INSERT INTO meta_menu (
				uuid, object_owner, original, record_type, approval_status, [language],
				import_origin,
				builtin_code, parent_uuid, sort_code,
				target_object, url_parameters, target_url, target_window,
				caption, description, helptext,
				svg_icon, css_class, system_role, permanent,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @sec_lang,
				@import_origin,
				s.builtin_code, x.calc_parent_uuid, ISNULL(s.sort_code, ''),
				x.calc_target_object, ISNULL(s.url_parameters, ''), ISNULL(s.target_url, ''), ISNULL(s.target_window, ''),
				ISNULL(NULLIF(s.caption_l, ''), ISNULL(s.caption, '')),
				ISNULL(NULLIF(s.description_l, ''), ISNULL(s.description, '')),
				ISNULL(NULLIF(s.helptext_l, ''), ISNULL(s.helptext, '')),
				ISNULL(s.svg_icon, ''), ISNULL(s.css_class, ''), ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(TRY_CAST(s.permanent AS bit), 0),
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM XLSX_menu$ s
			CROSS APPLY (
				SELECT
					dbo.f_generate_original('meta_menu', @sys_owner, s.builtin_code, '') AS orig_uuid,
					CASE
						WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL
						THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '')
						ELSE NULL
					END AS calc_parent_uuid,
					CASE
						WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL
						THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page)))
						ELSE NULL
					END AS calc_target_object
			) x
			WHERE NOT EXISTS (
				SELECT 1 FROM meta_menu t
				WHERE t.original = x.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
				  AND t.removed = 0
			);
		END

		EXEC insert_request_message 'Záložka menu byla úspěšně zpracována', 1, @intvalue = @cnt_a, @obj_type = 'meta_menu', @obj_name = 'menu';
	END
	ELSE
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_menu$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_menu$';
		RETURN;
	END
END
GO