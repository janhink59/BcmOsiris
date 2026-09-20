EXECUTE dropni 'v_user_organization_access', 'V'
GO

/* =============================================================================
 * SOUBOR: v_user_organization_access.sql
 * Účel: Rozšířený pohled nad vazební tabulkou user_organization_access pro
 *       vyhodnocení oprávnění uživatele. Nyní vrací i user_access_uuid pro naplnění 
 *       kontextu operací a last_orgadmin pro uchování paměti zvolené role.
 *
 * Vazby na okolí:
 * - Primárně voláno procedurou p_set_login pro rozhodnutí o cílové organizaci
 *   při přihlašování.
 * - Bude sloužit UI komponentám (user_context) pro naplnění rozevíracího 
 *   seznamu tenantů.
 * - LEFT JOIN na tabulku dbsession zajišťuje, že pohled funguje i ve chvíli, 
 *   kdy záznam relace (@@SPID) ještě neexistuje (prvotní login).
 * ============================================================================= */
CREATE VIEW v_user_organization_access AS
SELECT	a.original AS user_access_uuid,
	a.user_account_uuid,
	a.organization_uuid AS organization,
	o.caption AS organization_name,
	a.is_orgadmin,
	a.last_orgadmin,
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