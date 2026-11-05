/* =============================================================================
 * Verze: 2026-11-05 15:30
 * Soubor: fillup_meta_menu.sql
 * Účel:   Prvotní idempotentní naplnění systémové navigace (object_owner = 0x00)
 *         v tabulce meta_menu s rozestupy sort_code po desítkách ('010', '020'...).
 * Vazby:  - Odkazuje na záznamy stránek (object_type = 'P') v tabulce meta_object
 *           (musí běžet až po fillup_meta_object.sql).
 *         - Využívá deterministickou funkci dbo.f_generate_original.
 * Změny:  - 2026-11-04 15:15: Do složky crmm_folder doplněny agendy protiopatření
 *           a hodnotících škál: countermeasure ('050'), countermeasure_state ('060'),
 *           scale ('070'), scale_value ('080') a posunuty hierarchy ('090')
 *           a hierarchy_item ('100').
 *         - 2026-11-05 15:30: Doplněny chybějící SVG ikony (meta_class, meta_column,
 *           meta_phrase, meta_menu, excel_reader, xlsx_export_meta,
 *           organization_licence, org_users) a aplikována živější sémantická
 *           barevná paleta místo monochromatického currentColor.
 * ============================================================================= */

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

-- 1. Zjištění ID cílových stránek (meta_object.original) se sjednoceným prefixem page_
DECLARE @tgt_main uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_main');
DECLARE @tgt_asset_class uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_asset_class');
DECLARE @tgt_threat uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_threat');
DECLARE @tgt_impact uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_impact');
DECLARE @tgt_scenario uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_scenario');
DECLARE @tgt_countermeasure uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_countermeasure');
DECLARE @tgt_cm_state uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_countermeasure_state');
DECLARE @tgt_scale uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_scale');
DECLARE @tgt_scale_value uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_scale_value');
DECLARE @tgt_hierarchy uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_hierarchy');
DECLARE @tgt_hierarchy_item uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_hierarchy_item');
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
DECLARE @tgt_audit_login uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', 'page_audit_login_session');

-- 2. Příprava originálů menu uzlů pro vzájemné provázání (parent_uuid)
DECLARE @mnu_home uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'home', '');
DECLARE @mnu_crmm_folder uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'crmm_folder', '');
DECLARE @mnu_asset_class uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'asset_class', '');
DECLARE @mnu_threat uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'threat', '');
DECLARE @mnu_impact uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'impact', '');
DECLARE @mnu_scenario uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'scenario', '');
DECLARE @mnu_countermeasure uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'countermeasure', '');
DECLARE @mnu_cm_state uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'countermeasure_state', '');
DECLARE @mnu_scale uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'scale', '');
DECLARE @mnu_scale_value uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'scale_value', '');
DECLARE @mnu_hierarchy uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'hierarchy', '');
DECLARE @mnu_hierarchy_item uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'hierarchy_item', '');
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
DECLARE @mnu_audit_login uuid = dbo.f_generate_original('meta_menu', @sys_owner, 'audit_login_session', '');

-- 3. Pomocná struktura pro idempotentní dávkový zápis (sort_code rozřazen po desítkách)
DECLARE @init_menu TABLE (
	original uuid, parent_uuid uuid, sort_code varchar(20), builtin_code varchar(80),
	caption varchar(200), helptext varchar(max), target_object uuid, system_role varchar(1), svg_icon varchar(max)
);

INSERT INTO @init_menu VALUES
-- Kořenová položka (úroveň 0)
(@mnu_home, NULL, '000', 'home', 'Domů', 'Úvodní rozcestník aplikace', @tgt_main, 'U', '<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>'),

