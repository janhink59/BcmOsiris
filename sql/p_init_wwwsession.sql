EXECUTE dropni 'p_init_wwwsession', 'P'
GO

/* =============================================================================
 * Procedura: p_init_wwwsession
 * Účel: Zajišťuje přenos platné relace uživatele z wwwsession do dbsession
 *       pro aktuální @@SPID a provádí garbage collection starých relací.
 * Změny:
 * - Přidán dynamický přepočet oprávnění right_translate pro podporu nové
 *   architektury globálních a lokálních překladů na základě aktuálně 
 *   zvoleného jazyka relace a organizace (garanta překladu).
 * ============================================================================= */
CREATE PROCEDURE [dbo].[p_init_wwwsession]
	@wwwsession varchar(40),
	@language varchar(2)=null,
	@working_date date=null,
	@no_result bit=0
AS
BEGIN
	SET NOCOUNT ON;

	-- Garbage collection expirovaných relací
	DELETE FROM wwwsession
	FROM wwwsession u, system_constant c
	WHERE DATEADD(mi, c.session_timeout, u.request_date) < GETDATE();

	-- Aktualizace parametrů aktuální relace a napojení na aktuální proces (SPID)
	UPDATE wwwsession SET
		spid=@@spid,
		language=ISNULL(@language,language),
		working_date=ISNULL(@working_date,working_date),
		request_date=GETDATE()
	WHERE wwwsession=@wwwsession;

	-- [ ARCHITEKTURA PŘEKLADŮ ]
	-- Dynamický přepočet right_translate podle aktuálního jazyka
	-- Volá se při každém překreslení stránky (např. i po PRG redirectu při změně jazyka z UI)
	UPDATE w SET
		right_translate = CASE 
			WHEN w.right_sysadmin = 1 THEN 1                                          -- Sysadmin má právo překládat vždy
			WHEN a.right_translate = 1 AND l.translator_org = w.organization THEN 1   -- Oprávněný uživatel v garantující organizaci
			ELSE 0                                                                    -- Standardní tenant překládající jen pro sebe
		END
	FROM wwwsession w
	LEFT JOIN v_user_organization_access a ON a.user_account_uuid = w.user_account AND a.organization = w.organization
	LEFT JOIN [language] l ON l.[language] = w.language
	WHERE w.wwwsession = @wwwsession;

	-- Překlopení upravené relace do databázového kontextu aktuálního requestu
	DELETE FROM dbsession WHERE spid=@@spid;
	INSERT INTO dbsession SELECT * FROM wwwsession WHERE wwwsession=@wwwsession;

	-- Vrácení kontextu klientovi (PHP/PDO)
	IF @no_result=0 
	BEGIN
		SELECT * FROM dbsession WHERE spid=@@spid;
	END
END
GO