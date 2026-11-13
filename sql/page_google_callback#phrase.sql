/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_google_callback#phrase.sql
 * Účel:   Registrace SSO koncového bodu page_google_callback do sysinit_object.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_google_callback';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_google_callback','cs','U','Google SSO Callback','Koncový bod pro ověření identity přes Google OAuth'),
('P','page_google_callback','en','U','Google SSO Callback','Endpoint for identity verification via Google OAuth');
GO