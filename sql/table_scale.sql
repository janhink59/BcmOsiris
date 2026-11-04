/* =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: table_scale.sql
 * Tabulka: scale (Definice hodnotících škál CRMM)
 * Popis:   Uchovává definice hodnotících škál pro jednotlivé veličiny CRMM
 *          (scale_type: THREAT, VULNERABILITY, IMPACT, RISK).
 *          Při založení nové škály se podle sloupce initial_levels (n >= 2)
 *          automaticky vygeneruje n rovnoměrných stupňů v tabulce scale_value
 *          v procentuálním intervalu 0 až 100 %.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - Jednotlivé stupně škály jsou uloženy v tabulce scale_value
 *            (scale_value.scale -> scale.original).
 *          - Spravována stránkou page_scale.php.
 * ============================================================================= */

IF OBJECT_ID('scale') IS NULL
BEGIN
	CREATE TABLE scale (
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
		-- Identifikace a prezentační vlastnosti škály
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Unikátní kód škály (automaticky odvozený z názvu)
		external_code varchar(40) NOT NULL DEFAULT '',     -- Kód pro párování s externími systémy
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název škály (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Metodické a řídicí vlastnosti škály
		-- ---------------------------------------------------------------------
		scale_type varchar(20) NOT NULL DEFAULT 'IMPACT',  -- Veličina: THREAT, VULNERABILITY, IMPACT, RISK
		priority smallint NOT NULL DEFAULT 0,              -- 0 = Primární škála pro zadávání, > 0 = Přepočtová škála pro reporty
		initial_levels tinyint NOT NULL DEFAULT 4,         -- Výchozí počet automaticky generovaných stupňů při založení (2..20)
		is_default bit NOT NULL DEFAULT 0,                 -- 1 = Výchozí škála pro daný scale_type
		sort_code varchar(20) NOT NULL DEFAULT '',         -- Pořadí škály v seznamech

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_scale PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka scale byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'scale', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'scale', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'scale', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale', 'scale_type', 'varchar(20) NOT NULL DEFAULT ''IMPACT''';
EXEC p_create_missing_column 'scale', 'priority', 'smallint NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'scale', 'initial_levels', 'tinyint NOT NULL DEFAULT 4';
EXEC p_create_missing_column 'scale', 'is_default', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'scale', 'sort_code', 'varchar(20) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'uq_scale_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'uq_scale_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'uq_scale_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'ix_scale_type_priority', 
	@colnames = 'scale_type, priority, sort_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO