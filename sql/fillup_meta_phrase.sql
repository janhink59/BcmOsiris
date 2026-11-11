/* =============================================================================
 * Verze: 2026-11-11 22:45
 * Soubor: fillup_meta_phrase.sql
 * Účel:   Hromadné idempotentní naplnění a aktualizace výchozích českých frází
 *         (jazyk 'cs') v tabulce meta_phrase (object_owner = 0x00) pro všechny
 *         existující PHP třídy a stránky, seřazené podle (source_code, builtin_code)
 *         a rozdělené do bloků /*#od# <source_code> */ ... /*#do# <source_code> */.
 *         Nastavuje záznamy typu 'A' a symetrické 'L' záznamy pro jazyk 'cs'
 *         u všech položek s who_modified = 0x00, date_modified < '2026-11-01'
 *         nebo import_origin = 'AUTO_DISCOVERED'.
 * Vazby:  - Vyžaduje tabulku meta_object (fillup_meta_object.sql), tabulku
 *           meta_phrase a funkci dbo.f_generate_original.
 *         - Automaticky zařazeno v BuildListDb.txt přes masku fillup_*.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @phr_cs TABLE (
	source_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
	builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
	caption varchar(max) NOT NULL,
	helptext varchar(max) NOT NULL,
	css_class varchar(200) NOT NULL,
	PRIMARY KEY (source_code, builtin_code)
);

INSERT INTO @phr_cs (source_code, builtin_code, caption, helptext, css_class) VALUES
/*#od# abstract_button */
('abstract_button','btn_cancel','Zrušit','Zruší akci a vrátí se zpět','btn-secondary'),
('abstract_button','btn_delete_draft','Smazat koncept','Trvale odstraní váš rozpracovaný nebo vrácený koncept bez ovlivnění platného záznamu','btn-danger'),
('abstract_button','btn_discard','Zahodit změny','Zruší neuložené úpravy ve formuláři a zavře detail záznamu','btn-danger'),
('abstract_button','btn_forward_approval','Předat ke schválení','Odešle návrh změny ke kontrole a schválení (stav F)',''),
('abstract_button','btn_save','Uložit změny','Uloží provedené úpravy přímo jako platný schválený záznam (stav A)','btn-success'),
('abstract_button','btn_save_draft','Uložit koncept','Uloží rozpracovaný koncept viditelný pouze pro vás (stav D)','btn-secondary'),
/*#do# abstract_button */

/*#od# abstract_csv_package */
('abstract_csv_package','btn_export_csv','Exportovat balíček (CSV)','Vygeneruje a stáhne podepsaný víceblokový CSV soubor balíčku','btn-success'),
('abstract_csv_package','btn_run_phase2','Spustit import do databáze (Fáze 2)','Spustí uloženou proceduru pro zápis zkontrolovaných dat do databáze','btn-success'),
('abstract_csv_package','err_empty_mandatory_cells','Sloupec obsahuje prázdné hodnoty v povinném poli.','',''),
('abstract_csv_package','err_file_not_readable','Vstupní soubor nelze přečíst.','',''),
('abstract_csv_package','err_file_open_failed','Nepodařilo se otevřít vstupní soubor.','',''),
('abstract_csv_package','err_import_rolled_back','Import balíčku byl stornován kvůli chybám (Rollback).','',''),
('abstract_csv_package','err_invalid_signature','Neplatný bezpečnostní podpis souboru (soubor byl neautorizovaně změněn nebo poškozen).','',''),
('abstract_csv_package','err_missing_mandatory_col','V tabulce chybí povinný sloupec.','',''),
('abstract_csv_package','err_missing_mandatory_param','Chybí povinný parametr balíčku.','',''),
('abstract_csv_package','err_missing_mandatory_table','V souboru chybí povinná tabulka.','',''),
('abstract_csv_package','err_proc_not_found','Uložená procedura pro zpracování balíčku nebyla v databázi nalezena.','',''),
('abstract_csv_package','err_same_org_only_blocked','Import není umožněn: Balíček má nastaveno omezení importu pouze do stejné organizace, která data exportovala (same_org_only = 1).','',''),
('abstract_csv_package','err_wrong_package_code','Kód balíčku v souboru neodpovídá zvolenému typu importu.','',''),
('abstract_csv_package','hdr_phase1_summary','Kontrola načteného balíčku (Fáze 1)','',''),
('abstract_csv_package','lbl_param_import_origin','Označení původu dat (import_origin)','',''),
('abstract_csv_package','lbl_param_same_org_only','Povolit import pouze do stejné organizace, která data exportovala','',''),
('abstract_csv_package','lbl_param_target_status','Režim zápisu při importu','',''),
('abstract_csv_package','lbl_param_verify_data','Vyžadovat nezměnitelnost dat (podpis celého souboru)','',''),
('abstract_csv_package','msg_import_committed','Import balíčku byl úspěšně dokončen a uložen (Commit).','',''),
('abstract_csv_package','msg_same_org_only_verified','Kontrola organizace (same_org_only = 1) proběhla úspěšně – import probíhá do stejné organizace.','',''),
('abstract_csv_package','msg_signature_verified','Bezpečnostní podpis souboru je platný (integrita ověřena).','',''),
('abstract_csv_package','opt_status_active','Zapsat přímo jako platné schválené záznamy (A)','',''),
('abstract_csv_package','opt_status_draft','Uložit jako rozpracované koncepty (D)','',''),
('abstract_csv_package','opt_status_forward','Předat schvalovateli ke schválení (F)','',''),
('abstract_csv_package','th_col_list','Načtené sloupce','',''),
('abstract_csv_package','th_param_code','Parametr','',''),
('abstract_csv_package','th_param_val','Hodnota v souboru','',''),
('abstract_csv_package','th_row_count','Počet řádků','',''),
('abstract_csv_package','th_table_name','Tabulka v balíčku','',''),
/*#do# abstract_csv_package */

/*#od# abstract_page */
('abstract_page','msg_access_denied','Přístup odepřen. K zobrazení této stránky nemáte dostatečná oprávnění.','',''),
('abstract_page','msg_unsaved_changes','Máte neuložené změny. Opravdu chcete stránku opustit?','',''),
/*#do# abstract_page */

/*#od# abstract_page_master_detail */
('abstract_page_master_detail','badge_draft','Koncept','',''),
('abstract_page_master_detail','badge_forwarded','Ke schválení','',''),
('abstract_page_master_detail','badge_rejected','Vráceno','',''),
('abstract_page_master_detail','badge_removed','Zrušeno','',''),
('abstract_page_master_detail','default_detail_heading','Detail záznamu','',''),
('abstract_page_master_detail','default_list_heading','Seznam záznamů','',''),
('abstract_page_master_detail','err_ajax_detail','Chyba při načítání detailu:','',''),
('abstract_page_master_detail','err_ajax_network','Chyba sítě při AJAX volání','',''),
('abstract_page_master_detail','err_ajax_refresh','Chyba při obnově master panelu:','',''),
('abstract_page_master_detail','lbl_quick_filter_info','Rychlý filtr','',''),
('abstract_page_master_detail','lbl_show_removed','Zobrazit i zrušené','',''),
('abstract_page_master_detail','msg_no_list_columns','Master panel nemá v metadatech (list_order) definované žádné sloupce.','',''),
('abstract_page_master_detail','msg_select_item_prompt','Vyberte položku v levém seznamu pro zobrazení a úpravu detailu.','',''),
('abstract_page_master_detail','placeholder_search','Hledat...','',''),
('abstract_page_master_detail','tip_clear_adv_filter','Zrušit rozšířený filtr','',''),
('abstract_page_master_detail','tip_csv_export_import','Export / Import dat této třídy (CSV balíček simple_class)','',''),
('abstract_page_master_detail','tip_open_adv_filter','Rozšířený filtr podle více položek','',''),
/*#do# abstract_page_master_detail */

