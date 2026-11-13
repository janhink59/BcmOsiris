/* =============================================================================
 * Verze: 2026-11-13 16:30
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
('page_meta_column','grp_behavior','cs','Chování, překlad, historie a ochrana','',''),
('page_meta_column','grp_form_ui','cs','Formulářový prvek a zobrazení v seznamu','',''),
('page_meta_column','grp_identification','cs','Technická identifikace a dědičnost','',''),
('page_meta_column','grp_presentation','cs','Popisky, záhlaví a nápověda','',''),
('page_meta_column','grp_relations','cs','Vazby na číselníky a logické třídy','',''),
('page_meta_column','header_detail','cs','Sloupec metadat','',''),
('page_meta_column','lbl_select_class','cs','Zvolte logickou třídu (objekt):','',''),
('page_meta_column','page_title','cs','Sloupce metadat - BCM Osiris','',''),
('page_meta_column','page_title_class','cs','Sloupce: {$class}','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_meta_column','btn_back_to_class','en','← Back to Class: {$parent}','Return to the parent logical class detail'),
('page_meta_column','grp_behavior','en','Behavior, Translation, History & Protection',''),
('page_meta_column','grp_form_ui','en','Form Control & Master List Display',''),
('page_meta_column','grp_identification','en','Technical Identification & Inheritance',''),
('page_meta_column','grp_presentation','en','Labels, Headers & Help Text',''),
('page_meta_column','grp_relations','en','Codetable & Logical Class References',''),
('page_meta_column','header_detail','en','Metadata Column',''),
('page_meta_column','lbl_select_class','en','Select Logical Class (Object):',''),
('page_meta_column','page_title','en','Metadata Columns - BCM Osiris',''),
('page_meta_column','page_title_class','en','Columns: {$class}','');
GO