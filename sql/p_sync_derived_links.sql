/* =============================================================================
 * Verze: 2026-11-11 21:30
 * Soubor: p_sync_derived_links.sql
 * Funkce:    dbo.f_is_hierarchy_node_locked
 * Procedury: dbo.p_sync_derived_links, dbo.p_rebuild_link_diagram,
 *            dbo.p_split_hierarchy_node_to_folder
 * Účel:   1. Funkce f_is_hierarchy_node_locked ověří, zda je daný uzel hierarchie
 *            (nebo libovolný podřízený uzel v jeho podstromu) již navázán na jiné
 *            entity v tabulkách link, scenario, asset, scenario_assessment nebo
 *            countermeasure_implementation.
 *         2. Procedura p_sync_derived_links automaticky zrcadlí exkluzivní
 *            stromové vazby parent_uuid do tabulky link (is_derived = 1) a
 *            provádí materializaci zděděných vazeb přes ancestor_link.
 *         3. Procedura p_rebuild_link_diagram vyhodnotí pomocí funkce
 *            dbo.f_resolve_link_diagram cesty v heterogenní síti diagramu
 *            (link_diagram) a projektuje nepřímé vztahy do meta_link_def
 *            (is_derived = 1, diagram_uuid) a nepřímé vazby uzlů do tabulky
 *            link (is_derived = 1, diagram_uuid).
 *         4. Procedura p_split_hierarchy_node_to_folder automaticky rozčlení
 *            koncový uzel (is_leaf = 1) na vnitřní složku (is_leaf = 0) a
 *            založí podřízený uzel '<parent>_oth' ('... – ostatní').
 * ============================================================================= */

EXECUTE dropni 'p_split_hierarchy_node_to_folder', 'P';
EXECUTE dropni 'p_rebuild_link_diagram', 'P';
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
				LEFT JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.removed = 0
				WHERE hi.record_type = 'A' AND hi.removed = 0 AND l.record_type = 'A' AND l.removed = 0
				  AND ISNULL(mld.is_exclusive_parent, 0) = 0
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
	--    (Ignorujeme zrcadlené vazby parent_uuid s is_exclusive_parent = 1 a odvozené projekce diagramů)
	IF EXISTS (
		SELECT 1
		FROM link l
		JOIN @subtree s ON s.original = l.from_object OR s.original = l.to_object
		LEFT JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.removed = 0
		WHERE l.record_type = 'A'
		  AND l.removed = 0
		  AND l.diagram_uuid IS NULL
		  AND ISNULL(mld.is_exclusive_parent, 0) = 0
	)
		RETURN 1;

	RETURN 0;
END
GO

/* =============================================================================
 * Procedura: dbo.p_rebuild_link_diagram
 * Účel: Vyhodnotí orientované vztahy zařazené do diagramu (link_diagram) pomocí
 *       funkce dbo.f_resolve_link_diagram:
 *       1. Pro každou dosažitelnou dvojici tříd (from_class -> ... -> to_class)
 *          v diagramu vygeneruje/zaktualizuje odvozený vztah v meta_link_def
 *          (is_derived = 1, diagram_uuid = @diag).
 *       2. Pro každou acyklickou cestu mezi konkrétními objekty (uzly) v síti
 *          diagramu vygeneruje/zaktualizuje odvozenou vazbu v tabulce link
 *          (is_derived = 1, diagram_uuid = @diag).
 * ============================================================================= */
