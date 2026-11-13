/* =============================================================================
 * Verze: 2026-11-13 16:45
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
('page_org_users','badge_admin','cs','Admin org.','',''),
('page_org_users','badge_inactive','cs','Neaktivní','',''),
('page_org_users','badge_pending','cs','Žádost o přístup','',''),
('page_org_users','badge_translator','cs','Překladatel','',''),
('page_org_users','btn_new_user','cs','+ Přidat / přiřadit uživatele','Založí nového uživatele nebo přiřadí existující účet do této organizace',''),
('page_org_users','err_email_required','cs','E-mailová adresa uživatele je povinná.','',''),
('page_org_users','err_login_exists','cs','Zadané přihlašovací jméno již v systému existuje u jiného účtu.','',''),
('page_org_users','err_login_required','cs','Přihlašovací jméno (login) je povinné.','',''),
('page_org_users','err_password_too_short','cs','Nové heslo musí mít alespoň 8 znaků.','',''),
('page_org_users','grp_access_permissions','cs','Oprávnění a zařazení v této organizaci','',''),
('page_org_users','grp_account_identity','cs','Přihlašovací účet a osobní údaje','',''),
('page_org_users','grp_password_security','cs','Nastavení hesla a zabezpečení účtu','',''),
('page_org_users','header_edit_user','cs','Uživatel organizace','',''),
('page_org_users','header_new_user','cs','Nový uživatel organizace','',''),
('page_org_users','lbl_new_password','cs','Nové heslo (vyplňte pouze při změně):','',''),
('page_org_users','master_heading','cs','Uživatelé a přístupy v organizaci','',''),
('page_org_users','msg_user_saved','cs','Údaje uživatele a přístupu do organizace byly uloženy.','',''),
('page_org_users','page_title','cs','Uživatelé organizace - BCM Osiris','',''),
('page_org_users','th_dept_job','cs','Oddělení / Pozice','',''),
('page_org_users','th_login','cs','Login','',''),
('page_org_users','th_name','cs','Jméno a příjmení','',''),
('page_org_users','th_roles','cs','Role a práva','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_org_users','badge_admin','en','Org. Admin',''),
('page_org_users','badge_inactive','en','Inactive',''),
('page_org_users','badge_pending','en','Access Request',''),
('page_org_users','badge_translator','en','Translator',''),
('page_org_users','btn_new_user','en','+ Add / Assign User','Create a new user or assign an existing account to this organization'),
('page_org_users','err_email_required','en','User email address is required.',''),
('page_org_users','err_login_exists','en','The specified login name already exists for another account.',''),
('page_org_users','err_login_required','en','Login name is required.',''),
('page_org_users','err_password_too_short','en','New password must be at least 8 characters long.',''),
('page_org_users','grp_access_permissions','en','Permissions & Assignment in This Organization',''),
('page_org_users','grp_account_identity','en','Login Account & Personal Details',''),
('page_org_users','grp_password_security','en','Password & Account Security Settings',''),
('page_org_users','header_edit_user','en','Organization User',''),
('page_org_users','header_new_user','en','New Organization User',''),
('page_org_users','lbl_new_password','en','New Password (fill in only when changing):',''),
('page_org_users','master_heading','en','Organization Users & Access',''),
('page_org_users','msg_user_saved','en','User details and organization access settings have been saved.',''),
('page_org_users','page_title','en','Organization Users - BCM Osiris',''),
('page_org_users','th_dept_job','en','Department / Job Title',''),
('page_org_users','th_login','en','Login',''),
('page_org_users','th_name','en','Full Name',''),
('page_org_users','th_roles','en','Roles & Rights','');
GO