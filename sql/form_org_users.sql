EXECUTE dropni 'form_org_users', 'P'
GO

/* =============================================================================
 * Procedura: form_org_users
 * Účel: Bezpečné uložení, úprava nebo deaktivace uživatele v rámci tenanta.
 * 
 * Architektura a bezpečnost:
 * - Ochrana proti eskalaci privilegií: Běžný admin (A) nemůže přidělovat 
 *   ani odebírat globální role (S, D). Tyto parametry jsou pro něj ignorovány.
 * - Ochrana před sebevražedným zásahem: Uživatel nemůže sám sebe deaktivovat, 
 *   zbavit se org. administrátora ani globálních rolí.
 * - Audit: who_created/who_modified přebírá UUID z login_session_uuid.
 * ============================================================================= */
CREATE PROCEDURE form_org_users
	@organization_uuid uniqueidentifier,
	@user_original uniqueidentifier,
	@login_name varchar(100),
	@email varchar(200),
	@first_name varchar(100),
	@last_name varchar(100),
	@is_orgadmin bit,
	@is_system_admin bit = 0,
	@is_developer bit = 0,
	@remove_access bit = 0,
	@deactivate_global bit = 0
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	
	DECLARE @resolved_user_uuid uniqueidentifier = @user_original;
	DECLARE @access_uuid uniqueidentifier;
	
	-- Získání kontextu přístupu a identity uživatele PŘÍMO ze session
	DECLARE @login_session_uuid uniqueidentifier;
	DECLARE @current_user_account uniqueidentifier;
	DECLARE @active_role varchar(1);
	
	SELECT	@login_session_uuid = login_session_uuid,
		@current_user_account = user_account,
		@active_role = active_role
	FROM	dbsession 
	WHERE	spid = @@SPID;
	
	IF @login_session_uuid IS NULL
	BEGIN
		RAISERROR('Bezpečnostní chyba: Nelze ověřit identitu relace (dbsession chybí).', 16, 1);
		RETURN;
	END

	-- Pokud jde o nového uživatele (bez zadaného ID), pokusíme se najít existující účet
	IF @resolved_user_uuid IS NULL OR @resolved_user_uuid = 0x00
	BEGIN
		SELECT @resolved_user_uuid = original 
		FROM user_account 
		WHERE login_name = @login_name AND record_type = 'A' AND removed = 0;
	END

	-- Načtení stávajících globálních rolí, abychom zamezili eskalaci nebo nechtěné degradaci
	DECLARE @current_sysadmin bit = 0;
	DECLARE @current_developer bit = 0;

	IF @resolved_user_uuid IS NOT NULL
	BEGIN
		SELECT	@current_sysadmin = is_system_admin,
			@current_developer = is_developer
		FROM	user_account
		WHERE	original = @resolved_user_uuid AND record_type = 'A';
	END

	-- BEZPEČNOSTNÍ POJISTKA 1: Ochrana před eskalací privilegií z úrovně lokálního tenanta
	IF @active_role NOT IN ('S', 'D')
	BEGIN
		SET @is_system_admin = @current_sysadmin;
		SET @is_developer = @current_developer;
	END

	-- BEZPEČNOSTNÍ POJISTKA 2: Ochrana před ztrátou kontroly nad vlastním účtem
	IF @resolved_user_uuid = @current_user_account
	BEGIN
		SET @remove_access = 0;
		SET @deactivate_global = 0;
		SET @is_orgadmin = 1;
		SET @is_system_admin = @current_sysadmin;
		SET @is_developer = @current_developer;
	END
	
	BEGIN TRAN;
	
	-- Globální účet uživatele
	IF @resolved_user_uuid IS NULL
	BEGIN
		SET @resolved_user_uuid = NEWID();
		
		INSERT INTO user_account (
			uuid, object_owner, original, record_type, approval_status,
			caption, login_name, email, first_name, last_name, allow_local_login,
			is_system_admin, is_developer, inactive, who_created, who_modified
		) VALUES (
			@resolved_user_uuid, 0x00, @resolved_user_uuid, 'A', 'A',
			LTRIM(RTRIM(@first_name + ' ' + @last_name)), @login_name, @email, @first_name, @last_name, 1,
			@is_system_admin, @is_developer, @deactivate_global, @login_session_uuid, @login_session_uuid
		);
	END
	ELSE
	BEGIN
		UPDATE user_account
		SET caption = LTRIM(RTRIM(@first_name + ' ' + @last_name)),
			email = @email,
			first_name = @first_name,
			last_name = @last_name,
			is_system_admin = @is_system_admin,
			is_developer = @is_developer,
			inactive = CASE WHEN @deactivate_global = 1 THEN 1 ELSE inactive END,
			date_modified = GETDATE(),
			who_modified = @login_session_uuid
		WHERE original = @resolved_user_uuid AND record_type = 'A';
	END
	
	-- Lokální přístup do tenanta
	SELECT @access_uuid = original 
	FROM user_organization_access 
	WHERE user_account_uuid = @resolved_user_uuid 
	  AND organization_uuid = @organization_uuid 
	  AND record_type = 'A';
	
	IF @access_uuid IS NULL
	BEGIN
		IF @remove_access = 0
		BEGIN
			SET @access_uuid = NEWID();
			
			INSERT INTO user_organization_access (
				uuid, object_owner, original, record_type, approval_status,
				user_account_uuid, organization_uuid, is_orgadmin, removed,
				who_created, who_modified
			) VALUES (
				@access_uuid, @organization_uuid, @access_uuid, 'A', 'A',
				@resolved_user_uuid, @organization_uuid, @is_orgadmin, 0,
				@login_session_uuid, @login_session_uuid
			);
		END
	END
	ELSE
	BEGIN
		UPDATE user_organization_access
		SET is_orgadmin = @is_orgadmin,
			removed = @remove_access,
			date_modified = GETDATE(),
			who_modified = @login_session_uuid
		WHERE original = @access_uuid AND record_type = 'A';
	END
	
	COMMIT;
END
GO