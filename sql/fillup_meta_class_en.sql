/* =============================================================================
 * Verze: 2026-11-09 14:45
 * Soubor: fillup_meta_class_en.sql
 * Účel:   Hromadné idempotentní nastavení výchozích anglických překladů (jazyk 'en',
 *         record_type = 'L') pro systémové logické třídy v tabulce meta_class
 *         (object_owner = 0x00), seřazené abecedně podle class_name.
 * Vazby:  - Navazuje na fillup_meta_class.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @cls_en TABLE (
	class_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption varchar(200) NOT NULL,
	caption_plural varchar(200) NOT NULL,
	description varchar(max) NOT NULL,
	helptext varchar(max) NOT NULL
);

INSERT INTO @cls_en (class_name, caption, caption_plural, description, helptext) VALUES
('activation_token','One-Time Security Token','One-Time Security Tokens','Registry of one-time cryptographic tokens for password reset, account activation, and MFA.','Technical table for verifying time-limited security links.'),
('asset','Asset','Asset Inventory','Inventory of specific primary and supporting organization assets and spaces assigned to leaf asset classes.','Main catalog of organization assets subject to risk analysis and assessment.'),
('asset_application','Application (Installed)','Applications (Installed)','Installed application instances running on host computers and requiring data assets and personnel.','Inventory of operational applications. Inherits impacts from data assets, HW hosts, and SW packages and propagates them to supported services.'),
('asset_building','Building','Buildings','Organization buildings and facilities. At least one building (even fictitious) must be defined in the organization.','Rooms and cabling are mandatorily placed inside buildings. A building may be placed in a site.'),
('asset_cabling','Cabling & Wiring','Cabling & Wiring','Structured data cabling, fiber optic routes, and power wiring located in a building.','Cabling must be placed in a building and optionally connects rooms and host computers.'),
('asset_city','City / Municipality','Cities & Municipalities','Cities and municipalities where organization sites and buildings are located.','Optional spatial hierarchy level (City is in a District when districts are defined).'),
('asset_class','Asset Class','Asset Classes','Hierarchical catalog of asset classes and categories defining asset structure and threat inheritance.','Folders (is_leaf = 0) group classes and pass down links; leaf classes (is_leaf = 1) hold individual assets.'),
('asset_data','Data Asset','Data Assets','Data assets, databases, and logical information sets stored on host computers, media, or documents.','Evaluated for impacts of disclosure, inconsistency/errors (from minor errors to loss since last backup or complete destruction), and unavailability.'),
('asset_district','District / Region','Districts & Regions','Geographical districts and regions representing the highest optional level of spatial asset organization.','Top optional level of the spatial hierarchy.'),
('asset_document','Document','Documents','Controlled paper and electronic documents stored in rooms and containing data assets.','Every document must be placed in a specific room.'),
('asset_host','Host Computer / Server','Host Computers & Servers','Special subclass of physical assets: physical and virtual servers and host computers located in rooms.','Host computers run installed applications and store data assets.'),
('asset_interface','Interface Service','Interface Services (Internet, Voice, Video)','External or internal connectivity and communication services (internet, voice or video links, APIs) required by services and applications.','Interface services are typically provided by an external supplier or a previously defined internal service.'),
('asset_media','Media / Data Carrier','Media & Data Carriers','Portable and backup storage media (tapes, drives, vault media) stored in rooms and carrying data assets.','Every storage medium must be placed in a room.'),
('asset_personnel','Personnel / Key Role','Personnel & Key Roles','Key staff members, administrators, and job roles required to operate applications, services, and countermeasures.','Personnel can be a source of human errors as well as key person unavailability risk.'),
('asset_physical','Physical Asset (HW / Device)','Physical Assets & Hardware','Tangible and technical assets, network devices, workstations, and building utilities located in rooms.','Every physical asset must be placed in exactly one room and may be a source of HW faults and outages.'),
('asset_room','Room','Rooms & Halls','Specific rooms, server rooms, archives, and workspaces inside buildings.','Every room must belong to exactly one building. Physical assets, host computers, documents, and media are placed in rooms.'),
('asset_service','Service','Services (Internal & Customer-Facing)','Core business and internal support services supported by applications, interfaces, and personnel.','Services are evaluated for outage and degradation impacts across impact areas (financial, reputation, general hazard, criminal, management, legal).'),
('asset_site','Site / Campus','Sites & Campuses','Sites, campuses, and branches grouping buildings within a city or municipality.','Optional spatial hierarchy level (Site is in a City when cities are defined).'),
('asset_software','Software (Developed / Procured)','Software (Developed & Procured)','Developed or procured software products and packages deployed as installed applications.','Software is a source of software defects and vulnerabilities propagated to installed applications.'),
('asset_supplier','Supplier / Partner','Suppliers & External Partners','External providers of Interface services (internet, voice, video), hardware, software, and maintenance support.','Registry of third parties in the supply chain.'),
('audit_login_session','Login & Activity Record','User Login & Activity History','Forensic audit log of user logins, assumed roles, IP addresses, and session durations.','Used to monitor user activity and provide an immutable audit trail for record creation and modification.'),
('auth_tokens','Persistent Login Token','Persistent Login Tokens','Secure storage of long-lived authentication tokens (Remember Me) using the Selector & Validator pattern.','Technical table managing active persistent browser sessions.'),
('countermeasure','Countermeasure','Countermeasure Catalog','Hierarchical catalog of security, technical, and organizational countermeasures with reduction and risk factors.','Contains controls that reduce scenario residual risk and define minimum risk thresholds when unimplemented.'),
('countermeasure_implementation','Countermeasure Implementation','Countermeasure Implementations','Registry of the implementation state of security countermeasures on specific assets and spaces.','Tracks actual implementation status of controls on assets and its effect on residual risk reduction.'),
('countermeasure_state','Countermeasure State','Countermeasure States','Codetable of countermeasure implementation states determining reduction and risk factor weights.','Defines implementation states (e.g., Proposed, In Progress, Implemented, N/A) and their percentage weights.'),
('dbsession','Database Process Session','Database Process Sessions','Context of the currently executing database request bound to @@SPID in SQL Server.','Passes user identity, organization, language, and active role to stored procedures and functions.'),
('f_integer_list','Integer List Split Function','Split Integer List','Table-valued function splitting a comma-separated list of integers into bigint rows.','Helper parsing function of HinkMSSQLLibrary.'),
('f_language_list','Language Fallback List Function','Languages with Fallback Order','Table-valued function returning supported languages ordered by the active fallback chain.','Determines translation lookup order for the current session.'),
('f_resolve_hierarchy','Tree Hierarchy Resolution Function','Tree Hierarchy Resolution','Table-valued function computing tree ordering, nesting depth, and zero-padded sort paths.','Performs top-down tree traversal and orphan detection.'),
('f_string_list','String List Split Function','Split String List','Table-valued function splitting a comma-separated string into trimmed varchar rows.','Helper parsing function of HinkMSSQLLibrary.'),
('f_syscolumns','Table Columns Function','Columns of Specified Table','Table-valued function returning column metadata for a permanent or temporary (#temp) table.','Used for dynamic SQL generation and data exports.'),
('f_uuid_list','UUID List Split Function','Split UUID List','Table-valued function splitting a comma-separated list of GUIDs into uniqueidentifier rows.','Helper parsing function of HinkMSSQLLibrary.'),
('hierarchy','Secondary Hierarchy / Tag Set','Secondary Hierarchies & Tags','Registry of custom classification trees, enumerated codetables, and tag sets.','Each leaf entry (is_leaf = 1) represents a standalone classification codetable or tag tree.'),
('hierarchy_item','Secondary Hierarchy Item','Secondary Hierarchy Items','Nodes and leaf items of individual secondary hierarchies, classification codetables, and tag sets.','Tree list of values belonging to the selected secondary hierarchy or tag set.'),
('impact','Impact','Impact Catalog','Hierarchical catalog of impact types and areas for evaluating risk scenario consequences, service outages, and data compromises.','Combines impact areas (financial, reputation, general hazard, criminal liability, management disruption, legal breach).'),
('language','Application Language','Supported Languages','Codetable of supported application languages including fallback order and guarantee translator organization.','Defines available language mutations for UI and data.'),
('licence_level','Licence Level','Licence Levels','Static codetable of system licence levels (Demo, Standard, Expert, Custom, Enterprise, Developer).','Determines the scope of available features and permissions for a licensed organization.'),
('link','Object Link','Object Links & Dependencies','Universal table of user-defined and hierarchically inherited M:N links between entity records.','Stores direct links (ancestor_link = 0x00) as well as links automatically materialized down the hierarchy tree.'),
('meta_class','Logical Class (Object)','Logical Classes (Objects)','Definition of logical system entities over physical tables supporting Single Table Inheritance (STI) and trash retention.','Allows customizing class captions, trash retention days, and default SVG icons.'),
('meta_codetable','System Codetable Item','System Codetables','Universal storage of fixed system and methodological enumerated codetables for dropdown selects.','Contains items of fixed enumerated codetables referenced by metadata columns.'),
('meta_column','Metadata Column','Metadata Columns','Definition of properties, labels, form controls, and relations for columns of logical classes.','Allows customizing form field labels, list headers, tooltips, and display order.'),
('meta_link_def','Link Type Definition','Link Type Definitions','Catalog of allowed M:N relationship types between logical classes in the link table.','Defines which classes can be linked, whether the relation is mandatory, multiple, or restricted to leaf nodes.'),
('meta_menu','Menu Item (Navigation)','Menu Items (Navigation)','Tree structure of the main application navigation and dashboards with role-based access control.','Defines menu hierarchy, target pages, SVG icons, and required access roles.'),
('meta_object','System Object','System Objects','Registry of physical tables, views, functions, application pages, and UI classes.','Defines physical storage objects for logical classes and role-based access control for application pages.'),
('meta_original_keys','Deterministic Original Key','Deterministic Original Keys','Registry of key columns used to compute the deterministic original UUID of records.','Technical table defining MD5 hash key components for trgo_ triggers.'),
('meta_phrase','Text Phrase','Text Phrases & Translations','Catalog of localizable UI phrases, button labels, messages, and templates supporting variables.','Used to translate the user interface, buttons, and system messages into supported languages.'),
('organization','Organization','Organizations','Master registry of organizations (tenants) including billing, regional, and CRMM calculation parameters.','Manage organization identification, currency/date formatting, and risk assessment score limits.'),
('organization_licence','Organization Licence','Organization Licences','Registry of organization licences, licence levels, activation states, and initial administrator accounts.','Used to create and activate new organizations, assign licence levels (Demo to Developer), or disable login.'),
('organization_unit','Organizational Unit','Organizational Units','Directory of internal organizational units and departments within an organization.','Registry of the tenant organizational structure.'),
('request_message','Request Processing Message','Request Processing Messages','Temporary queue of status, warning, and error messages generated during SQL procedure execution.','Messages bound to @@SPID for displaying operation results to the user.'),
('request_variable','Request Variable','Request Variables','Temporary storage of return variables shared between stored procedures within the same @@SPID.','Technical table for passing values inside a database session.'),
('rowgenerator','Row Generator','Row Generator (0..1024)','Helper numeric table containing sequence 0 to 1024 for set-based operations.','System table of HinkMSSQLLibrary.'),
('scale','Assessment Scale','Assessment Scales','Definitions of assessment scales for threats, vulnerabilities, impacts, and resulting risks in CRMM.','Allows defining primary input scales (priority 0) and secondary conversion scales for reporting.'),
('scale_value','Assessment Scale Level','Assessment Scale Levels','Individual levels of assessment scales with lower threshold and calculation score in the 0 to 100% range.','Levels are sorted ascending by lower threshold (threshold_value) and must form a strictly monotonic sequence.'),
('scenario','Risk Scenario','Risk Scenarios','Hierarchical catalog of risk scenarios (events) linking a threat, target asset class, and minimum residual risk.','Defines assessable risk events and the minimum threshold below which residual risk cannot drop.'),
('scenario_assessment','Risk Scenario Assessment','Risk Scenario Assessments','Evaluation of threat level, vulnerability, impact, and resulting risk of scenarios on specific assets.','Records inherent and residual risk of individual scenarios across organization assets.'),
('service_logbook','Service Logbook Entry','Service Logbook','Chronological log of executed database upgrades (changes_YYYY.sql), metadata imports, and trash cleanup.','Used to audit service operations and database schema versions.'),
('session_import_column','CSV Import Column','CSV Import Columns','List of column names for individual tables loaded from an uploaded CSV/TSV file.','Temporary staging storage of column structure in Phase 1.'),
('session_import_data','CSV Import Cell Value','CSV Import Cell Data','Non-empty cell values loaded from an uploaded CSV/TSV file prior to Phase 2 database import.','Temporary session-bound staging storage of imported cell values.'),
('session_import_parameter','CSV Import Parameter','CSV Import Parameters','Staging table of header and control parameters loaded from a CSV/TSV package in Phase 1 of import.','Temporary session-bound staging storage of package parameters.'),
('session_import_table','CSV Import Table','CSV Import Tables','List of data blocks (tables) and row counts loaded from an uploaded CSV/TSV file.','Temporary staging storage of imported tables in Phase 1.'),
('sys_global_columns','Global Column Dictionary','Global Column Definitions','Central dictionary of default properties and translations for database columns inherited by class columns.','Class columns inherit their default labels, widths, and behavior from this global dictionary.'),
('system_constant','System Constants','System Constants','Global technical configuration of the database, schema version, SMTP mail server, and backups.','Singleton table holding technical parameters of the system instance.'),
('threat','Threat','Threat Catalog','Hierarchical catalog of threats with optional default threat score assessment.','Registry of physical, technical, cyber, and organizational threats affecting assets.'),
('user_account','User Account','User Accounts','Global registry of user identities, login credentials, contact details, and system roles.','Contains personal and authentication data valid across all organizations.'),
('user_organization_access','User Organization Access','Organization Users & Access','Relational registry of user permissions, organizational assignment, and working settings within a specific tenant.','Controls organization membership, OrgAdmin role, translation rights, department, job title, and working date.'),
('v_syscolumns','System Database Columns View','System Database Columns View','Catalog view of columns across all tables, views, and functions including data types and constraints.','System catalog view of HinkMSSQLLibrary.'),
('v_sysindexcolumns','System Index Columns View','System Index Columns View','Catalog view of all indexes and their key and included columns in the database.','System catalog view of HinkMSSQLLibrary.'),
('v_sysprimarykeys','System Primary Keys View','System Primary Keys View','Catalog view of columns participating in primary keys of database tables.','System catalog view of HinkMSSQLLibrary.'),
('v_user_organization_access','User Organization Access View','User Organization Access View','Extended view joining user access records with organizations, licence levels, and account status.','System view used during login and context switching.'),
('wwwsession','Web User Session','Active Web Sessions','Shared table of active browser sessions (session_id) holding organization and role context.','Maintains logged-in user state across HTTP requests.');

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
UPDATE l
SET l.caption = s.caption,
	l.caption_plural = s.caption_plural,
	l.description = s.description,
	l.helptext = s.helptext,
	l.who_modified = @sys_owner,
	l.date_modified = GETDATE()
FROM meta_class l
JOIN meta_class a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
JOIN @cls_en s ON s.class_name = a.class_name
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT l.caption, l.caption_plural, l.description, l.helptext
	EXCEPT
	SELECT s.caption, s.caption_plural, s.description, s.helptext
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
INSERT INTO meta_class (
	uuid, object_owner, original, record_type, approval_status, [language],
	class_name, storage_object, ancestor_class, sort_code, days_in_trash, svg_icon,
	caption, caption_plural, description, helptext,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.class_name, a.storage_object, a.ancestor_class, a.sort_code, a.days_in_trash, a.svg_icon,
	s.caption, s.caption_plural, s.description, s.helptext,
	a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_class a
JOIN @cls_en s ON s.class_name = a.class_name
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_class l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'en'
  );
GO