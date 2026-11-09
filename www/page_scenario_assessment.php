<?php
/**
 * =============================================================================
 * Verze: 2026-11-09 16:30
 * Soubor: page_scenario_assessment.php
 * Třída: page_scenario_assessment
 * Účel: Hodnocení velikosti hrozby, zranitelnosti, dopadu a vypočteného
 *       inherentního i reziduálního rizika scénářů (scenario) nad konkrétními
 *       aktivy (asset) se zařazením do stupňů primární škály rizika (semaforu).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_scenario_assessment`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'scenario_assessment'`.
 * - Při uložení záznamu (nebo stisku tlačítka Přepočítat rizika CRMM) volá
 *   proceduru `dbo.p_crmm_recalculate` (`p_crmm_recalculate.sql`).
 * =============================================================================
 */

declare(strict_types=1);

class page_scenario_assessment extends abstract_page_master_detail {

	private string $filter_asset_uuid = '';                                  // Volitelný filtr na konkrétní aktivum (asset.original)
	private string $filter_asset_caption = '';                               // Název filtrovaného aktiva

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'scenario_assessment';                           // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových hodnocení scénářů
		$this->page_title = $this->phrase('page_title', [], 'Hodnocení rizikových scénářů (CRMM)'); // Titulek stránky

		if ($this->access_denied) {                                          // Pokud předek zamítl přístup
			return;                                                          // Ukončení inicializace
		}

		$this->filter_asset_uuid = trim((string) getinput('asset_uuid'));    // Načtení filtru aktiva z URL
		if ($this->filter_asset_uuid !== '' AND is_guid($this->filter_asset_uuid)) { // Pokud je zadáno platné UUID aktiva
			$a_lit = guidliteral($this->filter_asset_uuid);                  // SQL literál aktiva
			$this->master_where = "m.asset_uuid = {$a_lit}";                 // Omezení seznamu na vybrané aktivum
			$a_row = sqlfirstrow("SELECT TOP 1 caption, builtin_code FROM asset WHERE original = {$a_lit} AND record_type = 'A' AND removed = 0"); // Název aktiva
			if (! empty($a_row)) {                                           // Pokud aktivum existuje
				$this->filter_asset_caption = (string) ($a_row['caption'] ?: $a_row['builtin_code']); // Uložení názvu aktiva
			}
		}

		if ($this->em === null) {                                            // Inicializace správce entit pro nastavení sloupců seznamu
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance entity_manageru
		}
		$this->em->set_list_columns([                                        // Přehledné sloupce v levém Master panelu
			'caption'             => $this->phrase('th_assess_caption', [], 'Hodnocený scénář / Popis'),
			'inherent_risk_score' => $this->phrase('th_inherent_risk', [], 'Inh. riziko (%)'),
			'residual_risk_score' => $this->phrase('th_residual_risk', [], 'Rez. riziko (%)'),
			'assessment_date'     => $this->phrase('th_assess_date', [], 'Datum')
		]);                                                                  // Konec definice sloupců seznamu

		$grp_rel  = $this->phrase('grp_asset_scenario', [], 'Hodnocené aktivum a rizikový scénář'); // Sekce klíčových vazeb
		$grp_in   = $this->phrase('grp_input_scores', [], 'Vstupní hodnocení hrozby, zranitelnosti a dopadu (0 až 100 %)'); // Vstupní skóre
		$grp_out  = $this->phrase('grp_calculated_risk', [], 'Vypočtené inherentní riziko, redukce a zbytkové riziko (0 až 100 %)'); // Výsledky
		$grp_pres = $this->phrase('grp_justification_audit', [], 'Zdůvodnění hodnocení, poznámka a odpovědná osoba'); // Zdůvodnění

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_rel  => ['asset_uuid', 'scenario_uuid', 'builtin_code', 'external_code'], // Hodnocené aktivum a scénář
			$grp_in   => ['threat_score', 'vulnerability_score', 'impact_score'], // Vstupní procentuální skóre (0..100 %)
			$grp_out  => ['inherent_risk_score', 'reduction_score', 'min_risk_floor_score', 'residual_risk_score'], // Vypočtená skóre
			$grp_pres => ['caption', 'description_text', 'note', 'assessor_user_uuid', 'assessment_date', 'valid_from', 'valid_to', 'inactive'] // Texty a garant
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Rozšíří kontextový přívažek URL o parametr `asset_uuid`.
	 */
	protected function get_context_url_suffix(): string {
		$suffix = parent::get_context_url_suffix();                          // Základní kontextové parametry z předka
		if ($this->filter_asset_uuid !== '' AND ! str_contains($suffix, '&asset_uuid=')) { // Zachování filtru aktiva
			$suffix .= '&asset_uuid=' . urlencode($this->filter_asset_uuid); // Připojení asset_uuid
		}
		return $suffix;                                                      // Vrácení přívažku URL
	}

