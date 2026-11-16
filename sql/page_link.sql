EXECUTE dropni 'page_link', 'P';
GO

/* =============================================================================
 * Verze: 2026-11-16 15:25
 * Soubor: page_link.sql
 * Procedura: dbo.page_link
 *
 * 1. Role souboru v celém systému:
 *    Databázová podpora pro obrazovku správy vazeb a závislostí page_link.php.
 *    Odstraňuje N+1 dotazy v PHP cyklech a hromadně načítá:
 *    - @subpage = 'lookups': Lokalizované názvy všech definic vazeb ('DEF')
 *      a propojovaných objektů ('OBJ') v tabulce link pro levý Master panel.
 *    - @subpage = 'endpoints': Pravidla všech aktivních typů vazeb ('DEF')
 *      společně s lokalizovanými položkami všech odkazovaných tříd ('OPT',
 *      včetně STI filtrování podle asset_archetype) v jediném volání.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Volána z PHP třídy page_link (page_link.php).
 *    - Automaticky zařazena do buildu databáze maskou page_*.sql v BuildListDb.txt.
 *    - Čte tabulky dbsession, meta_link_def, meta_class, asset, asset_class,
 *      threat, impact, scenario, countermeasure, hierarchy_item,
 *      organization_unit a link_diagram.
 *    - Využívá funkci dbo.f_language_list (f_language_list.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Načítá aktivní organizaci (organization) a jazyk relace (language)
 *      z tabulky dbsession pro aktuální @@SPID.
 * ============================================================================= */
