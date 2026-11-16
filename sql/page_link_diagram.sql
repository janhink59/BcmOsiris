EXECUTE dropni 'page_link_diagram', 'P';
GO

/* =============================================================================
 * Verze: 2026-11-16 15:40
 * Soubor: page_link_diagram.sql
 * Procedura: dbo.page_link_diagram
 *
 * 1. Role souboru v celém systému:
 *    Databázová podpora pro správu schémat heterogenních sítí vztahů
 *    (page_link_diagram.php):
 *    - @subpage = 'counts': Vrátí v jednom řádku počty přímých spojnic diagramu
 *      (cnt_edges), odvozených nepřímých vztahů (cnt_defs) a odvozených vazeb
 *      uzlů (cnt_links) pro tlačítka v hlavičce detailu.
 *    - @subpage = 'topology': Vyhodnotí topologický průchod logickými třídami
 *      v diagramu přes dbo.f_resolve_link_diagram s lokalizací přes @fl a
 *      detekcí vnitrotřídních smyček (@self_loops) i mezitřídních cyklů.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Volána z PHP třídy page_link_diagram (page_link_diagram.php).
 *    - Automaticky zařazena do buildu databáze maskou page_*.sql v BuildListDb.txt.
 *    - Čte tabulky dbsession, link, meta_link_def a meta_class.
 *    - Využívá tabulkový typ tt_resolve_link_diagram a funkce
 *      dbo.f_resolve_link_diagram a dbo.f_language_list.
 *
 * 3. Očekávaná kontextová data:
 *    - Čte aktivní organizaci (organization) a jazyk (language) z tabulky
 *      dbsession pro aktuální @@SPID.
 * ============================================================================= */
CREATE PROCEDURE dbo.page_link_diagram
	@subpage varchar(30),
	@diagram_uuid uniqueidentifier
AS
BEGIN
	SET NOCOUNT ON;

	IF @diagram_uuid IS NULL OR @diagram_uuid = 0x00
		RETURN;

	DECLARE @org_sql uniqueidentifier = 0x00;
	DECLARE @lang_sql varchar(2) = 'cs';

	SELECT TOP 1
		@org_sql = ISNULL(organization, 0x00),
		@lang_sql = ISNULL([language], 'cs')
	FROM dbsession
	WHERE spid = @@SPID;

	-- =========================================================================
	-- 1. Počty spojnic, odvozených vztahů a vazeb pro tlačítka v hlavičce
	-- =========================================================================
	IF @subpage = 'counts'
	BEGIN
		DECLARE @cnt_edges int = 0;
		DECLARE @cnt_defs int = 0;
		DECLARE @cnt_links int = 0;

		SELECT @cnt_edges = COUNT(1)
		FROM link l
		JOIN meta_link_def mld
			ON mld.original = l.link_def
			AND mld.link_code = 'diagram_includes_link_def'
			AND mld.record_type = 'A'
			AND mld.removed = 0
		WHERE l.from_object = @diagram_uuid
		  AND l.object_owner IN (@org_sql, 0x00)
		  AND l.record_type = 'A'
		  AND l.removed = 0;

		SELECT @cnt_defs = COUNT(1)
		FROM meta_link_def
		WHERE diagram_uuid = @diagram_uuid
		  AND is_derived = 1
		  AND object_owner IN (@org_sql, 0x00)
		  AND record_type = 'A'
		  AND removed = 0;

		SELECT @cnt_links = COUNT(1)
		FROM link
		WHERE diagram_uuid = @diagram_uuid
		  AND is_derived = 1
		  AND object_owner IN (@org_sql, 0x00)
		  AND record_type = 'A'
		  AND removed = 0;

		SELECT
			@cnt_edges AS cnt_edges,
			@cnt_defs AS cnt_defs,
			@cnt_links AS cnt_links;
		RETURN;
	END

	-- =========================================================================
	-- 2. Vyhodnocení topologie tříd v diagramu přes dbo.f_resolve_link_diagram
	-- =========================================================================
	IF @subpage = 'topology'
	BEGIN
		DECLARE @fl TABLE (
			[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			fallback_order int NOT NULL
		);
		INSERT INTO @fl ([language], fallback_order)
		SELECT [language], fallback_order
		FROM dbo.f_language_list(@lang_sql)
		WHERE fallback_order < 1000;

		DECLARE @edges TABLE (
			from_class uniqueidentifier NOT NULL,
			to_class uniqueidentifier NOT NULL,
			PRIMARY KEY (from_class, to_class),
			INDEX ix_edges_to (to_class)
		);

		INSERT INTO @edges (from_class, to_class)
		SELECT DISTINCT mld.from_class, mld.to_class
		FROM link l
		JOIN meta_link_def mld_inc
			ON mld_inc.original = l.link_def
			AND mld_inc.link_code = 'diagram_includes_link_def'
			AND mld_inc.record_type = 'A'
			AND mld_inc.removed = 0
		JOIN meta_link_def mld
			ON mld.original = l.to_object
			AND mld.object_owner IN (@org_sql, 0x00)
			AND mld.record_type = 'A'
			AND mld.removed = 0
			AND mld.inactive = 0
			AND mld.diagram_uuid IS NULL
		WHERE l.from_object = @diagram_uuid
		  AND l.object_owner IN (@org_sql, 0x00)
		  AND l.record_type = 'A'
		  AND l.removed = 0
		  AND l.inactive = 0;

		IF NOT EXISTS (SELECT 1 FROM @edges)
			RETURN;

		-- Samostatná indexovaná tabulková proměnná pro vnitrotřídní smyčky (from_class = to_class)
		DECLARE @self_loops TABLE (
			class_uuid uniqueidentifier NOT NULL PRIMARY KEY
		);

		INSERT INTO @self_loops (class_uuid)
		SELECT from_class
		FROM @edges
		WHERE from_class = to_class;

		DECLARE @inp tt_resolve_link_diagram;

		INSERT INTO @inp (node_id, from_id, sort_order)
		SELECT DISTINCT LOWER(CAST(c.original AS varchar(36))), '', c.class_name
		FROM (
			SELECT from_class AS cls_uuid FROM @edges
			UNION
			SELECT to_class AS cls_uuid FROM @edges
		) u
		JOIN meta_class c ON c.original = u.cls_uuid AND c.record_type = 'A' AND c.removed = 0;

		INSERT INTO @inp (node_id, from_id, sort_order)
		SELECT DISTINCT LOWER(CAST(e.to_class AS varchar(36))), LOWER(CAST(e.from_class AS varchar(36))), c.class_name
		FROM @edges e
		JOIN meta_class c ON c.original = e.to_class AND c.record_type = 'A' AND c.removed = 0
		WHERE e.from_class <> e.to_class;

		SELECT
			r.node_id,
			r.from_id,
			r.sort_order,
			r.level,
			r.bad,
			r.circular,
			r.hidden_root,
			mc.class_name,
			COALESCE(tr.caption, NULLIF(mc.caption, ''), mc.class_name) AS class_caption,
			CASE WHEN sl.class_uuid IS NOT NULL THEN 1 ELSE 0 END AS has_self_loop
		FROM dbo.f_resolve_link_diagram(@inp) r
		JOIN meta_class mc
			ON LOWER(CAST(mc.original AS varchar(36))) = r.node_id
			AND mc.record_type = 'A'
			AND mc.removed = 0
		LEFT JOIN @self_loops sl
			ON sl.class_uuid = mc.original
		OUTER APPLY (
			SELECT TOP 1 l.caption
			FROM meta_class l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = mc.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE r.hidden_root = 0
		ORDER BY r.sort_order ASC;
	END
END
GO