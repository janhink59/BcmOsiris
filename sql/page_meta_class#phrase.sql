/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_meta_class#phrase.sql
 * Účel:   Registrace stránky page_meta_class do sysinit_object, položky menu
 *         meta_class do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_meta_class';
DELETE FROM sysinit_menu WHERE builtin_code = 'meta_class';
DELETE FROM sysinit_phrase WHERE source_code = 'page_meta_class';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_meta_class','cs','U','Logické třídy (Objekty)','Správa logických entit, jejich vlastností a překladů'),
('P','page_meta_class','en','U','Logical Classes (Objects)','Management of logical entities, their properties, and translations');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('meta_class','cs','metadata_folder','010','page_meta_class','','U','<svg viewBox="0 0 24 24" fill="#4F46E5"><path d="M12 2l-5.5 9h11L12 2zm0 3.84L13.93 9h-3.87L12 5.84zM17.5 13c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zm0 7c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5zM3 21.5h8v-8H3v8zm2-6h4v4H5v-4z"/></svg>','Logické třídy (Objekty)','Správa logických entit, jejich vlastností a překladů','Správa logických entit, jejich vlastností a překladů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('meta_class','en','Logical Classes (Objects)','Management of logical entities, their properties, and translations','Management of logical entities, their properties, and translations');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_meta_class','btn_manage_columns','cs','Spravovat sloupce ({$count}) →','Přejde do správy sloupců vybrané logické třídy','btn-secondary'),
('page_meta_class','grp_identification','cs','Technická identifikace a úložiště','',''),
('page_meta_class','grp_presentation','cs','Prezentační texty a překlady','',''),
('page_meta_class','grp_settings','cs','Nastavení koše, oprávnění a ochrany','',''),
('page_meta_class','header_detail','cs','Logická třída','',''),
('page_meta_class','page_title','cs','Logické třídy (Objekty) - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_meta_class','btn_manage_columns','en','Manage Columns ({$count}) →','Open column definitions for the selected logical class'),
('page_meta_class','grp_identification','en','Technical Identification & Storage',''),
('page_meta_class','grp_presentation','en','Presentation Texts & Translations',''),
('page_meta_class','grp_settings','en','Trash Retention, Permissions & Protection',''),
('page_meta_class','header_detail','en','Logical Class',''),
('page_meta_class','page_title','en','Logical Classes (Objects) - BCM Osiris','');
GO