CREATE PROCEDURE dbo.page_link
	@subpage varchar(30)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @org_sql uniqueidentifier = 0x00;
	DECLARE @lang_sql varchar(2) = 'cs';

	SELECT TOP 1
		@org_sql = ISNULL(organization, 0x00),
		@lang_sql = ISNULL([language], 'cs')
	FROM dbsession
	WHERE spid = @@SPID;

	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@lang_sql)
	WHERE fallback_order < 1000;

	-- =========================================================================
	-- 1. Hromadné načtení čitelných názvů typů vazeb a objektů pro levý panel
	-- =========================================================================
	IF @subpage = 'lookups'
	BEGIN
		DECLARE @raw_objs TABLE (
			row_kind varchar(5) COLLATE DATABASE_DEFAULT NOT NULL,
			original uniqueidentifier NOT NULL,
			code_col varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			PRIMARY KEY (row_kind, original)
		);

		-- 1a. Definice typů vazeb (meta_link_def)
		INSERT INTO @raw_objs (row_kind, original, code_col, caption)
		SELECT
			'DEF',
			a.original,
			ISNULL(mc_f.class_name + '.', '') + a.link_code,
			COALESCE(tr.caption_forward, NULLIF(a.caption_forward, ''), a.link_code)
				+ CASE WHEN a.direction_type = 'R' THEN ' [R]' WHEN a.direction_type = 'S' THEN ' [S]' ELSE '' END
		FROM (
			SELECT original, from_class, link_code, direction_type, caption_forward,
				ROW_NUMBER() OVER (PARTITION BY original ORDER BY CASE WHEN object_owner = @org_sql THEN 0 ELSE 1 END) AS rn
			FROM meta_link_def
			WHERE object_owner IN (@org_sql, 0x00)
			  AND record_type = 'A'
			  AND removed = 0
		) a
		LEFT JOIN meta_class mc_f ON mc_f.original = a.from_class AND mc_f.record_type = 'A' AND mc_f.removed = 0
		OUTER APPLY (
			SELECT TOP 1 l.caption_forward
			FROM meta_link_def l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = a.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption_forward AS VARCHAR(MAX)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE a.rn = 1;

		-- 1b. Sjednocení všech propojovaných objektů z katalogových a věcných tabulek
		INSERT INTO @raw_objs (row_kind, original, code_col, caption)
		SELECT
			'OBJ',
			u.original,
			MAX(u.code_col),
			MAX(u.caption)
		FROM (
			SELECT original, builtin_code AS code_col, COALESCE(NULLIF(caption, ''), builtin_code) AS caption FROM asset WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM asset_class WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM threat WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM impact WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM scenario WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM countermeasure WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM hierarchy_item WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), NULLIF(shortname, ''), builtin_code) FROM organization_unit WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM link_diagram WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, link_code, COALESCE(NULLIF(caption_forward, ''), link_code) FROM meta_link_def WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
		) u
		GROUP BY u.original;

		SELECT row_kind, original, code_col, caption
		FROM @raw_objs;
		RETURN;
	END

	-- =========================================================================
	-- 2. Hromadné načtení pravidel definic vazeb a položek všech cílových tříd
	-- =========================================================================
	IF @subpage = 'endpoints'
	BEGIN
		DECLARE @defs TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			from_class uniqueidentifier NOT NULL,
			to_class uniqueidentifier NOT NULL,
			link_weight_enabled bit NOT NULL,
			INDEX ix_defs_from (from_class),
			INDEX ix_defs_to (to_class)
		);

		INSERT INTO @defs (original, from_class, to_class, link_weight_enabled)
		SELECT original, from_class, to_class, link_weight_enabled
		FROM (
			SELECT original, from_class, to_class, link_weight_enabled,
				ROW_NUMBER() OVER (PARTITION BY original ORDER BY CASE WHEN object_owner = @org_sql THEN 0 ELSE 1 END) AS rn
			FROM meta_link_def
			WHERE object_owner IN (@org_sql, 0x00)
			  AND record_type = 'A'
			  AND removed = 0
			  AND inactive = 0
		) x
		WHERE x.rn = 1;

		-- Unikátní seznam odkazovaných tříd s jejich úložnou tabulkou
		DECLARE @ref_classes TABLE (
			class_uuid uniqueidentifier NOT NULL PRIMARY KEY,
			class_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
			storage_table varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
			INDEX ix_ref_stg (storage_table, class_name)
		);

		INSERT INTO @ref_classes (class_uuid, class_name, storage_table)
		SELECT
			mc.original,
			mc.class_name,
			mo.builtin_code
		FROM (
			SELECT from_class AS cls_uuid FROM @defs
			UNION
			SELECT to_class AS cls_uuid FROM @defs
		) u
		JOIN meta_class mc ON mc.original = u.cls_uuid AND mc.record_type = 'A' AND mc.removed = 0
		JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0;

		-- Sběr všech záznamů podle fyzické tabulky a STI archetypu do jediné tabulkové proměnné
		DECLARE @all_opts TABLE (
			class_uuid uniqueidentifier NOT NULL,
			original uniqueidentifier NOT NULL,
			sort_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			code_col varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
			PRIMARY KEY (class_uuid, original)
		);

		-- 2a. Bázová třída asset a všech 17 STI tříd asset_*
		IF EXISTS (SELECT 1 FROM @ref_classes WHERE storage_table = 'asset')
		BEGIN
			DECLARE @assets TABLE (
				original uniqueidentifier NOT NULL PRIMARY KEY,
				asset_archetype varchar(30) COLLATE DATABASE_DEFAULT NOT NULL,
				sort_code varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
				code_col varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
				caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
				INDEX ix_assets_arch (asset_archetype, sort_code)
			);

			INSERT INTO @assets (original, asset_archetype, sort_code, code_col, caption)
			SELECT
				a.original,
				UPPER(a.asset_archetype),
				a.sort_code,
				a.builtin_code,
				COALESCE(tr.caption, NULLIF(a.caption, ''), a.builtin_code)
			FROM (
				SELECT original, asset_archetype, sort_code, builtin_code, caption,
					ROW_NUMBER() OVER (PARTITION BY original ORDER BY CASE WHEN object_owner = @org_sql THEN 0 ELSE 1 END) AS rn
				FROM asset
				WHERE object_owner IN (@org_sql, 0x00)
				  AND record_type = 'A'
				  AND removed = 0
			) a
			OUTER APPLY (
				SELECT TOP 1 l.caption
				FROM asset l
				JOIN @fl fl ON fl.[language] = l.[language]
				WHERE l.original = a.original
				  AND l.record_type = 'L'
				  AND l.removed = 0
				  AND l.object_owner IN (@org_sql, 0x00)
				  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
				ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
			) tr
			WHERE a.rn = 1;

			INSERT INTO @all_opts (class_uuid, original, sort_code, code_col, caption)
			SELECT
				rc.class_uuid,
				a.original,
				a.sort_code,
				a.code_col,
				a.caption
			FROM @ref_classes rc
			JOIN @assets a
				ON rc.class_name = 'asset'
				OR (rc.class_name LIKE 'asset[_]%' AND a.asset_archetype = UPPER(SUBSTRING(rc.class_name, 7, 30)))
			WHERE rc.storage_table = 'asset';
		END

		-- 2b. Ostatní katalogové tabulky (asset_class, threat, impact, scenario, countermeasure, organization_unit, link_diagram, meta_link_def)
		INSERT INTO @all_opts (class_uuid, original, sort_code, code_col, caption)
		SELECT rc.class_uuid, x.original, x.sort_code, x.code_col, x.caption
		FROM @ref_classes rc
		JOIN (
			SELECT 'asset_class' AS stg, original, sort_code, builtin_code AS code_col, COALESCE(NULLIF(caption, ''), builtin_code) AS caption FROM asset_class WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT 'threat', original, sort_code, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM threat WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT 'impact', original, sort_code, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM impact WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT 'scenario', original, sort_code, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM scenario WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT 'countermeasure', original, sort_code, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM countermeasure WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT 'organization_unit', original, sort_code, builtin_code, COALESCE(NULLIF(caption, ''), NULLIF(shortname, ''), builtin_code) FROM organization_unit WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT 'link_diagram', original, sort_code, builtin_code, COALESCE(NULLIF(caption, ''), builtin_code) FROM link_diagram WHERE object_owner IN (@org_sql, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT 'meta_link_def', mld.original, ISNULL(mc_f.class_name, ''), ISNULL(mc_f.class_name + '.', '') + mld.link_code, COALESCE(NULLIF(mld.caption_forward, ''), mld.link_code)
			FROM meta_link_def mld
			LEFT JOIN meta_class mc_f ON mc_f.original = mld.from_class AND mc_f.record_type = 'A' AND mc_f.removed = 0
			WHERE mld.object_owner IN (@org_sql, 0x00) AND mld.record_type = 'A' AND mld.removed = 0 AND mld.inactive = 0 AND mld.diagram_uuid IS NULL
		) x ON x.stg = rc.storage_table
		WHERE rc.storage_table <> 'asset';

		-- Výsledný sjednocený result-set (řádky 'DEF' i 'OPT' v jednom dotazu)
		SELECT
			'DEF' AS row_kind,
			d.original,
			d.from_class,
			d.to_class,
			d.link_weight_enabled,
			CAST(0x00 AS uniqueidentifier) AS class_uuid,
			'' AS sort_code,
			'' AS code_col,
			'' AS caption
		FROM @defs d

		UNION ALL

		SELECT
			'OPT' AS row_kind,
			o.original,
			CAST(0x00 AS uniqueidentifier) AS from_class,
			CAST(0x00 AS uniqueidentifier) AS to_class,
			CAST(0 AS bit) AS link_weight_enabled,
			o.class_uuid,
			o.sort_code,
			o.code_col,
			o.caption
		FROM @all_opts o
		ORDER BY row_kind ASC, class_uuid ASC, sort_code ASC, caption ASC, code_col ASC;
	END
END
GO