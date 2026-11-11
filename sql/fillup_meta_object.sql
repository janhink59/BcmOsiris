/* =============================================================================
 * Verze: 2026-11-11 22:15
 * Soubor: fillup_meta_object.sql
 * Účel:   Idempotentní prvotní naplnění a registrace systémových PHP stránek
 *         a UI tříd (object_type = 'P', object_owner = 0x00) do tabulky meta_object
 *         včetně symetrických 'L' záznamů pro výchozí jazyk ('cs').
 * Vazby:  - Vyžaduje existenci tabulky meta_object (table_meta_object.sql)
 *           a funkce dbo.f_generate_original (f_generate_original.sql).
 *         - Slouží jako podklad pro navigační vazby target_object v fillup_meta_menu.sql
 *           a pro kontrolu oprávnění v abstract_page::check_system_role_access().
 * Změny:  - 2026-11-11 22:15: Doplněna registrace stránky page_link_diagram.
 *         - 2026-11-09 14:45: Doplněna registrace stránek page_asset, page_link,
 *           page_meta_link_def, page_scenario_assessment a page_countermeasure_implementation.
 *         - 2026-11-06 14:15: Doplněna registrace třídy filter_manager a CSV balíčku
 *           csv_package_simple_class; stránka page_csv_package zpřístupněna pro roli 'U'.
 * ============================================================================= */

SET NOCOUNT ON;
GO

-- 1. Vyčištění zastaralých systémových záznamů (fráze 'G', bezejmenný '' a stránky bez prefixu 'page_')
DELETE FROM meta_object
WHERE object_owner = 0x00
  AND (
	object_type = 'G'
	OR (
		object_type = 'P'
		AND builtin_code IN (
			'', 'excel_reader', 'main', 'meta_class', 'meta_column',
			'organization_licence', 'org_users', 'change_user_context', 'logout'
		)
	)
  );
GO

-- 2. Registrace systémových stránek a UI tříd do meta_object (A + symetrické L)
DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @pages TABLE (
	builtin_code varchar(80),
	caption varchar(200),
	description varchar(max),
	system_role varchar(1)
);

