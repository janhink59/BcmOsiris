EXECUTE dropni 'page_link_diagram', 'P';
GO

/* =============================================================================
 * Verze: 2026-11-27 16:05
 * Soubor: page_link_diagram.sql
 * Procedura: dbo.page_link_diagram
 *
 * 1. Role souboru v celém systému:
 *    Databázová podpora pro správu schémat heterogenních sítí vztahů
 *    (page_link_diagram.php) nad samostatnou vazební tabulkou link_diagram_edge:
 *    - @subpage = 'counts':         Vrátí počty hran schématu (cnt_edges),
 *                                   odvozených nepřímých vztahů (cnt_defs) a
 *                                   odvozených vazeb uzlů (cnt_links).
 *    - @subpage = 'edges':          Vrátí seznam vztahů (meta_link_def) aktuálně
 *                                   zařazených do diagramu včetně lokalizovaných
 *                                   názvů zdrojové a cílové třídy.
 *    - @subpage = 'available_defs': Vrátí katalog orientovaných vztahů z
 *                                   meta_link_def dostupných pro přidání do
 *                                   diagramu (bez již zařazených a bez technických
 *                                   tabulek; volitelně vč. 1:N FK přes @include_fk).
 *    - @subpage = 'add_edge':       Přidá (nebo obnoví) vybraný orientovaný vztah
 *                                   do tabulky link_diagram_edge.
 *    - @subpage = 'remove_edge':    Odebere vybraný vztah z tabulky link_diagram_edge
 *                                   (u systémové hrany v kontextu tenanta založí
 *                                   override s removed = 1 bez zásahu do 0x00).
 *    - @subpage = 'topology':       Vyhodnotí topologický průchod logickými třídami
 *                                   v diagramu přes dbo.f_resolve_link_diagram
 *                                   s detekcí vnitrotřídních smyček a cyklů.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Volána z PHP třídy page_link_diagram (page_link_diagram.php).
 *    - Automaticky zařazena do buildu databáze maskou page_*.sql v BuildListDb.txt.
 *    - Čte a modifikuje tabulku link_diagram_edge (table_link_diagram_edge.sql).
 *    - Čte tabulky dbsession, link, meta_link_def a meta_class.
 *    - Využívá tabulkový typ tt_resolve_link_diagram a funkce
 *      dbo.f_resolve_link_diagram, dbo.f_language_list a dbo.f_generate_original.
 *
 * 3. Očekávaná kontextová data:
 *    - Čte aktivní organizaci (organization), jazyk (language) a relaci
 *      (login_session_uuid) z tabulky dbsession pro aktuální @@SPID.
 *
 * Změny:
 * - 2026-11-27 16:05: Opravena T-SQL chyba Msg 1046 v větvi add_edge
 *   (odstraněn poddotaz EXISTS z inicializace DECLARE @new_pk a nahrazen
 *   samostatným IF EXISTS ... SET @new_pk = NEWID()).
 * ============================================================================= */
CREATE PROCEDURE dbo.page_link_diagram
	@subpage varchar(30),                                                   -- Požadovaná akce / dotaz
	@diagram_uuid uniqueidentifier,                                         -- Identifikátor schématu sítě (link_diagram.original)
	@link_def_uuid uniqueidentifier = NULL,                                 -- Volitelný vztah (meta_link_def.original) pro add/remove
	@include_fk bit = 0,                                                    -- 1 = Zahrnout i odvozené 1:N FK vztahy (fk_* / ref_by_*)
	@sort_code varchar(20) = ''                                             -- Volitelné pořadí přidávané hrany
