/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: page_countermeasure_state#phrase.sql
 * Účel:   Registrace stránky page_countermeasure_state do sysinit_object,
 *         položky menu countermeasure_state do sysinit_menu a frází
 *         do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_countermeasure_state';
DELETE FROM sysinit_menu WHERE builtin_code = 'countermeasure_state';
DELETE FROM sysinit_phrase WHERE source_code = 'page_countermeasure_state';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_countermeasure_state','cs','U','Stavy protiopatření (CRMM)','Správa číselníku stavů implementace protiopatření a jejich redukčních a rizikových faktorů'),
('P','page_countermeasure_state','en','U','Countermeasure States (CRMM)','Management of the codetable of countermeasure implementation states and their reduction and risk factors');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('countermeasure_state','cs','crmm_folder','060','page_countermeasure_state','','U','<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>','Stavy protiopatření','Správa číselníku stavů implementace protiopatření a jejich redukčních a rizikových faktorů','Správa číselníku stavů implementace protiopatření a jejich redukčních a rizikových faktorů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('countermeasure_state','en','Countermeasure States','Management of the codetable of countermeasure implementation states and their reduction and risk factors','Management of the codetable of countermeasure implementation states and their reduction and risk factors');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_countermeasure_state','btn_new_cm_state','cs','+ Nový stav protiopatření','Založí nový stav implementace protiopatření',''),
('page_countermeasure_state','grp_factors','cs','Váhy redukčního a rizikového faktoru (0 až 100 %)','',''),
('page_countermeasure_state','grp_identification','cs','Kód, pořadí a vizuální označení','',''),
('page_countermeasure_state','grp_presentation','cs','Název a popis stavu','',''),
('page_countermeasure_state','grp_protection','cs','Platnost a ochrana záznamu','',''),
('page_countermeasure_state','header_edit_cm_state','cs','Stav protiopatření','',''),
('page_countermeasure_state','header_new_cm_state','cs','Nový stav protiopatření','',''),
('page_countermeasure_state','page_title','cs','Stavy protiopatření (CRMM)','',''),
('page_countermeasure_state','th_builtin_code','cs','Kód','',''),
('page_countermeasure_state','th_caption','cs','Stav protiopatření','',''),
('page_countermeasure_state','th_reduction_factor','cs','Redukce (%)','',''),
('page_countermeasure_state','th_risk_factor','cs','Riziko (%)','',''),
('page_countermeasure_state','th_sort_code','cs','Pořadí','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_countermeasure_state','btn_new_cm_state','en','+ New Countermeasure State','Create a new countermeasure implementation state'),
('page_countermeasure_state','grp_factors','en','Reduction & Risk Factor Weights (0 to 100%)',''),
('page_countermeasure_state','grp_identification','en','Code, Sort Order & Visual Styling',''),
('page_countermeasure_state','grp_presentation','en','State Name & Description',''),
('page_countermeasure_state','grp_protection','en','Validity & Record Protection',''),
('page_countermeasure_state','header_edit_cm_state','en','Countermeasure State',''),
('page_countermeasure_state','header_new_cm_state','en','New Countermeasure State',''),
('page_countermeasure_state','page_title','en','Countermeasure States (CRMM)',''),
('page_countermeasure_state','th_builtin_code','en','Code',''),
('page_countermeasure_state','th_caption','en','Countermeasure State',''),
('page_countermeasure_state','th_reduction_factor','en','Reduction (%)',''),
('page_countermeasure_state','th_risk_factor','en','Risk (%)',''),
('page_countermeasure_state','th_sort_code','en','Order','');
GO