/* =============================================================================
 * Verze: 2026-11-15 19:55
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
('page_change_user_context','badge_invitation','cs','Pozvánka od administrátora','',''),
('page_change_user_context','badge_request_rejected','cs','Zamítnuto / Vráceno','',''),
('page_change_user_context','badge_waiting_approval','cs','Čeká na schválení v organizaci','',''),
('page_change_user_context','btn_accept_invite','cs','Přijmout pozvánku','Přijme pozvánku a aktivuje váš přístup do této organizace','btn-success'),
('page_change_user_context','btn_cancel_request','cs','Zrušit / Smazat žádost','Odstraní vaši nevyřízenou nebo zamítnutou žádost o přístup','btn-danger'),
('page_change_user_context','btn_reject_invite','cs','Odmítnout','Odmítne pozvánku do organizace','btn-danger'),
('page_change_user_context','btn_request_access','cs','Odeslat žádost o přístup','Odešle administrátorovi vybrané organizace žádost o schválení přístupu',''),
('page_change_user_context','btn_switch_context','cs','Přepnout kontext','Aktivuje vybranou organizaci a roli pro aktuální sezení','btn-success'),
('page_change_user_context','desc_request_new_org','cs','Pokud potřebujete pracovat i v jiné organizaci, odešlete žádost jejímu administrátorovi ke schválení:','',''),
('page_change_user_context','err_context_save','cs','Nepodařilo se zapsat novou relaci.','',''),
('page_change_user_context','err_context_title','cs','Chyba při změně kontextu','',''),
('page_change_user_context','heading_change_org','cs','Změna pracovní organizace','',''),
('page_change_user_context','heading_pending_access','cs','Žádosti o přístup a pozvánky do organizací','',''),
('page_change_user_context','heading_request_new_org','cs','Požádat o přístup do další organizace','',''),
('page_change_user_context','intro_select_org_role','cs','Vyberte organizaci a roli, pod kterou se chcete přihlásit pro aktuální sezení:','',''),
('page_change_user_context','lbl_request_note','cs','Poznámka pro administrátora:','',''),
('page_change_user_context','lbl_role_admin','cs','Admin','',''),
('page_change_user_context','lbl_role_developer','cs','Developer','',''),
('page_change_user_context','lbl_role_sysadmin','cs','Sysadmin','',''),
('page_change_user_context','lbl_role_user','cs','User','',''),
('page_change_user_context','lbl_select_target_org','cs','Cílová organizace:','',''),
('page_change_user_context','lbl_system_core','cs','⚙ Systémové jádro (0x00)','',''),
('page_change_user_context','msg_no_org_access','cs','Nemáte přístup do žádných organizací ani k systémovým rolím.','',''),
('page_change_user_context','page_title','cs','Změna kontextu - BCM Osiris','',''),
('page_change_user_context','ph_reject_invite_reason','cs','Volitelný důvod odmítnutí...','',''),
('page_change_user_context','ph_request_note','cs','Volitelně uveďte důvod žádosti o přístup...','',''),
('page_change_user_context','th_base_role','cs','Základní role','',''),
('page_change_user_context','th_higher_role','cs','Vyšší role','',''),
('page_change_user_context','th_organization','cs','Organizace / Oblast','',''),
('page_change_user_context','th_pending_action','cs','Akce','',''),
('page_change_user_context','th_pending_org','cs','Organizace','',''),
('page_change_user_context','th_pending_status','cs','Stav a poznámka','',''),
('page_change_user_context','tip_enter_admin','cs','Vstoupit jako Administrátor','',''),
('page_change_user_context','tip_enter_developer','cs','Vstoupit jako Developer','',''),
('page_change_user_context','tip_enter_sysadmin','cs','Vstoupit jako Sysadmin','',''),
('page_change_user_context','tip_enter_user','cs','Vstoupit jako Uživatel','',''),
('page_change_user_context','tip_no_admin_rights','cs','Nemáte administrátorská práva','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_change_user_context','badge_invitation','en','Invitation from Administrator',''),
('page_change_user_context','badge_request_rejected','en','Rejected / Returned',''),
('page_change_user_context','badge_waiting_approval','en','Waiting for Organization Approval',''),
('page_change_user_context','btn_accept_invite','en','Accept Invitation','Accept the invitation and activate your access to this organization'),
('page_change_user_context','btn_cancel_request','en','Cancel / Delete Request','Delete your pending or rejected access request'),
('page_change_user_context','btn_reject_invite','en','Decline','Decline the organization invitation'),
('page_change_user_context','btn_request_access','en','Submit Access Request','Send an access request to the administrator of the selected organization'),
('page_change_user_context','btn_switch_context','en','Switch Context','Activate the selected organization and role for the current session'),
('page_change_user_context','desc_request_new_org','en','If you need to work in another organization, send a request to its administrator for approval:',''),
('page_change_user_context','err_context_save','en','Failed to save the new session context.',''),
('page_change_user_context','err_context_title','en','Context Switch Error',''),
('page_change_user_context','heading_change_org','en','Change Working Organization',''),
('page_change_user_context','heading_pending_access','en','Access Requests & Organization Invitations',''),
('page_change_user_context','heading_request_new_org','en','Request Access to Another Organization',''),
('page_change_user_context','intro_select_org_role','en','Select the organization and role under which you want to work in the current session:',''),
('page_change_user_context','lbl_request_note','en','Note for Administrator:',''),
('page_change_user_context','lbl_role_admin','en','Admin',''),
('page_change_user_context','lbl_role_developer','en','Developer',''),
('page_change_user_context','lbl_role_sysadmin','en','Sysadmin',''),
('page_change_user_context','lbl_role_user','en','User',''),
('page_change_user_context','lbl_select_target_org','en','Target Organization:',''),
('page_change_user_context','lbl_system_core','en','⚙ System Core (0x00)',''),
('page_change_user_context','msg_no_org_access','en','You do not have access to any organizations or system roles.',''),
('page_change_user_context','page_title','en','Change Context - BCM Osiris',''),
('page_change_user_context','ph_reject_invite_reason','en','Optional reason for declining...',''),
('page_change_user_context','ph_request_note','en','Optionally state the reason for your access request...',''),
('page_change_user_context','th_base_role','en','Base Role',''),
('page_change_user_context','th_higher_role','en','Higher Role',''),
('page_change_user_context','th_organization','en','Organization / Scope',''),
('page_change_user_context','th_pending_action','en','Action',''),
('page_change_user_context','th_pending_org','en','Organization',''),
('page_change_user_context','th_pending_status','en','Status & Note',''),
('page_change_user_context','tip_enter_admin','en','Enter as Administrator',''),
('page_change_user_context','tip_enter_developer','en','Enter as Developer',''),
('page_change_user_context','tip_enter_sysadmin','en','Enter as Sysadmin',''),
('page_change_user_context','tip_enter_user','en','Enter as User',''),
('page_change_user_context','tip_no_admin_rights','en','You do not have administrator privileges','');
GO