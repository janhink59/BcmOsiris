/* =============================================================================
 * Verze: 2026-11-11 21:30
 * Soubor: p_em_metadata.sql
 * Procedury: dbo.p_em_get_class_meta, dbo.p_em_get_columns_meta,
 *            dbo.p_em_get_select_options
 * Účel:   1. dbo.p_em_get_class_meta načte definici logické třídy ('A' a 'L'
 *            záznamy ve fallback řetězci < 1000), úložnou fyzickou tabulku
 *            a efektivní nadřazenou třídu pro načtení sloupců (s podporou STI
 *            dědění u odvozených hierarchií a STI tříd aktiv nad tabulkou asset).
 *         2. dbo.p_em_get_columns_meta načte definici sloupců ('A'), jejich
 *            předků v sys_global_columns ('ANC_A') a překladů ('L').
 *         3. dbo.p_em_get_select_options načte lokalizované položky pro <select>
 *            roletky v UI (source_code, meta_codetable, referenced_class včetně
 *            STI filtrování podle asset_archetype, asset_class_by_archetype a
 *            rekurzivní stromové vazby parent_uuid s vyloučením vlastního podstromu).
 * Vazby:  - Voláno z PHP třídy entity_manager (entity_manager.php, entity_manager_ui.php),
 *           page_asset.php, page_link.php, page_link_diagram.php, page_hierarchy_item.php,
 *           page_scale_value.php a page_approval.php.
 * ============================================================================= */

EXECUTE dropni 'p_em_get_class_meta', 'P';
EXECUTE dropni 'p_em_get_columns_meta', 'P';
EXECUTE dropni 'p_em_get_select_options', 'P';
GO

/* =============================================================================
 * Procedura: dbo.p_em_get_class_meta
 * ============================================================================= */