/*#od# abstract_page_tree */
('abstract_page_tree','badge_draft','Koncept','',''),
('abstract_page_tree','badge_forwarded','Ke schválení','',''),
('abstract_page_tree','badge_rejected','Vráceno','',''),
('abstract_page_tree','badge_removed','Zrušeno','',''),
('abstract_page_tree','btn_collapse_all','Sbalit vše','Sbalí všechny rozbalené větve stromu v levém panelu',''),
('abstract_page_tree','btn_expand_all','Rozbalit vše','Rozbalí všechny složky stromu v levém panelu',''),
('abstract_page_tree','btn_new_tree_item','+ Nová položka','Založí novou položku ve stromové struktuře',''),
('abstract_page_tree','btn_split_node_oth','Rozčlenit na podtřídy (+ _oth)','Vytvoří pod tímto uzlem koncovou položku „Ostatní (*_oth)“, převede na ni navázané záznamy a uvolní tento uzel jako složku','btn-secondary'),
('abstract_page_tree','confirm_split_node_oth','Opravdu chcete tento koncový uzel změnit na složku a převést jeho přímé vazby a záznamy na novou podřízenou položku „Ostatní ({$code}_oth)“?','',''),
('abstract_page_tree','default_tree_heading','Strom záznamů','',''),
('abstract_page_tree','lbl_show_removed','Zobrazit i zrušené','',''),
('abstract_page_tree','msg_auto_split_parent_info','Nadřízený koncový uzel byl automaticky změněn na složku a jeho původní přímé záznamy byly převedeny na novou položku „{$code}“.','',''),
('abstract_page_tree','msg_dnd_unsaved_notice','Nadřízená položka (parent_uuid) a pořadí (sort_code) byly upraveny přetažením. Zkontrolujte údaje a potvrďte je tlačítkem Uložit změny (příp. Uložit koncept / Předat ke schválení).','',''),
('abstract_page_tree','msg_node_locked_notice','🔒 Tento uzel (nebo jeho podřízený uzel) má již navázané platné záznamy. Změna nadřízeného uzlu (přepodřízení) a smazání jsou uzamčeny; pokud potřebujete tento koncový uzel dále členit na podtřídy, použijte tlačítko „Rozčlenit na podtřídy (+ _oth)“ v záhlaví detailu (nebo pod něj rovnou přidejte novou položku).','',''),
('abstract_page_tree','placeholder_search','Hledat ve stromu...','',''),
('abstract_page_tree','th_builtin_code','Kód','',''),
('abstract_page_tree','th_sort_code','Pořadí','',''),
('abstract_page_tree','th_tree_caption','Název položky (Strom)','',''),
('abstract_page_tree','tip_drag_handle','Přetažením myší (Drag & Drop) upravíte pořadí nebo nadřízenou složku v detailu','',''),
('abstract_page_tree','tip_folder_node','Vnitřní složka hierarchie (is_leaf = 0)','',''),
('abstract_page_tree','tip_locked_node','Uzel má navázané záznamy – změna nadřízené složky je uzamčena (lze měnit pouze pořadí mezi sourozenci)','',''),
('abstract_page_tree','tip_toggle_branch','Sbalit / rozbalit podřízené položky','',''),
/*#do# abstract_page_tree */

/*#od# csv_package_metadata */
('csv_package_metadata','err_import_dev_only','Import systémových metadat je povolen pouze vývojářům v systémové organizaci (0x00).','',''),
('csv_package_metadata','lbl_filter_class_name','Filtrovat na logickou třídu (class_name)','',''),
('csv_package_metadata','lbl_filter_date_from','Pouze změněné od data (date_modified >=)','',''),
('csv_package_metadata','lbl_filter_language','Jazyk překladů (language)','',''),
('csv_package_metadata','lbl_filter_only_custom','Pouze klientské úpravy (who_modified <> 0x00)','',''),
('csv_package_metadata','lbl_filter_source_code','Filtrovat fráze podle zdroje (source_code)','',''),
('csv_package_metadata','opt_all_classes','--- Všechny třídy ---','',''),
('csv_package_metadata','opt_all_languages','--- Všechny jazyky ---','',''),
('csv_package_metadata','opt_all_sources','--- Všechny zdroje (stránky a třídy) ---','',''),
('csv_package_metadata','pkg_caption','Systémová metadata a překlady (meta_*)','',''),
('csv_package_metadata','pkg_description','Přenos systémových metadat (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def) mezi vývojovými a produkčními instancemi.','',''),
/*#do# csv_package_metadata */

/*#od# csv_package_simple_class */
('csv_package_simple_class','err_class_not_found','Zvolená logická třída nebyla v metadatech nalezena.','',''),
('csv_package_simple_class','info_all_langs_exported','Exportovány všechny dostupné jazykové verze','',''),
('csv_package_simple_class','info_single_lang_exported','Exportována pouze jedna jazyková verze: {$caption} ({$code})','',''),
('csv_package_simple_class','lbl_active_filter_info','Aktivní filtr ze stránky','',''),
('csv_package_simple_class','lbl_Export_language','Jazykové verze pro export','',''),
('csv_package_simple_class','lbl_select_class','Logická třída (tabulka)','',''),
('csv_package_simple_class','opt_lang_all','Všechny dostupné jazykové verze (A + všechna L)','',''),
('csv_package_simple_class','opt_lang_single','Pouze jedna jazyková verze: {$caption} ({$code})','',''),
('csv_package_simple_class','pkg_caption','Data jedné třídy organizace (Simple Class CSV)','',''),
('csv_package_simple_class','pkg_description','Export a dvoufázový import záznamů jedné vybrané logické třídy aktuální organizace (včetně stromových struktur a jazykových verzí).','',''),
/*#do# csv_package_simple_class */

/*#od# entity_manager */
('entity_manager','confirm_delete_draft','Opravdu chcete trvale smazat tento rozpracovaný koncept?','',''),
('entity_manager','err_duplicate_key_active','Záznam se zadanou klíčovou položkou ({$keys}) již v databázi existuje. Zadejte unikátní hodnotu, aby nedošlo k výpočtu duplicitního originálu.','',''),
('entity_manager','err_duplicate_key_in_trash','Záznam se zadanou klíčovou položkou ({$keys}) již existuje v koši (zrušené záznamy). Zapněte v levém panelu „Zobrazit i zrušené“ a záznam obnovte, nebo zvolte jiný unikátní kód.','',''),
('entity_manager','err_hierarchy_code_collides_class','Kód hierarchie „{$code}“ koliduje s názvem již existující logické třídy v meta_class. Zvolte prosím jiný unikátní kód.','',''),
('entity_manager','err_key_col_empty','Klíčová položka „{$label}“ ({$col}) nesmí být prázdná.','',''),
('entity_manager','err_leaf_cannot_have_children','Zvolená nadřízená položka je koncovým listem (is_leaf = 1). Pod koncovou položku nelze vkládat další podpoložky; vyberte složku (nebo u nadřízené položky nejprve odškrtněte příznak Koncový uzel).','',''),
('entity_manager','err_mandatory_fields_prefix','Vyplňte prosím povinné položky: ','',''),
('entity_manager','err_meta_not_found','Metadata pro logickou třídu {$class} nebyla nalezena.','',''),
('entity_manager','err_node_has_children_cannot_be_leaf','Tento uzel obsahuje podřízené položky, a proto nemůže být označen jako koncový list (is_leaf = 1) ani přesunut do koše.','',''),
('entity_manager','err_node_has_links_cannot_move_or_delete','Tento uzel (nebo jeho podřízený uzel) má již v databázi navázané záznamy nebo vazby. Změna nadřízeného uzlu (přepodřízení) a přesun do koše nejsou povoleny.','',''),
('entity_manager','err_parent_cycle','Nepovolené zacyklení stromu: Položka nemůže být podřízena sama sobě ani svému vlastnímu potomkovi.','',''),
('entity_manager','err_scale_duplicate_threshold','Stupeň se shodnou prahovou hodnotou ({$thr} %) již v této škále existuje ({$name}). Prahové hodnoty musí tvořit rostoucí řadu.','',''),
('entity_manager','err_scale_score_exceeds_next_threshold','Hodnota skóre ({$scr} %) u stupně „{$name}“ přesahuje prahovou hodnotu následujícího stupně ({$next} %).','',''),
('entity_manager','err_scale_score_not_monotonic','Hodnoty skóre musí tvořit rostoucí řadu: stupeň „{$name}“ ({$scr} %) musí mít vyšší skóre než předchozí stupeň „{$prev_name}“ ({$prev_scr} %).','',''),
('entity_manager','err_scale_score_under_threshold','Hodnota skóre ({$scr} %) nesmí být nižší než dolní práh intervalu stupně ({$thr} %).','',''),
('entity_manager','lbl_approval_note_input','Průvodní poznámka k návrhu / připomínka ke schválení:','',''),
('entity_manager','lbl_auto_code_hint','Automaticky odvozeno z názvu (můžete upravit)','',''),
('entity_manager','lbl_inherited_from_ancestor','Děděno z předka:','',''),
('entity_manager','lbl_record_removed_checkbox','Přesunout záznam do koše (zrušený záznam)','',''),
('entity_manager','msg_draft_Banner','Pracujete s vlastním rozpracovaným konceptem (stav D). Změny zatím nejsou viditelné pro ostatní uživatele.','',''),
('entity_manager','msg_forwarded_banner','Tento návrh byl předán ke schválení (stav F). Další úpravy uloží aktualizovanou verzi návrhu.','',''),
('entity_manager','msg_rejected_banner','Schvalovatel vrátil tento návrh k přepracování (stav R). Důvod vrácení:','',''),
('entity_manager','msg_remove_lang_mutation_only','Ruší pouze jazykovou mutaci ({$lang})','',''),
('entity_manager','opt_root_no_parent','--- Kořenová položka (bez nadřízeného uzlu) ---','',''),
('entity_manager','opt_select_empty','--- Vyberte ---','',''),
('entity_manager','ph_approval_note','Zadejte volitelnou poznámku pro schvalovatele...','',''),
('entity_manager','sec_other_attributes','Ostatní vlastnosti','',''),
/*#do# entity_manager */

