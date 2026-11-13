/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: svg_icon_editor#phrase.sql
 * Účel:   Registrace komponenty svg_icon_editor do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'svg_icon_editor';
DELETE FROM sysinit_phrase WHERE source_code = 'svg_icon_editor';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','svg_icon_editor','cs','U','Modální editor SVG ikon','Komponenta pro náhled, validaci XML syntaxe a úpravu vektorových ikon svg_icon'),
('P','svg_icon_editor','en','U','Modal SVG Icon Editor','Component for previewing, XML syntax validation, and editing of svg_icon vector icons');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('svg_icon_editor','btn_apply_svg','cs','Převzít do detailu','Přenese zkontrolovanou SVG ikonu do náhledu ve formuláři','btn-success'),
('svg_icon_editor','btn_cancel_svg','cs','Zrušit','Zavře editor SVG ikony bez uplatnění změn','btn-secondary'),
('svg_icon_editor','btn_clear_svg','cs','Vymazat','Odstraní SVG ikonu z pole','btn-danger'),
('svg_icon_editor','btn_edit_svg','cs','Upravit ikonu','Otevře modální editor vektorové SVG ikony',''),
('svg_icon_editor','btn_validate_svg','cs','Zkontrolovat syntaxi a vyčistit','Ověří XML syntaxi a odstraní případné nepovolené značky',''),
('svg_icon_editor','err_js_not_svg_root','cs','Kód musí obsahovat kořenový element <svg>...</svg>.','',''),
('svg_icon_editor','err_js_xml_invalid','cs','Neplatná XML syntaxe: ','',''),
('svg_icon_editor','err_svg_not_root','cs','Kořenovým elementem ikony musí být značka <svg>.','',''),
('svg_icon_editor','err_svg_xml_syntax','cs','Chyba syntaxe SVG ikony: {$detail}','',''),
('svg_icon_editor','lbl_live_preview','cs','Živý náhled a kontrola syntaxe:','',''),
('svg_icon_editor','lbl_modal_title','cs','Editor vektorové ikony (SVG):','',''),
('svg_icon_editor','lbl_no_svg_icon','cs','Ikona není nastavena (dvojklikem upravíte)','',''),
('svg_icon_editor','lbl_svg_code_input','cs','Zdrojový kód SVG ikony (vložte <svg ...>...</svg>):','',''),
('svg_icon_editor','lbl_svg_sources','cs','Získat SVG kód ikony:','',''),
('svg_icon_editor','msg_modal_hint','cs','Tip: Ikony s fill="currentColor" nebo bez atributu fill automaticky přebírají barvu textu v menu a tlačítkách. Vlastní barvy (např. fill="#...") zůstávají všude zachovány.','',''),
('svg_icon_editor','msg_svg_empty_ok','cs','Ikona je prázdná (po potvrzení bude odstraněna).','',''),
('svg_icon_editor','msg_syntax_ok','cs','✓ Syntaxe SVG je platná.','',''),
('svg_icon_editor','tip_open_svg_editor','cs','Dvojklikem nebo tlačítkem otevřete editor vektorové ikony SVG','',''),
('svg_icon_editor','tip_svg_ext_source','cs','Otevře katalog ikon v nové záložce (zkopírujte SVG kód ikony a vložte jej sem)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('svg_icon_editor','btn_apply_svg','en','Apply to Detail','Transfer the validated SVG icon into the form preview'),
('svg_icon_editor','btn_cancel_svg','en','Cancel','Close the SVG icon editor without applying changes'),
('svg_icon_editor','btn_clear_svg','en','Clear','Remove the SVG icon'),
('svg_icon_editor','btn_edit_svg','en','Edit Icon','Open the modal SVG vector icon editor'),
('svg_icon_editor','btn_validate_svg','en','Validate Syntax & Clean','Validate XML syntax and sanitize the SVG code'),
('svg_icon_editor','err_js_not_svg_root','en','Code must contain a root <svg>...</svg> element.',''),
('svg_icon_editor','err_js_xml_invalid','en','Invalid XML syntax: ',''),
('svg_icon_editor','err_svg_not_root','en','The root element of the icon must be an <svg> tag.',''),
('svg_icon_editor','err_svg_xml_syntax','en','SVG icon syntax error: {$detail}',''),
('svg_icon_editor','lbl_live_preview','en','Live Preview & Syntax Check:',''),
('svg_icon_editor','lbl_modal_title','en','Vector Icon Editor (SVG):',''),
('svg_icon_editor','lbl_no_svg_icon','en','Icon not set (double-click to edit)',''),
('svg_icon_editor','lbl_svg_code_input','en','SVG Icon Source Code (paste <svg ...>...</svg>):',''),
('svg_icon_editor','lbl_svg_sources','en','Get SVG Icon Code:',''),
('svg_icon_editor','msg_modal_hint','en','Tip: Icons with fill="currentColor" or without a fill attribute automatically inherit text color in menus and buttons. Custom colors (e.g., fill="#...") are preserved everywhere.',''),
('svg_icon_editor','msg_svg_empty_ok','en','Icon is empty (will be cleared upon confirmation).',''),
('svg_icon_editor','msg_syntax_ok','en','✓ SVG syntax is valid.',''),
('svg_icon_editor','tip_open_svg_editor','en','Double-click or click the button to open the SVG vector icon editor',''),
('svg_icon_editor','tip_svg_ext_source','en','Opens the icon catalog in a new tab (copy the SVG icon code and paste it here)','');
GO