/* =============================================================================
 * Verze: 2026-11-15 20:05
 * Soubor: page_org_users#phrase.sql
 * Účel:   Registrace stránky page_org_users do sysinit_object, položky menu
 *         org_users do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_org_users';
DELETE FROM sysinit_menu WHERE builtin_code = 'org_users';
DELETE FROM sysinit_phrase WHERE source_code = 'page_org_users';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_org_users','cs','A','Uživatelé organizace','Správa uživatelských účtů a oprávnění v rámci organizace'),
('P','page_org_users','en','A','Organization Users','Management of user accounts and permissions within the organization');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('org_users','cs','admin_folder','040','page_org_users','','A','<svg viewBox="0 0 24 24" fill="#6366F1"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>','Uživatelé organizace','Správa uživatelů, oprávnění a žádostí o přístup v organizaci','Správa uživatelů, oprávnění a žádostí o přístup v organizaci');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('org_users','en','Organization Users','Management of users, permissions, and access requests within the organization','Management of users, permissions, and access requests within the organization');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_org_users','badge_role_admin','cs','Admin','',''),
('page_org_users','badge_role_trans','cs','Překlady','',''),
('page_org_users','btn_approve_access','cs','Schválit přístup','Schválí žádost uživatele a zpřístupní mu tuto organizaci','btn-success'),
('page_org_users','btn_cancel_invite','cs','Zrušit pozvánku','Zruší odeslanou pozvánku do organizace','btn-danger'),
('page_org_users','btn_new_user','cs','+ Nový / Pozvat uživatele','Založí nového uživatele nebo odešle pozvánku existujícímu účtu',''),
('page_org_users','btn_reject_access','cs','Odmítnout žádost','Odmítne žádost uživatele o přístup do této organizace','btn-danger'),
('page_org_users','btn_save','cs','Aktualizovat pozvánku','Uloží upravené nastavení odeslané pozvánky','btn-success'),
('page_org_users','detail_heading','cs','Detail uživatele a oprávnění','',''),
('page_org_users','detail_heading_new','cs','Nový uživatel / Pozvánka do organizace','',''),
('page_org_users','grp_global_account_admin','cs','3. Globální správa účtu','',''),
('page_org_users','grp_org_permissions','cs','1. Oprávnění, zařazení a nastavení v této organizaci (user_organization_access)','',''),
('page_org_users','grp_personal_data','cs','2. Osobní a kontaktní údaje účtu (user_account)','',''),
('page_org_users','lbl_access_approval_note','cs','Poznámka k pozvánce / důvod zamítnutí:','',''),
('page_org_users','lbl_allow_local_login','cs','Povolit přihlášení lokálním heslem','',''),
('page_org_users','lbl_deactivate_global','cs','Globálně deaktivovat účet ve všech organizacích','',''),
('page_org_users','lbl_department','cs','Oddělení / Útvar v organizaci','',''),
('page_org_users','lbl_email','cs','E-mail (nemusí být unikátní)','',''),
('page_org_users','lbl_evaluation_method','cs','Osobní metoda hodnocení (CRMM)','',''),
('page_org_users','lbl_first_name','cs','Křestní jméno','',''),
('page_org_users','lbl_is_developer','cs','Globální Developer (is_developer)','',''),
('page_org_users','lbl_is_orgadmin','cs','Administrátor organizace (is_orgadmin)','',''),
('page_org_users','lbl_is_system_admin','cs','Globální Sysadmin (is_system_admin)','',''),
('page_org_users','lbl_job_title','cs','Pracovní pozice v organizaci','',''),
('page_org_users','lbl_last_name','cs','Příjmení','',''),
('page_org_users','lbl_login_name','cs','Přihlašovací jméno (login)','',''),
('page_org_users','lbl_mobile','cs','Mobil','',''),
('page_org_users','lbl_phone','cs','Telefon','',''),
('page_org_users','lbl_remove_access','cs','Odebrat přístup do této organizace','',''),
('page_org_users','lbl_right_translate','cs','Právo pořizovat překlady (right_translate)','',''),
('page_org_users','lbl_show_removed','cs','Zobrazit odstraněné','',''),
('page_org_users','lbl_title_after','cs','Titul za jménem','',''),
('page_org_users','lbl_title_before','cs','Titul před jménem','',''),
('page_org_users','lbl_user_note','cs','Interní poznámka v organizaci','',''),
('page_org_users','lbl_working_date','cs','Osobní pracovní datum (prázdné = dnes)','',''),
('page_org_users','master_heading','cs','Uživatelé organizace','',''),
('page_org_users','msg_access_rejected_banner','cs','Tento návrh přístupu byl odmítnut.','',''),
('page_org_users','msg_new_or_invite_info','cs','Pokud přidáváte uživatele, který již má účet v jiné organizaci, zadejte pouze jeho Přihlašovací jméno (login) a nastavte mu oprávnění a zařazení v organizaci níže – systém mu odešle pozvánku ke schválení a jeho osobní údaje nepřepíše. Pokud login dosud neexistuje, vyplňte i osobní údaje pro založení nového účtu.','',''),
('page_org_users','msg_orgadmin_invited_banner','cs','Tomuto existujícímu uživateli byla odeslána pozvánka do vaší organizace. Přístup i možnost úpravy osobních údajů se aktivují, jakmile uživatel pozvánku přijme ve svém okně „Změna kontextu“.','',''),
('page_org_users','msg_select_or_create_user','cs','Vyberte uživatele ze seznamu vlevo nebo vytvořte / pozvěte nového.','',''),
('page_org_users','msg_self_protection','cs','Ochrana účtu: Vlastní přístup ani administrátorská práva nelze odebrat.','',''),
('page_org_users','msg_user_not_found','cs','Uživatel nebyl v této organizaci nalezen.','',''),
('page_org_users','msg_user_requested_access_banner','cs','Tento uživatel požádal o přístup do vaší organizace. Zkontrolujte jeho oprávnění a zařazení níže a klikněte na „Schválit přístup“ nebo „Odmítnout žádost“. Osobní údaje účtu budou zpřístupněny k úpravám až po schválení přístupu.','',''),
('page_org_users','page_title','cs','Správa uživatelů organizace','',''),
('page_org_users','placeholder_search','cs','Hledat uživatele...','',''),
('page_org_users','status_active','cs','Aktivní','',''),
('page_org_users','status_inactive','cs','Účet neaktivní','',''),
('page_org_users','status_invited','cs','Pozván (čeká se)','',''),
('page_org_users','status_rejected','cs','Odmítnuto','',''),
('page_org_users','status_removed','cs','Přístup zrušen','',''),
('page_org_users','status_user_request','cs','Žádost o přístup','',''),
('page_org_users','th_full_name','cs','Jméno a login','',''),
('page_org_users','th_org_roles','cs','Práva','',''),
('page_org_users','th_status','cs','Stav','',''),
('page_org_users','tip_is_orgadmin','cs','Umožňuje spravovat uživatele a nastavení v rámci této organizace','',''),
('page_org_users','tip_right_translate','cs','Opravňuje uživatele k ukládání překladů (v garantující organizaci i globálně)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_org_users','badge_role_admin','en','Admin',''),
('page_org_users','badge_role_trans','en','Translations',''),
('page_org_users','btn_approve_access','en','Approve Access','Approve the user request and grant access to this organization'),
('page_org_users','btn_cancel_invite','en','Cancel Invitation','Cancel the pending organization invitation'),
('page_org_users','btn_new_user','en','+ New / Invite User','Create a new user or invite an existing account to this organization'),
('page_org_users','btn_reject_access','en','Reject Request','Reject the user access request for this organization'),
('page_org_users','btn_save','en','Update Invitation','Save updated settings for the pending invitation'),
('page_org_users','detail_heading','en','User & Permissions Detail',''),
('page_org_users','detail_heading_new','en','New User / Organization Invitation',''),
('page_org_users','grp_global_account_admin','en','3. Global Account Administration',''),
('page_org_users','grp_org_permissions','en','1. Permissions, Assignment & Settings in This Organization (user_organization_access)',''),
('page_org_users','grp_personal_data','en','2. Personal & Contact Account Details (user_account)',''),
('page_org_users','lbl_access_approval_note','en','Invitation Note / Rejection Reason:',''),
('page_org_users','lbl_allow_local_login','en','Allow Local Password Login',''),
('page_org_users','lbl_deactivate_global','en','Globally Deactivate Account Across All Organizations',''),
('page_org_users','lbl_department','en','Department / Unit in Organization',''),
('page_org_users','lbl_email','en','Email (Not Required to Be Unique)',''),
('page_org_users','lbl_evaluation_method','en','Personal Evaluation Method (CRMM)',''),
('page_org_users','lbl_first_name','en','First Name',''),
('page_org_users','lbl_is_developer','en','Global Developer (is_developer)',''),
('page_org_users','lbl_is_orgadmin','en','Organization Administrator (is_orgadmin)',''),
('page_org_users','lbl_is_system_admin','en','Global Sysadmin (is_system_admin)',''),
('page_org_users','lbl_job_title','en','Job Title in Organization',''),
('page_org_users','lbl_last_name','en','Last Name',''),
('page_org_users','lbl_login_name','en','Login Name (Username)',''),
('page_org_users','lbl_mobile','en','Mobile',''),
('page_org_users','lbl_phone','en','Phone',''),
('page_org_users','lbl_remove_access','en','Revoke Access to This Organization',''),
('page_org_users','lbl_right_translate','en','Authorized to Save Translations (right_translate)',''),
('page_org_users','lbl_show_removed','en','Show Removed',''),
('page_org_users','lbl_title_after','en','Title After Name',''),
('page_org_users','lbl_title_before','en','Title Before Name',''),
('page_org_users','lbl_user_note','en','Internal Organization Note',''),
('page_org_users','lbl_working_date','en','Personal Working Date (Empty = Today)',''),
('page_org_users','master_heading','en','Organization Users',''),
('page_org_users','msg_access_rejected_banner','en','This access proposal was rejected.',''),
('page_org_users','msg_new_or_invite_info','en','If adding a user who already has an account in another organization, enter only their Login Name and set their organization permissions below – the system will send them an invitation for approval without overwriting their personal details. If the login does not exist yet, fill in personal details as well to create a new account.',''),
('page_org_users','msg_orgadmin_invited_banner','en','An invitation to your organization has been sent to this existing user. Access and personal data editing will activate once the user accepts the invitation in their "Change Context" screen.',''),
('page_org_users','msg_select_or_create_user','en','Select a user from the list on the left or create / invite a new one.',''),
('page_org_users','msg_self_protection','en','Account protection: You cannot revoke your own access or administrator privileges.',''),
('page_org_users','msg_user_not_found','en','User was not found in this organization.',''),
('page_org_users','msg_user_requested_access_banner','en','This user has requested access to your organization. Review their permissions and assignment below and click "Approve Access" or "Reject Request". Personal account details will become editable after access is approved.',''),
('page_org_users','page_title','en','Organization Users Management',''),
('page_org_users','placeholder_search','en','Search users...',''),
('page_org_users','status_active','en','Active',''),
('page_org_users','status_inactive','en','Account Inactive',''),
('page_org_users','status_invited','en','Invited (Pending)',''),
('page_org_users','status_rejected','en','Rejected',''),
('page_org_users','status_removed','en','Access Revoked',''),
('page_org_users','status_user_request','en','Access Request',''),
('page_org_users','th_full_name','en','Name & Login',''),
('page_org_users','th_org_roles','en','Rights',''),
('page_org_users','th_status','en','Status',''),
('page_org_users','tip_is_orgadmin','en','Allows managing users and settings within this organization',''),
('page_org_users','tip_right_translate','en','Authorizes the user to save translations (globally if in the guarantee translator organization)','');
GO