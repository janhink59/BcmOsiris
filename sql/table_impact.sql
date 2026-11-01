/* =============================================================================
 * Verze: 2026-11-01 18:00
 * Soubor: table_impact.sql
 * Tabulka: impact (Katalog dopadů CRMM)
 * Popis:   Hierarchický číselník dopadů kombinující druhy a oblasti dopadu
 *          (např. Výpadek služeb -> do 2H, Materiální škoda -> Přímá finanční).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - parent_uuid ukazuje na nadřízený dopad/složku (impact.original).
 *          - Vazby M:N na scénáře (scenario) a hrozby (threat) se ukládají
 *            do tabulky link.
 *          - Spravována stromovou stránkou page_impact.php.
 * ============================================================================= */

IF OBJECT_ID('impact') IS NULL
BEGIN
	CREATE TABLE impact (
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
		-- Společné identifikační a prezentační vlastnosti
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód pro deterministický originál (povinný v 0x00 a šablonách)
		caption varchar(200) NOT NULL DEFAULT '',          -- Název dopadu (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Stromová struktura a specifické sloupce pro dopady
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená položka v hierarchii dopadů (impact.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncový dopad, 0 = Složka (kategorie dopadů)
		editor_role_uuid uuid NULL,                        -- Role pro editaci (dědí se do podřízených)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_impact PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka impact byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'impact', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'impact', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'impact', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'impact', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'impact', 'editor_role_uuid', 'uuid NULL';
EXEC p_create_missing_column 'impact', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'impact', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'impact', 
	@iname = 'uq_impact_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'impact', 
	@iname = 'uq_impact_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'impact', 
	@iname = 'uq_impact_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'impact', 
	@iname = 'ix_impact_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO