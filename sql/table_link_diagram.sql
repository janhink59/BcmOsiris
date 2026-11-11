/* =============================================================================
 * Verze: 2026-11-11 21:30
 * Soubor: table_link_diagram.sql
 * Tabulka: link_diagram (Schémata / diagramy heterogenních sítí vztahů CRMM)
 * Popis:   Uchovává definice orientovaných schémat (diagramů) sítě pro výpočet
 *          cest přenosu rizik, dopadů a závislostí napříč různými třídami aktiv,
 *          organizačními jednotkami a personálem.
 *          Jednotlivé orientované vztahy (meta_link_def) zařazené do diagramu
 *          se propojují vazbou v tabulce link (vztah diagram_includes_link_def)
 *          a procedura dbo.p_rebuild_link_diagram z nich automaticky generuje
 *          nepřímé vztahy do meta_link_def (is_derived = 1, diagram_uuid)
 *          a nepřímé vazby uzlů do link (is_derived = 1, diagram_uuid).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - Spravována stránkou page_link_diagram.php.
 * ============================================================================= */

IF OBJECT_ID('link_diagram') IS NULL
BEGIN
	CREATE TABLE link_diagram (
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
		-- Identifikace a prezentační vlastnosti diagramu sítě
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Unikátní kód diagramu v snake_case
		external_code varchar(40) NOT NULL DEFAULT '',     -- Externí kód
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název diagramu (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',         -- Zkratka diagramu
		description_text varchar(max) NOT NULL DEFAULT '', -- Podrobný popis účelu sítě (is_html = 1)
		help_text varchar(max) NOT NULL DEFAULT '',        -- Metodická nápověda (is_html = 1)
		svg_icon varchar(max) NOT NULL DEFAULT '',         -- Vektorová ikona SVG
		sort_code varchar(20) NOT NULL DEFAULT '',         -- Pořadí v seznamech

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_link_diagram PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka link_diagram byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'link_diagram', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'link_diagram', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link_diagram', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'link_diagram', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link_diagram', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link_diagram', 'sort_code', 'varchar(20) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link_diagram', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'link_diagram', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'link_diagram', 
	@iname = 'uq_link_diagram_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'link_diagram', 
	@iname = 'uq_link_diagram_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'link_diagram', 
	@iname = 'uq_link_diagram_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO