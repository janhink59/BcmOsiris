/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_scenario#phrase.sql
 * Účel:   Registrace stránky page_scenario do sysinit_object, položky menu
 *         scenario do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_scenario';
DELETE FROM sysinit_menu WHERE builtin_code = 'scenario';
DELETE FROM sysinit_phrase WHERE source_code = 'page_scenario';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_scenario','cs','U','Rizikové scénáře (Katalog CRMM)','Správa hierarchického katalogu rizikových scénářů a událostí v modulu CRMM'),
('P','page_scenario','en','U','Risk Scenarios (CRMM Catalog)','Management of the hierarchical catalog of risk scenarios and events in CRMM');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('scenario','cs','crmm_folder','040','page_scenario','','U','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z"/></svg>','Rizikové scénáře','Správa hierarchického katalogu rizikových scénářů (událostí) a mezí reziduálního rizika','Správa hierarchického katalogu rizikových scénářů (událostí) a mezí reziduálního rizika');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('scenario','en','Risk Scenarios','Management of the hierarchical catalog of risk scenarios (events) and minimum residual risk thresholds','Management of the hierarchical catalog of risk scenarios (events) and minimum residual risk thresholds');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_scenario','btn_new_scenario','cs','+ Nový rizikový scénář','Založí novou skupinu nebo koncový rizikový scénář v katalogu',''),
('page_scenario','grp_identification','cs','Kód, zařazení ve stromu a ikona','',''),
('page_scenario','grp_permissions_protection','cs','Oprávnění, platnost a ochrana záznamu','',''),
('page_scenario','grp_presentation','cs','Prezentační texty a popis scénáře','',''),
('page_scenario','grp_relations_risk','cs','Působící hrozba, cílová třída aktiv a mez reziduálního rizika','',''),
('page_scenario','header_edit_scenario','cs','Rizikový scénář','',''),
('page_scenario','header_new_scenario','cs','Nový rizikový scénář','',''),
('page_scenario','master_heading','cs','Strom rizikových scénářů','',''),
('page_scenario','page_title','cs','Rizikové scénáře (Katalog CRMM)','',''),
('page_scenario','th_min_res_risk','cs','Min. rez.','',''),
('page_scenario','th_scenario_caption','cs','Rizikový scénář','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_scenario','btn_new_scenario','en','+ New Risk Scenario','Create a new group or leaf risk scenario in the catalog'),
('page_scenario','grp_identification','en','Code, Tree Placement & Icon',''),
('page_scenario','grp_permissions_protection','en','Permissions, Validity & Record Protection',''),
('page_scenario','grp_presentation','en','Presentation Texts & Scenario Description',''),
('page_scenario','grp_relations_risk','en','Causing Threat, Target Asset Class & Minimum Residual Risk',''),
('page_scenario','header_edit_scenario','en','Risk Scenario',''),
('page_scenario','header_new_scenario','en','New Risk Scenario',''),
('page_scenario','master_heading','en','Risk Scenario Tree',''),
('page_scenario','page_title','en','Risk Scenarios (CRMM Catalog)',''),
('page_scenario','th_min_res_risk','en','Min. Res.',''),
('page_scenario','th_scenario_caption','en','Risk Scenario','');
GO