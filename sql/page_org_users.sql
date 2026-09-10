IF OBJECT_ID('page_org_users') IS NOT NULL
	DROP PROCEDURE page_org_users;
GO

/* =============================================================================
 * Procedura: p_page_org_users
 * Účel: Načítá seznam uživatelů tenanta a detaily pro formulář v Master-Detail.
 * Architektura: Nezávislá na parametrech, kontext organizace čerpá z dbsession.
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

	-- Bezpečnostní záchytná brzda
	IF @current_org IS NULL
	BEGIN
		RAISERROR('Přístup odepřen: Nelze identifikovat aktivní relaci (dbsession).', 16, 1);
		RETURN;
	END

	-- 2. Zpracování pro levý panel (Master - Seznam uživatelů)
	IF @subpage = 'list'
	BEGIN
		SELECT 
			u.original AS user_uuid,
			u.first_name,
			u.last_name,
			u.email,
			ou.is_orgadmin,
			ou.removed AS remove_access
		FROM dbo.user_account u
		INNER JOIN dbo.user_organization_access ou ON u.original = ou.user_account_uuid
		WHERE ou.organization_uuid = @current_org
		  AND u.record_type = 'A' AND ou.record_type = 'A'
		  AND (ou.removed = 0 OR @show_removed = 1)
		ORDER BY u.last_name, u.first_name;
	END

	-- 3. Zpracování pro pravý panel (Detail pro editaci formuláře)
	ELSE IF @subpage = 'detail'
	BEGIN
		SELECT 
			u.login_name,
			u.first_name,
			u.last_name,
			u.email,
			ou.is_orgadmin,
			ou.removed AS remove_access,
			u.inactive AS deactivate_global
		FROM dbo.user_account u
		INNER JOIN dbo.user_organization_access ou ON u.original = ou.user_account_uuid
		WHERE u.original = @update_guid 
		  AND ou.organization_uuid = @current_org
		  AND u.record_type = 'A' AND ou.record_type = 'A';
	END
END
GO