/*#od# filter_manager */
('filter_manager','btn_apply_filter','Použít filtr','Aktivuje zadané filtrační podmínky a přefiltruje seznam','btn-success'),
('filter_manager','btn_clear_filter','Zrušit filtr','Vymaže všechny podmínky filtru a zobrazí kompletní seznam','btn-danger'),
('filter_manager','btn_close_filter','Zavřít','Zavře okno rozšířeného filtru bez uložení změn','btn-secondary'),
('filter_manager','btn_show_all_fields','Zobrazit vše (+{$count} dalších položek)','Rozbalí zbývající sloupce třídy v modálním okně filtru',''),
('filter_manager','err_date_range_order','Počáteční datum ({$min}) je větší než koncové ({$max}) u položky „{$label}“.','',''),
('filter_manager','err_invalid_date_expr','Neplatné datum „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_date_range','Neplatný datumový interval „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_number_expr','Neplatný číselný výraz „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_number_range','Neplatný číselný interval „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_number_range_order','Dolní mez intervalu ({$min}) je větší než horní mez ({$max}) u položky „{$label}“.','',''),
('filter_manager','help_bool','Vyberte Ano (1), Ne (0) nebo Vše.','',''),
('filter_manager','help_date','Zadejte datum (R-M-D nebo D.M.R), interval (od..do) nebo porovnání (>=, <=).','',''),
('filter_manager','help_number','Zadejte číslo, interval (10..50) nebo porovnání (>=10, <100, !=0).','',''),
('filter_manager','help_select','Vyberte konkrétní položku ze seznamu.','',''),
('filter_manager','help_text','Hledá výskyt textu (nerozlišuje velikost písmen). Podporuje hvězdičku (*) a čárkou oddělený seznam.','',''),
('filter_manager','lbl_modal_title','Rozšířený filtr záznamů','',''),
('filter_manager','opt_bool_all','--- Vše ---','',''),
('filter_manager','opt_bool_no','Ne (0)','',''),
('filter_manager','opt_bool_yes','Ano (1)','',''),
('filter_manager','opt_select_all','--- Vše ---','',''),
/*#do# filter_manager */

/*#od# global_phrase */
('global_phrase','cancel','Storno','',''),
('global_phrase','error','Chyba','',''),
('global_phrase','no','Ne','',''),
('global_phrase','ok','OK','',''),
('global_phrase','warning','Varování','',''),
('global_phrase','yes','Ano','',''),
/*#do# global_phrase */

/*#od# menu_manager */
('menu_manager','breadcrumb_home','Domů','',''),
/*#do# menu_manager */

/*#od# page_approval */
('page_approval','badge_action_delete','Návrh na zrušení (smazání)','',''),
('page_approval','badge_action_insert','Nový záznam','',''),
('page_approval','badge_action_translation','Překlad (L)','',''),
('page_approval','badge_action_update','Úprava záznamu','',''),
('page_approval','btn_approve','✓ Schválit a publikovat','Schválí vybraný návrh a promítne změnu do platných dat (stav A)','btn-success'),
('page_approval','btn_reject','↩ Vrátit k přepracování','Vrátí návrh autorovi s připomínkou (stav R)','btn-danger'),
('page_approval','err_reject_note_required','Při vrácení návrhu k přepracování musíte vyplnit důvod / připomínku pro autora.','',''),
('page_approval','hdr_comparison_table','Porovnání navržených změn oproti platnému stavu','',''),
('page_approval','header_detail_default','Posouzení návrhu změny','',''),
('page_approval','lbl_approval_note','Stanovisko schvalovatele / důvod vrácení:','',''),
('page_approval','lbl_author','Autor návrhu:','',''),
('page_approval','lbl_class','Třída (entita):','',''),
('page_approval','lbl_date_modified','Předáno dne:','',''),
('page_approval','lbl_filter_class','Filtrovat podle třídy:','',''),
('page_approval','lbl_language','Jazyk návrhu:','',''),
('page_approval','lbl_only_changed_rows','Zobrazit pouze změněné položky','',''),
('page_approval','master_heading','Návrhy čekající na schválení (stav F)','',''),
('page_approval','msg_approved_ok','Návrh byl úspěšně schválen a publikován.','',''),
('page_approval','msg_competing_warning','Upozornění: K tomuto záznamu existuje více souběžných návrhů od různých autorů. Schválením tohoto návrhu nahradíte aktuální platný stav; ostatní neuzavřené návrhy zůstanou autorům k dispozici.','',''),
('page_approval','msg_empty_queue','Momentálně nejsou ve frontě žádné návrhy čekající na schválení.','',''),
('page_approval','msg_rejected_ok','Návrh byl vrácen autorovi k přepracování.','',''),
('page_approval','msg_select_proposal','Vyberte návrh v levém seznamu pro zobrazení porovnání hodnot a rozhodnutí.','',''),
('page_approval','opt_all_classes','--- Všechny třídy ---','',''),
('page_approval','page_title','Schvalování změn - BCM Osiris','',''),
('page_approval','ph_approval_note','Zadejte komentář ke schválení nebo povinné zdůvodnění při vrácení návrhu...','',''),
('page_approval','th_author','Autor','',''),
('page_approval','th_caption','Záznam / Název','',''),
('page_approval','th_class','Třída','',''),
('page_approval','th_current_val','Platná hodnota (A)','',''),
('page_approval','th_date','Datum','',''),
('page_approval','th_field_name','Položka (Sloupec)','',''),
('page_approval','th_proposed_val','Navrhovaná hodnota (F)','',''),
('page_approval','tip_competing_proposals','K tomuto záznamu sešlo {$count} souběžných návrhů','',''),
('page_approval','txt_new_record_no_active','(Nový záznam – dosud neexistuje schválená verze)','',''),
/*#do# page_approval */

/*#od# page_asset */
('page_asset','btn_asset_cms','Opatření ({$count}) →','Přejde na přehled implementace protiopatření pro toto aktivum','btn-secondary'),
('page_asset','btn_asset_links','Vazby ({$count}) →','Přejde na přehled provozních a prostorových vazeb tohoto aktiva','btn-secondary'),
('page_asset','btn_asset_scenarios','Scénáře ({$count}) →','Přejde na hodnocení rizikových scénářů tohoto aktiva','btn-secondary'),
('page_asset','btn_new_asset','+ Nové aktivum','Založí nové aktivum v evidenci aktiv',''),
('page_asset','btn_new_space','+ Nový prostor / lokalita','Založí nový prostor, budovu nebo místnost',''),
('page_asset','grp_bia_risk_scores','Parametry dostupnosti (BIA) a agregované skóre rizik (0 až 100 %)','',''),
('page_asset','grp_identification','Klasifikace, archetyp a identifikace','',''),
('page_asset','grp_placement_relations','Zařazení ve stromu (parent_uuid)','',''),
('page_asset','grp_presentation','Prezentační texty, popis a poznámky','',''),
('page_asset','grp_validity_protection','Platnost, ikona a ochrana záznamu','',''),
('page_asset','header_edit_asset','Aktivum','',''),
('page_asset','header_edit_space','Prostor','',''),
('page_asset','header_new_asset','Nové aktivum','',''),
('page_asset','header_new_space','Nový prostor / lokalita','',''),
('page_asset','lbl_filter_archetype','Filtrovat podle archetypu:','',''),
('page_asset','master_heading','Strom a seznam aktiv','',''),
('page_asset','master_heading_space','Strom prostorů a lokalit','',''),
('page_asset','msg_no_building_warning','Upozornění: V organizaci zatím není definována žádná Budova (archetyp BUILDING). Založte prosím nejprve alespoň jednu budovu (i kdyby byla fiktivní), protože do budov se povinně umisťují místnosti a kabeláž a do místností fyzická aktiva, hostitelské počítače, dokumenty a média.','',''),
('page_asset','opt_all_assets','--- Všechny archetypy aktiv (mimo prostory) ---','',''),
('page_asset','opt_all_spaces','--- Všechny prostory a lokality ---','',''),
('page_asset','page_title','Evidence aktiv (CRMM)','',''),
('page_asset','page_title_space','Prostory a lokality (CRMM)','',''),
('page_asset','th_archetype','Archetyp','',''),
('page_asset','th_asset_caption','Aktivum / Služba','',''),
('page_asset','th_res_risk','Rez. riz.','',''),
('page_asset','th_space_caption','Prostor / Lokalita','',''),
/*#do# page_asset */

/*#od# page_asset_class */
('page_asset_class','btn_new_asset_class','+ Nová třída aktiv','Založí novou složku nebo koncovou třídu aktiv v katalogu',''),
('page_asset_class','grp_identification','Kód a zařazení ve stromu','',''),
('page_asset_class','grp_permissions_protection','Oprávnění, platnost a ochrana záznamu','',''),
('page_asset_class','grp_presentation','Prezentační texty a popis','',''),
('page_asset_class','header_edit_class','Třída aktiv','',''),
('page_asset_class','header_new_class','Nová třída aktiv','',''),
('page_asset_class','master_heading','Strom tříd aktiv','',''),
('page_asset_class','page_title','Třídy aktiv (Katalog CRMM)','',''),
('page_asset_class','th_class_caption','Třída aktiv','',''),
/*#do# page_asset_class */

