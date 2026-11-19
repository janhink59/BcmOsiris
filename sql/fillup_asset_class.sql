/* =============================================================================
 * Verze: 2026-11-19 16:05
 * Soubor: fillup_asset_class.sql
 *
 * 1. Role souboru v celém systému:
 *    Prvotní idempotentní naplnění systémového hierarchického katalogu tříd
 *    aktiv v tabulce asset_class (object_owner = 0x00, jazyk 'cs', záznamy 'A'
 *    a symetrické 'L') s čistým, disjunktním členěním pod všemi 17 STI
 *    archetypy a s řízením vícenásobného přiřazení přes sloupec multi_class.
 *    Osiřelé systémové záznamy (object_owner = 0x00 AND who_modified = 0x00),
 *    které již nejsou v aktuální sadě, jsou automaticky odstraněny.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Vyžaduje tabulku asset_class (table_asset_class.sql) včetně sloupce
 *      multi_class a funkci dbo.f_generate_original (f_generate_original.sql).
 *    - Všechny podřízené třídy nesou vyplněný sloupec instance_class_name
 *      ('asset_<archetype>') pro přesné filtrování v dbo.p_em_get_select_options
 *      (@mode = 'asset_class_by_archetype') a na stránce page_asset.php.
 *    - Navazuje překladový skript fillup_asset_class_en.sql.
 *    - V závěru volá dbo.p_sync_derived_links pro zrcadlení parent_to_child.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (maska fillup_*.sql) nad
 *      systémovými záznamy (object_owner = 0x00) bez závislosti na dbsession.
 * ============================================================================= */

SET NOCOUNT ON;
GO

