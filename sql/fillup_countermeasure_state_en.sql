/* =============================================================================
 * Verze: 2026-11-20 17:00
 * Soubor: fillup_countermeasure_state_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en', record_type = 'L')
 *    pro číselník stavů zavedení protiopatření v tabulce countermeasure_state.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_countermeasure_state.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulky
 *      countermeasure_state (table_countermeasure_state.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (pracuje nad systémovými
 *      záznamy s object_owner = 0x00, nevyžaduje relaci v dbsession).
 *
 * Změny:
 * - 2026-11-20 17:00: Upraven anglický popis stavu cm_state_na v souladu s
 *   opravou reduction_factor = 0.0000 a risk_factor = 0.0000.
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('countermeasure_state', 'U') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @lang varchar(2) = 'en';
	DECLARE @now datetime = GETDATE();

	DECLARE @tr TABLE (
		builtin_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @tr (builtin_code, shortname, caption, description_text, help_text) VALUES
	('cm_state_implemented', 'Implemented', 'Implemented in operation (unaudited)', 'Countermeasure is deployed in production, but has not yet undergone independent audit or practical effectiveness testing (85% reduction, 15% floor).', 'Standard state for routinely operated technical and organizational controls.'),
	('cm_state_in_progress', 'In Progress', 'Partially implemented / In progress', 'Countermeasure is under implementation or deployed only partially (40% of target reduction, 60% of risk floor).', 'Use during phased rollouts or partial asset coverage.'),
	('cm_state_na', 'Not Applicable', 'Not applicable (compensated)', 'Control is technically or operationally irrelevant for the asset, or addressed by another control (0% reduction, 0% floor — neutral in both risk reduction and floor calculation).', 'Does not enforce the non-implementation minimum risk floor and does not distort the combined reduction of other controls.'),
	('cm_state_none', 'Not Implemented', 'Not implemented (missing)', 'Countermeasure is neither implemented nor started (0% risk reduction, 100% enforcement of non-implementation risk floor).', 'Default state when a missing control is identified. Fully enforces the minimum risk floor (risk_factor) from the countermeasure catalog.'),
	('cm_state_planned', 'Planned / Approved', 'Approved for implementation (planned)', 'Countermeasure is approved with allocated budget/deadline, but only basic awareness is currently active (10% reduction, 90% floor).', 'State between formal approval and start of actual rollout.'),
	('cm_state_verified', 'Verified / Audited', 'Fully implemented and regularly verified', 'Countermeasure is fully operational, documented, and its effectiveness is regularly tested or audited (100% reduction, 0% floor).', 'Highest maturity state providing full reduction effectiveness.');

	UPDATE l
	SET l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM countermeasure_state l
	JOIN countermeasure_state a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN @tr s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
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
		NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
		a.builtin_code, a.sort_code, a.reduction_factor, a.risk_factor, a.color_code, a.is_default,
		s.shortname, s.caption, s.description_text, s.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @tr s
	JOIN countermeasure_state a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM countermeasure_state l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @lang
	);
END
GO