/*#od# page_audit_login_session */
('page_audit_login_session','badge_session_expired','Expirováno','',''),
('page_audit_login_session','badge_user_inactive','Neaktivní účet','',''),
('page_audit_login_session','btn_apply_filter','Filtrovat','Vyhledá přihlašovací relace podle zadaných kritérií',''),
('page_audit_login_session','btn_reset_filter','Zrušit filtr','Vymaže filtr a zobrazí nejnovější relace','btn-secondary'),
('page_audit_login_session','heading_user_activity','Aktivita a přihlášení uživatelů','',''),
('page_audit_login_session','intro_user_activity','Přehled přihlášení a aktivity uživatelů z tabulky audit_login_session a navazujících údajů účtu (seřazeno sestupně podle času).','',''),
('page_audit_login_session','lbl_displayed_records','Zobrazeno záznamů: {$count}','',''),
('page_audit_login_session','lbl_filter_limit','Počet řádků:','',''),
('page_audit_login_session','lbl_filter_only_open','Pouze aktivní (neukončené) relace','',''),
('page_audit_login_session','lbl_filter_user','Jméno / login uživatele:','',''),
('page_audit_login_session','msg_no_records','Zadaným kritériím neodpovídají v tabulce audit_login_session žádné záznamy.','',''),
('page_audit_login_session','page_title','Aktivita uživatelů - BCM Osiris','',''),
('page_audit_login_session','ph_filter_user','Zadejte jméno, příjmení, login nebo e-mail...','',''),
('page_audit_login_session','th_assumed_role','Role','',''),
('page_audit_login_session','th_dept_job','Oddělení / Pozice','',''),
('page_audit_login_session','th_duration_min','Trvání','',''),
('page_audit_login_session','th_email','E-mail','',''),
('page_audit_login_session','th_ip_address','IP adresa','',''),
('page_audit_login_session','th_last_request_time','Poslední aktivita','',''),
('page_audit_login_session','th_login_name','Login','',''),
('page_audit_login_session','th_login_time','Čas přihlášení','',''),
('page_audit_login_session','th_logout_time','Odhlášení / Expirace','',''),
('page_audit_login_session','th_organization','Organizace','',''),
('page_audit_login_session','th_user_name','Jméno uživatele','',''),
('page_audit_login_session','txt_session_open','Neukončeno','',''),
('page_audit_login_session','unit_minutes','min','',''),
/*#do# page_audit_login_session */

/*#od# page_change_user_context */
('page_change_user_context','badge_current','Aktivní','',''),
('page_change_user_context','badge_disabled','Blokováno','',''),
('page_change_user_context','badge_pending','Čeká na schválení','',''),
('page_change_user_context','btn_apply_context','Přepnout kontext','Aktivuje vybranou organizaci a aplikační roli pro aktuální relaci','btn-success'),
('page_change_user_context','btn_cancel_request','Zrušit žádost','Stornuje vaši dosud neschválenou žádost o přístup','btn-danger'),
('page_change_user_context','btn_request_access','Požádat o přístup','Odešle administrátorovi vybrané organizace žádost o přiřazení přístupu',''),
('page_change_user_context','btn_save_working_date','Uložit pracovní datum','Nastaví zvolené pracovní datum pro vyhodnocování časové platnosti záznamů','btn-secondary'),
('page_change_user_context','hdr_available_orgs','Dostupné organizace a volba aplikační role','',''),
('page_change_user_context','hdr_request_access','Žádost o přístup do další organizace','',''),
('page_change_user_context','hdr_working_date','Osobní pracovní datum (časový řez platnosti dat)','',''),
('page_change_user_context','lbl_select_org_request','Vyberte organizaci:','',''),
('page_change_user_context','lbl_select_role','Zvolte roli pro přihlášení:','',''),
('page_change_user_context','lbl_working_date','Pracovní datum (prázdné = dnešní datum):','',''),
('page_change_user_context','msg_context_switched','Kontext organizace a role byl úspěšně změněn.','',''),
('page_change_user_context','msg_request_cancelled','Žádost o přístup byla zrušena.','',''),
('page_change_user_context','msg_request_sent','Žádost o přístup do organizace byla odeslána ke schválení.','',''),
('page_change_user_context','msg_working_date_saved','Pracovní datum bylo uloženo.','',''),
('page_change_user_context','page_title','Změna kontextu uživatele - BCM Osiris','',''),
('page_change_user_context','th_action','Akce','',''),
('page_change_user_context','th_licence_level','Licence','',''),
('page_change_user_context','th_organization','Organizace','',''),
('page_change_user_context','th_role','Dostupné role','',''),
('page_change_user_context','th_status','Stav','',''),
/*#do# page_change_user_context */

/*#od# page_countermeasure */
('page_countermeasure','btn_new_countermeasure','+ Nové protiopatření','Založí novou skupinu nebo koncové protiopatření v katalogu',''),
('page_countermeasure','grp_factors','Redukční a prahový rizikový faktor (0 až 100 %)','',''),
('page_countermeasure','grp_identification','Kód, zařazení ve stromu a ikona','',''),
('page_countermeasure','grp_permissions_protection','Oprávnění, platnost a ochrana záznamu','',''),
('page_countermeasure','grp_presentation','Prezentační texty a popis opatření','',''),
('page_countermeasure','header_edit_countermeasure','Protiopatření','',''),
('page_countermeasure','header_new_countermeasure','Nové protiopatření','',''),
('page_countermeasure','master_heading','Strom katalogu protiopatření','',''),
('page_countermeasure','page_title','Katalog protiopatření (CRMM)','',''),
('page_countermeasure','th_cm_caption','Protiopatření','',''),
('page_countermeasure','th_reduction_factor','Redukce (%)','',''),
('page_countermeasure','th_risk_factor','Práh (%)','',''),
/*#do# page_countermeasure */

/*#od# page_countermeasure_implementation */
('page_countermeasure_implementation','btn_back_to_asset','← Zpět na aktivum: {$asset}','Návrat na detail aktiva','btn-secondary'),
('page_countermeasure_implementation','btn_new_cm_impl','+ Nová implementace opatření','Založí nový záznam implementace protiopatření',''),
('page_countermeasure_implementation','grp_asset_cm_state','Chráněné aktivum, aplikované protiopatření a stav zavedení','',''),
('page_countermeasure_implementation','grp_presentation','Popis realizace opatření a poznámky z kontroly','',''),
('page_countermeasure_implementation','grp_responsibility_factors','Odpovědnost, termíny a vypočtené efektivní faktory (0 až 100 %)','',''),
('page_countermeasure_implementation','grp_validity','Platnost záznamu','',''),
('page_countermeasure_implementation','header_edit_cm_impl','Implementace opatření','',''),
('page_countermeasure_implementation','header_new_cm_impl','Nová implementace protiopatření','',''),
('page_countermeasure_implementation','lbl_filter_asset','Chráněné aktivum / prostor:','',''),
('page_countermeasure_implementation','lbl_summary_eff_reduction','Efektivní redukce rizika scénářů:','',''),
('page_countermeasure_implementation','lbl_summary_eff_risk','Efektivní spodní práh rizika (při neimplementaci):','',''),
('page_countermeasure_implementation','opt_all_assets','--- Všechna aktiva a prostory ---','',''),
('page_countermeasure_implementation','page_title','Implementace protiopatření (CRMM)','',''),
('page_countermeasure_implementation','th_eff_reduction','Ef. redukce (%)','',''),
('page_countermeasure_implementation','th_eff_risk','Ef. práh rizika (%)','',''),
('page_countermeasure_implementation','th_impl_caption','Popis implementace / Opatření','',''),
('page_countermeasure_implementation','th_target_date','Termín','',''),
/*#do# page_countermeasure_implementation */

/*#od# page_countermeasure_state */
('page_countermeasure_state','btn_new_cm_state','+ Nový stav protiopatření','Založí nový stav implementace protiopatření',''),
('page_countermeasure_state','grp_factors','Váhy redukčního a rizikového faktoru (0 až 100 %)','',''),
('page_countermeasure_state','grp_identification','Kód, pořadí a vizuální označení','',''),
('page_countermeasure_state','grp_presentation','Název a popis stavu','',''),
('page_countermeasure_state','grp_protection','Platnost a ochrana záznamu','',''),
('page_countermeasure_state','header_edit_cm_state','Stav protiopatření','',''),
('page_countermeasure_state','header_new_cm_state','Nový stav protiopatření','',''),
('page_countermeasure_state','page_title','Stavy protiopatření (CRMM)','',''),
('page_countermeasure_state','th_builtin_code','Kód','',''),
('page_countermeasure_state','th_caption','Stav protiopatření','',''),
('page_countermeasure_state','th_reduction_factor','Redukce (%)','',''),
('page_countermeasure_state','th_risk_factor','Riziko (%)','',''),
('page_countermeasure_state','th_sort_code','Pořadí','',''),
/*#do# page_countermeasure_state */

/*#od# page_csv_package */
('page_csv_package','btn_clear_staging','Vyčistit načtený soubor (Staging)','Odstraní dočasně načtená data 1. fáze z databáze','btn-danger'),
('page_csv_package','btn_upload_phase1','Načíst a zkontrolovat soubor (Fáze 1)','Nahraje CSV soubor do staging tabulek a ověří jeho strukturu a podpis',''),
('page_csv_package','err_no_file_uploaded','Nebyl vybrán žádný soubor k nahrání.','',''),
('page_csv_package','hdr_export_section','Export datového balíčku do souboru CSV','',''),
('page_csv_package','hdr_import_section','Import datového balíčku ze souboru CSV (Dvoufázový)','',''),
('page_csv_package','lbl_select_csv_file','Vyberte CSV soubor balíčku:','',''),
('page_csv_package','lbl_select_package_type','Typ datového balíčku:','',''),
('page_csv_package','master_heading','Typy CSV balíčků','',''),
('page_csv_package','msg_staging_cleared','Dočasná staging data importu byla vyčištěna.','',''),
('page_csv_package','page_title','Přenos datových balíčků (CSV) - BCM Osiris','',''),
/*#do# page_csv_package */

