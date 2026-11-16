/* =============================================================================
 * Verze: 2026-11-16 16:25
 * Soubor: fillup_threat.sql
 *
 * 1. Role souboru v celém systému:
 *    Prvotní idempotentní naplnění stromového katalogu hrozeb (tabulka threat)
 *    pro primární jazyk ('cs'). Obsahuje 5 hlavních kategorií (is_leaf = 0)
 *    a 20 koncových hrozeb (is_leaf = 1) s výchozím skóre hrozby
 *    (default_threat_score v intervalu 0..100 %).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Využívá funkci dbo.f_generate_original a proceduru dbo.p_sync_derived_links.
 *    - Zapisuje do tabulky threat (table_threat.sql).
 *    - Na tato data navazuje překladový skript fillup_threat_en.sql, katalog
 *      scénářů (fillup_scenario.sql) a stránka page_threat.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (pracuje nad systémovými
 *      záznamy s object_owner = 0x00, nevyžaduje relaci v dbsession).
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('threat', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @now datetime = GETDATE();

	DECLARE @src TABLE (
		builtin_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		parent_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
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
	('thr_cyber_ddos', 'thr_grp_cyber', '030', 1, 50.0000, 'ISO27005-C.3', 'DDoS útok', 'Zahlcení služby nebo sítě (DoS / DDoS)', 'Cílené zahlcení síťové konektivity, firewallu nebo aplikačního serveru velkým množstvím požadavků.', 'Ohrožuje dostupnost externě publikovaných služeb, portálů a komunikačních rozhraní.'),
	('thr_cyber_exfiltration', 'thr_grp_cyber', '040', 1, 50.0000, 'ISO27005-C.4', 'Krádež a únik dat', 'Neoprávněný přístup a exfiltrace citlivých dat', 'Získání neoprávněného přístupu k databázím, úložištím nebo dokumentům s cílem odcizení či zveřejnění dat.', 'Vede k porušení důvěrnosti, postihům dle GDPR/NIS2 a poškození pověsti.'),
	('thr_cyber_phishing', 'thr_grp_cyber', '020', 1, 70.0000, 'ISO27005-C.2', 'Phishing / Soc. inženýrství', 'Phishing, podvržení identity a sociální inženýrství', 'Manipulace zaměstnanců pomocí podvodných e-mailů, zpráv nebo telefonátů s cílem získat přihlašovací údaje či schválit podvodnou transakci.', 'Často slouží jako vstupní vektor pro ransomware nebo kompromitaci účtů.'),
	('thr_cyber_ransomware', 'thr_grp_cyber', '010', 1, 70.0000, 'ISO27005-C.1', 'Ransomware / Malware', 'Škodlivý kód a šifrovací útok (Ransomware)', ' Infiltrace škodlivého kódu, který zašifruje servery, stanice a dostupná síťová úložiště a vyžaduje výkupné.', 'Kritická hrozba pro dostupnost IT infrastruktury a integritu dat.'),
	('thr_grp_cyber', '', '030', 0, 0.0000, 'THREAT-CYBER', 'Kybernetické útoky', 'Kybernetické a úmyslné útoky', 'Úmyslné externí i interní útoky vedené přes síť, aplikační rozhraní nebo pomocí sociálního inženýrství.', 'Složka hrozeb pokrývající malware, ransomware, phishing, DDoS a exfiltraci dat.'),
	('thr_grp_human', '', '040', 0, 0.0000, 'THREAT-HUMAN', 'Lidský faktor', 'Hrozby lidského faktoru a personálu', 'Neúmyslné chyby obsluhy, ztráta vybavení, nedostupnost klíčových pracovníků nebo úmyslná sabotáž.', 'Složka hrozeb souvisejících se zaměstnanci, administrátory a interními uživateli.'),
	('thr_grp_org', '', '050', 0, 0.0000, 'THREAT-ORG', 'Dodavatelé a procesy', 'Organizační, dodavatelské a právní hrozby', 'Selhání třetích stran, výpadky klíčových dodavatelů, porušení legislativních požadavků a procesní selhání.', 'Složka hrozeb pokrývající dodavatelský řetězec, cloudové poskytovatele a compliance.'),
	('thr_grp_phys', '', '010', 0, 0.0000, 'THREAT-PHYS', 'Fyzické a živelní', 'Fyzické, environmentální a živelní hrozby', 'Požáry, záplavy, extrémní povětrnostní jevy, výpadky inženýrských sítí a fyzické narušení objektů.', 'Složka hrozeb působících na lokality, budovy, sály a fyzickou techniku.'),
	('thr_grp_tech', '', '020', 0, 0.0000, 'THREAT-TECH', 'Technické a IT', 'Technická selhání HW, SW a infrastruktury', 'Poruchy serverů, diskových polí, síťových prvků, chyby v softwaru, selhání záloh a přetížení kapacity.', 'Složka technických a provozních závad bez nutnosti úmyslného útočníka.'),
	('thr_hum_admin_err', 'thr_grp_human', '020', 1, 50.0000, 'ISO27005-H.2', 'Chyba administrátora', 'Chybný zásah administrátora nebo chybná konfigurace', 'Smazání produkční databáze, chybná úprava směrování, vypnutí bezpečnostní kontroly nebo nasazení vadné konfigurace.', 'Může způsobit okamžitý plošný výpadek nebo neúmyslné zpřístupnění dat.'),
	('thr_hum_insider', 'thr_grp_human', '040', 1, 30.0000, 'ISO27005-H.4', 'Sabotáž / Zneužití práv', 'Úmyslné zneužití oprávnění interním pracovníkem', 'Vynášení dat, poškození systémů nebo neoprávněné operace provedené nespokojeným či bývalým pracovníkem.', 'Riziko roste při absenci kontroly privilegovaných účtů a opožděném odebírání přístupů.'),
	('thr_hum_key_person', 'thr_grp_human', '030', 1, 50.0000, 'ISO27005-H.3', 'Výpadek klíčové osoby', 'Nedostupnost nebo odchod klíčového specialisty', 'Náhlá nemoc, úraz nebo odchod pracovníka s unikátním know-how bez zastupitelnosti a dokumentace.', 'Ohrožuje schopnost obnovy a údržby specializovaných aplikací a procesů.'),
	('thr_hum_user_err', 'thr_grp_human', '010', 1, 70.0000, 'ISO27005-H.1', 'Chyba obsluhy', 'Neúmyslná chyba uživatele nebo obsluhy', 'Chybné zadání či přepsání dat, omylem smazaný soubor nebo odeslání citlivého dokumentu nesprávnému adresátovi.', 'Nejčastější provozní hrozba ovlivňující integritu a důvěrnost dat.'),
	('thr_org_compliance', 'thr_grp_org', '030', 1, 30.0000, 'ISO27005-O.3', 'Nesoulad se zákony', 'Porušení regulatorních, zákonných nebo smluvních povinností', 'Nedodržení požadavků kybernetické bezpečnosti (NIS2), ochrany osobních údajů (GDPR), licenčních ujednání nebo SLA.', 'Vede k finančním sankcím, kontrolám regulátora a ztrátě důvěry klientů.'),
	('thr_org_isp_outage', 'thr_grp_org', '020', 1, 50.0000, 'ISO27005-O.2', 'Výpadek telekomunikací', 'Výpadek poskytovatele internetu nebo komunikačního rozhraní', 'Přerušení datové, hlasové nebo cloudové konektivity na straně externího operátora.', 'Odřízne pobočky, vzdálené pracovníky i publikované služby od zákazníků.'),
	('thr_org_process_fail', 'thr_grp_org', '040', 1, 40.0000, 'ISO27005-O.4', 'Selhání řízení změn', 'Selhání interního procesu nebo neřízená změna', 'Neotestovaná změna v produkci, chybějící odpovědnost nebo neaktuální havarijní postupy.', 'Zvyšuje dobu výpadku a pravděpodobnost řetězení chyb při incidentu.'),
	('thr_org_supplier_outage', 'thr_grp_org', '010', 1, 50.0000, 'ISO27005-O.1', 'Výpadek dodavatele', 'Výpadek nebo ukončení činnosti klíčového dodavatele', 'Nedostupnost externě zajišťované služby, SaaS platformy, servisní podpory nebo kompromitace dodavatelského řetězce.', 'Kritické zejména u dodavatelů bez alternativního řešení (Vendor Lock-in).'),
	('thr_phys_fire', 'thr_grp_phys', '010', 1, 30.0000, 'ISO27005-P.1', 'Požár / Kouř', 'Požár nebo zakouření v budově či serverovně', 'Vznik požáru v důsledku zkratu elektroinstalace, přehřátí technologie nebo vznícení materiálu.', 'Způsobuje destrukci HW, kabeláže, listinných dokumentů a dlouhodobou nedostupnost prostor.'),
	('thr_phys_hvac', 'thr_grp_phys', '040', 1, 50.0000, 'ISO27005-P.4', 'Selhání klimatizace', 'Výpadek chlazení a klimatizace technologické místnosti', 'Porucha klimatizační jednotky v serverovně vedoucí k rychlému přehřátí a nouzovému odstavení serverů.', 'Častá příčina vynucené odstávky IT techniky v letních měsících.'),
	('thr_phys_intrusion', 'thr_grp_phys', '050', 1, 30.0000, 'ISO27005-P.5', 'Fyzické vniknutí / Krádež', 'Neoprávněné fyzické vniknutí, krádež nebo vandalismus', 'Proniknutí nepovolané osoby do objektu či místnosti, odcizení techniky, nosičů dat nebo fyzické poškození zařízení.', 'Ohrožuje dostupnost zařízení i důvěrnost nezašifrovaných dat na nosičích.'),
	('thr_phys_power', 'thr_grp_phys', '030', 1, 50.0000, 'ISO27005-P.3', 'Výpadek elektřiny', 'Dlouhodobý výpadek elektrického napájení', 'Přerušení dodávky elektrické energie z distribuční sítě přesahující kapacitu záložních zdrojů (UPS).', 'Postihuje veškerou techniku, osvětlení, klimatizaci i přístupové systémy v budově.'),
	('thr_phys_water', 'thr_grp_phys', '020', 1, 30.0000, 'ISO27005-P.2', 'Voda / Záplava', 'Zatečení vody, havárie potrubí nebo povodeň', 'Vytopení místnosti prasklým vodovodním či topným potrubím, přívalovým deštěm nebo povodní.', 'Vysoké riziko pro suterénní prostory, serverovny pod rozvody vody a archivy dokumentů.'),
	('thr_tech_capacity', 'thr_grp_tech', '040', 1, 50.0000, 'ISO27005-T.4', 'Vyčerpání kapacity', 'Přetížení výpočetní, paměťové nebo diskové kapacity', 'Zaplnění diskového prostoru (logů, databází), vyčerpání paměti RAM nebo procesorového výkonu.', 'Způsobuje zamrznutí aplikací, selhání zápisu transakcí a odmítání požadavků uživatelů.'),
	('thr_tech_hw_fail', 'thr_grp_tech', '010', 1, 60.0000, 'ISO27005-T.1', 'Selhání HW / Serveru', 'Technická porucha serveru, síťového prvku nebo HW', 'Výpadek zdroje, základní desky, síťového přepínače, firewallu nebo jiné fyzické komponenty.', 'Bez clusteru či redundantního zapojení vede k přímému výpadku hostovaných aplikací.'),
	('thr_tech_storage_fail', 'thr_grp_tech', '020', 1, 40.0000, 'ISO27005-T.2', 'Poškození úložiště / Dat', 'Selhání diskového pole, média nebo poškození databáze', 'Vícečetné selhání disků, poškození souborového systému, korupce databázových stránek nebo selhání obnovy ze zálohy.', 'Ohrožuje dostupnost i integritu klíčových podnikových dat.'),
	('thr_tech_sw_bug', 'thr_grp_tech', '030', 1, 60.0000, 'ISO27005-T.3', 'Chyba SW / Aktualizace', 'Softwarová chyba v aplikaci nebo neúspěšný upgrade', 'Projevení programové chyby v produkční verzi, nekompatibilita po aktualizaci OS/DB nebo zablokování databázových zámků.', 'Častá příčina degradace výkonu, chybných výpočtů nebo výpadku aplikačních služeb.');

	-- 1. Vložení/aktualizace v topologickém pořadí (nejprve složky parent_code = '', poté listy)
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

	-- 2. Synchronizace českých 'L' záznamů
	UPDATE l
	SET l.shortname = s.shortname,
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
		SELECT l.shortname, l.caption, l.description_text, l.help_text
		EXCEPT
		SELECT s.shortname, s.caption, s.description_text, s.help_text
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