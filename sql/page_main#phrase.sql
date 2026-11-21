/* =============================================================================
 * Verze: 2026-11-21 10:50
 * Soubor: page_main#phrase.sql
 *
 * 1. Role souboru v celém systému:
 *    Registrace úvodní stránky page_main do sysinit_object a jejích lokalizačních
 *    frází do sysinit_phrase (cs, en).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Kostra kořenové položky home a hlavních rozcestníkových složek menu byla
 *      vyčleněna do samostatného souboru fillup_meta_menu.sql.
 *    - Odpovídá voláním $this->phrase() v page_main.php.
 *    - Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (maska *#phrase.sql) nad
 *      staging tabulkami sysinit_* bez závislosti na relaci v dbsession.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_main';
DELETE FROM sysinit_phrase WHERE source_code = 'page_main';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_main','cs','U','Hlavní panel','Úvodní rozcestník aplikace po přihlášení'),
('P','page_main','en','U','Main Dashboard','Main application dashboard after login');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_main','default_description','cs','Vyberte požadovanou akci z níže uvedených modulů.','',''),
('page_main','default_heading','cs','Rozcestník','',''),
('page_main','msg_folder_empty','cs','Tato složka momentálně neobsahuje žádné dostupné moduly.','',''),
('page_main','page_title','cs','Hlavní panel - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_main','default_description','en','Select the desired action from the modules below.',''),
('page_main','default_heading','en','Dashboard',''),
('page_main','msg_folder_empty','en','This folder currently contains no available modules.',''),
('page_main','page_title','en','Main Dashboard - BCM Osiris','');
GO