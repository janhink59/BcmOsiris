EXECUTE dropni 'page_change_user_context', 'P'
GO

/* =============================================================================
 * SOUBOR: page_change_user_context.sql
 * Účel: Datová procedura pro stránku změny kontextu uživatele.
 * Změny: Přidána podpora pro čtení globálních systémových rolí (S, D) 
 *        a filtrace systémové organizace z běžného výpisu.
 * ============================================================================= */

CREATE PROCEDURE page_change_user_context
	@subpage varchar(30)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @user_account uniqueidentifier;
	
	-- Získání aktuálně přihlášeného uživatele (originálu) z relace
	SELECT	@user_account = user_account 
	FROM	dbsession 
	WHERE	spid = @@SPID;

	IF @subpage = 'main'
	BEGIN
		-- Načtení pouze klientských organizací, do kterých má tento uživatel přístup.
		-- Záměrně vyřazujeme 0x00, které má v UI vlastní dedikovanou sekci.
		SELECT	organization, 
			organization_name, 
			current_organization,
			is_orgadmin
		FROM	v_user_organization_access
		WHERE	user_account_uuid = @user_account
			AND organization <> 0x00
		ORDER BY organization_name;
	END
	ELSE IF @subpage = 'system_roles'
	BEGIN
		-- Zjištění globálních oprávnění pro vykreslení prvního (systémového) řádku
		SELECT	is_system_admin,
			is_developer
		FROM	user_account
		WHERE	original = @user_account AND record_type = 'A' AND removed = 0;
	END
END
GO