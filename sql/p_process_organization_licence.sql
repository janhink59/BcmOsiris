EXECUTE dropni 'p_process_organization_licence', 'P'
GO

/* =============================================================================
 * Procedura: p_process_organization_licence
 * Účel: Dávkové zpracování schválené licence (APPROVED) a aktivace nového tenanta.
 * 
 * Byznys proces a RAC vazby:
 * - Je volána automaticky z modulu page_organization_licence při uložení žádosti.
 * - Spolehlivě zprostředkuje zápis nové organizace (s vlastní object_owner linií),
 *   založí účet pro lokálního administrátora a spáruje je přístupovými právy 
 *   přes user_organization_access.
 * - Obsahuje reaktivační UPDATE větev pro bezbolestnou opravu poškozených dat
 *   (dokáže zaktualizovat caption u chybné instalace bez zásahu do uuid).
 * ============================================================================= */
CREATE PROCEDURE p_process_organization_licence
	@licence_original uniqueidentifier,
	@who_modified uniqueidentifier = 0x00
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @licence_state varchar(20);
	DECLARE @org_uuid uniqueidentifier;
	DECLARE @org_name varchar(200);
	DECLARE @login_domain varchar(200);
	DECLARE @licence_level tinyint;
	
	DECLARE @admin_login varchar(200);
	DECLARE @admin_first_name varchar(200);
	DECLARE @admin_last_name varchar(200);
	DECLARE @admin_email varchar(200);
	DECLARE @user_uuid uniqueidentifier;

	BEGIN TRAN;

	-- Vyhledání nezbytných dat ze zdrojové žádosti
	SELECT 
		@licence_state = licence_state,
		@org_uuid = NULLIF(organization_uuid, 0x00),
		@org_name = caption,
		@login_domain = login_domain,
		@licence_level = licence_level,
		@admin_login = admin_login,
		@admin_first_name = admin_first_name,
		@admin_last_name = admin_last_name,
		@admin_email = admin_email
	FROM organization_licence
	WHERE original = @licence_original AND record_type = 'A' AND removed = 0;

	-- Detekce neoprávněného stavu bránící spuštění procesu
	IF @licence_state IS NULL OR @licence_state <> 'APPROVED'
	BEGIN
		ROLLBACK;
		RAISERROR('Licence neexistuje nebo není ve stavu APPROVED.', 16, 1);
		RETURN;
	END

	-- Alokace a zápis nového tenanta do organizace
	IF @org_uuid IS NULL
	BEGIN
		SET @org_uuid = NEWID();
		
		INSERT INTO organization (
			uuid, object_owner, original, record_type, approval_status,
			caption, shortname, login_domain, licence_level,
			who_created, who_modified
		) VALUES (
			@org_uuid, @org_uuid, @org_uuid, 'A', 'A',
			@org_name, SUBSTRING(@org_name, 1, 40), @login_domain, @licence_level,
			@who_modified, @who_modified
		);
	END
	ELSE
	BEGIN
		-- Aktualizační oprava při opětovném průchodu (reaktivace licence)
		UPDATE organization 
		SET licence_level = @licence_level,
			caption = @org_name,
			shortname = SUBSTRING(@org_name, 1, 40),
			login_domain = @login_domain,
			date_modified = GETDATE(),
			who_modified = @who_modified
		WHERE original = @org_uuid AND record_type = 'A';
	END

	-- Dohledání globálního účtu organizátora na základě loginu
	SELECT @user_uuid = original 
	FROM user_account 
	WHERE login_name = @admin_login AND record_type = 'A' AND removed = 0;

	-- Založení účtu, pokud ještě v systému neexistuje
	IF @user_uuid IS NULL
	BEGIN
		SET @user_uuid = NEWID();
		
		INSERT INTO user_account (
			uuid, object_owner, original, record_type, approval_status,
			caption, login_name, email, first_name, last_name,
			who_created, who_modified
		) VALUES (
			@user_uuid, 0x00, @user_uuid, 'A', 'A',
			@admin_first_name + ' ' + @admin_last_name, @admin_login, @admin_email, @admin_first_name, @admin_last_name,
			@who_modified, @who_modified
		);
	END

	-- Vytvoření administrátorského přístupového bodu pro novou organizaci
	IF NOT EXISTS (
		SELECT 1 FROM user_organization_access 
		WHERE user_account_uuid = @user_uuid AND organization_uuid = @org_uuid AND record_type = 'A' AND removed = 0
	)
	BEGIN
		DECLARE @access_uuid uniqueidentifier = NEWID();
		
		INSERT INTO user_organization_access (
			uuid, object_owner, original, record_type, approval_status,
			user_account_uuid, organization_uuid, is_orgadmin,
			who_created, who_modified
		) VALUES (
			@access_uuid, @org_uuid, @access_uuid, 'A', 'A',
			@user_uuid, @org_uuid, 1,
			@who_modified, @who_modified
		);
	END

	-- Převedení zdrojové licence do stavu dokončeno
	UPDATE organization_licence
	SET licence_state = 'PROCESSED',
		organization_uuid = @org_uuid,
		activation_date = CAST(GETDATE() AS DATE),
		date_modified = GETDATE(),
		who_modified = @who_modified
	WHERE original = @licence_original AND record_type = 'A';

	COMMIT;
END
GO