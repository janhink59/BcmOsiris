/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: fillup_asset_class_en.sql
 * Účel:   Idempotentní nastavení výchozích anglických překladů (jazyk 'en',
 *         record_type = 'L') pro systémový katalog tříd aktiv v tabulce
 *         asset_class (object_owner = 0x00), seřazené podle builtin_code.
 * Vazby:  - Navazuje na fillup_asset_class.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @ac_en TABLE (
	builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption varchar(200) NOT NULL,
	shortname varchar(40) NOT NULL,
	description_text varchar(max) NOT NULL
);

INSERT INTO @ac_en (builtin_code, caption, shortname, description_text) VALUES
('ac_application','Applications (Installed)','APP','Specific installed application instances running on host computers and requiring data assets and personnel.'),
('ac_building','Buildings','BLD','Buildings and facilities. At least one building (even fictitious) must be defined in the organization to house rooms and cabling.'),
('ac_cabling','Cabling & Wiring','CAB','Structured data cabling, fiber optic routes, and power distribution wiring located in a building and connecting rooms.'),
('ac_city','Cities & Municipalities','CITY','Cities and municipalities where organization sites and buildings are located (optional spatial hierarchy level).'),
('ac_data','Data Assets (Information & Databases)','DATA','Data assets, databases, and logical information sets stored on host computers, media, or documents.'),
('ac_district','Districts & Regions','DIST','Geographical districts and regions representing the highest optional level of spatial asset organization.'),
('ac_document','Documents','DOC','Controlled paper and electronic documents, contracts, and operational documentation stored in rooms and carrying information.'),
('ac_grp_info','Information, Data, Documents & Media','INFO','Folder of data assets, documents, and portable or backup storage media.'),
('ac_grp_people_ext','Personnel & External Suppliers','PPL','Folder of human resources, key roles, and external suppliers or service partners.'),
('ac_grp_services','Services & Communication Interfaces','SRV','Folder of primary business services, internal support services, and external/internal interfaces.'),
('ac_grp_space','Spaces & Locations','LOC','Hierarchical folder of spatial asset placement (District -> City -> Site -> Building -> Room).'),
('ac_grp_sw_apps','Software & Installed Applications','SW','Folder of developed or procured software packages and specific installed applications.'),
('ac_grp_tech','Technical & Physical Assets (HW & Networks)','TECH','Folder of tangible equipment, host computers, servers, network devices, building utilities, and cabling.'),
('ac_host','Host Computers & Servers','HOST','Special subclass of physical assets: physical and virtual servers and host computers located in rooms that run applications and store data.'),
('ac_interface','Interface Services (Internet, Voice, Video)','IFC','External or internal connectivity and communication services (internet, voice, video links, APIs) required by other services.'),
('ac_media','Media & Data Carriers','MED','Portable and backup storage media (backup tapes, external drives, flash drives, optical media) stored in rooms or vaults.'),
('ac_personnel','Personnel & Key Roles','PERS','Internal and external staff, administrators, operators, and key job roles required to operate applications, services, and countermeasures.'),
('ac_physical','Physical Assets & Hardware','HW','General tangible and technical assets, network devices, workstations, machinery, and building utilities (UPS, HVAC, fire/intrusion alarms) located in rooms.'),
('ac_room','Rooms & Halls','ROOM','Specific rooms, server rooms, archives, and workspaces inside buildings. Physical assets, host computers, documents, and media must be placed in rooms.'),
('ac_service','Services (Internal & Customer-Facing)','SVC','Core business and internal support services supported by applications, interfaces, and personnel, evaluated for outage impacts across impact areas.'),
('ac_site','Sites & Campuses','SITE','Sites, campuses, and branches grouping multiple buildings within a city or municipality (optional spatial hierarchy level).'),
('ac_software','Software (Developed & Procured)','SWP','Source software products, internally developed software, and installation packages that may be a source of software defects for installed applications.'),
('ac_supplier','Suppliers & External Partners','SUP','External providers of communication interfaces, cloud services, hardware, software, and maintenance support.');

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
UPDATE l
SET l.caption = s.caption,
	l.shortname = s.shortname,
	l.description_text = s.description_text,
	l.date_modified = GETDATE()
FROM asset_class l
JOIN asset_class a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
JOIN @ac_en s ON s.builtin_code = a.builtin_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND l.who_modified = @sys_owner
  AND EXISTS (
	SELECT l.caption, l.shortname, l.description_text
	EXCEPT
	SELECT s.caption, s.shortname, s.description_text
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
INSERT INTO asset_class (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, is_leaf, instance_class_name,
	caption, shortname, description_text, svg_icon, is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.instance_class_name,
	s.caption, s.shortname, s.description_text, a.svg_icon, a.is_final, a.is_protected
FROM asset_class a
JOIN @ac_en s ON s.builtin_code = a.builtin_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM asset_class l
	WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'en'
  );
GO