/* =============================================================================
 * Verze: 2026-11-20 17:15
 * Soubor: fillup_impact_type.sql
 *
 * 1. Role souboru v celém systému:
 *    Prvotní idempotentní naplnění systémového hierarchického katalogu druhů
 *    dopadů / následků v tabulce impact_type (object_owner = 0x00, jazyk 'cs',
 *    záznamy 'A' a symetrické 'L'). Obsahuje 5 kořenových kategorií (is_leaf = 0)
 *    a 29 koncových druhů dopadů (is_leaf = 1, celkem 34 uzlů) pokrývajících
 *    důvěrnost, integritu, dostupnost (časové intervaly výpadku 15 min až 2+
 *    měsíce), ztrátu dat / fyzické zničení a integritu komunikace.
 *    Osiřelé systémové záznamy (object_owner = 0x00 AND who_modified = 0x00)
 *    mimo aktuální sadu jsou automaticky odstraněny.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Vyžaduje tabulku impact_type (table_impact_type.sql), funkci
 *      dbo.f_generate_original (f_generate_original.sql) a proceduru
 *      dbo.p_sync_derived_links (p_sync_derived_links.sql).
 *    - Navazuje překladový skript fillup_impact_type_en.sql a stránka
 *      page_impact_type.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      systémovými záznamy (object_owner = 0x00) bez závislosti na dbsession.
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('impact_type', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @now datetime = GETDATE();

	DECLARE @src TABLE (
		builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		parent_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		sort_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		is_leaf bit NOT NULL,
		cia_category varchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
		duration_minutes int NULL,
		external_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		svg_icon varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @src (
		builtin_code, parent_code, sort_code, is_leaf, cia_category, duration_minutes,
		external_code, shortname, caption, description_text, help_text, svg_icon
	) VALUES
	('it_comm_insertion','it_grp_communication','010',1,'COMMUNICATION',NULL,'INSERTION','Ins','Vložení falešné zprávy','Úmyslné vložení podvržené zprávy, příkazu nebo transakce do komunikačního kanálu.','Hodnotí se u komunikačních rozhraní, platebních a integračních systémů.',''),
	('it_comm_mis_routing','it_grp_communication','060',1,'COMMUNICATION',NULL,'MIS-ROUTING','Mr','Chybné směrování zprávy / dat','Doručení přenášených dat nebo zpráv nesprávnému příjemci v důsledku chyby či manipulace se směrováním.','Může vést k prozrazení obsahu i k nedostupnosti transakce u zamýšleného příjemce.',''),
	('it_comm_non_delivery','it_grp_communication','040',1,'COMMUNICATION',NULL,'NON-DELIVERY','Nd','Nedoručení zprávy / dat','Ztráta nebo zablokování zprávy během přenosu bez jejího doručení cílovému příjemci.','Kritické pro elektronické podatelny, objednávky, platební příkazy a řídicí povely.',''),
	('it_comm_out_of_seq','it_grp_communication','080',1,'COMMUNICATION',NULL,'OUT-OF-SEQ','Os','Narušená posloupnost zpráv / datových celků','Doručení zpráv nebo transakcí v nesprávném časovém pořadí vedoucí k nekonzistenci stavu.','Významné u účetních, skladových a distribuovaných databázových systémů.',''),
	('it_comm_replay','it_grp_communication','050',1,'COMMUNICATION',NULL,'REPLAY','Rp','Opakování zprávy / dat (Replay)','Opakované odeslání nebo zpracování již jednou provedené platné zprávy či transakce.','Může způsobit duplicitní platby, vícenásobné objednávky nebo obejití autentizace.',''),
	('it_comm_repud_origin','it_grp_communication','020',1,'COMMUNICATION',NULL,'REPUD-ORIGIN','Ro','Popření původu zprávy / dat','Odesílatel dodatečně popře, že zprávu, objednávku nebo pokyn odeslal či schválil.','Vyžaduje nepopiratelnost původu (elektronický podpis, auditní stopa).',''),
	('it_comm_repud_rec','it_grp_communication','030',1,'COMMUNICATION',NULL,'REPUD-REC','Rc','Popření přijetí zprávy / dat','Příjemce dodatečně popře, že mu byla zpráva, dokument nebo pokyn řádně doručena.','Důležité u smluvní, úřední a obchodní elektronické komunikace.',''),
	('it_comm_traffic_mon','it_grp_communication','070',1,'COMMUNICATION',NULL,'TRAFFIC-MON','Tm','Monitorování komunikačního provozu','Neoprávněné sledování objemu, časování nebo metadat síťové komunikace (analýza provozu).','Může odhalit citlivé obchodní vazby nebo provozní vzorce i u šifrovaného obsahu.',''),
	('it_destr_full','it_grp_destruction','020',1,'DESTRUCTION',NULL,'DESTR-FULL','DT','Úplná ztráta všech dat','Nenávratná likvidace produkčních dat i jejich záloh (např. při úspěšném ransomware útoku na zálohy nebo požáru bez offsite zálohy).','Nejvyšší stupeň poškození datových aktiv s možným existenčním dopadem.',''),
	('it_destr_part','it_grp_destruction','010',1,'DESTRUCTION',NULL,'DESTR-PART','DP','Ztráta dat od posledního zálohování','Ztráta transakcí a změn provedených od okamžiku poslední použitelné zálohy (odpovídá RPO).','Vyžaduje opakované pořízení dat nebo rekonstrukci z pomocných dokladů.',''),
	('it_discl_csp','it_grp_confidentiality','020',1,'CONFIDENTIALITY',NULL,'DISCL-SP','CSP','Neoprávněné prozrazení smluvním poskytovatelům služeb','Zpřístupnění uchovávaných informací externím dodavatelům nebo smluvním poskytovatelům služeb (CSP) nad rámec jejich oprávnění.','Dotčené osoby jsou vázány smlouvou / NDA, přesto jde o porušení důvěrnosti.',''),
	('it_discl_identifiable','it_grp_confidentiality','010',1,'CONFIDENTIALITY',NULL,'DISCL-I','I','Neoprávněné prozrazení identifikovatelným osobám','Zpřístupnění uchovávaných informací interním zaměstnancům, brigádníkům či jiným identifikovatelným osobám ve smluvním vztahu k organizaci bez příslušného oprávnění.','Nejnižší okruh prozrazení (vnitřní prostředí organizace), přesto může způsobit újmu nebo porušení GDPR.',''),
	('it_discl_outsiders','it_grp_confidentiality','030',1,'CONFIDENTIALITY',NULL,'DISCL-O','O','Neoprávněné prozrazení cizím osobám','Únik nebo zveřejnění uchovávaných informací neidentifikovaným cizím osobám, konkurenci či široké veřejnosti.','Nejvyšší stupeň narušení důvěrnosti s rizikem postihů, ztráty pověsti a obchodních škod.',''),
	('it_grp_availability','','030',0,'AVAILABILITY',NULL,'GRP-AVAIL','Dostupnost','Ohrožení dostupnosti informací a služeb','Dopady neplánovaného výpadku nebo nedostupnosti systému, aplikace, dat či služby v závislosti na délce trvání výpadku.','Hodnotí se v časových intervalech od 15 minut až po 2 měsíce a více; závažnost s časem neklesá.','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/></svg>'),
	('it_grp_communication','','050',0,'COMMUNICATION',NULL,'GRP-COMM','Komunikace','Ohrožení integrity komunikace','Následky narušení přenosu zpráv a dat po komunikačních sítích a rozhraních.','Zahrnuje vložení falešné zprávy, popření původu/přijetí, nedoručení, opakování, chybné směrování, odposlech a narušení pořadí.','<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg>'),
	('it_grp_confidentiality','','010',0,'CONFIDENTIALITY',NULL,'GRP-CONF','Důvěrnost','Ohrožení důvěrnosti informací','Následky neoprávněného prozrazení nebo zpřístupnění uchovávaných informací a dat podle okruhu neoprávněných osob.','Rozlišuje prozrazení interním osobám, smluvním dodavatelům a cizím osobám (veřejnosti / konkurenci).','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z"/></svg>'),
	('it_grp_destruction','','040',0,'DESTRUCTION',NULL,'GRP-DESTR','Ztráta / Zničení','Ztráta dat a fyzické zničení','Následky částečné či úplné ztráty dat nebo fyzického zničení systému a hardwaru.','Odděluje ztrátu dat od poslední zálohy (RPO), úplnou ztrátu dat a fyzickou destrukci infrastruktury.','<svg viewBox="0 0 24 24" fill="#DC2626"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>'),
	('it_grp_integrity','','020',0,'INTEGRITY',NULL,'GRP-INTEG','Integrita','Ohrožení integrity informací','Následky narušení přesnosti, úplnosti a pravosti uložených nebo zpracovávaných dat.','Rozlišuje neúmyslné chyby menšího či většího rozsahu a cílenou úmyslnou modifikaci dat.','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>'),
	('it_modif_deliberate','it_grp_integrity','030',1,'INTEGRITY',NULL,'MODIF-DEL','DM','Úmyslná modifikace uložených nebo přenášených dat','Záměrná neoprávněná změna dat v databázi, dokumentu nebo při přenosu (např. podvodná úprava účtu či obsahu zprávy).','Často skryté napadení s přímými finančními, právními nebo bezpečnostními dopady.',''),
	('it_modif_small','it_grp_integrity','010',1,'INTEGRITY',NULL,'MODIF-SS','SE','Chyby menšího rozsahu (překlep / drobné chyby přenosu)','Neúmyslná lidská chyba menšího rozsahu (např. překlep v jednom záznamu) nebo občasná drobná chyba při přenosu dat.','Omezený lokální rozsah bez systémového poškození celé databáze.',''),
	('it_modif_wide','it_grp_integrity','020',1,'INTEGRITY',NULL,'MODIF-WS','WE','Chyby většího rozsahu (systémové / programovací chyby)','Hromadná neúmyslná chyba (např. chyba v programování, chybný dávkový import nebo delší výpadek synchronizace dat).','Postihuje větší množství záznamů a vyžaduje náročnou kontrolu a opravu dat.',''),
	('it_physical_dest','it_grp_destruction','030',1,'DESTRUCTION',NULL,'PHYSICAL-DEST','PD','Fyzické zničení systému / aktiva','Fyzická destrukce technického zařízení, serverovny, média nebo listinného archivu (např. požárem, záplavou či sabotáží).','Zahrnuje náklady na pořízení nového vybavení a dlouhodobou obnovu provozu.',''),
	('it_unavail_12h','it_grp_availability','060',1,'AVAILABILITY',720,'UNAVAIL-12H','12H','Nedostupnost – 12 hodin','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu až 12 hodin (celá pracovní směna).','Postihuje celodenní provoz a denní uzávěrky.',''),
	('it_unavail_15m','it_grp_availability','010',1,'AVAILABILITY',15,'UNAVAIL-15M','15M','Nedostupnost – 15 minut','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu až 15 minut.','Kritické pouze pro real-time řídicí, platební a bezpečnostní služby.',''),
	('it_unavail_1d','it_grp_availability','070',1,'AVAILABILITY',1440,'UNAVAIL-1D','1D','Nedostupnost – 1 den','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu 1 dne (24 hodin).','Typický práh aktivace havarijních plánů u důležitých podnikových systémů.',''),
	('it_unavail_1h','it_grp_availability','030',1,'AVAILABILITY',60,'UNAVAIL-1H','1H','Nedostupnost – 1 hodina','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu až 1 hodiny.','Znatelné narušení práce operátorů a zákaznických kanálů.',''),
	('it_unavail_1m','it_grp_availability','110',1,'AVAILABILITY',43200,'UNAVAIL-1M','1M','Nedostupnost – 1 měsíc','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu 1 měsíce.','Zásadní narušení měsíčních uzávěrek, fakturace, výplat a smluvních závazků.',''),
	('it_unavail_1w','it_grp_availability','090',1,'AVAILABILITY',10080,'UNAVAIL-1W','1W','Nedostupnost – 1 týden','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu 1 týdne.','Významné obchodní ztráty, hromadění nevyřízených požadavků a porušování SLA.',''),
	('it_unavail_2d','it_grp_availability','080',1,'AVAILABILITY',2880,'UNAVAIL-2D','2D','Nedostupnost – 2 dny','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu 2 dnů (48 hodin).','Nemožnost dlouhodobějšího náhradního ručního provozu u klíčových agend.',''),
	('it_unavail_2h','it_grp_availability','040',1,'AVAILABILITY',120,'UNAVAIL-2H','2H','Nedostupnost – 2 hodiny','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu až 2 hodin.','Překročení běžné tolerance u silně vytížených provozních a zákaznických aplikací.',''),
	('it_unavail_2m','it_grp_availability','120',1,'AVAILABILITY',86400,'UNAVAIL-2MO','2M+','Nedostupnost – 2 měsíce a více','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu 2 měsíců a delší.','Dlouhodobý nebo trvalý výpadek ohrožující samotnou existenci služby či organizace.',''),
	('it_unavail_2w','it_grp_availability','100',1,'AVAILABILITY',20160,'UNAVAIL-2W','2W','Nedostupnost – 2 týdny','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu 2 týdnů.','Vážné ohrožení kontinuity činností, ztráta klientů a regulatorní sankce.',''),
	('it_unavail_30m','it_grp_availability','020',1,'AVAILABILITY',30,'UNAVAIL-30M','30M','Nedostupnost – 30 minut','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu až 30 minut.','Relevantní pro vysoce dostupné online služby, call centra a výrobní linky.',''),
	('it_unavail_3h','it_grp_availability','050',1,'AVAILABILITY',180,'UNAVAIL-3H','3H','Nedostupnost – 3 hodiny','Neplánovaná nedostupnost systému, aplikace nebo služby po dobu až 3 hodin (půl směny).','Způsobuje citelný výpadek produktivity a narušení obsluhy zákazníků.','');

	-- 0. Úklid zastaralých systémových záznamů (0x00, who_modified = 0x00), které již nejsou v @src
	DELETE t
	FROM impact_type t
	LEFT JOIN @src s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.who_modified = @sys_owner
	  AND t.record_type IN ('A', 'L')
	  AND s.builtin_code IS NULL;

	-- 1. Aktualizace nemodifikovaných 'A' záznamů
	UPDATE t
	SET t.sort_code = s.sort_code,
		t.is_leaf = s.is_leaf,
		t.cia_category = s.cia_category,
		t.duration_minutes = s.duration_minutes,
		t.external_code = s.external_code,
		t.shortname = s.shortname,
		t.caption = s.caption,
		t.description_text = s.description_text,
		t.help_text = s.help_text,
		t.svg_icon = CASE WHEN ISNULL(t.svg_icon, '') = '' AND s.svg_icon <> '' THEN s.svg_icon ELSE t.svg_icon END,
		t.[language] = 'cs',
		t.date_modified = @now
	FROM impact_type t
	JOIN @src s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.record_type = 'A'
	  AND t.who_modified = @sys_owner
	  AND EXISTS (
		SELECT t.sort_code, t.is_leaf, t.cia_category, t.duration_minutes, t.external_code, t.shortname, t.caption, t.description_text, t.help_text
		EXCEPT
		SELECT s.sort_code, s.is_leaf, s.cia_category, s.duration_minutes, s.external_code, s.shortname, s.caption, s.description_text, s.help_text
	  );

	-- 2. Vložení chybějících 'A' záznamů
	INSERT INTO impact_type (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, cia_category, duration_minutes,
		external_code, shortname, caption, description_text, help_text, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
		s.builtin_code, p.parent_orig, s.sort_code, s.is_leaf, s.cia_category, s.duration_minutes,
		s.external_code, s.shortname, s.caption, s.description_text, s.help_text, s.svg_icon,
		0, 1,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	CROSS APPLY (SELECT dbo.f_generate_original('impact_type', @sys_owner, s.builtin_code, '') AS orig) x
	OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('impact_type', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
	WHERE NOT EXISTS (
		SELECT 1 FROM impact_type t
		WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
	);

	-- Doplnění/sjednocení parent_uuid u nemodifikovaných záznamů
	UPDATE t
	SET t.parent_uuid = p.parent_orig,
		t.date_modified = @now
	FROM impact_type t
	JOIN @src s ON s.builtin_code = t.builtin_code
	OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('impact_type', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
	WHERE t.object_owner = @sys_owner
	  AND t.record_type IN ('A', 'L')
	  AND t.who_modified = @sys_owner
	  AND EXISTS (SELECT t.parent_uuid EXCEPT SELECT p.parent_orig);

	-- 3. Synchronizace českých 'L' záznamů
	UPDATE l
	SET l.sort_code = a.sort_code,
		l.is_leaf = a.is_leaf,
		l.cia_category = a.cia_category,
		l.duration_minutes = a.duration_minutes,
		l.external_code = a.external_code,
		l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM impact_type l
	JOIN impact_type a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN @src s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
	  AND l.who_modified = @sys_owner
	  AND EXISTS (
		SELECT l.sort_code, l.is_leaf, l.cia_category, l.duration_minutes, l.external_code, l.shortname, l.caption, l.description_text, l.help_text
		EXCEPT
		SELECT a.sort_code, a.is_leaf, a.cia_category, a.duration_minutes, a.external_code, s.shortname, s.caption, s.description_text, s.help_text
	  );

	INSERT INTO impact_type (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, cia_category, duration_minutes,
		external_code, shortname, caption, description_text, help_text, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.cia_category, a.duration_minutes,
		a.external_code, s.shortname, s.caption, s.description_text, s.help_text, a.svg_icon,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	JOIN impact_type a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM impact_type l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
	);

	IF OBJECT_ID('dbo.p_sync_derived_links', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_derived_links;
	END
END
GO