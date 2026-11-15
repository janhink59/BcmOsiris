/* =============================================================================
 * Verze: 2026-11-15 20:05
 * Soubor: page_meta_column#phrase.sql
 * Účel:   Registrace stránky page_meta_column do sysinit_object, položky menu
 *         meta_column do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_meta_column';
DELETE FROM sysinit_menu WHERE builtin_code = 'meta_column';
DELETE FROM sysinit_phrase WHERE source_code = 'page_meta_column';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_meta_column','cs','U','Sloupce metadat','Správa definic sloupců, formulářových prvků a překladů'),
('P','page_meta_column','en','U','Metadata Columns','Management of column definitions, form controls, and translations');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('meta_column','cs','metadata_folder','020','page_meta_column','','U','<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M14.67 5v14H9.33V5h5.34zm1 14H21V5h-5.33v14zm-7.34 0V5H3v14h5.33z"/></svg>','Sloupce metadat','Správa definic sloupců, formulářových prvků a překladů','Správa definic sloupců, formulářových prvků a překladů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('meta_column','en','Metadata Columns','Management of column definitions, form controls, and translations','Management of column definitions, form controls, and translations');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_meta_column','btn_back_to_class','cs','← Zpět na třídu: {$parent}','Návrat do detailu nadřízené logické třídy','btn-secondary'),
('page_meta_column','grp_behavior','cs','Behaviorální příznaky a ochrana','',''),
('page_meta_column','grp_presentation','cs','Základní prezentační údaje','',''),
('page_meta_column','grp_ui_props','cs','Formulářové vlastnosti a vazby (UI)','',''),
('page_meta_column','header_column','cs','Sloupec','',''),
('page_meta_column','lbl_select_class','cs','Logická třída (objekt):','',''),
('page_meta_column','msg_inherited_column','cs','Poznámka: Tento sloupec dědí vlastnosti od svého předka. Můžete zde upravit jeho překlady (nebo v roli Developer přepsat jeho vlastnosti).','',''),
('page_meta_column','page_title','cs','Správa metadat sloupce','',''),
('page_meta_column','page_title_class','cs','Sloupce: {$class}','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_meta_column','btn_back_to_class','en','← Back to Class: {$parent}','Return to the parent logical class detail'),
('page_meta_column','grp_behavior','en','Behavioral Flags & Protection',''),
('page_meta_column','grp_presentation','en','Basic Presentation Details',''),
('page_meta_column','grp_ui_props','en','Form Properties & References (UI)',''),
('page_meta_column','header_column','en','Column',''),
('page_meta_column','lbl_select_class','en','Logical Class (Object):',''),
('page_meta_column','msg_inherited_column','en','Note: This column inherits properties from its ancestor. You can customize its translations here (or override its properties in the Developer role).',''),
('page_meta_column','page_title','en','Column Metadata Management',''),
('page_meta_column','page_title_class','en','Columns: {$class}','');
GO