/* =============================================================================
 * Verze: 2026-11-15 19:55
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
('page_hierarchy','btn_new_hierarchy','cs','+ Nová hierarchie / složka','Založí novou složku nebo definici sekundární hierarchie / sady štítků',''),
('page_hierarchy','grp_hierarchy_rules','cs','Zařazení ve stromu a pravidla navazování','',''),
('page_hierarchy','grp_presentation','cs','Prezentační texty a nápověda','',''),
('page_hierarchy','grp_validity_protection','cs','Platnost, vzhled a ochrana','',''),
('page_hierarchy','header_edit_hierarchy','cs','Hierarchie','',''),
('page_hierarchy','header_new_hierarchy','cs','Nová hierarchie / složka','',''),
('page_hierarchy','master_heading','cs','Registr hierarchií a tagů','',''),
('page_hierarchy','msg_hierarchy_is_folder_notice','cs','📁 Tato položka má nezaškrtnutý příznak „Samostatná hierarchie (is_leaf = 0)“, proto slouží pouze jako organizační složka tohoto registru a nenabízí se na stránce Položky sekundárních hierarchií. Pokud do ní chcete vkládat položky (uzly), zaškrtněte pole „Samostatná hierarchie (list)“ a uložte změny.','',''),
('page_hierarchy','msg_hierarchy_type_hint','cs','Tip: Záznamy s příznakem „Samostatná hierarchie (is_leaf = 1)“ představují koncové hierarchie nebo sady štítků (tagů), které se automaticky registrují do logických tříd (meta_class) a v nichž lze spravovat jednotlivé položky. Záznamy s is_leaf = 0 slouží jako organizační složky tohoto registru.','',''),
('page_hierarchy','page_title','cs','Sekundární hierarchie a štítky (Tagy)','',''),
('page_hierarchy','th_hierarchy_caption','cs','Hierarchie / Složka','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_hierarchy','btn_manage_hierarchy_items','en','Manage Items ({$count}) →','Open management of nodes and items of this secondary hierarchy'),
('page_hierarchy','btn_new_hierarchy','en','+ New Hierarchy / Folder','Create a new folder or secondary hierarchy / tag set definition'),
('page_hierarchy','grp_hierarchy_rules','en','Tree Placement & Linking Rules',''),
('page_hierarchy','grp_presentation','en','Presentation Texts & Help',''),
('page_hierarchy','grp_validity_protection','en','Validity, Appearance & Protection',''),
('page_hierarchy','header_edit_hierarchy','en','Hierarchy',''),
('page_hierarchy','header_new_hierarchy','en','New Hierarchy / Folder',''),
('page_hierarchy','master_heading','en','Hierarchies & Tags Registry',''),
('page_hierarchy','msg_hierarchy_is_folder_notice','en','📁 This item has the "Standalone Hierarchy (is_leaf = 0)" flag unchecked, so it serves only as an organizational folder in this registry and is not offered on the Secondary Hierarchy Items page. To insert nodes into it, check "Standalone Hierarchy (leaf)" and save changes.',''),
('page_hierarchy','msg_hierarchy_type_hint','en','Tip: Records with "Standalone Hierarchy (is_leaf = 1)" represent terminal hierarchies or tag sets that are automatically registered as logical classes (meta_class) and can hold items. Records with is_leaf = 0 act as organizational folders in this registry.',''),
('page_hierarchy','page_title','en','Secondary Hierarchies & Tags',''),
('page_hierarchy','th_hierarchy_caption','en','Hierarchy / Folder','');
GO