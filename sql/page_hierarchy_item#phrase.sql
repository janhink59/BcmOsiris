/* =============================================================================
 * Verze: 2026-11-15 19:55
 * Soubor: page_hierarchy_item#phrase.sql
 * Účel:   Registrace stránky page_hierarchy_item do sysinit_object, položky
 *         menu hierarchy_item do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_hierarchy_item';
DELETE FROM sysinit_menu WHERE builtin_code = 'hierarchy_item';
DELETE FROM sysinit_phrase WHERE source_code = 'page_hierarchy_item';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_hierarchy_item','cs','U','Položky sekundárních hierarchií','Správa uzlů a položek jednotlivých sekundárních hierarchií, číselníků a štítků'),
('P','page_hierarchy_item','en','U','Secondary Hierarchy Items','Management of nodes and items of individual secondary hierarchies, codetables, and tags');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('hierarchy_item','cs','crmm_folder','100','page_hierarchy_item','','U','<svg viewBox="0 0 24 24" fill="#DB2777"><path d="M17.63 5.84C17.27 5.33 16.67 5 16 5L5 5.01C3.9 5.01 3 5.9 3 7v10c0 1.1.9 1.99 2 1.99L16 19c.67 0 1.27-.33 1.63-.84L22 12l-4.37-6.16z"/></svg>','Položky sekundárních hierarchií','Správa uzlů a koncových položek jednotlivých sekundárních hierarchií, číselníků a štítků','Správa uzlů a koncových položek jednotlivých sekundárních hierarchií, číselníků a štítků');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('hierarchy_item','en','Secondary Hierarchy Items','Management of nodes and leaf items of individual secondary hierarchies, codetables, and tags','Management of nodes and leaf items of individual secondary hierarchies, codetables, and tags');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_hierarchy_item','btn_back_to_hierarchy','cs','← Zpět na hierarchii: {$parent}','Návrat do registru sekundárních hierarchií','btn-secondary'),
('page_hierarchy_item','btn_new_hierarchy_item','cs','+ Nová položka hierarchie','Založí nový uzel nebo koncovou položku ve vybrané hierarchii',''),
('page_hierarchy_item','grp_presentation','cs','Prezentační texty a nápověda','',''),
('page_hierarchy_item','grp_tree_placement','cs','Zařazení v hierarchii a stromová struktura','',''),
('page_hierarchy_item','grp_visual_validity','cs','Vizuální atributy a platnost','',''),
('page_hierarchy_item','header_edit_item','cs','Položka hierarchie','',''),
('page_hierarchy_item','header_new_item','cs','Nová položka hierarchie','',''),
('page_hierarchy_item','lbl_select_hierarchy','cs','Zvolená hierarchie / sada štítků:','',''),
('page_hierarchy_item','master_heading','cs','Strom položek hierarchie','',''),
('page_hierarchy_item','opt_no_hierarchy_defined','cs','--- Nejprve založte koncovou hierarchii v registru ---','',''),
('page_hierarchy_item','page_title','cs','Položky sekundární hierarchie','',''),
('page_hierarchy_item','page_title_with_hier','cs','Položky hierarchie: {$hierarchy}','',''),
('page_hierarchy_item','th_is_default','cs','Výchozí','',''),
('page_hierarchy_item','th_item_caption','cs','Uzel hierarchie (Strom)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_hierarchy_item','btn_back_to_hierarchy','en','← Back to Hierarchy: {$parent}','Return to the secondary hierarchies registry'),
('page_hierarchy_item','btn_new_hierarchy_item','en','+ New Hierarchy Item','Create a new node or terminal item in the selected hierarchy'),
('page_hierarchy_item','grp_presentation','en','Presentation Texts & Help',''),
('page_hierarchy_item','grp_tree_placement','en','Hierarchy Assignment & Tree Structure',''),
('page_hierarchy_item','grp_visual_validity','en','Visual Attributes & Validity',''),
('page_hierarchy_item','header_edit_item','en','Hierarchy Item',''),
('page_hierarchy_item','header_new_item','en','New Hierarchy Item',''),
('page_hierarchy_item','lbl_select_hierarchy','en','Selected Hierarchy / Tag Set:',''),
('page_hierarchy_item','master_heading','en','Hierarchy Items Tree',''),
('page_hierarchy_item','opt_no_hierarchy_defined','en','--- Create a terminal hierarchy in the registry first ---',''),
('page_hierarchy_item','page_title','en','Secondary Hierarchy Items',''),
('page_hierarchy_item','page_title_with_hier','en','Hierarchy Items: {$hierarchy}',''),
('page_hierarchy_item','th_is_default','en','Default',''),
('page_hierarchy_item','th_item_caption','en','Hierarchy Node (Tree)','');
GO