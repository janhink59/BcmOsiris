/* =============================================================================
 * Verze: 2026-10-29 15:30
 * Soubor: table_user_account.sql
 * Tabulka: user_account (Uživatelské účty)
 * Popis:   Evidence globálních uživatelských účtů (object_owner = 0x00).
 *          Uchovává čistě globální identitu, kontaktní údaje a autentizaci osoby.
 *          Přístup do konkrétních tenantů a organizačně závislé zařazení
 *          (department_name, job_title, manager_uuid, note, working_date,
 *          evaluation_method) řeší tabulka user_organization_access.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Změny:
 * - 2026-10-29 15:30: Organizačně závislé sloupce (department_name, job_title,
 *   manager_uuid, note) přesunuty do tabulky user_organization_access.
 *   Doplněny SSC sloupce draft_author, approval_note, import_origin a index
 *   uq_user_account_draft.
 * ============================================================================= */

IF OBJECT_ID('user_account') IS NULL
BEGIN
	CREATE TABLE user_account (
		-- -------------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,                   -- Globální vlastnictví systémem
		original uuid NOT NULL,
		record_type varchar(1) NOT NULL DEFAULT 'A',
		approval_status varchar(1) NOT NULL DEFAULT 'A',
		draft_author uuid NOT NULL DEFAULT 0x00,
		approval_note varchar(max) NOT NULL DEFAULT '',
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		is_template bit NOT NULL DEFAULT 0,
		template uuid NULL,
		import_origin varchar(255) NULL,
		
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
		-- Specifické byznys sloupce uživatele (Autentizace a Globální identita)
		-- -------------------------------------------------------------------------
		login_name varchar(100) NOT NULL DEFAULT '',
		email varchar(200) NOT NULL DEFAULT '',
		password_hash varchar(255) NOT NULL DEFAULT '',
		
		-- Řízení bezpečnostních politik pro SSO / Lokální přihlášení
		allow_local_login bit NOT NULL DEFAULT 1,
		is_system_admin bit NOT NULL DEFAULT 0,
		is_developer bit NOT NULL DEFAULT 0,                       -- Příznak role vývojáře (Developer)
		require_password_change bit NOT NULL DEFAULT 0,
		failed_login_attempts int NOT NULL DEFAULT 0,
		locked_until datetime NULL,
		last_login_date datetime NULL,
		last_password_change datetime NULL,
		mfa_enabled bit NOT NULL DEFAULT 0,
		mfa_secret varchar(100) NOT NULL DEFAULT '',
		
		-- Kontext poslední navštívené organizace (pro automatické přihlášení)
		last_login_organization uuid NULL,
		
		-- Osobní a kontaktní údaje osoby
		user_title_before varchar(40) NOT NULL DEFAULT '',
		first_name varchar(100) NOT NULL DEFAULT '',
		last_name varchar(100) NOT NULL DEFAULT '',
		user_title_after varchar(40) NOT NULL DEFAULT '',
		phone varchar(50) NOT NULL DEFAULT '',
		mobile varchar(50) NOT NULL DEFAULT '',

		CONSTRAINT pk_user_account PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka user_account byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'user_account', 'last_login_organization', 'uuid NULL';
EXEC p_create_missing_column 'user_account', 'is_developer', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'user_account', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'user_account', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'user_account', 'import_origin', 'varchar(255) NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'user_account', 
	@iname = 'uq_user_account_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'user_account', 
	@iname = 'uq_user_account_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'user_account', 
	@iname = 'uq_user_account_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

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
		is_system_admin, is_developer, allow_local_login, last_login_organization
	) VALUES (
		0x01, 0x00, 0x01, 'A', 'A',
		'System Administrator', 'admin', 'Systémový master uživatelský účet.',
		'sysadmin', 'hink@rac.cz', 'System', 'Administrator',
		1, 1, 1, 0x00
	);
	PRINT 'Systémový účet 0x01 (sysadmin) byl vložen.';
END
ELSE
BEGIN
	UPDATE user_account 
	SET is_developer = 1 
	WHERE original = 0x01 AND record_type = 'A' AND is_developer = 0;
END
GO