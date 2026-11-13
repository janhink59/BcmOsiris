/* =============================================================================
 * Verze: 2026-11-13 16:15
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
('page_approval','badge_action_delete','cs','Návrh na zrušení (smazání)','',''),
('page_approval','badge_action_insert','cs','Nový záznam','',''),
('page_approval','badge_action_translation','cs','Překlad (L)','',''),
('page_approval','badge_action_update','cs','Úprava záznamu','',''),
('page_approval','btn_approve','cs','✓ Schválit a publikovat','Schválí vybraný návrh a promítne změnu do platných dat (stav A)','btn-success'),
('page_approval','btn_reject','cs','↩ Vrátit k přepracování','Vrátí návrh autorovi s připomínkou (stav R)','btn-danger'),
('page_approval','err_reject_note_required','cs','Při vrácení návrhu k přepracování musíte vyplnit důvod / připomínku pro autora.','',''),
('page_approval','hdr_comparison_table','cs','Porovnání navržených změn oproti platnému stavu','',''),
('page_approval','header_detail_default','cs','Posouzení návrhu změny','',''),
('page_approval','lbl_approval_note','cs','Stanovisko schvalovatele / důvod vrácení:','',''),
('page_approval','lbl_author','cs','Autor návrhu:','',''),
('page_approval','lbl_class','cs','Třída (entita):','',''),
('page_approval','lbl_date_modified','cs','Předáno dne:','',''),
('page_approval','lbl_filter_class','cs','Filtrovat podle třídy:','',''),
('page_approval','lbl_language','cs','Jazyk návrhu:','',''),
('page_approval','lbl_only_changed_rows','cs','Zobrazit pouze změněné položky','',''),
('page_approval','master_heading','cs','Návrhy čekající na schválení (stav F)','',''),
('page_approval','msg_approved_ok','cs','Návrh byl úspěšně schválen a publikován.','',''),
('page_approval','msg_competing_warning','cs','Upozornění: K tomuto záznamu existuje více souběžných návrhů od různých autorů. Schválením tohoto návrhu nahradíte aktuální platný stav; ostatní neuzavřené návrhy zůstanou autorům k dispozici.','',''),
('page_approval','msg_empty_queue','cs','Momentálně nejsou ve frontě žádné návrhy čekající na schválení.','',''),
('page_approval','msg_rejected_ok','cs','Návrh byl vrácen autorovi k přepracování.','',''),
('page_approval','msg_select_proposal','cs','Vyberte návrh v levém seznamu pro zobrazení porovnání hodnot a rozhodnutí.','',''),
('page_approval','opt_all_classes','cs','--- Všechny třídy ---','',''),
('page_approval','page_title','cs','Schvalování změn - BCM Osiris','',''),
('page_approval','ph_approval_note','cs','Zadejte komentář ke schválení nebo povinné zdůvodnění při vrácení návrhu...','',''),
('page_approval','th_author','cs','Autor','',''),
('page_approval','th_caption','cs','Záznam / Název','',''),
('page_approval','th_class','cs','Třída','',''),
('page_approval','th_current_val','cs','Platná hodnota (A)','',''),
('page_approval','th_date','cs','Datum','',''),
('page_approval','th_field_name','cs','Položka (Sloupec)','',''),
('page_approval','th_proposed_val','cs','Navrhovaná hodnota (F)','',''),
('page_approval','tip_competing_proposals','cs','K tomuto záznamu sešlo {$count} souběžných návrhů','',''),
('page_approval','txt_new_record_no_active','cs','(Nový záznam – dosud neexistuje schválená verze)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_approval','badge_action_delete','en','Deletion Proposal',''),
('page_approval','badge_action_insert','en','New Record',''),
('page_approval','badge_action_translation','en','Translation (L)',''),
('page_approval','badge_action_update','en','Record Update',''),
('page_approval','btn_approve','en','✓ Approve & Publish','Approve the selected proposal and publish changes into active data (state A)'),
('page_approval','btn_reject','en','↩ Return for Revision','Return the proposal to its author with comments (state R)'),
('page_approval','err_reject_note_required','en','You must provide a reason / comment for the author when returning a proposal for revision.',''),
('page_approval','hdr_comparison_table','en','Comparison of Proposed Changes Against Current Active State',''),
('page_approval','header_detail_default','en','Change Proposal Review',''),
('page_approval','lbl_approval_note','en','Approver Decision Note / Reason for Return:',''),
('page_approval','lbl_author','en','Proposal Author:',''),
('page_approval','lbl_class','en','Class (Entity):',''),
('page_approval','lbl_date_modified','en','Submitted On:',''),
('page_approval','lbl_filter_class','en','Filter by Class:',''),
('page_approval','lbl_language','en','Proposal Language:',''),
('page_approval','lbl_only_changed_rows','en','Show Modified Fields Only',''),
('page_approval','master_heading','en','Proposals Pending Approval (State F)',''),
('page_approval','msg_approved_ok','en','Proposal was approved and published successfully.',''),
('page_approval','msg_competing_warning','en','Warning: Multiple competing proposals from different authors exist for this record. Approving this proposal will replace the current active state; other open proposals will remain available to their authors.',''),
('page_approval','msg_empty_queue','en','There are currently no proposals waiting for approval.',''),
('page_approval','msg_rejected_ok','en','Proposal was returned to the author for revision.',''),
('page_approval','msg_select_proposal','en','Select a proposal from the left list to review value differences and make a decision.',''),
('page_approval','opt_all_classes','en','--- All Classes ---',''),
('page_approval','page_title','en','Change Approval - BCM Osiris',''),
('page_approval','ph_approval_note','en','Enter an approval comment or a mandatory reason when returning the proposal...',''),
('page_approval','th_author','en','Author',''),
('page_approval','th_caption','en','Record / Name',''),
('page_approval','th_class','en','Class',''),
('page_approval','th_current_val','en','Current Active Value (A)',''),
('page_approval','th_date','en','Date',''),
('page_approval','th_field_name','en','Field (Column)',''),
('page_approval','th_proposed_val','en','Proposed Value (F)',''),
('page_approval','tip_competing_proposals','en','{$count} competing proposals exist for this record',''),
('page_approval','txt_new_record_no_active','en','(New record – no approved version exists yet)','');
GO