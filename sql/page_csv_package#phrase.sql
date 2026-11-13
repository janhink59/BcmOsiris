/* =============================================================================
 * Verze: 2026-11-13 16:15
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
('page_csv_package','btn_clear_staging','cs','Vyčistit načtený soubor (Staging)','Odstraní dočasně načtená data 1. fáze z databáze','btn-danger'),
('page_csv_package','btn_upload_phase1','cs','Načíst a zkontrolovat soubor (Fáze 1)','Nahraje CSV soubor do staging tabulek a ověří jeho strukturu a podpis',''),
('page_csv_package','err_no_file_uploaded','cs','Nebyl vybrán žádný soubor k nahrání.','',''),
('page_csv_package','hdr_export_section','cs','Export datového balíčku do souboru CSV','',''),
('page_csv_package','hdr_import_section','cs','Import datového balíčku ze souboru CSV (Dvoufázový)','',''),
('page_csv_package','lbl_select_csv_file','cs','Vyberte CSV soubor balíčku:','',''),
('page_csv_package','lbl_select_package_type','cs','Typ datového balíčku:','',''),
('page_csv_package','master_heading','cs','Typy CSV balíčků','',''),
('page_csv_package','msg_staging_cleared','cs','Dočasná staging data importu byla vyčištěna.','',''),
('page_csv_package','page_title','cs','Přenos datových balíčků (CSV) - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_csv_package','btn_clear_staging','en','Clear Loaded File (Staging)','Remove temporary Phase 1 staging data from the database'),
('page_csv_package','btn_upload_phase1','en','Upload & Verify File (Phase 1)','Upload the CSV file into staging tables and verify its structure and signature'),
('page_csv_package','err_no_file_uploaded','en','No file was selected for upload.',''),
('page_csv_package','hdr_export_section','en','Export Data Package to CSV File',''),
('page_csv_package','hdr_import_section','en','Import Data Package from CSV File (Two-Phase)',''),
('page_csv_package','lbl_select_csv_file','en','Select package CSV file:',''),
('page_csv_package','lbl_select_package_type','en','Data Package Type:',''),
('page_csv_package','master_heading','en','CSV Package Types',''),
('page_csv_package','msg_staging_cleared','en','Temporary import staging data has been cleared.',''),
('page_csv_package','page_title','en','Data Package Transfer (CSV) - BCM Osiris','');
GO