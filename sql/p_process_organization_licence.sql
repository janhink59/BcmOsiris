EXECUTE dropni 'p_process_organization_licence', 'P'
GO

/* =============================================================================
 * Verze: 2026-10-29 15:30
 * Soubor: p_process_organization_licence.sql
 * Procedura: p_process_organization_licence
 * Účel: Dávkové zpracování schválené licence (APPROVED) a aktivace nového tenanta.
 * 
 * Byznys proces a RAC vazby:
 * - Je volána automaticky z modulu page_organization_licence při uložení žádosti.
 * - Spolehlivě zprostředkuje zápis nové organizace (s vlastní object_owner linií
 *   a symetrickým 'L' záznamem), založí účet pro lokálního administrátora a spáruje
 *   je přístupovými právy přes user_organization_access.
 * - Sloupec licence_level zůstává výhradně v tabulce organization_licence.
 * - Pokud má licence nejvyšší úroveň Developer (licence_level = 255), nastaví
 *   zakládanému administrátorovi příznak is_developer = 1 v user_account.
 * 
 * Změny:
 * - 2026-10-29 15:30: Odstraněn zápis licence_level do tabulky organization
 *   (licence_level je výhradně v organization_licence). Doplněno přenesení
 *   preferred_language do organization a automatické nastavení is_developer = 1
 *   u administrátora při licence_level = 255.
 * ============================================================================= */
CREATE PROCEDURE p_process_organization_licence
	@licence_original uniqueidentifier
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @licence_state varchar(20);
	DECLARE @org_uuid uniqueidentifier;
	DECLARE @org_name varchar(200);
	DECLARE @login_domain varchar(200);
	DECLARE @licence_level tinyint;
	DECLARE @pref_lang varchar(2) = 'cs';
	
	DECLARE @admin_login varchar(200);
	DECLARE @admin_first_name varchar(200);
	DECLARE @admin_last_name varchar(200);
	DECLARE @admin_email varchar(200);
	DECLARE @user_uuid uniqueidentifier;

	-- Získání kontextu přístupu PŘÍMO ze session
	DECLARE @login_session_uuid uniqueidentifier;
	
	SELECT	@login_session_uuid = login_session_uuid
	FROM	dbsession 
	WHERE	spid = @@SPID;
	
	IF @login_session_uuid IS NULL
	BEGIN
		RAISERROR('Bezpečnostní chyba: Nelze ověřit identitu relace (dbsession chybí).', 16, 1);
		RETURN;
	END

	BEGIN TRAN;

	-- Vyhledání nezbytných dat ze zdrojové žádosti
	SELECT 
		@licence_state = licence_state,
		@org_uuid = NULLIF(organization_uuid, 0x00),
		@org_name = caption,
		@login_domain = login_domain,
		@licence_level = licence_level,
		@pref_lang = ISNULL(NULLIF(LTRIM(RTRIM(preferred_language)), ''), 'cs'),
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

	DECLARE @grant_dev bit = CASE WHEN @licence_level = 255 THEN 1 ELSE 0 END;

	-- Alokace a zápis nového tenanta do organizace (bez licence_level, které je pouze v licenci)
	IF @org_uuid IS NULL
	BEGIN
		SET @org_uuid = NEWID();
		
		INSERT INTO organization (
			uuid, object_owner, original, record_type, approval_status, [language],
			caption, shortname, login_domain, preferred_language,
			who_created, who_modified
		) VALUES (
			@org_uuid, @org_uuid, @org_uuid, 'A', 'A', @pref_lang,
			@org_name, SUBSTRING(@org_name, 1, 40), @login_domain, @pref_lang,
			@login_session_uuid, @login_session_uuid
		);

		-- Symetrický 'L' záznam pro výchozí jazyk organizace
		INSERT INTO organization (
			uuid, object_owner, original, record_type, approval_status, [language],
			caption, shortname, login_domain, preferred_language,
			who_created, who_modified
		) VALUES (
			NEWID(), @org_uuid, @org_uuid, 'L', 'A', @pref_lang,
			@org_name, SUBSTRING(@org_name, 1, 40), @login_domain, @pref_lang,
			@login_session_uuid, @login_session_uuid
		);
	END
	ELSE
	BEGIN
		-- Aktualizační oprava při opětovném průchodu (reaktivace licence)
		UPDATE organization 
		SET caption = @org_name,
			shortname = SUBSTRING(@org_name, 1, 40),
			login_domain = @login_domain,
			preferred_language = @pref_lang,
			date_modified = GETDATE(),
			who_modified = @login_session_uuid
		WHERE original = @org_uuid AND record_type = 'A';

		IF EXISTS (
			SELECT 1 FROM organization
			WHERE original = @org_uuid AND object_owner = @org_uuid AND record_type = 'L' AND [language] = @pref_lang AND removed = 0
		)
		BEGIN
			UPDATE organization
			SET caption = @org_name,
				shortname = SUBSTRING(@org_name, 1, 40),
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE original = @org_uuid AND object_owner = @org_uuid AND record_type = 'L' AND [language] = @pref_lang AND removed = 0;
		END
		ELSE
		BEGIN
			INSERT INTO organization (
				uuid, object_owner, original, record_type, approval_status, [language],
				caption, shortname, login_domain, preferred_language,
				who_created, who_modified
			) VALUES (
				NEWID(), @org_uuid, @org_uuid, 'L', 'A', @pref_lang,
				@org_name, SUBSTRING(@org_name, 1, 40), @login_domain, @pref_lang,
				@login_session_uuid, @login_session_uuid
			);
		END
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
			is_developer, last_login_organization,
			who_created, who_modified
		) VALUES (
			@user_uuid, 0x00, @user_uuid, 'A', 'A',
			LTRIM(RTRIM(@admin_first_name + ' ' + @admin_last_name)), @admin_login, @admin_email, @admin_first_name, @admin_last_name,
			@grant_dev, @org_uuid,
			@login_session_uuid, @login_session_uuid
		);
	END
	ELSE IF @grant_dev = 1
	BEGIN
		UPDATE user_account
		SET is_developer = 1,
			date_modified = GETDATE(),
			who_modified = @login_session_uuid
		WHERE original = @user_uuid AND record_type = 'A' AND is_developer = 0;
	END

	-- Vytvoření administrátorského přístupového bodu pro novou organizaci
	IF NOT EXISTS (
		SELECT 1 FROM user_organization_access 
		WHERE user_account_uuid = @user_uuid AND organization_uuid = @org_uuid AND record_type = 'A' AND removed = 0
	)
	BEGIN
		DECLARE @access_uuid uniqueidentifier = dbo.f_generate_original('user_organization_access', @org_uuid, CAST(@user_uuid AS varchar(36)), CAST(@org_uuid AS varchar(36)));
		
		INSERT INTO user_organization_access (
			uuid, object_owner, original, record_type, approval_status,
			user_account_uuid, organization_uuid, is_orgadmin, last_role,
			who_created, who_modified
		) VALUES (
			@access_uuid, @org_uuid, @access_uuid, 'A', 'A',
			@user_uuid, @org_uuid, 1, 'A',
			@login_session_uuid, @login_session_uuid
		);
	END

	-- Převedení zdrojové licence do stavu dokončeno
	UPDATE organization_licence
	SET licence_state = 'PROCESSED',
		organization_uuid = @org_uuid,
		activation_date = CAST(GETDATE() AS DATE),
		date_modified = GETDATE(),
		who_modified = @login_session_uuid
	WHERE original = @licence_original AND record_type = 'A';

	COMMIT;
END
GO