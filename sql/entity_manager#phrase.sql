/* =============================================================================
 * Verze: 2026-11-15 19:55
 * Soubor: entity_manager#phrase.sql
 * Účel:   Registrace třídy entity_manager do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'entity_manager';
DELETE FROM sysinit_phrase WHERE source_code = 'entity_manager';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','entity_manager','cs','U','Správce logických entit','Dynamický generátor SQL dotazů, seznamů a formulářů podle metadat'),
('P','entity_manager','en','U','Logical Entity Manager','Dynamic metadata-driven generator of SQL queries, lists, and forms');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('entity_manager','confirm_mark_removed','cs','Potvrďte, že chcete tuto položku označit jako zrušenou.','',''),
('entity_manager','err_duplicate_key_active','cs','Záznam se zadanou klíčovou položkou ({$keys}) již v databázi existuje. Zadejte unikátní hodnotu, aby nedošlo k výpočtu duplicitního originálu.','',''),
('entity_manager','err_duplicate_key_in_trash','cs','Záznam se zadanou klíčovou položkou ({$keys}) již existuje v koši (zrušené záznamy). Zapněte v levém panelu „Zobrazit i zrušené“ a záznam obnovte, nebo zvolte jiný unikátní kód.','',''),
('entity_manager','err_duplicate_link','cs','Tato vazba mezi zvolenými záznamy již existuje.','',''),
('entity_manager','err_em_title','cs','Entity manager','',''),
('entity_manager','err_hierarchy_code_collides_class','cs','Kód hierarchie „{$code}“ koliduje s názvem již existující logické třídy v meta_class. Zvolte prosím jiný unikátní kód.','',''),
('entity_manager','err_key_col_empty','cs','Klíčová položka „{$label}“ ({$col}) nesmí být prázdná.','',''),
('entity_manager','err_link_keys_empty','cs','Klíčové položky vazby (link_def, from_object, to_object) musí být vyplněny.','',''),
('entity_manager','err_meta_not_found','cs','Metadata pro logickou třídu {$class} nebyla nalezena.','',''),
('entity_manager','err_save_failed_title','cs','Uložení selhalo','',''),
('entity_manager','err_save_no_session','cs','Nepodařilo se načíst kontext uživatele z globální relace dbsession.','',''),
('entity_manager','err_scale_duplicate_threshold','cs','Stupeň se shodnou prahovou hodnotou ({$thr} %) již v této škále existuje ({$name}). Prahové hodnoty musí tvořit rostoucí řadu.','',''),
('entity_manager','err_scale_first_threshold_zero','cs','Nejnižší stupeň hodnotící škály musí mít dolní prahovou hodnotu (threshold_value) rovnu 0 %.','',''),
('entity_manager','err_scale_missing','cs','Musí být zvolena nadřazená hodnotící škála (scale).','',''),
('entity_manager','err_scale_score_below_threshold','cs','Hodnota skóre (score_value) nesmí být menší než dolní prahová hodnota (threshold_value) daného stupně.','',''),
('entity_manager','err_scale_score_exceeds_next_threshold','cs','Hodnota skóre ({$scr} %) u stupně „{$name}“ přesahuje prahovou hodnotu následujícího stupně ({$next} %).','',''),
('entity_manager','err_scale_score_not_monotonic','cs','Hodnoty skóre musí tvořit rostoucí řadu: stupeň „{$name}“ ({$scr} %) musí mít vyšší skóre než předchozí stupeň „{$prev_name}“ ({$prev_scr} %).','',''),
('entity_manager','err_scale_val_range','cs','Prahová hodnota (threshold_value) i skóre (score_value) musí ležet v procentuálním intervalu 0 až 100 %.','',''),
('entity_manager','lbl_empty_richtext','cs','(Prázdné)','',''),
('entity_manager','lbl_record_removed','cs','Zrušený záznam (removed)','',''),
('entity_manager','msg_auto_rejected_other_approved','cs','Byl schválen záznam jiného uživatele.','',''),
('entity_manager','msg_rejected_by_approver','cs','Vráceno schvalovatelem k přepracování.','',''),
('entity_manager','msg_remove_global_cls_denied','cs','Systémový kontejner sys_global_columns nelze zrušit','',''),
('entity_manager','msg_remove_lang_denied','cs','Nemáte oprávnění rušit systémové překlady tohoto jazyka','',''),
('entity_manager','msg_remove_lang_mutation_only','cs','Ruší pouze jazykovou mutaci ({$lang})','',''),
('entity_manager','msg_remove_menu_home_denied','cs','Kořenovou položku menu (home) nelze zrušit','',''),
('entity_manager','msg_remove_meta_only_dev','cs','Systémová metadata smí rušit pouze vývojář (Developer)','',''),
('entity_manager','msg_remove_node_has_children','cs','Uzel hierarchie nelze zrušit, dokud obsahuje aktivní podřízené položky','',''),
('entity_manager','msg_remove_node_locked_by_links','cs','Uzel hierarchie nelze zrušit, protože jsou na něj navázány platné záznamy','',''),
('entity_manager','msg_remove_phys_col_denied','cs','Fyzicky existující sloupec databázové tabulky nelze v metadatech zrušit','',''),
('entity_manager','msg_remove_phys_object_denied','cs','Fyzický databázový objekt ani kontejner global_phrase nelze v metadatech zrušit','',''),
('entity_manager','msg_remove_prim_class_denied','cs','Primitivní třídu svázanou s existující fyzickou tabulkou nelze zrušit','',''),
('entity_manager','msg_remove_root_0x00_denied','cs','Systémový kořenový záznam (0x00) nelze zrušit','',''),
('entity_manager','msg_remove_system_record_denied','cs','Systémový záznam nelze v organizaci smazat (použijte příznak Neaktivní)','',''),
('entity_manager','opt_global_phrase_source','cs','global_phrase (Globální fráze systému)','',''),
('entity_manager','opt_select_default','cs','--- Vyberte ---','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('entity_manager','confirm_mark_removed','en','Please confirm that you want to mark this item as removed.',''),
('entity_manager','err_duplicate_key_active','en','A record with the specified key value ({$keys}) already exists in the database. Please enter a unique value to avoid a duplicate original identifier.',''),
('entity_manager','err_duplicate_key_in_trash','en','A record with the specified key value ({$keys}) already exists in the trash (removed records). Enable "Show removed" in the left panel to restore it, or choose a different unique code.',''),
('entity_manager','err_duplicate_link','en','This link between the selected records already exists.',''),
('entity_manager','err_em_title','en','Entity Manager',''),
('entity_manager','err_hierarchy_code_collides_class','en','The hierarchy code "{$code}" collides with an existing logical class name in meta_class. Please choose a different unique code.',''),
('entity_manager','err_key_col_empty','en','Key field "{$label}" ({$col}) cannot be empty.',''),
('entity_manager','err_link_keys_empty','en','Key link fields (link_def, from_object, to_object) must be filled in.',''),
('entity_manager','err_meta_not_found','en','Metadata for logical class {$class} was not found.',''),
('entity_manager','err_save_failed_title','en','Save Failed',''),
('entity_manager','err_save_no_session','en','Failed to load user context from global dbsession.',''),
('entity_manager','err_scale_duplicate_threshold','en','A level with the same threshold value ({$thr} %) already exists in this scale ({$name}). Threshold values must form a strictly increasing sequence.',''),
('entity_manager','err_scale_first_threshold_zero','en','The lowest level of an assessment scale must have a lower threshold value (threshold_value) equal to 0 %.',''),
('entity_manager','err_scale_missing','en','A parent assessment scale (scale) must be selected.',''),
('entity_manager','err_scale_score_below_threshold','en','The score value (score_value) cannot be less than the lower threshold value (threshold_value) of the level.',''),
('entity_manager','err_scale_score_exceeds_next_threshold','en','The score value ({$scr} %) of level "{$name}" exceeds the threshold value of the next level ({$next} %).',''),
('entity_manager','err_scale_score_not_monotonic','en','Score values must form an increasing sequence: level "{$name}" ({$scr} %) must have a higher score than the preceding level "{$prev_name}" ({$prev_scr} %).',''),
('entity_manager','err_scale_val_range','en','Both the threshold value (threshold_value) and score value (score_value) must lie within the 0 to 100 % percentage interval.',''),
('entity_manager','lbl_empty_richtext','en','(Empty)',''),
('entity_manager','lbl_record_removed','en','Removed Record (removed)',''),
('entity_manager','msg_auto_rejected_other_approved','en','Another user''s proposal for this record was approved.',''),
('entity_manager','msg_rejected_by_approver','en','Returned by approver for revision.',''),
('entity_manager','msg_remove_global_cls_denied','en','System container sys_global_columns cannot be removed',''),
('entity_manager','msg_remove_lang_denied','en','You do not have permission to remove system translations for this language',''),
('entity_manager','msg_remove_lang_mutation_only','en','Removes only the language mutation ({$lang})',''),
('entity_manager','msg_remove_menu_home_denied','en','Root menu item (home) cannot be removed',''),
('entity_manager','msg_remove_meta_only_dev','en','System metadata can only be removed by a Developer',''),
('entity_manager','msg_remove_node_has_children','en','Hierarchy node cannot be removed while it contains active child items',''),
('entity_manager','msg_remove_node_locked_by_links','en','Hierarchy node cannot be removed because active records are linked to it',''),
('entity_manager','msg_remove_phys_col_denied','en','Physically existing database table column cannot be removed in metadata',''),
('entity_manager','msg_remove_phys_object_denied','en','Physical database object or global_phrase container cannot be removed in metadata',''),
('entity_manager','msg_remove_prim_class_denied','en','Primitive class bound to an existing physical table cannot be removed',''),
('entity_manager','msg_remove_root_0x00_denied','en','System root record (0x00) cannot be removed',''),
('entity_manager','msg_remove_system_record_denied','en','System record cannot be deleted in an organization (use the Inactive flag instead)',''),
('entity_manager','opt_global_phrase_source','en','global_phrase (System Global Phrases)',''),
('entity_manager','opt_select_default','en','--- Select ---','');
GO