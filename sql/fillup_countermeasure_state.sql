/* =============================================================================
 * Verze: 2026-11-20 17:00
 * Soubor: fillup_countermeasure_state.sql
 *
 * 1. Role souboru v celém systému:
 *    Prvotní idempotentní naplnění plochého číselníku stavů zavedení
 *    protiopatření (tabulka countermeasure_state) pro primární jazyk ('cs').
 *    Definuje váhy účinnosti redukce (reduction_factor 0..100 %) a váhy
 *    uplatnění minimálního prahu rizika při neimplementaci (risk_factor 0..100 %).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Využívá funkci dbo.f_generate_original (generate_trgo.sql).
 *    - Zapisuje do tabulky countermeasure_state (table_countermeasure_state.sql).
 *    - Na tato data navazuje překladový skript fillup_countermeasure_state_en.sql,
 *      procedura dbo.p_crmm_recalculate a stránka page_countermeasure_implementation.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (pracuje nad systémovými
 *      záznamy s object_owner = 0x00, nevyžaduje relaci v dbsession).
 *
 * Změny:
 * - 2026-11-20 17:00: Opraven stav cm_state_na z reduction_factor = 100.0000 na
 *   0.0000 (neaplikovatelné opatření nesmí uměle redukovat riziko scénáře ani
 *   uplatňovat spodní penalizační práh risk_factor = 0.0000).
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('countermeasure_state', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @now datetime = GETDATE();

	DECLARE @src TABLE (
		builtin_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		sort_code varchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
		reduction_factor decimal(9,4) NOT NULL,
		risk_factor decimal(9,4) NOT NULL,
		color_code varchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
		is_default bit NOT NULL,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @src (
		builtin_code, sort_code, reduction_factor, risk_factor, color_code, is_default,
		shortname, caption, description_text, help_text
	) VALUES
	('cm_state_implemented', '040', 85.0000, 15.0000, '#65a30d', 0, 'Zavedeno', 'Zavedeno v provozu (neauditováno)', 'Protiopatření je plně nasazeno do provozu, zatím však neprošlo nezávislým auditem či praktickým testem účinnosti (85 % redukce, 15 % zbytkový práh).', 'Standardní stav pro běžně provozovaná technická a organizační opatření.'),
	('cm_state_in_progress', '030', 40.0000, 60.0000, '#eab308', 0, 'V realizaci', 'Částečně zavedeno / V realizaci', 'Protiopatření je rozpracováno nebo nasazeno pouze částečně (40 % cílové redukce, 60 % rizikového prahu).', 'Použijte při postupném nasazování opatření nebo při částečném pokrytí aktiva.'),
	('cm_state_na', '060', 0.0000, 0.0000, '#64748b', 0, 'Neaplikovatelné', 'Neaplikovatelné (nahrazeno kompenzací)', 'Opatření není pro dané aktivum technicky či provozně relevantní, nebo je řešeno jiným opatřením (0 % redukce, 0 % práh — nevstupuje do výpočtu redukce ani penalizace).', 'Neuplatňuje spodní penalizační práh rizika za neimplementaci a nijak nezkresluje souhrnnou redukci ostatních opatření.'),
	('cm_state_none', '010', 0.0000, 100.0000, '#dc2626', 1, 'Nezavedeno', 'Nezavedeno (chybí)', 'Protiopatření není zavedeno ani zahájeno (0 % redukce rizika, 100 % uplatnění prahu rizika neimplementace).', 'Výchozí stav při zjištění chybějícího opatření. Plně uplatňuje spodní práh rizika (risk_factor) z katalogu protiopatření.'),
	('cm_state_planned', '020', 10.0000, 90.0000, '#ea580c', 0, 'Schváleno v plánu', 'Schváleno k realizaci (v plánu)', 'Opatření je schváleno a má přidělený rozpočet/termín, v provozu však zatím působí jen základní povědomí (10 % redukce, 90 % prahu).', 'Stav mezi rozhodnutím o zavedení a zahájením vlastní implementace.'),
	('cm_state_verified', '050', 100.0000, 0.0000, '#16a34a', 0, 'Ověřeno / Auditováno', 'Plně zavedeno a pravidelně ověřováno', 'Protiopatření je plně funkční, dokumentované a jeho účinnost je pravidelně testována nebo auditována (100 % redukce, 0 % práh).', 'Nejvyšší stupeň zralosti protiopatření poskytující plný redukční účinek.');

	-- 1. Aktualizace nemodifikovaných 'A' záznamů
	UPDATE t
	SET t.sort_code = s.sort_code,
		t.reduction_factor = s.reduction_factor,
		t.risk_factor = s.risk_factor,
		t.color_code = s.color_code,
		t.is_default = s.is_default,
		t.shortname = s.shortname,
		t.caption = s.caption,
		t.description_text = s.description_text,
		t.help_text = s.help_text,
		t.[language] = 'cs',
		t.date_modified = @now
	FROM countermeasure_state t
	JOIN @src s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.record_type = 'A'
	  AND t.who_modified = @sys_owner
	  AND EXISTS (
		SELECT t.sort_code, t.reduction_factor, t.risk_factor, t.color_code, t.is_default, t.shortname, t.caption, t.description_text, t.help_text
		EXCEPT
		SELECT s.sort_code, s.reduction_factor, s.risk_factor, s.color_code, s.is_default, s.shortname, s.caption, s.description_text, s.help_text
	  );

	-- 2. Vložení chybějících 'A' záznamů
	INSERT INTO countermeasure_state (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, sort_code, reduction_factor, risk_factor, color_code, is_default,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
		s.builtin_code, s.sort_code, s.reduction_factor, s.risk_factor, s.color_code, s.is_default,
		s.shortname, s.caption, s.description_text, s.help_text,
		1, 1,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	CROSS APPLY (SELECT dbo.f_generate_original('countermeasure_state', @sys_owner, s.builtin_code, '') AS orig) x
	WHERE NOT EXISTS (
		SELECT 1 FROM countermeasure_state t
		WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
	);

	-- 3. Synchronizace českých 'L' záznamů
	UPDATE l
	SET l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM countermeasure_state l
	JOIN countermeasure_state a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
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

	INSERT INTO countermeasure_state (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, sort_code, reduction_factor, risk_factor, color_code, is_default,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
		a.builtin_code, a.sort_code, a.reduction_factor, a.risk_factor, a.color_code, a.is_default,
		s.shortname, s.caption, s.description_text, s.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @src s
	JOIN countermeasure_state a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM countermeasure_state l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
	);
END
GO