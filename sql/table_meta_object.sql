/* =============================================================================
 * Verze: 2026-10-18 12:35
 * Soubor: table_meta_object.sql
 * Tabulka: meta_object
 * Popis:   Uchovává metadata fyzických objektů v databázi (tabulky, views, funkce, stránky).
 * Vazby:   - Slouží jako fyzický podklad (storage_object) pro logické třídy v meta_class.
 *          - Záznamy typu 'P' (PHP Page / třída) jsou odkazovány z meta_menu.target_object,
 *            slouží k řízení přístupu přes sloupec system_role a představují platné
 *            zdrojové objekty (source_code) pro textové fráze v tabulce meta_phrase.
 *          - Záznamy typu 'G' (Global Phrase) uchovávají celosystémové textové fráze
 *            (nahrazeno samostatnou tabulkou meta_phrase).
 *          - Plněno automaticky procedurou p_fix_meta_column (typy T, V, F, C)
 *            a hromadným importem z Excelu přes proceduru p_xlsx_meta_object (typy P, M).
 * Změny:   - Odstraněny sloupce is_final a is_protected (ochrana je v meta_class).
 *          - Odstraněn sloupec column_ancestor (přesunut do meta_class).
 *          - Prezentační texty změněny na NULLable (primární zdroj je nově meta_class).
 *          - Přidán sloupec import_origin pro evidenci původu záznamu z importu (Měkký audit).
 *          - 2026-10-09: Přidán sloupec system_role pro základní řízení přístupu.
 *          - 2026-10-14: Přidán sloupec editor_note pro kontext k překladům pomocí AI.
 *          - 2026-10-15: Sjednocena jmenná konvence pro object_type = 'P' na celé názvy
 *            PHP souborů/tříd včetně prefixu page_ a zaregistrovány bázové UI třídy.
 *            Doplněn výmaz opuštěných záznamů bez prefixu page_ a starých frází typu 'G'.
 *          - 2026-10-15 23:55: Zaregistrována stránka page_meta_phrase a u stránek metadat
 *            (page_meta_class, page_meta_column, page_meta_phrase) nastavena system_role = 'U'
 *            pro umožnění překladů všem rolím (funkční atributy chrání entity_manager pro 'D').
 *          - 2026-10-17 00:50: Doplněny sloupce draft_author a approval_note pro schvalovací
 *            cyklus (SSC) a zaregistrována univerzální schvalovací stránka page_approval.
 *          - 2026-10-18 12:35: Doplněny unikátní indexy uq_meta_object_active a
 *            uq_meta_object_language a symetrické 'L' záznamy pro výchozí stránky.
 * ============================================================================= */

-- Idempotentní odstranění staré verze (pokud neobsahuje poslední významnou změnu)
IF NOT EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_object' AND colname = 'editor_note')
BEGIN
	EXECUTE dropni 'meta_object';
END
GO

