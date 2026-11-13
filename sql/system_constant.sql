/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: system_constant.sql
 * Tabulky: system_constant (Systémové konstanty), service_logbook (Provozní deník)
 * Popis:	1. system_constant uchovává globální konfiguraci systému v jediném
 *			   řádku (Singleton).
 *			2. service_logbook eviduje historii spuštěných změnových skriptů
 *			   (changes_YYMM.sql) a importů systémových dávek.
 *			3. Výchozí číslo verze databáze (database_version) se načítá
 *			   dynamicky z tabulky sysinit_constant (plněné procedurou
 *			   dbo.p_update_database_version), takže tento soubor již není nutné
 *			   při každém povýšení verze databáze upravovat.
 *
 * VÝJIMKA Z ARCHITEKTURY:
 * Tyto tabulky úmyslně NEPODLÉHAJÍ schvalovacímu procesu (SSC) ani pravidlům
 * pro záznamy a řízení přístupu (RAC). Z toho důvodu NEOBSAHUJÍ standardní
 * sloupce jako record_type, approval_status, language, original, object_owner
 * ani platnosti. Slouží čistě pro globální technické parametry a servisní audit.
 *
 * Změny:
 * - 2026-11-13 17:00: Doplněna registrace tříd a sloupců do sysinit_class
 *   a sysinit_column (včetně objektů z HinkMSSQLLibrary.sql) a dynamické
 *   načítání database_version z tabulky sysinit_constant.
 * ============================================================================= */

