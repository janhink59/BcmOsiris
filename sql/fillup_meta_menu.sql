/* =============================================================================
 * Verze: 2026-10-25 11:30
 * Soubor: fillup_meta_menu.sql
 * Účel:   Prvotní idempotentní naplnění systémové navigace (object_owner = 0x00)
 *         v tabulce meta_menu s rozestupy sort_code po desítkách ('010', '020'...).
 *         Odděleno od čistého DDL skriptu table_meta_menu.sql.
 * Vazby:  - Odkazuje na záznamy stránek (object_type = 'P') v tabulce meta_object
 *           (musí běžet až po fillup_meta_object.sql).
 *         - Využívá deterministickou funkci dbo.f_generate_original.
 *         - Aktualizaci struktury (parent_uuid, sort_code, target_object, system_role)
 *           provádí u 'A' záznamů pouze tehdy, pokud dosud nebyly ručně upraveny
 *           uživatelem v UI (who_modified = 0x00), nebo při jednorázovém přechodu
 *           ze starých 2znakových kódů (LEN(sort_code) = 2) na 3znakové desítky.
 *         - Technické sloupce v jazykových 'L' záznamech synchronizuje podle 'A'
 *           vždy bez ohledu na l.who_modified.
 * Změny:  - 2026-10-25 11:30: Do složky Systémová administrace (admin_folder)
 *           přidána položka service_logbook (sort_code = '060', system_role = 'S')
 *           odkazující na stránku page_service_logbook.
 * ============================================================================= */

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

-- 1. Zjištění ID cílových stránek (meta_object.original) se sjednoceným prefixem page_
DECLARE @tgt_main uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_main');
DECLARE @tgt_meta_class uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_meta_class');
DECLARE @tgt_meta_column uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_meta_column');
DECLARE @tgt_meta_phrase uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_meta_phrase');
DECLARE @tgt_meta_menu uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_meta_menu');
DECLARE @tgt_approval uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_approval');
DECLARE @tgt_organization uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_organization');
DECLARE @tgt_org_licence uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_organization_licence');
DECLARE @tgt_org_users uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_org_users');
DECLARE @tgt_excel_reader uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_excel_reader');
DECLARE @tgt_xlsx_export_meta uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_xlsx_export_meta');
DECLARE @tgt_csv_package uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_csv_package');
DECLARE @tgt_service_logbook uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_service_logbook');

-- 2. Příprava originálů menu uzlů pro vzájemné provázání (parent_uuid)
DECLARE @mnu_home uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'home', '');
DECLARE @mnu_meta_folder uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'metadata_folder', '');
DECLARE @mnu_admin uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'admin_folder', '');
DECLARE @mnu_meta_class uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'meta_class', '');
DECLARE @mnu_meta_column uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'meta_column', '');
DECLARE @mnu_meta_phrase uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'meta_phrase', '');
DECLARE @mnu_meta_menu uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'meta_menu', '');
DECLARE @mnu_approval uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'approval', '');
DECLARE @mnu_organization uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'organization', '');
DECLARE @mnu_org_licence uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'organization_licence', '');
DECLARE @mnu_org_users uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'org_users', '');
DECLARE @mnu_excel_reader uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'excel_reader', '');
DECLARE @mnu_xlsx_export_meta uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'xlsx_export_meta', '');
DECLARE @mnu_csv_package uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'csv_package', '');
DECLARE @mnu_service_logbook uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'service_logbook', '');

-- 3. Pomocná struktura pro idempotentní dávkový zápis (sort_code rozřazen po desítkách)
DECLARE @init_menu TABLE (
	original uuid, parent_uuid uuid, sort_code varchar(20), builtin_code varchar(80), 
	caption varchar(200), helptext varchar(max), target_object uuid, system_role varchar(1), svg_icon varchar(max)
);

