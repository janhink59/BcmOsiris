/* =============================================================================
 * Verze: 2026-11-13 18:10
 * Soubor: table_user_organization_access.sql
 * Tabulka: user_organization_access
 * Popis:	Vazební tabulka definující přístup globálních uživatelů 
 *			do konkrétních organizací (tenantů), jejich zařazení v organizaci
 *			(department_name, job_title, manager_uuid, note) a osobní pracovní
 *			parametry uživatele v dané organizaci (working_date, evaluation_method)
 *			včetně obousměrného schvalovacího cyklu (žádost uživatele / pozvánka orgadmina).
 * Vlastník: Záznam (object_owner) patří cílové organizaci, 
 *			která přístup uživateli uděluje.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Změny:	- 2026-11-13 18:10: Doplněna registrace tříd user_organization_access a
 *			  v_user_organization_access a jejich sloupců do sysinit_class a sysinit_column.
 *			- 2026-10-29 15:30: Přesunuty organizačně závislé sloupce z user_account
 *			  (department_name, job_title, manager_uuid, note) a doplněny pracovní
 *			  parametry uživatele v organizaci (working_date, evaluation_method).
 *			- 2026-10-18: Doplněny sloupce draft_author, approval_note a import_origin
 *			  pro podporu konceptů ('D').
 * ============================================================================= */

IF OBJECT_ID('user_organization_access') IS NULL
BEGIN
	CREATE TABLE user_organization_access (
		-- -------------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00, -- Sem se zapisuje UUID organizace
		original uuid NOT NULL DEFAULT 0x00,
		record_type varchar(1) NOT NULL DEFAULT 'A',
		approval_status varchar(1) NOT NULL DEFAULT 'A',
		draft_author uuid NOT NULL DEFAULT 0x00, -- Autor žádosti nebo pozvánky (user_account.original)
		approval_note varchar(max) NOT NULL DEFAULT '', -- Poznámka žadatele nebo důvod zamítnutí
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		is_template bit NOT NULL DEFAULT 0,
		template uuid NULL,
		import_origin varchar(255) NULL,

		-- -------------------------------------------------------------------------
		-- Auditní stopy
		-- -------------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- -------------------------------------------------------------------------
		-- Byznys logika (Vazby a Oprávnění v organizaci)
		-- -------------------------------------------------------------------------
		user_account_uuid uuid NOT NULL,         -- Odkaz na globální účet uživatele (user_account.original)
		organization_uuid uuid NOT NULL,         -- Odkaz na organizaci, do které má přístup (organization.original)
		is_orgadmin bit NOT NULL DEFAULT 0,      -- Příznak, zda je uživatel administrátorem dané organizace
		last_role varchar(1) NOT NULL DEFAULT 'U', -- Poslední zvolená role (U=User, A=Admin, S=Sysadmin, D=Developer)
		right_translate bit NOT NULL DEFAULT 0,  -- Příznak práva překládat v rámci této organizace

		-- -------------------------------------------------------------------------
		-- Organizační zařazení a pracovní parametry uživatele v daném tenantovi
		-- -------------------------------------------------------------------------
		department_name varchar(150) NOT NULL DEFAULT '',
		job_title varchar(150) NOT NULL DEFAULT '',
		manager_uuid uuid NULL,
		note varchar(max) NOT NULL DEFAULT '',
		working_date date NULL,                  -- Osobní pracovní datum uživatele v organizaci (NULL = aktuální datum)
		evaluation_method varchar(40) NOT NULL DEFAULT '', -- Osobní volba metody hodnocení v organizaci

		CONSTRAINT pk_user_organization_access PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka user_organization_access byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze a datová migrace
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'user_organization_access', 'last_role', 'varchar(1) NOT NULL DEFAULT ''U''';
EXEC p_create_missing_column 'user_organization_access', 'right_translate', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'user_organization_access', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'user_organization_access', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'user_organization_access', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'user_organization_access', 'department_name', 'varchar(150) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'user_organization_access', 'job_title', 'varchar(150) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'user_organization_access', 'manager_uuid', 'uuid NULL';
EXEC p_create_missing_column 'user_organization_access', 'note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'user_organization_access', 'working_date', 'date NULL';
EXEC p_create_missing_column 'user_organization_access', 'evaluation_method', 'varchar(40) NOT NULL DEFAULT ''''';
GO

-- Migrace organizačních údajů z user_account (pokud v user_account ještě existují) a jejich odstranění
IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'user_account' AND colname = 'department_name')
BEGIN
	EXEC('
		UPDATE uoa
		SET uoa.department_name = CASE WHEN uoa.department_name = '''' THEN u.department_name ELSE uoa.department_name END,
			uoa.job_title = CASE WHEN uoa.job_title = '''' THEN u.job_title ELSE uoa.job_title END,
			uoa.manager_uuid = COALESCE(uoa.manager_uuid, u.manager_uuid),
			uoa.note = CASE WHEN uoa.note = '''' THEN u.note ELSE uoa.note END
		FROM user_organization_access uoa
		JOIN user_account u ON u.original = uoa.user_account_uuid AND u.record_type = ''A''
	');
	EXEC sp_drop_column 'user_account', 'department_name';
	EXEC sp_drop_column 'user_account', 'job_title';
	EXEC sp_drop_column 'user_account', 'manager_uuid';
	EXEC sp_drop_column 'user_account', 'note';
END
GO

IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'user_organization_access' AND colname = 'last_orgadmin')
BEGIN
	EXEC('UPDATE user_organization_access SET last_role = ''A'' WHERE last_orgadmin = 1 AND last_role = ''U''');
	EXEC sp_drop_column 'user_organization_access', 'last_orgadmin';
	PRINT 'Sloupec last_orgadmin byl úspěšně migrován a odstraněn.';
