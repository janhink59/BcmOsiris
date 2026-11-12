EXECUTE dropni 'p_sync_derived_links', 'P';
GO

/* =============================================================================
 * Verze:     2026-11-12 17:10
 * Soubor:    p_sync_derived_links.sql
 * Procedura: dbo.p_sync_derived_links
 * Účel:      1. Normalizuje ručně zadané vazby uložené pod zpětným vztahem ('R')
 *               na kanonický primární vztah ('P') s otočením
 *               from_object <-> to_object, link_weight <-> reverse_link_weight
 *               a link_def -> reverse_link_def.
 *            2. Zrcadlí exkluzivní stromové vazby parent_uuid do tabulky link
 *               pod primárním vztahem parent_to_child ('P', is_derived = 1).
 *            3. Provádí materializaci (a výmaz) zděděných vazeb v tabulce link
 *               pomocí sloupce ancestor_link.
 * Vazby:     - Čte a modifikuje tabulku link.
 *            - Čte tabulky meta_link_def, meta_class, meta_object, v_syscolumns
 *              a stromové tabulky asset, asset_class, threat, impact, scenario,
 *              countermeasure, hierarchy, hierarchy_item a organization_unit.
 *            - Využívá funkce dbo.f_generate_original a dbo.f_link_original.
 * ============================================================================= */
