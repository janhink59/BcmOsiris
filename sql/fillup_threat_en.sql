/* =============================================================================
 * Verze: 2026-11-20 09:55
 * Soubor: fillup_threat_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění anglických překladů ('en', record_type = 'L')
 *    pro stromový katalog hrozeb v tabulce threat (object_owner = 0x00,
 *    9 složek + 41 koncových hrozeb = 50 uzlů) včetně automatického úklidu
 *    osiřelých systémových 'L' záznamů (who_modified = 0x00).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_threat.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulky threat
 *      (table_threat.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      systémovými záznamy (object_owner = 0x00) bez závislosti na dbsession.
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
	('thr_cyber_exfiltration','Data Breach / Exfil.','Unauthorized Access and Sensitive Data Exfiltration','Gaining unauthorized access to databases, repositories, or documents to steal or disclose sensitive data.','Leads to confidentiality breaches, GDPR/NIS2 penalties, and reputational damage.'),
	('thr_cyber_infiltration','Infiltration / Hacking','System Infiltration and Vulnerability Exploitation (Hacking)','Intrusion into a network, server, or application by exploiting a technical vulnerability, misconfiguration, or server spoofing.','Primary cyber attack vector threatening confidentiality, integrity, and availability.'),
	('thr_cyber_interception','Interception','Network Communication Interception / Eavesdropping','Unauthorized interception of data transmitted over networks, wireless links, or communication interfaces.','Threatens confidentiality of unencrypted traffic, credentials, and sensitive transfers.'),
	('thr_cyber_malware','Malware / Ransomware','Malicious Code, Viruses, and Encryption Attack (Malware / Ransomware)','Infiltration of malicious code (viruses, trojans, ransomware) via network, email, or media to encrypt or destroy data.','Critical threat to IT infrastructure availability and enterprise data integrity.'),
	('thr_cyber_manipulation','MITM / Tampering','Communication Manipulation in Transit (Man-in-the-Middle)','Intentional alteration, spoofing, or disruption of transmitted messages and transactions in transit.','Threatens integrity of transactions, commands, and transmitted documents.'),
	('thr_cyber_masquerade_csp','Masquerade (CSP)','Identity Masquerade or Privilege Misuse by Service Provider (CSP)','Impersonating an authorized user or misusing service accounts by a contracted service provider or vendor.','Requires strict management, approval, and auditing of third-party remote access.'),
	('thr_cyber_masquerade_ext','Masquerade (Outsiders)','User Identity Masquerade by External Attacker (Outsiders)','Takeover of a user or administrator account by an external actor using stolen credentials or session tokens.','Mitigated by multi-factor authentication (MFA) and login anomaly detection.'),
	('thr_cyber_masquerade_int','Masquerade (Insiders)','User Identity Masquerade by Internal Staff (Insiders)','Using another colleague''s unlocked workstation, shared password, or credentials to perform unauthorized actions.','Corrupts audit trails and bypasses Segregation of Duties (SoD) controls.'),
	('thr_cyber_phishing','Phishing / Soc. Eng.','Phishing, Communication Spoofing, and Social Engineering','Manipulating staff via fraudulent emails, messages, or calls to harvest credentials or authorize fraudulent transactions.','Most frequent initial entry vector for ransomware or account compromise.'),
	('thr_cyber_repudiation','Repudiation','Repudiation of Performed Action or Message','Denying having sent, received, or approved an electronic message or transaction due to lacking non-repudiation evidence.','Critical for financial, contractual, and approval systems lacking digital signatures and immutable logs.'),
	('thr_cyber_supply_chain','SW Supply Chain','Software and Update Supply Chain Compromise','Injection of malicious code into third-party libraries, installation packages, repositories, or software updates.','Affects both custom software development and procured commercial or open-source software.'),
	('thr_cyber_unauth_app_use','Unauth. App Use','Unauthorized Use of an Application Under Own Account','Performing fraudulent, unauthorized, or excessive operations in an application by a legitimate user under their own account.','Distinct from masquerade: the actor uses their own identity (abuse of excessive privileges).'),
	('thr_grp_cyber','Cyber Attacks','Cyber, Communication, and Logical Attacks','Intentional external, communication, and logical attacks targeting information systems, networks, and applications.','Parent folder for intrusions, identity masquerade, malware, DDoS, and communication attacks.'),
	('thr_grp_cyber_access','Intrusion & Access','Intrusions, Identity Masquerade, and Unauthorized Access','Attacks targeting authentication bypass, account misuse, phishing, and unauthorized use of applications or data.','Folder covering access and identity threats from outsiders, service providers, and insiders.'),
	('thr_grp_cyber_mal_comm','Malware, DDoS & Comm.','Malware, DDoS, Communication, and Supply Chain Attacks','Malware, ransomware, software supply chain compromise, denial of service, and transport-layer attacks.','Folder covering malicious code and security of data in transit.'),
	('thr_grp_human','Human Factor & Errors','Human Factor, Operator/Maintenance Errors, and Staff Shortage','Unintentional errors by users, administrators, and HW/SW maintenance staff, resource misuse, and key staff shortage.','Folder covering threats related to employees, maintenance, and staff availability.'),
	('thr_grp_org','Suppliers & Processes','Organizational, Supplier, and Legal Threats','Third-party failures, supplier and telecom outages, regulatory non-compliance, and internal process failures.','Folder covering supply chain, telecom carriers, compliance, and change management.'),
	('thr_grp_phys','Physical & Natural','Physical, Natural, and Environmental Threats','Natural disasters, utility outages, physical theft, vandalism, and targeted physical sabotage.','Parent folder for threats affecting sites, buildings, rooms, and physical equipment.'),
	('thr_grp_phys_act','Theft, Vandalism, Sabotage','Physical Intrusion, Theft, Wilful Damage, and Sabotage','Intentional physical acts against organization property and premises by outsiders or insiders.','Folder separating theft (confidentiality + availability) from physical damage and terrorism (availability).'),
	('thr_grp_phys_env','Natural & Utilities','Natural Disasters, Fire, Water, Power, and Cooling Failures','Natural and environmental events and failures of critical building and server room utilities.','Folder for fire, water damage, natural disasters, power outages, and HVAC failures.'),
	('thr_grp_tech','Technical Failures','Technical Failures of HW, Networks, and Software','Unintentional faults of compute and network HW, storage, network services, system/application SW, and capacity exhaustion.','Folder covering technical and operational faults without an intentional attacker.'),
	('thr_hum_hw_maint_err','HW Maintenance Error','Hardware Maintenance or Servicing Error','Damage, miswiring, or accidental disconnection of operational hardware or power during a maintenance intervention.','Occurs during component replacement, server room servicing, UPS maintenance, or cabling work.'),
	('thr_hum_misuse_res','Resource Misuse / Shadow IT','Misuse of System Resources (Shadow IT)','Non-work or unapproved use of IT equipment, internet, software licences, cloud services, or development tools by staff.','Increases costs, legal risks, and creates an unmanaged attack surface (Shadow IT).'),
	('thr_hum_ops_err','Operations / Admin Error','Operations or Administrator Error','Accidental deletion of a production database, operational mistake, disabling security controls, or failed backup routine.','Can cause immediate widespread outage or unintended data exposure.'),
	('thr_hum_staff_shortage','Staff Shortage','Staff Shortage or Unavailability of Key Specialist','Sudden illness, injury, strike, or departure of staff holding unique know-how without backup coverage or documentation.','Threatens business continuity, recovery, and maintenance of key applications and processes.'),
	('thr_hum_sw_maint_err','SW Maintenance Error','Software Maintenance, Configuration, or Deployment Error','Introducing defects during patching, misconfiguring production files, coding security flaws, or corrupting database schemas.','Leads to service outages, data inconsistency, or exploitable vulnerabilities.'),
	('thr_hum_user_err','User Error','Unintentional End-User Error','Incorrect data entry or overwrite, accidental file deletion, or sending sensitive documents to the wrong recipient.','Most frequent operational threat affecting data integrity and confidentiality.'),
	('thr_org_compliance','Non-Compliance','Breach of Legal, Regulatory, Licence, or Contractual Obligations','Failure to meet cybersecurity requirements (NIS2), data protection rules (GDPR), software licence terms, or SLAs.','Leads to financial fines, regulatory audits, and loss of customer trust.'),
	('thr_org_isp_outage','ISP / Telecom Outage','Internet Service Provider or Telecom Carrier Outage','Disruption of external data, voice, or cloud connectivity on the telecom operator side.','Disconnects branch offices, remote workers, and published customer services.'),
	('thr_org_process_fail','Change / Process Failure','Internal Process Failure or Uncontrolled Change','Untested production change, unclear accountability, uncontrolled software installations, or outdated emergency procedures.','Increases downtime duration and likelihood of cascading errors during an incident.'),
	('thr_org_supplier_outage','Supplier Outage','Key Supplier Outage or End of Support','Unavailability of outsourced service, SaaS platform, maintenance support, or demise of a SW/HW vendor.','Critical especially for single-source suppliers (Vendor Lock-in).'),
	('thr_phys_damage_ext','Wilful Damage (Outsiders)','Intentional Physical Damage or Vandalism by Outsiders','Intentional destruction or damage to a building, cabling, or equipment by an external perpetrator without theft intent.','Primarily threatens availability of premises, cabling, and physical infrastructure.'),
	('thr_phys_damage_int','Wilful Damage (Insiders)','Intentional Physical Damage or Sabotage by Insiders','Deliberate destruction of equipment, servers, backup media, or documents by a disgruntled or departing employee.','Requires physical access controls to server rooms and prompt revocation of access badges.'),
	('thr_phys_disaster','Natural Disaster / Hazard','Natural Disaster or External Industrial / Transport Accident','Area-wide natural calamity (storm, earthquake, extreme weather) or external accident (chemical leak, crash) affecting the entire site.','Can knock out an entire building or site; requires a geographically separated DR site.'),
	('thr_phys_fire','Fire / Smoke','Fire or Smoke in Building or Server Room','Fire caused by electrical short circuit, equipment overheating, or material ignition.','Causes destruction of hardware, cabling, paper documents, and long-term facility unavailability.'),
	('thr_phys_hvac','HVAC / Cooling Failure','Cooling and Air Conditioning Failure in Tech Room','Failure of server room HVAC unit leading to rapid overheating and emergency thermal shutdown of servers.','Common cause of forced IT equipment downtime during summer months.'),
	('thr_phys_power','Power Outage','Prolonged Electrical Power Outage','Grid power interruption exceeding the runtime capacity of uninterruptible power supplies (UPS).','Affects all equipment, lighting, cooling, and access control systems in the building.'),
	('thr_phys_terrorism','Terrorism / Sabotage','Terrorism, Explosion, or Targeted Physical Sabotage','Severe intentional physical attack on a building, data center, or critical technical facility of the organization.','Can knock out an entire site and requires geographically separated disaster recovery.'),
	('thr_phys_theft_ext','Theft (Outsiders)','Theft of Equipment, Media, or Documents by Outsiders','Entry of an unauthorized external person into premises or theft of portable equipment during travel to steal assets or data.','Threatens equipment availability and confidentiality of unencrypted drives, media, and papers.'),
	('thr_phys_theft_int','Theft (Insiders)','Theft of Equipment, Media, or Documents by Insiders','Theft of a laptop, backup media, installation keys, or sensitive files by a person with legitimate premises access.','Requires asset tracking, endpoint disk encryption, and locked sensitive zones.'),
	('thr_phys_water','Water Damage / Flood','Water Leakage, Pipe Burst, or Flooding','Flooding of premises due to burst water/heating pipes, torrential rain, or river flood.','High risk for basement areas, server rooms beneath water pipes, and document archives.'),
	('thr_tech_app_sw_fail','Application SW Failure','Application Software Failure or Defect','Programming defect in application business logic, application crash, deadlock, or calculation error after an update.','Directly affects installed applications (EUS) and integrity of processed data.'),
	('thr_tech_capacity','Capacity Exhaustion','Compute, Memory, or Disk Capacity Exhaustion','Disk space exhaustion (logs, databases), RAM depletion, or CPU saturation.','Causes application freezes, transaction write failures, and rejection of user requests.'),
	('thr_tech_hw_fail','Compute HW Failure','Technical Failure of Server, Workstation, or Peripheral','Failure of power supply, motherboard, CPU, memory, printer, or network management computer.','Without clustering or redundancy, leads directly to outage of hosted applications.'),
	('thr_tech_misrouting','Accidental Mis-routing','Accidental Network Traffic or Message Mis-routing','Unintended redirection of network traffic or messages to an unauthorized recipient or broken route.','Can cause confidentiality leaks or network service unavailability.'),
	('thr_tech_net_hw_fail','Network HW / Cabling Fail','Failure of Network Device, Gateway, Interface, or Cabling','Technical fault of a switch, router, firewall, Wi-Fi AP, network interface, or severed cabling.','Causes network segment isolation or communication outage between servers and users.'),
	('thr_tech_net_svc_fail','Network Service Failure','Internal Network Service or Communication Link Failure','Outage of DNS, DHCP, VPN tunnel, routing service, or communication link inside or outside the organization.','Prevents establishing connections between applications, users, and supporting services.'),
	('thr_tech_storage_fail','Storage / Media Failure','Disk Array Failure, Media Fault, or Database Corruption','Multiple drive failure, backup medium fault, filesystem corruption, or database page corruption.','Threatens both availability and integrity of core enterprise data and backups.'),
	('thr_tech_sys_sw_fail','System SW Failure','System or Network Software Failure (OS / DBMS / Firmware)','Failure of operating system, hypervisor, database engine, or network device firmware including failure of security controls.','Affects all applications and data running on the given host or device.');

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