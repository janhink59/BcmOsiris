/* =============================================================================
 * Verze: 2026-10-29 15:30
 * Soubor: p_get_menu_hierarchy.sql
 * Procedura: p_get_menu_hierarchy
 * Účel: Získání kompletního uživatelského menu s vyřešenou hierarchií, 
 *       RAC overridy, lokalizací přes dbo.f_language_list(@lang) a vyhodnocením
 *       oprávnění.
 * Vazby: - Volána z PHP třídy menu_manager (menu_manager.php).
 *        - Využívá dbsession, meta_menu, meta_object, f_resolve_hierarchy
 *          a dbo.f_language_list.
 * Změny: - 2026-10-29 15:30: Lokalizace caption a helptext napojena na indexovanou
 *          tabulkovou proměnnou @fl z dbo.f_language_list(@lang) s podmínkou
 *          fallback_order < 1000.
 * ============================================================================= */
IF OBJECT_ID('p_get_menu_hierarchy', 'P') IS NOT NULL DROP PROCEDURE p_get_menu_hierarchy;
GO

CREATE PROCEDURE p_get_menu_hierarchy
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @lang varchar(2), @active_role varchar(1), @org uuid;
	SELECT @lang = language, @active_role = active_role, @org = organization
	FROM dbsession WHERE spid = @@SPID;

	IF @lang IS NULL RETURN;

	-- 0. Načtení řetězce jazyků s fallback_order < 1000 do indexované tabulkové proměnné
	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@lang)
	WHERE fallback_order < 1000;

	-- 1. Sestavení platné množiny menu (Tenant Override vzor)
	SELECT * INTO #mix_menu FROM (
		SELECT sy.* FROM meta_menu sy 
		LEFT JOIN meta_menu my ON my.original = sy.original AND my.object_owner = @org AND my.record_type = 'A' AND my.removed = 0 AND my.inactive = 0
		WHERE sy.object_owner = 0x00 AND sy.record_type = 'A' AND sy.removed = 0 AND sy.inactive = 0 AND my.original IS NULL
		UNION ALL
		SELECT * FROM meta_menu WHERE object_owner = @org AND record_type = 'A' AND removed = 0 AND inactive = 0
	) m;

	-- 2. Příprava vstupních dat pro rekurzivní funkci
	DECLARE @hier_in tt_resolve_hierarchy;
	INSERT INTO @hier_in (keyvalue, parent, parent_order, top_level)
	SELECT 
		original, 
		parent_uuid, 
		sort_code, 
		CASE WHEN parent_uuid IS NULL THEN 1 ELSE 0 END
	FROM #mix_menu;

	-- 3. Vyřešení hierarchie (zploštění do lineárního tvaru se zero-paddingem)
	SELECT h.keyvalue, h.parent, h.hierarchy_sort, h.level
	INTO #tree
	FROM f_resolve_hierarchy(@hier_in) h;

	-- 4. Vyhodnocení přístupových práv a lokalizace přes @fl (fallback_order < 1000)
	SELECT 
		t.hierarchy_sort,
		t.level,
		m.original,
		m.parent_uuid,
		m.builtin_code,
		m.permanent,
		m.svg_icon,
		m.css_class,
		m.url_parameters,
		COALESCE(tr_cap.caption, m.caption) AS caption,
		COALESCE(tr_hlp.helptext, m.helptext) AS helptext,
		
		-- Detekce koncového uzlu (Dynamická ochrana proti chybně vyplněným metadatům)
		CASE WHEN EXISTS (SELECT 1 FROM #tree ch WHERE ch.parent = m.original) THEN 0 ELSE 1 END AS is_leaf,
		
		-- Vyhodnocení přímého přístupu (Kombinace oprávnění menu a cílového objektu)
		CASE 
			WHEN (
				@active_role IN ('S', 'D') 
				OR (@active_role = 'A' AND m.system_role IN ('U', 'A'))
				OR (@active_role = 'U' AND m.system_role = 'U')
			) 
			AND 
			(
				m.target_object IS NULL 
				OR EXISTS (
					SELECT 1 FROM meta_object mo 
					WHERE mo.original = m.target_object AND mo.record_type = 'A' AND mo.removed = 0
					AND (
						@active_role IN ('S', 'D') 
						OR (@active_role = 'A' AND mo.system_role IN ('U', 'A'))
						OR (@active_role = 'U' AND mo.system_role = 'U')
					)
				)
			)
			THEN 1 ELSE 0 
		END AS has_direct_access,
		
		m.target_object,
		m.target_url,
		m.target_window
	INTO #menu
	FROM #tree t
	JOIN #mix_menu m ON m.original = t.keyvalue
	OUTER APPLY (
		SELECT TOP 1 CAST(l.caption AS NVARCHAR(MAX)) AS caption
		FROM meta_menu l
		JOIN @fl fl ON fl.[language] = l.[language]
		WHERE l.original = m.original
		  AND l.record_type = 'L'
		  AND l.removed = 0
		  AND l.object_owner IN (@org, 0x00)
		  AND NULLIF(CAST(l.caption AS NVARCHAR(MAX)), '') IS NOT NULL
		ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org THEN 0 ELSE 1 END ASC
	) tr_cap
	OUTER APPLY (
		SELECT TOP 1 CAST(l.helptext AS NVARCHAR(MAX)) AS helptext
		FROM meta_menu l
		JOIN @fl fl ON fl.[language] = l.[language]
		WHERE l.original = m.original
		  AND l.record_type = 'L'
		  AND l.removed = 0
		  AND l.object_owner IN (@org, 0x00)
		  AND NULLIF(CAST(l.helptext AS NVARCHAR(MAX)), '') IS NOT NULL
		ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = @org THEN 0 ELSE 1 END ASC
	) tr_hlp;

	-- 5. Výpočet viditelnosti větví (Bottom-Up)
	SELECT 
		m.*,
		CASE 
			WHEN m.has_direct_access = 1 THEN 1
			WHEN EXISTS (
				SELECT 1 FROM #menu d 
				WHERE d.hierarchy_sort LIKE m.hierarchy_sort + '%' 
				  AND d.hierarchy_sort <> m.hierarchy_sort
				  AND d.has_direct_access = 1
			) THEN 1 
			ELSE 0 
		END AS has_valid_children
	INTO #final_menu
	FROM #menu m;

	-- 6. Finální výstup pro UI
	SELECT 
		f.original,
		f.parent_uuid,
		f.builtin_code,
		f.hierarchy_sort,
		f.level,
		f.caption,
		f.helptext,
		
		-- Bezpečnostní override: Odkazy vracíme VÝHRADNĚ u koncových uzlů
		CASE WHEN f.is_leaf = 1 THEN mo.builtin_code ELSE NULL END AS target_page,
		CASE WHEN f.is_leaf = 1 THEN f.target_url ELSE '' END AS target_url,
		CASE WHEN f.is_leaf = 1 THEN f.target_window ELSE '' END AS target_window,
		CASE WHEN f.is_leaf = 1 THEN f.url_parameters ELSE '' END AS url_parameters,
		
		f.svg_icon,
		f.css_class,
		
		-- Disabled stav (např. permanentní složka bez dostupného obsahu)
		CASE WHEN f.has_direct_access = 0 AND f.has_valid_children = 0 THEN 1 ELSE 0 END AS is_disabled
	FROM #final_menu f
	LEFT JOIN meta_object mo ON mo.original = f.target_object AND mo.record_type = 'A' AND mo.removed = 0
	WHERE f.has_direct_access = 1 
	   OR f.has_valid_children = 1 
	   OR f.permanent = 1
	ORDER BY f.hierarchy_sort;
	
	DROP TABLE #mix_menu;
	DROP TABLE #tree;
	DROP TABLE #menu;
	DROP TABLE #final_menu;
END
GO