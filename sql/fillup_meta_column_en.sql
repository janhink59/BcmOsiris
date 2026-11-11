/* =============================================================================
 * Verze: 2026-11-11 22:30
 * Soubor: fillup_meta_column_en.sql
 * Účel:   Hromadné idempotentní nastavení výchozích anglických překladů sloupců
 *         (jazyk 'en', record_type = 'L') pro globální slovník sys_global_columns
 *         (a specifické lokální overridy) v tabulce meta_column (object_owner = 0x00)
 *         jedním příkazem UPDATE a jedním INSERT, seřazené abecedně podle column_name.
 *         Přepisuje záznamy s who_modified = 0x00 nebo date_modified < '2026-11-01'.
 * Vazby:  - Navazuje na fillup_meta_column.sql.
 *         - V BuildListDb.txt se spouští za final_scripts.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
DECLARE @c_class uniqueidentifier = dbo.f_generate_original('meta_class', @sys_owner, 'sys_global_columns', '');
DECLARE @cls_hierarchy uniqueidentifier = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'hierarchy', '');

DECLARE @col_en TABLE (
	column_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption varchar(200) NOT NULL,
	label varchar(200) NOT NULL,
	header varchar(200) NOT NULL,
	helptext varchar(max) NOT NULL
);

INSERT INTO @col_en (column_name, caption, label, header, helptext) VALUES
('access_uuid','Access ID (access_uuid)','Original Access Record UUID','Access ID','Logical identifier of the record in user_organization_access.'),
('activation_date','Activation Date (activation_date)','Licence Activation Date','Activated On','Date when the licence was processed and the organization activated.'),
('active_role','Active Role (active_role)','Active Session Role (U/A/S/D)','Active Role','Effective application role in the current session.'),
('address_city','City / Town (address_city)','City / Municipality','City','City or municipality of the organization headquarters.'),
('address_name','Address Name (address_name)','Official Name in Registered Address','Address Name','Company name or supplement used in the postal address.'),
('address_state','Country / State (address_state)','Country / State','Country','Country where the organization headquarters is located.'),
('address_street','Street & Number (address_street)','Street and Building Number','Street','Street and building number of the organization headquarters.'),
('address_zip','Postal / ZIP Code (address_zip)','Postal / ZIP Code','ZIP Code','Postal code of the headquarters address.'),
('admin_email','Admin Email (admin_email)','Organization Administrator Email','Admin Email','Contact email address of the organization administrator.'),
('admin_first_name','Admin First Name (admin_first_name)','Administrator First Name','Admin First Name','First name of the initial organization administrator.'),
('admin_last_name','Admin Last Name (admin_last_name)','Administrator Last Name','Admin Last Name','Last name of the initial organization administrator.'),
('admin_login','Organization Admin Login (admin_login)','Initial Administrator Login','Admin Login','Login name of the initial administrator of the newly created organization.'),
('allow_local_login','Allow Local Login (allow_local_login)','Allow Username & Password Login','Local Login','Indicates whether the user may log in using a local password (if disabled, SSO is required).'),
('ancestor','Column Ancestor (ancestor)','Ancestor in Global Column Dictionary','Ancestor Column','Reference to the base column definition in sys_global_columns from which unspecified properties are inherited.'),
('ancestor_class','Ancestor Class for Inheritance (ancestor_class)','Parent Class (STI Inheritance)','Ancestor Class','Reference to the parent logical class from which this class inherits columns and default behavior.'),
('ancestor_link','Ancestor Source Link (ancestor_link)','Source Link for Hierarchy Inheritance','Ancestor Link','Identifier of the parent link in the link table from which this link was derived by hierarchy inheritance (0x00 = direct link).'),
('app_version','Application Version (app_version)','Application Code Version','App Version','Version identifier of the deployed PHP application scripts.'),
('application','Application Name (application)','Client Application Identifier','Application','Name of the client application connecting to the database.'),
('application_info_file','Application Info File (application_info_file)','Path to Version Release Notes File','Info File','Path to the file containing MOTD or release notes.'),
('approval_note','Approval Note (approval_note)','Approver Note / Rejection Reason','Approval Note','Accompanying note for the proposal or the approver reason when returning a draft for revision.'),
('approval_status','Approval Status (approval_status)','Approval Status (A/D/F/R)','Approval','SSC lifecycle status: A = approved, D = working draft, F = forwarded for approval, R = rejected/returned.'),
('assessment_date','Assessment Date (assessment_date)','Assessment / Review Date','Assessment Date','Calendar date when the risk scenario assessment was performed or last reviewed.'),
('assessor_user_uuid','Assessor (assessor_user_uuid)','Person Who Performed Assessment','Assessed By','Reference to the user account of the person who performed or reviewed the scenario assessment.'),
('asset_archetype','Asset Archetype (asset_archetype)','Asset Archetype (STI Classification)','Archetype','Core system category of the asset determining its behavior and placement (SPACE, PHYSICAL, HOST, DATA, APPLICATION, SERVICE...).'),
('asset_class_uuid','Target Asset Class (asset_class_uuid)','Asset Class for Impact Assessment','Asset Class','Reference to the asset class in asset_class on which the impact of this scenario is evaluated.'),
('asset_uuid','Assessed / Protected Asset (asset_uuid)','Asset / Space','Asset','Reference to the assessed or protected asset or space in the asset table.'),
('assumed_role','Assumed Session Role (assumed_role)','Effective Session Role (U/A/S/D)','Session Role','Effective role under which the user worked during the login session.'),
('authorization_code','Authorization Code (authorization_code)','Activation Authorization Code','Auth. Code','Unique identifier for authorizing the licence request.'),
('availability_score','Availability Score in % (availability_score)','Availability Requirement (0–100%)','Availability (%)','Calculation score of service or data outage impact in percent (0 to 100%).'),
('backup_diff_count','Differential Backup Count (backup_diff_count)','Differential Backups per Cycle','Diff Backup Count','Configured number of differential backups between full backups.'),
('backup_diff_counter','Differential Backup Counter (backup_diff_counter)','Current Differential Backup Number','Diff Counter','Internal counter of executed differential backups.'),
('backup_full_date','Last Full Backup Date (backup_full_date)','Last Full Database Backup Time','Full Backup Date','Date and time when the last FULL database backup was completed.'),
('backup_full_days','Full Backup Period (backup_full_days)','Full Backup Interval in Days','Full Backup Days','Number of days between automatic full database backups.'),
('backup_log_date','Last Log Backup Date (backup_log_date)','Last Transaction Log Backup Time','Log Backup Date','Date and time of the last transaction log backup.'),
('backup_log_hours','Log Backup Period (backup_log_hours)','Log Backup Interval in Hours','Log Period (h)','Number of hours between transaction log backups.'),
('backup_path','Backup Path (backup_path)','Database Backup Directory Path','Backup Path','Physical directory path on the server disk for database backup files.'),
('bad','Cyclic Edge (bad)','Flag of Node Causing a Cycle','Cycle (bad)','Flag (1) marking the terminal node of an edge that loops back to an already visited ancestor on the path.'),
('builtin','Built-in Record (builtin)','Built-in System Record','Built-in','Flag indicating a standard built-in record supplied with the system.'),
('builtin_code','Unique Code (builtin_code)','Record Code (builtin_code)','Code','Unique technical identifier used for deterministic original calculation (auto-derived from name on new records).'),
('caption','Display Caption (caption)','Name / Caption','Name','Primary display name of the item (supports translation into other languages).'),
('caption_backward','Backward Link Caption (caption_backward)','Link Caption from Target to Source','Backward Caption','Verbal description of the link from the target perspective (e.g., "Is Affected By" or "Belongs To").'),
('caption_forward','Forward Link Caption (caption_forward)','Link Caption from Source to Target','Forward Caption','Verbal description of the link from the source perspective (e.g., "Affects" or "Contains").'),
('caption_plural','Plural Caption (caption_plural)','Plural Name (List Heading)','Plural Name','Plural form of the name displayed as the master list heading in the left panel.'),
('cell_value','Cell Value (cell_value)','CSV Cell Text Value','Cell Value','Non-empty cell content loaded from the imported CSV file.'),
('change_context_allowed','Context Switch Allowed (change_context_allowed)','Allow Switching Organization / Role','Context Switch','Indicates whether the user can switch organizations or roles from the top bar.'),
('charvalue','Character Value (charvalue)','Text Detail / Variable Value','Char. Value','Text detail of the message or value of the request variable.'),
('children','Direct Child Count (children)','Number of Subsequent Branch Nodes','Children','Total number of direct successor nodes of the given node in the resolved graph.'),
('circular','Branch Contains Cycle (circular)','Flag of Branch Leading to a Cycle','Cyclic Branch','Flag (1) on all nodes of a branch under which a cycle occurred in the directed graph.'),
('class_name','Technical Class Name (class_name)','Logical Class Code (class_name)','Class Code','Unique system identifier of the logical class in the STI architecture.'),
('client_ip','Client IP Address (client_ip)','Client IP Address','Client IP','Network IP address of the client browser.'),
('code','Code (code)','Item / Message Code','Code','Technical code of the message or item.'),
('codetable_name','Codetable Name (codetable_name)','Codetable Code (codetable_name)','Codetable Code','Technical identifier of the codetable group in meta_codetable.'),
('colid','Column ID (colid)','Column Sequential Number in Table','Col. ID','Internal sequential column number in the system syscolumns catalog.'),
('collation_name','Collation Name (collation_name)','Database Column Collation Name','Collation','Collation name applied to a character column in SQL Server.'),
('colname','Column Name (colname)','System Column Name','Column','Column name in the database system catalog.'),
('color','Text Color (color)','Message Display Color','Color','Explicit text color for rendering the message row.'),
('color_code','Color Code (color_code)','Color (HEX / CSS Code)','Color','Color code (e.g., #16A34A) for visual highlighting of the item or scale level.'),
('column_id','Import Column ID (column_id)','Global Column Number in CSV','Column ID','Unique sequential column number within the CSV import staging tables.'),
('column_name','Technical Column Name (column_name)','Technical Column Name','Column','Exact database identifier of the column in the storage table or view.'),
('completion_date','Completion Date (completion_date)','Actual Completion / Verification Date','Completed On','Actual date when the countermeasure was implemented and verified.'),
('computed_syntax','Computed Column Formula (computed_syntax)','SQL Formula of Computed Column','Computed Formula','SQL expression defining a computed column.'),
('confidentiality_score','Confidentiality Score in % (confidentiality_score)','Confidentiality Requirement (0–100%)','Confidentiality (%)','Calculation score of data disclosure impact in percent (0 to 100%).'),
('content','Content / Note (content)','Record Content / Change Description','Content / Note','Text description of the executed operation, database upgrade, or imported package.'),
('copyonly_backup_switch','COPY_ONLY Backup Mode (copyonly_backup_switch)','Use COPY_ONLY Flag During Backups','COPY_ONLY Backup','Prevents disrupting the LSN chain when external backups are used concurrently.'),
('counter','Message Counter (counter)','Sequential Message Number','Counter','Automatic sequential number of the message in request_message.'),
('countermeasure_uuid','Applied Countermeasure (countermeasure_uuid)','Catalog Countermeasure','Countermeasure','Reference to the security, technical, or organizational control in the countermeasure table.'),
('currency_before','Currency Before Amount (currency_before)','Display Currency Symbol Before Number','Currency Before','If checked, the currency symbol is placed before the numeric amount (e.g., € 100).'),
('currency_digits','Currency Decimal Places (currency_digits)','Number of Currency Decimal Places','Currency Decimals','Number of decimal places displayed for financial amounts.'),
('currency_unit','Currency Unit (currency_unit)','Currency Unit Used','Currency','Currency unit label used for financial impact and risk valuation (e.g., kCZK, EUR).'),
('current_organization','Current Session Organization (current_organization)','Currently Active Organization','Current Org.','Organization active in the currently executing @@SPID session.'),
('current_path','Current Traversal Path (current_path)','Sequence of Nodes from Root','Graph Path','Space-separated list of visited nodes from the root used for cycle detection in the graph.'),
('current_year','Current Year (current_year)','Current Calendar Year','Current Year','Default calendar year in system settings.'),
('customizable','Allow Customization (customizable)','Allow Tenant Customization','Customizable','Indicates whether a client organization (tenant) may customize properties of this column.'),
('database_state','Database State (database_state)','Database Operational State','DB State','Single-character indicator of the database operational state.'),
('database_version','Database Version (database_version)','Current Database Schema Version','DB Version','Database schema version in YY.MM.DD.N format managed by changes_YYYY.sql.'),
('date','Date & Time (date)','Record Date & Time','Date & Time','Timestamp of the entry in the service logbook.'),
('date_created','Date Created (date_created)','Created Date & Time','Created','Exact date and time when the record was initially created.'),
('date_modified','Date Modified (date_modified)','Last Modified Date & Time','Modified','Exact date and time of the last modification of the record or its language mutation.'),
('days_in_trash','Days in Trash (days_in_trash)','Trash Retention Days Before Purge','Days in Trash','Number of days removed records (removed = 1) are kept in the trash before automatic physical deletion (0 = never purge).'),
('debug','Debug Mode (debug)','Enable Debug Output (debug)','Debug','Flag enabling developer debug output in the session.'),
('decimal_separator','Decimal Separator (decimal_separator)','Decimal Separator Character','Decimal Sep.','Character separating integer and fractional parts of a number (comma or dot).'),
('default_constraint_name','Default Constraint Name (default_constraint_name)','System DEFAULT Constraint Name','Default Name','Database constraint name enforcing the column default value.'),
('default_syntax','Default Value Syntax (default_syntax)','DEFAULT Constraint Definition','Default Syntax','SQL expression of the column default value in the system catalog.'),
('default_threat_score','Default Threat Score (default_threat_score)','Default Threat Level (Score)','Default Score','Default numeric threat rating pre-filled during scenario analysis.'),
('department_name','Department / Unit (department_name)','Department / Organizational Unit','Department','Name of the department or unit to which the user is assigned in the organization.'),
('description','Description (description)','Detailed Description','Description','Detailed description of the purpose and meaning of the item (supports Markdown / HTML).'),
('description_text','Description (description_text)','Detailed Description','Description','Detailed methodological or domain description of the item (supports Markdown / HTML).'),
('diagram_uuid','Source Network Diagram (diagram_uuid)','Network Diagram / Schema (link_diagram)','Network Diagram','Reference to the heterogeneous network schema (link_diagram) from which this indirect relationship or link was projected.'),
('digital_signature','Digital Signature (digital_signature)','Verification Digital Signature','Signature','Binary checksum or digital signature of the record.'),
('direction_type','Relationship Direction (direction_type)','Direction Type (P/R/S)','Direction (P/R/S)','Specifies relationship orientation: P = Primary (governing direction), R = Reverse (inverse direction), S = Symmetric (undirected).'),
('display_name','Display Name (display_name)','Logged-in User Full Name','Display Name','Full display name of the user shown in the top bar.'),
('draft_author','Draft Author (draft_author)','Draft Author','Draft Author','User account identifier of the author of the working draft or proposed change.'),
('editor_note','AI Context Note (editor_note)','Translator & AI Context Note','AI Context','Semantic clarification of the record meaning for accurate human and AI translation (not translated).'),
('editor_role_uuid','Editor Role (editor_role_uuid)','Role Authorized to Edit','Editor Role','Reference to the role authorized to edit records in this hierarchy branch (inherited by child nodes).'),
('effective_reduction_factor','Effective Reduction Factor in % (effective_reduction_factor)','Effective Risk Reduction (0–100%)','Eff. Reduction (%)','Calculated product of the countermeasure reduction factor and its state weight in percent (0 to 100%).'),
('effective_risk_factor','Effective Risk Floor Factor in % (effective_risk_factor)','Effective Minimum Risk Floor (0–100%)','Eff. Risk Floor (%)','Calculated product of the countermeasure risk factor and its state weight when unimplemented (0 to 100%).'),
('email','Email Address (email)','Email Address','Email','Contact and authentication email address of the user.'),
('email_sender_address','Email Sender Address (email_sender_address)','Sender Email Address','Sender Email','Email address used as the sender of system notifications.'),
('email_sender_name','Email Sender Name (email_sender_name)','Display Name of Email Sender','Sender Name','Display name used in the From header of outgoing system emails.'),
('evaluation_method','Risk Evaluation Method (evaluation_method)','Selected CRMM Evaluation Method','Evaluation Method','Code of the methodology or calculation model used for risk evaluation.'),
('expires','Token Expiration (expires)','Token Valid Until','Expires','Expiration date and time of the persistent login token.'),
('expires_at','Expires At (expires_at)','Token Expiration Timestamp','Expires At','Exact timestamp when the one-time security token expires.'),
('export_delimiter','CSV Field Delimiter (export_delimiter)','Default Delimiter for CSV Export','CSV Delimiter','Character separating columns in exported CSV files (semicolon ; by default).'),
('external_code','External Code (external_code)','External Code (for mapping)','Ext. Code','Optional identifier for mapping the record with external systems, standards, or catalogs.'),
('failed_login_attempts','Failed Login Attempts (failed_login_attempts)','Consecutive Failed Login Attempts','Failed Attempts','Counter of consecutive invalid password attempts (locks account temporarily when threshold is reached).'),
('fallback_language','Fallback Language (fallback_language)','Parent Fallback Language','Fallback Lang.','Code of the fallback language used when a text is not translated into the active language.'),
('fallback_order','Fallback Chain Order (fallback_order)','Language Fallback Order','Fallback Order','Computed language order in the fallback chain for the current session (1 = active language, < 1000 = in chain).'),
('first_name','First Name (first_name)','First Name','First Name','Given first name of the person.'),
('format_date','Date Format (format_date)','Date Display Format','Date Format','Formatting mask for displaying calendar dates in the UI (e.g., dd.MM.yyyy or yyyy-MM-dd).'),
('format_time','Time Format (format_time)','Time Display Format','Time Format','Formatting mask for displaying time values in the UI (e.g., HH:mm:ss).'),
('from_class','Source Link Class (from_class)','Source Class of Link (From)','From Class','Reference to the logical class in meta_class forming the origin side of the link.'),
('from_id','Edge Source Node (from_id)','Parent / Source Node in Graph','From Node (from_id)','Identifier of the parent source node of an edge in f_resolve_link_diagram.'),
('from_object','Source Link Object (from_object)','Source Linked Record (From)','From Object','Original UUID of the source record connected by the link.'),
('hashed_validator','Validator Hash (hashed_validator)','SHA-256 Hash of Secret Validator','Validator Hash','Cryptographic hash of the secret validator part of the persistent login token.'),
('header','Table Column Header (header)','List Column Header (header)','Header','Short column heading used in summary tables and master lists.'),
('help_text','Help Text (help_text)','Help Text (Tooltip / Guidance)','Help Text','Methodological help or user instructions displayed for the item.'),
('helptext','Help Text (helptext)','Help Text (Tooltip / Guidance)','Help Text','Methodological help or user instructions displayed for the item.'),
('hidden','Hidden Column (hidden)','Hide Field in Standard Form','Hidden','Technical column hidden from standard detail edit forms.'),
('hidden_root','Hidden Root with Predecessor (hidden_root)','Node Is Not a Graph Root (Has Predecessor)','Hidden Root','Flag (1) marking starting nodes that have an incoming valid edge from another node (not top-level roots).'),
('hierarchy','Parent Hierarchy (hierarchy)','Secondary Hierarchy / Tag Set','Hierarchy','Reference to the secondary hierarchy or tag set definition in the hierarchy table.'),
('hierarchy_sort','Tree Sort Path (hierarchy_sort)','Zero-Padded Tree Traversal Sort Key','Tree Sort Key','Concatenated zero-padded sort string determining exact tree order.'),
('history','Track History (history)','Store Historical Versions (H)','History','Indicates whether changing the column value creates a historical snapshot record (type H).'),
('i','Integer Value (i)','Parsed Integer Value','Integer (i)','Integer value returned by f_integer_list.'),
('icon','Message Icon (icon)','Message Icon','Icon','Icon identifier for a request message.'),
('id','Sequential ID (id)','Numeric Record Identifier (ID)','ID','Automatically generated sequential record number (IDENTITY).'),
('impact_score','Impact Score in % (impact_score)','Scenario Impact Severity (0–100%)','Impact (%)','Input rating of overall scenario impact on the asset in percent (0 to 100%).'),
('import_origin','Import Origin (import_origin)','Record Import Origin','Import Origin','Identification of the external source, package, or author during bulk data import (soft audit).'),
('inactive','Inactive Record (inactive)','Inactive (Deactivated)','Inactive','Flag temporarily or permanently disabling the record from standard selection without deleting it.'),
('indent','Indentation Level (indent)','Message Row Indentation','Indent','Numeric visual indentation level of the message from the left.'),
('index_name','Index Name (index_name)','System Index Name','Index','Database index name in sys.indexes.'),
('inherent_risk_score','Inherent Risk in % (inherent_risk_score)','Inherent Risk Before Controls (0–100%)','Inh. Risk (%)','Calculated inherent (initial) risk score prior to applying countermeasures in percent (0 to 100%).'),
('initial_levels','Initial Level Count (initial_levels)','Number of Levels (to Generate)','Level Count','Number of even levels (2 to 20) automatically generated in the 0 to 100% range when first saving a new scale.'),
('input_rows','Textarea Rows (input_rows)','Number of Rows (for textarea)','Rows','Height of a multi-line text field (textarea) in visible rows.'),
('input_type','Input Control Type (input_type)','Form Input Type','Input Type','HTML control type in the detail form (text, textarea, number, date, checkbox).'),
('input_width','Input Width (input_width)','Input Field Width (CSS)','Input Width','CSS width of the form control in the detail panel (e.g., 100%, 180px, auto).'),
('instance_class_name','Instance Class Name (instance_class_name)','Object Instance Class','Instance Class','Specific application class designation for instances of this category.'),
('integrity_score','Integrity Score in % (integrity_score)','Integrity Requirement (0–100%)','Integrity (%)','Calculation score of data inconsistency, corruption, or destruction impact in percent (0 to 100%).'),
('intvalue','Integer Value (intvalue)','Numeric Value / Row Count','Int. Value','Integer value associated with the message or variable (e.g., processed row count).'),
('inventory_number','Inventory / Serial Number (inventory_number)','Inventory / Serial Number','Inv. No.','Inventory, asset tag, or serial number of a physical asset, storage medium, or document.'),
('invoice_info','Billing Information (invoice_info)','Billing & Bank Account Details','Billing Info','Additional billing details, bank account numbers, or invoice notes.'),
('ip_address','IP Address (ip_address)','Client IP Address','IP Address','Network IP address of the client (including X-Forwarded-For path).'),
('is_computed','Computed Column (is_computed)','Computed Column (Read-Only)','Computed','The column is calculated by the database or application and is locked as read-only in forms.'),
('is_default','Default Item (is_default)','Default Value (Preselected)','Default','Check for the item that should be automatically preselected when creating a new record.'),
('is_derived','Derived Link (is_derived)','Link Materialized by Inheritance','Derived','Flag indicating that the link was automatically materialized by inheritance from a parent hierarchy node.'),
('is_descending_key','Descending Index Key (is_descending_key)','Index Column Sorted Descending (DESC)','Descending (DESC)','Indicates whether the column is sorted descending in the index.'),
('is_developer','System Developer (is_developer)','Global Developer Role (D)','Developer','Authorizes the user to modify system metadata, structures, and developer packages.'),
('is_exclusive_parent','Exclusive Tree Parent (is_exclusive_parent)','Relationship Maps to parent_uuid Column','Excl. Parent','Indicates that this relationship represents direct exclusive tree parenthood from the parent_uuid column (at most 1 parent).'),
('is_final','Final Record without Override (is_final)','Disallow Tenant Override (is_final)','Final','If checked (1), client organizations cannot override functional attributes of the record (only translations are allowed).'),
('is_html','Formatted Text Markdown/HTML (is_html)','Formatted Rich Text (Markdown / HTML)','Rich Text','Enables formatted rich text support with preview and modal Toast UI Editor (Markdown / HTML).'),
('is_identity','Identity Column (is_identity)','IDENTITY Auto-Increment Flag','Is IDENTITY','Indicates whether the database column uses IDENTITY auto-incrementing.'),
('is_included_column','Included Column (is_included_column)','Non-Key Column Added via INCLUDE','Included Col.','Indicates whether the column is attached to the index via the INCLUDE clause.'),
('is_leaf','Leaf Node (is_leaf)','Leaf Node (Terminal Item)','Leaf','Check for a terminal leaf item. Uncheck for an internal folder node that will contain child items.'),
('is_mandatory','Mandatory Field (is_mandatory)','Mandatory Field (Required)','Mandatory','Marks a field that must be filled in before saving the form.'),
('is_multiple','Multiple Link (is_multiple)','Allow Linking Multiple Objects (M:N)','Multiple','Indicates whether multiple target records of this type can be linked to a single source record.'),
('is_orgadmin','Organization Administrator (is_orgadmin)','Administrator of This Organization (A)','Org. Admin','Authorizes the user to manage users, access requests, and settings within this organization.'),
('is_primary_key','Primary Key (is_primary_key)','Index Forms Table Primary Key','Primary Key','Indicates whether the index represents the primary key of the table.'),
('is_protected','Protected Technical Logic (is_protected)','Protected System Element (is_protected)','Protected','Restricts client modifications of purely technical and architectural properties of the record.'),
('is_system_admin','System Administrator (is_system_admin)','Global Sysadmin Role (S)','Sysadmin','Authorizes the user to enter the system organization (0x00) and administer the entire server.'),
('is_template','Template Flag (is_template)','Acts as Template','Is Template','Indicates whether this record serves as a master template for cloning.'),
('is_unique','Unique Index (is_unique)','Unique Index Flag','Unique','Indicates whether the index enforces uniqueness of key values.'),
('is_url','Contains URL Address (is_url)','Field Contains URL Link','Is URL','Validates and formats the input field as a web URL address.'),
('is_used','Token Already Used (is_used)','Token Has Been Used','Used','Flag preventing replay/reuse of a one-time security token.'),
('iscomputed','Computed Column (iscomputed)','Database Computed Column Flag','Computed (DB)','System catalog flag indicating whether the column is a computed column.'),
('job_title','Job Title (job_title)','Job Title / Position','Job Title','Job title or position of the user within the organization.'),
('key1_column','First Key Column (key1_column)','1st Original Key Column','1st Key','Name of the first column used to calculate the deterministic original identifier.'),
('key2_column','Second Key Column (key2_column)','2nd Original Key Column','2nd Key','Name of the optional second column used to calculate the deterministic original identifier.'),
('key_ordinal','Index Key Ordinal (key_ordinal)','Column Position in Index Key','Key Ordinal','Position of the column within the index key (0 = included non-key column).'),
('keyno','Primary Key Ordinal (keyno)','Column Position in Primary Key','PK Ordinal','Sequential position of the column within a composite primary key.'),
('keyvalue','Node Key Value (keyvalue)','Tree Node Identifier','Node Key','Item identifier used during tree hierarchy resolution.'),
('label','Form Field Label (label)','Detail Field Label (label)','Label','Label text displayed to the left of the input control in the detail edit form.'),
('language','Record Language (language)','Language','Language','Two-letter ISO language code of the record or language mutation (e.g., cs, en, sk, de).'),
('last_login_date','Last Login Date (last_login_date)','Last Login Date & Time','Last Login','Timestamp of the user last successful login.'),
('last_login_org','Last Organization (last_login_org)','Last Logged-in Organization','Last Org.','Organization into which the user last logged in.'),
('last_login_organization','Last Login Organization (last_login_organization)','Last Visited Organization','Last Organization','Reference to the organization in which the user worked during their last login.'),
('last_name','Last Name (last_name)','Last Name / Surname','Last Name','Family surname of the person.'),
('last_password_change','Last Password Change (last_password_change)','Last Password Change Date & Time','Password Changed','Timestamp of the last password change for the user account.'),
('last_request_time','Last Activity (last_request_time)','Last Request Time in Session','Last Activity','Timestamp of the last HTTP request recorded in the session.'),
('last_role','Last Selected Role (last_role)','Last Used Role (U/A/S/D)','Last Role','Last effective role used by the user in this organization.'),
('last_used','Last Used (last_used)','Token Last Used Timestamp','Last Used','Date and time when this persistent token was last used for auto-login.'),
('ldap_root','LDAP Root Path (ldap_root)','Active Directory / LDAP Root Path','LDAP Root','Configuration path for Active Directory / LDAP integration.'),
('leaf_only','Leaf Nodes Only (leaf_only)','Allow Links to Leaf Nodes Only','Leaves Only','Indicates whether target records may be linked exclusively to terminal leaf nodes (is_leaf = 1) of this hierarchy.'),
('level','Nesting Level (level)','Tree Node Nesting Depth','Level','Numeric nesting depth of the item in the tree hierarchy (0 = root).'),
('licence_level','Licence Level (licence_level)','Organization Licence Level','Licence Level','Organization permission tier: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
('licence_state','Licence State (licence_state)','Licence Lifecycle State','Licence State','Licence lifecycle state: DRAFT, APPROVED (triggers activation), PROCESSED (active), REJECTED.'),
('link_code','Link Type Code (link_code)','Technical Link Type Code','Link Code','Unique system identifier of the link definition in meta_link_def.'),
('link_def','Link Definition (link_def)','Link Type (meta_link_def)','Link Type','Reference to the link type definition in meta_link_def.'),
('link_weight','Link Numeric Weight (link_weight)','Quantitative Link Weight / Priority','Link Weight','Numeric value expressing risk transfer weight or priority of the specific link instance.'),
('link_weight_enabled','Link Weight Enabled (link_weight_enabled)','Track Numeric Weight on Link','Weight Enabled','Enables entering a quantitative weight or priority directly on the link instance in the link table.'),
('list_order','Master List Order (list_order)','Column Order in Master List','List Order','If set to a positive integer, the column is displayed in the left master list table in this order.'),
('locked_until','Locked Until (locked_until)','Account Temporarily Locked Until','Locked Until','Date and time until which login is blocked following repeated failed password attempts.'),
('login_date','Session Login Date (login_date)','Session Creation Time','Login Date','Date and time when the web session was created.'),
('login_disabled','Disable Login (login_disabled)','Disable Login for Organization','Login Disabled','If checked, no user can log into the context of this organization.'),
('login_domain','SSO Login Domain (login_domain)','Domain for SSO Login','SSO Domain','Internet domain of the organization used to automatically detect the home tenant during SSO authentication.'),
('login_name','Login Name (login_name)','User Login Name','Login','Unique user login name in the system.'),
('login_session_uuid','Audit Session UUID (login_session_uuid)','Reference to audit_login_session','Session UUID','Unique login session identifier in audit_login_session used for the audit trail.'),
('login_time','Login Time (login_time)','Login Date & Time','Login Time','Timestamp when the user login session started.'),
('login_with_token','Require Token on Login (login_with_token)','Globally Require Authentication Token','Login with Token','Global switch enforcing token-based authentication.'),
('logo_data','Logo Binary Data (logo_data)','Organization Logo File Data','Logo (Data)','Binary content of the organization logo image file.'),
('logo_filename','Logo Filename (logo_filename)','Original Logo Filename','Logo Filename','Filename of the uploaded organization logo image.'),
('logo_mime_type','Logo MIME Type (logo_mime_type)','Logo Image Format (MIME)','Logo MIME Type','Internet media type of the uploaded logo (e.g., image/png, image/svg+xml).'),
('logout_time','Logout / Expiration Time (logout_time)','Logout or Session Expiration Time','Logout Time','Timestamp when the user logged out or the inactive session expired.'),
('machine_guid','Machine GUID (machine_guid)','Unique Server Identifier','Machine GUID','Hardware or system identifier of the server.'),
('manager_uuid','Line Manager (manager_uuid)','Direct Line Manager','Manager','Reference to the user account of the user direct manager in the organization.'),
('max_impact_financial','Financial Value of Max Impact (max_impact_financial)','Financial Expression of Highest Impact','Max. Impact (Fin.)','Financial amount in the organization currency corresponding to the highest impact level.'),
('max_impact_score','Maximum Impact Score (max_impact_score)','Upper Limit of Impact Score','Max. Impact','Highest allowed score value when assessing impact severity in the organization.'),
('max_length','Maximum Text Length (max_length)','Maximum Character Count','Max. Length','Maximum allowed number of characters in a text input matching the database definition.'),
('max_risk_score','Maximum Risk Score (max_risk_score)','Upper Limit of Resulting Risk Score','Max. Risk','Highest resulting risk score value in the organization methodology.'),
('max_threat_score','Maximum Threat Score (max_threat_score)','Upper Limit of Threat Score','Max. Threat','Highest allowed score value when assessing threat level in the organization.'),
('max_vulnerability_score','Maximum Vulnerability Score (max_vulnerability_score)','Upper Limit of Vulnerability Score','Max. Vulnerability','Highest allowed score value when assessing vulnerability in the organization.'),
('mfa_enabled','Multi-Factor Authentication (mfa_enabled)','Require Multi-Factor Authentication','MFA Enabled','Flag enabling multi-factor authentication for the user account.'),
('mfa_secret','MFA Secret Key (mfa_secret)','Cryptographic MFA Secret Key','MFA Secret','Internal secret key used to generate one-time TOTP codes.'),
('min_risk_floor_score','Minimum Risk Floor in % (min_risk_floor_score)','Minimum Residual Risk Floor (0–100%)','Min. Floor (%)','Calculated lower bound below which scenario residual risk cannot drop (from scenario and unimplemented controls).'),
('mobile','Mobile Phone (mobile)','Mobile Phone Number','Mobile','Mobile phone number of the user.'),
('module','Application Module (module)','Licence Module','Module','Code of the application or licensing module to which the object or phrase belongs.'),
('msgtext','Message Text (msgtext)','Main Message Text','Message','Status or error message text displayed to the user.'),
('multiple','Multiple Assignment (multiple)','Allow Assigning Multiple Items','Multiple Items','Indicates whether a target record can be linked to multiple items from this hierarchy simultaneously.'),
('name','Name (name)','Name','Name','Technical or display name of the item.'),
('node_id','Graph Node Identifier (node_id)','Network Node Identifier','Node (node_id)','String identifier of a node during directed graph traversal in f_resolve_link_diagram.'),
('note','Note (note)','Note','Note','Additional internal comment or note on the record (supports Markdown / HTML).'),
('nulls','Nullability (nulls)','NULL Permission (null / not null)','NULL / NOT NULL','Indicates whether the database column allows NULL values.'),
('num','Sibling Order Number (num)','Node Order Among Siblings','Order (num)','Computed sequential number of the node under the same parent.'),
('obj_name','Affected Object Name (obj_name)','Specific Object / Item Identifier','Object Name','Specific identifier or name of the record to which the message relates.'),
('obj_type','Affected Object Type (obj_type)','Object Type','Object Type','Type of object or table to which the message relates.'),
('object_owner','Object Owner (object_owner)','Owner (Organization)','Owner','Identifier of the owning organization (tenant); 0x00 denotes a system record.'),
('object_type','System Object Type (object_type)','Object Type (T/V/F/P/C/M)','Obj. Type','Object category: T = Table, V = View, F = Function, P = PHP Page/Class, C = Global Column Dictionary, M = Module.'),
('ordr','List Item Order (ordr)','Sequential Number in Parsed List','Order','Item position returned by list-splitting functions f_string_list, f_integer_list, and f_uuid_list.'),
('organization','Active Organization (organization)','Organization','Organization','Identifier of the active organization in the session or view.'),
('organization_name','Organization Name (organization_name)','Organization Name','Organization Name','Display name of the organization.'),
('organization_note','Licence Note (organization_note)','Internal Note on Organization Licence','Licence Note','Additional note by the licence issuer regarding the licensed organization.'),
('organization_uuid','Target Organization (organization_uuid)','Organization (UUID)','Organization','Reference to the original identifier of the organization in the organization table.'),
('original','Logical Record Identifier (original)','Original (Object UUID)','Original','Shared logical identifier of the record across language versions, drafts, and tenant overrides.'),
('original_login','SQL Login Account (original_login)','Original SQL Server Login Account','SQL Login','System login name of the SQL Server account (original_login()) that executed the script.'),
('owner_user_uuid','Asset Owner / Guarantor (owner_user_uuid)','Asset Owner / Guarantor (Person)','Asset Owner','Reference to the user account of the person responsible for the asset or space.'),
('param_order','Parameter Order (param_order)','Parameter Order in File','Param. Order','Sequential order of the header parameter in the imported CSV file.'),
('parameter_code','Parameter Code (parameter_code)','Technical Package Parameter Name','Parameter Code','Identifier of the parameter in the CSV import header (e.g., package_name, verify_data, signature).'),
('parameter_value','Parameter Value (parameter_value)','Package Parameter Value','Parameter Value','Text value of the parameter loaded from the CSV file header.'),
('parent','Parent Node (parent)','Parent Identifier in Tree','Parent','Reference to the parent element in f_resolve_hierarchy.'),
('parent_class','Belongs to Class (parent_class)','Parent Logical Class','Class','Structural link defining which logical class this column belongs to.'),
('parent_order','Column Table Order (parent_order)','Column Order in Class','Col. Order','Numeric column order derived from the physical structure of the database table.'),
('parent_path','Parent Traversal Path (parent_path)','Sequence of Nodes to Parent Node','Parent Path','Path from the root to the immediate predecessor node in the directed graph.'),
('parent_uuid','Parent Tree Node (parent_uuid)','Parent Folder / Item','Parent Node','Reference to the parent node in the tree hierarchy (empty means a top-level root item).'),
('password_hash','Password Hash (password_hash)','Cryptographic Password Hash','Password Hash','Securely stored bcrypt/argon2 password hash of the user.'),
('permanent','Permanently Visible Item (permanent)','Always Show Even When Empty','Permanent','Keeps a menu folder visible (as disabled) even when the user has no access to any child items.'),
('phone','Phone (phone)','Phone Number (Landline)','Phone','Contact phone number of the user.'),
('placeholder','Input Placeholder (placeholder)','Empty Input Placeholder Text','Placeholder','Hint text displayed inside an empty input field (translatable).'),
('prec','Precision / Length (prec)','Maximum Type Length or Precision','Length / Prec.','Numeric length or precision of the data type in the system catalog.'),
('prec_syntax','Length Syntax (prec_syntax)','DDL Length / Precision Syntax','Length Syntax','Formatted length or precision in parentheses for DDL statements, e.g., (200) or (9,4).'),
('preferred_language','Default Organization Language (preferred_language)','Preferred Default Language','Default Language','Default UI and data language for newly created users and records in the organization.'),
('primary_asset_class','Primary Asset Class (primary_asset_class)','Primary Leaf Asset Class','Asset Class','Reference to the main terminal asset class (is_leaf = 1) used to classify and sort the asset.'),
('priority','Scale Priority (priority)','Scale Priority (0 = Primary)','Priority','0 = primary scale for data entry and default display; > 0 = secondary conversion scale for reporting.'),
('record_type','Record Type (record_type)','Record Type (A/L/D/H)','Rec. Type','Determines record kind: A = active approved, L = language mutation, D = draft/proposal, H = history.'),
('reduction_factor','Reduction Factor in % (reduction_factor)','Risk Reduction Factor (0–100%)','Reduction (%)','Specifies the residual risk reduction of a scenario when the control is applied (or the state weight).'),
('reduction_score','Combined Risk Reduction in % (reduction_score)','Risk Reduction from Controls (0–100%)','Reduction (%)','Calculated average risk reduction of the scenario from applied countermeasures in percent (0 to 100%).'),
('referenced_class','Referenced Class (referenced_class)','Linked Logical Class (Foreign Key)','Referenced Class','Reference to the target logical class in meta_class for selecting related records from a dropdown list.'),
('referenced_codetable','Referenced Codetable (referenced_codetable)','Linked System Codetable','Codetable','Codetable name in meta_codetable used to populate the dropdown select for this field.'),
('register_id','Company Registration ID (register_id)','Company Registration Number (ID)','Reg. ID','Official registration number of the organization in the commercial register.'),
('removed','Removed Record in Trash (removed)','Removed Record (In Trash)','Removed','Flag moving the record to the trash bin; automatically purged after days_in_trash days.'),
('request_date','Last Request Date (request_date)','Last HTTP Request Time','Request Date','Timestamp of the last web session activity for timeout tracking.'),
('request_ip','Request IP Address (request_ip)','Token Requester IP Address','Request IP','IP address from which the security token was requested.'),
('require_password_change','Require Password Change (require_password_change)','Force Password Change on Next Login','Change Password','Prompts the user to set a new password upon next login.'),
('residual_risk_min_financial','Financial Residual Risk Threshold (residual_risk_min_financial)','Negligible Annual Loss (Score 1)','Min. Res. (Fin.)','Financial value of annual loss in the organization currency considered negligible residual risk.'),
('residual_risk_min_score','Minimum Residual Risk (residual_risk_min_score)','Minimum Residual Risk Score','Min. Res. Risk','Lower bound of scenario residual risk score below which residual risk cannot drop even after implementing controls.'),
('residual_risk_score','Residual Risk in % (residual_risk_score)','Residual Risk After Controls (0–100%)','Res. Risk (%)','Calculated resulting residual risk score after accounting for countermeasures and minimum risk floor in percent (0 to 100%).'),
('responsible_user_uuid','Responsible Person (responsible_user_uuid)','Person Responsible for Countermeasure','Responsible Person','Reference to the user account of the person responsible for implementing and operating the countermeasure.'),
('reverse_link_def','Reverse Relationship (reverse_link_def)','Paired Reverse Relationship (meta_link_def)','Reverse Link','Reference to the paired definition of the opposite direction of the same relationship in meta_link_def.'),
('reverse_link_weight','Reverse Link Weight (reverse_link_weight)','Quantitative Weight of Reverse Direction','Reverse Weight','Optional numeric risk transfer weight or priority in the opposite direction of the link.'),
('right_profadmin_enabled','Professional Admin Mode (right_profadmin_enabled)','Enable Global Methodology Management','Profadmin Enabled','System switch for methodology administration mode.'),
('right_translate','Translation Right (right_translate)','Authorized to Save Translations','Translation Right','Authorizes the user to save language translations (globally if in the guarantee translator organization).'),
('risk_factor','Risk Factor / Threshold in % (risk_factor)','Minimum Risk Factor / Threshold (0–100%)','Risk Threshold (%)','Specifies the resulting risk score below which scenario risk cannot drop if the control is not implemented.'),
('role_editor','Class Editor Role (role_editor)','Role Authorized to Edit Class','Editor Role','Reference to the role authorized to edit records of this logical class.'),
('root_id','Path Root Node (root_id)','Initial Root Node of Graph Tree','Root (root_id)','Identifier of the top-level node (level = 0) from which the graph path originated.'),
('row_count','Row Count (row_count)','Data Row Count in Block','Row Count','Total number of data rows loaded for the table in the CSV import.'),
('row_id','Import Row Number (row_id)','Sequential Data Row Number','Row ID','Sequential number of the data row within the imported table.'),
('row_num','Row Number (row_num)','Sequential Row Number (0..1024)','Row Num.','Sequential number in the helper rowgenerator system table.'),
('rpo_hours','Recovery Point Objective in Hours (rpo_hours)','RPO – Max. Data Loss Window (Hours)','RPO (h)','Maximum acceptable age of lost data since the last valid backup in hours.'),
('rto_hours','Recovery Time Objective in Hours (rto_hours)','RTO – Max. Recovery Time (Hours)','RTO (h)','Maximum acceptable outage duration of the asset or service in hours.'),
('s','String Value (s)','Parsed String Item','String (s)','String item returned by f_string_list.'),
('scale','Assessment Scale (scale)','Assessment Scale','Scale','Reference to the assessment scale definition in the scale table.'),
('scale_type','Scale Type (scale_type)','Measured Quantity Type','Scale Type','Determines the quantity evaluated by this scale (Threat, Vulnerability, Impact, Resulting Risk).'),
('scenario_uuid','Assessed Risk Scenario (scenario_uuid)','Catalog Risk Scenario','Risk Scenario','Reference to the assessed risk scenario (event) in the scenario table.'),
('score_value','Score Value in % (score_value)','Calculation Score Value (0–100%)','Score (%)','Calculation score of the level in percent (0 to 100%). Must lie within the level interval and form an increasing sequence.'),
('selector','Token Public Selector (selector)','Token Identifier (selector)','Selector','Public part of the persistent login token used for fast database lookup.'),
('server_licence','Server Licence (server_licence)','Server Licence Identifier','Server Licence','Code or key of the server licence.'),
('servername','Server Name (servername)','Server Name','Server','Network name of the database or application server.'),
('session_log','Session Log Code (session_log)','Session Logging Flag','Session Log','Internal session logging flag.'),
('session_timeout','Session Timeout in Minutes (session_timeout)','Inactivity Timeout Before Logout (min)','Timeout (min)','Number of inactivity minutes before a web session automatically expires.'),
('severity','Message Severity (severity)','Severity Level (0=Info,1=OK,2=Warn,3=Err)','Severity','Numeric severity level: 0 = info, 1 = OK confirmation, 2 = warning, 3 = critical error.'),
('shortname','Short Name (shortname)','Short Name / Abbreviation','Short Name','Abbreviated label used in compact tables, matrices, and badges.'),
('show_empty','Show When Empty (show_empty)','Display Field Even When Empty','Show Empty','Indicates whether the field should be displayed in views even when its value is empty.'),
('smtp_port','SMTP Port (smtp_port)','SMTP Server Port Number','SMTP Port','Network port number of the SMTP server (e.g., 25, 465, 587, 2525).'),
('smtp_server','SMTP Server (smtp_server)','Outgoing SMTP Mail Server Address','SMTP Server','Hostname or IP address of the SMTP server used for sending system emails.'),
('sort_code','Sort Code (sort_code)','Sort Order (sort_code)','Sort Order','Code determining item order in lists and among tree siblings (recommended numbering by tens: 010, 020...).'),
('sort_order','Graph Sort Path (sort_order)','Zero-Padded Graph Traversal Key','Graph Order','Concatenated 5-digit key determining the unique branch order in f_resolve_link_diagram.'),
('source_code','Source Class / Page (source_code)','Source PHP Class / Page','Source (Class)','Name of the PHP class or page owning the text phrase (global_phrase for system-wide phrases).'),
('spid','SQL Server Process ID (spid)','SQL Server Process ID (@@SPID)','SPID','Server process identifier of the database connection (@@SPID).'),
('state_uuid','Countermeasure Implementation State (state_uuid)','Countermeasure Implementation State','Control State','Reference to the current implementation state in the countermeasure_state codetable.'),
('storage_object','Physical Storage (storage_object)','Physical Storage Table / View','Storage','Reference to the physical database table or view in meta_object storing data for this class.'),
('style','Row CSS Style (style)','Inline CSS Display Style','CSS Style','Additional inline CSS style for rendering the message row.'),
('svg_icon','Vector Icon (svg_icon)','Vector Icon (SVG)','Icon','SVG vector icon. Double-click or click Edit Icon to open the modal editor with XML syntax validation.'),
('sysadmin_email','Sysadmin Email (sysadmin_email)','Primary System Administrator Email','Sysadmin Email','Email address for emergency admin password recovery and system alerts.'),
('sysmsg_recipients','System Message Recipients (sysmsg_recipients)','Service Alert Recipient List','Alert Recipients','List of email addresses receiving automatic operational and error notifications.'),
('system_admin_pwd','Emergency Admin Password Hash (system_admin_pwd)','Break-Glass Admin Password Hash','Emergency Password','Bcrypt/argon2 password hash for emergency break-glass system administrator login.'),
('system_role','Minimum System Role (system_role)','Minimum Required Role (U/A/S/D)','Min. Role','Minimum effective role required for access: U = User, A = Org Admin, S = Sysadmin, D = Developer.'),
('table_id','Import Table ID (table_id)','Sequential Table Number in CSV','Table ID','Sequential number of the table block within the current CSV import.'),
('table_name','Table Name (table_name)','Physical Table Name','Table','Name of the database table in the dbo schema.'),
('table_type','Table Object Type (table_type)','Object Type in sys.objects','Table Type','Object type code in the system catalog (U = User Table, V = View).'),
('tabname','Table Name (tabname)','Table / View Name','Table','System name of the table or view in the database catalog.'),
('target_date','Target Implementation Date (target_date)','Planned Implementation Date','Target Date','Planned completion date for countermeasure implementation.'),
('target_object','Target Page (target_object)','Target Application Page (meta_object)','Target Page','Reference to the registered PHP page (object_type = P) opened when clicking a leaf menu item.'),
('target_url','External URL Link (target_url)','External or Fixed URL Address','External URL','Direct URL address for menu items pointing outside standard application pages.'),
('target_window','Link Target Window (target_window)','Browser Target Window (e.g., _blank)','Target Window','Specifies how the link opens (empty = same window, _blank = new browser tab).'),
('tax_id','Tax Identification Number (tax_id)','VAT / Tax ID of Organization','Tax ID','Tax identification number of the organization for billing and VAT purposes.'),
('template','Source Template (template)','Created from Template','Template','Reference to the template from which this record was cloned.'),
('thousand_separator','Thousands Separator (thousand_separator)','Thousands Separator Character','Thousands Sep.','Character used to separate thousands when formatting numbers (e.g., space or comma).'),
('threat_score','Threat Level Score in % (threat_score)','Threat Level / Likelihood (0–100%)','Threat (%)','Input rating of threat magnitude or scenario likelihood in percent (0 to 100%).'),
('threat_uuid','Causing Threat (threat_uuid)','Threat Triggering the Scenario','Threat','Reference to the threat from the threat catalog that causes this risk event (scenario).'),
('threshold_value','Lower Threshold in % (threshold_value)','Lower Interval Threshold (0–100%)','Threshold (%)','Lower bound of the level interval in percent (0 to 100%). Determines level ordering (the lowest level starts at 0).'),
('time_zone','Time Zone (time_zone)','Organization Time Zone','Time Zone','Time zone identifier of the organization (e.g., Europe/Prague).'),
('title','Title (title)','Title','Title','Display title or heading of the record.'),
('to_class','Target Link Class (to_class)','Target Class of Link (To)','To Class','Reference to the logical class in meta_class forming the destination side of the link.'),
('to_object','Target Link Object (to_object)','Target Linked Record (To)','To Object','Original UUID of the target record connected by the link.'),
('token_hash','Token Hash (token_hash)','Cryptographic Token Hash','Token Hash','SHA-256 hash of the one-time security token.'),
('token_purpose','Token Purpose (token_purpose)','Security Token Purpose','Token Purpose','Specifies the token usage context (PASSWORD_RESET, ACTIVATION, MFA).'),
('transfer_roles','Transfer Permissions (transfer_roles)','Transfer Edit Permissions Along Link','Transfer Roles','Indicates whether the link transfers edit permissions from the source object to the target object.'),
('translate','Supports Translation (translate)','Translatable Column (L records)','Translate','Indicates whether the column value can be translated into other languages via L records.'),
('translator_org','Translation Guarantee Org (translator_org)','Organization Guaranteeing Global Translation','Translator Org.','Organization whose translators are authorized to write translations of this language directly to system records (0x00).'),
('typename','Data Type (typename)','SQL Server Data Type Name','Data Type','Physical SQL data type of the column (e.g., varchar, int, uuid, bit).'),
('url_parameters','URL Parameters (url_parameters)','Additional GET URL Parameters','URL Parameters','Optional query string parameters appended to the target page URL (e.g., &hierarchy=...).'),
('user_account','User Account (user_account)','User Account','User','Reference to the user account.'),
('user_account_uuid','User Account (user_account_uuid)','User (Account UUID)','User (UUID)','Reference to the global user account in the user_account table.'),
('user_agent','Browser User-Agent (user_agent)','Browser & OS Identification (User-Agent)','User-Agent','User-Agent string identifying the user browser and operating system.'),
('user_name','Session User Name (user_name)','User Login Name','Login','Login name of the user in the active session.'),
('user_title_after','Title After Name (user_title_after)','Academic Title After Name','Title After','Academic title placed after the last name (e.g., Ph.D., MBA).'),
('user_title_before','Title Before Name (user_title_before)','Academic Title Before Name','Title Before','Academic or professional title placed before the first name.'),
('uuid','Row Primary Key (uuid)','Row UUID','UUID','Physical primary key of the specific row in the database table.'),
('uuidvalue','UUID Value (uuidvalue)','UUID Variable Value','UUID Value','UUID identifier stored in a request variable.'),
('valid_from','Valid From (valid_from)','Valid From','Valid From','Start date of record validity.'),
('valid_to','Valid To (valid_to)','Valid To','Valid To','End date of record validity (leave empty for unlimited validity).'),
('valid_today','Valid on Working Date (valid_today)','Valid Today','Valid','Flag indicating whether the record is valid as of the currently selected working date.'),
('value_code','Codetable Value Code (value_code)','Stored Value Code (value_code)','Value Code','Internal item code stored in the database when selected in a dropdown.'),
('varname','Variable Name (varname)','Request Variable Name','Variable','Name of the variable stored in request_variable.'),
('version','Version (version)','Version Identifier','Version','Version number or timestamp of the database, upgrade script, or data package.'),
('vulnerability_score','Vulnerability Score in % (vulnerability_score)','Asset Vulnerability to Scenario (0–100%)','Vulnerability (%)','Input rating of asset vulnerability to the scenario in percent (0 to 100%).'),
('who_created','Created By (who_created)','Created By (Session)','Created By','Reference to the login session of the user who originally created the record.'),
('who_modified','Last Modified By (who_modified)','Last Modified By (Session)','Modified By','Reference to the login session of the user who performed the last modification.'),
('working_date','Working Date (working_date)','Personal Working Date (Empty = Today)','Working Date','Effective date used to evaluate temporal validity of records in the user session.'),
('www_address','Website (www_address)','Website Address (URL)','Website','Official website URL of the organization.'),
('wwwsession','Web Session ID (wwwsession)','Browser Session Identifier (SID)','Web Session','Unique browser session identifier (PHP session_id).');

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en') v sys_global_columns
UPDATE l
SET l.caption = s.caption,
	l.caption_plural = s.caption,
	l.label = s.label,
	l.header = s.header,
	l.helptext = s.helptext,
	l.who_modified = @sys_owner,
	l.date_modified = GETDATE()
FROM meta_column l
JOIN meta_column a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
	AND a.parent_class = @c_class
JOIN @col_en s ON s.column_name = a.column_name
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT l.caption, l.caption_plural, l.label, l.header, l.helptext
	EXCEPT
	SELECT s.caption, s.caption, s.label, s.header, s.helptext
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en') v sys_global_columns
INSERT INTO meta_column (
	uuid, object_owner, original, record_type, approval_status, [language],
	parent_class, parent_order, sort_code, column_name, list_order,
	caption, caption_plural, description, label, header, helptext, placeholder,
	input_type, input_width, input_rows, max_length, css_class,
	translate, history, is_html, is_mandatory, is_url, is_computed,
	show_empty, hidden, customizable, ancestor, referenced_codetable, referenced_class,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
	s.caption, s.caption, NULL, s.label, s.header, s.helptext, NULL,
	a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
	a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
	a.show_empty, a.hidden, a.customizable, a.ancestor, a.referenced_codetable, a.referenced_class,
	a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_column a
JOIN @col_en s ON s.column_name = a.column_name
WHERE a.parent_class = @c_class
  AND a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_column l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'en'
  );

-- 3. Specifický anglický překlad pro sloupec is_leaf na třídě hierarchy
UPDATE l
SET l.caption = 'Standalone Hierarchy / Tag Set (is_leaf)',
	l.label = 'Standalone Hierarchy (is_leaf)',
	l.header = 'Hierarchy',
	l.helptext = 'Check (1) for a terminal hierarchy or tag set definition into which you will insert items. Uncheck (0) only for a parent organizational folder in this registry.',
	l.date_modified = GETDATE()
FROM meta_column l
JOIN meta_column a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
	AND a.parent_class = @cls_hierarchy
	AND a.column_name = 'is_leaf'
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01');

INSERT INTO meta_column (
	uuid, object_owner, original, record_type, approval_status, [language],
	parent_class, parent_order, sort_code, column_name, list_order,
	caption, caption_plural, label, header, helptext,
	ancestor, is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
	'Standalone Hierarchy / Tag Set (is_leaf)',
	'Standalone Hierarchy / Tag Set (is_leaf)',
	'Standalone Hierarchy (is_leaf)',
	'Hierarchy',
	'Check (1) for a terminal hierarchy or tag set definition into which you will insert items. Uncheck (0) only for a parent organizational folder in this registry.',
	a.ancestor, a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_column a
WHERE a.parent_class = @cls_hierarchy
  AND a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.column_name = 'is_leaf'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_column l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'en'
  );
GO