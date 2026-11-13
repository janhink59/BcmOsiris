/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_logout#phrase.sql
 * Účel:   Registrace odhlašovací stránky page_logout do sysinit_object.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_logout';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_logout','cs','U','Odhlášení ze systému','Ukončení relace a zneplatnění přihlašovacích tokenů'),
('P','page_logout','en','U','System Logout','Session termination and invalidation of login tokens');
GO