/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: page_change_user_context#phrase.sql
 * Účel:   Registrace stránky page_change_user_context do sysinit_object
 *         a naplnění jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_change_user_context';
DELETE FROM sysinit_phrase WHERE source_code = 'page_change_user_context';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_change_user_context','cs','U','Změna kontextu uživatele','Přepínání aktivní organizace, aplikační role a žádosti o přístup'),
('P','page_change_user_context','en','U','Change User Context','Switching active organization, application role, and access requests');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_change_user_context','badge_current','cs','Aktivní','',''),
('page_change_user_context','badge_disabled','cs','Blokováno','',''),
('page_change_user_context','badge_pending','cs','Čeká na schválení','',''),
('page_change_user_context','btn_apply_context','cs','Přepnout kontext','Aktivuje vybranou organizaci a aplikační roli pro aktuální relaci','btn-success'),
('page_change_user_context','btn_cancel_request','cs','Zrušit žádost','Stornuje vaši dosud neschválenou žádost o přístup','btn-danger'),
('page_change_user_context','btn_request_access','cs','Požádat o přístup','Odešle administrátorovi vybrané organizace žádost o přiřazení přístupu',''),
('page_change_user_context','btn_save_working_date','cs','Uložit pracovní datum','Nastaví zvolené pracovní datum pro vyhodnocování časové platnosti záznamů','btn-secondary'),
('page_change_user_context','hdr_available_orgs','cs','Dostupné organizace a volba aplikační role','',''),
('page_change_user_context','hdr_request_access','cs','Žádost o přístup do další organizace','',''),
('page_change_user_context','hdr_working_date','cs','Osobní pracovní datum (časový řez platnosti dat)','',''),
('page_change_user_context','lbl_select_org_request','cs','Vyberte organizaci:','',''),
('page_change_user_context','lbl_select_role','cs','Zvolte roli pro přihlášení:','',''),
('page_change_user_context','lbl_working_date','cs','Pracovní datum (prázdné = dnešní datum):','',''),
('page_change_user_context','msg_context_switched','cs','Kontext organizace a role byl úspěšně změněn.','',''),
('page_change_user_context','msg_request_cancelled','cs','Žádost o přístup byla zrušena.','',''),
('page_change_user_context','msg_request_sent','cs','Žádost o přístup do organizace byla odeslána ke schválení.','',''),
('page_change_user_context','msg_working_date_saved','cs','Pracovní datum bylo uloženo.','',''),
('page_change_user_context','page_title','cs','Změna kontextu uživatele - BCM Osiris','',''),
('page_change_user_context','th_action','cs','Akce','',''),
('page_change_user_context','th_licence_level','cs','Licence','',''),
('page_change_user_context','th_organization','cs','Organizace','',''),
('page_change_user_context','th_role','cs','Dostupné role','',''),
('page_change_user_context','th_status','cs','Stav','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_change_user_context','badge_current','en','Active',''),
('page_change_user_context','badge_disabled','en','Disabled',''),
('page_change_user_context','badge_pending','en','Pending Approval',''),
('page_change_user_context','btn_apply_context','en','Switch Context','Activate the selected organization and application role for the current session'),
('page_change_user_context','btn_cancel_request','en','Cancel Request','Withdraw your pending access request'),
('page_change_user_context','btn_request_access','en','Request Access','Send an access request to the administrator of the selected organization'),
('page_change_user_context','btn_save_working_date','en','Save Working Date','Set the personal working date used to evaluate temporal validity of records'),
('page_change_user_context','hdr_available_orgs','en','Available Organizations & Role Selection',''),
('page_change_user_context','hdr_request_access','en','Request Access to Another Organization',''),
('page_change_user_context','hdr_working_date','en','Personal Working Date (Temporal Validity Slice)',''),
('page_change_user_context','lbl_select_org_request','en','Select organization:',''),
('page_change_user_context','lbl_select_role','en','Select login role:',''),
('page_change_user_context','lbl_working_date','en','Working date (empty = today):',''),
('page_change_user_context','msg_context_switched','en','Organization and role context switched successfully.',''),
('page_change_user_context','msg_request_cancelled','en','Access request has been cancelled.',''),
('page_change_user_context','msg_request_sent','en','Access request has been sent for approval.',''),
('page_change_user_context','msg_working_date_saved','en','Working date has been saved.',''),
('page_change_user_context','page_title','en','Change User Context - BCM Osiris',''),
('page_change_user_context','th_action','en','Action',''),
('page_change_user_context','th_licence_level','en','Licence',''),
('page_change_user_context','th_organization','en','Organization',''),
('page_change_user_context','th_role','en','Available Roles',''),
('page_change_user_context','th_status','en','Status','');
GO