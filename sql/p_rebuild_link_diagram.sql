EXECUTE dropni 'p_rebuild_link_diagram', 'P';
GO

/* =============================================================================
 * Verze:     2026-11-27 15:40
 * Soubor:    p_rebuild_link_diagram.sql
 * Procedura: dbo.p_rebuild_link_diagram
 *
 * 1. Role souboru v celém systému:
 *    Vyhodnotí topologii schématu heterogenní sítě (@diagram_uuid z tabulky
 *    link_diagram) na základě jeho hran v tabulce link_diagram_edge:
 *    1. Synchronizuje stromové a zděděné vazby (dbo.p_sync_derived_links).
 *    2. Bezpečně vymaže předchozí odvozené záznamy tohoto diagramu výhradně
 *       pro cílového vlastníka (@org_uuid) v tabulkách link a meta_link_def.
 *    3. Vyhodnotí topologii na úrovni logických tříd přes
 *       dbo.f_resolve_link_diagram. Při zjištění mezitřídního cyklu (bad = 1)
 *       projekci bezpečně zastaví a nahlásí chybu.
 *    4. Promítne všechny dosažitelné nepřímé dvojice tříd (level >= 2 a
 *       vnitrotřídní self-referencing vztahy) do meta_link_def (is_derived = 1,
 *       diagram_uuid = @diagram_uuid, 'A' + 'L' v cs a en) i tehdy, když v DB
 *       zatím nejsou vloženy konkrétní instance aktiv.
 *    5. Pokud existují propojené instance objektů v tabulce link, vyhodnotí
 *       acyklické cesty mezi uzly a promítne nepřímé vazby (level >= 2) do
 *       tabulky link (is_derived = 1, diagram_uuid = @diagram_uuid).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Čte tabulky dbsession, link_diagram, link_diagram_edge a meta_class.
 *    - Čte a modifikuje tabulky meta_link_def a link.
 *    - Využívá tabulkový typ tt_resolve_link_diagram, proceduru
 *      dbo.p_sync_derived_links, insert_request_message a funkce
 *      dbo.f_resolve_link_diagram, dbo.f_generate_original a dbo.f_link_original.
 *
 * 3. Očekávaná kontextová data:
 *    - Pokud není předán parametr @org_uuid, čte organizaci a login_session_uuid
 *      z tabulky dbsession pro aktuální @@SPID.
 *
 * Změny:
 * - 2026-11-27 15:40: Přepojeno na samostatnou tabulku link_diagram_edge;
 *   opraven destruktivní DELETE (nyní maže výhradně object_owner = @org_uuid);
 *   doplněna kontrola mezitřídního cyklu a projekce nepřímých vztahů tříd do
 *   meta_link_def (vč. anglického překladu 'en') i bez existujících instancí aktiv.
 * - 2026-11-12 18:30: Opraveno volání agregační funkce MIN() nad typem
 *   uniqueidentifier a povoleny stromové a 1:N vztahy (mld.diagram_uuid IS NULL).
 * ============================================================================= */
