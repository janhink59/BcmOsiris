/* =============================================================================
 * Tabulka: user_organization_access
 * Popis:	Vazební tabulka definující přístup globálních uživatelů 
 *			do konkrétních organizací (tenantů).
 * Vlastník: Záznam (object_owner) by měl patřit cílové organizaci, 
 *			která přístup uživateli uděluje.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * ============================================================================= */

IF OBJECT_ID('user_organization_access') IS NULL
BEGIN
	CREATE TABLE user_organization_access (
		-- -------------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00, -- Sem se bude zapisovat UUID organizace
		original uuid NOT NULL DEFAULT 0x00,
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
		-- Auditní stopy
		-- -------------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- -------------------------------------------------------------------------
		-- Byznys logika (Vazby a Oprávnění)
		-- -------------------------------------------------------------------------
		
		-- Odkaz na globální účet uživatele (user_account.original)
		user_account_uuid uuid NOT NULL,
		
		-- Odkaz na organizaci, do které má přístup (organization.original)
		organization_uuid uuid NOT NULL,
		
		-- Příznak, zda je uživatel administrátorem dané organizace
		is_orgadmin bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_user_organization_access PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka user_organization_access byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka a originál.
EXEC sp_create_index 
	@tname = 'user_organization_access', 
	@iname = 'uq_user_org_access_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Optimalizační indexy pro byznys logiku (přihlašování)
-- -----------------------------------------------------------------------------

-- Rychlé vyhledání všech organizací, do kterých má konkrétní uživatel přístup
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

-- Ujistíme se, že sysadmin (uživatel 0x01) má přístup jako orgadmin do systémové organizace (0x00)
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
		who_created,
		who_modified
	) VALUES (
		NEWID(), -- unikátní GUID záznamu
		0x00,    -- owner = systémová organizace
		NEWID(), -- originál musí mít vlastní UUID, není to 0x00 systémový záznam v pravém slova smyslu, jen logické propojení
		'A',
		'A',
		0x01,    -- user_account_uuid = id sysadmina
		0x00,    -- organization_uuid = systémová org
		1,       -- is_orgadmin
		0x01,
		0x01
	);
	
	-- Originál zkopírujeme do UUID, abychom udrželi RAC standard 
	-- (při inzerci NEWID() nevíme jaký vygenerovalo originál, takže to aktualizujeme)
	UPDATE user_organization_access 
	SET original = uuid 
	WHERE user_account_uuid = 0x01 AND organization_uuid = 0x00 AND record_type = 'A';
	
	PRINT 'Vytvořen přístup System Administrátora do systémové organizace.';
END
GO