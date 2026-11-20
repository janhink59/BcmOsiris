/* =============================================================================
 * Verze: 2026-11-20 15:50
 * Soubor: fillup_scale.sql
 *
 * 1. Role souboru v celém systému:
 *    Prvotní idempotentní naplnění katalogu hodnotících škál (tabulka scale)
 *    a jejich stupňů (tabulka scale_value) pro primární jazyk ('cs').
 *    Zakládá 4 výchozí pětistupňové škály (0..100 %):
 *    - scale_threat        (THREAT)
 *    - scale_vulnerability (VULNERABILITY)
 *    - scale_impact        (IMPACT)
 *    - scale_risk          (RISK)
 *    a k nim 20 stupňů v tabulce scale_value s rovnoměrnými prahy
 *    (0, 20, 40, 60, 80 %) a bodovými skóre uprostřed intervalu
 *    (10, 30, 50, 70, 90 %).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Využívá funkci dbo.f_generate_original (generate_trgo.sql).
 *    - Zapisuje do tabulek scale a scale_value (table_scale.sql).
 *    - Na tato data navazuje překladový skript fillup_scale_en.sql, stránky
 *      page_scale.php, page_scale_value.php a funkce resolve_scale_level_badge()
 *      v new_functions.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (pracuje nad systémovými
 *      záznamy s object_owner = 0x00, nevyžaduje relaci v dbsession).
 *
 * Změny:
 * - 2026-11-20 15:50: Opraven překlep se znaky cyrilice v popisu lvl_4 u
 *   scale_vulnerability ('zastaralá technologie').
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('scale', 'U') IS NOT NULL
   AND OBJECT_ID('scale_value', 'U') IS NOT NULL
   AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @now datetime = GETDATE();

	-- =========================================================================
	-- 1. DEFINICE VÝCHOZÍCH ŠKÁL V TABULCE scale
	-- =========================================================================
	DECLARE @src_scale TABLE (
		builtin_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		scale_type varchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
		initial_levels int NOT NULL,
		priority int NOT NULL,
		is_default bit NOT NULL,
		sort_code varchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @src_scale (
		builtin_code, scale_type, initial_levels, priority, is_default, sort_code,
		shortname, caption, description_text, help_text
	) VALUES
	('scale_impact', 'IMPACT', 5, 10, 1, '030', 'Dopad (5 st.)', 'Pětistupňová škála velikosti dopadu', 'Výchozí primární pětistupňová škála pro hodnocení závažnosti dopadů scénářů v intervalu 0 až 100 %.', 'Stupně: Zanedbatelný (0–20 %), Malý (20–40 %), Střední (40–60 %), Velký (60–80 %), Kritický (80–100 %).'),
	('scale_risk', 'RISK', 5, 10, 1, '040', 'Riziko (5 st.)', 'Pětistupňová škála úrovně rizika (Semafor)', 'Výchozí primární pětistupňová škála pro klasifikaci inherentního a zbytkového rizika v intervalu 0 až 100 %.', 'Slouží pro barevnou indikaci (semafor) výsledného rizika scénářů a aktiv.'),
	('scale_threat', 'THREAT', 5, 10, 1, '010', 'Hrozba (5 st.)', 'Pětistupňová škála frekvence a síly hrozby', 'Výchozí primární pětistupňová škála pro hodnocení pravděpodobnosti/intenzity působení hrozby v intervalu 0 až 100 %.', 'Stupně: Velmi nízká (0–20 %), Nízká (20–40 %), Střední (40–60 %), Vysoká (60–80 %), Velmi vysoká (80–100 %).'),
	('scale_vulnerability', 'VULNERABILITY', 5, 10, 1, '020', 'Zranitelnost (5 st.)', 'Pětistupňová škála míry zranitelnosti', 'Výchozí primární pětistupňová škála pro hodnocení náchylnosti aktiva vůči scénáři hrozby v intervalu 0 až 100 %.', 'Stupně: Zanedbatelná (0–20 %), Nízká (20–40 %), Střední (40–60 %), Vysoká (60–80 %), Kritická (80–100 %).');

	-- 1a. Aktualizace nemodifikovaných 'A' záznamů v tabulce scale
	UPDATE t
	SET t.scale_type = s.scale_type,
		t.initial_levels = s.initial_levels,
		t.priority = s.priority,
		t.is_default = s.is_default,
		t.sort_code = s.sort_code,
		t.shortname = s.shortname,
		t.caption = s.caption,
		t.description_text = s.description_text,
		t.help_text = s.help_text,
		t.[language] = 'cs',
		t.date_modified = @now
	FROM scale t
	JOIN @src_scale s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.record_type = 'A'
	  AND t.who_modified = @sys_owner
	  AND EXISTS (
		SELECT t.scale_type, t.initial_levels, t.priority, t.is_default, t.sort_code, t.shortname, t.caption, t.description_text, t.help_text
		EXCEPT
		SELECT s.scale_type, s.initial_levels, s.priority, s.is_default, s.sort_code, s.shortname, s.caption, s.description_text, s.help_text
	  );

	-- 1b. Vložení chybějících 'A' záznamů do tabulky scale
	INSERT INTO scale (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, scale_type, initial_levels, priority, is_default, sort_code,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
		s.builtin_code, s.scale_type, s.initial_levels, s.priority, s.is_default, s.sort_code,
		s.shortname, s.caption, s.description_text, s.help_text,
		1, 1,
		@now, @sys_owner, @now, @sys_owner
	FROM @src_scale s
	CROSS APPLY (SELECT dbo.f_generate_original('scale', @sys_owner, s.builtin_code, '') AS orig) x
	WHERE NOT EXISTS (
		SELECT 1 FROM scale t
		WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
	);

	-- 1c. Synchronizace českých 'L' záznamů v tabulce scale
	UPDATE l
	SET l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM scale l
	JOIN scale a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN @src_scale s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
	  AND l.who_modified = @sys_owner
	  AND EXISTS (
		SELECT l.shortname, l.caption, l.description_text, l.help_text
		EXCEPT
		SELECT s.shortname, s.caption, s.description_text, s.help_text
	  );

	INSERT INTO scale (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, scale_type, initial_levels, priority, is_default, sort_code,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
		a.builtin_code, a.scale_type, a.initial_levels, a.priority, a.is_default, a.sort_code,
		s.shortname, s.caption, s.description_text, s.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @src_scale s
	JOIN scale a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM scale l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
	);

	-- =========================================================================
	-- 2. DEFINICE STUPŇŮ ŠKÁL V TABULCE scale_value
	-- =========================================================================
	DECLARE @src_val TABLE (
		scale_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		builtin_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		threshold_value decimal(9,4) NOT NULL,
		score_value decimal(9,4) NOT NULL,
		color_code varchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
		is_default bit NOT NULL,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		PRIMARY KEY (scale_code, builtin_code)
	);

	INSERT INTO @src_val (
		scale_code, builtin_code, threshold_value, score_value, color_code, is_default,
		shortname, caption, description_text, help_text
	) VALUES
	('scale_impact', 'lvl_1', 0.0000, 10.0000, '#16a34a', 1, '1 - Zanedbatelný', 'Zanedbatelný dopad', 'Bez měřitelného vlivu na provoz, finance nebo reputaci organizace (0 až 20 %).', 'Provoz pokračuje bez omezení, případné drobné nepohodlí je vyřešeno běžnou operativou.'),
	('scale_impact', 'lvl_2', 20.0000, 30.0000, '#65a30d', 0, '2 - Malý', 'Malý dopad', 'Krátkodobé lokální narušení nebo drobné finanční náklady (20 až 40 %).', 'Dotčena je pouze menší část interních uživatelů bez dopadu na klíčové zákaznické služby.'),
	('scale_impact', 'lvl_3', 40.0000, 50.0000, '#eab308', 0, '3 - Střední', 'Střední (významný) dopad', 'Citelná degradace důležité služby, znatelná finanční ztráta nebo stížnosti klientů (40 až 60 %).', 'Vyžaduje zásah podpory a řízení incidentu, avšak neohrožuje existenci organizace.'),
	('scale_impact', 'lvl_4', 60.0000, 70.0000, '#ea580c', 0, '4 - Velký', 'Velký (závažný) dopad', 'Dlouhodobý výpadek klíčové služby, vysoké finanční škody, porušení SLA nebo zákona (60 až 80 %).', 'Vyžaduje aktivaci plánu obnovy (DRP/BCP) a eskalaci na vrcholové vedení.'),
	('scale_impact', 'lvl_5', 80.0000, 90.0000, '#dc2626', 0, '5 - Kritický', 'Kritický (katastrofický) dopad', 'Zastavení hlavních činností organizace, ohrožení zdraví/životů, ztráta licence nebo fatální škody (80 až 100 %).', 'Nejvyšší stupeň závažnosti vyžadující okamžité krizové řízení.'),
	('scale_risk', 'lvl_1', 0.0000, 10.0000, '#16a34a', 1, 'Nízké', 'Nízké (akceptovatelné) riziko', 'Riziko je plně pod kontrolou a nevyžaduje zavádění dalších nákladných opatření (0 až 20 %).', 'Postačuje běžný dohled a udržování stávajících kontrol.'),
	('scale_risk', 'lvl_2', 20.0000, 30.0000, '#65a30d', 0, 'Mírné', 'Mírné (sledované) riziko', 'Riziko je přijatelné, avšak vyžaduje průběžné monitorování a občasnou kontrolu (20 až 40 %).', 'Případná opatření se realizují pouze tehdy, jsou-li nízkonákladová.'),
	('scale_risk', 'lvl_3', 40.0000, 50.0000, '#eab308', 0, 'Střední', 'Střední (zvýšené) riziko', 'Riziko vyžaduje naplánování přiměřených technických nebo organizačních protiopatření (40 až 60 %).', 'Návrh opatření se zařazuje do střednědobého plánu snižování rizik.'),
	('scale_risk', 'lvl_4', 60.0000, 70.0000, '#ea580c', 0, 'Vysoké', 'Vysoké (nežádoucí) riziko', 'Riziko převyšuje běžnou toleranci organizace a vyžaduje prioritní redukci (60 až 80 %).', 'Opatření musí být schválena a realizována v krátkodobém horizontu.'),
	('scale_risk', 'lvl_5', 80.0000, 90.0000, '#dc2626', 0, 'Kritické', 'Kritické (nepřijatelné) riziko', 'Nepřijatelná úroveň rizika vyžadující okamžitý zásah vedení a bezodkladná opatření (80 až 100 %).', 'Provoz dotčeného aktiva nebo služby může vyžadovat podmíněné omezení do zavedení kompenzačních opatření.'),
	('scale_threat', 'lvl_1', 0.0000, 10.0000, '#16a34a', 1, '1 - Velmi nízká', 'Velmi nízká (ojedinělá) hrozba', 'Mimořádně nepravděpodobný výskyt (méně než 1× za 10 let, skóre 0 až 20 %).', 'Historicky nezaznamenáno nebo téměř vyloučeno v dané lokalitě/odvětví.'),
	('scale_threat', 'lvl_2', 20.0000, 30.0000, '#65a30d', 0, '2 - Nízká', 'Nízká (méně pravděpodobná) hrozba', 'Ojedinělý výskyt (zhruba 1× za 3 až 10 let, skóre 20 až 40 %).', 'Hrozba se vyskytuje zřídka, pouze při souběhu nepříznivých okolností.'),
	('scale_threat', 'lvl_3', 40.0000, 50.0000, '#eab308', 0, '3 - Střední', 'Střední (možná) hrozba', 'Občasný výskyt (zhruba 1× za 1 až 3 roky, skóre 40 až 60 %).', 'Hrozba byla v minulosti zaznamenána u organizace nebo u srovnatelných subjektů.'),
	('scale_threat', 'lvl_4', 60.0000, 70.0000, '#ea580c', 0, '4 - Vysoká', 'Vysoká (pravděpodobná) hrozba', 'Častý výskyt (několikrát ročně, skóre 60 až 80 %).', 'Běžně se vyskytující provozní, technická nebo kybernetická hrozba.'),
	('scale_threat', 'lvl_5', 80.0000, 90.0000, '#dc2626', 0, '5 - Velmi vysoká', 'Velmi vysoká (téměř jistá) hrozba', 'Trvalé nebo opakované působení hrozby (měsíčně či denně, skóre 80 až 100 %).', 'Např. automatizované útoky z internetu, lidská nepozornost nebo opotřebení techniky.'),
	('scale_vulnerability', 'lvl_1', 0.0000, 10.0000, '#16a34a', 1, '1 - Zanedbatelná', 'Zanedbatelná zranitelnost', 'Aktivum je robustně chráněno, redundantní a odolné vůči danému scénáři (0 až 20 %).', 'Zneužití nebo selhání vyžaduje extrémní úsilí či nepravděpodobnou souhru chyb.'),
	('scale_vulnerability', 'lvl_2', 20.0000, 30.0000, '#65a30d', 0, '2 - Nízká', 'Nízká zranitelnost', 'Dobrá úroveň zabezpečení s drobnými, obtížně zneužitelnými slabinami (20 až 40 %).', 'Většina standardních obranných mechanismů je funkční.'),
	('scale_vulnerability', 'lvl_3', 40.0000, 50.0000, '#eab308', 0, '3 - Střední', 'Střední zranitelnost', 'Částečná ochrana, existují známá slabá místa nebo chybí plná redundance (40 až 60 %).', 'Při cíleném útoku nebo větší provozní závadě může dojít k prolomení.'),
	('scale_vulnerability', 'lvl_4', 60.0000, 70.0000, '#ea580c', 0, '4 - Vysoká', 'Vysoká zranitelnost', 'Výrazné slabiny v zabezpečení, zastaralá technologie nebo chybějící klíčové kontroly (60 až 80 %).', 'Snadno zneužitelné známými postupy nebo běžnou provozní poruchou.'),
	('scale_vulnerability', 'lvl_5', 80.0000, 90.0000, '#dc2626', 0, '5 - Kritická', 'Kritická zranitelnost', 'Zcela nechráněné aktivum, Single Point of Failure (SPOF) bez jakékoliv zálohy (80 až 100 %).', 'Jakékoliv působení hrozby vede téměř okamžitě k naplnění negativního scénáře.');

	-- 2a. Aktualizace nemodifikovaných 'A' záznamů v tabulce scale_value
	UPDATE sv
	SET sv.threshold_value = v.threshold_value,
		sv.score_value = v.score_value,
		sv.color_code = v.color_code,
		sv.is_default = v.is_default,
		sv.shortname = v.shortname,
		sv.caption = v.caption,
		sv.description_text = v.description_text,
		sv.help_text = v.help_text,
		sv.[language] = 'cs',
		sv.date_modified = @now
	FROM scale_value sv
	JOIN scale sc ON sc.original = sv.scale AND sc.object_owner = @sys_owner AND sc.record_type = 'A'
	JOIN @src_val v ON v.scale_code = sc.builtin_code AND v.builtin_code = sv.builtin_code
	WHERE sv.object_owner = @sys_owner
	  AND sv.record_type = 'A'
	  AND sv.who_modified = @sys_owner
	  AND EXISTS (
		SELECT sv.threshold_value, sv.score_value, sv.color_code, sv.is_default, sv.shortname, sv.caption, sv.description_text, sv.help_text
		EXCEPT
		SELECT v.threshold_value, v.score_value, v.color_code, v.is_default, v.shortname, v.caption, v.description_text, v.help_text
	  );

	-- 2b. Vložení chybějících 'A' záznamů do tabulky scale_value
	INSERT INTO scale_value (
		uuid, object_owner, original, record_type, approval_status, [language],
		scale, builtin_code, threshold_value, score_value, color_code, is_default,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
		sc.original, v.builtin_code, v.threshold_value, v.score_value, v.color_code, v.is_default,
		v.shortname, v.caption, v.description_text, v.help_text,
		1, 1,
		@now, @sys_owner, @now, @sys_owner
	FROM @src_val v
	JOIN scale sc ON sc.builtin_code = v.scale_code AND sc.object_owner = @sys_owner AND sc.record_type = 'A' AND sc.removed = 0
	CROSS APPLY (SELECT dbo.f_generate_original('scale_value', @sys_owner, CAST(sc.original AS varchar(36)), v.builtin_code) AS orig) x
	WHERE NOT EXISTS (
		SELECT 1 FROM scale_value sv
		WHERE sv.original = x.orig AND sv.object_owner = @sys_owner AND sv.record_type = 'A'
	);

	-- 2c. Synchronizace českých 'L' záznamů v tabulce scale_value
	UPDATE l
	SET l.shortname = v.shortname,
		l.caption = v.caption,
		l.description_text = v.description_text,
		l.help_text = v.help_text,
		l.date_modified = @now
	FROM scale_value l
	JOIN scale_value a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN scale sc ON sc.original = a.scale AND sc.object_owner = @sys_owner AND sc.record_type = 'A'
	JOIN @src_val v ON v.scale_code = sc.builtin_code AND v.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
	  AND l.who_modified = @sys_owner
	  AND EXISTS (
		SELECT l.shortname, l.caption, l.description_text, l.help_text
		EXCEPT
		SELECT v.shortname, v.caption, v.description_text, v.help_text
	  );

	INSERT INTO scale_value (
		uuid, object_owner, original, record_type, approval_status, [language],
		scale, builtin_code, threshold_value, score_value, color_code, is_default,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
		a.scale, a.builtin_code, a.threshold_value, a.score_value, a.color_code, a.is_default,
		v.shortname, v.caption, v.description_text, v.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @src_val v
	JOIN scale sc ON sc.builtin_code = v.scale_code AND sc.object_owner = @sys_owner AND sc.record_type = 'A' AND sc.removed = 0
	JOIN scale_value a ON a.scale = sc.original AND a.builtin_code = v.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM scale_value l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
	);
END
GO