CREATE PROCEDURE dbo.p_em_get_class_meta
	@class_name varchar(80),
	@org_uuid uniqueidentifier = NULL,
	@requested_lang varchar(2) = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF @org_uuid IS NULL OR @requested_lang IS NULL
	BEGIN
		SELECT TOP 1
			@org_uuid = COALESCE(@org_uuid, organization, 0x00),
			@requested_lang = COALESCE(NULLIF(LTRIM(RTRIM(@requested_lang)), ''), [language], 'cs')
		FROM dbsession
		WHERE spid = @@SPID;
	END

	SET @org_uuid = ISNULL(@org_uuid, 0x00);

	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@requested_lang)
	WHERE fallback_order < 1000;

	DECLARE @cls_orig uniqueidentifier = NULL;
	DECLARE @anc_cls uniqueidentifier = NULL;
	DECLARE @col_parent_cls uniqueidentifier = NULL;
	DECLARE @stg_name varchar(80) = '';
	DECLARE @stg_orig uniqueidentifier = 0x00;

	SELECT TOP 1
		@cls_orig = mc.original,
		@anc_cls = mc.ancestor_class,
		@stg_name = mo.builtin_code,
		@stg_orig = mo.original
	FROM meta_class mc
	JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
	WHERE mc.class_name = @class_name
	  AND mc.record_type = 'A'
	  AND mc.object_owner IN (0x00, @org_uuid)
	  AND mc.removed = 0
	ORDER BY CASE WHEN mc.object_owner = @org_uuid THEN 0 ELSE 1 END;

	IF @cls_orig IS NULL
		RETURN;

	-- Dohledání nejbližší nadřazené třídy v hierarchii dědičnosti (ancestor_class), která má definované sloupce v meta_column
	SET @col_parent_cls = @cls_orig;
	DECLARE @walk_anc uniqueidentifier = @anc_cls;
	DECLARE @guard int = 0;

	WHILE @walk_anc IS NOT NULL AND @guard < 10 AND NOT EXISTS (
		SELECT 1 FROM meta_column WHERE parent_class = @col_parent_cls AND record_type = 'A' AND removed = 0
	)
	BEGIN
		SET @col_parent_cls = @walk_anc;
		SET @walk_anc = NULL;
		SELECT TOP 1 @walk_anc = ancestor_class
		FROM meta_class
		WHERE original = @col_parent_cls AND record_type = 'A' AND removed = 0;
		SET @guard = @guard + 1;
	END

	SELECT
		'A' AS row_kind,
		0 AS is_tenant_l,
		0 AS fallback_order,
		c.original,
		c.class_name,
		c.storage_object,
		c.ancestor_class,
		c.sort_code,
		c.svg_icon,
		c.is_final,
		c.is_protected,
		c.inactive,
		c.[language],
		COALESCE(NULLIF(CAST(c_my.caption AS NVARCHAR(MAX)), ''), CAST(c.caption AS NVARCHAR(MAX)), '') AS caption,
		COALESCE(NULLIF(CAST(c_my.caption_plural AS NVARCHAR(MAX)), ''), CAST(c.caption_plural AS NVARCHAR(MAX)), '') AS caption_plural,
		COALESCE(NULLIF(CAST(c_my.description AS NVARCHAR(MAX)), ''), CAST(c.description AS NVARCHAR(MAX)), '') AS description,
		COALESCE(NULLIF(CAST(c_my.helptext AS NVARCHAR(MAX)), ''), CAST(c.helptext AS NVARCHAR(MAX)), '') AS helptext,
		@stg_name AS storage_table_name,
		@stg_orig AS storage_original,
		@col_parent_cls AS effective_col_parent_class
	FROM meta_class c
	LEFT JOIN meta_class c_my
		ON c_my.original = c.original
		AND c_my.record_type = 'A'
		AND c_my.object_owner = @org_uuid
		AND c_my.object_owner <> 0x00
		AND c_my.removed = 0
	WHERE c.original = @cls_orig
	  AND c.record_type = 'A'
	  AND c.object_owner IN (0x00, @org_uuid)
	  AND c.removed = 0

	UNION ALL

	SELECT
		'L' AS row_kind,
		CASE WHEN l.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant_l,
		fl.fallback_order,
		l.original,
		l.class_name,
		l.storage_object,
		l.ancestor_class,
		l.sort_code,
		l.svg_icon,
		l.is_final,
		l.is_protected,
		l.inactive,
		l.[language],
		CAST(l.caption AS NVARCHAR(MAX)) AS caption,
		CAST(l.caption_plural AS NVARCHAR(MAX)) AS caption_plural,
		CAST(l.description AS NVARCHAR(MAX)) AS description,
		CAST(l.helptext AS NVARCHAR(MAX)) AS helptext,
		'' AS storage_table_name,
		0x00 AS storage_original,
		@col_parent_cls AS effective_col_parent_class
	FROM meta_class l
	JOIN @fl fl ON fl.[language] = l.[language]
	WHERE l.original = @cls_orig
	  AND l.record_type = 'L'
	  AND l.removed = 0
	  AND l.object_owner IN (0x00, @org_uuid)
	ORDER BY row_kind ASC, fallback_order ASC, is_tenant_l DESC;
END
GO

/* =============================================================================
 * Procedura: dbo.p_em_get_columns_meta
 * ============================================================================= */
