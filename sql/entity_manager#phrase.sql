/* =============================================================================
 * Verze: 2026-11-13 16:15
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
('entity_manager','confirm_delete_draft','cs','Opravdu chcete trvale smazat tento rozpracovaný koncept?','',''),
('entity_manager','err_duplicate_key_active','cs','Záznam se zadanou klíčovou položkou ({$keys}) již v databázi existuje. Zadejte unikátní hodnotu, aby nedošlo k výpočtu duplicitního originálu.','',''),
('entity_manager','err_duplicate_key_in_trash','cs','Záznam se zadanou klíčovou položkou ({$keys}) již existuje v koši (zrušené záznamy). Zapněte v levém panelu „Zobrazit i zrušené“ a záznam obnovte, nebo zvolte jiný unikátní kód.','',''),
('entity_manager','err_hierarchy_code_collides_class','cs','Kód hierarchie „{$code}“ koliduje s názvem již existující logické třídy v meta_class. Zvolte prosím jiný unikátní kód.','',''),
('entity_manager','err_key_col_empty','cs','Klíčová položka „{$label}“ ({$col}) nesmí být prázdná.','',''),
('entity_manager','err_leaf_cannot_have_children','cs','Zvolená nadřízená položka je koncovým listem (is_leaf = 1). Pod koncovou položku nelze vkládat další podpoložky; vyberte složku (nebo u nadřízené položky nejprve odškrtněte příznak Koncový uzel).','',''),
('entity_manager','err_mandatory_fields_prefix','cs','Vyplňte prosím povinné položky: ','',''),
('entity_manager','err_meta_not_found','cs','Metadata pro logickou třídu {$class} nebyla nalezena.','',''),
('entity_manager','err_node_has_children_cannot_be_leaf','cs','Tento uzel obsahuje podřízené položky, a proto nemůže být označen jako koncový list (is_leaf = 1) ani přesunut do koše.','',''),
('entity_manager','err_node_has_links_cannot_move_or_delete','cs','Tento uzel (nebo jeho podřízený uzel) má již v databázi navázané záznamy nebo vazby. Změna nadřízeného uzlu (přepodřízení) a přesun do koše nejsou povoleny.','',''),
('entity_manager','err_parent_cycle','cs','Nepovolené zacyklení stromu: Položka nemůže být podřízena sama sobě ani svému vlastnímu potomkovi.','',''),
('entity_manager','err_scale_duplicate_threshold','cs','Stupeň se shodnou prahovou hodnotou ({$thr} %) již v této škále existuje ({$name}). Prahové hodnoty musí tvořit rostoucí řadu.','',''),
('entity_manager','err_scale_score_exceeds_next_threshold','cs','Hodnota skóre ({$scr} %) u stupně „{$name}“ přesahuje prahovou hodnotu následujícího stupně ({$next} %).','',''),
('entity_manager','err_scale_score_not_monotonic','cs','Hodnoty skóre musí tvořit rostoucí řadu: stupeň „{$name}“ ({$scr} %) musí mít vyšší skóre než předchozí stupeň „{$prev_name}“ ({$prev_scr} %).','',''),
('entity_manager','err_scale_score_under_threshold','cs','Hodnota skóre ({$scr} %) nesmí být nižší než dolní práh intervalu stupně ({$thr} %).','',''),
('entity_manager','lbl_approval_note_input','cs','Průvodní poznámka k návrhu / připomínka ke schválení:','',''),
('entity_manager','lbl_auto_code_hint','cs','Automaticky odvozeno z názvu (můžete upravit)','',''),
('entity_manager','lbl_inherited_from_ancestor','cs','Děděno z předka:','',''),
('entity_manager','lbl_record_removed_checkbox','cs','Přesunout záznam do koše (zrušený záznam)','',''),
('entity_manager','msg_draft_Banner','cs','Pracujete s vlastním rozpracovaným konceptem (stav D). Změny zatím nejsou viditelné pro ostatní uživatele.','',''),
('entity_manager','msg_forwarded_banner','cs','Tento návrh byl předán ke schválení (stav F). Další úpravy uloží aktualizovanou verzi návrhu.','',''),
('entity_manager','msg_rejected_banner','cs','Schvalovatel vrátil tento návrh k přepracování (stav R). Důvod vrácení:','',''),
('entity_manager','msg_remove_lang_mutation_only','cs','Ruší pouze jazykovou mutaci ({$lang})','',''),
('entity_manager','opt_root_no_parent','cs','--- Kořenová položka (bez nadřízeného uzlu) ---','',''),
('entity_manager','opt_select_empty','cs','--- Vyberte ---','',''),
('entity_manager','ph_approval_note','cs','Zadejte volitelnou poznámku pro schvalovatele...','',''),
('entity_manager','sec_other_attributes','cs','Ostatní vlastnosti','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('entity_manager','confirm_delete_draft','en','Are you sure you want to permanently delete this work-in-progress draft?',''),
('entity_manager','err_duplicate_key_active','en','A record with the specified key value ({$keys}) already exists in the database. Please enter a unique value to avoid a duplicate original identifier.',''),
('entity_manager','err_duplicate_key_in_trash','en','A record with the specified key value ({$keys}) already exists in the trash (removed records). Enable "Show removed" in the left panel to restore it, or choose a different unique code.',''),
('entity_manager','err_hierarchy_code_collides_class','en','The hierarchy code "{$code}" collides with an existing logical class name in meta_class. Please choose a different unique code.',''),
('entity_manager','err_key_col_empty','en','Key field "{$label}" ({$col}) cannot be empty.',''),
('entity_manager','err_leaf_cannot_have_children','en','The selected parent item is a terminal leaf node (is_leaf = 1). Child items cannot be placed under a leaf node; select a folder (or uncheck Leaf Node on the parent item first).',''),
('entity_manager','err_mandatory_fields_prefix','en','Please fill in the mandatory fields: ',''),
('entity_manager','err_meta_not_found','en','Metadata for logical class {$class} was not found.',''),
('entity_manager','err_node_has_children_cannot_be_leaf','en','This node contains child items and therefore cannot be marked as a terminal leaf node (is_leaf = 1) or moved to trash.',''),
('entity_manager','err_node_has_links_cannot_move_or_delete','en','This node (or its child node) already has linked records in the database. Changing its parent node (reparenting) or moving it to trash is not permitted.',''),
('entity_manager','err_parent_cycle','en','Invalid tree cycle: An item cannot be a child of itself or its own descendant.',''),
('entity_manager','err_scale_duplicate_threshold','en','A level with the same threshold value ({$thr} %) already exists in this scale ({$name}). Threshold values must form a strictly increasing sequence.',''),
('entity_manager','err_scale_score_exceeds_next_threshold','en','The score value ({$scr} %) of level "{$name}" exceeds the threshold value of the next level ({$next} %).',''),
('entity_manager','err_scale_score_not_monotonic','en','Score values must form an increasing sequence: level "{$name}" ({$scr} %) must have a higher score than the preceding level "{$prev_name}" ({$prev_scr} %).',''),
('entity_manager','err_scale_score_under_threshold','en','The score value ({$scr} %) cannot be lower than the lower threshold of the level interval ({$thr} %).',''),
('entity_manager','lbl_approval_note_input','en','Proposal note / comment for approver:',''),
('entity_manager','lbl_auto_code_hint','en','Automatically derived from name (editable)',''),
('entity_manager','lbl_inherited_from_ancestor','en','Inherited from ancestor:',''),
('entity_manager','lbl_record_removed_checkbox','en','Move record to trash (removed record)',''),
('entity_manager','msg_draft_Banner','en','You are working on your private draft (state D). Changes are not yet visible to other users.',''),
('entity_manager','msg_forwarded_banner','en','This proposal has been submitted for approval (state F). Saving further changes will update the submitted proposal.',''),
('entity_manager','msg_rejected_banner','en','The approver returned this proposal for revision (state R). Reason:',''),
('entity_manager','msg_remove_lang_mutation_only','en','Removes only the language mutation ({$lang})',''),
('entity_manager','opt_root_no_parent','en','--- Root Item (No Parent Node) ---',''),
('entity_manager','opt_select_empty','en','--- Select ---',''),
('entity_manager','ph_approval_note','en','Enter an optional note for the approver...',''),
('entity_manager','sec_other_attributes','en','Other Attributes','');
GO