/* =============================================================================
 * Verze: 2026-10-29 15:30
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
 * Změny:	- 2026-10-29 15:30: Přesunuty organizačně závislé sloupce z user_account
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