AS
BEGIN
	SET NOCOUNT ON;

	IF @diagram_uuid IS NULL OR @diagram_uuid = 0x00
		RETURN;

	DECLARE @org_sql uniqueidentifier = 0x00;
	DECLARE @lang_sql varchar(2) = 'cs';
	DECLARE @user_session uniqueidentifier = 0x00;

	SELECT TOP 1
		@org_sql = ISNULL(organization, 0x00),
		@lang_sql = ISNULL([language], 'cs'),
		@user_session = ISNULL(login_session_uuid, 0x00)
	FROM dbsession
	WHERE spid = @@SPID;

	-- =========================================================================
	-- 1. Přidání orientovaného vztahu do schématu (link_diagram_edge)
	-- =========================================================================
	IF @subpage = 'add_edge'
	BEGIN
		IF @link_def_uuid IS NULL OR @link_def_uuid = 0x00
			RETURN;

		IF NOT EXISTS (
			SELECT 1
			FROM meta_link_def
			WHERE original = @link_def_uuid
			  AND object_owner IN (@org_sql, 0x00)
			  AND record_type = 'A'
			  AND removed = 0
			  AND inactive = 0
			  AND diagram_uuid IS NULL
		)
			RETURN;

		SET @sort_code = LTRIM(RTRIM(ISNULL(@sort_code, '')));

		DECLARE @ex_uuid uniqueidentifier = NULL;
		SELECT TOP 1 @ex_uuid = uuid
		FROM link_diagram_edge
		WHERE diagram_uuid = @diagram_uuid
		  AND link_def_uuid = @link_def_uuid
		  AND object_owner = @org_sql
		  AND record_type = 'A'
		ORDER BY removed ASC, date_modified DESC;

		IF @ex_uuid IS NOT NULL
		BEGIN
			UPDATE link_diagram_edge
			SET removed = 0,
				inactive = 0,
				sort_code = CASE WHEN @sort_code <> '' THEN @sort_code ELSE sort_code END,
				date_modified = GETDATE(),
				who_modified = @user_session
			WHERE uuid = @ex_uuid;
			RETURN;
		END

		DECLARE @calc_orig uniqueidentifier = dbo.f_generate_original(
			'link_diagram_edge',
			@org_sql,
			CAST(@diagram_uuid AS varchar(36)),
			CAST(@link_def_uuid AS varchar(36))
		);
		DECLARE @new_pk uniqueidentifier = @calc_orig;
		IF EXISTS (SELECT 1 FROM link_diagram_edge WHERE uuid = @calc_orig)
			SET @new_pk = NEWID();

		INSERT INTO link_diagram_edge (
			uuid, object_owner, original, record_type, approval_status, [language],
			diagram_uuid, link_def_uuid, sort_code,
			date_created, who_created, date_modified, who_modified
		) VALUES (
			@new_pk, @org_sql, @calc_orig, 'A', 'A', @lang_sql,
			@diagram_uuid, @link_def_uuid, @sort_code,
			GETDATE(), @user_session, GETDATE(), @user_session
		);

		INSERT INTO link_diagram_edge (
			uuid, object_owner, original, record_type, approval_status, [language],
			diagram_uuid, link_def_uuid, sort_code,
			date_created, who_created, date_modified, who_modified
		) VALUES (
			NEWID(), @org_sql, @calc_orig, 'L', 'A', @lang_sql,
			@diagram_uuid, @link_def_uuid, @sort_code,
			GETDATE(), @user_session, GETDATE(), @user_session
		);
		RETURN;
	END

	-- =========================================================================
	-- 2. Odebrání orientovaného vztahu ze schématu (link_diagram_edge)
	-- =========================================================================
	IF @subpage = 'remove_edge'
	BEGIN
		IF @link_def_uuid IS NULL OR @link_def_uuid = 0x00
			RETURN;

		DELETE FROM link_diagram_edge
		WHERE diagram_uuid = @diagram_uuid
		  AND link_def_uuid = @link_def_uuid
		  AND object_owner = @org_sql;

		-- Pokud hrana pochází ze systémového schématu (0x00) a odebírá ji tenant, založíme override s removed = 1
		IF @org_sql <> 0x00 AND EXISTS (
			SELECT 1
			FROM link_diagram_edge
			WHERE diagram_uuid = @diagram_uuid
			  AND link_def_uuid = @link_def_uuid
			  AND object_owner = 0x00
			  AND record_type = 'A'
			  AND removed = 0
		)
		BEGIN
			DECLARE @sys_orig uniqueidentifier = NULL;
			SELECT TOP 1 @sys_orig = original
			FROM link_diagram_edge
			WHERE diagram_uuid = @diagram_uuid
			  AND link_def_uuid = @link_def_uuid
			  AND object_owner = 0x00
			  AND record_type = 'A'
			  AND removed = 0;

			INSERT INTO link_diagram_edge (
				uuid, object_owner, original, record_type, approval_status, [language],
				removed, diagram_uuid, link_def_uuid,
				date_created, who_created, date_modified, who_modified
			) VALUES (
				NEWID(), @org_sql, @sys_orig, 'A', 'A', @lang_sql,
				1, @diagram_uuid, @link_def_uuid,
				GETDATE(), @user_session, GETDATE(), @user_session
			);
		END
		RETURN;
	END

	-- Společný sběr aktivních hran tohoto schématu s respektem k overridu tenanta
	DECLARE @active_edges TABLE (
		link_def_uuid uniqueidentifier NOT NULL PRIMARY KEY,
		edge_owner uniqueidentifier NOT NULL,
		sort_code varchar(20) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @active_edges (link_def_uuid, edge_owner, sort_code)
	SELECT x.link_def_uuid, x.object_owner, x.sort_code
	FROM (
		SELECT
			lde.link_def_uuid,
			lde.object_owner,
			lde.sort_code,
			lde.removed,
			lde.inactive,
			ROW_NUMBER() OVER (
				PARTITION BY lde.link_def_uuid
				ORDER BY CASE WHEN lde.object_owner = @org_sql THEN 0 ELSE 1 END ASC
			) AS rn
		FROM link_diagram_edge lde
		WHERE lde.diagram_uuid = @diagram_uuid
		  AND lde.object_owner IN (@org_sql, 0x00)
		  AND lde.record_type = 'A'
	) x
	WHERE x.rn = 1
	  AND x.removed = 0
	  AND x.inactive = 0;

	-- =========================================================================
	-- 3. Počty hran, odvozených vztahů a vazeb pro hlavičku detailu
	-- =========================================================================
	IF @subpage = 'counts'
	BEGIN
		DECLARE @cnt_edges int = 0;
		DECLARE @cnt_defs int = 0;
		DECLARE @cnt_links int = 0;

		SELECT @cnt_edges = COUNT(1) FROM @active_edges;

		SELECT @cnt_defs = COUNT(DISTINCT original)
		FROM meta_link_def
		WHERE diagram_uuid = @diagram_uuid
		  AND is_derived = 1
		  AND object_owner IN (@org_sql, 0x00)
		  AND record_type = 'A'
		  AND removed = 0;

		SELECT @cnt_links = COUNT(DISTINCT original)
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

	-- Společná jazyková tabulka pro lokalizaci tříd a vztahů
	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@lang_sql)
	WHERE fallback_order < 1000;

	-- Lokalizované názvy aktivních tříd v meta_class
	DECLARE @cls_loc TABLE (
		original uniqueidentifier NOT NULL PRIMARY KEY,
		class_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		caption varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		INDEX ix_cls_loc_name (class_name)
	);

	INSERT INTO @cls_loc (original, class_name, caption)
	SELECT
		c.original,
		c.class_name,
		COALESCE(tr.caption, NULLIF(c.caption, ''), c.class_name)
	FROM (
		SELECT
			mc.original,
			mc.class_name,
			mc.caption,
			ROW_NUMBER() OVER (PARTITION BY mc.original ORDER BY CASE WHEN mc.object_owner = @org_sql THEN 0 ELSE 1 END ASC) AS rn
		FROM meta_class mc
		WHERE mc.object_owner IN (@org_sql, 0x00)
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
	) c
	OUTER APPLY (
		SELECT TOP 1 l.caption
		FROM meta_class l
		JOIN @fl fl ON fl.[language] = l.[language]
		WHERE l.original = c.original
		  AND l.record_type = 'L'
		  AND l.removed = 0
		  AND l.object_owner IN (@org_sql, 0x00)
		  AND NULLIF(CAST(l.caption AS varchar(max)), '') IS NOT NULL
		ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
	) tr
	WHERE c.rn = 1;

	-- =========================================================================
	-- 4. Seznam vztahů (hran) aktuálně zařazených do diagramu
	-- =========================================================================
	IF @subpage = 'edges'
	BEGIN
		SELECT
			m.original AS link_def_uuid,
			ae.sort_code,
			ae.edge_owner,
			m.link_code,
			m.direction_type,
			m.is_exclusive_parent,
			m.from_class,
			m.to_class,
			fc.class_name AS from_class_name,
			fc.caption AS from_class_caption,
			tc.class_name AS to_class_name,
			tc.caption AS to_class_caption,
			COALESCE(tr.caption_forward, NULLIF(m.caption_forward, ''), m.link_code) AS link_caption
		FROM @active_edges ae
		JOIN (
			SELECT
				mld.original,
				mld.link_code,
				mld.direction_type,
				mld.is_exclusive_parent,
				mld.from_class,
				mld.to_class,
				mld.caption_forward,
				ROW_NUMBER() OVER (PARTITION BY mld.original ORDER BY CASE WHEN mld.object_owner = @org_sql THEN 0 ELSE 1 END ASC) AS rn
			FROM meta_link_def mld
			WHERE mld.object_owner IN (@org_sql, 0x00)
			  AND mld.record_type = 'A'
			  AND mld.removed = 0
			  AND mld.diagram_uuid IS NULL
		) m ON m.original = ae.link_def_uuid AND m.rn = 1
		JOIN @cls_loc fc ON fc.original = m.from_class
		JOIN @cls_loc tc ON tc.original = m.to_class
		OUTER APPLY (
			SELECT TOP 1 l.caption_forward
			FROM meta_link_def l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = m.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption_forward AS varchar(max)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		ORDER BY ae.sort_code ASC, fc.caption ASC, tc.caption ASC, m.link_code ASC;
		RETURN;
	END

	-- =========================================================================
	-- 5. Katalog vztahů dostupných k přidání do tohoto schématu sítě
	-- =========================================================================
	IF @subpage = 'available_defs'
	BEGIN
		SELECT
			m.original AS link_def_uuid,
			m.link_code,
			m.direction_type,
			m.is_exclusive_parent,
			m.is_derived,
			fc.class_name AS from_class_name,
			fc.caption AS from_class_caption,
			tc.class_name AS to_class_name,
			tc.caption AS to_class_caption,
			COALESCE(tr.caption_forward, NULLIF(m.caption_forward, ''), m.link_code) AS link_caption
		FROM (
			SELECT
				mld.original,
				mld.link_code,
				mld.direction_type,
				mld.is_exclusive_parent,
				mld.is_derived,
				mld.from_class,
				mld.to_class,
				mld.caption_forward,
				ROW_NUMBER() OVER (PARTITION BY mld.original ORDER BY CASE WHEN mld.object_owner = @org_sql THEN 0 ELSE 1 END ASC) AS rn
			FROM meta_link_def mld
			WHERE mld.object_owner IN (@org_sql, 0x00)
			  AND mld.record_type = 'A'
			  AND mld.removed = 0
			  AND mld.inactive = 0
			  AND mld.diagram_uuid IS NULL
			  AND (@include_fk = 1 OR mld.is_derived = 0 OR mld.is_exclusive_parent = 1)
		) m
		JOIN @cls_loc fc ON fc.original = m.from_class
		JOIN @cls_loc tc ON tc.original = m.to_class
		LEFT JOIN @active_edges ae ON ae.link_def_uuid = m.original
		OUTER APPLY (
			SELECT TOP 1 l.caption_forward
			FROM meta_link_def l
			JOIN @fl fl ON fl.[language] = l.[language]
			WHERE l.original = m.original
			  AND l.record_type = 'L'
			  AND l.removed = 0
			  AND l.object_owner IN (@org_sql, 0x00)
			  AND NULLIF(CAST(l.caption_forward AS varchar(max)), '') IS NOT NULL
			ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org_sql THEN 0 ELSE 1 END ASC
		) tr
		WHERE m.rn = 1
		  AND ae.link_def_uuid IS NULL
		  AND fc.class_name NOT LIKE 'meta[_]%'
		  AND tc.class_name NOT LIKE 'meta[_]%'
		  AND fc.class_name NOT LIKE 'sys[_]%'
		  AND tc.class_name NOT LIKE 'sys[_]%'
		  AND fc.class_name NOT IN ('link_diagram', 'link_diagram_edge', 'user_account', 'user_organization_access', 'organization', 'organization_licence', 'audit_login_session', 'wwwsession', 'dbsession', 'request_message', 'request_variable', 'service_logbook', 'system_constant')
		  AND tc.class_name NOT IN ('link_diagram', 'link_diagram_edge', 'user_account', 'user_organization_access', 'organization', 'organization_licence', 'audit_login_session', 'wwwsession', 'dbsession', 'request_message', 'request_variable', 'service_logbook', 'system_constant')
		ORDER BY fc.caption ASC, tc.caption ASC, m.direction_type ASC, m.link_code ASC;
		RETURN;
	END

	-- =========================================================================
	-- 6. Vyhodnocení topologie tříd v diagramu přes dbo.f_resolve_link_diagram
	-- =========================================================================
	IF @subpage = 'topology'
	BEGIN
		DECLARE @edges TABLE (
			from_class uniqueidentifier NOT NULL,
			to_class uniqueidentifier NOT NULL,
			PRIMARY KEY (from_class, to_class),
			INDEX ix_edges_to (to_class)
		);

		INSERT INTO @edges (from_class, to_class)
		SELECT DISTINCT mld.from_class, mld.to_class
		FROM @active_edges ae
		JOIN meta_link_def mld
			ON mld.original = ae.link_def_uuid
			AND mld.object_owner IN (@org_sql, 0x00)
			AND mld.record_type = 'A'
			AND mld.removed = 0
			AND mld.inactive = 0
			AND mld.diagram_uuid IS NULL;

		IF NOT EXISTS (SELECT 1 FROM @edges)
			RETURN;

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
		JOIN @cls_loc c ON c.original = u.cls_uuid;

		INSERT INTO @inp (node_id, from_id, sort_order)
		SELECT DISTINCT LOWER(CAST(e.to_class AS varchar(36))), LOWER(CAST(e.from_class AS varchar(36))), c.class_name
		FROM @edges e
		JOIN @cls_loc c ON c.original = e.to_class
		WHERE e.from_class <> e.to_class;

		SELECT
			r.node_id,
			r.from_id,
			r.sort_order,
			r.level,
			r.bad,
			r.circular,
			r.hidden_root,
			c.class_name,
			c.caption AS class_caption,
			CASE WHEN sl.class_uuid IS NOT NULL THEN 1 ELSE 0 END AS has_self_loop
		FROM dbo.f_resolve_link_diagram(@inp) r
		JOIN @cls_loc c ON LOWER(CAST(c.original AS varchar(36))) = r.node_id
		LEFT JOIN @self_loops sl ON sl.class_uuid = c.original
		WHERE r.hidden_root = 0
		ORDER BY r.sort_order ASC;
	END
END
GO