/* =============================================================================
 * Verze: 2026-11-07 13:15
 * Soubor: fillup_meta_column_en.sql
 * Účel:   Hromadné idempotentní nastavení výchozích anglických překladů sloupců
 *         (jazyk 'en', record_type = 'L') pro globální slovník sys_global_columns
 *         (a specifické lokální overridy) v tabulce meta_column (object_owner = 0x00)
 *         jedním příkazem UPDATE a jedním INSERT.
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
-- 1. Standard RAC, SSC, temporal, and audit columns
('uuid',                        'Row Primary Key (uuid)',                          'Row UUID',                               'UUID',                   'Physical primary key of the specific row in the database table.'),
('object_owner',                'Object Owner (object_owner)',                     'Owner (Organization)',                   'Owner',                  'Identifier of the owning organization (tenant); 0x00 denotes a system record.'),
('original',                    'Logical Record Identifier (original)',            'Original (Object UUID)',                 'Original',               'Shared logical identifier of the record across language versions, drafts, and tenant overrides.'),
('record_type',                 'Record Type (record_type)',                       'Record Type (A/L/D/H)',                  'Rec. Type',              'Determines record kind: A = active approved, L = language mutation, D = draft/proposal, H = history.'),
('approval_status',             'Approval Status (approval_status)',               'Approval Status (A/D/F/R)',              'Approval',               'SSC lifecycle status: A = approved, D = working draft, F = forwarded for approval, R = rejected/returned.'),
('draft_author',                'Draft Author (draft_author)',                     'Draft Author',                           'Draft Author',           'User account identifier of the author of the working draft or proposed change.'),
('approval_note',               'Approval Note (approval_note)',                   'Approver Note / Rejection Reason',       'Approval Note',          'Accompanying note for the proposal or the approver reason when returning a draft for revision.'),
('inactive',                    'Inactive Record (inactive)',                      'Inactive (Deactivated)',                 'Inactive',               'Flag temporarily or permanently disabling the record from standard selection without deleting it.'),
('removed',                     'Removed Record in Trash (removed)',               'Removed Record (In Trash)',              'Removed',                'Flag moving the record to the trash bin; automatically purged after days_in_trash days.'),
('language',                    'Record Language (language)',                      'Language',                               'Language',               'Two-letter ISO language code of the record or language mutation (e.g., cs, en, sk, de).'),
('valid_from',                  'Valid From (valid_from)',                         'Valid From',                             'Valid From',             'Start date of record validity.'),
('valid_to',                    'Valid To (valid_to)',                             'Valid To',                               'Valid To',               'End date of record validity (leave empty for unlimited validity).'),
('valid_today',                 'Valid on Working Date (valid_today)',             'Valid Today',                            'Valid',                  'Flag indicating whether the record is valid as of the currently selected working date.'),
('is_template',                 'Template Flag (is_template)',                     'Acts as Template',                       'Is Template',            'Indicates whether this record serves as a master template for cloning.'),
('template',                    'Source Template (template)',                      'Created from Template',                  'Template',               'Reference to the template from which this record was cloned.'),
('import_origin',               'Import Origin (import_origin)',                   'Record Import Origin',                   'Import Origin',          'Identification of the external source, package, or author during bulk data import (soft audit).'),
('date_created',                'Date Created (date_created)',                     'Created Date & Time',                    'Created',                'Exact date and time when the record was initially created.'),
('who_created',                 'Created By (who_created)',                        'Created By (Session)',                   'Created By',             'Reference to the login session of the user who originally created the record.'),
('date_modified',               'Date Modified (date_modified)',                   'Last Modified Date & Time',              'Modified',               'Exact date and time of the last modification of the record or its language mutation.'),
('who_modified',                'Last Modified By (who_modified)',                 'Last Modified By (Session)',             'Modified By',            'Reference to the login session of the user who performed the last modification.'),

-- 2. Shared identification, presentation, and tree columns
('builtin_code',                'Unique Code (builtin_code)',                      'Record Code (builtin_code)',             'Code',                   'Unique technical identifier used for deterministic original calculation (auto-derived from name on new records).'),
('external_code',               'External Code (external_code)',                   'External Code (for mapping)',            'Ext. Code',              'Optional identifier for mapping the record with external systems, standards, or catalogs.'),
('caption',                     'Display Caption (caption)',                       'Name / Caption',                         'Name',                   'Primary display name of the item (supports translation into other languages).'),
('caption_plural',              'Plural Caption (caption_plural)',                 'Plural Name (List Heading)',             'Plural Name',            'Plural form of the name displayed as the master list heading in the left panel.'),
('shortname',                   'Short Name (shortname)',                          'Short Name / Abbreviation',              'Short Name',             'Abbreviated label used in compact tables, matrices, and badges.'),
('title',                       'Title (title)',                                   'Title',                                  'Title',                  'Display title or heading of the record.'),
('name',                        'Name (name)',                                     'Name',                                   'Name',                   'Technical or display name of the item.'),
('description',                 'Description (description)',                       'Detailed Description',                   'Description',            'Detailed description of the purpose and meaning of the item (supports Markdown / HTML).'),
('description_text',            'Description (description_text)',                  'Detailed Description',                   'Description',            'Detailed methodological or domain description of the item (supports Markdown / HTML).'),
('helptext',                    'Help Text (helptext)',                            'Help Text (Tooltip / Guidance)',         'Help Text',              'Methodological help or user instructions displayed for the item.'),
('help_text',                   'Help Text (help_text)',                           'Help Text (Tooltip / Guidance)',         'Help Text',              'Methodological help or user instructions displayed for the item.'),
('note',                        'Note (note)',                                     'Note',                                   'Note',                   'Additional internal comment or note on the record (supports Markdown / HTML).'),
('editor_note',                 'AI Context Note (editor_note)',                   'Translator & AI Context Note',           'AI Context',             'Semantic clarification of the record meaning for accurate human and AI translation (not translated).'),
('svg_icon',                    'Vector Icon (svg_icon)',                          'Vector Icon (SVG)',                      'Icon',                   'SVG vector icon. Double-click or click Edit Icon to open the modal editor with XML syntax validation.'),
('color_code',                  'Color Code (color_code)',                         'Color (HEX / CSS Code)',                 'Color',                  'Color code (e.g., #16A34A) for visual highlighting of the item or scale level.'),
('css_class',                   'CSS Class (css_class)',                           'Additional CSS Class',                   'CSS Class',              'Optional CSS class for custom styling of the element or button in the UI.'),
('parent_uuid',                 'Parent Tree Node (parent_uuid)',                  'Parent Folder / Item',                   'Parent Node',            'Reference to the parent node in the tree hierarchy (empty means a top-level root item).'),
('sort_code',                   'Sort Code (sort_code)',                           'Sort Order (sort_code)',                 'Sort Order',             'Code determining item order in lists and among tree siblings (recommended numbering by tens: 010, 020...).'),
('is_leaf',                     'Leaf Node (is_leaf)',                             'Leaf Node (Terminal Item)',              'Leaf',                   'Check for a terminal leaf item. Uncheck for an internal folder node that will contain child items.'),
('is_default',                  'Default Item (is_default)',                       'Default Value (Preselected)',            'Default',                'Check for the item that should be automatically preselected when creating a new record.'),
('is_final',                    'Final Record without Override (is_final)',        'Disallow Tenant Override (is_final)',    'Final',                  'If checked (1), client organizations cannot override functional attributes of the record (only translations are allowed).'),
('is_protected',                'Protected Technical Logic (is_protected)',        'Protected System Element (is_protected)','Protected',              'Restricts client modifications of purely technical and architectural properties of the record.'),
('builtin',                     'Built-in Record (builtin)',                       'Built-in System Record',                 'Built-in',               'Flag indicating a standard built-in record supplied with the system.'),
('instance_class_name',         'Instance Class Name (instance_class_name)',       'Object Instance Class',                  'Instance Class',         'Specific application class designation for instances of this category.'),
('editor_role_uuid',            'Editor Role (editor_role_uuid)',                  'Role Authorized to Edit',                'Editor Role',            'Reference to the role authorized to edit records in this hierarchy branch (inherited by child nodes).'),

-- 3. Metadata columns (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def)
('object_type',                 'System Object Type (object_type)',                'Object Type (T/V/F/P/C/M)',              'Obj. Type',              'Object category: T = Table, V = View, F = Function, P = PHP Page/Class, C = Global Column Dictionary, M = Module.'),
('module',                      'Application Module (module)',                     'Licence Module',                         'Module',                 'Code of the application or licensing module to which the object or phrase belongs.'),
('system_role',                 'Minimum System Role (system_role)',               'Minimum Required Role (U/A/S/D)',        'Min. Role',              'Minimum effective role required for access: U = User, A = Org Admin, S = Sysadmin, D = Developer.'),
('class_name',                  'Technical Class Name (class_name)',               'Logical Class Code (class_name)',        'Class Code',             'Unique system identifier of the logical class in the STI architecture.'),
('storage_object',              'Physical Storage (storage_object)',               'Physical Storage Table / View',          'Storage',                'Reference to the physical database table or view in meta_object storing data for this class.'),
('ancestor_class',              'Ancestor Class for Inheritance (ancestor_class)', 'Parent Class (STI Inheritance)',         'Ancestor Class',         'Reference to the parent logical class from which this class inherits columns and default behavior.'),
('days_in_trash',               'Days in Trash (days_in_trash)',                   'Trash Retention Days Before Purge',      'Days in Trash',          'Number of days removed records (removed = 1) are kept in the trash before automatic physical deletion (0 = never purge).'),
('role_editor',                 'Class Editor Role (role_editor)',                 'Role Authorized to Edit Class',          'Editor Role',            'Reference to the role authorized to edit records of this logical class.'),
('parent_class',                'Belongs to Class (parent_class)',                 'Parent Logical Class',                   'Class',                  'Structural link defining which logical class this column belongs to.'),
('parent_order',                'Column Table Order (parent_order)',               'Column Order in Class',                  'Col. Order',             'Numeric column order derived from the physical structure of the database table.'),
('column_name',                 'Technical Column Name (column_name)',             'Technical Column Name',                  'Column',                 'Exact database identifier of the column in the storage table or view.'),
('list_order',                  'Master List Order (list_order)',                  'Column Order in Master List',            'List Order',             'If set to a positive integer, the column is displayed in the left master list table in this order.'),
('label',                       'Form Field Label (label)',                        'Detail Field Label (label)',             'Label',                  'Label text displayed to the left of the input control in the detail edit form.'),
('header',                      'Table Column Header (header)',                    'List Column Header (header)',            'Header',                 'Short column heading used in summary tables and master lists.'),
('placeholder',                 'Input Placeholder (placeholder)',                 'Empty Input Placeholder Text',           'Placeholder',            'Hint text displayed inside an empty input field (translatable).'),
('input_type',                  'Input Control Type (input_type)',                 'Form Input Type',                        'Input Type',             'HTML control type in the detail form (text, textarea, number, date, checkbox).'),
('input_width',                 'Input Width (input_width)',                       'Input Field Width (CSS)',                'Input Width',            'CSS width of the form control in the detail panel (e.g., 100%, 180px, auto).'),
('input_rows',                  'Textarea Rows (input_rows)',                      'Number of Rows (for textarea)',          'Rows',                   'Height of a multi-line text field (textarea) in visible rows.'),
('max_length',                  'Maximum Text Length (max_length)',                'Maximum Character Count',                'Max. Length',            'Maximum allowed number of characters in a text input matching the database definition.'),
('translate',                   'Supports Translation (translate)',                'Translatable Column (L records)',        'Translate',              'Indicates whether the column value can be translated into other languages via L records.'),
('history',                     'Track History (history)',                         'Store Historical Versions (H)',          'History',                'Indicates whether changing the column value creates a historical snapshot record (type H).'),
('is_html',                     'Formatted Text Markdown/HTML (is_html)',          'Formatted Rich Text (Markdown / HTML)',  'Rich Text',              'Enables formatted rich text support with preview and modal Toast UI Editor (Markdown / HTML).'),
('is_mandatory',                'Mandatory Field (is_mandatory)',                  'Mandatory Field (Required)',             'Mandatory',              'Marks a field that must be filled in before saving the form.'),
('is_url',                      'Contains URL Address (is_url)',                   'Field Contains URL Link',                'Is URL',                 'Validates and formats the input field as a web URL address.'),
('is_computed',                 'Computed Column (is_computed)',                   'Computed Column (Read-Only)',            'Computed',               'The column is calculated by the database or application and is locked as read-only in forms.'),
('show_empty',                  'Show When Empty (show_empty)',                    'Display Field Even When Empty',          'Show Empty',             'Indicates whether the field should be displayed in views even when its value is empty.'),
('hidden',                      'Hidden Column (hidden)',                          'Hide Field in Standard Form',            'Hidden',                 'Technical column hidden from standard detail edit forms.'),
('customizable',                'Allow Customization (customizable)',              'Allow Tenant Customization',             'Customizable',           'Indicates whether a client organization (tenant) may customize properties of this column.'),
('ancestor',                    'Column Ancestor (ancestor)',                      'Ancestor in Global Column Dictionary',   'Ancestor Column',        'Reference to the base column definition in sys_global_columns from which unspecified properties are inherited.'),
('referenced_codetable',        'Referenced Codetable (referenced_codetable)',     'Linked System Codetable',                'Codetable',              'Codetable name in meta_codetable used to populate the dropdown select for this field.'),
('referenced_class',            'Referenced Class (referenced_class)',             'Linked Logical Class (Foreign Key)',     'Referenced Class',       'Reference to the target logical class in meta_class for selecting related records from a dropdown list.'),
('target_object',               'Target Page (target_object)',                     'Target Application Page (meta_object)',  'Target Page',            'Reference to the registered PHP page (object_type = P) opened when clicking a leaf menu item.'),
('url_parameters',              'URL Parameters (url_parameters)',                 'Additional GET URL Parameters',          'URL Parameters',         'Optional query string parameters appended to the target page URL (e.g., &hierarchy=...).'),
('target_url',                  'External URL Link (target_url)',                  'External or Fixed URL Address',          'External URL',           'Direct URL address for menu items pointing outside standard application pages.'),
('target_window',               'Link Target Window (target_window)',              'Browser Target Window (e.g., _blank)',   'Target Window',          'Specifies how the link opens (empty = same window, _blank = new browser tab).'),
('permanent',                   'Permanently Visible Item (permanent)',            'Always Show Even When Empty',            'Permanent',              'Keeps a menu folder visible (as disabled) even when the user has no access to any child items.'),
('source_code',                 'Source Class / Page (source_code)',               'Source PHP Class / Page',                'Source (Class)',         'Name of the PHP class or page owning the text phrase (global_phrase for system-wide phrases).'),
('codetable_name',              'Codetable Name (codetable_name)',                 'Codetable Code (codetable_name)',        'Codetable Code',         'Technical identifier of the codetable group in meta_codetable.'),
('value_code',                  'Codetable Value Code (value_code)',               'Stored Value Code (value_code)',         'Value Code',             'Internal item code stored in the database when selected in a dropdown.'),
('link_code',                   'Link Type Code (link_code)',                      'Technical Link Type Code',               'Link Code',              'Unique system identifier of the link definition in meta_link_def.'),
('from_class',                  'Source Link Class (from_class)',                  'Source Class of Link (From)',            'From Class',             'Reference to the logical class in meta_class forming the origin side of the link.'),
('to_class',                    'Target Link Class (to_class)',                    'Target Class of Link (To)',              'To Class',               'Reference to the logical class in meta_class forming the destination side of the link.'),
('caption_forward',             'Forward Link Caption (caption_forward)',          'Link Caption from Source to Target',     'Forward Caption',        'Verbal description of the link from the source perspective (e.g., "Affects" or "Contains").'),
('caption_backward',            'Backward Link Caption (caption_backward)',        'Link Caption from Target to Source',     'Backward Caption',       'Verbal description of the link from the target perspective (e.g., "Is Affected By" or "Belongs To").'),
('is_multiple',                 'Multiple Link (is_multiple)',                     'Allow Linking Multiple Objects (M:N)',   'Multiple',               'Indicates whether multiple target records of this type can be linked to a single source record.'),
('transfer_roles',              'Transfer Permissions (transfer_roles)',           'Transfer Edit Permissions Along Link',   'Transfer Roles',         'Indicates whether the link transfers edit permissions from the source object to the target object.'),
('link_weight_enabled',         'Link Weight Enabled (link_weight_enabled)',       'Track Numeric Weight on Link',           'Weight Enabled',         'Enables entering a quantitative weight or priority directly on the link instance in the link table.'),
('table_name',                  'Table Name (table_name)',                         'Physical Table Name',                    'Table',                  'Name of the database table in the dbo schema.'),
('key1_column',                 'First Key Column (key1_column)',                  '1st Original Key Column',                '1st Key',                'Name of the first column used to calculate the deterministic original identifier.'),
('key2_column',                 'Second Key Column (key2_column)',                 '2nd Original Key Column',                '2nd Key',                'Name of the optional second column used to calculate the deterministic original identifier.'),

-- 4. CRMM module columns (hierarchies, scales, scenarios, countermeasures, links)
('multiple',                    'Multiple Assignment (multiple)',                  'Allow Assigning Multiple Items',         'Multiple Items',         'Indicates whether a target record can be linked to multiple items from this hierarchy simultaneously.'),
('leaf_only',                   'Leaf Nodes Only (leaf_only)',                     'Allow Links to Leaf Nodes Only',         'Leaves Only',            'Indicates whether target records may be linked exclusively to terminal leaf nodes (is_leaf = 1) of this hierarchy.'),
('hierarchy',                   'Parent Hierarchy (hierarchy)',                    'Secondary Hierarchy / Tag Set',          'Hierarchy',              'Reference to the secondary hierarchy or tag set definition in the hierarchy table.'),
('scale',                       'Assessment Scale (scale)',                        'Assessment Scale',                       'Scale',                  'Reference to the assessment scale definition in the scale table.'),
('scale_type',                  'Scale Type (scale_type)',                         'Measured Quantity Type',                 'Scale Type',             'Determines the quantity evaluated by this scale (Threat, Vulnerability, Impact, Resulting Risk).'),
('priority',                    'Scale Priority (priority)',                       'Scale Priority (0 = Primary)',           'Priority',               '0 = primary scale for data entry and default display; > 0 = secondary conversion scale for reporting.'),
('initial_levels',              'Initial Level Count (initial_levels)',            'Number of Levels (to Generate)',         'Level Count',            'Number of even levels (2 to 20) automatically generated in the 0 to 100% range when first saving a new scale.'),
('threshold_value',             'Lower Threshold in % (threshold_value)',          'Lower Interval Threshold (0–100%)',      'Threshold (%)',          'Lower bound of the level interval in percent (0 to 100%). Determines level ordering (the lowest level starts at 0).'),
('score_value',                 'Score Value in % (score_value)',                  'Calculation Score Value (0–100%)',       'Score (%)',              'Calculation score of the level in percent (0 to 100%). Must lie within the level interval and form an increasing sequence.'),
('reduction_factor',            'Reduction Factor in % (reduction_factor)',        'Risk Reduction Factor (0–100%)',         'Reduction (%)',          'Specifies the residual risk reduction of a scenario when the control is applied (or the state weight).'),
('risk_factor',                 'Risk Factor / Threshold in % (risk_factor)',      'Minimum Risk Factor / Threshold (0–100%)','Risk Threshold (%)',    'Specifies the resulting risk score below which scenario risk cannot drop if the control is not implemented.'),
('default_threat_score',        'Default Threat Score (default_threat_score)',     'Default Threat Level (Score)',           'Default Score',          'Default numeric threat rating pre-filled during scenario analysis.'),
('threat_uuid',                 'Causing Threat (threat_uuid)',                    'Threat Triggering the Scenario',         'Threat',                 'Reference to the threat from the threat catalog that causes this risk event (scenario).'),
('asset_class_uuid',            'Target Asset Class (asset_class_uuid)',           'Asset Class for Impact Assessment',      'Asset Class',            'Reference to the asset class in asset_class on which the impact of this scenario is evaluated.'),
('primary_asset_class',         'Primary Asset Class (primary_asset_class)',       'Primary Leaf Asset Class',               'Asset Class',            'Reference to the main terminal asset class (is_leaf = 1) used to classify and sort the asset.'),
('residual_risk_min_score',     'Minimum Residual Risk (residual_risk_min_score)', 'Minimum Residual Risk Score',            'Min. Res. Risk',         'Lower bound of scenario residual risk score below which residual risk cannot drop even after implementing controls.'),
('link_def',                    'Link Definition (link_def)',                      'Link Type (meta_link_def)',              'Link Type',              'Reference to the link type definition in meta_link_def.'),
('from_object',                 'Source Link Object (from_object)',                'Source Linked Record (From)',            'From Object',            'Original UUID of the source record connected by the link.'),
('to_object',                   'Target Link Object (to_object)',                  'Target Linked Record (To)',              'To Object',              'Original UUID of the target record connected by the link.'),
('ancestor_link',               'Ancestor Source Link (ancestor_link)',            'Source Link for Hierarchy Inheritance',  'Ancestor Link',          'Identifier of the parent link in the link table from which this link was derived by hierarchy inheritance (0x00 = direct link).'),
('link_weight',                 'Link Numeric Weight (link_weight)',               'Quantitative Link Weight / Priority',    'Link Weight',            'Numeric value expressing risk transfer weight or priority of the specific link instance.'),
('is_derived',                  'Derived Link (is_derived)',                       'Link Materialized by Inheritance',       'Derived',                'Flag indicating that the link was automatically materialized by inheritance from a parent hierarchy node.'),

-- 5. Organizations, licences, CRMM settings, and users
('login_domain',                'SSO Login Domain (login_domain)',                 'Domain for SSO Login',                   'SSO Domain',             'Internet domain of the organization used to automatically detect the home tenant during SSO authentication.'),
('register_id',                 'Company Registration ID (register_id)',           'Company Registration Number (ID)',       'Reg. ID',                'Official registration number of the organization in the commercial register.'),
('tax_id',                      'Tax Identification Number (tax_id)',              'VAT / Tax ID of Organization',           'Tax ID',                 'Tax identification number of the organization for billing and VAT purposes.'),
('invoice_info',                'Billing Information (invoice_info)',              'Billing & Bank Account Details',         'Billing Info',           'Additional billing details, bank account numbers, or invoice notes.'),
('address_name',                'Address Name (address_name)',                     'Official Name in Registered Address',    'Address Name',           'Company name or supplement used in the postal address.'),
('address_street',              'Street & Number (address_street)',                'Street and Building Number',             'Street',                 'Street and building number of the organization headquarters.'),
('address_city',                'City / Town (address_city)',                      'City / Municipality',                    'City',                   'City or municipality of the organization headquarters.'),
('address_zip',                 'Postal / ZIP Code (address_zip)',                 'Postal / ZIP Code',                      'ZIP Code',               'Postal code of the headquarters address.'),
('address_state',               'Country / State (address_state)',                 'Country / State',                        'Country',                'Country where the organization headquarters is located.'),
('www_address',                 'Website (www_address)',                           'Website Address (URL)',                  'Website',                'Official website URL of the organization.'),
('preferred_language',          'Default Organization Language (preferred_language)','Preferred Default Language',           'Default Language',       'Default UI and data language for newly created users and records in the organization.'),
('currency_unit',               'Currency Unit (currency_unit)',                   'Currency Unit Used',                     'Currency',               'Currency unit label used for financial impact and risk valuation (e.g., kCZK, EUR).'),
('currency_digits',             'Currency Decimal Places (currency_digits)',       'Number of Currency Decimal Places',      'Currency Decimals',      'Number of decimal places displayed for financial amounts.'),
('currency_before',             'Currency Before Amount (currency_before)',        'Display Currency Symbol Before Number',  'Currency Before',        'If checked, the currency symbol is placed before the numeric amount (e.g., € 100).'),
('format_date',                 'Date Format (format_date)',                       'Date Display Format',                    'Date Format',            'Formatting mask for displaying calendar dates in the UI (e.g., dd.MM.yyyy or yyyy-MM-dd).'),
('format_time',                 'Time Format (format_time)',                       'Time Display Format',                    'Time Format',            'Formatting mask for displaying time values in the UI (e.g., HH:mm:ss).'),
('time_zone',                   'Time Zone (time_zone)',                           'Organization Time Zone',                 'Time Zone',              'Time zone identifier of the organization (e.g., Europe/Prague).'),
('thousand_separator',          'Thousands Separator (thousand_separator)',        'Thousands Separator Character',          'Thousands Sep.',         'Character used to separate thousands when formatting numbers (e.g., space or comma).'),
('decimal_separator',           'Decimal Separator (decimal_separator)',           'Decimal Separator Character',            'Decimal Sep.',           'Character separating integer and fractional parts of a number (comma or dot).'),
('export_delimiter',            'CSV Field Delimiter (export_delimiter)',          'Default Delimiter for CSV Export',       'CSV Delimiter',          'Character separating columns in exported CSV files (semicolon ; by default).'),
('max_threat_score',            'Maximum Threat Score (max_threat_score)',         'Upper Limit of Threat Score',            'Max. Threat',            'Highest allowed score value when assessing threat level in the organization.'),
('max_vulnerability_score',     'Maximum Vulnerability Score (max_vulnerability_score)', 'Upper Limit of Vulnerability Score','Max. Vulnerability',    'Highest allowed score value when assessing vulnerability in the organization.'),
('max_impact_score',            'Maximum Impact Score (max_impact_score)',         'Upper Limit of Impact Score',            'Max. Impact',            'Highest allowed score value when assessing impact severity in the organization.'),
('max_risk_score',              'Maximum Risk Score (max_risk_score)',             'Upper Limit of Resulting Risk Score',    'Max. Risk',              'Highest resulting risk score value in the organization methodology.'),
('max_impact_financial',        'Financial Value of Max Impact (max_impact_financial)', 'Financial Expression of Highest Impact', 'Max. Impact (Fin.)','Financial amount in the organization currency corresponding to the highest impact level.'),
('residual_risk_min_financial', 'Financial Residual Risk Threshold (residual_risk_min_financial)', 'Negligible Annual Loss (Score 1)', 'Min. Res. (Fin.)', 'Financial value of annual loss in the organization currency considered negligible residual risk.'),
('evaluation_method',           'Risk Evaluation Method (evaluation_method)',      'Selected CRMM Evaluation Method',        'Evaluation Method',      'Code of the methodology or calculation model used for risk evaluation.'),
('logo_data',                   'Logo Binary Data (logo_data)',                    'Organization Logo File Data',            'Logo (Data)',            'Binary content of the organization logo image file.'),
('logo_filename',               'Logo Filename (logo_filename)',                   'Original Logo Filename',                 'Logo Filename',          'Filename of the uploaded organization logo image.'),
('logo_mime_type',              'Logo MIME Type (logo_mime_type)',                 'Logo Image Format (MIME)',               'Logo MIME Type',         'Internet media type of the uploaded logo (e.g., image/png, image/svg+xml).'),
('licence_state',               'Licence State (licence_state)',                   'Licence Lifecycle State',                'Licence State',          'Licence lifecycle state: DRAFT, APPROVED (triggers activation), PROCESSED (active), REJECTED.'),
('licence_level',               'Licence Level (licence_level)',                   'Organization Licence Level',             'Licence Level',          'Organization permission tier: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
('login_disabled',              'Disable Login (login_disabled)',                  'Disable Login for Organization',         'Login Disabled',         'If checked, no user can log into the context of this organization.'),
('organization_uuid',           'Target Organization (organization_uuid)',         'Organization (UUID)',                    'Organization',           'Reference to the original identifier of the organization in the organization table.'),
('organization',                'Active Organization (organization)',              'Organization',                           'Organization',           'Identifier of the active organization in the session or view.'),
('organization_name',           'Organization Name (organization_name)',           'Organization Name',                      'Organization Name',      'Display name of the organization.'),
('organization_note',           'Licence Note (organization_note)',                'Internal Note on Organization Licence',  'Licence Note',           'Additional note by the licence issuer regarding the licensed organization.'),
('server_licence',              'Server Licence (server_licence)',                 'Server Licence Identifier',              'Server Licence',         'Code or key of the server licence.'),
('authorization_code',          'Authorization Code (authorization_code)',         'Activation Authorization Code',          'Auth. Code',             'Unique identifier for authorizing the licence request.'),
('activation_date',             'Activation Date (activation_date)',               'Licence Activation Date',                'Activated On',           'Date when the licence was processed and the organization activated.'),
('admin_login',                 'Organization Admin Login (admin_login)',          'Initial Administrator Login',            'Admin Login',            'Login name of the initial administrator of the newly created organization.'),
('admin_first_name',            'Admin First Name (admin_first_name)',             'Administrator First Name',               'Admin First Name',       'First name of the initial organization administrator.'),
('admin_last_name',             'Admin Last Name (admin_last_name)',               'Administrator Last Name',                'Admin Last Name',        'Last name of the initial organization administrator.'),
('admin_email',                 'Admin Email (admin_email)',                       'Organization Administrator Email',       'Admin Email',            'Contact email address of the organization administrator.'),
('digital_signature',           'Digital Signature (digital_signature)',           'Verification Digital Signature',         'Signature',              'Binary checksum or digital signature of the record.'),
('login_name',                  'Login Name (login_name)',                         'User Login Name',                        'Login',                  'Unique user login name in the system.'),
('email',                       'Email Address (email)',                           'Email Address',                          'Email',                  'Contact and authentication email address of the user.'),
('password_hash',               'Password Hash (password_hash)',                   'Cryptographic Password Hash',            'Password Hash',          'Securely stored bcrypt/argon2 password hash of the user.'),
('allow_local_login',           'Allow Local Login (allow_local_login)',           'Allow Username & Password Login',        'Local Login',            'Indicates whether the user may log in using a local password (if disabled, SSO is required).'),
('is_system_admin',             'System Administrator (is_system_admin)',          'Global Sysadmin Role (S)',               'Sysadmin',               'Authorizes the user to enter the system organization (0x00) and administer the entire server.'),
('is_developer',                'System Developer (is_developer)',                 'Global Developer Role (D)',              'Developer',              'Authorizes the user to modify system metadata, structures, and developer packages.'),
('require_password_change',     'Require Password Change (require_password_change)','Force Password Change on Next Login',   'Change Password',        'Prompts the user to set a new password upon next login.'),
('failed_login_attempts',       'Failed Login Attempts (failed_login_attempts)',   'Consecutive Failed Login Attempts',      'Failed Attempts',        'Counter of consecutive invalid password attempts (locks account temporarily when threshold is reached).'),
('locked_until',                'Locked Until (locked_until)',                     'Account Temporarily Locked Until',       'Locked Until',           'Date and time until which login is blocked following repeated failed password attempts.'),
('last_login_date',             'Last Login Date (last_login_date)',               'Last Login Date & Time',                 'Last Login',             'Timestamp of the user last successful login.'),
('last_password_change',        'Last Password Change (last_password_change)',     'Last Password Change Date & Time',       'Password Changed',       'Timestamp of the last password change for the user account.'),
('mfa_enabled',                 'Multi-Factor Authentication (mfa_enabled)',       'Require Multi-Factor Authentication',    'MFA Enabled',            'Flag enabling multi-factor authentication for the user account.'),
('mfa_secret',                  'MFA Secret Key (mfa_secret)',                     'Cryptographic MFA Secret Key',           'MFA Secret',             'Internal secret key used to generate one-time TOTP codes.'),
('last_login_organization',     'Last Login Organization (last_login_organization)','Last Visited Organization',             'Last Organization',      'Reference to the organization in which the user worked during their last login.'),
('user_title_before',           'Title Before Name (user_title_before)',           'Academic Title Before Name',             'Title Before',           'Academic or professional title placed before the first name.'),
('first_name',                  'First Name (first_name)',                         'First Name',                             'First Name',             'Given first name of the person.'),
('last_name',                   'Last Name (last_name)',                           'Last Name / Surname',                    'Last Name',              'Family surname of the person.'),
('user_title_after',            'Title After Name (user_title_after)',             'Academic Title After Name',              'Title After',            'Academic title placed after the last name (e.g., Ph.D., MBA).'),
('phone',                       'Phone (phone)',                                   'Phone Number (Landline)',                'Phone',                  'Contact phone number of the user.'),
('mobile',                      'Mobile Phone (mobile)',                           'Mobile Phone Number',                    'Mobile',                 'Mobile phone number of the user.'),
('user_account_uuid',           'User Account (user_account_uuid)',                'User (Account UUID)',                    'User (UUID)',            'Reference to the global user account in the user_account table.'),
('user_account',                'User Account (user_account)',                     'User Account',                           'User',                   'Reference to the user account.'),
('is_orgadmin',                 'Organization Administrator (is_orgadmin)',        'Administrator of This Organization (A)', 'Org. Admin',             'Authorizes the user to manage users, access requests, and settings within this organization.'),
('last_role',                   'Last Selected Role (last_role)',                  'Last Used Role (U/A/S/D)',               'Last Role',              'Last effective role used by the user in this organization.'),
('right_translate',             'Translation Right (right_translate)',             'Authorized to Save Translations',        'Translation Right',      'Authorizes the user to save language translations (globally if in the guarantee translator organization).'),
('department_name',             'Department / Unit (department_name)',             'Department / Organizational Unit',       'Department',             'Name of the department or unit to which the user is assigned in the organization.'),
('job_title',                   'Job Title (job_title)',                           'Job Title / Position',                   'Job Title',              'Job title or position of the user within the organization.'),
('manager_uuid',                'Line Manager (manager_uuid)',                     'Direct Line Manager',                    'Manager',                'Reference to the user account of the user direct manager in the organization.'),
('working_date',                'Working Date (working_date)',                     'Personal Working Date (Empty = Today)',  'Working Date',           'Effective date used to evaluate temporal validity of records in the user session.'),

-- 6. Sessions, login audit, tokens, system constants, service logbook, and system views
('fallback_language',           'Fallback Language (fallback_language)',           'Parent Fallback Language',               'Fallback Lang.',         'Code of the fallback language used when a text is not translated into the active language.'),
('translator_org',              'Translation Guarantee Org (translator_org)',      'Organization Guaranteeing Global Translation','Translator Org.',   'Organization whose translators are authorized to write translations of this language directly to system records (0x00).'),
('fallback_order',              'Fallback Chain Order (fallback_order)',           'Language Fallback Order',                'Fallback Order',         'Computed language order in the fallback chain for the current session (1 = active language, < 1000 = in chain).'),
('assumed_role',                'Assumed Session Role (assumed_role)',             'Effective Session Role (U/A/S/D)',       'Session Role',           'Effective role under which the user worked during the login session.'),
('active_role',                 'Active Role (active_role)',                       'Active Session Role (U/A/S/D)',          'Active Role',            'Effective application role in the current session.'),
('login_time',                  'Login Time (login_time)',                         'Login Date & Time',                      'Login Time',             'Timestamp when the user login session started.'),
('last_request_time',           'Last Activity (last_request_time)',               'Last Request Time in Session',           'Last Activity',          'Timestamp of the last HTTP request recorded in the session.'),
('logout_time',                 'Logout / Expiration Time (logout_time)',          'Logout or Session Expiration Time',      'Logout Time',            'Timestamp when the user logged out or the inactive session expired.'),
('ip_address',                  'IP Address (ip_address)',                         'Client IP Address',                      'IP Address',             'Network IP address of the client (including X-Forwarded-For path).'),
('client_ip',                   'Client IP Address (client_ip)',                   'Client IP Address',                      'Client IP',              'Network IP address of the client browser.'),
('request_ip',                  'Request IP Address (request_ip)',                 'Token Requester IP Address',             'Request IP',             'IP address from which the security token was requested.'),
('selector',                    'Token Public Selector (selector)',                'Token Identifier (selector)',            'Selector',               'Public part of the persistent login token used for fast database lookup.'),
('hashed_validator',            'Validator Hash (hashed_validator)',               'SHA-256 Hash of Secret Validator',       'Validator Hash',         'Cryptographic hash of the secret validator part of the persistent login token.'),
('expires',                     'Token Expiration (expires)',                      'Token Valid Until',                      'Expires',                'Expiration date and time of the persistent login token.'),
('expires_at',                  'Expires At (expires_at)',                         'Token Expiration Timestamp',             'Expires At',             'Exact timestamp when the one-time security token expires.'),
('user_agent',                  'Browser User-Agent (user_agent)',                 'Browser & OS Identification (User-Agent)','User-Agent',            'User-Agent string identifying the user browser and operating system.'),
('last_used',                   'Last Used (last_used)',                           'Token Last Used Timestamp',              'Last Used',              'Date and time when this persistent token was last used for auto-login.'),
('token_hash',                  'Token Hash (token_hash)',                         'Cryptographic Token Hash',               'Token Hash',             'SHA-256 hash of the one-time security token.'),
('token_purpose',               'Token Purpose (token_purpose)',                   'Security Token Purpose',                 'Token Purpose',          'Specifies the token usage context (PASSWORD_RESET, ACTIVATION, MFA).'),
('is_used',                     'Token Already Used (is_used)',                    'Token Has Been Used',                    'Used',                   'Flag preventing replay/reuse of a one-time security token.'),
('spid',                        'SQL Server Process ID (spid)',                    'SQL Server Process ID (@@SPID)',         'SPID',                   'Server process identifier of the database connection (@@SPID).'),
('wwwsession',                  'Web Session ID (wwwsession)',                     'Browser Session Identifier (SID)',       'Web Session',            'Unique browser session identifier (PHP session_id).'),
('login_session_uuid',          'Audit Session UUID (login_session_uuid)',         'Reference to audit_login_session',       'Session UUID',           'Unique login session identifier in audit_login_session used for the audit trail.'),
('user_name',                   'Session User Name (user_name)',                   'User Login Name',                        'Login',                  'Login name of the user in the active session.'),
('display_name',                'Display Name (display_name)',                     'Logged-in User Full Name',               'Display Name',           'Full display name of the user shown in the top bar.'),
('login_date',                  'Session Login Date (login_date)',                 'Session Creation Time',                  'Login Date',             'Date and time when the web session was created.'),
('request_date',                'Last Request Date (request_date)',                'Last HTTP Request Time',                 'Request Date',           'Timestamp of the last web session activity for timeout tracking.'),
('session_log',                 'Session Log Code (session_log)',                  'Session Logging Flag',                   'Session Log',            'Internal session logging flag.'),
('debug',                       'Debug Mode (debug)',                              'Enable Debug Output (debug)',            'Debug',                  'Flag enabling developer debug output in the session.'),
('servername',                  'Server Name (servername)',                        'Server Name',                            'Server',                 'Network name of the database or application server.'),
('application',                 'Application Name (application)',                  'Client Application Identifier',          'Application',            'Name of the client application connecting to the database.'),
('change_context_allowed',      'Context Switch Allowed (change_context_allowed)', 'Allow Switching Organization / Role',    'Context Switch',         'Indicates whether the user can switch organizations or roles from the top bar.'),
('database_version',            'Database Version (database_version)',             'Current Database Schema Version',        'DB Version',             'Database schema version in YY.MM.DD.N format managed by changes_YYYY.sql.'),
('app_version',                 'Application Version (app_version)',               'Application Code Version',               'App Version',            'Version identifier of the deployed PHP application scripts.'),
('database_state',              'Database State (database_state)',                 'Database Operational State',             'DB State',               'Single-character indicator of the database operational state.'),
('sysadmin_email',              'Sysadmin Email (sysadmin_email)',                 'Primary System Administrator Email',     'Sysadmin Email',         'Email address for emergency admin password recovery and system alerts.'),
('system_admin_pwd',            'Emergency Admin Password Hash (system_admin_pwd)','Break-Glass Admin Password Hash',        'Emergency Password',     'Bcrypt/argon2 password hash for emergency break-glass system administrator login.'),
('login_with_token',            'Require Token on Login (login_with_token)',       'Globally Require Authentication Token',  'Login with Token',       'Global switch enforcing token-based authentication.'),
('ldap_root',                   'LDAP Root Path (ldap_root)',                      'Active Directory / LDAP Root Path',      'LDAP Root',              'Configuration path for Active Directory / LDAP integration.'),
('application_info_file',       'Application Info File (application_info_file)',   'Path to Version Release Notes File',     'Info File',              'Path to the file containing MOTD or release notes.'),
('smtp_server',                 'SMTP Server (smtp_server)',                       'Outgoing SMTP Mail Server Address',      'SMTP Server',            'Hostname or IP address of the SMTP server used for sending system emails.'),
('smtp_port',                   'SMTP Port (smtp_port)',                           'SMTP Server Port Number',                'SMTP Port',              'Network port number of the SMTP server (e.g., 25, 465, 587, 2525).'),
('email_sender_name',           'Email Sender Name (email_sender_name)',           'Display Name of Email Sender',           'Sender Name',            'Display name used in the From header of outgoing system emails.'),
('email_sender_address',        'Email Sender Address (email_sender_address)',     'Sender Email Address',                   'Sender Email',           'Email address used as the sender of system notifications.'),
('sysmsg_recipients',           'System Message Recipients (sysmsg_recipients)',   'Service Alert Recipient List',           'Alert Recipients',       'List of email addresses receiving automatic operational and error notifications.'),
('backup_path',                 'Backup Path (backup_path)',                       'Database Backup Directory Path',         'Backup Path',            'Physical directory path on the server disk for database backup files.'),
('backup_full_date',            'Last Full Backup Date (backup_full_date)',        'Last Full Database Backup Time',         'Full Backup Date',       'Date and time when the last FULL database backup was completed.'),
('backup_full_days',            'Full Backup Period (backup_full_days)',           'Full Backup Interval in Days',           'Full Backup Days',       'Number of days between automatic full database backups.'),
('backup_diff_count',           'Differential Backup Count (backup_diff_count)',   'Differential Backups per Cycle',         'Diff Backup Count',      'Configured number of differential backups between full backups.'),
('backup_diff_counter',         'Differential Backup Counter (backup_diff_counter)','Current Differential Backup Number',    'Diff Counter',           'Internal counter of executed differential backups.'),
('backup_log_date',             'Last Log Backup Date (backup_log_date)',          'Last Transaction Log Backup Time',       'Log Backup Date',        'Date and time of the last transaction log backup.'),
('backup_log_hours',            'Log Backup Period (backup_log_hours)',            'Log Backup Interval in Hours',           'Log Period (h)',         'Number of hours between transaction log backups.'),
('copyonly_backup_switch',      'COPY_ONLY Backup Mode (copyonly_backup_switch)',  'Use COPY_ONLY Flag During Backups',      'COPY_ONLY Backup',       'Prevents disrupting the LSN chain when external backups are used concurrently.'),
('session_timeout',             'Session Timeout in Minutes (session_timeout)',    'Inactivity Timeout Before Logout (min)', 'Timeout (min)',          'Number of inactivity minutes before a web session automatically expires.'),
('current_year',                'Current Year (current_year)',                     'Current Calendar Year',                  'Current Year',           'Default calendar year in system settings.'),
('machine_guid',                'Machine GUID (machine_guid)',                     'Unique Server Identifier',               'Machine GUID',           'Hardware or system identifier of the server.'),
('right_profadmin_enabled',     'Professional Admin Mode (right_profadmin_enabled)','Enable Global Methodology Management',  'Profadmin Enabled',      'System switch for methodology administration mode.'),
('id',                          'Sequential ID (id)',                              'Numeric Record Identifier (ID)',         'ID',                     'Automatically generated sequential record number (IDENTITY).'),
('original_login',              'SQL Login Account (original_login)',              'Original SQL Server Login Account',      'SQL Login',              'System login name of the SQL Server account (original_login()) that executed the script.'),
('date',                        'Date & Time (date)',                              'Record Date & Time',                     'Date & Time',            'Timestamp of the entry in the service logbook.'),
('version',                     'Version (version)',                               'Version Identifier',                     'Version',                'Version number or timestamp of the database, upgrade script, or data package.'),
('content',                     'Content / Note (content)',                        'Record Content / Change Description',    'Content / Note',         'Text description of the executed operation, database upgrade, or imported package.'),
('counter',                     'Message Counter (counter)',                       'Sequential Message Number',              'Counter',                'Automatic sequential number of the message in request_message.'),
('code',                        'Code (code)',                                     'Item / Message Code',                    'Code',                   'Technical code of the message or item.'),
('severity',                    'Message Severity (severity)',                     'Severity Level (0=Info,1=OK,2=Warn,3=Err)', 'Severity',            'Numeric severity level: 0 = info, 1 = OK confirmation, 2 = warning, 3 = critical error.'),
('color',                       'Text Color (color)',                              'Message Display Color',                  'Color',                  'Explicit text color for rendering the message row.'),
('icon',                        'Message Icon (icon)',                             'Message Icon',                           'Icon',                   'Icon identifier for a request message.'),
('msgtext',                     'Message Text (msgtext)',                          'Main Message Text',                      'Message',                'Status or error message text displayed to the user.'),
('obj_type',                    'Affected Object Type (obj_type)',                 'Object Type',                            'Object Type',            'Type of object or table to which the message relates.'),
('obj_name',                    'Affected Object Name (obj_name)',                 'Specific Object / Item Identifier',      'Object Name',            'Specific identifier or name of the record to which the message relates.'),
('indent',                      'Indentation Level (indent)',                      'Message Row Indentation',                'Indent',                 'Numeric visual indentation level of the message from the left.'),
('style',                       'Row CSS Style (style)',                           'Inline CSS Display Style',               'CSS Style',              'Additional inline CSS style for rendering the message row.'),
('intvalue',                    'Integer Value (intvalue)',                        'Numeric Value / Row Count',              'Int. Value',             'Integer value associated with the message or variable (e.g., processed row count).'),
('charvalue',                   'Character Value (charvalue)',                     'Text Detail / Variable Value',           'Char. Value',            'Text detail of the message or value of the request variable.'),
('varname',                     'Variable Name (varname)',                         'Request Variable Name',                  'Variable',               'Name of the variable stored in request_variable.'),
('uuidvalue',                   'UUID Value (uuidvalue)',                          'UUID Variable Value',                    'UUID Value',             'UUID identifier stored in a request variable.'),
('param_order',                 'Parameter Order (param_order)',                   'Parameter Order in File',                'Param. Order',           'Sequential order of the header parameter in the imported CSV file.'),
('parameter_code',              'Parameter Code (parameter_code)',                 'Technical Package Parameter Name',       'Parameter Code',         'Identifier of the parameter in the CSV import header (e.g., package_name, verify_data, signature).'),
('parameter_value',             'Parameter Value (parameter_value)',               'Package Parameter Value',                'Parameter Value',        'Text value of the parameter loaded from the CSV file header.'),
('table_id',                    'Import Table ID (table_id)',                      'Sequential Table Number in CSV',         'Table ID',               'Sequential number of the table block within the current CSV import.'),
('row_count',                   'Row Count (row_count)',                           'Data Row Count in Block',                'Row Count',              'Total number of data rows loaded for the table in the CSV import.'),
('column_id',                   'Import Column ID (column_id)',                    'Global Column Number in CSV',            'Column ID',              'Unique sequential column number within the CSV import staging tables.'),
('row_id',                      'Import Row Number (row_id)',                      'Sequential Data Row Number',             'Row ID',                 'Sequential number of the data row within the imported table.'),
('cell_value',                  'Cell Value (cell_value)',                         'CSV Cell Text Value',                    'Cell Value',             'Non-empty cell content loaded from the imported CSV file.'),
('row_num',                     'Row Number (row_num)',                            'Sequential Row Number (0..1024)',        'Row Num.',               'Sequential number in the helper rowgenerator system table.'),
('access_uuid',                 'Access ID (access_uuid)',                         'Original Access Record UUID',            'Access ID',              'Logical identifier of the record in user_organization_access.'),
('last_login_org',              'Last Organization (last_login_org)',              'Last Logged-in Organization',            'Last Org.',              'Organization into which the user last logged in.'),
('current_organization',        'Current Session Organization (current_organization)', 'Currently Active Organization',      'Current Org.',           'Organization active in the currently executing @@SPID session.'),
('tabname',                     'Table Name (tabname)',                            'Table / View Name',                      'Table',                  'System name of the table or view in the database catalog.'),
('colid',                       'Column ID (colid)',                               'Column Sequential Number in Table',      'Col. ID',                'Internal sequential column number in the system syscolumns catalog.'),
('colname',                     'Column Name (colname)',                           'System Column Name',                     'Column',                 'Column name in the database system catalog.'),
('typename',                    'Data Type (typename)',                            'SQL Server Data Type Name',              'Data Type',              'Physical SQL data type of the column (e.g., varchar, int, uuid, bit).'),
('prec',                        'Precision / Length (prec)',                       'Maximum Type Length or Precision',       'Length / Prec.',         'Numeric length or precision of the data type in the system catalog.'),
('prec_syntax',                 'Length Syntax (prec_syntax)',                     'DDL Length / Precision Syntax',          'Length Syntax',          'Formatted length or precision in parentheses for DDL statements, e.g., (200) or (9,4).'),
('iscomputed',                  'Computed Column (iscomputed)',                    'Database Computed Column Flag',          'Computed (DB)',          'System catalog flag indicating whether the column is a computed column.'),
('collation_name',              'Collation Name (collation_name)',                 'Database Column Collation Name',         'Collation',              'Collation name applied to a character column in SQL Server.'),
('keyno',                       'Primary Key Ordinal (keyno)',                     'Column Position in Primary Key',         'PK Ordinal',             'Sequential position of the column within a composite primary key.'),
('nulls',                       'Nullability (nulls)',                             'NULL Permission (null / not null)',      'NULL / NOT NULL',        'Indicates whether the database column allows NULL values.'),
('default_syntax',              'Default Value Syntax (default_syntax)',           'DEFAULT Constraint Definition',          'Default Syntax',         'SQL expression of the column default value in the system catalog.'),
('default_constraint_name',     'Default Constraint Name (default_constraint_name)','System DEFAULT Constraint Name',        'Default Name',           'Database constraint name enforcing the column default value.'),
('is_identity',                 'Identity Column (is_identity)',                   'IDENTITY Auto-Increment Flag',           'Is IDENTITY',            'Indicates whether the database column uses IDENTITY auto-incrementing.'),
('computed_syntax',             'Computed Column Formula (computed_syntax)',       'SQL Formula of Computed Column',         'Computed Formula',       'SQL expression defining a computed column.'),
('table_type',                  'Table Object Type (table_type)',                  'Object Type in sys.objects',             'Table Type',             'Object type code in the system catalog (U = User Table, V = View).'),
('index_name',                  'Index Name (index_name)',                         'System Index Name',                      'Index',                  'Database index name in sys.indexes.'),
('is_unique',                   'Unique Index (is_unique)',                        'Unique Index Flag',                      'Unique',                 'Indicates whether the index enforces uniqueness of key values.'),
('is_primary_key',              'Primary Key (is_primary_key)',                    'Index Forms Table Primary Key',          'Primary Key',            'Indicates whether the index represents the primary key of the table.'),
('key_ordinal',                 'Index Key Ordinal (key_ordinal)',                 'Column Position in Index Key',           'Key Ordinal',            'Position of the column within the index key (0 = included non-key column).'),
('is_descending_key',           'Descending Index Key (is_descending_key)',        'Index Column Sorted Descending (DESC)',  'Descending (DESC)',      'Indicates whether the column is sorted descending in the index.'),
('is_included_column',          'Included Column (is_included_column)',            'Non-Key Column Added via INCLUDE',       'Included Col.',          'Indicates whether the column is attached to the index via the INCLUDE clause.'),
('keyvalue',                    'Node Key Value (keyvalue)',                       'Tree Node Identifier',                   'Node Key',               'Item identifier used during tree hierarchy resolution.'),
('parent',                      'Parent Node (parent)',                            'Parent Identifier in Tree',              'Parent',                 'Reference to the parent element in f_resolve_hierarchy.'),
('num',                         'Sibling Order Number (num)',                      'Node Order Among Siblings',              'Order (num)',            'Computed sequential number of the node under the same parent.'),
('hierarchy_sort',              'Tree Sort Path (hierarchy_sort)',                 'Zero-Padded Tree Traversal Sort Key',    'Tree Sort Key',          'Concatenated zero-padded sort string determining exact tree order.'),
('level',                       'Nesting Level (level)',                           'Tree Node Nesting Depth',                'Level',                  'Numeric nesting depth of the item in the tree hierarchy (0 = root).'),
('ordr',                        'List Item Order (ordr)',                          'Sequential Number in Parsed List',       'Order',                  'Item position returned by list-splitting functions f_string_list, f_integer_list, and f_uuid_list.'),
('i',                           'Integer Value (i)',                               'Parsed Integer Value',                   'Integer (i)',            'Integer value returned by f_integer_list.'),
('s',                           'String Value (s)',                                'Parsed String Item',                     'String (s)',             'String item returned by f_string_list.');

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