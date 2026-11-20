/* =============================================================================
 * Verze: 2026-11-20 17:00
 * Soubor: p_crmm_recalculate.sql
 * Procedura: dbo.p_crmm_recalculate
 *
 * 1. Role souboru v celém systému:
 *    Centrální výpočetní procedura modulu CRMM (Custom Risk Management Module):
 *    - Přepočítá efektivní redukční faktor (effective_reduction_factor)
 *      a efektivní rizikový práh (effective_risk_factor) v tabulce
 *      countermeasure_implementation jako součin faktoru opatření
 *      (countermeasure) a váhy stavu (countermeasure_state) v % (0..100).
 *    - Přepočítá hodnocení scénářů v tabulce scenario_assessment:
 *      inherent_risk_score (normalizovaný součet logaritmicky chápaných skóre
 *      H, Z, D do intervalu 0..100 %), reduction_score (multiplikativní
 *      kombinace 100 * (1 - PROD(1 - r_i/100)) bez zkreslení nulovými/N/A
 *      opatřeními), min_risk_floor_score a residual_risk_score.
 *    - Agreguje vypočtené inherentní a reziduální riziko na jednotlivá
 *      aktiva v tabulce asset a propaguje skóre rizik po orientovaných
 *      provozních vazbách v tabulce link (Data/Host/SW -> Aplikace -> Služba).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Volána automaticky z PHP traitu entity_manager_ssc::run_post_save_hooks()
 *      (entity_manager_ssc.php) a z akčních tlačítek na stránkách
 *      page_scenario_assessment.php.
 *    - Volá proceduru dbo.p_sync_derived_links (p_sync_derived_links.sql).
 *    - Čte tabulky dbsession, countermeasure, countermeasure_state, scenario,
 *      threat, link a meta_link_def.
 *    - Aktualizuje tabulky countermeasure_implementation, scenario_assessment
 *      a asset.
 *
 * 3. Očekávaná kontextová data:
 *    - Pokud není parametr @org_uuid explicitně předán, načítá aktivní
 *      organizaci (organization) z tabulky dbsession pro aktuální @@SPID.
 *
 * Změny:
 * - 2026-11-20 17:00: V sekci 2c nahrazena chybná agregace AVG(effective_reduction_factor)
 *   multiplikativní kombinací 100 * (1 - EXP(SUM(LOG(1 - r/100)))) s ošetřením
 *   r >= 100 % a ignorováním nulové redukce (r <= 0 %, např. cm_state_na / cm_state_none).
 * - 2026-11-16 14:40: Odstraněny korelované poddotazy EXISTS / NOT EXISTS
 *   uvnitř OUTER APPLY v sekci 2b a opakované skenování tabulek link a
 *   meta_link_def v sekci 3b; nahrazeno indexovanými tabulkovými proměnnými
 *   @asset_loc_map, @asset_scope, @scen_cm_map, @scen_has_cm a @prop_edges.
 * - 2026-11-12 17:10: Odstraněny odkazy na zrušené sloupce room_uuid
 *   a building_uuid v asset (nahrazeno vazbami v tabulce link), opravena
 *   podmínka NOT EXISTS u protiopatření scénáře (omezena na vztahy
 *   countermeasure_mitigates_scenario / countermeasure_mitigates_threat)
 *   a zpřesněno šíření rizik mezi aktivy.
 * ============================================================================= */

EXECUTE dropni 'p_crmm_recalculate', 'P';
GO

