/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: page_countermeasure#phrase.sql
 * Účel:   Registrace stránky page_countermeasure do sysinit_object, položky
 *         menu countermeasure do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_countermeasure';
DELETE FROM sysinit_menu WHERE builtin_code = 'countermeasure';
DELETE FROM sysinit_phrase WHERE source_code = 'page_countermeasure';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_countermeasure','cs','U','Katalog protiopatření (CRMM)','Správa hierarchického katalogu bezpečnostních a provozních protiopatření v modulu CRMM'),
('P','page_countermeasure','en','U','Countermeasure Catalog (CRMM)','Management of the hierarchical catalog of security and operational countermeasures in CRMM');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('countermeasure','cs','crmm_folder','050','page_countermeasure','','U','<svg viewBox="0 0 24 24" fill="#059669"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z"/></svg>','Katalog protiopatření','Správa hierarchického katalogu bezpečnostních a provozních protiopatření a jejich redukčních a rizikových faktorů','Správa hierarchického katalogu bezpečnostních a provozních protiopatření a jejich redukčních a rizikových faktorů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('countermeasure','en','Countermeasure Catalog','Management of the hierarchical catalog of security and operational countermeasures and their reduction and risk factors','Management of the hierarchical catalog of security and operational countermeasures and their reduction and risk factors');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_countermeasure','btn_new_countermeasure','cs','+ Nové protiopatření','Založí novou skupinu nebo koncové protiopatření v katalogu',''),
('page_countermeasure','grp_factors','cs','Redukční a prahový rizikový faktor (0 až 100 %)','',''),
('page_countermeasure','grp_identification','cs','Kód, zařazení ve stromu a ikona','',''),
('page_countermeasure','grp_permissions_protection','cs','Oprávnění, platnost a ochrana záznamu','',''),
('page_countermeasure','grp_presentation','cs','Prezentační texty a popis opatření','',''),
('page_countermeasure','header_edit_countermeasure','cs','Protiopatření','',''),
('page_countermeasure','header_new_countermeasure','cs','Nové protiopatření','',''),
('page_countermeasure','master_heading','cs','Strom katalogu protiopatření','',''),
('page_countermeasure','page_title','cs','Katalog protiopatření (CRMM)','',''),
('page_countermeasure','th_cm_caption','cs','Protiopatření','',''),
('page_countermeasure','th_reduction_factor','cs','Redukce (%)','',''),
('page_countermeasure','th_risk_factor','cs','Práh (%)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_countermeasure','btn_new_countermeasure','en','+ New Countermeasure','Create a new group or leaf countermeasure in the catalog'),
('page_countermeasure','grp_factors','en','Reduction & Minimum Risk Threshold Factors (0 to 100%)',''),
('page_countermeasure','grp_identification','en','Code, Tree Placement & Icon',''),
('page_countermeasure','grp_permissions_protection','en','Permissions, Validity & Record Protection',''),
('page_countermeasure','grp_presentation','en','Presentation Texts & Countermeasure Description',''),
('page_countermeasure','header_edit_countermeasure','en','Countermeasure',''),
('page_countermeasure','header_new_countermeasure','en','New Countermeasure',''),
('page_countermeasure','master_heading','en','Countermeasure Catalog Tree',''),
('page_countermeasure','page_title','en','Countermeasure Catalog (CRMM)',''),
('page_countermeasure','th_cm_caption','en','Countermeasure',''),
('page_countermeasure','th_reduction_factor','en','Reduction (%)',''),
('page_countermeasure','th_risk_factor','en','Floor (%)','');
GO