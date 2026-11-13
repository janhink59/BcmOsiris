/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: table_hierarchy.sql
 * Tabulka: hierarchy (Registr sekundárních hierarchií a stromových štítků / tagů)
 * Popis:   Uchovává definice dalších hierarchických struktur a štítků (tagů),
 *          které poskytují alternativní pohledy, klasifikaci a filtrování
 *          nad záznamy v databázi.
 *          Samotná tabulka je rovněž hierarchického typu (parent_uuid, sort_code,
 *          is_leaf). Její jednotlivé položky (uzly) jsou uloženy v tabulce
 *          hierarchy_item.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - Každá koncová hierarchie (is_leaf = 1) se přes doménový trigger
 *            trg_hierarchy_sync_meta_class volající proceduru
 *            dbo.p_sync_hierarchy_to_meta_class (definovanou v p_fix_meta_column.sql)
 *            automaticky promítá jako logická třída do tabulky meta_class
 *            (s úložným objektem hierarchy_item), včetně symetrických 'L' záznamů.
 *          - Povolené vazby na systémové třídy se evidují v meta_link_def a
 *            aplikovatelnost na uživatelské třídy aktiv (asset_class) v tabulce link.
 * Změny:   - 2026-11-13 17:00: Doplněna registrace třídy a sloupců do sysinit_class
 *            a sysinit_column (včetně specifického kontextového popisku pro is_leaf).
 *          - 2026-11-01 11:45: Duplicitní SQL kód v triggeru trg_hierarchy_sync_meta_class
 *            nahrazen voláním společné procedury dbo.p_sync_hierarchy_to_meta_class.
 *          - 2026-10-31 11:00: Trigger trg_hierarchy_sync_meta_class upraven tak,
 *            aby do meta_class promítal pouze koncové hierarchie (is_leaf = 1),
 *            složky (is_leaf = 0) v meta_class zneplatnil (removed = 1) a plně
 *            synchronizoval i jazykové 'L' záznamy.
 * ============================================================================= */

IF OBJECT_ID('hierarchy') IS NULL
BEGIN
	CREATE TABLE hierarchy (
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
		-- Společné prezentační a identifikační vlastnosti
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Unikátní kód hierarchie (promítá se jako class_name do meta_class)
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název hierarchie (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Hierarchické uspořádání samotných hierarchií
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená položka v registru hierarchií (hierarchy.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncová hierarchie, 0 = Složka hierarchií

		-- ---------------------------------------------------------------------
		-- Výchozí pravidla pro navazování položek této hierarchie (meta_link_def)
		-- ---------------------------------------------------------------------
		multiple bit NOT NULL DEFAULT 1,                   -- 1 = Cílový záznam může mít vazbu na více položek této hierarchie
		leaf_only bit NOT NULL DEFAULT 1,                  -- 1 = Cílový záznam smí být vázán pouze na koncový uzel (is_leaf = 1)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_hierarchy PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka hierarchy byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'hierarchy', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'hierarchy', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'hierarchy', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'hierarchy', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'hierarchy', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'hierarchy', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'hierarchy', 'multiple', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'hierarchy', 'leaf_only', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'hierarchy', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'uq_hierarchy_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'uq_hierarchy_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'uq_hierarchy_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'ix_hierarchy_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Doménový trigger: Automatické promítnutí koncové hierarchie (is_leaf = 1)
--                   do tabulky meta_class přes dbo.p_sync_hierarchy_to_meta_class
-- Poznámka: Prefix trg_ (nikoliv trgo_) chrání trigger před smazáním v generate_trgo.sql
-- -----------------------------------------------------------------------------
IF OBJECT_ID('trg_hierarchy_sync_meta_class', 'TR') IS NOT NULL
	DROP TRIGGER trg_hierarchy_sync_meta_class;
GO

CREATE TRIGGER trg_hierarchy_sync_meta_class
ON hierarchy
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	IF OBJECT_ID('dbo.p_sync_hierarchy_to_meta_class', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_hierarchy_to_meta_class @fix_childless_folders = 0;
	END
END;
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'hierarchy';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('hierarchy','cs','T','hierarchy','Sekundární hierarchie / sada štítků','Sekundární hierarchie a štítky','Registr uživatelských klasifikačních stromů, výčtových číselníků a sad štítků (tagů).','Každá koncová hierarchie (is_leaf = 1) představuje samostatný klasifikační číselník nebo strom štítků.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('hierarchy','en','Secondary Hierarchy / Tag Set','Secondary Hierarchies & Tags','Registry of custom classification trees, enumerated codetables, and tag sets.','Each leaf entry (is_leaf = 1) represents a standalone classification codetable or tag tree.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'hierarchy';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext, referenced_class_code) VALUES
	('hierarchy','is_leaf','cs','Samostatná hierarchie / sada štítků (is_leaf)','Samostatná hierarchie (is_leaf)','Hierarchie','Zaškrtněte (1) u koncové definice hierarchie nebo sady štítků, do které budete vkládat položky. Odškrtněte (0) pouze u nadřazené organizační složky v tomto registru.',''),
	('hierarchy','leaf_only','cs','Pouze koncové uzly (leaf_only)','Vazby pouze na koncové uzly (listy)','Jen listy','Určuje, zda lze cílové záznamy navazovat výhradně na koncové uzly (is_leaf = 1) této hierarchie.',''),
	('hierarchy','multiple','cs','Vícenásobné přiřazení (multiple)','Povolit přiřazení více položek','Více položek','Určuje, zda cílový záznam může mít navázáno více položek z této hierarchie současně.',''),
	('hierarchy','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','hierarchy');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('hierarchy','is_leaf','en','Standalone Hierarchy / Tag Set (is_leaf)','Standalone Hierarchy (is_leaf)','Hierarchy','Check (1) for a terminal hierarchy or tag set definition into which you will insert items. Uncheck (0) only for a parent organizational folder in this registry.'),
	('hierarchy','leaf_only','en','Leaf Nodes Only (leaf_only)','Allow Links to Leaf Nodes Only','Leaves Only','Indicates whether target records may be linked exclusively to terminal leaf nodes (is_leaf = 1) of this hierarchy.'),
	('hierarchy','multiple','en','Multiple Assignment (multiple)','Allow Assigning Multiple Items','Multiple Items','Indicates whether a target record can be linked to multiple items from this hierarchy simultaneously.');
END
GO