IF OBJECT_ID('meta_object') IS NULL
BEGIN
	CREATE TABLE meta_object(
		-- -------------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,           -- UUID tenanta (organizace). 0x00 pro systémové záznamy.
		original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor záznamu napříč verzemi a tenant overridy.
		record_type varchar(1) NOT NULL DEFAULT 'A',       -- 'A' = aktuálně schválený, 'L' = jazyková verze, 'D' = koncept, 'H' = historie.
		approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stavy schvalování v rámci SSC ('A' = schválený, 'D' = rozpracovaný, 'F' = ke schválení, 'R' = vrácený).
		draft_author uuid NOT NULL DEFAULT 0x00,           -- Autor konceptu (user_account.original) pro record_type = 'D'.
		approval_note varchar(max) NOT NULL DEFAULT '',    -- Poznámka schvalovatele (důvod odmítnutí / vrácení).
		inactive bit NOT NULL DEFAULT 0,                   -- Příznak deaktivace (používá se např. u systémových záznamů místo fyzického smazání).
		removed bit NOT NULL DEFAULT 0,                    -- Příznak odstranění.
		language varchar(2) NOT NULL DEFAULT 'cs',         -- Jazyková mutace (využito pro record_type = 'L' a 'D').
		valid_from date NOT NULL DEFAULT '1970-01-01',     -- Platnost od.
		valid_to date NULL,                                -- Platnost do.
		is_template bit NOT NULL DEFAULT 0,                -- Určuje, zda záznam slouží jako šablona.
		template uuid NULL,                                -- Odkaz na šablonu, ze které byl záznam vytvořen.
		import_origin varchar(255) NULL,                   -- Původní textový autor/systém z importu (Měkký audit)

		-- -------------------------------------------------------------------------
		-- Auditní stopy
		-- -------------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,            -- Načítáno autonomně z dbsession.login_session_uuid.
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,           -- Načítáno autonomně z dbsession.login_session_uuid.

		-- -------------------------------------------------------------------------
		-- Specifické atributy objektu
		-- -------------------------------------------------------------------------
		object_type varchar(1) NOT NULL,                   -- T=Table, V=View, F=Function, P=PHP Page, G=Global Phrase, C=Column Ancestor, M=Module
		builtin_code varchar(80) NOT NULL,                 -- Fyzický název objektu v DB (např. název tabulky, view) nebo kód.
		
		-- Prezentační texty (slouží primárně jako technická dokumentace pro DB admina)
		caption varchar(200) NULL,                         -- Zobrazovaný název (lokalizovatelný).
		caption_plural varchar(200) NULL,                  -- Množné číslo názvu.
		description varchar(max) NULL,                     -- Podrobnější interní popis objektu a jeho účelu.
		helptext varchar(max) NULL,                        -- Text nápovědy určený pro UI.
		editor_note varchar(max) NULL,                     -- Kontextová poznámka pro překladatele a AI (nepřekládá se).
		
		module varchar(80) NOT NULL DEFAULT '',            -- Modul, ke kterému objekt patří (odkaz na builtin_code u object_type = 'M').

		-- -------------------------------------------------------------------------
		-- Řízení přístupu (Autorizace)
		-- -------------------------------------------------------------------------
		-- Určuje minimální oprávnění pro přístup k objektu (např. stránce). 
		-- Hodnoty: D (Developer), S (Sysadmin), A (Orgadmin), U (User). 
		-- Výchozí 'S' zajišťuje Deny-by-Default (omezení na nejvyšší roli při opomenutí).
		system_role varchar(1) NOT NULL DEFAULT 'S',

		CONSTRAINT pk_meta_object PRIMARY KEY (uuid),
		CONSTRAINT chk_meta_object_type CHECK (object_type IN ('T', 'V', 'F', 'P', 'G', 'C', 'M'))
	);
	PRINT 'Tabulka meta_object byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro upgrady existujících databází
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_object', 'system_role', 'varchar(1) NOT NULL DEFAULT ''S''';
EXEC p_create_missing_column 'meta_object', 'editor_note', 'varchar(max) NULL';
EXEC p_create_missing_column 'meta_object', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_object', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'meta_object', 
	@iname = 'uq_meta_object_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'meta_object', 
	@iname = 'uq_meta_object_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Vyčištění zastaralých systémových záznamů (fráze 'G' a stránky bez prefixu 'page_')
-- -----------------------------------------------------------------------------
DELETE FROM meta_object
WHERE object_owner = 0x00
  AND (
	object_type = 'G'
	OR (
		object_type = 'P'
		AND builtin_code IN (
			'excel_reader', 'main', 'meta_class', 'meta_column',
			'organization_licence', 'org_users', 'change_user_context', 'logout'
		)
	)
  );
GO

/* =============================================================================
 * REGISTRACE STRÁNKY EXCEL READER A SYSTÉMOVÝCH OBJEKTŮ DO METADAT
 * Účel: Zajišťuje, aby všechny systémové stránky a UI třídy měly v meta_object
 *       jak hlavní 'A' záznam, tak symetrický 'L' záznam.
 * ============================================================================= */
DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @pages TABLE (builtin_code varchar(80), caption varchar(200), description varchar(max), system_role varchar(1));
INSERT INTO @pages (builtin_code, caption, description, system_role) VALUES 
('', 'Globální fráze systému', 'Bezejmenný kontejner pro celosystémové textové fráze a sdílené popisky', 'U'),
('abstract_page', 'Základní šablona stránky', 'Abstraktní předek všech stránek zajišťující hlavičku, kontext a ochranu formulářů', 'U'),
('abstract_page_master_detail', 'Šablona Master-Detail', 'Abstraktní dvoupanelová šablona pro správu entit', 'U'),
('abstract_button', 'Komponenta tlačítka', 'Základní třída pro vykreslování tlačítek s ikonou a tooltipem', 'U'),
('user_context', 'Kontextový panel uživatele', 'Horní lišta s informacemi o přihlášeném uživateli, roli a volbou jazyka', 'U'),
('menu_manager', 'Správce navigace', 'Třída pro sestavení a vykreslení drobečkové navigace a menu', 'U'),
('entity_manager', 'Správce logických entit', 'Dynamický generátor SQL dotazů, seznamů a formulářů podle metadat', 'U'),
('page_main', 'Hlavní panel', 'Úvodní rozcestník aplikace po přihlášení', 'U'),
('page_meta_class', 'Logické třídy (Objekty)', 'Správa logických entit, jejich vlastností a překladů', 'U'),
('page_meta_column', 'Sloupce metadat', 'Správa definic sloupců, formulářových prvků a překladů', 'U'),
('page_meta_phrase', 'Textové fráze a překlady', 'Správa textových frází, tlačítek a jazykových mutací', 'U'),
('page_approval', 'Schvalování změn', 'Přehled, porovnání a schvalování navržených záznamů napříč třídami', 'U'),
('page_organization_licence', 'Správa licencí organizací', 'Evidence a aktivace licencí pro jednotlivé tenanty', 'S'),
('page_org_users', 'Uživatelé organizace', 'Správa uživatelských účtů a oprávnění v rámci organizace', 'A'),
('page_excel_reader', 'Import dat z Excelu', 'Nástroj pro hromadný import a export datových struktur', 'S'),
('page_change_user_context', 'Změna kontextu uživatele', 'Přepínání aktivní organizace, aplikační role a žádosti o přístup', 'U'),
('page_login', 'Přihlášení do systému', 'Přihlašovací obrazovka s podporou lokální autentizace a SSO', 'U'),
('page_password_reset', 'Obnova hesla', 'Stránka pro vyžádání a nastavení nového hesla pomocí tokenu', 'U'),
('page_google_callback', 'Google SSO Callback', 'Koncový bod pro ověření identity přes Google OAuth', 'U'),
('page_logout', 'Odhlášení ze systému', 'Ukončení relace a zneplatnění přihlašovacích tokenů', 'U');

-- 1. Idempotentní vložení hlavních 'A' záznamů
INSERT INTO meta_object (
	uuid, object_owner, original, record_type, approval_status, [language],
	object_type, builtin_code, system_role, caption, description, module
)
SELECT 
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	@sys_owner,
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	'A', 'A', 'cs', 'P', p.builtin_code, p.system_role, p.caption, p.description, ''
FROM @pages p
WHERE NOT EXISTS (
	SELECT 1 FROM meta_object mo 
	WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code)
	  AND mo.record_type = 'A' AND mo.object_owner = @sys_owner AND mo.removed = 0
);

-- 2. Idempotentní vložení symetrických 'L' záznamů pro výchozí jazyk ('cs')
INSERT INTO meta_object (
	uuid, object_owner, original, record_type, approval_status, [language],
	object_type, builtin_code, system_role, caption, description, module
)
SELECT 
	NEWID(),
	@sys_owner,
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	'L', 'A', 'cs', 'P', p.builtin_code, p.system_role, p.caption, p.description, ''
FROM @pages p
WHERE NOT EXISTS (
	SELECT 1 FROM meta_object mo 
	WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code)
	  AND mo.record_type = 'L' AND mo.[language] = 'cs' AND mo.object_owner = @sys_owner AND mo.removed = 0
);

-- 3. Idempotentní sjednocení system_role u stávajících systémových záznamů
UPDATE mo
SET mo.system_role = p.system_role
FROM meta_object mo
JOIN @pages p ON p.builtin_code = mo.builtin_code
WHERE mo.object_owner = @sys_owner
  AND mo.object_type = 'P'
  AND mo.record_type IN ('A', 'L')
  AND mo.system_role <> p.system_role;
GO