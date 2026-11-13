/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_scale#phrase.sql
 * Účel:   Registrace stránky page_scale do sysinit_object, položky menu
 *         scale do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_scale';
DELETE FROM sysinit_menu WHERE builtin_code = 'scale';
DELETE FROM sysinit_phrase WHERE source_code = 'page_scale';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_scale','cs','U','Hodnotící škály (CRMM)','Správa definic hodnotících škál pro hrozby, zranitelnosti, dopady a rizika'),
('P','page_scale','en','U','Assessment Scales (CRMM)','Management of assessment scale definitions for threats, vulnerabilities, impacts, and risks');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('scale','cs','crmm_folder','070','page_scale','','U','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/></svg>','Hodnotící škály','Správa hodnotících škál pro hrozby, zranitelnosti, dopady a výsledná rizika','Správa hodnotících škál pro hrozby, zranitelnosti, dopady a výsledná rizika');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('scale','en','Assessment Scales','Management of assessment scales for threats, vulnerabilities, impacts, and resulting risks','Management of assessment scales for threats, vulnerabilities, impacts, and resulting risks');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_scale','btn_manage_scale_values','cs','Spravovat stupně škály ({$count}) →','Přejde do správy jednotlivých stupňů, prahů a skóre této škály','btn-secondary'),
('page_scale','btn_new_scale','cs','+ Nová hodnotící škála','Založí novou hodnotící škálu a automaticky vygeneruje výchozí stupně',''),
('page_scale','grp_identification','cs','Kód, druh veličiny, priorita a výchozí počet stupňů','',''),
('page_scale','grp_presentation','cs','Název a metodický popis škály','',''),
('page_scale','grp_protection','cs','Platnost a ochrana záznamu','',''),
('page_scale','header_edit_scale','cs','Hodnotící škála','',''),
('page_scale','header_new_scale','cs','Nová hodnotící škála','',''),
('page_scale','lbl_filter_scale_type','cs','Filtrovat podle druhu škály:','',''),
('page_scale','msg_initial_levels_hint','cs','Při prvním uložení nové škály systém automaticky vygeneruje zadaný počet stupňů (initial_levels) rovnoměrně rozložených v intervalu 0 až 100 %.','',''),
('page_scale','opt_all_scale_types','cs','--- Všechny druhy škál ---','',''),
('page_scale','page_title','cs','Hodnotící škály (CRMM)','',''),
('page_scale','th_builtin_code','cs','Kód','',''),
('page_scale','th_caption','cs','Název škály','',''),
('page_scale','th_priority','cs','Priorita','',''),
('page_scale','th_scale_type','cs','Druh','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_scale','btn_manage_scale_values','en','Manage Scale Levels ({$count}) →','Open management of individual levels, thresholds, and scores for this scale'),
('page_scale','btn_new_scale','en','+ New Assessment Scale','Create a new assessment scale and automatically generate default levels'),
('page_scale','grp_identification','en','Code, Quantity Type, Priority & Initial Level Count',''),
('page_scale','grp_presentation','en','Scale Name & Methodological Description',''),
('page_scale','grp_protection','en','Validity & Record Protection',''),
('page_scale','header_edit_scale','en','Assessment Scale',''),
('page_scale','header_new_scale','en','New Assessment Scale',''),
('page_scale','lbl_filter_scale_type','en','Filter by Scale Type:',''),
('page_scale','msg_initial_levels_hint','en','When saving a new scale for the first time, the system automatically generates the specified number of levels (initial_levels) evenly distributed across the 0 to 100% range.',''),
('page_scale','opt_all_scale_types','en','--- All Scale Types ---',''),
('page_scale','page_title','en','Assessment Scales (CRMM)',''),
('page_scale','th_builtin_code','en','Code',''),
('page_scale','th_caption','en','Scale Name',''),
('page_scale','th_priority','en','Priority',''),
('page_scale','th_scale_type','en','Type','');
GO