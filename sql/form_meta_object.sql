/* =============================================================================
 * Verze: 2026-09-27
 * Soubor: form_meta_object.sql
 * Procedura: form_meta_object
 * Účel: Zápis úprav nad hlavním objektem (tenant override nebo překlad).
 * ============================================================================= */
IF OBJECT_ID('form_meta_object', 'P') IS NOT NULL DROP PROCEDURE form_meta_object;
GO
CREATE PROCEDURE form_meta_object
	@object_original UNIQUEIDENTIFIER,
	@caption VARCHAR(200),
	@description VARCHAR(MAX),
	@helptext VARCHAR(MAX),
	@column_ancestor UNIQUEIDENTIFIER = NULL
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
			column_ancestor = @column_ancestor,
			date_modified = GETDATE(),
			who_modified = @user_access_uuid
		WHERE	uuid = @existing_uuid;
	END
	ELSE
	BEGIN
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status,
			object_type, builtin_code, caption, caption_plural, description, helptext,
			module, column_ancestor,
			who_created, who_modified
		)
		SELECT 
			NEWID(), @organization_uuid, original, 'A', 'A',
			object_type, builtin_code, @caption, caption_plural, @description, @helptext,
			module, @column_ancestor,
			@user_access_uuid, @user_access_uuid
		FROM meta_object
		WHERE original = @object_original AND object_owner = 0x00 AND record_type = 'A';
	END
	COMMIT;
END
GO