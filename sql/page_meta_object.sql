/* =============================================================================
 * Verze: 2026-09-27
 * Soubor: page_meta_object.sql
 * Procedura: page_meta_object
 * Účel: Dodává data pro UI editoru metadat objektů.
 * Změna: Doplněno načítání informací o uživatelích přes f_get_user_info pro auditní stopu.
 * ============================================================================= */
IF OBJECT_ID('page_meta_object', 'P') IS NOT NULL DROP PROCEDURE page_meta_object;
GO
CREATE PROCEDURE page_meta_object
	@subpage VARCHAR(30),
	@update_guid UNIQUEIDENTIFIER = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF @subpage = 'list'
	BEGIN
		SELECT	original AS object_uuid, 
			builtin_code, 
			caption, 
			object_type 
		FROM	vrepo_meta_object 
		ORDER BY object_type, builtin_code;
	END
	ELSE IF @subpage = 'detail' AND @update_guid IS NOT NULL
	BEGIN
		-- 1. Resultset: Detail vybraného objektu s formátovanými auditními stopami
		SELECT	o.*,
			dbo.f_get_user_info(o.who_created) AS who_created_info,
			dbo.f_get_user_info(o.who_modified) AS who_modified_info
		FROM	vrepo_meta_object o
		WHERE	o.original = @update_guid;

		-- 2. Resultset: Číselník potenciálních předků obsahujících sloupce (mimo sebe sama)
		SELECT	original AS ancestor_uuid,
			builtin_code,
			caption,
			object_type
		FROM	vrepo_meta_object o
		WHERE	original <> @update_guid
			AND EXISTS (SELECT 1 FROM vrepo_meta_column c WHERE c.parent_object = o.original AND c.record_type = 'A' AND c.removed = 0)
		ORDER BY object_type, builtin_code;
	END
END
GO