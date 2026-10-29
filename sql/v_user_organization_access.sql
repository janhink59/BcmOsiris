EXECUTE dropni 'v_user_organization_access', 'V'
GO

/* =============================================================================
 * Verze: 2026-10-29 15:30
 * SOUBOR: v_user_organization_access.sql
 * Účel: Rozšířený pohled nad vazební tabulkou user_organization_access pro
 *       vyhodnocení oprávnění uživatele, úrovně licence organizace (licence_level)
 *       a organizačně závislých údajů uživatele.
 * Vazby: Čte tabulky user_organization_access, organization, organization_licence,
 *        user_account a dbsession. Využíván v p_set_login, p_init_wwwsession
 *        a page_change_user_context.
 * Změny:
 * - 2026-10-29 15:30: Přidáno napojení na organization_licence pro získání
 *   licence_level a kontrolu login_disabled = 0. Doplněny sloupce department_name,
 *   job_title, manager_uuid, note, working_date a evaluation_method.
 * ============================================================================= */
CREATE VIEW v_user_organization_access AS
SELECT	a.original AS access_uuid,
	a.user_account_uuid,
	a.organization_uuid AS organization,
	o.caption AS organization_name,
	a.is_orgadmin,
	a.last_role,
	a.right_translate,
	a.department_name,
	a.job_title,
	a.manager_uuid,
	a.note,
	a.working_date,
	a.evaluation_method,
	CASE WHEN a.organization_uuid = 0x00 THEN CAST(255 AS tinyint) ELSE ISNULL(lic.licence_level, 0) END AS licence_level,
	u.last_login_organization AS last_login_org,
	s.organization AS current_organization,
	a.date_created
FROM	user_organization_access a
	JOIN organization o
		ON o.original = a.organization_uuid
		AND o.record_type = 'A'
		AND o.removed = 0
		AND o.inactive = 0
	JOIN user_account u
		ON u.original = a.user_account_uuid
		AND u.record_type = 'A'
		AND u.removed = 0
	OUTER APPLY (
		SELECT TOP 1 ol.licence_level, ol.login_disabled
		FROM organization_licence ol
		WHERE ol.organization_uuid = a.organization_uuid
		  AND ol.record_type = 'A'
		  AND ol.removed = 0
		  AND ol.inactive = 0
		  AND ol.licence_state = 'PROCESSED'
		ORDER BY ol.date_modified DESC
	) lic
	LEFT JOIN dbsession s
		ON s.spid = @@SPID
		AND s.user_account = a.user_account_uuid
WHERE	a.record_type = 'A'
	AND a.removed = 0
	AND a.inactive = 0
	AND (a.organization_uuid = 0x00 OR ISNULL(lic.login_disabled, 0) = 0);
GO