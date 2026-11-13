/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: table_user_session.sql
 * Popis:  Tento script obsahuje DDL příkazy pro vytvoření dvou tabulek
 *         s identickou strukturou:
 *         wwwsession - záznam o přihlášeném uživateli (PK na session_id prohlížeče)
 *         dbsession  - záznam o běžícím requestu (PK na @@spid)
 * Vazby:  Trigger trg_wwwsession_audit_logout automaticky zapisuje logout_time
 *         do tabulky audit_login_session při každém smazání relace z wwwsession.
 * Změny:
 * - 2026-11-13 17:00: Doplněna registrace tříd a sloupců do sysinit_class
 *   a sysinit_column.
 * - 2026-11-09 13:00: Doplněn AFTER DELETE trigger trg_wwwsession_audit_logout
 *   pro automatické uzavření záznamu v audit_login_session při odhlášení,
 *   přepnutí kontextu nebo expiraci relace.
 * ============================================================================= */

drop table if exists session_import_data
drop table if exists session_import_column
drop table if exists session_import_parameter
drop table if exists session_import_table

drop table if exists request_message
drop table if exists request_variable
drop table if exists wwwsession
drop table if exists dbsession

GO

CREATE TABLE [dbo].[wwwsession](
	[spid] [int] NOT NULL, -- @@spid posledního requestu
	[wwwsession] [varchar](50) NOT NULL primary key,
	[user_account] uuid not null,
	[login_session_uuid] uuid not null, -- Odkaz na záznam v tabulce audit_login_session
	[user_name] [varchar](80) NOT NULL,
	[organization] uuid not null,
	[organization_name] [nvarchar](200) default '' NOT NULL,
	[display_name] [varchar](200) NOT NULL,
	[licence_level] [tinyint] default 0 NOT NULL,
	[language] [varchar](2) default 'en' NOT NULL,
	[working_date] [date] default getdate() NOT NULL,
	
	[active_role] [varchar](1) default 'U' NOT NULL, -- Efektivní role v aktuálním sezení (U, A, S, D)
	[right_translate] [bit] default 0 NOT NULL,      -- Doplňkové oprávnění pro ukládání globálních překladů
	
	[login_date] [datetime] default getdate() NOT NULL,
	[request_date] [datetime] default getdate() NOT NULL,
	[session_log] [int] NOT NULL,
	[debug] [bit] default 0 NOT NULL,
	[servername] [varchar](200) default '' NOT NULL,
	[client_ip] [varchar](200) default '' NOT NULL,
	[application] [varchar](200) default '' NOT NULL,
	[permanent] [bit] default 0 NOT NULL,
	[change_context_allowed] [bit] default 0 NOT NULL
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[dbsession](
	[spid] [int] primary key NOT NULL, -- @@spid requestu
	[wwwsession] [varchar](50) NOT NULL,
	[user_account] uuid not null,
	[login_session_uuid] uuid not null, -- Odkaz na záznam v tabulce audit_login_session
	[user_name] [varchar](80) NOT NULL,
	[organization] uuid not null,
	[organization_name] [nvarchar](200) default '' NOT NULL,
	[display_name] [varchar](200) NOT NULL,
	[licence_level] [tinyint] default 0 NOT NULL,
	[language] [varchar](2) default 'en' NOT NULL,
	[working_date] [date] default getdate() NOT NULL,
	
	[active_role] [varchar](1) default 'U' NOT NULL, -- Efektivní role v aktuálním sezení (U, A, S, D)
	[right_translate] [bit] default 0 NOT NULL,      -- Doplňkové oprávnění pro ukládání globálních překladů
	
	[login_date] [datetime] default getdate() NOT NULL,
	[request_date] [datetime] default getdate() NOT NULL,
	[session_log] [int] NOT NULL,
	[debug] [bit] default 0 NOT NULL,
	[servername] [varchar](200) default '' NOT NULL,
	[client_ip] [varchar](200) default '' NOT NULL,
	[application] [varchar](200) default '' NOT NULL,
	[permanent] [bit] default 0 NOT NULL,
	[change_context_allowed] [bit] default 0 NOT NULL
) ON [PRIMARY]
GO

CREATE TRIGGER trg_wwwsession_audit_logout
ON [dbo].[wwwsession]
AFTER DELETE
AS
BEGIN
	SET NOCOUNT ON;

	IF OBJECT_ID('audit_login_session', 'U') IS NOT NULL AND OBJECT_ID('system_constant', 'U') IS NOT NULL
	BEGIN
		UPDATE a
		SET a.logout_time = CASE
			WHEN DATEADD(minute, c.session_timeout, d.request_date) < GETDATE()
				THEN DATEADD(minute, c.session_timeout, d.request_date)
			ELSE GETDATE()
		END
		FROM audit_login_session a
		JOIN deleted d ON d.login_session_uuid = a.uuid
		CROSS JOIN system_constant c
		WHERE a.logout_time IS NULL;
	END
END
GO

-- -----------------------------------------------------------------------------
-- Registrace tříd a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name IN ('wwwsession', 'dbsession');

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('dbsession','cs','T','dbsession','Databázová relace procesu','Databázové relace procesů','Kontext právě běžícího databázového požadavku navázaný na @@SPID v SQL Serveru.','Zajišťuje předání identity uživatele, organizace, jazyka a role do uložených procedur a funkcí.'),
	('wwwsession','cs','T','wwwsession','Webová relace uživatele','Aktivní webové relace','Sdílená tabulka aktivních přihlašovacích relací prohlížečů (session_id) s kontextem organizace a role.','Uchovává stav přihlášeného uživatele mezi jednotlivými HTTP požadavky.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('dbsession','en','Database Process Session','Database Process Sessions','Context of the currently executing database request bound to @@SPID in SQL Server.','Passes user identity, organization, language, and active role to stored procedures and functions.'),
	('wwwsession','en','Web User Session','Active Web Sessions','Shared table of active browser sessions (session_id) holding organization and role context.','Maintains logged-in user state across HTTP requests.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name IN ('wwwsession', 'dbsession');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('wwwsession','active_role','cs','Aktivní role (active_role)','Aktivní role sezení (U/A/S/D)','Aktivní role','Efektivní aplikační role v běžícím sezení.'),
	('wwwsession','application','cs','Název aplikace (application)','Identifikátor klientské aplikace','Aplikace','Název aplikace přistupující k databázi.'),
	('wwwsession','change_context_allowed','cs','Povolena změna kontextu (change_context_allowed)','Povolit přepínání organizace / role','Změna kontextu','Určuje, zda má uživatel v horní liště k dispozici odkaz pro přepnutí organizace nebo role.'),
	('wwwsession','client_ip','cs','IP adresa klienta (client_ip)','IP adresa klienta','IP klienta','Síťová IP adresa klientského prohlížeče.'),
	('wwwsession','debug','cs','Ladicí režim (debug)','Zapnout ladicí výpisy (debug)','Debug','Příznak aktivace vývojářského ladicího režimu v relaci.'),
	('wwwsession','display_name','cs','Zobrazované jméno (display_name)','Celé jméno přihlášeného uživatele','Jméno uživatele','Zobrazované celé jméno uživatele v horní liště aplikace.'),
	('wwwsession','licence_level','cs','Úroveň licence (licence_level)','Úroveň licence organizace','Úroveň licence','Rozsah oprávnění organizace: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
	('wwwsession','login_date','cs','Čas přihlášení relace (login_date)','Čas vzniku relace','Přihlášeno','Datum a čas vytvoření webové relace.'),
	('wwwsession','login_session_uuid','cs','ID auditní relace (login_session_uuid)','Odkaz do audit_login_session','ID relace','Unikátní identifikátor přihlášení v tabulce audit_login_session pro auditní stopu.'),
	('wwwsession','organization','cs','Aktivní organizace (organization)','Organizace','Organizace','Identifikátor aktivní organizace v relaci nebo pohledu.'),
	('wwwsession','organization_name','cs','Název organizace (organization_name)','Název organizace','Název organizace','Zobrazovaný název organizace.'),
	('wwwsession','permanent','cs','Trvale viditelná položka (permanent)','Trvale zobrazit i prázdnou složku','Trvalé','Ponechá složku menu viditelnou (jako neaktivní) i tehdy, když uživatel nemá přístup k žádné její podpoložce.'),
	('wwwsession','request_date','cs','Čas posledního požadavku (request_date)','Čas posledního HTTP požadavku','Posl. požadavek','Čas poslední aktivity webové relace pro hlídání timeoutu.'),
	('wwwsession','right_translate','cs','Právo překládat (right_translate)','Oprávnění pořizovat překlady','Právo překladu','Opravňuje uživatele ukládat jazykové překlady (v garantující organizaci i globálně pro systém).'),
	('wwwsession','servername','cs','Název serveru (servername)','Název serveru','Server','Síťový název databázového nebo aplikačního serveru.'),
	('wwwsession','session_log','cs','Kód logování relace (session_log)','Příznak logování relace','Log relace','Interní příznak úrovně logování relace.'),
	('wwwsession','spid','cs','ID procesu SQL Serveru (spid)','Číslo procesu SQL Serveru (@@SPID)','SPID','Identifikátor serverového procesu databázového spojení (@@SPID).'),
	('wwwsession','user_account','cs','Uživatelský účet (user_account)','Uživatelský účet','Uživatel','Odkaz na účet uživatele.'),
	('wwwsession','user_name','cs','Uživatelské jméno v relaci (user_name)','Přihlašovací jméno uživatele','Login','Přihlašovací jméno uživatele v aktivní relaci.'),
	('wwwsession','working_date','cs','Pracovní datum (working_date)','Osobní pracovní datum (prázdné = dnes)','Pracovní datum','Datum, ke kterému se vyhodnocuje časová platnost záznamů v relaci uživatele.'),
	('wwwsession','wwwsession','cs','ID webové relace (wwwsession)','Identifikátor relace prohlížeče (SID)','Web Session','Unikátní identifikátor relace prohlížeče (PHP session_id).'),
	('wwwsession','active_role','en','Active Role (active_role)','Active Session Role (U/A/S/D)','Active Role','Effective application role in the current session.'),
	('wwwsession','application','en','Application Name (application)','Client Application Identifier','Application','Name of the client application connecting to the database.'),
	('wwwsession','change_context_allowed','en','Context Switch Allowed (change_context_allowed)','Allow Switching Organization / Role','Context Switch','Indicates whether the user can switch organizations or roles from the top bar.'),
	('wwwsession','client_ip','en','Client IP Address (client_ip)','Client IP Address','Client IP','Network IP address of the client browser.'),
	('wwwsession','debug','en','Debug Mode (debug)','Enable Debug Output (debug)','Debug','Flag enabling developer debug output in the session.'),
	('wwwsession','display_name','en','Display Name (display_name)','Logged-in User Full Name','Display Name','Full display name of the user shown in the top bar.'),
	('wwwsession','licence_level','en','Licence Level (licence_level)','Organization Licence Level','Licence Level','Organization permission tier: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
	('wwwsession','login_date','en','Session Login Date (login_date)','Session Creation Time','Login Date','Date and time when the web session was created.'),
	('wwwsession','login_session_uuid','en','Audit Session UUID (login_session_uuid)','Reference to audit_login_session','Session UUID','Unique login session identifier in audit_login_session used for the audit trail.'),
	('wwwsession','organization','en','Active Organization (organization)','Organization','Organization','Identifier of the active organization in the session or view.'),
	('wwwsession','organization_name','en','Organization Name (organization_name)','Organization Name','Organization Name','Display name of the organization.'),
	('wwwsession','permanent','en','Permanently Visible Item (permanent)','Always Show Even When Empty','Permanent','Keeps a menu folder visible (as disabled) even when the user has no access to any child items.'),
	('wwwsession','request_date','en','Last Request Date (request_date)','Last HTTP Request Time','Request Date','Timestamp of the last web session activity for timeout tracking.'),
	('wwwsession','right_translate','en','Translation Right (right_translate)','Authorized to Save Translations','Translation Right','Authorizes the user to save language translations (globally if in the guarantee translator organization).'),
	('wwwsession','servername','en','Server Name (servername)','Server Name','Server','Network name of the database or application server.'),
	('wwwsession','session_log','en','Session Log Code (session_log)','Session Logging Flag','Session Log','Internal session logging flag.'),
	('wwwsession','spid','en','SQL Server Process ID (spid)','SQL Server Process ID (@@SPID)','SPID','Server process identifier of the database connection (@@SPID).'),
	('wwwsession','user_account','en','User Account (user_account)','User Account','User','Reference to the user account.'),
	('wwwsession','user_name','en','Session User Name (user_name)','User Login Name','Login','Login name of the user in the active session.'),
	('wwwsession','working_date','en','Working Date (working_date)','Personal Working Date (Empty = Today)','Working Date','Effective date used to evaluate temporal validity of records in the user session.'),
	('wwwsession','wwwsession','en','Web Session ID (wwwsession)','Browser Session Identifier (SID)','Web Session','Unique browser session identifier (PHP session_id).');
END
GO