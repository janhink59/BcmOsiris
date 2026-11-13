/* =============================================================================
 * Verze: 2026-11-13 16:30
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
('page_excel_reader','btn_distribute','cs','Distribuovat do systémových metadat','Spustí uloženou proceduru pro rozpad importovaných listů do tabulek meta_*','btn-success'),
('page_excel_reader','btn_upload','cs','Nahrát a importovat do DB','Nahraje vybraný sešit XLSX a uloží jeho listy do databázových tabulek _excel_*',''),
('page_excel_reader','chk_drop_tables','cs','Smazat existující tabulky _excel_* před importem','',''),
('page_excel_reader','err_upload_failed','cs','Chyba při nahrávání souboru.','',''),
('page_excel_reader','heading_main','cs','Import a kontrola dat z Excelu (XLSX)','',''),
('page_excel_reader','lbl_select_file','cs','Vyberte soubor Excel (.xlsx):','',''),
('page_excel_reader','lbl_sheets_overview','cs','Přehled listů v databázi:','',''),
('page_excel_reader','msg_distribute_done','cs','Distribuce dat do systémových tabulek byla dokončena.','',''),
('page_excel_reader','msg_import_done','cs','Import sešitu do tabulek _excel_* byl úspěšně dokončen.','',''),
('page_excel_reader','msg_rows_truncated','cs','... Zobrazeno pouze prvních {$max} z celkových {$total} řádků ...','',''),
('page_excel_reader','page_title','cs','Import dat z Excelu - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_excel_reader','btn_distribute','en','Distribute into System Metadata','Run the stored procedure to distribute imported sheets into meta_* tables'),
('page_excel_reader','btn_upload','en','Upload & Import into DB','Upload the selected XLSX workbook and store its sheets into _excel_* tables'),
('page_excel_reader','chk_drop_tables','en','Drop existing _excel_* tables before import',''),
('page_excel_reader','err_upload_failed','en','File upload failed.',''),
('page_excel_reader','heading_main','en','Import & Verify Data from Excel (XLSX)',''),
('page_excel_reader','lbl_select_file','en','Select Excel file (.xlsx):',''),
('page_excel_reader','lbl_sheets_overview','en','Database Sheets Overview:',''),
('page_excel_reader','msg_distribute_done','en','Distribution of data into system metadata tables completed.',''),
('page_excel_reader','msg_import_done','en','Workbook import into _excel_* tables completed successfully.',''),
('page_excel_reader','msg_rows_truncated','en','... Displaying only the first {$max} of {$total} total rows ...',''),
('page_excel_reader','page_title','en','Import Data from Excel - BCM Osiris','');
GO