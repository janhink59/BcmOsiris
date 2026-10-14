/* =============================================================================
 * Verze: 2026-10-14 12:30
 * Soubor: table_meta_object.sql
 * Tabulka: meta_object
 * Popis:   Uchovává metadata fyzických objektů v databázi (tabulky, views, funkce, stránky).
 * Vazby:   - Slouží jako fyzický podklad (storage_object) pro logické třídy v meta_class.
 *          - Záznamy typu 'P' (PHP Page) jsou odkazovány z meta_menu.target_object
 *            a slouží k řízení přístupu přes sloupec system_role.
 *          - Záznamy typu 'G' (Global Phrase) uchovávají celosystémové textové fráze.
 *          - Plněno automaticky procedurou p_fix_meta_column (typy T, V, F, C)
 *            a hromadným importem z Excelu přes proceduru p_xlsx_meta_object (typy P, G, M).
 * Změny:   - Odstraněny sloupce is_final a is_protected (ochrana je v meta_class).
 *          - Odstraněn sloupec column_ancestor (přesunut do meta_class).
 *          - Prezentační texty změněny na NULLable (primární zdroj je nově meta_class).
 *          - Přidán sloupec import_origin pro evidenci původu záznamu z importu (Měkký audit).
 *          - 2026-10-09: Přidán sloupec system_role pro základní řízení přístupu.
 *          - 2026-10-14: Přidán sloupec editor_note pro kontext k překladům pomocí AI.
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
		record_type varchar(1) NOT NULL DEFAULT 'A',       -- 'A' = aktuálně schválený, 'L' = jazyková verze, 'H' = historie (audit).
		approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stavy schvalování v rámci SSC ('D', 'W', 'S', 'A', 'R', 'C', 'I').
		inactive bit NOT NULL DEFAULT 0,                   -- Příznak deaktivace (používá se např. u systémových záznamů místo fyzického smazání).
		removed bit NOT NULL DEFAULT 0,                    -- Příznak odstranění.
		language varchar(2) NOT NULL DEFAULT 'cs',         -- Jazyková mutace (využito pro record_type = 'L').
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
GO
/* =============================================================================
 * REGISTRACE STRÁNKY EXCEL READER DO METADAT
 * Účel: Zajišťuje, aby nová stránka pro import byla viditelná v dynamickém menu.
 * ============================================================================= */
DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
DECLARE @orig_guid uniqueidentifier = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'excel_reader');

IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @orig_guid AND object_owner = 0x00 AND record_type = 'A')
BEGIN
	INSERT INTO meta_object (
		uuid, object_owner, original, record_type, approval_status,
		object_type, builtin_code, system_role, caption, description, module
	) VALUES (
		@orig_guid, 0x00, @orig_guid, 'A', 'A',
		'P', 'excel_reader', 'S', 'Import dat z Excelu', 'Nástroj pro hromadný import datových struktur', ''
	);
	PRINT 'Stránka excel_reader byla zaregistrována do meta_object.';
END
GO
-- Registrace chybějících fyzických stránek do metadat (nutné pro bezpečnostní validaci menu)
DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @pages TABLE (builtin_code varchar(80), caption varchar(200), system_role varchar(1));
INSERT INTO @pages (builtin_code, caption, system_role) VALUES 
('main', 'Hlavní panel', 'U'),
('meta_class', 'Logické třídy (Objekty)', 'S'),
('meta_column', 'Sloupce metadat', 'S'),
('organization_licence', 'Správa licencí organizací', 'S'),
('org_users', 'Uživatelé organizace', 'A'),
('change_user_context', 'Změna kontextu uživatele', 'U'),
('logout', 'Odhlášení ze systému', 'U');

INSERT INTO meta_object (
	uuid, object_owner, original, record_type, approval_status,
	object_type, builtin_code, system_role, caption, module
)
SELECT 
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	@sys_owner,
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	'A', 'A', 'P', p.builtin_code, p.system_role, p.caption, ''
FROM @pages p
WHERE NOT EXISTS (
	SELECT 1 FROM meta_object mo 
	WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code)
	  AND mo.record_type = 'A' AND mo.object_owner = @sys_owner
);
GO