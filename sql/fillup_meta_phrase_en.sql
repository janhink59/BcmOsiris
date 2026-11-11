/* =============================================================================
 * Verze: 2026-11-11 22:45
 * Soubor: fillup_meta_phrase_en.sql
 * Účel:   Hromadné idempotentní nastavení výchozích anglických překladů (jazyk 'en',
 *         record_type = 'L') pro systémové textové fráze v tabulce meta_phrase
 *         (object_owner = 0x00), seřazené podle (source_code, builtin_code)
 *         a rozdělené do bloků /*#od# <source_code> */ ... /*#do# <source_code> */.
 *         Přepisuje záznamy s who_modified = 0x00 nebo date_modified < '2026-11-01'
 *         a vkládá chybějící 'L' záznamy pro jazyk 'en'.
 * Vazby:  - Navazuje na fillup_meta_phrase.sql a p_phrases.sql.
 *         - Automaticky zařazeno v BuildListDb.txt přes masku fillup_*.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @phr_en TABLE (
	source_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
	builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
	caption varchar(max) NOT NULL,
	helptext varchar(max) NOT NULL,
	PRIMARY KEY (source_code, builtin_code)
);

INSERT INTO @phr_en (source_code, builtin_code, caption, helptext) VALUES
/*#od# abstract_button */
('abstract_button','btn_cancel','Cancel','Cancel the current action and return'),
('abstract_button','btn_delete_draft','Delete Draft','Permanently delete this work-in-progress draft'),
('abstract_button','btn_discard','Discard Changes','Close the form without saving changes'),
('abstract_button','btn_forward_approval','Submit for Approval','Submit the draft to an approver for review (state F)'),
('abstract_button','btn_save','Save Changes','Save changes directly as an approved record (state A)'),
('abstract_button','btn_save_draft','Save Draft','Save the record as a private work-in-progress draft (state D)'),
/*#do# abstract_button */

/*#od# abstract_csv_package */
('abstract_csv_package','btn_export_csv','Export Package (CSV)','Generate and download the multi-block CSV package'),
('abstract_csv_package','btn_run_phase2','Run Database Import (Phase 2)','Execute the database import of the verified staging data'),
('abstract_csv_package','err_empty_mandatory_cells','Column contains empty values in a mandatory field.',''),
('abstract_csv_package','err_file_not_readable','Input file is not readable.',''),
('abstract_csv_package','err_file_open_failed','Failed to open input file.',''),
('abstract_csv_package','err_import_rolled_back','Package import was rolled back due to errors (Rollback).',''),
('abstract_csv_package','err_invalid_signature','Invalid file security signature (the file was modified without authorization or corrupted).',''),
('abstract_csv_package','err_missing_mandatory_col','Mandatory column is missing in the table.',''),
('abstract_csv_package','err_missing_mandatory_param','Mandatory package parameter is missing.',''),
('abstract_csv_package','err_missing_mandatory_table','Mandatory table is missing in the file.',''),
('abstract_csv_package','err_proc_not_found','Stored procedure for processing the package was not found in the database.',''),
('abstract_csv_package','err_same_org_only_blocked','Import blocked: This package is restricted to import only into the same organization that exported the data (same_org_only = 1).',''),
('abstract_csv_package','err_wrong_package_code','Package code in the file does not match the selected import type.',''),
('abstract_csv_package','hdr_phase1_summary','Loaded Package Verification (Phase 1)',''),
('abstract_csv_package','lbl_param_import_origin','Data Origin Label (import_origin)',''),
('abstract_csv_package','lbl_param_same_org_only','Allow import only into the same organization that exported the data',''),
('abstract_csv_package','lbl_param_target_status','Import Write Mode',''),
('abstract_csv_package','lbl_param_verify_data','Enforce data immutability (full file cryptographic signature)',''),
('abstract_csv_package','msg_import_committed','Package import was completed and committed successfully.',''),
('abstract_csv_package','msg_same_org_only_verified','Organization check (same_org_only = 1) passed – importing into the same organization.',''),
('abstract_csv_package','msg_signature_verified','File security signature is valid (integrity verified).',''),
('abstract_csv_package','opt_status_active','Write directly as approved active records (A)',''),
('abstract_csv_package','opt_status_draft','Save as work-in-progress drafts (D)',''),
('abstract_csv_package','opt_status_forward','Submit to approver for review (F)',''),
('abstract_csv_package','th_col_list','Loaded Columns',''),
('abstract_csv_package','th_param_code','Parameter',''),
('abstract_csv_package','th_param_val','File Value',''),
('abstract_csv_package','th_row_count','Row Count',''),
('abstract_csv_package','th_table_name','Package Table',''),
/*#do# abstract_csv_package */

/*#od# abstract_page */
('abstract_page','msg_access_denied','Access denied. You do not have sufficient permissions to view this page.',''),
('abstract_page','msg_unsaved_changes','You have unsaved changes. Are you sure you want to leave this page?',''),
/*#do# abstract_page */

/*#od# abstract_page_master_detail */
('abstract_page_master_detail','badge_draft','Draft',''),
('abstract_page_master_detail','badge_forwarded','Pending Approval',''),
('abstract_page_master_detail','badge_rejected','Returned',''),
('abstract_page_master_detail','badge_removed','Removed',''),
('abstract_page_master_detail','default_detail_heading','Record Detail',''),
('abstract_page_master_detail','default_list_heading','Record List',''),
('abstract_page_master_detail','err_ajax_detail','Error loading detail panel:',''),
('abstract_page_master_detail','err_ajax_network','Network error during AJAX call',''),
('abstract_page_master_detail','err_ajax_refresh','Error refreshing master panel:',''),
('abstract_page_master_detail','lbl_quick_filter_info','Quick filter',''),
('abstract_page_master_detail','lbl_show_removed','Show removed',''),
('abstract_page_master_detail','msg_no_list_columns','Master panel has no columns defined in metadata (list_order).',''),
('abstract_page_master_detail','msg_select_item_prompt','Select an item in the left list to view and edit its details.',''),
('abstract_page_master_detail','placeholder_search','Search...',''),
('abstract_page_master_detail','tip_clear_adv_filter','Clear advanced filter',''),
('abstract_page_master_detail','tip_csv_export_import','Export / Import data of this class (simple_class CSV package)',''),
('abstract_page_master_detail','tip_open_adv_filter','Advanced multi-field filter',''),
/*#do# abstract_page_master_detail */

