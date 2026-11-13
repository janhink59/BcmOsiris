/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_hierarchy#phrase.sql
 * Účel:   Registrace stránky page_hierarchy do sysinit_object, položky menu
 *         hierarchy do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_hierarchy';
DELETE FROM sysinit_menu WHERE builtin_code = 'hierarchy';
DELETE FROM sysinit_phrase WHERE source_code = 'page_hierarchy';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_hierarchy','cs','U','Sekundární hierarchie a štítky (Tagy)','Správa registru sekundárních hierarchií, číselníků a stromů štítků (tagů)'),
('P','page_hierarchy','en','U','Secondary Hierarchies & Tags','Management of the registry of secondary hierarchies, codetables, and tag trees');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('hierarchy','cs','crmm_folder','090','page_hierarchy','','U','<svg viewBox="0 0 24 24" fill="#9333EA"><path d="M22 11V3h-7v3H9V3H2v8h7V8h2v10h4v3h7v-8h-7v3h-2V8h2v3z"/></svg>','Sekundární hierarchie a štítky','Správa registru sekundárních hierarchií, klasifikačních stromů, číselníků a štítků (tagů)','Správa registru sekundárních hierarchií, klasifikačních stromů, číselníků a štítků (tagů)');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('hierarchy','en','Secondary Hierarchies & Tags','Management of the registry of secondary hierarchies, classification trees, codetables, and tags','Management of the registry of secondary hierarchies, classification trees, codetables, and tags');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_hierarchy','btn_manage_hierarchy_items','cs','Spravovat položky ({$count}) →','Přejde do správy uzlů a položek této sekundární hierarchie','btn-secondary'),
('page_hierarchy','btn_new_hierarchy','cs','+ Nová sekundární hierarchie','Založí novou složku nebo definici sekundární hierarchie / sady štítků',''),
('page_hierarchy','grp_identification','cs','Kód, zařazení v registru a ikona','',''),
('page_hierarchy','grp_presentation','cs','Prezentační texty a popis hierarchie','',''),
('page_hierarchy','grp_rules_protection','cs','Pravidla přiřazování, oprávnění a ochrana','',''),
('page_hierarchy','header_edit_hierarchy','cs','Sekundární hierarchie','',''),
('page_hierarchy','header_new_hierarchy','cs','Nová sekundární hierarchie / sada štítků','',''),
('page_hierarchy','master_heading','cs','Registr sekundárních hierarchií a štítků','',''),
('page_hierarchy','msg_folder_no_items_notice','cs','Tento záznam je organizační složkou v registru hierarchií (is_leaf = 0). Položky hodnot se vkládají pouze do koncových hierarchií (zaškrtnutá volba Samostatná hierarchie).','',''),
('page_hierarchy','page_title','cs','Sekundární hierarchie a štítky (CRMM)','',''),
('page_hierarchy','th_hierarchy_caption','cs','Sekundární hierarchie / Sada štítků','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_hierarchy','btn_manage_hierarchy_items','en','Manage Items ({$count}) →','Open management of nodes and items of this secondary hierarchy'),
('page_hierarchy','btn_new_hierarchy','en','+ New Secondary Hierarchy','Create a new folder or secondary hierarchy / tag set definition'),
('page_hierarchy','grp_identification','en','Code, Registry Placement & Icon',''),
('page_hierarchy','grp_presentation','en','Presentation Texts & Hierarchy Description',''),
('page_hierarchy','grp_rules_protection','en','Assignment Rules, Permissions & Protection',''),
('page_hierarchy','header_edit_hierarchy','en','Secondary Hierarchy',''),
('page_hierarchy','header_new_hierarchy','en','New Secondary Hierarchy / Tag Set',''),
('page_hierarchy','master_heading','en','Secondary Hierarchies & Tag Sets Registry',''),
('page_hierarchy','msg_folder_no_items_notice','en','This record is an organizational folder in the hierarchy registry (is_leaf = 0). Value items can only be inserted into terminal hierarchies (where Standalone Hierarchy is checked).',''),
('page_hierarchy','page_title','en','Secondary Hierarchies & Tags (CRMM)',''),
('page_hierarchy','th_hierarchy_caption','en','Secondary Hierarchy / Tag Set','');
GO