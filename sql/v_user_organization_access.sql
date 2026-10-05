EXECUTE dropni 'v_user_organization_access', 'V'
GO

/* =============================================================================
 * SOUBOR: v_user_organization_access.sql
 * Účel: Rozšířený pohled nad vazební tabulkou user_organization_access pro
 *       vyhodnocení oprávnění uživatele. 
 * Změny: Nahrazen zrušený sloupec last_orgadmin novým sloupcem last_role.
 *        Přejmenován alias na access_uuid pro zamezení zmatků se session.
 * ============================================================================= */
CREATE VIEW v_user_organization_access AS
SELECT	a.original AS access_uuid,
	a.user_account_uuid,
	a.organization_uuid AS organization,
	o.caption AS organization_name,
	a.is_orgadmin,
	a.last_role,
	a.right_translate,
	u.last_login_organization AS last_login_org,
	s.organization AS current_organization,
	a.date_created
FROM	user_organization_access a
	JOIN organization o ON o.original = a.organization_uuid AND o.record_type = 'A' AND o.removed = 0
	JOIN user_account u ON u.original = a.user_account_uuid AND u.record_type = 'A' AND u.removed = 0
	LEFT JOIN dbsession s ON s.spid = @@SPID AND s.user_account = a.user_account_uuid
WHERE	a.record_type = 'A' 
	AND a.removed = 0 
	AND a.inactive = 0
GO