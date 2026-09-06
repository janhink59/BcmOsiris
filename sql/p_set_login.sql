EXECUTE dropni 'p_set_login', 'P'
GO

/* =============================================================================
 * Procedura: p_set_login
 * Účel: Založí záznam o relaci do tabulky wwwsession po úspěšné autentizaci.
 * 
 * Logika Multi-tenancy:
 * - Uživatel se přednostně přihlašuje do organizace (tenanta), kterou navštívil
 *   naposledy (sloupec last_login_organization v tabulce user_account).
 * - Pokud do ní už ztratil přístup, vybere se první dostupná organizace.
 * - Bez oprávnění do jakékoliv organizace je přihlášení striktně zamítnuto 
 *   (neplatí pro systémový účet 0x01).
 * - Automaticky dohledává a vkládá název organizace pro potřeby uživatelského UI.
 * ============================================================================= */
CREATE PROCEDURE p_set_login
	@user_uuid uniqueidentifier,
	@wwwsession varchar(50),
	@client_ip varchar(200)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Proměnné pro kontext relace (s výchozími fallbacky)
	DECLARE @user_name varchar(80) = 'admin';
	DECLARE @display_name varchar(200) = 'System Administrator';
	DECLARE @organization uniqueidentifier = 0x00;
	DECLARE @organization_name nvarchar(200) = 'Systémová organizace';
	DECLARE @is_orgadmin bit = 0;
	DECLARE @is_sysadmin bit = 1;

	DECLARE @last_login_org uniqueidentifier;
	DECLARE @target_org uniqueidentifier = NULL;

	BEGIN TRAN;

	-- Vyčištění případných expirovaných/recyklovaných relací
	DELETE FROM wwwsession WHERE wwwsession = @wwwsession;

	IF @user_uuid <> 0x00 AND @user_uuid <> '00000000-0000-0000-0000-000000000000'
	BEGIN
		-- Načtení základních údajů uživatele a zjištění preferovaného tenanta
		SELECT 
			@user_name = login_name,
			@display_name = LTRIM(RTRIM(ISNULL(first_name, '') + ' ' + ISNULL(last_name, ''))),
			@last_login_org = last_login_organization,
			@is_sysadmin = is_system_admin
		FROM user_account
		WHERE original = @user_uuid AND record_type = 'A' AND removed = 0 AND inactive = 0;

		IF @display_name = '' SET @display_name = @user_name;

		-- Ověření, zda má uživatel stále přístup k preferovanému tenantovi
		IF @last_login_org IS NOT NULL
		BEGIN
			SELECT TOP 1 @target_org = organization_uuid, @is_orgadmin = is_orgadmin
			FROM user_organization_access
			WHERE user_account_uuid = @user_uuid 
			  AND organization_uuid = @last_login_org
			  AND record_type = 'A' AND removed = 0 AND inactive = 0;
		END

		-- Fallback: Výběr libovolného dostupného tenanta
		IF @target_org IS NULL
		BEGIN
			SELECT TOP 1 @target_org = organization_uuid, @is_orgadmin = is_orgadmin
			FROM user_organization_access
			WHERE user_account_uuid = @user_uuid 
			  AND record_type = 'A' AND removed = 0 AND inactive = 0
			ORDER BY date_created DESC;
		END
		
		-- Ochrana: Uživateli bez jakéhokoliv přístupu se odepře založení relace
		IF @target_org IS NULL
		BEGIN
			ROLLBACK;
			RAISERROR ('Uživateli nebyl přidělen přístup do žádné organizace.', 16, 1);
			RETURN;
		END

		SET @organization = @target_org;
		
		-- Načtení vizuálního názvu tenanta pro UI
		SELECT @organization_name = caption 
		FROM organization 
		WHERE original = @organization AND record_type = 'A' AND removed = 0;

		-- Aktualizace statistik a metadat posledního úspěšného přihlášení
		UPDATE user_account 
		SET failed_login_attempts = 0, 
			last_login_date = GETDATE(),
			last_login_organization = @organization
		WHERE original = @user_uuid AND record_type = 'A';
	END
	ELSE 
	BEGIN
		-- Speciální zpracování pro systémového break-glass admina (0x01)
		SET @organization = 0x00;
		SET @organization_name = 'Systémová organizace';
		SET @is_orgadmin = 1;
		SET @is_sysadmin = 1;
	END

	-- Fyzický zápis do tabulky relací
	INSERT INTO wwwsession (
		spid, wwwsession, user_account, user_name, organization, organization_name, display_name, 
		session_log, client_ip, login_date, right_orgadmin, right_sysadmin
	) VALUES (
		@@SPID, @wwwsession, @user_uuid, @user_name, @organization, @organization_name, @display_name, 
		0, @client_ip, GETDATE(), @is_orgadmin, @is_sysadmin
	);

	COMMIT;
END
GO