/*#od# page_excel_reader */
('page_excel_reader','btn_distribute','Distribuovat do systémových metadat','Spustí uloženou proceduru pro rozpad importovaných listů do tabulek meta_*','btn-success'),
('page_excel_reader','btn_upload','Nahrát a importovat do DB','Nahraje vybraný sešit XLSX a uloží jeho listy do databázových tabulek _excel_*',''),
('page_excel_reader','chk_drop_tables','Smazat existující tabulky _excel_* před importem','',''),
('page_excel_reader','err_upload_failed','Chyba při nahrávání souboru.','',''),
('page_excel_reader','heading_main','Import a kontrola dat z Excelu (XLSX)','',''),
('page_excel_reader','lbl_select_file','Vyberte soubor Excel (.xlsx):','',''),
('page_excel_reader','lbl_sheets_overview','Přehled listů v databázi:','',''),
('page_excel_reader','msg_distribute_done','Distribuce dat do systémových tabulek byla dokončena.','',''),
('page_excel_reader','msg_import_done','Import sešitu do tabulek _excel_* byl úspěšně dokončen.','',''),
('page_excel_reader','msg_rows_truncated','... Zobrazeno pouze prvních {$max} z celkových {$total} řádků ...','',''),
('page_excel_reader','page_title','Import dat z Excelu - BCM Osiris','',''),
/*#do# page_excel_reader */

/*#od# page_hierarchy */
('page_hierarchy','btn_manage_hierarchy_items','Spravovat položky ({$count}) →','Přejde do správy uzlů a položek této sekundární hierarchie','btn-secondary'),
('page_hierarchy','btn_new_hierarchy','+ Nová sekundární hierarchie','Založí novou složku nebo definici sekundární hierarchie / sady štítků',''),
('page_hierarchy','grp_identification','Kód, zařazení v registru a ikona','',''),
('page_hierarchy','grp_presentation','Prezentační texty a popis hierarchie','',''),
('page_hierarchy','grp_rules_protection','Pravidla přiřazování, oprávnění a ochrana','',''),
('page_hierarchy','header_edit_hierarchy','Sekundární hierarchie','',''),
('page_hierarchy','header_new_hierarchy','Nová sekundární hierarchie / sada štítků','',''),
('page_hierarchy','master_heading','Registr sekundárních hierarchií a štítků','',''),
('page_hierarchy','msg_folder_no_items_notice','Tento záznam je organizační složkou v registru hierarchií (is_leaf = 0). Položky hodnot se vkládají pouze do koncových hierarchií (zaškrtnutá volba Samostatná hierarchie).','',''),
('page_hierarchy','page_title','Sekundární hierarchie a štítky (CRMM)','',''),
('page_hierarchy','th_hierarchy_caption','Sekundární hierarchie / Sada štítků','',''),
/*#do# page_hierarchy */

/*#od# page_hierarchy_item */
('page_hierarchy_item','btn_back_to_hierarchy','← Zpět na hierarchii: {$parent}','Návrat do registru sekundárních hierarchií','btn-secondary'),
('page_hierarchy_item','btn_new_hierarchy_item','+ Nová položka hierarchie','Založí nový uzel nebo koncovou položku ve vybrané hierarchii',''),
('page_hierarchy_item','grp_identification','Nadřazená hierarchie, kód a zařazení ve stromu','',''),
('page_hierarchy_item','grp_presentation','Prezentační texty, barva a ikona','',''),
('page_hierarchy_item','grp_protection','Oprávnění, platnost a ochrana záznamu','',''),
('page_hierarchy_item','header_edit_item','Položka hierarchie','',''),
('page_hierarchy_item','header_new_item','Nová položka sekundární hierarchie','',''),
('page_hierarchy_item','lbl_select_hierarchy','Zvolte sekundární hierarchii / sadu štítků:','',''),
('page_hierarchy_item','master_heading','Strom položek hierarchie','',''),
('page_hierarchy_item','msg_no_leaf_hierarchy_defined','V registru sekundárních hierarchií zatím není definována žádná koncová hierarchie (is_leaf = 1). Založte ji nejprve na stránce Sekundární hierarchie a štítky.','',''),
('page_hierarchy_item','page_title','Položky sekundárních hierarchií (CRMM)','',''),
('page_hierarchy_item','page_title_with_hier','Položky hierarchie: {$hierarchy}','',''),
('page_hierarchy_item','th_item_caption','Položka hierarchie / Štítek','',''),
/*#do# page_hierarchy_item */

/*#od# page_impact */
('page_impact','btn_new_impact','+ Nový dopad','Založí novou oblast nebo položku dopadu v katalogu',''),
('page_impact','grp_identification','Kód, zařazení ve stromu a ikona','',''),
('page_impact','grp_permissions_protection','Oprávnění, platnost a ochrana záznamu','',''),
('page_impact','grp_presentation','Prezentační texty a popis dopadu','',''),
('page_impact','header_edit_impact','Dopad','',''),
('page_impact','header_new_impact','Nový dopad','',''),
('page_impact','master_heading','Strom katalogu dopadů','',''),
('page_impact','page_title','Katalog dopadů (CRMM)','',''),
('page_impact','th_impact_caption','Druh / Oblast dopadu','',''),
/*#do# page_impact */

/*#od# page_link */
('page_link','badge_derived','Zděděno','',''),
('page_link','btn_back_to_asset','← Zpět na aktivum: {$asset}','Návrat na detail filtrovaného aktiva','btn-secondary'),
('page_link','btn_back_to_diagram','← Zpět na schéma sítě: {$diagram}','Návrat na detail schématu heterogenní sítě','btn-secondary'),
('page_link','btn_new_link','+ Nová vazba objektů','Založí novou vazbu mezi objekty',''),
('page_link','grp_link_endpoints','Typ vazby, zdrojový a cílový objekt','',''),
('page_link','grp_weight_note','Váha přenosu rizika, původ, poznámka a platnost','',''),
('page_link','header_edit_link','Detail vazby mezi objekty','',''),
('page_link','header_new_link','Nová vazba mezi objekty','',''),
('page_link','lbl_filter_link_def','Typ vazby (link_def):','',''),
('page_link','lbl_show_removed','Zobrazit i zrušené','',''),
('page_link','master_heading','Seznam vazeb a závislostí','',''),
('page_link','msg_derived_link_readonly','Tato vazba vznikla automatickým děděním po hierarchii, ze sloupce parent_uuid nebo projekcí ze schématu sítě (is_derived = 1). Zděděnou vazbu nelze ručně přepisovat; upravte ji na zdrojovém záznamu nebo diagramu.','',''),
('page_link','opt_all_link_defs','--- Všechny typy vazeb ---','',''),
('page_link','opt_select_default','--- Vyberte ---','',''),
('page_link','page_title','Vazby a závislosti aktiv (CRMM)','',''),
('page_link','placeholder_search','Hledat ve vazbách...','',''),
('page_link','th_from_object','Zdroj (Odkud)','',''),
('page_link','th_link_def','Typ vazby','',''),
('page_link','th_to_object','Cíl (Kam)','',''),
/*#do# page_link */

/*#od# page_link_diagram */
('page_link_diagram','badge_cycle_error','Zacyklení tříd!','',''),
('page_link_diagram','badge_self_loop','Vnitrotřídní průchod (self-referencing)','',''),
('page_link_diagram','badge_top_class','Vrcholová třída','',''),
('page_link_diagram','btn_diagram_derived_defs','Odvozené vztahy ({$count}) →','Přejde na přehled nepřímých vztahů vygenerovaných z tohoto diagramu','btn-secondary'),
('page_link_diagram','btn_diagram_edges','Spojnice a vazby sítě ({$edges} / {$links}) →','Přejde na správu spojnic diagramu a přehled vygenerovaných nepřímých vazeb','btn-secondary'),
('page_link_diagram','btn_new_diagram','+ Nové schéma sítě (diagram)','Založí nové schéma heterogenní sítě vztahů',''),
('page_link_diagram','btn_rebuild_diagram','↻ Přepočítat a promítnout síť','Vyhodnotí topologii diagramu a vygeneruje odvozené nepřímé vztahy do meta_link_def a vazby do link',''),
('page_link_diagram','grp_identification','Identifikace, řazení, vzhled a platnost','',''),
('page_link_diagram','grp_presentation','Prezentační texty a popis schématu sítě','',''),
('page_link_diagram','hdr_diagram_class_topology','Topologie tříd v heterogenní síti (vrcholové třídy → podřízené třídy):','',''),
('page_link_diagram','header_edit_diagram','Schéma sítě','',''),
('page_link_diagram','header_new_diagram','Nové schéma sítě vztahů','',''),
('page_link_diagram','msg_diagram_no_edges','V tomto schématu sítě zatím nejsou zařazeny žádné orientované vztahy. Klikněte na „Spojnice a vazby sítě“ v záhlaví detailu a přidejte vztahy pomocí „diagram_includes_link_def“.','',''),
('page_link_diagram','msg_new_diagram_hint','Tip: Po uložení schématu sítě k němu tlačítkem „Spojnice a vazby sítě“ přiřaďte orientované vztahy (vztah diagram_includes_link_def) a stiskněte „Přepočítat a promítnout síť“.','',''),
('page_link_diagram','page_title','Schémata sítí vztahů (Diagramy CRMM)','',''),
('page_link_diagram','th_builtin_code','Kód','',''),
('page_link_diagram','th_diagram_caption','Název schématu sítě','',''),
('page_link_diagram','th_sort_code','Pořadí','',''),
/*#do# page_link_diagram */

