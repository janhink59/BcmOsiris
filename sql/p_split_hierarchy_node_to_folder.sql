EXECUTE dropni 'p_split_hierarchy_node_to_folder', 'P';
GO

/* =============================================================================
 * Verze:     2026-11-12 17:10
 * Soubor:    p_split_hierarchy_node_to_folder.sql
 * Procedura: dbo.p_split_hierarchy_node_to_folder
 * Účel:      Automaticky rozčlení koncový uzel (is_leaf = 1) na vnitřní složku
 *            (is_leaf = 0) a v případě, že je uzel již uzamčen existujícími
 *            vazbami (dbo.f_is_hierarchy_node_locked = 1), převede stávající
 *            záznamy a vazby na novou podpoložku '<parent>_oth'.
 * Vazby:     - Čte tabulky dbsession a meta_link_def.
 *            - Čte a modifikuje tabulky asset_class, threat, impact, scenario,
 *              countermeasure, hierarchy_item, asset, scenario_assessment,
 *              countermeasure_implementation a link.
 *            - Využívá funkce dbo.f_is_hierarchy_node_locked,
 *              dbo.f_generate_original, dbo.f_syscolumns, dbo.f_link_original
 *              a proceduru dbo.p_sync_derived_links.
 * ============================================================================= */
CREATE PROCEDURE dbo.p_split_hierarchy_node_to_folder
	@table_name varchar(128),
	@node_original uniqueidentifier,
	@org_uuid uniqueidentifier = NULL,
	@user_session uniqueidentifier = NULL,
	@new_oth_original uniqueidentifier = NULL OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	SET @new_oth_original = NULL;

	IF @node_original IS NULL OR @node_original = 0x00
		RETURN;

	IF @table_name NOT IN ('asset_class', 'threat', 'impact', 'scenario', 'countermeasure', 'hierarchy_item', 'asset')
		RETURN;

	IF OBJECT_ID(@table_name, 'U') IS NULL OR COL_LENGTH(@table_name, 'is_leaf') IS NULL
		RETURN;

	IF @org_uuid IS NULL OR @user_session IS NULL
	BEGIN
		SELECT TOP 1
			@org_uuid = COALESCE(@org_uuid, organization, 0x00),
			@user_session = COALESCE(@user_session, login_session_uuid, 0x00)
		FROM dbsession
		WHERE spid = @@SPID;
	END
	SET @org_uuid = ISNULL(@org_uuid, 0x00);
	SET @user_session = ISNULL(@user_session, 0x00);

	DECLARE @is_leaf bit = 0;
	DECLARE @base_code varchar(80) = '';
	DECLARE @hier_uuid uniqueidentifier = NULL;

	DECLARE @sql_chk nvarchar(max) = N'
	SELECT TOP 1
		@p_leaf = is_leaf,
		@p_code = builtin_code'
		+ CASE WHEN @table_name = 'hierarchy_item' THEN N', @p_hier = hierarchy' ELSE N'' END + N'
	FROM [' + @table_name + N']
	WHERE original = @p_orig
		AND object_owner IN (@p_org, 0x00)
		AND record_type = ''A''
		AND removed = 0
	ORDER BY CASE WHEN object_owner = @p_org THEN 0 ELSE 1 END;';

	EXEC sp_executesql
		@stmt = @sql_chk,
		@params = N'@p_orig uniqueidentifier, @p_org uniqueidentifier, @p_leaf bit OUTPUT, @p_code varchar(80) OUTPUT, @p_hier uniqueidentifier OUTPUT',
		@p_orig = @node_original,
		@p_org = @org_uuid,
		@p_leaf = @is_leaf OUTPUT,
		@p_code = @base_code OUTPUT,
		@p_hier = @hier_uuid OUTPUT;

	IF @base_code = '' OR @is_leaf = 0
		RETURN;

	DECLARE @is_locked bit = dbo.f_is_hierarchy_node_locked(@table_name, @node_original, @org_uuid);

	IF @is_locked = 1
	BEGIN
		DECLARE @clean_base varchar(70) = LOWER(LTRIM(RTRIM(@base_code)));
		IF RIGHT(@clean_base, 4) = '_oth'
			SET @clean_base = LEFT(@clean_base, LEN(@clean_base) - 4);
		SET @clean_base = LEFT(@clean_base, 70);

		DECLARE @oth_code varchar(80) = @clean_base + '_oth';
		DECLARE @suffix_idx int = 1;
		DECLARE @code_exists bit = 1;

		WHILE @code_exists = 1 AND @suffix_idx <= 50
		BEGIN
			SET @code_exists = 0;
			DECLARE @sql_dup nvarchar(max) = N'
			IF EXISTS (
				SELECT 1 FROM [' + @table_name + N']
				WHERE builtin_code = @p_c
					AND object_owner IN (@p_org, 0x00)
					AND record_type = ''A''
					' + CASE WHEN @table_name = 'hierarchy_item' THEN N'AND hierarchy = @p_h' ELSE N'' END + N'
			) SET @p_ex = 1;';

			EXEC sp_executesql
				@stmt = @sql_dup,
				@params = N'@p_c varchar(80), @p_org uniqueidentifier, @p_h uniqueidentifier, @p_ex bit OUTPUT',
				@p_c = @oth_code,
				@p_org = @org_uuid,
				@p_h = @hier_uuid,
				@p_ex = @code_exists OUTPUT;

			IF @code_exists = 1
			BEGIN
				SET @suffix_idx = @suffix_idx + 1;
				SET @oth_code = @clean_base + '_oth_' + CAST(@suffix_idx AS varchar(10));
			END
		END

		IF @table_name = 'hierarchy_item'
			SET @new_oth_original = dbo.f_generate_original(@table_name, @org_uuid, CAST(@hier_uuid AS varchar(36)), @oth_code);
		ELSE
			SET @new_oth_original = dbo.f_generate_original(@table_name, @org_uuid, @oth_code, NULL);

		DECLARE @copy_cols nvarchar(max) = N'';
		SELECT @copy_cols = @copy_cols + N', [' + colname + N']'
		FROM dbo.f_syscolumns(@table_name)
		WHERE iscomputed = 0
			AND is_identity = 0
			AND colname NOT IN (
				'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
				'draft_author', 'approval_note', 'inactive', 'removed', 'language',
				'date_created', 'who_created', 'date_modified', 'who_modified',
				'builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'caption', 'shortname'
			)
		ORDER BY colid;

		DECLARE @sql_ins_oth nvarchar(max) = N'
		INSERT INTO [' + @table_name + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, inactive, removed, [language],
			date_created, who_created, date_modified, who_modified,
			builtin_code, parent_uuid, sort_code, is_leaf, caption, shortname' + @copy_cols + N'
		)
		SELECT TOP 1
			@p_oth_orig, @p_org, @p_oth_orig, ''A'', ''A'',
			0x00, '''', 0, 0, [language],
			GETDATE(), @p_user, GETDATE(), @p_user,
			@p_oth_code, @p_orig, ''900'', 1,
			LEFT(ISNULL(NULLIF(caption, ''''), @p_oth_code) + CASE WHEN [language] = ''en'' THEN '' - other'' ELSE '' - ostatní'' END, 200),
			CASE WHEN ISNULL(shortname, '''') <> '''' THEN LEFT(shortname, 35) + ''_OTH'' ELSE '''' END' + @copy_cols + N'
		FROM [' + @table_name + N']
		WHERE original = @p_orig
			AND object_owner IN (@p_org, 0x00)
			AND record_type = ''A''
			AND removed = 0
		ORDER BY CASE WHEN object_owner = @p_org THEN 0 ELSE 1 END;

		INSERT INTO [' + @table_name + N'] (
			uuid, object_owner, original, record_type, approval_status,
			draft_author, approval_note, inactive, removed, [language],
			date_created, who_created, date_modified, who_modified,
			builtin_code, parent_uuid, sort_code, is_leaf, caption, shortname' + @copy_cols + N'
		)
		SELECT
			NEWID(), @p_org, @p_oth_orig, ''L'', ''A'',
			0x00, '''', 0, 0, l.[language],
			GETDATE(), @p_user, GETDATE(), @p_user,
			@p_oth_code, @p_orig, ''900'', 1,
			LEFT(ISNULL(NULLIF(l.caption, ''''), @p_oth_code) + CASE WHEN l.[language] = ''en'' THEN '' - other'' ELSE '' - ostatní'' END, 200),
			CASE WHEN ISNULL(l.shortname, '''') <> '''' THEN LEFT(l.shortname, 35) + ''_OTH'' ELSE '''' END' + REPLACE(@copy_cols, N', [', N', l.[') + N'
		FROM (
			SELECT *, ROW_NUMBER() OVER (PARTITION BY [language] ORDER BY CASE WHEN object_owner = @p_org THEN 0 ELSE 1 END) AS rn
			FROM [' + @table_name + N']
			WHERE original = @p_orig
				AND object_owner IN (@p_org, 0x00)
				AND record_type = ''L''
				AND removed = 0
		) l
		WHERE l.rn = 1;';

		EXEC sp_executesql
			@stmt = @sql_ins_oth,
			@params = N'@p_orig uniqueidentifier, @p_oth_orig uniqueidentifier, @p_org uniqueidentifier, @p_user uniqueidentifier, @p_oth_code varchar(80)',
			@p_orig = @node_original,
			@p_oth_orig = @new_oth_original,
			@p_org = @org_uuid,
			@p_user = @user_session,
			@p_oth_code = @oth_code;

		-- 3. Převedení stávajících záznamů a přímých vazeb z @node_original na @new_oth_original
		IF @table_name = 'asset_class'
		BEGIN
			IF OBJECT_ID('asset', 'U') IS NOT NULL
				UPDATE asset SET primary_asset_class = @new_oth_original WHERE primary_asset_class = @node_original AND object_owner IN (@org_uuid, 0x00);
			IF OBJECT_ID('scenario', 'U') IS NOT NULL
				UPDATE scenario SET asset_class_uuid = @new_oth_original WHERE asset_class_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
		END
		ELSE IF @table_name = 'threat'
		BEGIN
			IF OBJECT_ID('scenario', 'U') IS NOT NULL
				UPDATE scenario SET threat_uuid = @new_oth_original WHERE threat_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
		END
		ELSE IF @table_name = 'scenario'
		BEGIN
			IF OBJECT_ID('scenario_assessment', 'U') IS NOT NULL
				UPDATE scenario_assessment SET scenario_uuid = @new_oth_original WHERE scenario_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
		END
		ELSE IF @table_name = 'countermeasure'
		BEGIN
			IF OBJECT_ID('countermeasure_implementation', 'U') IS NOT NULL
				UPDATE countermeasure_implementation SET countermeasure_uuid = @new_oth_original WHERE countermeasure_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
		END
		ELSE IF @table_name = 'asset'
		BEGIN
			IF OBJECT_ID('scenario_assessment', 'U') IS NOT NULL
				UPDATE scenario_assessment SET asset_uuid = @new_oth_original WHERE asset_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
			IF OBJECT_ID('countermeasure_implementation', 'U') IS NOT NULL
				UPDATE countermeasure_implementation SET asset_uuid = @new_oth_original WHERE asset_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
		END

		-- Přesměrování přímých vazeb v tabulce link (mimo interní stromové parent_to_child)
		IF OBJECT_ID('link', 'U') IS NOT NULL
		BEGIN
			UPDATE l
			SET l.to_object = @new_oth_original,
				l.original = dbo.f_link_original(CAST(l.object_owner AS varchar(36)), CAST(l.link_def AS varchar(36)), CAST(l.from_object AS varchar(36)), CAST(@new_oth_original AS varchar(36)), CAST(l.ancestor_link AS varchar(36))),
				l.date_modified = GETDATE(),
				l.who_modified = @user_session
			FROM link l
			JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.removed = 0
			WHERE l.to_object = @node_original
				AND l.ancestor_link = 0x00
				AND l.is_derived = 0
				AND mld.is_exclusive_parent = 0
				AND l.object_owner IN (@org_uuid, 0x00)
				AND (mld.leaf_only = 1 OR @table_name = 'asset');

			UPDATE l
			SET l.from_object = @new_oth_original,
				l.original = dbo.f_link_original(CAST(l.object_owner AS varchar(36)), CAST(l.link_def AS varchar(36)), CAST(@new_oth_original AS varchar(36)), CAST(l.to_object AS varchar(36)), CAST(l.ancestor_link AS varchar(36))),
				l.date_modified = GETDATE(),
				l.who_modified = @user_session
			FROM link l
			JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.removed = 0
			WHERE l.from_object = @node_original
				AND l.ancestor_link = 0x00
				AND l.is_derived = 0
				AND mld.is_exclusive_parent = 0
				AND l.object_owner IN (@org_uuid, 0x00)
				AND @table_name = 'asset';

			EXEC dbo.p_sync_derived_links;
		END
	END

	-- 4. Přepnutí původního uzlu @node_original na složku (is_leaf = 0)
	DECLARE @sql_folder nvarchar(max) = N'
	UPDATE [' + @table_name + N']
	SET is_leaf = 0,
		date_modified = GETDATE(),
		who_modified = @p_user
	WHERE original = @p_orig
		AND object_owner IN (@p_org, 0x00)
		AND record_type IN (''A'', ''L'');';

	EXEC sp_executesql
		@stmt = @sql_folder,
		@params = N'@p_orig uniqueidentifier, @p_org uniqueidentifier, @p_user uniqueidentifier',
		@p_orig = @node_original,
		@p_org = @org_uuid,
		@p_user = @user_session;
END
GO