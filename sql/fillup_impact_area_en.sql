/* =============================================================================
 * Verze: 2026-11-20 17:15
 * Soubor: fillup_impact_area_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en', record_type = 'L')
 *    pro stromový katalog oblastí dopadů v tabulce impact_area (object_owner = 0x00,
 *    3 složky perspektiv + 15 koncových oblastí = 18 uzlů) včetně automatického
 *    úklidu osiřelých systémových 'L' záznamů (who_modified = 0x00).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_impact_area.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulky impact_area.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      systémovými záznamy (object_owner = 0x00) bez závislosti na dbsession.
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('impact_area', 'U') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @lang varchar(2) = 'en';
	DECLARE @now datetime = GETDATE();

	DECLARE @tr TABLE (
		builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		shortname varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		description_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		help_text varchar(max) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @tr (builtin_code, shortname, caption, description_text, help_text) VALUES
	('ia_grp_org','Organization','Impacts on Organization','Measurable impacts of security incidents and outages directly affecting the organization (finances, commercial interests, reputation, legal compliance, criminal liability, personal safety, and management).','Core perspective for every organization; individual child areas may be deactivated per tenant if not relevant.'),
	('ia_grp_state','State','Impacts on State & Public Interest','Impacts extending beyond the organization to public order, international relations, public administration, national defence, and intelligence/security interests.','Relevant primarily for public administration bodies, critical infrastructure, and regulated entities (NIS2).'),
	('ia_grp_subject','Data Subject','Impacts on Data Subjects (Citizens / GDPR)','Impacts on the rights, freedoms, health, property, and emotional well-being of affected individuals and citizens.','Essential for Data Protection Impact Assessments (DPIA / GDPR) and public-facing services.'),
	('ia_org_commercial','Commercial','Commercial & Economic Interests','Value of information or advantage to competitors, loss of profit-generating capability, disadvantage in commercial negotiations, or trade secret compromise.','Assessed by commercial value to competitors (from non-commercial value up to major turnover losses threatening organizational viability).'),
	('ia_org_criminal','Criminal','Criminal Acts & Criminal Liability','Facilitating criminal offences, impeding or halting criminal investigations or court proceedings, and criminal liability of responsible persons.','Assessed from facilitating ordinary offences up to serious crimes and halting major investigations.'),
	('ia_org_financial','Financial','Financial Loss / Operational Disruption','Direct and indirect financial losses, recovery and restoration costs, SLA penalties, and lost revenue.','Assessed by financial loss brackets configured in the organization currency.'),
	('ia_org_legal','Legal / Reg.','Legal & Regulatory Obligations','Administrative proceedings, civil litigation, or fines for violating statutory and regulatory duties (GDPR, NIS2, DORA, sector laws).','Assessed by potential fine levels, damages, and possible criminal sentencing ranges.'),
	('ia_org_management','Management','Organization Management & Operations','Inefficient operation of an organizational unit, disruption of governance, disadvantage in strategic negotiations, up to halting major operational components.','Assessed by the scope of internal decision-making and operational disruption.'),
	('ia_org_reputation','Reputation','Loss of Goodwill & Reputation','Adverse effects on internal relations, partner trust, and public standing, causing localized, nationwide, or international negative publicity.','Assessed by geographic reach and duration of negative publicity and customer/partner trust erosion.'),
	('ia_org_safety','Personal Safety','Personal Safety (Health & Life Hazard)','Threat to personal safety, liberty, health, or life of one or more individuals (staff, clients, public).','Assessed from minor harm to a single person up to severe injury or loss of life of one or more persons.'),
	('ia_state_defence','Defence','National Defence & Operational Readiness','Difficulties or damage to the operational readiness or security of armed forces from local level up to exceptionally grave nationwide impairment.','Relevant for defence institutions, defence industry, and critical national infrastructure.'),
	('ia_state_intelligence','Security / Class.','Security & Intelligence Interests (Classified Info)','Harm to national interests corresponding to security classification levels (Restricted, Confidential, Secret, Top Secret).','Maps to statutory classified information tiers from disadvantageous up to exceptionally grave harm to national interests.'),
	('ia_state_international','International','International & Diplomatic Relations','Adverse impact or grave damage to diplomatic relations, international tension, or direct threat to internal stability of friendly states.','Relevant for government bodies, diplomacy, and multinational programs.'),
	('ia_state_public_admin','Public Admin','Public Administration & State Services','Inefficient functioning of a state body, impeding vital public activities, up to halting core public administration services.','Assessed by the impact on state governance and public services delivered to citizens.'),
	('ia_state_public_order','Public Order','Public Order & State Stability','Triggering local protests, demonstrations, pressure actions, nationwide strikes, or threatening state stability.','Relevant for outages of essential services (energy, transport, telecoms, healthcare, finance).'),
	('ia_subj_material','Material Harm','Material (Financial / Property) Harm to Data Subjects','Direct property or financial loss suffered by affected individuals (e.g., payment fraud, identity theft, loss of benefits or services).','Assessed by the extent of financial damage inflicted on individuals or groups of citizens.'),
	('ia_subj_nonmaterial','Non-Material','Non-Material (Moral & Emotional) Harm to Data Subjects','Emotional distress (anger, frustration, loss of privacy, discrimination, reputational harm) to an individual or group resulting from a personal data breach.','Corresponds to GDPR moral and psychological harm assessment and personal data protection guidelines.'),
	('ia_subj_physical','Physical Harm','Physical Harm to Data Subjects (Health / Liberty)','Threat to physical health, bodily integrity, personal safety, or liberty of affected individuals (e.g., exposure of sensitive medical or location data).','Assessed from minor health or safety risks up to direct danger to citizens'' health and lives.');

	-- 0. Úklid zastaralých anglických 'L' záznamů (0x00, who_modified = 0x00) mimo @tr
	DELETE l
	FROM impact_area l
	LEFT JOIN @tr s ON s.builtin_code = l.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.who_modified = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
	  AND s.builtin_code IS NULL;

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
	JOIN @tr s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
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
		NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf,
		a.external_code, s.shortname, s.caption, s.description_text, s.help_text, a.svg_icon,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @tr s
	JOIN impact_area a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM impact_area l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @lang
	);
END
GO