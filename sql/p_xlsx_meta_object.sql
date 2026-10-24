/* =============================================================================
 * Verze: 2026-10-24 23:45
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
 * - Využívá funkci dbo.f_xlsx_clean pro odstranění stříšek <...> u zděděných hodnot.
 * - Zapisuje průběžné a chybové zprávy přes proceduru insert_request_message.
 *
 * Architektura dvou režimů (Jádro vs. Překlady), Delta kontroly, dědičnosti (<do stříšek>), svg_icon a removed:
 * - Upravuje výhradně systémové záznamy (object_owner = 0x00).
 * - Sloupce svg_icon se z Excelu vůbec neimportují ani neaktualizují (jejich nastavení
 *   v tabulkách meta_phrase, meta_menu a meta_class zůstává nedotčené a řeší se výhradně
 *   idempotentními databázovými skripty).
 * - DELTA KONTROLA ZMĚN (EXCEPT):
 *   Všechny příkazy UPDATE nad existujícími 'A' i 'L' záznamy obsahují podmínku
 *   EXISTS (SELECT ... EXCEPT SELECT ...), takže se dotknou výhradně těch řádků,
 *   kde skutečně došlo ke změně dat. U nezměněných záznamů zůstává původní
 *   date_modified a who_modified. Normalizace zděděných hodnot na NULL probíhá
 *   přímo v #clean_class a #clean_column ještě před porovnáním s databází.
 * - REŽIM 1: Import jádra a základního jazyka (když second_language = ''):
 *   Zapisuje hlavní 'A' záznamy a symetrické 'L' záznamy pro základní jazyk (@lang).
 *   Pokud je záznam v DB v koši (removed = 1) a v Excelu má removed = 0 (a platné
 *   vazby), obnoví jej zpět na removed = 0.
 * - REŽIM 2: Import překladů druhého jazyka (když second_language <> ''):
 *   Nijak nemodifikuje věcné atributy 'A' záznamů ani primární jazyk (@lang)! Zpracovává
 *   'L' záznamy druhého jazyka (@sec_lang) ze sloupců s příponou *_l (a při skutečné
 *   změně překladu aktualizuje auditní stopu date_modified/who_modified na 'A' záznamu).
 *
 * Změny:
 * - 2026-10-24 23:45: Doplněna podpora sloupce days_in_trash na záložce class.
 *   Sjednocena kontrola platnosti třídy (class_valid) na záložce column (ověření
 *   platnosti třídy v meta_class i jejího storage_object v meta_object).
 *   Doplněna podpora obnovy dříve zrušených záznamů z koše (removed: 1 -> 0).
 * - 2026-10-23 15:35: Doplněna Delta kontrola změn pomocí operátoru EXCEPT do všech
 *   UPDATE dotazů (zamezení přepisu date_modified a who_modified u nezměněných řádků).
 *   Přesunuta normalizace zděděných hodnot (NULL při shodě s předkem) přímo do
 *   dočasných tabulek #clean_class a #clean_column před samotný UPDATE/INSERT.
 * - 2026-10-21 15:40: Vyřazeno čtení a přepisování sloupce svg_icon ze záložek
 *   phrase, menu a class (hodnoty svg_icon v DB zůstávají při importu z Excelu nedotčeny).
 * - 2026-10-21 14:25: Opakující se výrazy pro odstranění stříšek <...> nahrazeny
 *   funkcí dbo.f_xlsx_clean.
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
	DECLARE @is_trans_mode bit = 0;                                       -- 1 = Režim překladu (@sec_lang <> ''), 0 = Režim jádra
	DECLARE @import_origin varchar(255) = NULL;                           -- Původ importu (měkký audit)
	DECLARE @cnt_a int = 0;                                               -- Počitadlo změněných/vložených 'A' záznamů
	DECLARE @cnt_l int = 0;                                               -- Počitadlo změněných/vložených 'L' záznamů
	DECLARE @cnt_rem int = 0;                                             -- Počitadlo zreplikovaných odstranění (removed=1)
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

	-- Kontrola platnosti druhého jazyka a nastavení režimu importu
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
	IF OBJECT_ID('XLSX_page$') IS NOT NULL
	BEGIN
		-- Doplnění sloupce removed se standardní hodnotou 0, pokud pochází ze staršího Excelu
		IF COL_LENGTH('XLSX_page$', 'removed') IS NULL
			ALTER TABLE XLSX_page$ ADD removed bit NOT NULL DEFAULT 0;

		-- Zákaz bezejmenného builtin_code = '' na záložce page
		IF EXISTS (SELECT 1 FROM XLSX_page$ WHERE LTRIM(RTRIM(ISNULL(builtin_code, ''))) = '')
		BEGIN
			EXEC insert_request_message 'Záložka page nesmí obsahovat prázdný builtin_code (pro globální fráze použijte global_phrase)', 3, @obj_type = 'page', @obj_name = '(prázdný builtin_code)';
			RETURN;
		END

		-- Kontrola duplicitních builtin_code v rámci záložky page
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(builtin_code))
		FROM XLSX_page$
		GROUP BY LTRIM(RTRIM(builtin_code))
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní builtin_code na záložce page', 3, @obj_type = 'page', @obj_name = @bad_code;
			RETURN;
		END

		-- Očištění dat záložky page (u *_l sloupců se <zděděné hodnoty ve stříškách> považují za nepřeložené '')
		IF OBJECT_ID('tempdb..#clean_page') IS NOT NULL DROP TABLE #clean_page;

		SELECT
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

		-- Kontrola v režimu překladů: V Excelu je removed = 0, ale v databázi je hlavní 'A' záznam neplatný (removed = 1)
		IF @is_trans_mode = 1
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je objekt stránky neplatný (removed=1)', 'meta_object (P)', s.builtin_code
			FROM #clean_page s
			WHERE s.removed = 0
			  AND EXISTS (SELECT 1 FROM meta_object t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_object t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END

		IF @is_trans_mode = 0
		BEGIN
			-- 1.A) REŽIM JÁDRA: Replikace zrušení (v Excelu je removed = 1 a v DB je objekt platný removed = 0)
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN #clean_page s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND s.builtin_code <> 'global_phrase'
			  AND t.object_owner = @sys_owner
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění objektů (removed=1) na záložce page', 1, @intvalue = @cnt_rem, @obj_type = 'meta_object (P)', @obj_name = 'page';

			-- 1.B) REŽIM JÁDRA: Delta UPDATE 'A' záznamů (včetně případné obnovy z koše removed: 1 -> 0)
			UPDATE t
			SET
				t.[language] = @lang,
				t.removed = 0,
				t.system_role = s.system_role,
				t.module = s.module,
				t.inactive = s.inactive,
				t.editor_note = s.editor_note,
				t.caption = s.caption,
				t.description = s.description,
				t.helptext = s.helptext,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN #clean_page s ON s.orig_uuid = t.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND EXISTS (
				SELECT t.[language], t.removed, t.system_role, t.module, t.inactive, t.editor_note, t.caption, t.description, t.helptext
				EXCEPT
				SELECT @lang, CAST(0 AS bit), s.system_role, s.module, s.inactive, s.editor_note, s.caption, s.description, s.helptext
			  );

			SET @cnt_a = @@ROWCOUNT;

			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				object_type, builtin_code, system_role, module,
				editor_note, caption, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				s.orig_uuid, @sys_owner, s.orig_uuid, 'A', 'A', @lang,
				s.inactive, 0, @import_origin,
				'P', s.builtin_code, s.system_role, s.module,
				s.editor_note, s.caption, s.description, s.helptext,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_page s
			WHERE s.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_object t
				WHERE t.original = s.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'A'
			  );

			SET @cnt_a = @cnt_a + @@ROWCOUNT;

			-- Symetrické 'L' záznamy pro primární jazyk (@lang) s Delta kontrolou (vč. obnovy z koše)
			UPDATE t
			SET
				t.removed = 0,
				t.system_role = s.system_role,
				t.module = s.module,
				t.inactive = s.inactive,
				t.caption = s.caption,
				t.description = s.description,
				t.helptext = s.helptext,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN #clean_page s ON s.orig_uuid = t.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND EXISTS (
				SELECT t.removed, t.system_role, t.module, t.inactive, t.caption, t.description, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), s.system_role, s.module, s.inactive, s.caption, s.description, s.helptext
			  );

			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				object_type, builtin_code, system_role, module,
				caption, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, s.orig_uuid, 'L', 'A', @lang,
				s.inactive, 0, @import_origin,
				'P', s.builtin_code, s.system_role, s.module,
				s.caption, s.description, s.helptext,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_page s
			WHERE s.removed = 0
			  AND EXISTS (
				SELECT 1 FROM meta_object a
				WHERE a.original = s.orig_uuid AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			  )
			  AND NOT EXISTS (
				SELECT 1 FROM meta_object t
				WHERE t.original = s.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @lang
			  );

			EXEC insert_request_message 'Záložka page (jádro - změněné/nové záznamy)', 1, @intvalue = @cnt_a, @obj_type = 'meta_object (P)', @obj_name = 'page';
		END
		ELSE
		BEGIN
			-- 1.C) REŽIM PŘEKLADŮ (@sec_lang): Upravují se výhradně změněné 'L' záznamy pro @sec_lang
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN #clean_page s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění překladů (removed=1) na záložce page', 1, @intvalue = @cnt_rem, @obj_type = 'meta_object (L)', @obj_name = @sec_lang;

			UPDATE t
			SET
				t.removed = 0,
				t.caption = s.caption_l,
				t.description = s.description_l,
				t.helptext = s.helptext_l,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN meta_object a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_page s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND EXISTS (
				SELECT t.removed, t.caption, t.description, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), s.caption_l, s.description_l, s.helptext_l
			  );

			SET @cnt_l = @@ROWCOUNT;

			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				object_type, builtin_code, system_role, module,
				caption, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @sec_lang,
				a.inactive, 0, @import_origin,
				'P', a.builtin_code, a.system_role, a.module,
				s.caption_l, s.description_l, s.helptext_l,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_page s
			JOIN meta_object a ON a.original = s.orig_uuid AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			WHERE s.removed = 0
			  AND (s.caption_l <> '' OR s.description_l <> '' OR s.helptext_l <> '')
			  AND NOT EXISTS (
				SELECT 1 FROM meta_object t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
			  );

			SET @cnt_l = @cnt_l + @@ROWCOUNT;

			-- Jednotná auditní stopa na 'A' záznamu, pokud byl překlad 'L' právě změněn
			UPDATE a
			SET a.date_modified = l.date_modified,
				a.who_modified = l.who_modified
			FROM meta_object a
			JOIN meta_object l ON l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @sec_lang
			WHERE a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND l.date_modified > a.date_modified;

			EXEC insert_request_message 'Záložka page (překlady - změněné/nové záznamy)', 1, @intvalue = @cnt_l, @obj_type = 'meta_object (L)', @obj_name = @sec_lang;
		END

		DROP TABLE #clean_page;
	END
	ELSE
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_page$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_page$';
		RETURN;
	END

	-- =========================================================================
	-- 2. Zpracování záložky: phrase (tabulka meta_phrase – bez čtení svg_icon)
	-- =========================================================================
	IF OBJECT_ID('XLSX_phrase$') IS NOT NULL
	BEGIN
		IF COL_LENGTH('XLSX_phrase$', 'inactive') IS NULL
			ALTER TABLE XLSX_phrase$ ADD inactive bit NOT NULL DEFAULT 0;

		IF COL_LENGTH('XLSX_phrase$', 'removed') IS NULL
			ALTER TABLE XLSX_phrase$ ADD removed bit NOT NULL DEFAULT 0;

		-- Striktní zákaz bezejmenného source_code = '' nebo prázdného builtin_code = ''
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = ISNULL(LTRIM(RTRIM(source_code)), '(NULL)') + '.' + ISNULL(LTRIM(RTRIM(builtin_code)), '(NULL)')
		FROM XLSX_phrase$
		WHERE LTRIM(RTRIM(ISNULL(source_code, ''))) = ''
		   OR LTRIM(RTRIM(ISNULL(builtin_code, ''))) = '';

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Fráze na záložce phrase nesmí mít prázdný source_code ani builtin_code (pro globální fráze použijte global_phrase)', 3, @obj_type = 'meta_phrase', @obj_name = @bad_code;
			RETURN;
		END

		-- Kontrola duplicitních kombinací (source_code, builtin_code) v rámci záložky phrase
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

		-- Očištění dat záložky phrase (bez svg_icon; hodnoty *_l v <stříškách> se považují za nepřeložené '')
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
			dbo.f_xlsx_clean(s.caption_l, 1) AS caption_l,
			dbo.f_xlsx_clean(s.helptext_l, 1) AS helptext_l
		INTO #clean_phrase
		FROM XLSX_phrase$ s;

		-- Kontrola referenční integrity source_code proti registrovaným objektům typu 'P' v meta_object (pro platné záznamy removed = 0)
		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = s.source_code + ' (' + s.builtin_code + ')'
		FROM #clean_phrase s
		WHERE s.removed = 0
		  AND NOT EXISTS (
			SELECT 1 FROM meta_object mo
			WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', s.source_code)
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

		-- Kontrola v režimu překladů: V Excelu je removed = 0, ale v databázi je hlavní 'A' záznam fráze neplatný (removed = 1)
		IF @is_trans_mode = 1
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je fráze neplatná (removed=1)', 'meta_phrase', s.source_code + '.' + s.builtin_code
			FROM #clean_phrase s
			WHERE s.removed = 0
			  AND EXISTS (SELECT 1 FROM meta_phrase t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_phrase t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END

		IF @is_trans_mode = 0
		BEGIN
			-- 2.A) REŽIM JÁDRA: Replikace zrušení fráze (removed = 1)
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_phrase t
			JOIN #clean_phrase s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND t.object_owner = @sys_owner
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění frází (removed=1) na záložce phrase', 1, @intvalue = @cnt_rem, @obj_type = 'meta_phrase', @obj_name = 'phrase';

			-- 2.B) REŽIM JÁDRA: Delta UPDATE hlavních záznamů ('A') v meta_phrase (vč. obnovy z koše, svg_icon v DB zůstává nedotčeno!)
			UPDATE t
			SET
				t.[language] = @lang,
				t.removed = 0,
				t.source_code = s.source_code,
				t.builtin_code = s.builtin_code,
				t.module = s.module,
				t.css_class = s.css_class,
				t.inactive = s.inactive,
				t.editor_note = s.editor_note,
				t.caption = s.caption,
				t.helptext = s.helptext,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_phrase t
			JOIN #clean_phrase s ON s.orig_uuid = t.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND EXISTS (
				SELECT t.[language], t.removed, t.source_code, t.builtin_code, t.module, t.css_class, t.inactive, t.editor_note, t.caption, t.helptext
				EXCEPT
				SELECT @lang, CAST(0 AS bit), s.source_code, s.builtin_code, s.module, s.css_class, s.inactive, s.editor_note, s.caption, s.helptext
			  );

			SET @cnt_a = @@ROWCOUNT;

			INSERT INTO meta_phrase (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				source_code, builtin_code, module,
				css_class,
				editor_note, caption, helptext,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				s.orig_uuid, @sys_owner, s.orig_uuid, 'A', 'A', @lang,
				s.inactive, 0, @import_origin,
				s.source_code, s.builtin_code, s.module,
				s.css_class,
				s.editor_note, s.caption, s.helptext,
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_phrase s
			WHERE s.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_phrase t
				WHERE t.original = s.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'A'
			  );

			SET @cnt_a = @cnt_a + @@ROWCOUNT;

			-- Symetrické 'L' záznamy v meta_phrase pro primární jazyk (@lang) s Delta kontrolou
			UPDATE t
			SET
				t.removed = 0,
				t.source_code = a.source_code,
				t.builtin_code = a.builtin_code,
				t.module = a.module,
				t.svg_icon = a.svg_icon,
				t.css_class = a.css_class,
				t.inactive = a.inactive,
				t.caption = a.caption,
				t.helptext = a.helptext,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_phrase t
			JOIN meta_phrase a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_phrase s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND EXISTS (
				SELECT t.removed, t.source_code, t.builtin_code, t.module, t.svg_icon, t.css_class, t.inactive, t.caption, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), a.source_code, a.builtin_code, a.module, a.svg_icon, a.css_class, a.inactive, a.caption, a.helptext
			  );

			INSERT INTO meta_phrase (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				source_code, builtin_code, module,
				svg_icon, css_class,
				caption, helptext,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
				a.inactive, 0, @import_origin,
				a.source_code, a.builtin_code, a.module,
				a.svg_icon, a.css_class,
				a.caption, a.helptext,
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM meta_phrase a
			JOIN #clean_phrase s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_phrase t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @lang
			  );

			EXEC insert_request_message 'Záložka phrase (jádro - změněné/nové záznamy)', 1, @intvalue = @cnt_a, @obj_type = 'meta_phrase', @obj_name = 'phrase';
		END
		ELSE
		BEGIN
			-- 2.C) REŽIM PŘEKLADŮ (@sec_lang): Upravují se výhradně změněné 'L' záznamy pro @sec_lang
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_phrase t
			JOIN #clean_phrase s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění překladů (removed=1) na záložce phrase', 1, @intvalue = @cnt_rem, @obj_type = 'meta_phrase (L)', @obj_name = @sec_lang;

			UPDATE t
			SET
				t.removed = 0,
				t.caption = s.caption_l,
				t.helptext = s.helptext_l,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_phrase t
			JOIN meta_phrase a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_phrase s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND EXISTS (
				SELECT t.removed, t.caption, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), s.caption_l, s.helptext_l
			  );

			SET @cnt_l = @@ROWCOUNT;

			INSERT INTO meta_phrase (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				source_code, builtin_code, module,
				svg_icon, css_class,
				caption, helptext,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @sec_lang,
				a.inactive, 0, @import_origin,
				a.source_code, a.builtin_code, a.module,
				a.svg_icon, a.css_class,
				s.caption_l, s.helptext_l,
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_phrase s
			JOIN meta_phrase a ON a.original = s.orig_uuid AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			WHERE s.removed = 0
			  AND (s.caption_l <> '' OR s.helptext_l <> '')
			  AND NOT EXISTS (
				SELECT 1 FROM meta_phrase t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
			  );

			SET @cnt_l = @cnt_l + @@ROWCOUNT;

			-- Jednotná auditní stopa na 'A' záznamu při změně překladu
			UPDATE a
			SET a.date_modified = l.date_modified,
				a.who_modified = l.who_modified
			FROM meta_phrase a
			JOIN meta_phrase l ON l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @sec_lang
			WHERE a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND l.date_modified > a.date_modified;

			EXEC insert_request_message 'Záložka phrase (překlady - změněné/nové záznamy)', 1, @intvalue = @cnt_l, @obj_type = 'meta_phrase (L)', @obj_name = @sec_lang;
		END

		DROP TABLE #clean_phrase;
	END
	ELSE
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_phrase$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_phrase$';
		RETURN;
	END

	-- =========================================================================
	-- 3. Zpracování záložky: menu (tabulka meta_menu – bez čtení svg_icon)
	-- =========================================================================
	IF OBJECT_ID('XLSX_menu$') IS NOT NULL
	BEGIN
		IF COL_LENGTH('XLSX_menu$', 'removed') IS NULL
			ALTER TABLE XLSX_menu$ ADD removed bit NOT NULL DEFAULT 0;

		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(builtin_code))
		FROM XLSX_menu$
		GROUP BY LTRIM(RTRIM(builtin_code))
		HAVING COUNT(*) > 1;

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
			CASE WHEN NULLIF(LTRIM(RTRIM(s.parent_code)), '') IS NOT NULL THEN dbo.f_generate_original('meta_menu', @sys_owner, LTRIM(RTRIM(s.parent_code)), '') ELSE NULL END AS calc_parent_uuid,
			ISNULL(s.sort_code, '') AS sort_code,
			LTRIM(RTRIM(ISNULL(s.target_page, ''))) AS target_page,
			CASE WHEN NULLIF(LTRIM(RTRIM(s.target_page)), '') IS NOT NULL THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', LTRIM(RTRIM(s.target_page))) ELSE NULL END AS calc_target_object,
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
			dbo.f_xlsx_clean(s.caption_l, 1) AS caption_l,
			dbo.f_xlsx_clean(s.description_l, 1) AS description_l,
			dbo.f_xlsx_clean(s.helptext_l, 1) AS helptext_l
		INTO #clean_menu
		FROM XLSX_menu$ s;

		-- Kontrola v režimu překladů: V Excelu je removed = 0, ale v databázi je hlavní 'A' záznam položky menu neplatný (removed = 1)
		IF @is_trans_mode = 1
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je položka menu neplatná (removed=1)', 'meta_menu', s.builtin_code
			FROM #clean_menu s
			WHERE s.removed = 0
			  AND EXISTS (SELECT 1 FROM meta_menu t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_menu t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END

		IF @is_trans_mode = 0
		BEGIN
			-- 3.A) REŽIM JÁDRA: Replikace zrušení položky menu (removed = 1)
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_menu t
			JOIN #clean_menu s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND s.builtin_code <> 'home'
			  AND t.object_owner = @sys_owner
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění položek menu (removed=1)', 1, @intvalue = @cnt_rem, @obj_type = 'meta_menu', @obj_name = 'menu';

			-- 3.B) REŽIM JÁDRA: Delta UPDATE hlavních záznamů ('A') v meta_menu (vč. obnovy z koše, svg_icon v DB zůstává nedotčeno!)
			UPDATE t
			SET
				t.[language] = @lang,
				t.removed = 0,
				t.parent_uuid = s.calc_parent_uuid,
				t.sort_code = s.sort_code,
				t.target_object = s.calc_target_object,
				t.url_parameters = s.url_parameters,
				t.target_url = s.target_url,
				t.target_window = s.target_window,
				t.system_role = s.system_role,
				t.permanent = s.permanent,
				t.css_class = s.css_class,
				t.editor_note = s.editor_note,
				t.caption = s.caption,
				t.description = s.description,
				t.helptext = s.helptext,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_menu t
			JOIN #clean_menu s ON s.orig_uuid = t.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND EXISTS (
				SELECT t.[language], t.removed, t.parent_uuid, t.sort_code, t.target_object, t.url_parameters, t.target_url, t.target_window, t.system_role, t.permanent, t.css_class, t.editor_note, t.caption, t.description, t.helptext
				EXCEPT
				SELECT @lang, CAST(0 AS bit), s.calc_parent_uuid, s.sort_code, s.calc_target_object, s.url_parameters, s.target_url, s.target_window, s.system_role, s.permanent, s.css_class, s.editor_note, s.caption, s.description, s.helptext
			  );

			SET @cnt_a = @@ROWCOUNT;

			INSERT INTO meta_menu (
				uuid, object_owner, original, record_type, approval_status, [language],
				removed, import_origin,
				builtin_code, parent_uuid, sort_code,
				target_object, url_parameters, target_url, target_window,
				caption, description, helptext, editor_note,
				css_class, system_role, permanent,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				s.orig_uuid, @sys_owner, s.orig_uuid, 'A', 'A', @lang,
				0, @import_origin,
				s.builtin_code, s.calc_parent_uuid, s.sort_code,
				s.calc_target_object, s.url_parameters, s.target_url, s.target_window,
				s.caption, s.description, s.helptext, s.editor_note,
				s.css_class, s.system_role, s.permanent,
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_menu s
			WHERE s.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_menu t
				WHERE t.original = s.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'A'
			  );

			SET @cnt_a = @cnt_a + @@ROWCOUNT;

			-- Kontrola referenční integrity vazeb parent_code a target_page (pro platné záznamy removed = 0)
			SET @bad_code = NULL;
			SELECT TOP 1 @bad_code = s.builtin_code + ' -> ' + s.parent_code
			FROM #clean_menu s
			WHERE s.removed = 0
			  AND s.parent_code <> ''
			  AND NOT EXISTS (
				SELECT 1 FROM meta_menu p
				WHERE p.original = s.calc_parent_uuid
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
			SELECT TOP 1 @bad_code = s.builtin_code + ' -> ' + s.target_page
			FROM #clean_menu s
			WHERE s.removed = 0
			  AND s.target_page <> ''
			  AND NOT EXISTS (
				SELECT 1 FROM meta_object mo
				WHERE mo.original = s.calc_target_object
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

			-- Symetrické 'L' záznamy v meta_menu pro primární jazyk (@lang) s Delta kontrolou
			UPDATE t
			SET
				t.removed = 0,
				t.parent_uuid = a.parent_uuid,
				t.sort_code = a.sort_code,
				t.target_object = a.target_object,
				t.url_parameters = a.url_parameters,
				t.target_url = a.target_url,
				t.target_window = a.target_window,
				t.system_role = a.system_role,
				t.permanent = a.permanent,
				t.svg_icon = a.svg_icon,
				t.css_class = a.css_class,
				t.caption = a.caption,
				t.description = a.description,
				t.helptext = a.helptext,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_menu t
			JOIN meta_menu a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_menu s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND EXISTS (
				SELECT t.removed, t.parent_uuid, t.sort_code, t.target_object, t.url_parameters, t.target_url, t.target_window, t.system_role, t.permanent, t.svg_icon, t.css_class, t.caption, t.description, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), a.parent_uuid, a.sort_code, a.target_object, a.url_parameters, a.target_url, a.target_window, a.system_role, a.permanent, a.svg_icon, a.css_class, a.caption, a.description, a.helptext
			  );

			INSERT INTO meta_menu (
				uuid, object_owner, original, record_type, approval_status, [language],
				removed, import_origin,
				builtin_code, parent_uuid, sort_code,
				target_object, url_parameters, target_url, target_window,
				caption, description, helptext,
				svg_icon, css_class, system_role, permanent,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
				0, @import_origin,
				a.builtin_code, a.parent_uuid, a.sort_code,
				a.target_object, a.url_parameters, a.target_url, a.target_window,
				a.caption, a.description, a.helptext,
				a.svg_icon, a.css_class, a.system_role, a.permanent,
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM meta_menu a
			JOIN #clean_menu s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_menu t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @lang
			  );

			EXEC insert_request_message 'Záložka menu (jádro - změněné/nové záznamy)', 1, @intvalue = @cnt_a, @obj_type = 'meta_menu', @obj_name = 'menu';
		END
		ELSE
		BEGIN
			-- 3.C) REŽIM PŘEKLADŮ (@sec_lang): Upravují se výhradně změněné 'L' záznamy pro @sec_lang
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_menu t
			JOIN #clean_menu s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění překladů (removed=1) na záložce menu', 1, @intvalue = @cnt_rem, @obj_type = 'meta_menu (L)', @obj_name = @sec_lang;

			UPDATE t
			SET
				t.removed = 0,
				t.caption = s.caption_l,
				t.description = s.description_l,
				t.helptext = s.helptext_l,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_menu t
			JOIN meta_menu a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_menu s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND EXISTS (
				SELECT t.removed, t.caption, t.description, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), s.caption_l, s.description_l, s.helptext_l
			  );

			SET @cnt_l = @@ROWCOUNT;

			INSERT INTO meta_menu (
				uuid, object_owner, original, record_type, approval_status, [language],
				removed, import_origin,
				builtin_code, parent_uuid, sort_code,
				target_object, url_parameters, target_url, target_window,
				caption, description, helptext,
				svg_icon, css_class, system_role, permanent,
				is_final, is_protected,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @sec_lang,
				0, @import_origin,
				a.builtin_code, a.parent_uuid, a.sort_code,
				a.target_object, a.url_parameters, a.target_url, a.target_window,
				s.caption_l, s.description_l, s.helptext_l,
				a.svg_icon, a.css_class, a.system_role, a.permanent,
				1, 1,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_menu s
			JOIN meta_menu a ON a.original = s.orig_uuid AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			WHERE s.removed = 0
			  AND (s.caption_l <> '' OR s.description_l <> '' OR s.helptext_l <> '')
			  AND NOT EXISTS (
				SELECT 1 FROM meta_menu t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
			  );

			SET @cnt_l = @cnt_l + @@ROWCOUNT;

			-- Jednotná auditní stopa na 'A' záznamu při změně překladu
			UPDATE a
			SET a.date_modified = l.date_modified,
				a.who_modified = l.who_modified
			FROM meta_menu a
			JOIN meta_menu l ON l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @sec_lang
			WHERE a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND l.date_modified > a.date_modified;

			EXEC insert_request_message 'Záložka menu (překlady - změněné/nové záznamy)', 1, @intvalue = @cnt_l, @obj_type = 'meta_menu (L)', @obj_name = @sec_lang;
		END

		DROP TABLE #clean_menu;
	END
	ELSE
	BEGIN
		EXEC insert_request_message 'Chybí povinná tabulka XLSX_menu$', 3, @obj_type = 'Tabulka', @obj_name = 'XLSX_menu$';
		RETURN;
	END

	-- =========================================================================
	-- 4. Zpracování volitelné záložky: class (tabulka meta_class – bez čtení svg_icon)
	-- =========================================================================
	IF OBJECT_ID('XLSX_class$') IS NOT NULL
	BEGIN
		IF COL_LENGTH('XLSX_class$', 'removed') IS NULL
			ALTER TABLE XLSX_class$ ADD removed varchar(10) NOT NULL DEFAULT '0';

		IF COL_LENGTH('XLSX_class$', 'days_in_trash') IS NULL
			ALTER TABLE XLSX_class$ ADD days_in_trash varchar(20) NOT NULL DEFAULT '365';

		SET @bad_code = NULL;
		SELECT TOP 1 @bad_code = LTRIM(RTRIM(class_name))
		FROM XLSX_class$
		GROUP BY LTRIM(RTRIM(class_name))
		HAVING COUNT(*) > 1;

		IF @bad_code IS NOT NULL
		BEGIN
			EXEC insert_request_message 'Duplicitní class_name na záložce class', 3, @obj_type = 'class', @obj_name = @bad_code;
			RETURN;
		END

		-- Očištění hodnot uzavřených <do stříšek> do pomocné tabulky #clean_class pomocí dbo.f_xlsx_clean (bez svg_icon)
		IF OBJECT_ID('tempdb..#clean_class') IS NOT NULL DROP TABLE #clean_class;

		SELECT
			LTRIM(RTRIM(ISNULL(s.class_name, ''))) AS class_name,
			dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), LTRIM(RTRIM(ISNULL(s.class_name, ''))), '') AS orig_uuid,
			ISNULL(NULLIF(LTRIM(RTRIM(s.storage_type)), ''), 'T') AS storage_type,
			LTRIM(RTRIM(ISNULL(s.storage_code, ''))) AS storage_code,
			dbo.f_generate_original('meta_object', @sys_owner, ISNULL(NULLIF(LTRIM(RTRIM(s.storage_type)), ''), 'T'), LTRIM(RTRIM(ISNULL(s.storage_code, '')))) AS calc_storage_uuid,
			LTRIM(RTRIM(ISNULL(s.ancestor_code, ''))) AS ancestor_code,
			CASE WHEN LTRIM(RTRIM(ISNULL(s.ancestor_code, ''))) <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), LTRIM(RTRIM(s.ancestor_code)), '') ELSE NULL END AS calc_ancestor_uuid,
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

		-- Propustná kontrola existence úložného objektu (storage_code) v meta_object
		UPDATE s
		SET s.storage_valid = 0
		FROM #clean_class s
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object mo
			WHERE mo.original = s.calc_storage_uuid
			  AND mo.object_owner = @sys_owner
			  AND mo.record_type = 'A'
			  AND mo.removed = 0
		);

		-- Zápis do protokolu (propustná chyba severity = 2), pokud je v Excelu removed = 0 a v DB úložný objekt neexistuje / je neplatný
		INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
		SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je úložný objekt (storage_code) neplatný nebo neexistuje (třída přeskočena)', 'meta_class', s.class_name + ' -> ' + s.storage_type + ':' + s.storage_code
		FROM #clean_class s
		WHERE s.removed = 0 AND s.storage_valid = 0;

		-- Zápis do protokolu v režimu překladů (severity = 2), pokud je v Excelu removed = 0 a v DB je hlavní 'A' záznam třídy označen removed = 1
		IF @is_trans_mode = 1
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je logická třída neplatná (removed=1)', 'meta_class', s.class_name
			FROM #clean_class s
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND EXISTS (SELECT 1 FROM meta_class t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_class t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END

		-- Normalizace zděděných hodnot přímo v #clean_class před porovnáním s DB (při shodě s předkem uložíme NULL)
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
		LEFT JOIN #clean_class anc_s ON anc_s.orig_uuid = s.calc_ancestor_uuid AND anc_s.removed = 0 AND anc_s.storage_valid = 1
		LEFT JOIN meta_class anc_db ON anc_db.original = s.calc_ancestor_uuid AND anc_db.object_owner = @sys_owner AND anc_db.record_type = 'A' AND anc_db.removed = 0
		LEFT JOIN meta_class anc_l ON anc_l.original = s.calc_ancestor_uuid AND anc_l.object_owner = @sys_owner AND anc_l.record_type = 'L' AND anc_l.[language] = @sec_lang AND anc_l.removed = 0 AND @is_trans_mode = 1
		WHERE s.calc_ancestor_uuid IS NOT NULL;

		IF @is_trans_mode = 0
		BEGIN
			-- 4.A) REŽIM JÁDRA: Replikace zrušení třídy (removed = 1)
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'Primitivní třídu svázanou s existujícím fyzickým objektem nelze odstranit (removed=1 ignorováno)', 'meta_class', s.class_name
			FROM #clean_class s
			WHERE s.removed = 1
			  AND s.storage_valid = 1
			  AND s.class_name = s.storage_code
			  AND EXISTS (
				SELECT 1 FROM meta_class t
				WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0
			  );

			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_class t
			JOIN #clean_class s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND (s.class_name <> s.storage_code OR s.storage_valid = 0)
			  AND t.object_owner = @sys_owner
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění logických tříd (removed=1)', 1, @intvalue = @cnt_rem, @obj_type = 'meta_class', @obj_name = 'class';

			-- 4.B) REŽIM JÁDRA: Delta UPDATE hlavních záznamů ('A') v meta_class (vč. obnovy z koše a days_in_trash, svg_icon nedotčeno!)
			UPDATE t
			SET
				t.[language] = @lang,
				t.removed = 0,
				t.storage_object = s.calc_storage_uuid,
				t.ancestor_class = s.calc_ancestor_uuid,
				t.sort_code = s.sort_code,
				t.days_in_trash = s.days_in_trash,
				t.is_final = s.is_final,
				t.is_protected = s.is_protected,
				t.inactive = s.inactive,
				t.editor_note = s.editor_note,
				t.caption = s.caption,
				t.caption_plural = s.caption_plural,
				t.description = s.description,
				t.helptext = s.helptext,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_class t
			JOIN #clean_class s ON s.orig_uuid = t.original
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND EXISTS (
				SELECT t.[language], t.removed, t.storage_object, t.ancestor_class, t.sort_code, t.days_in_trash, t.is_final, t.is_protected, t.inactive, t.editor_note, t.caption, t.caption_plural, t.description, t.helptext
				EXCEPT
				SELECT @lang, CAST(0 AS bit), s.calc_storage_uuid, s.calc_ancestor_uuid, s.sort_code, s.days_in_trash, s.is_final, s.is_protected, s.inactive, s.editor_note, s.caption, s.caption_plural, s.description, s.helptext
			  );

			SET @cnt_a = @@ROWCOUNT;

			INSERT INTO meta_class (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				class_name, storage_object, ancestor_class, sort_code, days_in_trash,
				is_final, is_protected,
				editor_note, caption, caption_plural, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				s.orig_uuid, @sys_owner, s.orig_uuid, 'A', 'A', @lang,
				s.inactive, 0, @import_origin,
				s.class_name, s.calc_storage_uuid, s.calc_ancestor_uuid, s.sort_code, s.days_in_trash,
				s.is_final, s.is_protected,
				s.editor_note, s.caption, s.caption_plural, s.description, s.helptext,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_class s
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND NOT EXISTS (
				SELECT 1 FROM meta_class t
				WHERE t.original = s.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'A'
			  );

			SET @cnt_a = @cnt_a + @@ROWCOUNT;

			-- Kontrola referenční integrity ancestor_code proti meta_class
			SET @bad_code = NULL;
			SELECT TOP 1 @bad_code = s.class_name + ' -> ' + s.ancestor_code
			FROM #clean_class s
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND s.ancestor_code <> ''
			  AND NOT EXISTS (
				SELECT 1 FROM meta_class p
				WHERE p.original = s.calc_ancestor_uuid
				  AND p.object_owner = @sys_owner
				  AND p.record_type = 'A'
				  AND p.removed = 0
			  );

			IF @bad_code IS NOT NULL
			BEGIN
				EXEC insert_request_message 'Neexistující nadřízená třída (ancestor_code) na záložce class', 3, @obj_type = 'meta_class', @obj_name = @bad_code;
				RETURN;
			END

			-- Symetrické 'L' záznamy v meta_class pro primární jazyk (@lang) s Delta kontrolou
			UPDATE t
			SET
				t.removed = 0,
				t.storage_object = a.storage_object,
				t.ancestor_class = a.ancestor_class,
				t.sort_code = a.sort_code,
				t.days_in_trash = a.days_in_trash,
				t.svg_icon = a.svg_icon,
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
			JOIN #clean_class s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND EXISTS (
				SELECT t.removed, t.storage_object, t.ancestor_class, t.sort_code, t.days_in_trash, t.svg_icon, t.is_final, t.is_protected, t.inactive, t.caption, t.caption_plural, t.description, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), a.storage_object, a.ancestor_class, a.sort_code, a.days_in_trash, a.svg_icon, a.is_final, a.is_protected, a.inactive, a.caption, a.caption_plural, a.description, a.helptext
			  );

			INSERT INTO meta_class (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				class_name, storage_object, ancestor_class, sort_code, days_in_trash, svg_icon,
				is_final, is_protected,
				caption, caption_plural, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
				a.inactive, 0, @import_origin,
				a.class_name, a.storage_object, a.ancestor_class, a.sort_code, a.days_in_trash, a.svg_icon,
				a.is_final, a.is_protected,
				a.caption, a.caption_plural, a.description, a.helptext,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM meta_class a
			JOIN #clean_class s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_class t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @lang
			  );

			EXEC insert_request_message 'Záložka class (jádro - změněné/nové záznamy)', 1, @intvalue = @cnt_a, @obj_type = 'meta_class', @obj_name = 'class';
		END
		ELSE
		BEGIN
			-- 4.C) REŽIM PŘEKLADŮ (@sec_lang): Upravují se výhradně změněné 'L' záznamy pro @sec_lang
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_class t
			JOIN #clean_class s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění překladů (removed=1) na záložce class', 1, @intvalue = @cnt_rem, @obj_type = 'meta_class (L)', @obj_name = @sec_lang;

			UPDATE t
			SET
				t.removed = 0,
				t.caption = s.caption_l,
				t.caption_plural = s.caption_plural_l,
				t.description = s.description_l,
				t.helptext = s.helptext_l,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_class t
			JOIN meta_class a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_class s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND EXISTS (
				SELECT t.removed, t.caption, t.caption_plural, t.description, t.helptext
				EXCEPT
				SELECT CAST(0 AS bit), s.caption_l, s.caption_plural_l, s.description_l, s.helptext_l
			  );

			SET @cnt_l = @@ROWCOUNT;

			INSERT INTO meta_class (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
				class_name, storage_object, ancestor_class, sort_code, days_in_trash, svg_icon,
				is_final, is_protected,
				caption, caption_plural, description, helptext,
				date_created, who_created, date_modified, who_modified
			)
			SELECT
				NEWID(), @sys_owner, a.original, 'L', 'A', @sec_lang,
				a.inactive, 0, @import_origin,
				a.class_name, a.storage_object, a.ancestor_class, a.sort_code, a.days_in_trash, a.svg_icon,
				a.is_final, a.is_protected,
				s.caption_l,
				s.caption_plural_l,
				s.description_l,
				s.helptext_l,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_class s
			JOIN meta_class a ON a.original = s.orig_uuid AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			WHERE s.removed = 0
			  AND s.storage_valid = 1
			  AND (s.caption_l IS NOT NULL OR s.caption_plural_l IS NOT NULL OR s.description_l IS NOT NULL OR s.helptext_l IS NOT NULL)
			  AND NOT EXISTS (
				SELECT 1 FROM meta_class t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
			  );

			SET @cnt_l = @cnt_l + @@ROWCOUNT;

			-- Jednotná auditní stopa na 'A' záznamu při změně překladu
			UPDATE a
			SET a.date_modified = l.date_modified,
				a.who_modified = l.who_modified
			FROM meta_class a
			JOIN meta_class l ON l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @sec_lang
			WHERE a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND l.date_modified > a.date_modified;

			EXEC insert_request_message 'Záložka class (překlady - změněné/nové záznamy)', 1, @intvalue = @cnt_l, @obj_type = 'meta_class (L)', @obj_name = @sec_lang;
		END

		DROP TABLE #clean_class;
	END

	-- =========================================================================
	-- 5. Zpracování volitelné záložky: column (tabulka meta_column)
	-- =========================================================================
	IF OBJECT_ID('XLSX_column$') IS NOT NULL
	BEGIN
		IF COL_LENGTH('XLSX_column$', 'removed') IS NULL
			ALTER TABLE XLSX_column$ ADD removed varchar(10) NOT NULL DEFAULT '0';

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

		-- Očištění všech hodnot od případných stříšek <...> do pomocné tabulky #clean_column pomocí dbo.f_xlsx_clean
		IF OBJECT_ID('tempdb..#clean_column') IS NOT NULL DROP TABLE #clean_column;

		SELECT
			LTRIM(RTRIM(ISNULL(s.class_name, ''))) AS class_name,
			LTRIM(RTRIM(ISNULL(s.column_name, ''))) AS column_name,
			p.calc_parent_class,
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
			CASE WHEN LTRIM(RTRIM(ISNULL(s.class_name, ''))) <> 'sys_global_columns' AND v.ancestor_column <> '' THEN dbo.f_generate_original('meta_column', @sys_owner, CAST(@global_cls_uuid AS varchar(36)), v.ancestor_column) ELSE NULL END AS calc_ancestor_uuid,
			ISNULL(dbo.f_xlsx_clean(s.referenced_codetable, 0), '') AS referenced_codetable,
			v.referenced_class_code,
			CASE WHEN v.referenced_class_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), v.referenced_class_code, '') ELSE NULL END AS calc_ref_class_uuid,
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
			CAST(1 AS bit) AS class_valid
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

		-- Propustná kontrola existence nadřízené třídy v meta_class I platnosti jejího úložného objektu v meta_object
		UPDATE s
		SET s.class_valid = 0
		FROM #clean_column s
		WHERE NOT EXISTS (
			SELECT 1
			FROM meta_class mc
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0
			WHERE mc.original = s.calc_parent_class
			  AND mc.object_owner = @sys_owner
			  AND mc.record_type = 'A'
			  AND mc.removed = 0
		);

		-- Zápis propustného varování (severity = 2) pro sloupce neplatných / přeskočených tříd
		INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
		SELECT @@SPID, 2, 'V Excelu je removed=0, ale nadřízená logická třída v databázi není platná (sloupec přeskočen)', 'meta_column', s.class_name + '.' + s.column_name
		FROM #clean_column s
		WHERE s.removed = 0 AND s.class_valid = 0;

		-- Zápis varování v režimu překladů (severity = 2), pokud je v Excelu removed = 0 a v DB má hlavní 'A' záznam sloupce removed = 1
		IF @is_trans_mode = 1
		BEGIN
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'V Excelu je removed=0, ale v databázi je sloupec neplatný (removed=1)', 'meta_column', s.class_name + '.' + s.column_name
			FROM #clean_column s
			WHERE s.removed = 0
			  AND s.class_valid = 1
			  AND EXISTS (SELECT 1 FROM meta_column t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 1)
			  AND NOT EXISTS (SELECT 1 FROM meta_column t WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0);
		END

		-- Normalizace zděděných hodnot přímo v #clean_column před porovnáním s DB:
		-- Pokud má sloupec předka v sys_global_columns (v Excelu gc_s nebo v DB gc_db) a hodnota je shodná, uložíme NULL (resp. '' u referenced_codetable)
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
			s.calc_ref_class_uuid = CASE WHEN s.calc_ref_class_uuid = COALESCE(gc_s.calc_ref_class_uuid, gc_db.referenced_class) THEN NULL ELSE s.calc_ref_class_uuid END,
			s.caption_l = CASE WHEN ISNULL(s.caption_l, '') = ISNULL(COALESCE(gc_s.caption_l, gc_l.caption), '') THEN NULL ELSE s.caption_l END,
			s.caption_plural_l = CASE WHEN ISNULL(s.caption_plural_l, '') = ISNULL(COALESCE(gc_s.caption_plural_l, gc_l.caption_plural), '') THEN NULL ELSE s.caption_plural_l END,
			s.description_l = CASE WHEN ISNULL(s.description_l, '') = ISNULL(COALESCE(gc_s.description_l, gc_l.description), '') THEN NULL ELSE s.description_l END,
			s.label_l = CASE WHEN ISNULL(s.label_l, '') = ISNULL(COALESCE(gc_s.label_l, gc_l.label), '') THEN NULL ELSE s.label_l END,
			s.header_l = CASE WHEN ISNULL(s.header_l, '') = ISNULL(COALESCE(gc_s.header_l, gc_l.header), '') THEN NULL ELSE s.header_l END,
			s.helptext_l = CASE WHEN ISNULL(s.helptext_l, '') = ISNULL(COALESCE(gc_s.helptext_l, gc_l.helptext), '') THEN NULL ELSE s.helptext_l END,
			s.placeholder_l = CASE WHEN ISNULL(s.placeholder_l, '') = ISNULL(COALESCE(gc_s.placeholder_l, gc_l.placeholder), '') THEN NULL ELSE s.placeholder_l END
		FROM #clean_column s
		LEFT JOIN #clean_column gc_s ON gc_s.orig_uuid = s.calc_ancestor_uuid AND gc_s.removed = 0 AND gc_s.class_valid = 1
		LEFT JOIN meta_column gc_db ON gc_db.original = s.calc_ancestor_uuid AND gc_db.object_owner = @sys_owner AND gc_db.record_type = 'A' AND gc_db.removed = 0
		LEFT JOIN meta_column gc_l ON gc_l.original = s.calc_ancestor_uuid AND gc_l.object_owner = @sys_owner AND gc_l.record_type = 'L' AND gc_l.[language] = @sec_lang AND gc_l.removed = 0 AND @is_trans_mode = 1
		WHERE s.calc_parent_class <> @global_cls_uuid
		  AND s.calc_ancestor_uuid IS NOT NULL;

		IF @is_trans_mode = 0
		BEGIN
			-- 5.A) REŽIM JÁDRA: Replikace zrušení sloupce (removed = 1)
			INSERT INTO request_message (spid, severity, msgtext, obj_type, obj_name)
			SELECT @@SPID, 2, 'Fyzicky existující sloupec databázové tabulky nelze v metadatech odstranit (removed=1 ignorováno)', 'meta_column', s.class_name + '.' + s.column_name
			FROM #clean_column s
			JOIN meta_class mc ON mc.original = s.calc_parent_class AND mc.object_owner = @sys_owner AND mc.record_type = 'A' AND mc.removed = 0
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0
			JOIN v_syscolumns vc ON vc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT AND vc.colname = s.column_name COLLATE DATABASE_DEFAULT
			WHERE s.removed = 1
			  AND mc.class_name = mo.builtin_code
			  AND EXISTS (
				SELECT 1 FROM meta_column t
				WHERE t.original = s.orig_uuid AND t.object_owner = @sys_owner AND t.record_type = 'A' AND t.removed = 0
			  );

			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_column t
			JOIN #clean_column s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND t.object_owner = @sys_owner
			  AND t.removed = 0
			  AND NOT EXISTS (
				SELECT 1
				FROM meta_class mc
				JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_owner = @sys_owner AND mo.record_type = 'A' AND mo.removed = 0
				JOIN v_syscolumns vc ON vc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT AND vc.colname = s.column_name COLLATE DATABASE_DEFAULT
				WHERE mc.original = s.calc_parent_class
				  AND mc.object_owner = @sys_owner
				  AND mc.record_type = 'A'
				  AND mc.removed = 0
				  AND mc.class_name = mo.builtin_code
			  );

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění sloupců (removed=1)', 1, @intvalue = @cnt_rem, @obj_type = 'meta_column', @obj_name = 'column';

			-- 5.B) REŽIM JÁDRA: Delta UPDATE hlavních záznamů ('A') v meta_column (vč. obnovy z koše)
			UPDATE t
			SET
				t.[language] = @lang,
				t.removed = 0,
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
				t.ancestor = s.calc_ancestor_uuid,
				t.referenced_codetable = s.referenced_codetable,
				t.referenced_class = s.calc_ref_class_uuid,
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
			JOIN #clean_column s ON s.orig_uuid = t.original
			WHERE s.removed = 0
			  AND s.class_valid = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'A'
			  AND EXISTS (
				SELECT
					t.[language], t.removed, t.parent_order, t.sort_code, t.list_order,
					t.input_type, t.input_width, t.input_rows, t.max_length, t.css_class,
					t.translate, t.history, t.is_html, t.is_mandatory, t.is_url, t.is_computed,
					t.show_empty, t.hidden, t.customizable,
					t.ancestor, t.referenced_codetable, t.referenced_class,
					t.is_final, t.is_protected, t.inactive, t.editor_note,
					t.caption, t.caption_plural, t.description, t.label, t.header, t.helptext, t.placeholder
				EXCEPT
				SELECT
					@lang, CAST(0 AS bit), s.parent_order, s.sort_code, s.list_order,
					s.input_type, s.input_width, s.input_rows, s.max_length, s.css_class,
					s.translate, s.history, s.is_html, s.is_mandatory, s.is_url, s.is_computed,
					s.show_empty, s.hidden, s.customizable,
					s.calc_ancestor_uuid, s.referenced_codetable, s.calc_ref_class_uuid,
					s.is_final, s.is_protected, s.inactive, s.editor_note,
					s.caption, s.caption_plural, s.description, s.label, s.header, s.helptext, s.placeholder
			  );

			SET @cnt_a = @@ROWCOUNT;

			INSERT INTO meta_column (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
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
				s.orig_uuid, @sys_owner, s.orig_uuid, 'A', 'A', @lang,
				s.inactive, 0, @import_origin,
				s.calc_parent_class, s.parent_order, s.sort_code, s.column_name, s.list_order,
				s.caption, s.caption_plural, s.description, s.label, s.header, s.helptext, s.placeholder, s.editor_note,
				s.input_type, s.input_width, s.input_rows, s.max_length, s.css_class,
				s.translate, s.history, s.is_html, s.is_mandatory, s.is_url, s.is_computed,
				s.show_empty, s.hidden, s.customizable,
				s.calc_ancestor_uuid, s.referenced_codetable, s.calc_ref_class_uuid,
				s.is_final, s.is_protected,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM #clean_column s
			WHERE s.removed = 0
			  AND s.class_valid = 1
			  AND NOT EXISTS (
				SELECT 1 FROM meta_column t
				WHERE t.original = s.orig_uuid
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'A'
			  );

			SET @cnt_a = @cnt_a + @@ROWCOUNT;

			-- Symetrické 'L' záznamy v meta_column pro primární jazyk (@lang) s Delta kontrolou
			UPDATE t
			SET
				t.removed = 0,
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
			JOIN #clean_column s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND s.class_valid = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @lang
			  AND EXISTS (
				SELECT
					t.removed, t.parent_order, t.sort_code, t.list_order,
					t.caption, t.caption_plural, t.description, t.label, t.header, t.helptext, t.placeholder,
					t.input_type, t.input_width, t.input_rows, t.max_length, t.css_class,
					t.translate, t.history, t.is_html, t.is_mandatory, t.is_url, t.is_computed,
					t.show_empty, t.hidden, t.customizable,
					t.ancestor, t.referenced_codetable, t.referenced_class,
					t.is_final, t.is_protected, t.inactive
				EXCEPT
				SELECT
					CAST(0 AS bit), a.parent_order, a.sort_code, a.list_order,
					a.caption, a.caption_plural, a.description, a.label, a.header, a.helptext, a.placeholder,
					a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
					a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
					a.show_empty, a.hidden, a.customizable,
					a.ancestor, a.referenced_codetable, a.referenced_class,
					a.is_final, a.is_protected, a.inactive
			  );

			INSERT INTO meta_column (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
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
				a.inactive, 0, @import_origin,
				a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
				a.caption, a.caption_plural, a.description, a.label, a.header, a.helptext, a.placeholder,
				a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
				a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
				a.show_empty, a.hidden, a.customizable,
				a.ancestor, a.referenced_codetable, a.referenced_class,
				a.is_final, a.is_protected,
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM meta_column a
			JOIN #clean_column s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND s.class_valid = 1
			  AND a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND NOT EXISTS (
				SELECT 1 FROM meta_column t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @lang
			  );

			EXEC insert_request_message 'Záložka column (jádro - změněné/nové záznamy)', 1, @intvalue = @cnt_a, @obj_type = 'meta_column', @obj_name = 'column';
		END
		ELSE
		BEGIN
			-- 5.C) REŽIM PŘEKLADŮ (@sec_lang): Upravují se výhradně změněné 'L' záznamy pro @sec_lang
			UPDATE t
			SET t.removed = 1,
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_column t
			JOIN #clean_column s ON s.orig_uuid = t.original
			WHERE s.removed = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND t.removed = 0;

			SET @cnt_rem = @@ROWCOUNT;
			IF @cnt_rem > 0
				EXEC insert_request_message 'Zreplikováno odstranění překladů (removed=1) na záložce column', 1, @intvalue = @cnt_rem, @obj_type = 'meta_column (L)', @obj_name = @sec_lang;

			UPDATE t
			SET
				t.removed = 0,
				t.caption = s.caption_l,
				t.caption_plural = s.caption_plural_l,
				t.description = s.description_l,
				t.label = s.label_l,
				t.header = s.header_l,
				t.helptext = s.helptext_l,
				t.placeholder = s.placeholder_l,
				t.import_origin = ISNULL(@import_origin, t.import_origin),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_column t
			JOIN meta_column a ON a.original = t.original AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			JOIN #clean_column s ON s.orig_uuid = a.original
			WHERE s.removed = 0
			  AND s.class_valid = 1
			  AND t.object_owner = @sys_owner
			  AND t.record_type = 'L'
			  AND t.[language] = @sec_lang
			  AND EXISTS (
				SELECT t.removed, t.caption, t.caption_plural, t.description, t.label, t.header, t.helptext, t.placeholder
				EXCEPT
				SELECT CAST(0 AS bit), s.caption_l, s.caption_plural_l, s.description_l, s.label_l, s.header_l, s.helptext_l, s.placeholder_l
			  );

			SET @cnt_l = @@ROWCOUNT;

			INSERT INTO meta_column (
				uuid, object_owner, original, record_type, approval_status, [language],
				inactive, removed, import_origin,
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
				a.inactive, 0, @import_origin,
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
			FROM #clean_column s
			JOIN meta_column a ON a.original = s.orig_uuid AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
			WHERE s.removed = 0
			  AND s.class_valid = 1
			  AND (
				s.caption_l IS NOT NULL OR s.caption_plural_l IS NOT NULL OR s.description_l IS NOT NULL
				OR s.label_l IS NOT NULL OR s.header_l IS NOT NULL OR s.helptext_l IS NOT NULL OR s.placeholder_l IS NOT NULL
			  )
			  AND NOT EXISTS (
				SELECT 1 FROM meta_column t
				WHERE t.original = a.original
				  AND t.object_owner = @sys_owner
				  AND t.record_type = 'L'
				  AND t.[language] = @sec_lang
			  );

			SET @cnt_l = @cnt_l + @@ROWCOUNT;

			-- Jednotná auditní stopa na 'A' záznamu při změně překladu
			UPDATE a
			SET a.date_modified = l.date_modified,
				a.who_modified = l.who_modified
			FROM meta_column a
			JOIN meta_column l ON l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @sec_lang
			WHERE a.object_owner = @sys_owner
			  AND a.record_type = 'A'
			  AND l.date_modified > a.date_modified;

			EXEC insert_request_message 'Záložka column (překlady - změněné/nové záznamy)', 1, @intvalue = @cnt_l, @obj_type = 'meta_column (L)', @obj_name = @sec_lang;
		END

		DROP TABLE #clean_column;
	END
END
GO