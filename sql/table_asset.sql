/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: table_asset.sql
 * Tabulka: asset (Evidence aktiv organizace – STI úložiště všech archetypů)
 * Popis:   Společná fyzická tabulka pro evidenci všech tříd a archetypů aktiv
 *          v modulu CRMM (Prostory: okres, město, lokalita, budova, místnost;
 *          Fyzická aktiva, Hostitelské počítače, Kabeláž, Dokumenty, Média,
 *          Datová aktiva, Software, Instalované aplikace, Služby, Služby typu
 *          Interface, Personál a Dodavatelé).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus) + STI
 * Vazby:   - primary_asset_class ukazuje na koncový uzel asset_class.original.
 *          - parent_uuid umožňuje exkluzivní stromovou hierarchii (zejména pro
 *            Prostory: Okres -> Město -> Lokalita -> Budova -> Místnost, příp.
 *            podsystémy aktiv) a automaticky se promítá do tabulky link.
 *          - owner_user_uuid ukazuje na user_account.original (vlastník/garant).
 *          - Veškeré umístění aktiv v prostorech a provozní vazby M:N
 *            (aplikace -> host, aplikace -> data, služba -> aplikace atd.)
 *            jsou uloženy v tabulce link podle definic v meta_link_def.
 * Změny:
 * - 2026-11-13 17:00: Doplněna registrace třídy asset, 17 odvozených STI tříd
 *   aktiv, číselníku asset_archetype a sloupců do sysinit_class,
 *   sysinit_codetable a sysinit_column.
 * - 2026-11-11 21:30: Odstraněny duplicitní 1:N sloupce building_uuid, room_uuid,
 *   host_uuid, software_uuid a supplier_uuid (nahrazeno přímým parent_uuid a
 *   univerzálními vazbami v tabulce link).
 * ============================================================================= */

