/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: page_countermeasure_implementation#phrase.sql
 * Účel:   Registrace stránky page_countermeasure_implementation do sysinit_object,
 *         položky menu countermeasure_implementation do sysinit_menu a frází
 *         do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_countermeasure_implementation';
DELETE FROM sysinit_menu WHERE builtin_code = 'countermeasure_implementation';
DELETE FROM sysinit_phrase WHERE source_code = 'page_countermeasure_implementation';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_countermeasure_implementation','cs','U','Implementace protiopatření (CRMM)','Evidence stavu zavedení protiopatření na aktivech a prostorech organizace'),
('P','page_countermeasure_implementation','en','U','Countermeasure Implementation (CRMM)','Registry of the implementation state of countermeasures on organization assets and spaces');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('countermeasure_implementation','cs','crmm_analysis_folder','050','page_countermeasure_implementation','','U','<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z"/></svg>','Implementace protiopatření','Evidence stavu zavedení jednotlivých bezpečnostních protiopatření u konkrétních aktiv a prostorů','Evidence stavu zavedení jednotlivých bezpečnostních protiopatření u konkrétních aktiv a prostorů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('countermeasure_implementation','en','Countermeasure Implementation','Registry of the implementation status of security countermeasures across specific assets and spaces','Registry of the implementation status of security countermeasures across specific assets and spaces');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_countermeasure_implementation','btn_back_to_asset','cs','← Zpět na aktivum: {$asset}','Návrat na detail aktiva','btn-secondary'),
('page_countermeasure_implementation','btn_new_cm_impl','cs','+ Nová implementace opatření','Založí nový záznam implementace protiopatření',''),
('page_countermeasure_implementation','grp_asset_cm_state','cs','Chráněné aktivum, aplikované protiopatření a stav zavedení','',''),
('page_countermeasure_implementation','grp_presentation','cs','Popis realizace opatření a poznámky z kontroly','',''),
('page_countermeasure_implementation','grp_responsibility_factors','cs','Odpovědnost, termíny a vypočtené efektivní faktory (0 až 100 %)','',''),
('page_countermeasure_implementation','grp_validity','cs','Platnost záznamu','',''),
('page_countermeasure_implementation','header_edit_cm_impl','cs','Implementace opatření','',''),
('page_countermeasure_implementation','header_new_cm_impl','cs','Nová implementace protiopatření','',''),
('page_countermeasure_implementation','lbl_filter_asset','cs','Chráněné aktivum / prostor:','',''),
('page_countermeasure_implementation','lbl_summary_eff_reduction','cs','Efektivní redukce rizika scénářů:','',''),
('page_countermeasure_implementation','lbl_summary_eff_risk','cs','Efektivní spodní práh rizika (při neimplementaci):','',''),
('page_countermeasure_implementation','opt_all_assets','cs','--- Všechna aktiva a prostory ---','',''),
('page_countermeasure_implementation','page_title','cs','Implementace protiopatření (CRMM)','',''),
('page_countermeasure_implementation','th_eff_reduction','cs','Ef. redukce (%)','',''),
('page_countermeasure_implementation','th_eff_risk','cs','Ef. práh rizika (%)','',''),
('page_countermeasure_implementation','th_impl_caption','cs','Popis implementace / Opatření','',''),
('page_countermeasure_implementation','th_target_date','cs','Termín','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_countermeasure_implementation','btn_back_to_asset','en','← Back to Asset: {$asset}','Return to the asset detail'),
('page_countermeasure_implementation','btn_new_cm_impl','en','+ New Control Implementation','Create a new countermeasure implementation record'),
('page_countermeasure_implementation','grp_asset_cm_state','en','Protected Asset, Applied Countermeasure & Implementation State',''),
('page_countermeasure_implementation','grp_presentation','en','Implementation Description & Audit Notes',''),
('page_countermeasure_implementation','grp_responsibility_factors','en','Responsibility, Dates & Calculated Effective Factors (0 to 100%)',''),
('page_countermeasure_implementation','grp_validity','en','Record Validity',''),
('page_countermeasure_implementation','header_edit_cm_impl','en','Control Implementation',''),
('page_countermeasure_implementation','header_new_cm_impl','en','New Countermeasure Implementation',''),
('page_countermeasure_implementation','lbl_filter_asset','en','Protected Asset / Space:',''),
('page_countermeasure_implementation','lbl_summary_eff_reduction','en','Effective Scenario Risk Reduction:',''),
('page_countermeasure_implementation','lbl_summary_eff_risk','en','Effective Minimum Risk Floor (When Unimplemented):',''),
('page_countermeasure_implementation','opt_all_assets','en','--- All Assets & Spaces ---',''),
('page_countermeasure_implementation','page_title','en','Countermeasure Implementation (CRMM)',''),
('page_countermeasure_implementation','th_eff_reduction','en','Eff. Reduction (%)',''),
('page_countermeasure_implementation','th_eff_risk','en','Eff. Risk Floor (%)',''),
('page_countermeasure_implementation','th_impl_caption','en','Implementation Description / Control',''),
('page_countermeasure_implementation','th_target_date','en','Target Date','');
GO