-- 1. úroveň: Složka "Analýza a řízení rizik (CRMM)" (sort_code = '010') a její podřízené položky po desítkách
(@mnu_crmm_folder, @mnu_home, '010', 'crmm_folder', 'Analýza a řízení rizik (CRMM)', 'Katalogy tříd aktiv, hrozeb, dopadů, scénářů, protiopatření, hodnotících škál a sekundárních hierarchií', NULL, 'U', '<svg viewBox="0 0 24 24" fill="#4F46E5"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z"/></svg>'),
(@mnu_asset_class, @mnu_crmm_folder, '010', 'asset_class', 'Třídy aktiv', 'Správa hierarchického katalogu tříd aktiv, koncových uzlů a rolí editorů', @tgt_asset_class, 'U', '<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9H9V9h10v2zm-4 4H9v-2h6v2zm4-8H9V5h10v2z"/></svg>'),
(@mnu_threat, @mnu_crmm_folder, '020', 'threat', 'Katalog hrozeb', 'Správa hierarchického katalogu hrozeb a jejich výchozích hodnot skóre', @tgt_threat, 'U', '<svg viewBox="0 0 24 24" fill="#DC2626"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>'),
(@mnu_impact, @mnu_crmm_folder, '030', 'impact', 'Katalog dopadů', 'Správa hierarchického katalogu druhů a oblastí dopadů', @tgt_impact, 'U', '<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z"/></svg>'),
(@mnu_scenario, @mnu_crmm_folder, '040', 'scenario', 'Rizikové scénáře', 'Správa hierarchického katalogu rizikových scénářů (událostí) a mezí reziduálního rizika', @tgt_scenario, 'U', '<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z"/></svg>'),
(@mnu_countermeasure, @mnu_crmm_folder, '050', 'countermeasure', 'Katalog protiopatření', 'Správa hierarchického katalogu bezpečnostních a provozních protiopatření a jejich redukčních a rizikových faktorů', @tgt_countermeasure, 'U', '<svg viewBox="0 0 24 24" fill="#059669"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z"/></svg>'),
(@mnu_cm_state, @mnu_crmm_folder, '060', 'countermeasure_state', 'Stavy protiopatření', 'Správa číselníku stavů implementace protiopatření a jejich redukčních a rizikových faktorů', @tgt_cm_state, 'U', '<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>'),
(@mnu_scale, @mnu_crmm_folder, '070', 'scale', 'Hodnotící škály', 'Správa hodnotících škál pro hrozby, zranitelnosti, dopady a výsledná rizika', @tgt_scale, 'U', '<svg viewBox="0 0 24 24" fill="#D97706"><path d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/></svg>'),
(@mnu_scale_value, @mnu_crmm_folder, '080', 'scale_value', 'Stupně hodnotících škál', 'Správa jednotlivých stupňů hodnotících škál, prahových hodnot a skóre (0 až 100 %)', @tgt_scale_value, 'U', '<svg viewBox="0 0 24 24" fill="#3B82F6"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z"/></svg>'),
(@mnu_hierarchy, @mnu_crmm_folder, '090', 'hierarchy', 'Sekundární hierarchie a štítky', 'Správa registru sekundárních hierarchií, klasifikačních stromů, číselníků a štítků (tagů)', @tgt_hierarchy, 'U', '<svg viewBox="0 0 24 24" fill="#9333EA"><path d="M22 11V3h-7v3H9V3H2v8h7V8h2v10h4v3h7v-8h-7v3h-2V8h2v3z"/></svg>'),
(@mnu_hierarchy_item, @mnu_crmm_folder, '100', 'hierarchy_item', 'Položky sekundárních hierarchií', 'Správa uzlů a koncových položek jednotlivých sekundárních hierarchií, číselníků a štítků', @tgt_hierarchy_item, 'U', '<svg viewBox="0 0 24 24" fill="#DB2777"><path d="M17.63 5.84C17.27 5.33 16.67 5 16 5L5 5.01C3.9 5.01 3 5.9 3 7v10c0 1.1.9 1.99 2 1.99L16 19c.67 0 1.27-.33 1.63-.84L22 12l-4.37-6.16z"/></svg>'),

-- 1. úroveň: Složka "Práce s metadaty" (sort_code = '080') a její podřízené položky po desítkách
(@mnu_meta_folder, @mnu_home, '080', 'metadata_folder', 'Práce s metadaty', 'Správa logických tříd, sloupců, textových frází, navigace a vývojářských balíčků metadat', NULL, 'U', '<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 3C7.58 3 4 4.79 4 7s3.58 4 8 4 8-1.79 8-4-3.58-4-8-4zM4 9v3c0 2.21 3.58 4 8 4s8-1.79 8-4V9c0 2.21-3.58 4-8 4s-8-1.79-8-4zm0 5v3c0 2.21 3.58 4 8 4s8-1.79 8-4v-3c0 2.21-3.58 4-8 4s-8-1.79-8-4z"/></svg>'),
(@mnu_meta_class, @mnu_meta_folder, '010', 'meta_class', 'Logické třídy (Objekty)', 'Správa logických entit, jejich vlastností a překladů', @tgt_meta_class, 'U', '<svg viewBox="0 0 24 24" fill="#4F46E5"><path d="M12 2l-5.5 9h11L12 2zm0 3.84L13.93 9h-3.87L12 5.84zM17.5 13c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zm0 7c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5zM3 21.5h8v-8H3v8zm2-6h4v4H5v-4z"/></svg>'),
(@mnu_meta_column, @mnu_meta_folder, '020', 'meta_column', 'Sloupce metadat', 'Správa definic sloupců, formulářových prvků a překladů', @tgt_meta_column, 'U', '<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M14.67 5v14H9.33V5h5.34zm1 14H21V5h-5.33v14zm-7.34 0V5H3v14h5.33z"/></svg>'),
(@mnu_meta_phrase, @mnu_meta_folder, '030', 'meta_phrase', 'Textové fráze a překlady', 'Správa textových frází, tlačítek a jazykových mutací', @tgt_meta_phrase, 'U', '<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94 2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v1.99h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.3 9.19 6.69 8h-2c.73 1.63 1.73 3.17 2.98 4.56l-5.09 5.02L4 19l5-5 3.11 3.11.76-2.04zM18.5 10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z"/></svg>'),
(@mnu_meta_menu, @mnu_meta_folder, '040', 'meta_menu', 'Položky menu (Navigace)', 'Úprava hierarchie, pořadí, cílových stránek a překladů položek menu', @tgt_meta_menu, 'U', '<svg viewBox="0 0 24 24" fill="#D97706"><path d="M3 18h13v-2H3v2zm0-5h10v-2H3v2zm0-7v2h13V6H3zm18 9.59L17.42 12 21 8.41 19.59 7l-5 5 5 5L21 15.59z"/></svg>'),
(@mnu_excel_reader, @mnu_meta_folder, '050', 'excel_reader', 'Import dat z Excelu', 'Hromadný import a kontrola metadat ze souboru XLSX', @tgt_excel_reader, 'S', '<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm4 18H6V4h7v5h5v11zM8 15.01l1.41 1.41L11 14.84V19h2v-4.16l1.59 1.59L16 15.01 12.01 11 8 15.01z"/></svg>'),
(@mnu_xlsx_export_meta, @mnu_meta_folder, '060', 'xlsx_export_meta', 'Export metadat do Excelu', 'Zpětný export systémových metadat do souboru XLSX', @tgt_xlsx_export_meta, 'S', '<svg viewBox="0 0 24 24" fill="#0D9488"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm4 18H6V4h7v5h5v11zm-2-6.99l-1.41-1.41L13 15.16V11h-2v4.16l-1.59-1.59L8 13.01 12.01 17 16 13.01z"/></svg>'),

