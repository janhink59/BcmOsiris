/* =============================================================================
 * Verze: 2026-11-15 19:15
 * Soubor: filter_manager#phrase.sql
 * Účel:   Registrace třídy filter_manager do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'filter_manager';
DELETE FROM sysinit_phrase WHERE source_code = 'filter_manager';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','filter_manager','cs','U','Správce filtrů a filtračních výrazů','Univerzální služba pro zobrazení, validaci a vyhodnocování vícepoložkových filtrů'),
('P','filter_manager','en','U','Filter & Expression Manager','Universal service for rendering, validating, and evaluating multi-field filters');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('filter_manager','btn_apply_filter','cs','Použít filtr','Aktivuje zadané filtrační podmínky a přefiltruje seznam','btn-success'),
('filter_manager','btn_cancel_modal','cs','Zavřít','Zavře okno rozšířeného filtru bez uložení změn','btn-secondary'),
('filter_manager','btn_clear_filter','cs','Vymazat vše','Vymaže všechny podmínky filtru a zobrazí kompletní seznam','btn-secondary'),
('filter_manager','btn_hide_extra_fields','cs','Skrýt rozšiřující položky','Skryje dodatečné sloupce v modálním okně filtru',''),
('filter_manager','btn_show_all_fields','cs','Zobrazit vše (+{$count} dalších položek)','Rozbalí zbývající sloupce třídy v modálním okně filtru',''),
('filter_manager','err_date_range_order','cs','Počáteční datum ({$min}) je větší než koncové ({$max}) u položky „{$label}“.','',''),
('filter_manager','err_invalid_date_expr','cs','Neplatné datum „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_date_range','cs','Neplatný datumový interval „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_number_expr','cs','Neplatný číselný výraz „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_number_range','cs','Neplatný číselný interval „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_number_range_order','cs','Dolní mez intervalu ({$min}) je větší než horní mez ({$max}) u položky „{$label}“.','',''),
('filter_manager','hdr_modal_filter','cs','Rozšířené filtrování záznamů','',''),
('filter_manager','help_syntax_number','cs','Čísla a data: 10..50 (interval), 10.., ..50, >=10, <=50, <>0, seznam oddělený ; a samotné = (nezadáno / NULL).','',''),
('filter_manager','help_syntax_string','cs','Texty: slovo (obsahuje), slovo* (začíná), *slovo (končí), =text (přesně), !text (neobsahuje), = (nezadáno), * (zadáno).','',''),
('filter_manager','lbl_quick_filter','cs','Rychlý filtr','',''),
('filter_manager','lbl_record_state','cs','Stav záznamu','',''),
('filter_manager','opt_all','cs','--- Vše ---','',''),
('filter_manager','opt_is_null','cs','= (Nezadaná hodnota / NULL)','',''),
('filter_manager','opt_not_null','cs','* (Zadaná hodnota / NOT NULL)','',''),
('filter_manager','opt_state_active','cs','Aktivní platné záznamy','',''),
('filter_manager','opt_state_draft_any','cs','Rozpracované návrhy (D / F / R)','',''),
('filter_manager','opt_state_draft_f','cs','Předáno ke schválení (F)','',''),
('filter_manager','opt_state_draft_r','cs','Vráceno k přepracování (R)','',''),
('filter_manager','opt_state_inactive','cs','Neaktivní (inactive = 1)','',''),
('filter_manager','opt_state_mine','cs','Pouze vlastní záznamy organizace','',''),
('filter_manager','opt_state_removed','cs','Zrušené v koši (removed = 1)','',''),
('filter_manager','opt_state_system','cs','Pouze systémové záznamy (0x00)','',''),
('filter_manager','ph_date_expr','cs','např. 1.1.2026..31.12.2026, >=2026-01-01 nebo = (prázdné)','',''),
('filter_manager','ph_number_expr','cs','např. 10..50, >=25, <>0, 1;2;5 nebo = (prázdné)','',''),
('filter_manager','ph_text_expr','cs','slovo (obsahuje), slovo*, *slovo, =přesně, !není, = (prázdné)','',''),
('filter_manager','val_no','cs','Ne (0)','',''),
('filter_manager','val_yes','cs','Ano (1)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('filter_manager','btn_apply_filter','en','Apply Filter','Apply the specified filter conditions and refresh the list'),
('filter_manager','btn_cancel_modal','en','Close','Close the advanced filter window without saving changes'),
('filter_manager','btn_clear_filter','en','Clear All','Clear all filter conditions and show the full list'),
('filter_manager','btn_hide_extra_fields','en','Hide Extra Fields','Hide additional columns in the filter modal window'),
('filter_manager','btn_show_all_fields','en','Show All (+{$count} more fields)','Expand the remaining columns of the class in the filter modal'),
('filter_manager','err_date_range_order','en','Start date ({$min}) is greater than end date ({$max}) in field "{$label}".',''),
('filter_manager','err_invalid_date_expr','en','Invalid date "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_date_range','en','Invalid date range "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_number_expr','en','Invalid numeric expression "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_number_range','en','Invalid numeric range "{$expr}" in field "{$label}".',''),
('filter_manager','err_number_range_order','en','Lower bound ({$min}) is greater than upper bound ({$max}) in field "{$label}".',''),
('filter_manager','hdr_modal_filter','en','Advanced Record Filtering',''),
('filter_manager','help_syntax_number','en','Numbers & dates: 10..50 (range), 10.., ..50, >=10, <=50, <>0, semicolon-separated list ; and = (empty / NULL).',''),
('filter_manager','help_syntax_string','en','Strings: word (contains), word* (starts with), *word (ends with), =text (exact), !text (not), = (empty), * (non-empty).',''),
('filter_manager','lbl_quick_filter','en','Quick Filter',''),
('filter_manager','lbl_record_state','en','Record State',''),
('filter_manager','opt_all','en','--- All ---',''),
('filter_manager','opt_is_null','en','= (Empty / NULL)',''),
('filter_manager','opt_not_null','en','* (Non-Empty / NOT NULL)',''),
('filter_manager','opt_state_active','en','Active Valid Records',''),
('filter_manager','opt_state_draft_any','en','Work-in-Progress Drafts (D / F / R)',''),
('filter_manager','opt_state_draft_f','en','Submitted for Approval (F)',''),
('filter_manager','opt_state_draft_r','en','Returned for Revision (R)',''),
('filter_manager','opt_state_inactive','en','Inactive (inactive = 1)',''),
('filter_manager','opt_state_mine','en','Organization Own Records Only',''),
('filter_manager','opt_state_removed','en','Removed in Trash (removed = 1)',''),
('filter_manager','opt_state_system','en','System Records Only (0x00)',''),
('filter_manager','ph_date_expr','en','e.g. 1.1.2026..31.12.2026, >=2026-01-01 or = (empty)',''),
('filter_manager','ph_number_expr','en','e.g. 10..50, >=25, <>0, 1;2;5 or = (empty)',''),
('filter_manager','ph_text_expr','en','word (contains), word*, *word, =exact, !not, = (empty)',''),
('filter_manager','val_no','en','No (0)',''),
('filter_manager','val_yes','en','Yes (1)','');
GO