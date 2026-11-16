/* =============================================================================
 * Verze: 2026-11-16 16:25
 * Soubor: fillup_scale_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en', record_type = 'L')
 *    pro výchozí hodnotící škály v tabulce scale a jejich stupně v tabulce
 *    scale_value.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_scale.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulek scale
 *      a scale_value (table_scale.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (pracuje nad systémovými
 *      záznamy s object_owner = 0x00, nevyžaduje relaci v dbsession).
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('scale', 'U') IS NOT NULL AND OBJECT_ID('scale_value', 'U') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @lang varchar(2) = 'en';
	DECLARE @now datetime = GETDATE();

	-- 1. Anglické překlady tabulky scale
	DECLARE @tr_scale TABLE (
		builtin_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @tr_scale (builtin_code, shortname, caption, description_text, help_text) VALUES
	('scale_impact', 'Impact (5 lvl)', 'Five-Level Impact Severity Scale', 'Default primary 5-level scale for assessing scenario impact severity on a 0 to 100% range.', 'Levels: Negligible (0–20%), Minor (20–40%), Moderate (40–60%), Major (60–80%), Critical (80–100%).'),
	('scale_risk', 'Risk (5 lvl)', 'Five-Level Risk Rating Scale (Traffic Light)', 'Default primary 5-level scale for classifying inherent and residual risk on a 0 to 100% range.', 'Used for traffic-light color coding of scenario and asset risk scores.'),
	('scale_threat', 'Threat (5 lvl)', 'Five-Level Threat Frequency & Intensity Scale', 'Default primary 5-level scale for assessing threat likelihood and intensity on a 0 to 100% range.', 'Levels: Very Low (0–20%), Low (20–40%), Medium (40–60%), High (60–80%), Very High (80–100%).'),
	('scale_vulnerability', 'Vulnerability (5 lvl)', 'Five-Level Vulnerability Scale', 'Default primary 5-level scale for assessing asset susceptibility to a threat scenario on a 0 to 100% range.', 'Levels: Negligible (0–20%), Low (20–40%), Medium (40–60%), High (60–80%), Critical (80–100%).');

	UPDATE l
	SET l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM scale l
	JOIN scale a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN @tr_scale s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
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
		NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
		a.builtin_code, a.scale_type, a.initial_levels, a.priority, a.is_default, a.sort_code,
		s.shortname, s.caption, s.description_text, s.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @tr_scale s
	JOIN scale a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM scale l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @lang
	);

	-- 2. Anglické překlady tabulky scale_value
	DECLARE @tr_val TABLE (
		scale_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		builtin_code varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		PRIMARY KEY (scale_code, builtin_code)
	);

	INSERT INTO @tr_val (scale_code, builtin_code, shortname, caption, description_text, help_text) VALUES
	('scale_impact', 'lvl_1', '1 - Negligible', 'Negligible impact', 'No measurable effect on operations, finances, or reputation (0 to 20%).', 'Operations continue without restriction; minor inconveniences are handled by routine operations.'),
	('scale_impact', 'lvl_2', '2 - Minor', 'Minor impact', 'Short-term localized disruption or minor financial cost (20 to 40%).', 'Affects only a small group of internal users without impacting key customer services.'),
	('scale_impact', 'lvl_3', '3 - Moderate', 'Moderate (significant) impact', 'Noticeable degradation of an important service, moderate financial loss, or client complaints (40 to 60%).', 'Requires support intervention and incident management, but does not threaten business continuity.'),
	('scale_impact', 'lvl_4', '4 - Major', 'Major (severe) impact', 'Prolonged outage of a key service, high financial damages, SLA or regulatory breach (60 to 80%).', 'Requires activation of recovery plans (DRP/BCP) and executive escalation.'),
	('scale_impact', 'lvl_5', '5 - Critical', 'Critical (catastrophic) impact', 'Halt of core business activities, threat to life/health, loss of license, or fatal damages (80 to 100%).', 'Highest severity level requiring immediate crisis management.'),
	('scale_risk', 'lvl_1', 'Low', 'Low (acceptable) risk', 'Risk is fully controlled and does not require additional costly countermeasures (0 to 20%).', 'Routine oversight and maintenance of existing controls are sufficient.'),
	('scale_risk', 'lvl_2', 'Moderate', 'Moderate (monitored) risk', 'Risk is tolerable but requires ongoing monitoring and periodic review (20 to 40%).', 'Additional controls are implemented only if low-cost.'),
	('scale_risk', 'lvl_3', 'Medium', 'Medium (elevated) risk', 'Risk requires planning reasonable technical or organizational countermeasures (40 to 60%).', 'Mitigation measures are included in the medium-term risk treatment plan.'),
	('scale_risk', 'lvl_4', 'High', 'High (undesirable) risk', 'Risk exceeds standard organizational tolerance and requires priority reduction (60 to 80%).', 'Countermeasures must be approved and implemented in the short term.'),
	('scale_risk', 'lvl_5', 'Critical', 'Critical (unacceptable) risk', 'Unacceptable risk level requiring immediate executive action and urgent mitigation (80 to 100%).', 'Operation of the affected asset or service may require conditional restriction until compensating controls are in place.'),
	('scale_threat', 'lvl_1', '1 - Very Low', 'Very low (rare) threat', 'Extremely unlikely occurrence (less than once in 10 years, score 0 to 20%).', 'Historically unrecorded or virtually excluded in the given location/sector.'),
	('scale_threat', 'lvl_2', '2 - Low', 'Low (unlikely) threat', 'Infrequent occurrence (approx. once in 3 to 10 years, score 20 to 40%).', 'Occurs rarely, only when unfavorable circumstances coincide.'),
	('scale_threat', 'lvl_3', '3 - Medium', 'Medium (possible) threat', 'Occasional occurrence (approx. once in 1 to 3 years, score 40 to 60%).', 'Recorded in the past within the organization or comparable peers.'),
	('scale_threat', 'lvl_4', '4 - High', 'High (likely) threat', 'Frequent occurrence (several times per year, score 60 to 80%).', 'Common operational, technical, or cyber threat.'),
	('scale_threat', 'lvl_5', '5 - Very High', 'Very high (almost certain) threat', 'Continuous or repeated threat activity (monthly or daily, score 80 to 100%).', 'E.g., automated internet attacks, human inattention, or hardware wear and tear.'),
	('scale_vulnerability', 'lvl_1', '1 - Negligible', 'Negligible vulnerability', 'Asset is robustly protected, redundant, and resilient against the scenario (0 to 20%).', 'Exploitation or failure requires extreme effort or an improbable chain of errors.'),
	('scale_vulnerability', 'lvl_2', '2 - Low', 'Low vulnerability', 'Good security posture with minor, hard-to-exploit weaknesses (20 to 40%).', 'Most standard defensive mechanisms are active and effective.'),
	('scale_vulnerability', 'lvl_3', '3 - Medium', 'Medium vulnerability', 'Partial protection; known weak spots exist or full redundancy is missing (40 to 60%).', 'Targeted attack or significant operational fault may cause a breach or outage.'),
	('scale_vulnerability', 'lvl_4', '4 - High', 'High vulnerability', 'Significant security weaknesses, legacy technology, or missing key controls (60 to 80%).', 'Easily exploitable by known methods or ordinary operational failure.'),
	('scale_vulnerability', 'lvl_5', '5 - Critical', 'Critical vulnerability', 'Completely unprotected asset, Single Point of Failure (SPOF) without any backup (80 to 100%).', 'Any threat occurrence almost immediately leads to full scenario realization.');

	UPDATE l
	SET l.shortname = v.shortname,
		l.caption = v.caption,
		l.description_text = v.description_text,
		l.help_text = v.help_text,
		l.date_modified = @now
	FROM scale_value l
	JOIN scale_value a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN scale sc ON sc.original = a.scale AND sc.object_owner = @sys_owner AND sc.record_type = 'A'
	JOIN @tr_val v ON v.scale_code = sc.builtin_code AND v.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
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
		NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
		a.scale, a.builtin_code, a.threshold_value, a.score_value, a.color_code, a.is_default,
		v.shortname, v.caption, v.description_text, v.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @tr_val v
	JOIN scale sc ON sc.builtin_code = v.scale_code AND sc.object_owner = @sys_owner AND sc.record_type = 'A' AND sc.removed = 0
	JOIN scale_value a ON a.scale = sc.original AND a.builtin_code = v.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM scale_value l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @lang
	);
END
GO