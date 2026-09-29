EXECUTE dropni 'p_generate_primitive_classes', 'P'
GO

/* =============================================================================
 * Soubor: p_generate_primitive_classes.sql
 * Procedura: p_generate_primitive_classes
 * Účel: Automaticky vygeneruje výchozí primitivní logické třídy (1:1) 
 *       do tabulky meta_class pro všechny fyzické objekty (T, V) 
 *       evidované v meta_object. Tím zajišťuje STI vrstvu.
 * ============================================================================= */
CREATE PROCEDURE p_generate_primitive_classes
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Explicitní definice vlastníka pro deterministický výpočet original
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

	-- Vložení výchozích logických tříd k fyzickým tabulkám
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status,
		class_name, storage_object, ancestor_class,
		caption, caption_plural, description, helptext,
		is_final, is_protected,
		who_created, who_modified
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		mo.builtin_code, mo.original, NULL,
		NULL, NULL, NULL, NULL,
		1, 0, -- Zákaz vytvoření overridu celé primitivní třídy, ale povolena úprava UI
		0x00, 0x00
	FROM meta_object mo
	CROSS APPLY (
		SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), mo.builtin_code, '') AS orig_uuid
	) x
	WHERE mo.object_owner = 0x00 
		AND mo.record_type = 'A' 
		AND mo.removed = 0
		-- AND mo.object_type IN ('T', 'V') -- Beru všechny objekty, jinak bych se nedostal na jejich sloupce
		AND NOT EXISTS (
			SELECT 1 FROM meta_class mc 
			WHERE mc.original = x.orig_uuid
				AND mc.object_owner = 0x00 
				AND mc.record_type = 'A'
		);

END
GO