/*#od# abstract_page_tree */
('abstract_page_tree','badge_draft','Draft',''),
('abstract_page_tree','badge_forwarded','Pending Approval',''),
('abstract_page_tree','badge_rejected','Returned',''),
('abstract_page_tree','badge_removed','Removed',''),
('abstract_page_tree','btn_collapse_all','Collapse All','Collapse all expanded tree branches in the left panel'),
('abstract_page_tree','btn_expand_all','Expand All','Expand all tree folders in the left panel'),
('abstract_page_tree','btn_new_tree_item','+ New Item','Create a new item in the tree hierarchy'),
('abstract_page_tree','btn_split_node_oth','Split into Subclasses (+ _oth)','Creates a terminal "Other (*_oth)" item under this node, moves linked records to it, and converts this node into a folder'),
('abstract_page_tree','confirm_split_node_oth','Are you sure you want to convert this leaf node into a folder and move its direct links and records to a new child item "Other ({$code}_oth)"?',''),
('abstract_page_tree','default_tree_heading','Record Tree',''),
('abstract_page_tree','lbl_show_removed','Show removed',''),
('abstract_page_tree','msg_auto_split_parent_info','The parent leaf node was automatically converted into a folder and its original direct records were moved to the new item "{$code}".',''),
('abstract_page_tree','msg_dnd_unsaved_notice','Parent item (parent_uuid) and sort order (sort_code) were adjusted via Drag & Drop. Review the details and confirm by clicking Save Changes (or Save Draft / Submit for Approval).',''),
('abstract_page_tree','msg_node_locked_notice','🔒 This node (or its child node) already has active linked records. Changing its parent node (reparenting) and deletion are locked; if you need to subdivide this leaf node into subclasses, use the "Split into Subclasses (+ _oth)" button in the detail header (or add a new child item directly under it).',''),
('abstract_page_tree','placeholder_search','Search tree...',''),
('abstract_page_tree','th_builtin_code','Code',''),
('abstract_page_tree','th_sort_code','Order',''),
('abstract_page_tree','th_tree_caption','Item Name (Tree)',''),
('abstract_page_tree','tip_drag_handle','Drag & Drop to adjust sort order or parent folder in the detail panel',''),
('abstract_page_tree','tip_folder_node','Internal hierarchy folder (is_leaf = 0)',''),
('abstract_page_tree','tip_locked_node','Node has linked records – changing parent folder is locked (only sibling order can be changed)',''),
('abstract_page_tree','tip_toggle_branch','Collapse / expand child items',''),
/*#do# abstract_page_tree */

/*#od# csv_package_metadata */
('csv_package_metadata','err_import_dev_only','Importing system metadata is permitted only for developers in the system organization (0x00).',''),
('csv_package_metadata','lbl_filter_class_name','Filter by Logical Class (class_name)',''),
('csv_package_metadata','lbl_filter_date_from','Modified Since Date (date_modified >=)',''),
('csv_package_metadata','lbl_filter_language','Translation Language (language)',''),
('csv_package_metadata','lbl_filter_only_custom','Client Customizations Only (who_modified <> 0x00)',''),
('csv_package_metadata','lbl_filter_source_code','Filter Phrases by Source (source_code)',''),
('csv_package_metadata','opt_all_classes','--- All Classes ---',''),
('csv_package_metadata','opt_all_languages','--- All Languages ---',''),
('csv_package_metadata','opt_all_sources','--- All Sources (Pages & Classes) ---',''),
('csv_package_metadata','pkg_caption','System Metadata & Translations (meta_*)',''),
('csv_package_metadata','pkg_description','Transfer of system metadata (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def) between development and production instances.',''),
/*#do# csv_package_metadata */

/*#od# csv_package_simple_class */
('csv_package_simple_class','err_class_not_found','Selected logical class was not found in metadata.',''),
('csv_package_simple_class','info_all_langs_exported','All available language versions exported',''),
('csv_package_simple_class','info_single_lang_exported','Exported single language version only: {$caption} ({$code})',''),
('csv_package_simple_class','lbl_active_filter_info','Active Page Filter',''),
('csv_package_simple_class','lbl_Export_language','Language Versions to Export',''),
('csv_package_simple_class','lbl_select_class','Logical Class (Table)',''),
('csv_package_simple_class','opt_lang_all','All available language versions (A + all L)',''),
('csv_package_simple_class','opt_lang_single','Single language version only: {$caption} ({$code})',''),
('csv_package_simple_class','pkg_caption','Single Organization Class Data (Simple Class CSV)',''),
('csv_package_simple_class','pkg_description','Export and two-phase import of records for a single selected logical class of the current organization (including tree structures and language mutations).',''),
/*#do# csv_package_simple_class */

/*#od# entity_manager */
('entity_manager','confirm_delete_draft','Are you sure you want to permanently delete this work-in-progress draft?',''),
('entity_manager','err_duplicate_key_active','A record with the specified key value ({$keys}) already exists in the database. Please enter a unique value to avoid a duplicate original identifier.',''),
('entity_manager','err_duplicate_key_in_trash','A record with the specified key value ({$keys}) already exists in the trash (removed records). Enable "Show removed" in the left panel to restore it, or choose a different unique code.',''),
('entity_manager','err_hierarchy_code_collides_class','The hierarchy code "{$code}" collides with an existing logical class name in meta_class. Please choose a different unique code.',''),
('entity_manager','err_key_col_empty','Key field "{$label}" ({$col}) cannot be empty.',''),
('entity_manager','err_leaf_cannot_have_children','The selected parent item is a terminal leaf node (is_leaf = 1). Child items cannot be placed under a leaf node; select a folder (or uncheck Leaf Node on the parent item first).',''),
('entity_manager','err_mandatory_fields_prefix','Please fill in the mandatory fields: ',''),
('entity_manager','err_meta_not_found','Metadata for logical class {$class} was not found.',''),
('entity_manager','err_node_has_children_cannot_be_leaf','This node contains child items and therefore cannot be marked as a terminal leaf node (is_leaf = 1) or moved to trash.',''),
('entity_manager','err_node_has_links_cannot_move_or_delete','This node (or its child node) already has linked records in the database. Changing its parent node (reparenting) or moving it to trash is not permitted.',''),
('entity_manager','err_parent_cycle','Invalid tree cycle: An item cannot be a child of itself or its own descendant.',''),
('entity_manager','err_scale_duplicate_threshold','A level with the same threshold value ({$thr} %) already exists in this scale ({$name}). Threshold values must form a strictly increasing sequence.',''),
('entity_manager','err_scale_score_exceeds_next_threshold','The score value ({$scr} %) of level "{$name}" exceeds the threshold value of the next level ({$next} %).',''),
('entity_manager','err_scale_score_not_monotonic','Score values must form an increasing sequence: level "{$name}" ({$scr} %) must have a higher score than the preceding level "{$prev_name}" ({$prev_scr} %).',''),
('entity_manager','err_scale_score_under_threshold','The score value ({$scr} %) cannot be lower than the lower threshold of the level interval ({$thr} %).',''),
('entity_manager','lbl_approval_note_input','Proposal note / comment for approver:',''),
('entity_manager','lbl_auto_code_hint','Automatically derived from name (editable)',''),
('entity_manager','lbl_inherited_from_ancestor','Inherited from ancestor:',''),
('entity_manager','lbl_record_removed_checkbox','Move record to trash (removed record)',''),
('entity_manager','msg_draft_Banner','You are working on your private draft (state D). Changes are not yet visible to other users.',''),
('entity_manager','msg_forwarded_banner','This proposal has been submitted for approval (state F). Saving further changes will update the submitted proposal.',''),
('entity_manager','msg_rejected_banner','The approver returned this proposal for revision (state R). Reason:',''),
('entity_manager','msg_remove_lang_mutation_only','Removes only the language mutation ({$lang})',''),
('entity_manager','opt_root_no_parent','--- Root Item (No Parent Node) ---',''),
('entity_manager','opt_select_empty','--- Select ---',''),
('entity_manager','ph_approval_note','Enter an optional note for the approver...',''),
('entity_manager','sec_other_attributes','Other Attributes',''),
/*#do# entity_manager */

