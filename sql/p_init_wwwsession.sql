EXECUTE dropni 'p_init_wwwsession', 'P'
GO

/* =============================================================================
 * Procedura: p_init_wwwsession
 * Účel: Zajišťuje přenos platné relace uživatele z wwwsession do dbsession
 *       pro aktuální @@SPID a provádí garbage collection starých relací.
 * Změny:
 * - Nahrazení right_sysadmin/right_orgadmin za active_role.
 * - Aktualizuje last_request_time ve forenzním logu audit_login_session.
 * - Vyznačí logout_time u expirovaných relací před jejich odstraněním.
 * ============================================================================= */
CREATE PROCEDURE [dbo].[p_init_wwwsession]
	@wwwsession varchar(50),
	@language varchar(2) = null,
	@working_date date = null,
	@no_result bit = 0
AS
BEGIN
	SET NOCOUNT ON;

	-- 1. Zaznamenání expirace (timeoutu) do logu před fyzickým odstraněním relace
	UPDATE a
	SET logout_time = DATEADD(mi, c.session_timeout, u.request_date) -- Uložení přesného času vypršení
	FROM audit_login_session a
	JOIN wwwsession u ON u.login_session_uuid = a.uuid
	CROSS JOIN system_constant c
	WHERE DATEADD(mi, c.session_timeout, u.request_date) < GETDATE() AND a.logout_time IS NULL;

	-- 2. Garbage collection expirovaných relací
	DELETE FROM wwwsession
	FROM wwwsession u, system_constant c
	WHERE DATEADD(mi, c.session_timeout, u.request_date) < GETDATE();

	-- 3. Aktualizace parametrů aktuální relace a napojení na proces (SPID)
	UPDATE wwwsession SET
		spid = @@SPID,
		language = ISNULL(@language, language),
		working_date = ISNULL(@working_date, working_date),
		request_date = GETDATE()
	WHERE wwwsession = @wwwsession;

	-- 4. Aktualizace aktivity v auditním logu pro dané sezení
	UPDATE a
	SET last_request_time = GETDATE()
	FROM audit_login_session a
	JOIN wwwsession w ON w.login_session_uuid = a.uuid
	WHERE w.wwwsession = @wwwsession;

	-- 5. [ ARCHITEKTURA PŘEKLADŮ ]
	-- Dynamický přepočet right_translate podle aktuálního jazyka
	UPDATE w SET
		right_translate = CASE 
			WHEN w.active_role IN ('S', 'D') THEN 1                                   -- Sysadmin a Developer překládají vždy
			WHEN a.right_translate = 1 AND l.translator_org = w.organization THEN 1   -- Oprávněný uživatel v garantující organizaci
			ELSE 0                                                                    -- Standardní tenant překládající jen pro sebe
		END
	FROM wwwsession w
	LEFT JOIN v_user_organization_access a ON a.user_account_uuid = w.user_account AND a.organization = w.organization
	LEFT JOIN [language] l ON l.[language] = w.language
	WHERE w.wwwsession = @wwwsession;

	-- 6. Překlopení upravené relace do databázového kontextu aktuálního requestu
	DELETE FROM dbsession WHERE spid = @@SPID;
	INSERT INTO dbsession SELECT * FROM wwwsession WHERE wwwsession = @wwwsession;

	-- 7. Vrácení kontextu klientovi (PHP/PDO)
	IF @no_result = 0 
	BEGIN
		SELECT * FROM dbsession WHERE spid = @@SPID;
	END
END
GO