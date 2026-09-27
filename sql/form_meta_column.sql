/* =============================================================================
 * Verze: 2026-09-27
 * Soubor: form_meta_column.sql
 * Procedura: form_meta_column
 * Účel: Zápis detailních úprav nad jedním sloupcem (tenant override nebo překlad).
 * ============================================================================= */
EXECUTE dropni 'form_meta_column', 'P'
GO

CREATE PROCEDURE form_meta_column
	@col_original UNIQUEIDENTIFIER,
	@sort_code VARCHAR(20) = NULL,
	@caption VARCHAR(200) = NULL,
	@label VARCHAR(200) = NULL,
	@header VARCHAR(200) = NULL,
	@helptext VARCHAR(MAX) = NULL,
	@placeholder VARCHAR(200) = NULL,
	@input_type VARCHAR(20) = NULL,
	@input_width VARCHAR(50) = NULL,
	@input_rows INT = NULL,
	@max_length INT = NULL,
	@css_class VARCHAR(200) = NULL,
	@translate BIT = NULL,
	@history BIT = NULL,
	@is_html BIT = NULL,
	@is_mandatory BIT = NULL,
	@is_url BIT = NULL,
	@is_computed BIT = NULL,
	@show_empty BIT = NULL,
	@hidden BIT = NULL,
	@customizable BIT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @user_access_uuid UNIQUEIDENTIFIER;
	DECLARE @organization_uuid UNIQUEIDENTIFIER;

	-- Načtení identity PŘÍMO z dbsession pro dodržení autonimní auditní stopy
	SELECT	@user_access_uuid = user_access_uuid, 
		@organization_uuid = organization
	FROM	dbsession 
	WHERE	spid = @@SPID;

	IF @user_access_uuid IS NULL RETURN;

	BEGIN TRAN;

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
		SET	sort_code = ISNULL(@sort_code, sort_code),
			caption = @caption,
			label = @label,
			header = @header,
			helptext = @helptext,
			placeholder = @placeholder,
			input_type = ISNULL(@input_type, input_type),
			input_width = @input_width,
			input_rows = @input_rows,
			max_length = @max_length,
			css_class = @css_class,
			translate = ISNULL(@translate, translate),
			history = ISNULL(@history, history),
			is_html = ISNULL(@is_html, is_html),
			is_mandatory = ISNULL(@is_mandatory, is_mandatory),
			is_url = ISNULL(@is_url, is_url),
			is_computed = ISNULL(@is_computed, is_computed),
			show_empty = ISNULL(@show_empty, show_empty),
			hidden = ISNULL(@hidden, hidden),
			customizable = ISNULL(@customizable, customizable),
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
			parent_object, parent_order, ISNULL(@sort_code, sort_code), column_name, 
			@caption, caption_plural, description, @label, @header, @helptext, @placeholder,
			ISNULL(@input_type, input_type), @input_width, @input_rows, @max_length, @css_class,
			ISNULL(@translate, translate), ISNULL(@history, history), ISNULL(@is_html, is_html), ISNULL(@is_mandatory, is_mandatory), ISNULL(@is_url, is_url), ISNULL(@is_computed, is_computed), 
			ISNULL(@show_empty, show_empty), ISNULL(@hidden, hidden), ISNULL(@customizable, customizable), is_final, is_protected, ancestor,
			@user_access_uuid, @user_access_uuid
		FROM meta_column
		WHERE original = @col_original AND object_owner = 0x00 AND record_type = 'A';
	END
	
	COMMIT;
END
GO