	/**
	 * Zpracuje případný požadavek na celkový přepočet rizik (`btn_recalculate_crmm`)
	 * a následně zavolá standardní uložení formuláře.
	 */
	protected function process_save(): void {
		if (isset($_POST['btn_recalculate_crmm'])) {                         // Ruční spuštění přepočtu rizik CRMM
			$org_sql = guidliteral(get_session_org());                       // SQL literál aktivní organizace
			sqlrun("EXEC dbo.p_crmm_recalculate @org_uuid = {$org_sql}");    // Spuštění přepočtu všech faktorů a rizik
			$url_suffix = $this->get_context_url_suffix();                   // Kontextové parametry URL
			$upd = trim((string) getinput('update_guid'));                   // Případně otevřený záznam v detailu
			$upd_part = ($upd !== '') ? ('&update_guid=' . urlencode($upd)) : ''; // Zachování otevřeného detailu
			autoredirect("index.php?page=page_scenario_assessment{$url_suffix}{$upd_part}"); // PRG redirect
			return;                                                          // Ukončení
		}

		parent::process_save();                                              // Standardní uložení záznamu v předkovi
	}

	/**
	 * Zařadí procentuální skóre (0..100 %) do stupně primární hodnotící škály daného typu (`scale_type`).
	 *
	 * @return array{caption: string, shortname: string, color_code: string}
	 */
	private function resolve_scale_level_badge(string $scale_type, float $score): array { // Vyhodnocení stupně škály
		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace
		$lang_sql = charliteral(get_session_lang(), 2);                      // SQL literál jazyka relace
		$safe_type = charliteral($scale_type, 20);                           // SQL literál druhu škály
		$score_sql = number_format(max(0.0, min(100.0, $score)), 4, '.', ''); // Ošetřené skóre v rozsahu 0..100

		$row = sqlfirstrow("
			SELECT TOP 1
				COALESCE(NULLIF(l.caption, ''), sv.caption, sv.builtin_code) AS caption,
				COALESCE(NULLIF(l.shortname, ''), sv.shortname, '') AS shortname,
				sv.color_code
			FROM scale sc
			JOIN scale_value sv
				ON sv.scale = sc.original
				AND sv.object_owner IN ({$org_sql}, 0x00)
				AND sv.record_type = 'A'
				AND sv.removed = 0
				AND sv.inactive = 0
			LEFT JOIN scale_value l
				ON l.original = sv.original
				AND l.object_owner IN ({$org_sql}, 0x00)
				AND l.record_type = 'L'
				AND l.[language] = {$lang_sql}
				AND l.removed = 0
			WHERE sc.scale_type = {$safe_type}
			  AND sc.object_owner IN ({$org_sql}, 0x00)
			  AND sc.record_type = 'A'
			  AND sc.removed = 0
			  AND sc.inactive = 0
			  AND sv.threshold_value <= {$score_sql}
			ORDER BY
				CASE WHEN sc.is_default = 1 THEN 0 ELSE 1 END ASC,
				sc.priority ASC,
				CASE WHEN sc.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC,
				sv.threshold_value DESC
		");                                                                  // Nalezení stupně škály podle dolního prahu threshold_value

		return [                                                             // Vrácení názvu, zkratky a barvy stupně
			'caption'    => (string) ($row['caption'] ?? ''),
			'shortname'  => (string) ($row['shortname'] ?? ''),
			'color_code' => (string) ($row['color_code'] ?? '')
		];
	}

	/**
	 * Vykreslí horní lištu levého panelu (návrat na aktivum, filtr aktiva, tlačítko přepočtu a + Nové hodnocení).
	 */
	protected function render_master_top(): void {
		if ($this->filter_asset_uuid !== '') {                               // Návratové tlačítko při příchodu z detailu aktiva
			$back_url = "index.php?page=page_asset&update_guid=" . urlencode($this->filter_asset_uuid); // URL aktiva
			$btn_back = new abstract_button('btn_back_to_asset', '← Zpět na aktivum: {' . chr(36) . 'asset}', 'page_scenario_assessment', '', 'btn-secondary'); // Tlačítko
			$btn_back->set_href($back_url)                                   // Nastavení cílové URL
				->set_vars(['asset' => $this->filter_asset_caption ?: $this->filter_asset_uuid]) // Název aktiva
				->set_style('width: 100%; justify-content: center; margin-bottom: 8px;'); // Stylování
			echo $btn_back->render();                                         // Vykreslení tlačítka
		}

		$lbl_all = htmlspecialchars($this->phrase('opt_all_assets', [], '--- Všechna hodnocená aktiva ---')); // Volba všech aktiv
		$options_html = "<option value=\"\">{$lbl_all}</option>";            // První položka roletky
		$as_meta = ($this->em !== null) ? $this->em->get_column_meta('asset_uuid') : []; // Metadata sloupce asset_uuid
		$ref_cls = guidliteral((string) ($as_meta['referenced_class'] ?? '')); // UUID třídy asset
		if ($ref_cls !== 'NULL') {                                           // Načtení aktiv přes p_em_get_select_options
			$as_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'ref_class', @param_code = 'asset_uuid', @ref_class_uuid = {$ref_cls}"); // Aktiva
			if (is_array($as_rows)) {                                        // Průchod aktivy
				foreach ($as_rows as $ar) {                                  // Zpracování aktiva
					$u = (string) $ar['original'];                           // UUID aktiva
					$c = (string) $ar['code_col'];                           // Kód aktiva
					$cp = (string) $ar['caption'];                           // Název aktiva
					$sel = (strcasecmp($u, $this->filter_asset_uuid) === 0) ? 'selected' : ''; // Označení vybraného aktiva
					$lbl = ($cp !== '' AND $cp !== $c) ? "{$cp} ({$c})" : ($cp ?: $c); // Popisek volby
					$options_html .= '<option value="' . htmlspecialchars($u) . '" ' . $sel . '>' . htmlspecialchars($lbl) . '</option>'; // Volba
				}
			}
		}

		$lbl_flt = htmlspecialchars($this->phrase('lbl_filter_asset', [], 'Hodnocené aktivum:')); // Popisek roletky

		echo <<<HTML
		<div style="margin-bottom: 10px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_flt}</label>
			<select onchange="document.location='index.php?page=page_scenario_assessment&asset_uuid=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;

		if ($this->allow_insert) {                                           // Tlačítka pro nové hodnocení a přepočet rizik
			$url_suffix = $this->get_context_url_suffix();                   // Přívažek URL
			$new_url = "index.php?page=page_scenario_assessment{$url_suffix}&update_guid=NEW"; // URL nového hodnocení
			$btn_new = new abstract_button('btn_new_assessment', '+ Nové hodnocení scénáře', 'page_scenario_assessment'); // Tlačítko
			$btn_new->set_href($new_url)                                     // Nastavení cílové URL
				->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
				->set_style('flex: 1; justify-content: center;');            // Stylování

			$btn_recalc = new abstract_button('btn_recalculate_crmm', '↻ Přepočítat rizika', 'page_scenario_assessment', '', 'btn-secondary'); // Tlačítko přepočtu
			$btn_recalc->set_type('submit')->set_name_value('btn_recalculate_crmm', '1')->set_onclick('isFormDirty = false;'); // Submit přepočtu

			$act_url = htmlspecialchars("index.php?page=page_scenario_assessment{$url_suffix}"); // URL formuláře přepočtu
			echo "<form method=\"post\" action=\"{$act_url}\" style=\"display: flex; gap: 6px; margin-bottom: 10px;\">" . $btn_new->render() . $btn_recalc->render() . "</form>\n"; // Lišta tlačítek
		}
	}

	/**
	 * Sestaví nadpis pravého detailního panelu.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Zakládání nového hodnocení
			return htmlspecialchars($this->phrase('header_new_assessment', [], 'Nové hodnocení rizikového scénáře')); // Nadpis nového záznamu
		}
		$cap = htmlspecialchars((string) ($datarow['caption'] ?: $datarow['builtin_code'] ?: '')); // Popis hodnocení
		$lbl = htmlspecialchars($this->phrase('header_edit_assessment', [], 'Hodnocení scénáře')); // Návěstí
		return "{$lbl}: <span style=\"color: #555;\">{$cap}</span>";         // Výsledný nadpis
	}

	/**
	 * Předvyplní výchozí údaje u nového hodnocení a vykreslí semafor výsledného rizika podle hodnotící škály.
	 */
	protected function render_detail_top(): void {
		global $datarow, $dbsession;                                         // Aktuální řádek detailu a relace
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nové hodnocení
			if ($this->filter_asset_uuid !== '') {                           // Předvyplnění aktiva z filtru
				$datarow['asset_uuid'] = $this->filter_asset_uuid;           // Nastavení asset_uuid
			}
			$datarow['assessment_date'] = date('Y-m-d');                     // Dnešní datum hodnocení
			$datarow['assessor_user_uuid'] = (string) ($dbsession['user_account'] ?? ''); // Přihlášený uživatel jako hodnotitel
		}

		if ($update_guid !== '' AND $update_guid !== 'NEW' AND is_array($datarow)) { // Semafor výsledného rizika u uloženého hodnocení
			$inh_val = (float) ($datarow['inherent_risk_score'] ?? 0);       // Inherentní riziko v %
			$red_val = (float) ($datarow['reduction_score'] ?? 0);           // Redukce opatřeními v %
			$flr_val = (float) ($datarow['min_risk_floor_score'] ?? 0);      // Spodní práh rizika v %
			$res_val = (float) ($datarow['residual_risk_score'] ?? 0);       // Zbytkové riziko v %

			$inh_fmt = number_format($inh_val, 2, '.', ' ');                 // Formátované inherentní riziko
			$red_fmt = number_format($red_val, 2, '.', ' ');                 // Formátovaná redukce
			$flr_fmt = number_format($flr_val, 2, '.', ' ');                 // Formátovaný spodní práh
			$res_fmt = number_format($res_val, 2, '.', ' ');                 // Formátované zbytkové riziko

			$lvl_info = $this->resolve_scale_level_badge('RISK', $res_val);  // Zařazení zbytkového rizika do stupně škály RISK
			$lvl_html = '';                                                  // HTML štítku stupně škály
			if ($lvl_info['caption'] !== '') {                               // Pokud existuje primární škála pro RISK
				$bg_col = ($lvl_info['color_code'] !== '') ? htmlspecialchars($lvl_info['color_code']) : '#004488'; // Barva semaforu
				$safe_lcap = htmlspecialchars($lvl_info['caption']);         // Název stupně
				$lvl_html = "<span style=\"display: inline-block; margin-left: 8px; padding: 2px 8px; border-radius: 3px; background-color: {$bg_col}; color: #fff; font-weight: bold; font-size: 12px;\">{$safe_lcap}</span>"; // Odznak stupně
			}

			$lbl_inh = htmlspecialchars($this->phrase('lbl_sum_inherent', [], 'Inherentní riziko:')); // Popisek inherentního rizika
			$lbl_red = htmlspecialchars($this->phrase('lbl_sum_reduction', [], 'Redukce opatřeními:')); // Popisek redukce
			$lbl_flr = htmlspecialchars($this->phrase('lbl_sum_floor', [], 'Min. práh:')); // Popisek spodního prahu
			$lbl_res = htmlspecialchars($this->phrase('lbl_sum_residual', [], 'Zbytkové (reziduální) riziko:')); // Popisek zbytkového rizika

			echo <<<HTML
			<div style="margin-bottom: 14px; padding: 10px 14px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-left: 4px solid #004488; border-radius: 4px; font-size: 13px; display: flex; justify-content: space-between; align-items: center; gap: 16px; flex-wrap: wrap;">
				<div><strong>{$lbl_inh}</strong> <span style="font-family: monospace;">{$inh_fmt} %</span></div>
				<div><strong>{$lbl_red}</strong> <span style="font-family: monospace; color: #15803d;">-{$red_fmt} %</span></div>
				<div><strong>{$lbl_flr}</strong> <span style="font-family: monospace; color: #64748b;">{$flr_fmt} %</span></div>
				<div><strong>{$lbl_res}</strong> <span style="font-family: monospace; font-weight: bold; font-size: 14px; color: #0f172a;">{$res_fmt} %</span>{$lvl_html}</div>
			</div>
HTML;
		}
	}
}