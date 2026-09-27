/* =============================================================================
 * Verze: 2026-09-27
 * Soubor: page_meta_column.sql
 * Procedura: page_meta_column
 * Účel: Dodává data pro UI editoru detailních vlastností sloupců.
 * Voláno z: page_meta_column.php
 * ============================================================================= */
IF OBJECT_ID('page_meta_column', 'P') IS NOT NULL DROP PROCEDURE page_meta_column;
GO
CREATE PROCEDURE page_meta_column
	@subpage VARCHAR(30),
	@parent_object UNIQUEIDENTIFIER = NULL,
	@update_guid UNIQUEIDENTIFIER = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF @subpage = 'parent_info' AND @parent_object IS NOT NULL
	BEGIN
		SELECT	builtin_code, 
			caption 
		FROM	vrepo_meta_object 
		WHERE	original = @parent_object;
	END
	ELSE IF @subpage = 'list' AND @parent_object IS NOT NULL
	BEGIN
		SELECT	original AS column_uuid,
			column_name,
			caption,
			parent_order
		FROM	vrepo_meta_column
		WHERE	parent_object = @parent_object
		ORDER BY parent_order, column_name;
	END
	ELSE IF @subpage = 'detail' AND @update_guid IS NOT NULL
	BEGIN
		SELECT	c.*,
			dbo.f_get_user_info(c.who_created) AS who_created_info,
			dbo.f_get_user_info(c.who_modified) AS who_modified_info
		FROM	vrepo_meta_column c
		WHERE	c.original = @update_guid;
	END
END
GO