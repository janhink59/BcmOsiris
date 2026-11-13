/* =============================================================================
 * Verze: 2026-11-13 16:45
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
('page_scale_value','grp_identification','cs','Nadřazená škála a unikátní kód stupně','',''),
('page_scale_value','grp_presentation','cs','Název, zkratka, barva a popis stupně','',''),
('page_scale_value','grp_protection','cs','Platnost a ochrana záznamu','',''),
('page_scale_value','grp_thresholds','cs','Dolní práh intervalu a výpočtové skóre (0 až 100 %)','',''),
('page_scale_value','header_edit_level','cs','Stupeň hodnotící škály','',''),
('page_scale_value','header_new_level','cs','Nový stupeň hodnotící škály','',''),
('page_scale_value','lbl_interval_preview','cs','Platný interval stupně:','',''),
('page_scale_value','lbl_select_scale','cs','Zvolte hodnotící škálu:','',''),
('page_scale_value','master_heading','cs','Stupně škály (seřazeno podle prahu)','',''),
('page_scale_value','msg_no_scale_defined','cs','V systému zatím není definována žádná hodnotící škála. Založte ji nejprve na stránce Hodnotící škály.','',''),
('page_scale_value','page_title','cs','Stupně hodnotících škál (CRMM)','',''),
('page_scale_value','page_title_with_scale','cs','Stupně škály: {$scale}','',''),
('page_scale_value','th_level_caption','cs','Stupeň škály','',''),
('page_scale_value','th_score_value','cs','Skóre (%)','',''),
('page_scale_value','th_threshold_value','cs','Od prahu (%)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_scale_value','btn_back_to_scale','en','← Back to Scale: {$parent}','Return to the parent assessment scale detail'),
('page_scale_value','btn_new_scale_value','en','+ New Scale Level','Add a new level to the selected assessment scale'),
('page_scale_value','grp_identification','en','Parent Scale & Unique Level Code',''),
('page_scale_value','grp_presentation','en','Name, Short Name, Color & Level Description',''),
('page_scale_value','grp_protection','en','Validity & Record Protection',''),
('page_scale_value','grp_thresholds','en','Lower Interval Threshold & Calculation Score (0 to 100%)',''),
('page_scale_value','header_edit_level','en','Assessment Scale Level',''),
('page_scale_value','header_new_level','en','New Assessment Scale Level',''),
('page_scale_value','lbl_interval_preview','en','Effective Level Interval:',''),
('page_scale_value','lbl_select_scale','en','Select Assessment Scale:',''),
('page_scale_value','master_heading','en','Scale Levels (Sorted by Threshold)',''),
('page_scale_value','msg_no_scale_defined','en','No assessment scale is defined in the system yet. Please create one first on the Assessment Scales page.',''),
('page_scale_value','page_title','en','Assessment Scale Levels (CRMM)',''),
('page_scale_value','page_title_with_scale','en','Scale Levels: {$scale}',''),
('page_scale_value','th_level_caption','en','Scale Level',''),
('page_scale_value','th_score_value','en','Score (%)',''),
('page_scale_value','th_threshold_value','en','Threshold (%)','');
GO