-- 1. úroveň: Složka "Systémová administrace" (sort_code = '090') a její podřízené položky po desítkách
(@mnu_admin, @mnu_home, '090', 'admin_folder', 'Systémová administrace', 'Schvalování změn, správa organizací, licencí, uživatelů, přenos datových balíčků, provozní deník a aktivita uživatelů', NULL, 'U', '<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.06-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.73,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.06,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59,0.22l1.92-3.32c0.12-0.22,0.07-0.49-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>'),
(@mnu_approval, @mnu_admin, '010', 'approval', 'Schvalování změn', 'Posouzení, schvalování a vracení navržených změn záznamů', @tgt_approval, 'U', '<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>'),
(@mnu_organization, @mnu_admin, '020', 'organization', 'Správa a nastavení organizace', 'Přehled, nastavení organizace a výpočtových parametrů CRMM', @tgt_organization, 'A', '<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>'),
(@mnu_org_licence, @mnu_admin, '030', 'organization_licence', 'Správa licencí organizací', 'Evidence žádostí o licenci a aktivace nových organizací', @tgt_org_licence, 'A', '<svg viewBox="0 0 24 24" fill="#D97706"><path d="M20 2H4c-1.11 0-2 .89-2 2v11c0 1.11.89 2 2 2h4v5l4-2 4 2v-5h4c1.11 0 2-.89 2-2V4c0-1.11-.89-2-2-2zm0 13H4v-2h16v2zm0-5H4V4h16v6z"/></svg>'),
(@mnu_org_users, @mnu_admin, '040', 'org_users', 'Uživatelé organizace', 'Správa uživatelů, oprávnění a žádostí o přístup v organizaci', @tgt_org_users, 'A', '<svg viewBox="0 0 24 24" fill="#6366F1"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>'),
(@mnu_csv_package, @mnu_admin, '050', 'csv_package', 'Přenos balíčků (CSV/TSV)', 'Export a dvoufázový import datových balíčků mezi instancemi', @tgt_csv_package, 'S', '<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>'),
(@mnu_service_logbook, @mnu_admin, '060', 'service_logbook', 'Provozní deník (Logbook)', 'Přehled historie provedených upgradů databáze a importů systémových dávek', @tgt_service_logbook, 'S', '<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>'),
(@mnu_audit_login, @mnu_admin, '070', 'audit_login_session', 'Aktivita uživatelů', 'Přehled přihlášení a aktivity uživatelů z tabulky audit_login_session', @tgt_audit_login, 'A', '<svg viewBox="0 0 24 24" fill="#0D9488"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>');

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

-- 6. Aktualizace výchozí hierarchie a system_role u 'A' záznamů (pokud nebyly ručně upraveny)
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
		OR i.builtin_code IN ('organization', 'organization_licence', 'hierarchy', 'hierarchy_item', 'countermeasure', 'countermeasure_state', 'scale', 'scale_value')
	)
	AND (
		ISNULL(m.parent_uuid, 0x00) <> ISNULL(i.parent_uuid, 0x00)
		OR m.sort_code <> i.sort_code
		OR ISNULL(m.target_object, 0x00) <> ISNULL(i.target_object, 0x00)
		OR m.system_role <> i.system_role
		OR (m.helptext = '' AND i.helptext <> '')
	);

-- 7. Technické atributy v jazykových záznamech 'L' zrcadlí svůj hlavní 'A' záznam
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

-- 8. Aktualizace dosud nezadaných nebo výchozích monochromatických ikon u 'A' záznamů

UPDATE m
SET m.svg_icon = i.svg_icon
FROM meta_menu m
JOIN @init_menu i ON i.original = m.original
WHERE m.object_owner = @sys_owner
	AND m.record_type = 'A'
	AND (
		ISNULL(m.svg_icon, '') = ''
		OR m.svg_icon LIKE '%fill="currentColor"%'
	);

GO