/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_service_logbook#phrase.sql
 * Účel:   Registrace stránky page_service_logbook do sysinit_object, položky
 *         menu service_logbook do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_service_logbook';
DELETE FROM sysinit_menu WHERE builtin_code = 'service_logbook';
DELETE FROM sysinit_phrase WHERE source_code = 'page_service_logbook';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_service_logbook','cs','S','Provozní deník (service_logbook)','Přehled historie provedených upgradů databáze a importů systémových dávek'),
('P','page_service_logbook','en','S','Service Logbook (service_logbook)','History of executed database upgrades and system batch imports');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('service_logbook','cs','admin_folder','060','page_service_logbook','','S','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>','Provozní deník (Logbook)','Přehled historie provedených upgradů databáze a importů systémových dávek','Přehled historie provedených upgradů databáze a importů systémových dávek');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('service_logbook','en','Service Logbook','History of executed database upgrades and system batch imports','History of executed database upgrades and system batch imports');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_service_logbook','btn_apply_filter','cs','Filtrovat','Vyhledá záznamy v provozním deníku podle zadaných kritérií',''),
('page_service_logbook','btn_reset_filter','cs','Zrušit filtr','Vymaže filtr a zobrazí nejnovější záznamy provozního deníku','btn-secondary'),
('page_service_logbook','heading_logbook','cs','Provozní deník databáze (service_logbook)','',''),
('page_service_logbook','intro_logbook','cs','Chronologická evidence spuštěných změnových skriptů (changes_YYYY.sql), importů metadat a servisních operací (seřazeno sestupně od nejnovějších).','',''),
('page_service_logbook','lbl_displayed_records','cs','Zobrazeno záznamů: {$count}','',''),
('page_service_logbook','lbl_filter_limit','cs','Počet řádků:','',''),
('page_service_logbook','lbl_filter_name','cs','Název skriptu / operace:','',''),
('page_service_logbook','lbl_filter_text','cs','Hledat v popisu / verzi:','',''),
('page_service_logbook','msg_no_records','cs','Zadaným kritériím neodpovídají v tabulce service_logbook žádné záznamy.','',''),
('page_service_logbook','opt_all_scripts','cs','--- Všechny skripty a operace ---','',''),
('page_service_logbook','page_title','cs','Provozní deník (service_logbook) - BCM Osiris','',''),
('page_service_logbook','ph_filter_text','cs','Zadejte hledaný text nebo číslo verze...','',''),
('page_service_logbook','th_content','cs','Obsah / Popis provedené změny','',''),
('page_service_logbook','th_date','cs','Datum a čas','',''),
('page_service_logbook','th_id','cs','ID','',''),
('page_service_logbook','th_name','cs','Skript / Operace','',''),
('page_service_logbook','th_original_login','cs','SQL Login','',''),
('page_service_logbook','th_servername','cs','Server','',''),
('page_service_logbook','th_version','cs','Verze','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_service_logbook','btn_apply_filter','en','Filter','Filter service logbook entries by the specified criteria'),
('page_service_logbook','btn_reset_filter','en','Reset Filter','Clear filter criteria and display the latest logbook entries'),
('page_service_logbook','heading_logbook','en','Database Service Logbook (service_logbook)',''),
('page_service_logbook','intro_logbook','en','Chronological log of executed upgrade scripts (changes_YYYY.sql), metadata imports, and service operations (sorted descending from newest).',''),
('page_service_logbook','lbl_displayed_records','en','Displayed records: {$count}',''),
('page_service_logbook','lbl_filter_limit','en','Row limit:',''),
('page_service_logbook','lbl_filter_name','en','Script / operation name:',''),
('page_service_logbook','lbl_filter_text','en','Search description / version:',''),
('page_service_logbook','msg_no_records','en','No records in service_logbook match the specified criteria.',''),
('page_service_logbook','opt_all_scripts','en','--- All Scripts & Operations ---',''),
('page_service_logbook','page_title','en','Service Logbook (service_logbook) - BCM Osiris',''),
('page_service_logbook','ph_filter_text','en','Enter search text or version number...',''),
('page_service_logbook','th_content','en','Content / Change Description',''),
('page_service_logbook','th_date','en','Date & Time',''),
('page_service_logbook','th_id','en','ID',''),
('page_service_logbook','th_name','en','Script / Operation',''),
('page_service_logbook','th_original_login','en','SQL Login',''),
('page_service_logbook','th_servername','en','Server',''),
('page_service_logbook','th_version','en','Version','');
GO