/* =============================================================================
 * Verze: 2026-11-15 19:15
 * Soubor: page_excel_reader#phrase.sql
 * Účel:   Registrace stránky page_excel_reader do sysinit_object, položky menu
 *         excel_reader do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_excel_reader';
DELETE FROM sysinit_menu WHERE builtin_code = 'excel_reader';
DELETE FROM sysinit_phrase WHERE source_code = 'page_excel_reader';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_excel_reader','cs','S','Import dat z Excelu','Nástroj pro hromadný import a distribuci datových struktur z Excelu'),
('P','page_excel_reader','en','S','Import Data from Excel','Tool for bulk import and distribution of data structures from Excel');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('excel_reader','cs','metadata_folder','050','page_excel_reader','','S','<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm4 18H6V4h7v5h5v11zM8 15.01l1.41 1.41L11 14.84V19h2v-4.16l1.59 1.59L16 15.01 12.01 11 8 15.01z"/></svg>','Import dat z Excelu','Hromadný import a kontrola metadat ze souboru XLSX','Hromadný import a kontrola metadat ze souboru XLSX');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('excel_reader','en','Import Data from Excel','Bulk import and verification of metadata from an XLSX file','Bulk import and verification of metadata from an XLSX file');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_excel_reader','btn_goto_export_meta','cs','Přejít na export metadat do Excelu →','Přejde na stránku pro vygenerování a stažení souboru meta_object.xlsx','btn-secondary'),
('page_excel_reader','btn_submit_excel','cs','Načíst a zpracovat','Nahraje vybraný soubor XLSX a provede zvolený režim zpracování','btn-success'),
('page_excel_reader','err_pkg_not_ready','cs','Balíček není připraven pro distribuci','',''),
('page_excel_reader','form_heading','cs','Načtení dat z excelu pro účely distribuce a importu','',''),
('page_excel_reader','form_intro','cs','Vyberte zdrojový soubor XLSX a zvolte požadovaný režim zpracování.','',''),
('page_excel_reader','lbl_import_mode','cs','Režim zpracování:','',''),
('page_excel_reader','lbl_input_file','cs','Vstupní soubor','',''),
('page_excel_reader','lbl_xlsx_file','cs','Soubor XLSX:','',''),
('page_excel_reader','msg_data_outside_table','cs','Data jsou i mimo tabulku','',''),
('page_excel_reader','msg_processing_data','cs','Zpracování dat','',''),
('page_excel_reader','msg_rows_truncated','cs','... Zobrazeno pouze prvních {$max} z celkových {$total} řádků ...','',''),
('page_excel_reader','opt_mode_commit','cs','Import se zápisem (Commit)','',''),
('page_excel_reader','opt_mode_dist','cs','Distribuce (SQL skript)','',''),
('page_excel_reader','opt_mode_preview','cs','Pouze zobrazit data','',''),
('page_excel_reader','opt_mode_rollback','cs','Kontrolní běh (Rollback)','',''),
('page_excel_reader','page_title','cs','Import dat z Excelu - BCM Osiris','',''),
('page_excel_reader','warn_mode_switched','cs','Režim byl automaticky přepnut na zobrazení dat','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_excel_reader','btn_goto_export_meta','en','Go to Export Metadata to Excel →','Open the page for generating and downloading meta_object.xlsx'),
('page_excel_reader','btn_submit_excel','en','Upload & Process','Upload the selected XLSX file and execute the chosen processing mode'),
('page_excel_reader','err_pkg_not_ready','en','Package is not ready for distribution',''),
('page_excel_reader','form_heading','en','Load Data from Excel for Distribution and Import',''),
('page_excel_reader','form_intro','en','Select a source XLSX workbook and choose the desired processing mode.',''),
('page_excel_reader','lbl_import_mode','en','Processing Mode:',''),
('page_excel_reader','lbl_input_file','en','Input File',''),
('page_excel_reader','lbl_xlsx_file','en','XLSX File:',''),
('page_excel_reader','msg_data_outside_table','en','Data detected outside the table boundary',''),
('page_excel_reader','msg_processing_data','en','Processing data',''),
('page_excel_reader','msg_rows_truncated','en','... Displaying only the first {$max} of {$total} total rows ...',''),
('page_excel_reader','opt_mode_commit','en','Import with Write (Commit)',''),
('page_excel_reader','opt_mode_dist','en','Distribution (SQL Script)',''),
('page_excel_reader','opt_mode_preview','en','Preview Data Only',''),
('page_excel_reader','opt_mode_rollback','en','Validation Run (Rollback)',''),
('page_excel_reader','page_title','en','Import Data from Excel - BCM Osiris',''),
('page_excel_reader','warn_mode_switched','en','Mode was automatically switched to data preview','');
GO