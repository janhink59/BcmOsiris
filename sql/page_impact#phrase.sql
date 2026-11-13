/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_impact#phrase.sql
 * Účel:   Registrace stránky page_impact do sysinit_object, položky menu
 *         impact do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_impact';
DELETE FROM sysinit_menu WHERE builtin_code = 'impact';
DELETE FROM sysinit_phrase WHERE source_code = 'page_impact';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_impact','cs','U','Katalog dopadů (CRMM)','Správa hierarchického číselníku dopadů v modulu CRMM'),
('P','page_impact','en','U','Impact Catalog (CRMM)','Management of the hierarchical impact catalog in CRMM');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('impact','cs','crmm_folder','030','page_impact','','U','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z"/></svg>','Katalog dopadů','Správa hierarchického katalogu druhů a oblastí dopadů','Správa hierarchického katalogu druhů a oblastí dopadů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('impact','en','Impact Catalog','Management of the hierarchical catalog of impact types and areas','Management of the hierarchical catalog of impact types and areas');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_impact','btn_new_impact','cs','+ Nový dopad','Založí novou oblast nebo položku dopadu v katalogu',''),
('page_impact','grp_identification','cs','Kód, zařazení ve stromu a ikona','',''),
('page_impact','grp_permissions_protection','cs','Oprávnění, platnost a ochrana záznamu','',''),
('page_impact','grp_presentation','cs','Prezentační texty a popis dopadu','',''),
('page_impact','header_edit_impact','cs','Dopad','',''),
('page_impact','header_new_impact','cs','Nový dopad','',''),
('page_impact','master_heading','cs','Strom katalogu dopadů','',''),
('page_impact','page_title','cs','Katalog dopadů (CRMM)','',''),
('page_impact','th_impact_caption','cs','Druh / Oblast dopadu','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_impact','btn_new_impact','en','+ New Impact','Create a new impact area or item in the catalog'),
('page_impact','grp_identification','en','Code, Tree Placement & Icon',''),
('page_impact','grp_permissions_protection','en','Permissions, Validity & Record Protection',''),
('page_impact','grp_presentation','en','Presentation Texts & Impact Description',''),
('page_impact','header_edit_impact','en','Impact',''),
('page_impact','header_new_impact','en','New Impact',''),
('page_impact','master_heading','en','Impact Catalog Tree',''),
('page_impact','page_title','en','Impact Catalog (CRMM)',''),
('page_impact','th_impact_caption','en','Impact Type / Area','');
GO