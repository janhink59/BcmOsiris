/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_scenario_assessment#phrase.sql
 * Účel:   Registrace stránky page_scenario_assessment do sysinit_object,
 *         položky menu scenario_assessment do sysinit_menu a frází
 *         do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_scenario_assessment';
DELETE FROM sysinit_menu WHERE builtin_code = 'scenario_assessment';
DELETE FROM sysinit_phrase WHERE source_code = 'page_scenario_assessment';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_scenario_assessment','cs','U','Hodnocení rizikových scénářů (CRMM)','Vyhodnocení velikosti hrozby, zranitelnosti, dopadu a míry rizika scénářů nad aktivy organizace'),
('P','page_scenario_assessment','en','U','Risk Scenario Assessments (CRMM)','Evaluation of threat level, vulnerability, impact, and risk of scenarios across organization assets');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('scenario_assessment','cs','crmm_analysis_folder','040','page_scenario_assessment','','U','<svg viewBox="0 0 24 24" fill="#DC2626"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z"/></svg>','Hodnocení rizikových scénářů','Vyhodnocení velikosti hrozby, zranitelnosti, dopadu a vypočteného inherentního i zbytkového rizika scénářů nad aktivy','Vyhodnocení velikosti hrozby, zranitelnosti, dopadu a vypočteného inherentního i zbytkového rizika scénářů nad aktivy');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('scenario_assessment','en','Risk Scenario Assessments','Evaluation of threat level, vulnerability, impact, and calculated inherent and residual risk of scenarios on organization assets','Evaluation of threat level, vulnerability, impact, and calculated inherent and residual risk of scenarios on organization assets');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_scenario_assessment','btn_back_to_asset','cs','← Zpět na aktivum: {$asset}','Návrat na detail filtrovaného aktiva','btn-secondary'),
('page_scenario_assessment','btn_new_assessment','cs','+ Nové hodnocení scénáře','Založí nové hodnocení rizikového scénáře nad aktivem',''),
('page_scenario_assessment','btn_recalculate_crmm','cs','↻ Přepočítat rizika','Spustí přepočet efektivních faktorů opatření, scénářů a agregovaných rizik aktiv','btn-secondary'),
('page_scenario_assessment','grp_asset_scenario','cs','Hodnocené aktivum a rizikový scénář','',''),
('page_scenario_assessment','grp_calculated_risk','cs','Vypočtené inherentní riziko, redukce a zbytkové riziko (0 až 100 %)','',''),
('page_scenario_assessment','grp_input_scores','cs','Vstupní hodnocení hrozby, zranitelnosti a dopadu (0 až 100 %)','',''),
('page_scenario_assessment','grp_justification_audit','cs','Zdůvodnění hodnocení, poznámka a odpovědná osoba','',''),
('page_scenario_assessment','header_edit_assessment','cs','Hodnocení scénáře','',''),
('page_scenario_assessment','header_new_assessment','cs','Nové hodnocení rizikového scénáře','',''),
('page_scenario_assessment','lbl_filter_asset','cs','Hodnocené aktivum:','',''),
('page_scenario_assessment','lbl_sum_floor','cs','Min. práh:','',''),
('page_scenario_assessment','lbl_sum_inherent','cs','Inherentní riziko:','',''),
('page_scenario_assessment','lbl_sum_reduction','cs','Redukce opatřeními:','',''),
('page_scenario_assessment','lbl_sum_residual','cs','Zbytkové (reziduální) riziko:','',''),
('page_scenario_assessment','opt_all_assets','cs','--- Všechna hodnocená aktiva ---','',''),
('page_scenario_assessment','page_title','cs','Hodnocení rizikových scénářů (CRMM)','',''),
('page_scenario_assessment','th_assess_caption','cs','Hodnocený scénář / Popis','',''),
('page_scenario_assessment','th_assess_date','cs','Datum','',''),
('page_scenario_assessment','th_inherent_risk','cs','Inh. riziko (%)','',''),
('page_scenario_assessment','th_residual_risk','cs','Rez. riziko (%)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_scenario_assessment','btn_back_to_asset','en','← Back to Asset: {$asset}','Return to the filtered asset detail'),
('page_scenario_assessment','btn_new_assessment','en','+ New Scenario Assessment','Create a new risk scenario assessment on an asset'),
('page_scenario_assessment','btn_recalculate_crmm','en','↻ Recalculate Risks','Recalculate effective control factors, scenario risks, and aggregated asset risks'),
('page_scenario_assessment','grp_asset_scenario','en','Assessed Asset & Risk Scenario',''),
('page_scenario_assessment','grp_calculated_risk','en','Calculated Inherent Risk, Reduction & Residual Risk (0 to 100%)',''),
('page_scenario_assessment','grp_input_scores','en','Input Threat, Vulnerability & Impact Scores (0 to 100%)',''),
('page_scenario_assessment','grp_justification_audit','en','Assessment Justification, Note & Assessor',''),
('page_scenario_assessment','header_edit_assessment','en','Scenario Assessment',''),
('page_scenario_assessment','header_new_assessment','en','New Risk Scenario Assessment',''),
('page_scenario_assessment','lbl_filter_asset','en','Assessed Asset:',''),
('page_scenario_assessment','lbl_sum_floor','en','Min. Floor:',''),
('page_scenario_assessment','lbl_sum_inherent','en','Inherent Risk:',''),
('page_scenario_assessment','lbl_sum_reduction','en','Control Reduction:',''),
('page_scenario_assessment','lbl_sum_residual','en','Residual Risk:',''),
('page_scenario_assessment','opt_all_assets','en','--- All Assessed Assets ---',''),
('page_scenario_assessment','page_title','en','Risk Scenario Assessments (CRMM)',''),
('page_scenario_assessment','th_assess_caption','en','Assessed Scenario / Description',''),
('page_scenario_assessment','th_assess_date','en','Date',''),
('page_scenario_assessment','th_inherent_risk','en','Inh. Risk (%)',''),
('page_scenario_assessment','th_residual_risk','en','Res. Risk (%)','');
GO