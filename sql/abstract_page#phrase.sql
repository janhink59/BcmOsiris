/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: abstract_page#phrase.sql
 * Účel:   Registrace základní třídy abstract_page do sysinit_object a naplnění
 *         jejích výchozích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'abstract_page';
DELETE FROM sysinit_phrase WHERE source_code = 'abstract_page';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','abstract_page','cs','U','Základní šablona stránky','Abstraktní předek všech stránek zajišťující hlavičku, kontext a ochranu formulářů'),
('P','abstract_page','en','U','Base Page Template','Abstract ancestor of all pages providing header, user context, and form protection');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('abstract_page','msg_access_denied','cs','Přístup odepřen. K zobrazení této stránky nemáte dostatečná oprávnění.','',''),
('abstract_page','msg_unsaved_changes','cs','Máte neuložené změny. Opravdu chcete stránku opustit?','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('abstract_page','msg_access_denied','en','Access denied. You do not have sufficient permissions to view this page.',''),
('abstract_page','msg_unsaved_changes','en','You have unsaved changes. Are you sure you want to leave this page?','');
GO