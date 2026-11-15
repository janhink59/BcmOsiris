/* =============================================================================
 * Verze: 2026-11-15 19:15
 * Soubor: page_csv_package#phrase.sql
 * Účel:   Registrace stránky page_csv_package do sysinit_object, položky menu
 *         csv_package do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_csv_package';
DELETE FROM sysinit_menu WHERE builtin_code = 'csv_package';
DELETE FROM sysinit_phrase WHERE source_code = 'page_csv_package';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_csv_package','cs','U','Přenos balíčků (CSV/TSV)','Nástroj pro export a dvoufázový import datových balíčků ve formátu TSV/CSV'),
('P','page_csv_package','en','U','Package Transfer (CSV/TSV)','Tool for exporting and two-phase importing of data packages in TSV/CSV format');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('csv_package','cs','admin_folder','050','page_csv_package','','U','<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>','Přenos balíčků (CSV/TSV)','Export a dvoufázový import datových balíčků mezi instancemi','Export a dvoufázový import datových balíčků mezi instancemi');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('csv_package','en','Package Transfer (CSV/TSV)','Export and two-phase import of data packages between instances','Export and two-phase import of data packages between instances');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_csv_package','btn_back_after_import','cs','← Zpět na přenos balíčků','Návrat na výchozí obrazovku exportu a importu CSV balíčků','btn-secondary'),
('page_csv_package','btn_back_to_form','cs','← Zpět na výběr souboru','Návrat na výběr souboru bez spuštění 2. fáze importu','btn-secondary'),
('page_csv_package','btn_upload_phase1','cs','Načíst a zkontrolovat soubor (Fáze 1)','Nahraje CSV soubor do staging tabulek a ověří jeho strukturu a podpis',''),
('page_csv_package','desc_import_section','cs','Nahrajte soubor balíčku (.csv). V 1. fázi systém ověří elektronický podpis, zkontroluje oprávnění organizace i strukturu a zobrazí přehled dat před samotným zápisem do databáze.','',''),
('page_csv_package','err_package_not_found','cs','Požadovaná třída balíčku nebyla nalezena.','',''),
('page_csv_package','hdr_import_section','cs','Dvoufázový import balíčku ze souboru CSV','',''),
('page_csv_package','hdr_phase2_result','cs','Výsledek importu balíčku do databáze (Fáze 2)','',''),
('page_csv_package','heading_csv_packages','cs','Přenos datových balíčků (CSV)','',''),
('page_csv_package','lbl_csv_file','cs','Soubor balíčku (CSV):','',''),
('page_csv_package','lbl_switch_package','cs','Typ přenosového balíčku:','',''),
('page_csv_package','msg_uploaded_file','cs','Nahrán vstupní soubor','',''),
('page_csv_package','opt_pkg_metadata','cs','Systémová metadata 0x00 (metadata)','',''),
('page_csv_package','opt_pkg_simple_class','cs','Data jedné třídy organizace (simple_class)','',''),
('page_csv_package','page_title','cs','Přenos datových balíčků (CSV) - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_csv_package','btn_back_after_import','en','← Back to Package Transfer','Return to the main CSV package export and import screen'),
('page_csv_package','btn_back_to_form','en','← Back to File Selection','Return to file selection without executing Phase 2 import'),
('page_csv_package','btn_upload_phase1','en','Upload & Verify File (Phase 1)','Upload the CSV file into staging tables and verify its structure and signature'),
('page_csv_package','desc_import_section','en','Upload a package file (.csv). In Phase 1, the system verifies the cryptographic signature, organization permissions, and structure, and displays a summary before writing to the database.',''),
('page_csv_package','err_package_not_found','en','Requested package class was not found.',''),
('page_csv_package','hdr_import_section','en','Two-Phase Package Import from CSV File',''),
('page_csv_package','hdr_phase2_result','en','Database Package Import Result (Phase 2)',''),
('page_csv_package','heading_csv_packages','en','Data Package Transfer (CSV)',''),
('page_csv_package','lbl_csv_file','en','Package File (CSV):',''),
('page_csv_package','lbl_switch_package','en','Transfer Package Type:',''),
('page_csv_package','msg_uploaded_file','en','Uploaded input file',''),
('page_csv_package','opt_pkg_metadata','en','System Metadata 0x00 (metadata)',''),
('page_csv_package','opt_pkg_simple_class','en','Single Organization Class Data (simple_class)',''),
('page_csv_package','page_title','en','Data Package Transfer (CSV) - BCM Osiris','');
GO