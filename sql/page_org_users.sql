IF OBJECT_ID('page_org_users') IS NOT NULL
	DROP PROCEDURE page_org_users;
GO

/* =============================================================================
 * Verze: 2026-11-16 14:40
 * Soubor: page_org_users.sql
 * Procedura: dbo.page_org_users
 *
 * 1. Role souboru v celém systému:
 *    Načítá seznam uživatelů tenanta (včetně žádostí o přístup a pozvánek 'D')
 *    a oddělené detaily osobního účtu (user_account) a oprávnění + zařazení
 *    v organizaci (user_organization_access) pro Master-Detail obrazovku
 *    page_org_users.php.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Volána z PHP modulu page_org_users.php (metody render_master a render_detail).
 *    - Čte tabulky dbsession, user_organization_access a user_account.
 *    - Využívá funkci dbo.f_get_user_info (f_get_user_info.sql) pro auditní stopu.
 *
 * 3. Očekávaná kontextová data:
 *    - Čerpá aktivní organizaci (organization) a účet uživatele (user_account)
 *      z tabulky dbsession pro aktuální @@SPID.
 *
 * Změny:
 * - 2026-11-16 14:40: Odstraněno CTE (;WITH ranked_access) ve větvi 'list' a
 *   nahrazeno indexovanou tabulkovou proměnnou @ranked_access s PRIMARY KEY
 *   (user_account_uuid) a inline indexem ix_ranked_sort.
 * - 2026-10-29 16:00: Sloupce department_name, job_title, manager_uuid, note,
 *   working_date a evaluation_method se v detailu načítají z tabulky
 *   user_organization_access (ou) místo z user_account (u).
 * ============================================================================= */
CREATE PROCEDURE dbo.page_org_users
	@subpage VARCHAR(50),
	@show_removed BIT = 0,
	@update_guid UNIQUEIDENTIFIER = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @current_org UNIQUEIDENTIFIER;
	DECLARE @current_user_uuid UNIQUEIDENTIFIER;

	-- 1. Načtení kontextu z aktuální databázové relace
	SELECT 
		@current_org = organization,
		@current_user_uuid = user_account
	FROM dbo.dbsession 
	WHERE spid = @@SPID;

	IF @current_org IS NULL
	BEGIN
		RAISERROR('Přístup odepřen: Nelze identifikovat aktivní relaci (dbsession).', 16, 1);
		RETURN;
	END

	-- 2. Zpracování pro levý panel (Master - Seznam uživatelů, žádostí a pozvánek)
	IF @subpage = 'list'
	BEGIN
		DECLARE @ranked_access TABLE (
			user_account_uuid UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
			record_type VARCHAR(1) NOT NULL,
			approval_status VARCHAR(1) NOT NULL,
			draft_author UNIQUEIDENTIFIER NOT NULL,
			approval_note VARCHAR(MAX) NOT NULL,
			is_orgadmin BIT NOT NULL,
			right_translate BIT NOT NULL,
			department_name VARCHAR(150) NOT NULL,
			job_title VARCHAR(150) NOT NULL,
			removed BIT NOT NULL,
			date_modified DATETIME NOT NULL,
			INDEX ix_ranked_sort (removed ASC, record_type ASC, date_modified DESC)
		);

		INSERT INTO @ranked_access (
			user_account_uuid, record_type, approval_status, draft_author, approval_note,
			is_orgadmin, right_translate, department_name, job_title, removed, date_modified
		)
		SELECT
			x.user_account_uuid, x.record_type, x.approval_status, x.draft_author, x.approval_note,
			x.is_orgadmin, x.right_translate, x.department_name, x.job_title, x.removed, x.date_modified
		FROM (
			SELECT
				ou.user_account_uuid,
				ou.record_type,
				ou.approval_status,
				ou.draft_author,
				ou.approval_note,
				ou.is_orgadmin,
				ou.right_translate,
				ou.department_name,
				ou.job_title,
				ou.removed,
				ou.date_modified,
				ROW_NUMBER() OVER (
					PARTITION BY ou.user_account_uuid
					ORDER BY ou.removed ASC, CASE WHEN ou.record_type = 'A' THEN 0 ELSE 1 END ASC, ou.date_modified DESC
				) AS rn
			FROM dbo.user_organization_access ou
			WHERE ou.organization_uuid = @current_org
			  AND ou.record_type IN ('A', 'D')
			  AND (
				(ou.record_type = 'A' AND (ou.removed = 0 OR @show_removed = 1))
				OR (ou.record_type = 'D' AND ou.removed = 0)
			  )
		) x
		WHERE x.rn = 1;

		SELECT 
			u.original AS user_uuid,
			u.login_name,
			u.first_name,
			u.last_name,
			u.email,
			u.inactive,
			ou.record_type,
			ou.approval_status,
			ou.draft_author,
			ou.approval_note,
			ou.is_orgadmin,
			ou.right_translate,
			ou.department_name,
			ou.job_title,
			ou.removed AS access_removed,
			CASE WHEN ou.record_type = 'D' AND ou.draft_author = u.original THEN 1 ELSE 0 END AS is_user_request
		FROM @ranked_access ou
		INNER JOIN dbo.user_account u ON u.original = ou.user_account_uuid
		WHERE u.record_type = 'A'
		  AND u.removed = 0
		ORDER BY
			CASE WHEN ou.record_type = 'D' AND ou.approval_status = 'F' THEN 0 ELSE 1 END ASC,
			ou.removed ASC,
			u.last_name ASC,
			u.first_name ASC;
	END

	-- 3. Zpracování pro pravý panel (Detail pro editaci formuláře)
	ELSE IF @subpage = 'detail'
	BEGIN
		SELECT TOP 1
			-- Osobní a kontaktní údaje globálního účtu (user_account)
			u.original AS user_uuid,
			u.login_name,
			u.user_title_before,
			u.first_name,
			u.last_name,
			u.user_title_after,
			u.email,
			u.phone,
			u.mobile,
			-- Globální systémové příznaky účtu (user_account)
			u.is_system_admin,
			u.is_developer,
			u.allow_local_login,
			u.inactive AS deactivate_global,
			-- Oprávnění, organizační zařazení a pracovní parametry v aktuální organizaci (user_organization_access)
			ou.record_type,
			ou.approval_status,
			ou.draft_author,
			ou.approval_note,
			ou.is_orgadmin,
			ou.right_translate,
			ou.department_name,
			ou.job_title,
			ou.manager_uuid,
			ou.note,
			ou.working_date,
			ou.evaluation_method,
			ou.removed AS remove_access,
			CASE WHEN ou.record_type = 'D' AND ou.draft_author = u.original THEN 1 ELSE 0 END AS is_user_request,
			-- Auditní stopa
			u.date_created,
			dbo.f_get_user_info(u.who_created) AS who_created_info,
			CASE WHEN ou.date_modified > u.date_modified THEN ou.date_modified ELSE u.date_modified END AS date_modified,
			dbo.f_get_user_info(CASE WHEN ou.date_modified > u.date_modified THEN ou.who_modified ELSE u.who_modified END) AS who_modified_info
		FROM dbo.user_account u
		INNER JOIN dbo.user_organization_access ou ON u.original = ou.user_account_uuid
		WHERE u.original = @update_guid 
		  AND ou.organization_uuid = @current_org
		  AND u.record_type = 'A'
		  AND u.removed = 0
		  AND ou.record_type IN ('A', 'D')
		ORDER BY ou.removed ASC, CASE WHEN ou.record_type = 'A' THEN 0 ELSE 1 END ASC, ou.date_modified DESC;
	END
END
GO