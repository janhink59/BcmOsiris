/* =============================================================================
 * Verze: 2026-11-13 18:10
 * Soubor: table_user_account.sql
 * Tabulka: user_account (Uživatelské účty)
 * Popis:   Evidence globálních uživatelských účtů (object_owner = 0x00).
 *          Uchovává čistě globální identitu, kontaktní údaje a autentizaci osoby.
 *          Přístup do konkrétních tenantů a organizačně závislé zařazení
 *          (department_name, job_title, manager_uuid, note, working_date,
 *          evaluation_method) řeší tabulka user_organization_access.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Změny:
 * - 2026-11-13 18:10: Doplněna registrace třídy a sloupců do sysinit_class
 *   a sysinit_column.
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

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'user_account';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('user_account','cs','T','user_account','Uživatelský účet','Uživatelské účty','Globální evidence uživatelských účtů, osobních údajů, přihlašovacích jmen a systémových rolí.','Uchovává globální identitu uživatele nezávislou na jednotlivých organizacích.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('user_account','en','User Account','User Accounts','Global registry of user accounts, personal details, login names, and system-wide roles.','Stores global user identity independent of individual organizations.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'user_account';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		is_mandatory, hidden, referenced_class_code
	) VALUES
	('user_account','allow_local_login','cs','Lokální přihlášení heslem (allow_local_login)','Povolit lokální přihlášení heslem','Lokální login','Určuje, zda se uživatel může přihlásit lokálním heslem (nebo zda smí použít výhradně SSO).',0,0,''),
	('user_account','email','cs','E-mailová adresa (email)','E-mail','E-mail','Kontaktní a přihlašovací e-mailová adresa uživatele.',1,0,''),
	('user_account','failed_login_attempts','cs','Neúspěšné pokusy o přihlášení (failed_login_attempts)','Počet neúspěšných pokusů o přihlášení','Chybné loginy','Počítadlo po sobě jdoucích neúspěšných pokusů o zadání hesla.',0,1,''),
	('user_account','first_name','cs','Křestní jméno (first_name)','Křestní jméno','Jméno','Křestní jméno uživatele.',0,0,''),
	('user_account','is_developer','cs','Vývojář systému (is_developer)','Oprávnění vývojáře systému (Developer)','Vývojář','Umožňuje přihlášení v roli Developer (D) pro správu systémových metadat a struktur.',0,0,''),
	('user_account','is_system_admin','cs','Systémový administrátor (is_system_admin)','Globální správce systému (Sysadmin)','Sysadmin','Uděluje účtu globální oprávnění systémového administrátora (role S).',0,0,''),
	('user_account','last_login_date','cs','Datum posledního přihlášení (last_login_date)','Naposledy přihlášen dne','Posl. přihlášení','Datum a čas posledního úspěšného přihlášení uživatele do systému.',0,1,''),
	('user_account','last_login_organization','cs','Poslední navštívená organizace (last_login_organization)','Naposledy aktivní organizace','Posl. organizace','Odkaz na organizaci, do které byl uživatel naposledy přihlášen.',0,1,'organization'),
	('user_account','last_name','cs','Příjmení (last_name)','Příjmení','Příjmení','Příjmení uživatele.',1,0,''),
	('user_account','last_password_change','cs','Datum poslední změny hesla (last_password_change)','Heslo naposledy změněno dne','Změna hesla','Datum a čas poslední změny lokálního hesla uživatele.',0,1,''),
	('user_account','locked_until','cs','Účet uzamčen do (locked_until)','Dočasné uzamčení účtu do','Uzamčeno do','Časový údaj, do kdy je účet dočasně zablokován po překročení limitu chybných přihlášení.',0,1,''),
	('user_account','login_name','cs','Přihlašovací jméno (login_name)','Přihlašovací jméno (login)','Login','Unikátní přihlašovací jméno uživatele v systému.',1,0,''),
	('user_account','mfa_enabled','cs','Dvoufaktorové ověření (mfa_enabled)','Vyžadovat dvoufaktorové ověření (MFA)','MFA zapnuto','Příznak aktivace vícefaktorového ověřování u účtu uživatele.',0,0,''),
	('user_account','mfa_secret','cs','Tajný klíč MFA (mfa_secret)','Šifrovací klíč TOTP / MFA','MFA klíč','Tajný klíč pro generování jednorázových TOTP kódů dvoufaktorového ověření.',0,1,''),
	('user_account','mobile','cs','Mobilní telefon (mobile)','Mobilní telefon (pro SMS / MFA)','Mobil','Číslo mobilního telefonu uživatele.',0,0,''),
	('user_account','password_hash','cs','Hash hesla (password_hash)','Kryptografický hash hesla','Hash hesla','Bezpečně uložený otisk hesla uživatele pro lokální přihlášení.',0,1,''),
	('user_account','phone','cs','Telefon (phone)','Telefonní číslo','Telefon','Pevná linka nebo kontaktní telefonní číslo uživatele.',0,0,''),
	('user_account','require_password_change','cs','Vyžadovat změnu hesla (require_password_change)','Vynutit změnu hesla při příštím přihlášení','Vynutit změnu hesla','Pokud je zaškrtnuto, uživatel musí po přihlášení nastavit nové heslo.',0,0,''),
	('user_account','user_title_after','cs','Titul za jménem (user_title_after)','Titul za jménem (např. Ph.D.)','Titul za','Akademický nebo profesní titul uváděný za příjmením.',0,0,''),
	('user_account','user_title_before','cs','Titul před jménem (user_title_before)','Titul před jménem (např. Ing.)','Titul před','Akademický nebo profesní titul uváděný před jménem.',0,0,'');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('user_account','allow_local_login','en','Allow Local Password Login (allow_local_login)','Allow Local Password Login','Local Login','Indicates whether the user may log in using a local password (or must use SSO exclusively).'),
	('user_account','email','en','Email Address (email)','Email','Email','Contact and login email address of the user.'),
	('user_account','failed_login_attempts','en','Failed Login Attempts (failed_login_attempts)','Consecutive Failed Login Attempts','Failed Logins','Counter of consecutive failed password login attempts.'),
	('user_account','first_name','en','First Name (first_name)','First Name','First Name','First (given) name of the user.'),
	('user_account','is_developer','en','System Developer (is_developer)','System Developer Privilege (Role D)','Developer','Allows logging in with the Developer (D) role to manage system metadata and structures.'),
	('user_account','is_system_admin','en','System Administrator (is_system_admin)','Global System Administrator (Sysadmin)','Sysadmin','Grants global system administrator privileges (role S) to the user account.'),
	('user_account','last_login_date','en','Last Login Date (last_login_date)','Last Logged In On','Last Login','Date and time of the user last successful login.'),
	('user_account','last_login_organization','en','Last Login Organization (last_login_organization)','Last Active Organization','Last Org.','Reference to the organization into which the user last logged in.'),
	('user_account','last_name','en','Last Name (last_name)','Last Name / Surname','Last Name','Last name (surname) of the user.'),
	('user_account','last_password_change','en','Last Password Change (last_password_change)','Password Last Changed On','Pwd Changed','Date and time when the user local password was last changed.'),
	('user_account','locked_until','en','Account Locked Until (locked_until)','Temporary Account Lockout Until','Locked Until','Timestamp until which the account is temporarily locked after excessive failed login attempts.'),
	('user_account','login_name','en','Login Name (login_name)','User Login Name','Login','Unique login username in the system.'),
	('user_account','mfa_enabled','en','Multi-Factor Authentication (mfa_enabled)','Require Multi-Factor Authentication (MFA)','MFA Enabled','Flag enabling multi-factor authentication for the user account.'),
	('user_account','mfa_secret','en','MFA Secret Key (mfa_secret)','TOTP / MFA Secret Key','MFA Secret','Secret key used to generate one-time TOTP multi-factor authentication codes.'),
	('user_account','mobile','en','Mobile Phone (mobile)','Mobile Phone Number (SMS / MFA)','Mobile','Mobile phone number of the user.'),
	('user_account','password_hash','en','Password Hash (password_hash)','Cryptographic Password Hash','Password Hash','Securely stored password hash for local authentication.'),
	('user_account','phone','en','Phone Number (phone)','Phone Number','Phone','Landline or contact phone number of the user.'),
	('user_account','require_password_change','en','Require Password Change (require_password_change)','Force Password Change on Next Login','Force Pwd Change','If checked, the user must set a new password upon next login.'),
	('user_account','user_title_after','en','Title After Name (user_title_after)','Suffix Title (e.g., Ph.D., MBA)','Title After','Academic or professional title placed after the surname.'),
	('user_account','user_title_before','en','Title Before Name (user_title_before)','Prefix Title (e.g., Dr., Ing.)','Title Before','Academic or professional title placed before the given name.');
END
GO