IF OBJECT_ID('system_constant') IS NULL
BEGIN
	CREATE TABLE system_constant (
		-- Primární klíč pro jediný záznam v tabulce
		uuid uuid NOT NULL,
		
		-- Základní auditní stopa (bez plného SSC a RAC)
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,
		
		-- Globální verze a stavy (formát verze 'RR.MM.DD.N')
		database_version varchar(20) NOT NULL DEFAULT '',
		app_version varchar(20) NOT NULL DEFAULT '',
		database_state varchar(1) NOT NULL DEFAULT 'X',
		
		-- Bezpečnost, autentizace a inicializace
		sysadmin_email varchar(200) NOT NULL DEFAULT '',
		system_admin_pwd varchar(255) NOT NULL DEFAULT '', -- Hash hesla pro offline/nouzovou aktivaci
		login_with_token bit NOT NULL DEFAULT 0, -- Globální vynucení tokenů / MFA
		ldap_root varchar(255) NOT NULL DEFAULT '', -- Cesta pro lokální Active Directory / LDAP integraci
		
		-- Licence a aplikační informace
		server_licence varchar(max) NOT NULL DEFAULT '',
		application_info_file varchar(255) NOT NULL DEFAULT '', -- Cesta k MOTD nebo release notes
		
		-- Globální poštovní server
		smtp_server varchar(200) NOT NULL DEFAULT '',
		smtp_port int NOT NULL DEFAULT 25,
		email_sender_name varchar(200) NOT NULL DEFAULT '',
		email_sender_address varchar(200) NOT NULL DEFAULT '',
		sysmsg_recipients varchar(max) NOT NULL DEFAULT '',
		
		-- Konfigurace zálohování a údržby MSSQL
		backup_path varchar(max) NOT NULL DEFAULT '',
		backup_full_date datetime NULL,
		backup_full_days int NOT NULL DEFAULT 0,
		backup_diff_count int NOT NULL DEFAULT 0,
		backup_diff_counter int NOT NULL DEFAULT 0,
		backup_log_date datetime NULL,
		backup_log_hours int NOT NULL DEFAULT 0,
		copyonly_backup_switch bit NOT NULL DEFAULT 0, -- Zabrání narušení LSN řetězce při záloze
		
		-- Ostatní systémové parametry
		session_timeout int NOT NULL DEFAULT 20,
		current_year int NOT NULL DEFAULT YEAR(GETDATE()),
		machine_guid varchar(200) NOT NULL DEFAULT '',
		right_profadmin_enabled bit NOT NULL DEFAULT 1, -- Přepínač pro globální údržbový/striktní režim

		CONSTRAINT pk_system_constant PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka system_constant byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců, načtení verze ze sysinit_constant a DEFAULTu
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'system_constant', 'system_admin_pwd', 'varchar(255) NOT NULL DEFAULT ''''';
GO

DECLARE @fallback_version varchar(20) = '26.11.12.0';                          -- Fallback verze při spuštění nad zcela prázdnou DB
DECLARE @active_version varchar(20) = NULL;                                    -- Verze načtená z tabulky sysinit_constant

IF OBJECT_ID('sysinit_constant', 'U') IS NOT NULL
BEGIN
	SELECT TOP 1 @active_version = NULLIF(LTRIM(RTRIM(database_version)), '')
	FROM sysinit_constant;
END

SET @active_version = ISNULL(@active_version, @fallback_version);

EXEC sp_drop_default 'system_constant', 'database_version';

DECLARE @sql_df nvarchar(400) = N'ALTER TABLE system_constant ADD CONSTRAINT df_system_constant_db_version DEFAULT '''
	+ REPLACE(@active_version, '''', '''''') + N''' FOR database_version;';
EXEC sp_executesql @sql_df;

-- Inicializační vložení (Singleton) pouze pokud je tabulka zcela prázdná
IF NOT EXISTS (SELECT 1 FROM system_constant)
BEGIN
	INSERT INTO system_constant (
		uuid,
		database_version,
		sysadmin_email,
		system_admin_pwd,
		smtp_server,
		smtp_port,
		email_sender_name,
		email_sender_address
	) VALUES (
		NEWID(),
		@active_version,
		'hink@rac.cz',
		'', -- Ponecháno prázdné, doplní se při aktivaci systému
		'sandbox.smtp.mailtrap.io', -- Nultý bod: Vývojový SMTP server
		2525,                       -- Nultý bod: Port pro Mailtrap
		'Ramses Enterprise ISMS',
		'noreply@rac.cz'
	);
END
GO

-- -----------------------------------------------------------------------------
-- Tabulka: service_logbook (Provozní deník upgradů a systémových importů)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('service_logbook') IS NULL
BEGIN
	CREATE TABLE service_logbook (
		id int IDENTITY PRIMARY KEY,
		servername varchar(250) NOT NULL DEFAULT @@servername,
		original_login varchar(200) NOT NULL DEFAULT original_login(),
		[date] smalldatetime NOT NULL DEFAULT getdate(),
		[name] varchar(250) NOT NULL,
		[version] varchar(200) NOT NULL,
		content varchar(max) NULL
	);
	PRINT 'Tabulka service_logbook byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Registrace systémových tříd a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name IN (
		'system_constant', 'service_logbook', 'rowgenerator',
		'f_integer_list', 'f_string_list', 'f_syscolumns', 'f_uuid_list',
		'v_syscolumns', 'v_sysindexcolumns', 'v_sysprimarykeys'
	);

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('f_integer_list','cs','F','f_integer_list','Funkce rozkladu seznamu čísel','Rozklad seznamu celých čísel','Tabulková funkce převádějící čárkami oddělený seznam celých čísel na tabulku hodnot bigint.','Pomocná parsovací funkce knihovny HinkMSSQLLibrary.'),
	('f_string_list','cs','F','f_string_list','Funkce rozkladu seznamu textů','Rozklad seznamu textů','Tabulková funkce převádějící čárkami oddělený řetězec na tabulku oříznutých textových položek.','Pomocná parsovací funkce knihovny HinkMSSQLLibrary.'),
	('f_syscolumns','cs','F','f_syscolumns','Funkce sloupců tabulky','Sloupce zadané tabulky','Tabulková funkce vracející metadata sloupců pro zadanou trvalou nebo dočasnou (#temp) tabulku.','Využívána při dynamickém skládání SQL dotazů a exportů.'),
	('f_uuid_list','cs','F','f_uuid_list','Funkce rozkladu seznamu UUID','Rozklad seznamu identifikátorů UUID','Tabulková funkce převádějící čárkami oddělený seznam GUIDů na tabulku hodnot uniqueidentifier.','Pomocná parsovací funkce knihovny HinkMSSQLLibrary.'),
	('rowgenerator','cs','T','rowgenerator','Generátor řádků','Generátor řádků (0..1024)','Pomocná číselná tabulka obsahující sekvenci čísel 0 až 1024 pro množinové operace.','Systémová tabulka knihovny HinkMSSQLLibrary.'),
	('service_logbook','cs','T','service_logbook','Záznam provozního deníku','Provozní deník (service_logbook)','Chronologická evidence provedených upgradů databáze (changes_YYMM.sql), importů metadat a údržby koše.','Slouží ke kontrole historie servisních zásahů a verzí databáze.'),
	('system_constant','cs','T','system_constant','Systémové konstanty','Systémové konstanty','Globální technická konfigurace databáze, verze schématu, poštovního serveru SMTP a zálohování.','Singleton tabulka s technickými parametry instance systému.'),
	('v_syscolumns','cs','V','v_syscolumns','Systémový pohled sloupců DB','Systémový pohled sloupců DB','Přehled sloupců všech tabulek, pohledů a funkcí v databázi včetně datových typů a constraintů.','Systémový katalogový pohled knihovny HinkMSSQLLibrary.'),
	('v_sysindexcolumns','cs','V','v_sysindexcolumns','Systémový pohled sloupců indexů','Systémový pohled sloupců indexů','Přehled všech indexů a jejich klíčových i inkludovaných sloupců v databázi.','Systémový katalogový pohled knihovny HinkMSSQLLibrary.'),
	('v_sysprimarykeys','cs','V','v_sysprimarykeys','Systémový pohled primárních klíčů','Systémový pohled primárních klíčů','Přehled sloupců tvořících primární klíče jednotlivých tabulek databáze.','Systémový katalogový pohled knihovny HinkMSSQLLibrary.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('f_integer_list','en','Integer List Split Function','Split Integer List','Table-valued function splitting a comma-separated list of integers into bigint rows.','Helper parsing function of HinkMSSQLLibrary.'),
	('f_string_list','en','String List Split Function','Split String List','Table-valued function splitting a comma-separated string into trimmed varchar rows.','Helper parsing function of HinkMSSQLLibrary.'),
	('f_syscolumns','en','Table Columns Function','Columns of Specified Table','Table-valued function returning column metadata for a permanent or temporary (#temp) table.','Used for dynamic SQL generation and data exports.'),
	('f_uuid_list','en','UUID List Split Function','Split UUID List','Table-valued function splitting a comma-separated list of GUIDs into uniqueidentifier rows.','Helper parsing function of HinkMSSQLLibrary.'),
	('rowgenerator','en','Row Generator','Row Generator (0..1024)','Helper numeric table containing sequence 0 to 1024 for set-based operations.','System table of HinkMSSQLLibrary.'),
	('service_logbook','en','Service Logbook Entry','Service Logbook','Chronological log of executed database upgrades (changes_YYMM.sql), metadata imports, and trash cleanup.','Used to audit service operations and database schema versions.'),
	('system_constant','en','System Constants','System Constants','Global technical configuration of the database, schema version, SMTP mail server, and backups.','Singleton table holding technical parameters of the system instance.'),
	('v_syscolumns','en','System Database Columns View','System Database Columns View','Catalog view of columns across all tables, views, and functions including data types and constraints.','System catalog view of HinkMSSQLLibrary.'),
	('v_sysindexcolumns','en','System Index Columns View','System Index Columns View','Catalog view of all indexes and their key and included columns in the database.','System catalog view of HinkMSSQLLibrary.'),
	('v_sysprimarykeys','en','System Primary Keys View','System Primary Keys View','Catalog view of columns participating in primary keys of database tables.','System catalog view of HinkMSSQLLibrary.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name IN ('system_constant', 'service_logbook');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('service_logbook','content','cs','Obsah / poznámka (content)','Obsah záznamu / popis provedené změny','Obsah / Poznámka','Textový popis provedené operace, upgradu nebo importovaného balíčku.'),
	('service_logbook','date','cs','Datum a čas (date)','Datum a čas záznamu','Datum a čas','Datum a čas pořízení záznamu v provozním deníku.'),
	('service_logbook','id','cs','Pořadové ID (id)','Číselný identifikátor záznamu (ID)','ID','Automaticky generované pořadové číslo záznamu (IDENTITY).'),
	('service_logbook','name','cs','Název / Jméno (name)','Název / Jméno','Název','Technický nebo zobrazovaný název položky.'),
	('service_logbook','original_login','cs','Přihlašovací účet SQL (original_login)','Původní přihlašovací účet SQL Serveru','SQL Login','Systémové jméno účtu SQL Serveru (original_login()), pod kterým byl skript spuštěn.'),
	('service_logbook','servername','cs','Název serveru (servername)','Název serveru','Server','Síťový název databázového nebo aplikačního serveru.'),
	('service_logbook','version','cs','Verze (version)','Označení verze','Verze','Číslo nebo časové označení verze databáze, skriptu či datového balíčku.'),
	('system_constant','app_version','cs','Verze aplikace (app_version)','Verze aplikačního kódu','Verze aplikace','Označení verze nasazených PHP skriptů aplikace.'),
	('system_constant','application_info_file','cs','Soubor informací o aplikaci (application_info_file)','Cesta k souboru s informacemi o verzi','Info soubor','Cesta k souboru se zprávou pro uživatele (MOTD / release notes).'),
	('system_constant','backup_diff_count','cs','Počet rozdílových záloh (backup_diff_count)','Počet rozdílových záloh v cyklu','Počet diff záloh','Nastavený počet diferenciálních záloh mezi plnými zálohami.'),
	('system_constant','backup_diff_counter','cs','Počítadlo rozdílových záloh (backup_diff_counter)','Aktuální pořadí rozdílové zálohy','Čítač diff záloh','Interní počítadlo provedených diferenciálních záloh.'),
	('system_constant','backup_full_date','cs','Datum plné zálohy (backup_full_date)','Čas poslední plné zálohy databáze','Plná záloha dne','Datum a čas posledního provedení úplné (FULL) zálohy databáze.'),
	('system_constant','backup_full_days','cs','Perioda plné zálohy (backup_full_days)','Interval plné zálohy ve dnech','Perioda plné zál.','Počet dnů mezi automatickými úplnými zálohami databáze.'),
	('system_constant','backup_log_date','cs','Datum zálohy logu (backup_log_date)','Čas poslední zálohy transakčního logu','Záloha logu dne','Datum a čas poslední zálohy transakčního logu.'),
	('system_constant','backup_log_hours','cs','Perioda zálohy logu (backup_log_hours)','Interval zálohy logu v hodinách','Perioda logu (h)','Počet hodin mezi zálohami transakčního logu.'),
	('system_constant','backup_path','cs','Cesta pro zálohy (backup_path)','Adresář pro ukládání záloh databáze','Cesta záloh','Fyzická cesta na disku serveru určená pro soubory záloh databáze.'),
	('system_constant','copyonly_backup_switch','cs','Režim COPY_ONLY zálohy (copyonly_backup_switch)','Používat při zálohování příznak COPY_ONLY','COPY_ONLY záloha','Zabraňuje narušení sekvence LSN řetězce při souběžném externím zálohování.'),
	('system_constant','current_year','cs','Aktuální rok (current_year)','Aktuální kalendářní rok','Aktuální rok','Výchozí kalendářní rok v systémovém nastavení.'),
	('system_constant','database_state','cs','Stav databáze (database_state)','Provozní stav databáze','Stav DB','Jednoznakový indikátor provozního stavu databáze.'),
	('system_constant','database_version','cs','Verze databáze (database_version)','Aktuální verze schématu databáze','Verze DB','Označení verze databázového schématu ve formátu RR.MM.DD.N řízené skriptem changes_YYMM.sql.'),
	('system_constant','email_sender_address','cs','Adresa odesílatele (email_sender_address)','E-mailová adresa odesílatele','E-mail odesílatele','E-mailová adresa uváděná jako odesílatel systémových zpráv.'),
	('system_constant','email_sender_name','cs','Jméno odesílatele e-mailů (email_sender_name)','Zobrazované jméno odesílatele e-mailů','Jméno odesílatele','Jméno uváděné v hlavičce From u systémových e-mailů.'),
	('system_constant','ldap_root','cs','Kořenová cesta LDAP (ldap_root)','Kořenová cesta Active Directory / LDAP','LDAP kořen','Konfigurační cesta pro integraci s adresářovou službou Active Directory / LDAP.'),
	('system_constant','login_with_token','cs','Vyžadovat token při přihlášení (login_with_token)','Globálně vyžadovat autentizační token','Login s tokenem','Globální přepínač vynucující přihlašování s bezpečnostním tokenem.'),
	('system_constant','machine_guid','cs','Identifikátor stroje (machine_guid)','Unikátní identifikátor serveru','ID stroje','Hardwarový nebo systémový identifikátor serveru.'),
	('system_constant','right_profadmin_enabled','cs','Režim profesního admina (right_profadmin_enabled)','Povolit globální správu metodiky','Profadmin povolen','Systémový přepínač režimu správy metodiky.'),
	('system_constant','server_licence','cs','Licence serveru (server_licence)','Identifikátor serverové licence','Licence serveru','Kód nebo klíč serverové licence.'),
	('system_constant','session_timeout','cs','Timeout relace v minutách (session_timeout)','Doba neaktivity před odhlášením (min)','Timeout (min)','Počet minut neaktivity uživatele, po jejichž uplynutí webová relace automaticky expiruje.'),
	('system_constant','smtp_port','cs','SMTP port (smtp_port)','Číslo portu SMTP serveru','SMTP port','Číslo síťového portu SMTP serveru (např. 25, 465, 587, 2525).'),
	('system_constant','smtp_server','cs','SMTP server (smtp_server)','Adresa odchozího poštovního serveru','SMTP server','Doménový název nebo IP adresa SMTP serveru pro odesílání systémových e-mailů.'),
	('system_constant','sysadmin_email','cs','E-mail systémového správce (sysadmin_email)','E-mail hlavního správce systému','E-mail sysadmina','E-mailová adresa pro nouzovou obnovu hesla účtu admin a systémová upozornění.'),
	('system_constant','sysmsg_recipients','cs','Příjemci systémových zpráv (sysmsg_recipients)','Seznam příjemců servisních hlášení','Příjemci hlášení','Seznam e-mailových adres pro doručování automatických provozních a chybových zpráv.'),
	('system_constant','system_admin_pwd','cs','Hash nouzového hesla (system_admin_pwd)','Hash hesla nouzového účtu admin','Nouzové heslo','Bcrypt/argon2 hash hesla pro offline/break-glass přihlášení systémového administrátora.'),
	('service_logbook','content','en','Content / Note (content)','Record Content / Change Description','Content / Note','Text description of the executed operation, database upgrade, or imported package.'),
	('service_logbook','date','en','Date & Time (date)','Record Date & Time','Date & Time','Timestamp of the entry in the service logbook.'),
	('service_logbook','id','en','Sequential ID (id)','Numeric Record Identifier (ID)','ID','Automatically generated sequential record number (IDENTITY).'),
	('service_logbook','name','en','Name (name)','Name','Name','Technical or display name of the item.'),
	('service_logbook','original_login','en','SQL Login Account (original_login)','Original SQL Server Login Account','SQL Login','System login name of the SQL Server account (original_login()) that executed the script.'),
	('service_logbook','servername','en','Server Name (servername)','Server Name','Server','Network name of the database or application server.'),
	('service_logbook','version','en','Version (version)','Version Identifier','Version','Version number or timestamp of the database, upgrade script, or data package.'),
	('system_constant','app_version','en','Application Version (app_version)','Application Code Version','App Version','Version identifier of the deployed PHP application scripts.'),
	('system_constant','application_info_file','en','Application Info File (application_info_file)','Path to Version Release Notes File','Info File','Path to the file containing MOTD or release notes.'),
	('system_constant','backup_diff_count','en','Differential Backup Count (backup_diff_count)','Differential Backups per Cycle','Diff Backup Count','Configured number of differential backups between full backups.'),
	('system_constant','backup_diff_counter','en','Differential Backup Counter (backup_diff_counter)','Current Differential Backup Number','Diff Counter','Internal counter of executed differential backups.'),
	('system_constant','backup_full_date','en','Last Full Backup Date (backup_full_date)','Last Full Database Backup Time','Full Backup Date','Date and time when the last FULL database backup was completed.'),
	('system_constant','backup_full_days','en','Full Backup Period (backup_full_days)','Full Backup Interval in Days','Full Backup Days','Number of days between automatic full database backups.'),
	('system_constant','backup_log_date','en','Last Log Backup Date (backup_log_date)','Last Transaction Log Backup Time','Log Backup Date','Date and time of the last transaction log backup.'),
	('system_constant','backup_log_hours','en','Log Backup Period (backup_log_hours)','Log Backup Interval in Hours','Log Period (h)','Number of hours between transaction log backups.'),
	('system_constant','backup_path','en','Backup Path (backup_path)','Database Backup Directory Path','Backup Path','Physical directory path on the server disk for database backup files.'),
	('system_constant','copyonly_backup_switch','en','COPY_ONLY Backup Mode (copyonly_backup_switch)','Use COPY_ONLY Flag During Backups','COPY_ONLY Backup','Prevents disrupting the LSN chain when external backups are used concurrently.'),
	('system_constant','current_year','en','Current Year (current_year)','Current Calendar Year','Current Year','Default calendar year in system settings.'),
	('system_constant','database_state','en','Database State (database_state)','Database Operational State','DB State','Single-character indicator of the database operational state.'),
	('system_constant','database_version','en','Database Version (database_version)','Current Database Schema Version','DB Version','Database schema version in YY.MM.DD.N format managed by changes_YYMM.sql.'),
	('system_constant','email_sender_address','en','Email Sender Address (email_sender_address)','Sender Email Address','Sender Email','Email address used as the sender of system notifications.'),
	('system_constant','email_sender_name','en','Email Sender Name (email_sender_name)','Display Name of Email Sender','Sender Name','Display name used in the From header of outgoing system emails.'),
	('system_constant','ldap_root','en','LDAP Root Path (ldap_root)','Active Directory / LDAP Root Path','LDAP Root','Configuration path for Active Directory / LDAP integration.'),
	('system_constant','login_with_token','en','Require Token on Login (login_with_token)','Globally Require Authentication Token','Login with Token','Global switch enforcing token-based authentication.'),
	('system_constant','machine_guid','en','Machine GUID (machine_guid)','Unique Server Identifier','Machine GUID','Hardware or system identifier of the server.'),
	('system_constant','right_profadmin_enabled','en','Professional Admin Mode (right_profadmin_enabled)','Enable Global Methodology Management','Profadmin Enabled','System switch for methodology administration mode.'),
	('system_constant','server_licence','en','Server Licence (server_licence)','Server Licence Identifier','Server Licence','Code or key of the server licence.'),
	('system_constant','session_timeout','en','Session Timeout in Minutes (session_timeout)','Inactivity Timeout Before Logout (min)','Timeout (min)','Number of inactivity minutes before a web session automatically expires.'),
	('system_constant','smtp_port','en','SMTP Port (smtp_port)','SMTP Server Port Number','SMTP Port','Network port number of the SMTP server (e.g., 25, 465, 587, 2525).'),
	('system_constant','smtp_server','en','SMTP Server (smtp_server)','Outgoing SMTP Mail Server Address','SMTP Server','Hostname or IP address of the SMTP server used for sending system emails.'),
	('system_constant','sysadmin_email','en','Sysadmin Email (sysadmin_email)','Primary System Administrator Email','Sysadmin Email','Email address for emergency admin password recovery and system alerts.'),
	('system_constant','sysmsg_recipients','en','System Message Recipients (sysmsg_recipients)','Service Alert Recipient List','Alert Recipients','List of email addresses receiving automatic operational and error notifications.'),
	('system_constant','system_admin_pwd','en','Emergency Admin Password Hash (system_admin_pwd)','Break-Glass Admin Password Hash','Emergency Password','Bcrypt/argon2 password hash for emergency break-glass system administrator login.');
END
GO