EXECUTE dropni 'p_rebuild_link_diagram', 'P';
GO

/* =============================================================================
 * Verze:     2026-11-12 17:10
 * Soubor:    p_rebuild_link_diagram.sql
 * Procedura: dbo.p_rebuild_link_diagram
 * Účel:      Vyhodnotí topologii schématu heterogenní sítě (@diagram_uuid
 *            z tabulky link_diagram):
 *            1. Nejprve synchronizuje stromové a zděděné vazby
 *               (dbo.p_sync_derived_links).
 *            2. Vyhodnotí cesty mezi logickými třídami přes
 *               dbo.f_resolve_link_diagram a pro každou dosažitelnální dvojici
 *               tříd (from_class, to_class) vygeneruje do meta_link_def
 *               odvozený vztah (is_derived = 1, diagram_uuid = @diagram_uuid).
 *            3. Vyhodnotí cesty mezi konkrétními objekty (uzly) po všech
 *               spojnicích zařazených do diagramu (včetně vnitrotřídních
 *               self-referencing vztahů a obou směrů 'P' i 'R') a promítne
 *               nepřímé vazby (level >= 2) do tabulky link (is_derived = 1,
 *               diagram_uuid = @diagram_uuid).
 * Vazby:     - Čte tabulky dbsession, link_diagram a meta_class.
 *            - Čte a modifikuje tabulky meta_link_def a link.
 *            - Využívá tabulkový typ tt_resolve_link_diagram, proceduru
 *              dbo.p_sync_derived_links a funkce dbo.f_resolve_link_diagram,
 *              dbo.f_generate_original a dbo.f_link_original.
 * ============================================================================= */
