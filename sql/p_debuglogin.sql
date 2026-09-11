EXECUTE dropni 'p_debuglogin', 'P'
GO
/* =============================================================================
 * SOUBOR: p_debuglogin.sql
 * Účel: Pomocná procedura pro ladění (vývoj/debug). Vytvoří relaci 'debug' 
 *	 pro zadaný login, aby bylo možné testovat Views a procedury 
 *	 přímo v SSMS (či jiném IDE) v kontextu aktuálního @@spid.
 *	 Pokud je volána bez parametru, odpojí a vyčistí aktuální @@spid.
 *
 * Vazby na okolí:
 * - Slouží POUZE pro vývoj a ladění, nebude volána z běžného PHP.
 * - Využívá existující procedury p_set_login a p_init_wwwsession, čímž 
 *	 garantuje naprosto shodné chování jako při reálném přihlášení (včetně 
 *	 vyhledání tenanta přes v_user_organization_access).
 * - Přímo manipuluje s tabulkami wwwsession a dbsession.
 * ============================================================================= */
CREATE PROCEDURE p_debuglogin
	@login varchar(100) = '',
	@language varchar(2) = 'cz'
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Pokud není předán login, provedeme úplné odhlášení (vyčištění) aktuálního SPID
	IF @login = '' OR @login IS NULL
	BEGIN
		DELETE FROM dbsession WHERE spid = @@SPID;
		DELETE FROM wwwsession WHERE wwwsession = 'debug' OR spid = @@SPID;
		
		PRINT 'Relace pro @@SPID = ' + CAST(@@SPID AS varchar(10)) + ' byla odpojena.';
		RETURN;
	END

	DECLARE @user_uuid uniqueidentifier;

	-- Dohledání originálního UUID uživatele podle loginu
	SELECT	@user_uuid = original
	FROM	user_account
	WHERE	login_name = @login AND record_type = 'A' AND removed = 0;

	IF @user_uuid IS NULL
	BEGIN
		RAISERROR('Uživatel s loginem "%s" nebyl nalezen nebo je neaktivní.', 16, 1, @login);
		RETURN;
	END

	-- 1. Založení relace 'debug' (aplikuje standardní byznys logiku)
	EXEC p_set_login 
		@user_uuid = @user_uuid, 
		@wwwsession = 'debug', 
		@client_ip = '127.0.0.1';

	-- 2. Propojení relace s aktuálním @@SPID a zkopírování do dbsession
	-- Parametr @no_result = 1 zamezí nechtěnému vypsání result-setu do konzole SSMS
	EXEC p_init_wwwsession 
		@wwwsession = 'debug', 
		@language = @language, 
		@working_date = NULL, 
		@no_result = 1;

	--PRINT 'Debug session byla úspěšně inicializována pro @@SPID = ' + CAST(@@SPID AS varchar(10));
END
GO
execute p_debuglogin 'honza.hink@gmail.com'
GO
