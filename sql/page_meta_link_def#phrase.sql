/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_meta_link_def#phrase.sql
 * Účel:   Registrace stránky page_meta_link_def do sysinit_object, položky menu
 *         meta_link_def do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_meta_link_def';
DELETE FROM sysinit_menu WHERE builtin_code = 'meta_link_def';
DELETE FROM sysinit_phrase WHERE source_code = 'page_meta_link_def';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_meta_link_def','cs','U','Definice typů vazeb (CRMM)','Správa povolených typů relací a vazeb mezi třídami objektů v tabulce meta_link_def'),
('P','page_meta_link_def','en','U','Link Type Definitions (CRMM)','Management of allowed relationship and link types between object classes in meta_link_def');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('meta_link_def','cs','crmm_folder','110','page_meta_link_def','','U','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M17 7h-4v2h4c1.65 0 3 1.35 3 3s-1.35 3-3 3h-4v2h4c2.76 0 5-2.24 5-5s-2.24-5-5-5zm-6 8H7c-1.65 0-3-1.35-3-3s1.35-3 3-3h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-2zm-3-4h8v2H8z"/></svg>','Definice typů vazeb','Správa katalogu povolených typů relací a vazeb mezi logickými třídami v tabulce meta_link_def','Správa katalogu povolených typů relací a vazeb mezi logickými třídami v tabulce meta_link_def');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('meta_link_def','en','Link Type Definitions','Management of the catalog of allowed relationship and link types between logical classes in meta_link_def','Management of the catalog of allowed relationship and link types between logical classes in meta_link_def');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_meta_link_def','btn_new_link_def','cs','+ Nový typ vazby','Založí novou definici typu vztahu v meta_link_def',''),
('page_meta_link_def','grp_identification','cs','Kód vazby, směr a propojované logické třídy','',''),
('page_meta_link_def','grp_presentation','cs','Prezentační názvy vazby (tam / zpět) a nápověda','',''),
('page_meta_link_def','grp_rules_protection','cs','Pravidla navazování, váha, původ a ochrana','',''),
('page_meta_link_def','header_edit_link_def','cs','Typ vazby','',''),
('page_meta_link_def','header_new_link_def','cs','Nová definice typu vazby','',''),
('page_meta_link_def','msg_derived_link_def_readonly','cs','Tento nepřímý vztah byl automaticky vygenerován ze schématu heterogenní sítě (is_derived = 1). Upravuje se přepočtem příslušného diagramu sítě.','',''),
('page_meta_link_def','page_title','cs','Definice typů vazeb (CRMM)','',''),
('page_meta_link_def','th_caption_forward','cs','Název vazby (tam)','',''),
('page_meta_link_def','th_direction_type','cs','Směr','',''),
('page_meta_link_def','th_link_code','cs','Kód vazby','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_meta_link_def','btn_new_link_def','en','+ New Link Type','Create a new relationship type definition in meta_link_def'),
('page_meta_link_def','grp_identification','en','Link Code, Direction & Connected Logical Classes',''),
('page_meta_link_def','grp_presentation','en','Presentation Link Captions (Forward / Backward) & Help',''),
('page_meta_link_def','grp_rules_protection','en','Linking Rules, Weight, Origin & Protection',''),
('page_meta_link_def','header_edit_link_def','en','Link Type',''),
('page_meta_link_def','header_new_link_def','en','New Link Type Definition',''),
('page_meta_link_def','msg_derived_link_def_readonly','en','This indirect relationship was automatically generated from a heterogeneous network schema (is_derived = 1). It is updated by recalculating the corresponding network diagram.',''),
('page_meta_link_def','page_title','en','Link Type Definitions (CRMM)',''),
('page_meta_link_def','th_caption_forward','en','Forward Caption',''),
('page_meta_link_def','th_direction_type','en','Dir.',''),
('page_meta_link_def','th_link_code','en','Link Code','');
GO