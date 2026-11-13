/* =============================================================================
 * Soubor: table_meta_class.sql
 * Verze: 2026-11-13 17:15
 * Tabulka: meta_class
 * Popis:   Logické třídy (entity) systému. Slouží jako nadstavba nad 
 *          fyzickými objekty (meta_object). Definuje konkrétní třídy 
 *          v rámci vzoru Single Table Inheritance (STI) a jejich chování.
 * Vazby:   - storage_object (UUID) ukazuje na meta_object (fyzická tabulka).
 *          - ancestor_class (UUID) ukazuje na jinou meta_class (dědičnost logiky i sloupců).
 *          - Plněno automaticky procedurou p_fix_meta_column, p_sysinit_process a importem p_xlsx_meta_object.
 * Změny:   - 2026-11-13 17:15: Doplněna registrace tříd meta_class a sys_global_columns
 *            do sysinit_class a sloupců do sysinit_column.
 *          - 2026-10-24 23:45: Přidán sloupec days_in_trash smallint NOT NULL DEFAULT 365
 *            pro řízení automatického vysypávání koše (removed = 1; 0 = nikdy).
 * ============================================================================= */

if not exists (select * from v_syscolumns where tabname='meta_class' and colname='storage_object')
	execute dropni 'meta_class';

IF OBJECT_ID('meta_class') IS NULL
CREATE TABLE meta_class(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu (0x00 pro systémové třídy)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor třídy napříč overridy
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, L, D, H)
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení (A, D, F, R)
	draft_author uuid NOT NULL DEFAULT 0x00,           -- Autor konceptu (user_account.original)
	approval_note varchar(max) NOT NULL DEFAULT '',    -- Poznámka schvalovatele / důvod vrácení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,                   -- Původní textový autor/systém z importu (Měkký audit)

	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické atributy logické třídy
	-- -------------------------------------------------------------------------
	class_name varchar(80) NOT NULL,                   -- Interní identifikátor třídy (např. 'asset_class', 'employee')
	storage_object uuid NOT NULL,                      -- Vazba na fyzickou tabulku z meta_object
	ancestor_class uuid NULL,                          -- Vazba na předka pro dědičnost (meta_class.original). Plně nahrazuje původní column_ancestor z meta_object.
	
	-- Prezentační texty (přeložitelné v overridu typu 'L', NULL = dědí se)
	caption varchar(200) NULL,
	caption_plural varchar(200) NULL,
	description varchar(max) NULL,
	helptext varchar(max) NULL,
	editor_note varchar(max) NULL,                     -- Sémantický kontext pro překladatele a AI (nepřekládá se)
	
	-- Uživatelské rozhraní a správa životního cyklu
	svg_icon varchar(max) NULL,                        -- Vektorová ikona SVG pro navigaci a seznamy (NULL = dědí se)
	sort_code varchar(20) NOT NULL DEFAULT '',         -- Výchozí třídění v hierarchii
	days_in_trash smallint NOT NULL DEFAULT 365,       -- Počet dnů uchování zrušených záznamů (removed = 1) v koši (0 = nikdy)
	
	-- Oprávnění (Vazba na role v rámci tenanta)
	role_editor uuid NULL,                             -- Odkaz (UUID) na roli oprávněnou k editaci dat této třídy

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur (limity klientského overridu)
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,                   -- 1 = Zcela zakazuje tenantům vytvořit 'A' override třídy
	is_protected bit NOT NULL DEFAULT 0,               -- 1 = Tenant nesmí měnit technickou logiku (povolena jen vizuální úprava)

	CONSTRAINT pk_meta_class PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze (změnový příkaz)
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_class', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'meta_class', 'editor_note', 'varchar(max) NULL';
EXEC p_create_missing_column 'meta_class', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_class', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'meta_class', 'svg_icon', 'varchar(max) NULL';
EXEC p_create_missing_column 'meta_class', 'days_in_trash', 'smallint NOT NULL DEFAULT 365';
GO