IF OBJECT_ID('asset') IS NULL
BEGIN
	CREATE TABLE asset (
		-- ---------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- ---------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,
		original uuid NOT NULL DEFAULT 0x00,
		record_type varchar(1) NOT NULL DEFAULT 'A',
		approval_status varchar(1) NOT NULL DEFAULT 'A',
		draft_author uuid NOT NULL DEFAULT 0x00,
		approval_note varchar(max) NOT NULL DEFAULT '',
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		is_template bit NOT NULL DEFAULT 0,
		template uuid NULL,
		import_origin varchar(255) NULL,

		-- ---------------------------------------------------------------------
		-- Auditní stopy
		-- ---------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- ---------------------------------------------------------------------
		-- Společné identifikační a prezentační vlastnosti
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',                        -- Unikátní kód aktiva (automaticky odvozený z názvu)
		external_code varchar(40) NOT NULL DEFAULT '',                       -- Externí kód / spárování s CMDB či majetkovou evidencí
		inventory_number varchar(80) NOT NULL DEFAULT '',                    -- Inventární nebo sériové číslo (pro HW, média, dokumenty)
		caption varchar(200) NOT NULL DEFAULT '',                            -- Zobrazovaný název aktiva (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',                           -- Zkratka aktiva
		description_text varchar(max) NOT NULL DEFAULT '',                   -- Podrobný popis aktiva (is_html = 1)
		help_text varchar(max) NOT NULL DEFAULT '',                          -- Metodická nápověda / pokyny (is_html = 1)
		note varchar(max) NOT NULL DEFAULT '',                               -- Interní poznámka (is_html = 1)
		svg_icon varchar(max) NOT NULL DEFAULT '',                           -- Vektorová ikona SVG

		-- ---------------------------------------------------------------------
		-- Klasifikace STI archetypu, primární třída, strom a vlastník
		-- ---------------------------------------------------------------------
		asset_archetype varchar(30) NOT NULL DEFAULT 'PHYSICAL',             -- Archetyp STI (DISTRICT, CITY, SITE, BUILDING, ROOM, PHYSICAL, HOST, CABLING, DOCUMENT, MEDIA, DATA, SOFTWARE, APPLICATION, SERVICE, INTERFACE, PERSONNEL, SUPPLIER)
		primary_asset_class uuid NULL,                                       -- Primární koncová třída aktiv (asset_class.original s is_leaf = 1)
		parent_uuid uuid NULL,                                               -- Exkluzivní nadřízené aktivum / prostor ve stromu (asset.original)
		sort_code varchar(200) NOT NULL DEFAULT '',                          -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                                      -- 1 = Koncová položka, 0 = Složka / souhrnný uzel
		owner_user_uuid uuid NULL,                                           -- Vlastník / garant aktiva (user_account.original)

		-- ---------------------------------------------------------------------
		-- Parametry dostupnosti (BIA) a agregované skóre hodnocení rizik (0..100 %)
		-- ---------------------------------------------------------------------
		rto_hours decimal(9,2) NULL,                                         -- Recovery Time Objective – max. přijatelná doba výpadku v hodinách
		rpo_hours decimal(9,2) NULL,                                         -- Recovery Point Objective – max. přijatelná ztráta dat od poslední zálohy v hodinách
		confidentiality_score decimal(9,4) NULL,                             -- Skóre požadavku na důvěrnost (dopad prozrazení dat, 0 až 100 %)
		integrity_score decimal(9,4) NULL,                                   -- Skóre požadavku na integritu (dopad chyby/nekonzistence/likvidace dat, 0 až 100 %)
		availability_score decimal(9,4) NULL,                                -- Skóre požadavku na dostupnost (dopad výpadku služby/dat, 0 až 100 %)
		inherent_risk_score decimal(9,4) NULL,                               -- Vypočtené agregované inherentní riziko aktiva (0 až 100 %)
		residual_risk_score decimal(9,4) NULL,                               -- Vypočtené agregované zbytkové (reziduální) riziko aktiva (0 až 100 %)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových a šablonových záznamů
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_asset PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka asset byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců a odstranění vyčleněných 1:N sloupců
-- -----------------------------------------------------------------------------
EXEC sp_drop_index 'asset', 'ix_asset_locations';
EXEC sp_drop_column 'asset', 'building_uuid';
EXEC sp_drop_column 'asset', 'room_uuid';
EXEC sp_drop_column 'asset', 'host_uuid';
EXEC sp_drop_column 'asset', 'software_uuid';
EXEC sp_drop_column 'asset', 'supplier_uuid';
GO

EXEC p_create_missing_column 'asset', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'asset', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'asset', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'inventory_number', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'asset_archetype', 'varchar(30) NOT NULL DEFAULT ''PHYSICAL''';
EXEC p_create_missing_column 'asset', 'primary_asset_class', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'asset', 'owner_user_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'rto_hours', 'decimal(9,2) NULL';
EXEC p_create_missing_column 'asset', 'rpo_hours', 'decimal(9,2) NULL';
EXEC p_create_missing_column 'asset', 'confidentiality_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'integrity_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'availability_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'inherent_risk_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'residual_risk_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'asset', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury, stromu prostorů a filtrování STI
-- -----------------------------------------------------------------------------
EXEC sp_create_index
	@tname = 'asset',
	@iname = 'uq_asset_active',
	@colnames = 'original, object_owner',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'uq_asset_language',
	@colnames = 'original, object_owner, language',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'uq_asset_draft',
	@colnames = 'original, object_owner, language, draft_author',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'ix_asset_parent_sort',
	@colnames = 'object_owner, parent_uuid, sort_code, builtin_code',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'ix_asset_archetype_class',
	@colnames = 'object_owner, asset_archetype, primary_asset_class',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace tříd, číselníku asset_archetype a sloupců do sysinit_*
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'asset' OR class_name LIKE 'asset[_]%' AND class_name <> 'asset_class';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, ancestor_code, sort_code, is_final, is_protected, caption, caption_plural, description, helptext) VALUES
	('asset','cs','T','asset','','010',0,1,'Aktivum','Evidence aktiv','Evidence konkrétních primárních a podpůrných aktiv a prostorů organizace zařazených do koncových tříd aktiv.','Hlavní katalog aktiv organizace, nad kterými se provádí analýza a hodnocení rizik.'),
	('asset_application','cs','T','asset','asset','130',0,1,'Aplikace (instalovaná)','Aplikace (instalované)','Instalované instance aplikačního vybavení provozované na hostitelských počítačích, vyžadující datová aktiva a personál.','Evidence provozovaných aplikací. Přijímá dopady z datových aktiv, HW hostů a SW balíků a přenáší je na podporované služby.'),
	('asset_building','cs','T','asset','asset','040',0,1,'Budova','Budovy','Stavební objekty a budovy organizace. V organizaci musí být definována alespoň jedna budova (i fiktivní).','Do budov se povinně zařazují místnosti a kabeláž. Budova může být zařazena do lokality.'),
	('asset_cabling','cs','T','asset','asset','080',0,1,'Kabeláž a rozvody','Kabeláž a rozvody','Strukturovaná datová kabeláž, optické trasy a silnoproudé rozvody umístěné v budově.','Kabeláž musí být umístěna v budově a volitelně propojuje místnosti a hostitelské počítače.'),
	('asset_city','cs','T','asset','asset','020',0,1,'Město / obec','Města a obce','Města a obce, ve kterých se nacházejí lokality a budovy organizace.','Volitelná úroveň prostorové hierarchie (Město je v Okrese, jsou-li okresy definovány).'),
	('asset_data','cs','T','asset','asset','110',0,1,'Datové aktivum','Datová aktiva','Datová aktiva, databáze a logické informační celky uložené na hostitelských počítačích, médiích nebo v dokumentech.','Hodnotí se dopady prozrazení, nekonzistence/chyb (od drobných chyb po ztrátu od poslední zálohy či likvidaci) a nedostupnosti dat.'),
	('asset_district','cs','T','asset','asset','010',0,1,'Okres / region','Okresy a regiony','Územní okresy a regiony představující nejvyšší volitelnou úroveň prostorového členění aktiv.','Nejvyšší volitelná úroveň prostorové hierarchie.'),
	('asset_document','cs','T','asset','asset','090',0,1,'Dokument','Dokumenty','Řízené listinné a elektronické dokumenty uložené v místnostech a obsahující datová aktiva.','Každý dokument musí být umístěn v konkrétní místnosti.'),
	('asset_host','cs','T','asset','asset_physical','070',0,1,'Hostitelský počítač / server','Hostitelské počítače a servery','Speciální podtřída fyzických aktiv: fyzické a virtuální servery a hostitelské počítače umístěné v místnostech.','Na hostitelských počítačích běží instalované aplikace a jsou na nich uložena datová aktiva.'),
	('asset_interface','cs','T','asset','asset','150',0,1,'Služba typu Interface','Služby typu Interface (Internet, hlas, video)','Externí nebo interní propojovací a komunikační služby (internet, hlasové či video spojení, API) vyžadované službami a aplikacemi.','Služby rozhraní jsou typicky zajišťovány externím dodavatelem nebo dříve definovanou interní službou.'),
	('asset_media','cs','T','asset','asset','100',0,1,'Médium / nosič dat','Média a nosiče dat','Přenosná a záložní paměťová média (pásky, disky, trezorová média) uložená v místnostech a nesoucí datová aktiva.','Každé paměťové médium musí být umístěno v místnosti.'),
	('asset_personnel','cs','T','asset','asset','160',0,1,'Personál / klíčová role','Personál a klíčové role','Klíčoví pracovníci, administrátoři a pracovní role vyžadované pro provoz aplikací, služeb a realizaci protiopatření.','Personál je zdrojem lidských chyb i rizika nedostupnosti klíčových osob.'),
	('asset_physical','cs','T','asset','asset','060',0,1,'Fyzické aktivum (HW / zařízení)','Fyzická aktiva a hardware','Hmotná a technická aktiva, síťové prvky, koncové stanice a podpůrné technologie budov umístěné v místnostech.','Každé fyzické aktivum musí být umístěno právě v jedné místnosti a může být zdrojem HW chyb a výpadků.'),
	('asset_room','cs','T','asset','asset','050',0,1,'Místnost','Místnosti a sály','Konkrétní místnosti, serverovny, archivy a pracoviště uvnitř budov.','Každá místnost musí patřit právě do jedné budovy. Do místností se umisťují fyzická aktiva, hostitelské počítače, dokumenty a média.'),
	('asset_service','cs','T','asset','asset','140',0,1,'Služba','Služby (interní a zákaznické)','Primární byznys služby a interní podpůrné služby organizace podporované aplikacemi, rozhraními a personálem.','U služeb se hodnotí dopady výpadků a degradace do jednotlivých oblastí (finanční, pověst, obecné ohrožení, trestní, řízení, zákony).'),
	('asset_site','cs','T','asset','asset','030',0,1,'Lokalita / areál','Lokality a areály','Areály, kampusy a pobočky sdružující budovy v rámci města nebo obce.','Volitelná úroveň prostorové hierarchie (Lokalita je ve Městě, jsou-li města definována).'),
	('asset_software','cs','T','asset','asset','120',0,1,'Software (vyvíjený / pořizovaný)','Software (vyvíjený a pořizovaný)','Vyvíjené nebo nakupované softwarové produkty a balíky, které se instalují jako aplikace.','Software je zdrojem softwarových chyb a zranitelností přenášených na instalované aplikace.'),
	('asset_supplier','cs','T','asset','asset','170',0,1,'Dodavatel / partner','Dodavatelé a externí partneři','Externí dodavatelé služeb typu Interface (internet, hlas, video), hardwaru, softwaru a servisní podpory.','Evidence třetích stran v dodavatelském řetězci.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('asset','en','Asset','Asset Inventory','Inventory of specific primary and supporting organization assets and spaces assigned to leaf asset classes.','Main catalog of organization assets subject to risk analysis and assessment.'),
	('asset_application','en','Application (Installed)','Applications (Installed)','Installed application instances running on host computers and requiring data assets and personnel.','Inventory of operational applications. Inherits impacts from data assets, HW hosts, and SW packages and propagates them to supported services.'),
	('asset_building','en','Building','Buildings','Organization buildings and facilities. At least one building (even fictitious) must be defined in the organization.','Rooms and cabling are mandatorily placed inside buildings. A building may be placed in a site.'),
	('asset_cabling','en','Cabling & Wiring','Cabling & Wiring','Structured data cabling, fiber optic routes, and power wiring located in a building.','Cabling must be placed in a building and optionally connects rooms and host computers.'),
	('asset_city','en','City / Municipality','Cities & Municipalities','Cities and municipalities where organization sites and buildings are located.','Optional spatial hierarchy level (City is in a District when districts are defined).'),
	('asset_data','en','Data Asset','Data Assets','Data assets, databases, and logical information sets stored on host computers, media, or documents.','Evaluated for impacts of disclosure, inconsistency/errors (from minor errors to loss since last backup or complete destruction), and unavailability.'),
	('asset_district','en','District / Region','Districts & Regions','Geographical districts and regions representing the highest optional level of spatial asset organization.','Top optional level of the spatial hierarchy.'),
	('asset_document','en','Document','Documents','Controlled paper and electronic documents stored in rooms and containing data assets.','Every document must be placed in a specific room.'),
	('asset_host','en','Host Computer / Server','Host Computers & Servers','Special subclass of physical assets: physical and virtual servers and host computers located in rooms.','Host computers run installed applications and store data assets.'),
	('asset_interface','en','Interface Service','Interface Services (Internet, Voice, Video)','External or internal connectivity and communication services (internet, voice or video links, APIs) required by services and applications.','Interface services are typically provided by an external supplier or a previously defined internal service.'),
	('asset_media','en','Media / Data Carrier','Media & Data Carriers','Portable and backup storage media (tapes, drives, vault media) stored in rooms and carrying data assets.','Every storage medium must be placed in a room.'),
	('asset_personnel','en','Personnel / Key Role','Personnel & Key Roles','Key staff members, administrators, and job roles required to operate applications, services, and countermeasures.','Personnel can be a source of human errors as well as key person unavailability risk.'),
	('asset_physical','en','Physical Asset (HW / Device)','Physical Assets & Hardware','Tangible and technical assets, network devices, workstations, and building utilities located in rooms.','Every physical asset must be placed in exactly one room and may be a source of HW faults and outages.'),
	('asset_room','en','Room','Rooms & Halls','Specific rooms, server rooms, archives, and workspaces inside buildings.','Every room must belong to exactly one building. Physical assets, host computers, documents, and media are placed in rooms.'),
	('asset_service','en','Service','Services (Internal & Customer-Facing)','Core business and internal support services supported by applications, interfaces, and personnel.','Services are evaluated for outage and degradation impacts across impact areas (financial, reputation, general hazard, criminal, management, legal).'),
	('asset_site','en','Site / Campus','Sites & Campuses','Sites, campuses, and branches grouping buildings within a city or municipality.','Optional spatial hierarchy level (Site is in a City when cities are defined).'),
	('asset_software','en','Software (Developed / Procured)','Software (Developed & Procured)','Developed or procured software products and packages deployed as installed applications.','Software is a source of software defects and vulnerabilities propagated to installed applications.'),
	('asset_supplier','en','Supplier / Partner','Suppliers & External Partners','External providers of Interface services (internet, voice, video), hardware, software, and maintenance support.','Registry of third parties in the supply chain.');
END

IF OBJECT_ID('sysinit_codetable', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_codetable WHERE codetable_name = 'asset_archetype';

	INSERT INTO sysinit_codetable (codetable_name, value_code, [language], sort_code, caption) VALUES
	('asset_archetype','APPLICATION','cs','130','Aplikace (instalovaná instance)'),
	('asset_archetype','BUILDING','cs','040','Budova (povinný prostor)'),
	('asset_archetype','CABLING','cs','080','Kabeláž a rozvody (v budově)'),
	('asset_archetype','CITY','cs','020','Město / obec (prostor)'),
	('asset_archetype','DATA','cs','110','Datové aktivum (informace / databáze)'),
	('asset_archetype','DISTRICT','cs','010','Okres / region (prostor)'),
	('asset_archetype','DOCUMENT','cs','090','Dokument (uložený v místnosti)'),
	('asset_archetype','HOST','cs','070','Hostitelský počítač / server (v místnosti)'),
	('asset_archetype','INTERFACE','cs','150','Služba typu Interface (internet/hlas/video)'),
	('asset_archetype','MEDIA','cs','100','Médium / nosič dat (uložený v místnosti)'),
	('asset_archetype','PERSONNEL','cs','160','Personál / klíčová role'),
	('asset_archetype','PHYSICAL','cs','060','Fyzické aktivum / hardware (v místnosti)'),
	('asset_archetype','ROOM','cs','050','Místnost / sál (prostor v budově)'),
	('asset_archetype','SERVICE','cs','140','Služba (interní / zákaznická)'),
	('asset_archetype','SITE','cs','030','Lokalita / areál (prostor)'),
	('asset_archetype','SOFTWARE','cs','120','Software (vyvíjený / pořizovaný)'),
	('asset_archetype','SUPPLIER','cs','170','Dodavatel / externí partner'),
	('asset_archetype','APPLICATION','en','130','Application (Installed Instance)'),
	('asset_archetype','BUILDING','en','040','Building (Mandatory Space)'),
	('asset_archetype','CABLING','en','080','Cabling & Wiring (in Building)'),
	('asset_archetype','CITY','en','020','City / Municipality (Space)'),
	('asset_archetype','DATA','en','110','Data Asset (Information / Database)'),
	('asset_archetype','DISTRICT','en','010','District / Region (Space)'),
	('asset_archetype','DOCUMENT','en','090','Document (Stored in Room)'),
	('asset_archetype','HOST','en','070','Host Computer / Server (in Room)'),
	('asset_archetype','INTERFACE','en','150','Interface Service (Internet/Voice/Video)'),
	('asset_archetype','MEDIA','en','100','Storage Media / Carrier (in Room)'),
	('asset_archetype','PERSONNEL','en','160','Personnel / Key Role'),
	('asset_archetype','PHYSICAL','en','060','Physical Asset / Hardware (in Room)'),
	('asset_archetype','ROOM','en','050','Room / Hall (Space in Building)'),
	('asset_archetype','SERVICE','en','140','Service (Internal / Customer-Facing)'),
	('asset_archetype','SITE','en','030','Site / Campus (Space)'),
	('asset_archetype','SOFTWARE','en','120','Software (Developed / Procured)'),
	('asset_archetype','SUPPLIER','en','170','Supplier / External Partner');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'asset';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		referenced_codetable, referenced_class_code
	) VALUES
	('asset','asset_archetype','cs','Archetyp aktiva (asset_archetype)','Archetyp aktiva (STI klasifikace)','Archetyp','Základní systémová kategorie aktiva určující jeho chování a umístění (SPACE, PHYSICAL, HOST, DATA, APPLICATION, SERVICE...).','asset_archetype',''),
	('asset','availability_score','cs','Skóre dostupnosti v % (availability_score)','Požadavek na dostupnost (0–100 %)','Dostupnost (%)','Výpočtové skóre dopadu výpadku nebo nedostupnosti služby či dat v procentech (0 až 100 %).','',''),
	('asset','confidentiality_score','cs','Skóre důvěrnosti v % (confidentiality_score)','Požadavek na důvěrnost (0–100 %)','Důvěrnost (%)','Výpočtové skóre dopadu prozrazení datového aktiva v procentech (0 až 100 %).','',''),
	('asset','inherent_risk_score','cs','Inherentní riziko v % (inherent_risk_score)','Inherentní riziko před opatřeními (0–100 %)','Inh. riziko (%)','Vypočtené skóre inherentního (výchozího) rizika před započtením protiopatření v procentech (0 až 100 %).','',''),
	('asset','integrity_score','cs','Skóre integrity v % (integrity_score)','Požadavek na integritu (0–100 %)','Integrita (%)','Výpočtové skóre dopadu nekonzistence, chybovosti nebo likvidace dat v procentech (0 až 100 %).','',''),
	('asset','inventory_number','cs','Inventární / sériové číslo (inventory_number)','Inventární / sériové číslo','Inv. číslo','Evidenční, inventární nebo sériové číslo fyzického aktiva, média či dokumentu.','',''),
	('asset','owner_user_uuid','cs','Vlastník / garant aktiva (owner_user_uuid)','Vlastník / garant aktiva (osoba)','Vlastník aktiva','Odkaz na uživatelský účet osoby odpovědné za dané aktivum nebo prostor.','','user_account'),
	('asset','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','','asset'),
	('asset','primary_asset_class','cs','Primární třída aktiva (primary_asset_class)','Primární koncová třída aktiva','Třída aktiva','Odkaz na hlavní koncovou třídu aktiv (is_leaf = 1), podle které se aktivum třídí a zařazuje.','','asset_class'),
	('asset','residual_risk_score','cs','Zbytkové riziko v % (residual_risk_score)','Zbytkové / reziduální riziko (0–100 %)','Rez. riziko (%)','Vypočtené výsledné zbytkové (reziduální) riziko po zohlednění protiopatření a spodního prahu v procentech (0 až 100 %).','',''),
	('asset','rpo_hours','cs','Recovery Point Objective v hodinách (rpo_hours)','RPO – max. ztráta dat (hodiny)','RPO (h)','Maximální přijatelný věk ztracených dat od poslední zálohy v hodinách.','',''),
	('asset','rto_hours','cs','Recovery Time Objective v hodinách (rto_hours)','RTO – max. doba obnovy (hodiny)','RTO (h)','Maximální přijatelná doba trvání výpadku aktiva nebo služby v hodinách.','','');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('asset','asset_archetype','en','Asset Archetype (asset_archetype)','Asset Archetype (STI Classification)','Archetype','Core system category of the asset determining its behavior and placement (SPACE, PHYSICAL, HOST, DATA, APPLICATION, SERVICE...).'),
	('asset','availability_score','en','Availability Score in % (availability_score)','Availability Requirement (0–100%)','Availability (%)','Calculation score of service or data outage impact in percent (0 to 100%).'),
	('asset','confidentiality_score','en','Confidentiality Score in % (confidentiality_score)','Confidentiality Requirement (0–100%)','Confidentiality (%)','Calculation score of data disclosure impact in percent (0 to 100%).'),
	('asset','inherent_risk_score','en','Inherent Risk in % (inherent_risk_score)','Inherent Risk Before Controls (0–100%)','Inh. Risk (%)','Calculated inherent (initial) risk score prior to applying countermeasures in percent (0 to 100%).'),
	('asset','integrity_score','en','Integrity Score in % (integrity_score)','Integrity Requirement (0–100%)','Integrity (%)','Calculation score of data inconsistency, corruption, or destruction impact in percent (0 to 100%).'),
	('asset','inventory_number','en','Inventory / Serial Number (inventory_number)','Inventory / Serial Number','Inv. No.','Inventory, asset tag, or serial number of a physical asset, storage medium, or document.'),
	('asset','owner_user_uuid','en','Asset Owner / Guarantor (owner_user_uuid)','Asset Owner / Guarantor (Person)','Asset Owner','Reference to the user account of the person responsible for the asset or space.'),
	('asset','parent_uuid','en','Parent Tree Node (parent_uuid)','Parent Folder / Item','Parent Node','Reference to the parent node in the tree hierarchy (empty means a top-level root item).'),
	('asset','primary_asset_class','en','Primary Asset Class (primary_asset_class)','Primary Leaf Asset Class','Asset Class','Reference to the main terminal asset class (is_leaf = 1) used to classify and sort the asset.'),
	('asset','residual_risk_score','en','Residual Risk in % (residual_risk_score)','Residual Risk After Controls (0–100%)','Res. Risk (%)','Calculated resulting residual risk score after accounting for countermeasures and minimum risk floor in percent (0 to 100%).'),
	('asset','rpo_hours','en','Recovery Point Objective in Hours (rpo_hours)','RPO – Max. Data Loss Window (Hours)','RPO (h)','Maximum acceptable age of lost data since the last valid backup in hours.'),
	('asset','rto_hours','en','Recovery Time Objective in Hours (rto_hours)','RTO – Max. Recovery Time (Hours)','RTO (h)','Maximum acceptable outage duration of the asset or service in hours.');
END
GO