EXECUTE dropni 'p_set_login', 'P'
GO

/* =============================================================================
 * Procedura: p_set_login
 * Účel: Založení uživatelské relace a inicializace kontextu (tenant, práva).
 *
 * Vazby:
 * - Voláno primárně při úspěšné autentizaci (např. z page_login nebo page_google_callback), 
 *   nebo pro explicitní změnu kontextu z UI (page_change_user_context).
 * - Čte dostupná oprávnění z pohledu v_user_organization_access.
 * - Zapisuje aktivní relaci do tabulky wwwsession (a následně přes p_init_wwwsession do dbsession).
 * - Aktualizuje last_login_date a last_login_organization v tabulce user_account.
 * - Umožňuje přes parametr @requested_admin explicitně přepínat efektivní roli Admin/User.
 * ============================================================================= */
CREATE PROCEDURE p_set_login
	@user_uuid uniqueidentifier,
	@wwwsession varchar(50),
	@client_ip varchar(200),
	@requested_org uniqueidentifier = NULL,
	@requested_admin bit = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @user_name varchar(80) = 'admin';
	DECLARE @display_name varchar(200) = 'System Administrator';
	DECLARE @is_sysadmin bit = 1;
	
	DECLARE @organization uniqueidentifier = NULL;
	DECLARE @organization_name nvarchar(200) = '';
	DECLARE @is_orgadmin bit = 0;
	DECLARE @last_orgadmin bit = 0;
	DECLARE @change_context_allowed bit = 0;
	DECLARE @user_access_uuid uniqueidentifier = NULL;

	BEGIN TRAN;

	DELETE FROM wwwsession WHERE wwwsession = @wwwsession;

	IF @user_uuid <> 0x00 AND @user_uuid <> '00000000-0000-0000-0000-000000000000'
	BEGIN
		SELECT	@user_name = login_name,
			@display_name = LTRIM(RTRIM(ISNULL(first_name, '') + ' ' + ISNULL(last_name, ''))),
			@is_sysadmin = is_system_admin
		FROM	user_account
		WHERE	original = @user_uuid AND record_type = 'A' AND removed = 0 AND inactive = 0;

		IF @display_name = '' SET @display_name = @user_name;

		SELECT TOP 1 
			@organization = v.organization,
			@organization_name = v.organization_name,
			@is_orgadmin = v.is_orgadmin,
			@last_orgadmin = v.last_orgadmin,
			@user_access_uuid = v.user_access_uuid
		FROM	v_user_organization_access v
		WHERE	v.user_account_uuid = @user_uuid
		ORDER BY 
			CASE 
				WHEN v.organization = @requested_org THEN 0
				WHEN v.organization = v.last_login_org THEN 1
				ELSE 2 
			END,
			v.date_created DESC;
		
		IF @organization IS NULL
		BEGIN
			ROLLBACK;
			RAISERROR ('Uživateli nebyl přidělen přístup do žádné organizace.', 16, 1);
			RETURN;
		END
		
		-- Zpracování explicitní žádosti o změnu role (Admin / User z UI)
		IF @requested_admin IS NOT NULL AND @is_orgadmin = 1
		BEGIN
			UPDATE	user_organization_access
			SET	last_orgadmin = @requested_admin
			WHERE	original = @user_access_uuid AND record_type = 'A';
			
			SET @last_orgadmin = @requested_admin;
		END

		-- Vyhodnocení, zda má uživatel na výběr z více možností kontextu
		-- OPRAVA: Kontext lze měnit, pokud je uživatel členem více organizací, 
		-- NEBO pokud má alespoň v jedné roli administrátora.
		IF (SELECT COUNT(1) FROM v_user_organization_access WHERE user_account_uuid = @user_uuid) > 1
			OR EXISTS (SELECT 1 FROM v_user_organization_access WHERE user_account_uuid = @user_uuid AND is_orgadmin = 1)
		BEGIN
			SET @change_context_allowed = 1;
		END

		UPDATE	user_account 
		SET	failed_login_attempts = 0, 
			last_login_date = GETDATE(),
			last_login_organization = @organization
		WHERE	original = @user_uuid AND record_type = 'A';
	END
	ELSE 
	BEGIN
		-- Master fallback pro systémový účet (0x00)
		SET @organization = 0x00;
		SET @organization_name = 'Systémová organizace';
		SET @is_orgadmin = 1;
		SET @last_orgadmin = 1;
		SET @is_sysadmin = 1;
		SET @change_context_allowed = 1;
		SET @user_access_uuid = 0x00;
	END

	-- Výpočet efektivních práv pro relaci: administrátorem je, jen pokud má k tomu 
	-- statická práva (is_orgadmin) A ZÁROVEŇ má tuto roli aktivně zvolenou (last_orgadmin)
	DECLARE @effective_orgadmin bit = 0;
	IF @is_orgadmin = 1 AND @last_orgadmin = 1
	BEGIN
		SET @effective_orgadmin = 1;
	END

	-- Zápis do session se skutečně uplatňovanými právy
	INSERT INTO wwwsession (
		spid, wwwsession, user_account, user_access_uuid, user_name, organization, organization_name, display_name, 
		session_log, client_ip, login_date, right_orgadmin, right_sysadmin, change_context_allowed
	) VALUES (
		@@SPID, @wwwsession, @user_uuid, @user_access_uuid, @user_name, @organization, @organization_name, @display_name, 
		0, @client_ip, GETDATE(), @effective_orgadmin, @is_sysadmin, @change_context_allowed
	);

	COMMIT;
END
GO