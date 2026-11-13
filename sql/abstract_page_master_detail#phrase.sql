/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: abstract_page_master_detail#phrase.sql
 * Účel:   Registrace šablony abstract_page_master_detail do sysinit_object
 *         a naplnění jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'abstract_page_master_detail';
DELETE FROM sysinit_phrase WHERE source_code = 'abstract_page_master_detail';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','abstract_page_master_detail','cs','U','Šablona Master-Detail','Abstraktní dvoupanelová šablona pro správu entit'),
('P','abstract_page_master_detail','en','U','Master-Detail Template','Abstract two-panel template for entity management');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('abstract_page_master_detail','badge_draft','cs','Koncept','',''),
('abstract_page_master_detail','badge_forwarded','cs','Ke schválení','',''),
('abstract_page_master_detail','badge_rejected','cs','Vráceno','',''),
('abstract_page_master_detail','badge_removed','cs','Zrušeno','',''),
('abstract_page_master_detail','default_detail_heading','cs','Detail záznamu','',''),
('abstract_page_master_detail','default_list_heading','cs','Seznam záznamů','',''),
('abstract_page_master_detail','err_ajax_detail','cs','Chyba při načítání detailu:','',''),
('abstract_page_master_detail','err_ajax_network','cs','Chyba sítě při AJAX volání','',''),
('abstract_page_master_detail','err_ajax_refresh','cs','Chyba při obnově master panelu:','',''),
('abstract_page_master_detail','lbl_quick_filter_info','cs','Rychlý filtr','',''),
('abstract_page_master_detail','lbl_show_removed','cs','Zobrazit i zrušené','',''),
('abstract_page_master_detail','msg_no_list_columns','cs','Master panel nemá v metadatech (list_order) definované žádné sloupce.','',''),
('abstract_page_master_detail','msg_select_item_prompt','cs','Vyberte položku v levém seznamu pro zobrazení a úpravu detailu.','',''),
('abstract_page_master_detail','placeholder_search','cs','Hledat...','',''),
('abstract_page_master_detail','tip_clear_adv_filter','cs','Zrušit rozšířený filtr','',''),
('abstract_page_master_detail','tip_csv_export_import','cs','Export / Import dat této třídy (CSV balíček simple_class)','',''),
('abstract_page_master_detail','tip_open_adv_filter','cs','Rozšířený filtr podle více položek','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('abstract_page_master_detail','badge_draft','en','Draft',''),
('abstract_page_master_detail','badge_forwarded','en','Pending Approval',''),
('abstract_page_master_detail','badge_rejected','en','Returned',''),
('abstract_page_master_detail','badge_removed','en','Removed',''),
('abstract_page_master_detail','default_detail_heading','en','Record Detail',''),
('abstract_page_master_detail','default_list_heading','en','Record List',''),
('abstract_page_master_detail','err_ajax_detail','en','Error loading detail panel:',''),
('abstract_page_master_detail','err_ajax_network','en','Network error during AJAX call',''),
('abstract_page_master_detail','err_ajax_refresh','en','Error refreshing master panel:',''),
('abstract_page_master_detail','lbl_quick_filter_info','en','Quick filter',''),
('abstract_page_master_detail','lbl_show_removed','en','Show removed',''),
('abstract_page_master_detail','msg_no_list_columns','en','Master panel has no columns defined in metadata (list_order).',''),
('abstract_page_master_detail','msg_select_item_prompt','en','Select an item in the left list to view and edit its details.',''),
('abstract_page_master_detail','placeholder_search','en','Search...',''),
('abstract_page_master_detail','tip_clear_adv_filter','en','Clear advanced filter',''),
('abstract_page_master_detail','tip_csv_export_import','en','Export / Import data of this class (simple_class CSV package)',''),
('abstract_page_master_detail','tip_open_adv_filter','en','Advanced multi-field filter','');
GO