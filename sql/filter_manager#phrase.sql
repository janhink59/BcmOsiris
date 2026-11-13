/* =============================================================================
 * Verze: 2026-11-13 16:15
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
('filter_manager','btn_clear_filter','cs','Zrušit filtr','Vymaže všechny podmínky filtru a zobrazí kompletní seznam','btn-danger'),
('filter_manager','btn_close_filter','cs','Zavřít','Zavře okno rozšířeného filtru bez uložení změn','btn-secondary'),
('filter_manager','btn_show_all_fields','cs','Zobrazit vše (+{$count} dalších položek)','Rozbalí zbývající sloupce třídy v modálním okně filtru',''),
('filter_manager','err_date_range_order','cs','Počáteční datum ({$min}) je větší než koncové ({$max}) u položky „{$label}“.','',''),
('filter_manager','err_invalid_date_expr','cs','Neplatné datum „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_date_range','cs','Neplatný datumový interval „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_number_expr','cs','Neplatný číselný výraz „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_invalid_number_range','cs','Neplatný číselný interval „{$expr}“ u položky „{$label}“.','',''),
('filter_manager','err_number_range_order','cs','Dolní mez intervalu ({$min}) je větší než horní mez ({$max}) u položky „{$label}“.','',''),
('filter_manager','help_bool','cs','Vyberte Ano (1), Ne (0) nebo Vše.','',''),
('filter_manager','help_date','cs','Zadejte datum (R-M-D nebo D.M.R), interval (od..do) nebo porovnání (>=, <=).','',''),
('filter_manager','help_number','cs','Zadejte číslo, interval (10..50) nebo porovnání (>=10, <100, !=0).','',''),
('filter_manager','help_select','cs','Vyberte konkrétní položku ze seznamu.','',''),
('filter_manager','help_text','cs','Hledá výskyt textu (nerozlišuje velikost písmen). Podporuje hvězdičku (*) a čárkou oddělený seznam.','',''),
('filter_manager','lbl_modal_title','cs','Rozšířený filtr záznamů','',''),
('filter_manager','opt_bool_all','cs','--- Vše ---','',''),
('filter_manager','opt_bool_no','cs','Ne (0)','',''),
('filter_manager','opt_bool_yes','cs','Ano (1)','',''),
('filter_manager','opt_select_all','cs','--- Vše ---','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('filter_manager','btn_apply_filter','en','Apply Filter','Apply the specified filter conditions and refresh the list'),
('filter_manager','btn_clear_filter','en','Clear Filter','Clear all filter conditions and show the full list'),
('filter_manager','btn_close_filter','en','Close','Close the advanced filter window without saving changes'),
('filter_manager','btn_show_all_fields','en','Show All (+{$count} more fields)','Expand the remaining columns of the class in the filter modal'),
('filter_manager','err_date_range_order','en','Start date ({$min}) is greater than end date ({$max}) in field "{$label}".',''),
('filter_manager','err_invalid_date_expr','en','Invalid date "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_date_range','en','Invalid date range "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_number_expr','en','Invalid numeric expression "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_number_range','en','Invalid numeric range "{$expr}" in field "{$label}".',''),
('filter_manager','err_number_range_order','en','Lower bound ({$min}) is greater than upper bound ({$max}) in field "{$label}".',''),
('filter_manager','help_bool','en','Select Yes (1), No (0), or All.',''),
('filter_manager','help_date','en','Enter a date (Y-M-D or D.M.Y), range (from..to), or comparison (>=, <=).',''),
('filter_manager','help_number','en','Enter a number, range (10..50), or comparison (>=10, <100, !=0).',''),
('filter_manager','help_select','en','Select a specific item from the dropdown list.',''),
('filter_manager','help_text','en','Case-insensitive substring search. Supports wildcard (*) and comma-separated lists.',''),
('filter_manager','lbl_modal_title','en','Advanced Record Filter',''),
('filter_manager','opt_bool_all','en','--- All ---',''),
('filter_manager','opt_bool_no','en','No (0)',''),
('filter_manager','opt_bool_yes','en','Yes (1)',''),
('filter_manager','opt_select_all','en','--- All ---','');
GO