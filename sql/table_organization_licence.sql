/* =============================================================================
 * Verze: 2026-11-13 17:30
 * Soubor: table_organization_licence.sql
 * Tabulka: organization_licence
 * Popis:   Evidence licencí organizací. Každá organizace (včetně systémové 0x00)
 *          musí mít záznam v této tabulce, kde se zakládá.
 *          Výhradně zde jsou uloženy sloupce licence_level a login_disabled,
 *          které nesmí cílová organizace sama měnit.
 *          - licence_level = 255 (Developer) umožňuje organizaci přidávat do
 *            systému developery (user_account.is_developer = 1).
 *          - licence_level = 40 (Enterprise) a 255 (Developer) umožňuje
 *            vytvářet licence dalším organizacím.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - organization_uuid ukazuje na organization.original
 *          - licence_level ukazuje na licence_level.licence_level
 *          - Výchozí záznam pro systémovou organizaci 0x00 čte sysadmin_email
 *            z tabulky system_constant.
 *          - Zpracováváno procedurou p_process_organization_licence a čteno
 *            při přihlášení v p_set_login a v_user_organization_access.
 * Změny:
 * - 2026-11-13 17:30: Doplněna registrace třídy a sloupců do sysinit_class
 *   a sysinit_column.
 * - 2026-11-09 18:30: Sjednocen builtin_code systémové licence na 'sys' (snake_case).
 * - 2026-10-30 23:35: Při vkládání výchozího záznamu systémové organizace (0x00)
 *   se admin_email načítá ze system_constant.sysadmin_email.
 * ============================================================================= */

-- Kontrola a odstranění tabulky, pokud pochází ze starého systému
IF EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='admin_initial_password')
	OR EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='admin_sex')
	OR EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='guid')
	OR NOT EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='licence_state')
	EXECUTE dropni 'organization_licence';
GO

IF OBJECT_ID('organization_licence') IS NULL
BEGIN
	CREATE TABLE organization_licence (
		-- -------------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,           -- Vydavatel licence (0x00 nebo Enterprise/Developer organizace)
		original uuid NOT NULL DEFAULT 0x00,
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
		-- Společné textové vlastnosti
		-- -------------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',
		caption varchar(200) NOT NULL DEFAULT '',          -- Název licencované organizace
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		instance_class_name varchar(80) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		
		-- -------------------------------------------------------------------------
		-- Auditní stopy
		-- -------------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- -------------------------------------------------------------------------
		-- Specifické licenční sloupce (pod kontrolou vydavatele licence)
		-- -------------------------------------------------------------------------
		licence_state varchar(20) NOT NULL DEFAULT 'DRAFT', -- DRAFT, APPROVED, PROCESSED, REJECTED
		licence_level tinyint NOT NULL DEFAULT 0,           -- 0=Demo, 10=Standard, 20=Expert, 30=Custom, 40=Enterprise, 255=Developer
		login_disabled bit NOT NULL DEFAULT 0,              -- 1 = Zablokování přihlášení všem uživatelům této organizace

		organization_uuid uuid NOT NULL DEFAULT 0x00,       -- Vazba na založenou organizaci (organization.original)
		server_licence uuid NOT NULL DEFAULT 0x00,
		login_domain varchar(200) NOT NULL DEFAULT '',
		organization_note varchar(max) NOT NULL DEFAULT '',
		authorization_code uuid NOT NULL DEFAULT 0x00,
		activation_date date NULL,
		
		ip_address varchar(200) NOT NULL DEFAULT '',
		preferred_language varchar(2) NOT NULL DEFAULT 'cs',
		admin_login varchar(200) NOT NULL DEFAULT '',
		admin_first_name varchar(200) NOT NULL DEFAULT '',
		admin_last_name varchar(200) NOT NULL DEFAULT '',
		admin_email varchar(200) NOT NULL DEFAULT '',
		digital_signature varbinary(20) NULL,

		CONSTRAINT pk_organization_licence PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka organization_licence byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců a vyčištění duplicit pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'organization_licence', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization_licence', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'organization_licence', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization_licence', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'organization_licence', 'login_disabled', 'bit NOT NULL DEFAULT 0';
GO

IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'organization_licence' AND colname = 'is_developer')
BEGIN
	EXEC('UPDATE organization_licence SET licence_level = 255 WHERE is_developer = 1 AND licence_level < 255');
	EXEC sp_drop_column 'organization_licence', 'is_developer';
END
GO

IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'organization_licence' AND colname = 'organization_name')
BEGIN
	EXEC('UPDATE organization_licence SET caption = organization_name WHERE caption = '''' AND organization_name <> ''''');
	EXEC sp_drop_column 'organization_licence', 'organization_name';
END
GO

-- Doplnění chybějícího builtin_code u existujících licencí v snake_case
UPDATE organization_licence 
SET builtin_code = LOWER(REPLACE(REPLACE(LTRIM(RTRIM(SUBSTRING(caption, 1, 60))), ' ', '_'), '-', '_'))
WHERE builtin_code = '' AND caption <> '';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'organization_licence', 
	@iname = 'uq_organization_licence_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_licence', 
	@iname = 'uq_organization_licence_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_licence', 
	@iname = 'uq_organization_licence_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_licence', 
	@iname = 'ix_organization_licence_org', 
	@colnames = 'organization_uuid, licence_state', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Inicializační licenční záznam pro systémovou master organizaci (0x00)
-- Využívá sysadmin_email z tabulky system_constant.
-- -----------------------------------------------------------------------------
DECLARE @sysadmin_email varchar(200) = '';
IF OBJECT_ID('system_constant') IS NOT NULL
BEGIN
	SELECT TOP 1 @sysadmin_email = ISNULL(LTRIM(RTRIM(sysadmin_email)), '')
	FROM system_constant;
END

IF NOT EXISTS (SELECT 1 FROM organization_licence WHERE organization_uuid = 0x00 AND record_type = 'A' AND removed = 0)
BEGIN
	DECLARE @sys_lic uuid = CONVERT(
		uniqueidentifier,
		HASHBYTES('MD5', 'organization_licence|' + LOWER(CONVERT(varchar(36), CAST(0x00 AS uniqueidentifier))) + '|sys|')
	);

	INSERT INTO organization_licence (
		uuid, object_owner, original, record_type, approval_status, [language],
		builtin_code, caption, shortname, description_text,
		licence_state, licence_level, organization_uuid, login_disabled,
		admin_login, admin_first_name, admin_last_name, admin_email, activation_date
	) VALUES (
		@sys_lic, 0x00, @sys_lic, 'A', 'A', 'cs',
		'sys', 'System', 'SYS', 'Licence systémové master organizace.',
		'PROCESSED', 255, 0x00, 0,
		'sysadmin', 'System', 'Administrator', @sysadmin_email, CAST(GETDATE() AS date)
	);
END
ELSE IF @sysadmin_email <> ''
BEGIN
	UPDATE organization_licence
	SET admin_email = @sysadmin_email
	WHERE organization_uuid = 0x00
	  AND record_type = 'A'
	  AND removed = 0
	  AND who_modified = 0x00
	  AND admin_email = '';
