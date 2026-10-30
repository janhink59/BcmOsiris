/* =============================================================================
 * Verze: 2026-10-30 23:35
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
 * - 2026-10-30 23:35: Při vkládání výchozího záznamu systémové organizace (0x00)
 *   se admin_email načítá ze system_constant.sysadmin_email.
 * - 2026-10-29 15:30: Přesunut sloupec login_disabled z tabulky organization.
 *   Odstraněny duplicitní sloupce is_developer (nahrazeno licence_level = 255)
 *   a organization_name (používá se caption). Doplněny SSC sloupce draft_author,
 *   approval_note, import_origin, index uq_organization_licence_draft a výchozí
 *   licenční záznam pro systémovou organizaci 0x00.
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

-- Doplnění chybějícího builtin_code u existujících licencí
UPDATE organization_licence 
SET builtin_code = SUBSTRING(caption, 1, 80) 
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
		'SYS', 'System', 'SYS', 'Licence systémové master organizace.',
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