/*#od# page_main */
('page_main','empty_menu','Pro vaši roli nejsou v této složce dostupné žádné položky.','',''),
('page_main','heading_dashboard','Hlavní rozcestník aplikace','',''),
('page_main','page_title','Hlavní panel - BCM Osiris','',''),
/*#do# page_main */

/*#od# page_meta_class */
('page_meta_class','btn_manage_columns','Spravovat sloupce ({$count}) →','Přejde do správy sloupců vybrané logické třídy','btn-secondary'),
('page_meta_class','grp_identification','Technická identifikace a úložiště','',''),
('page_meta_class','grp_presentation','Prezentační texty a překlady','',''),
('page_meta_class','grp_settings','Nastavení koše, oprávnění a ochrany','',''),
('page_meta_class','header_detail','Logická třída','',''),
('page_meta_class','page_title','Logické třídy (Objekty) - BCM Osiris','',''),
/*#do# page_meta_class */

/*#od# page_meta_column */
('page_meta_column','btn_back_to_class','← Zpět na třídu: {$parent}','Návrat do detailu nadřízené logické třídy','btn-secondary'),
('page_meta_column','grp_behavior','Chování, překlad, historie a ochrana','',''),
('page_meta_column','grp_form_ui','Formulářový prvek a zobrazení v seznamu','',''),
('page_meta_column','grp_identification','Technická identifikace a dědičnost','',''),
('page_meta_column','grp_presentation','Popisky, záhlaví a nápověda','',''),
('page_meta_column','grp_relations','Vazby na číselníky a logické třídy','',''),
('page_meta_column','header_detail','Sloupec metadat','',''),
('page_meta_column','lbl_select_class','Zvolte logickou třídu (objekt):','',''),
('page_meta_column','page_title','Sloupce metadat - BCM Osiris','',''),
('page_meta_column','page_title_class','Sloupce: {$class}','',''),
/*#do# page_meta_column */

/*#od# page_meta_link_def */
('page_meta_link_def','btn_new_link_def','+ Nový typ vazby','Založí novou definici typu vztahu v meta_link_def',''),
('page_meta_link_def','grp_identification','Kód vazby, směr a propojované logické třídy','',''),
('page_meta_link_def','grp_presentation','Prezentační názvy vazby (tam / zpět) a nápověda','',''),
('page_meta_link_def','grp_rules_protection','Pravidla navazování, váha, původ a ochrana','',''),
('page_meta_link_def','header_edit_link_def','Typ vazby','',''),
('page_meta_link_def','header_new_link_def','Nová definice typu vazby','',''),
('page_meta_link_def','msg_derived_link_def_readonly','Tento nepřímý vztah byl automaticky vygenerován ze schématu heterogenní sítě (is_derived = 1). Upravuje se přepočtem příslušného diagramu sítě.','',''),
('page_meta_link_def','page_title','Definice typů vazeb (CRMM)','',''),
('page_meta_link_def','th_caption_forward','Název vazby (tam)','',''),
('page_meta_link_def','th_direction_type','Směr','',''),
('page_meta_link_def','th_link_code','Kód vazby','',''),
/*#do# page_meta_link_def */

/*#od# page_meta_menu */
('page_meta_menu','btn_new_menu_item','+ Nová položka menu','Založí novou složku nebo odkaz v navigačním menu',''),
('page_meta_menu','grp_identification','Kód, nadřízená složka a pořadí ve stromu','',''),
('page_meta_menu','grp_navigation','Cílová stránka, parametry URL a oprávnění','',''),
('page_meta_menu','grp_presentation','Název, nápověda a vektorová ikona','',''),
('page_meta_menu','grp_protection','Platnost a ochrana záznamu','',''),
('page_meta_menu','header_edit_menu','Položka menu','',''),
('page_meta_menu','header_new_menu','Nová položka menu','',''),
('page_meta_menu','master_heading','Strom navigačního menu','',''),
('page_meta_menu','page_title','Položky menu (Navigace) - BCM Osiris','',''),
('page_meta_menu','th_menu_caption','Položka menu','',''),
/*#do# page_meta_menu */

/*#od# page_meta_phrase */
('page_meta_phrase','btn_new_phrase','+ Nová textová fráze','Založí novou lokalizovatelnou textovou frázi nebo tlačítko',''),
('page_meta_phrase','grp_ai_protection','Kontext pro překlad (AI) a ochrana','',''),
('page_meta_phrase','grp_identification','Zdrojová třída a unikátní kód fráze','',''),
('page_meta_phrase','grp_presentation','Text fráze, tooltip a vzhled tlačítka','',''),
('page_meta_phrase','header_edit_phrase','Textová fráze','',''),
('page_meta_phrase','header_new_phrase','Nová textová fráze','',''),
('page_meta_phrase','lbl_filter_source','Filtrovat podle zdroje (source_code):','',''),
('page_meta_phrase','opt_all_sources','--- Všechny zdroje (stránky a třídy) ---','',''),
('page_meta_phrase','page_title','Textové fráze a překlady - BCM Osiris','',''),
/*#do# page_meta_phrase */

/*#od# page_org_users */
('page_org_users','badge_admin','Admin org.','',''),
('page_org_users','badge_inactive','Neaktivní','',''),
('page_org_users','badge_pending','Žádost o přístup','',''),
('page_org_users','badge_translator','Překladatel','',''),
('page_org_users','btn_new_user','+ Přidat / přiřadit uživatele','Založí nového uživatele nebo přiřadí existující účet do této organizace',''),
('page_org_users','err_email_required','E-mailová adresa uživatele je povinná.','',''),
('page_org_users','err_login_exists','Zadané přihlašovací jméno již v systému existuje u jiného účtu.','',''),
('page_org_users','err_login_required','Přihlašovací jméno (login) je povinné.','',''),
('page_org_users','err_password_too_short','Nové heslo musí mít alespoň 8 znaků.','',''),
('page_org_users','grp_access_permissions','Oprávnění a zařazení v této organizaci','',''),
('page_org_users','grp_account_identity','Přihlašovací účet a osobní údaje','',''),
('page_org_users','grp_password_security','Nastavení hesla a zabezpečení účtu','',''),
('page_org_users','header_edit_user','Uživatel organizace','',''),
('page_org_users','header_new_user','Nový uživatel organizace','',''),
('page_org_users','lbl_new_password','Nové heslo (vyplňte pouze při změně):','',''),
('page_org_users','master_heading','Uživatelé a přístupy v organizaci','',''),
('page_org_users','msg_user_saved','Údaje uživatele a přístupu do organizace byly uloženy.','',''),
('page_org_users','page_title','Uživatelé organizace - BCM Osiris','',''),
('page_org_users','th_dept_job','Oddělení / Pozice','',''),
('page_org_users','th_login','Login','',''),
('page_org_users','th_name','Jméno a příjmení','',''),
('page_org_users','th_roles','Role a práva','',''),
/*#do# page_org_users */

/*#od# page_organization */
('page_organization','btn_delete_logo','Odstranit logo','Vymaže uložené grafické logo organizace','btn-danger'),
('page_organization','grp_address_contact','Adresa sídla, identifikace a fakturace','',''),
('page_organization','grp_crmm_limits','Metodické parametry a horní limity skóre CRMM','',''),
('page_organization','grp_general','Název, zkratka, SSO doména a popis organizace','',''),
('page_organization','grp_logo','Grafické logo organizace','',''),
('page_organization','grp_regional_formats','Regionální formáty, měna a oddělovače','',''),
('page_organization','header_edit_org','Nastavení organizace','',''),
('page_organization','lbl_current_logo','Aktuální logo:','',''),
('page_organization','lbl_upload_logo','Nahrát nové logo (PNG, SVG, JPG, max. 512 KB):','',''),
('page_organization','msg_logo_deleted','Logo organizace bylo odstraněno.','',''),
('page_organization','msg_logo_too_large','Soubor loga překračuje povolenou velikost 512 KB.','',''),
('page_organization','msg_logo_uploaded','Logo organizace bylo úspěšně aktualizováno.','',''),
('page_organization','page_title','Správa a nastavení organizace - BCM Osiris','',''),
/*#do# page_organization */

/*#od# page_organization_licence */
('page_organization_licence','btn_new_licence','+ Nová licence organizace','Založí nový licenční záznam pro vytvoření a aktivaci organizace',''),
('page_organization_licence','grp_admin_account','Výchozí administrátor zakládané organizace','',''),
('page_organization_licence','grp_licence_params','Parametry licence, úroveň a stav aktivace','',''),
('page_organization_licence','grp_notes_validity','Poznámky a časová platnost licence','',''),
('page_organization_licence','header_edit_licence','Licence organizace','',''),
('page_organization_licence','header_new_licence','Nová licence organizace','',''),
('page_organization_licence','msg_activation_hint','Při uložení se stavem APPROVED (Schváleno k aktivaci) systém automaticky založí cílovou organizaci, výchozího administrátora a odešle aktivační e-mail.','',''),
('page_organization_licence','page_title','Správa licencí organizací - BCM Osiris','',''),
/*#do# page_organization_licence */

