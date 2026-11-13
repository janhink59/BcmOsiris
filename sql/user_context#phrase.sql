/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: user_context#phrase.sql
 * Účel:   Registrace komponenty user_context do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'user_context';
DELETE FROM sysinit_phrase WHERE source_code = 'user_context';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','user_context','cs','U','Kontextový panel uživatele','Horní lišta s informacemi o přihlášeném uživateli, roli a volbou jazyka'),
('P','user_context','en','U','User Context Bar','Top bar displaying logged-in user details, active role, and language selector');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('user_context','btn_logout','cs','Odhlásit','Ukončí aktuální relaci a odhlásí uživatele ze systému','ctx-logout'),
('user_context','lbl_default_org','cs','Organizace','',''),
('user_context','lbl_default_user','cs','Uživatel','',''),
('user_context','lbl_logo_placeholder','cs','[ Logo / Grafika ]','',''),
('user_context','role_admin','cs','ADMIN','',''),
('user_context','role_dev','cs','DEV','',''),
('user_context','role_sysadmin','cs','SYSADMIN','',''),
('user_context','role_user','cs','USER','',''),
('user_context','tip_change_context','cs','Změnit organizaci či roli','',''),
('user_context','tip_current_org','cs','Aktuální organizace','',''),
('user_context','tip_logged_user','cs','Přihlášený uživatel','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('user_context','btn_logout','en','Log Out','End the current session and log out of the system'),
('user_context','lbl_default_org','en','Organization',''),
('user_context','lbl_default_user','en','User',''),
('user_context','lbl_logo_placeholder','en','[ Logo / Graphics ]',''),
('user_context','role_admin','en','ADMIN',''),
('user_context','role_dev','en','DEV',''),
('user_context','role_sysadmin','en','SYSADMIN',''),
('user_context','role_user','en','USER',''),
('user_context','tip_change_context','en','Change organization or role',''),
('user_context','tip_current_org','en','Current organization',''),
('user_context','tip_logged_user','en','Logged-in user','');
GO