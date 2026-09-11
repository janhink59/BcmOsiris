/* =============================================================================
 * SOUBOR: page_change_user_context.sql
 * Účel: Datová procedura pro stránku změny kontextu uživatele.
 * ============================================================================= */

EXECUTE dropni 'page_change_user_context', 'P'
GO

CREATE PROCEDURE page_change_user_context
	@subpage varchar(30)
AS
BEGIN
	SET NOCOUNT ON;

	IF @subpage = 'main'
	BEGIN
		DECLARE @user_account uniqueidentifier;
		
		-- Získání aktuálně přihlášeného uživatele z relace
		SELECT	@user_account = user_account 
		FROM	dbsession 
		WHERE	spid = @@SPID;

		-- Načtení pouze těch organizací, do kterých má tento uživatel přístup
		SELECT	organization, 
			organization_name, 
			current_organization,
			is_orgadmin
		FROM	v_user_organization_access
		WHERE	user_account_uuid = @user_account
		ORDER BY organization_name;
	END
END
GO