/*#od# page_scale */
('page_scale','btn_manage_scale_values','Spravovat stupně škály ({$count}) →','Přejde do správy jednotlivých stupňů, prahů a skóre této škály','btn-secondary'),
('page_scale','btn_new_scale','+ Nová hodnotící škála','Založí novou hodnotící škálu a automaticky vygeneruje výchozí stupně',''),
('page_scale','grp_identification','Kód, druh veličiny, priorita a výchozí počet stupňů','',''),
('page_scale','grp_presentation','Název a metodický popis škály','',''),
('page_scale','grp_protection','Platnost a ochrana záznamu','',''),
('page_scale','header_edit_scale','Hodnotící škála','',''),
('page_scale','header_new_scale','Nová hodnotící škála','',''),
('page_scale','lbl_filter_scale_type','Filtrovat podle druhu škály:','',''),
('page_scale','msg_initial_levels_hint','Při prvním uložení nové škály systém automaticky vygeneruje zadaný počet stupňů (initial_levels) rovnoměrně rozložených v intervalu 0 až 100 %.','',''),
('page_scale','opt_all_scale_types','--- Všechny druhy škál ---','',''),
('page_scale','page_title','Hodnotící škály (CRMM)','',''),
('page_scale','th_builtin_code','Kód','',''),
('page_scale','th_caption','Název škály','',''),
('page_scale','th_priority','Priorita','',''),
('page_scale','th_scale_type','Druh','',''),
/*#do# page_scale */

/*#od# page_scale_value */
('page_scale_value','btn_back_to_scale','← Zpět na škálu: {$parent}','Návrat do detailu nadřazené hodnotící škály','btn-secondary'),
('page_scale_value','btn_new_scale_value','+ Nový stupeň škály','Přidá nový stupeň do vybrané hodnotící škály',''),
('page_scale_value','grp_identification','Nadřazená škála a unikátní kód stupně','',''),
('page_scale_value','grp_presentation','Název, zkratka, barva a popis stupně','',''),
('page_scale_value','grp_protection','Platnost a ochrana záznamu','',''),
('page_scale_value','grp_thresholds','Dolní práh intervalu a výpočtové skóre (0 až 100 %)','',''),
('page_scale_value','header_edit_level','Stupeň hodnotící škály','',''),
('page_scale_value','header_new_level','Nový stupeň hodnotící škály','',''),
('page_scale_value','lbl_interval_preview','Platný interval stupně:','',''),
('page_scale_value','lbl_select_scale','Zvolte hodnotící škálu:','',''),
('page_scale_value','master_heading','Stupně škály (seřazeno podle prahu)','',''),
('page_scale_value','msg_no_scale_defined','V systému zatím není definována žádná hodnotící škála. Založte ji nejprve na stránce Hodnotící škály.','',''),
('page_scale_value','page_title','Stupně hodnotících škál (CRMM)','',''),
('page_scale_value','page_title_with_scale','Stupně škály: {$scale}','',''),
('page_scale_value','th_level_caption','Stupeň škály','',''),
('page_scale_value','th_score_value','Skóre (%)','',''),
('page_scale_value','th_threshold_value','Od prahu (%)','',''),
/*#do# page_scale_value */

/*#od# page_scenario */
('page_scenario','btn_new_scenario','+ Nový rizikový scénář','Založí novou skupinu nebo koncový rizikový scénář v katalogu',''),
('page_scenario','grp_identification','Kód, zařazení ve stromu a ikona','',''),
('page_scenario','grp_permissions_protection','Oprávnění, platnost a ochrana záznamu','',''),
('page_scenario','grp_presentation','Prezentační texty a popis scénáře','',''),
('page_scenario','grp_relations_risk','Působící hrozba, cílová třída aktiv a mez reziduálního rizika','',''),
('page_scenario','header_edit_scenario','Rizikový scénář','',''),
('page_scenario','header_new_scenario','Nový rizikový scénář','',''),
('page_scenario','master_heading','Strom rizikových scénářů','',''),
('page_scenario','page_title','Rizikové scénáře (Katalog CRMM)','',''),
('page_scenario','th_min_res_risk','Min. rez.','',''),
('page_scenario','th_scenario_caption','Rizikový scénář','',''),
/*#do# page_scenario */

/*#od# page_scenario_assessment */
('page_scenario_assessment','btn_back_to_asset','← Zpět na aktivum: {$asset}','Návrat na detail filtrovaného aktiva','btn-secondary'),
('page_scenario_assessment','btn_new_assessment','+ Nové hodnocení scénáře','Založí nové hodnocení rizikového scénáře nad aktivem',''),
('page_scenario_assessment','btn_recalculate_crmm','↻ Přepočítat rizika','Spustí přepočet efektivních faktorů opatření, scénářů a agregovaných rizik aktiv','btn-secondary'),
('page_scenario_assessment','grp_asset_scenario','Hodnocené aktivum a rizikový scénář','',''),
('page_scenario_assessment','grp_calculated_risk','Vypočtené inherentní riziko, redukce a zbytkové riziko (0 až 100 %)','',''),
('page_scenario_assessment','grp_input_scores','Vstupní hodnocení hrozby, zranitelnosti a dopadu (0 až 100 %)','',''),
('page_scenario_assessment','grp_justification_audit','Zdůvodnění hodnocení, poznámka a odpovědná osoba','',''),
('page_scenario_assessment','header_edit_assessment','Hodnocení scénáře','',''),
('page_scenario_assessment','header_new_assessment','Nové hodnocení rizikového scénáře','',''),
('page_scenario_assessment','lbl_filter_asset','Hodnocené aktivum:','',''),
('page_scenario_assessment','lbl_sum_floor','Min. práh:','',''),
('page_scenario_assessment','lbl_sum_inherent','Inherentní riziko:','',''),
('page_scenario_assessment','lbl_sum_reduction','Redukce opatřeními:','',''),
('page_scenario_assessment','lbl_sum_residual','Zbytkové (reziduální) riziko:','',''),
('page_scenario_assessment','opt_all_assets','--- Všechna hodnocená aktiva ---','',''),
('page_scenario_assessment','page_title','Hodnocení rizikových scénářů (CRMM)','',''),
('page_scenario_assessment','th_assess_caption','Hodnocený scénář / Popis','',''),
('page_scenario_assessment','th_assess_date','Datum','',''),
('page_scenario_assessment','th_inherent_risk','Inh. riziko (%)','',''),
('page_scenario_assessment','th_residual_risk','Rez. riziko (%)','',''),
/*#do# page_scenario_assessment */

/*#od# page_service_logbook */
('page_service_logbook','btn_apply_filter','Filtrovat','Vyhledá záznamy v provozním deníku podle zadaných kritérií',''),
('page_service_logbook','btn_reset_filter','Zrušit filtr','Vymaže filtr a zobrazí nejnovější záznamy provozního deníku','btn-secondary'),
('page_service_logbook','heading_logbook','Provozní deník databáze (service_logbook)','',''),
('page_service_logbook','intro_logbook','Chronologická evidence spuštěných změnových skriptů (changes_YYYY.sql), importů metadat a servisních operací (seřazeno sestupně od nejnovějších).','',''),
('page_service_logbook','lbl_displayed_records','Zobrazeno záznamů: {$count}','',''),
('page_service_logbook','lbl_filter_limit','Počet řádků:','',''),
('page_service_logbook','lbl_filter_name','Název skriptu / operace:','',''),
('page_service_logbook','lbl_filter_text','Hledat v popisu / verzi:','',''),
('page_service_logbook','msg_no_records','Zadaným kritériím neodpovídají v tabulce service_logbook žádné záznamy.','',''),
('page_service_logbook','opt_all_scripts','--- Všechny skripty a operace ---','',''),
('page_service_logbook','page_title','Provozní deník (service_logbook) - BCM Osiris','',''),
('page_service_logbook','ph_filter_text','Zadejte hledaný text nebo číslo verze...','',''),
('page_service_logbook','th_content','Obsah / Popis provedené změny','',''),
('page_service_logbook','th_date','Datum a čas','',''),
('page_service_logbook','th_id','ID','',''),
('page_service_logbook','th_name','Skript / Operace','',''),
('page_service_logbook','th_original_login','SQL Login','',''),
('page_service_logbook','th_servername','Server','',''),
('page_service_logbook','th_version','Verze','',''),
/*#do# page_service_logbook */

/*#od# page_threat */
('page_threat','btn_new_threat','+ Nová hrozba','Založí novou skupinu nebo koncovou hrozbu v katalogu',''),
('page_threat','grp_evaluation','Výchozí hodnocení hrozby','',''),
('page_threat','grp_identification','Kód, zařazení ve stromu a ikona','',''),
('page_threat','grp_permissions_protection','Oprávnění, platnost a ochrana záznamu','',''),
('page_threat','grp_presentation','Prezentační texty a popis hrozby','',''),
('page_threat','header_edit_threat','Hrozba','',''),
('page_threat','header_new_threat','Nová hrozba','',''),
('page_threat','master_heading','Strom katalogu hrozeb','',''),
('page_threat','page_title','Katalog hrozeb (CRMM)','',''),
('page_threat','th_default_score','Výchozí skóre','',''),
('page_threat','th_threat_caption','Hrozba','',''),
/*#do# page_threat */

