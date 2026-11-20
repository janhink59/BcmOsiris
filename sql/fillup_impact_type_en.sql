/* =============================================================================
 * Verze: 2026-11-20 17:15
 * Soubor: fillup_impact_type_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en', record_type = 'L')
 *    pro stromový katalog druhů dopadů v tabulce impact_type (object_owner = 0x00,
 *    5 složek + 29 koncových druhů dopadů = 34 uzlů) včetně automatického úklidu
 *    osiřelých systémových 'L' záznamů (who_modified = 0x00).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_impact_type.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulky impact_type.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      systémovými záznamy (object_owner = 0x00) bez závislosti na dbsession.
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('impact_type', 'U') IS NOT NULL
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
	('it_comm_insertion','Ins','Insertion of False Message','Intentional injection of a forged message, command, or transaction into a communication channel.','Evaluated for communication interfaces, payment systems, and integration gateways.'),
	('it_comm_mis_routing','Mr','Mis-routing of Message / Data','Delivery of transmitted data or messages to the wrong recipient due to routing error or manipulation.','May lead to both confidentiality breaches and unavailability for the intended recipient.'),
	('it_comm_non_delivery','Nd','Non-delivery of Message / Data','Loss or blocking of a message in transit without delivery to the intended recipient.','Critical for electronic registries, orders, payment instructions, and control commands.'),
	('it_comm_out_of_seq','Os','Out-of-sequence Messages / Data Blocks','Delivery of messages or transactions in the wrong chronological order causing state inconsistency.','Significant for accounting, inventory, and distributed database systems.'),
	('it_comm_replay','Rp','Message / Data Replay','Repeated submission or processing of a previously valid message or transaction.','Can cause duplicate payments, repeated orders, or authentication bypass.'),
	('it_comm_repud_origin','Ro','Repudiation of Message / Data Origin','The sender subsequently denies having sent or approved a message, order, or instruction.','Requires non-repudiation of origin (digital signatures, immutable audit trail).'),
	('it_comm_repud_rec','Rc','Repudiation of Message / Data Receipt','The recipient subsequently denies having properly received a message, document, or instruction.','Important for contractual, regulatory, and commercial electronic communication.'),
	('it_comm_traffic_mon','Tm','Communication Traffic Monitoring','Unauthorized observation of volume, timing, or metadata of network traffic (traffic analysis).','Can reveal sensitive business relationships or operational patterns even with encrypted payloads.'),
	('it_destr_full','DT','Complete Loss of All Data','Irreversible destruction of production data and backups (e.g., ransomware wiping backups or fire without offsite backup).','Highest level of data asset damage with potential existential impact.'),
	('it_destr_part','DP','Data Loss Since Last Backup','Loss of transactions and changes made since the last usable backup (corresponds to RPO).','Requires manual re-entry of data or reconstruction from supporting records.'),
	('it_discl_csp','CSP','Unauthorized Disclosure to Service Providers (CSP)','Exposure of stored information to external vendors or contracted service providers beyond their authorization.','Affected parties are bound by contract / NDA, yet it remains a confidentiality breach.'),
	('it_discl_identifiable','I','Unauthorized Disclosure to Identifiable Persons','Exposure of stored information to internal staff, temporary workers, or other identifiable contracted persons without authorization.','Narrowest disclosure scope (internal environment), yet may cause harm or GDPR violation.'),
	('it_discl_outsiders','O','Unauthorized Disclosure to Outsiders','Leakage or publication of stored information to unidentified external parties, competitors, or the general public.','Highest level of confidentiality breach carrying regulatory fines, reputational loss, and commercial damages.'),
	('it_grp_availability','Availability','Information & Service Availability Threat','Impacts of unplanned outage or unavailability of a system, application, data, or service depending on downtime duration.','Evaluated across time intervals from 15 minutes to 2+ months; severity is non-decreasing with duration.'),
	('it_grp_communication','Communication','Communication Integrity Threat','Consequences of tampering with or disrupting messages and data transmitted across networks and interfaces.','Covers false message insertion, repudiation of origin/receipt, non-delivery, replay, mis-routing, traffic monitoring, and out-of-sequence delivery.'),
	('it_grp_confidentiality','Confidentiality','Information Confidentiality Threat','Consequences of unauthorized disclosure or exposure of stored information based on the scope of unauthorized recipients.','Distinguishes disclosure to internal staff, contracted service providers, and outsiders (public / competitors).'),
	('it_grp_destruction','Loss / Destr.','Data Loss & Physical Destruction','Consequences of partial or total data loss or physical destruction of a system and hardware.','Separates data loss since last backup (RPO), complete data loss, and physical infrastructure destruction.'),
	('it_grp_integrity','Integrity','Information Integrity Threat','Consequences of compromising the accuracy, completeness, and authenticity of stored or processed data.','Distinguishes unintentional small-scale or wide-scale errors from deliberate modification.'),
	('it_modif_deliberate','DM','Deliberate Modification of Stored or Transmitted Data','Intentional unauthorized alteration of data in a database, document, or in transit (e.g., fraudulent payment or message alteration).','Often covert compromise with direct financial, legal, or safety consequences.'),
	('it_modif_small','SE','Small-Scale Errors (Typo / Minor Transfer Errors)','Unintentional minor human error (e.g., typo in a single record) or occasional brief communication glitch.','Limited local scope without systemic corruption of the entire database.'),
	('it_modif_wide','WE','Wide-Scale Errors (Systemic / Programming Defects)','Mass unintentional error (e.g., software bug, faulty batch import, or prolonged synchronization failure).','Affects a large number of records and requires costly verification and remediation.'),
	('it_physical_dest','PD','Physical Destruction of System / Asset','Physical destruction of technical equipment, server room, media, or paper archive (e.g., fire, flood, or sabotage).','Includes hardware replacement costs and long-term operational recovery.'),
	('it_unavail_12h','12H','Unavailability – 12 Hours','Unplanned unavailability of a system, application, or service for up to 12 hours (full work shift).','Affects full-day operations and end-of-day closings.'),
	('it_unavail_15m','15M','Unavailability – 15 Minutes','Unplanned unavailability of a system, application, or service for up to 15 minutes.','Critical primarily for real-time control, payment, and safety systems.'),
	('it_unavail_1d','1D','Unavailability – 1 Day','Unplanned unavailability of a system, application, or service for 1 day (24 hours).','Typical threshold for activating contingency plans on key enterprise systems.'),
	('it_unavail_1h','1H','Unavailability – 1 Hour','Unplanned unavailability of a system, application, or service for up to 1 hour.','Noticeable disruption to operators and customer-facing channels.'),
	('it_unavail_1m','1M','Unavailability – 1 Month','Unplanned unavailability of a system, application, or service for 1 month.','Major disruption of monthly closings, billing, payroll, and contractual obligations.'),
	('it_unavail_1w','1W','Unavailability – 1 Week','Unplanned unavailability of a system, application, or service for 1 week.','Significant commercial losses, backlog accumulation, and SLA breaches.'),
	('it_unavail_2d','2D','Unavailability – 2 Days','Unplanned unavailability of a system, application, or service for 2 days (48 hours).','Inability to sustain manual workarounds for core business processes.'),
	('it_unavail_2h','2H','Unavailability – 2 Hours','Unplanned unavailability of a system, application, or service for up to 2 hours.','Exceeds normal tolerance for high-volume operational and customer applications.'),
	('it_unavail_2m','2M+','Unavailability – 2 Months or More','Unplanned unavailability of a system, application, or service for 2 months or longer.','Prolonged or permanent outage threatening the survival of the service or organization.'),
	('it_unavail_2w','2W','Unavailability – 2 Weeks','Unplanned unavailability of a system, application, or service for 2 weeks.','Severe threat to business continuity, client churn, and regulatory sanctions.'),
	('it_unavail_30m','30M','Unavailability – 30 Minutes','Unplanned unavailability of a system, application, or service for up to 30 minutes.','Relevant for high-availability online services, call centers, and production lines.'),
	('it_unavail_3h','3H','Unavailability – 3 Hours','Unplanned unavailability of a system, application, or service for up to 3 hours (half shift).','Causes noticeable productivity loss and disruption of customer service.');

	-- 0. Úklid zastaralých anglických 'L' záznamů (0x00, who_modified = 0x00) mimo @tr
	DELETE l
	FROM impact_type l
	LEFT JOIN @tr s ON s.builtin_code = l.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.who_modified = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
	  AND s.builtin_code IS NULL;

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
	JOIN @tr s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
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
		NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.cia_category, a.duration_minutes,
		a.external_code, s.shortname, s.caption, s.description_text, s.help_text, a.svg_icon,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @tr s
	JOIN impact_type a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM impact_type l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @lang
	);
END
GO