/*
	Tento script obsahuje DDL příkazy pro vytvoření dvou tabulek s identickou strukturou
	wwwsession - obsahuje záznam o přihlášeném uživateli s primárním klíčem na session_id prohlížeče
	dbsession - obsahuje záznam o běžícím requestu s primárním klíčem na "spid"

	Změny v architektuře:
	- Sloupec user_access_uuid přejmenován na login_session_uuid (odkazuje do audit_login_session).
	- Bitová práva right_sysadmin a right_orgadmin sloučena do active_role (U, A, S, D).
*/

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