/*#od# filter_manager */
('filter_manager','btn_apply_filter','Apply Filter','Apply the specified filter conditions and refresh the list'),
('filter_manager','btn_clear_filter','Clear Filter','Clear all filter conditions and show the full list'),
('filter_manager','btn_close_filter','Close','Close the advanced filter window without saving changes'),
('filter_manager','btn_show_all_fields','Show All (+{$count} more fields)','Expand the remaining columns of the class in the filter modal'),
('filter_manager','err_date_range_order','Start date ({$min}) is greater than end date ({$max}) in field "{$label}".',''),
('filter_manager','err_invalid_date_expr','Invalid date "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_date_range','Invalid date range "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_number_expr','Invalid numeric expression "{$expr}" in field "{$label}".',''),
('filter_manager','err_invalid_number_range','Invalid numeric range "{$expr}" in field "{$label}".',''),
('filter_manager','err_number_range_order','Lower bound ({$min}) is greater than upper bound ({$max}) in field "{$label}".',''),
('filter_manager','help_bool','Select Yes (1), No (0), or All.',''),
('filter_manager','help_date','Enter a date (Y-M-D or D.M.Y), range (from..to), or comparison (>=, <=).',''),
('filter_manager','help_number','Enter a number, range (10..50), or comparison (>=10, <100, !=0).',''),
('filter_manager','help_select','Select a specific item from the dropdown list.',''),
('filter_manager','help_text','Case-insensitive substring search. Supports wildcard (*) and comma-separated lists.',''),
('filter_manager','lbl_modal_title','Advanced Record Filter',''),
('filter_manager','opt_bool_all','--- All ---',''),
('filter_manager','opt_bool_no','No (0)',''),
('filter_manager','opt_bool_yes','Yes (1)',''),
('filter_manager','opt_select_all','--- All ---',''),
/*#do# filter_manager */

/*#od# global_phrase */
('global_phrase','cancel','Cancel',''),
('global_phrase','error','Error',''),
('global_phrase','no','No',''),
('global_phrase','ok','OK',''),
('global_phrase','warning','Warning',''),
('global_phrase','yes','Yes',''),
/*#do# global_phrase */

/*#od# menu_manager */
('menu_manager','breadcrumb_home','Home',''),
/*#do# menu_manager */

/*#od# page_approval */
('page_approval','badge_action_delete','Deletion Proposal',''),
('page_approval','badge_action_insert','New Record',''),
('page_approval','badge_action_translation','Translation (L)',''),
('page_approval','badge_action_update','Record Update',''),
('page_approval','btn_approve','✓ Approve & Publish','Approve the selected proposal and publish changes into active data (state A)'),
('page_approval','btn_reject','↩ Return for Revision','Return the proposal to its author with comments (state R)'),
('page_approval','err_reject_note_required','You must provide a reason / comment for the author when returning a proposal for revision.',''),
('page_approval','hdr_comparison_table','Comparison of Proposed Changes Against Current Active State',''),
('page_approval','header_detail_default','Change Proposal Review',''),
('page_approval','lbl_approval_note','Approver Decision Note / Reason for Return:',''),
('page_approval','lbl_author','Proposal Author:',''),
('page_approval','lbl_class','Class (Entity):',''),
('page_approval','lbl_date_modified','Submitted On:',''),
('page_approval','lbl_filter_class','Filter by Class:',''),
('page_approval','lbl_language','Proposal Language:',''),
('page_approval','lbl_only_changed_rows','Show Modified Fields Only',''),
('page_approval','master_heading','Proposals Pending Approval (State F)',''),
('page_approval','msg_approved_ok','Proposal was approved and published successfully.',''),
('page_approval','msg_competing_warning','Warning: Multiple competing proposals from different authors exist for this record. Approving this proposal will replace the current active state; other open proposals will remain available to their authors.',''),
('page_approval','msg_empty_queue','There are currently no proposals waiting for approval.',''),
('page_approval','msg_rejected_ok','Proposal was returned to the author for revision.',''),
('page_approval','msg_select_proposal','Select a proposal from the left list to review value differences and make a decision.',''),
('page_approval','opt_all_classes','--- All Classes ---',''),
('page_approval','page_title','Change Approval - BCM Osiris',''),
('page_approval','ph_approval_note','Enter an approval comment or a mandatory reason when returning the proposal...',''),
('page_approval','th_author','Author',''),
('page_approval','th_caption','Record / Name',''),
('page_approval','th_class','Class',''),
('page_approval','th_current_val','Current Active Value (A)',''),
('page_approval','th_date','Date',''),
('page_approval','th_field_name','Field (Column)',''),
('page_approval','th_proposed_val','Proposed Value (F)',''),
('page_approval','tip_competing_proposals','{$count} competing proposals exist for this record',''),
('page_approval','txt_new_record_no_active','(New record – no approved version exists yet)',''),
/*#do# page_approval */

/*#od# page_asset */
('page_asset','btn_asset_cms','Controls ({$count}) →','Open countermeasure implementations for this asset'),
('page_asset','btn_asset_links','Links ({$count}) →','Open operational and spatial links for this asset'),
('page_asset','btn_asset_scenarios','Scenarios ({$count}) →','Open risk scenario assessments for this asset'),
('page_asset','btn_new_asset','+ New Asset','Create a new asset in the asset inventory'),
('page_asset','btn_new_space','+ New Space / Location','Create a new space, building, or room'),
('page_asset','grp_bia_risk_scores','Availability Parameters (BIA) & Aggregated Risk Scores (0 to 100%)',''),
('page_asset','grp_identification','Classification, Archetype & Identification',''),
('page_asset','grp_placement_relations','Tree Placement (parent_uuid)',''),
('page_asset','grp_presentation','Presentation Texts, Description & Notes',''),
('page_asset','grp_validity_protection','Validity, Icon & Record Protection',''),
('page_asset','header_edit_asset','Asset',''),
('page_asset','header_edit_space','Space',''),
('page_asset','header_new_asset','New Asset',''),
('page_asset','header_new_space','New Space / Location',''),
('page_asset','lbl_filter_archetype','Filter by Archetype:',''),
('page_asset','master_heading','Asset Tree & Inventory',''),
('page_asset','master_heading_space','Spaces & Locations Tree',''),
('page_asset','msg_no_building_warning','Warning: No Building (archetype BUILDING) is defined in the organization yet. Please create at least one building (even fictitious), as rooms and cabling must be placed in buildings, and physical assets, hosts, documents, and media must be placed in rooms.',''),
('page_asset','opt_all_assets','--- All Asset Archetypes (Excl. Spaces) ---',''),
('page_asset','opt_all_spaces','--- All Spaces & Locations ---',''),
('page_asset','page_title','Asset Inventory (CRMM)',''),
('page_asset','page_title_space','Spaces & Locations (CRMM)',''),
('page_asset','th_archetype','Archetype',''),
('page_asset','th_asset_caption','Asset / Service',''),
('page_asset','th_res_risk','Res. Risk',''),
('page_asset','th_space_caption','Space / Location',''),
/*#do# page_asset */

/*#od# page_asset_class */
('page_asset_class','btn_new_asset_class','+ New Asset Class','Create a new folder or leaf asset class in the catalog'),
('page_asset_class','grp_identification','Code & Tree Placement',''),
('page_asset_class','grp_permissions_protection','Permissions, Validity & Record Protection',''),
('page_asset_class','grp_presentation','Presentation Texts & Description',''),
('page_asset_class','header_edit_class','Asset Class',''),
('page_asset_class','header_new_class','New Asset Class',''),
('page_asset_class','master_heading','Asset Class Tree',''),
('page_asset_class','page_title','Asset Classes (CRMM Catalog)',''),
('page_asset_class','th_class_caption','Asset Class',''),
/*#do# page_asset_class */

