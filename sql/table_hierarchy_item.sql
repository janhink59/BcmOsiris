/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: table_hierarchy_item.sql
 * Tabulka: hierarchy_item (Uzly a položky sekundárních hierarchií, číselníků a tagů)
 * Popis:   Uchovává veškeré uzly (vnitřní složky is_leaf = 0 i koncové listy
 *          is_leaf = 1) všech sekundárních hierarchií, prostých číselníků
 *          a stromů štítků (tagů) definovaných v tabulce hierarchy.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - Sloupec hierarchy ukazuje na hierarchy.original.
 *          - Sloupec parent_uuid ukazuje na nadřízený uzel hierarchy_item.original
 *            v rámci téže hierarchie.
 *          - Vazby mezi položkami hierarchy_item a cílovými entitami CRMM se
 *            ukládají do univerzální tabulky link (včetně materializace dědění
 *            přes ancestor_link).
 * Změny:   - 2026-11-13 17:00: Doplněna registrace třídy a sloupců do sysinit_class
 *            a sysinit_column.
 *          - 2026-11-04 15:15: Doplněn sloupec is_default bit NOT NULL DEFAULT 0.
 * ============================================================================= */

IF OBJECT_ID('hierarchy_item') IS NULL
BEGIN
	CREATE TABLE hierarchy_item (
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
		-- Zařazení do hierarchie a stromová struktura
		-- ---------------------------------------------------------------------
		hierarchy uuid NOT NULL,                           -- Odkaz na definici hierarchie (hierarchy.original)
		parent_uuid uuid NULL,                             -- Nadřízený uzel v téže hierarchii (hierarchy_item.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncový uzel, 0 = Vnitřní uzel (složka)
		is_default bit NOT NULL DEFAULT 0,                 -- 1 = Výchozí položka při zakládání nového záznamu

		-- ---------------------------------------------------------------------
		-- Prezentační a identifikační vlastnosti uzlu
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód uzlu v rámci dané hierarchie
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název uzlu (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(40) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',
		color_code varchar(20) NOT NULL DEFAULT '',

		CONSTRAINT pk_hierarchy_item PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka hierarchy_item byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'hierarchy_item', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'hierarchy_item', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'hierarchy_item', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'hierarchy_item', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'hierarchy_item', 'color_code', 'varchar(20) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'hierarchy_item', 'is_default', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a rychlého průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'hierarchy_item', 
	@iname = 'uq_hierarchy_item_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy_item', 
	@iname = 'uq_hierarchy_item_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy_item', 
	@iname = 'uq_hierarchy_item_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy_item', 
	@iname = 'ix_hierarchy_item_tree', 
	@colnames = 'hierarchy, parent_uuid, sort_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'hierarchy_item';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('hierarchy_item','cs','T','hierarchy_item','Položka sekundární hierarchie','Položky sekundární hierarchie','Uzly a koncové položky jednotlivých sekundárních hierarchií, klasifikačních číselníků a štítků.','Stromový seznam hodnot patřících do vybrané sekundární hierarchie nebo sady štítků.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('hierarchy_item','en','Secondary Hierarchy Item','Secondary Hierarchy Items','Nodes and leaf items of individual secondary hierarchies, classification codetables, and tag sets.','Tree list of values belonging to the selected secondary hierarchy or tag set.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'hierarchy_item';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		is_mandatory, referenced_class_code
	) VALUES
	('hierarchy_item','hierarchy','cs','Nadřazená hierarchie (hierarchy)','Sekundární hierarchie / sada štítků','Hierarchie','Odkaz na definici sekundární hierarchie nebo sady štítků (tagů) v tabulce hierarchy.',1,'hierarchy'),
	('hierarchy_item','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).',0,'hierarchy_item');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('hierarchy_item','hierarchy','en','Parent Hierarchy (hierarchy)','Secondary Hierarchy / Tag Set','Hierarchy','Reference to the secondary hierarchy or tag set definition in the hierarchy table.');
END
GO