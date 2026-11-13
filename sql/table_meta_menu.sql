/* =============================================================================
 * Verze: 2026-11-13 17:15
 * Soubor: table_meta_menu.sql
 * Tabulka: meta_menu
 * Popis:   DDL definice tabulky pro strukturu uživatelského menu s vazbou na stránky.
 *          Prvotní naplnění položek menu zajišťují modulární skripty *#phrase.sql
 *          a procedura dbo.p_sysinit_process.
 * Vazby:   - target_object (UUID) ukazuje na meta_object.original (stránka 'P')
 *          - parent_uuid (UUID) ukazuje na nadřízený uzel v téže tabulce (original)
 *          - Čteno procedurou p_get_menu_hierarchy (p_get_menu_hierarchy.sql),
 *            spravováno stránkou page_meta_menu.php a plněno procedurou
 *            p_sysinit_process nebo importem p_xlsx_meta_object / p_csv_import_metadata.
 * Změny:   - 2026-11-13 17:15: Doplněna registrace třídy a sloupců do sysinit_class
 *            a sysinit_column.
 *          - 2026-10-24 13:15: Oddělení DDL struktury od datového plnění.
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

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'meta_menu';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('meta_menu','cs','T','meta_menu','Položka menu (Navigace)','Položky menu (Navigace)','Stromová struktura hlavní aplikační navigace a rozcestníků s řízením přístupu podle rolí.','Určuje hierarchii menu, cílové stránky, ikony a oprávnění pro zobrazení navigačních položek.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('meta_menu','en','Menu Item (Navigation)','Menu Items (Navigation)','Tree structure of the main application navigation and dashboards with role-based access control.','Defines menu hierarchy, target pages, SVG icons, and required access roles.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'meta_menu';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		referenced_class_code
	) VALUES
	('meta_menu','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','meta_menu'),
	('meta_menu','permanent','cs','Trvale viditelná položka (permanent)','Trvale zobrazit i prázdnou složku','Trvalé','Ponechá složku menu viditelnou (jako neaktivní) i tehdy, když uživatel nemá přístup k žádné její podpoložce.',''),
	('meta_menu','system_role','cs','Minimální systémová role (system_role)','Minimální požadovaná role (U/A/S/D)','Min. role','Minimální efektivní role nutná pro přístup: U = User, A = Admin organizace, S = Sysadmin, D = Developer.',''),
	('meta_menu','target_object','cs','Cílová stránka (target_object)','Cílová stránka aplikace (meta_object)','Cílová stránka','Odkaz na registrovanou PHP stránku (object_type = P), kterou otevře kliknutí na koncovou položku menu.','meta_object'),
	('meta_menu','target_url','cs','Externí URL odkaz (target_url)','Externí nebo pevná URL adresa','Externí URL','Přímá URL adresa pro položky menu směřující mimo standardní aplikační stránky.',''),
	('meta_menu','target_window','cs','Cílové okno odkazu (target_window)','Cílové okno prohlížeče (např. _blank)','Cílové okno','Určuje způsob otevření odkazu (prázdné = totéž okno, _blank = nová záložka prohlížeče).',''),
	('meta_menu','url_parameters','cs','Parametry URL (url_parameters)','Dodatečné GET parametry URL','Parametry URL','Volitelné parametry připojované za URL cílové stránky (např. &hierarchy=...).','');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('meta_menu','permanent','en','Permanently Visible Item (permanent)','Always Show Even When Empty','Permanent','Keeps a menu folder visible (as disabled) even when the user has no access to any child items.'),
	('meta_menu','system_role','en','Minimum System Role (system_role)','Minimum Required Role (U/A/S/D)','Min. Role','Minimum effective role required for access: U = User, A = Org Admin, S = Sysadmin, D = Developer.'),
	('meta_menu','target_object','en','Target Page (target_object)','Target Application Page (meta_object)','Target Page','Reference to the registered PHP page (object_type = P) opened when clicking a leaf menu item.'),
	('meta_menu','target_url','en','External URL Link (target_url)','External or Fixed URL Address','External URL','Direct URL address for menu items pointing outside standard application pages.'),
	('meta_menu','target_window','en','Link Target Window (target_window)','Browser Target Window (e.g., _blank)','Target Window','Specifies how the link opens (empty = same window, _blank = new browser tab).'),
	('meta_menu','url_parameters','en','URL Parameters (url_parameters)','Additional GET URL Parameters','URL Parameters','Optional query string parameters appended to the target page URL (e.g., &hierarchy=...).');
END
GO