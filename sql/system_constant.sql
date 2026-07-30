/*
	============================================================================
	Změny v databázi pro rok 2026 - Úvodní inicializace jádra GRC / ISMS
	============================================================================
	
	Kompatibilita: SQL Server moderní (bez omezení na DB-compat 110)
	Konvence: snake_case, malá písmena, odsazení tabulátory
	Verzování: Formát YYYYMMDD (datum releasu)
*/

set xact_abort on
set ansi_warnings on
set nocount off
GO

-- ============================================================================
-- 1. ZÁKLADNÍ SYSTÉMOVÁ TABULKA: system_constant (Singleton)
-- ============================================================================
drop table if exists dbo.system_constant;
GO

create table dbo.system_constant (
	pkey tinyint not null primary key check (pkey = 1),
	
	-- Verzování databáze a aplikace datem releasu (YYYYMMDD)
	database_version varchar(8) not null default '20260730',
	app_version varchar(8) not null default '20260730',
	
	-- Stav databáze: 'R' = Ready, 'M' = Maintenance, 'L' = Locked
	database_state char(1) not null default 'R',
	
	-- Nastavení údržby a notifikací
	maintenance_mode bit not null default 0,
	maintenance_message nvarchar(500) not null default '',
	smtp_server varchar(100) not null default '',
	smtp_port int not null default 25,
	email_sender_name nvarchar(100) not null default '',
	email_sender_address varchar(100) not null default '',
	sysmsg_recipients varchar(500) not null default '',
	
	-- Parametry prostředí a autentizace
	ldap_root varchar(200) not null default '',
	login_with_token bit not null default 0,
	session_timeout_minutes smallint not null default 60,
	max_login_attempts tinyint not null default 5,
	machine_guid varchar(100) not null default '',
	environment_name varchar(20) not null default 'PROD'
);

insert into dbo.system_constant (pkey, database_version, app_version, database_state)
values (1, '20260730', '20260730', 'R');

print 'Inicializována tabulka system_constant (verze 20260730).';
GO
