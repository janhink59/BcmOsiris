IF OBJECT_ID('f_link_original', 'FN') IS NOT NULL 
	DROP FUNCTION f_link_original;
GO

/* =============================================================================
 * Verze: 2026-10-30 23:35
 * Soubor: f_link_original.sql
 * FUNKCE: dbo.f_link_original
 * Účel: Deterministický výpočet identifikátoru "original" specificky pro vazby
 *       v tabulce link ze 4 klíčových složek (link_def, from_object, to_object,
 *       ancestor_link) a vlastníka (object_owner).
 *       Nezávislá "pure" funkce pro maximální výkon uvnitř triggeru trgo_link
 *       a procedury p_sync_derived_links.
 * Vazby:
 * - Volána z triggeru trgo_link (generate_trgo.sql), procedury p_sync_derived_links
 *   (p_sync_derived_links.sql) a z PHP traitu entity_manager_write.php.
 * Změny:
 * - 2026-10-30 23:35: Přidán 5. parametr @ancestor_link (výchozí hodnota
 *   '00000000-0000-0000-0000-000000000000' pro kořenové vazby s ancestor_link = 0x00),
 *   aby mohly v tabulce link koexistovat vazby zděděné po různých cestách.
 * ============================================================================= */
CREATE FUNCTION dbo.f_link_original(
	@owner varchar(36),                                                        -- Vlastník záznamu (tenant nebo systém)
	@link_def varchar(36),                                                     -- UUID definice vazby (meta_link_def.original)
	@from_object varchar(36),                                                  -- UUID zdrojového záznamu
	@to_object varchar(36),                                                    -- UUID cílového záznamu
	@ancestor_link varchar(36) = '00000000-0000-0000-0000-000000000000'        -- UUID nadřízené vazby při dědění (0x00 pro přímou vazbu)
)
RETURNS uniqueidentifier
AS
BEGIN
	RETURN HASHBYTES('MD5', 
		'link|' + 
		LOWER(ISNULL(@owner, '')) + '|' + 
		LOWER(ISNULL(@link_def, '')) + '|' + 
		LOWER(ISNULL(@from_object, '')) + '|' + 
		LOWER(ISNULL(@to_object, '')) + '|' + 
		LOWER(ISNULL(NULLIF(@ancestor_link, ''), '00000000-0000-0000-0000-000000000000'))
	);
END
GO