/* =============================================================================
 * Verze: 2026-11-15 19:15
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
('page_xlsx_export_meta','btn_export_excel','cs','Stáhnout meta_object.xlsx','Sestaví sešit Excel se systémovými metadaty a odešle jej ke stažení','btn-success'),
('page_xlsx_export_meta','btn_goto_import_excel','cs','← Přejít na import z Excelu','Přejde na stránku pro nahrání a import sešitu XLSX','btn-secondary'),
('page_xlsx_export_meta','export_heading','cs','Export systémových metadat do Excelu (meta_object.xlsx)','',''),
('page_xlsx_export_meta','export_intro','cs','Vygeneruje aktuální soubor meta_object.xlsx přímo z databáze (záložky page, menu, phrase, class, column; zděděné hodnoty jsou uzavřeny <do stříšek>).','',''),
('page_xlsx_export_meta','lbl_import_origin','cs','Označení původu (import_origin):','',''),
('page_xlsx_export_meta','lbl_primary_language','cs','Základní jazyk (language):','',''),
('page_xlsx_export_meta','lbl_second_language','cs','Druhý jazyk (*_l):','',''),
('page_xlsx_export_meta','opt_no_second_lang','cs','--- Bez druhého jazyka (režim jádra) ---','',''),
('page_xlsx_export_meta','page_title','cs','Export systémových metadat do Excelu - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_xlsx_export_meta','btn_export_excel','en','Download meta_object.xlsx','Build the Excel workbook with system metadata and download it'),
('page_xlsx_export_meta','btn_goto_import_excel','en','← Go to Excel Import','Open the page for uploading and importing an XLSX workbook'),
('page_xlsx_export_meta','export_heading','en','Export System Metadata to Excel (meta_object.xlsx)',''),
('page_xlsx_export_meta','export_intro','en','Generates the current meta_object.xlsx workbook directly from the database (sheets page, menu, phrase, class, column; inherited values are enclosed <in angle brackets>).',''),
('page_xlsx_export_meta','lbl_import_origin','en','Data Origin Label (import_origin):',''),
('page_xlsx_export_meta','lbl_primary_language','en','Primary Language (language):',''),
('page_xlsx_export_meta','lbl_second_language','en','Second Language (*_l):',''),
('page_xlsx_export_meta','opt_no_second_lang','en','--- No Second Language (Core Mode) ---',''),
('page_xlsx_export_meta','page_title','en','Export System Metadata to Excel - BCM Osiris','');
GO