END
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'user_organization_access', 
	@iname = 'uq_user_org_access_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'user_organization_access', 
	@iname = 'uq_user_organization_access_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'user_organization_access', 
	@iname = 'ix_user_org_access_user', 
	@colnames = 'user_account_uuid, organization_uuid', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

-- -----------------------------------------------------------------------------
-- Inicializace: Přístup System Administrátora do systémové organizace
-- -----------------------------------------------------------------------------
IF NOT EXISTS(
	SELECT 1 FROM user_organization_access 
	WHERE user_account_uuid = 0x01 
	  AND organization_uuid = 0x00 
	  AND record_type = 'A'
)
BEGIN
	INSERT INTO user_organization_access (
		uuid,
		object_owner,
		original,
		record_type,
		approval_status,
		user_account_uuid,
		organization_uuid,
		is_orgadmin,
		last_role,
		right_translate,
		who_created,
		who_modified
	) VALUES (
		NEWID(),
		0x00,
		NEWID(),
		'A',
		'A',
		0x01,
		0x00,
		1,
		'S',
		1,
		0x01,
		0x01
	);
END

UPDATE user_organization_access 
SET original = uuid 
WHERE user_account_uuid = 0x01 AND organization_uuid = 0x00 AND record_type = 'A' AND original <> uuid;
GO

