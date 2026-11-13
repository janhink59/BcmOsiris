/* =============================================================================
 * Verze: 2026-11-13 16:15
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
('csv_package_simple_class','err_class_not_found','cs','Zvolená logická třída nebyla v metadatech nalezena.','',''),
('csv_package_simple_class','info_all_langs_exported','cs','Exportovány všechny dostupné jazykové verze','',''),
('csv_package_simple_class','info_single_lang_exported','cs','Exportována pouze jedna jazyková verze: {$caption} ({$code})','',''),
('csv_package_simple_class','lbl_active_filter_info','cs','Aktivní filtr ze stránky','',''),
('csv_package_simple_class','lbl_Export_language','cs','Jazykové verze pro export','',''),
('csv_package_simple_class','lbl_select_class','cs','Logická třída (tabulka)','',''),
('csv_package_simple_class','opt_lang_all','cs','Všechny dostupné jazykové verze (A + všechna L)','',''),
('csv_package_simple_class','opt_lang_single','cs','Pouze jedna jazyková verze: {$caption} ({$code})','',''),
('csv_package_simple_class','pkg_caption','cs','Data jedné třídy organizace (Simple Class CSV)','',''),
('csv_package_simple_class','pkg_description','cs','Export a dvoufázový import záznamů jedné vybrané logické třídy aktuální organizace (včetně stromových struktur a jazykových verzí).','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('csv_package_simple_class','err_class_not_found','en','Selected logical class was not found in metadata.',''),
('csv_package_simple_class','info_all_langs_exported','en','All available language versions exported',''),
('csv_package_simple_class','info_single_lang_exported','en','Exported single language version only: {$caption} ({$code})',''),
('csv_package_simple_class','lbl_active_filter_info','en','Active Page Filter',''),
('csv_package_simple_class','lbl_Export_language','en','Language Versions to Export',''),
('csv_package_simple_class','lbl_select_class','en','Logical Class (Table)',''),
('csv_package_simple_class','opt_lang_all','en','All available language versions (A + all L)',''),
('csv_package_simple_class','opt_lang_single','en','Single language version only: {$caption} ({$code})',''),
('csv_package_simple_class','pkg_caption','en','Single Organization Class Data (Simple Class CSV)',''),
('csv_package_simple_class','pkg_description','en','Export and two-phase import of records for a single selected logical class of the current organization (including tree structures and language mutations).','');
GO