/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_link#phrase.sql
 * Účel:   Registrace stránky page_link do sysinit_object, položky menu
 *         link do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_link';
DELETE FROM sysinit_menu WHERE builtin_code = 'link';
DELETE FROM sysinit_phrase WHERE source_code = 'page_link';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_link','cs','U','Vazby a závislosti aktiv (CRMM)','Správa uživatelských a zděděných vazeb M:N mezi aktivy, službami, aplikacemi, daty, hrozbami a opatřeními'),
('P','page_link','en','U','Asset Links & Dependencies (CRMM)','Management of user-defined and derived M:N links between assets, services, applications, data, threats, and controls');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('link','cs','crmm_analysis_folder','030','page_link','','U','<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z"/></svg>','Vazby a závislosti aktiv','Správa provozních, podpůrných a prostorových vazeb M:N mezi aktivy, službami, aplikacemi, daty a personálem','Správa provozních, podpůrných a prostorových vazeb M:N mezi aktivy, službami, aplikacemi, daty a personálem');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('link','en','Asset Links & Dependencies','Management of operational, support, and spatial M:N links between assets, services, applications, data, and personnel','Management of operational, support, and spatial M:N links between assets, services, applications, data, and personnel');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_link','badge_derived','cs','Zděděno','',''),
('page_link','btn_back_to_asset','cs','← Zpět na aktivum: {$asset}','Návrat na detail filtrovaného aktiva','btn-secondary'),
('page_link','btn_back_to_diagram','cs','← Zpět na schéma sítě: {$diagram}','Návrat na detail schématu heterogenní sítě','btn-secondary'),
('page_link','btn_new_link','cs','+ Nová vazba objektů','Založí novou vazbu mezi objekty',''),
('page_link','grp_link_endpoints','cs','Typ vazby, zdrojový a cílový objekt','',''),
('page_link','grp_weight_note','cs','Váha přenosu rizika, původ, poznámka a platnost','',''),
('page_link','header_edit_link','cs','Detail vazby mezi objekty','',''),
('page_link','header_new_link','cs','Nová vazba mezi objekty','',''),
('page_link','lbl_filter_link_def','cs','Typ vazby (link_def):','',''),
('page_link','lbl_show_removed','cs','Zobrazit i zrušené','',''),
('page_link','master_heading','cs','Seznam vazeb a závislostí','',''),
('page_link','msg_derived_link_readonly','cs','Tato vazba vznikla automatickým děděním po hierarchii, ze sloupce parent_uuid nebo projekcí ze schématu sítě (is_derived = 1). Zděděnou vazbu nelze ručně přepisovat; upravte ji na zdrojovém záznamu nebo diagramu.','',''),
('page_link','opt_all_link_defs','cs','--- Všechny typy vazeb ---','',''),
('page_link','opt_select_default','cs','--- Vyberte ---','',''),
('page_link','page_title','cs','Vazby a závislosti aktiv (CRMM)','',''),
('page_link','placeholder_search','cs','Hledat ve vazbách...','',''),
('page_link','th_from_object','cs','Zdroj (Odkud)','',''),
('page_link','th_link_def','cs','Typ vazby','',''),
('page_link','th_to_object','cs','Cíl (Kam)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_link','badge_derived','en','Derived',''),
('page_link','btn_back_to_asset','en','← Back to Asset: {$asset}','Return to the filtered asset detail'),
('page_link','btn_back_to_diagram','en','← Back to Network Diagram: {$diagram}','Return to the network diagram detail'),
('page_link','btn_new_link','en','+ New Object Link','Create a new link between objects'),
('page_link','grp_link_endpoints','en','Link Type, Source & Target Object',''),
('page_link','grp_weight_note','en','Risk Transfer Weight, Origin, Note & Validity',''),
('page_link','header_edit_link','en','Object Link Detail',''),
('page_link','header_new_link','en','New Object Link',''),
('page_link','lbl_filter_link_def','en','Link Type (link_def):',''),
('page_link','lbl_show_removed','en','Show Removed',''),
('page_link','master_heading','en','Links & Dependencies List',''),
('page_link','msg_derived_link_readonly','en','This link was automatically generated by hierarchy inheritance, from the parent_uuid column, or by network diagram projection (is_derived = 1). Derived links are read-only; edit the source record or diagram instead.',''),
('page_link','opt_all_link_defs','en','--- All Link Types ---',''),
('page_link','opt_select_default','en','--- Select ---',''),
('page_link','page_title','en','Asset Links & Dependencies (CRMM)',''),
('page_link','placeholder_search','en','Search links...',''),
('page_link','th_from_object','en','Source (From)',''),
('page_link','th_link_def','en','Link Type',''),
('page_link','th_to_object','en','Target (To)','');
GO