END
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'organization_licence';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('organization_licence','cs','T','organization_licence','Licence organizace','Licence organizací','Evidence licencí organizací, licenčních úrovní, stavů aktivace a výchozích správcovských účtů.','Slouží k založení a aktivaci nové organizace, nastavení úrovně licence (Demo až Developer) a případné blokaci přihlášení.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('organization_licence','en','Organization Licence','Organization Licences','Registry of organization licences, licence levels, activation states, and initial administrator accounts.','Used to create and activate new organizations, assign licence levels (Demo to Developer), or disable login.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'organization_licence';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('organization_licence','activation_date','cs','Datum aktivace (activation_date)','Datum aktivace licence','Aktivováno dne','Datum, kdy byla licence zpracována a organizace aktivována.'),
	('organization_licence','admin_email','cs','E-mail správce (admin_email)','E-mail administrátora organizace','E-mail admina','Kontaktní e-mailová adresa administrátora organizace.'),
	('organization_licence','admin_first_name','cs','Jméno správce (admin_first_name)','Křestní jméno administrátora','Jméno admina','Křestní jméno výchozího administrátora organizace.'),
	('organization_licence','admin_last_name','cs','Příjmení správce (admin_last_name)','Příjmení administrátora','Příjmení admina','Příjmení výchozího administrátora organizace.'),
	('organization_licence','admin_login','cs','Login správce organizace (admin_login)','Login prvního administrátora','Login admina','Přihlašovací jméno výchozího administrátora zakládané organizace.'),
	('organization_licence','authorization_code','cs','Autorizační kód (authorization_code)','Autorizační kód aktivace','Autorizační kód','Unikátní identifikátor pro autorizaci licenčního požadavku.'),
	('organization_licence','digital_signature','cs','Digitální podpis (digital_signature)','Kontrolní digitální podpis','Podpis','Binární kontrolní součet nebo podpis záznamu.'),
	('organization_licence','ip_address','cs','IP adresa (ip_address)','Klientská IP adresa','IP adresa','Síťová IP adresa klienta (včetně případné cesty X-Forwarded-For).'),
	('organization_licence','licence_level','cs','Úroveň licence (licence_level)','Úroveň licence organizace','Úroveň licence','Rozsah oprávnění organizace: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
	('organization_licence','licence_state','cs','Stav licence (licence_state)','Stav licenčního záznamu','Stav licence','Životní cyklus licence: DRAFT = koncept, APPROVED = schváleno k aktivaci, PROCESSED = aktivní, REJECTED = zamítnuto.'),
	('organization_licence','login_disabled','cs','Zablokovat přihlášení (login_disabled)','Zablokovat přihlašování organizaci','Přihlášení blok.','Pokud je zaškrtnuto, žádný uživatel se nemůže přihlásit do kontextu této organizace.'),
	('organization_licence','login_domain','cs','Přihlašovací SSO doména (login_domain)','Doména pro SSO přihlášení','SSO doména','Internetová doména organizace pro automatické rozpoznání domovského tenanta při SSO autentizaci.'),
	('organization_licence','organization_note','cs','Poznámka k licenci (organization_note)','Interní poznámka k licenci organizace','Pozn. k licenci','Doplňující poznámka vydavatele licence k licencované organizaci.'),
	('organization_licence','organization_uuid','cs','Cílová organizace (organization_uuid)','Organizace (UUID)','Organizace','Odkaz na originální identifikátor organizace v tabulce organization.'),
	('organization_licence','preferred_language','cs','Výchozí jazyk organizace (preferred_language)','Preferovaný výchozí jazyk','Výchozí jazyk','Výchozí jazyk prostředí a dat pro nově zakládané uživatele a záznamy organizace.'),
	('organization_licence','server_licence','cs','Licence serveru (server_licence)','Identifikátor serverové licence','Licence serveru','Kód nebo klíč serverové licence.'),
	('organization_licence','activation_date','en','Activation Date (activation_date)','Licence Activation Date','Activated On','Date when the licence was processed and the organization activated.'),
	('organization_licence','admin_email','en','Admin Email (admin_email)','Organization Administrator Email','Admin Email','Contact email address of the organization administrator.'),
	('organization_licence','admin_first_name','en','Admin First Name (admin_first_name)','Administrator First Name','Admin First Name','First name of the initial organization administrator.'),
	('organization_licence','admin_last_name','en','Admin Last Name (admin_last_name)','Administrator Last Name','Admin Last Name','Last name of the initial organization administrator.'),
	('organization_licence','admin_login','en','Organization Admin Login (admin_login)','Initial Administrator Login','Admin Login','Login name of the initial administrator of the newly created organization.'),
	('organization_licence','authorization_code','en','Authorization Code (authorization_code)','Activation Authorization Code','Auth. Code','Unique identifier for authorizing the licence request.'),
	('organization_licence','digital_signature','en','Digital Signature (digital_signature)','Verification Digital Signature','Signature','Binary checksum or digital signature of the record.'),
	('organization_licence','ip_address','en','IP Address (ip_address)','Client IP Address','IP Address','Network IP address of the client (including X-Forwarded-For path).'),
	('organization_licence','licence_level','en','Licence Level (licence_level)','Organization Licence Level','Licence Level','Organization permission tier: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
	('organization_licence','licence_state','en','Licence State (licence_state)','Licence Lifecycle State','Licence State','Licence lifecycle state: DRAFT, APPROVED (triggers activation), PROCESSED (active), REJECTED.'),
	('organization_licence','login_disabled','en','Disable Login (login_disabled)','Disable Login for Organization','Login Disabled','If checked, no user can log into the context of this organization.'),
	('organization_licence','login_domain','en','SSO Login Domain (login_domain)','Domain for SSO Login','SSO Domain','Internet domain of the organization used to automatically detect the home tenant during SSO authentication.'),
	('organization_licence','organization_note','en','Licence Note (organization_note)','Internal Note on Organization Licence','Licence Note','Additional note by the licence issuer regarding the licensed organization.'),
	('organization_licence','organization_uuid','en','Target Organization (organization_uuid)','Organization (UUID)','Organization','Reference to the original identifier of the organization in the organization table.'),
	('organization_licence','preferred_language','en','Default Organization Language (preferred_language)','Preferred Default Language','Default Language','Default UI and data language for newly created users and records in the organization.'),
	('organization_licence','server_licence','en','Server Licence (server_licence)','Server Licence Identifier','Server Licence','Code or key of the server licence.');
END
GO