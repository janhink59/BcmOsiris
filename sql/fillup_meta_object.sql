/* =============================================================================
 * Verze: 2026-10-25 11:30
 * Soubor: fillup_meta_object.sql
 * Účel:   Idempotentní prvotní naplnění a registrace systémových PHP stránek
 *         a UI tříd (object_type = 'P', object_owner = 0x00) do tabulky meta_object
 *         včetně symetrických 'L' záznamů pro výchozí jazyk ('cs').
 *         Vyčleněno z DDL skriptu table_meta_object.sql.
 * Vazby:  - Vyžaduje existenci tabulky meta_object (table_meta_object.sql)
 *           a funkce dbo.f_generate_original (f_generate_original.sql).
 *         - Slouží jako podklad pro navigační vazby target_object v fillup_meta_menu.sql
 *           a pro kontrolu oprávnění v abstract_page::check_system_role_access().
 * Změny:  - 2026-10-25 11:30: Doplněna registrace stránky page_service_logbook
 *           (system_role = 'S').
 *         - 2026-10-24 13:15: Vyčleněno do samostatného souboru a doplněna
 *           registrace stránky page_meta_menu.
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
('global_phrase', 'Globální fráze systému', 'Třída a kontejner pro celosystémové textové fráze a sdílené popisky', 'U'),
('abstract_page', 'Základní šablona stránky', 'Abstraktní předek všech stránek zajišťující hlavičku, kontext a ochranu formulářů', 'U'),
('abstract_page_master_detail', 'Šablona Master-Detail', 'Abstraktní dvoupanelová šablona pro správu entit', 'U'),
('abstract_button', 'Komponenta tlačítka', 'Základní třída pro vykreslování tlačítek s ikonou a tooltipem', 'U'),
('abstract_csv_package', 'Abstraktní CSV/TSV balíček', 'Základní třída pro export a dvoufázový import víceblokových CSV/TSV balíčků', 'U'),
('csv_package_metadata', 'CSV/TSV balíček systémových metadat', 'Definice a filtry pro přenos systémových metadat mezi instancemi', 'U'),
('user_context', 'Kontextový panel uživatele', 'Horní lišta s informacemi o přihlášeném uživateli, roli a volbou jazyka', 'U'),
('menu_manager', 'Správce navigace', 'Třída pro sestavení a vykreslení drobečkové navigace a menu', 'U'),
('entity_manager', 'Správce logických entit', 'Dynamický generátor SQL dotazů, seznamů a formulářů podle metadat', 'U'),
('page_main', 'Hlavní panel', 'Úvodní rozcestník aplikace po přihlášení', 'U'),
('page_meta_class', 'Logické třídy (Objekty)', 'Správa logických entit, jejich vlastností a překladů', 'U'),
('page_meta_column', 'Sloupce metadat', 'Správa definic sloupců, formulářových prvků a překladů', 'U'),
('page_meta_phrase', 'Textové fráze a překlady', 'Správa textových frází, tlačítek a jazykových mutací', 'U'),
('page_meta_menu', 'Položky menu (Navigace)', 'Správa hierarchie, pořadí, cílových stránek a překladů položek menu', 'U'),
('page_approval', 'Schvalování změn', 'Přehled, porovnání a schvalování navržených záznamů napříč třídami', 'U'),
('page_organization', 'Správa organizací', 'Přehled a editace klientských organizací a jejich nastavení', 'S'),
('page_organization_licence', 'Správa licencí organizací', 'Evidence a aktivace licencí pro jednotlivé tenanty', 'S'),
('page_org_users', 'Uživatelé organizace', 'Správa uživatelských účtů a oprávnění v rámci organizace', 'A'),
('page_excel_reader', 'Import dat z Excelu', 'Nástroj pro hromadný import a distribuci datových struktur z Excelu', 'S'),
('page_xlsx_export_meta', 'Export metadat do Excelu', 'Nástroj pro zpětný export systémových metadat do souboru XLSX', 'S'),
('page_csv_package', 'Přenos balíčků (CSV/TSV)', 'Nástroj pro export a dvoufázový import datových balíčků ve formátu TSV/CSV', 'S'),
('page_service_logbook', 'Provozní deník (service_logbook)', 'Přehled historie provedených upgradů databáze a importů systémových dávek', 'S'),
('page_change_user_context', 'Změna kontextu uživatele', 'Přepínání aktivní organizace, aplikační role a žádosti o přístup', 'U'),
('page_login', 'Přihlášení do systému', 'Přihlašovací obrazovka s podporou lokální autentizace a SSO', 'U'),
('page_password_reset', 'Obnova hesla', 'Stránka pro vyžádání a nastavení nového hesla pomocí tokenu', 'U'),
('page_google_callback', 'Google SSO Callback', 'Koncový bod pro ověření identity přes Google OAuth', 'U'),
('page_logout', 'Odhlášení ze systému', 'Ukončení relace a zneplatnění přihlašovacích tokenů', 'U');

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
GO