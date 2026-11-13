/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_password_reset#phrase.sql
 * Účel:   Registrace stránky obnovy hesla page_password_reset do sysinit_object.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_password_reset';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_password_reset','cs','U','Obnova hesla','Stránka pro vyžádání a nastavení nového hesla pomocí tokenu'),
('P','page_password_reset','en','U','Password Reset','Page for requesting and setting a new password using a token');
GO