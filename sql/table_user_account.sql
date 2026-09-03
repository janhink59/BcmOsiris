/* =============================================================================
 * Tabulka: user_account (Uživatelské účty)
 * Popis:	Evidence uživatelských účtů s plnou podporou multi-tenancy, RAC a SSC.
 *			Účty jsou nyní vlastněny globálně systémem (object_owner = 0x00).
 *			Přístup do konkrétních tenantů řeší vazební tabulka user_organization_access.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * ============================================================================= */

IF OBJECT_ID('user_account') IS NULL
BEGIN
	CREATE TABLE user_account (
		-- -------------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00, -- Globální vlastnictví systémem
		original uuid NOT NULL,
		record_type varchar(1) NOT NULL DEFAULT 'A',
		approval_status varchar(1) NOT NULL DEFAULT 'A',
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		is_template bit NOT NULL DEFAULT 0,
		template uuid NULL,
		
		-- -------------------------------------------------------------------------
		-- Společné textové vlastnosti (podpora UTF-8)
		-- -------------------------------------------------------------------------
		caption varchar(200) NOT NULL DEFAULT '',
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		instance_class_name varchar(80) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		
		-- -------------------------------------------------------------------------
		-- Auditní stopy (výhradně uuid odkazy bez denormalizovaných jmen)
		-- -------------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- -------------------------------------------------------------------------
		-- Specifické byznys sloupce uživatele (Autentizace a Identita)
		-- -------------------------------------------------------------------------
		login_name varchar(100) NOT NULL DEFAULT '',
		email varchar(200) NOT NULL DEFAULT '',
		password_hash varchar(255) NOT NULL DEFAULT '',
		
		-- Řízení bezpečnostních politik pro SSO / Lokální přihlášení
		allow_local_login bit NOT NULL DEFAULT 1,
		is_system_admin bit NOT NULL DEFAULT 0,
		require_password_change bit NOT NULL DEFAULT 0,
		failed_login_attempts int NOT NULL DEFAULT 0,
		locked_until datetime NULL,
		last_login_date datetime NULL,
		last_password_change datetime NULL,
		mfa_enabled bit NOT NULL DEFAULT 0,
		mfa_secret varchar(100) NOT NULL DEFAULT '',
		
		-- NOVÉ: Kontext poslední navštívené organizace (pro automatické přihlášení)
		last_login_organization uuid NULL,
		
		-- Osobní a kontaktní údaje
		user_title_before varchar(40) NOT NULL DEFAULT '',
		first_name varchar(100) NOT NULL DEFAULT '',
		last_name varchar(100) NOT NULL DEFAULT '',
		user_title_after varchar(40) NOT NULL DEFAULT '',
		phone varchar(50) NOT NULL DEFAULT '',
		mobile varchar(50) NOT NULL DEFAULT '',
		
		-- Organizační struktura uživatele (volné vazby)
		department_name varchar(150) NOT NULL DEFAULT '',
		job_title varchar(150) NOT NULL DEFAULT '',
		manager_uuid uuid NULL,
		note varchar(max) NOT NULL DEFAULT '',

		CONSTRAINT pk_user_account PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka user_account byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze (změnový příkaz)
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'user_account', 'last_login_organization', 'uuid NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka a originál.
EXEC sp_create_index 
	@tname = 'user_account', 
	@iname = 'uq_user_account_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti jazykových verzí (Language) pro daného vlastníka a originál.
EXEC sp_create_index 
	@tname = 'user_account', 
	@iname = 'uq_user_account_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- Zajištění unikátnosti přihlašovacího jména. Vzhledem k tomu, že object_owner je
-- nyní globálně 0x00, zaručuje tento index unikátnost loginu v celém systému.
EXEC sp_create_index 
	@tname = 'user_account', 
	@iname = 'uq_user_account_login', 
	@colnames = 'login_name, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND inactive = 0 AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Inicializační systémový záznam (0x01)
-- -----------------------------------------------------------------------------
IF NOT EXISTS(SELECT 1 FROM user_account WHERE original = 0x01 AND record_type = 'A' AND removed = 0)
BEGIN
	INSERT INTO user_account (
		uuid, object_owner, original, record_type, approval_status,
		caption, shortname, description_text,
		login_name, email, first_name, last_name,
		is_system_admin, allow_local_login, last_login_organization
	) VALUES (
		0x01, 0x00, 0x01, 'A', 'A',
		'System Administrator', 'admin', 'Systémový master uživatelský účet.',
		'sysadmin', 'hink@rac.cz', 'System', 'Administrator',
		1, 1, 0x00
	);
	PRINT 'Systémový účet 0x01 (sysadmin) byl vložen.';
END
GO