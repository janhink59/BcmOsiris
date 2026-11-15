/* =============================================================================
 * Verze: 2026-11-15 19:55
 * Soubor: page_approval#phrase.sql
 * Účel:   Registrace stránky page_approval do sysinit_object, položky menu
 *         approval do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_approval';
DELETE FROM sysinit_menu WHERE builtin_code = 'approval';
DELETE FROM sysinit_phrase WHERE source_code = 'page_approval';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_approval','cs','U','Schvalování změn','Přehled, porovnání a schvalování navržených záznamů napříč třídami'),
('P','page_approval','en','U','Change Approval','Overview, comparison, and approval of proposed records across classes');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('approval','cs','admin_folder','010','page_approval','','U','<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>','Schvalování změn','Posouzení, schvalování a vracení navržených změn záznamů','Posouzení, schvalování a vracení navržených změn záznamů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('approval','en','Change Approval','Review, approval, and rejection of proposed record changes','Review, approval, and rejection of proposed record changes');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_approval','badge_remove_proposal','cs','Zrušení','',''),
('page_approval','btn_approve_draft','cs','Schválit návrh','Schválí vybraný návrh a promítne změnu do platných dat (stav A)','btn-success'),
('page_approval','btn_bulk_approve','cs','Schválit vybrané','Hromadně schválí všechny zaškrtnuté návrhy v seznamu','btn-success'),
('page_approval','btn_bulk_reject','cs','Odmítnout vybrané','Hromadně vrátí zaškrtnuté návrhy autorům k přepracování','btn-danger'),
('page_approval','btn_reject_draft','cs','Odmítnout / Vrátit','Vrátí návrh autorovi k přepracování s uvedenou poznámkou (stav R)','btn-danger'),
('page_approval','detail_heading','cs','Posouzení návrhu','',''),
('page_approval','lbl_approval_note','cs','Poznámka schvalovatele (důvod vrácení / odmítnutí):','',''),
('page_approval','lbl_filter_class','cs','Filtrovat podle logické třídy:','',''),
('page_approval','lbl_proposal_author','cs','Autor návrhu:','',''),
('page_approval','lbl_proposal_date','cs','Datum předání:','',''),
('page_approval','lbl_proposal_new_record','cs','Návrh nového záznamu (INSERT)','',''),
('page_approval','lbl_proposal_update_record','cs','Návrh úpravy existujícího záznamu (UPDATE)','',''),
('page_approval','lbl_show_raw_source','cs','Zobrazit zdrojový text (Markdown / HTML)','',''),
('page_approval','master_heading','cs','Návrhy čekající na schválení','',''),
('page_approval','msg_competing_proposals_warning','cs','Upozornění: K tomuto záznamu existují i další souběžné návrhy. Schválením tohoto návrhu budou ostatní souběžné návrhy automaticky odmítnuty:','',''),
('page_approval','msg_invalid_target_class','cs','Cílová logická třída nebyla nalezena.','',''),
('page_approval','msg_no_pending_approvals','cs','V aktuálním jazyce momentálně nečekají žádné návrhy na schválení.','',''),
('page_approval','msg_proposal_not_found','cs','Návrh nebyl nalezen nebo již byl zpracován.','',''),
('page_approval','msg_select_at_least_one','cs','Zaškrtněte prosím alespoň jeden návrh v seznamu.','',''),
('page_approval','msg_select_proposal_from_left','cs','Vyberte návrh ke schválení z levého panelu.','',''),
('page_approval','opt_all_classes','cs','--- Všechny logické třídy ---','',''),
('page_approval','page_title','cs','Schvalování navržených změn','',''),
('page_approval','ph_bulk_approval_note','cs','Důvod při hromadném odmítnutí...','',''),
('page_approval','placeholder_approval_note','cs','Zadejte důvod v případě vrácení návrhu k přepracování...','',''),
('page_approval','placeholder_search','cs','Hledat v návrzích...','',''),
('page_approval','th_approved_value','cs','Původní schválená hodnota','',''),
('page_approval','th_author','cs','Autor návrhu','',''),
('page_approval','th_class_and_record','cs','Třída / Záznam','',''),
('page_approval','th_date_forwarded','cs','Předáno','',''),
('page_approval','th_field_name','cs','Položka (Sloupec)','',''),
('page_approval','th_proposed_value','cs','Navrhovaná hodnota','',''),
('page_approval','tip_competing_proposals','cs','K tomuto záznamu sešlo {$count} souběžných návrhů','',''),
('page_approval','tip_select_all_proposals','cs','Označit / odznačit všechny zobrazené návrhy','',''),
('page_approval','txt_not_existing_yet','cs','(Nový záznam)','',''),
('page_approval','val_checkbox_no','cs','Ne','',''),
('page_approval','val_checkbox_yes','cs','Ano','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_approval','badge_remove_proposal','en','Removal',''),
('page_approval','btn_approve_draft','en','Approve Proposal','Approve the selected proposal and publish changes into active data (state A)'),
('page_approval','btn_bulk_approve','en','Approve Selected','Bulk approve all checked proposals in the list'),
('page_approval','btn_bulk_reject','en','Reject Selected','Bulk return checked proposals to their authors for revision'),
('page_approval','btn_reject_draft','en','Reject / Return','Return the proposal to its author for revision with a note (state R)'),
('page_approval','detail_heading','en','Proposal Review',''),
('page_approval','lbl_approval_note','en','Approver Note (Reason for Return / Rejection):',''),
('page_approval','lbl_filter_class','en','Filter by Logical Class:',''),
('page_approval','lbl_proposal_author','en','Proposal Author:',''),
('page_approval','lbl_proposal_date','en','Submitted On:',''),
('page_approval','lbl_proposal_new_record','en','New Record Proposal (INSERT)',''),
('page_approval','lbl_proposal_update_record','en','Existing Record Update Proposal (UPDATE)',''),
('page_approval','lbl_show_raw_source','en','Show raw source (Markdown / HTML)',''),
('page_approval','master_heading','en','Proposals Pending Approval',''),
('page_approval','msg_competing_proposals_warning','en','Warning: Other competing proposals exist for this record. Approving this proposal will automatically reject the other competing proposals:',''),
('page_approval','msg_invalid_target_class','en','Target logical class was not found.',''),
('page_approval','msg_no_pending_approvals','en','There are currently no proposals waiting for approval in the active language.',''),
('page_approval','msg_proposal_not_found','en','Proposal was not found or has already been processed.',''),
('page_approval','msg_select_at_least_one','en','Please check at least one proposal in the list.',''),
('page_approval','msg_select_proposal_from_left','en','Select a proposal for review from the left panel.',''),
('page_approval','opt_all_classes','en','--- All Logical Classes ---',''),
('page_approval','page_title','en','Proposed Changes Approval',''),
('page_approval','ph_bulk_approval_note','en','Reason for bulk rejection...',''),
('page_approval','placeholder_approval_note','en','Enter reason when returning the proposal for revision...',''),
('page_approval','placeholder_search','en','Search proposals...',''),
('page_approval','th_approved_value','en','Original Approved Value',''),
('page_approval','th_author','en','Proposal Author',''),
('page_approval','th_class_and_record','en','Class / Record',''),
('page_approval','th_date_forwarded','en','Submitted',''),
('page_approval','th_field_name','en','Field (Column)',''),
('page_approval','th_proposed_value','en','Proposed Value',''),
('page_approval','tip_competing_proposals','en','{$count} competing proposals exist for this record',''),
('page_approval','tip_select_all_proposals','en','Select / deselect all visible proposals',''),
('page_approval','txt_not_existing_yet','en','(New record)',''),
('page_approval','val_checkbox_no','en','No',''),
('page_approval','val_checkbox_yes','en','Yes','');
GO