/* =============================================================================
 * Tabulka: system_constant (Systémové konstanty)
 * Popis:	Uchovává globální konfiguraci systému v jediném řádku (Singleton).
 *
 * VÝJIMKA Z ARCHITEKTURY:
 * Tato tabulka úmyslně NEPODLÉHÁ schvalovacímu procesu (SSC) ani pravidlům
 * pro záznamy a řízení přístupu (RAC). Z toho důvodu NEOBSAHUJE standardní
 * sloupce jako record_type, approval_status, language, original, object_owner
 * ani platnosti. Slouží čistě pro globální technické parametry serveru.
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
		
		-- Globální verze a stavy
		database_version varchar(20) NOT NULL DEFAULT '20260804',
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
-- Zajištění chybějících sloupců pro upgrady existujících databází pomocí procedury "p_create_missing_column"
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'system_constant', 'system_admin_pwd', 'varchar(255) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Inicializační vložení (Singleton)
-- Vloží se pouze v případě, že je tabulka zcela prázdná.
-- OBSAHUJE NULTÝ BOD: Předvyplněný vývojový SMTP server (Mailtrap.io)
-- -----------------------------------------------------------------------------
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
		'20260804',
		'admin@tvoje-domena.cz',
		'', -- Ponecháno prázdné, doplní se při prvním spuštění / bootstrapu
		'sandbox.smtp.mailtrap.io', -- Nultý bod: Vývojový SMTP server
		2525,                       -- Nultý bod: Port pro Mailtrap
		'Ramses Enterprise ISMS',
		'noreply@tvoje-domena.cz'
	);
END
GO

/* =============================================================================
 * Tabulka: password_reset_request
 * Popis:	Uchovává jednorázové tokeny pro obnovu hesla a inicializaci.
 *			Abychom tokeny chránili, ukládáme pouze jejich SHA-256 hash.
 * ============================================================================= */

IF OBJECT_ID('password_reset_request') IS NULL
BEGIN
	CREATE TABLE password_reset_request (
		uuid uuid NOT NULL,
		
		-- Identifikace, pro koho token je (0x00 znamená systémový break-glass admin)
		target_account_uuid uuid NOT NULL, 
		
		-- Ukládáme pouze HASH tokenu (např. SHA-256), nikoliv token samotný
		token_hash varchar(64) NOT NULL,
		
		-- Platnost tokenu (např. 1 hodina od vygenerování)
		expires_at datetime NOT NULL,
		
		-- Příznak, zda už byl token použit
		is_used bit NOT NULL DEFAULT 0,
		
		-- Sledovací sloupce
		date_created datetime NOT NULL DEFAULT getdate(),
		
		CONSTRAINT pk_password_reset_request PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka password_reset_request byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Indexy (idempotentní založení)
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'password_reset_request', 
	@iname = 'ix_password_reset_request_token', 
	@colnames = 'token_hash', 
	@uni = '', 
	@options = 'WHERE is_used = 0';
GO