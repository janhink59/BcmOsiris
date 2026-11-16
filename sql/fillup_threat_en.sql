/* =============================================================================
 * Verze: 2026-11-16 16:25
 * Soubor: fillup_threat_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en', record_type = 'L')
 *    pro stromový katalog hrozeb v tabulce threat.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_threat.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulky threat
 *      (table_threat.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (pracuje nad systémovými
 *      záznamy s object_owner = 0x00, nevyžaduje relaci v dbsession).
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('threat', 'U') IS NOT NULL
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
	('thr_cyber_ddos', 'DDoS Attack', 'Denial of Service / Network Flooding (DoS / DDoS)', 'Targeted flooding of network connectivity, firewalls, or application servers with overwhelming request volume.', 'Threatens availability of externally published services, portals, and communication interfaces.'),
	('thr_cyber_exfiltration', 'Data Breach / Theft', 'Unauthorized Access and Sensitive Data Exfiltration', 'Gaining unauthorized access to databases, repositories, or documents to steal or disclose confidential data.', 'Leads to confidentiality breaches, GDPR/NIS2 penalties, and reputational damage.'),
	('thr_cyber_phishing', 'Phishing / Soc. Eng.', 'Phishing, Identity Spoofing, and Social Engineering', 'Manipulating staff via fraudulent emails, messages, or calls to harvest credentials or authorize fraudulent transactions.', 'Frequently serves as the initial entry vector for ransomware or account compromise.'),
	('thr_cyber_ransomware', 'Ransomware / Malware', 'Malicious Code and Encryption Attack (Ransomware)', 'Infiltration of malicious code that encrypts servers, workstations, and accessible network storage while demanding ransom.', 'Critical threat to IT infrastructure availability and data integrity.'),
	('thr_grp_cyber', 'Cyber Attacks', 'Cyber and Intentional Attacks', 'Intentional external and internal attacks conducted over networks, application interfaces, or via social engineering.', 'Folder covering malware, ransomware, phishing, DDoS, and data exfiltration.'),
	('thr_grp_human', 'Human Factor', 'Human Factor and Personnel Threats', 'Unintentional operator errors, loss of equipment, unavailability of key staff, or intentional insider sabotage.', 'Folder covering threats related to employees, administrators, and internal users.'),
	('thr_grp_org', 'Suppliers & Processes', 'Organizational, Supplier, and Legal Threats', 'Third-party failures, key supplier outages, regulatory non-compliance, and internal process failures.', 'Folder covering supply chain, cloud providers, and compliance.'),
	('thr_grp_phys', 'Physical & Environmental', 'Physical, Environmental, and Natural Threats', 'Fires, floods, extreme weather events, utility outages, and physical intrusion into premises.', 'Folder covering threats affecting sites, buildings, server rooms, and physical equipment.'),
	('thr_grp_tech', 'Technical & IT', 'Technical Failures of HW, SW, and Infrastructure', 'Server, storage array, and network device failures, software bugs, backup failures, and capacity exhaustion.', 'Folder covering technical and operational faults without requiring an intentional attacker.'),
	('thr_hum_admin_err', 'Admin Error', 'Administrator Error or Misconfiguration', 'Accidental deletion of a production database, routing misconfiguration, disabling security controls, or faulty deployment.', 'Can cause immediate widespread outage or unintended data exposure.'),
	('thr_hum_insider', 'Insider Sabotage', 'Intentional Misuse of Privileges by Insider', 'Data theft, system sabotage, or unauthorized operations performed by a disgruntled or former employee.', 'Risk increases when privileged accounts are unmonitored or access revocation is delayed.'),
	('thr_hum_key_person', 'Key Person Loss', 'Unavailability or Departure of Key Specialist', 'Sudden illness, injury, or departure of an employee holding unique know-how without backup staff or documentation.', 'Threatens recovery capability and maintenance of specialized applications and processes.'),
	('thr_hum_user_err', 'Operator Error', 'Unintentional User or Operator Error', 'Incorrect data entry or overwrite, accidental file deletion, or sending sensitive documents to the wrong recipient.', 'Most frequent operational threat affecting data integrity and confidentiality.'),
	('thr_org_compliance', 'Non-Compliance', 'Breach of Regulatory, Legal, or Contractual Obligations', 'Failure to meet cybersecurity requirements (NIS2), data protection rules (GDPR), license terms, or customer SLAs.', 'Leads to financial fines, regulatory audits, and loss of customer trust.'),
	('thr_org_isp_outage', 'Telecom Outage', 'Internet Service Provider or Interface Outage', 'Disruption of data, voice, or cloud connectivity on the external telecom operator side.', 'Disconnects branch offices, remote workers, and published customer services.'),
	('thr_org_process_fail', 'Change Mgmt Failure', 'Internal Process Failure or Uncontrolled Change', 'Untested production change, unclear accountability, or outdated emergency procedures.', 'Increases downtime duration and likelihood of cascading errors during an incident.'),
	('thr_org_supplier_outage', 'Supplier Outage', 'Key Supplier Outage or Business Termination', 'Unavailability of outsourced service, SaaS platform, maintenance support, or supply chain compromise.', 'Critical especially for single-source suppliers (Vendor Lock-in).'),
	('thr_phys_fire', 'Fire / Smoke', 'Fire or Smoke in Building or Server Room', 'Fire caused by electrical short circuit, equipment overheating, or material ignition.', 'Causes destruction of hardware, cabling, paper documents, and long-term facility unavailability.'),
	('thr_phys_hvac', 'HVAC / Cooling Failure', 'Cooling and Air Conditioning Failure in Tech Room', 'Failure of server room HVAC unit leading to rapid overheating and emergency thermal shutdown of servers.', 'Common cause of forced IT equipment downtime during summer months.'),
	('thr_phys_intrusion', 'Physical Intrusion', 'Unauthorized Physical Intrusion, Theft, or Vandalism', 'Entry of unauthorized person into building or room, theft of hardware/media, or physical damage to equipment.', 'Threatens both equipment availability and confidentiality of unencrypted media.'),
	('thr_phys_power', 'Power Outage', 'Prolonged Electrical Power Outage', 'Grid power interruption exceeding the runtime capacity of uninterruptible power supplies (UPS).', 'Affects all equipment, lighting, cooling, and access control systems in the building.'),
	('thr_phys_water', 'Water / Flood', 'Water Leakage, Pipe Burst, or Flooding', 'Flooding of premises due to burst water/heating pipes, torrential rain, or river flood.', 'High risk for basement areas, server rooms beneath water pipes, and document archives.'),
	('thr_tech_capacity', 'Capacity Exhaustion', 'Compute, Memory, or Disk Capacity Exhaustion', 'Disk space exhaustion (logs, databases), RAM depletion, or CPU saturation.', 'Causes application freezes, transaction write failures, and rejection of user requests.'),
	('thr_tech_hw_fail', 'HW / Server Failure', 'Technical Failure of Server, Network Device, or HW', 'Failure of power supply, motherboard, network switch, firewall, or other physical component.', 'Without clustering or redundancy, leads directly to outage of hosted applications.'),
	('thr_tech_storage_fail', 'Storage / DB Corruption', 'Disk Array Failure, Media Fault, or Database Corruption', 'Multiple drive failure, filesystem corruption, database page corruption, or failed backup restoration.', 'Threatens both availability and integrity of core enterprise data.'),
	('thr_tech_sw_bug', 'SW Bug / Failed Update', 'Application Software Bug or Failed Upgrade', 'Manifestation of a software bug in production, incompatibility after OS/DB patching, or database lock contention.', 'Common cause of performance degradation, calculation errors, or application service outage.');

	UPDATE l
	SET l.shortname = s.shortname,
		l.caption = s.caption,
		l.description_text = s.description_text,
		l.help_text = s.help_text,
		l.date_modified = @now
	FROM threat l
	JOIN threat a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
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

	INSERT INTO threat (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, default_threat_score, external_code,
		shortname, caption, description_text, help_text,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.default_threat_score, a.external_code,
		s.shortname, s.caption, s.description_text, s.help_text,
		a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM @tr s
	JOIN threat a ON a.builtin_code = s.builtin_code AND a.object_owner = @sys_owner AND a.record_type = 'A' AND a.removed = 0
	WHERE NOT EXISTS (
		SELECT 1 FROM threat l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @lang
	);
END
GO