CREATE PROCEDURE dbo.p_rebuild_link_diagram
	@diagram_uuid uniqueidentifier = NULL,
	@org_uuid uniqueidentifier = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF OBJECT_ID('link_diagram', 'U') IS NULL
	   OR OBJECT_ID('meta_link_def', 'U') IS NULL
	   OR OBJECT_ID('link', 'U') IS NULL
	   OR OBJECT_ID('dbo.f_resolve_link_diagram', 'TF') IS NULL
		RETURN;

	IF @org_uuid IS NULL
	BEGIN
		SELECT TOP 1 @org_uuid = ISNULL(organization, 0x00)
		FROM dbsession
		WHERE spid = @@SPID;
	END
	SET @org_uuid = ISNULL(@org_uuid, 0x00);

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @mld_diag_inc uniqueidentifier = dbo.f_generate_original('meta_link_def', @sys_owner, 'diagram_includes_link_def', '');

	-- 1. Odstranění odvozených záznamů pro smazané nebo neaktivní diagramy
	DELETE l
	FROM link l
	LEFT JOIN link_diagram d
		ON d.original = l.diagram_uuid
		AND d.record_type = 'A'
		AND d.removed = 0
		AND d.inactive = 0
	WHERE l.diagram_uuid IS NOT NULL
	  AND l.is_derived = 1
	  AND (@diagram_uuid IS NULL OR l.diagram_uuid = @diagram_uuid)
	  AND d.uuid IS NULL;

	DELETE mld
	FROM meta_link_def mld
	LEFT JOIN link_diagram d
		ON d.original = mld.diagram_uuid
		AND d.record_type = 'A'
		AND d.removed = 0
		AND d.inactive = 0
	WHERE mld.diagram_uuid IS NOT NULL
	  AND mld.is_derived = 1
	  AND (@diagram_uuid IS NULL OR mld.diagram_uuid = @diagram_uuid)
	  AND d.uuid IS NULL;

	-- 2. Seznam aktivních diagramů ke zpracování
	DECLARE @diags TABLE (
		diag_orig uniqueidentifier NOT NULL PRIMARY KEY,
		diag_owner uniqueidentifier NOT NULL,
		diag_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		diag_caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @diags (diag_orig, diag_owner, diag_code, diag_caption, [language])
	SELECT original, object_owner, builtin_code, caption, [language]
	FROM (
		SELECT d.original, d.object_owner, d.builtin_code, d.caption, d.[language],
			ROW_NUMBER() OVER (PARTITION BY d.original ORDER BY CASE WHEN d.object_owner = @org_uuid THEN 0 ELSE 1 END) AS rn
		FROM link_diagram d
		WHERE d.object_owner IN (@org_uuid, 0x00)
		  AND d.record_type = 'A'
		  AND d.removed = 0
		  AND d.inactive = 0
		  AND (@diagram_uuid IS NULL OR d.original = @diagram_uuid)
	) x
	WHERE x.rn = 1;

	DECLARE @d_orig uniqueidentifier, @d_owner uniqueidentifier, @d_code varchar(80), @d_cap varchar(200), @d_lang varchar(2);

	DECLARE cur_diag CURSOR LOCAL FAST_FORWARD FOR
		SELECT diag_orig, diag_owner, diag_code, diag_caption, [language]
		FROM @diags;

	OPEN cur_diag;
	FETCH NEXT FROM cur_diag INTO @d_orig, @d_owner, @d_code, @d_cap, @d_lang;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- A. Načtení základních vztahů (meta_link_def) zařazených do tohoto diagramu
		DECLARE @inc_defs TABLE (
			mld_orig uniqueidentifier NOT NULL PRIMARY KEY,
			from_class uniqueidentifier NOT NULL,
			to_class uniqueidentifier NOT NULL,
			direction_type varchar(1) COLLATE DATABASE_DEFAULT NOT NULL,
			reverse_link_def uniqueidentifier NULL,
			edge_weight decimal(9,4) NOT NULL
		);
		DELETE FROM @inc_defs;

		INSERT INTO @inc_defs (mld_orig, from_class, to_class, direction_type, reverse_link_def, edge_weight)
		SELECT
			mld.original,
			mld.from_class,
			mld.to_class,
			ISNULL(NULLIF(mld.direction_type, ''), 'P'),
			mld.reverse_link_def,
			CASE WHEN ISNULL(l.link_weight, 0) > 0 AND l.link_weight <= 100 THEN CAST(l.link_weight AS decimal(9,4)) ELSE 100.0000 END
		FROM link l
		JOIN meta_link_def mld
			ON mld.original = l.to_object
			AND mld.record_type = 'A'
			AND mld.removed = 0
			AND mld.inactive = 0
			AND mld.is_derived = 0
		WHERE l.link_def = @mld_diag_inc
		  AND l.from_object = @d_orig
		  AND l.object_owner IN (@d_owner, @org_uuid, 0x00)
		  AND l.record_type = 'A'
		  AND l.removed = 0
		  AND l.inactive = 0;

		-- B. Sestavení metagrafu tříd v diagramu přes dbo.f_resolve_link_diagram
		DECLARE @cls_in tt_resolve_link_diagram;
		DELETE FROM @cls_in;

		INSERT INTO @cls_in (node_id, from_id, sort_order)
		SELECT DISTINCT LOWER(CAST(c_uuid AS varchar(36))), '', LOWER(CAST(c_uuid AS varchar(36)))
		FROM (
			SELECT from_class AS c_uuid FROM @inc_defs
			UNION
			SELECT to_class AS c_uuid FROM @inc_defs
		) u;

		INSERT INTO @cls_in (node_id, from_id, sort_order)
		SELECT DISTINCT
			LOWER(CAST(to_class AS varchar(36))),
			LOWER(CAST(from_class AS varchar(36))),
			LOWER(CAST(to_class AS varchar(36)))
		FROM @inc_defs
		WHERE from_class <> to_class;

		-- C. Dosažitelné dvojice tříd v diagramu (včetně vnitrotřídních self-referencing cest)
		DECLARE @cls_pairs TABLE (
			from_class uniqueidentifier NOT NULL,
			to_class uniqueidentifier NOT NULL,
			derived_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
			derived_orig uniqueidentifier NOT NULL,
			caption_cs varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			PRIMARY KEY (from_class, to_class)
		);
		DELETE FROM @cls_pairs;

		INSERT INTO @cls_pairs (from_class, to_class, derived_code, derived_orig, caption_cs)
		SELECT
			p.fc_uuid,
			p.tc_uuid,
			v.d_code,
			dbo.f_generate_original('meta_link_def', @d_owner, v.d_code, ''),
			LEFT('[' + @d_code + '] ' + ISNULL(mc_f.caption, mc_f.class_name) + ' -> ' + ISNULL(mc_t.caption, mc_t.class_name), 200)
		FROM (
			SELECT DISTINCT
				TRY_CONVERT(uniqueidentifier, root_id) AS fc_uuid,
				TRY_CONVERT(uniqueidentifier, node_id) AS tc_uuid
			FROM dbo.f_resolve_link_diagram(@cls_in)
			WHERE level >= 1 AND bad = 0
			UNION
			SELECT DISTINCT from_class, to_class
			FROM @inc_defs
		) p
		JOIN meta_class mc_f ON mc_f.original = p.fc_uuid AND mc_f.record_type = 'A' AND mc_f.removed = 0 AND mc_f.object_owner IN (0x00, @d_owner)
		JOIN meta_class mc_t ON mc_t.original = p.tc_uuid AND mc_t.record_type = 'A' AND mc_t.removed = 0 AND mc_t.object_owner IN (0x00, @d_owner)
		CROSS APPLY (
			SELECT LOWER(LEFT('dg_' + @d_code + '_' + mc_f.class_name + '_' + mc_t.class_name, 80)) AS d_code
		) v
		WHERE p.fc_uuid IS NOT NULL AND p.tc_uuid IS NOT NULL;

		-- Odstranění neplatných odvozených vztahů diagramu z meta_link_def
		DELETE mld
		FROM meta_link_def mld
		WHERE mld.diagram_uuid = @d_orig
		  AND mld.is_derived = 1
		  AND NOT EXISTS (SELECT 1 FROM @cls_pairs cp WHERE cp.derived_orig = mld.original);

		-- Vložení/aktualizace odvozených vztahů diagramu v meta_link_def (A + symetrické L)
		INSERT INTO meta_link_def (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_code, from_class, to_class, direction_type,
			caption_forward, caption_backward,
			is_multiple, is_mandatory, leaf_only, link_weight_enabled,
			is_derived, diagram_uuid, is_final, is_protected
		)
		SELECT
			cp.derived_orig, @d_owner, cp.derived_orig, 'A', 'A', @d_lang,
			cp.derived_code, cp.from_class, cp.to_class, 'P',
			cp.caption_cs, cp.caption_cs,
			1, 0, 0, 1,
			1, @d_orig, 1, 1
		FROM @cls_pairs cp
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_link_def ex
			WHERE ex.original = cp.derived_orig AND ex.object_owner = @d_owner AND ex.record_type = 'A'
		);

		INSERT INTO meta_link_def (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_code, from_class, to_class, direction_type,
			caption_forward, caption_backward,
			is_multiple, is_mandatory, leaf_only, link_weight_enabled,
			is_derived, diagram_uuid, is_final, is_protected
		)
		SELECT
			NEWID(), @d_owner, cp.derived_orig, 'L', 'A', @d_lang,
			cp.derived_code, cp.from_class, cp.to_class, 'P',
			cp.caption_cs, cp.caption_cs,
			1, 0, 0, 1,
			1, @d_orig, 1, 1
		FROM @cls_pairs cp
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_link_def ex
			WHERE ex.original = cp.derived_orig AND ex.object_owner = @d_owner AND ex.record_type = 'L' AND ex.[language] = @d_lang
		);

		-- D. Sestavení sítě konkrétních objektů (uzlů) po všech spojnicích diagramu
		DECLARE @edges TABLE (
			from_obj uniqueidentifier NOT NULL,
			to_obj uniqueidentifier NOT NULL,
			PRIMARY KEY (from_obj, to_obj)
		);
		DELETE FROM @edges;

		INSERT INTO @edges (from_obj, to_obj)
		SELECT DISTINCT src.from_obj, src.to_obj
		FROM (
			-- 1. Přímé a symetrické vazby uložené pod mld_orig
			SELECT l.from_object AS from_obj, l.to_object AS to_obj
			FROM @inc_defs idf
			JOIN link l
				ON l.link_def = idf.mld_orig
				AND l.object_owner IN (@org_uuid, @d_owner, 0x00)
				AND l.record_type = 'A'
				AND l.removed = 0
				AND l.inactive = 0
				AND l.diagram_uuid IS NULL
			WHERE idf.direction_type IN ('P', 'S', 'R')

			UNION

			-- 2. Zpětné vztahy ('R') a opačný směr symetrických vztahů ('S') čtené z kanonického záznamu v link
			SELECT l.to_object AS from_obj, l.from_object AS to_obj
			FROM @inc_defs idf
			JOIN link l
				ON (
					(idf.direction_type = 'R' AND l.link_def = idf.reverse_link_def)
					OR (idf.direction_type = 'S' AND l.link_def = idf.mld_orig)
				)
				AND l.object_owner IN (@org_uuid, @d_owner, 0x00)
				AND l.record_type = 'A'
				AND l.removed = 0
				AND l.inactive = 0
				AND l.diagram_uuid IS NULL
		) src
		WHERE src.from_obj <> src.to_obj;

		DECLARE @obj_in tt_resolve_link_diagram;
		DELETE FROM @obj_in;

		INSERT INTO @obj_in (node_id, from_id, sort_order)
		SELECT DISTINCT LOWER(CAST(o_uuid AS varchar(36))), '', LOWER(CAST(o_uuid AS varchar(36)))
		FROM (
			SELECT from_obj AS o_uuid FROM @edges
			UNION
			SELECT to_obj AS o_uuid FROM @edges
		) u;

		INSERT INTO @obj_in (node_id, from_id, sort_order)
		SELECT
			LOWER(CAST(to_obj AS varchar(36))),
			LOWER(CAST(from_obj AS varchar(36))),
			LOWER(CAST(to_obj AS varchar(36)))
		FROM @edges;

		-- E. Zjištění třídy každého zapojeného objektu pro spárování s @cls_pairs
		DECLARE @obj_class TABLE (
			obj_orig uniqueidentifier NOT NULL PRIMARY KEY,
			cls_orig uniqueidentifier NOT NULL
		);
		DELETE FROM @obj_class;

		INSERT INTO @obj_class (obj_orig, cls_orig)
		SELECT a.original, dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'asset_' + LOWER(a.asset_archetype), '')
		FROM asset a
		WHERE a.object_owner IN (@org_uuid, 0x00) AND a.record_type = 'A' AND a.removed = 0
		  AND EXISTS (SELECT 1 FROM @obj_in oi WHERE oi.from_id = '' AND oi.node_id = LOWER(CAST(a.original AS varchar(36))));

		INSERT INTO @obj_class (obj_orig, cls_orig)
		SELECT ou.original, dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'organization_unit', '')
		FROM organization_unit ou
		WHERE ou.object_owner IN (@org_uuid, 0x00) AND ou.record_type = 'A' AND ou.removed = 0
		  AND NOT EXISTS (SELECT 1 FROM @obj_class ex WHERE ex.obj_orig = ou.original)
		  AND EXISTS (SELECT 1 FROM @obj_in oi WHERE oi.from_id = '' AND oi.node_id = LOWER(CAST(ou.original AS varchar(36))));

		-- F. Projekce vyřešených cest z f_resolve_link_diagram do tabulky link (is_derived = 1, diagram_uuid = @d_orig)
		DELETE FROM link
		WHERE diagram_uuid = @d_orig
		  AND object_owner = @org_uuid
		  AND is_derived = 1;

		INSERT INTO link (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_def, from_object, to_object, ancestor_link, diagram_uuid,
			link_weight, note, is_derived
		)
		SELECT
			x.calc_orig, @org_uuid, x.calc_orig, 'A', 'A', @d_lang,
			cp.derived_orig, paths.f_obj, paths.t_obj, @d_orig, @d_orig,
			CAST(paths.min_lvl AS decimal(16,4)), '', 1
		FROM (
			SELECT
				TRY_CONVERT(uniqueidentifier, r.root_id) AS f_obj,
				TRY_CONVERT(uniqueidentifier, r.node_id) AS t_obj,
				MIN(r.level) AS min_lvl
			FROM dbo.f_resolve_link_diagram(@obj_in) r
			WHERE r.level >= 1
			  AND r.bad = 0
			GROUP BY r.root_id, r.node_id
		) paths
		JOIN @obj_class oc_f ON oc_f.obj_orig = paths.f_obj
		JOIN @obj_class oc_t ON oc_t.obj_orig = paths.t_obj
		JOIN @cls_pairs cp ON cp.from_class = oc_f.cls_orig AND cp.to_class = oc_t.cls_orig
		CROSS APPLY (
			SELECT dbo.f_link_original(
				CAST(@org_uuid AS varchar(36)),
				CAST(cp.derived_orig AS varchar(36)),
				CAST(paths.f_obj AS varchar(36)),
				CAST(paths.t_obj AS varchar(36)),
				CAST(@d_orig AS varchar(36))
			) AS calc_orig
		) x
		WHERE paths.f_obj <> paths.t_obj;

		FETCH NEXT FROM cur_diag INTO @d_orig, @d_owner, @d_code, @d_cap, @d_lang;
	END

	CLOSE cur_diag;
	DEALLOCATE cur_diag;
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

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

	-- 0. Automatické zrcadlení exkluzivních stromových vztahů parent_uuid do tabulky link (is_derived = 1)
	IF @root_link_original IS NULL AND OBJECT_ID('meta_link_def', 'U') IS NOT NULL
	BEGIN
		DECLARE @parent_tabs TABLE (
			tabname varchar(128) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			link_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL
		);
		INSERT INTO @parent_tabs (tabname, link_code) VALUES
			('asset',          'asset_has_parent'),
			('asset_class',    'asset_class_has_parent'),
			('threat',         'threat_has_parent'),
			('impact',         'impact_has_parent'),
			('scenario',       'scenario_has_parent'),
			('countermeasure', 'countermeasure_has_parent'),
			('hierarchy_item', 'hierarchy_item_has_parent');

		DECLARE @pt_tab varchar(128), @pt_code varchar(80);
		DECLARE cur_pt CURSOR LOCAL FAST_FORWARD FOR
			SELECT tabname, link_code FROM @parent_tabs;

		OPEN cur_pt;
		FETCH NEXT FROM cur_pt INTO @pt_tab, @pt_code;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF OBJECT_ID(@pt_tab, 'U') IS NOT NULL AND COL_LENGTH(@pt_tab, 'parent_uuid') IS NOT NULL
			BEGIN
				DECLARE @mld_par uuid = dbo.f_generate_original('meta_link_def', @sys_owner, @pt_code, '');
				IF EXISTS (SELECT 1 FROM meta_link_def WHERE original = @mld_par AND record_type = 'A' AND removed = 0)
				BEGIN
					DECLARE @sql_par nvarchar(max) = N'
					DELETE l
					FROM link l
					LEFT JOIN [' + @pt_tab + N'] src
						ON src.original = l.from_object
						AND src.parent_uuid = l.to_object
						AND src.object_owner = l.object_owner
						AND src.record_type = ''A''
						AND src.removed = 0
						AND src.inactive = 0
					WHERE l.link_def = @p_mld
					  AND l.is_derived = 1
					  AND l.ancestor_link = 0x00
					  AND src.uuid IS NULL;

					INSERT INTO link (
						uuid, object_owner, original, record_type, approval_status, [language],
						link_def, from_object, to_object, ancestor_link, is_derived,
						date_created, who_created, date_modified, who_modified
					)
					SELECT
						x.calc_orig, src.object_owner, x.calc_orig, ''A'', ''A'', src.[language],
						@p_mld, src.original, src.parent_uuid, 0x00, 1,
						src.date_created, src.who_created, src.date_modified, src.who_modified
					FROM [' + @pt_tab + N'] src
					CROSS APPLY (
						SELECT dbo.f_link_original(
							CAST(src.object_owner AS varchar(36)),
							CAST(@p_mld AS varchar(36)),
							CAST(src.original AS varchar(36)),
							CAST(src.parent_uuid AS varchar(36)),
							''00000000-0000-0000-0000-000000000000''
						) AS calc_orig
					) x
					WHERE src.record_type = ''A''
					  AND src.removed = 0
					  AND src.inactive = 0
					  AND src.parent_uuid IS NOT NULL
					  AND src.parent_uuid <> 0x00
					  AND NOT EXISTS (
						SELECT 1 FROM link ex
						WHERE ex.object_owner = src.object_owner
						  AND ex.link_def = @p_mld
						  AND ex.from_object = src.original
						  AND ex.to_object = src.parent_uuid
						  AND ex.ancestor_link = 0x00
						  AND ex.record_type = ''A''
						  AND ex.removed = 0
					  );';

					EXEC sp_executesql @sql_par, N'@p_mld uniqueidentifier', @p_mld = @mld_par;
				END
			END
			FETCH NEXT FROM cur_pt INTO @pt_tab, @pt_code;
		END

		CLOSE cur_pt;
		DEALLOCATE cur_pt;
	END

	-- 1. Odstranění osiřelých odvozených vazeb z dědění po hierarchii (mimo projekce diagramů diagram_uuid IS NOT NULL)
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

	-- 2. Načtení aktivních kořenových vazeb ke zpracování (mimo is_exclusive_parent a mimo diagramy)
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
	  AND r.ancestor_link = 0x00
	  AND r.diagram_uuid IS NULL
	  AND (@root_link_original IS NULL OR r.original = @root_link_original);

	-- 3. Zpracování jednotlivých kořenových vazeb, u nichž alespoň jedna strana podporuje katalogovou hierarchii (parent_uuid)
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

	-- 4. Přepočet nepřímých vztahů a vazeb ve všech aktivních diagramech sítě
	IF OBJECT_ID('dbo.p_rebuild_link_diagram', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_rebuild_link_diagram;
	END
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
			IF OBJECT_ID('scenario_assessment', 'U') IS NOT NULL
				UPDATE scenario_assessment SET asset_uuid = @new_oth_original WHERE asset_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
			IF OBJECT_ID('countermeasure_implementation', 'U') IS NOT NULL
				UPDATE countermeasure_implementation SET asset_uuid = @new_oth_original WHERE asset_uuid = @node_original AND object_owner IN (@org_uuid, 0x00);
		END

		-- Přesměrování přímých vazeb v tabulce link (mimo is_exclusive_parent)
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
			  AND l.diagram_uuid IS NULL
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
			  AND l.diagram_uuid IS NULL
			  AND mld.is_exclusive_parent = 0
			  AND l.object_owner IN (@org_uuid, 0x00)
			  AND @table_name = 'asset';
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

	IF OBJECT_ID('dbo.p_sync_derived_links', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_derived_links;
	END
END
GO