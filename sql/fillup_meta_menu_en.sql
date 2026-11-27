/* =============================================================================
 * Verze: 2026-11-27 15:40
 * Soubor: fillup_meta_menu_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en') pro kořenovou položku
 *    ('home') a hlavní rozcestníkové složky navigace ('crmm_analysis_folder',
 *    'crmm_folder', 'metadata_folder', 'admin_folder') do staging tabulky
 *    sysinit_menu.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní český skript fillup_meta_menu.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje do tabulky sysinit_menu (zakládané v sysinit_reset.sql).
 *    - Promítnutí do meta_menu (záznamy record_type = 'L', language = 'en')
 *      provádí procedura dbo.p_sysinit_process (p_sysinit_process.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      staging tabulkou sysinit_menu bez závislosti na relaci v dbsession
 *      či SESSION_CONTEXT.
 * ============================================================================= */

SET NOCOUNT ON;
GO

IF OBJECT_ID('sysinit_menu', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_menu
	WHERE [language] = 'en'
	  AND builtin_code IN ('home', 'crmm_analysis_folder', 'crmm_folder', 'metadata_folder', 'admin_folder');

	INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
	('admin_folder','en','System Administration','Change approval, management of organizations, licences, users, data package transfer, service logbook, and user activity','Change approval, management of organizations, licences, users, data package transfer, service logbook, and user activity'),
	('crmm_analysis_folder','en','Risk Analysis & Management (CRMM)','Operational CRMM agenda: spaces and asset inventory, dependency links, risk scenario assessments, and countermeasure implementation','Operational CRMM agenda: spaces and asset inventory, dependency links, risk scenario assessments, and countermeasure implementation'),
	('crmm_folder','en','CRMM Configuration & Catalogs','Methodological configuration of the CRMM system: catalogs of asset classes, threats, impact types and areas, scenarios, countermeasures, assessment scales, secondary hierarchies, link types, and network diagrams','Methodological configuration of the CRMM system: catalogs of asset classes, threats, impact types and areas, scenarios, countermeasures, assessment scales, secondary hierarchies, link types, and network diagrams'),
	('home','en','Home','Main application dashboard','Main application dashboard'),
	('metadata_folder','en','Metadata Management','Management of logical classes, columns, text phrases, navigation, and developer metadata packages','Management of logical classes, columns, text phrases, navigation, and developer metadata packages');
END
GO