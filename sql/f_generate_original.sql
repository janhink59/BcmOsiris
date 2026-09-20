/* =============================================================================
 * FUNKCE: f_generate_original
 * Účel: Deterministický výpočet identifikátoru "original" ze 4 parametrů.
 * Vazby: Datové typy parametrů jsou záměrně varchar, aby MSSQL provedl 
 *        implicitní konverzi UUID automaticky při volání funkce.
 * ============================================================================= */
IF OBJECT_ID('f_generate_original', 'FN') IS NOT NULL 
	DROP FUNCTION f_generate_original;
GO

CREATE FUNCTION f_generate_original(
	@table_name varchar(128),
	@original_owner varchar(36),
	@key1 varchar(max),
	@key2 varchar(max)
)
RETURNS uniqueidentifier
AS
BEGIN
	-- Využití implicitní konverze: HASHBYTES vrací varbinary(16), 
	-- což funkce plynule a bez chyb vrátí jako uniqueidentifier.
	RETURN HASHBYTES('MD5', 
		LOWER(@table_name) + '|' + 
		LOWER(@original_owner) + '|' + 
		LOWER(ISNULL(@key1, '')) + '|' + 
		LOWER(ISNULL(@key2, ''))
	);
END
GO