/*#od# page_audit_login_session */
('page_audit_login_session','badge_session_expired','Expired',''),
('page_audit_login_session','badge_user_inactive','Inactive Account',''),
('page_audit_login_session','btn_apply_filter','Filter','Filter login sessions by the specified criteria'),
('page_audit_login_session','btn_reset_filter','Reset Filter','Clear filter criteria and display the latest sessions'),
('page_audit_login_session','heading_user_activity','User Login & Activity History',''),
('page_audit_login_session','intro_user_activity','Overview of user logins and session activity from audit_login_session and linked account details (sorted descending by login time).',''),
('page_audit_login_session','lbl_displayed_records','Displayed records: {$count}',''),
('page_audit_login_session','lbl_filter_limit','Row limit:',''),
('page_audit_login_session','lbl_filter_only_open','Active (open) sessions only',''),
('page_audit_login_session','lbl_filter_user','User name / login:',''),
('page_audit_login_session','msg_no_records','No records in audit_login_session match the specified criteria.',''),
('page_audit_login_session','page_title','User Activity - BCM Osiris',''),
('page_audit_login_session','ph_filter_user','Enter first name, last name, login, or email...',''),
('page_audit_login_session','th_assumed_role','Role',''),
('page_audit_login_session','th_dept_job','Department / Job Title',''),
('page_audit_login_session','th_duration_min','Duration',''),
('page_audit_login_session','th_email','Email',''),
('page_audit_login_session','th_ip_address','IP Address',''),
('page_audit_login_session','th_last_request_time','Last Activity',''),
('page_audit_login_session','th_login_name','Login',''),
('page_audit_login_session','th_login_time','Login Time',''),
('page_audit_login_session','th_logout_time','Logout / Expiration',''),
('page_audit_login_session','th_organization','Organization',''),
('page_audit_login_session','th_user_name','User Name',''),
('page_audit_login_session','txt_session_open','Active',''),
('page_audit_login_session','unit_minutes','min',''),
/*#do# page_audit_login_session */

/*#od# page_change_user_context */
('page_change_user_context','badge_current','Active',''),
('page_change_user_context','badge_disabled','Disabled',''),
('page_change_user_context','badge_pending','Pending Approval',''),
('page_change_user_context','btn_apply_context','Switch Context','Activate the selected organization and application role for the current session'),
('page_change_user_context','btn_cancel_request','Cancel Request','Withdraw your pending access request'),
('page_change_user_context','btn_request_access','Request Access','Send an access request to the administrator of the selected organization'),
('page_change_user_context','btn_save_working_date','Save Working Date','Set the personal working date used to evaluate temporal validity of records'),
('page_change_user_context','hdr_available_orgs','Available Organizations & Role Selection',''),
('page_change_user_context','hdr_request_access','Request Access to Another Organization',''),
('page_change_user_context','hdr_working_date','Personal Working Date (Temporal Validity Slice)',''),
('page_change_user_context','lbl_select_org_request','Select organization:',''),
('page_change_user_context','lbl_select_role','Select login role:',''),
('page_change_user_context','lbl_working_date','Working date (empty = today):',''),
('page_change_user_context','msg_context_switched','Organization and role context switched successfully.',''),
('page_change_user_context','msg_request_cancelled','Access request has been cancelled.',''),
('page_change_user_context','msg_request_sent','Access request has been sent for approval.',''),
('page_change_user_context','msg_working_date_saved','Working date has been saved.',''),
('page_change_user_context','page_title','Change User Context - BCM Osiris',''),
('page_change_user_context','th_action','Action',''),
('page_change_user_context','th_licence_level','Licence',''),
('page_change_user_context','th_organization','Organization',''),
('page_change_user_context','th_role','Available Roles',''),
('page_change_user_context','th_status','Status',''),
/*#do# page_change_user_context */

/*#od# page_countermeasure */
('page_countermeasure','btn_new_countermeasure','+ New Countermeasure','Create a new group or leaf countermeasure in the catalog'),
('page_countermeasure','grp_factors','Reduction & Minimum Risk Threshold Factors (0 to 100%)',''),
('page_countermeasure','grp_identification','Code, Tree Placement & Icon',''),
('page_countermeasure','grp_permissions_protection','Permissions, Validity & Record Protection',''),
('page_countermeasure','grp_presentation','Presentation Texts & Countermeasure Description',''),
('page_countermeasure','header_edit_countermeasure','Countermeasure',''),
('page_countermeasure','header_new_countermeasure','New Countermeasure',''),
('page_countermeasure','master_heading','Countermeasure Catalog Tree',''),
('page_countermeasure','page_title','Countermeasure Catalog (CRMM)',''),
('page_countermeasure','th_cm_caption','Countermeasure',''),
('page_countermeasure','th_reduction_factor','Reduction (%)',''),
('page_countermeasure','th_risk_factor','Floor (%)',''),
/*#do# page_countermeasure */

/*#od# page_countermeasure_implementation */
('page_countermeasure_implementation','btn_back_to_asset','← Back to Asset: {$asset}','Return to the asset detail'),
('page_countermeasure_implementation','btn_new_cm_impl','+ New Control Implementation','Create a new countermeasure implementation record'),
('page_countermeasure_implementation','grp_asset_cm_state','Protected Asset, Applied Countermeasure & Implementation State',''),
('page_countermeasure_implementation','grp_presentation','Implementation Description & Audit Notes',''),
('page_countermeasure_implementation','grp_responsibility_factors','Responsibility, Dates & Calculated Effective Factors (0 to 100%)',''),
('page_countermeasure_implementation','grp_validity','Record Validity',''),
('page_countermeasure_implementation','header_edit_cm_impl','Control Implementation',''),
('page_countermeasure_implementation','header_new_cm_impl','New Countermeasure Implementation',''),
('page_countermeasure_implementation','lbl_filter_asset','Protected Asset / Space:',''),
('page_countermeasure_implementation','lbl_summary_eff_reduction','Effective Scenario Risk Reduction:',''),
('page_countermeasure_implementation','lbl_summary_eff_risk','Effective Minimum Risk Floor (When Unimplemented):',''),
('page_countermeasure_implementation','opt_all_assets','--- All Assets & Spaces ---',''),
('page_countermeasure_implementation','page_title','Countermeasure Implementation (CRMM)',''),
('page_countermeasure_implementation','th_eff_reduction','Eff. Reduction (%)',''),
('page_countermeasure_implementation','th_eff_risk','Eff. Risk Floor (%)',''),
('page_countermeasure_implementation','th_impl_caption','Implementation Description / Control',''),
('page_countermeasure_implementation','th_target_date','Target Date',''),
/*#do# page_countermeasure_implementation */

/*#od# page_countermeasure_state */
('page_countermeasure_state','btn_new_cm_state','+ New Countermeasure State','Create a new countermeasure implementation state'),
('page_countermeasure_state','grp_factors','Reduction & Risk Factor Weights (0 to 100%)',''),
('page_countermeasure_state','grp_identification','Code, Sort Order & Visual Styling',''),
('page_countermeasure_state','grp_presentation','State Name & Description',''),
('page_countermeasure_state','grp_protection','Validity & Record Protection',''),
('page_countermeasure_state','header_edit_cm_state','Countermeasure State',''),
('page_countermeasure_state','header_new_cm_state','New Countermeasure State',''),
('page_countermeasure_state','page_title','Countermeasure States (CRMM)',''),
('page_countermeasure_state','th_builtin_code','Code',''),
('page_countermeasure_state','th_caption','Countermeasure State',''),
('page_countermeasure_state','th_reduction_factor','Reduction (%)',''),
('page_countermeasure_state','th_risk_factor','Risk (%)',''),
('page_countermeasure_state','th_sort_code','Order',''),
/*#do# page_countermeasure_state */

