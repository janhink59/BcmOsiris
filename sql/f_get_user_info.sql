EXECUTE dropni 'f_get_user_info', 'FN'
GO

/* =============================================================================
 * Funkce: f_get_user_info
 * Účel: Vrátí formátovaný řetězec pro auditní stopy (např. "Jméno Příjmení/Zkratka org [Role]").
 * Změny: Napojeno na novou tabulku audit_login_session. Odpadá závislost na
 *        vazbě v user_organization_access.
 * Vstup: @who (uuid) - Očekává se hodnota login_session_uuid z dbsession, 
 *        případně systémové 0x00 nebo přímé UUID z user_account.
 * ============================================================================= */
CREATE FUNCTION dbo.f_get_user_info(@who uniqueidentifier)
RETURNS varchar(500)
AS
BEGIN
	-- 1. Záchytný bod pro systémové a automatizované události (short-circuit)
	IF @who IS NULL OR @who = 0x00 RETURN 'Systém'

	DECLARE @result varchar(500)

	-- 2. Primární dohledání přes login_session_uuid z auditního logu přihlášení
	SELECT TOP 1 
		@result = u.caption + '/' + ISNULL(NULLIF(o.shortname, ''), o.caption) + 
		' [' + 
		CASE als.assumed_role 
			WHEN 'U' THEN 'User'
			WHEN 'A' THEN 'Admin'
			WHEN 'S' THEN 'Sysadmin'
			WHEN 'D' THEN 'Developer'
			ELSE als.assumed_role 
		END + ']'
	FROM	audit_login_session als
	JOIN	user_account u ON u.original = als.user_account_uuid AND u.record_type = 'A'
	JOIN	organization o ON o.original = als.organization_uuid AND o.record_type = 'A'
	WHERE	als.uuid = @who

	-- 3. Fallback: Pokud je v @who napřímo uloženo UUID z user_account (např. starší data nebo master skripty)
	IF @result IS NULL
	BEGIN
		SELECT TOP 1 
			@result = caption + ' [Neznámá relace]'
		FROM	user_account
		WHERE	original = @who AND record_type = 'A'
	END

	RETURN ISNULL(@result, 'Neznámý uživatel')
END
GO