CREATE PROCEDURE dbo.p_rebuild_link_diagram
	@diagram_uuid uniqueidentifier,
	@org_uuid uniqueidentifier = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @diagram_uuid IS NULL OR @diagram_uuid = 0x00
		RETURN;

	IF OBJECT_ID('link_diagram', 'U') IS NULL OR OBJECT_ID('meta_link_def', 'U') IS NULL OR OBJECT_ID('link', 'U') IS NULL
		RETURN;

	DECLARE @user_session uniqueidentifier = 0x00;
	IF @org_uuid IS NULL
	BEGIN
		SELECT TOP 1
			@org_uuid = ISNULL(organization, 0x00),
			@user_session = ISNULL(login_session_uuid, 0x00)
		FROM dbsession
		WHERE spid = @@SPID;
	END
	ELSE
	BEGIN
		SELECT TOP 1 @user_session = ISNULL(login_session_uuid, 0x00)
		FROM dbsession
		WHERE spid = @@SPID;
	END
	SET @org_uuid = ISNULL(@org_uuid, 0x00);

	-- 0. Zajištění aktuálnosti stromových vazeb parent_to_child v tabulce link
	EXEC dbo.p_sync_derived_links;

	DECLARE @dg_code varchar(40) = '';
	DECLARE @dg_cap varchar(100) = '';
	SELECT TOP 1
		@dg_code = LEFT(ISNULL(NULLIF(builtin_code, ''), 'dg'), 25),
		@dg_cap = LEFT(ISNULL(NULLIF(caption, ''), builtin_code), 80)
	FROM link_diagram
	WHERE original = @diagram_uuid
		AND object_owner IN (@org_uuid, 0x00)
		AND record_type = 'A'
		AND removed = 0
	ORDER BY CASE WHEN object_owner = @org_uuid THEN 0 ELSE 1 END;

	IF @dg_code = ''
		RETURN;

	-- 1. Odstranění předchozích odvozených záznamů tohoto diagramu v link a meta_link_def
	DELETE FROM link
	WHERE diagram_uuid = @diagram_uuid
		AND is_derived = 1
		AND object_owner IN (@org_uuid, 0x00);

	DELETE FROM meta_link_def
	WHERE diagram_uuid = @diagram_uuid
		AND is_derived = 1
		AND object_owner IN (@org_uuid, 0x00);

	-- 2. Načtení orientovaných vztahů zařazených do diagramu (přes diagram_includes_link_def)
	DECLARE @dg_defs TABLE (
		link_def_orig uniqueidentifier NOT NULL PRIMARY KEY,
		canonical_p_def uniqueidentifier NOT NULL,
		direction_type varchar(1) NOT NULL,
		from_class uniqueidentifier NOT NULL,
		to_class uniqueidentifier NOT NULL
	);

	INSERT INTO @dg_defs (link_def_orig, canonical_p_def, direction_type, from_class, to_class)
	SELECT DISTINCT
		mld.original,
		CASE WHEN mld.direction_type = 'R' AND mld.reverse_link_def IS NOT NULL THEN mld.reverse_link_def ELSE mld.original END,
		mld.direction_type,
		mld.from_class,
		mld.to_class
	FROM link l
	JOIN meta_link_def mld_inc
		ON mld_inc.original = l.link_def
		AND mld_inc.link_code = 'diagram_includes_link_def'
		AND mld_inc.record_type = 'A'
		AND mld_inc.removed = 0
	JOIN meta_link_def mld
		ON mld.original = l.to_object
		AND mld.object_owner IN (@org_uuid, 0x00)
		AND mld.record_type = 'A'
		AND mld.removed = 0
		AND mld.inactive = 0
		AND mld.is_derived = 0
	WHERE l.from_object = @diagram_uuid
		AND l.object_owner IN (@org_uuid, 0x00)
		AND l.record_type = 'A'
		AND l.removed = 0
		AND l.inactive = 0;

	IF NOT EXISTS (SELECT 1 FROM @dg_defs)
		RETURN;

	-- 3. Sestavení grafu konkrétních uzlů (objektů) po všech spojnicích diagramu:
	--    Pokud je v diagramu použit vztah se směrem 'P' (nebo 'S'), čteme z link (from_object -> to_object).
	--    Pokud je v diagramu použit zpětný vztah 'R', čteme kanonické řádky jeho 'P' protějšku otočeně (to_object -> from_object)!
	DECLARE @obj_edges TABLE (
		from_obj uniqueidentifier NOT NULL,
		to_obj uniqueidentifier NOT NULL,
		from_cls uniqueidentifier NOT NULL,
		to_cls uniqueidentifier NOT NULL,
		PRIMARY KEY (from_obj, to_obj)
	);

	INSERT INTO @obj_edges (from_obj, to_obj, from_cls, to_cls)
	SELECT DISTINCT
		src.from_obj,
		src.to_obj,
		MIN(src.from_cls),
		MIN(src.to_cls)
	FROM (
		SELECT
			CASE WHEN dd.direction_type = 'R' THEN l.to_object ELSE l.from_object END AS from_obj,
			CASE WHEN dd.direction_type = 'R' THEN l.from_object ELSE l.to_object END AS to_obj,
			dd.from_class AS from_cls,
			dd.to_class AS to_cls
		FROM @dg_defs dd
		JOIN link l
			ON l.link_def = dd.canonical_p_def
			AND l.object_owner IN (@org_uuid, 0x00)
			AND l.record_type = 'A'
			AND l.removed = 0
			AND l.inactive = 0
			AND l.diagram_uuid IS NULL
	) src
	WHERE src.from_obj <> src.to_obj
	GROUP BY src.from_obj, src.to_obj;

	IF NOT EXISTS (SELECT 1 FROM @obj_edges)
		RETURN;

	-- Mapa třídy každého uzlu v síti
	DECLARE @node_class TABLE (
		obj_uuid uniqueidentifier NOT NULL PRIMARY KEY,
		cls_uuid uniqueidentifier NOT NULL
	);

	INSERT INTO @node_class (obj_uuid, cls_uuid)
	SELECT obj_uuid, MIN(cls_uuid)
	FROM (
		SELECT from_obj AS obj_uuid, from_cls AS cls_uuid FROM @obj_edges
		UNION ALL
		SELECT to_obj AS obj_uuid, to_cls AS cls_uuid FROM @obj_edges
	) u
	GROUP BY obj_uuid;

	-- 4. Vyhodnocení acyklických cest mezi uzly přes dbo.f_resolve_link_diagram
	DECLARE @inp_obj tt_resolve_link_diagram;

	INSERT INTO @inp_obj (node_id, from_id, sort_order)
	SELECT LOWER(CAST(obj_uuid AS varchar(36))), '', LOWER(CAST(obj_uuid AS varchar(36)))
	FROM @node_class;

	INSERT INTO @inp_obj (node_id, from_id, sort_order)
	SELECT
		LOWER(CAST(to_obj AS varchar(36))),
		LOWER(CAST(from_obj AS varchar(36))),
		LOWER(CAST(to_obj AS varchar(36)))
	FROM @obj_edges;

	-- Sběr nepřímých dvojic (root_id -> node_id na level >= 2 bez cyklu)
	DECLARE @indirect_pairs TABLE (
		from_obj uniqueidentifier NOT NULL,
		to_obj uniqueidentifier NOT NULL,
		from_cls uniqueidentifier NOT NULL,
		to_cls uniqueidentifier NOT NULL,
		min_level int NOT NULL,
		PRIMARY KEY (from_obj, to_obj)
	);

	INSERT INTO @indirect_pairs (from_obj, to_obj, from_cls, to_cls, min_level)
	SELECT
		CAST(r.root_id AS uniqueidentifier) AS from_obj,
		CAST(r.node_id AS uniqueidentifier) AS to_obj,
		nc_from.cls_uuid AS from_cls,
		nc_to.cls_uuid AS to_cls,
		MIN(r.level) AS min_level
	FROM dbo.f_resolve_link_diagram(@inp_obj) r
	JOIN @node_class nc_from ON LOWER(CAST(nc_from.obj_uuid AS varchar(36))) = r.root_id
	JOIN @node_class nc_to ON LOWER(CAST(nc_to.obj_uuid AS varchar(36))) = r.node_id
	WHERE r.level >= 2
		AND r.bad = 0
		AND r.root_id <> r.node_id
	GROUP BY r.root_id, r.node_id, nc_from.cls_uuid, nc_to.cls_uuid;

	-- 5. Projekce zjištěných nepřímých vztahů tříd do meta_link_def (is_derived = 1, diagram_uuid = @diagram_uuid)
	DECLARE @cls_pairs TABLE (
		from_cls uniqueidentifier NOT NULL,
		to_cls uniqueidentifier NOT NULL,
		link_code_p varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		link_code_r varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		orig_p uniqueidentifier NOT NULL,
		orig_r uniqueidentifier NOT NULL,
		cap_p varchar(200) NOT NULL,
		cap_r varchar(200) NOT NULL,
		PRIMARY KEY (from_cls, to_cls)
	);

	INSERT INTO @cls_pairs (from_cls, to_cls, link_code_p, link_code_r, orig_p, orig_r, cap_p, cap_r)
	SELECT
		d.from_cls,
		d.to_cls,
		codes.code_p,
		codes.code_r,
		dbo.f_generate_original('meta_link_def', @org_uuid, CAST(d.from_cls AS varchar(36)), codes.code_p),
		dbo.f_generate_original('meta_link_def', @org_uuid, CAST(d.to_cls AS varchar(36)), codes.code_r),
		LEFT('[' + @dg_cap + '] Nepřímý přenos na ' + COALESCE(NULLIF(mc_to.caption, ''), mc_to.class_name), 200),
		LEFT('[' + @dg_cap + '] Nepřímý přenos z ' + COALESCE(NULLIF(mc_from.caption, ''), mc_from.class_name), 200)
	FROM (
		SELECT DISTINCT from_cls, to_cls FROM @indirect_pairs
	) d
	JOIN meta_class mc_from ON mc_from.original = d.from_cls AND mc_from.record_type = 'A' AND mc_from.removed = 0
	JOIN meta_class mc_to ON mc_to.original = d.to_cls AND mc_to.record_type = 'A' AND mc_to.removed = 0
	CROSS APPLY (
		SELECT
			LEFT('dg_' + @dg_code + '_to_' + mc_to.class_name, 80) AS code_p,
			LEFT('dg_' + @dg_code + '_from_' + mc_from.class_name, 80) AS code_r
	) codes;

	-- Vložení 'P' a 'R' odvozených vztahů do meta_link_def (A + symetrické L)
	INSERT INTO meta_link_def (
		uuid, object_owner, original, record_type, approval_status, [language],
		link_code, from_class, to_class, reverse_link_def, direction_type,
		is_exclusive_parent, is_derived, diagram_uuid,
		caption_forward, caption_backward,
		is_multiple, is_mandatory, leaf_only, link_weight_enabled,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		cp.orig_p, @org_uuid, cp.orig_p, 'A', 'A', 'cs',
		cp.link_code_p, cp.from_cls, cp.to_cls, cp.orig_r, 'P',
		0, 1, @diagram_uuid,
		cp.cap_p, cp.cap_r,
		1, 0, 0, 1,
		1, 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @cls_pairs cp
	UNION ALL
	SELECT
		cp.orig_r, @org_uuid, cp.orig_r, 'A', 'A', 'cs',
		cp.link_code_r, cp.to_cls, cp.from_cls, cp.orig_p, 'R',
		0, 1, @diagram_uuid,
		cp.cap_r, cp.cap_p,
		1, 0, 0, 1,
		1, 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @cls_pairs cp;

	INSERT INTO meta_link_def (
		uuid, object_owner, original, record_type, approval_status, [language],
		link_code, from_class, to_class, reverse_link_def, direction_type,
		is_exclusive_parent, is_derived, diagram_uuid,
		caption_forward, caption_backward,
		is_multiple, is_mandatory, leaf_only, link_weight_enabled,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), a.object_owner, a.original, 'L', 'A', 'cs',
		a.link_code, a.from_class, a.to_class, a.reverse_link_def, a.direction_type,
		a.is_exclusive_parent, a.is_derived, a.diagram_uuid,
		a.caption_forward, a.caption_backward,
		a.is_multiple, a.is_mandatory, a.leaf_only, a.link_weight_enabled,
		a.is_final, a.is_protected,
		a.date_created, a.who_created, a.date_modified, a.who_modified
	FROM meta_link_def a
	WHERE a.diagram_uuid = @diagram_uuid
		AND a.is_derived = 1
		AND a.object_owner = @org_uuid
		AND a.record_type = 'A';

	-- 6. Projekce nepřímých vazeb mezi konkrétními objekty do tabulky link (is_derived = 1, diagram_uuid = @diagram_uuid)
	INSERT INTO link (
		uuid, object_owner, original, record_type, approval_status, [language],
		link_def, from_object, to_object, ancestor_link, diagram_uuid,
		link_weight, note, is_derived,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.calc_orig, @org_uuid, x.calc_orig, 'A', 'A', 'cs',
		cp.orig_p, ip.from_obj, ip.to_obj, @diagram_uuid, @diagram_uuid,
		100.0000, 'Nepřímá vazba ze schématu sítě: ' + @dg_cap + ' (počet kroků: ' + CAST(ip.min_level AS varchar(10)) + ')', 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @indirect_pairs ip
	JOIN @cls_pairs cp ON cp.from_cls = ip.from_cls AND cp.to_cls = ip.to_cls
	CROSS APPLY (
		SELECT dbo.f_link_original(
			CAST(@org_uuid AS varchar(36)),
			CAST(cp.orig_p AS varchar(36)),
			CAST(ip.from_obj AS varchar(36)),
			CAST(ip.to_obj AS varchar(36)),
			CAST(@diagram_uuid AS varchar(36))
		) AS calc_orig
	) x
	WHERE NOT EXISTS (
		SELECT 1 FROM link ex
		WHERE ex.object_owner = @org_uuid
			AND ex.link_def = cp.orig_p
			AND ex.from_object = ip.from_obj
			AND ex.to_object = ip.to_obj
			AND ex.ancestor_link = @diagram_uuid
			AND ex.record_type = 'A'
			AND ex.removed = 0
	);
END
GO