/* =============================================================================
 * Verze: 2026-11-09 14:45
 * Soubor: fillup_meta_menu_en.sql
 * Účel:   Hromadné idempotentní nastavení výchozích anglických překladů (jazyk 'en',
 *         record_type = 'L') pro systémové položky navigace v tabulce meta_menu
 *         (object_owner = 0x00), seřazené abecedně podle builtin_code.
 * Vazby:  - Navazuje na fillup_meta_menu.sql a p_get_menu_hierarchy.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @mnu_en TABLE (
	builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption varchar(200) NOT NULL,
	description varchar(max) NOT NULL,
	helptext varchar(max) NOT NULL
);

INSERT INTO @mnu_en (builtin_code, caption, description, helptext) VALUES
('admin_folder','System Administration','Change approval, management of organizations, licences, users, data package transfer, service logbook, and user activity','Change approval, management of organizations, licences, users, data package transfer, service logbook, and user activity'),
('approval','Change Approval','Review, approval, and rejection of proposed record changes','Review, approval, and rejection of proposed record changes'),
('asset','Asset Inventory','Inventory of physical assets, host computers, cabling, documents, media, data, software, applications, services, interfaces, personnel, and suppliers','Inventory of physical assets, host computers, cabling, documents, media, data, software, applications, services, interfaces, personnel, and suppliers'),
('asset_class','Asset Classes','Management of the hierarchical catalog of asset classes, leaf nodes, and editor roles','Management of the hierarchical catalog of asset classes, leaf nodes, and editor roles'),
('asset_locations','Spaces & Locations','Hierarchical inventory of spaces (District -> City -> Site -> Building -> Room) for asset placement','Hierarchical inventory of spaces (District -> City -> Site -> Building -> Room) for asset placement'),
('audit_login_session','User Activity','Overview of user logins and activity from the audit_login_session table','Overview of user logins and activity from the audit_login_session table'),
('countermeasure','Countermeasure Catalog','Management of the hierarchical catalog of security and operational countermeasures and their reduction and risk factors','Management of the hierarchical catalog of security and operational countermeasures and their reduction and risk factors'),
('countermeasure_implementation','Countermeasure Implementation','Registry of the implementation status of security countermeasures across specific assets and spaces','Registry of the implementation status of security countermeasures across specific assets and spaces'),
('countermeasure_state','Countermeasure States','Management of the codetable of countermeasure implementation states and their reduction and risk factors','Management of the codetable of countermeasure implementation states and their reduction and risk factors'),
('crmm_analysis_folder','Risk Analysis & Management (CRMM)','Operational CRMM agenda: spaces and asset inventory, dependency links, risk scenario assessments, and countermeasure implementation','Operational CRMM agenda: spaces and asset inventory, dependency links, risk scenario assessments, and countermeasure implementation'),
('crmm_folder','CRMM Configuration & Catalogs','Methodological configuration of the CRMM system: catalogs of asset classes, threats, impacts, scenarios, countermeasures, assessment scales, secondary hierarchies, and link types','Methodological configuration of the CRMM system: catalogs of asset classes, threats, impacts, scenarios, countermeasures, assessment scales, secondary hierarchies, and link types'),
('csv_package','Package Transfer (CSV/TSV)','Export and two-phase import of data packages between instances','Export and two-phase import of data packages between instances'),
('excel_reader','Import Data from Excel','Bulk import and verification of metadata from an XLSX file','Bulk import and verification of metadata from an XLSX file'),
('hierarchy','Secondary Hierarchies & Tags','Management of the registry of secondary hierarchies, classification trees, codetables, and tags','Management of the registry of secondary hierarchies, classification trees, codetables, and tags'),
('hierarchy_item','Secondary Hierarchy Items','Management of nodes and leaf items of individual secondary hierarchies, codetables, and tags','Management of nodes and leaf items of individual secondary hierarchies, codetables, and tags'),
('home','Home','Main application dashboard','Main application dashboard'),
('impact','Impact Catalog','Management of the hierarchical catalog of impact types and areas','Management of the hierarchical catalog of impact types and areas'),
('link','Asset Links & Dependencies','Management of operational, support, and spatial M:N links between assets, services, applications, data, and personnel','Management of operational, support, and spatial M:N links between assets, services, applications, data, and personnel'),
('meta_class','Logical Classes (Objects)','Management of logical entities, their properties, and translations','Management of logical entities, their properties, and translations'),
('meta_column','Metadata Columns','Management of column definitions, form controls, and translations','Management of column definitions, form controls, and translations'),
('meta_link_def','Link Type Definitions','Management of the catalog of allowed relationship and link types between logical classes in meta_link_def','Management of the catalog of allowed relationship and link types between logical classes in meta_link_def'),
('meta_menu','Menu Items (Navigation)','Management of hierarchy, sort order, target pages, and translations of menu items','Management of hierarchy, sort order, target pages, and translations of menu items'),
('meta_phrase','Text Phrases & Translations','Management of text phrases, buttons, and language mutations','Management of text phrases, buttons, and language mutations'),
('metadata_folder','Metadata Management','Management of logical classes, columns, text phrases, navigation, and developer metadata packages','Management of logical classes, columns, text phrases, navigation, and developer metadata packages'),
('org_users','Organization Users','Management of users, permissions, and access requests within the organization','Management of users, permissions, and access requests within the organization'),
('organization','Organization Management & Settings','Overview, organization settings, and CRMM calculation parameters','Overview, organization settings, and CRMM calculation parameters'),
('organization_licence','Organization Licence Management','Registry of licence requests and activation of new organizations','Registry of licence requests and activation of new organizations'),
('scale','Assessment Scales','Management of assessment scales for threats, vulnerabilities, impacts, and resulting risks','Management of assessment scales for threats, vulnerabilities, impacts, and resulting risks'),
('scale_value','Assessment Scale Levels','Management of individual assessment scale levels, threshold values, and scores (0 to 100 %)','Management of individual assessment scale levels, threshold values, and scores (0 to 100 %)'),
('scenario','Risk Scenarios','Management of the hierarchical catalog of risk scenarios (events) and minimum residual risk thresholds','Management of the hierarchical catalog of risk scenarios (events) and minimum residual risk thresholds'),
('scenario_assessment','Risk Scenario Assessments','Evaluation of threat level, vulnerability, impact, and calculated inherent and residual risk of scenarios on organization assets','Evaluation of threat level, vulnerability, impact, and calculated inherent and residual risk of scenarios on organization assets'),
('service_logbook','Service Logbook','History of executed database upgrades and system batch imports','History of executed database upgrades and system batch imports'),
('threat','Threat Catalog','Management of the hierarchical catalog of threats and their default score values','Management of the hierarchical catalog of threats and their default score values'),
('xlsx_export_meta','Export Metadata to Excel','Reverse export of system metadata into an XLSX file','Reverse export of system metadata into an XLSX file');

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
UPDATE l
SET l.caption = s.caption,
	l.description = s.description,
	l.helptext = s.helptext,
	l.parent_uuid = a.parent_uuid,
	l.sort_code = a.sort_code,
	l.target_object = a.target_object,
	l.url_parameters = a.url_parameters,
	l.system_role = a.system_role,
	l.svg_icon = a.svg_icon,
	l.who_modified = @sys_owner,
	l.date_modified = GETDATE()
FROM meta_menu l
JOIN meta_menu a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
JOIN @mnu_en s
	ON s.builtin_code = a.builtin_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT l.caption, l.description, l.helptext, l.parent_uuid, l.sort_code, l.target_object, l.url_parameters, l.system_role
	EXCEPT
	SELECT s.caption, s.description, s.helptext, a.parent_uuid, a.sort_code, a.target_object, a.url_parameters, a.system_role
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
INSERT INTO meta_menu (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, target_object, url_parameters, target_url, target_window,
	caption, description, helptext, svg_icon, css_class, system_role, permanent,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.builtin_code, a.parent_uuid, a.sort_code, a.target_object, a.url_parameters, a.target_url, a.target_window,
	s.caption, s.description, s.helptext, a.svg_icon, a.css_class, a.system_role, a.permanent,
	a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_menu a
JOIN @mnu_en s
	ON s.builtin_code = a.builtin_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_menu l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'en'
  );
GO