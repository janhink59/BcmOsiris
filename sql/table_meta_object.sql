/* =============================================================================
 * Tabulka: meta_object
 * Popis:   Uchovává metadata fyzických objektů v databázi (tabulky, views, funkce, stránky).
 * Změny:   - Odstraněny sloupce is_final a is_protected (ochrana je v meta_class).
 *          - Odstraněn sloupec column_ancestor (přesunut do meta_class).
 *          - Prezentační texty změněny na NULLable (primární zdroj je nově meta_class).
 *          - Přidán sloupec import_origin pro evidenci původu záznamu z importu (Měkký audit).
 *          - 2026-10-09: Přidán sloupec system_role pro základní řízení přístupu.
 * ============================================================================= */

-- Idempotentní odstranění staré verze (pokud neobsahuje poslední významnou změnu)
IF NOT EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_object' AND colname='import_origin')
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
GO