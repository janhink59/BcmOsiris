/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_login#phrase.sql
 * Účel:   Registrace přihlašovací stránky page_login do sysinit_object.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_login';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_login','cs','U','Přihlášení do systému','Přihlašovací obrazovka s podporou lokální autentizace a SSO'),
('P','page_login','en','U','System Login','Login screen supporting local authentication and SSO');
GO