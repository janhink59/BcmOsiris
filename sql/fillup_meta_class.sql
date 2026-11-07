/* =============================================================================
 * Verze: 2026-11-07 12:45
 * Soubor: fillup_meta_class.sql
 * Účel:   Hromadné idempotentní nastavení výchozích českých textů (jazyk 'cs')
 *         pro systémové logické třídy v tabulce meta_class (object_owner = 0x00).
 *         Nastavuje hlavní záznamy typu 'A' (a synchronizuje symetrické 'L' pro 'cs')
 *         u všech záznamů s who_modified = 0x00 nebo date_modified < '2026-11-01'.
 * Vazby:  - Vyžaduje tabulku meta_class a funkci dbo.f_generate_original.
 *         - Automaticky zařazeno v BuildListDb.txt přes masku fillup_*.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.p_fix_meta_column', 'P') IS NOT NULL
BEGIN
	EXEC dbo.p_fix_meta_column;
END
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @cls_cs TABLE (
	class_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption varchar(200) NOT NULL,
	caption_plural varchar(200) NOT NULL,
	description varchar(max) NOT NULL,
	helptext varchar(max) NOT NULL
);

INSERT INTO @cls_cs (class_name, caption, caption_plural, description, helptext) VALUES
-- 1. Systémové metadatové třídy
('sys_global_columns',        'Globální slovník sloupců',               'Globální definice sloupců',              'Centrální katalog výchozích vlastností a překladů databázových sloupců, ze kterého dědí sloupce jednotlivých tříd.', 'Sloupce jednotlivých tříd přebírají své výchozí popisky, šířky a chování z tohoto globálního slovníku.'),
('meta_object',               'Systémový objekt',                       'Systémové objekty',                      'Registr fyzických tabulek, pohledů, funkcí, aplikačních stránek a UI tříd systému.', 'Definuje fyzické úložiště pro logické třídy a řízení přístupu ke stránkám aplikace podle systémové role.'),
('meta_class',                'Logická třída (Objekt)',                 'Logické třídy (Objekty)',                'Definice logických entit systému nad fyzickými tabulkami s podporou dědičnosti (STI) a správy koše.', 'Zde můžete upravit zobrazované názvy tříd, dobu uchování smazaných záznamů v koši a výchozí ikonu.'),
('meta_column',               'Sloupec metadat',                        'Sloupce metadat',                        'Definice vlastností, popisků, formulářových prvků a vazeb jednotlivých sloupců logických tříd.', 'Umožňuje přizpůsobit popisky polí ve formulářích, záhlaví seznamů, nápovědu a pořadí zobrazení.'),
('meta_menu',                 'Položka menu (Navigace)',                'Položky menu (Navigace)',                'Stromová struktura hlavní aplikační navigace a rozcestníků s řízením přístupu podle rolí.', 'Určuje hierarchii menu, cílové stránky, ikony a oprávnění pro zobrazení navigačních položek.'),
('meta_phrase',               'Textová fráze',                          'Textové fráze a překlady',               'Katalog lokalizovatelných textových frází, popisků tlačítek, zpráv a šablon s podporou proměnných.', 'Slouží k překladu uživatelského rozhraní, tlačítek a systémových hlášení do podporovaných jazyků.'),
('meta_codetable',            'Položka systémového číselníku',          'Systémové číselníky',                    'Univerzální úložiště pevných systémových a metodických výčtových číselníků pro rozevírací seznamy.', 'Obsahuje položky pevných výčtových číselníků odkazovaných ze sloupců metadat.'),
('meta_link_def',             'Definice typu vazby',                    'Definice typů vazeb',                    'Katalog povolených typů relací a vazeb M:N mezi logickými třídami v tabulce link.', 'Určuje, které třídy lze mezi sebou propojovat, zda je vazba povinná, vícenásobná nebo omezená na koncové listy.'),
('meta_original_keys',        'Klíč deterministického originálu',       'Klíče deterministických originálů',      'Registr klíčových sloupců tabulek, ze kterých se počítá deterministický identifikátor original.', 'Technická tabulka určující složky MD5 hashe pro výpočet identifikátoru original v triggerech trgo_.'),

-- 2. Organizace, licence, uživatelé a relace
('organization',              'Organizace',                             'Organizace',                             'Kmenová evidence organizací (tenantů) včetně fakturačních, regionálních a metodických parametrů CRMM.', 'Správa identifikačních údajů organizace, formátování měn a dat a výpočtových limitů hodnocení rizik.'),
('organization_licence',      'Licence organizace',                     'Licence organizací',                     'Evidence licencí organizací, licenčních úrovní, stavů aktivace a výchozích správcovských účtů.', 'Slouží k založení a aktivaci nové organizace, nastavení úrovně licence (Demo až Developer) a případné blokaci přihlášení.'),
('organization_unit',         'Organizační jednotka',                   'Organizační jednotky',                   'Číselník vnitřních organizačních útvarů a oddělení v rámci organizace.', 'Evidence organizační struktury tenanta.'),
('licence_level',             'Úroveň licence',                         'Úrovně licencí',                         'Statický číselník licenčních úrovní systému (Demo, Standard, Expert, Custom, Enterprise, Developer).', 'Určuje rozsah dostupných funkcí a oprávnění licencované organizace.'),
('language',                  'Jazyk aplikace',                         'Podporované jazyky',                     'Číselník jazyků podporovaných v aplikaci včetně pořadí fallbacku a garantující překladatelské organizace.', 'Definuje dostupné jazykové mutace uživatelského rozhraní a dat.'),
('user_account',              'Uživatelský účet',                       'Uživatelské účty',                       'Globální evidence identit uživatelů, přihlašovacích údajů, kontaktních informací a systémových rolí.', 'Obsahuje osobní a autentizační údaje uživatele platné napříč všemi organizacemi.'),
('user_organization_access',  'Přístup uživatele do organizace',        'Uživatelé organizace a přístupy',        'Vazební evidence oprávnění, organizačního zařazení a pracovního nastavení uživatelů v konkrétní organizaci.', 'Řídí členství uživatele v organizaci, roli administrátora, právo překladu, oddělení, pozici a pracovní datum.'),
('audit_login_session',       'Záznam přihlášení a aktivity',           'Historie přihlášení a aktivity',         'Forenzní auditní protokol přihlášení uživatelů, zvolených rolí, IP adres a doby trvání relací.', 'Slouží ke kontrole aktivity uživatelů a jako neměnný základ pro auditní stopu vytvoření a úprav záznamů.'),
('auth_tokens',               'Token trvalého přihlášení',              'Tokeny trvalého přihlášení',             'Bezpečné úložiště dlouhodobých autentizačních tokenů (Remember Me) podle vzoru Selector & Validator.', 'Technická tabulka spravující aktivní trvalá přihlášení prohlížečů.'),
('activation_token',          'Jednorázový bezpečnostní token',         'Jednorázové bezpečnostní tokeny',        'Evidence jednorázových kryptografických tokenů pro obnovu hesla, aktivaci účtu a dvoufaktorové ověření.', 'Technická tabulka pro ověřování časově omezených bezpečnostních odkazů.'),
('wwwsession',                'Webová relace uživatele',                'Aktivní webové relace',                  'Sdílená tabulka aktivních přihlašovacích relací prohlížečů (session_id) s kontextem organizace a role.', 'Uchovává stav přihlášeného uživatele mezi jednotlivými HTTP požadavky.'),
('dbsession',                 'Databázová relace procesu',              'Databázové relace procesů',              'Kontext právě běžícího databázového požadavku navázaný na @@SPID v SQL Serveru.', 'Zajišťuje předání identity uživatele, organizace, jazyka a role do uložených procedur a funkcí.'),

-- 3. Katalogové a věcné třídy modulu CRMM
('asset_class',               'Třída aktiv',                            'Třídy aktiv',                            'Hierarchický katalog tříd a kategorií aktiv určující strukturu evidence aktiv a dědění hrozeb.', 'Složky (is_leaf = 0) slouží k logickému členění a dědění vazeb; do koncových tříd (is_leaf = 1) se zařazují konkrétní aktiva.'),
('threat',                    'Hrozba',                                 'Katalog hrozeb',                         'Hierarchický katalog hrozeb s možností nastavení výchozího skóre velikosti hrozby.', 'Evidence fyzických, technických, kybernetických a organizačních hrozeb působících na aktiva.'),
('impact',                    'Dopad',                                  'Katalog dopadů',                         'Hierarchický katalog druhů a oblastí dopadů pro hodnocení následků rizikových scénářů.', 'Kombinuje oblasti a stupně dopadů (např. výpadek služeb, finanční škoda, prozrazení dat).'),
('scenario',                  'Rizikový scénář',                        'Rizikové scénáře',                       'Hierarchický katalog rizikových scénářů (událostí) propojujících hrozbu, třídu aktiv a mez reziduálního rizika.', 'Definuje hodnotitelné rizikové události a minimální skóre, pod které nemůže klesnout zbytkové riziko.'),
('countermeasure',            'Protiopatření',                          'Katalog protiopatření',                  'Hierarchický katalog bezpečnostních, technických a organizačních opatření s redukčním a rizikovým faktorem.', 'Obsahuje opatření ke snížení rizika scénářů a prahový rizikový faktor při neimplementaci.'),
('countermeasure_state',      'Stav protiopatření',                     'Stavy protiopatření',                    'Číselník stavů implementace protiopatření určující míru započtení redukčního a rizikového faktoru.', 'Definuje stavy zavedení opatření (např. Navrženo, V realizaci, Zavedeno, Neaplikovatelné) a jejich váhy v procentech.'),
('scale',                     'Hodnotící škála',                        'Hodnotící škály',                        'Definice hodnotících škál pro hrozby, zranitelnosti, dopady a výsledná rizika v modulu CRMM.', 'Umožňuje definovat primární škály pro zadávání (priorita 0) i převodní škály pro reportování.'),
('scale_value',               'Stupeň hodnotící škály',                 'Stupně hodnotících škál',                'Jednotlivé stupně hodnotících škál s dolní prahovou hodnotou a výpočtovým skóre v intervalu 0 až 100 %.', 'Stupně jsou řazeny vzestupně podle dolního prahu (threshold_value) a musí tvořit monotónně rostoucí řadu.'),
('hierarchy',                 'Sekundární hierarchie / sada štítků',    'Sekundární hierarchie a štítky',         'Registr uživatelských klasifikačních stromů, výčtových číselníků a sad štítků (tagů).', 'Každá koncová hierarchie (is_leaf = 1) představuje samostatný klasifikační číselník nebo strom štítků.'),
('hierarchy_item',            'Položka sekundární hierarchie',          'Položky sekundární hierarchie',          'Uzly a koncové položky jednotlivých sekundárních hierarchií, klasifikačních číselníků a štítků.', 'Stromový seznam hodnot patřících do vybrané sekundární hierarchie nebo sady štítků.'),
('link',                      'Vazba mezi objekty',                     'Vazby mezi objekty',                     'Univerzální tabulka uživatelských i hierarchicky zděděných vazeb M:N mezi záznamy entit.', 'Uchovává přímé vazby (ancestor_link = 0x00) i vazby automaticky zmaterializované děděním po stromu.'),
('asset',                     'Aktivum',                                'Evidence aktiv',                         'Evidence konkrétních primárních a podpůrných aktiv organizace zařazených do koncových tříd aktiv.', 'Hlavní katalog aktiv organizace, nad kterými se provádí analýza a hodnocení rizik.'),
('scenario_assessment',       'Hodnocení rizikového scénáře',           'Hodnocení rizikových scénářů',           'Vyhodnocení velikosti hrozby, zranitelnosti, dopadu a míry rizika scénářů nad konkrétními aktivy.', 'Evidence inherentního a zbytkového rizika jednotlivých scénářů na aktivech organizace.'),
('countermeasure_implementation', 'Implementace protiopatření',         'Implementace protiopatření',             'Evidence stavu zavedení jednotlivých bezpečnostních protiopatření u konkrétních aktiv.', 'Sleduje skutečný stav implementace opatření na aktivech a jeho vliv na snížení zbytkového rizika.'),

-- 4. Servisní, importní a pomocné tabulky, pohledy a funkce
('system_constant',           'Systémové konstanty',                    'Systémové konstanty',                    'Globální technická konfigurace databáze, verze schématu, poštovního serveru SMTP a zálohování.', 'Singleton tabulka s technickými parametry instance systému.'),
('service_logbook',           'Záznam provozního deníku',               'Provozní deník (service_logbook)',       'Chronologická evidence provedených upgradů databáze (changes_YYYY.sql), importů metadat a údržby koše.', 'Slouží ke kontrole historie servisních zásahů a verzí databáze.'),
('request_message',           'Zpráva zpracování požadavku',            'Zprávy zpracování požadavku',            'Dočasná fronta stavových, varovných a chybových zpráv vygenerovaných během běhu SQL procedur.', 'Zprávy vázané na @@SPID pro zobrazení výsledku operace uživateli.'),
('request_variable',          'Proměnná požadavku',                     'Proměnné požadavku',                     'Dočasné úložiště návratových proměnných mezi uloženými procedurami v rámci jednoho @@SPID.', 'Technická tabulka pro předávání hodnot uvnitř databázové relace.'),
('session_import_parameter',  'Parametr CSV importu',                   'Parametry CSV importu',                  'Pracovní tabulka hlavičkových a řídicích parametrů načteného CSV/TSV balíčku v 1. fázi importu.', 'Dočasné staging úložiště parametrů vázané na relaci uživatele.'),
('session_import_table',      'Tabulka CSV importu',                    'Tabulky CSV importu',                    'Seznam datových bloků (tabulek) a počtů řádků načtených ze vstupního CSV/TSV souboru.', 'Dočasné staging úložiště seznamu tabulek v 1. fázi importu.'),
('session_import_column',     'Sloupec CSV importu',                    'Sloupce CSV importu',                    'Seznam názvů sloupců jednotlivých tabulek načtených ze vstupního CSV/TSV souboru.', 'Dočasné staging úložiště struktury sloupců v 1. fázi importu.'),
('session_import_data',       'Hodnota buňky CSV importu',              'Data buněk CSV importu',                 'Hodnoty neprázdných buněk načtených ze vstupního CSV/TSV souboru před spuštěním 2. fáze importu.', 'Dočasné staging úložiště datových buněk vázané na relaci uživatele.'),
('rowgenerator',              'Generátor řádků',                        'Generátor řádků (0..1024)',              'Pomocná číselná tabulka obsahující sekvenci čísel 0 až 1024 pro množinové operace.', 'Systémová tabulka knihovny HinkMSSQLLibrary.'),
('v_user_organization_access','Pohled přístupů uživatelů',              'Pohled přístupů uživatelů k organizacím','Rozšířený pohled propojující přístupy uživatelů s organizacemi, úrovní licence a stavem účtu.', 'Systémový pohled využívaný při přihlašování a změně kontextu.'),
('v_syscolumns',              'Systémový pohled sloupců DB',            'Systémový pohled sloupců DB',            'Přehled sloupců všech tabulek, pohledů a funkcí v databázi včetně datových typů a constraintů.', 'Systémový katalogový pohled knihovny HinkMSSQLLibrary.'),
('v_sysprimarykeys',          'Systémový pohled primárních klíčů',      'Systémový pohled primárních klíčů',      'Přehled sloupců tvořících primární klíče jednotlivých tabulek databáze.', 'Systémový katalogový pohled knihovny HinkMSSQLLibrary.'),
('v_sysindexcolumns',         'Systémový pohled sloupců indexů',        'Systémový pohled sloupců indexů',        'Přehled všech indexů a jejich klíčových i inkludovaných sloupců v databázi.', 'Systémový katalogový pohled knihovny HinkMSSQLLibrary.'),
('f_language_list',           'Funkce seznamu jazyků s fallbackem',     'Seznam jazyků s pořadím dědičnosti',     'Tabulková funkce vracející podporované jazyky seřazené podle řetězce dědičnosti (fallback_order).', 'Určuje pořadí prohledávání jazykových mutací pro aktuální relaci.'),
('f_resolve_hierarchy',       'Funkce výpočtu stromové hierarchie',     'Výpočet stromové hierarchie',            'Tabulková funkce pro seřazení stromové struktury, výpočet úrovně zanoření a lexikografického kódu.', 'Zajišťuje průchod stromem od kořenů k listům a detekci sirotků.'),
('f_syscolumns',              'Funkce sloupců tabulky',                 'Sloupce zadané tabulky',                 'Tabulková funkce vracející metadata sloupců pro zadanou trvalou nebo dočasnou (#temp) tabulku.', 'Využívána při dynamickém skládání SQL dotazů a exportů.'),
('f_string_list',             'Funkce rozkladu seznamu textů',          'Rozklad seznamu textů',                  'Tabulková funkce převádějící čárkami oddělený řetězec na tabulku oříznutých textových položek.', 'Pomocná parsovací funkce knihovny HinkMSSQLLibrary.'),
('f_integer_list',            'Funkce rozkladu seznamu čísel',          'Rozklad seznamu celých čísel',           'Tabulková funkce převádějící čárkami oddělený seznam celých čísel na tabulku hodnot bigint.', 'Pomocná parsovací funkce knihovny HinkMSSQLLibrary.'),
('f_uuid_list',               'Funkce rozkladu seznamu UUID',           'Rozklad seznamu identifikátorů UUID',    'Tabulková funkce převádějící čárkami oddělený seznam GUIDů na tabulku hodnot uniqueidentifier.', 'Pomocná parsovací funkce knihovny HinkMSSQLLibrary.');

-- 1. Hromadný UPDATE hlavních záznamů (record_type = 'A', language = 'cs')
UPDATE mc
SET mc.caption = s.caption,
	mc.caption_plural = s.caption_plural,
	mc.description = s.description,
	mc.helptext = s.helptext,
	mc.[language] = 'cs',
	mc.who_modified = @sys_owner,
	mc.date_modified = GETDATE()
FROM meta_class mc
JOIN @cls_cs s ON s.class_name = mc.class_name
WHERE mc.object_owner = @sys_owner
  AND mc.record_type = 'A'
  AND (mc.who_modified = @sys_owner OR mc.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT mc.caption, mc.caption_plural, mc.description, mc.helptext, mc.[language]
	EXCEPT
	SELECT s.caption, s.caption_plural, s.description, s.helptext, 'cs'
  );

-- 2. Hromadný UPDATE existujících symetrických 'L' záznamů pro češtinu (language = 'cs')
UPDATE l
SET l.caption = s.caption,
	l.caption_plural = s.caption_plural,
	l.description = s.description,
	l.helptext = s.helptext,
	l.who_modified = @sys_owner,
	l.date_modified = GETDATE()
FROM meta_class l
JOIN meta_class a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
JOIN @cls_cs s ON s.class_name = a.class_name
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'cs'
  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT l.caption, l.caption_plural, l.description, l.helptext
	EXCEPT
	SELECT s.caption, s.caption_plural, s.description, s.helptext
  );

-- 3. Doplnění chybějících symetrických 'L' záznamů pro češtinu (language = 'cs')
INSERT INTO meta_class (
	uuid, object_owner, original, record_type, approval_status, [language],
	class_name, storage_object, ancestor_class, sort_code, days_in_trash, svg_icon,
	caption, caption_plural, description, helptext,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
	a.class_name, a.storage_object, a.ancestor_class, a.sort_code, a.days_in_trash, a.svg_icon,
	s.caption, s.caption_plural, s.description, s.helptext,
	a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_class a
JOIN @cls_cs s ON s.class_name = a.class_name
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_class l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
  );
GO