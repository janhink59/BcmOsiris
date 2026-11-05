/* =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: table_countermeasure_state.sql
 * Tabulka: countermeasure_state (Číselník stavů protiopatření CRMM)
 * Popis:   Plochý (nehierarchický) číselník stavů implementace protiopatření
 *          (např. Navrženo, V realizaci, Zavedeno, Ověřeno, Neaplikovatelné).
 *          Obsahuje dva faktory typu decimal(9,4):
 *          - reduction_factor: váha započtení redukčního faktoru opatření v tomto stavu,
 *          - risk_factor: váha započtení prahového rizikového faktoru neimplementovaného opatření.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - Odkazována z implementací opatření (countermeasure_implementation).
 *          - Spravována stránkou page_countermeasure_state.php.
 * ============================================================================= */

IF OBJECT_ID('countermeasure_state') IS NULL
BEGIN
	CREATE TABLE countermeasure_state (
		-- ---------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- ---------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,
		original uuid NOT NULL DEFAULT 0x00,
		record_type varchar(1) NOT NULL DEFAULT 'A',
		approval_status varchar(1) NOT NULL DEFAULT 'A',
		draft_author uuid NOT NULL DEFAULT 0x00,
		approval_note varchar(max) NOT NULL DEFAULT '',
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		is_template bit NOT NULL DEFAULT 0,
		template uuid NULL,
		import_origin varchar(255) NULL,

		-- ---------------------------------------------------------------------
		-- Auditní stopy
		-- ---------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- ---------------------------------------------------------------------
		-- Identifikace a prezentační vlastnosti stavu
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód stavu (automaticky odvozený z názvu)
		external_code varchar(40) NOT NULL DEFAULT '',     -- Kód pro párování s externími systémy
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název stavu (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Výpočtové faktory stavu a řazení
		-- ---------------------------------------------------------------------
		sort_code varchar(20) NOT NULL DEFAULT '',         -- Pořadí stavu v číselníku
		is_default bit NOT NULL DEFAULT 0,                 -- 1 = Výchozí stav při založení implementace opatření
		reduction_factor decimal(9,4) NOT NULL DEFAULT 0.0000, -- Faktor uplatnění redukce rizika v tomto stavu (0 až 100 %)
		risk_factor decimal(9,4) NOT NULL DEFAULT 0.0000,      -- Faktor uplatnění prahu rizika při neimplementaci (0 až 100 %)

		-- ---------------------------------------------------------------------
		-- Vizuální atributy a ochrana
		-- ---------------------------------------------------------------------
		color_code varchar(20) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_countermeasure_state PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka countermeasure_state byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'countermeasure_state', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'countermeasure_state', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_state', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'countermeasure_state', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_state', 'sort_code', 'varchar(20) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_state', 'is_default', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'countermeasure_state', 'reduction_factor', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'countermeasure_state', 'risk_factor', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'countermeasure_state', 'color_code', 'varchar(20) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_state', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'countermeasure_state', 
	@iname = 'uq_countermeasure_state_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'countermeasure_state', 
	@iname = 'uq_countermeasure_state_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'countermeasure_state', 
	@iname = 'uq_countermeasure_state_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'countermeasure_state', 
	@iname = 'ix_countermeasure_state_sort', 
	@colnames = 'sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO