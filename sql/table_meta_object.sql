/* =============================================================================
 * Tabulka: meta_object
 * Popis:   Uchovává metadata objektů v databázi a aplikaci.
 * ============================================================================= */

-- Pokud tabulka existuje, ale constraint chk_meta_object_type ještě neobsahuje typ 'C', tabulku rovnou dropneme
IF OBJECT_ID('meta_object') IS NOT NULL 
	AND NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'chk_meta_object_type' AND definition LIKE '%''C''%')
BEGIN
	EXECUTE dropni 'meta_object';
END
GO

IF OBJECT_ID('meta_object') IS NULL
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

	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,            -- Načítáno autonovně z dbsession.user_access_uuid.
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,           -- Načítáno autonovně z dbsession.user_access_uuid.

	-- -------------------------------------------------------------------------
	-- Specifické atributy objektu
	-- -------------------------------------------------------------------------
	object_type varchar(1) NOT NULL,                   -- T=Table, V=View, F=Function, P=PHP Page, G=Global Phrase, C=Column Ancestor, M=Module
	builtin_code varchar(80) NOT NULL,                 -- Fyzický název objektu v DB (např. název tabulky, view) nebo kód.
	caption varchar(200) NOT NULL,                     -- Zobrazovaný název (lokalizovatelný).
	caption_plural varchar(200) NOT NULL,              -- Množné číslo názvu.
	description varchar(max) NOT NULL DEFAULT '',      -- Podrobnější interní popis objektu a jeho účelu.
	helptext varchar(max) NOT NULL,                    -- Text nápovědy určený pro UI.
	
	module varchar(80) NOT NULL DEFAULT '',            -- Modul, ke kterému objekt patří (odkaz na builtin_code u object_type = 'M').

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur a limitace overridu
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,                   -- 1 = Zcela zakazuje tenantům vytvořit override záznamu (typ 'A'). Povoleny jen překlady ('L').
	is_protected bit NOT NULL DEFAULT 0,               -- 1 = Povoluje tenantům vytvořit override, ale omezuje editaci v PHP výhradně na vizuální vlastnosti.

	CONSTRAINT pk_meta_object PRIMARY KEY (uuid),
	CONSTRAINT chk_meta_object_type CHECK (object_type IN ('T', 'V', 'F', 'P', 'G', 'C', 'M'))
);
GO