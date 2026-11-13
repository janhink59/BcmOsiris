/* =============================================================================
 * Verze: 2026-11-13 18:10
 * Soubor: table_threat.sql
 * Tabulka: threat (Katalog hrozeb CRMM)
 * Popis:   Hierarchický katalog hrozeb (např. Fyzické hrozby -> Požár,
 *          Technické hrozby -> Výpadek elektřiny).
 *          Obsahuje výchozí velikost hrozby (default_threat_score) z intervalu
 *          hodnocení hrozeb.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - parent_uuid ukazuje na nadřízenou hrozbu/složku (threat.original).
 *          - Odkazována ze scénářů (scenario.threat_uuid) a z tabulky link
 *            (vazby M:N na třídy aktiv asset_class a dopady impact).
 *          - Spravována stromovou stránkou page_threat.php.
 * Změny:
 * - 2026-11-13 18:10: Doplněna registrace třídy a sloupců do sysinit_class
 *   a sysinit_column.
 * ============================================================================= */

IF OBJECT_ID('threat') IS NULL
BEGIN
	CREATE TABLE threat (
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
		caption varchar(200) NOT NULL DEFAULT '',          -- Název hrozby (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Stromová struktura a specifické sloupce pro hrozby
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená položka v hierarchii hrozeb (threat.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncová hrozba, 0 = Složka (skupina hrozeb)
		default_threat_score decimal(9,4) NULL,            -- Výchozí velikost hrozby (skóre z intervalu hodnocení hrozeb)
		editor_role_uuid uuid NULL,                        -- Role pro editaci (dědí se do podřízených)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_threat PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka threat byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'threat', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'threat', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'threat', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'threat', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'threat', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'threat', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'threat', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'threat', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'threat', 'default_threat_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'threat', 'editor_role_uuid', 'uuid NULL';
EXEC p_create_missing_column 'threat', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'threat', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'threat', 
	@iname = 'uq_threat_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'threat', 
	@iname = 'uq_threat_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'threat', 
	@iname = 'uq_threat_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'threat', 
	@iname = 'ix_threat_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'threat';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('threat','cs','T','threat','Hrozba','Katalog hrozeb','Hierarchický katalog hrozeb a jejich výchozích hodnot skóre v modulu CRMM.','Slouží k evidenci přírodních, technických, procesních a úmyslných hrozeb působících na aktiva.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('threat','en','Threat','Threat Catalog','Hierarchical catalog of threats and their default score values in the CRMM module.','Used to manage natural, technical, operational, and intentional threats affecting assets.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'threat';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		referenced_class_code
	) VALUES
	('threat','default_threat_score','cs','Výchozí skóre hrozby (default_threat_score)','Výchozí hodnocení / skóre hrozby (0–100 %)','Výchozí skóre','Přednastavená výchozí hodnota skóre velikosti hrozby (v intervalu 0 až 100 %) pro hodnocení scénářů.',''),
	('threat','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','threat');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('threat','default_threat_score','en','Default Threat Score (default_threat_score)','Default Threat Evaluation / Score (0–100%)','Default Score','Preconfigured default threat severity score (0 to 100%) used in scenario assessments.');
END
GO