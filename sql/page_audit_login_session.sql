EXECUTE dropni 'page_audit_login_session', 'P';
GO

/* =============================================================================
 * Verze: 2026-11-16 15:40
 * Soubor: page_audit_login_session.sql
 * Procedura: dbo.page_audit_login_session
 *
 * 1. Role souboru v celém systému:
 *    Databázová podpora pro přehledovou stránku aktivity a přihlášení uživatelů
 *    (page_audit_login_session.php). Nejprve uzavře expirované relace voláním
 *    dbo.p_cleanup_expired_sessions a následně vrátí filtrovaný přehled relací
 *    z tabulky audit_login_session.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Volána z PHP třídy page_audit_login_session (page_audit_login_session.php).
 *    - Automaticky zařazena do buildu databáze maskou page_*.sql v BuildListDb.txt.
 *    - Volá proceduru dbo.p_cleanup_expired_sessions (p_init_wwwsession.sql).
 *    - Čte tabulky dbsession, wwwsession, audit_login_session, system_constant,
 *      user_account, organization a user_organization_access.
 *
 * 3. Očekávaná kontextová data:
 *    - Čte aktivní organizaci (organization) z tabulky dbsession pro @@SPID
 *      (mimo systémovou organizaci 0x00 omezuje výpis pouze na relace daného
 *      tenanta).
 * ============================================================================= */
CREATE PROCEDURE dbo.page_audit_login_session
	@limit int = 100,                                                          -- Maximální počet vrácených záznamů (1..10000)
	@user_filter varchar(200) = '',                                            -- Volitelný textový filtr (jméno, login, e-mail)
	@only_open bit = 0                                                         -- 1 = Pouze právě aktivní (neukončené) relace
AS
BEGIN
	SET NOCOUNT ON;

	-- 1. Uzavření expirovaných a osiřelých relací před čtením přehledu
	IF OBJECT_ID('dbo.p_cleanup_expired_sessions', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_cleanup_expired_sessions;
	END

	-- 2. Načtení kontextu aktivní organizace z dbsession
	DECLARE @current_org uniqueidentifier = 0x00;
	SELECT TOP 1 @current_org = ISNULL(organization, 0x00)
	FROM dbsession
	WHERE spid = @@SPID;

	IF @limit IS NULL OR @limit < 1 SET @limit = 100;
	IF @limit > 10000 SET @limit = 10000;

	SET @user_filter = LTRIM(RTRIM(ISNULL(@user_filter, '')));
	DECLARE @like_pattern varchar(210) = '%' + @user_filter + '%';

	-- 3. Při filtru @only_open = 1 načteme živé relace z wwwsession do indexované tabulkové proměnné
	DECLARE @open_sessions TABLE (
		login_session_uuid uniqueidentifier NOT NULL PRIMARY KEY
	);

	IF @only_open = 1
	BEGIN
		INSERT INTO @open_sessions (login_session_uuid)
		SELECT DISTINCT login_session_uuid
		FROM wwwsession
		WHERE login_session_uuid IS NOT NULL;
	END

	-- 4. Hlavní dotaz bez korelovaných poddotazů ve WHERE
	SELECT TOP (@limit)
		a.uuid,
		a.user_account_uuid,
		a.organization_uuid,
		a.assumed_role,
		a.login_time,
		a.last_request_time,
		a.logout_time,
		CASE
			WHEN a.logout_time IS NOT NULL AND DATEDIFF(second, a.last_request_time, a.logout_time) >= ISNULL(c.session_timeout, 20) * 60
				THEN 1
			ELSE 0
		END AS is_expired,
		a.ip_address,
		DATEDIFF(minute, a.login_time, COALESCE(a.logout_time, a.last_request_time)) AS duration_minutes,
		CASE
			WHEN a.user_account_uuid = 0x00 THEN 'admin'
			ELSE ISNULL(u.login_name, '')
		END AS login_name,
		CASE
			WHEN a.user_account_uuid = 0x00 THEN 'System Administrator'
			ELSE ISNULL(NULLIF(LTRIM(RTRIM(u.caption)), ''), LTRIM(RTRIM(ISNULL(u.first_name, '') + ' ' + ISNULL(u.last_name, ''))))
		END AS user_full_name,
		ISNULL(u.email, '') AS email,
		ISNULL(uoa.department_name, '') AS department_name,
		ISNULL(uoa.job_title, '') AS job_title,
		ISNULL(u.inactive, 0) AS user_inactive,
		CASE
			WHEN a.organization_uuid = 0x00 THEN 'System (0x00)'
			ELSE ISNULL(NULLIF(LTRIM(RTRIM(o.shortname)), ''), ISNULL(o.caption, ''))
		END AS org_display,
		ISNULL(o.caption, '') AS org_full_caption
	FROM audit_login_session a
	CROSS JOIN system_constant c
	LEFT JOIN @open_sessions os
		ON os.login_session_uuid = a.uuid
	LEFT JOIN user_account u
		ON u.original = a.user_account_uuid
		AND u.record_type = 'A'
	LEFT JOIN organization o
		ON o.original = a.organization_uuid
		AND o.record_type = 'A'
	LEFT JOIN user_organization_access uoa
		ON uoa.user_account_uuid = a.user_account_uuid
		AND uoa.organization_uuid = a.organization_uuid
		AND uoa.record_type = 'A'
	WHERE (@current_org = 0x00 OR a.organization_uuid = @current_org)
	  AND (@only_open = 0 OR (a.logout_time IS NULL AND os.login_session_uuid IS NOT NULL))
	  AND (
		@user_filter = ''
		OR ISNULL(u.login_name, CASE WHEN a.user_account_uuid = 0x00 THEN 'admin' ELSE '' END) LIKE @like_pattern
		OR ISNULL(u.caption, CASE WHEN a.user_account_uuid = 0x00 THEN 'System Administrator' ELSE '' END) LIKE @like_pattern
		OR ISNULL(u.first_name, '') LIKE @like_pattern
		OR ISNULL(u.last_name, '') LIKE @like_pattern
		OR (ISNULL(u.first_name, '') + ' ' + ISNULL(u.last_name, '')) LIKE @like_pattern
		OR (ISNULL(u.last_name, '') + ' ' + ISNULL(u.first_name, '')) LIKE @like_pattern
		OR ISNULL(u.email, '') LIKE @like_pattern
	  )
	ORDER BY a.login_time DESC, a.last_request_time DESC;
END
GO