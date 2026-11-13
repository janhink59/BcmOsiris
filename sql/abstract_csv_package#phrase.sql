/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: abstract_csv_package#phrase.sql
 * Účel:   Registrace třídy abstract_csv_package do sysinit_object a naplnění
 *         jejích výchozích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'abstract_csv_package';
DELETE FROM sysinit_phrase WHERE source_code = 'abstract_csv_package';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','abstract_csv_package','cs','U','Abstraktní CSV/TSV balíček','Základní třída pro export a dvoufázový import víceblokových CSV/TSV balíčků'),
('P','abstract_csv_package','en','U','Abstract CSV/TSV Package','Base class for exporting and two-phase importing of multi-block CSV/TSV packages');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('abstract_csv_package','btn_export_csv','cs','Exportovat balíček (CSV)','Vygeneruje a stáhne podepsaný víceblokový CSV soubor balíčku','btn-success'),
('abstract_csv_package','btn_run_phase2','cs','Spustit import do databáze (Fáze 2)','Spustí uloženou proceduru pro zápis zkontrolovaných dat do databáze','btn-success'),
('abstract_csv_package','err_empty_mandatory_cells','cs','Sloupec obsahuje prázdné hodnoty v povinném poli.','',''),
('abstract_csv_package','err_file_not_readable','cs','Vstupní soubor nelze přečíst.','',''),
('abstract_csv_package','err_file_open_failed','cs','Nepodařilo se otevřít vstupní soubor.','',''),
('abstract_csv_package','err_import_rolled_back','cs','Import balíčku byl stornován kvůli chybám (Rollback).','',''),
('abstract_csv_package','err_invalid_signature','cs','Neplatný bezpečnostní podpis souboru (soubor byl neautorizovaně změněn nebo poškozen).','',''),
('abstract_csv_package','err_missing_mandatory_col','cs','V tabulce chybí povinný sloupec.','',''),
('abstract_csv_package','err_missing_mandatory_param','cs','Chybí povinný parametr balíčku.','',''),
('abstract_csv_package','err_missing_mandatory_table','cs','V souboru chybí povinná tabulka.','',''),
('abstract_csv_package','err_proc_not_found','cs','Uložená procedura pro zpracování balíčku nebyla v databázi nalezena.','',''),
('abstract_csv_package','err_same_org_only_blocked','cs','Import není umožněn: Balíček má nastaveno omezení importu pouze do stejné organizace, která data exportovala (same_org_only = 1).','',''),
('abstract_csv_package','err_wrong_package_code','cs','Kód balíčku v souboru neodpovídá zvolenému typu importu.','',''),
('abstract_csv_package','hdr_phase1_summary','cs','Kontrola načteného balíčku (Fáze 1)','',''),
('abstract_csv_package','lbl_param_import_origin','cs','Označení původu dat (import_origin)','',''),
('abstract_csv_package','lbl_param_same_org_only','cs','Povolit import pouze do stejné organizace, která data exportovala','',''),
('abstract_csv_package','lbl_param_target_status','cs','Režim zápisu při importu','',''),
('abstract_csv_package','lbl_param_verify_data','cs','Vyžadovat nezměnitelnost dat (podpis celého souboru)','',''),
('abstract_csv_package','msg_import_committed','cs','Import balíčku byl úspěšně dokončen a uložen (Commit).','',''),
('abstract_csv_package','msg_same_org_only_verified','cs','Kontrola organizace (same_org_only = 1) proběhla úspěšně – import probíhá do stejné organizace.','',''),
('abstract_csv_package','msg_signature_verified','cs','Bezpečnostní podpis souboru je platný (integrita ověřena).','',''),
('abstract_csv_package','opt_status_active','cs','Zapsat přímo jako platné schválené záznamy (A)','',''),
('abstract_csv_package','opt_status_draft','cs','Uložit jako rozpracované koncepty (D)','',''),
('abstract_csv_package','opt_status_forward','cs','Předat schvalovateli ke schválení (F)','',''),
('abstract_csv_package','th_col_list','cs','Načtené sloupce','',''),
('abstract_csv_package','th_param_code','cs','Parametr','',''),
('abstract_csv_package','th_param_val','cs','Hodnota v souboru','',''),
('abstract_csv_package','th_row_count','cs','Počet řádků','',''),
('abstract_csv_package','th_table_name','cs','Tabulka v balíčku','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('abstract_csv_package','btn_export_csv','en','Export Package (CSV)','Generate and download the multi-block CSV package'),
('abstract_csv_package','btn_run_phase2','en','Run Database Import (Phase 2)','Execute the database import of the verified staging data'),
('abstract_csv_package','err_empty_mandatory_cells','en','Column contains empty values in a mandatory field.',''),
('abstract_csv_package','err_file_not_readable','en','Input file is not readable.',''),
('abstract_csv_package','err_file_open_failed','en','Failed to open input file.',''),
('abstract_csv_package','err_import_rolled_back','en','Package import was rolled back due to errors (Rollback).',''),
('abstract_csv_package','err_invalid_signature','en','Invalid file security signature (the file was modified without authorization or corrupted).',''),
('abstract_csv_package','err_missing_mandatory_col','en','Mandatory column is missing in the table.',''),
('abstract_csv_package','err_missing_mandatory_param','en','Mandatory package parameter is missing.',''),
('abstract_csv_package','err_missing_mandatory_table','en','Mandatory table is missing in the file.',''),
('abstract_csv_package','err_proc_not_found','en','Stored procedure for processing the package was not found in the database.',''),
('abstract_csv_package','err_same_org_only_blocked','en','Import blocked: This package is restricted to import only into the same organization that exported the data (same_org_only = 1).',''),
('abstract_csv_package','err_wrong_package_code','en','Package code in the file does not match the selected import type.',''),
('abstract_csv_package','hdr_phase1_summary','en','Loaded Package Verification (Phase 1)',''),
('abstract_csv_package','lbl_param_import_origin','en','Data Origin Label (import_origin)',''),
('abstract_csv_package','lbl_param_same_org_only','en','Allow import only into the same organization that exported the data',''),
('abstract_csv_package','lbl_param_target_status','en','Import Write Mode',''),
('abstract_csv_package','lbl_param_verify_data','en','Enforce data immutability (full file cryptographic signature)',''),
('abstract_csv_package','msg_import_committed','en','Package import was completed and committed successfully.',''),
('abstract_csv_package','msg_same_org_only_verified','en','Organization check (same_org_only = 1) passed – importing into the same organization.',''),
('abstract_csv_package','msg_signature_verified','en','File security signature is valid (integrity verified).',''),
('abstract_csv_package','opt_status_active','en','Write directly as approved active records (A)',''),
('abstract_csv_package','opt_status_draft','en','Save as work-in-progress drafts (D)',''),
('abstract_csv_package','opt_status_forward','en','Submit to approver for review (F)',''),
('abstract_csv_package','th_col_list','en','Loaded Columns',''),
('abstract_csv_package','th_param_code','en','Parameter',''),
('abstract_csv_package','th_param_val','en','File Value',''),
('abstract_csv_package','th_row_count','en','Row Count',''),
('abstract_csv_package','th_table_name','en','Package Table','');
GO