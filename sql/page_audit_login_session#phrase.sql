/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: page_audit_login_session#phrase.sql
 * Účel:   Registrace stránky page_audit_login_session do sysinit_object, položky
 *         menu audit_login_session do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_audit_login_session';
DELETE FROM sysinit_menu WHERE builtin_code = 'audit_login_session';
DELETE FROM sysinit_phrase WHERE source_code = 'page_audit_login_session';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_audit_login_session','cs','A','Aktivita uživatelů (audit_login_session)','Přehled historie přihlášení a aktivity uživatelů z tabulky audit_login_session'),
('P','page_audit_login_session','en','A','User Activity (audit_login_session)','Overview of user login history and session activity from audit_login_session');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('audit_login_session','cs','admin_folder','070','page_audit_login_session','','A','<svg viewBox="0 0 24 24" fill="#0D9488"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>','Aktivita uživatelů','Přehled přihlášení a aktivity uživatelů z tabulky audit_login_session','Přehled přihlášení a aktivity uživatelů z tabulky audit_login_session');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('audit_login_session','en','User Activity','Overview of user logins and activity from the audit_login_session table','Overview of user logins and activity from the audit_login_session table');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_audit_login_session','badge_session_expired','cs','Expirováno','',''),
('page_audit_login_session','badge_user_inactive','cs','Neaktivní účet','',''),
('page_audit_login_session','btn_apply_filter','cs','Filtrovat','Vyhledá přihlašovací relace podle zadaných kritérií',''),
('page_audit_login_session','btn_reset_filter','cs','Zrušit filtr','Vymaže filtr a zobrazí nejnovější relace','btn-secondary'),
('page_audit_login_session','heading_user_activity','cs','Aktivita a přihlášení uživatelů','',''),
('page_audit_login_session','intro_user_activity','cs','Přehled přihlášení a aktivity uživatelů z tabulky audit_login_session a navazujících údajů účtu (seřazeno sestupně podle času).','',''),
('page_audit_login_session','lbl_displayed_records','cs','Zobrazeno záznamů: {$count}','',''),
('page_audit_login_session','lbl_filter_limit','cs','Počet řádků:','',''),
('page_audit_login_session','lbl_filter_only_open','cs','Pouze aktivní (neukončené) relace','',''),
('page_audit_login_session','lbl_filter_user','cs','Jméno / login uživatele:','',''),
('page_audit_login_session','msg_no_records','cs','Zadaným kritériím neodpovídají v tabulce audit_login_session žádné záznamy.','',''),
('page_audit_login_session','page_title','cs','Aktivita uživatelů - BCM Osiris','',''),
('page_audit_login_session','ph_filter_user','cs','Zadejte jméno, příjmení, login nebo e-mail...','',''),
('page_audit_login_session','th_assumed_role','cs','Role','',''),
('page_audit_login_session','th_dept_job','cs','Oddělení / Pozice','',''),
('page_audit_login_session','th_duration_min','cs','Trvání','',''),
('page_audit_login_session','th_email','cs','E-mail','',''),
('page_audit_login_session','th_ip_address','cs','IP adresa','',''),
('page_audit_login_session','th_last_request_time','cs','Poslední aktivita','',''),
('page_audit_login_session','th_login_name','cs','Login','',''),
('page_audit_login_session','th_login_time','cs','Čas přihlášení','',''),
('page_audit_login_session','th_logout_time','cs','Odhlášení / Expirace','',''),
('page_audit_login_session','th_organization','cs','Organizace','',''),
('page_audit_login_session','th_user_name','cs','Jméno uživatele','',''),
('page_audit_login_session','txt_session_open','cs','Neukončeno','',''),
('page_audit_login_session','unit_minutes','cs','min','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_audit_login_session','badge_session_expired','en','Expired',''),
('page_audit_login_session','badge_user_inactive','en','Inactive Account',''),
('page_audit_login_session','btn_apply_filter','en','Filter','Filter login sessions by the specified criteria'),
('page_audit_login_session','btn_reset_filter','en','Reset Filter','Clear filter criteria and display the latest sessions'),
('page_audit_login_session','heading_user_activity','en','User Login & Activity History',''),
('page_audit_login_session','intro_user_activity','en','Overview of user logins and session activity from audit_login_session and linked account details (sorted descending by login time).',''),
('page_audit_login_session','lbl_displayed_records','en','Displayed records: {$count}',''),
('page_audit_login_session','lbl_filter_limit','en','Row limit:',''),
('page_audit_login_session','lbl_filter_only_open','en','Active (open) sessions only',''),
('page_audit_login_session','lbl_filter_user','en','User name / login:',''),
('page_audit_login_session','msg_no_records','en','No records in audit_login_session match the specified criteria.',''),
('page_audit_login_session','page_title','en','User Activity - BCM Osiris',''),
('page_audit_login_session','ph_filter_user','en','Enter first name, last name, login, or email...',''),
('page_audit_login_session','th_assumed_role','en','Role',''),
('page_audit_login_session','th_dept_job','en','Department / Job Title',''),
('page_audit_login_session','th_duration_min','en','Duration',''),
('page_audit_login_session','th_email','en','Email',''),
('page_audit_login_session','th_ip_address','en','IP Address',''),
('page_audit_login_session','th_last_request_time','en','Last Activity',''),
('page_audit_login_session','th_login_name','en','Login',''),
('page_audit_login_session','th_login_time','en','Login Time',''),
('page_audit_login_session','th_logout_time','en','Logout / Expiration',''),
('page_audit_login_session','th_organization','en','Organization',''),
('page_audit_login_session','th_user_name','en','User Name',''),
('page_audit_login_session','txt_session_open','en','Active',''),
('page_audit_login_session','unit_minutes','en','min','');
GO