/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_xlsx_export_meta#phrase.sql
 * Účel:   Registrace stránky page_xlsx_export_meta do sysinit_object, položky
 *         menu xlsx_export_meta do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_xlsx_export_meta';
DELETE FROM sysinit_menu WHERE builtin_code = 'xlsx_export_meta';
DELETE FROM sysinit_phrase WHERE source_code = 'page_xlsx_export_meta';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_xlsx_export_meta','cs','S','Export metadat do Excelu','Nástroj pro zpětný export systémových metadat do souboru XLSX'),
('P','page_xlsx_export_meta','en','S','Export Metadata to Excel','Tool for reverse export of system metadata into an XLSX file');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('xlsx_export_meta','cs','metadata_folder','060','page_xlsx_export_meta','','S','<svg viewBox="0 0 24 24" fill="#0D9488"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm4 18H6V4h7v5h5v11zm-2-6.99l-1.41-1.41L13 15.16V11h-2v4.16l-1.59-1.59L8 13.01 12.01 17 16 13.01z"/></svg>','Export metadat do Excelu','Zpětný export systémových metadat do souboru XLSX','Zpětný export systémových metadat do souboru XLSX');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('xlsx_export_meta','en','Export Metadata to Excel','Reverse export of system metadata into an XLSX file','Reverse export of system metadata into an XLSX file');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_xlsx_export_meta','btn_download_xlsx','cs','Vygenerovat a stáhnout XLSX','Sestaví sešit Excel se systémovými metadaty a odešle jej ke stažení','btn-success'),
('page_xlsx_export_meta','heading_export','cs','Export systémových metadat do Excelu (XLSX)','',''),
('page_xlsx_export_meta','intro_export','cs','Tento nástroj vygeneruje vícezáložkový sešit XLSX obsahující aktuální stav systémových metadat (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def).','',''),
('page_xlsx_export_meta','lbl_filter_only_custom','cs','Exportovat pouze záznamy upravené v rozhraní (who_modified <> 0x00)','',''),
('page_xlsx_export_meta','page_title','cs','Export metadat do Excelu - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_xlsx_export_meta','btn_download_xlsx','en','Generate & Download XLSX','Build the Excel workbook with system metadata and download it'),
('page_xlsx_export_meta','heading_export','en','Export System Metadata to Excel (XLSX)',''),
('page_xlsx_export_meta','intro_export','en','This tool generates a multi-sheet XLSX workbook containing the current state of system metadata (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def).',''),
('page_xlsx_export_meta','lbl_filter_only_custom','en','Export only records customized in the UI (who_modified <> 0x00)',''),
('page_xlsx_export_meta','page_title','en','Export Metadata to Excel - BCM Osiris','');
GO