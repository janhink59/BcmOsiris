/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_meta_menu#phrase.sql
 * Účel:   Registrace stránky page_meta_menu do sysinit_object, položky menu
 *         meta_menu do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_meta_menu';
DELETE FROM sysinit_menu WHERE builtin_code = 'meta_menu';
DELETE FROM sysinit_phrase WHERE source_code = 'page_meta_menu';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_meta_menu','cs','U','Položky menu (Navigace)','Správa hierarchie, pořadí, cílových stránek a překladů položek menu'),
('P','page_meta_menu','en','U','Menu Items (Navigation)','Management of hierarchy, sort order, target pages, and translations of menu items');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('meta_menu','cs','metadata_folder','040','page_meta_menu','','U','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M3 18h13v-2H3v2zm0-5h10v-2H3v2zm0-7v2h13V6H3zm18 9.59L17.42 12 21 8.41 19.59 7l-5 5 5 5L21 15.59z"/></svg>','Položky menu (Navigace)','Úprava hierarchie, pořadí, cílových stránek a překladů položek menu','Úprava hierarchie, pořadí, cílových stránek a překladů položek menu');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('meta_menu','en','Menu Items (Navigation)','Management of hierarchy, sort order, target pages, and translations of menu items','Management of hierarchy, sort order, target pages, and translations of menu items');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_meta_menu','btn_new_menu_item','cs','+ Nová položka menu','Založí novou složku nebo odkaz v navigačním menu',''),
('page_meta_menu','grp_identification','cs','Kód, nadřízená složka a pořadí ve stromu','',''),
('page_meta_menu','grp_navigation','cs','Cílová stránka, parametry URL a oprávnění','',''),
('page_meta_menu','grp_presentation','cs','Název, nápověda a vektorová ikona','',''),
('page_meta_menu','grp_protection','cs','Platnost a ochrana záznamu','',''),
('page_meta_menu','header_edit_menu','cs','Položka menu','',''),
('page_meta_menu','header_new_menu','cs','Nová položka menu','',''),
('page_meta_menu','master_heading','cs','Strom navigačního menu','',''),
('page_meta_menu','page_title','cs','Položky menu (Navigace) - BCM Osiris','',''),
('page_meta_menu','th_menu_caption','cs','Položka menu','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_meta_menu','btn_new_menu_item','en','+ New Menu Item','Create a new folder or link in the navigation menu'),
('page_meta_menu','grp_identification','en','Code, Parent Folder & Tree Order',''),
('page_meta_menu','grp_navigation','en','Target Page, URL Parameters & Permissions',''),
('page_meta_menu','grp_presentation','en','Caption, Help Text & Vector Icon',''),
('page_meta_menu','grp_protection','en','Validity & Record Protection',''),
('page_meta_menu','header_edit_menu','en','Menu Item',''),
('page_meta_menu','header_new_menu','en','New Menu Item',''),
('page_meta_menu','master_heading','en','Navigation Menu Tree',''),
('page_meta_menu','page_title','en','Menu Items (Navigation) - BCM Osiris',''),
('page_meta_menu','th_menu_caption','en','Menu Item','');
GO