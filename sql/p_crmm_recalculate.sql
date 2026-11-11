/* =============================================================================
 * Verze: 2026-11-11 21:30
 * Soubor: p_crmm_recalculate.sql
 * Procedura: dbo.p_crmm_recalculate
 * Účel:   Centrální výpočetní procedura modulu CRMM (Custom Risk Management Module):
 *         1. Přepočítá efektivní redukční faktor (effective_reduction_factor)
 *            a efektivní rizikový práh (effective_risk_factor) v tabulce
 *            countermeasure_implementation jako součin faktoru opatření
 *            (countermeasure) a váhy stavu (countermeasure_state) v % (0..100).
 *         2. Přepočítá hodnocení scénářů v tabulce scenario_assessment:
 *            - inherent_risk_score (normalizovaný průměr hrozby, zranitelnosti
 *              a dopadu v intervalu 0..100 %),
 *            - reduction_score (průměrná efektivní redukce z opatření
 *              aplikovaných na daném aktivu či jeho nadřazeném prostoru v link
 *              a navázaných na scénář/hrozbu přes countermeasure_mitigates_*),
 *            - min_risk_floor_score (maximum ze scenario.residual_risk_min_score
 *              a efektivního rizikového faktoru neimplementovaných opatření),
 *            - residual_risk_score (zbytkové riziko po redukci, omezené shora 100 %
 *              a zdola prahem min_risk_floor_score).
 *         3. Agreguje vypočtené inherentní a reziduální riziko na jednotlivá
 *            aktiva v tabulce asset a propaguje skóre rizik po orientovaných
 *            provozních a prostorových vazbách v tabulce link.
 * Vazby:  - Volána automaticky z entity_manager_ssc::run_post_save_hooks()
 *           a z akčních tlačítek na stránkách page_asset, page_scenario_assessment
 *           a page_countermeasure_implementation.
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

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @mld_cm_scen uniqueidentifier = dbo.f_generate_original('meta_link_def', @sys_owner, 'countermeasure_mitigates_scenario', '');
	DECLARE @mld_cm_thrt uniqueidentifier = dbo.f_generate_original('meta_link_def', @sys_owner, 'countermeasure_mitigates_threat', '');

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

	-- 2b. Výpočet inherentního rizika, redukce, spodního prahu a reziduálního rizika
	UPDATE sa
	SET sa.inherent_risk_score = calc.inh_score,
		sa.reduction_score = calc.red_score,
		sa.min_risk_floor_score = calc.floor_score,
		sa.residual_risk_score = calc.res_score
	FROM scenario_assessment sa
	LEFT JOIN asset a
		ON a.original = sa.asset_uuid
		AND a.object_owner IN (@org_uuid, 0x00)
		AND a.record_type = 'A'
		AND a.removed = 0
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
		-- Aplikovaná protiopatření na hodnoceném aktivu nebo na nadřazeném prostoru/aktivu v tabulce link.
		-- Kontrola specifických opatření scénáře/hrozby je omezena výhradně na vztahy countermeasure_mitigates_*.
		SELECT
			ISNULL(AVG(ci.effective_reduction_factor), 0.0000) AS avg_red,
			ISNULL(MAX(ci.effective_risk_factor), 0.0000) AS max_rsk
		FROM countermeasure_implementation ci
		WHERE ci.object_owner = @org_uuid
		  AND ci.record_type = 'A'
		  AND ci.removed = 0
		  AND ci.inactive = 0
		  AND (
			ci.asset_uuid = sa.asset_uuid
			OR ci.asset_uuid = a.parent_uuid
			OR EXISTS (
				SELECT 1
				FROM link loc_l
				WHERE loc_l.from_object = sa.asset_uuid
				  AND loc_l.to_object = ci.asset_uuid
				  AND loc_l.object_owner IN (@org_uuid, 0x00)
				  AND loc_l.record_type = 'A'
				  AND loc_l.removed = 0
				  AND loc_l.inactive = 0
			)
		  )
		  AND (
			NOT EXISTS (
				SELECT 1
				FROM link l
				WHERE l.from_object IN (sa.scenario_uuid, sc_info.threat_uuid)
				  AND l.link_def IN (@mld_cm_scen, @mld_cm_thrt)
				  AND l.object_owner IN (@org_uuid, 0x00)
				  AND l.record_type = 'A'
				  AND l.removed = 0
				  AND l.inactive = 0
			)
			OR EXISTS (
				SELECT 1
				FROM link l
				WHERE l.from_object IN (sa.scenario_uuid, sc_info.threat_uuid)
				  AND l.link_def IN (@mld_cm_scen, @mld_cm_thrt)
				  AND l.to_object = ci.countermeasure_uuid
				  AND l.object_owner IN (@org_uuid, 0x00)
				  AND l.record_type = 'A'
				  AND l.removed = 0
				  AND l.inactive = 0
			)
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
					CAST(ROUND(ISNULL(cm_agg.avg_red, 0.0000), 4) AS decimal(9,4)) AS red_val,
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
	-- 3. AGREGACE RIZIK NA AKTIVA A ŠÍŘENÍ PO ORIENTOVANÝCH VAZBÁCH V TABULCE link
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

	-- 3b. Vícekrokový přenos rizik po orientovaných závislostech v tabulce link (direction_type IN ('P', 'S'))
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
				MAX(
					CAST(
						ROUND(
							target_sc.prop_inh * CASE WHEN ISNULL(l.link_weight, 0) > 0 AND l.link_weight <= 100 AND l.diagram_uuid IS NULL THEN l.link_weight / 100.0000 ELSE 1.0000 END,
							4
						) AS decimal(9,4)
					)
				) AS max_dep_inh,
				MAX(
					CAST(
						ROUND(
							target_sc.prop_res * CASE WHEN ISNULL(l.link_weight, 0) > 0 AND l.link_weight <= 100 AND l.diagram_uuid IS NULL THEN l.link_weight / 100.0000 ELSE 1.0000 END,
							4
						) AS decimal(9,4)
					)
				) AS max_dep_res
			FROM link l
			JOIN meta_link_def mld
				ON mld.original = l.link_def
				AND mld.record_type = 'A'
				AND mld.removed = 0
				AND mld.direction_type IN ('P', 'S')
			JOIN @asset_scores target_sc ON target_sc.asset_uuid = l.to_object
			WHERE l.from_object = src.asset_uuid
			  AND l.object_owner IN (@org_uuid, 0x00)
			  AND l.record_type = 'A'
			  AND l.removed = 0
			  AND l.inactive = 0
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