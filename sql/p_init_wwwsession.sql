EXECUTE dropni 'p_init_wwwsession', 'P';
EXECUTE dropni 'p_cleanup_expired_sessions', 'P';
GO

/* =============================================================================
 * Verze: 2026-11-16 15:10
 * Soubor: p_init_wwwsession.sql
 * Procedury: dbo.p_cleanup_expired_sessions, dbo.p_init_wwwsession
 *
 * 1. Role souboru v celém systému:
 *    - dbo.p_cleanup_expired_sessions uzavírá expirované a osiřelé relace ve
 *      forenzním logu audit_login_session (nastavením logout_time) a odstraňuje
 *      expirované záznamy z tabulky wwwsession podle session_timeout.
 *    - dbo.p_init_wwwsession zajišťuje na začátku každého HTTP požadavku přenos
 *      platné relace uživatele z wwwsession do dbsession pro aktuální @@SPID
 *      a dynamicky přepočítává oprávnění right_translate.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Voláno z PHP funkce initsession() v OsirisLib.php, z p_debuglogin.sql
 *      a ze stránky page_audit_login_session.php.
 *    - Čte tabulky system_constant, language a pohled v_user_organization_access.
 *    - Aktualizuje tabulky audit_login_session, wwwsession a dbsession.
 *
 * 3. Očekávaná kontextová data:
 *    - Přijímá identifikátor relace prohlížeče @wwwsession ($SID z PHP) a
 *      váže kontext databázového spojení v tabulce dbsession na aktuální @@SPID.
 *
 * Změny:
 * - 2026-11-16 15:10: Vyčleněna samostatná procedura dbo.p_cleanup_expired_sessions
 *   sdílená mezi p_init_wwwsession a page_audit_login_session.php.
 * - 2026-11-09 13:00: Doplněno dodatečné uzavření všech neukončených záznamů
 *   v audit_login_session, kterým vypršel čas expirace (session_timeout)
 *   nebo které již nemají aktivní záznam v tabulce wwwsession.
 * - Nahrazení right_sysadmin/right_orgadmin za active_role.
 * - Aktualizuje last_request_time ve forenzním logu audit_login_session.
 * - Vyznačí logout_time u expirovaných relací před jejich odstraněním.
 * ============================================================================= */
CREATE PROCEDURE [dbo].[p_cleanup_expired_sessions]
AS
BEGIN
	SET NOCOUNT ON;

	-- 1. Zaznamenání expirace (timeoutu) do logu před fyzickým odstraněním relace z wwwsession
	UPDATE a
	SET a.logout_time = DATEADD(mi, c.session_timeout, u.request_date)
	FROM audit_login_session a
	JOIN wwwsession u ON u.login_session_uuid = a.uuid
	CROSS JOIN system_constant c
	WHERE a.logout_time IS NULL
	  AND DATEADD(mi, c.session_timeout, u.request_date) < GETDATE();

	-- 2. Garbage collection expirovaných relací z wwwsession
	DELETE u
	FROM wwwsession u
	CROSS JOIN system_constant c
	WHERE DATEADD(mi, c.session_timeout, u.request_date) < GETDATE();

	-- 3. Dodatečné ukončení osiřelých a expirovaných relací přímo v audit_login_session
	UPDATE a
	SET a.logout_time = CASE
		WHEN DATEADD(mi, c.session_timeout, a.last_request_time) < GETDATE()
			THEN DATEADD(mi, c.session_timeout, a.last_request_time)
		ELSE a.last_request_time
	END
	FROM audit_login_session a
	CROSS JOIN system_constant c
	LEFT JOIN wwwsession w ON w.login_session_uuid = a.uuid
	WHERE a.logout_time IS NULL
	  AND (
		w.wwwsession IS NULL
		OR DATEADD(mi, c.session_timeout, a.last_request_time) < GETDATE()
	  );
END
GO

CREATE PROCEDURE [dbo].[p_init_wwwsession]
	@wwwsession varchar(50),
	@language varchar(2) = null,
	@working_date date = null,
	@no_result bit = 0
AS
BEGIN
	SET NOCOUNT ON;

	-- 1. Úklid expirovaných a osiřelých relací v audit_login_session a wwwsession
	EXEC dbo.p_cleanup_expired_sessions;

	-- 2. Aktualizace parametrů aktuální relace a napojení na proces (SPID)
	UPDATE wwwsession SET
		spid = @@SPID,
		language = ISNULL(@language, language),
		working_date = ISNULL(@working_date, working_date),
		request_date = GETDATE()
	WHERE wwwsession = @wwwsession;

	-- 3. Aktualizace aktivity v auditním logu pro dané sezení
	UPDATE a
	SET last_request_time = GETDATE()
	FROM audit_login_session a
	JOIN wwwsession w ON w.login_session_uuid = a.uuid
	WHERE w.wwwsession = @wwwsession;

	-- 4. [ ARCHITEKTURA PŘEKLADŮ ]
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

	-- 5. Překlopení upravené relace do databázového kontextu aktuálního requestu
	DELETE FROM dbsession WHERE spid = @@SPID;
	INSERT INTO dbsession SELECT * FROM wwwsession WHERE wwwsession = @wwwsession;

	-- 6. Vrácení kontextu klientovi (PHP/SQLSRV)
	IF @no_result = 0 
	BEGIN
		SELECT * FROM dbsession WHERE spid = @@SPID;
	END
END
GO