/*#od# page_csv_package */
('page_csv_package','btn_clear_staging','Clear Loaded File (Staging)','Remove temporary Phase 1 staging data from the database'),
('page_csv_package','btn_upload_phase1','Upload & Verify File (Phase 1)','Upload the CSV file into staging tables and verify its structure and signature'),
('page_csv_package','err_no_file_uploaded','No file was selected for upload.',''),
('page_csv_package','hdr_export_section','Export Data Package to CSV File',''),
('page_csv_package','hdr_import_section','Import Data Package from CSV File (Two-Phase)',''),
('page_csv_package','lbl_select_csv_file','Select package CSV file:',''),
('page_csv_package','lbl_select_package_type','Data Package Type:',''),
('page_csv_package','master_heading','CSV Package Types',''),
('page_csv_package','msg_staging_cleared','Temporary import staging data has been cleared.',''),
('page_csv_package','page_title','Data Package Transfer (CSV) - BCM Osiris',''),
/*#do# page_csv_package */

/*#od# page_excel_reader */
('page_excel_reader','btn_distribute','Distribute into System Metadata','Run the stored procedure to distribute imported sheets into meta_* tables'),
('page_excel_reader','btn_upload','Upload & Import into DB','Upload the selected XLSX workbook and store its sheets into _excel_* tables'),
('page_excel_reader','chk_drop_tables','Drop existing _excel_* tables before import',''),
('page_excel_reader','err_upload_failed','File upload failed.',''),
('page_excel_reader','heading_main','Import & Verify Data from Excel (XLSX)',''),
('page_excel_reader','lbl_select_file','Select Excel file (.xlsx):',''),
('page_excel_reader','lbl_sheets_overview','Database Sheets Overview:',''),
('page_excel_reader','msg_distribute_done','Distribution of data into system metadata tables completed.',''),
('page_excel_reader','msg_import_done','Workbook import into _excel_* tables completed successfully.',''),
('page_excel_reader','msg_rows_truncated','... Displaying only the first {$max} of {$total} total rows ...',''),
('page_excel_reader','page_title','Import Data from Excel - BCM Osiris',''),
/*#do# page_excel_reader */

/*#od# page_hierarchy */
('page_hierarchy','btn_manage_hierarchy_items','Manage Items ({$count}) →','Open management of nodes and items of this secondary hierarchy'),
('page_hierarchy','btn_new_hierarchy','+ New Secondary Hierarchy','Create a new folder or secondary hierarchy / tag set definition'),
('page_hierarchy','grp_identification','Code, Registry Placement & Icon',''),
('page_hierarchy','grp_presentation','Presentation Texts & Hierarchy Description',''),
('page_hierarchy','grp_rules_protection','Assignment Rules, Permissions & Protection',''),
('page_hierarchy','header_edit_hierarchy','Secondary Hierarchy',''),
('page_hierarchy','header_new_hierarchy','New Secondary Hierarchy / Tag Set',''),
('page_hierarchy','master_heading','Secondary Hierarchies & Tag Sets Registry',''),
('page_hierarchy','msg_folder_no_items_notice','This record is an organizational folder in the hierarchy registry (is_leaf = 0). Value items can only be inserted into terminal hierarchies (where Standalone Hierarchy is checked).',''),
('page_hierarchy','page_title','Secondary Hierarchies & Tags (CRMM)',''),
('page_hierarchy','th_hierarchy_caption','Secondary Hierarchy / Tag Set',''),
/*#do# page_hierarchy */

/*#od# page_hierarchy_item */
('page_hierarchy_item','btn_back_to_hierarchy','← Back to Hierarchy: {$parent}','Return to the secondary hierarchies registry'),
('page_hierarchy_item','btn_new_hierarchy_item','+ New Hierarchy Item','Create a new node or terminal item in the selected hierarchy'),
('page_hierarchy_item','grp_identification','Parent Hierarchy, Code & Tree Placement',''),
('page_hierarchy_item','grp_presentation','Presentation Texts, Color & Icon',''),
('page_hierarchy_item','grp_protection','Permissions, Validity & Record Protection',''),
('page_hierarchy_item','header_edit_item','Hierarchy Item',''),
('page_hierarchy_item','header_new_item','New Secondary Hierarchy Item',''),
('page_hierarchy_item','lbl_select_hierarchy','Select Secondary Hierarchy / Tag Set:',''),
('page_hierarchy_item','master_heading','Hierarchy Items Tree',''),
('page_hierarchy_item','msg_no_leaf_hierarchy_defined','No terminal hierarchy (is_leaf = 1) is defined in the registry yet. Please create one first on the Secondary Hierarchies & Tags page.',''),
('page_hierarchy_item','page_title','Secondary Hierarchy Items (CRMM)',''),
('page_hierarchy_item','page_title_with_hier','Hierarchy Items: {$hierarchy}',''),
('page_hierarchy_item','th_item_caption','Hierarchy Item / Tag',''),
/*#do# page_hierarchy_item */

/*#od# page_impact */
('page_impact','btn_new_impact','+ New Impact','Create a new impact area or item in the catalog'),
('page_impact','grp_identification','Code, Tree Placement & Icon',''),
('page_impact','grp_permissions_protection','Permissions, Validity & Record Protection',''),
('page_impact','grp_presentation','Presentation Texts & Impact Description',''),
('page_impact','header_edit_impact','Impact',''),
('page_impact','header_new_impact','New Impact',''),
('page_impact','master_heading','Impact Catalog Tree',''),
('page_impact','page_title','Impact Catalog (CRMM)',''),
('page_impact','th_impact_caption','Impact Type / Area',''),
/*#do# page_impact */

/*#od# page_link */
('page_link','badge_derived','Derived',''),
('page_link','btn_back_to_asset','← Back to Asset: {$asset}','Return to the filtered asset detail'),
('page_link','btn_back_to_diagram','← Back to Network Diagram: {$diagram}','Return to the network diagram detail'),
('page_link','btn_new_link','+ New Object Link','Create a new link between objects'),
('page_link','grp_link_endpoints','Link Type, Source & Target Object',''),
('page_link','grp_weight_note','Risk Transfer Weight, Origin, Note & Validity',''),
('page_link','header_edit_link','Object Link Detail',''),
('page_link','header_new_link','New Object Link',''),
('page_link','lbl_filter_link_def','Link Type (link_def):',''),
('page_link','lbl_show_removed','Show Removed',''),
('page_link','master_heading','Links & Dependencies List',''),
('page_link','msg_derived_link_readonly','This link was automatically generated by hierarchy inheritance, from the parent_uuid column, or by network diagram projection (is_derived = 1). Derived links are read-only; edit the source record or diagram instead.',''),
('page_link','opt_all_link_defs','--- All Link Types ---',''),
('page_link','opt_select_default','--- Select ---',''),
('page_link','page_title','Asset Links & Dependencies (CRMM)',''),
('page_link','placeholder_search','Search links...',''),
('page_link','th_from_object','Source (From)',''),
('page_link','th_link_def','Link Type',''),
('page_link','th_to_object','Target (To)',''),
/*#do# page_link */

