/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: abstract_button#phrase.sql
 * Účel:   Registrace UI třídy abstract_button do sysinit_object a naplnění
 *         jejích výchozích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'abstract_button';
DELETE FROM sysinit_phrase WHERE source_code = 'abstract_button';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','abstract_button','cs','U','Komponenta tlačítka','Základní třída pro vykreslování tlačítek s ikonou a tooltipem'),
('P','abstract_button','en','U','Button Component','Base class for rendering buttons with an icon and tooltip');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('abstract_button','btn_cancel','cs','Zrušit','Zruší akci a vrátí se zpět','btn-secondary'),
('abstract_button','btn_delete_draft','cs','Smazat koncept','Trvale odstraní váš rozpracovaný nebo vrácený koncept bez ovlivnění platného záznamu','btn-danger'),
('abstract_button','btn_discard','cs','Zahodit změny','Zruší neuložené úpravy ve formuláři a zavře detail záznamu','btn-danger'),
('abstract_button','btn_forward_approval','cs','Předat ke schválení','Odešle návrh změny ke kontrole a schválení (stav F)',''),
('abstract_button','btn_save','cs','Uložit změny','Uloží provedené úpravy přímo jako platný schválený záznam (stav A)','btn-success'),
('abstract_button','btn_save_draft','cs','Uložit koncept','Uloží rozpracovaný koncept viditelný pouze pro vás (stav D)','btn-secondary');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('abstract_button','btn_cancel','en','Cancel','Cancel the current action and return'),
('abstract_button','btn_delete_draft','en','Delete Draft','Permanently delete this work-in-progress draft'),
('abstract_button','btn_discard','en','Discard Changes','Close the form without saving changes'),
('abstract_button','btn_forward_approval','en','Submit for Approval','Submit the draft to an approver for review (state F)'),
('abstract_button','btn_save','en','Save Changes','Save changes directly as an approved record (state A)'),
('abstract_button','btn_save_draft','en','Save Draft','Save the record as a private work-in-progress draft (state D)');
GO