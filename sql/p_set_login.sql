IF OBJECT_ID('p_set_login') IS NOT NULL DROP PROCEDURE p_set_login;
GO
/* =============================================================================
 * Procedura: p_set_login
 * Účel: Založí záznam o přihlášení uživatele do tabulky wwwsession.
 *       Volá se z aplikační vrstvy po úspěšném ověření jména/hesla nebo SSO tokenu.
 * Logika multi-tenancy:
 *       1. Ověří, zda má uživatel stále přístup do organizace z posledního přihlášení.
 *       2. Pokud nemá, vybere první platnou organizaci, do které má přístup.
 *       3. Pokud nemá přístup nikam, proces selže (rollback).
 * ============================================================================= */
CREATE PROCEDURE p_set_login
	@user_uuid uuid,
	@wwwsession varchar(50),
	@client_ip varchar(200)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Proměnné pro kontext relace
	DECLARE @user_name varchar(80) = 'admin';
	DECLARE @display_name varchar(200) = 'System Administrator';
	DECLARE @organization uuid = 0x00;
	DECLARE @is_orgadmin bit = 0;
	
	-- Proměnné pro zjišťování dostupných organizací
	DECLARE @last_login_org uuid;
	DECLARE @target_org uuid = NULL;

	BEGIN TRAN;

	-- 1. Vyčištění případných starých relací (ukradené/recyklované session_id)
	DELETE FROM wwwsession WHERE wwwsession = @wwwsession;

	-- 2. Načtení dat a kontextu pro standardního uživatele
	IF @user_uuid <> 0x00 AND @user_uuid <> '00000000-0000-0000-0000-000000000000'
	BEGIN
		-- Načtení základních údajů uživatele a zjištění poslední navštívené organizace
		SELECT 
			@user_name = login_name,
			@display_name = LTRIM(RTRIM(ISNULL(first_name, '') + ' ' + ISNULL(last_name, ''))),
			@last_login_org = last_login_organization -- Tento sloupec musíme fyzicky přidat do user_account!
		FROM user_account
		WHERE original = @user_uuid AND record_type = 'A' AND removed = 0 AND inactive = 0;

		IF @display_name = '' SET @display_name = @user_name;

		-- Zjištění, zda má uživatel stále přístup k poslední organizaci
		IF @last_login_org IS NOT NULL
		BEGIN
			SELECT TOP 1 @target_org = organization_uuid, @is_orgadmin = is_orgadmin
			FROM user_organization_access
			WHERE user_account_uuid = @user_uuid 
			  AND organization_uuid = @last_login_org
			  AND record_type = 'A' AND removed = 0 AND inactive = 0;
		END

		-- Pokud do poslední organizace přístup nemá (nebo se přihlašuje poprvé), 
		-- vezmeme první platnou organizaci, kterou najdeme.
		IF @target_org IS NULL
		BEGIN
			SELECT TOP 1 @target_org = organization_uuid, @is_orgadmin = is_orgadmin
			FROM user_organization_access
			WHERE user_account_uuid = @user_uuid 
			  AND record_type = 'A' AND removed = 0 AND inactive = 0
			ORDER BY date_created DESC; -- Například nejnovější přidělený přístup
		END
		
		-- Kritické selhání: Uživatel nemá platný přístup do ŽÁDNÉ organizace
		IF @target_org IS NULL
		BEGIN
			ROLLBACK;
			RAISERROR ('Uživateli nebyl přidělen přístup do žádné organizace.', 16, 1);
			RETURN;
		END

		SET @organization = @target_org;

		-- Aktualizace uživatelského účtu: 
		-- Reset chybných pokusů, záznam času a uložení kontextu poslední organizace
		UPDATE user_account 
		SET failed_login_attempts = 0, 
			last_login_date = GETDATE(),
			last_login_organization = @organization
		WHERE original = @user_uuid AND record_type = 'A';
	END
	ELSE 
	BEGIN
		-- Speciální fallback pro System Admina (vždy se přihlašuje do SYS - 0x00)
		SET @organization = 0x00;
		SET @is_orgadmin = 1;
	END

	-- 3. Zápis do wwwsession s využitím zjištěných hodnot
	-- Do tabulky wwwsession propíšeme i flag z vazební tabulky (right_orgadmin)
	INSERT INTO wwwsession (
		spid, wwwsession, user_account, user_name, organization, display_name, 
		session_log, client_ip, login_date, right_orgadmin
	) VALUES (
		@@SPID, @wwwsession, @user_uuid, @user_name, @organization, @display_name, 
		0, @client_ip, GETDATE(), @is_orgadmin
	);

	COMMIT;
END
GO