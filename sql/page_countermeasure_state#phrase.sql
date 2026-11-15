/* =============================================================================
 * Verze: 2026-11-15 19:55
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
('page_countermeasure_state','btn_new_cm_state','cs','+ Nový stav opatření','Založí nový stav implementace protiopatření',''),
('page_countermeasure_state','grp_factors_ordering','cs','Výpočtové faktory stavu (0 až 100 %) a řazení','',''),
('page_countermeasure_state','grp_presentation','cs','Prezentační texty a nápověda','',''),
('page_countermeasure_state','grp_visual_validity','cs','Vizuální atributy, platnost a ochrana','',''),
('page_countermeasure_state','header_edit_cm_state','cs','Stav protiopatření','',''),
('page_countermeasure_state','header_new_cm_state','cs','Nový stav protiopatření','',''),
('page_countermeasure_state','page_title','cs','Stavy protiopatření (CRMM)','',''),
('page_countermeasure_state','th_is_default','cs','Výchozí','',''),
('page_countermeasure_state','th_reduction_pct','cs','Redukce (%)','',''),
('page_countermeasure_state','th_risk_pct','cs','Riziko (%)','',''),
('page_countermeasure_state','th_sort_code','cs','Pořadí','',''),
('page_countermeasure_state','th_state_caption','cs','Stav opatření','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_countermeasure_state','btn_new_cm_state','en','+ New Countermeasure State','Create a new countermeasure implementation state'),
('page_countermeasure_state','grp_factors_ordering','en','State Calculation Factors (0 to 100%) & Ordering',''),
('page_countermeasure_state','grp_presentation','en','Presentation Texts & Help',''),
('page_countermeasure_state','grp_visual_validity','en','Visual Attributes, Validity & Protection',''),
('page_countermeasure_state','header_edit_cm_state','en','Countermeasure State',''),
('page_countermeasure_state','header_new_cm_state','en','New Countermeasure State',''),
('page_countermeasure_state','page_title','en','Countermeasure States (CRMM)',''),
('page_countermeasure_state','th_is_default','en','Default',''),
('page_countermeasure_state','th_reduction_pct','en','Reduction (%)',''),
('page_countermeasure_state','th_risk_pct','en','Risk (%)',''),
('page_countermeasure_state','th_sort_code','en','Order',''),
('page_countermeasure_state','th_state_caption','en','Control State','');
GO