INSERT INTO @pages (builtin_code, caption, description, system_role) VALUES 
('abstract_button','Komponenta tlačítka','Základní třída pro vykreslování tlačítek s ikonou a tooltipem','U'),
('abstract_csv_package','Abstraktní CSV/TSV balíček','Základní třída pro export a dvoufázový import víceblokových CSV/TSV balíčků','U'),
('abstract_page','Základní šablona stránky','Abstraktní předek všech stránek zajišťující hlavičku, kontext a ochranu formulářů','U'),
('abstract_page_master_detail','Šablona Master-Detail','Abstraktní dvoupanelová šablona pro správu entit','U'),
('abstract_page_tree','Stromová šablona Master-Detail','Abstraktní dvoupanelová šablona pro správu hierarchických stromových struktur s podporou Drag & Drop','U'),
('csv_package_metadata','CSV/TSV balíček systémových metadat','Definice a filtry pro přenos systémových metadat mezi instancemi','U'),
('csv_package_simple_class','CSV balíček dat jedné třídy organizace','Export a dvoufázový import záznamů jedné logické třídy aktuálního tenanta','U'),
('entity_manager','Správce logických entit','Dynamický generátor SQL dotazů, seznamů a formulářů podle metadat','U'),
('filter_manager','Správce filtrů a filtračních výrazů','Univerzální služba pro zobrazení, validaci a vyhodnocování vícepoložkových filtrů','U'),
('global_phrase','Globální fráze systému','Třída a kontejner pro celosystémové textové fráze a sdílené popisky','U'),
('menu_manager','Správce navigace','Třída pro sestavení a vykreslení drobečkové navigace a menu','U'),
('page_approval','Schvalování změn','Přehled, porovnání a schvalování navržených záznamů napříč třídami','U'),
('page_asset','Evidence aktiv a prostorů (CRMM)','Správa prostorů (okres, město, lokalita, budova, místnost) a všech archetypů aktiv organizace','U'),
('page_asset_class','Třídy aktiv (Katalog CRMM)','Správa hierarchického katalogu tříd aktiv v modulu CRMM','U'),
('page_audit_login_session','Aktivita uživatelů (audit_login_session)','Přehled historie přihlášení a aktivity uživatelů z tabulky audit_login_session','A'),
('page_change_user_context','Změna kontextu uživatele','Přepínání aktivní organizace, aplikační role a žádosti o přístup','U'),
('page_countermeasure','Katalog protiopatření (CRMM)','Správa hierarchického katalogu bezpečnostních a provozních protiopatření v modulu CRMM','U'),
('page_countermeasure_implementation','Implementace protiopatření (CRMM)','Evidence stavu zavedení protiopatření na aktivech a prostorech organizace','U'),
('page_countermeasure_state','Stavy protiopatření (CRMM)','Správa číselníku stavů implementace protiopatření a jejich redukčních a rizikových faktorů','U'),
('page_csv_package','Přenos balíčků (CSV/TSV)','Nástroj pro export a dvoufázový import datových balíčků ve formátu TSV/CSV','U'),
('page_excel_reader','Import dat z Excelu','Nástroj pro hromadný import a distribuci datových struktur z Excelu','S'),
('page_google_callback','Google SSO Callback','Koncový bod pro ověření identity přes Google OAuth','U'),
('page_hierarchy','Sekundární hierarchie a štítky (Tagy)','Správa registru sekundárních hierarchií, číselníků a stromů štítků (tagů)','U'),
('page_hierarchy_item','Položky sekundárních hierarchií','Správa uzlů a položek jednotlivých sekundárních hierarchií, číselníků a štítků','U'),
('page_impact','Katalog dopadů (CRMM)','Správa hierarchického číselníku dopadů v modulu CRMM','U'),
('page_link','Vazby a závislosti aktiv (CRMM)','Správa uživatelských a zděděných vazeb M:N mezi aktivy, službami, aplikacemi, daty, hrozbami a opatřeními','U'),
('page_link_diagram','Schémata sítí vztahů (Diagramy CRMM)','Správa orientovaných schémat heterogenních sítí vztahů a projekce nepřímých vazeb pro přenos rizik','U'),
('page_login','Přihlášení do systému','Přihlašovací obrazovka s podporou lokální autentizace a SSO','U'),
('page_logout','Odhlášení ze systému','Ukončení relace a zneplatnění přihlašovacích tokenů','U'),
('page_main','Hlavní panel','Úvodní rozcestník aplikace po přihlášení','U'),
('page_meta_class','Logické třídy (Objekty)','Správa logických entit, jejich vlastností a překladů','U'),
('page_meta_column','Sloupce metadat','Správa definic sloupců, formulářových prvků a překladů','U'),
('page_meta_link_def','Definice typů vazeb (CRMM)','Správa povolených typů relací a vazeb mezi třídami objektů v tabulce meta_link_def','U'),
('page_meta_menu','Položky menu (Navigace)','Správa hierarchie, pořadí, cílových stránek a překladů položek menu','U'),
('page_meta_phrase','Textové fráze a překlady','Správa textových frází, tlačítek a jazykových mutací','U'),
('page_org_users','Uživatelé organizace','Správa uživatelských účtů a oprávnění v rámci organizace','A'),
('page_organization','Správa a nastavení organizace','Nastavení organizace, fakturačních údajů a parametrů výpočtů CRMM','A'),
('page_organization_licence','Správa licencí organizací','Evidence a aktivace licencí pro jednotlivé tenanty','A'),
('page_password_reset','Obnova hesla','Stránka pro vyžádání a nastavení nového hesla pomocí tokenu','U'),
('page_scale','Hodnotící škály (CRMM)','Správa definic hodnotících škál pro hrozby, zranitelnosti, dopady a rizika','U'),
('page_scale_value','Stupně hodnotících škál (CRMM)','Správa jednotlivých stupňů hodnotících škál, prahových hodnot a skóre v intervalu 0 až 100 %','U'),
('page_scenario','Rizikové scénáře (Katalog CRMM)','Správa hierarchického katalogu rizikových scénářů a událostí v modulu CRMM','U'),
('page_scenario_assessment','Hodnocení rizikových scénářů (CRMM)','Vyhodnocení velikosti hrozby, zranitelnosti, dopadu a míry rizika scénářů nad aktivy organizace','U'),
('page_service_logbook','Provozní deník (service_logbook)','Přehled historie provedených upgradů databáze a importů systémových dávek','S'),
('page_threat','Katalog hrozeb (CRMM)','Správa hierarchického katalogu hrozeb a jejich výchozího hodnocení v modulu CRMM','U'),
('page_xlsx_export_meta','Export metadat do Excelu','Nástroj pro zpětný export systémových metadat do souboru XLSX','S'),
('svg_icon_editor','Modální editor SVG ikon','Komponenta pro náhled, validaci XML syntaxe a úpravu vektorových ikon svg_icon','U'),
('user_context','Kontextový panel uživatele','Horní lišta s informacemi o přihlášeném uživateli, roli a volbou jazyka','U');

-- 2a. Idempotentní vložení chybějících hlavních 'A' záznamů
INSERT INTO meta_object (
	uuid, object_owner, original, record_type, approval_status, [language],
	object_type, builtin_code, system_role, caption, description, module
)
SELECT 
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	@sys_owner,
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	'A', 'A', 'cs', 'P', p.builtin_code, p.system_role, p.caption, p.description, ''
FROM @pages p
WHERE NOT EXISTS (
	SELECT 1 FROM meta_object mo 
	WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code)
	  AND mo.record_type = 'A' AND mo.object_owner = @sys_owner AND mo.removed = 0
);

-- 2b. Idempotentní vložení chybějících symetrických 'L' záznamů pro výchozí jazyk ('cs')
INSERT INTO meta_object (
	uuid, object_owner, original, record_type, approval_status, [language],
	object_type, builtin_code, system_role, caption, description, module
)
SELECT 
	NEWID(),
	@sys_owner,
	dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code),
	'L', 'A', 'cs', 'P', p.builtin_code, p.system_role, p.caption, p.description, ''
FROM @pages p
WHERE NOT EXISTS (
	SELECT 1 FROM meta_object mo 
	WHERE mo.original = dbo.f_generate_original('meta_object', @sys_owner, 'P', p.builtin_code)
	  AND mo.record_type = 'L' AND mo.[language] = 'cs' AND mo.object_owner = @sys_owner AND mo.removed = 0
);

-- 2c. Aktualizace system_role u page_organization, page_organization_licence a page_csv_package
UPDATE mo
SET mo.system_role = p.system_role
FROM meta_object mo
JOIN @pages p ON p.builtin_code = mo.builtin_code
WHERE mo.object_owner = @sys_owner
  AND mo.object_type = 'P'
  AND mo.builtin_code IN ('page_organization', 'page_organization_licence', 'page_csv_package')
  AND mo.system_role <> p.system_role;
GO