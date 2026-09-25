/* =============================================================================
 * Verze: 2026-09-25 16:46
 * Procedura: page_meta_object
 * Účel: Dodává data pro UI editoru metadat objektů a jejich sloupců.
 * Voláno z: page_meta_object.php
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
		-- 1. Resultset: Detail vybraného objektu
		SELECT	*
		FROM	vrepo_meta_object 
		WHERE	original = @update_guid;

		-- 2. Resultset: Seznam všech sloupců k němu příslušících
		SELECT	*
		FROM	vrepo_meta_column 
		WHERE	parent_object = @update_guid 
		ORDER BY parent_order, column_name;
	END
END
GO

/* =============================================================================
 * Verze: 2026-09-25 16:46
 * Procedura: form_meta_object
 * Účel: Zápis úprav nad hlavním objektem (tenant override nebo překlad).
 * ============================================================================= */
IF OBJECT_ID('form_meta_object', 'P') IS NOT NULL DROP PROCEDURE form_meta_object;
GO
CREATE PROCEDURE form_meta_object
	@object_original UNIQUEIDENTIFIER,
	@caption VARCHAR(200),
	@description VARCHAR(MAX),
	@helptext VARCHAR(MAX)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @user_access_uuid UNIQUEIDENTIFIER;
	DECLARE @organization_uuid UNIQUEIDENTIFIER;

	SELECT	@user_access_uuid = user_access_uuid, 
		@organization_uuid = organization
	FROM	dbsession 
	WHERE	spid = @@SPID;

	IF @user_access_uuid IS NULL RETURN;

	BEGIN TRAN;
	
	DECLARE @existing_uuid UNIQUEIDENTIFIER;
	SELECT	@existing_uuid = uuid 
	FROM	meta_object 
	WHERE	original = @object_original 
		AND object_owner = @organization_uuid 
		AND record_type = 'A' 
		AND removed = 0;

	IF @existing_uuid IS NOT NULL
	BEGIN
		UPDATE	meta_object
		SET	caption = @caption,
			description = @description,
			helptext = @helptext,
			date_modified = GETDATE(),
			who_modified = @user_access_uuid
		WHERE	uuid = @existing_uuid;
	END
	ELSE
	BEGIN
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status,
			object_type, builtin_code, caption, caption_plural, description, helptext,
			module, is_final, is_protected,
			who_created, who_modified
		)
		SELECT 
			NEWID(), @organization_uuid, original, 'A', 'A',
			object_type, builtin_code, @caption, caption_plural, @description, @helptext,
			module, is_final, is_protected,
			@user_access_uuid, @user_access_uuid
		FROM meta_object
		WHERE original = @object_original AND object_owner = 0x00 AND record_type = 'A';
	END
	COMMIT;
END
GO

/* =============================================================================
 * Verze: 2026-09-25 16:46
 * Procedura: form_meta_column
 * Účel: Zápis úprav nad konkrétním sloupcem (iterativně voláno z PHP).
 * ============================================================================= */
IF OBJECT_ID('form_meta_column', 'P') IS NOT NULL DROP PROCEDURE form_meta_column;
GO
CREATE PROCEDURE form_meta_column
	@col_original UNIQUEIDENTIFIER,
	@caption VARCHAR(200),
	@label VARCHAR(200),
	@header VARCHAR(200),
	@input_width VARCHAR(50),
	@translate BIT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @user_access_uuid UNIQUEIDENTIFIER;
	DECLARE @organization_uuid UNIQUEIDENTIFIER;

	SELECT	@user_access_uuid = user_access_uuid, 
		@organization_uuid = organization
	FROM	dbsession 
	WHERE	spid = @@SPID;

	IF @user_access_uuid IS NULL RETURN;

	DECLARE @existing_uuid UNIQUEIDENTIFIER;
	SELECT	@existing_uuid = uuid 
	FROM	meta_column 
	WHERE	original = @col_original 
		AND object_owner = @organization_uuid 
		AND record_type = 'A' 
		AND removed = 0;

	IF @existing_uuid IS NOT NULL
	BEGIN
		UPDATE	meta_column
		SET	caption = @caption,
			label = @label,
			header = @header,
			input_width = @input_width,
			translate = @translate,
			date_modified = GETDATE(),
			who_modified = @user_access_uuid
		WHERE	uuid = @existing_uuid;
	END
	ELSE
	BEGIN
		INSERT INTO meta_column (
			uuid, object_owner, original, record_type, approval_status,
			parent_object, parent_order, sort_code, column_name, 
			caption, caption_plural, description, label, header, helptext, placeholder,
			input_type, input_width, input_rows, max_length, css_class,
			translate, history, is_html, is_mandatory, is_url, is_computed, 
			show_empty, hidden, customizable, is_final, is_protected, ancestor,
			who_created, who_modified
		)
		SELECT 
			NEWID(), @organization_uuid, original, 'A', 'A',
			parent_object, parent_order, sort_code, column_name, 
			@caption, caption_plural, description, @label, @header, helptext, placeholder,
			input_type, @input_width, input_rows, max_length, css_class,
			@translate, history, is_html, is_mandatory, is_url, is_computed, 
			show_empty, hidden, customizable, is_final, is_protected, ancestor,
			@user_access_uuid, @user_access_uuid
		FROM meta_column
		WHERE original = @col_original AND object_owner = 0x00 AND record_type = 'A';
	END
END
GO