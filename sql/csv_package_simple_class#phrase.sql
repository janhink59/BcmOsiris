/* =============================================================================
 * Verze: 2026-11-15 19:15
 * Soubor: csv_package_simple_class#phrase.sql
 * Účel:   Registrace třídy csv_package_simple_class do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'csv_package_simple_class';
DELETE FROM sysinit_phrase WHERE source_code = 'csv_package_simple_class';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','csv_package_simple_class','cs','U','CSV balíček dat jedné třídy organizace','Export a dvoufázový import záznamů jedné logické třídy aktuálního tenanta'),
('P','csv_package_simple_class','en','U','Single Organization Class CSV Package','Export and two-phase import of records for a single logical class of the current tenant');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('csv_package_simple_class','info_all_langs_exported','cs','Exportovány všechny jazykové mutace tenanta (A + L1 + L2...)','',''),
('csv_package_simple_class','info_no_filter_applied','cs','Bez filtru (všechny záznamy třídy vlastněné organizací)','',''),
('csv_package_simple_class','info_single_lang_exported','cs','Exportována pouze jedna jazyková verze: {$caption} ({$code})','',''),
('csv_package_simple_class','lbl_param_class_name','cs','Logická třída (class_name / builtin_code)','',''),
('csv_package_simple_class','lbl_param_export_languages','cs','Jazykové mutace k exportu','',''),
('csv_package_simple_class','lbl_param_info','cs','Popis aplikovaného filtru (info – víceřádkový ve tvaru Label: výraz)','',''),
('csv_package_simple_class','opt_lang_all','cs','Všechny jazykové mutace tenanta (A + L1 + L2...)','',''),
('csv_package_simple_class','opt_lang_single','cs','Pouze jedna jazyková verze: {$caption} ({$code})','',''),
('csv_package_simple_class','pkg_desc','cs','Export a dvoufázový import záznamů jedné logické třídy vlastněných aktuální organizací (včetně všech nebo vybrané jazykové mutace a popisu filtru).','',''),
('csv_package_simple_class','pkg_title','cs','Export a import dat jedné třídy organizace (simple_class)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('csv_package_simple_class','info_all_langs_exported','en','Exported all tenant language mutations (A + L1 + L2...)',''),
('csv_package_simple_class','info_no_filter_applied','en','No filter applied (all class records owned by the organization)',''),
('csv_package_simple_class','info_single_lang_exported','en','Exported single language version only: {$caption} ({$code})',''),
('csv_package_simple_class','lbl_param_class_name','en','Logical Class (class_name / builtin_code)',''),
('csv_package_simple_class','lbl_param_export_languages','en','Language Mutations to Export',''),
('csv_package_simple_class','lbl_param_info','en','Applied Filter Description (info – multi-line in Label: expression format)',''),
('csv_package_simple_class','opt_lang_all','en','All tenant language mutations (A + L1 + L2...)',''),
('csv_package_simple_class','opt_lang_single','en','Single language version only: {$caption} ({$code})',''),
('csv_package_simple_class','pkg_desc','en','Export and two-phase import of records for a single logical class owned by the current organization (including all or selected language mutations and filter description).',''),
('csv_package_simple_class','pkg_title','en','Single Organization Class Data Export & Import (simple_class)','');
GO