/*#od# page_xlsx_export_meta */
('page_xlsx_export_meta','btn_download_xlsx','Vygenerovat a stáhnout XLSX','Sestaví sešit Excel se systémovými metadaty a odešle jej ke stažení','btn-success'),
('page_xlsx_export_meta','heading_export','Export systémových metadat do Excelu (XLSX)','',''),
('page_xlsx_export_meta','intro_export','Tento nástroj vygeneruje vícezáložkový sešit XLSX obsahující aktuální stav systémových metadat (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def).','',''),
('page_xlsx_export_meta','lbl_filter_only_custom','Exportovat pouze záznamy upravené v rozhraní (who_modified <> 0x00)','',''),
('page_xlsx_export_meta','page_title','Export metadat do Excelu - BCM Osiris','',''),
/*#do# page_xlsx_export_meta */

/*#od# rich_text */
('rich_text','btn_apply_text','Převzít do detailu','Přenese upravený text z modálního editoru do formuláře (pro trvalé uložení do DB poté klikněte na Uložit změny)','btn-success'),
('rich_text','btn_cancel_text','Zrušit','Zavře modální editor bez přenesení změn do formuláře','btn-secondary'),
('rich_text','btn_edit_text','Upravit text','Otevře modální WYSIWYG / Markdown editor na popředí',''),
('rich_text','confirm_convert_format','Převést stávající text do nově zvoleného formátu?','',''),
('rich_text','lbl_format_select','Formát uložení:','',''),
('rich_text','lbl_modal_title','Úprava formátovaného textu:','',''),
('rich_text','msg_modal_hint','Pro trvalé uložení do databáze nezapomeňte po převzetí textu uložit celý formulář.','',''),
('rich_text','opt_format_html','Čisté HTML','',''),
('rich_text','opt_format_markdown','Markdown (preferováno)','',''),
('rich_text','tip_convert_format','Převede stávající text mezi formáty Markdown a HTML a přepne režim editoru','',''),
('rich_text','tip_open_editor','Otevřít editor formátovaného textu na popředí','',''),
('rich_text','txt_empty_prev','(Prázdné – klikněte na Upravit text)','',''),
('rich_text','txt_empty_preview','(Prázdné – klikněte na Upravit)','',''),
/*#do# rich_text */

/*#od# svg_icon_editor */
('svg_icon_editor','btn_apply_svg','Převzít do detailu','Přenese zkontrolovanou SVG ikonu do náhledu ve formuláři','btn-success'),
('svg_icon_editor','btn_cancel_svg','Zrušit','Zavře editor SVG ikony bez uplatnění změn','btn-secondary'),
('svg_icon_editor','btn_clear_svg','Vymazat','Odstraní SVG ikonu z pole','btn-danger'),
('svg_icon_editor','btn_edit_svg','Upravit ikonu','Otevře modální editor vektorové SVG ikony',''),
('svg_icon_editor','btn_validate_svg','Zkontrolovat syntaxi a vyčistit','Ověří XML syntaxi a odstraní případné nepovolené značky',''),
('svg_icon_editor','err_js_not_svg_root','Kód musí obsahovat kořenový element <svg>...</svg>.','',''),
('svg_icon_editor','err_js_xml_invalid','Neplatná XML syntaxe: ','',''),
('svg_icon_editor','err_svg_not_root','Kořenovým elementem ikony musí být značka <svg>.','',''),
('svg_icon_editor','err_svg_xml_syntax','Chyba syntaxe SVG ikony: {$detail}','',''),
('svg_icon_editor','lbl_live_preview','Živý náhled a kontrola syntaxe:','',''),
('svg_icon_editor','lbl_modal_title','Editor vektorové ikony (SVG):','',''),
('svg_icon_editor','lbl_no_svg_icon','Ikona není nastavena (dvojklikem upravíte)','',''),
('svg_icon_editor','lbl_svg_code_input','Zdrojový kód SVG ikony (vložte <svg ...>...</svg>):','',''),
('svg_icon_editor','lbl_svg_sources','Získat SVG kód ikony:','',''),
('svg_icon_editor','msg_modal_hint','Tip: Ikony s fill="currentColor" nebo bez atributu fill automaticky přebírají barvu textu v menu a tlačítkách. Vlastní barvy (např. fill="#...") zůstávají všude zachovány.','',''),
('svg_icon_editor','msg_svg_empty_ok','Ikona je prázdná (po potvrzení bude odstraněna).','',''),
('svg_icon_editor','msg_syntax_ok','✓ Syntaxe SVG je platná.','',''),
('svg_icon_editor','tip_open_svg_editor','Dvojklikem nebo tlačítkem otevřete editor vektorové ikony SVG','',''),
('svg_icon_editor','tip_svg_ext_source','Otevře katalog ikon v nové záložce (zkopírujte SVG kód ikony a vložte jej sem)','',''),
/*#do# svg_icon_editor */

/*#od# user_context */
('user_context','btn_logout','Odhlásit','Ukončí aktuální relaci a odhlásí uživatele ze systému','ctx-logout'),
('user_context','lbl_default_org','Organizace','',''),
('user_context','lbl_default_user','Uživatel','',''),
('user_context','lbl_logo_placeholder','[ Logo / Grafika ]','',''),
('user_context','role_admin','ADMIN','',''),
('user_context','role_dev','DEV','',''),
('user_context','role_sysadmin','SYSADMIN','',''),
('user_context','role_user','USER','',''),
('user_context','tip_change_context','Změnit organizaci či roli','',''),
('user_context','tip_current_org','Aktuální organizace','',''),
('user_context','tip_logged_user','Přihlášený uživatel','','');
/*#do# user_context */

-- 1. Hromadný UPDATE existujících hlavních záznamů (record_type = 'A', language = 'cs')
UPDATE mp
SET mp.caption = s.caption,
	mp.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE mp.helptext END,
	mp.css_class = CASE WHEN s.css_class <> '' THEN s.css_class ELSE mp.css_class END,
	mp.[language] = 'cs',
	mp.import_origin = CASE WHEN mp.import_origin = 'AUTO_DISCOVERED' THEN NULL ELSE mp.import_origin END,
	mp.who_modified = @sys_owner,
	mp.date_modified = GETDATE()
FROM meta_phrase mp
JOIN @phr_cs s
	ON s.source_code = mp.source_code
	AND s.builtin_code = mp.builtin_code
WHERE mp.object_owner = @sys_owner
  AND mp.record_type = 'A'
  AND (
	mp.who_modified = @sys_owner
	OR mp.date_modified < '2026-11-01'
	OR mp.import_origin = 'AUTO_DISCOVERED'
  )
  AND EXISTS (
	SELECT mp.caption, mp.helptext, mp.css_class, mp.[language]
	EXCEPT
	SELECT s.caption, CASE WHEN s.helptext <> '' THEN s.helptext ELSE mp.helptext END, CASE WHEN s.css_class <> '' THEN s.css_class ELSE mp.css_class END, 'cs'
  );

-- 2. Hromadný INSERT chybějících hlavních záznamů (record_type = 'A', language = 'cs')
INSERT INTO meta_phrase (
	uuid, object_owner, original, record_type, approval_status, [language],
	source_code, builtin_code, caption, helptext, css_class,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
	s.source_code, s.builtin_code, s.caption, s.helptext, s.css_class,
	1, 1,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM @phr_cs s
CROSS APPLY (
	SELECT dbo.f_generate_original('meta_phrase', @sys_owner, s.source_code, s.builtin_code) AS orig
) x
WHERE NOT EXISTS (
	SELECT 1 FROM meta_phrase mp
	WHERE mp.original = x.orig
	  AND mp.object_owner = @sys_owner
	  AND mp.record_type = 'A'
);

-- 3. Hromadný UPDATE existujících symetrických 'L' záznamů pro češtinu (language = 'cs')
UPDATE l
SET l.caption = s.caption,
	l.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END,
	l.css_class = a.css_class,
	l.import_origin = CASE WHEN l.import_origin = 'AUTO_DISCOVERED' THEN NULL ELSE l.import_origin END,
	l.who_modified = @sys_owner,
	l.date_modified = GETDATE()
FROM meta_phrase l
JOIN meta_phrase a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
JOIN @phr_cs s
	ON s.source_code = a.source_code
	AND s.builtin_code = a.builtin_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'cs'
  AND (
	l.who_modified = @sys_owner
	OR l.date_modified < '2026-11-01'
	OR l.import_origin = 'AUTO_DISCOVERED'
  )
  AND EXISTS (
	SELECT l.caption, l.helptext, l.css_class
	EXCEPT
	SELECT s.caption, CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END, a.css_class
  );

-- 4. Hromadný INSERT chybějících symetrických 'L' záznamů pro češtinu (language = 'cs')
INSERT INTO meta_phrase (
	uuid, object_owner, original, record_type, approval_status, [language],
	source_code, builtin_code, caption, helptext, svg_icon, css_class,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
	a.source_code, a.builtin_code, s.caption, s.helptext, a.svg_icon, a.css_class,
	a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_phrase a
JOIN @phr_cs s
	ON s.source_code = a.source_code
	AND s.builtin_code = a.builtin_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_phrase l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
  );
GO