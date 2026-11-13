/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: table_audit_login_session.sql
 * Tabulka: audit_login_session
 * Popis:   Forenzní log přihlášení uživatelů. Nahrazuje původní ukládání identity
 *          do user_organization_access. Poskytuje nezměnitelný historický
 *          kontext pro auditní stopy (who_created, who_modified).
 * Vazby:   user_account_uuid -> user_account.original
 *          organization_uuid -> organization.original
 * ============================================================================= */

IF OBJECT_ID('audit_login_session') IS NULL
BEGIN
	CREATE TABLE audit_login_session (
		uuid uuid NOT NULL,
		
		user_account_uuid uuid NOT NULL,           -- Identita přihlášeného uživatele (originál z user_account)
		organization_uuid uuid NOT NULL,           -- Tenant, do kterého uživatel vstoupil (originál z organization)
		
		assumed_role varchar(1) NOT NULL,          -- Zvolená efektivní role (U=User, A=Admin, S=Sysadmin, D=Developer)
		
		login_time datetime NOT NULL DEFAULT getdate(),
		last_request_time datetime NOT NULL DEFAULT getdate(), -- Sledování aktivity pro určení délky relace
		logout_time datetime NULL,                 -- Čas explicitního odhlášení nebo expirace
		
		ip_address varchar(200) NOT NULL DEFAULT '', -- IP adresa včetně forwarded hlaviček
		
		CONSTRAINT pk_audit_login_session PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka audit_login_session byla vytvorena.';
END
GO

-- Idempotentní vytvoření indexů pro rychlé dohledávání historie konkrétního uživatele nebo tenanta
EXEC sp_create_index 
	@tname = 'audit_login_session', 
	@iname = 'ix_audit_login_session_user', 
	@colnames = 'user_account_uuid, login_time', 
	@uni = '', 
	@options = '';
GO

EXEC sp_create_index 
	@tname = 'audit_login_session', 
	@iname = 'ix_audit_login_session_org', 
	@colnames = 'organization_uuid, login_time', 
	@uni = '', 
	@options = '';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'audit_login_session';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('audit_login_session','cs','T','audit_login_session','Záznam přihlášení a aktivity','Historie přihlášení a aktivity','Forenzní auditní protokol přihlášení uživatelů, zvolených rolí, IP adres a doby trvání relací.','Slouží ke kontrole aktivity uživatelů a jako neměnný základ pro auditní stopu vytvoření a úprav záznamů.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('audit_login_session','en','Login & Activity Record','User Login & Activity History','Forensic audit log of user logins, assumed roles, IP addresses, and session durations.','Used to monitor user activity and provide an immutable audit trail for record creation and modification.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'audit_login_session';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('audit_login_session','assumed_role','cs','Zvolená role v relaci (assumed_role)','Efektivní role v relaci (U/A/S/D)','Role v relaci','Role, pod kterou uživatel v dané přihlašovací relaci pracoval.'),
	('audit_login_session','ip_address','cs','IP adresa (ip_address)','Klientská IP adresa','IP adresa','Síťová IP adresa klienta (včetně případné cesty X-Forwarded-For).'),
	('audit_login_session','last_request_time','cs','Poslední aktivita (last_request_time)','Čas posledního požadavku v relaci','Posl. aktivita','Časová značka posledního HTTP požadavku zaznamenaného v dané relaci.'),
	('audit_login_session','login_time','cs','Čas přihlášení (login_time)','Datum a čas přihlášení','Přihlášení','Okamžik zahájení přihlašovací relace uživatele.'),
	('audit_login_session','logout_time','cs','Čas odhlášení / expirace (logout_time)','Datum a čas odhlášení nebo expirace','Odhlášení','Okamžik řádného odhlášení uživatele nebo automatického vypršení neaktivní relace.'),
	('audit_login_session','organization_uuid','cs','Cílová organizace (organization_uuid)','Organizace (UUID)','Organizace','Odkaz na originální identifikátor organizace v tabulce organization.'),
	('audit_login_session','user_account_uuid','cs','Uživatelský účet (user_account_uuid)','Uživatel (UUID účtu)','Uživatel (UUID)','Odkaz na globální účet uživatele v tabulce user_account.'),
	('audit_login_session','assumed_role','en','Assumed Session Role (assumed_role)','Effective Session Role (U/A/S/D)','Session Role','Effective role under which the user worked during the login session.'),
	('audit_login_session','ip_address','en','IP Address (ip_address)','Client IP Address','IP Address','Network IP address of the client (including X-Forwarded-For path).'),
	('audit_login_session','last_request_time','en','Last Activity (last_request_time)','Last Request Time in Session','Last Activity','Timestamp of the last HTTP request recorded in the session.'),
	('audit_login_session','login_time','en','Login Time (login_time)','Login Date & Time','Login Time','Timestamp when the user login session started.'),
	('audit_login_session','logout_time','en','Logout / Expiration Time (logout_time)','Logout or Session Expiration Time','Logout Time','Timestamp when the user logged out or the inactive session expired.'),
	('audit_login_session','organization_uuid','en','Target Organization (organization_uuid)','Organization (UUID)','Organization','Reference to the original identifier of the organization in the organization table.'),
	('audit_login_session','user_account_uuid','en','User Account (user_account_uuid)','User (Account UUID)','User (UUID)','Reference to the global user account in the user_account table.');
END
GO