-- -----------------------------------------------------------------------------
-- Registrace tříd a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name IN ('user_organization_access', 'v_user_organization_access');

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('user_organization_access','cs','T','user_organization_access','Přístup uživatele do organizace','Přístupy uživatelů do organizace','Vazební evidence oprávnění, rolí, pracovního zařazení a osobního nastavení uživatele v konkrétní organizaci.','Řídí přístup uživatele k organizaci, právo OrgAdmina, právo překladu a organizační zařazení.'),
	('v_user_organization_access','cs','V','v_user_organization_access','Pohled přístupů uživatelů k organizacím','Pohled přístupů uživatelů','Spojený pohled uživatelů, jejich přístupů do organizací a stavu licencí pro rychlé vyhodnocení přihlášení.','Podkladový pohled pro přihlašování a správu uživatelů organizace.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('user_organization_access','en','User Organization Access','User Organization Accesses','Relational registry of permissions, roles, job assignment, and personal settings of a user in a specific organization.','Controls user access to an organization, OrgAdmin privileges, translation rights, and job assignment.'),
	('v_user_organization_access','en','User Organization Access View','User Organization Access View','Joined view of users, their organization accesses, and licence states for fast login evaluation.','Underlying view for authentication and organization user management.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name IN ('user_organization_access', 'v_user_organization_access');

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		referenced_class_code
	) VALUES
	('user_organization_access','department_name','cs','Oddělení / útvar (department_name)','Název oddělení / útvaru','Oddělení','Organizační útvar nebo oddělení, ve kterém uživatel v rámci dané organizace působí.',''),
	('user_organization_access','evaluation_method','cs','Metoda hodnocení rizik (evaluation_method)','Zvolená metodika hodnocení CRMM','Metoda hodnocení','Kód metodiky nebo výpočtového modelu používaného pro vyhodnocení rizik.',''),
	('user_organization_access','is_orgadmin','cs','Administrátor organizace (is_orgadmin)','Oprávnění administrátora organizace','Admin org.','Uděluje uživateli roli administrátora (A) v rámci dané organizace.',''),
	('user_organization_access','job_title','cs','Pracovní pozice / funkce (job_title)','Pracovní pozice / funkce','Pozice','Název pracovní pozice nebo funkčního zařazení uživatele v organizaci.',''),
	('user_organization_access','last_role','cs','Naposledy zvolená role (last_role)','Naposledy použitá role v organizaci','Posl. role','Kód aplikační role (U, A, S, D), kterou měl uživatel naposledy aktivní v této organizaci.',''),
	('user_organization_access','manager_uuid','cs','Nadřízený pracovník (manager_uuid)','Přímý nadřízený pracovník','Nadřízený','Odkaz na účet přímého nadřízeného pracovníka v rámci dané organizace.','user_account'),
	('user_organization_access','organization_uuid','cs','Cílová organizace (organization_uuid)','Organizace (UUID)','Organizace','Odkaz na originální identifikátor organizace v tabulce organization.','organization'),
	('user_organization_access','right_translate','cs','Právo překládat (right_translate)','Oprávnění pořizovat překlady','Právo překladu','Opravňuje uživatele ukládat jazykové překlady (v garantující organizaci i globálně pro systém).',''),
	('user_organization_access','user_account_uuid','cs','Uživatelský účet (user_account_uuid)','Uživatel (UUID účtu)','Uživatel (UUID)','Odkaz na globální účet uživatele v tabulce user_account.','user_account'),
	('user_organization_access','working_date','cs','Pracovní datum (working_date)','Osobní pracovní datum (prázdné = dnes)','Pracovní datum','Datum, ke kterému se vyhodnocuje časová platnost záznamů v relaci uživatele.',''),
	('v_user_organization_access','access_uuid','cs','UUID přístupu (access_uuid)','Logický identifikátor přístupu','UUID přístupu','Logický identifikátor záznamu v tabulce user_organization_access.',''),
	('v_user_organization_access','current_organization','cs','Aktuální organizace relace (current_organization)','Právě aktivní organizace v relaci','Aktuální org.','Identifikátor organizace právě aktivní v dbsession pro daného uživatele.',''),
	('v_user_organization_access','last_login_org','cs','Poslední přihlášená organizace (last_login_org)','Naposledy navštívená organizace','Posl. organizace','Identifikátor organizace, do které se uživatel naposledy přihlásil.','');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('user_organization_access','department_name','en','Department / Unit (department_name)','Department / Unit Name','Department','Organizational unit or department in which the user works within the organization.'),
	('user_organization_access','evaluation_method','en','Risk Evaluation Method (evaluation_method)','Selected CRMM Evaluation Method','Evaluation Method','Code of the methodology or calculation model used for risk evaluation.'),
	('user_organization_access','is_orgadmin','en','Organization Administrator (is_orgadmin)','Organization Administrator Privilege','Org. Admin','Grants the user administrator (A) privileges within the specific organization.'),
	('user_organization_access','job_title','en','Job Title / Position (job_title)','Job Title / Position','Job Title','Job title or functional position of the user within the organization.'),
	('user_organization_access','last_role','en','Last Selected Role (last_role)','Last Active Role in Organization','Last Role','Application role code (U, A, S, D) last used by the user in this organization.'),
	('user_organization_access','manager_uuid','en','Line Manager (manager_uuid)','Direct Line Manager','Manager','Reference to the user account of the direct manager within the organization.'),
	('user_organization_access','organization_uuid','en','Target Organization (organization_uuid)','Organization (UUID)','Organization','Reference to the original identifier of the organization in the organization table.'),
	('user_organization_access','right_translate','en','Translation Right (right_translate)','Authorized to Save Translations','Translation Right','Authorizes the user to save language translations (globally if in the guarantee translator organization).'),
	('user_organization_access','user_account_uuid','en','User Account (user_account_uuid)','User (Account UUID)','User (UUID)','Reference to the global user account in the user_account table.'),
	('user_organization_access','working_date','en','Working Date (working_date)','Personal Working Date (Empty = Today)','Working Date','Effective date used to evaluate temporal validity of records in the user session.'),
	('v_user_organization_access','access_uuid','en','Access UUID (access_uuid)','Logical Access Record Identifier','Access UUID','Logical record identifier in the user_organization_access table.'),
	('v_user_organization_access','current_organization','en','Current Session Organization (current_organization)','Currently Active Organization in Session','Current Org.','Identifier of the organization currently active in dbsession for the user.'),
	('v_user_organization_access','last_login_org','en','Last Login Organization (last_login_org)','Last Visited Organization','Last Org.','Identifier of the organization into which the user last logged in.');
END
GO