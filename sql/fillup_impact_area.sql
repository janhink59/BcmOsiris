/* =============================================================================
 * Verze: 2026-11-20 17:15
 * Soubor: fillup_impact_area.sql
 *
 * 1. Role souboru v celém systému:
 *    Prvotní idempotentní naplnění systémového hierarchického katalogu oblastí
 *    dopadů v tabulce impact_area (object_owner = 0x00, jazyk 'cs', záznamy 'A'
 *    a symetrické 'L'). Obsahuje 3 perspektivy (is_leaf = 0: Dopady na organizaci,
 *    Dopady na stát, Dopady na subjekt údajů / obyvatelstvo) a 15 koncových
 *    měřitelných oblastí dopadů (is_leaf = 1, celkem 18 uzlů).
 *    Osiřelé systémové záznamy (object_owner = 0x00 AND who_modified = 0x00)
 *    mimo aktuální sadu jsou automaticky odstraněny.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Vyžaduje tabulku impact_area (table_impact_area.sql), funkci
 *      dbo.f_generate_original (f_generate_original.sql) a proceduru
 *      dbo.p_sync_derived_links (p_sync_derived_links.sql).
 *    - Navazuje překladový skript fillup_impact_area_en.sql a stránka
 *      page_impact_area.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      systémovými záznamy (object_owner = 0x00) bez závislosti na dbsession.
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('impact_area', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @now datetime = GETDATE();

	DECLARE @src TABLE (
		builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		parent_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		sort_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		is_leaf bit NOT NULL,
		external_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		svg_icon varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @src (
		builtin_code, parent_code, sort_code, is_leaf, external_code,
		shortname, caption, description_text, help_text, svg_icon
	) VALUES
	('ia_grp_org','','010',0,'AREA-ORG','Organizace','Dopady na organizaci','Měřitelné dopady bezpečnostních incidentů a výpadků přímo na samotnou organizaci (finance, obchodní zájmy, pověst, zákony, trestní odpovědnost, osobní bezpečnost a provoz).','Rozhodující skupina oblastí pro každou organizaci; jednotlivé podřízené oblasti lze na úrovni tenanta podle potřeby deaktivovat.','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10z"/></svg>'),
	('ia_grp_state','','020',0,'AREA-STATE','Stát','Dopady na stát a veřejný zájem','Dopady přesahující samotnou organizaci na veřejný pořádek, mezinárodní vztahy, veřejnou správu, obranu a bezpečnostní či zpravodajské zájmy státu.','Relevantní zejména pro orgány veřejné správy, kritickou infrastrukturu a regulované subjekty (NIS2 / ZKB).','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M4 10v7h3v-7H4zm6 0v7h3v-7h-3zM2 22h19v-3H2v3zm14-12v7h3v-7h-3zm-4.5-9L2 6v2h19V6l-9.5-5z"/></svg>'),
	('ia_grp_subject','','030',0,'AREA-SUBJ','Subjekt údajů','Dopady na subjekt údajů (obyvatelstvo / GDPR)','Dopady na práva, svobody, zdraví, majetek a emocionální rovnováhu dotčených fyzických osob a obyvatelstva.','Zásadní pro hodnocení dopadů na ochranu osobních údajů (DPIA / GDPR) a služby pro veřejnost.','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>'),
	('ia_org_commercial','ia_grp_org','020',1,'CRAMM-COMM','Obchodní zájmy','Obchodní a ekonomické zájmy','Hodnota informací nebo výhody pro konkurenci, ztráta schopnosti vytvářet zisk, znevýhodnění v obchodních jednáních či poškození obchodního tajemství.','Hodnotí se podle komerční hodnoty pro konkurenci (od nekomerční hodnoty po stovky mil. Kč obratu a ohrožení životaschopnosti organizace).',''),
	('ia_org_criminal','ia_grp_org','050',1,'CRAMM-CRIM','Trestní jednání','Trestní jednání a trestní odpovědnost','Napomáhání spáchání trestného činu, zbrzdění či zastavení vyšetřování nebo soudního řízení a riziko trestní odpovědnosti odpovědných osob.','Hodnotí se od napomáhání běžnému trestnému činu až po závažné trestné činy a zmaření vyšetřování.',''),
	('ia_org_financial','ia_grp_org','010',1,'CRAMM-FIN','Finanční ztráta','Finanční ztráta / Narušení činností','Přímé i nepřímé finanční ztráty, náklady na obnovu provozu a dat, smluvní pokuty (SLA) a ušlý výnos.','Hodnotí se podle finančního rozpětí (ve vodítkách CRAMM typicky od 100 tis. Kč až nad 1 mld. Kč, v měně organizace).',''),
	('ia_org_legal','ia_grp_org','040',1,'CRAMM-LEG','Povinnosti ze zákona','Povinnosti ze zákona a regulací','Správní řízení, občanskoprávní soudní pře nebo sankce za porušení zákonných a regulatorních povinností (GDPR, NIS2, DORA, oborové předpisy).','Hodnotí se podle výše hrozících pokut, náhrad škody a případné trestní sazby odnětí svobody.',''),
	('ia_org_management','ia_grp_org','070',1,'CRAMM-MGMT','Řízení a provoz','Řízení a provoz organizace','Neefektivní fungování části organizace, narušení řádného řízení, znevýhodnění při strategických jednáních až po zastavení významných složek provozu.','Hodnotí se rozsah narušení vnitřního rozhodování a operativního chodu organizace.',''),
	('ia_org_reputation','ia_grp_org','030',1,'CRAMM-REP','Důvěryhodnost','Ztráta důvěryhodnosti a pověsti','Negativní ovlivnění vztahů uvnitř organizace, s obchodními partnery a veřejností, negativní lokální, celostátní či nadnárodní publicita.','Hodnotí se rozsah a trvání negativní publicity a dopad na důvěru zákazníků a partnerů.',''),
	('ia_org_safety','ia_grp_org','060',1,'CRAMM-SAFE','Osobní bezpečnost','Ohrožení zdraví a života (osobní bezpečnost)','Ohrožení osobní bezpečnosti, svobody, zdraví nebo života jedné či více osob (zaměstnanců, klientů, veřejnosti).','Hodnotí se od menší újmy jedné osoby přes větší újmu až po ohrožení či ztrátu života jedné nebo více osob.',''),
	('ia_state_defence','ia_grp_state','040',1,'CRAMM-DEF','Obrana','Obrana a operační akceschopnost','Obtíže nebo poškození operační akceschopnosti či bezpečnosti ozbrojených sil od místní úrovně až po výjimečně vážné celostátní poškození.','Relevantní pro resort obrany, obranný průmysl a prvky kritické infrastruktury státu.',''),
	('ia_state_intelligence','ia_grp_state','050',1,'CRAMM-SEC','Utajení / Bezpečnost','Bezpečnostní a zpravodajské zájmy (utajované informace)','Újma zájmům státu odpovídající stupňům utajení (Vyhrazené, Důvěrné, Tajné, Přísně tajné).','Odpovídá zákonné klasifikaci utajovaných informací (nevýhodné až mimořádně vážná újma zájmům ČR).',''),
	('ia_state_international','ia_grp_state','020',1,'CRAMM-INTL','Mezinárodní vztahy','Mezinárodní a diplomatické vztahy','Negativní ovlivnění nebo závažné poškození diplomatických vztahů, vyvolání mezinárodního napětí až ohrožení stability spřátelených států.','Relevantní pro státní správu, diplomacii a nadnárodní projekty.',''),
	('ia_state_public_admin','ia_grp_state','030',1,'CRAMM-GOV','Veřejná správa','Politika a činnosti veřejné správy (služby státu)','Neefektivní fungování státní organizace, bránění důležitým činnostem státu až po zastavení základních agend veřejné správy.','Hodnotí se dopad na výkon státní správy a služby zajišťované státem pro občany.',''),
	('ia_state_public_order','ia_grp_state','010',1,'CRAMM-ORD','Veřejný pořádek','Veřejný pořádek a stabilita státu','Vyvolání místních protestů, demonstrací, nátlakových akcí, stávek s celostátními důsledky až po ohrožení stability státu.','Relevantní u výpadků základních služeb (energie, doprava, telekomunikace, zdravotnictví, finance).',''),
	('ia_subj_material','ia_grp_subject','020',1,'GDPR-MAT','Hmotná újma','Hmotná (finanční / majetková) újma subjektu údajů','Přímá majetková nebo finanční ztráta dotčených fyzických osob (např. zneužití platebních údajů, krádež identity, ztráta nároku na dávku či službu).','Hodnotí se rozsah finančního poškození jednotlivců nebo skupin osob.',''),
	('ia_subj_nonmaterial','ia_grp_subject','030',1,'GDPR-NONMAT','Nehmotná újma','Nehmotná (morální a emocionální) újma subjektu údajů','Narušení emocionální rovnováhy (zlost, frustrace, ztráta soukromí, diskriminace, poškození dobré pověsti) jednotlivce nebo skupiny osob v důsledku narušení ochrany osobních údajů.','Odpovídá hodnocení morální a psychické újmy osob dle GDPR a vodítek Ochrany osobních údajů.',''),
	('ia_subj_physical','ia_grp_subject','010',1,'GDPR-PHYS','Fyzická újma','Fyzická újma subjektu údajů (zdraví / svoboda)','Ohrožení fyzického zdraví, tělesné integrity, osobní bezpečnosti nebo svobody dotčených fyzických osob (např. při úniku citlivých zdravotních či lokalizačních údajů).','Hodnotí se od drobného zdravotního či bezpečnostního rizika po přímé ohrožení zdraví a života občanů.','');

	-- 0. Úklid zastaralých systémových záznamů (0x00, who_modified = 0x00), které již nejsou v @src
	DELETE t
	FROM impact_area t
	LEFT JOIN @src s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.who_modified = @sys_owner
	  AND t.record_type IN ('A', 'L')
	  AND s.builtin_code IS NULL;

	-- 1. Aktualizace nemodifikovaných 'A' záznamů
	UPDATE t
	SET t.sort_code = s.sort_code,
		t.is_leaf = s.is_leaf,
		t.external_code = s.external_code,
		t.shortname = s.shortname,
		t.caption = s.caption,
		t.description_text = s.description_text,
		t.help_text = s.help_text,
		t.svg_icon = CASE WHEN ISNULL(t.svg_icon, '') = '' AND s.svg_icon <> '' THEN s.svg_icon ELSE t.svg_icon END,
		t.[language] = 'cs',
		t.date_modified = @now
	FROM impact_area t
	JOIN @src s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.record_type = 'A'
	  AND t.who_modified = @sys_owner
	  AND EXISTS (
		SELECT t.sort_code, t.is_leaf, t.external_code, t.shortname, t.caption, t.description_text, t.help_text
		EXCEPT
		SELECT s.sort_code, s.is_leaf, s.external_code, s.shortname, s.caption, s.description_text, s.help_text
	  );

	-- 2. Vložení chybějících 'A' záznamů
	INSERT INTO impact_area (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf,
		external_code, shortname, caption, description_text, help_text, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
		s.builtin_code, p.parent_orig, s.sort_code, s.is_leaf,
		s.external_code, s.shortname, s.caption, s.description_text, s.help_text, s.svg_icon,
		0, 1,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	CROSS APPLY (SELECT dbo.f_generate_original('impact_area', @sys_owner, s.builtin_code, '') AS orig) x
	OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('impact_area', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
	WHERE NOT EXISTS (
		SELECT 1 FROM impact_area t
		WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
	);

	-- Doplnění/sjednocení parent_uuid u nemodifikovaných záznamů
	UPDATE t
	SET t.parent_uuid = p.parent_orig,
		t.date_modified = @now
	FROM impact_area t
	JOIN @src s ON s.builtin_code = t.builtin_code
	OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('impact_area', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
	WHERE t.object_owner = @sys_owner
	  AND t.record_type IN ('A', 'L')
	  AND t.who_modified = @sys_owner
	  AND EXISTS (SELECT t.parent_uuid EXCEPT SELECT p.parent_orig);

	-- 3. Synchronizace českých 'L' záznamů
	UPDATE l
	SET l.sort_code = a.sort_code,
		l.is_leaf = a.is_leaf,
		l.external_code = a.external_code,
		l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM impact_area l
	JOIN impact_area a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN @src s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
	  AND l.who_modified = @sys_owner
	  AND EXISTS (
		SELECT l.sort_code, l.is_leaf, l.external_code, l.shortname, l.caption, l.description_text, l.help_text
		EXCEPT
		SELECT a.sort_code, a.is_leaf, a.external_code, s.shortname, s.caption, s.description_text, s.help_text
	  );

	INSERT INTO impact_area (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf,
		external_code, shortname, caption, description_text, help_text, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf,
		a.external_code, s.shortname, s.caption, s.description_text, s.help_text, a.svg_icon,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	JOIN impact_area a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM impact_area l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
	);

	IF OBJECT_ID('dbo.p_sync_derived_links', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_derived_links;
	END
END
GO