CREATE PROCEDURE dbo.p_em_get_columns_meta
	@col_parent_class uniqueidentifier,
	@org_uuid uniqueidentifier = NULL,
	@requested_lang varchar(2) = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF @org_uuid IS NULL OR @requested_lang IS NULL
	BEGIN
		SELECT TOP 1
			@org_uuid = COALESCE(@org_uuid, organization, 0x00),
			@requested_lang = COALESCE(NULLIF(LTRIM(RTRIM(@requested_lang)), ''), [language], 'cs')
		FROM dbsession
		WHERE spid = @@SPID;
	END

	SET @org_uuid = ISNULL(@org_uuid, 0x00);

	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@requested_lang)
	WHERE fallback_order < 1000;

	DECLARE @col_origs TABLE (
		original uniqueidentifier NOT NULL PRIMARY KEY,
		row_kind varchar(10) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @col_origs (original, row_kind)
	SELECT c.original, 'A'
	FROM meta_column c
	WHERE c.parent_class = @col_parent_class
	  AND c.record_type = 'A'
	  AND c.object_owner = 0x00
	  AND c.removed = 0;

	INSERT INTO @col_origs (original, row_kind)
	SELECT DISTINCT c.ancestor, 'ANC_A'
	FROM @col_origs co
	JOIN meta_column c
		ON c.original = co.original
		AND c.record_type = 'A'
		AND c.object_owner = 0x00
		AND c.removed = 0
	WHERE co.row_kind = 'A'
	  AND c.ancestor IS NOT NULL
	  AND NOT EXISTS (SELECT 1 FROM @col_origs ex WHERE ex.original = c.ancestor);

	SELECT co.row_kind, 0 AS is_tenant_l, 0 AS fallback_order, c.*
	FROM @col_origs co
	JOIN meta_column c
		ON c.original = co.original
		AND c.record_type = 'A'
		AND c.object_owner = 0x00
		AND c.removed = 0

	UNION ALL

	SELECT 'L' AS row_kind, CASE WHEN l.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant_l, fl.fallback_order, l.*
	FROM @col_origs co
	JOIN meta_column l
		ON l.original = co.original
		AND l.record_type = 'L'
		AND l.removed = 0
		AND l.object_owner IN (0x00, @org_uuid)
	JOIN @fl fl ON fl.[language] = l.[language]
	ORDER BY row_kind ASC, parent_order ASC, sort_code ASC, fallback_order ASC, is_tenant_l DESC;
END
GO

/* =============================================================================
 * Procedura: dbo.p_em_get_select_options
 * ============================================================================= */
CREATE PROCEDURE dbo.p_em_get_select_options
	@mode varchar(30),
	@param_code varchar(200) = '',
	@ref_class_uuid uniqueidentifier = NULL,
	@curr_guid uniqueidentifier = NULL,
	@current_val uniqueidentifier = NULL,
	@hier_uuid uniqueidentifier = NULL,
	@storage_table varchar(128) = ''
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @org_sql uniqueidentifier = 0x00;
	DECLARE @sess_lang varchar(2) = 'cs';

	SELECT TOP 1
		@org_sql = ISNULL(organization, 0x00),
		@sess_lang = ISNULL([language], 'cs')
	FROM dbsession
	WHERE spid = @@SPID;

	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@sess_lang)
	WHERE fallback_order < 1000;

	-- 1. Výběr PHP třídy / stránky z meta_object (pro meta_phrase.source_code)
	IF @mode = 'source_code'
	BEGIN
		SELECT a.builtin_code AS value_code, a.builtin_code AS code_col, COALESCE(tr.caption, a.caption, '') AS caption
		FROM meta_object a
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM meta_object l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = a.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE a.object_type = 'P'
		  AND a.builtin_code <> ''
		  AND a.builtin_code <> 'global_phrase'
		  AND a.object_owner = 0x00
		  AND a.record_type = 'A'
		  AND a.removed = 0
		ORDER BY a.builtin_code;
		RETURN;
	END

	-- 2. Výběr položek číselníku z meta_codetable
	IF @mode = 'codetable'
	BEGIN
		SELECT c.value_code, c.value_code AS code_col, COALESCE(tr.caption, c.caption, c.value_code) AS caption
		FROM (
			SELECT original, value_code, caption, sort_code,
				ROW_NUMBER() OVER (PARTITION BY value_code ORDER BY CASE WHEN object_owner = @org_sql THEN 0 ELSE 1 END) AS rn
			FROM meta_codetable
			WHERE codetable_name = @param_code
			  AND object_owner IN (@org_sql, 0x00)
			  AND record_type = 'A'
			  AND removed = 0
			  AND inactive = 0
		) c
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM meta_codetable l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = c.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE c.rn = 1
		ORDER BY c.sort_code, caption;
		RETURN;
	END

	-- 2b. Koncové třídy aktiv (asset_class s is_leaf = 1) podřízené zadanému archetypu (nebo mapa všech archetypů)
	IF @mode = 'asset_class_by_archetype' AND OBJECT_ID('asset_class', 'U') IS NOT NULL
	BEGIN
		DECLARE @ac_nodes TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			parent_uuid uniqueidentifier NULL,
			builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
			instance_class_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
			sort_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			is_leaf bit NOT NULL,
			caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			root_archetype varchar(30) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO @ac_nodes (original, parent_uuid, builtin_code, instance_class_name, sort_code, is_leaf, caption, root_archetype)
		SELECT
			x.original, x.parent_uuid, x.builtin_code, x.instance_class_name, x.sort_code, x.is_leaf,
			COALESCE(tr.caption, x.caption, x.builtin_code),
			CASE
				WHEN x.instance_class_name LIKE 'asset[_]%' THEN UPPER(SUBSTRING(x.instance_class_name, 7, 30))
				WHEN x.builtin_code LIKE 'ac[_]%' AND x.builtin_code NOT LIKE 'ac[_]grp[_]%' THEN UPPER(SUBSTRING(x.builtin_code, 4, 30))
				ELSE NULL
			END
		FROM (
			SELECT a.original, a.parent_uuid, a.builtin_code, a.instance_class_name, a.sort_code, a.is_leaf, a.caption,
				ROW_NUMBER() OVER (PARTITION BY a.original ORDER BY CASE WHEN a.object_owner = @org_sql THEN 0 ELSE 1 END) AS rn
			FROM asset_class a
			WHERE a.object_owner IN (@org_sql, 0x00)
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND a.inactive = 0
		) x
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM asset_class l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = x.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE x.rn = 1;

		WHILE @@ROWCOUNT > 0
		BEGIN
			UPDATE ch
			SET ch.root_archetype = par.root_archetype
			FROM @ac_nodes ch
			JOIN @ac_nodes par ON par.original = ch.parent_uuid
			WHERE ch.root_archetype IS NULL
			  AND par.root_archetype IS NOT NULL;
		END

		SELECT
			original,
			builtin_code AS code_col,
			caption,
			ISNULL(root_archetype, '') AS archetype_code
		FROM @ac_nodes
		WHERE (is_leaf = 1 OR original = @current_val)
		  AND (@param_code = '' OR root_archetype = UPPER(@param_code) OR original = @current_val)
		ORDER BY root_archetype, sort_code, caption, builtin_code;
		RETURN;
	END

	-- 3. Stromový výběr nadřízeného uzlu (parent_uuid) s ochranou proti zacyklení
	IF @mode = 'parent_tree' AND @storage_table <> '' AND OBJECT_ID(@storage_table, 'U') IS NOT NULL
	BEGIN
		DECLARE @has_code bit = CASE WHEN COL_LENGTH(@storage_table, 'builtin_code') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @has_short bit = CASE WHEN COL_LENGTH(@storage_table, 'shortname') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @has_sort bit = CASE WHEN COL_LENGTH(@storage_table, 'sort_code') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @has_leaf bit = CASE WHEN COL_LENGTH(@storage_table, 'is_leaf') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @has_hier bit = CASE WHEN COL_LENGTH(@storage_table, 'hierarchy') IS NOT NULL THEN 1 ELSE 0 END;

		DECLARE @code_expr nvarchar(100) = CASE WHEN @has_code = 1 THEN N'a.builtin_code' WHEN @has_short = 1 THEN N'a.shortname' ELSE N'''''' END;
		DECLARE @sort_expr nvarchar(100) = CASE WHEN @has_sort = 1 THEN N'a.sort_code' ELSE N'''''' END;
		DECLARE @leaf_cond nvarchar(200) = CASE
			WHEN @storage_table IN ('meta_menu', 'asset', 'asset_class', 'threat', 'impact', 'scenario', 'countermeasure', 'hierarchy_item') AND @curr_guid IS NULL THEN N''
			WHEN @storage_table IN ('meta_menu', 'asset') THEN N''
			WHEN @has_leaf = 1 THEN N'AND (a.is_leaf = 0 OR a.original = @p_cur_val)'
			ELSE N''
		END;
		DECLARE @hier_cond nvarchar(200) = CASE WHEN @has_hier = 1 AND @hier_uuid IS NOT NULL THEN N'AND a.hierarchy = @p_hier' ELSE N'' END;

		DECLARE @sql_tree nvarchar(max) = N'
		DECLARE @fl TABLE ([language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, fallback_order int NOT NULL);
		INSERT INTO @fl ([language], fallback_order) SELECT [language], fallback_order FROM dbo.f_language_list(@p_lang) WHERE fallback_order < 1000;

		DECLARE @valid_nodes TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			code_col varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			parent_uuid uniqueidentifier NULL,
			sort_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			caption varchar(200) COLLATE DATABASE_DEFAULT NULL
		);

		INSERT INTO @valid_nodes (original, code_col, parent_uuid, sort_code, caption)
		SELECT original, ISNULL(code_col, ''''), parent_uuid, ISNULL(sort_code, ''''), caption
		FROM (
			SELECT a.original, ' + @code_expr + N' AS code_col, a.parent_uuid, ' + @sort_expr + N' AS sort_code, a.caption,
				ROW_NUMBER() OVER (PARTITION BY a.original ORDER BY CASE WHEN a.object_owner = @p_org THEN 0 ELSE 1 END) AS rn
			FROM [' + @storage_table + N'] a
			WHERE a.object_owner IN (@p_org, 0x00)
			  AND a.record_type = ''A''
			  AND a.removed = 0
			  ' + @leaf_cond + N'
			  ' + @hier_cond + N'
		) x
		WHERE x.rn = 1;

		DECLARE @descendants TABLE (original uniqueidentifier NOT NULL PRIMARY KEY);
		IF @p_curr IS NOT NULL AND @p_curr <> 0x00
		BEGIN
			INSERT INTO @descendants (original)
			SELECT original FROM @valid_nodes WHERE original = @p_curr;

			WHILE @@ROWCOUNT > 0
			BEGIN
				INSERT INTO @descendants (original)
				SELECT m.original
				FROM @valid_nodes m
				JOIN @descendants d ON m.parent_uuid = d.original
				WHERE NOT EXISTS (SELECT 1 FROM @descendants ex WHERE ex.original = m.original);
			END
		END

		SELECT r.original, r.code_col, COALESCE(tr.caption, r.caption, '''') AS caption
		FROM @valid_nodes r
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM [' + @storage_table + N'] l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = r.original
			  AND l.record_type = ''L''
			  AND l.removed = 0
			  AND l.object_owner IN (@p_org, 0x00)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '''') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @p_org THEN 0 ELSE 1 END ASC
		) tr
		WHERE NOT EXISTS (SELECT 1 FROM @descendants d WHERE d.original = r.original)
		ORDER BY CASE WHEN r.parent_uuid IS NULL THEN 0 ELSE 1 END, r.sort_code, r.code_col, caption;';

		EXEC sp_executesql
			@stmt = @sql_tree,
			@params = N'@p_org uniqueidentifier, @p_lang varchar(2), @p_curr uniqueidentifier, @p_cur_val uniqueidentifier, @p_hier uniqueidentifier',
			@p_org = @org_sql,
			@p_lang = @sess_lang,
			@p_curr = @curr_guid,
			@p_cur_val = @current_val,
			@p_hier = @hier_uuid;
		RETURN;
	END

	-- 4. Obecný relační výběr (referenced_class)
	IF @mode = 'ref_class' AND @ref_class_uuid IS NOT NULL
	BEGIN
		DECLARE @ref_table varchar(128) = '';
		DECLARE @ref_class_name varchar(80) = '';

		SELECT TOP 1
			@ref_table = mo.builtin_code,
			@ref_class_name = mc.class_name
		FROM meta_class mc
		JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
		WHERE mc.original = @ref_class_uuid
		  AND mc.object_owner IN (0x00, @org_sql)
		  AND mc.record_type = 'A'
		  AND mc.removed = 0;

		IF @ref_table = '' OR OBJECT_ID(@ref_table, 'U') IS NULL
			RETURN;

		IF @ref_table = 'meta_class'
		BEGIN
			SELECT a.original, a.class_name AS code_col, COALESCE(tr.caption, a.caption, '') AS caption
			FROM meta_class a
			OUTER APPLY (
				SELECT TOP 1 l.caption
				FROM meta_class l
				JOIN @fl fl ON fl.[language] = l.[language]
				WHERE l.original = a.original AND l.record_type = 'L' AND l.removed = 0 AND l.object_owner IN (@org_sql, 0x00)
				  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
				ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
			) tr
			WHERE a.object_owner IN (0x00, @org_sql) AND a.record_type = 'A' AND a.removed = 0
			  AND (@ref_table <> @storage_table OR @curr_guid IS NULL OR a.original <> @curr_guid)
			ORDER BY a.class_name;
			RETURN;
		END

		IF @ref_table = 'meta_object'
		BEGIN
			SELECT a.original, a.builtin_code AS code_col, COALESCE(tr.caption, a.caption, '') AS caption
			FROM meta_object a
			OUTER APPLY (
				SELECT TOP 1 l.caption
				FROM meta_object l
				JOIN @fl fl ON fl.[language] = l.[language]
				WHERE l.original = a.original AND l.record_type = 'L' AND l.removed = 0 AND l.object_owner IN (@org_sql, 0x00)
				  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
				ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
			) tr
			WHERE a.object_owner = 0x00 AND a.record_type = 'A' AND a.removed = 0
			  AND (@param_code <> 'target_object' OR a.object_type = 'P')
			  AND (@ref_table <> @storage_table OR @curr_guid IS NULL OR a.original <> @curr_guid)
			ORDER BY a.object_type, a.builtin_code;
			RETURN;
		END

		IF @ref_table = 'meta_column'
		BEGIN
			SELECT a.original, a.column_name AS code_col, COALESCE(tr.caption, a.caption, '') AS caption
			FROM meta_column a
			OUTER APPLY (
				SELECT TOP 1 l.caption
				FROM meta_column l
				JOIN @fl fl ON fl.[language] = l.[language]
				WHERE l.original = a.original AND l.record_type = 'L' AND l.removed = 0 AND l.object_owner IN (@org_sql, 0x00)
				  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
				ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
			) tr
			WHERE a.object_owner = 0x00 AND a.record_type = 'A' AND a.removed = 0
			  AND (@ref_table <> @storage_table OR @curr_guid IS NULL OR a.original <> @curr_guid)
			ORDER BY a.column_name;
			RETURN;
		END

		IF @ref_table = 'meta_link_def'
		BEGIN
			SELECT a.original, a.link_code AS code_col,
				COALESCE(tr.caption_forward, a.caption_forward, a.link_code)
				+ CASE WHEN a.direction_type = 'R' THEN ' [R]' WHEN a.direction_type = 'S' THEN ' [S]' ELSE '' END AS caption
			FROM meta_link_def a
			OUTER APPLY (
				SELECT TOP 1 l.caption_forward
				FROM meta_link_def l
				JOIN @fl fl ON fl.[language] = l.[language]
				WHERE l.original = a.original AND l.record_type = 'L' AND l.removed = 0 AND l.object_owner IN (@org_sql, 0x00)
				  AND NULLIF(CAST(l.caption_forward AS VARCHAR(MAX)), '') IS NOT NULL
				ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
			) tr
			WHERE a.object_owner IN (0x00, @org_sql)
			  AND a.record_type = 'A'
			  AND a.removed = 0
			  AND a.inactive = 0
			  AND (@ref_table <> @storage_table OR @curr_guid IS NULL OR a.original <> @curr_guid)
			ORDER BY a.is_derived ASC, a.link_code ASC;
			RETURN;
		END

		-- Obecná cílová tabulka (hierarchy, scale, scale_value, organization, asset_class, asset, link_diagram...)
		DECLARE @ref_has_code bit = CASE WHEN COL_LENGTH(@ref_table, 'builtin_code') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @ref_has_login bit = CASE WHEN COL_LENGTH(@ref_table, 'login_name') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @ref_has_sort bit = CASE WHEN COL_LENGTH(@ref_table, 'sort_code') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @ref_has_thresh bit = CASE WHEN COL_LENGTH(@ref_table, 'threshold_value') IS NOT NULL THEN 1 ELSE 0 END;
		DECLARE @ref_code_sql nvarchar(100) = CASE
			WHEN @ref_has_code = 1 THEN N'a.builtin_code'
			WHEN @ref_has_login = 1 THEN N'a.login_name'
			ELSE N''''''
		END;
		DECLARE @ref_sort_sql nvarchar(200) = CASE
			WHEN @ref_has_sort = 1 THEN N'a.sort_code'
			WHEN @ref_has_thresh = 1 THEN N'RIGHT(''0000000000'' + CAST(CAST(a.threshold_value * 10000 AS bigint) AS varchar(20)), 10)'
			ELSE N''''''
		END;
		DECLARE @extra_ref_cond nvarchar(400) = CASE
			WHEN @ref_table = 'hierarchy' AND @param_code = 'hierarchy' THEN N'AND (a.is_leaf = 1 OR a.original = @p_cur_val)'
			WHEN @ref_table = 'asset_class' AND @param_code = 'primary_asset_class' THEN N'AND (a.is_leaf = 1 OR a.original = @p_cur_val)'
			WHEN @ref_table = 'asset' AND @ref_class_name LIKE 'asset[_]%' THEN
				N'AND (a.asset_archetype = ''' + UPPER(SUBSTRING(@ref_class_name, 7, 40)) + N''' OR a.original = @p_cur_val)'
			ELSE N''
		END;
		DECLARE @excl_self_cond nvarchar(200) = CASE
			WHEN @ref_table = @storage_table AND @curr_guid IS NOT NULL THEN N'AND a.original <> @p_curr'
			ELSE N''
		END;

		DECLARE @sql_ref nvarchar(max) = N'
		DECLARE @fl TABLE ([language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, fallback_order int NOT NULL);
		INSERT INTO @fl ([language], fallback_order) SELECT [language], fallback_order FROM dbo.f_language_list(@p_lang) WHERE fallback_order < 1000;

		SELECT r.original, r.code_col, COALESCE(tr.caption, r.caption, '''') AS caption
		FROM (
			SELECT a.original, ' + @ref_code_sql + N' AS code_col, ' + @ref_sort_sql + N' AS sort_code, a.caption,
				ROW_NUMBER() OVER (PARTITION BY a.original ORDER BY CASE WHEN a.object_owner = @p_org THEN 0 ELSE 1 END) AS rn
			FROM [' + @ref_table + N'] a
			WHERE (a.object_owner IN (@p_org, 0x00) OR a.object_owner = a.original)
			  AND a.record_type = ''A''
			  AND a.removed = 0
			  ' + @excl_self_cond + N'
			  ' + @extra_ref_cond + N'
		) r
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM [' + @ref_table + N'] l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = r.original
			  AND l.record_type = ''L''
			  AND l.removed = 0
			  AND (l.object_owner IN (@p_org, 0x00) OR l.object_owner = l.original)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '''') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @p_org THEN 0 ELSE 1 END ASC
		) tr
		WHERE r.rn = 1
		ORDER BY r.sort_code, caption, r.code_col;';

		EXEC sp_executesql
			@stmt = @sql_ref,
			@params = N'@p_org uniqueidentifier, @p_lang varchar(2), @p_curr uniqueidentifier, @p_cur_val uniqueidentifier',
			@p_org = @org_sql,
			@p_lang = @sess_lang,
			@p_curr = @curr_guid,
			@p_cur_val = @current_val;
	END
END
GO