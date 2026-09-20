EXECUTE dropni 'f_get_user_info', 'FN'
GO

/* =============================================================================
 * Funkce: f_get_user_info
 * Účel: Vrátí formátovaný řetězec "Jméno Příjmení/Zkratka organizace" pro
 *       potřeby zobrazení auditních stop v UI.
 *
 * Vstup: @who (uuid) - Očekává se hodnota user_access_uuid z dbsession, 
 *        případně systémové 0x00 nebo přímé UUID z user_account.
 * ============================================================================= */
CREATE FUNCTION dbo.f_get_user_info(@who uniqueidentifier)
RETURNS varchar(500)
AS
BEGIN
	-- 1. Záchytný bod pro systémové události
	IF @who IS NULL OR @who = 0x00 RETURN 'Systém'

	DECLARE @result varchar(500)

	-- 2. Primární dohledání přes user_access_uuid (standardní auditní stopa z dbsession)
	SELECT TOP 1 
		@result = u.caption + '/' + ISNULL(NULLIF(o.shortname, ''), o.caption)
	FROM	user_organization_access a
	JOIN	user_account u ON u.original = a.user_account_uuid AND u.record_type = 'A'
	JOIN	organization o ON o.original = a.organization_uuid AND o.record_type = 'A'
	WHERE	a.original = @who AND a.record_type = 'A'

	-- 3. Fallback: Pokud je v @who napřímo uloženo UUID z user_account (např. master skripty)
	IF @result IS NULL
	BEGIN
		SELECT TOP 1 
			@result = caption + '/SYS'
		FROM	user_account
		WHERE	original = @who AND record_type = 'A'
	END

	RETURN ISNULL(@result, 'Neznámý uživatel')
END
GO