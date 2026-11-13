/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: csv_package_metadata#phrase.sql
 * Účel:   Registrace třídy csv_package_metadata do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'csv_package_metadata';
DELETE FROM sysinit_phrase WHERE source_code = 'csv_package_metadata';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','csv_package_metadata','cs','U','CSV/TSV balíček systémových metadat','Definice a filtry pro přenos systémových metadat mezi instancemi'),
('P','csv_package_metadata','en','U','System Metadata CSV/TSV Package','Definition and filters for transferring system metadata between instances');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('csv_package_metadata','err_import_dev_only','cs','Import systémových metadat je povolen pouze vývojářům v systémové organizaci (0x00).','',''),
('csv_package_metadata','lbl_filter_class_name','cs','Filtrovat na logickou třídu (class_name)','',''),
('csv_package_metadata','lbl_filter_date_from','cs','Pouze změněné od data (date_modified >=)','',''),
('csv_package_metadata','lbl_filter_language','cs','Jazyk překladů (language)','',''),
('csv_package_metadata','lbl_filter_only_custom','cs','Pouze klientské úpravy (who_modified <> 0x00)','',''),
('csv_package_metadata','lbl_filter_source_code','cs','Filtrovat fráze podle zdroje (source_code)','',''),
('csv_package_metadata','opt_all_classes','cs','--- Všechny třídy ---','',''),
('csv_package_metadata','opt_all_languages','cs','--- Všechny jazyky ---','',''),
('csv_package_metadata','opt_all_sources','cs','--- Všechny zdroje (stránky a třídy) ---','',''),
('csv_package_metadata','pkg_caption','cs','Systémová metadata a překlady (meta_*)','',''),
('csv_package_metadata','pkg_description','cs','Přenos systémových metadat (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def) mezi vývojovými a produkčními instancemi.','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('csv_package_metadata','err_import_dev_only','en','Importing system metadata is permitted only for developers in the system organization (0x00).',''),
('csv_package_metadata','lbl_filter_class_name','en','Filter by Logical Class (class_name)',''),
('csv_package_metadata','lbl_filter_date_from','en','Modified Since Date (date_modified >=)',''),
('csv_package_metadata','lbl_filter_language','en','Translation Language (language)',''),
('csv_package_metadata','lbl_filter_only_custom','en','Client Customizations Only (who_modified <> 0x00)',''),
('csv_package_metadata','lbl_filter_source_code','en','Filter Phrases by Source (source_code)',''),
('csv_package_metadata','opt_all_classes','en','--- All Classes ---',''),
('csv_package_metadata','opt_all_languages','en','--- All Languages ---',''),
('csv_package_metadata','opt_all_sources','en','--- All Sources (Pages & Classes) ---',''),
('csv_package_metadata','pkg_caption','en','System Metadata & Translations (meta_*)',''),
('csv_package_metadata','pkg_description','en','Transfer of system metadata (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def) between development and production instances.','');
GO