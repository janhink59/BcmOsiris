/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: fillup_meta_link_def_en.sql
 * Účel:   Idempotentní nastavení výchozích anglických překladů (jazyk 'en',
 *         record_type = 'L') pro systémové definice typů vazeb v tabulce
 *         meta_link_def (object_owner = 0x00), seřazené podle link_code.
 * Vazby:  - Navazuje na fillup_meta_link_def.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @links_en TABLE (
	link_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption_forward varchar(200) NOT NULL,
	caption_backward varchar(200) NOT NULL,
	description varchar(max) NOT NULL,
	helptext varchar(max) NOT NULL
);

INSERT INTO @links_en (link_code, caption_forward, caption_backward, description, helptext) VALUES
('app_instance_of_sw','Is an installation of software (inherits SW defects)','Is deployed as installed application','Link between an installed application and a developed or procured software product. Propagates software bugs and vulnerabilities to the application.','Select the software products that make up this installed application.'),
('app_requires_data','Requires and processes data asset','Is used by application (propagates outages, errors, and breaches)','M:N link between an installed application and data assets. Unavailability, inconsistency/errors, and disclosure of data propagate to the application and dependent services.','Specify the data assets read or written by this application.'),
('app_requires_interface','Requires communication interface','Provides communication for application','Dependency of an application on an external or internal interface (internet, API, communication line).','Select interfaces required for the application to communicate.'),
('app_requires_personnel','Requires personnel (administration & operation)','Administers / operates application (source of human errors)','Dependency of an application on key personnel (administrators, owners). Propagates staff unavailability and human error risks.','Assign key roles or staff members responsible for operating the application.'),
('app_runs_on_host','Runs on host computer / server','Hosts installed application (propagates HW outages and errors)','Operational placement of an installed application on a host computer or server. Server outage or HW fault directly affects the application.','Select one or more host computers (servers) on which the application runs.'),
('asset_additional_class','Belongs to secondary asset class','Contains asset (secondary classification)','Allows assigning an asset to additional leaf asset classes in the catalog besides its primary_asset_class.','Optional assignment of the asset to additional asset class catalog categories.'),
('asset_maintained_by_supplier','Is supplied / maintained by supplier','Supplies / maintains asset','Link from a general asset (HW, SW, utility) to an external supplier or maintenance partner.','Select the supplier providing delivery, warranty, or maintenance for the asset.'),
('building_in_site','Is located in site / campus','Contains building','Spatial placement of a building within a site (when sites are defined in the organization).','If you track sites or campuses, select the site where the building is located.'),
('cabling_connects_room','Connects room','Is connected by cabling','List of rooms in the building served by this power or data cabling.','Select rooms served by this cabling.'),
('cabling_in_building','Is installed in building','Contains cabling and wiring','Mandatory spatial placement of cabling into a specific building. Building damage propagates to the cabling.','Every cabling record must be assigned to exactly one building.'),
('city_in_district','Is located in district / region','Contains city / municipality','Spatial placement of a city within a district (when districts are defined in the organization).','If you track districts, select the parent district.'),
('countermeasure_applies_to_asset_class','Recommended countermeasure for asset class','Applies to asset class (inherited down the tree)','Catalog link specifying which countermeasures are relevant for a given asset class and its child classes.','Assign countermeasures to be offered for assets in this class.'),
('countermeasure_mitigates_scenario','Is mitigated by countermeasure','Reduces scenario risk (reduction_factor / risk_factor)','Methodological link between a risk scenario and countermeasures that reduce its residual risk or set a minimum risk floor when unimplemented.','Select countermeasures mitigating this risk scenario.'),
('countermeasure_mitigates_threat','Is suppressed by countermeasure','Acts against threat','Methodological link between a catalog threat and preventive or detective countermeasures.','Select countermeasures that reduce the impact or likelihood of this threat.'),
('countermeasure_requires_personnel','Requires personnel for implementation / operation','Operates countermeasure','Human resources and roles required for a security control (e.g., guards, SOC monitoring, inspections) to function effectively.','Specify personnel required to operate this countermeasure.'),
('data_evaluated_by_impact','Is evaluated for impact in area (breach / corruption / loss)','Is an impact area for data asset','Evaluation of impacts of data disclosure, inconsistency, or errors (from minor errors to loss since last backup or complete destruction) across impact areas.','Assess the impacts of compromise or loss of this data asset.'),
('data_in_document','Is recorded in document','Contains data asset','Storage of a data asset in a paper or controlled electronic document.','Select documents containing this data.'),
('data_on_host','Is stored on host computer / server','Stores data asset (propagates HW errors and outages)','Physical or virtual storage of a database or files on a host computer. Host failure or compromise directly threatens the data.','Select host computers (servers) storing this data.'),
('data_on_media','Is stored / backed up on media','Carries data asset (backup / archive)','Storage or backup of a data asset on portable or vault storage media.','Select storage media carrying copies or backups of this data.'),
('data_on_physical','Is stored on physical device','Contains data asset','Storage of data on a specialized HW device (SAN/NAS array, workstation, appliance).','Select physical devices where the data resides.'),
('document_in_room','Is stored in room','Contains document','Mandatory spatial placement of a document in a specific room (archive, office).','Select the room where the document is permanently stored.'),
('host_in_room','Is located in room','Contains host computer / server','Mandatory spatial placement of a host computer / server in exactly one room (server room).','Every host computer must be placed in exactly one room.'),
('host_uses_cabling','Uses cabling and wiring','Connects / powers host computer','Dependency of a server on building data and power cabling.','Select cabling providing connectivity and power to this host computer.'),
('interface_provided_by_supplier','Is provided by supplier (service provider)','Provides Interface service (internet / voice / video)','Link from an external interface (internet connectivity, voice/video service, leased line) to its supplier.','Select the supplier (carrier / ISP) providing this interface.'),
('media_in_room','Is stored in room','Contains storage media','Mandatory spatial placement of storage media in a specific room or vault.','Select the room where the storage media is kept.'),
('physical_in_room','Is located in room','Contains physical asset','Mandatory spatial placement of every physical asset in exactly one room.','Every physical asset must be placed in exactly one room.'),
('room_in_building','Is located in building','Contains room','Mandatory spatial assignment of a room to a building. Every room must belong to exactly one building.','Select the building in which this room is located.'),
('scenario_causes_impact','Causes impact in area','Is caused by risk scenario','Specifies which impact areas (financial, reputation, general hazard, criminal liability, management disruption, legal breach) are triggered by the scenario.','Assign impact areas threatened by this risk scenario.'),
('service_evaluated_by_impact','Has outage / degradation evaluated in impact area','Evaluates service outage impact','Evaluation of service outage or degradation impacts across impact areas (financial, reputation, general hazard, criminal liability, management disruption, legal breach).','Specify impact areas and severity levels for an outage or degradation of this service.'),
('service_requires_app','Requires application (is supported by)','Supports service (propagates outages and errors)','Core M:N link between a service and supporting applications. Application outages as well as data errors/breaches propagate to the service.','Select installed applications required to deliver this service.'),
('service_requires_interface','Requires interface (internet / voice / video / ext. service)','Provides connectivity / interface for service','Dependency of a service on a communication interface or another previously defined service (internet, voice, or video connection).','Select Interface services required for the operation of this service.'),
('service_requires_personnel','Requires personnel for service delivery','Operates and delivers service','Dependency of a service on key staff members and roles.','Assign personnel required to deliver this service.'),
('service_requires_service','Requires underlying (internal) service','Supports parent service (propagates outages)','Chaining of dependencies between internal support services and customer-facing business services.','Select other internal services on which this service depends.'),
('site_in_city','Is located in city / municipality','Contains site / campus','Spatial placement of a site within a city (when cities are defined in the organization).','If you track cities, select the city where the site is located.'),
('threat_applies_to_asset_class','Is exposed to threat','Affects asset class (inherited down the tree)','Catalog link specifying which threats affect a given asset class and are automatically inherited by child classes.','Assign threats relevant to this asset class.');

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
UPDATE l
SET l.caption_forward = s.caption_forward,
	l.caption_backward = s.caption_backward,
	l.description = s.description,
	l.helptext = s.helptext,
	l.date_modified = GETDATE()
FROM meta_link_def l
JOIN meta_link_def a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
JOIN @links_en s ON LOWER(s.link_code) = LOWER(a.link_code)
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND l.who_modified = @sys_owner
  AND EXISTS (
	SELECT l.caption_forward, l.caption_backward, l.description, l.helptext
	EXCEPT
	SELECT s.caption_forward, s.caption_backward, s.description, s.helptext
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
INSERT INTO meta_link_def (
	uuid, object_owner, original, record_type, approval_status, [language],
	link_code, from_class, to_class,
	caption_forward, caption_backward, description, helptext,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.link_code, a.from_class, a.to_class,
	s.caption_forward, s.caption_backward, s.description, s.helptext,
	a.is_multiple, a.is_mandatory, a.leaf_only, a.link_weight_enabled,
	a.is_final, a.is_protected
FROM meta_link_def a
JOIN @links_en s ON LOWER(s.link_code) = LOWER(a.link_code)
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_link_def l
	WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'en'
  );
GO