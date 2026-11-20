/* =============================================================================
 * Verze: 2026-11-20 10:00
 * Soubor: fillup_asset_class_en.sql
 *
 * 1. Role souboru v celém systému:
 *    Idempotentní naplnění výchozích anglických překladů (jazyk 'en',
 *    record_type = 'L') pro systémový katalog tříd aktiv v tabulce asset_class
 *    (object_owner = 0x00, celkem 119 uzlů) včetně automatického úklidu
 *    osiřelých systémových 'L' záznamů (who_modified = 0x00).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Navazuje na základní skript fillup_asset_class.sql.
 *    - Automaticky zařazen do buildu databáze maskou fillup_*.sql v BuildListDb.txt.
 *    - Zapisuje záznamy record_type = 'L' (@lang = 'en') do tabulky asset_class.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze nad systémovými záznamy
 *      (object_owner = 0x00) bez závislosti na uživatelské relaci v dbsession
 *      či SESSION_CONTEXT.
 * ============================================================================= */

SET NOCOUNT ON;
GO

IF OBJECT_ID('asset_class', 'U') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @lang varchar(2) = 'en';
	DECLARE @now datetime = GETDATE();

	DECLARE @ac_en TABLE (
		builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		caption varchar(200) NOT NULL,
		shortname varchar(40) NOT NULL,
		description_text varchar(max) NOT NULL
	);

	INSERT INTO @ac_en (builtin_code, caption, shortname, description_text) VALUES
	('ac_app_collab','Office, Email & Collaboration Applications','APP-COL','Installed systems for email, document sharing, messaging, and team collaboration.'),
	('ac_app_dev_tools','Development, Testing & CI/CD Tools','APP-DEV','Operational development environments, version control systems (Git), build servers (CI/CD), test platforms, and artifact repositories.'),
	('ac_app_erp_crm','Enterprise ERP / CRM / Core Information Systems','APP-ERP','Core enterprise information systems (ERP, CRM, order management, manufacturing, and logistics).'),
	('ac_app_financial','Financial, Accounting & Payment Applications','APP-FIN','Applications processing financial transfers, accounting, billing, banking, and payment transactions.'),
	('ac_app_hr','Human Resources & Payroll Applications','APP-HR','Applications managing employee records, payroll, attendance, and staff evaluation.'),
	('ac_app_other','Other General Installed Application','APP-OTH','Other operational application systems not covered by specialized groups.'),
	('ac_app_safety','Safety-Critical & Operational Technology Apps (OT)','APP-OT','Industrial and control applications (SCADA/OT) whose failure may endanger human life, health, or critical technology.'),
	('ac_app_security','Security, Monitoring & Administration Apps','APP-SEC','Applications for identity management (IAM/PAM), SIEM, backup, monitoring, and cybersecurity.'),
	('ac_app_web','Web Portals, E-Commerce & API Gateways','APP-WEB','Externally and internally published web applications, client portals, e-shops, and integration APIs.'),
	('ac_application','Applications / End User Services (EUS)','APP','Installed and operational application instances (End User Services) running on host computers and requiring data assets and personnel.'),
	('ac_bld_datacenter','Data Center / Technology Facility','BLD-DC','Dedicated building facility housing a data center or critical communication technology.'),
	('ac_bld_office','Administrative / Office Building','BLD-OFF','Organization headquarters, branch office, or administrative building.'),
	('ac_bld_other','Other Building / Facility','BLD-OTH','Other building facilities or a fictitious building grouping rooms.'),
	('ac_bld_production','Operational / Production / Warehouse Facility','BLD-PRD','Manufacturing hall, warehouse, logistics terminal, or operational facility.'),
	('ac_building','Buildings','BLD','Buildings and facilities. At least one building (even fictitious) must be defined in the organization to house rooms and cabling.'),
	('ac_cab_data','Structured Data Cabling (Copper / Fiber)','CAB-DAT','Copper and fiber-optic data cabling and backbone runs inside a building.'),
	('ac_cab_other','Other Cabling & Wiring','CAB-OTH','Other low-voltage, signaling, or specialized cabling inside a building.'),
	('ac_cab_power','Electrical Power Distribution Wiring','CAB-PWR','Main and backed-up electrical power circuits and distribution panels inside a building.'),
	('ac_cabling','Cabling & Wiring','CAB','Structured data cabling, fiber optic routes, and power distribution wiring located in a building and connecting rooms.'),
	('ac_city','Cities & Municipalities','CITY','Cities and municipalities where organization sites and buildings are located (optional spatial hierarchy level).'),
	('ac_data','Data Assets (Information & Databases)','DATA','Data assets, databases, and logical information sets stored on host computers, media, or documents.'),
	('ac_data_business','Trade Secrets, Contractual & Customer Data','DAT-BUS','Customer databases, contracts, pricing, intellectual property, and strategic business records.'),
	('ac_data_financial','Financial, Accounting & Payment Data','DAT-FIN','Accounting ledgers, tax records, payment orders, and financial statements.'),
	('ac_data_install_lic','Installation Packages, Licences & Activation Keys','DAT-LIC','Software installation media/packages, licence files, serial numbers, and activation codes required for installation, recovery, and licence compliance.'),
	('ac_data_operational','Operational, Technical & Configuration Data','DAT-OPS','Operational registers, production data, and infrastructure configuration databases.'),
	('ac_data_other','Other Data Assets','DAT-OTH','Other electronic or logical information sets and databases.'),
	('ac_data_personal','Personal & Sensitive Data (GDPR / HR)','DAT-PII','Personal data of employees, customers, or third parties subject to statutory protection (GDPR).'),
	('ac_data_security','Security Data (Credentials, Keys, Logs)','DAT-SEC','Cryptographic keys, certificates, account directories, audit logs, and security records.'),
	('ac_data_source_code','Source Code & Development Artifacts','DAT-SRC','Source code of developed software, database scripts, development branches, build signing keys, and code documentation.'),
	('ac_district','Districts & Regions','DIST','Geographical districts and regions representing the highest optional level of spatial asset organization.'),
	('ac_doc_legal','Contracts, Legal & Statutory Documents','DOC-LEG','Original contracts, incorporation deeds, licences, permits, and legally binding vital records.'),
	('ac_doc_ops','Operational, Security & Contingency Documentation','DOC-OPS','Controlled policies, crisis and recovery plans (BCP/DRP), operational manuals, and diagrams.'),
	('ac_doc_other','Other Controlled Documents','DOC-OTH','Other paper and electronic documents (accounting, HR, project files).'),
	('ac_document','Documents','DOC','Controlled paper and electronic documents, contracts, and operational documentation stored in rooms and carrying information.'),
	('ac_fac_hvac','Cooling & Air Conditioning (HVAC)','FAC-HVAC','Precision cooling units for server rooms, air conditioning, and ventilation of technical rooms.'),
	('ac_fac_other','Other Building Support Utility','FAC-OTH','Other supporting facility technology and building equipment.'),
	('ac_fac_power','Backup Power (UPS / Diesel Generator)','FAC-PWR','Uninterruptible power supplies (UPS), battery banks, diesel generators, and PDUs.'),
	('ac_fac_sec','Physical Security (Fire / Intrusion / CCTV / Access)','FAC-SEC','Fire detection and suppression, intrusion alarms, CCTV cameras, and physical access control systems.'),
	('ac_grp_info','Information, Data, Documents & Media','INFO','Folder of data assets, source code, licence keys, documents, and portable or backup storage media.'),
	('ac_grp_people_ext','Personnel & External Suppliers','PPL','Folder of human resources, key roles, and external suppliers or service partners.'),
	('ac_grp_services','Services & Communication Interfaces','SRV','Folder of primary business services, internal support services, and external/internal interfaces.'),
	('ac_grp_space','Spaces & Locations','LOC','Hierarchical folder of spatial asset placement (District -> City -> Site -> Building -> Room).'),
	('ac_grp_tech','Technical & Physical Assets (HW & Networks)','TECH','Folder of tangible equipment, host computers, servers, network devices, building utilities, and cabling.'),
	('ac_host','Host Computers, Servers & Workstations','HOST','Physical and virtual servers as well as end-user workstations. Server roles (multi_class = 1) may be combined on a single host, whereas workstations (multi_class = 0) are mutually exclusive with servers.'),
	('ac_host_app','Application Server','HST-APP','Server running enterprise, line-of-business, or integration applications (combinable role).'),
	('ac_host_cloud','Cloud Server / IaaS Instance','HST-CLD','Compute instance hosted at an external cloud provider (combinable role).'),
	('ac_host_db','Database Server','HST-DB','Server running a relational or NoSQL database engine (combinable role).'),
	('ac_host_file','File Server','HST-FIL','Server providing shared file storage to users and applications (combinable role).'),
	('ac_host_iam','Directory, Authentication & PKI Server','HST-IAM','Domain controller (Active Directory / LDAP), authentication server, SSO, or certificate authority (combinable role).'),
	('ac_host_mail','Mail & Messaging Server','HST-ML','Server providing email, messaging, and mail gateway functions (combinable role).'),
	('ac_host_net','Network & Monitoring Server (DNS/DHCP/NMS/SIEM)','HST-NET','Infrastructure server for DNS, DHCP, NTP, network/firewall management, and log collection (combinable role).'),
	('ac_host_other','Other Host Server','HST-OTH','Other specialized host servers (combinable role).'),
	('ac_host_print','Print Server','HST-PRT','Server managing print queues and network printing services (combinable role).'),
	('ac_host_virt','Virtualization Host / Hypervisor','HST-HYP','Physical host computer running a hypervisor for virtual machines (combinable role).'),
	('ac_host_vm','Virtual Server / Container Node','HST-VM','Virtual machine server (VM) or container platform node (combinable role).'),
	('ac_host_web','Web & Portal Server','HST-WEB','Server hosting web applications, reverse proxies, portals, and APIs (combinable role).'),
	('ac_ifc_data','Data & Internet Connectivity (WAN / MPLS / VPN)','IFC-DAT','Internet access, private data circuits, leased lines, dark fiber, and VPN connectivity.'),
	('ac_ifc_edi_api','External Integration Interface (EDI / API / Payment)','IFC-API','Electronic data interchange (EDI) and connections to banking, government, or partner APIs.'),
	('ac_ifc_other','Other Interface Communication Service','IFC-OTH','Other external or internal transmission and communication services.'),
	('ac_ifc_video','Video Conferencing & AV Transmission Service','IFC-VID','Services for video feeds, video conferencing, and remote visual communication.'),
	('ac_ifc_voice','Voice & Telephony Service (VoIP / Mobile / Fixed)','IFC-VOX','Public and private voice communications, SIP trunks, mobile voice, and SMS services.'),
	('ac_interface','Interface Services (Internet, Voice, Video)','IFC','External or internal connectivity and communication services (internet, voice, video links, APIs) required by other services.'),
	('ac_med_disk','Removable & External Drives / USB / SSD','MED-DSK','External hard drives, USB flash drives, memory cards, and removable disk cartridges.'),
	('ac_med_optical','Optical & Other Archival Media','MED-OPT','Optical discs (CD/DVD/Blu-ray) and other physical data carriers.'),
	('ac_med_tape','Backup Magnetic Tapes','MED-TAP','Magnetic tape media (LTO) for offline backups and long-term data archiving.'),
	('ac_media','Media & Data Carriers','MED','Portable and backup storage media (backup tapes, external drives, flash drives, optical media) stored in rooms or vaults.'),
	('ac_net_firewall','Firewall / UTM / IDS-IPS / VPN Gateway','NET-FW','Network security gateways, firewalls, intrusion detection/prevention systems, and VPN concentrators.'),
	('ac_net_other','Other Network Device','NET-OTH','Other active and passive network devices (load balancers, media converters, modems, patch panels).'),
	('ac_net_pbx','Telephone Exchange (PBX) / VoIP Gateway','NET-PBX','Private branch exchanges and hardware voice gateways.'),
	('ac_net_router','Router / WAN Gateway','NET-RTR','Routers and perimeter network gateways interconnecting local and external networks.'),
	('ac_net_switch','Network Switch','NET-SW','Core and access LAN and SAN network switches.'),
	('ac_net_wifi','Wireless Access Point (Wi-Fi AP / Radio Link)','NET-WIF','Wi-Fi access points, wireless controllers, and directional microwave/radio links.'),
	('ac_periph_other','Other Peripheral Device','PER-OTH','Other peripheral and office equipment (card readers, projectors, specialized terminals).'),
	('ac_periph_phone','Desk / IP Phone & Conferencing Device','PER-PHN','Wired and cordless desk telephones, IP phones, and audio/video conferencing units.'),
	('ac_periph_printer','Printer / Scanner / Multifunction Device','PER-PRT','Network and local printers, copiers, scanners, and multifunction devices.'),
	('ac_pers_dev','Developers, Analysts & Application Owners','PRS-DEV','Internal software developers, application owners, and database specialists.'),
	('ac_pers_ext','External Consultants & Contractors','PRS-EXT','Contracted staff and external specialists with access to organization assets or premises.'),
	('ac_pers_it_admin','IT Administrators, Network & Security Staff','PRS-ADM','Privileged administrators of servers, networks, databases, and cybersecurity managers.'),
	('ac_pers_mgmt','Executive Management & Process / Asset Owners','PRS-MGT','Statutory bodies, executives, and owners of business services and key assets.'),
	('ac_pers_ops','Operational Staff, Operators & End Users','PRS-OPS','Employees operating business applications, customer services, and supporting operations.'),
	('ac_personnel','Personnel & Key Roles','PERS','Internal and external staff, administrators, operators, and key job roles required to operate applications, services, and countermeasures.'),
	('ac_phys_facility','Building Utilities & Physical Security HW','PHYS-FAC','Equipment ensuring power supply, cooling, and physical protection of buildings and server rooms.'),
	('ac_phys_net','Network & Security Devices','PHYS-NET','Active network and security hardware interconnecting and protecting communication infrastructure.'),
	('ac_phys_periph','Peripheral & Communication Equipment','PHYS-PER','Printing, scanning, voice, and conferencing hardware located in rooms.'),
	('ac_phys_storage','Storage Devices & Arrays','PHYS-STR','Dedicated hardware data storage systems and backup appliances (excluding removable media).'),
	('ac_physical','Physical Assets & Hardware','HW','General tangible and technical assets, network devices, storage arrays, peripherals, and building utilities (UPS, HVAC, fire/intrusion alarms) located in rooms.'),
	('ac_room','Rooms & Halls','ROOM','Specific rooms, server rooms, archives, and workspaces inside buildings. Physical assets, host computers, documents, and media must be placed in rooms.'),
	('ac_room_archive','Archive / Records Room / Vault','RM-ARC','Secured room or vault for storing vital paper documents and offline backup media.'),
	('ac_room_office','Office / Standard Workspace','RM-OFF','Controlled workspace for internal employees and workstations.'),
	('ac_room_other','Other Room / Space','RM-OTH','Other operational or storage rooms inside a building.'),
	('ac_room_public','Reception / Publicly Accessible Area','RM-PUB','Areas accessible to visitors, customers, or the public (mutually exclusive with restricted zones).'),
	('ac_room_server','Server Room / Data Hall','RM-SRV','Dedicated secured space housing servers, core networking, and storage arrays.'),
	('ac_room_tech','Technical Room / Wiring Closet / UPS Room','RM-TEC','Room housing wiring panels, cabling hubs, UPS units, HVAC, or building utilities.'),
	('ac_service','Services (Internal & Customer-Facing)','SVC','Core business and internal support services supported by applications, interfaces, and personnel, evaluated for outage impacts across impact areas.'),
	('ac_site','Sites & Campuses','SITE','Sites, campuses, and branches grouping multiple buildings within a city or municipality (optional spatial hierarchy level).'),
	('ac_software','Software (Procurement, Development & Maintenance)','SWP','Standalone branch for software products in development or procurement lifecycle (installation media, activation keys, testing, distribution, and maintenance). Linked to installed applications (EUS) only optionally.'),
	('ac_srv_business','Core Customer / Business Service','SRV-BUS','Primary product or customer-facing service generating revenue or fulfilling statutory mandate.'),
	('ac_srv_cloud','Externally Hosted SaaS / Cloud Service','SRV-CLD','Service delivered as SaaS / PaaS by a third-party provider.'),
	('ac_srv_internal','Internal Support & IT Service','SRV-INT','Internal operational, infrastructure, or administrative service supporting the organization.'),
	('ac_srv_other','Other Service','SRV-OTH','Other services provided or consumed by the organization.'),
	('ac_stor_other','Other Storage Device','STR-OTH','Other hardware storage and archiving appliances.'),
	('ac_stor_san_nas','Storage Array (SAN / NAS)','STR-SAN','Centralized network and block storage arrays (SAN, NAS, hyperconverged storage).'),
	('ac_stor_tape','Tape Library / Backup Appliance','STR-TAP','Hardware tape libraries and dedicated backup storage appliances.'),
	('ac_sup_facility','Utilities, Facility & Physical Security Supplier','SUP-FAC','Providers of electrical power, building maintenance, HVAC, cleaning, and physical security guards.'),
	('ac_sup_it_cloud','IT, Software & Cloud Service Supplier','SUP-IT','Suppliers of software development/maintenance, hardware, data centers, and cloud platforms.'),
	('ac_sup_other','Other External Supplier / Partner','SUP-OTH','Other contractual partners, advisors, and supply chain vendors.'),
	('ac_sup_telecom','Telecom Carrier / ISP','SUP-TEL','Providers of internet connectivity, data circuits, and voice/mobile telecom services.'),
	('ac_supplier','Suppliers & External Partners','SUP','External providers of communication interfaces, cloud services, hardware, software, and maintenance support.'),
	('ac_sw_bespoke','Bespoke / Internally Developed Software','SW-BSP','Custom software developed internally or by a vendor (risks of source code, testing, build distribution, licences, and maintenance).'),
	('ac_sw_oss','Open-Source & Community Software','SW-OSS','Open-source software and libraries operated without commercial vendor support or with community support (dependency and licence compatibility risks).'),
	('ac_sw_other','Other Software Product','SW-OTH','Other software packages and utilities in procurement or development inventory.'),
	('ac_sw_package','Procured Commercial Software (COTS)','SW-PKG','Standard procured commercial software (risks of preserving installation media, activation codes, installation process, and patching/maintenance).'),
	('ac_sw_system','System Software (OS / DBMS / Middleware)','SW-SYS','Operating systems, database management systems, application servers, and virtualization platforms (installation kits, licences, and update cycles).'),
	('ac_workstation','Workstations & End-User Devices','WS','End-user computers and mobile devices (multi_class = 0: cannot be combined with server roles).'),
	('ac_ws_desktop','Fixed Workstation / Desktop PC','WS-PC','Desktop personal computer or workstation permanently located at a workplace.'),
	('ac_ws_laptop','Portable Computer / Laptop','WS-NB','Laptop or portable workstation used both on premises and remotely.'),
	('ac_ws_mobile','Smart Mobile Device (Smartphone / Tablet)','WS-MOB','Corporate smartphones and tablets accessing email, documents, or business applications.'),
	('ac_ws_other','Other Workstation','WS-OTH','Other end-user computing devices.'),
	('ac_ws_terminal','Terminal / Thin Client','WS-TRM','Fixed terminal, thin client, or POS/kiosk terminal.');

	-- 0. Úklid zastaralých anglických 'L' záznamů (0x00, who_modified = 0x00) mimo @ac_en
	DELETE l
	FROM asset_class l
	LEFT JOIN @ac_en s ON s.builtin_code = l.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.who_modified = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
	  AND s.builtin_code IS NULL;

	-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
	UPDATE l
	SET l.parent_uuid = a.parent_uuid,
		l.sort_code = a.sort_code,
		l.is_leaf = a.is_leaf,
		l.multi_class = a.multi_class,
		l.instance_class_name = a.instance_class_name,
		l.caption = s.caption,
		l.shortname = s.shortname,
		l.description_text = s.description_text,
		l.date_modified = @now
	FROM asset_class l
	JOIN asset_class a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
	JOIN @ac_en s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = @lang
	  AND l.who_modified = @sys_owner
	  AND EXISTS (
		SELECT l.parent_uuid, l.sort_code, l.is_leaf, l.multi_class, l.instance_class_name, l.caption, l.shortname, l.description_text
		EXCEPT
		SELECT a.parent_uuid, a.sort_code, a.is_leaf, a.multi_class, a.instance_class_name, s.caption, s.shortname, s.description_text
	  );

	-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
	INSERT INTO asset_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, multi_class, instance_class_name,
		caption, shortname, description_text, svg_icon, is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', @lang,
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.multi_class, a.instance_class_name,
		s.caption, s.shortname, s.description_text, a.svg_icon, a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM asset_class a
	JOIN @ac_en s ON s.builtin_code = a.builtin_code
	WHERE a.object_owner = @sys_owner
	  AND a.record_type = 'A'
	  AND a.removed = 0
	  AND NOT EXISTS (
		SELECT 1 FROM asset_class l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = @lang
	  );
END
GO