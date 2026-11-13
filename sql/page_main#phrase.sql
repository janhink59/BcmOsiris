/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_main#phrase.sql
 * Účel:   Registrace stránky page_main do sysinit_object, kořenové položky
 *         home a hlavních rozcestníkových složek menu (crmm_analysis_folder,
 *         crmm_folder, metadata_folder, admin_folder) do sysinit_menu a frází
 *         do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_main';
DELETE FROM sysinit_menu WHERE builtin_code IN ('home', 'crmm_analysis_folder', 'crmm_folder', 'metadata_folder', 'admin_folder');
DELETE FROM sysinit_phrase WHERE source_code = 'page_main';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_main','cs','U','Hlavní panel','Úvodní rozcestník aplikace po přihlášení'),
('P','page_main','en','U','Main Dashboard','Main application dashboard after login');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('admin_folder','cs','home','090','','','U','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.06-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.73,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.06,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59,0.22l1.92-3.32c0.12-0.22,0.07-0.49-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>','Systémová administrace','Schvalování změn, správa organizací, licencí, uživatelů, přenos datových balíčků, provozní deník a aktivita uživatelů','Schvalování změn, správa organizací, licencí, uživatelů, přenos datových balíčků, provozní deník a aktivita uživatelů'),
('crmm_analysis_folder','cs','home','010','','','U','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z"/></svg>','Analýza a řízení rizik (CRMM)','Provozní agenda CRMM: evidence prostorů a aktiv, správa závislostí, hodnocení rizikových scénářů a implementace protiopatření','Provozní agenda CRMM: evidence prostorů a aktiv, správa závislostí, hodnocení rizikových scénářů a implementace protiopatření'),
('crmm_folder','cs','home','020','','','U','<svg viewBox="0 0 24 24" fill="#4F46E5"><path d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/></svg>','Nastavení a katalogy CRMM','Metodické nastavení systému CRMM pro organizaci: katalogy tříd aktiv, hrozeb, dopadů, scénářů, protiopatření, hodnotících škál, sekundárních hierarchií, typů vazeb a schémat sítí','Metodické nastavení systému CRMM pro organizaci: katalogy tříd aktiv, hrozeb, dopadů, scénářů, protiopatření, hodnotících škál, sekundárních hierarchií, typů vazeb a schémat sítí'),
('home','cs','','000','page_main','','U','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>','Domů','Úvodní rozcestník aplikace','Úvodní rozcestník aplikace'),
('metadata_folder','cs','home','080','','','U','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 3C7.58 3 4 4.79 4 7s3.58 4 8 4 8-1.79 8-4-3.58-4-8-4zM4 9v3c0 2.21 3.58 4 8 4s8-1.79 8-4V9c0 2.21-3.58 4-8 4s-8-1.79-8-4zm0 5v3c0 2.21 3.58 4 8 4s8-1.79 8-4v-3c0 2.21-3.58 4-8 4s-8-1.79-8-4z"/></svg>','Práce s metadaty','Správa logických tříd, sloupců, textových frází, navigace a vývojářských balíčků metadat','Správa logických tříd, sloupců, textových frází, navigace a vývojářských balíčků metadat');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('admin_folder','en','System Administration','Change approval, management of organizations, licences, users, data package transfer, service logbook, and user activity','Change approval, management of organizations, licences, users, data package transfer, service logbook, and user activity'),
('crmm_analysis_folder','en','Risk Analysis & Management (CRMM)','Operational CRMM agenda: spaces and asset inventory, dependency links, risk scenario assessments, and countermeasure implementation','Operational CRMM agenda: spaces and asset inventory, dependency links, risk scenario assessments, and countermeasure implementation'),
('crmm_folder','en','CRMM Configuration & Catalogs','Methodological configuration of the CRMM system: catalogs of asset classes, threats, impacts, scenarios, countermeasures, assessment scales, secondary hierarchies, link types, and network diagrams','Methodological configuration of the CRMM system: catalogs of asset classes, threats, impacts, scenarios, countermeasures, assessment scales, secondary hierarchies, link types, and network diagrams'),
('home','en','Home','Main application dashboard','Main application dashboard'),
('metadata_folder','en','Metadata Management','Management of logical classes, columns, text phrases, navigation, and developer metadata packages','Management of logical classes, columns, text phrases, navigation, and developer metadata packages');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_main','empty_menu','cs','Pro vaši roli nejsou v této složce dostupné žádné položky.','',''),
('page_main','heading_dashboard','cs','Hlavní rozcestník aplikace','',''),
('page_main','page_title','cs','Hlavní panel - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_main','empty_menu','en','No items are available in this folder for your current role.',''),
('page_main','heading_dashboard','en','Application Dashboard',''),
('page_main','page_title','en','Main Dashboard - BCM Osiris','');
GO