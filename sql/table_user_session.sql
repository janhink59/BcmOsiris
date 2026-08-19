/*
    Tento script obsahuje DDL příkazy pro vytvoření dvou tabulek s identickou strukturou
    wwwsession - obsahuje záznam o přihlášeném uživateli s primárním klíčem na session_id prohlížeče
    dbsession - obsahuje záznam o běžícím requestu s primárním klíčem na "spid"

    Systém umožňuje vícenásobné přihlášení uživatele s různým "wwwsession".
    Při přihlášení se zkopírují kontextové informace uživatele (jazyk, organizace ....)
    z tabulky user_account a zůstávají v platnosti po celou dobu session.

    Systém umožňuje rovněž provedení víc requestů v rámci jedné session.
    Při zahájení requestu (procedura init_session) se odstraní řádek pro platné @@spid
    a je do něj zkopírován aktuální záznam z wwwsession, kde je předtím aktualizován sloupec "spid".

    Obě tabulky jsou ve scriptu nejdřív odstraněny, protože neobsahují uživatelská data.

*/

drop table if exists wwwsession
drop table if exists dbsession
GO

CREATE TABLE [dbo].[wwwsession](
	[spid] [int] NOT NULL, -- @@spid posledního requestu
	[wwwsession] [varchar](50) NOT NULL primary key,
	[user_account] uuid not null,
	[user_name] [varchar](80) NOT NULL,
	[organization] uuid not null,
	[organization_name] [nvarchar](200) default '' NOT NULL,
	[display_name] [varchar](200) NOT NULL,
	[licence_level] [tinyint] default 0 NOT NULL,
	[language] [varchar](2) default 'en' NOT NULL,
	[working_date] [date] default getdate() NOT NULL,
	[right_sysadmin] [bit] default 0 NOT NULL,
	[right_orgadmin] [bit] default 0 NOT NULL,
	[right_translate] [bit] default 0 NOT NULL,
	[login_date] [datetime] default getdate() NOT NULL,
	[request_date] [datetime] default getdate() NOT NULL,
	[session_log] [int] NOT NULL,
	[debug] [bit] default 0 NOT NULL,
	[servername] [varchar](200) default '' NOT NULL,
	[client_ip] [varchar](200) default '' NOT NULL,
	[application] [varchar](200) default '' NOT NULL,
	[permanent] [bit] default 0 NOT NULL
	) ON [PRIMARY]
GO

CREATE TABLE [dbo].[dbsession](
	[spid] [int] primary key NOT NULL, -- @@spid requestu
	[wwwsession] [varchar](50) NOT NULL,
	[user_account] uuid not null,
	[user_name] [varchar](80) NOT NULL,
	[organization] uuid not null,
	[organization_name] [nvarchar](200) default '' NOT NULL,
	[display_name] [varchar](200) NOT NULL,
	[licence_level] [tinyint] default 0 NOT NULL,
	[language] [varchar](2) default 'en' NOT NULL,
	[working_date] [date] default getdate() NOT NULL,
	[right_sysadmin] [bit] default 0 NOT NULL,
	[right_orgadmin] [bit] default 0 NOT NULL,
	[right_translate] [bit] default 0 NOT NULL,
	[login_date] [datetime] default getdate() NOT NULL,
	[request_date] [datetime] default getdate() NOT NULL,
	[session_log] [int] NOT NULL,
	[debug] [bit] default 0 NOT NULL,
	[servername] [varchar](200) default '' NOT NULL,
	[client_ip] [varchar](200) default '' NOT NULL,
	[application] [varchar](200) default '' NOT NULL,
	[permanent] [bit] default 0 NOT NULL
	) ON [PRIMARY]
GO
