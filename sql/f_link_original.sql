IF OBJECT_ID('f_link_original', 'FN') IS NOT NULL 
	DROP FUNCTION f_link_original;
GO

/* =============================================================================
 * FUNKCE: f_link_original
 * Účel: Deterministický výpočet identifikátoru "original" specificky pro vazby.
 *       Nezávislá "pure" funkce pro maximální výkon uvnitř triggeru.
 * ============================================================================= */
CREATE FUNCTION f_link_original(
	@owner varchar(36),                 -- Vlastník záznamu (tenant nebo systém)
	@link_def varchar(36),              -- UUID definice vazby
	@from_object varchar(36),           -- UUID zdrojového záznamu
	@to_object varchar(36)              -- UUID cílového záznamu
)
RETURNS uniqueidentifier
AS
BEGIN
	RETURN HASHBYTES('MD5', 
		'link|' + 
		LOWER(@owner) + '|' + 
		LOWER(ISNULL(@link_def, '')) + '|' + 
		LOWER(ISNULL(@from_object, '')) + '|' + 
		LOWER(ISNULL(@to_object, ''))
	);
END
GO