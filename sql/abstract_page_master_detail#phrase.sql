/* =============================================================================
 * Verze: 2026-11-21 11:30
 * Soubor: abstract_page_master_detail#phrase.sql
 *
 * 1. Role souboru v celém systému:
 *    Registrace šablony abstract_page_master_detail do sysinit_object a
 *    naplnění jejích českých a anglických frází do sysinit_phrase.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Odpovídá voláním $this->phrase() v abstract_page_master_detail.php.
 *    - Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (maska *#phrase.sql) nad
 *      staging tabulkami sysinit_* bez závislosti na relaci v dbsession.
 *
 * Změny:
 * - 2026-11-21 11:30: Doplněna fráze msg_record_readonly_save_denied pro cs i en.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'abstract_page_master_detail';
DELETE FROM sysinit_phrase WHERE source_code = 'abstract_page_master_detail';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','abstract_page_master_detail','cs','U','Šablona Master-Detail','Abstraktní dvoupanelová šablona pro správu entit'),
('P','abstract_page_master_detail','en','U','Master-Detail Template','Abstract two-panel template for entity management');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('abstract_page_master_detail','audit_created_by','cs','Vytvořil','',''),
('abstract_page_master_detail','audit_modified_by','cs','Změnil','',''),
('abstract_page_master_detail','audit_unknown_user','cs','Neznámý uživatel','',''),
('abstract_page_master_detail','badge_draft','cs','Koncept','',''),
('abstract_page_master_detail','badge_forwarded','cs','Ke schválení','',''),
('abstract_page_master_detail','badge_rejected','cs','Vráceno','',''),
('abstract_page_master_detail','badge_removed','cs','Zrušeno','',''),
('abstract_page_master_detail','confirm_delete_draft','cs','Opravdu chcete tento koncept bez náhrady odstranit?','',''),
('abstract_page_master_detail','default_detail_heading','cs','Detail záznamu','',''),
('abstract_page_master_detail','default_list_heading','cs','Seznam záznamů','',''),
('abstract_page_master_detail','err_ajax_detail','cs','Chyba při načítání detailu:','',''),
('abstract_page_master_detail','err_ajax_network','cs','Chyba sítě při AJAX volání','',''),
('abstract_page_master_detail','err_ajax_refresh','cs','Chyba při obnově master panelu:','',''),
('abstract_page_master_detail','lbl_mandatory_field','cs','Povinné pole','',''),
('abstract_page_master_detail','lbl_quick_filter_info','cs','Rychlý filtr','',''),
('abstract_page_master_detail','lbl_rejection_reason','cs','Důvod vrácení:','',''),
('abstract_page_master_detail','lbl_show_removed','cs','Zobrazit i zrušené','',''),
('abstract_page_master_detail','lbl_supports_translation','cs','(Podporuje překlad)','',''),
('abstract_page_master_detail','lbl_translatable_tooltip','cs','Tato hodnota může být přeložena do jiných jazyků','',''),
('abstract_page_master_detail','msg_detail_not_configured','cs','Detail panel není nakonfigurován.','',''),
('abstract_page_master_detail','msg_insert_not_allowed','cs','Zakládání nových záznamů není v této úloze povoleno.','',''),
('abstract_page_master_detail','msg_no_list_columns','cs','Master panel nemá v metadatech (list_order) definované žádné sloupce.','',''),
('abstract_page_master_detail','msg_record_not_found','cs','Záznam nebyl nalezen.','',''),
('abstract_page_master_detail','msg_record_readonly_save_denied','cs','Tento záznam je uzamčen pouze pro čtení a nelze jej upravovat ani mazat.','',''),
('abstract_page_master_detail','msg_select_from_left','cs','Vyberte záznam z levého panelu.','',''),
('abstract_page_master_detail','msg_ssc_status_draft','cs','Pracujete s rozpracovaným konceptem, který je viditelný pouze pro vás.','',''),
('abstract_page_master_detail','msg_ssc_status_forwarded','cs','Tento záznam je postoupen ke schválení. Do doby schválení jej můžete dále upravit nebo stáhnout zpět do konceptu.','',''),
('abstract_page_master_detail','msg_ssc_status_rejected','cs','Tento návrh byl vrácen / odmítnut schvalovatelem. Můžete jej upravit a znovu postoupit, nebo smazat.','',''),
('abstract_page_master_detail','msg_unsaved_changes','cs','Máte neuložené změny. Opravdu chcete stránku opustit?','',''),
('abstract_page_master_detail','placeholder_search','cs','Hledat...','',''),
('abstract_page_master_detail','tip_clear_adv_filter','cs','Zrušit rozšířený filtr','',''),
('abstract_page_master_detail','tip_csv_export_import','cs','Export / Import dat této třídy (CSV balíček simple_class)','',''),
('abstract_page_master_detail','tip_open_adv_filter','cs','Rozšířený filtr podle více položek','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('abstract_page_master_detail','audit_created_by','en','Created by',''),
('abstract_page_master_detail','audit_modified_by','en','Modified by',''),
('abstract_page_master_detail','audit_unknown_user','en','Unknown user',''),
('abstract_page_master_detail','badge_draft','en','Draft',''),
('abstract_page_master_detail','badge_forwarded','en','Pending Approval',''),
('abstract_page_master_detail','badge_rejected','en','Returned',''),
('abstract_page_master_detail','badge_removed','en','Removed',''),
('abstract_page_master_detail','confirm_delete_draft','en','Are you sure you want to permanently delete this draft?',''),
('abstract_page_master_detail','default_detail_heading','en','Record Detail',''),
('abstract_page_master_detail','default_list_heading','en','Record List',''),
('abstract_page_master_detail','err_ajax_detail','en','Error loading detail panel:',''),
('abstract_page_master_detail','err_ajax_network','en','Network error during AJAX call',''),
('abstract_page_master_detail','err_ajax_refresh','en','Error refreshing master panel:',''),
('abstract_page_master_detail','lbl_mandatory_field','en','Mandatory field',''),
('abstract_page_master_detail','lbl_quick_filter_info','en','Quick filter',''),
('abstract_page_master_detail','lbl_rejection_reason','en','Reason for return:',''),
('abstract_page_master_detail','lbl_show_removed','en','Show removed',''),
('abstract_page_master_detail','lbl_supports_translation','en','(Supports translation)',''),
('abstract_page_master_detail','lbl_translatable_tooltip','en','This value can be translated into other languages',''),
('abstract_page_master_detail','msg_detail_not_configured','en','Detail panel is not configured.',''),
('abstract_page_master_detail','msg_insert_not_allowed','en','Creating new records is not allowed in this agenda.',''),
('abstract_page_master_detail','msg_no_list_columns','en','Master panel has no columns defined in metadata (list_order).',''),
('abstract_page_master_detail','msg_record_not_found','en','Record was not found.',''),
('abstract_page_master_detail','msg_record_readonly_save_denied','en','This record is locked as read-only and cannot be edited or deleted.',''),
('abstract_page_master_detail','msg_select_from_left','en','Select a record from the left panel.',''),
('abstract_page_master_detail','msg_ssc_status_draft','en','You are working on a private draft visible only to you.',''),
('abstract_page_master_detail','msg_ssc_status_forwarded','en','This record is submitted for approval. Until approved, you may continue editing it or revert it to a draft.',''),
('abstract_page_master_detail','msg_ssc_status_rejected','en','This proposal was returned / rejected by the approver. You may revise and resubmit it, or delete it.',''),
('abstract_page_master_detail','msg_unsaved_changes','en','You have unsaved changes. Are you sure you want to leave this page?',''),
('abstract_page_master_detail','placeholder_search','en','Search...',''),
('abstract_page_master_detail','tip_clear_adv_filter','en','Clear advanced filter',''),
('abstract_page_master_detail','tip_csv_export_import','en','Export / Import data of this class (simple_class CSV package)',''),
('abstract_page_master_detail','tip_open_adv_filter','en','Advanced multi-field filter','');
GO