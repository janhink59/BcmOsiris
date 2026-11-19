/* =============================================================================
 * Verze: 2026-11-19 16:50
 * Soubor: fillup_threat_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en', record_type = 'L')
 *    pro stromový katalog hrozeb v tabulce threat (object_owner = 0x00)
 *    včetně automatického úklidu osiřelých systémových 'L' záznamů
 *    (who_modified = 0x00).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_threat.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulky threat
 *      (table_threat.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze nad systémovými záznamy
 *      (object_owner = 0x00) bez závislosti na uživatelské relaci v dbsession.
 * ============================================================================= */
SET NOCOUNT ON;
GO

IF OBJECT_ID('threat', 'U') IS NOT NULL
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
	('thr_cyber_ddos','DDoS Attack','Denial of Service / Network Flooding (DoS / DDoS)','Targeted flooding of network connectivity, firewalls, or application servers with overwhelming request volume.','Threatens availability of externally published services, portals, and communication interfaces.'),
	('thr_cyber_exfiltration','Data Breach / Theft','Unauthorized Access and Sensitive Data Exfiltration (Outsiders)','Gaining unauthorized access to databases, repositories, or documents by an external attacker to steal or disclose confidential data.','Leads to confidentiality breaches, GDPR/NIS2 penalties, and reputational damage.'),
	('thr_cyber_interception','Interception','Network Communication Interception / Eavesdropping','Unauthorized interception of data transmitted over networks, wireless links, or communication interfaces.','Threatens confidentiality of unencrypted traffic, credentials, and sensitive transfers.'),
	('thr_cyber_manipulation','MITM / Tampering','Communication Manipulation in Transit (Man-in-the-Middle)','Intentional alteration, spoofing, or disruption of transmitted messages and transactions in transit.','Threatens integrity of transactions, commands, and transmitted documents.'),
	('thr_cyber_masquerade_csp','Masquerade (CSP)','Identity or Privilege Misuse by Contracted Service Provider (CSP)','Impersonating an authorized user or misusing service accounts by an external contractor or vendor.','Requires strict management and auditing of remote and third-party service access.'),
	('thr_cyber_masquerade_ext','Masquerade (Outsiders)','User Identity Misuse by External Attacker (Outsiders)','Takeover of a user or administrator account by an external actor using stolen credentials or session tokens.','Mitigated by multi-factor authentication (MFA) and login anomaly detection.'),
	('thr_cyber_phishing','Phishing / Soc. Eng.','Phishing, Identity Spoofing, and Social Engineering','Manipulating staff via fraudulent emails, messages, or calls to harvest credentials or authorize fraudulent transactions.','Frequently serves as the initial entry vector for ransomware or account compromise.'),
	('thr_cyber_ransomware','Ransomware / Malware','Malicious Code and Encryption Attack (Ransomware / Malware)','Infiltration of malicious code that encrypts servers, workstations, and accessible network storage while demanding ransom.','Critical threat to IT infrastructure availability and data integrity.'),
	('thr_cyber_repudiation','Repudiation','Repudiation of Performed Action or Message','Denying having sent, received, or approved an electronic message or transaction due to lacking non-repudiation evidence.','Critical for financial, contractual, and approval systems lacking digital signatures and immutable logs.'),
	('thr_grp_cyber','Cyber Attacks','Cyber, Communication, and Intentional Attacks','Intentional external and communication attacks conducted over networks, application interfaces, or via social engineering.','Folder covering malware, ransomware, phishing, DDoS, interception, tampering, and identity misuse.'),
	('thr_grp_human','Human Factor & Maint.','Human Factor, Operator, and Maintenance Threats','Unintentional errors by users, operators, and HW/SW maintenance staff, unavailability of key personnel, or insider misuse.','Folder covering threats related to employees, administrators, maintenance, and internal users.'),
	('thr_grp_org','Suppliers & Processes','Organizational, Supplier, and Legal Threats','Third-party failures, key supplier outages, regulatory non-compliance, and internal process failures.','Folder covering supply chain, cloud providers, and compliance.'),
	('thr_grp_phys','Physical & Environmental','Physical, Environmental, and Natural Threats','Fires, floods, utility outages, physical intrusion into premises, theft, and physical sabotage.','Folder covering threats affecting sites, buildings, server rooms, and physical equipment.'),
	('thr_grp_tech','Technical & IT','Technical Failures of HW, SW, and Infrastructure','Server, storage array, and network device failures, software bugs, mis-routing, and capacity exhaustion.','Folder covering technical and operational faults without requiring an intentional attacker.'),
	('thr_hum_hw_maint_err','HW Maintenance Error','Hardware Maintenance or Servicing Error','Damage, miswiring, or accidental disconnection of operational hardware or power during a maintenance intervention.','Occurs during component replacement, server room servicing, UPS maintenance, or cabling work.'),
	('thr_hum_insider','Insider Sabotage','Intentional Misuse of Privileges or Sabotage by Insider','Data theft, system sabotage, or unauthorized operations performed by a disgruntled or former employee.','Risk increases when privileged accounts are unmonitored or access revocation is delayed.'),
	('thr_hum_key_person','Key Person Loss','Unavailability or Departure of Key Specialist','Sudden illness, injury, or departure of an employee holding unique know-how without backup staff or documentation.','Threatens recovery capability and maintenance of specialized applications and processes.'),
	('thr_hum_masquerade_int','Masquerade (Insiders)','User Identity Misuse by Internal Staff (Insiders)','Using another colleague''s unlocked workstation, shared password, or credentials to perform unauthorized actions.','Corrupts audit trails and bypasses Segregation of Duties (SoD) controls.'),
	('thr_hum_ops_err','Operations / Admin Error','Operations or Administrator Error','Accidental deletion of a production database, operational mistake, disabling security controls, or failed backup routine.','Can cause immediate widespread outage or unintended data exposure.'),
	('thr_hum_sw_maint_err','SW Maintenance Error','Software Maintenance, Configuration, or Deployment Error','Introducing defects during patching, misconfiguring production files, coding security flaws, or corrupting database schemas.','Leads to service outages, data inconsistency, or exploitable vulnerabilities.'),
	('thr_hum_user_err','User Error','Unintentional End-User Error','Incorrect data entry or overwrite, accidental file deletion, or sending sensitive documents to the wrong recipient.','Most frequent operational threat affecting data integrity and confidentiality.'),
	('thr_org_compliance','Non-Compliance','Breach of Regulatory, Legal, or Contractual Obligations','Failure to meet cybersecurity requirements (NIS2), data protection rules (GDPR), licence terms, or customer SLAs.','Leads to financial fines, regulatory audits, and loss of customer trust.'),
	('thr_org_isp_outage','Telecom Outage','Internet Service Provider or Interface Outage','Disruption of data, voice, or cloud connectivity on the external telecom operator side.','Disconnects branch offices, remote workers, and published customer services.'),
	('thr_org_process_fail','Change Mgmt Failure','Internal Process Failure or Uncontrolled Change','Untested production change, unclear accountability, or outdated emergency procedures.','Increases downtime duration and likelihood of cascading errors during an incident.'),
	('thr_org_supplier_outage','Supplier Outage','Key Supplier Outage or Business Termination','Unavailability of outsourced service, SaaS platform, maintenance support, or supply chain compromise.','Critical especially for single-source suppliers (Vendor Lock-in).'),
	('thr_phys_fire','Fire / Smoke','Fire or Smoke in Building or Server Room','Fire caused by electrical short circuit, equipment overheating, or material ignition.','Causes destruction of hardware, cabling, paper documents, and long-term facility unavailability.'),
	('thr_phys_hvac','HVAC / Cooling Failure','Cooling and Air Conditioning Failure in Tech Room','Failure of server room HVAC unit leading to rapid overheating and emergency thermal shutdown of servers.','Common cause of forced IT equipment downtime during summer months.'),
	('thr_phys_intrusion','Intrusion / Theft (Ext.)','Unauthorized Physical Intrusion, Theft, or Vandalism (Outsiders)','Entry of an unauthorized external person into a building or room, theft of hardware/media, or physical damage to equipment.','Threatens both equipment availability and confidentiality of unencrypted media.'),
	('thr_phys_power','Power Outage','Prolonged Electrical Power Outage','Grid power interruption exceeding the runtime capacity of uninterruptible power supplies (UPS).','Affects all equipment, lighting, cooling, and access control systems in the building.'),
	('thr_phys_terrorism','Terrorism / Sabotage','Terrorism, Explosion, or Targeted Physical Sabotage','Severe intentional physical attack on a building, data center, or critical technical facility of the organization.','Can knock out an entire site and requires geographically separated disaster recovery (DR site).'),
	('thr_phys_theft_insider','Theft / Damage (Int.)','Theft or Intentional Physical Damage by Insider or Partner','Theft of portable hardware, backup media, or documents, or physical damage committed by a person with legitimate premises access.','Requires asset tracking, disk encryption, and physical access controls to sensitive zones.'),
	('thr_phys_water','Water / Flood','Water Leakage, Pipe Burst, or Flooding','Flooding of premises due to burst water/heating pipes, torrential rain, or river flood.','High risk for basement areas, server rooms beneath water pipes, and document archives.'),
	('thr_tech_capacity','Capacity Exhaustion','Compute, Memory, or Disk Capacity Exhaustion','Disk space exhaustion (logs, databases), RAM depletion, or CPU saturation.','Causes application freezes, transaction write failures, and rejection of user requests.'),
	('thr_tech_hw_fail','HW / Server Failure','Technical Failure of Server, Network Device, or HW','Failure of power supply, motherboard, network switch, firewall, or other physical component.','Without clustering or redundancy, leads directly to outage of hosted applications.'),
	('thr_tech_misrouting','Accidental Mis-routing','Accidental Network Traffic or Message Mis-routing','Unintended redirection of network traffic or messages to an unauthorized recipient or broken route.','Can cause confidentiality leaks or network service unavailability.'),
	('thr_tech_storage_fail','Storage / DB Corruption','Disk Array Failure, Media Fault, or Database Corruption','Multiple drive failure, filesystem corruption, database page corruption, or failed backup restoration.','Threatens both availability and integrity of core enterprise data.'),
	('thr_tech_sw_bug','SW Bug / Failed Update','Application Software Bug or Failed Upgrade','Manifestation of a software bug in production, incompatibility after OS/DB patching, or database lock contention.','Common cause of performance degradation, calculation errors, or application service outage.');

	-- 0. Úklid zastaralých anglických 'L' záznamů (0x00, who_modified = 0x00) mimo @tr
	DELETE l
	FROM threat l
	LEFT JOIN @tr s ON s.builtin_code = l.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.who_modified = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
	  AND s.builtin_code IS NULL;

	UPDATE l
	SET l.sort_code = a.sort_code,
		l.is_leaf = a.is_leaf,
		l.default_threat_score = a.default_threat_score,
		l.external_code = a.external_code,
		l.shortname = s.shortname,
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
		SELECT l.sort_code, l.is_leaf, l.default_threat_score, l.external_code, l.shortname, l.caption, l.description_text, l.help_text
		EXCEPT
		SELECT a.sort_code, a.is_leaf, a.default_threat_score, a.external_code, s.shortname, s.caption, s.description_text, s.help_text
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