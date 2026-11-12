EXECUTE dropni 'f_is_hierarchy_node_locked', 'FN';
GO

/* =============================================================================
 * Verze:  2026-11-12 17:10
 * Soubor: f_is_hierarchy_node_locked.sql
 * Funkce: dbo.f_is_hierarchy_node_locked
 * Účel:   Ověří, zda je daný uzel hierarchie (nebo libovolný podřízený uzel
 *         v jeho podstromu) již navázán na jiné entity v tabulkách link
 *         (mimo interní stromové vazby parent_to_child a odvozené vazby
 *         diagramů), scenario, asset, scenario_assessment nebo
 *         countermeasure_implementation.
 * Vazby:  Čte tabulky asset_class, threat, impact, scenario, countermeasure,
 *         asset, hierarchy, hierarchy_item, scenario_assessment,
 *         countermeasure_implementation, link a meta_link_def.
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
				JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.is_exclusive_parent = 0
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

	-- 2. Společná kontrola platných vazeb v tabulce link (mimo odvozené vazby parent_to_child)
	IF EXISTS (
		SELECT 1
		FROM link l
		JOIN @subtree s ON s.original = l.from_object OR s.original = l.to_object
		JOIN meta_link_def mld ON mld.original = l.link_def AND mld.record_type = 'A' AND mld.removed = 0
		WHERE l.record_type = 'A'
			AND l.removed = 0
			AND mld.is_exclusive_parent = 0
			AND l.diagram_uuid IS NULL
	)
		RETURN 1;

	RETURN 0;
END
GO