/* =============================================================================
 * Verze: 2026-11-15 20:05
 * Soubor: page_scale_value#phrase.sql
 * Účel:   Registrace stránky page_scale_value do sysinit_object, položky menu
 *         scale_value do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_scale_value';
DELETE FROM sysinit_menu WHERE builtin_code = 'scale_value';
DELETE FROM sysinit_phrase WHERE source_code = 'page_scale_value';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_scale_value','cs','U','Stupně hodnotících škál (CRMM)','Správa jednotlivých stupňů hodnotících škál, prahových hodnot a skóre v intervalu 0 až 100 %'),
('P','page_scale_value','en','U','Assessment Scale Levels (CRMM)','Management of individual assessment scale levels, threshold values, and scores in the 0 to 100% range');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('scale_value','cs','crmm_folder','080','page_scale_value','','U','<svg viewBox="0 0 24 24" fill="#3B82F6"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z"/></svg>','Stupně hodnotících škál','Správa jednotlivých stupňů hodnotících škál, prahových hodnot a skóre (0 až 100 %)','Správa jednotlivých stupňů hodnotících škál, prahových hodnot a skóre (0 až 100 %)');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('scale_value','en','Assessment Scale Levels','Management of individual assessment scale levels, threshold values, and scores (0 to 100 %)','Management of individual assessment scale levels, threshold values, and scores (0 to 100 %)');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_scale_value','btn_back_to_scale','cs','← Zpět na škálu: {$parent}','Návrat do detailu nadřazené hodnotící škály','btn-secondary'),
('page_scale_value','btn_new_scale_value','cs','+ Nový stupeň škály','Přidá nový stupeň do vybrané hodnotící škály',''),
('page_scale_value','grp_presentation','cs','Prezentační texty a metodický popis stupně','',''),
('page_scale_value','grp_thresholds_scores','cs','Zařazení do škály, prahová hodnota a skóre (0 až 100 %)','',''),
('page_scale_value','grp_visual_validity','cs','Vizuální atributy (semafor), platnost a ochrana','',''),
('page_scale_value','header_edit_scale_value','cs','Stupeň škály','',''),
('page_scale_value','header_new_scale_value','cs','Nový stupeň škály','',''),
('page_scale_value','lbl_select_scale','cs','Zvolená hodnotící škála:','',''),
('page_scale_value','msg_scale_value_monotonic_hint','cs','Pravidlo škály: Stupně jsou vždy seřazeny vzestupně podle dolní prahové hodnoty (threshold_value v %). Nejnižší stupeň musí začínat na 0 % a hodnoty prahů i skóre (0 až 100 %) musí tvořit monotónně rostoucí řadu.','',''),
('page_scale_value','opt_no_scale_defined','cs','--- Nejprve založte hodnotící škálu ---','',''),
('page_scale_value','page_title','cs','Stupně hodnotících škál (CRMM)','',''),
('page_scale_value','page_title_with_scale','cs','Stupně škály: {$scale}','',''),
('page_scale_value','th_level_caption','cs','Název stupně','',''),
('page_scale_value','th_score_pct','cs','Skóre (%)','',''),
('page_scale_value','th_shortname','cs','Zkratka','',''),
('page_scale_value','th_threshold_pct','cs','Práh (%)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_scale_value','btn_back_to_scale','en','← Back to Scale: {$parent}','Return to the parent assessment scale detail'),
('page_scale_value','btn_new_scale_value','en','+ New Scale Level','Add a new level to the selected assessment scale'),
('page_scale_value','grp_presentation','en','Presentation Texts & Methodological Level Description',''),
('page_scale_value','grp_thresholds_scores','en','Scale Assignment, Threshold Value & Score (0 to 100%)',''),
('page_scale_value','grp_visual_validity','en','Visual Attributes (Traffic Light), Validity & Protection',''),
('page_scale_value','header_edit_scale_value','en','Scale Level',''),
('page_scale_value','header_new_scale_value','en','New Scale Level',''),
('page_scale_value','lbl_select_scale','en','Selected Assessment Scale:',''),
('page_scale_value','msg_scale_value_monotonic_hint','en','Scale rule: Levels are always sorted ascending by their lower threshold value (threshold_value in %). The lowest level must start at 0%, and both thresholds and scores (0 to 100%) must form a strictly monotonic increasing sequence.',''),
('page_scale_value','opt_no_scale_defined','en','--- Create an assessment scale first ---',''),
('page_scale_value','page_title','en','Assessment Scale Levels (CRMM)',''),
('page_scale_value','page_title_with_scale','en','Scale Levels: {$scale}',''),
('page_scale_value','th_level_caption','en','Level Name',''),
('page_scale_value','th_score_pct','en','Score (%)',''),
('page_scale_value','th_shortname','en','Short Name',''),
('page_scale_value','th_threshold_pct','en','Threshold (%)','');
GO