/*#od# page_link_diagram */
('page_link_diagram','badge_cycle_error','Class Cycle Detected!',''),
('page_link_diagram','badge_self_loop','Intra-Class Traversal (Self-Referencing)',''),
('page_link_diagram','badge_top_class','Top-Level Class',''),
('page_link_diagram','btn_diagram_derived_defs','Derived Relationships ({$count}) →','View indirect relationships generated from this diagram'),
('page_link_diagram','btn_diagram_edges','Network Edges & Links ({$edges} / {$links}) →','Manage diagram edges and view projected indirect links'),
('page_link_diagram','btn_new_diagram','+ New Network Diagram (Schema)','Create a new heterogeneous network relationship diagram'),
('page_link_diagram','btn_rebuild_diagram','↻ Recalculate & Project Network','Evaluate diagram topology and project indirect relationships and links'),
('page_link_diagram','grp_identification','Identification, Ordering, Appearance & Validity',''),
('page_link_diagram','grp_presentation','Presentation Texts & Network Schema Description',''),
('page_link_diagram','hdr_diagram_class_topology','Class Topology in Heterogeneous Network (Top-Level Classes → Subordinate Classes):',''),
('page_link_diagram','header_edit_diagram','Network Schema',''),
('page_link_diagram','header_new_diagram','New Network Relationship Diagram',''),
('page_link_diagram','msg_diagram_no_edges','No directed relationships are assigned to this network schema yet. Click "Network Edges & Links" in the detail header and add relationships using "diagram_includes_link_def".',''),
('page_link_diagram','msg_new_diagram_hint','Tip: After saving the network schema, use the "Network Edges & Links" button to assign directed relationships (diagram_includes_link_def) and click "Recalculate & Project Network".',''),
('page_link_diagram','page_title','Network Relationship Diagrams (CRMM)',''),
('page_link_diagram','th_builtin_code','Code',''),
('page_link_diagram','th_diagram_caption','Network Schema Name',''),
('page_link_diagram','th_sort_code','Order',''),
/*#do# page_link_diagram */

/*#od# page_main */
('page_main','empty_menu','No items are available in this folder for your current role.',''),
('page_main','heading_dashboard','Application Dashboard',''),
('page_main','page_title','Main Dashboard - BCM Osiris',''),
/*#do# page_main */

/*#od# page_meta_class */
('page_meta_class','btn_manage_columns','Manage Columns ({$count}) →','Open column definitions for the selected logical class'),
('page_meta_class','grp_identification','Technical Identification & Storage',''),
('page_meta_class','grp_presentation','Presentation Texts & Translations',''),
('page_meta_class','grp_settings','Trash Retention, Permissions & Protection',''),
('page_meta_class','header_detail','Logical Class',''),
('page_meta_class','page_title','Logical Classes (Objects) - BCM Osiris',''),
/*#do# page_meta_class */

/*#od# page_meta_column */
('page_meta_column','btn_back_to_class','← Back to Class: {$parent}','Return to the parent logical class detail'),
('page_meta_column','grp_behavior','Behavior, Translation, History & Protection',''),
('page_meta_column','grp_form_ui','Form Control & Master List Display',''),
('page_meta_column','grp_identification','Technical Identification & Inheritance',''),
('page_meta_column','grp_presentation','Labels, Headers & Help Text',''),
('page_meta_column','grp_relations','Codetable & Logical Class References',''),
('page_meta_column','header_detail','Metadata Column',''),
('page_meta_column','lbl_select_class','Select Logical Class (Object):',''),
('page_meta_column','page_title','Metadata Columns - BCM Osiris',''),
('page_meta_column','page_title_class','Columns: {$class}',''),
/*#do# page_meta_column */

/*#od# page_meta_link_def */
('page_meta_link_def','btn_new_link_def','+ New Link Type','Create a new relationship type definition in meta_link_def'),
('page_meta_link_def','grp_identification','Link Code, Direction & Connected Logical Classes',''),
('page_meta_link_def','grp_presentation','Presentation Link Captions (Forward / Backward) & Help',''),
('page_meta_link_def','grp_rules_protection','Linking Rules, Weight, Origin & Protection',''),
('page_meta_link_def','header_edit_link_def','Link Type',''),
('page_meta_link_def','header_new_link_def','New Link Type Definition',''),
('page_meta_link_def','msg_derived_link_def_readonly','This indirect relationship was automatically generated from a heterogeneous network schema (is_derived = 1). It is updated by recalculating the corresponding network diagram.',''),
('page_meta_link_def','page_title','Link Type Definitions (CRMM)',''),
('page_meta_link_def','th_caption_forward','Forward Caption',''),
('page_meta_link_def','th_direction_type','Dir.',''),
('page_meta_link_def','th_link_code','Link Code',''),
/*#do# page_meta_link_def */

/*#od# page_meta_menu */
('page_meta_menu','btn_new_menu_item','+ New Menu Item','Create a new folder or link in the navigation menu'),
('page_meta_menu','grp_identification','Code, Parent Folder & Tree Order',''),
('page_meta_menu','grp_navigation','Target Page, URL Parameters & Permissions',''),
('page_meta_menu','grp_presentation','Caption, Help Text & Vector Icon',''),
('page_meta_menu','grp_protection','Validity & Record Protection',''),
('page_meta_menu','header_edit_menu','Menu Item',''),
('page_meta_menu','header_new_menu','New Menu Item',''),
('page_meta_menu','master_heading','Navigation Menu Tree',''),
('page_meta_menu','page_title','Menu Items (Navigation) - BCM Osiris',''),
('page_meta_menu','th_menu_caption','Menu Item',''),
/*#do# page_meta_menu */

/*#od# page_meta_phrase */
('page_meta_phrase','btn_new_phrase','+ New Text Phrase','Create a new localizable text phrase or button label'),
('page_meta_phrase','grp_ai_protection','Translation Context (AI) & Protection',''),
('page_meta_phrase','grp_identification','Source Class & Unique Phrase Code',''),
('page_meta_phrase','grp_presentation','Phrase Text, Tooltip & Button Styling',''),
('page_meta_phrase','header_edit_phrase','Text Phrase',''),
('page_meta_phrase','header_new_phrase','New Text Phrase',''),
('page_meta_phrase','lbl_filter_source','Filter by Source (source_code):',''),
('page_meta_phrase','opt_all_sources','--- All Sources (Pages & Classes) ---',''),
('page_meta_phrase','page_title','Text Phrases & Translations - BCM Osiris',''),
/*#do# page_meta_phrase */

/*#od# page_org_users */
('page_org_users','badge_admin','Org. Admin',''),
('page_org_users','badge_inactive','Inactive',''),
('page_org_users','badge_pending','Access Request',''),
('page_org_users','badge_translator','Translator',''),
('page_org_users','btn_new_user','+ Add / Assign User','Create a new user or assign an existing account to this organization'),
('page_org_users','err_email_required','User email address is required.',''),
('page_org_users','err_login_exists','The specified login name already exists for another account.',''),
('page_org_users','err_login_required','Login name is required.',''),
('page_org_users','err_password_too_short','New password must be at least 8 characters long.',''),
('page_org_users','grp_access_permissions','Permissions & Assignment in This Organization',''),
('page_org_users','grp_account_identity','Login Account & Personal Details',''),
('page_org_users','grp_password_security','Password & Account Security Settings',''),
('page_org_users','header_edit_user','Organization User',''),
('page_org_users','header_new_user','New Organization User',''),
('page_org_users','lbl_new_password','New Password (fill in only when changing):',''),
('page_org_users','master_heading','Organization Users & Access',''),
('page_org_users','msg_user_saved','User details and organization access settings have been saved.',''),
('page_org_users','page_title','Organization Users - BCM Osiris',''),
('page_org_users','th_dept_job','Department / Job Title',''),
('page_org_users','th_login','Login',''),
('page_org_users','th_name','Full Name',''),
('page_org_users','th_roles','Roles & Rights',''),
/*#do# page_org_users */