CREATE PROCEDURE dbo.p_sync_derived_links
	@root_link_original uniqueidentifier = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- 0a. Automatická normalizace vazeb uložených pod zpětným směrem ('R') na kanonický primární směr ('P'):
	--     Prohodí se from_object <-> to_object, link_weight <-> reverse_link_weight a link_def -> reverse_link_def.
	IF EXISTS (
		SELECT 1
		FROM link l
		JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.removed = 0
		WHERE l.record_type = 'A'
			AND l.removed = 0
			AND l.is_derived = 0
			AND mld.direction_type = 'R'
			AND mld.reverse_link_def IS NOT NULL
	)
	BEGIN
		-- Pokud již shodná primární vazba 'P' existuje, duplicitní 'R' řádek odstraníme
		DELETE l_rev
		FROM link l_rev
		JOIN meta_link_def mld ON mld.original = l_rev.link_def AND mld.record_type = 'A' AND mld.removed = 0
		JOIN link l_pri
			ON l_pri.object_owner = l_rev.object_owner
			AND l_pri.link_def = mld.reverse_link_def
			AND l_pri.from_object = l_rev.to_object
			AND l_pri.to_object = l_rev.from_object
			AND l_pri.ancestor_link = l_rev.ancestor_link
			AND l_pri.record_type = 'A'
			AND l_pri.removed = 0
		WHERE l_rev.record_type = 'A'
			AND l_rev.removed = 0
			AND l_rev.is_derived = 0
			AND mld.direction_type = 'R'
			AND mld.reverse_link_def IS NOT NULL;

		-- Převod zbývajících 'R' vazeb na 'P'
		UPDATE l
		SET l.link_def = mld.reverse_link_def,
			l.from_object = l.to_object,
			l.to_object = l.from_object,
			l.link_weight = l.reverse_link_weight,
			l.reverse_link_weight = l.link_weight,
			l.original = dbo.f_link_original(
				CAST(l.object_owner AS varchar(36)),
				CAST(mld.reverse_link_def AS varchar(36)),
				CAST(l.to_object AS varchar(36)),
				CAST(l.from_object AS varchar(36)),
				CAST(l.ancestor_link AS varchar(36))
			)
		FROM link l
		JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.removed = 0
		WHERE l.record_type = 'A'
			AND l.removed = 0
			AND l.is_derived = 0
			AND mld.direction_type = 'R'
			AND mld.reverse_link_def IS NOT NULL;
	END

	-- 0b. Zrcadlení exkluzivních vazeb parent_uuid ze stromových tabulek do tabulky link
	--     pod primárním vztahem parent_to_child ('P', from_object = parent_uuid, to_object = original, is_derived = 1)
	IF @root_link_original IS NULL
	BEGIN
		DECLARE @tree_tabs TABLE (tabname varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
		INSERT INTO @tree_tabs (tabname) VALUES
			('asset'), ('asset_class'), ('threat'), ('impact'),
			('scenario'), ('countermeasure'), ('hierarchy'), ('hierarchy_item'), ('organization_unit');

		DECLARE @tt varchar(80);
		DECLARE cur_tt CURSOR LOCAL FAST_FORWARD FOR
			SELECT tabname FROM @tree_tabs;

		OPEN cur_tt;
		FETCH NEXT FROM cur_tt INTO @tt;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF OBJECT_ID(@tt, 'U') IS NOT NULL AND COL_LENGTH(@tt, 'parent_uuid') IS NOT NULL
			BEGIN
				DECLARE @cls_tt uuid = dbo.f_generate_original('meta_class', '00000000-0000-0000-0000-000000000000', @tt, '');
				DECLARE @ld_ptc uuid = NULL;

				SELECT TOP 1 @ld_ptc = original
				FROM meta_link_def
				WHERE from_class = @cls_tt
					AND link_code = 'parent_to_child'
					AND direction_type = 'P'
					AND record_type = 'A'
					AND removed = 0;

				IF @ld_ptc IS NOT NULL
				BEGIN
					DECLARE @sql_sync_tree nvarchar(max) = N'
					DELETE l
					FROM link l
					LEFT JOIN [' + @tt + N'] t
						ON t.original = l.to_object
						AND t.parent_uuid = l.from_object
						AND t.object_owner = l.object_owner
						AND t.record_type = ''A''
						AND t.removed = 0
						AND t.inactive = 0
					WHERE l.link_def = @p_ld
						AND l.is_derived = 1
						AND l.diagram_uuid IS NULL
						AND t.uuid IS NULL;

					INSERT INTO link (
						uuid, object_owner, original, record_type, approval_status, [language],
						link_def, from_object, to_object, ancestor_link, is_derived,
						date_created, who_created, date_modified, who_modified
					)
					SELECT
						x.calc_orig, t.object_owner, x.calc_orig, ''A'', ''A'', t.[language],
						@p_ld, t.parent_uuid, t.original, 0x00, 1,
						t.date_created, t.who_created, t.date_modified, t.who_modified
					FROM [' + @tt + N'] t
					CROSS APPLY (
						SELECT dbo.f_link_original(
							CAST(t.object_owner AS varchar(36)),
							CAST(@p_ld AS varchar(36)),
							CAST(t.parent_uuid AS varchar(36)),
							CAST(t.original AS varchar(36)),
							CAST(CAST(0x00 AS uniqueidentifier) AS varchar(36))
						) AS calc_orig
					) x
					WHERE t.record_type = ''A''
						AND t.removed = 0
						AND t.inactive = 0
						AND t.parent_uuid IS NOT NULL
						AND t.parent_uuid <> 0x00
						AND NOT EXISTS (
							SELECT 1 FROM link ex
							WHERE ex.object_owner = t.object_owner
								AND ex.link_def = @p_ld
								AND ex.from_object = t.parent_uuid
								AND ex.to_object = t.original
								AND ex.ancestor_link = 0x00
								AND ex.record_type = ''A''
								AND ex.removed = 0
						);';

					EXEC sp_executesql @sql_sync_tree, N'@p_ld uniqueidentifier', @p_ld = @ld_ptc;
				END
			END

			FETCH NEXT FROM cur_tt INTO @tt;
		END

		CLOSE cur_tt;
		DEALLOCATE cur_tt;
	END

	-- 1. Odstranění osiřelých odvozených vazeb (s ancestor_link <> 0x00 a mimo vazby diagramů)
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
		AND d.diagram_uuid IS NULL
		AND (@root_link_original IS NULL OR d.ancestor_link = @root_link_original)
		AND r.uuid IS NULL;

	-- 2. Načtení aktivních kořenových vazeb ke zpracování dědění po hierarchii
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
		AND mld.is_exclusive_parent = 0
		AND mld.is_derived = 0
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
		AND r.is_derived = 0
		AND r.ancestor_link = 0x00
		AND r.diagram_uuid IS NULL
		AND (@root_link_original IS NULL OR r.original = @root_link_original);

	-- 3. Zpracování jednotlivých kořenových vazeb, u nichž alespoň jedna strana podporuje katalogovou hierarchii
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

		IF @f_par = 1 AND @f_tab NOT IN ('asset', 'organization_unit')
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

		IF @t_par = 1 AND @t_tab NOT IN ('asset', 'organization_unit')
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
			AND d.diagram_uuid IS NULL
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