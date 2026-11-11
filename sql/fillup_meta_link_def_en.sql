/* =============================================================================
 * Verze: 2026-11-11 22:00
 * Soubor: fillup_meta_link_def_en.sql
 * Účel:   Idempotentní nastavení výchozích anglických překladů (jazyk 'en',
 *         record_type = 'L') pro všechny primární, zpětné, vnitrotřídní
 *         i exkluzivní stromové vztahy v tabulce meta_link_def (object_owner = 0x00),
 *         seřazené abecedně podle link_code.
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
('app_requires_app','Requires another application to operate','Supports parent application','Reverse dependency relationship between installed applications (checked for acyclicity via f_resolve_link_diagram).','Select underlying applications required by this application.'),
('app_requires_data','Requires and processes data asset','Is used by application (propagates outages, errors, and breaches)','M:N link between an installed application and data assets. Unavailability, inconsistency/errors, and disclosure of data propagate to the application and dependent services.','Specify the data assets read or written by this application.'),
('app_requires_interface','Requires communication interface','Provides communication for application','Dependency of an application on an external or internal interface (internet, API, communication line).','Select interfaces required for the application to communicate.'),
('app_requires_personnel','Requires personnel (administration & operation)','Administers / operates application (source of human errors)','Dependency of an application on key personnel (administrators, owners). Propagates staff unavailability and human error risks.','Assign key roles or staff members responsible for operating the application.'),
('app_runs_on_host','Runs on host computer / server','Hosts installed application (propagates HW outages and errors)','Operational placement of an installed application on one or more host computers or servers. Server outage or HW fault directly affects the application.','Select one or more host computers (servers) on which the application runs.'),
('app_supports_app','Supports another application (propagates defects and outages)','Requires application to operate','Intra-class directed relationship between installed applications (with cycle detection).','Select dependent applications supported by this application.'),
('app_supports_service','Supports service (propagates outages and errors)','Requires application (is supported by)','Reverse relationship from an installed application to business services supported by it.','Overview of services dependent on this installed application.'),
('asset_additional_class','Belongs to secondary asset class','Contains asset (secondary classification)','Allows assigning an asset to additional leaf asset classes in the catalog besides its primary_asset_class.','Optional assignment of the asset to additional asset class catalog categories.'),
('asset_class_exposed_to_threat','Affects asset class (inherited down the tree)','Is exposed to threat','Reverse relationship from a catalog threat to asset classes exposed to it.','Asset classes threatened by this threat.'),
('asset_class_has_asset','Contains asset (secondary classification)','Belongs to secondary asset class','Reverse relationship from an asset class to secondarily assigned assets.','Assets secondarily assigned to this asset class.'),
('asset_class_uses_countermeasure','Applies to asset class (inherited down the tree)','Recommended countermeasure for asset class','Reverse relationship from a countermeasure to asset classes for which it is recommended.','Asset classes to which this countermeasure applies.'),
('asset_maintained_by_supplier','Is supplied / maintained by supplier','Supplies / maintains asset','Link from a general asset (HW, SW, utility, interface) to an external supplier or maintenance partner.','Select the supplier providing delivery, warranty, or maintenance for the asset.'),
('asset_managed_by_ou','Is managed by organizational unit (department)','Manages / is responsible for asset','Link from an asset (application, data, service, HW) to the organizational unit managing it (enables risk propagation to departments and HR).','Select the organizational unit responsible for managing this asset.'),
('building_contains_cabling','Contains cabling and wiring','Is installed in building','Reverse relationship from a building to cabling installed inside the building.','Overview of cabling installed in this building.'),
('building_contains_room','Contains room / hall','Is located in building','Reverse relationship from a building to rooms located inside it.','Rooms registered inside this building.'),
('building_in_site','Is located in site / campus','Contains building','Spatial placement of a building within a site (when sites are defined in the organization).','If you track sites or campuses, select the site where the building is located.'),
('cabling_connects_room','Connects room','Is connected by cabling','List of rooms in the building served by this power or data cabling.','Select rooms served by this cabling.'),
('cabling_in_building','Is installed in building','Contains cabling and wiring','Mandatory spatial placement of cabling into a specific building. Building damage propagates to the cabling.','Every cabling record must be assigned to exactly one building.'),
('cabling_serves_host','Connects / powers host computer','Uses cabling and wiring','Reverse relationship from cabling to connected host computers and servers.','Host computers using this cabling.'),
('child_asset','Is parent asset / space for (parent_uuid)','Has parent asset / space (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link in the asset table.','Child items in the primary asset and space tree.'),
('child_asset_class','Contains child asset class (parent_uuid)','Belongs under parent asset class (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link in the asset class catalog.','Child asset classes in the tree.'),
('child_countermeasure','Contains child countermeasure (parent_uuid)','Belongs under parent countermeasure group (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link in the countermeasure catalog.','Child countermeasures in the tree.'),
('child_hierarchy_item','Contains child hierarchy item (parent_uuid)','Belongs under parent hierarchy node (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link in hierarchy_item.','Child nodes of the secondary hierarchy.'),
('child_impact','Contains child impact (parent_uuid)','Belongs under parent impact area (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link in the impact catalog.','Child impact items in the tree.'),
('child_organization_unit','Governs child organizational unit (parent_uuid)','Reports to parent organizational unit (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link between organizational units.','Subordinate organizational units.'),
('child_scenario','Contains child scenario (parent_uuid)','Belongs under parent scenario group (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link in the scenario catalog.','Child risk scenarios in the tree.'),
('child_threat','Contains child threat (parent_uuid)','Belongs under parent threat group (parent_uuid)','Reverse direction of the exclusive parent_uuid tree link in the threat catalog.','Child threats in the tree.'),
('city_contains_site','Contains site / campus','Is located in city / municipality','Reverse relationship from a city to sites and campuses located in it.','Sites and campuses located in this city.'),
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
('data_used_by_app','Is used by application (propagates outages, errors, and breaches)','Requires and processes data asset','Reverse relationship from a data asset to installed applications reading or writing the data (propagates data errors to applications).','Applications processing this data asset.'),
('diagram_includes_link_def','Includes directed relationship (network edge)','Is part of network diagram (schema)','Assignment of a directed relationship from meta_link_def into a heterogeneous network diagram (link_diagram) for risk propagation path calculation.','Select directed relationships forming the edges of this network diagram.'),
('district_contains_city','Contains city / municipality','Is located in district / region','Reverse relationship from a district to cities and municipalities.','Cities and municipalities registered in this district.'),
('document_contains_data','Contains data asset','Is recorded in document','Reverse relationship from a document to data assets recorded in it.','Data assets recorded in this document.'),
('document_in_room','Is stored in room','Contains document','Mandatory spatial placement of a document in a specific room (archive, office).','Select the room where the document is permanently stored.'),
('host_in_room','Is located in room','Contains host computer / server','Mandatory spatial placement of a host computer / server in exactly one room (server room).','Every host computer must be placed in exactly one room.'),
('host_runs_app','Hosts installed application (propagates HW outages and errors)','Runs on host computer / server','Reverse relationship from a host computer to installed applications running on it.','Installed applications running on this server.'),
('host_stores_data','Stores data asset (propagates HW errors and outages)','Is stored on host computer / server','Reverse relationship from a host computer to data assets stored on it.','Data assets stored on this host computer.'),
('host_uses_cabling','Uses cabling and wiring','Connects / powers host computer','Dependency of a server on building data and power cabling.','Select cabling providing connectivity and power to this host computer.'),
('impact_caused_by_scenario','Is caused by risk scenario','Causes impact in area','Reverse relationship from an impact area to risk scenarios.','Risk scenarios causing impact in this area.'),
('impact_evaluates_data','Is an impact area for data asset','Is evaluated for impact in area','Reverse relationship from an impact area to evaluated data assets.','Data assets evaluated in this impact area.'),
('impact_evaluates_service','Evaluates service outage impact','Has outage / degradation evaluated in impact area','Reverse relationship from an impact area to services.','Services evaluated in this impact area.'),
('interface_provided_by_supplier','Is provided by supplier (service provider)','Provides Interface service (internet / voice / video)','Link from an external interface (internet connectivity, voice/video service, leased line) to its supplier.','Select the supplier (carrier / ISP) providing this interface.'),
('interface_supports_app','Provides communication for application','Requires communication interface','Reverse relationship from a communication interface to dependent applications.','Applications using this communication interface.'),
('interface_supports_service','Provides connectivity / interface for service','Requires interface (internet / voice / video / ext. service)','Reverse relationship from an Interface service to supported business services.','Services dependent on this communication interface.'),
('link_def_in_diagram','Is part of network diagram (schema)','Includes directed relationship (network edge)','Reverse relationship from a link definition to network diagrams using it.','Network diagrams containing this relationship.'),
('media_carries_data','Carries data asset (backup / archive)','Is stored / backed up on media','Reverse relationship from storage media to stored data assets.','Data assets stored or backed up on this medium.'),
('media_in_room','Is stored in room','Contains storage media','Mandatory spatial placement of storage media in a specific room or vault.','Select the room where the storage media is kept.'),
('ou_employs_personnel','Includes personnel / job roles','Is assigned to organizational unit','Reverse relationship from an organizational unit to assigned personnel.','Staff members and roles belonging to this department.'),
('ou_manages_asset','Manages / is responsible for asset','Is managed by organizational unit (department)','Reverse relationship from an organizational unit to managed assets.','Assets managed by this organizational unit.'),
('parent_asset','Has parent asset / space (parent_uuid)','Is parent asset / space for (parent_uuid)','Exclusive parent_uuid tree relationship in the asset table (at most 1 parent, automatically mirrored into link).','Parent node in the space or asset tree.'),
('parent_asset_class','Belongs under parent asset class (parent_uuid)','Contains child asset class (parent_uuid)','Exclusive parent_uuid tree relationship in the asset class catalog.','Parent folder in the asset class catalog.'),
('parent_countermeasure','Belongs under parent countermeasure group (parent_uuid)','Contains child countermeasure (parent_uuid)','Exclusive parent_uuid tree relationship in the countermeasure catalog.','Parent group in the countermeasure catalog.'),
('parent_hierarchy_item','Belongs under parent hierarchy node (parent_uuid)','Contains child hierarchy item (parent_uuid)','Exclusive parent_uuid tree relationship in secondary hierarchy items.','Parent node in the secondary hierarchy.'),
('parent_impact','Belongs under parent impact area (parent_uuid)','Contains child impact (parent_uuid)','Exclusive parent_uuid tree relationship in the impact catalog.','Parent area in the impact catalog.'),
('parent_organization_unit','Reports to parent organizational unit (parent_uuid)','Governs child organizational unit (parent_uuid)','Exclusive parent_uuid tree relationship between organizational units (enables risk propagation up the management hierarchy).','Parent department in the organizational structure.'),
('parent_scenario','Belongs under parent scenario group (parent_uuid)','Contains child scenario (parent_uuid)','Exclusive parent_uuid tree relationship in the risk scenario catalog.','Parent group in the scenario catalog.'),
('parent_threat','Belongs under parent threat group (parent_uuid)','Contains child threat (parent_uuid)','Exclusive parent_uuid tree relationship in the threat catalog.','Parent group in the threat catalog.'),
('personnel_in_ou','Is assigned to organizational unit (department)','Includes personnel / job roles','Assignment of key personnel or job role to an organizational unit (e.g., IT department, HR / training department).','Select the organizational unit to which this person or role belongs.'),
('personnel_operates_app','Administers / operates application (source of human errors)','Requires personnel (administration & operation)','Reverse relationship from personnel to applications they administer or operate.','Applications dependent on this role or person.'),
('personnel_operates_cm','Operates countermeasure','Requires personnel for implementation / operation','Reverse relationship from personnel to countermeasures they operate.','Countermeasures requiring this role or person.'),
('personnel_supports_service','Operates and delivers service','Requires personnel for service delivery','Reverse relationship from personnel to supported services.','Services dependent on this role or person.'),
('physical_in_room','Is located in room','Contains physical asset','Mandatory spatial placement of every physical asset in exactly one room.','Every physical asset must be placed in exactly one room.'),
('physical_stores_data','Contains data asset','Is stored on physical device','Reverse relationship from a physical device to stored data assets.','Data assets stored on this device.'),
('room_connected_by_cabling','Is connected by cabling','Connects room','Reverse relationship from a room to cabling serving the room.','Cabling and wiring connecting this room.'),
('room_contains_document','Contains document','Is stored in room','Reverse relationship from a room to documents stored in it.','Documents stored in this room.'),
('room_contains_host','Contains host computer / server','Is located in room','Reverse relationship from a room (server room) to servers located in it.','Host computers and servers located in this room.'),
('room_contains_media','Contains storage media','Is stored in room','Reverse relationship from a room to storage media kept in it.','Storage media kept in this room.'),
('room_contains_physical','Contains physical asset','Is located in room','Reverse relationship from a room to physical assets and utilities located in it.','Physical assets located in this room.'),
('room_in_building','Is located in building','Contains room','Mandatory spatial assignment of a room to a building. Every room must belong to exactly one building.','Select the building in which this room is located.'),
('scenario_causes_impact','Causes impact in area','Is caused by risk scenario','Specifies which impact areas (financial, reputation, general hazard, criminal liability, management disruption, legal breach) are triggered by the scenario.','Assign impact areas threatened by this risk scenario.'),
('scenario_mitigated_by_cm','Reduces scenario risk (reduction_factor / risk_factor)','Is mitigated by countermeasure','Reverse relationship from a countermeasure to risk scenarios mitigated by it.','Risk scenarios mitigated by this countermeasure.'),
('service_evaluated_by_impact','Has outage / degradation evaluated in impact area','Evaluates service outage impact','Evaluation of service outage or degradation impacts across impact areas (financial, reputation, general hazard, criminal liability, management disruption, legal breach).','Specify impact areas and severity levels for an outage or degradation of this service.'),
('service_requires_app','Requires application (is supported by)','Supports service (propagates outages and errors)','Core M:N link between a service and supporting applications. Application outages as well as data errors/breaches propagate to the service.','Select installed applications required to deliver this service.'),
('service_requires_interface','Requires interface (internet / voice / video / ext. service)','Provides connectivity / interface for service','Dependency of a service on a communication interface or another previously defined service (internet, voice, or video connection).','Select Interface services required for the operation of this service.'),
('service_requires_personnel','Requires personnel for service delivery','Operates and delivers service','Dependency of a service on key staff members and roles.','Assign personnel required to deliver this service.'),
('service_requires_service','Requires underlying (internal) service','Supports parent service (propagates outages)','Intra-class directed relationship between internal support services and customer-facing business services (with cycle detection).','Select other internal services on which this service depends.'),
('service_supports_service','Supports parent service (propagates outages)','Requires underlying (internal) service','Reverse intra-class relationship from a supporting service to parent services.','Parent services dependent on this service.'),
('site_contains_building','Contains building','Is located in site / campus','Reverse relationship from a site (campus) to buildings located within it.','Buildings registered in this site.'),
('site_in_city','Is located in city / municipality','Contains site / campus','Spatial placement of a site within a city (when cities are defined in the organization).','If you track cities, select the city where the site is located.'),
('supplier_maintains_asset','Supplies / maintains asset','Is supplied / maintained by supplier','Reverse relationship from a supplier to supplied or maintained assets.','Assets supplied or maintained by this supplier.'),
('supplier_provides_interface','Provides Interface service (internet / voice / video)','Is provided by supplier (service provider)','Reverse relationship from a supplier to communication interfaces provided by them.','Interface services provided by this supplier.'),
('sw_deployed_as_app','Is deployed as installed application (propagates SW defects)','Is an installation of software','Reverse relationship from a software product to its installed application instances.','Installed application instances of this software.'),
('threat_applies_to_asset_class','Is exposed to threat','Affects asset class (inherited down the tree)','Catalog link specifying which threats affect a given asset class and are automatically inherited by child classes.','Assign threats relevant to this asset class.'),
('threat_mitigated_by_cm','Acts against threat','Is suppressed by countermeasure','Reverse relationship from a countermeasure to catalog threats suppressed by it.','Threats suppressed by this countermeasure.');

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
UPDATE l
SET l.from_class = a.from_class,
	l.to_class = a.to_class,
	l.reverse_link_def = a.reverse_link_def,
	l.direction_type = a.direction_type,
	l.is_exclusive_parent = a.is_exclusive_parent,
	l.caption_forward = s.caption_forward,
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
	SELECT l.reverse_link_def, l.direction_type, l.is_exclusive_parent, l.caption_forward, l.caption_backward, l.description, l.helptext
	EXCEPT
	SELECT a.reverse_link_def, a.direction_type, a.is_exclusive_parent, s.caption_forward, s.caption_backward, s.description, s.helptext
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
INSERT INTO meta_link_def (
	uuid, object_owner, original, record_type, approval_status, [language],
	link_code, from_class, to_class, reverse_link_def, direction_type, is_exclusive_parent,
	caption_forward, caption_backward, description, helptext,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.link_code, a.from_class, a.to_class, a.reverse_link_def, a.direction_type, a.is_exclusive_parent,
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