/*#od# page_organization */
('page_organization','btn_delete_logo','Delete Logo','Remove the stored organization logo image'),
('page_organization','grp_address_contact','Headquarters Address, Identification & Billing',''),
('page_organization','grp_crmm_limits','CRMM Methodology Parameters & Score Limits',''),
('page_organization','grp_general','Name, Short Name, SSO Domain & Description',''),
('page_organization','grp_logo','Organization Graphic Logo',''),
('page_organization','grp_regional_formats','Regional Formats, Currency & Separators',''),
('page_organization','header_edit_org','Organization Settings',''),
('page_organization','lbl_current_logo','Current Logo:',''),
('page_organization','lbl_upload_logo','Upload New Logo (PNG, SVG, JPG, max. 512 KB):',''),
('page_organization','msg_logo_deleted','Organization logo has been removed.',''),
('page_organization','msg_logo_too_large','Logo file exceeds the maximum allowed size of 512 KB.',''),
('page_organization','msg_logo_uploaded','Organization logo has been updated successfully.',''),
('page_organization','page_title','Organization Management & Settings - BCM Osiris',''),
/*#do# page_organization */

/*#od# page_organization_licence */
('page_organization_licence','btn_new_licence','+ New Organization Licence','Create a new licence record to set up and activate an organization'),
('page_organization_licence','grp_admin_account','Initial Administrator of the Organization',''),
('page_organization_licence','grp_licence_params','Licence Parameters, Tier & Activation State',''),
('page_organization_licence','grp_notes_validity','Notes & Licence Temporal Validity',''),
('page_organization_licence','header_edit_licence','Organization Licence',''),
('page_organization_licence','header_new_licence','New Organization Licence',''),
('page_organization_licence','msg_activation_hint','When saved with state APPROVED, the system automatically creates the target organization, sets up the initial administrator, and sends an activation email.',''),
('page_organization_licence','page_title','Organization Licence Management - BCM Osiris',''),
/*#do# page_organization_licence */

/*#od# page_scale */
('page_scale','btn_manage_scale_values','Manage Scale Levels ({$count}) →','Open management of individual levels, thresholds, and scores for this scale'),
('page_scale','btn_new_scale','+ New Assessment Scale','Create a new assessment scale and automatically generate default levels'),
('page_scale','grp_identification','Code, Quantity Type, Priority & Initial Level Count',''),
('page_scale','grp_presentation','Scale Name & Methodological Description',''),
('page_scale','grp_protection','Validity & Record Protection',''),
('page_scale','header_edit_scale','Assessment Scale',''),
('page_scale','header_new_scale','New Assessment Scale',''),
('page_scale','lbl_filter_scale_type','Filter by Scale Type:',''),
('page_scale','msg_initial_levels_hint','When saving a new scale for the first time, the system automatically generates the specified number of levels (initial_levels) evenly distributed across the 0 to 100% range.',''),
('page_scale','opt_all_scale_types','--- All Scale Types ---',''),
('page_scale','page_title','Assessment Scales (CRMM)',''),
('page_scale','th_builtin_code','Code',''),
('page_scale','th_caption','Scale Name',''),
('page_scale','th_priority','Priority',''),
('page_scale','th_scale_type','Type',''),
/*#do# page_scale */

/*#od# page_scale_value */
('page_scale_value','btn_back_to_scale','← Back to Scale: {$parent}','Return to the parent assessment scale detail'),
('page_scale_value','btn_new_scale_value','+ New Scale Level','Add a new level to the selected assessment scale'),
('page_scale_value','grp_identification','Parent Scale & Unique Level Code',''),
('page_scale_value','grp_presentation','Name, Short Name, Color & Level Description',''),
('page_scale_value','grp_protection','Validity & Record Protection',''),
('page_scale_value','grp_thresholds','Lower Interval Threshold & Calculation Score (0 to 100%)',''),
('page_scale_value','header_edit_level','Assessment Scale Level',''),
('page_scale_value','header_new_level','New Assessment Scale Level',''),
('page_scale_value','lbl_interval_preview','Effective Level Interval:',''),
('page_scale_value','lbl_select_scale','Select Assessment Scale:',''),
('page_scale_value','master_heading','Scale Levels (Sorted by Threshold)',''),
('page_scale_value','msg_no_scale_defined','No assessment scale is defined in the system yet. Please create one first on the Assessment Scales page.',''),
('page_scale_value','page_title','Assessment Scale Levels (CRMM)',''),
('page_scale_value','page_title_with_scale','Scale Levels: {$scale}',''),
('page_scale_value','th_level_caption','Scale Level',''),
('page_scale_value','th_score_value','Score (%)',''),
('page_scale_value','th_threshold_value','Threshold (%)',''),
/*#do# page_scale_value */

/*#od# page_scenario */
('page_scenario','btn_new_scenario','+ New Risk Scenario','Create a new group or leaf risk scenario in the catalog'),
('page_scenario','grp_identification','Code, Tree Placement & Icon',''),
('page_scenario','grp_permissions_protection','Permissions, Validity & Record Protection',''),
('page_scenario','grp_presentation','Presentation Texts & Scenario Description',''),
('page_scenario','grp_relations_risk','Causing Threat, Target Asset Class & Minimum Residual Risk',''),
('page_scenario','header_edit_scenario','Risk Scenario',''),
('page_scenario','header_new_scenario','New Risk Scenario',''),
('page_scenario','master_heading','Risk Scenario Tree',''),
('page_scenario','page_title','Risk Scenarios (CRMM Catalog)',''),
('page_scenario','th_min_res_risk','Min. Res.',''),
('page_scenario','th_scenario_caption','Risk Scenario',''),
/*#do# page_scenario */

/*#od# page_scenario_assessment */
('page_scenario_assessment','btn_back_to_asset','← Back to Asset: {$asset}','Return to the filtered asset detail'),
('page_scenario_assessment','btn_new_assessment','+ New Scenario Assessment','Create a new risk scenario assessment on an asset'),
('page_scenario_assessment','btn_recalculate_crmm','↻ Recalculate Risks','Recalculate effective control factors, scenario risks, and aggregated asset risks'),
('page_scenario_assessment','grp_asset_scenario','Assessed Asset & Risk Scenario',''),
('page_scenario_assessment','grp_calculated_risk','Calculated Inherent Risk, Reduction & Residual Risk (0 to 100%)',''),
('page_scenario_assessment','grp_input_scores','Input Threat, Vulnerability & Impact Scores (0 to 100%)',''),
('page_scenario_assessment','grp_justification_audit','Assessment Justification, Note & Assessor',''),
('page_scenario_assessment','header_edit_assessment','Scenario Assessment',''),
('page_scenario_assessment','header_new_assessment','New Risk Scenario Assessment',''),
('page_scenario_assessment','lbl_filter_asset','Assessed Asset:',''),
('page_scenario_assessment','lbl_sum_floor','Min. Floor:',''),
('page_scenario_assessment','lbl_sum_inherent','Inherent Risk:',''),
('page_scenario_assessment','lbl_sum_reduction','Control Reduction:',''),
('page_scenario_assessment','lbl_sum_residual','Residual Risk:',''),
('page_scenario_assessment','opt_all_assets','--- All Assessed Assets ---',''),
('page_scenario_assessment','page_title','Risk Scenario Assessments (CRMM)',''),
('page_scenario_assessment','th_assess_caption','Assessed Scenario / Description',''),
('page_scenario_assessment','th_assess_date','Date',''),
('page_scenario_assessment','th_inherent_risk','Inh. Risk (%)',''),
('page_scenario_assessment','th_residual_risk','Res. Risk (%)',''),
/*#do# page_scenario_assessment */

