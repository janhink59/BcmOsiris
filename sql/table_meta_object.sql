/* =============================================================================
 * Tabulka: meta_object
 * Popis:   Uchovává metadata fyzických objektů v databázi (tabulky, views, funkce).
 * Změny:   - Odstraněny sloupce is_final a is_protected, protože fyzická vrstva 
 *            je z principu vždy chráněna před tenant overridy. Ochrana se 
 *            přesunula do logické vrstvy (meta_class).
 * ============================================================================= */

-- Idempotentní odstranění staré verze (pokud obsahuje zrušené sloupce)
IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_object' AND colname = 'is_final')
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
	column_ancestor uuid null,                         -- Odkaz na jiný meta_object, ze kterého se dědí stejnojmenné sloupce

	CONSTRAINT pk_meta_object PRIMARY KEY (uuid),
	CONSTRAINT chk_meta_object_type CHECK (object_type IN ('T', 'V', 'F', 'P', 'G', 'C', 'M'))
);
GO