INSERT INTO @init_menu VALUES
-- Kořenová položka (úroveň 0)
(@mnu_home, NULL, '000', 'home', 'Domů', 'Úvodní rozcestník aplikace', @tgt_main, 'U', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>'),

-- 1. úroveň: Složka "Práce s metadaty" (sort_code = '080') a její podřízené položky po desítkách
(@mnu_meta_folder, @mnu_home, '080', 'metadata_folder', 'Práce s metadaty', 'Správa logických tříd, sloupců, textových frází, navigace a vývojářských balíčků metadat', NULL, 'U', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3C7.58 3 4 4.79 4 7s3.58 4 8 4 8-1.79 8-4-3.58-4-8-4zM4 9v3c0 2.21 3.58 4 8 4s8-1.79 8-4V9c0 2.21-3.58 4-8 4s-8-1.79-8-4zm0 5v3c0 2.21 3.58 4 8 4s8-1.79 8-4v-3c0 2.21-3.58 4-8 4s-8-1.79-8-4z"/></svg>'),
(@mnu_meta_class, @mnu_meta_folder, '010', 'meta_class', 'Logické třídy (Objekty)', 'Správa logických entit, jejich vlastností a překladů', @tgt_meta_class, 'U', ''),
(@mnu_meta_column, @mnu_meta_folder, '020', 'meta_column', 'Sloupce metadat', 'Správa definic sloupců, formulářových prvků a překladů', @tgt_meta_column, 'U', ''),
(@mnu_meta_phrase, @mnu_meta_folder, '030', 'meta_phrase', 'Textové fráze a překlady', 'Správa textových frází, tlačítek a jazykových mutací', @tgt_meta_phrase, 'U', ''),
(@mnu_meta_menu, @mnu_meta_folder, '040', 'meta_menu', 'Položky menu (Navigace)', 'Úprava hierarchie, pořadí, cílových stránek a překladů položek menu', @tgt_meta_menu, 'U', ''),
(@mnu_excel_reader, @mnu_meta_folder, '050', 'excel_reader', 'Import dat z Excelu', 'Hromadný import a kontrola metadat ze souboru XLSX', @tgt_excel_reader, 'S', ''),
(@mnu_xlsx_export_meta, @mnu_meta_folder, '060', 'xlsx_export_meta', 'Export metadat do Excelu', 'Zpětný export systémových metadat do souboru XLSX', @tgt_xlsx_export_meta, 'S', ''),

-- 1. úroveň: Složka "Systémová administrace" (sort_code = '090') a její podřízené položky po desítkách
(@mnu_admin, @mnu_home, '090', 'admin_folder', 'Systémová administrace', 'Schvalování změn, správa organizací, licencí, uživatelů, přenos datových balíčků a provozní deník', NULL, 'U', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.06-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.73,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.06,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12-0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62-0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.49-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>'),
(@mnu_approval, @mnu_admin, '010', 'approval', 'Schvalování změn', 'Posouzení, schvalování a vracení navržených změn záznamů', @tgt_approval, 'U', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>'),
(@mnu_organization, @mnu_admin, '020', 'organization', 'Správa organizací', 'Přehled a nastavení klientských organizací (tenantů)', @tgt_organization, 'S', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>'),
(@mnu_org_licence, @mnu_admin, '030', 'organization_licence', 'Správa licencí organizací', 'Evidence žádostí o licenci a aktivace nových organizací', @tgt_org_licence, 'S', ''),
(@mnu_org_users, @mnu_admin, '040', 'org_users', 'Uživatelé organizace', 'Správa uživatelů, oprávnění a žádostí o přístup v organizaci', @tgt_org_users, 'A', ''),
(@mnu_csv_package, @mnu_admin, '050', 'csv_package', 'Přenos balíčků (CSV/TSV)', 'Export a dvoufázový import datových balíčků mezi instancemi', @tgt_csv_package, 'S', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>'),
(@mnu_service_logbook, @mnu_admin, '060', 'service_logbook', 'Provozní deník (Logbook)', 'Přehled historie provedených upgradů databáze a importů systémových dávek', @tgt_service_logbook, 'S', '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>');

-- 4. Idempotentní INSERT hlavních 'A' záznamů pomocí NOT EXISTS
INSERT INTO meta_menu (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, caption, helptext, target_object, system_role, svg_icon, is_final, is_protected
)
SELECT 
	original, @sys_owner, original, 'A', 'A', 'cs',
	builtin_code, parent_uuid, sort_code, caption, helptext, target_object, system_role, svg_icon, 1, 1
FROM @init_menu i
WHERE NOT EXISTS (
	SELECT 1 FROM meta_menu m WHERE m.original = i.original AND m.record_type = 'A' AND m.object_owner = @sys_owner AND m.removed = 0
);

-- 5. Idempotentní INSERT symetrických 'L' záznamů pro výchozí jazyk ('cs')
INSERT INTO meta_menu (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, caption, helptext, target_object, system_role, svg_icon, is_final, is_protected
)
SELECT 
	NEWID(), @sys_owner, original, 'L', 'A', 'cs',
	builtin_code, parent_uuid, sort_code, caption, helptext, target_object, system_role, svg_icon, 1, 1
FROM @init_menu i
WHERE NOT EXISTS (
	SELECT 1 FROM meta_menu m WHERE m.original = i.original AND m.record_type = 'L' AND m.[language] = 'cs' AND m.object_owner = @sys_owner AND m.removed = 0
);

-- 6. Aktualizace výchozí hierarchie a 3znakových desítkových sort_code u 'A' záznamů,
--    které dosud nebyly ručně upraveny v UI (m.who_modified = 0x00), anebo mají ještě starý 2znakový sort_code.
UPDATE m
SET m.parent_uuid = i.parent_uuid,
	m.sort_code = i.sort_code,
	m.target_object = i.target_object,
	m.system_role = i.system_role,
	m.helptext = CASE WHEN m.helptext = '' THEN i.helptext ELSE m.helptext END
FROM meta_menu m
JOIN @init_menu i ON i.original = m.original
WHERE m.object_owner = @sys_owner
  AND m.record_type = 'A'
  AND (
	m.who_modified = @sys_owner
	OR LEN(m.sort_code) = 2
	OR (i.parent_uuid = @mnu_meta_folder AND m.parent_uuid = @mnu_admin)
  )
  AND (
	ISNULL(m.parent_uuid, 0x00) <> ISNULL(i.parent_uuid, 0x00)
	OR m.sort_code <> i.sort_code
	OR ISNULL(m.target_object, 0x00) <> ISNULL(i.target_object, 0x00)
	OR m.system_role <> i.system_role
	OR (m.helptext = '' AND i.helptext <> '')
  );

-- 7. Technické atributy (parent_uuid, sort_code, target_object, system_role) v jazykových
--    záznamech 'L' musí vždy zrcadlit svůj hlavní 'A' záznam (bez ohledu na l.who_modified).
UPDATE l
SET l.parent_uuid = a.parent_uuid,
	l.sort_code = a.sort_code,
	l.target_object = a.target_object,
	l.system_role = a.system_role,
	l.helptext = CASE WHEN l.helptext = '' AND l.[language] = a.[language] THEN a.helptext ELSE l.helptext END
FROM meta_menu l
JOIN meta_menu a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND (
	ISNULL(l.parent_uuid, 0x00) <> ISNULL(a.parent_uuid, 0x00)
	OR l.sort_code <> a.sort_code
	OR ISNULL(l.target_object, 0x00) <> ISNULL(a.target_object, 0x00)
	OR l.system_role <> a.system_role
	OR (l.helptext = '' AND l.[language] = a.[language] AND a.helptext <> '')
  );
GO