/*#od# page_service_logbook */
('page_service_logbook','btn_apply_filter','Filter','Filter service logbook entries by the specified criteria'),
('page_service_logbook','btn_reset_filter','Reset Filter','Clear filter criteria and display the latest logbook entries'),
('page_service_logbook','heading_logbook','Database Service Logbook (service_logbook)',''),
('page_service_logbook','intro_logbook','Chronological log of executed upgrade scripts (changes_YYYY.sql), metadata imports, and service operations (sorted descending from newest).',''),
('page_service_logbook','lbl_displayed_records','Displayed records: {$count}',''),
('page_service_logbook','lbl_filter_limit','Row limit:',''),
('page_service_logbook','lbl_filter_name','Script / operation name:',''),
('page_service_logbook','lbl_filter_text','Search description / version:',''),
('page_service_logbook','msg_no_records','No records in service_logbook match the specified criteria.',''),
('page_service_logbook','opt_all_scripts','--- All Scripts & Operations ---',''),
('page_service_logbook','page_title','Service Logbook (service_logbook) - BCM Osiris',''),
('page_service_logbook','ph_filter_text','Enter search text or version number...',''),
('page_service_logbook','th_content','Content / Change Description',''),
('page_service_logbook','th_date','Date & Time',''),
('page_service_logbook','th_id','ID',''),
('page_service_logbook','th_name','Script / Operation',''),
('page_service_logbook','th_original_login','SQL Login',''),
('page_service_logbook','th_servername','Server',''),
('page_service_logbook','th_version','Version',''),
/*#do# page_service_logbook */

/*#od# page_threat */
('page_threat','btn_new_threat','+ New Threat','Create a new group or leaf threat in the catalog'),
('page_threat','grp_evaluation','Default Threat Evaluation',''),
('page_threat','grp_identification','Code, Tree Placement & Icon',''),
('page_threat','grp_permissions_protection','Permissions, Validity & Record Protection',''),
('page_threat','grp_presentation','Presentation Texts & Threat Description',''),
('page_threat','header_edit_threat','Threat',''),
('page_threat','header_new_threat','New Threat',''),
('page_threat','master_heading','Threat Catalog Tree',''),
('page_threat','page_title','Threat Catalog (CRMM)',''),
('page_threat','th_default_score','Default Score',''),
('page_threat','th_threat_caption','Threat',''),
/*#do# page_threat */

/*#od# page_xlsx_export_meta */
('page_xlsx_export_meta','btn_download_xlsx','Generate & Download XLSX','Build the Excel workbook with system metadata and download it'),
('page_xlsx_export_meta','heading_export','Export System Metadata to Excel (XLSX)',''),
('page_xlsx_export_meta','intro_export','This tool generates a multi-sheet XLSX workbook containing the current state of system metadata (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def).',''),
('page_xlsx_export_meta','lbl_filter_only_custom','Export only records customized in the UI (who_modified <> 0x00)',''),
('page_xlsx_export_meta','page_title','Export Metadata to Excel - BCM Osiris',''),
/*#do# page_xlsx_export_meta */

/*#od# rich_text */
('rich_text','btn_apply_text','Apply to Detail','Transfer the edited text from the modal editor into the form (click Save Changes afterwards to store in DB)'),
('rich_text','btn_cancel_text','Cancel','Close the modal editor without applying changes to the form'),
('rich_text','btn_edit_text','Edit Text','Open the foreground WYSIWYG / Markdown modal editor'),
('rich_text','confirm_convert_format','Convert existing text to the newly selected format?',''),
('rich_text','lbl_format_select','Storage format:',''),
('rich_text','lbl_modal_title','Edit Formatted Text:',''),
('rich_text','msg_modal_hint','Remember to save the main form after applying the text to store changes permanently in the database.',''),
('rich_text','opt_format_html','Pure HTML',''),
('rich_text','opt_format_markdown','Markdown (preferred)',''),
('rich_text','tip_convert_format','Converts existing text between Markdown and HTML formats and switches editor mode',''),
('rich_text','tip_open_editor','Open foreground rich text editor',''),
('rich_text','txt_empty_prev','(Empty – click Edit Text)',''),
('rich_text','txt_empty_preview','(Empty – click Edit)',''),
/*#do# rich_text */

/*#od# svg_icon_editor */
('svg_icon_editor','btn_apply_svg','Apply to Detail','Transfer the validated SVG icon into the form preview'),
('svg_icon_editor','btn_cancel_svg','Cancel','Close the SVG icon editor without applying changes'),
('svg_icon_editor','btn_clear_svg','Clear','Remove the SVG icon'),
('svg_icon_editor','btn_edit_svg','Edit Icon','Open the modal SVG vector icon editor'),
('svg_icon_editor','btn_validate_svg','Validate Syntax & Clean','Validate XML syntax and sanitize the SVG code'),
('svg_icon_editor','err_js_not_svg_root','Code must contain a root <svg>...</svg> element.',''),
('svg_icon_editor','err_js_xml_invalid','Invalid XML syntax: ',''),
('svg_icon_editor','err_svg_not_root','The root element of the icon must be an <svg> tag.',''),
('svg_icon_editor','err_svg_xml_syntax','SVG icon syntax error: {$detail}',''),
('svg_icon_editor','lbl_live_preview','Live Preview & Syntax Check:',''),
('svg_icon_editor','lbl_modal_title','Vector Icon Editor (SVG):',''),
('svg_icon_editor','lbl_no_svg_icon','Icon not set (double-click to edit)',''),
('svg_icon_editor','lbl_svg_code_input','SVG Icon Source Code (paste <svg ...>...</svg>):',''),
('svg_icon_editor','lbl_svg_sources','Get SVG Icon Code:',''),
('svg_icon_editor','msg_modal_hint','Tip: Icons with fill="currentColor" or without a fill attribute automatically inherit text color in menus and buttons. Custom colors (e.g., fill="#...") are preserved everywhere.',''),
('svg_icon_editor','msg_svg_empty_ok','Icon is empty (will be cleared upon confirmation).',''),
('svg_icon_editor','msg_syntax_ok','✓ SVG syntax is valid.',''),
('svg_icon_editor','tip_open_svg_editor','Double-click or click the button to open the SVG vector icon editor',''),
('svg_icon_editor','tip_svg_ext_source','Opens the icon catalog in a new tab (copy the SVG icon code and paste it here)',''),
/*#do# svg_icon_editor */

/*#od# user_context */
('user_context','btn_logout','Log Out','End the current session and log out of the system'),
('user_context','lbl_default_org','Organization',''),
('user_context','lbl_default_user','User',''),
('user_context','lbl_logo_placeholder','[ Logo / Graphics ]',''),
('user_context','role_admin','ADMIN',''),
('user_context','role_dev','DEV',''),
('user_context','role_sysadmin','SYSADMIN',''),
('user_context','role_user','USER',''),
('user_context','tip_change_context','Change organization or role',''),
('user_context','tip_current_org','Current organization',''),
('user_context','tip_logged_user','Logged-in user','');
/*#do# user_context */

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
UPDATE l
SET l.caption = s.caption,
	l.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END,
	l.who_modified = @sys_owner,
	l.date_modified = GETDATE()
FROM meta_phrase l
JOIN meta_phrase a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
JOIN @phr_en s
	ON s.source_code = a.source_code
	AND s.builtin_code = a.builtin_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT l.caption, l.helptext
	EXCEPT
	SELECT s.caption, CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
INSERT INTO meta_phrase (
	uuid, object_owner, original, record_type, approval_status, [language],
	source_code, builtin_code, module, caption, helptext, svg_icon, css_class,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.source_code, a.builtin_code, a.module,
	s.caption,
	CASE WHEN s.helptext <> '' THEN s.helptext ELSE a.helptext END,
	a.svg_icon, a.css_class,
	a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_phrase a
JOIN @phr_en s
	ON s.source_code = a.source_code
	AND s.builtin_code = a.builtin_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_phrase l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'en'
  );
GO