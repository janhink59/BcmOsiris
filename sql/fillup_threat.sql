/* =============================================================================
 * Verze: 2026-11-20 09:55
 * Soubor: fillup_threat.sql
 *
 * 1. Role souboru v celém systému:
 *    Prvotní idempotentní naplnění systémového stromového katalogu hrozeb
 *    (tabulka threat, object_owner = 0x00, jazyk 'cs', záznamy 'A' a symetrické
 *    'L'). Obsahuje 9 hierarchických složek (is_leaf = 0) a 41 koncových hrozeb
 *    (is_leaf = 1, celkem 50 uzlů) pokrývajících 100 % původního katalogu
 *    CRAMM (external_code = 'CRAMM-*') i moderní hrozby ISO 27005 / NIS2.
 *    Osiřelé systémové záznamy (object_owner = 0x00 AND who_modified = 0x00)
 *    mimo aktuální sadu jsou automaticky odstraněny.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Využívá funkci dbo.f_generate_original (f_generate_original.sql)
 *      a proceduru dbo.p_sync_derived_links (p_sync_derived_links.sql).
 *    - Zapisuje do tabulky threat (table_threat.sql).
 *    - Navazuje překladový skript fillup_threat_en.sql a stránka page_threat.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      systémovými záznamy (object_owner = 0x00) bez závislosti na dbsession.
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('threat', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @now datetime = GETDATE();

	DECLARE @src TABLE (
		builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		parent_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		sort_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		is_leaf bit NOT NULL,
		default_threat_score decimal(9,4) NOT NULL,
		external_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @src (
		builtin_code, parent_code, sort_code, is_leaf, default_threat_score, external_code,
		shortname, caption, description_text, help_text
	) VALUES
	('thr_cyber_ddos','thr_grp_cyber_mal_comm','030',1,50.0000,'CRAMM-65-DOS','DDoS útok','Zahlcení služby nebo sítě (DoS / DDoS)','Cílené zahlcení síťové konektivity, firewallu nebo aplikačního serveru velkým množstvím požadavků.','Ohrožuje dostupnost externě publikovaných služeb, portálů a komunikačních rozhraní.'),
	('thr_cyber_exfiltration','thr_grp_cyber_access','060',1,50.0000,'ISO27005-C.4','Únik a exfiltrace dat','Neoprávněný přístup a exfiltrace citlivých dat','Získání neoprávněného přístupu k databázím, úložištím nebo dokumentům s cílem odcizení či zveřejnění citlivých dat.','Vede k porušení důvěrnosti, postihům dle GDPR/NIS2 a poškození pověsti.'),
	('thr_cyber_infiltration','thr_grp_cyber_access','010',1,60.0000,'CRAMM-65','Infiltrace / Hacking','Infiltrace systému a zneužití zranitelnosti (Hacking / Exploit)','Průnik do sítě, serveru nebo aplikace zneužitím technické zranitelnosti, chybné konfigurace nebo podvržení serveru.','Primární vektor kybernetických útoků ohrožující důvěrnost, integritu i dostupnost.'),
	('thr_cyber_interception','thr_grp_cyber_mal_comm','040',1,40.0000,'CRAMM-67','Odposlech komunikace','Zachycení a odposlech síťové komunikace (Interception)','Neoprávněné zachycení dat přenášených po síti, bezdrátovém spoji nebo komunikačním rozhraní.','Ohrožuje důvěrnost nešifrované komunikace, přihlašovacích údajů a citlivých přenosů.'),
	('thr_cyber_malware','thr_grp_cyber_mal_comm','010',1,70.0000,'CRAMM-50,87','Malware / Ransomware','Škodlivý kód, viry a šifrovací útok (Malware / Ransomware)','Infiltrace škodlivého kódu (viry, trojské koně, ransomware) přes síť, e-mail nebo média s cílem zašifrování či zničení dat.','Kritická hrozba pro dostupnost IT infrastruktury a integritu podnikových dat.'),
	('thr_cyber_manipulation','thr_grp_cyber_mal_comm','050',1,40.0000,'CRAMM-72','Manipulace komunikace','Manipulace dat při přenosu (Man-in-the-Middle / Tampering)','Úmyslná změna, podvržení nebo přerušení přenášených zpráv a transakcí na komunikační trase.','Ohrožuje integritu transakcí, příkazů a přenášených dokumentů.'),
	('thr_cyber_masquerade_csp','thr_grp_cyber_access','030',1,30.0000,'CRAMM-20','Falšování identity (CSP)','Falšování identity nebo zneužití práv smluvním dodavatelem (CSP)','Vydávání se za oprávněného uživatele nebo zneužití servisních účtů ze strany smluvního poskytovatele služeb.','Vyžaduje striktní řízení, schvalování a audit vzdálených přístupů třetích stran.'),
	('thr_cyber_masquerade_ext','thr_grp_cyber_access','020',1,50.0000,'CRAMM-30','Falšování identity (Cizí)','Falšování identity uživatele externí osobou (Outsiders)','Převzetí uživatelského nebo administrátorského účtu cizí osobou pomocí ukradených přihlašovacích údajů či relace.','Riziko snižuje vícefaktorové ověřování (MFA) a detekce anomálií přihlášení.'),
	('thr_cyber_masquerade_int','thr_grp_cyber_access','040',1,30.0000,'CRAMM-10','Falšování identity (Interní)','Falšování identity jiného uživatele interní osobou (Insiders)','Využití cizího neuzamčeného pracoviště, sdíleného hesla nebo přihlašovacích údajů kolegy k provedení neoprávněné akce.','Zkresluje auditní stopu a umožňuje obcházení principu oddělení rolí (SoD).'),
	('thr_cyber_phishing','thr_grp_cyber_access','070',1,70.0000,'ISO27005-C.2','Phishing / Soc. inženýrství','Phishing, podvržení komunikace a sociální inženýrství','Manipulace zaměstnanců pomocí podvodných e-mailů, zpráv nebo telefonátů s cílem získat přihlašovací údaje či schválit podvodnou transakci.','Nejčastější vstupní vektor pro ransomware nebo kompromitaci účtů.'),
	('thr_cyber_repudiation','thr_grp_cyber_mal_comm','060',1,30.0000,'CRAMM-77','Odmítnutí odpovědnosti','Odmítnutí odpovědnosti za provedenou operaci nebo zprávu (Repudiation)','Popření odeslání, přijetí nebo schválení elektronické zprávy či transakce při chybějícím průkazném záznamu.','Kritické pro finanční, smluvní a schvalovací systémy bez elektronického podpisu a nezměnitelných logů.'),
	('thr_cyber_supply_chain','thr_grp_cyber_mal_comm','020',1,40.0000,'NIS2-SC','Kompromitace SW řetězce','Kompromitace dodavatelského řetězce SW a aktualizací (Supply Chain)','Zanesení škodlivého kódu do knihoven třetích stran, instalačních balíčků, repozitářů nebo aktualizací softwaru.','Postihuje jak vlastní vývoj softwaru, tak nakupovaný komerční a open-source software.'),
	('thr_cyber_unauth_app_use','thr_grp_cyber_access','050',1,40.0000,'CRAMM-40','Neoprávněné použití aplikace','Neoprávněné použití aplikace pod vlastním účtem','Provedení podvodné, neoprávněné nebo nadbytečné operace v aplikaci legitimním uživatelem s využitím jeho vlastního účtu.','Zásadní rozdíl oproti falšování identity: pachatel jedná pod svým účtem (zneužití nepřiměřených práv).'),
	('thr_grp_cyber','','030',0,0.0000,'THREAT-CYBER','Kybernetické útoky','Kybernetické, komunikační a logické útoky','Úmyslné externí, komunikační a logické útoky vedené na informační systémy, sítě a aplikace.','Nadřazená složka pro průniky, falšování identity, malware, DDoS a útoky na komunikaci.'),
	('thr_grp_cyber_access','thr_grp_cyber','010',0,0.0000,'THREAT-CYBER-ACC','Průniky a zneužití přístupu','Průniky, falšování identity a neoprávněný přístup','Útoky zaměřené na prolomení autentizace, zneužití účtů, phishing a neoprávněnou práci s aplikacemi či daty.','Složka pokrývající hrozby přístupu a identity ze strany cizích osob, dodavatelů i interních pracovníků.'),
	('thr_grp_cyber_mal_comm','thr_grp_cyber','020',0,0.0000,'THREAT-CYBER-COM','Malware, DDoS a komunikace','Škodlivý kód, DDoS a útoky na komunikaci a dodavatelský řetězec','Hrozby malware, ransomware, kompromitace SW řetězce, zahlcení služeb a útoky na přenosovou vrstvu.','Složka pokrývající škodlivý kód a bezpečnost přenášených dat.'),
	('thr_grp_human','','040',0,0.0000,'THREAT-HUMAN','Lidský faktor a chyby','Lidský faktor, chyby obsluhy, údržby a nedostatek personálu','Neúmyslné chyby uživatelů, administrátorů a servisu HW/SW, zneužití firemních prostředků a nedostatek klíčových pracovníků.','Složka hrozeb souvisejících s pracovníky, údržbou a zastupitelností personálu.'),
	('thr_grp_org','','050',0,0.0000,'THREAT-ORG','Dodavatelé a procesy','Organizační, dodavatelské a právní hrozby','Selhání třetích stran, výpadky dodavatelů a operátorů, porušení legislativních požadavků a procesní selhání.','Složka hrozeb pokrývající dodavatelský řetězec, telekomunikační operátory, compliance a řízení změn.'),
	('thr_grp_phys','','010',0,0.0000,'THREAT-PHYS','Fyzické a živelní','Fyzické, živelní a environmentální hrozby','Živelní pohromy, výpadky inženýrských sítí, fyzické krádeže, vandalismus a cílená fyzická sabotáž.','Nadřazená složka hrozeb působících na lokality, budovy, místnosti a fyzickou techniku.'),
	('thr_grp_phys_act','thr_grp_phys','020',0,0.0000,'THREAT-PHYS-ACT','Krádež, vandalismus, sabotáž','Fyzické vniknutí, krádež, úmyslné poškození a sabotáž','Úmyslné fyzické činy proti majetku a prostorům organizace ze strany cizích i interních osob.','Složka oddělující krádež (důvěrnost + dostupnost) od fyzického poškození a terorismu (dostupnost).'),
	('thr_grp_phys_env','thr_grp_phys','010',0,0.0000,'THREAT-PHYS-ENV','Živelní a prostředí','Živelní pohromy, požár, voda a selhání napájení či chlazení','Přírodní a environmentální jevy a výpadky klíčových inženýrských sítí budov a serveroven.','Složka pro požár, vodu, přírodní katastrofy, výpadky elektřiny a klimatizace.'),
	('thr_grp_tech','','020',0,0.0000,'THREAT-TECH','Technická selhání','Technická selhání HW, sítí a softwaru','Neúmyslné poruchy výpočetního a síťového HW, úložišť, síťových služeb, systémového i aplikačního SW a vyčerpání kapacity.','Složka technických a provozních závad bez účasti úmyslného útočníka.'),
	('thr_hum_hw_maint_err','thr_grp_human','030',1,40.0000,'CRAMM-250','Chyba údržby HW','Chyba při údržbě nebo servisu hardwaru (HW Maintenance Error)','Poškození, chybné zapojení nebo neúmyslné odpojení funkčního hardwaru či napájení během servisního zásahu.','Vyskytuje se při výměně komponent, údržbě serveroven, UPS nebo kabeláže.'),
	('thr_hum_misuse_res','thr_grp_human','050',1,40.0000,'CRAMM-60','Zneužití prostředků / Shadow IT','Zneužití systémových prostředků organizace (Misuse / Shadow IT)','Nepracovní nebo neschválené využívání IT vybavení, internetu, licencí, cloudu či vývojových nástrojů zaměstnanci.','Zvyšuje náklady, právní rizika a vytváří nekontrolovaný povrch útoku (Shadow IT).'),
	('thr_hum_ops_err','thr_grp_human','020',1,50.0000,'CRAMM-240','Provozní chyba / Admin','Provozní chyba obsluhy nebo administrátora (Operations Error)','Smazání produkční databáze, chybný zásah v provozu, vypnutí bezpečnostní kontroly nebo selhání rutinní obsluhy záloh.','Může způsobit okamžitý plošný výpadek nebo neúmyslné zpřístupnění dat.'),
	('thr_hum_staff_shortage','thr_grp_human','060',1,50.0000,'CRAMM-310','Nedostatek personálu','Nedostatek personálu nebo výpadek klíčového specialisty','Náhlá nemoc, úraz, stávka nebo odchod pracovníků s unikátním know-how bez zajištěné zastupitelnosti a dokumentace.','Ohrožuje nepřetržitost provozu, obnovy a údržby klíčových aplikací a procesů.'),
	('thr_hum_sw_maint_err','thr_grp_human','040',1,50.0000,'CRAMM-260','Chyba údržby SW','Chyba při údržbě, konfiguraci nebo nasazení softwaru (SW Maintenance Error)','Zanesení chyby při aktualizaci, chybná úprava konfiguračních souborů, bezpečnostní chyba v kódu nebo poškození databázového schématu.','Vede k výpadku služeb, nekonzistenci dat nebo vzniku zranitelností.'),
	('thr_hum_user_err','thr_grp_human','010',1,70.0000,'CRAMM-270','Chyba uživatele','Neúmyslná chyba koncového uživatele (User Error)','Chybné zadání či přepsání dat, omylem smazaný soubor nebo odeslání citlivého dokumentu nesprávnému adresátovi.','Nejčastější provozní hrozba ovlivňující integritu a důvěrnost dat.'),
	('thr_org_compliance','thr_grp_org','030',1,30.0000,'ISO27005-O.3','Nesoulad se zákony a licencemi','Porušení zákonných, regulatorních, licenčních nebo smluvních povinností','Nedodržení požadavků kybernetické bezpečnosti (NIS2), ochrany osobních údajů (GDPR), softwarových licencí nebo SLA.','Vede k finančním sankcím, kontrolám regulátora a ztrátě důvěry klientů.'),
	('thr_org_isp_outage','thr_grp_org','020',1,50.0000,'CRAMM-82-ISP','Výpadek ISP / operátora','Výpadek poskytovatele internetu nebo telekomunikací (ISP)','Přerušení externí datové, hlasové nebo cloudové konektivity na straně telekomunikačního operátora.','Odřízne pobočky, vzdálené pracovníky i publikované služby od zákazníků.'),
	('thr_org_process_fail','thr_grp_org','040',1,40.0000,'ISO27005-O.4','Selhání řízení změn / procesů','Selhání interního procesu nebo neřízená změna','Neotestovaná změna v produkci, chybějící odpovědnost, chybějící řízení instalací nebo neaktuální havarijní postupy.','Zvyšuje dobu výpadku a pravděpodobnost řetězení chyb při incidentu.'),
	('thr_org_supplier_outage','thr_grp_org','010',1,50.0000,'ISO27005-O.1','Výpadek dodavatele','Výpadek nebo ukončení podpory klíčového dodavatele','Nedostupnost externě zajišťované služby, SaaS platformy, servisní podpory nebo zánik dodavatele SW/HW.','Kritické zejména u dodavatelů bez alternativního řešení (Vendor Lock-in).'),
	('thr_phys_damage_ext','thr_grp_phys_act','030',1,30.0000,'CRAMM-350','Poškození / Vandalismus (Cizí)','Úmyslné fyzické poškození nebo vandalismus cizí osobou (Outsiders)','Úmyslné zničení nebo poškození budovy, kabeláže, techniky či zařízení externím pachatelem bez cíle odcizení.','Ohrožuje primárně dostupnost prostorů, kabeláže a fyzické infrastruktury.'),
	('thr_phys_damage_int','thr_grp_phys_act','040',1,20.0000,'CRAMM-340','Poškození / Sabotáž (Interní)','Úmyslné fyzické poškození nebo sabotáž interní osobou (Insiders)','Záměrné zničení techniky, serverů, zálohovacích médií nebo dokumentů nespokojeným či odcházejícím zaměstnancem.','Vyžaduje kontrolu fyzického vstupu do serveroven a důsledné odebírání přístupových karet.'),
	('thr_phys_disaster','thr_grp_phys_env','030',1,20.0000,'CRAMM-300','Přírodní katastrofa / Havárie','Přírodní katastrofa nebo vnější průmyslová / dopravní havárie','Plošná živelná pohroma (vichřice, zemětřesení, extrémní bouře) nebo vnější havárie (únik chemikálií, pád letadla) postihující celou lokalitu.','Vyřadí celou budovu či lokalitu z provozu; vyžaduje záložní lokalitu (DR site).'),
	('thr_phys_fire','thr_grp_phys_env','010',1,30.0000,'CRAMM-280','Požár / Kouř','Požár nebo zakouření v budově či serverovně','Vznik požáru v důsledku zkratu elektroinstalace, přehřátí technologie nebo vznícení materiálu.','Způsobuje destrukci HW, kabeláže, listinných dokumentů a dlouhodobou nedostupnost prostor.'),
	('thr_phys_hvac','thr_grp_phys_env','050',1,50.0000,'CRAMM-210','Selhání klimatizace','Výpadek chlazení a klimatizace technologické místnosti','Porucha klimatizační jednotky v serverovně vedoucí k rychlému přehřátí a nouzovému odstavení serverů.','Častá příčina vynucené odstávky IT techniky v letních měsících.'),
	('thr_phys_power','thr_grp_phys_env','040',1,50.0000,'CRAMM-200','Výpadek elektřiny','Dlouhodobý výpadek elektrického napájení','Přerušení dodávky elektrické energie z distribuční sítě přesahující kapacitu záložních zdrojů (UPS).','Postihuje veškerou techniku, osvětlení, klimatizaci i přístupové systémy v budově.'),
	('thr_phys_terrorism','thr_grp_phys_act','050',1,10.0000,'CRAMM-360','Terorismus / Sabotáž','Terorismus, výbuch nebo cílená fyzická sabotáž objektu','Závažný úmyslný fyzický útok na budovu, datové centrum nebo kritickou technickou infrastrukturu organizace.','Může vyřadit celou lokalitu z provozu a vyžaduje geograficky oddělenou obnovu.'),
	('thr_phys_theft_ext','thr_grp_phys_act','010',1,30.0000,'CRAMM-330','Krádež (Cizí osoby)','Krádež vybavení, médií nebo dokumentů cizí osobou (Outsiders)','Vniknutí nepovolané externí osoby do objektu nebo krádež přenosné techniky na cestách s cílem odcizení majetku či dat.','Ohrožuje dostupnost techniky i důvěrnost nezašifrovaných disků, médií a listin.'),
	('thr_phys_theft_int','thr_grp_phys_act','020',1,30.0000,'CRAMM-320','Krádež (Interní osoby)','Krádež vybavení, médií nebo dokumentů interní osobou (Insiders)','Odcizení notebooku, záložních médií, instalačních klíčů nebo citlivých spisů osobou s legitimním přístupem do objektu.','Vyžaduje evidenci majetku, šifrování koncových stanic a uzamykání citlivých zón.'),
	('thr_phys_water','thr_grp_phys_env','020',1,30.0000,'CRAMM-290','Poškození vodou / Záplava','Zatečení vody, havárie potrubí nebo povodeň','Vytopení místnosti prasklým vodovodním či topným potrubím, přívalovým deštěm nebo povodní.','Vysoké riziko pro suterénní prostory, serverovny pod rozvody vody a archivy dokumentů.'),
	('thr_tech_app_sw_fail','thr_grp_tech','070',1,60.0000,'CRAMM-230','Selhání aplikačního SW','Selhání nebo chyba aplikačního softwaru','Programová chyba v obchodní logice aplikace, pád aplikační služby, deadlock nebo chybný výpočet po aktualizaci.','Postihuje přímo instalované aplikace (EUS) a integritu zpracovávaných dat.'),
	('thr_tech_capacity','thr_grp_tech','080',1,50.0000,'ISO27005-T.4','Vyčerpání kapacity','Přetížení výpočetní, paměťové nebo diskové kapacity','Zaplnění diskového prostoru (logů, databází), vyčerpání paměti RAM nebo procesorového výkonu.','Způsobuje zamrznutí aplikací, selhání zápisu transakcí a odmítání požadavků uživatelů.'),
	('thr_tech_hw_fail','thr_grp_tech','010',1,60.0000,'CRAMM-120,140,170','Porucha výpočetního HW','Technická porucha serveru, pracovní stanice nebo periferie','Výpadek zdroje, základní desky, procesoru, paměti, tiskového nebo řídicího počítače.','Bez clusteru či redundantního zapojení vede k přímému výpadku hostovaných aplikací.'),
	('thr_tech_misrouting','thr_grp_tech','050',1,30.0000,'CRAMM-100','Chybné směrování','Chybné směrování síťové komunikace nebo zpráv (Mis-routing)','Neúmyslné přesměrování síťového provozu nebo zpráv k neoprávněnému příjemci či do nefunkční sítě.','Může způsobit únik přenášených dat nebo nedostupnost síťové služby.'),
	('thr_tech_net_hw_fail','thr_grp_tech','030',1,50.0000,'CRAMM-150,160,180','Porucha síťového HW / kabeláže','Porucha síťového prvku, brány, rozhraní nebo kabeláže','Technická závada přepínače, směrovače, firewallu, Wi-Fi AP, síťového rozhraní nebo přerušení kabeláže.','Způsobuje izolaci segmentu sítě nebo výpadek komunikace mezi servery a uživateli.'),
	('thr_tech_net_svc_fail','thr_grp_tech','040',1,50.0000,'CRAMM-82,190','Selhání síťové služby / spojení','Selhání interní síťové služby nebo komunikačního spojení','Výpadek DNS, DHCP, VPN tunelu, směrovací služby nebo přenosového rozhraní uvnitř i vně organizace.','Znemožňuje navázání spojení mezi aplikacemi, uživateli a podpůrnými službami.'),
	('thr_tech_storage_fail','thr_grp_tech','020',1,40.0000,'CRAMM-130','Selhání úložiště / média','Selhání diskového pole, média nebo poškození databáze','Vícečetné selhání disků, poškození záložního média, korupce souborového systému nebo databázových stránek.','Ohrožuje dostupnost i integritu klíčových podnikových dat a záloh.'),
	('thr_tech_sys_sw_fail','thr_grp_tech','060',1,50.0000,'CRAMM-220','Selhání systémového SW','Selhání systémového nebo síťového softwaru (OS / DBMS / firmware)','Porucha operačního systému, hypervizoru, databázového stroje nebo firmwaru síťového prvku včetně selhání bezpečnostních funkcí.','Postihuje všechny aplikace a data provozované na daném hostiteli nebo prvku.');

	-- 0. Úklid zastaralých systémových záznamů (0x00, who_modified = 0x00), které již nejsou v @src
	DELETE t
	FROM threat t
	LEFT JOIN @src s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.who_modified = @sys_owner
	  AND t.record_type IN ('A', 'L')
	  AND s.builtin_code IS NULL;

	-- 1. Aktualizace nemodifikovaných 'A' záznamů
	UPDATE t
	SET t.sort_code = s.sort_code,
		t.is_leaf = s.is_leaf,
		t.default_threat_score = s.default_threat_score,
		t.external_code = s.external_code,
		t.shortname = s.shortname,
		t.caption = s.caption,
		t.description_text = s.description_text,
		t.help_text = s.help_text,
		t.[language] = 'cs',
		t.date_modified = @now
	FROM threat t
	JOIN @src s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.record_type = 'A'
	  AND t.who_modified = @sys_owner
	  AND EXISTS (
		SELECT t.sort_code, t.is_leaf, t.default_threat_score, t.external_code, t.shortname, t.caption, t.description_text, t.help_text
		EXCEPT
		SELECT s.sort_code, s.is_leaf, s.default_threat_score, s.external_code, s.shortname, s.caption, s.description_text, s.help_text
	  );

	-- 2. Vložení chybějících 'A' záznamů
	INSERT INTO threat (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, default_threat_score, external_code,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
		s.builtin_code, p.parent_orig, s.sort_code, s.is_leaf, s.default_threat_score, s.external_code,
		s.shortname, s.caption, s.description_text, s.help_text,
		1, 1,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	CROSS APPLY (SELECT dbo.f_generate_original('threat', @sys_owner, s.builtin_code, '') AS orig) x
	OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('threat', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
	WHERE NOT EXISTS (
		SELECT 1 FROM threat t
		WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
	);

	-- Doplnění/sjednocení parent_uuid u nemodifikovaných záznamů
	UPDATE t
	SET t.parent_uuid = p.parent_orig,
		t.date_modified = @now
	FROM threat t
	JOIN @src s ON s.builtin_code = t.builtin_code
	OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('threat', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
	WHERE t.object_owner = @sys_owner
	  AND t.record_type IN ('A', 'L')
	  AND t.who_modified = @sys_owner
	  AND EXISTS (SELECT t.parent_uuid EXCEPT SELECT p.parent_orig);

	-- 3. Synchronizace českých 'L' záznamů
	UPDATE l
	SET l.sort_code = a.sort_code,
		l.is_leaf = a.is_leaf,
		l.default_threat_score = a.default_threat_score,
		l.external_code = a.external_code,
		l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM threat l
	JOIN threat a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN @src s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
	  AND l.who_modified = @sys_owner
	  AND EXISTS (
		SELECT l.sort_code, l.is_leaf, l.default_threat_score, l.external_code, l.shortname, l.caption, l.description_text, l.help_text
		EXCEPT
		SELECT a.sort_code, a.is_leaf, a.default_threat_score, a.external_code, s.shortname, s.caption, s.description_text, s.help_text
	  );

	INSERT INTO threat (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, default_threat_score, external_code,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.default_threat_score, a.external_code,
		s.shortname, s.caption, s.description_text, s.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	JOIN threat a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM threat l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
	);

	IF OBJECT_ID('dbo.p_sync_derived_links', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_derived_links;
	END
END
GO