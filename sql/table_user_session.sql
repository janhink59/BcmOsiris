/* =============================================================================
 * Verze: 2026-11-09 13:00
 * Soubor: table_user_session.sql
 * Popis:  Tento script obsahuje DDL příkazy pro vytvoření dvou tabulek
 *         s identickou strukturou:
 *         wwwsession - záznam o přihlášeném uživateli (PK na session_id prohlížeče)
 *         dbsession  - záznam o běžícím requestu (PK na @@spid)
 * Vazby:  Trigger trg_wwwsession_audit_logout automaticky zapisuje logout_time
 *         do tabulky audit_login_session při každém smazání relace z wwwsession.
 * Změny:
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