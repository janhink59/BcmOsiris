IF OBJECT_ID('p_set_login') IS NOT NULL DROP PROCEDURE p_set_login;
GO
/* =============================================================================
 * Procedura: p_set_login
 * Účel: Založí záznam o přihlášení uživatele do tabulky wwwsession.
 *       Volá se z aplikační vrstvy (PHP) po úspěšném ověření bcrypt hashe.
 *       U běžných uživatelů si procedura sama dotáhne organizační kontext
 *       a vizualizační jméno z tabulky user_account.
 * ============================================================================= */
CREATE PROCEDURE p_set_login
	@user_uuid uuid,
	@wwwsession varchar(50),
	@client_ip varchar(200)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Výchozí hodnoty pro systémového administrátora (break-glass účet)
	DECLARE @user_name varchar(80) = 'admin';
	DECLARE @organization uuid = 0x00;
	DECLARE @display_name varchar(200) = 'System Administrator';

	BEGIN TRAN;

	-- 1. Vyčištění případných starých relací pro dané (ukradené/recyklované) session_id
	DELETE FROM wwwsession WHERE wwwsession = @wwwsession;

	-- 2. Načtení kontextu pro standardního uživatele
	IF @user_uuid <> 0x00 AND @user_uuid <> '00000000-0000-0000-0000-000000000000'
	BEGIN
		-- Získání dat z aktivního (A) záznamu
		SELECT 
			@user_name = login_name,
			@organization = object_owner,
			@display_name = LTRIM(RTRIM(ISNULL(first_name, '') + ' ' + ISNULL(last_name, '')))
		FROM user_account
		WHERE original = @user_uuid AND record_type = 'A';

		-- Fallback, pokud uživatel nemá vyplněné jméno a příjmení
		IF @display_name = '' SET @display_name = @user_name;

		-- Aktualizace uživatelského účtu: reset chybných pokusů a záznam času přihlášení
		UPDATE user_account 
		SET failed_login_attempts = 0, 
			last_login_date = GETDATE() 
		WHERE original = @user_uuid AND record_type = 'A';
	END

	-- 3. Zápis do wwwsession s využitím zjištěných hodnot
	INSERT INTO wwwsession (
		spid, wwwsession, user_account, user_name, organization, display_name, session_log, client_ip, login_date
	) VALUES (
		@@SPID, @wwwsession, @user_uuid, @user_name, @organization, @display_name, 0, @client_ip, GETDATE()
	);

	COMMIT;
END
GO