-- Idempotentní migrace a odstranění zastaralého sloupce iconname
IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_class' AND colname = 'iconname')
BEGIN
	EXEC('UPDATE meta_class SET svg_icon = iconname WHERE svg_icon IS NULL AND iconname IS NOT NULL AND iconname <> ''''');
	EXEC sp_drop_column 'meta_class', 'iconname';
END
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka
EXEC sp_create_index 
	@tname = 'meta_class', 
	@iname = 'uq_meta_class_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti jazykových verzí (Language)
EXEC sp_create_index 
	@tname = 'meta_class', 
	@iname = 'uq_meta_class_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace tříd a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name IN ('meta_class', 'sys_global_columns');

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('meta_class','cs','T','meta_class','Logická třída (Objekt)','Logické třídy (Objekty)','Definice logických entit systému nad fyzickými tabulkami s podporou dědičnosti (STI) a správy koše.','Zde můžete upravit zobrazované názvy tříd, dobu uchování smazaných záznamů v koši a výchozí ikonu.'),
	('sys_global_columns','cs','C','sys_global_columns','Globální slovník sloupců','Globální definice sloupců','Centrální katalog výchozích vlastností a překladů databázových sloupců, ze kterého dědí sloupce jednotlivých tříd.','Sloupce jednotlivých tříd přebírají své výchozí popisky, šířky a chování z tohoto globálního slovníku.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('meta_class','en','Logical Class (Object)','Logical Classes (Objects)','Definition of logical system entities over physical tables supporting Single Table Inheritance (STI) and trash retention.','Allows customizing class captions, trash retention days, and default SVG icons.'),
	('sys_global_columns','en','Global Column Dictionary','Global Column Definitions','Central dictionary of default properties and translations for database columns inherited by class columns.','Class columns inherit their default labels, widths, and behavior from this global dictionary.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'meta_class';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		list_order, is_mandatory, referenced_class_code
	) VALUES
	('meta_class','ancestor_class','cs','Předek třídy pro dědičnost (ancestor_class)','Nadřazená třída (dědičnost STI)','Předek třídy','Odkaz na nadřazenou logickou třídu, ze které tato třída dědí definici sloupců a výchozí chování.',NULL,0,'meta_class'),
	('meta_class','class_name','cs','Technický název třídy (class_name)','Kód logické třídy (class_name)','Kód třídy','Unikátní systémový identifikátor logické třídy v architektuře STI.',5,1,''),
	('meta_class','days_in_trash','cs','Dny uchování v koši (days_in_trash)','Dny v koši před smazáním','Dny v koši','Počet dnů uchování zrušených záznamů (removed = 1) v koši před automatickým fyzickým smazáním (0 = nikdy nemazat).',NULL,0,''),
	('meta_class','role_editor','cs','Role editora třídy (role_editor)','Role oprávněná k editaci třídy','Role editora','Odkaz na roli oprávněnou k úpravám dat této logické třídy.',NULL,0,''),
	('meta_class','storage_object','cs','Fyzické úložiště (storage_object)','Fyzická úložná tabulka / pohled','Úložiště','Odkaz na fyzickou databázovou tabulku nebo pohled v meta_object, kde jsou uložena data této třídy.',NULL,0,'meta_object');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('meta_class','ancestor_class','en','Ancestor Class for Inheritance (ancestor_class)','Parent Class (STI Inheritance)','Ancestor Class','Reference to the parent logical class from which this class inherits columns and default behavior.'),
	('meta_class','class_name','en','Technical Class Name (class_name)','Logical Class Code (class_name)','Class Code','Unique system identifier of the logical class in the STI architecture.'),
	('meta_class','days_in_trash','en','Days in Trash (days_in_trash)','Trash Retention Days Before Purge','Days in Trash','Number of days removed records (removed = 1) are kept in the trash before automatic physical deletion (0 = never purge).'),
	('meta_class','role_editor','en','Class Editor Role (role_editor)','Role Authorized to Edit Class','Editor Role','Reference to the role authorized to edit records of this logical class.'),
	('meta_class','storage_object','en','Physical Storage (storage_object)','Physical Storage Table / View','Storage','Reference to the physical database table or view in meta_object storing data for this class.');
END
GO