/* =============================================================================
 * Verze: 2026-10-19 23:40
 * Soubor: p_xlsx_meta_object.sql
 * Procedura: p_xlsx_meta_object
 * Účel: Hromadný import systémových stránek a tříd (page), textových frází (phrase),
 *       struktury navigace (menu), logických tříd (class) a sloupců metadat (column)
 *       ze staging tabulek XLSX_*$ do tabulek meta_object, meta_phrase, meta_menu,
 *       meta_class a meta_column.
 *
 * Vazby na okolí:
 * - Volána z PHP třídy excel_reader (metoda run_package) při testovacím ('1')
 *   nebo ostrém ('2') importu a z distribuční SQL dávky fillup_meta_object.sql.
 * - Očekává staging tabulky XLSX_CONTENT_INFO$, XLSX_page$, XLSX_menu$,
 *   XLSX_phrase$ a volitelně XLSX_class$ a XLSX_column$ připravené a zvalidované
 *   třídou xlsx_meta_object.
 * - Čte kontext relace (login_session_uuid) z tabulky dbsession pro @@SPID.
 * - Validuje kódy jazyků proti tabulce [language].
 * - Využívá deterministickou funkci dbo.f_generate_original pro výpočet klíčů
 *   original a převod mnemotechnických textových odkazů na UUID.
 * - Zapisuje průběžné a chybové zprávy přes proceduru insert_request_message.
 *
 * Architektura zápisu a dědičnosti (<do stříšek>):
 * - Upravuje výhradně systémové záznamy (object_owner = 0x00).
 * - Texty základního jazyka (language) zapisuje do 'A' záznamu i do
 *   symetrického 'L' záznamu. Nepřekládaný kontext editor_note ukládá do 'A'.
 * - Pokud je v CONTENT_INFO vyplněn second_language, zapisuje překlady ze
 *   sloupců *_l do 'L' záznamu druhého jazyka.
 * - U záložek class a column automaticky odstraňuje případné stříšky <...>
 *   vyznačující zděděnou hodnotu a pokud je hodnota shodná s předkem
 *   (ancestor_class / sys_global_columns), ukládá do DB hodnotu NULL.
 *
 * Změny:
 * - 2026-10-15: Přesměrování importu záložky phrase (XLSX_phrase$) z tabulky
 *   meta_object (typ 'G') do dedikované tabulky meta_phrase.
 * - 2026-10-18 17:30: Doplněno zpracování záložek class (XLSX_class$ -> meta_class)
 *   a column (XLSX_column$ -> meta_column) s odstraněním stříšek <...>
 *   a automatickým ukládáním NULL při shodě s hodnotou předka.
 * - 2026-10-19 23:40: Odstraněn fallback na primární jazyk při zápisu 'L' záznamů
 *   druhého jazyka (@sec_lang) na záložkách page, phrase, menu, class a column,
 *   aby prázdné sloupce *_l nebyly v DB přepisovány textem primárního jazyka.
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
		SELECT TOP 1 @bad_code = ISNULL(LTRIM(RTRIM(builtin_code)), '')
		FROM XLSX_page$
		GROUP BY ISNULL(LTRIM(RTRIM(builtin_code)), '')
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní builtin_code na záložce page', 3, @obj_type = 'page', @obj_name = @bad_code;
			RETURN;
		END

		-- 1.A) Zpracování hlavních záznamů ('A') pro stránky a UI třídy
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
			ON dbo.f_generate_original('meta_object', @sys_owner, 'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) = t.original
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
			'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), ''), ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(s.module, ''),
			ISNULL(s.editor_note, ''), ISNULL(s.caption, ''), ISNULL(s.description, ''), ISNULL(s.helptext, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_page$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_object', @sys_owner, 'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) AS orig_uuid
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
			ON dbo.f_generate_original('meta_object', @sys_owner, 'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) = t.original
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
			'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), ''), ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(s.module, ''),
			ISNULL(s.caption, ''), ISNULL(s.description, ''), ISNULL(s.helptext, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_page$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_object', @sys_owner, 'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) AS orig_uuid
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
		--      (Ukládá se čistě hodnota ze sloupců *_l bez přepisování primárním jazykem)
		IF @sec_lang <> ''
		BEGIN
			UPDATE t
			SET
				t.system_role = ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'),
				t.module = ISNULL(s.module, ''),
				t.inactive = ISNULL(TRY_CAST(s.inactive AS bit), 0),
				t.caption = ISNULL(s.caption_l, ''),
				t.description = ISNULL(s.description_l, ''),
				t.helptext = ISNULL(s.helptext_l, ''),
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN XLSX_page$ s
				ON dbo.f_generate_original('meta_object', @sys_owner, 'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) = t.original
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
				'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), ''), ISNULL(NULLIF(LTRIM(RTRIM(s.system_role)), ''), 'S'), ISNULL(s.module, ''),
				ISNULL(s.caption_l, ''),
				ISNULL(s.description_l, ''),
				ISNULL(s.helptext_l, ''),
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM XLSX_page$ s
			CROSS APPLY (
				SELECT dbo.f_generate_original('meta_object', @sys_owner, 'P', ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) AS orig_uuid
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
	-- 2. Zpracování záložky: phrase (tabulka meta_phrase)
	-- =========================================================================
	IF OBJECT_ID('XLSX_phrase$') IS NOT NULL
	BEGIN
		SET @bad_code = NULL;

		-- Kontrola duplicitních kombinací (source_code, builtin_code) v rámci záložky phrase
		SELECT TOP 1 @bad_code = ISNULL(LTRIM(RTRIM(source_code)), '') + '.' + ISNULL(LTRIM(RTRIM(builtin_code)), '')
		FROM XLSX_phrase$
		GROUP BY ISNULL(LTRIM(RTRIM(source_code)), ''), LTRIM(RTRIM(builtin_code))
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní kombinace (source_code, builtin_code) na záložce phrase', 3, @obj_type = 'phrase', @obj_name = @bad_code;
			RETURN;
		END

		-- Kontrola referenční integrity source_code proti registrovaným objektům typu 'P' v meta_object
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(s.source_code)) + ' (' + ISNULL(LTRIM(RTRIM(s.builtin_code)), '') + ')'
		FROM XLSX_phrase$ s
		WHERE NULLIF(LTRIM(RTRIM(s.source_code)), '') IS NOT NULL
		  AND NOT EXISTS (
			SELECT 1 FROM meta_object mo
			WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.source_code)))
			  AND mo.object_type = 'P'
			  AND mo.object_owner = @sys_owner
			  AND mo.record_type = 'A'
			  AND mo.removed = 0
		  );

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující zdrojový objekt (source_code) na záložce phrase', 3, @obj_type = 'meta_phrase', @obj_name = @bad_code;
			RETURN;
		END

		-- 2.A) Zpracování hlavních záznamů ('A') v tabulce meta_phrase
		UPDATE t
		SET
			t.[language] = @lang,
			t.source_code = ISNULL(LTRIM(RTRIM(s.source_code)), ''),
			t.builtin_code = ISNULL(LTRIM(RTRIM(s.builtin_code)), ''),
			t.module = ISNULL(s.module, ''),
			t.svg_icon = ISNULL(s.svg_icon, ''),
			t.css_class = ISNULL(s.css_class, ''),
			t.editor_note = ISNULL(s.editor_note, ''),
			t.caption = ISNULL(s.caption, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_phrase t
		JOIN XLSX_phrase$ s
			ON dbo.f_generate_original('meta_phrase', @sys_owner, ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) = t.original
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'A'
		  AND t.removed = 0;

		SET @cnt_a = @@ROWCOUNT;

		INSERT INTO meta_phrase (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin,
			source_code, builtin_code, module,
			svg_icon, css_class,
			editor_note, caption, helptext,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.orig_uuid, @sys_owner, x.orig_uuid, 'A', 'A', @lang,
			@import_origin,
			ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), ''), ISNULL(s.module, ''),
			ISNULL(s.svg_icon, ''), ISNULL(s.css_class, ''),
			ISNULL(s.editor_note, ''), ISNULL(s.caption, ''), ISNULL(s.helptext, ''),
			1, 1,
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_phrase$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_phrase', @sys_owner, ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) AS orig_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_phrase t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND t.removed = 0
		);

		SET @cnt_a = @cnt_a + @@ROWCOUNT;

		-- 2.B) Symetrické 'L' záznamy v meta_phrase pro primární jazyk (@lang)
		UPDATE t
		SET
			t.source_code = ISNULL(LTRIM(RTRIM(s.source_code)), ''),
			t.builtin_code = ISNULL(LTRIM(RTRIM(s.builtin_code)), ''),
			t.module = ISNULL(s.module, ''),
			t.svg_icon = ISNULL(s.svg_icon, ''),
			t.css_class = ISNULL(s.css_class, ''),
			t.caption = ISNULL(s.caption, ''),
			t.helptext = ISNULL(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_phrase t
		JOIN XLSX_phrase$ s
			ON dbo.f_generate_original('meta_phrase', @sys_owner, ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) = t.original
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'L'
		  AND t.[language] = @lang
		  AND t.removed = 0;

		INSERT INTO meta_phrase (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin,
			source_code, builtin_code, module,
			svg_icon, css_class,
			caption, helptext,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @lang,
			@import_origin,
			ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), ''), ISNULL(s.module, ''),
			ISNULL(s.svg_icon, ''), ISNULL(s.css_class, ''),
			ISNULL(s.caption, ''), ISNULL(s.helptext, ''),
			1, 1,
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_phrase$ s
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_phrase', @sys_owner, ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) AS orig_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_phrase t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND t.removed = 0
		);

		-- 2.C) Jazykové 'L' záznamy v meta_phrase pro druhý jazyk (@sec_lang)
		--      (Ukládá se čistě hodnota ze sloupců *_l bez přepisování primárním jazykem)
		IF @sec_lang <> ''
		BEGIN
			UPDATE t
			SET
				t.source_code = ISNULL(LTRIM(RTRIM(s.source_code)), ''),
				t.builtin_code = ISNULL(LTRIM(RTRIM(s.builtin_code)), ''),
				t.module = ISNULL(s.module, ''),
				t.svg_icon = ISNULL(s.svg_icon, ''),
				t.css_class = ISNULL(s.css_class, ''),
				t.caption = ISNULL(s.caption_l, ''),
				t.helptext = ISNULL(s.helptext_l, ''),
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_phrase t
			JOIN XLSX_phrase$ s
				ON dbo.f_generate_original('meta_phrase', @sys_owner, ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) = t.original
			WHERE t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			INSERT INTO meta_phrase (
				uuid, object_owner, original, record_type, approval_status, [language],
				import_origin,
				source_code, builtin_code, module,
				svg_icon, css_class,
				caption, helptext,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, x.orig_uuid, 'L', 'A', @sec_lang,
				@import_origin,
				ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), ''), ISNULL(s.module, ''),
				ISNULL(s.svg_icon, ''), ISNULL(s.css_class, ''),
				ISNULL(s.caption_l, ''),
				ISNULL(s.helptext_l, ''),
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM XLSX_phrase$ s
			CROSS APPLY (
				SELECT dbo.f_generate_original('meta_phrase', @sys_owner, ISNULL(LTRIM(RTRIM(s.source_code)), ''), ISNULL(LTRIM(RTRIM(s.builtin_code)), '')) AS orig_uuid
			) x
			WHERE NOT EXISTS (
				SELECT 1 FROM meta_phrase t
				WHERE t.original = x.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
				  AND t.removed = 0
			);
		END

		EXEC insert_request_message 'Záložka phrase byla úspěšně zpracována', 1, @intvalue = @cnt_a, @obj_type = 'meta_phrase', @obj_name = 'phrase';
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
		--      (Ukládá se čistě hodnota ze sloupců *_l bez přepisování primárním jazykem)
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
				t.caption = ISNULL(s.caption_l, ''),
				t.description = ISNULL(s.description_l, ''),
				t.helptext = ISNULL(s.helptext_l, ''),
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
				ISNULL(s.caption_l, ''),
				ISNULL(s.description_l, ''),
				ISNULL(s.helptext_l, ''),
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

	-- =========================================================================
	-- 4. Zpracování volitelné záložky: class (tabulka meta_class)
	-- =========================================================================
	IF OBJECT_ID('XLSX_class$') IS NOT NULL
	BEGIN
		SET @bad_code = NULL;

		-- Kontrola duplicitních class_name v rámci záložky class
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(class_name))
		FROM XLSX_class$
		GROUP BY LTRIM(RTRIM(class_name))
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní class_name na záložce class', 3, @obj_type = 'class', @obj_name = @bad_code;
			RETURN;
		END

		-- Očištění hodnot uzavřených <do stříšek> do pomocné tabulky #clean_class
		IF OBJECT_ID('tempdb..#clean_class') IS NOT NULL DROP TABLE #clean_class;

		SELECT
			LTRIM(RTRIM(ISNULL(s.class_name, ''))) AS class_name,
			ISNULL(NULLIF(LTRIM(RTRIM(s.storage_type)), ''), 'T') AS storage_type,
			LTRIM(RTRIM(ISNULL(s.storage_code, ''))) AS storage_code,
			LTRIM(RTRIM(ISNULL(s.ancestor_code, ''))) AS ancestor_code,
			LTRIM(RTRIM(ISNULL(s.sort_code, ''))) AS sort_code,
			v.iconname,
			ISNULL(TRY_CAST(v.is_final AS bit), 1) AS is_final,
			ISNULL(TRY_CAST(v.is_protected AS bit), 0) AS is_protected,
			ISNULL(TRY_CAST(v.inactive AS bit), 0) AS inactive,
			v.editor_note,
			v.caption,
			v.caption_plural,
			v.description,
			v.helptext,
			v.caption_l,
			v.caption_plural_l,
			v.description_l,
			v.helptext_l
		INTO #clean_class
		FROM XLSX_class$ s
		CROSS APPLY (
			SELECT
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.iconname, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.iconname, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.iconname)), 2, LEN(LTRIM(RTRIM(s.iconname))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.iconname, ''))) END AS iconname,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_final, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_final, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_final)), 2, LEN(LTRIM(RTRIM(s.is_final))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_final, ''))) END AS is_final,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_protected, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_protected, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_protected)), 2, LEN(LTRIM(RTRIM(s.is_protected))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_protected, ''))) END AS is_protected,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.inactive, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.inactive, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.inactive)), 2, LEN(LTRIM(RTRIM(s.inactive))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.inactive, ''))) END AS inactive,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.editor_note, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.editor_note, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.editor_note)), 2, LEN(LTRIM(RTRIM(s.editor_note))) - 2) ELSE ISNULL(s.editor_note, '') END AS editor_note,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption)), 2, LEN(LTRIM(RTRIM(s.caption))) - 2) ELSE ISNULL(s.caption, '') END AS caption,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption_plural, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption_plural, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption_plural)), 2, LEN(LTRIM(RTRIM(s.caption_plural))) - 2) ELSE ISNULL(s.caption_plural, '') END AS caption_plural,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.description, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.description, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.description)), 2, LEN(LTRIM(RTRIM(s.description))) - 2) ELSE ISNULL(s.description, '') END AS description,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.helptext, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.helptext, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.helptext)), 2, LEN(LTRIM(RTRIM(s.helptext))) - 2) ELSE ISNULL(s.helptext, '') END AS helptext,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption_l)), 2, LEN(LTRIM(RTRIM(s.caption_l))) - 2) ELSE ISNULL(s.caption_l, '') END AS caption_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption_plural_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption_plural_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption_plural_l)), 2, LEN(LTRIM(RTRIM(s.caption_plural_l))) - 2) ELSE ISNULL(s.caption_plural_l, '') END AS caption_plural_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.description_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.description_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.description_l)), 2, LEN(LTRIM(RTRIM(s.description_l))) - 2) ELSE ISNULL(s.description_l, '') END AS description_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.helptext_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.helptext_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.helptext_l)), 2, LEN(LTRIM(RTRIM(s.helptext_l))) - 2) ELSE ISNULL(s.helptext_l, '') END AS helptext_l
		) v;

		-- Kontrola referenční integrity storage_code proti meta_object
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.class_name + ' -> ' + s.storage_type + ':' + s.storage_code
		FROM #clean_class s
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object mo
			WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, s.storage_type, s.storage_code)
			  AND mo.object_owner = @sys_owner
			  AND mo.record_type = 'A'
			  AND mo.removed = 0
		);

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující úložný objekt (storage_code) na záložce class', 3, @obj_type = 'meta_class', @obj_name = @bad_code;
			RETURN;
		END

		-- 4.A) Zpracování hlavních záznamů ('A') v meta_class
		UPDATE t
		SET
			t.[language] = @lang,
			t.storage_object = x.calc_storage_uuid,
			t.ancestor_class = x.calc_ancestor_uuid,
			t.sort_code = s.sort_code,
			t.iconname = NULLIF(s.iconname, ''),
			t.is_final = s.is_final,
			t.is_protected = s.is_protected,
			t.inactive = s.inactive,
			t.editor_note = NULLIF(s.editor_note, ''),
			t.caption = NULLIF(s.caption, ''),
			t.caption_plural = NULLIF(s.caption_plural, ''),
			t.description = NULLIF(s.description, ''),
			t.helptext = NULLIF(s.helptext, ''),
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_class t
		JOIN #clean_class s
			ON dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.class_name, '') = t.original
		CROSS APPLY (
			SELECT
				dbo.f_generate_original('meta_object', @sys_owner, s.storage_type, s.storage_code) AS calc_storage_uuid,
				CASE WHEN s.ancestor_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.ancestor_code, '') ELSE NULL END AS calc_ancestor_uuid
		) x
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'A'
		  AND t.removed = 0;

		SET @cnt_a = @@ROWCOUNT;

		INSERT INTO meta_class (
			uuid, object_owner, original, record_type, approval_status, [language],
			inactive, import_origin,
			class_name, storage_object, ancestor_class, sort_code, iconname,
			is_final, is_protected,
			editor_note, caption, caption_plural, description, helptext,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.orig_uuid, @sys_owner, x.orig_uuid, 'A', 'A', @lang,
			s.inactive, @import_origin,
			s.class_name, x.calc_storage_uuid, x.calc_ancestor_uuid, s.sort_code, NULLIF(s.iconname, ''),
			s.is_final, s.is_protected,
			NULLIF(s.editor_note, ''), NULLIF(s.caption, ''), NULLIF(s.caption_plural, ''), NULLIF(s.description, ''), NULLIF(s.helptext, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM #clean_class s
		CROSS APPLY (
			SELECT
				dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.class_name, '') AS orig_uuid,
				dbo.f_generate_original('meta_object', @sys_owner, s.storage_type, s.storage_code) AS calc_storage_uuid,
				CASE WHEN s.ancestor_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.ancestor_code, '') ELSE NULL END AS calc_ancestor_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_class t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND t.removed = 0
		);

		SET @cnt_a = @cnt_a + @@ROWCOUNT;

		-- Kontrola referenční integrity ancestor_code proti meta_class
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.class_name + ' -> ' + s.ancestor_code
		FROM #clean_class s
		WHERE s.ancestor_code <> ''
		  AND NOT EXISTS (
			SELECT 1 FROM meta_class p
			WHERE p.original = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.ancestor_code, '')
			  AND p.object_owner = @sys_owner
			  AND p.record_type = 'A'
			  AND p.removed = 0
		  );

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující nadřízená třída (ancestor_code) na záložce class', 3, @obj_type = 'meta_class', @obj_name = @bad_code;
			RETURN;
		END

		-- Pokud je hodnota na třídě shodná s předkem (ancestor_class), uložíme NULL pro zachování dědičnosti
		UPDATE c
		SET
			c.iconname = CASE WHEN ISNULL(c.iconname, '') = ISNULL(anc.iconname, '') THEN NULL ELSE c.iconname END,
			c.caption = CASE WHEN ISNULL(c.caption, '') = ISNULL(anc.caption, '') THEN NULL ELSE c.caption END,
			c.caption_plural = CASE WHEN ISNULL(c.caption_plural, '') = ISNULL(anc.caption_plural, '') THEN NULL ELSE c.caption_plural END,
			c.description = CASE WHEN ISNULL(c.description, '') = ISNULL(anc.description, '') THEN NULL ELSE c.description END,
			c.helptext = CASE WHEN ISNULL(c.helptext, '') = ISNULL(anc.helptext, '') THEN NULL ELSE c.helptext END
		FROM meta_class c
		JOIN meta_class anc ON anc.original = c.ancestor_class AND anc.object_owner = @sys_owner AND anc.record_type = 'A' AND anc.removed = 0
		WHERE c.object_owner = @sys_owner
		  AND c.record_type = 'A'
		  AND c.removed = 0;

		-- 4.B) Symetrické 'L' záznamy v meta_class pro primární jazyk (@lang)
		UPDATE t
		SET
			t.storage_object = a.storage_object,
			t.ancestor_class = a.ancestor_class,
			t.sort_code = a.sort_code,
			t.iconname = a.iconname,
			t.is_final = a.is_final,
			t.is_protected = a.is_protected,
			t.inactive = a.inactive,
			t.caption = a.caption,
			t.caption_plural = a.caption_plural,
			t.description = a.description,
			t.helptext = a.helptext,
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_class t
		JOIN meta_class a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
		JOIN #clean_class s ON s.class_name = a.class_name
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'L'
		  AND t.[language] = @lang
		  AND t.removed = 0;

		INSERT INTO meta_class (
			uuid, object_owner, original, record_type, approval_status, [language],
			inactive, import_origin,
			class_name, storage_object, ancestor_class, sort_code, iconname,
			is_final, is_protected,
			caption, caption_plural, description, helptext,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
			a.inactive, @import_origin,
			a.class_name, a.storage_object, a.ancestor_class, a.sort_code, a.iconname,
			a.is_final, a.is_protected,
			a.caption, a.caption_plural, a.description, a.helptext,
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM meta_class a
		JOIN #clean_class s ON s.class_name = a.class_name
		WHERE a.object_owner = @sys_owner
		  AND a.record_type = 'A'
		  AND a.removed = 0
		  AND NOT EXISTS (
			SELECT 1 FROM meta_class t
			WHERE t.original = a.original
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND t.removed = 0
		  );

		-- 4.C) Jazykové 'L' záznamy v meta_class pro druhý jazyk (@sec_lang)
		--      (Ukládá se čistě hodnota ze sloupců *_l bez přepisování primárním jazykem)
		IF @sec_lang <> ''
		BEGIN
			UPDATE t
			SET
				t.storage_object = a.storage_object,
				t.ancestor_class = a.ancestor_class,
				t.sort_code = a.sort_code,
				t.iconname = a.iconname,
				t.is_final = a.is_final,
				t.is_protected = a.is_protected,
				t.inactive = a.inactive,
				t.caption = NULLIF(s.caption_l, ''),
				t.caption_plural = NULLIF(s.caption_plural_l, ''),
				t.description = NULLIF(s.description_l, ''),
				t.helptext = NULLIF(s.helptext_l, ''),
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_class t
			JOIN meta_class a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_class s ON s.class_name = a.class_name
			WHERE t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			INSERT INTO meta_class (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, import_origin,
				class_name, storage_object, ancestor_class, sort_code, iconname,
				is_final, is_protected,
				caption, caption_plural, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @sec_lang,
				a.inactive, @import_origin,
				a.class_name, a.storage_object, a.ancestor_class, a.sort_code, a.iconname,
				a.is_final, a.is_protected,
				NULLIF(s.caption_l, ''),
				NULLIF(s.caption_plural_l, ''),
				NULLIF(s.description_l, ''),
				NULLIF(s.helptext_l, ''),
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM meta_class a
			JOIN #clean_class s ON s.class_name = a.class_name
			WHERE a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_class t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
				  AND t.removed = 0
			  );

			-- Zachování dědičnosti u 'L' záznamu druhého jazyka při shodě s předkem
			UPDATE l
			SET
				l.caption = CASE WHEN ISNULL(l.caption, '') = ISNULL(anc_l.caption, '') THEN NULL ELSE l.caption END,
				l.caption_plural = CASE WHEN ISNULL(l.caption_plural, '') = ISNULL(anc_l.caption_plural, '') THEN NULL ELSE l.caption_plural END,
				l.description = CASE WHEN ISNULL(l.description, '') = ISNULL(anc_l.description, '') THEN NULL ELSE l.description END,
				l.helptext = CASE WHEN ISNULL(l.helptext, '') = ISNULL(anc_l.helptext, '') THEN NULL ELSE l.helptext END
			FROM meta_class l
			JOIN meta_class anc_l ON anc_l.original = l.ancestor_class AND anc_l.object_owner = @sys_owner AND anc_l.record_type = 'L' AND anc_l.[language] = @sec_lang AND anc_l.removed = 0
			WHERE l.object_owner = @sys_owner
			  AND l.record_type = 'L'
			  AND l.[language] = @sec_lang
			  AND l.removed = 0;
		END

		DROP TABLE #clean_class;
		EXEC insert_request_message 'Záložka class byla úspěšně zpracována', 1, @intvalue = @cnt_a, @obj_type = 'meta_class', @obj_name = 'class';
	END

	-- =========================================================================
	-- 5. Zpracování volitelné záložky: column (tabulka meta_column)
	-- =========================================================================
	IF OBJECT_ID('XLSX_column$') IS NOT NULL
	BEGIN
		SET @bad_code = NULL;

		-- Kontrola duplicitních kombinací (class_name, column_name) na záložce column
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(class_name)) + '.' + LTRIM(RTRIM(column_name))
		FROM XLSX_column$
		GROUP BY LTRIM(RTRIM(class_name)), LTRIM(RTRIM(column_name))
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní kombinace (class_name, column_name) na záložce column', 3, @obj_type = 'column', @obj_name = @bad_code;
			RETURN;
		END

		-- Očištění všech hodnot od případných stříšek <...> do pomocné tabulky #clean_column
		IF OBJECT_ID('tempdb..#clean_column') IS NOT NULL DROP TABLE #clean_column;

		SELECT
			LTRIM(RTRIM(ISNULL(s.class_name, ''))) AS class_name,
			LTRIM(RTRIM(ISNULL(s.column_name, ''))) AS column_name,
			ISNULL(TRY_CAST(v.parent_order AS int), 0) AS parent_order,
			NULLIF(v.sort_code, '') AS sort_code,
			TRY_CAST(NULLIF(v.list_order, '') AS int) AS list_order,
			NULLIF(v.input_type, '') AS input_type,
			NULLIF(v.input_width, '') AS input_width,
			TRY_CAST(NULLIF(v.input_rows, '') AS int) AS input_rows,
			TRY_CAST(NULLIF(v.max_length, '') AS int) AS max_length,
			NULLIF(v.css_class, '') AS css_class,
			TRY_CAST(NULLIF(v.translate, '') AS bit) AS translate,
			TRY_CAST(NULLIF(v.history, '') AS bit) AS history,
			TRY_CAST(NULLIF(v.is_html, '') AS bit) AS is_html,
			TRY_CAST(NULLIF(v.is_mandatory, '') AS bit) AS is_mandatory,
			TRY_CAST(NULLIF(v.is_url, '') AS bit) AS is_url,
			TRY_CAST(NULLIF(v.is_computed, '') AS bit) AS is_computed,
			TRY_CAST(NULLIF(v.show_empty, '') AS bit) AS show_empty,
			TRY_CAST(NULLIF(v.hidden, '') AS bit) AS hidden,
			TRY_CAST(NULLIF(v.customizable, '') AS bit) AS customizable,
			v.ancestor_column,
			v.referenced_codetable,
			v.referenced_class_code,
			ISNULL(TRY_CAST(v.is_final AS bit), 1) AS is_final,
			ISNULL(TRY_CAST(v.is_protected AS bit), 0) AS is_protected,
			ISNULL(TRY_CAST(v.inactive AS bit), 0) AS inactive,
			NULLIF(v.editor_note, '') AS editor_note,
			NULLIF(v.caption, '') AS caption,
			NULLIF(v.caption_plural, '') AS caption_plural,
			NULLIF(v.description, '') AS description,
			NULLIF(v.label, '') AS label,
			NULLIF(v.header, '') AS header,
			NULLIF(v.helptext, '') AS helptext,
			NULLIF(v.placeholder, '') AS placeholder,
			NULLIF(v.caption_l, '') AS caption_l,
			NULLIF(v.caption_plural_l, '') AS caption_plural_l,
			NULLIF(v.description_l, '') AS description_l,
			NULLIF(v.label_l, '') AS label_l,
			NULLIF(v.header_l, '') AS header_l,
			NULLIF(v.helptext_l, '') AS helptext_l,
			NULLIF(v.placeholder_l, '') AS placeholder_l
		INTO #clean_column
		FROM XLSX_column$ s
		CROSS APPLY (
			SELECT
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.parent_order, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.parent_order, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.parent_order)), 2, LEN(LTRIM(RTRIM(s.parent_order))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.parent_order, ''))) END AS parent_order,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.sort_code, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.sort_code, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.sort_code)), 2, LEN(LTRIM(RTRIM(s.sort_code))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.sort_code, ''))) END AS sort_code,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.list_order, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.list_order, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.list_order)), 2, LEN(LTRIM(RTRIM(s.list_order))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.list_order, ''))) END AS list_order,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.input_type, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.input_type, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.input_type)), 2, LEN(LTRIM(RTRIM(s.input_type))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.input_type, ''))) END AS input_type,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.input_width, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.input_width, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.input_width)), 2, LEN(LTRIM(RTRIM(s.input_width))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.input_width, ''))) END AS input_width,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.input_rows, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.input_rows, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.input_rows)), 2, LEN(LTRIM(RTRIM(s.input_rows))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.input_rows, ''))) END AS input_rows,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.max_length, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.max_length, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.max_length)), 2, LEN(LTRIM(RTRIM(s.max_length))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.max_length, ''))) END AS max_length,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.css_class, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.css_class, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.css_class)), 2, LEN(LTRIM(RTRIM(s.css_class))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.css_class, ''))) END AS css_class,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.translate, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.translate, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.translate)), 2, LEN(LTRIM(RTRIM(s.translate))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.translate, ''))) END AS translate,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.history, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.history, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.history)), 2, LEN(LTRIM(RTRIM(s.history))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.history, ''))) END AS history,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_html, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_html, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_html)), 2, LEN(LTRIM(RTRIM(s.is_html))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_html, ''))) END AS is_html,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_mandatory, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_mandatory, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_mandatory)), 2, LEN(LTRIM(RTRIM(s.is_mandatory))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_mandatory, ''))) END AS is_mandatory,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_url, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_url, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_url)), 2, LEN(LTRIM(RTRIM(s.is_url))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_url, ''))) END AS is_url,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_computed, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_computed, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_computed)), 2, LEN(LTRIM(RTRIM(s.is_computed))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_computed, ''))) END AS is_computed,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.show_empty, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.show_empty, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.show_empty)), 2, LEN(LTRIM(RTRIM(s.show_empty))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.show_empty, ''))) END AS show_empty,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.hidden, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.hidden, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.hidden)), 2, LEN(LTRIM(RTRIM(s.hidden))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.hidden, ''))) END AS hidden,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.customizable, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.customizable, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.customizable)), 2, LEN(LTRIM(RTRIM(s.customizable))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.customizable, ''))) END AS customizable,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.ancestor_column, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.ancestor_column, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.ancestor_column)), 2, LEN(LTRIM(RTRIM(s.ancestor_column))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.ancestor_column, ''))) END AS ancestor_column,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.referenced_codetable, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.referenced_codetable, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.referenced_codetable)), 2, LEN(LTRIM(RTRIM(s.referenced_codetable))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.referenced_codetable, ''))) END AS referenced_codetable,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.referenced_class_code, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.referenced_class_code, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.referenced_class_code)), 2, LEN(LTRIM(RTRIM(s.referenced_class_code))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.referenced_class_code, ''))) END AS referenced_class_code,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_final, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_final, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_final)), 2, LEN(LTRIM(RTRIM(s.is_final))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_final, ''))) END AS is_final,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.is_protected, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.is_protected, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.is_protected)), 2, LEN(LTRIM(RTRIM(s.is_protected))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.is_protected, ''))) END AS is_protected,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.inactive, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.inactive, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.inactive)), 2, LEN(LTRIM(RTRIM(s.inactive))) - 2) ELSE LTRIM(RTRIM(ISNULL(s.inactive, ''))) END AS inactive,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.editor_note, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.editor_note, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.editor_note)), 2, LEN(LTRIM(RTRIM(s.editor_note))) - 2) ELSE ISNULL(s.editor_note, '') END AS editor_note,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption)), 2, LEN(LTRIM(RTRIM(s.caption))) - 2) ELSE ISNULL(s.caption, '') END AS caption,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption_plural, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption_plural, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption_plural)), 2, LEN(LTRIM(RTRIM(s.caption_plural))) - 2) ELSE ISNULL(s.caption_plural, '') END AS caption_plural,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.description, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.description, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.description)), 2, LEN(LTRIM(RTRIM(s.description))) - 2) ELSE ISNULL(s.description, '') END AS description,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.label, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.label, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.label)), 2, LEN(LTRIM(RTRIM(s.label))) - 2) ELSE ISNULL(s.label, '') END AS label,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.header, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.header, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.header)), 2, LEN(LTRIM(RTRIM(s.header))) - 2) ELSE ISNULL(s.header, '') END AS header,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.helptext, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.helptext, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.helptext)), 2, LEN(LTRIM(RTRIM(s.helptext))) - 2) ELSE ISNULL(s.helptext, '') END AS helptext,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.placeholder, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.placeholder, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.placeholder)), 2, LEN(LTRIM(RTRIM(s.placeholder))) - 2) ELSE ISNULL(s.placeholder, '') END AS placeholder,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption_l)), 2, LEN(LTRIM(RTRIM(s.caption_l))) - 2) ELSE ISNULL(s.caption_l, '') END AS caption_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.caption_plural_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.caption_plural_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.caption_plural_l)), 2, LEN(LTRIM(RTRIM(s.caption_plural_l))) - 2) ELSE ISNULL(s.caption_plural_l, '') END AS caption_plural_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.description_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.description_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.description_l)), 2, LEN(LTRIM(RTRIM(s.description_l))) - 2) ELSE ISNULL(s.description_l, '') END AS description_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.label_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.label_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.label_l)), 2, LEN(LTRIM(RTRIM(s.label_l))) - 2) ELSE ISNULL(s.label_l, '') END AS label_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.header_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.header_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.header_l)), 2, LEN(LTRIM(RTRIM(s.header_l))) - 2) ELSE ISNULL(s.header_l, '') END AS header_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.helptext_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.helptext_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.helptext_l)), 2, LEN(LTRIM(RTRIM(s.helptext_l))) - 2) ELSE ISNULL(s.helptext_l, '') END AS helptext_l,
				CASE WHEN LEFT(LTRIM(RTRIM(ISNULL(s.placeholder_l, ''))), 1) = '<' AND RIGHT(LTRIM(RTRIM(ISNULL(s.placeholder_l, ''))), 1) = '>' THEN SUBSTRING(LTRIM(RTRIM(s.placeholder_l)), 2, LEN(LTRIM(RTRIM(s.placeholder_l))) - 2) ELSE ISNULL(s.placeholder_l, '') END AS placeholder_l
		) v;

		-- Kontrola referenční integrity class_name na záložce column proti meta_class
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.class_name + '.' + s.column_name
		FROM #clean_column s
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_class mc
			WHERE mc.original = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.class_name, '')
			  AND mc.object_owner = @sys_owner
			  AND mc.record_type = 'A'
			  AND mc.removed = 0
		);

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Neexistující logická třída (class_name) na záložce column', 3, @obj_type = 'meta_column', @obj_name = @bad_code;
			RETURN;
		END

		DECLARE @global_cls_uuid uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'sys_global_columns', '');

		-- 5.A) Zpracování hlavních záznamů ('A') v meta_column
		UPDATE t
		SET
			t.[language] = @lang,
			t.parent_order = s.parent_order,
			t.sort_code = s.sort_code,
			t.list_order = s.list_order,
			t.input_type = s.input_type,
			t.input_width = s.input_width,
			t.input_rows = s.input_rows,
			t.max_length = s.max_length,
			t.css_class = s.css_class,
			t.translate = s.translate,
			t.history = s.history,
			t.is_html = s.is_html,
			t.is_mandatory = s.is_mandatory,
			t.is_url = s.is_url,
			t.is_computed = s.is_computed,
			t.show_empty = s.show_empty,
			t.hidden = s.hidden,
			t.customizable = s.customizable,
			t.ancestor = x.calc_ancestor_uuid,
			t.referenced_codetable = ISNULL(s.referenced_codetable, ''),
			t.referenced_class = x.calc_ref_class_uuid,
			t.is_final = s.is_final,
			t.is_protected = s.is_protected,
			t.inactive = s.inactive,
			t.editor_note = s.editor_note,
			t.caption = s.caption,
			t.caption_plural = s.caption_plural,
			t.description = s.description,
			t.label = s.label,
			t.header = s.header,
			t.helptext = s.helptext,
			t.placeholder = s.placeholder,
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_column t
		JOIN #clean_column s
			ON dbo.f_generate_original(
				'meta_column',
				@sys_owner,
				CAST(dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.class_name, '') AS varchar(36)),
				s.column_name
			) = t.original
		CROSS APPLY (
			SELECT
				CASE
					WHEN s.class_name <> 'sys_global_columns' AND s.ancestor_column <> ''
					THEN dbo.f_generate_original('meta_column', @sys_owner, CAST(@global_cls_uuid AS varchar(36)), s.ancestor_column)
					ELSE NULL
				END AS calc_ancestor_uuid,
				CASE
					WHEN s.referenced_class_code <> ''
					THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.referenced_class_code, '')
					ELSE NULL
				END AS calc_ref_class_uuid
		) x
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'A'
		  AND t.removed = 0;

		SET @cnt_a = @@ROWCOUNT;

		INSERT INTO meta_column (
			uuid, object_owner, original, record_type, approval_status, [language],
			inactive, import_origin,
			parent_class, parent_order, sort_code, column_name, list_order,
			caption, caption_plural, description, label, header, helptext, placeholder, editor_note,
			input_type, input_width, input_rows, max_length, css_class,
			translate, history, is_html, is_mandatory, is_url, is_computed,
			show_empty, hidden, customizable,
			ancestor, referenced_codetable, referenced_class,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.orig_uuid, @sys_owner, x.orig_uuid, 'A', 'A', @lang,
			s.inactive, @import_origin,
			x.calc_parent_class, s.parent_order, s.sort_code, s.column_name, s.list_order,
			s.caption, s.caption_plural, s.description, s.label, s.header, s.helptext, s.placeholder, s.editor_note,
			s.input_type, s.input_width, s.input_rows, s.max_length, s.css_class,
			s.translate, s.history, s.is_html, s.is_mandatory, s.is_url, s.is_computed,
			s.show_empty, s.hidden, s.customizable,
			x.calc_ancestor_uuid, ISNULL(s.referenced_codetable, ''), x.calc_ref_class_uuid,
			s.is_final, s.is_protected,
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM #clean_column s
		CROSS APPLY (
			SELECT
				dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.class_name, '') AS calc_parent_class
		) p
		CROSS APPLY (
			SELECT
				p.calc_parent_class,
				dbo.f_generate_original('meta_column', @sys_owner, CAST(p.calc_parent_class AS varchar(36)), s.column_name) AS orig_uuid,
				CASE
					WHEN s.class_name <> 'sys_global_columns' AND s.ancestor_column <> ''
					THEN dbo.f_generate_original('meta_column', @sys_owner, CAST(@global_cls_uuid AS varchar(36)), s.ancestor_column)
					ELSE NULL
				END AS calc_ancestor_uuid,
				CASE
					WHEN s.referenced_class_code <> ''
					THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.referenced_class_code, '')
					ELSE NULL
				END AS calc_ref_class_uuid
		) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_column t
			WHERE t.original = x.orig_uuid
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND t.removed = 0
		);

		SET @cnt_a = @cnt_a + @@ROWCOUNT;

		-- Pokud má sloupec předka (ancestor v sys_global_columns) a jeho hodnota je shodná s předkem,
		-- uložíme do sloupce NULL (u referenced_codetable prázdný string ''), aby fungovalo dědění!
		UPDATE mc
		SET
			mc.list_order = CASE WHEN mc.list_order = gc.list_order THEN NULL ELSE mc.list_order END,
			mc.caption = CASE WHEN ISNULL(mc.caption, '') = ISNULL(gc.caption, '') THEN NULL ELSE mc.caption END,
			mc.caption_plural = CASE WHEN ISNULL(mc.caption_plural, '') = ISNULL(gc.caption_plural, '') THEN NULL ELSE mc.caption_plural END,
			mc.description = CASE WHEN ISNULL(mc.description, '') = ISNULL(gc.description, '') THEN NULL ELSE mc.description END,
			mc.label = CASE WHEN ISNULL(mc.label, '') = ISNULL(gc.label, '') THEN NULL ELSE mc.label END,
			mc.header = CASE WHEN ISNULL(mc.header, '') = ISNULL(gc.header, '') THEN NULL ELSE mc.header END,
			mc.helptext = CASE WHEN ISNULL(mc.helptext, '') = ISNULL(gc.helptext, '') THEN NULL ELSE mc.helptext END,
			mc.placeholder = CASE WHEN ISNULL(mc.placeholder, '') = ISNULL(gc.placeholder, '') THEN NULL ELSE mc.placeholder END,
			mc.input_type = CASE WHEN ISNULL(mc.input_type, '') = ISNULL(gc.input_type, '') THEN NULL ELSE mc.input_type END,
			mc.input_width = CASE WHEN ISNULL(mc.input_width, '') = ISNULL(gc.input_width, '') THEN NULL ELSE mc.input_width END,
			mc.input_rows = CASE WHEN mc.input_rows = gc.input_rows THEN NULL ELSE mc.input_rows END,
			mc.max_length = CASE WHEN mc.max_length = gc.max_length THEN NULL ELSE mc.max_length END,
			mc.css_class = CASE WHEN ISNULL(mc.css_class, '') = ISNULL(gc.css_class, '') THEN NULL ELSE mc.css_class END,
			mc.translate = CASE WHEN mc.translate = gc.translate THEN NULL ELSE mc.translate END,
			mc.history = CASE WHEN mc.history = gc.history THEN NULL ELSE mc.history END,
			mc.is_html = CASE WHEN mc.is_html = gc.is_html THEN NULL ELSE mc.is_html END,
			mc.is_mandatory = CASE WHEN mc.is_mandatory = gc.is_mandatory THEN NULL ELSE mc.is_mandatory END,
			mc.is_url = CASE WHEN mc.is_url = gc.is_url THEN NULL ELSE mc.is_url END,
			mc.is_computed = CASE WHEN mc.is_computed = gc.is_computed THEN NULL ELSE mc.is_computed END,
			mc.show_empty = CASE WHEN mc.show_empty = gc.show_empty THEN NULL ELSE mc.show_empty END,
			mc.hidden = CASE WHEN mc.hidden = gc.hidden THEN NULL ELSE mc.hidden END,
			mc.customizable = CASE WHEN mc.customizable = gc.customizable THEN NULL ELSE mc.customizable END,
			mc.referenced_codetable = CASE WHEN ISNULL(mc.referenced_codetable, '') = ISNULL(gc.referenced_codetable, '') THEN '' ELSE ISNULL(mc.referenced_codetable, '') END,
			mc.referenced_class = CASE WHEN mc.referenced_class = gc.referenced_class THEN NULL ELSE mc.referenced_class END
		FROM meta_column mc
		JOIN meta_column gc
			ON gc.original = mc.ancestor
			AND gc.object_owner = @sys_owner
			AND gc.record_type = 'A'
			AND gc.removed = 0
		WHERE mc.object_owner = @sys_owner
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
		  AND mc.parent_class <> @global_cls_uuid;

		-- 5.B) Symetrické 'L' záznamy v meta_column pro primární jazyk (@lang)
		UPDATE t
		SET
			t.parent_order = a.parent_order,
			t.sort_code = a.sort_code,
			t.list_order = a.list_order,
			t.caption = a.caption,
			t.caption_plural = a.caption_plural,
			t.description = a.description,
			t.label = a.label,
			t.header = a.header,
			t.helptext = a.helptext,
			t.placeholder = a.placeholder,
			t.input_type = a.input_type,
			t.input_width = a.input_width,
			t.input_rows = a.input_rows,
			t.max_length = a.max_length,
			t.css_class = a.css_class,
			t.translate = a.translate,
			t.history = a.history,
			t.is_html = a.is_html,
			t.is_mandatory = a.is_mandatory,
			t.is_url = a.is_url,
			t.is_computed = a.is_computed,
			t.show_empty = a.show_empty,
			t.hidden = a.hidden,
			t.customizable = a.customizable,
			t.ancestor = a.ancestor,
			t.referenced_codetable = a.referenced_codetable,
			t.referenced_class = a.referenced_class,
			t.is_final = a.is_final,
			t.is_protected = a.is_protected,
			t.inactive = a.inactive,
			t.import_origin = ISNULL(@import_origin, t.import_origin),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_column t
		JOIN meta_column a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
		JOIN meta_class mc ON mc.original = a.parent_class AND mc.object_owner = @sys_owner AND mc.record_type = 'A' AND mc.removed = 0
		JOIN #clean_column s ON s.class_name = mc.class_name AND s.column_name = a.column_name
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'L'
		  AND t.[language] = @lang
		  AND t.removed = 0;

		INSERT INTO meta_column (
			uuid, object_owner, original, record_type, approval_status, [language],
			inactive, import_origin,
			parent_class, parent_order, sort_code, column_name, list_order,
			caption, caption_plural, description, label, header, helptext, placeholder,
			input_type, input_width, input_rows, max_length, css_class,
			translate, history, is_html, is_mandatory, is_url, is_computed,
			show_empty, hidden, customizable,
			ancestor, referenced_codetable, referenced_class,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
			a.inactive, @import_origin,
			a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
			a.caption, a.caption_plural, a.description, a.label, a.header, a.helptext, a.placeholder,
			a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
			a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
			a.show_empty, a.hidden, a.customizable,
			a.ancestor, a.referenced_codetable, a.referenced_class,
			a.is_final, a.is_protected,
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM meta_column a
		JOIN meta_class mc ON mc.original = a.parent_class AND mc.object_owner = @sys_owner AND mc.record_type = 'A' AND mc.removed = 0
		JOIN #clean_column s ON s.class_name = mc.class_name AND s.column_name = a.column_name
		WHERE a.object_owner = @sys_owner
		  AND a.record_type = 'A'
		  AND a.removed = 0
		  AND NOT EXISTS (
			SELECT 1 FROM meta_column t
			WHERE t.original = a.original
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND t.removed = 0
		  );

		-- 5.C) Jazykové 'L' záznamy v meta_column pro druhý jazyk (@sec_lang)
		--      (Ukládá se čistě hodnota ze sloupců *_l bez přepisování primárním jazykem)
		IF @sec_lang <> ''
		BEGIN
			UPDATE t
			SET
				t.parent_order = a.parent_order,
				t.sort_code = a.sort_code,
				t.list_order = a.list_order,
				t.caption = s.caption_l,
				t.caption_plural = s.caption_plural_l,
				t.description = s.description_l,
				t.label = s.label_l,
				t.header = s.header_l,
				t.helptext = s.helptext_l,
				t.placeholder = s.placeholder_l,
				t.input_type = a.input_type,
				t.input_width = a.input_width,
				t.input_rows = a.input_rows,
				t.max_length = a.max_length,
				t.css_class = a.css_class,
				t.translate = a.translate,
				t.history = a.history,
				t.is_html = a.is_html,
				t.is_mandatory = a.is_mandatory,
				t.is_url = a.is_url,
				t.is_computed = a.is_computed,
				t.show_empty = a.show_empty,
				t.hidden = a.hidden,
				t.customizable = a.customizable,
				t.ancestor = a.ancestor,
				t.referenced_codetable = a.referenced_codetable,
				t.referenced_class = a.referenced_class,
				t.is_final = a.is_final,
				t.is_protected = a.is_protected,
				t.inactive = a.inactive,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_column t
			JOIN meta_column a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN meta_class mc ON mc.original = a.parent_class AND mc.object_owner = @sys_owner AND mc.record_type = 'A' AND mc.removed = 0
			JOIN #clean_column s ON s.class_name = mc.class_name AND s.column_name = a.column_name
			WHERE t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			INSERT INTO meta_column (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, import_origin,
				parent_class, parent_order, sort_code, column_name, list_order,
				caption, caption_plural, description, label, header, helptext, placeholder,
				input_type, input_width, input_rows, max_length, css_class,
				translate, history, is_html, is_mandatory, is_url, is_computed,
				show_empty, hidden, customizable,
				ancestor, referenced_codetable, referenced_class,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @sec_lang,
				a.inactive, @import_origin,
				a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
				s.caption_l,
				s.caption_plural_l,
				s.description_l,
				s.label_l,
				s.header_l,
				s.helptext_l,
				s.placeholder_l,
				a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
				a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
				a.show_empty, a.hidden, a.customizable,
				a.ancestor, a.referenced_codetable, a.referenced_class,
				a.is_final, a.is_protected,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM meta_column a
			JOIN meta_class mc ON mc.original = a.parent_class AND mc.object_owner = @sys_owner AND mc.record_type = 'A' AND mc.removed = 0
			JOIN #clean_column s ON s.class_name = mc.class_name AND s.column_name = a.column_name
			WHERE a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_column t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
				  AND t.removed = 0
			  );

			-- Zachování dědičnosti u 'L' záznamu druhého jazyka v meta_column při shodě s předkem
			UPDATE l
			SET
				l.caption = CASE WHEN ISNULL(l.caption, '') = ISNULL(gc_l.caption, '') THEN NULL ELSE l.caption END,
				l.caption_plural = CASE WHEN ISNULL(l.caption_plural, '') = ISNULL(gc_l.caption_plural, '') THEN NULL ELSE l.caption_plural END,
				l.description = CASE WHEN ISNULL(l.description, '') = ISNULL(gc_l.description, '') THEN NULL ELSE l.description END,
				l.label = CASE WHEN ISNULL(l.label, '') = ISNULL(gc_l.label, '') THEN NULL ELSE l.label END,
				l.header = CASE WHEN ISNULL(l.header, '') = ISNULL(gc_l.header, '') THEN NULL ELSE l.header END,
				l.helptext = CASE WHEN ISNULL(l.helptext, '') = ISNULL(gc_l.helptext, '') THEN NULL ELSE l.helptext END,
				l.placeholder = CASE WHEN ISNULL(l.placeholder, '') = ISNULL(gc_l.placeholder, '') THEN NULL ELSE l.placeholder END
			FROM meta_column l
			JOIN meta_column gc_l
				ON gc_l.original = l.ancestor
				AND gc_l.object_owner = @sys_owner
				AND gc_l.record_type = 'L'
				AND gc_l.[language] = @sec_lang
				AND gc_l.removed = 0
			WHERE l.object_owner = @sys_owner
			  AND l.record_type = 'L'
			  AND l.[language] = @sec_lang
			  AND l.removed = 0
			  AND l.parent_class <> @global_cls_uuid;
		END

		DROP TABLE #clean_column;
		EXEC insert_request_message 'Záložka column byla úspěšně zpracována', 1, @intvalue = @cnt_a, @obj_type = 'meta_column', @obj_name = 'column';
	END
END
GO