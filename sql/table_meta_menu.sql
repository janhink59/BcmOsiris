/* =============================================================================
 * Verze: 2026-10-23 16:20
 * Soubor: table_meta_menu.sql
 * Tabulka: meta_menu
 * Popis:   Uchovává strukturu uživatelského menu s vazbou na fyzické stránky.
 * Vazby:   - target_object (UUID) ukazuje na meta_object.original (stránka 'P')
 *          - parent_uuid (UUID) ukazuje na nadřízený uzel v téže tabulce (original)
 *          - Čteno procedurou p_get_menu_hierarchy (p_get_menu_hierarchy.sql)
 *            a plněno hromadným importem přes p_xlsx_meta_object nebo p_csv_import_metadata.
 * Změny:   - 2026-10-23 16:20: Přidána položka menu csv_package (Přenos balíčků CSV/TSV)
 *            směřující na stránku page_csv_package (system_role = 'S').
 *          - 2026-10-22 16:15: Přidána položka menu organization (Správa organizací)
 *            směřující na stránku page_organization (system_role = 'S').
 *          - 2026-10-21 15:05: Přidána položka menu xlsx_export_meta (Export metadat
 *            do Excelu) směřující na samostatnou stránku page_xlsx_export_meta.
 * ============================================================================= */

IF OBJECT_ID('meta_menu') IS NULL
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
GO

EXEC p_create_missing_column 'meta_menu', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_menu', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
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

-- -----------------------------------------------------------------------------
-- INICIÁLNÍ NAPLNĚNÍ SYSTÉMOVÉHO MENU (0x00)
-- -----------------------------------------------------------------------------
DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

-- 1. Zjištění ID cílových stránek (meta_object.original) se sjednoceným prefixem page_
DECLARE @tgt_main uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_main');
DECLARE @tgt_meta_class uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_meta_class');
DECLARE @tgt_meta_column uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_meta_column');
DECLARE @tgt_meta_phrase uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_meta_phrase');
DECLARE @tgt_approval uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_approval');
DECLARE @tgt_organization uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_organization');
DECLARE @tgt_org_licence uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_organization_licence');
DECLARE @tgt_org_users uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_org_users');
DECLARE @tgt_excel_reader uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_excel_reader');
DECLARE @tgt_xlsx_export_meta uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_xlsx_export_meta');
DECLARE @tgt_csv_package uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_csv_package');

-- 2. Příprava originálů menu uzlů, abychom je mohli mezi sebou ihned provázat (parent_uuid)
DECLARE @mnu_home uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'home', '');
DECLARE @mnu_admin uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'admin_folder', '');
DECLARE @mnu_meta_class uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'meta_class', '');
DECLARE @mnu_meta_column uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'meta_column', '');
DECLARE @mnu_meta_phrase uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'meta_phrase', '');
DECLARE @mnu_approval uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'approval', '');
DECLARE @mnu_organization uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'organization', '');
DECLARE @mnu_org_licence uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'organization_licence', '');
DECLARE @mnu_org_users uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'org_users', '');
DECLARE @mnu_excel_reader uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'excel_reader', '');
DECLARE @mnu_xlsx_export_meta uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'xlsx_export_meta', '');
DECLARE @mnu_csv_package uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'csv_package', '');

-- 3. Pomocná struktura pro idempotentní dávkový zápis bez duplikace kódu
DECLARE @init_menu TABLE (
	original uuid, parent_uuid uuid, sort_code varchar(20), builtin_code varchar(80), 
	caption varchar(200), target_object uuid, system_role varchar(1), svg_icon varchar(max)
);

INSERT INTO @init_menu VALUES
(@mnu_home, NULL, '00', 'home', 'Domů', @tgt_main, 'U', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>'),
(@mnu_admin, @mnu_home, '90', 'admin_folder', 'Systémová administrace', NULL, 'U', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.06-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.73,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.06,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12-0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62-0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.49-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>'),
(@mnu_meta_class, @mnu_admin, '01', 'meta_class', 'Logické třídy (Objekty)', @tgt_meta_class, 'U', ''),
(@mnu_meta_column, @mnu_admin, '02', 'meta_column', 'Sloupce metadat', @tgt_meta_column, 'U', ''),
(@mnu_meta_phrase, @mnu_admin, '03', 'meta_phrase', 'Textové fráze a překlady', @tgt_meta_phrase, 'U', ''),
(@mnu_approval, @mnu_admin, '04', 'approval', 'Schvalování změn', @tgt_approval, 'U', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>'),
(@mnu_organization, @mnu_admin, '05', 'organization', 'Správa organizací', @tgt_organization, 'S', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>'),
(@mnu_org_licence, @mnu_admin, '06', 'organization_licence', 'Správa licencí organizací', @tgt_org_licence, 'S', ''),
(@mnu_org_users, @mnu_admin, '07', 'org_users', 'Uživatelé organizace', @tgt_org_users, 'A', ''),
(@mnu_excel_reader, @mnu_admin, '08', 'excel_reader', 'Import dat z Excelu', @tgt_excel_reader, 'S', ''),
(@mnu_xlsx_export_meta, @mnu_admin, '09', 'xlsx_export_meta', 'Export metadat do Excelu', @tgt_xlsx_export_meta, 'S', ''),
(@mnu_csv_package, @mnu_admin, '10', 'csv_package', 'Přenos balíčků (CSV/TSV)', @tgt_csv_package, 'S', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>');

-- 4. Idempotentní INSERT hlavních 'A' záznamů pomocí NOT EXISTS
INSERT INTO meta_menu (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, caption, target_object, system_role, svg_icon, is_final, is_protected
)
SELECT 
	original, @sys_owner, original, 'A', 'A', 'cs',
	builtin_code, parent_uuid, sort_code, caption, target_object, system_role, svg_icon, 1, 1
FROM @init_menu i
WHERE NOT EXISTS (
	SELECT 1 FROM meta_menu m WHERE m.original = i.original AND m.record_type = 'A' AND m.object_owner = @sys_owner AND m.removed = 0
);

-- 5. Idempotentní INSERT symetrických 'L' záznamů pro výchozí jazyk ('cs')
INSERT INTO meta_menu (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, caption, target_object, system_role, svg_icon, is_final, is_protected
)
SELECT 
	NEWID(), @sys_owner, original, 'L', 'A', 'cs',
	builtin_code, parent_uuid, sort_code, caption, target_object, system_role, svg_icon, 1, 1
FROM @init_menu i
WHERE NOT EXISTS (
	SELECT 1 FROM meta_menu m WHERE m.original = i.original AND m.record_type = 'L' AND m.[language] = 'cs' AND m.object_owner = @sys_owner AND m.removed = 0
);

-- 6. Aktualizace target_object, sort_code a system_role u již existujících systémových záznamů
UPDATE m
SET m.target_object = i.target_object,
	m.sort_code = i.sort_code,
	m.system_role = i.system_role
FROM meta_menu m
JOIN @init_menu i ON i.original = m.original
WHERE m.object_owner = @sys_owner
  AND m.record_type IN ('A', 'L')
  AND (
	ISNULL(m.target_object, 0x00) <> ISNULL(i.target_object, 0x00)
	OR m.sort_code <> i.sort_code
	OR m.system_role <> i.system_role
  );
GO