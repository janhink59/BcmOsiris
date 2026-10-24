/* =============================================================================
 * Verze: 2026-10-24 13:15
 * Soubor: table_meta_menu.sql
 * Tabulka: meta_menu
 * Popis:   DDL definice tabulky pro strukturu uživatelského menu s vazbou na stránky.
 *          Prvotní naplnění položek menu je vyčleněno do skriptu fillup_meta_menu.sql.
 * Vazby:   - target_object (UUID) ukazuje na meta_object.original (stránka 'P')
 *          - parent_uuid (UUID) ukazuje na nadřízený uzel v téže tabulce (original)
 *          - Čteno procedurou p_get_menu_hierarchy (p_get_menu_hierarchy.sql),
 *            spravováno stránkou page_meta_menu.php a plněno skriptem
 *            fillup_meta_menu.sql nebo importem p_xlsx_meta_object / p_csv_import_metadata.
 * Změny:   - 2026-10-24 13:15: Oddělení DDL struktury od datového plnění
 *            (plnění přesunuto do souboru fillup_meta_menu.sql).
 * ============================================================================= */

IF OBJECT_ID('meta_menu') IS NULL
BEGIN
	CREATE TABLE meta_menu(
		-- Standardní RAC a SSC sloupce
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu (0x00 pro systémové menu)
		original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor
		record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, L, D, H)
		approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení (A, D, F, R)
		draft_author uuid NOT NULL DEFAULT 0x00,           -- Autor konceptu (user_account.original)
		approval_note varchar(max) NOT NULL DEFAULT '',    -- Poznámka schvalovatele
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		is_template bit NOT NULL DEFAULT 0,
		template uuid NULL,
		import_origin varchar(255) NULL,                   -- Původ z importu

		-- Auditní stopy
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- Identifikace a hierarchie
		builtin_code varchar(80) NOT NULL,                 -- Identifikátor pro deterministický originál a odkazování
		parent_uuid uuid NULL,                             -- Odkaz na nadřízenou položku menu (meta_menu.original)
		sort_code varchar(20) NOT NULL DEFAULT '',         -- Logické řazení v rámci úrovně (sourozenců)

		-- Cíle navigace (Uplatní se pouze na koncových uzlech - listech)
		target_object uuid NULL,                           -- Odkaz na meta_object.original (typ P)
		url_parameters varchar(500) NOT NULL DEFAULT '',   -- GET parametry pro aplikaci ke stránce
		target_url varchar(500) NOT NULL DEFAULT '',       -- Externí nebo absolutní odkaz
		target_window varchar(20) NOT NULL DEFAULT '',     -- Chování okna (např. '_blank')

		-- Prezentační texty
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný text v menu
		description varchar(max) NOT NULL DEFAULT '',      -- Podrobnější popis (tooltip)
		helptext varchar(max) NOT NULL DEFAULT '',
		editor_note varchar(max) NOT NULL DEFAULT '',      -- AI kontext pro spolehlivější překlady

		-- UI prvky
		svg_icon varchar(max) NOT NULL DEFAULT '',         -- Vektorová ikona položky
		css_class varchar(200) NOT NULL DEFAULT '',        -- Klientské CSS třídy pro vlastní stylování

		-- Řízení přístupu a chování
		system_role varchar(1) NOT NULL DEFAULT 'S',       -- Minimální nutná role
		permanent bit NOT NULL DEFAULT 0,                  -- 1 = Viditelné (disabled) i bez dostupných podpoložek

		-- Ochrana
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_meta_menu PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka meta_menu byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_menu', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_menu', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'meta_menu', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'meta_menu', 'editor_note', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'meta_menu', 
	@iname = 'uq_meta_menu_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'meta_menu', 
	@iname = 'uq_meta_menu_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'meta_menu', 
	@iname = 'uq_meta_menu_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO