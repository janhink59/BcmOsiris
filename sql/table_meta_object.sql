/* =============================================================================
 * Verze: 2026-10-24 13:15
 * Soubor: table_meta_object.sql
 * Tabulka: meta_object
 * Popis:   DDL definice tabulky pro metadata fyzických objektů v databázi
 *          (tabulky, views, funkce, stránky a systémové kontejnery).
 *          Prvotní naplnění systémových záznamů typu 'P' je vyčleněno do
 *          samostatného skriptu fillup_meta_object.sql.
 * Vazby:   - Slouží jako fyzický podklad (storage_object) pro logické třídy v meta_class.
 *          - Záznamy typu 'P' (PHP Page / třída) jsou odkazovány z meta_menu.target_object,
 *            slouží k řízení přístupu přes sloupec system_role a představují platné
 *            zdrojové objekty (source_code) pro textové fráze v tabulce meta_phrase.
 *          - Plněno skriptem fillup_meta_object.sql, procedurou p_fix_meta_column
 *            (typy T, V, F, C) a importy p_xlsx_meta_object / p_csv_import_metadata.
 * Změny:   - 2026-10-24 13:15: Oddělení DDL struktury od datového plnění
 *            (plnění přesunuto do souboru fillup_meta_object.sql).
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
-- Indexy pro zajištění RAC a SSC architektury
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

EXEC sp_create_index 
	@tname = 'meta_object', 
	@iname = 'uq_meta_object_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO