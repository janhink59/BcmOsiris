/* =============================================================================
 * Verze: 2026-11-09 16:30
 * Soubor: p_sync_derived_links.sql
 * Funkce:    dbo.f_is_hierarchy_node_locked
 * Procedura: dbo.p_sync_derived_links
 * Účel:   1. Funkce f_is_hierarchy_node_locked ověří, zda je daný uzel hierarchie
 *            (nebo libovolný podřízený uzel v jeho podstromu) již navázán na jiné
 *            entity v tabulkách link, scenario, asset, scenario_assessment nebo
 *            countermeasure_implementation, což uzamyká uzel proti přepodřízení
 *            (změně parent_uuid), změně is_leaf z 1 na 0 nebo smazání.
 *         2. Procedura p_sync_derived_links provádí materializaci (a výmaz)
 *            zděděných vazeb v tabulce link pomocí sloupce ancestor_link.
 * Vazby:  - Čte tabulky link, meta_link_def, meta_class, meta_object, asset_class,
 *           threat, impact, scenario, countermeasure, hierarchy, hierarchy_item,
 *           asset, scenario_assessment, countermeasure_implementation a v_syscolumns.
 *         - Využívá deterministickou funkci dbo.f_link_original.
 *         - Volána z entity_manager_ui.php a entity_manager_ssc.php.
 * Změny:  - 2026-11-09 16:30: Do funkce dbo.f_is_hierarchy_node_locked doplněn
 *           průchod podstromem pro tabulku asset a kontrola vazeb v tabulkách
 *           asset (primary_asset_class, building_uuid, room_uuid, host_uuid,
 *           software_uuid, supplier_uuid), scenario_assessment (asset_uuid,
 *           scenario_uuid) a countermeasure_implementation (asset_uuid,
 *           countermeasure_uuid).
 * ============================================================================= */

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