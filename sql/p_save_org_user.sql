EXECUTE dropni 'p_save_org_user', 'P'
GO

/* =============================================================================
 * Procedura: p_save_org_user
 * Účel: Bezpečné uložení, úprava nebo deaktivace uživatele v rámci tenanta.
 * 
 * Architektura a bezpečnost:
 * - Zajišťuje logický zápis do globální tabulky user_account (vlastněné 0x00)
 *   i vytvoření vazby na lokálního tenanta v tabulce user_organization_access.
 * - Podporuje odříznutí přístupu (remove_access) pro Orgadmina i globální umrtvení 
 *   účtu (deactivate_global) pro Sysadmina.
 * - Striktní hard-coded override: Pokud uživatel edituje vlastní záznam, 
 *   databáze vynutí ignorování příkazů k odebrání práv či zablokování, i kdyby 
 *   byl volající HTTP požadavek kompromitován.
 * ============================================================================= */
CREATE PROCEDURE p_save_org_user
	@organization_uuid uniqueidentifier,
	@user_original uniqueidentifier,
	@login_name varchar(100),
	@email varchar(200),
	@first_name varchar(100),
	@last_name varchar(100),
	@is_orgadmin bit,
	@remove_access bit = 0,
	@deactivate_global bit = 0,
	@who_modified uniqueidentifier
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	
	DECLARE @resolved_user_uuid uniqueidentifier = @user_original;
	DECLARE @access_uuid uniqueidentifier;
	
	-- Pokud jde o nového uživatele (bez zadaného ID), pokusíme se najít existující účet
	IF @resolved_user_uuid IS NULL OR @resolved_user_uuid = 0x00
	BEGIN
		SELECT @resolved_user_uuid = original 
		FROM user_account 
		WHERE login_name = @login_name AND record_type = 'A' AND removed = 0;
	END
	
	-- BEZPEČNOSTNÍ POJISTKA BACKENDU: Ochrana před ztrátou kontroly nad vlastním účtem
	IF @resolved_user_uuid = @who_modified
	BEGIN
		SET @remove_access = 0;
		SET @deactivate_global = 0;
		SET @is_orgadmin = 1;
	END
	
	BEGIN TRAN;
	
	-- Globální účet uživatele
	IF @resolved_user_uuid IS NULL
	BEGIN
		SET @resolved_user_uuid = NEWID();
		
		INSERT INTO user_account (
			uuid, object_owner, original, record_type, approval_status,
			caption, login_name, email, first_name, last_name, allow_local_login,
			inactive, who_created, who_modified
		) VALUES (
			@resolved_user_uuid, 0x00, @resolved_user_uuid, 'A', 'A',
			LTRIM(RTRIM(@first_name + ' ' + @last_name)), @login_name, @email, @first_name, @last_name, 1,
			@deactivate_global, @who_modified, @who_modified
		);
	END
	ELSE
	BEGIN
		UPDATE user_account
		SET caption = LTRIM(RTRIM(@first_name + ' ' + @last_name)),
			email = @email,
			first_name = @first_name,
			last_name = @last_name,
			inactive = CASE WHEN @deactivate_global = 1 THEN 1 ELSE inactive END,
			date_modified = GETDATE(),
			who_modified = @who_modified
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
				@who_modified, @who_modified
			);
		END
	END
	ELSE
	BEGIN
		UPDATE user_organization_access
		SET is_orgadmin = @is_orgadmin,
			removed = @remove_access,
			date_modified = GETDATE(),
			who_modified = @who_modified
		WHERE original = @access_uuid AND record_type = 'A';
	END
	
	COMMIT;
END
GO