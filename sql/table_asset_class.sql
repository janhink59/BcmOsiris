/* =============================================================================
 * Verze: 2026-11-01 18:00
 * Soubor: table_asset_class.sql
 * Tabulka: asset_class (Třídy aktiv)
 * Popis:	Hierarchický katalog pro klasifikaci aktiv v modulu CRMM.
 *			Určuje strukturu (např. Umístění -> Budova -> Místnost), 
 *			definuje koncové uzly (is_leaf = 1) a umožňuje dědění rolí editorů
 *			a vazeb na hrozby, scénáře a klasifikační číselníky.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:	- parent_uuid ukazuje na nadřízený uzel asset_class.original.
 *			- Koncové uzly (is_leaf = 1) jsou odkazovány ze sloupce
 *			  asset.primary_asset_class a z tabulky link.
 *			- Spravováno stromovou stránkou page_asset_class.php.
 * Změny:
 * - 2026-11-01 18:00: Doplněny sloupce builtin_code, svg_icon, is_final,
 *   is_protected a index ix_asset_class_parent_sort pro sjednocení se šablonou
 *   abstract_page_tree.
 * - 2026-10-23 11:00: Doplněny sloupce draft_author, approval_note a import_origin.
 * ============================================================================= */

IF OBJECT_ID('asset_class') IS NULL
BEGIN
	CREATE TABLE asset_class (
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
		-- Společné identifikační a prezentační vlastnosti (podpora UTF-8)
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód pro deterministický originál (povinný v 0x00 a šablonách)
		caption varchar(200) NOT NULL DEFAULT '',
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		instance_class_name varchar(80) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Stromová struktura a specifické sloupce pro asset_class
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená třída aktiv (asset_class.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncová třída aktiv (lze navázat aktiva), 0 = Složka
		editor_role_uuid uuid NULL,                        -- Role oprávněná k editaci aktiv v této třídě (dědí se)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_asset_class PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka asset_class byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'asset_class', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'asset_class', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset_class', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'asset_class', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset_class', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset_class', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'asset_class', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'asset_class', 
	@iname = 'uq_asset_class_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'asset_class', 
	@iname = 'uq_asset_class_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'asset_class', 
	@iname = 'uq_asset_class_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'asset_class', 
	@iname = 'ix_asset_class_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Inicializační systémový kořenový záznam (0x00)
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM asset_class WHERE uuid = 0x00)
BEGIN
	INSERT INTO asset_class (
		uuid, object_owner, original, record_type, approval_status,
		builtin_code, caption, shortname, description_text,
		is_leaf, sort_code
	) VALUES (
		0x00, 0x00, 0x00, 'A', 'A',
		'ROOT', 'Kořenová třída aktiv', 'ROOT', 'Výchozí systémový uzel pro hierarchii tříd aktiv.',
		0, '000'
	);
END
GO