CREATE PROCEDURE dbo.p_rebuild_link_diagram
	@diagram_uuid uniqueidentifier,                                         -- Identifikátor schématu sítě (link_diagram.original)
	@org_uuid uniqueidentifier = NULL                                       -- Cílová organizace (NULL = z dbsession)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @diagram_uuid IS NULL OR @diagram_uuid = 0x00
		RETURN;

	IF OBJECT_ID('link_diagram', 'U') IS NULL
	   OR OBJECT_ID('link_diagram_edge', 'U') IS NULL
	   OR OBJECT_ID('meta_link_def', 'U') IS NULL
	   OR OBJECT_ID('link', 'U') IS NULL
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
	IF OBJECT_ID('dbo.p_sync_derived_links', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_derived_links;
	END

	DECLARE @dg_code varchar(40) = '';
	DECLARE @dg_cap_cs varchar(100) = '';
	DECLARE @dg_cap_en varchar(100) = '';

	SELECT TOP 1
		@dg_code = LEFT(ISNULL(NULLIF(builtin_code, ''), 'dg'), 25),
		@dg_cap_cs = LEFT(ISNULL(NULLIF(caption, ''), builtin_code), 80)
	FROM link_diagram
	WHERE original = @diagram_uuid
	  AND object_owner IN (@org_uuid, 0x00)
	  AND record_type = 'A'
	  AND removed = 0
	ORDER BY CASE WHEN object_owner = @org_uuid THEN 0 ELSE 1 END;

	IF @dg_code = ''
		RETURN;

	SELECT TOP 1
		@dg_cap_en = LEFT(ISNULL(NULLIF(caption, ''), @dg_cap_cs), 80)
	FROM link_diagram
	WHERE original = @diagram_uuid
	  AND object_owner IN (@org_uuid, 0x00)
	  AND record_type = 'L'
	  AND [language] = 'en'
	  AND removed = 0
	ORDER BY CASE WHEN object_owner = @org_uuid THEN 0 ELSE 1 END;

	IF @dg_cap_en = ''
		SET @dg_cap_en = @dg_cap_cs;

	-- 1. Odstranění předchozích odvozených záznamů tohoto diagramu VÝHRADNĚ pro @org_uuid
	DELETE FROM link
	WHERE diagram_uuid = @diagram_uuid
	  AND is_derived = 1
	  AND object_owner = @org_uuid;

	DELETE FROM meta_link_def
	WHERE diagram_uuid = @diagram_uuid
	  AND is_derived = 1
	  AND object_owner = @org_uuid;

	-- 2. Načtení aktivních orientovaných vztahů zařazených do diagramu (z link_diagram_edge s respektem k overridu tenanta)
	DECLARE @active_edges TABLE (
		link_def_uuid uniqueidentifier NOT NULL PRIMARY KEY
	);

	INSERT INTO @active_edges (link_def_uuid)
	SELECT x.link_def_uuid
	FROM (
		SELECT
			lde.link_def_uuid,
			lde.removed,
			lde.inactive,
			ROW_NUMBER() OVER (
				PARTITION BY lde.link_def_uuid
				ORDER BY CASE WHEN lde.object_owner = @org_uuid THEN 0 ELSE 1 END ASC
			) AS rn
		FROM link_diagram_edge lde
		WHERE lde.diagram_uuid = @diagram_uuid
		  AND lde.object_owner IN (@org_uuid, 0x00)
		  AND lde.record_type = 'A'
	) x
	WHERE x.rn = 1
	  AND x.removed = 0
	  AND x.inactive = 0;

	IF NOT EXISTS (SELECT 1 FROM @active_edges)
		RETURN;

	DECLARE @dg_defs TABLE (
		link_def_orig uniqueidentifier NOT NULL PRIMARY KEY,
		canonical_p_def uniqueidentifier NOT NULL,
		direction_type varchar(1) NOT NULL,
		from_class uniqueidentifier NOT NULL,
		to_class uniqueidentifier NOT NULL,
		INDEX ix_dg_defs_classes (from_class, to_class),
		INDEX ix_dg_defs_canon (canonical_p_def)
	);

	INSERT INTO @dg_defs (link_def_orig, canonical_p_def, direction_type, from_class, to_class)
	SELECT
		m.original,
		CASE WHEN m.direction_type = 'R' AND m.reverse_link_def IS NOT NULL THEN m.reverse_link_def ELSE m.original END,
		m.direction_type,
		m.from_class,
		m.to_class
	FROM (
		SELECT
			mld.original,
			mld.reverse_link_def,
			mld.direction_type,
			mld.from_class,
			mld.to_class,
			ROW_NUMBER() OVER (
				PARTITION BY mld.original
				ORDER BY CASE WHEN mld.object_owner = @org_uuid THEN 0 ELSE 1 END ASC
			) AS rn
		FROM @active_edges ae
		JOIN meta_link_def mld
			ON mld.original = ae.link_def_uuid
			AND mld.object_owner IN (@org_uuid, 0x00)
			AND mld.record_type = 'A'
			AND mld.removed = 0
			AND mld.inactive = 0
			AND mld.diagram_uuid IS NULL
	) m
	WHERE m.rn = 1;

	IF NOT EXISTS (SELECT 1 FROM @dg_defs)
		RETURN;

	-- 3. Vyhodnocení topologie a acykličnosti na úrovni logických tříd (from_class <> to_class)
	DECLARE @inp_cls tt_resolve_link_diagram;

	INSERT INTO @inp_cls (node_id, from_id, sort_order)
	SELECT DISTINCT LOWER(CAST(c.original AS varchar(36))), '', c.class_name
	FROM (
		SELECT from_class AS cls_uuid FROM @dg_defs
		UNION
		SELECT to_class AS cls_uuid FROM @dg_defs
	) u
	JOIN meta_class c
		ON c.original = u.cls_uuid
		AND c.object_owner IN (@org_uuid, 0x00)
		AND c.record_type = 'A'
		AND c.removed = 0;

	INSERT INTO @inp_cls (node_id, from_id, sort_order)
	SELECT DISTINCT
		LOWER(CAST(d.to_class AS varchar(36))),
		LOWER(CAST(d.from_class AS varchar(36))),
		c.class_name
	FROM @dg_defs d
	JOIN meta_class c
		ON c.original = d.to_class
		AND c.object_owner IN (@org_uuid, 0x00)
		AND c.record_type = 'A'
		AND c.removed = 0
	WHERE d.from_class <> d.to_class;

	DECLARE @cls_resolved TABLE (
		root_id varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		node_id varchar(40) COLLATE DATABASE_DEFAULT NOT NULL,
		level tinyint NOT NULL,
		bad bit NOT NULL,
		INDEX ix_cls_res_bad (bad),
		INDEX ix_cls_res_pair (level, bad, root_id, node_id)
	);

	INSERT INTO @cls_resolved (root_id, node_id, level, bad)
	SELECT root_id, node_id, level, bad
	FROM dbo.f_resolve_link_diagram(@inp_cls);

	-- Ochrana proti projekci zacykleného grafu logických tříd
	IF EXISTS (SELECT 1 FROM @cls_resolved WHERE bad = 1)
	BEGIN
		IF OBJECT_ID('insert_request_message', 'P') IS NOT NULL
		BEGIN
			EXEC insert_request_message
				'Schéma sítě obsahuje zacyklení mezi logickými třídami – projekce nepřímých vztahů byla zastavena.',
				3,
				@obj_type = 'link_diagram',
				@obj_name = @dg_code;
		END
		RETURN;
	END

	-- 4. Vyhodnocení nepřímých cest mezi konkrétními instancemi objektů v tabulce link (pokud již existují)
	DECLARE @obj_edges TABLE (
		from_obj uniqueidentifier NOT NULL,
		to_obj uniqueidentifier NOT NULL,
		from_cls uniqueidentifier NOT NULL,
		to_cls uniqueidentifier NOT NULL,
		PRIMARY KEY (from_obj, to_obj)
	);

	INSERT INTO @obj_edges (from_obj, to_obj, from_cls, to_cls)
	SELECT
		src.from_obj,
		src.to_obj,
		CAST(MIN(CAST(src.from_cls AS varchar(36))) AS uniqueidentifier),
		CAST(MIN(CAST(src.to_cls AS varchar(36))) AS uniqueidentifier)
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

	DECLARE @indirect_pairs TABLE (
		from_obj uniqueidentifier NOT NULL,
		to_obj uniqueidentifier NOT NULL,
		from_cls uniqueidentifier NOT NULL,
		to_cls uniqueidentifier NOT NULL,
		min_level int NOT NULL,
		PRIMARY KEY (from_obj, to_obj),
		INDEX ix_ind_cls (from_cls, to_cls)
	);

	IF EXISTS (SELECT 1 FROM @obj_edges)
	BEGIN
		DECLARE @node_class TABLE (
			obj_uuid uniqueidentifier NOT NULL PRIMARY KEY,
			cls_uuid uniqueidentifier NOT NULL
		);

		INSERT INTO @node_class (obj_uuid, cls_uuid)
		SELECT
			obj_uuid,
			CAST(MIN(CAST(cls_uuid AS varchar(36))) AS uniqueidentifier)
		FROM (
			SELECT from_obj AS obj_uuid, from_cls AS cls_uuid FROM @obj_edges
			UNION ALL
			SELECT to_obj AS obj_uuid, to_cls AS cls_uuid FROM @obj_edges
		) u
		GROUP BY obj_uuid;

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
	END

	-- 5. Sjednocení všech nepřímých dvojic tříd (z topologie tříd, self-loopů i instancí objektů)
	DECLARE @all_cls_pairs TABLE (
		from_cls uniqueidentifier NOT NULL,
		to_cls uniqueidentifier NOT NULL,
		PRIMARY KEY (from_cls, to_cls)
	);

	INSERT INTO @all_cls_pairs (from_cls, to_cls)
	SELECT DISTINCT from_cls, to_cls
	FROM (
		-- 5a. Všechny nepřímé dvojice tříd (level >= 2) z topologie diagramu (funguje i bez instancí aktiv)
		SELECT
			CAST(cr.root_id AS uniqueidentifier) AS from_cls,
			CAST(cr.node_id AS uniqueidentifier) AS to_cls
		FROM @cls_resolved cr
		WHERE cr.level >= 2
		  AND cr.bad = 0
		  AND cr.root_id <> cr.node_id

		UNION

		-- 5b. Vnitrotřídní self-referencing vztahy (umožňují 2+ kroky v rámci téže třídy)
		SELECT d.from_class AS from_cls, d.to_class AS to_cls
		FROM @dg_defs d
		WHERE d.from_class = d.to_class

		UNION

		-- 5c. Případné dvojice z instancí (např. kombinace self-loopu s přímou hranou A -> A -> B)
		SELECT ip.from_cls, ip.to_cls
		FROM @indirect_pairs ip
	) u;

	IF NOT EXISTS (SELECT 1 FROM @all_cls_pairs)
		RETURN;

	-- Deduplikované názvy tříd v češtině i angličtině pro čisté popisky odvozených vztahů
	DECLARE @cls_names TABLE (
		original uniqueidentifier NOT NULL PRIMARY KEY,
		class_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		cap_cs varchar(200) COLLATE DATABASE_DEFAULT NOT NULL,
		cap_en varchar(200) COLLATE DATABASE_DEFAULT NOT NULL
	);

	INSERT INTO @cls_names (original, class_name, cap_cs, cap_en)
	SELECT
		c.original,
		c.class_name,
		COALESCE(NULLIF(lcs.caption, ''), NULLIF(c.caption, ''), c.class_name),
		COALESCE(NULLIF(len_.caption, ''), NULLIF(c.caption, ''), c.class_name)
	FROM (
		SELECT
			mc.original,
			mc.class_name,
			mc.caption,
			ROW_NUMBER() OVER (PARTITION BY mc.original ORDER BY CASE WHEN mc.object_owner = @org_uuid THEN 0 ELSE 1 END ASC) AS rn
		FROM meta_class mc
		WHERE mc.object_owner IN (@org_uuid, 0x00)
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
	) c
	OUTER APPLY (
		SELECT TOP 1 l.caption
		FROM meta_class l
		WHERE l.original = c.original
		  AND l.object_owner IN (@org_uuid, 0x00)
		  AND l.record_type = 'L'
		  AND l.[language] = 'cs'
		  AND l.removed = 0
		ORDER BY CASE WHEN l.object_owner = @org_uuid THEN 0 ELSE 1 END ASC
	) lcs
	OUTER APPLY (
		SELECT TOP 1 l.caption
		FROM meta_class l
		WHERE l.original = c.original
		  AND l.object_owner IN (@org_uuid, 0x00)
		  AND l.record_type = 'L'
		  AND l.[language] = 'en'
		  AND l.removed = 0
		ORDER BY CASE WHEN l.object_owner = @org_uuid THEN 0 ELSE 1 END ASC
	) len_
	WHERE c.rn = 1;

	DECLARE @cls_pairs TABLE (
		from_cls uniqueidentifier NOT NULL,
		to_cls uniqueidentifier NOT NULL,
		link_code_p varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		link_code_r varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
		orig_p uniqueidentifier NOT NULL,
		orig_r uniqueidentifier NOT NULL,
		cap_p_cs varchar(200) NOT NULL,
		cap_r_cs varchar(200) NOT NULL,
		cap_p_en varchar(200) NOT NULL,
		cap_r_en varchar(200) NOT NULL,
		PRIMARY KEY (from_cls, to_cls)
	);

	INSERT INTO @cls_pairs (from_cls, to_cls, link_code_p, link_code_r, orig_p, orig_r, cap_p_cs, cap_r_cs, cap_p_en, cap_r_en)
	SELECT
		d.from_cls,
		d.to_cls,
		codes.code_p,
		codes.code_r,
		dbo.f_generate_original('meta_link_def', @org_uuid, CAST(d.from_cls AS varchar(36)), codes.code_p),
		dbo.f_generate_original('meta_link_def', @org_uuid, CAST(d.to_cls AS varchar(36)), codes.code_r),
		LEFT('[' + @dg_cap_cs + '] Nepřímý přenos na ' + mc_to.cap_cs, 200),
		LEFT('[' + @dg_cap_cs + '] Nepřímý přenos z ' + mc_from.cap_cs, 200),
		LEFT('[' + @dg_cap_en + '] Indirect transfer to ' + mc_to.cap_en, 200),
		LEFT('[' + @dg_cap_en + '] Indirect transfer from ' + mc_from.cap_en, 200)
	FROM @all_cls_pairs d
	JOIN @cls_names mc_from ON mc_from.original = d.from_cls
	JOIN @cls_names mc_to ON mc_to.original = d.to_cls
	CROSS APPLY (
		SELECT
			LEFT('dg_' + @dg_code + '_to_' + mc_to.class_name, 80) AS code_p,
			LEFT('dg_' + @dg_code + '_from_' + mc_from.class_name, 80) AS code_r
	) codes;

	-- 6. Projekce zjištěných nepřímých vztahů tříd do meta_link_def (A + L cs + L en)
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
		cp.cap_p_cs, cp.cap_r_cs,
		1, 0, 0, 1,
		1, 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @cls_pairs cp
	UNION ALL
	SELECT
		cp.orig_r, @org_uuid, cp.orig_r, 'A', 'A', 'cs',
		cp.link_code_r, cp.to_cls, cp.from_cls, cp.orig_p, 'R',
		0, 1, @diagram_uuid,
		cp.cap_r_cs, cp.cap_p_cs,
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
		NEWID(), @org_uuid, cp.orig_p, 'L', 'A', 'cs',
		cp.link_code_p, cp.from_cls, cp.to_cls, cp.orig_r, 'P',
		0, 1, @diagram_uuid,
		cp.cap_p_cs, cp.cap_r_cs,
		1, 0, 0, 1,
		1, 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @cls_pairs cp
	UNION ALL
	SELECT
		NEWID(), @org_uuid, cp.orig_r, 'L', 'A', 'cs',
		cp.link_code_r, cp.to_cls, cp.from_cls, cp.orig_p, 'R',
		0, 1, @diagram_uuid,
		cp.cap_r_cs, cp.cap_p_cs,
		1, 0, 0, 1,
		1, 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @cls_pairs cp
	UNION ALL
	SELECT
		NEWID(), @org_uuid, cp.orig_p, 'L', 'A', 'en',
		cp.link_code_p, cp.from_cls, cp.to_cls, cp.orig_r, 'P',
		0, 1, @diagram_uuid,
		cp.cap_p_en, cp.cap_r_en,
		1, 0, 0, 1,
		1, 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @cls_pairs cp
	UNION ALL
	SELECT
		NEWID(), @org_uuid, cp.orig_r, 'L', 'A', 'en',
		cp.link_code_r, cp.to_cls, cp.from_cls, cp.orig_p, 'R',
		0, 1, @diagram_uuid,
		cp.cap_r_en, cp.cap_p_en,
		1, 0, 0, 1,
		1, 1,
		GETDATE(), @user_session, GETDATE(), @user_session
	FROM @cls_pairs cp;

	-- 7. Projekce nepřímých vazeb mezi konkrétními objekty do tabulky link (pokud existují instance aktiv)
	IF EXISTS (SELECT 1 FROM @indirect_pairs)
	BEGIN
		INSERT INTO link (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_def, from_object, to_object, ancestor_link, diagram_uuid,
			link_weight, note, is_derived,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.calc_orig, @org_uuid, x.calc_orig, 'A', 'A', 'cs',
			cp.orig_p, ip.from_obj, ip.to_obj, @diagram_uuid, @diagram_uuid,
			100.0000, 'Nepřímá vazba ze schématu sítě: ' + @dg_cap_cs + ' (počet kroků: ' + CAST(ip.min_level AS varchar(10)) + ')', 1,
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
END
GO