CREATE PROCEDURE dbo.p_crmm_recalculate
	@org_uuid uniqueidentifier = NULL,                                         -- Cílová organizace (NULL = načte se z dbsession)
	@asset_uuid uniqueidentifier = NULL                                        -- Volitelný filtr na konkrétní aktivum (NULL = všechna)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF OBJECT_ID('asset', 'U') IS NULL
	   OR OBJECT_ID('scenario_assessment', 'U') IS NULL
	   OR OBJECT_ID('countermeasure_implementation', 'U') IS NULL
		RETURN;

	IF @org_uuid IS NULL
	BEGIN
		SELECT TOP 1 @org_uuid = ISNULL(organization, 0x00)
		FROM dbsession
		WHERE spid = @@SPID;
	END
	SET @org_uuid = ISNULL(@org_uuid, 0x00);

	-- Synchronizace odvozených a stromových vazeb v tabulce link před přepočtem
	IF OBJECT_ID('dbo.p_sync_derived_links', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_derived_links;
	END

	-- =========================================================================
	-- 1. PŘEPOČET EFEKTIVNÍCH FAKTORŮ V TABULCE countermeasure_implementation
	-- =========================================================================
	DECLARE @def_state_red decimal(9,4) = 0.0000;
	DECLARE @def_state_rsk decimal(9,4) = 100.0000;

	SELECT TOP 1
		@def_state_red = ISNULL(reduction_factor, 0.0000),
		@def_state_rsk = ISNULL(risk_factor, 100.0000)
	FROM countermeasure_state
	WHERE object_owner IN (@org_uuid, 0x00)
	  AND record_type = 'A'
	  AND removed = 0
	  AND inactive = 0
	  AND is_default = 1
	ORDER BY CASE WHEN object_owner = @org_uuid THEN 0 ELSE 1 END, sort_code;

	UPDATE ci
	SET ci.effective_reduction_factor = calc.eff_red,
		ci.effective_risk_factor = calc.eff_rsk
	FROM countermeasure_implementation ci
	OUTER APPLY (
		SELECT TOP 1
			ISNULL(cm.reduction_factor, 0.0000) AS cm_red,
			ISNULL(cm.risk_factor, 0.0000) AS cm_rsk
		FROM countermeasure cm
		WHERE cm.original = ci.countermeasure_uuid
		  AND cm.object_owner IN (@org_uuid, 0x00)
		  AND cm.record_type = 'A'
		  AND cm.removed = 0
		ORDER BY CASE WHEN cm.object_owner = @org_uuid THEN 0 ELSE 1 END
	) cm_data
	OUTER APPLY (
		SELECT TOP 1
			ISNULL(st.reduction_factor, 0.0000) AS st_red,
			ISNULL(st.risk_factor, 0.0000) AS st_rsk
		FROM countermeasure_state st
		WHERE st.original = ci.state_uuid
		  AND st.object_owner IN (@org_uuid, 0x00)
		  AND st.record_type = 'A'
		  AND st.removed = 0
		ORDER BY CASE WHEN st.object_owner = @org_uuid THEN 0 ELSE 1 END
	) st_data
	CROSS APPLY (
		SELECT
			CAST(
				CASE
					WHEN raw_red < 0.0000 THEN 0.0000
					WHEN raw_red > 100.0000 THEN 100.0000
					ELSE raw_red
				END AS decimal(9,4)
			) AS eff_red,
			CAST(
				CASE
					WHEN raw_rsk < 0.0000 THEN 0.0000
					WHEN raw_rsk > 100.0000 THEN 100.0000
					ELSE raw_rsk
				END AS decimal(9,4)
			) AS eff_rsk
		FROM (
			SELECT
				ROUND(ISNULL(cm_data.cm_red, 0.0000) * COALESCE(st_data.st_red, @def_state_red) / 100.0000, 4) AS raw_red,
				ROUND(ISNULL(cm_data.cm_rsk, 0.0000) * COALESCE(st_data.st_rsk, @def_state_rsk) / 100.0000, 4) AS raw_rsk
		) r
	) calc
	WHERE ci.object_owner = @org_uuid
	  AND ci.record_type IN ('A', 'L')
	  AND ci.removed = 0
	  AND (@asset_uuid IS NULL OR ci.asset_uuid = @asset_uuid)
	  AND EXISTS (
		SELECT ci.effective_reduction_factor, ci.effective_risk_factor
		EXCEPT
		SELECT calc.eff_red, calc.eff_rsk
	  );

	-- =========================================================================
	-- 2. PŘEPOČET HODNOCENÍ SCÉNÁŘŮ V TABULCE scenario_assessment
	-- =========================================================================
	-- 2a. Doplnění výchozího threat_score z katalogu threat, pokud je v hodnocení 0
	UPDATE sa
	SET sa.threat_score = th.default_threat_score
	FROM scenario_assessment sa
	JOIN scenario sc
		ON sc.original = sa.scenario_uuid
		AND sc.object_owner IN (@org_uuid, 0x00)
		AND sc.record_type = 'A'
		AND sc.removed = 0
	JOIN threat th
		ON th.original = sc.threat_uuid
		AND th.object_owner IN (@org_uuid, 0x00)
		AND th.record_type = 'A'
		AND th.removed = 0
	WHERE sa.object_owner = @org_uuid
	  AND sa.record_type IN ('A', 'L')
	  AND sa.removed = 0
	  AND sa.threat_score = 0.0000
	  AND ISNULL(th.default_threat_score, 0.0000) > 0.0000
	  AND (@asset_uuid IS NULL OR sa.asset_uuid = @asset_uuid);

	-- 2b. Příprava indexovaných tabulkových proměnných pro prostorové vazby a opatření scénářů
	DECLARE @asset_loc_map TABLE (
		child_asset uniqueidentifier NOT NULL,
		parent_asset uniqueidentifier NOT NULL,
		PRIMARY KEY (child_asset, parent_asset),
		INDEX ix_loc_parent (parent_asset)
	);

	INSERT INTO @asset_loc_map (child_asset, parent_asset)
	SELECT DISTINCT
		l_loc.to_object,
		l_loc.from_object
	FROM link l_loc
	JOIN meta_link_def mld_loc
		ON mld_loc.original = l_loc.link_def
		AND mld_loc.record_type = 'A'
		AND mld_loc.removed = 0
		AND mld_loc.link_code IN (
			'parent_to_child', 'room_contains_physical', 'room_contains_host',
			'room_contains_document', 'room_contains_media',
			'building_contains_room', 'building_contains_cabling'
		)
	WHERE l_loc.object_owner IN (@org_uuid, 0x00)
	  AND l_loc.record_type = 'A'
	  AND l_loc.removed = 0
	  AND l_loc.inactive = 0;

	-- Sjednocená mapa všech aktiv a jejich nadřazených prostorů/rodičů pro přímý Index Seek na countermeasure_implementation
	DECLARE @asset_scope TABLE (
		assessed_asset uniqueidentifier NOT NULL,
		scope_asset uniqueidentifier NOT NULL,
		PRIMARY KEY (assessed_asset, scope_asset),
		INDEX ix_scope_asset (scope_asset)
	);

	INSERT INTO @asset_scope (assessed_asset, scope_asset)
	SELECT DISTINCT assessed_asset, scope_asset
	FROM (
		SELECT a.original AS assessed_asset, a.original AS scope_asset
		FROM asset a
		WHERE a.object_owner IN (@org_uuid, 0x00)
		  AND a.record_type = 'A'
		  AND a.removed = 0
		  AND (@asset_uuid IS NULL OR a.original = @asset_uuid)

		UNION ALL

		SELECT a.original AS assessed_asset, a.parent_uuid AS scope_asset
		FROM asset a
		WHERE a.object_owner IN (@org_uuid, 0x00)
		  AND a.record_type = 'A'
		  AND a.removed = 0
		  AND a.parent_uuid IS NOT NULL
		  AND (@asset_uuid IS NULL OR a.original = @asset_uuid)

		UNION ALL

		SELECT lm.child_asset AS assessed_asset, lm.parent_asset AS scope_asset
		FROM @asset_loc_map lm
		WHERE (@asset_uuid IS NULL OR lm.child_asset = @asset_uuid)
	) s;

	-- Mapa metodických vazeb mezi scénářem/hrozbou a protiopatřeními
	DECLARE @scen_cm_map TABLE (
		source_obj uniqueidentifier NOT NULL,
		cm_uuid uniqueidentifier NOT NULL,
		PRIMARY KEY (source_obj, cm_uuid),
		INDEX ix_scm_cm (cm_uuid)
	);

	INSERT INTO @scen_cm_map (source_obj, cm_uuid)
	SELECT DISTINCT
		l.from_object,
		l.to_object
	FROM link l
	JOIN meta_link_def mld_cm
		ON mld_cm.original = l.link_def
		AND mld_cm.record_type = 'A'
		AND mld_cm.removed = 0
		AND mld_cm.link_code IN ('countermeasure_mitigates_scenario', 'countermeasure_mitigates_threat')
	WHERE l.object_owner IN (@org_uuid, 0x00)
	  AND l.record_type = 'A'
	  AND l.removed = 0
	  AND l.inactive = 0;

	DECLARE @scen_has_cm TABLE (
		source_obj uniqueidentifier NOT NULL PRIMARY KEY
	);

	INSERT INTO @scen_has_cm (source_obj)
	SELECT DISTINCT source_obj
	FROM @scen_cm_map;

	-- 2c. Výpočet inherentního rizika, multiplikativní redukce, spodního prahu a reziduálního rizika
	UPDATE sa
	SET sa.inherent_risk_score = calc.inh_score,
		sa.reduction_score = calc.red_score,
		sa.min_risk_floor_score = calc.floor_score,
		sa.residual_risk_score = calc.res_score
	FROM scenario_assessment sa
	OUTER APPLY (
		SELECT TOP 1
			ISNULL(sc.residual_risk_min_score, 0.0000) AS scen_min_risk,
			sc.threat_uuid
		FROM scenario sc
		WHERE sc.original = sa.scenario_uuid
		  AND sc.object_owner IN (@org_uuid, 0x00)
		  AND sc.record_type = 'A'
		  AND sc.removed = 0
		ORDER BY CASE WHEN sc.object_owner = @org_uuid THEN 0 ELSE 1 END
	) sc_info
	OUTER APPLY (
		-- Multiplikativní kombinace redukce opatření: 100 * (1 - PROD(1 - r_i / 100)) přes přímé Index Seeky
		SELECT
			CASE
				WHEN MAX(CASE WHEN ci.effective_reduction_factor >= 100.0000 THEN 1 ELSE 0 END) = 1 THEN 100.0000
				ELSE 100.0 * (
					1.0 - EXP(
						ISNULL(
							SUM(
								CASE
									WHEN ci.effective_reduction_factor > 0.0000 AND ci.effective_reduction_factor < 100.0000
										THEN LOG(1.0 - CAST(ci.effective_reduction_factor AS float) / 100.0)
									ELSE 0.0
								END
							),
							0.0
						)
					)
				)
			END AS comb_red,
			ISNULL(MAX(ci.effective_risk_factor), 0.0000) AS max_rsk
		FROM @asset_scope ascope
		JOIN countermeasure_implementation ci
			ON ci.asset_uuid = ascope.scope_asset
			AND ci.object_owner = @org_uuid
			AND ci.record_type = 'A'
			AND ci.removed = 0
			AND ci.inactive = 0
		LEFT JOIN @scen_has_cm shc_s ON shc_s.source_obj = sa.scenario_uuid
		LEFT JOIN @scen_has_cm shc_t ON shc_t.source_obj = sc_info.threat_uuid
		LEFT JOIN @scen_cm_map scm_s ON scm_s.source_obj = sa.scenario_uuid AND scm_s.cm_uuid = ci.countermeasure_uuid
		LEFT JOIN @scen_cm_map scm_t ON scm_t.source_obj = sc_info.threat_uuid AND scm_t.cm_uuid = ci.countermeasure_uuid
		WHERE ascope.assessed_asset = sa.asset_uuid
		  AND (
			(shc_s.source_obj IS NULL AND shc_t.source_obj IS NULL)
			OR scm_s.cm_uuid IS NOT NULL
			OR scm_t.cm_uuid IS NOT NULL
		  )
	) cm_agg
	CROSS APPLY (
		SELECT
			inh_val AS inh_score,
			red_val AS red_score,
			flr_val AS floor_score,
			CAST(
				CASE
					WHEN reduced_raw < flr_val THEN flr_val
					WHEN reduced_raw > 100.0000 THEN 100.0000
					WHEN reduced_raw < 0.0000 THEN 0.0000
					ELSE reduced_raw
				END AS decimal(9,4)
			) AS res_score
		FROM (
			SELECT
				inh_val,
				red_val,
				flr_val,
				ROUND(inh_val * (100.0000 - red_val) / 100.0000, 4) AS reduced_raw
			FROM (
				SELECT
					CAST(
						ROUND(
							(
								CASE WHEN sa.threat_score < 0 THEN 0 WHEN sa.threat_score > 100 THEN 100 ELSE sa.threat_score END
								+ CASE WHEN sa.vulnerability_score < 0 THEN 0 WHEN sa.vulnerability_score > 100 THEN 100 ELSE sa.vulnerability_score END
								+ CASE WHEN sa.impact_score < 0 THEN 0 WHEN sa.impact_score > 100 THEN 100 ELSE sa.impact_score END
							) / 3.0000,
							4
						) AS decimal(9,4)
					) AS inh_val,
					CAST(
						CASE
							WHEN ISNULL(cm_agg.comb_red, 0.0) < 0.0 THEN 0.0000
							WHEN ISNULL(cm_agg.comb_red, 0.0) > 100.0 THEN 100.0000
							ELSE ROUND(ISNULL(cm_agg.comb_red, 0.0), 4)
						END AS decimal(9,4)
					) AS red_val,
					CAST(
						ROUND(
							CASE
								WHEN ISNULL(sc_info.scen_min_risk, 0.0000) >= ISNULL(cm_agg.max_rsk, 0.0000)
									THEN ISNULL(sc_info.scen_min_risk, 0.0000)
								ELSE ISNULL(cm_agg.max_rsk, 0.0000)
							END,
							4
						) AS decimal(9,4)
					) AS flr_val
			) base_calc
		) step_calc
	) calc
	WHERE sa.object_owner = @org_uuid
	  AND sa.record_type IN ('A', 'L')
	  AND sa.removed = 0
	  AND (@asset_uuid IS NULL OR sa.asset_uuid = @asset_uuid)
	  AND EXISTS (
		SELECT sa.inherent_risk_score, sa.reduction_score, sa.min_risk_floor_score, sa.residual_risk_score
		EXCEPT
		SELECT calc.inh_score, calc.red_score, calc.floor_score, calc.res_score
	  );

	-- =========================================================================
	-- 3. AGREGACE RIZIK NA AKTIVA A ŠÍŘENÍ PO VAZBÁCH V TABULCE link
	-- =========================================================================
	DECLARE @asset_scores TABLE (
		asset_uuid uniqueidentifier NOT NULL PRIMARY KEY,
		direct_inh decimal(9,4) NULL,
		direct_res decimal(9,4) NULL,
		prop_inh decimal(9,4) NULL,
		prop_res decimal(9,4) NULL
	);

	-- 3a. Přímé skóre aktiva z jeho vlastních hodnocených scénářů (scenario_assessment)
	INSERT INTO @asset_scores (asset_uuid, direct_inh, direct_res, prop_inh, prop_res)
	SELECT
		a.original,
		sa_agg.max_inh,
		sa_agg.max_res,
		sa_agg.max_inh,
		sa_agg.max_res
	FROM asset a
	OUTER APPLY (
		SELECT
			CAST(ROUND(MAX(sa.inherent_risk_score), 4) AS decimal(9,4)) AS max_inh,
			CAST(ROUND(MAX(sa.residual_risk_score), 4) AS decimal(9,4)) AS max_res
		FROM scenario_assessment sa
		WHERE sa.asset_uuid = a.original
		  AND sa.object_owner = @org_uuid
		  AND sa.record_type = 'A'
		  AND sa.removed = 0
		  AND sa.inactive = 0
	) sa_agg
	WHERE a.object_owner IN (@org_uuid, 0x00)
	  AND a.record_type = 'A'
	  AND a.removed = 0;

	-- 3b. Načtení aktivních orientovaných hran pro šíření rizik do indexované tabulkové proměnné
	DECLARE @prop_edges TABLE (
		from_object uniqueidentifier NOT NULL,
		to_object uniqueidentifier NOT NULL,
		weight_factor decimal(9,4) NOT NULL,
		PRIMARY KEY (from_object, to_object),
		INDEX ix_prop_to (to_object)
	);

	INSERT INTO @prop_edges (from_object, to_object, weight_factor)
	SELECT
		l.from_object,
		l.to_object,
		MAX(CASE WHEN ISNULL(l.link_weight, 0) > 0 AND l.link_weight <= 100 THEN CAST(ROUND(l.link_weight / 100.0000, 4) AS decimal(9,4)) ELSE 1.0000 END)
	FROM link l
	JOIN meta_link_def mld
		ON mld.original = l.link_def
		AND mld.record_type = 'A'
		AND mld.removed = 0
		AND mld.is_exclusive_parent = 0
		AND mld.link_code <> 'asset_additional_class'
	WHERE l.object_owner IN (@org_uuid, 0x00)
	  AND l.record_type = 'A'
	  AND l.removed = 0
	  AND l.inactive = 0
	  AND l.from_object <> l.to_object
	GROUP BY l.from_object, l.to_object;

	-- Vícekrokový přenos rizik v paměti přes @prop_edges
	DECLARE @pass int = 1;
	WHILE @pass <= 6
	BEGIN
		UPDATE src
		SET src.prop_inh = CASE
				WHEN ISNULL(dep.max_dep_inh, 0.0000) > ISNULL(src.prop_inh, 0.0000) THEN dep.max_dep_inh
				ELSE src.prop_inh
			END,
			src.prop_res = CASE
				WHEN ISNULL(dep.max_dep_res, 0.0000) > ISNULL(src.prop_res, 0.0000) THEN dep.max_dep_res
				ELSE src.prop_res
			END
		FROM @asset_scores src
		CROSS APPLY (
			SELECT
				MAX(CAST(ROUND(target_sc.prop_inh * pe.weight_factor, 4) AS decimal(9,4))) AS max_dep_inh,
				MAX(CAST(ROUND(target_sc.prop_res * pe.weight_factor, 4) AS decimal(9,4))) AS max_dep_res
			FROM @prop_edges pe
			JOIN @asset_scores target_sc ON target_sc.asset_uuid = pe.to_object
			WHERE pe.from_object = src.asset_uuid
			  AND target_sc.prop_res IS NOT NULL
		) dep
		WHERE dep.max_dep_inh > ISNULL(src.prop_inh, -1.0000)
		   OR dep.max_dep_res > ISNULL(src.prop_res, -1.0000);

		IF @@ROWCOUNT = 0
			BREAK;

		SET @pass = @pass + 1;
	END

	-- 3c. Zápis vypočtených agregovaných skóre do tabulky asset (A i L záznamy tenanta)
	UPDATE a
	SET a.inherent_risk_score = sc.prop_inh,
		a.residual_risk_score = sc.prop_res
	FROM asset a
	JOIN @asset_scores sc ON sc.asset_uuid = a.original
	WHERE a.object_owner = @org_uuid
	  AND a.record_type IN ('A', 'L')
	  AND a.removed = 0
	  AND (@asset_uuid IS NULL OR a.original = @asset_uuid)
	  AND EXISTS (
		SELECT a.inherent_risk_score, a.residual_risk_score
		EXCEPT
		SELECT sc.prop_inh, sc.prop_res
	  );
END
GO