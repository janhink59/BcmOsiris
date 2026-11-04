/* =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: table_scale_value.sql
 * Tabulka: scale_value (Stupně hodnotících škál CRMM v intervalu 0 až 100 %)
 * Popis:   Uchovává jednotlivé stupně hodnotících škál definovaných v tabulce scale.
 *          Neobsahuje sloupec sort_code – stupně jsou vždy tříděny vzestupně
 *          podle dolní prahové hodnoty threshold_value (0 až 100 %) a spolu se
 *          score_value (0 až 100 %) musí tvořit monotónně rostoucí řadu.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - Sloupec scale ukazuje na scale.original.
 *          - Spravována stránkou page_scale_value.php.
 * ============================================================================= */

IF OBJECT_ID('scale_value') IS NULL
BEGIN
	CREATE TABLE scale_value (
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
		-- Příslušnost ke škále a identifikace stupně
		-- ---------------------------------------------------------------------
		scale uuid NOT NULL,                               -- Odkaz na definici škály (scale.original)
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód stupně v rámci škály (např. 'l1', 'l2'...)
		external_code varchar(40) NOT NULL DEFAULT '',     -- Kód pro párování s externími systémy
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název stupně (např. 'Nízká', 'Kritická')
		shortname varchar(40) NOT NULL DEFAULT '',         -- Zkratka stupně do matic a přehledů (např. 'L', 'C')
		description_text varchar(max) NOT NULL DEFAULT '', -- Metodický popis stupně (is_html = 1)
		help_text varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Výpočtové hodnoty v procentuálním intervalu 0.0000 až 100.0000 %
		-- ---------------------------------------------------------------------
		threshold_value decimal(9,4) NOT NULL DEFAULT 0.0000, -- Dolní práh intervalu stupně (0 až 100 %), určuje pořadí
		score_value decimal(9,4) NOT NULL DEFAULT 0.0000,     -- Hodnota skóre stupně pro výpočty (0 až 100 %)
		is_default bit NOT NULL DEFAULT 0,                    -- 1 = Výchozí předvybraný stupeň škály

		-- ---------------------------------------------------------------------
		-- Vizuální atributy a ochrana
		-- ---------------------------------------------------------------------
		color_code varchar(20) NOT NULL DEFAULT '',        -- Barva stupně (semafor)
		svg_icon varchar(max) NOT NULL DEFAULT '',
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_scale_value PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka scale_value byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'scale_value', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'scale_value', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale_value', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'scale_value', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale_value', 'threshold_value', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scale_value', 'score_value', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scale_value', 'is_default', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'scale_value', 'color_code', 'varchar(20) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale_value', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a unikátnosti prahů ve škále
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'scale_value', 
	@iname = 'uq_scale_value_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale_value', 
	@iname = 'uq_scale_value_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale_value', 
	@iname = 'uq_scale_value_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale_value', 
	@iname = 'ix_scale_value_lookup', 
	@colnames = 'scale, object_owner, threshold_value', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO