/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: rich_text#phrase.sql
 * Účel:   Registrace služby rich_text do sysinit_object a naplnění jejích
 *         českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'rich_text';
DELETE FROM sysinit_phrase WHERE source_code = 'rich_text';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','rich_text','cs','U','Služba formátovaného textu (Markdown/HTML)','Konverze, sanitizace a modální Toast UI Editor pro sloupce s is_html = 1'),
('P','rich_text','en','U','Rich Text Service (Markdown/HTML)','Conversion, sanitization, and modal Toast UI Editor for columns with is_html = 1');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('rich_text','btn_apply_text','cs','Převzít do detailu','Přenese upravený text z modálního editoru do formuláře (pro trvalé uložení do DB poté klikněte na Uložit změny)','btn-success'),
('rich_text','btn_cancel_text','cs','Zrušit','Zavře modální editor bez přenesení změn do formuláře','btn-secondary'),
('rich_text','btn_edit_text','cs','Upravit text','Otevře modální WYSIWYG / Markdown editor na popředí',''),
('rich_text','confirm_convert_format','cs','Převést stávající text do nově zvoleného formátu?','',''),
('rich_text','lbl_format_select','cs','Formát uložení:','',''),
('rich_text','lbl_modal_title','cs','Úprava formátovaného textu:','',''),
('rich_text','msg_modal_hint','cs','Pro trvalé uložení do databáze nezapomeňte po převzetí textu uložit celý formulář.','',''),
('rich_text','opt_format_html','cs','Čisté HTML','',''),
('rich_text','opt_format_markdown','cs','Markdown (preferováno)','',''),
('rich_text','tip_convert_format','cs','Převede stávající text mezi formáty Markdown a HTML a přepne režim editoru','',''),
('rich_text','tip_open_editor','cs','Otevřít editor formátovaného textu na popředí','',''),
('rich_text','txt_empty_prev','cs','(Prázdné – klikněte na Upravit text)','',''),
('rich_text','txt_empty_preview','cs','(Prázdné – klikněte na Upravit)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('rich_text','btn_apply_text','en','Apply to Detail','Transfer the edited text from the modal editor into the form (click Save Changes afterwards to store in DB)'),
('rich_text','btn_cancel_text','en','Cancel','Close the modal editor without applying changes to the form'),
('rich_text','btn_edit_text','en','Edit Text','Open the foreground WYSIWYG / Markdown modal editor'),
('rich_text','confirm_convert_format','en','Convert existing text to the newly selected format?',''),
('rich_text','lbl_format_select','en','Storage format:',''),
('rich_text','lbl_modal_title','en','Edit Formatted Text:',''),
('rich_text','msg_modal_hint','en','Remember to save the main form after applying the text to store changes permanently in the database.',''),
('rich_text','opt_format_html','en','Pure HTML',''),
('rich_text','opt_format_markdown','en','Markdown (preferred)',''),
('rich_text','tip_convert_format','en','Converts existing text between Markdown and HTML formats and switches editor mode',''),
('rich_text','tip_open_editor','en','Open foreground rich text editor',''),
('rich_text','txt_empty_prev','en','(Empty – click Edit Text)',''),
('rich_text','txt_empty_preview','en','(Empty – click Edit)','');
GO