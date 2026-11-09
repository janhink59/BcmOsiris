/* =============================================================================
 * Verze: 2026-11-09 18:30
 * Soubor: p_sync_derived_links.sql
 * Funkce:    dbo.f_is_hierarchy_node_locked
 * Procedury: dbo.p_sync_derived_links, dbo.p_split_hierarchy_node_to_folder
 * Účel:   1. Funkce f_is_hierarchy_node_locked ověří, zda je daný uzel hierarchie
 *            (nebo libovolný podřízený uzel v jeho podstromu) již navázán na jiné
 *            entity v tabulkách link, scenario, asset, scenario_assessment nebo
 *            countermeasure_implementation.
 *         2. Procedura p_sync_derived_links provádí materializaci (a výmaz)
 *            zděděných vazeb v tabulce link pomocí sloupce ancestor_link.
 *         3. Procedura p_split_hierarchy_node_to_folder automaticky rozčlení
 *            koncový uzel (is_leaf = 1) na vnitřní složku (is_leaf = 0): pokud
 *            jsou na uzel již navázány záznamy, založí pod ním nový koncový
 *            uzel s builtin_code '<parent>_oth' ('... – ostatní') a převede na
 *            něj stávající vazby a záznamy.
 * Vazby:  - Čte tabulky link, meta_link_def, meta_class, meta_object, asset_class,
 *           threat, impact, scenario, countermeasure, hierarchy, hierarchy_item,
 *           asset, scenario_assessment, countermeasure_implementation a v_syscolumns.
 *         - Využívá deterministické funkce dbo.f_generate_original a dbo.f_link_original.
 *         - Volána z entity_manager_ui.php, entity_manager_write.php,
 *           entity_manager_ssc.php a abstract_page_tree.php.
 * ============================================================================= */

EXECUTE dropni 'p_split_hierarchy_node_to_folder', 'P';
EXECUTE dropni 'p_sync_derived_links', 'P';
EXECUTE dropni 'f_is_hierarchy_node_locked', 'FN';
GO

/* =============================================================================
 * Funkce: dbo.f_is_hierarchy_node_locked
 * ============================================================================= */
CREATE FUNCTION dbo.f_is_hierarchy_node_locked(
	@table_name varchar(128),
	@node_original uniqueidentifier,
	@object_owner uniqueidentifier = 0x00
)
RETURNS bit
AS
BEGIN
	IF @node_original IS NULL OR @node_original = 0x00
		RETURN 0;

	DECLARE @subtree TABLE (original uniqueidentifier NOT NULL PRIMARY KEY);
	INSERT INTO @subtree (original) VALUES (@node_original);

	-- 1. Sběr podstromu a specifické relační kontroly podle tabulky
	IF @table_name = 'asset_class' AND OBJECT_ID('asset_class', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM asset_class c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END

		IF OBJECT_ID('scenario', 'U') IS NOT NULL
			IF EXISTS (SELECT 1 FROM scenario sc JOIN @subtree s ON s.original = sc.asset_class_uuid WHERE sc.record_type = 'A' AND sc.removed = 0)
				RETURN 1;

		IF OBJECT_ID('asset', 'U') IS NOT NULL
			IF EXISTS (SELECT 1 FROM asset a JOIN @subtree s ON s.original = a.primary_asset_class WHERE a.record_type = 'A' AND a.removed = 0)
				RETURN 1;
	END
	ELSE IF @table_name = 'threat' AND OBJECT_ID('threat', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM threat c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END

		IF OBJECT_ID('scenario', 'U') IS NOT NULL
			IF EXISTS (SELECT 1 FROM scenario sc JOIN @subtree s ON s.original = sc.threat_uuid WHERE sc.record_type = 'A' AND sc.removed = 0)
				RETURN 1;
	END
	ELSE IF @table_name = 'impact' AND OBJECT_ID('impact', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM impact c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END
	END
	ELSE IF @table_name = 'scenario' AND OBJECT_ID('scenario', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM scenario c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END

		IF OBJECT_ID('scenario_assessment', 'U') IS NOT NULL
			IF EXISTS (SELECT 1 FROM scenario_assessment sa JOIN @subtree s ON s.original = sa.scenario_uuid WHERE sa.record_type = 'A' AND sa.removed = 0)
				RETURN 1;
	END
	ELSE IF @table_name = 'countermeasure' AND OBJECT_ID('countermeasure', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM countermeasure c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END

		IF OBJECT_ID('countermeasure_implementation', 'U') IS NOT NULL
			IF EXISTS (SELECT 1 FROM countermeasure_implementation ci JOIN @subtree s ON s.original = ci.countermeasure_uuid WHERE ci.record_type = 'A' AND ci.removed = 0)
				RETURN 1;
	END
	ELSE IF @table_name = 'asset' AND OBJECT_ID('asset', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM asset c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END

		IF EXISTS (
			SELECT 1
			FROM asset a
			JOIN @subtree s
				ON s.original IN (a.building_uuid, a.room_uuid, a.host_uuid, a.software_uuid, a.supplier_uuid)
			WHERE a.record_type = 'A'
			  AND a.removed = 0
			  AND NOT EXISTS (SELECT 1 FROM @subtree self_s WHERE self_s.original = a.original)
		)
			RETURN 1;

		IF OBJECT_ID('scenario_assessment', 'U') IS NOT NULL
			IF EXISTS (SELECT 1 FROM scenario_assessment sa JOIN @subtree s ON s.original = sa.asset_uuid WHERE sa.record_type = 'A' AND sa.removed = 0)
				RETURN 1;

		IF OBJECT_ID('countermeasure_implementation', 'U') IS NOT NULL
			IF EXISTS (SELECT 1 FROM countermeasure_implementation ci JOIN @subtree s ON s.original = ci.asset_uuid WHERE ci.record_type = 'A' AND ci.removed = 0)
				RETURN 1;
	END
	ELSE IF @table_name = 'hierarchy' AND OBJECT_ID('hierarchy', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM hierarchy c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END

		IF OBJECT_ID('hierarchy_item', 'U') IS NOT NULL
			IF EXISTS (
				SELECT 1
				FROM hierarchy_item hi
				JOIN @subtree s ON s.original = hi.hierarchy
				JOIN link l ON (l.from_object = hi.original OR l.to_object = hi.original)
				WHERE hi.record_type = 'A' AND hi.removed = 0 AND l.record_type = 'A' AND l.removed = 0
			)
				RETURN 1;
	END
	ELSE IF @table_name = 'hierarchy_item' AND OBJECT_ID('hierarchy_item', 'U') IS NOT NULL
	BEGIN
		WHILE @@ROWCOUNT > 0
		BEGIN
			INSERT INTO @subtree (original)
			SELECT DISTINCT c.original
			FROM hierarchy_item c
			JOIN @subtree s ON c.parent_uuid = s.original
			WHERE c.record_type = 'A' AND c.removed = 0 AND c.object_owner IN (0x00, @object_owner)
			  AND NOT EXISTS (SELECT 1 FROM @subtree ex WHERE ex.original = c.original);
		END
	END

	-- 2. Společná kontrola platných vazeb v tabulce link na libovolný uzel podstromu
	IF EXISTS (
		SELECT 1
		FROM link l
		JOIN @subtree s ON s.original = l.from_object OR s.original = l.to_object
		WHERE l.record_type = 'A'
		  AND l.removed = 0
	)
		RETURN 1;

	RETURN 0;
END
GO

/* =============================================================================
 * Procedura: dbo.p_sync_derived_links
 * ============================================================================= */
CREATE PROCEDURE dbo.p_sync_derived_links
	@root_link_original uniqueidentifier = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- 1. Odstranění osiřelých odvozených vazeb, jejichž kořenová vazba již neexistuje nebo je zrušená/neaktivní
	DELETE d
	FROM link d
	LEFT JOIN link r
		ON r.original = d.ancestor_link
		AND r.object_owner = d.object_owner
		AND r.record_type = 'A'
		AND r.removed = 0
		AND r.inactive = 0
		AND r.ancestor_link = 0x00
	WHERE d.ancestor_link <> 0x00
	  AND (@root_link_original IS NULL OR d.ancestor_link = @root_link_original)
	  AND r.uuid IS NULL;

	-- 2. Načtení aktivních kořenových vazeb ke zpracování
	DECLARE @roots TABLE (
		root_orig uniqueidentifier NOT NULL,
		root_owner uniqueidentifier NOT NULL,
		link_def uniqueidentifier NOT NULL,
		from_obj uniqueidentifier NOT NULL,
		to_obj uniqueidentifier NOT NULL,
		link_weight decimal(16,4) NULL,
		note varchar(max) COLLATE DATABASE_DEFAULT NOT NULL,
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL,
		who_modified uniqueidentifier NOT NULL,
		from_table varchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
		to_table varchar(128) COLLATE DATABASE_DEFAULT NOT NULL,
		from_has_parent bit NOT NULL,
		to_has_parent bit NOT NULL,
		PRIMARY KEY (root_orig, root_owner)
	);

	INSERT INTO @roots (
		root_orig, root_owner, link_def, from_obj, to_obj,
		link_weight, note, [language], who_modified,
		from_table, to_table, from_has_parent, to_has_parent
	)
	SELECT
		r.original,
		r.object_owner,
		r.link_def,
		r.from_object,
		r.to_object,
		r.link_weight,
		r.note,
		r.[language],
		r.who_modified,
		mo_from.builtin_code,
		mo_to.builtin_code,
		CASE WHEN EXISTS (SELECT 1 FROM v_syscolumns sc WHERE sc.tabname = mo_from.builtin_code COLLATE DATABASE_DEFAULT AND sc.colname = 'parent_uuid') THEN 1 ELSE 0 END,
		CASE WHEN EXISTS (SELECT 1 FROM v_syscolumns sc WHERE sc.tabname = mo_to.builtin_code COLLATE DATABASE_DEFAULT AND sc.colname = 'parent_uuid') THEN 1 ELSE 0 END
	FROM link r
	JOIN meta_link_def mld
		ON mld.original = r.link_def
		AND mld.record_type = 'A'
		AND mld.removed = 0
		AND mld.object_owner IN (0x00, r.object_owner)
	JOIN meta_class mc_from
		ON mc_from.original = mld.from_class
		AND mc_from.record_type = 'A'
		AND mc_from.removed = 0
		AND mc_from.object_owner IN (0x00, r.object_owner)
	JOIN meta_object mo_from
		ON mo_from.original = mc_from.storage_object
		AND mo_from.record_type = 'A'
		AND mo_from.removed = 0
		AND mo_from.object_type = 'T'
	JOIN meta_class mc_to
		ON mc_to.original = mld.to_class
		AND mc_to.record_type = 'A'
		AND mc_to.removed = 0
		AND mc_to.object_owner IN (0x00, r.object_owner)
	JOIN meta_object mo_to
		ON mo_to.original = mc_to.storage_object
		AND mo_to.record_type = 'A'
		AND mo_to.removed = 0
		AND mo_to.object_type = 'T'
	WHERE r.record_type = 'A'
	  AND r.removed = 0
	  AND r.inactive = 0
	  AND r.ancestor_link = 0x00
	  AND (@root_link_original IS NULL OR r.original = @root_link_original);

	-- 3. Zpracování jednotlivých kořenových vazeb, u nichž alespoň jedna strana podporuje hierarchii (parent_uuid)
	DECLARE @r_orig uniqueidentifier, @r_owner uniqueidentifier, @r_def uniqueidentifier;
	DECLARE @f_obj uniqueidentifier, @t_obj uniqueidentifier;
	DECLARE @w decimal(16,4), @nt varchar(max), @lng varchar(2), @who uniqueidentifier;
	DECLARE @f_tab varchar(128), @t_tab varchar(128), @f_par bit, @t_par bit;

	DECLARE cur_roots CURSOR LOCAL FAST_FORWARD FOR
		SELECT
			root_orig, root_owner, link_def, from_obj, to_obj,
			link_weight, note, [language], who_modified,
			from_table, to_table, from_has_parent, to_has_parent
		FROM @roots
		WHERE from_has_parent = 1 OR to_has_parent = 1;

	OPEN cur_roots;
	FETCH NEXT FROM cur_roots INTO
		@r_orig, @r_owner, @r_def, @f_obj, @t_obj,
		@w, @nt, @lng, @who,
		@f_tab, @t_tab, @f_par, @t_par;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF OBJECT_ID('tempdb..#desc_from') IS NOT NULL DROP TABLE #desc_from;
		IF OBJECT_ID('tempdb..#desc_to') IS NOT NULL DROP TABLE #desc_to;

		CREATE TABLE #desc_from (original uniqueidentifier NOT NULL PRIMARY KEY);
		CREATE TABLE #desc_to (original uniqueidentifier NOT NULL PRIMARY KEY);

		INSERT INTO #desc_from (original) VALUES (@f_obj);
		INSERT INTO #desc_to (original) VALUES (@t_obj);

		IF @f_par = 1 AND @f_tab <> 'asset'
		BEGIN
			DECLARE @sql_f nvarchar(max) = N'
			WHILE @@ROWCOUNT > 0
			BEGIN
				INSERT INTO #desc_from (original)
				SELECT DISTINCT c.original
				FROM [' + @f_tab + N'] c
				JOIN #desc_from d ON c.parent_uuid = d.original
				WHERE c.record_type = ''A''
				  AND c.removed = 0
				  AND c.inactive = 0
				  AND c.object_owner IN (0x00, @p_owner)
				  AND NOT EXISTS (SELECT 1 FROM #desc_from ex WHERE ex.original = c.original);
			END';
			EXEC sp_executesql @sql_f, N'@p_owner uniqueidentifier', @p_owner = @r_owner;
		END

		IF @t_par = 1 AND @t_tab <> 'asset'
		BEGIN
			DECLARE @sql_t nvarchar(max) = N'
			WHILE @@ROWCOUNT > 0
			BEGIN
				INSERT INTO #desc_to (original)
				SELECT DISTINCT c.original
				FROM [' + @t_tab + N'] c
				JOIN #desc_to d ON c.parent_uuid = d.original
				WHERE c.record_type = ''A''
				  AND c.removed = 0
				  AND c.inactive = 0
				  AND c.object_owner IN (0x00, @p_owner)
				  AND NOT EXISTS (SELECT 1 FROM #desc_to ex WHERE ex.original = c.original);
			END';
			EXEC sp_executesql @sql_t, N'@p_owner uniqueidentifier', @p_owner = @r_owner;
		END

		DELETE d
		FROM link d
		WHERE d.ancestor_link = @r_orig
		  AND d.object_owner = @r_owner
		  AND NOT EXISTS (
			SELECT 1
			FROM #desc_from df
			CROSS JOIN #desc_to dt
			WHERE df.original = d.from_object
			  AND dt.original = d.to_object
			  AND NOT (df.original = @f_obj AND dt.original = @t_obj)
		  );

		INSERT INTO link (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_def, from_object, to_object, ancestor_link,
			link_weight, note, is_derived,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.calc_orig, @r_owner, x.calc_orig, 'A', 'A', @lng,
			@r_def, df.original, dt.original, @r_orig,
			@w, @nt, 1,
			GETDATE(), @who, GETDATE(), @who
		FROM #desc_from df
		CROSS JOIN #desc_to dt
		CROSS APPLY (
			SELECT dbo.f_link_original(
				CAST(@r_owner AS varchar(36)),
				CAST(@r_def AS varchar(36)),
				CAST(df.original AS varchar(36)),
				CAST(dt.original AS varchar(36)),
				CAST(@r_orig AS varchar(36))
			) AS calc_orig
		) x
		WHERE NOT (df.original = @f_obj AND dt.original = @t_obj)
		  AND NOT EXISTS (
			SELECT 1 FROM link ex
			WHERE ex.object_owner = @r_owner
			  AND ex.link_def = @r_def
			  AND ex.from_object = df.original
			  AND ex.to_object = dt.original
			  AND ex.ancestor_link = @r_orig
			  AND ex.record_type = 'A'
			  AND ex.removed = 0
		  );

		DROP TABLE #desc_from;
		DROP TABLE #desc_to;

		FETCH NEXT FROM cur_roots INTO
			@r_orig, @r_owner, @r_def, @f_obj, @t_obj,
			@w, @nt, @lng, @who,
			@f_tab, @t_tab, @f_par, @t_par;
	END

	CLOSE cur_roots;
	DEALLOCATE cur_roots;
END
GO

/* =============================================================================
 * Procedura: dbo.p_split_hierarchy_node_to_folder
 * Účel: Automaticky rozčlení koncový uzel hierarchie (is_leaf = 1) na vnitřní
 *       složku (is_leaf = 0). Pokud jsou na tento uzel již navázány záznamy
 *       vyžadující koncový list, založí pod ním nový koncový uzel s příponou
 *       '_oth' (v názvu ' – ostatní' / ' – other') a stávající záznamy na něj
 *       automaticky převede.
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

	-- 1. Zjištění stavu uzlu a jeho klíčového kódu
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

	-- Pokud uzel neexistuje nebo již je složkou (is_leaf = 0), není co dělit
	IF @base_code = '' OR @is_leaf = 0
		RETURN;

	DECLARE @is_locked bit = dbo.f_is_hierarchy_node_locked(@table_name, @node_original, @org_uuid);

	-- 2. Pokud je uzel již navázán na záznamy, vytvoříme podřízený záchytný uzel '<builtin_code>_oth' ('... – ostatní')
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

		-- Sestavení seznamu dalších datových sloupců ke zkopírování z rodiče na uzel _oth
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

		-- Vložení záznamu 'A' a jazykových záznamů 'L' pro nový uzel '_oth'
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
			UPDATE asset SET building_uuid = @new_oth_original WHERE building_uuid = @node_original AND object_owner IN (@org_uuid, 0x00) AND original <> @new_oth_original;
			UPDATE asset SET room_uuid = @new_oth_original WHERE room_uuid = @node_original AND object_owner IN (@org_uuid, 0x00) AND original <> @new_oth_original;
			UPDATE asset SET host_uuid = @new_oth_original WHERE host_uuid = @node_original AND object_owner IN (@org_uuid, 0x00) AND original <> @new_oth_original;
			UPDATE asset SET software_uuid = @new_oth_original WHERE software_uuid = @node_original AND object_owner IN (@org_uuid, 0x00) AND original <> @new_oth_original;
			UPDATE asset SET supplier_uuid = @new_oth_original WHERE supplier_uuid = @node_original AND object_owner IN (@org_uuid, 0x00) AND original <> @new_oth_original;

			IF OBJECT_ID('scenario_assessment', 'U') IS NOT NULL
				UPDATE scenario_assessment SET asset_uuid = @new_oth_original WHERE asset_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
			IF OBJECT_ID('countermeasure_implementation', 'U') IS NOT NULL
				UPDATE countermeasure_implementation SET asset_uuid = @new_oth_original WHERE asset_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
		END

		-- Přesměrování přímých vazeb v tabulce link (kde je cíl/zdroj vázán na koncový list)
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
			  AND l.object_owner IN (@org_uuid, 0x00)
			  AND (mld.leaf_only = 1 OR @table_name = 'asset');

			UPDATE l
			SET l.from_object = @new_oth_original,
				l.original = dbo.f_link_original(CAST(l.object_owner AS varchar(36)), CAST(l.link_def AS varchar(36)), CAST(@new_oth_original AS varchar(36)), CAST(l.to_object AS varchar(36)), CAST(l.ancestor_link AS varchar(36))),
				l.date_modified = GETDATE(),
				l.who_modified = @user_session
			FROM link l
			WHERE l.from_object = @node_original
			  AND l.ancestor_link = 0x00
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