IF OBJECT_ID('asset_class', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
BEGIN
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @now datetime = GETDATE();

	DECLARE @ac_cs TABLE (
		builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		parent_code varchar(80) COLLATE DATABASE_DEFAULT NULL,
		sort_code varchar(200) NOT NULL,
		is_leaf bit NOT NULL,
		multi_class bit NOT NULL,
		instance_class_name varchar(80) NOT NULL,
		caption varchar(200) NOT NULL,
		shortname varchar(40) NOT NULL,
		description_text varchar(max) NOT NULL,
		svg_icon varchar(max) NOT NULL
	);

	INSERT INTO @ac_cs (
		builtin_code, parent_code, sort_code, is_leaf, multi_class,
		instance_class_name, caption, shortname, description_text, svg_icon
	) VALUES
	('ac_app_collab','ac_application','050',1,1,'asset_application','Kancelářské, poštovní a komunikační aplikace','APP-COL','Instalované systémy pro elektronickou poštu, sdílení dokumentů, chat a týmovou spolupráci.',''),
	('ac_app_erp_crm','ac_application','020',1,1,'asset_application','Podnikové ERP / CRM / jádrové systémy','APP-ERP','Hlavní podnikové informační systémy (ERP, CRM, řízení zakázek, výroby a logistiky).',''),
	('ac_app_financial','ac_application','010',1,1,'asset_application','Finanční, účetní a platební aplikace','APP-FIN','Aplikace zpracovávající finanční převody, účetnictví, fakturaci, bankovní a platební transakce.',''),
	('ac_app_hr','ac_application','030',1,1,'asset_application','Personalistické a mzdové aplikace','APP-HR','Aplikace pro evidenci zaměstnanců, mezd, docházky a hodnocení personálu.',''),
	('ac_app_other','ac_application','090',1,1,'asset_application','Jiná obecná instalovaná aplikace','APP-OTH','Ostatní provozované aplikační systémy nezařazené do specializovaných skupin.',''),
	('ac_app_safety','ac_application','040',1,1,'asset_application','Aplikace kritické pro bezpečnost osob a provozu (OT)','APP-OT','Řídicí a průmyslové aplikace (SCADA/OT), jejichž selhání může ohrozit život, zdraví nebo klíčovou technologii.',''),
	('ac_app_security','ac_application','070',1,1,'asset_application','Bezpečnostní, dohledové a správcovské aplikace','APP-SEC','Aplikace pro správu identit (IAM/PAM), SIEM, zálohování, monitoring a kybernetickou bezpečnost.',''),
	('ac_app_web','ac_application','060',1,1,'asset_application','Webové portály, e-shopy a API brány','APP-WEB','Externě i interně publikované webové aplikace, klientské portály, e-commerce a integrační API.',''),
	('ac_application','ac_grp_sw_apps','020',0,0,'asset_application','Aplikace (instalované)','APP','Konkrétní instalované instance aplikačního vybavení provozované na hostitelských počítačích a vyžadující datová aktiva a personál.','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11z"/></svg>'),
	('ac_bld_datacenter','ac_building','020',1,1,'asset_building','Datové centrum / technologický objekt','BLD-DC','Vyhrazený stavební objekt pro datové centrum nebo kritickou komunikační technologii.',''),
	('ac_bld_office','ac_building','010',1,1,'asset_building','Administrativní / kancelářská budova','BLD-OFF','Sídlo organizace, pobočka nebo kancelářská budova.',''),
	('ac_bld_other','ac_building','090',1,1,'asset_building','Jiná budova / objekt','BLD-OTH','Ostatní stavební objekty nebo fiktivní budova pro sdružení místností.',''),
	('ac_bld_production','ac_building','030',1,1,'asset_building','Provozní / výrobní / skladový objekt','BLD-PRD','Výrobní hala, sklad, logistický terminál nebo provozní budova.',''),
	('ac_building','ac_grp_space','040',0,0,'asset_building','Budovy','BLD','Stavební objekty a budovy. V organizaci musí být definována alespoň jedna budova (i fiktivní), do níž se umisťují místnosti a kabeláž.','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10z"/></svg>'),
	('ac_cab_data','ac_cabling','010',1,1,'asset_cabling','Strukturovaná datová kabeláž (metalická / optická)','CAB-DAT','Metalické a optické datové rozvody a páteřní trasy uvnitř budovy.',''),
	('ac_cab_other','ac_cabling','090',1,1,'asset_cabling','Jiná kabeláž a rozvody','CAB-OTH','Ostatní slaboproudé, signalizační nebo speciální kabelové rozvody v budově.',''),
	('ac_cab_power','ac_cabling','020',1,1,'asset_cabling','Silnoproudé elektrické rozvody','CAB-PWR','Hlavní i záložní elektrické napájecí okruhy a rozvaděče v budově.',''),
	('ac_cabling','ac_grp_tech','030',0,0,'asset_cabling','Kabeláž a rozvody','CAB','Strukturovaná datová kabeláž, optické trasy a silnoproudé rozvody umístěné v budově a propojující místnosti.','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M20 10V8h-4V4h-2v4h-4V4H8v4H4v2h4v4H4v2h4v4h2v-4h4v4h2v-4h4v-2h-4v-4h4zm-6 4h-4v-4h4v4z"/></svg>'),
	('ac_city','ac_grp_space','020',1,0,'asset_city','Města a obce','CITY','Města a obce, ve kterých se nacházejí lokality a budovy organizace (volitelná úroveň prostorové hierarchie).','<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M15 11V5l-3-3-3 3v2H3v14h18V11h-6zm-8 8H5v-2h2v2zm0-4H5v-2h2v2zm0-4H5V9h2v2zm6 8h-2v-2h2v2zm0-4h-2v-2h2v2zm0-4h-2V9h2v2zm0-4h-2V5h2v2zm6 12h-2v-2h2v2zm0-4h-2v-2h2v2z"/></svg>'),
	('ac_data','ac_grp_info','010',0,0,'asset_data','Datová aktiva (Informace a databáze)','DATA','Datová aktiva, databáze a logické informační celky uložené na hostitelských počítačích, médiích nebo v dokumentech.','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M12 3C7.58 3 4 4.79 4 7s3.58 4 8 4 8-1.79 8-4-3.58-4-8-4zM4 9v3c0 2.21 3.58 4 8 4s8-1.79 8-4V9c0 2.21-3.58 4-8 4s-8-1.79-8-4zm0 5v3c0 2.21 3.58 4 8 4s8-1.79 8-4v-3c0 2.21-3.58 4-8 4s-8-1.79-8-4z"/></svg>'),
	('ac_data_business','ac_data','030',1,1,'asset_data','Obchodní tajemství, smluvní a zákaznická data','DAT-BUS','Databáze klientů, smluv, cenotvorby, know-how a strategických podkladů organizace.',''),
	('ac_data_financial','ac_data','020',1,1,'asset_data','Finanční, účetní a platební data','DAT-FIN','Účetní knihy, daňové doklady, platební příkazy a finanční výkazy.',''),
	('ac_data_operational','ac_data','040',1,1,'asset_data','Provozní, technická a konfigurační data','DAT-OPS','Provozní evidence, výrobní data, zdrojové kódy a konfigurační databáze infrastruktury.',''),
	('ac_data_other','ac_data','090',1,1,'asset_data','Jiná datová aktiva','DAT-OTH','Ostatní elektronické nebo logické soubory informací a databáze.',''),
	('ac_data_personal','ac_data','010',1,1,'asset_data','Osobní a citlivé údaje (GDPR / HR)','DAT-PII','Osobní údaje zaměstnanců, zákazníků nebo třetích stran podléhající zákonné ochraně (GDPR).',''),
	('ac_data_security','ac_data','050',1,1,'asset_data','Bezpečnostní data (přístupové údaje, klíče, logy)','DAT-SEC','Kryptografické klíče, certifikáty, databáze účtů, auditní logy a bezpečnostní záznamy.',''),
	('ac_district','ac_grp_space','010',1,0,'asset_district','Okresy a regiony','DIST','Územní okresy a regiony představující nejvyšší volitelnou úroveň prostorového členění aktiv.','<svg viewBox="0 0 24 24" fill="#0D9488"><path d="M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z"/></svg>'),
	('ac_doc_legal','ac_document','010',1,1,'asset_document','Smlouvy, právní a statutární dokumenty','DOC-LEG','Originály smluv, zřizovacích listin, licencí, povolení a právně závazných spisů (Vital Records).',''),
	('ac_doc_ops','ac_document','020',1,1,'asset_document','Provozní, bezpečnostní a havarijní dokumentace','DOC-OPS','Listinné či řízené směrnice, krizové plány (BCP/DRP), provozní manuály a schémata.',''),
	('ac_doc_other','ac_document','090',1,1,'asset_document','Jiné řízené dokumenty','DOC-OTH','Ostatní listinné a elektronické dokumenty (účetní, personální, projektové spisy).',''),
	('ac_document','ac_grp_info','020',0,0,'asset_document','Dokumenty','DOC','Řízené listinné i elektronické dokumenty, smlouvy a provozní dokumentace uložená v místnostech a nesoucí informace.','<svg viewBox="0 0 24 24" fill="#9333EA"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>'),
	('ac_fac_hvac','ac_phys_facility','020',1,0,'asset_physical','Klimatizace a chlazení (HVAC)','FAC-HVAC','Jednotky přesného chlazení serveroven, klimatizace a vzduchotechnika technologických místností.',''),
	('ac_fac_other','ac_phys_facility','090',1,0,'asset_physical','Jiná podpůrná technologie budovy','FAC-OTH','Ostatní podpůrná technická zařízení budov a sálů.',''),
	('ac_fac_power','ac_phys_facility','010',1,0,'asset_physical','Záložní napájení (UPS / dieselagregát)','FAC-PWR','Nepřerušitelné zdroje napájení (UPS), bateriová pole, motorgenerátory a PDU.',''),
	('ac_fac_sec','ac_phys_facility','030',1,0,'asset_physical','Fyzické zabezpečení (EPS / EZS / CCTV / EKV)','FAC-SEC','Elektrická požární a zabezpečovací signalizace, stabilní hasicí zařízení, kamery a kontrola vstupu.',''),
	('ac_grp_info',NULL,'030',0,0,'','Informace, data, dokumenty a média','INFO','Složka datových aktiv, dokumentů a přenosných či záložních paměťových médií.','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/></svg>'),
	('ac_grp_people_ext',NULL,'060',0,0,'','Personál a externí dodavatelé','PPL','Složka lidských zdrojů, klíčových rolí a externích dodavatelů či servisních partnerů.','<svg viewBox="0 0 24 24" fill="#059669"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>'),
	('ac_grp_services',NULL,'050',0,0,'','Služby a komunikační rozhraní','SRV','Složka primárních byznys služeb, interních podpůrných služeb a externích/interních rozhraní (interface).','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/></svg>'),
	('ac_grp_space',NULL,'010',0,0,'','Prostory a lokality','LOC','Hierarchická složka prostorového umístění aktiv (Okres -> Město -> Lokalita -> Budova -> Místnost).','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>'),
	('ac_grp_sw_apps',NULL,'040',0,0,'','Software a instalované aplikace','SW','Složka vyvíjeného či nakupovaného softwaru a konkrétních instalovaných aplikací.','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M20 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm-5 14H4v-4h11v4zm0-5H4V9h11v4zm5 5h-4V9h4v9z"/></svg>'),
	('ac_grp_tech',NULL,'020',0,0,'','Technická a fyzická aktiva (HW a sítě)','TECH','Složka hmotného vybavení, hostitelských počítačů, serverů, síťových prvků, technologií budov a kabeláže.','<svg viewBox="0 0 24 24" fill="#475569"><path d="M4 6h16v2H4zm0 5h16v2H4zm0 5h16v2H4z"/></svg>'),
	('ac_host','ac_grp_tech','010',0,0,'asset_host','Hostitelské počítače, servery a stanice','HOST','Fyzické a virtuální servery i koncové pracovní stanice. Role serverů (multi_class = 1) lze na jednom stroji kombinovat, pracovní stanice (multi_class = 0) jsou vůči serverům výlučné.','<svg viewBox="0 0 24 24" fill="#1D4ED8"><path d="M20 13H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1v-6c0-.55-.45-1-1-1zM7 19c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zM20 3H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1V4c0-.55-.45-1-1-1zM7 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"/></svg>'),
	('ac_host_app','ac_host','010',1,1,'asset_host','Aplikační server','HST-APP','Server provozující podnikové, oborové nebo integrační aplikace (kombinovatelná role).',''),
	('ac_host_cloud','ac_host','110',1,1,'asset_host','Cloudový server / IaaS instance','HST-CLD','Výpočetní instance hostovaná u externího cloudového poskytovatele (kombinovatelná role).',''),
	('ac_host_db','ac_host','020',1,1,'asset_host','Databázový server','HST-DB','Server provozující relační nebo NoSQL databázový stroj (kombinovatelná role).',''),
	('ac_host_file','ac_host','030',1,1,'asset_host','Souborový server','HST-FIL','Server poskytující sdílená souborová úložiště uživatelům a aplikacím (kombinovatelná role).',''),
	('ac_host_iam','ac_host','060',1,1,'asset_host','Adresářový, autentizační a PKI server','HST-IAM','Doménový řadič (Active Directory / LDAP), autentizační server, SSO nebo certifikační autorita (kombinovatelná role).',''),
	('ac_host_mail','ac_host','050',1,1,'asset_host','Poštovní a komunikační server','HST-ML','Server pro elektronickou poštu, přenos zpráv a komunikační brány (kombinovatelná role).',''),
	('ac_host_net','ac_host','070',1,1,'asset_host','Síťový a dohledový server (DNS/DHCP/NMS/SIEM)','HST-NET','Infrastrukturní server pro DNS, DHCP, NTP, správu sítě, firewallů a sběr logů (kombinovatelná role).',''),
	('ac_host_other','ac_host','120',1,1,'asset_host','Jiný hostitelský server','HST-OTH','Ostatní specializované servery (kombinovatelná role).',''),
	('ac_host_print','ac_host','080',1,1,'asset_host','Tiskový server','HST-PRT','Server zajišťující správu tiskových front a síťového tisku (kombinovatelná role).',''),
	('ac_host_virt','ac_host','090',1,1,'asset_host','Virtualizační hostitel / hypervizor','HST-HYP','Fyzický hostitelský server provozující hypervizor pro běh virtuálních strojů (kombinovatelná role).',''),
	('ac_host_vm','ac_host','100',1,1,'asset_host','Virtuální server / kontejnerový uzel','HST-VM','Virtuální server (VM) nebo uzel kontejnerové platformy (kombinovatelná role).',''),
	('ac_host_web','ac_host','040',1,1,'asset_host','Webový a portálový server','HST-WEB','Server hostující webové prezentace, reverzní proxy, portály a API (kombinovatelná role).',''),
	('ac_ifc_data','ac_interface','010',1,1,'asset_interface','Datové a internetové připojení (WAN / MPLS / VPN)','IFC-DAT','Přístup k internetu, privátní datové okruhy, pronajaté linky, optika a VPN konektivita.',''),
	('ac_ifc_edi_api','ac_interface','040',1,1,'asset_interface','Externí integrační rozhraní (EDI / API / platební brána)','IFC-API','Elektronická výměna dat (EDI), napojení na bankovní, státní nebo partnerská API.',''),
	('ac_ifc_other','ac_interface','090',1,1,'asset_interface','Jiná komunikační služba typu Interface','IFC-OTH','Ostatní externí nebo interní přenosové a komunikační služby.',''),
	('ac_ifc_video','ac_interface','030',1,1,'asset_interface','Videokonferenční a AV přenosová služba','IFC-VID','Služby pro video přenosy, videokonference a dálkovou vizuální komunikaci.',''),
	('ac_ifc_voice','ac_interface','020',1,1,'asset_interface','Hlasová a telefonní služba (VoIP / mobilní / pevná)','IFC-VOX','Veřejná i neveřejná hlasová spojení, SIP trunky, mobilní hlasové a SMS služby.',''),
	('ac_interface','ac_grp_services','020',0,0,'asset_interface','Služby typu Interface (Internet, hlas, video)','IFC','Externí nebo interní propojovací a komunikační služby (internetová konektivita, hlasové a video spojení, API rozhraní) vyžadované jinými službami.','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9v-2h2v2zm0-4H9V7h2v5zm4 4h-2v-2h2v2zm0-4h-2V7h2v5z"/></svg>'),
	('ac_med_disk','ac_media','020',1,0,'asset_media','Výměnné a externí disky / USB / SSD','MED-DSK','Externí pevné disky, USB flash disky, paměťové karty a vyjímatelné diskové kazety.',''),
	('ac_med_optical','ac_media','030',1,0,'asset_media','Optická a jiná archivní média','MED-OPT','Optické disky (CD/DVD/Blu-ray) a ostatní fyzické nosiče dat.',''),
	('ac_med_tape','ac_media','010',1,0,'asset_media','Záložní magnetické pásky','MED-TAP','Pásková média (LTO) pro offline zálohování a dlouhodobou archivaci dat.',''),
	('ac_media','ac_grp_info','030',0,0,'asset_media','Média a nosiče dat','MED','Přenosná a záložní paměťová média (záložní pásky, externí disky, flash disky, optické nosiče) uložená v místnostech nebo trezorech.','<svg viewBox="0 0 24 24" fill="#DB2777"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14.5c-2.49 0-4.5-2.01-4.5-4.5S9.51 7.5 12 7.5s4.5 2.01 4.5 4.5-2.01 4.5-4.5 4.5zm0-5.5c-.55 0-1 .45-1 1s.45 1 1 1 1-.45 1-1-.45-1-1-1z"/></svg>'),
	('ac_net_firewall','ac_phys_net','030',1,1,'asset_physical','Firewall / UTM / IDS-IPS / VPN brána','NET-FW','Bezpečnostní síťové brány, firewally, systémy detekce/prevence průniků a VPN koncentrátory.',''),
	('ac_net_other','ac_phys_net','090',1,1,'asset_physical','Jiný síťový prvek','NET-OTH','Ostatní aktivní i pasivní síťové prvky (load balancery, převodníky, modemy, optické vany).',''),
	('ac_net_pbx','ac_phys_net','050',1,1,'asset_physical','Telefonní ústředna / VoIP brána','NET-PBX','Pobočkové telefonní ústředny a hardwarové hlasové brány.',''),
	('ac_net_router','ac_phys_net','010',1,1,'asset_physical','Směrovač (Router / WAN brána)','NET-RTR','Směrovače a hraniční síťové brány propojující lokální a vnější sítě.',''),
	('ac_net_switch','ac_phys_net','020',1,1,'asset_physical','Síťový přepínač (Switch)','NET-SW','Páteřní i přístupové síťové přepínače LAN a SAN.',''),
	('ac_net_wifi','ac_phys_net','040',1,1,'asset_physical','Bezdrátový přístupový bod (Wi-Fi AP / pojítko)','NET-WIF','Wi-Fi přístupové body, kontroléry a směrová bezdrátová/mikrovlnná pojítka.',''),
	('ac_periph_other','ac_phys_periph','090',1,0,'asset_physical','Jiné periferní zařízení','PER-OTH','Ostatní periferní a kancelářská technika (čtečky, projektory, terminály).',''),
	('ac_periph_phone','ac_phys_periph','020',1,0,'asset_physical','Stolní / IP telefon a konferenční zařízení','PER-PHN','Stolní drátové a bezdrátové telefony, IP telefony a audio/videokonferenční jednotky.',''),
	('ac_periph_printer','ac_phys_periph','010',1,0,'asset_physical','Tiskárna / skener / multifunkční zařízení','PER-PRT','Síťové i lokální tiskárny, kopírky, skenery a multifunkční zařízení.',''),
	('ac_pers_dev','ac_personnel','030',1,1,'asset_personnel','Vývojáři, analytici a správci aplikací','PRS-DEV','Interní vývojáři, aplikační garanti a databázoví specialisté.',''),
	('ac_pers_ext','ac_personnel','050',1,1,'asset_personnel','Externí konzultanti a smluvní pracovníci','PRS-EXT','Smluvní pracovníci a externí specialisté s přístupem k aktivům nebo prostorům organizace.',''),
	('ac_pers_it_admin','ac_personnel','020',1,1,'asset_personnel','IT administrátoři, správci sítí a bezpečnosti','PRS-ADM','Privilegovaní správci serverů, sítí, databází a manažeři kybernetické bezpečnosti.',''),
	('ac_pers_mgmt','ac_personnel','010',1,1,'asset_personnel','Vedení organizace a vlastníci procesů / aktiv','PRS-MGT','Statutární orgány, manažeři a vlastníci byznys služeb a klíčových aktiv.',''),
	('ac_pers_ops','ac_personnel','040',1,1,'asset_personnel','Provozní personál, obsluha a běžní uživatelé','PRS-OPS','Zaměstnanci obsluhující aplikace, zákaznické služby a podpůrné provozy.',''),
	('ac_personnel','ac_grp_people_ext','010',0,0,'asset_personnel','Personál a klíčové role','PERS','Interní i externí pracovníci, administrátoři, operátoři a klíčové pracovní role nezbytné pro provoz aplikací, služeb a realizaci protiopatření.','<svg viewBox="0 0 24 24" fill="#059669"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>'),
	('ac_phys_facility','ac_physical','040',0,0,'asset_physical','Podpůrná technika a zabezpečení budov','PHYS-FAC','Zařízení zajišťující napájení, chlazení a fyzickou ochranu budov a serveroven.',''),
	('ac_phys_net','ac_physical','010',0,0,'asset_physical','Síťové a bezpečnostní prvky','PHYS-NET','Aktivní síťové a bezpečnostní prvky propojující a chránící komunikační infrastrukturu.',''),
	('ac_phys_periph','ac_physical','030',0,0,'asset_physical','Periferní a komunikační zařízení','PHYS-PER','Tisková, skenovací, hlasová a konferenční technika umístěná v místnostech.',''),
	('ac_phys_storage','ac_physical','020',0,0,'asset_physical','Paměťová zařízení a úložiště','PHYS-STR','Vyhrazená hardwarová datová úložiště a záložní jednotky (mimo výměnná média).',''),
	('ac_physical','ac_grp_tech','020',0,0,'asset_physical','Fyzická aktiva a hardware','HW','Obecná hmotná a technická aktiva, síťové prvky, paměťová úložiště, periferie a podpůrné technologie budov (UPS, klimatizace, EPS/EZS) umístěné v místnostech.','<svg viewBox="0 0 24 24" fill="#475569"><path d="M20 18c1.1 0 1.99-.9 1.99-2L22 6c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2H0v2h24v-2h-4zM4 6h16v10H4V6z"/></svg>'),
	('ac_room','ac_grp_space','050',0,0,'asset_room','Místnosti a sály','ROOM','Konkrétní místnosti, serverovny, archivy a pracoviště uvnitř budov. Do místností se povinně umisťují fyzická aktiva, hostitelské počítače, dokumenty a média.','<svg viewBox="0 0 24 24" fill="#0369A1"><path d="M19 19V4h-4V3H5v16H3v2h12V6h2v15h4v-2h-2zm-6 0H7V5h6v14zm-3-8h2v2h-2v-2z"/></svg>'),
	('ac_room_archive','ac_room','030',1,1,'asset_room','Spisovna / archiv / trezor','RM-ARC','Zabezpečená místnost nebo trezor pro ukládání důležitých dokumentů a offline zálohovacích médií.',''),
	('ac_room_office','ac_room','040',1,1,'asset_room','Kancelář / běžné pracoviště','RM-OFF','Uzavřený pracovní prostor pro interní zaměstnance a pracovní stanice.',''),
	('ac_room_other','ac_room','090',1,1,'asset_room','Jiná místnost / prostor','RM-OTH','Ostatní provozní nebo skladové místnosti uvnitř budovy.',''),
	('ac_room_public','ac_room','050',1,0,'asset_room','Recepce / veřejně přístupný prostor','RM-PUB','Prostory přístupné návštěvníkům, zákazníkům nebo veřejnosti (výlučné vůči zabezpečeným zónám).',''),
	('ac_room_server','ac_room','010',1,1,'asset_room','Serverovna / datový sál','RM-SRV','Vyhrazený zabezpečený prostor pro servery, síťové jádro a datová úložiště.',''),
	('ac_room_tech','ac_room','020',1,1,'asset_room','Technická místnost / rozvodna / UPS','RM-TEC','Místnost s rozvaděči, kabelovými uzly, UPS, klimatizací nebo fyzickou technologií budovy.',''),
	('ac_service','ac_grp_services','010',0,0,'asset_service','Služby (interní a zákaznické)','SVC','Hlavní byznys služby a interní podpůrné služby organizace podporované aplikacemi, rozhraními a personálem, u nichž se hodnotí dopady výpadků do jednotlivých oblastí.','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M12 2l-5.5 9h11L12 2zm0 3.84L13.93 9h-3.87L12 5.84zM17.5 13c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zM3 21.5h8v-8H3v8z"/></svg>'),
	('ac_site','ac_grp_space','030',1,0,'asset_site','Lokality a areály','SITE','Areály, kampusy a pobočky sdružující více budov v rámci města nebo obce (volitelná úroveň prostorové hierarchie).','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/></svg>'),
	('ac_software','ac_grp_sw_apps','010',0,0,'asset_software','Software (vyvíjený a pořizovaný)','SWP','Zdrojové softwarové produkty, interně vyvíjený software a instalační balíky, které mohou být zdrojem softwarových chyb pro instalované aplikace.','<svg viewBox="0 0 24 24" fill="#4F46E5"><path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/></svg>'),
	('ac_srv_business','ac_service','010',1,1,'asset_service','Klíčová zákaznická / byznys služba','SRV-BUS','Hlavní produktová nebo zákaznická služba generující výnosy či plnící zákonné poslání organizace.',''),
	('ac_srv_cloud','ac_service','030',1,1,'asset_service','Externě provozovaná SaaS / cloudová služba','SRV-CLD','Služba poskytovaná formou SaaS / PaaS třetí stranou.',''),
	('ac_srv_internal','ac_service','020',1,1,'asset_service','Interní podpůrná a IT služba','SRV-INT','Interní provozní, infrastrukturní nebo administrativní služba podporující chod organizace.',''),
	('ac_srv_other','ac_service','090',1,1,'asset_service','Jiná služba','SRV-OTH','Ostatní poskytované nebo využívané služby organizace.',''),
	('ac_stor_other','ac_phys_storage','090',1,0,'asset_physical','Jiné paměťové zařízení','STR-OTH','Ostatní hardwarová paměťová a archivační zařízení.',''),
	('ac_stor_san_nas','ac_phys_storage','010',1,0,'asset_physical','Diskové pole (SAN / NAS)','STR-SAN','Centrální síťová a bloková disková pole (SAN, NAS, hyperkonvergovaná úložiště).',''),
	('ac_stor_tape','ac_phys_storage','020',1,0,'asset_physical','Pásková knihovna / záložní jednotka','STR-TAP','Hardwarové páskové knihovny a dedikované zálohovací appliance.',''),
	('ac_sup_facility','ac_supplier','030',1,1,'asset_supplier','Dodavatel energií, facility a fyzické ostrahy','SUP-FAC','Poskytovatelé elektrické energie, správy budov, klimatizace, úklidu a fyzické ostrahy.',''),
	('ac_sup_it_cloud','ac_supplier','010',1,1,'asset_supplier','Dodavatel IT, SW a cloudových služeb','SUP-IT','Dodavatelé vývoje a servisu softwaru, hardwaru, datových center a cloudových platforem.',''),
	('ac_sup_other','ac_supplier','090',1,1,'asset_supplier','Jiný externí dodavatel / partner','SUP-OTH','Ostatní smluvní partneři, poradci a dodavatelé v dodavatelském řetězci.',''),
	('ac_sup_telecom','ac_supplier','020',1,1,'asset_supplier','Telekomunikační operátor / ISP','SUP-TEL','Poskytovatelé internetového připojení, datových okruhů a hlasových/mobilních služeb.',''),
	('ac_supplier','ac_grp_people_ext','020',0,0,'asset_supplier','Dodavatelé a externí partneři','SUP','Externí dodavatelé komunikačních rozhraní (interface), cloudových služeb, hardwaru, softwaru a servisní podpory.','<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4z"/></svg>'),
	('ac_sw_bespoke','ac_software','010',1,0,'asset_software','Software vyvíjený na zakázku / interní vývoj','SW-BSP','Aplikace vyvíjené na míru interně nebo externím dodavatelem se správou zdrojového kódu.',''),
	('ac_sw_oss','ac_software','030',1,0,'asset_software','Open-source a komunitní software','SW-OSS','Otevřený software a knihovny provozované bez komerční podpory nebo s komunitní podporou.',''),
	('ac_sw_other','ac_software','090',1,0,'asset_software','Jiný softwarový produkt','SW-OTH','Ostatní softwarové balíky a nástroje.',''),
	('ac_sw_package','ac_software','020',1,0,'asset_software','Komerční krabicový software (COTS)','SW-PKG','Standardní komerčně pořizovaný aplikační software od externího výrobce.',''),
	('ac_sw_system','ac_software','040',1,0,'asset_software','Systémový software (OS / DBMS / middleware)','SW-SYS','Operační systémy, databázové stroje, aplikační servery a virtualizační platformy.',''),
	('ac_workstation','ac_host','200',0,0,'asset_host','Pracovní stanice a koncová zařízení','WS','Koncové počítače a mobilní zařízení uživatelů (multi_class = 0: nelze kombinovat se servery).',''),
	('ac_ws_desktop','ac_workstation','010',1,0,'asset_host','Pevná pracovní stanice / PC','WS-PC','Stolní osobní počítač nebo pracovní stanice pevně umístěná na pracovišti.',''),
	('ac_ws_laptop','ac_workstation','020',1,0,'asset_host','Přenosný počítač / notebook','WS-NB','Notebook nebo přenosná pracovní stanice využívaná v kanceláři i mimo prostory organizace.',''),
	('ac_ws_mobile','ac_workstation','040',1,0,'asset_host','Chytré mobilní zařízení (smartphone / tablet)','WS-MOB','Služební chytré telefony a tablety s přístupem k poště, dokumentům či aplikacím.',''),
	('ac_ws_other','ac_workstation','090',1,0,'asset_host','Jiná pracovní stanice','WS-OTH','Ostatní koncová uživatelská výpočetní zařízení.',''),
	('ac_ws_terminal','ac_workstation','030',1,0,'asset_host','Terminál / tenký klient','WS-TRM','Pevně umístěný terminál, tenký klient nebo pokladní/kioskový terminál.','');

	-- 0. Úklid zastaralých systémových záznamů (0x00, who_modified = 0x00), které již nejsou v @ac_cs
	DELETE t
	FROM asset_class t
	LEFT JOIN @ac_cs s ON s.builtin_code = t.builtin_code
	WHERE t.object_owner = @sys_owner
	  AND t.who_modified = @sys_owner
	  AND t.record_type IN ('A', 'L')
	  AND s.builtin_code IS NULL;

	-- 1. Idempotentní UPDATE existujících hlavních záznamů (record_type = 'A', language = 'cs')
	UPDATE t
	SET t.parent_uuid = p.parent_orig,
		t.sort_code = s.sort_code,
		t.is_leaf = s.is_leaf,
		t.multi_class = s.multi_class,
		t.instance_class_name = s.instance_class_name,
		t.caption = s.caption,
		t.shortname = s.shortname,
		t.description_text = s.description_text,
		t.svg_icon = CASE WHEN ISNULL(t.svg_icon, '') = '' AND s.svg_icon <> '' THEN s.svg_icon ELSE t.svg_icon END,
		t.[language] = 'cs',
		t.date_modified = @now
	FROM asset_class t
	JOIN @ac_cs s ON s.builtin_code = t.builtin_code
	OUTER APPLY (
		SELECT CASE WHEN s.parent_code IS NOT NULL THEN dbo.f_generate_original('asset_class', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig
	) p
	WHERE t.object_owner = @sys_owner
	  AND t.record_type = 'A'
	  AND t.who_modified = @sys_owner
	  AND EXISTS (
		SELECT t.parent_uuid, t.sort_code, t.is_leaf, t.multi_class, t.instance_class_name, t.caption, t.shortname, t.description_text
		EXCEPT
		SELECT p.parent_orig, s.sort_code, s.is_leaf, s.multi_class, s.instance_class_name, s.caption, s.shortname, s.description_text
	  );

	-- 2. Idempotentní INSERT chybějících hlavních záznamů (record_type = 'A', language = 'cs')
	INSERT INTO asset_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, multi_class, instance_class_name,
		caption, shortname, description_text, svg_icon, is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
		s.builtin_code, p.parent_orig, s.sort_code, s.is_leaf, s.multi_class, s.instance_class_name,
		s.caption, s.shortname, s.description_text, s.svg_icon, 0, 1,
		@now, @sys_owner, @now, @sys_owner
	FROM @ac_cs s
	CROSS APPLY (
		SELECT dbo.f_generate_original('asset_class', @sys_owner, s.builtin_code, '') AS orig
	) x
	OUTER APPLY (
		SELECT CASE WHEN s.parent_code IS NOT NULL THEN dbo.f_generate_original('asset_class', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig
	) p
	WHERE NOT EXISTS (
		SELECT 1 FROM asset_class t
		WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
	);

	-- 3. Idempotentní UPDATE a INSERT symetrických 'L' záznamů pro češtinu (language = 'cs')
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
	JOIN @ac_cs s ON s.builtin_code = a.builtin_code
	WHERE l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
	  AND l.who_modified = @sys_owner
	  AND EXISTS (
		SELECT l.parent_uuid, l.sort_code, l.is_leaf, l.multi_class, l.instance_class_name, l.caption, l.shortname, l.description_text
		EXCEPT
		SELECT a.parent_uuid, a.sort_code, a.is_leaf, a.multi_class, a.instance_class_name, s.caption, s.shortname, s.description_text
	  );

	INSERT INTO asset_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, parent_uuid, sort_code, is_leaf, multi_class, instance_class_name,
		caption, shortname, description_text, svg_icon, is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
		a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.multi_class, a.instance_class_name,
		s.caption, s.shortname, s.description_text, a.svg_icon, a.is_final, a.is_protected,
		@now, @sys_owner, @now, @sys_owner
	FROM asset_class a
	JOIN @ac_cs s ON s.builtin_code = a.builtin_code
	WHERE a.object_owner = @sys_owner
	  AND a.record_type = 'A'
	  AND a.removed = 0
	  AND NOT EXISTS (
		SELECT 1 FROM asset_class l
		WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
	  );

	IF OBJECT_ID('dbo.p_sync_derived_links', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_derived_links;
	END
END
GO