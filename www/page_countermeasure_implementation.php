<?php
/**
 * =============================================================================
 * Verze: 2026-11-09 16:30
 * Soubor: page_countermeasure_implementation.php
 * Třída: page_countermeasure_implementation
 * Účel: Evidence skutečného stavu zavedení protiopatření (countermeasure)
 *       na konkrétních aktivech a prostorech (asset) s automatickým výpočtem
 *       efektivního redukčního a rizikového faktoru (0 až 100 %).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_countermeasure_implementation`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou
 *   `'countermeasure_implementation'`.
 * - Při uložení záznamu automaticky spouští `dbo.p_crmm_recalculate` přes
 *   `entity_manager_ssc::run_post_save_hooks()`.
 * =============================================================================
 */

declare(strict_types=1);

class page_countermeasure_implementation extends abstract_page_master_detail {

	private string $filter_asset_uuid = '';                                  // Volitelný filtr na konkrétní aktivum (asset.original)
	private string $filter_asset_caption = '';                               // Název filtrovaného aktiva

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'countermeasure_implementation';                 // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových implementací opatření
		$this->page_title = $this->phrase('page_title', [], 'Implementace protiopatření (CRMM)'); // Titulek stránky

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
			'caption'                    => $this->phrase('th_impl_caption', [], 'Popis implementace / Opatření'),
			'effective_reduction_factor' => $this->phrase('th_eff_reduction', [], 'Ef. redukce (%)'),
			'effective_risk_factor'      => $this->phrase('th_eff_risk', [], 'Ef. práh rizika (%)'),
			'target_date'                => $this->phrase('th_target_date', [], 'Termín')
		]);                                                                  // Konec definice sloupců seznamu

		$grp_rel  = $this->phrase('grp_asset_cm_state', [], 'Chráněné aktivum, aplikované protiopatření a stav zavedení'); // Sekce vazeb
		$grp_pres = $this->phrase('grp_presentation', [], 'Popis realizace opatření a poznámky z kontroly'); // Sekce textů
		$grp_resp = $this->phrase('grp_responsibility_factors', [], 'Odpovědnost, termíny a vypočtené efektivní faktory (0 až 100 %)'); // Sekce faktorů
		$grp_val  = $this->phrase('grp_validity', [], 'Platnost záznamu');   // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_rel  => ['asset_uuid', 'countermeasure_uuid', 'state_uuid', 'builtin_code', 'external_code'], // Klíčové vazby
			$grp_pres => ['caption', 'description_text', 'note'],            // Popis realizace a poznámka
			$grp_resp => ['responsible_user_uuid', 'target_date', 'completion_date', 'effective_reduction_factor', 'effective_risk_factor'], // Termíny a faktory
			$grp_val  => ['valid_from', 'valid_to', 'inactive']              // Platnost
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
	 * Vykreslí v horní části levého panelu návratové tlačítko na aktivum, filtr aktiva a tlačítko + Nová implementace.
	 */
	protected function render_master_top(): void {
		if ($this->filter_asset_uuid !== '') {                               // Návratové tlačítko při příchodu z detailu aktiva
			$back_url = "index.php?page=page_asset&update_guid=" . urlencode($this->filter_asset_uuid); // URL aktiva
			$btn_back = new abstract_button('btn_back_to_asset', '← Zpět na aktivum: {' . chr(36) . 'asset}', 'page_countermeasure_implementation', '', 'btn-secondary'); // Tlačítko
			$btn_back->set_href($back_url)                                   // Nastavení cílové URL
				->set_vars(['asset' => $this->filter_asset_caption ?: $this->filter_asset_uuid]) // Název aktiva
				->set_style('width: 100%; justify-content: center; margin-bottom: 8px;'); // Stylování
			echo $btn_back->render();                                         // Vykreslení tlačítka
		}

		$lbl_all = htmlspecialchars($this->phrase('opt_all_assets', [], '--- Všechna aktiva a prostory ---')); // Volba všech aktiv
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

		$lbl_flt = htmlspecialchars($this->phrase('lbl_filter_asset', [], 'Chráněné aktivum / prostor:')); // Popisek roletky

		echo <<<HTML
		<div style="margin-bottom: 10px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_flt}</label>
			<select onchange="document.location='index.php?page=page_countermeasure_implementation&asset_uuid=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;

		if ($this->allow_insert) {                                           // Tlačítko pro založení nové implementace opatření
			$url_suffix = $this->get_context_url_suffix();                   // Přívažek URL
			$new_url = "index.php?page=page_countermeasure_implementation{$url_suffix}&update_guid=NEW"; // Cílová URL
			$btn_new = new abstract_button('btn_new_cm_impl', '+ Nová implementace opatření', 'page_countermeasure_implementation'); // Tlačítko
			$btn_new->set_href($new_url)                                     // Nastavení cílové URL
				->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
				->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Stylování
			echo $btn_new->render();                                         // Vykreslení tlačítka
		}
	}

	/**
	 * Sestaví nadpis pravého detailního panelu.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Zakládání nového záznamu
			return htmlspecialchars($this->phrase('header_new_cm_impl', [], 'Nová implementace protiopatření')); // Nadpis pro nový záznam
		}
		$cap = htmlspecialchars((string) ($datarow['caption'] ?: $datarow['builtin_code'] ?: '')); // Popis implementace
		$lbl = htmlspecialchars($this->phrase('header_edit_cm_impl', [], 'Implementace opatření')); // Návěstí
		return "{$lbl}: <span style=\"color: #555;\">{$cap}</span>";         // Výsledný nadpis
	}

	/**
	 * Předvyplní aktivum a výchozí stav u nového záznamu a zobrazí přehledový proužek efektivních faktorů.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace

		if ($this->em !== null) {                                            // Vypočítávané efektivní faktory uzamkneme jako readonly
			foreach (['effective_reduction_factor', 'effective_risk_factor'] as $comp_col) { // Vypočítávané sloupce
				$m = $this->em->get_column_meta($comp_col);                  // Načtení metadat sloupce
				if (! empty($m)) {                                           // Pokud sloupec v metadatech existuje
					$m['is_computed'] = 1;                                   // Označení jako počítaný (readonly)
				}
			}
		}

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			if ($this->filter_asset_uuid !== '') {                           // Předvyplnění aktiva z kontextového filtru
				$datarow['asset_uuid'] = $this->filter_asset_uuid;           // Nastavení asset_uuid
			}
			$def_st = sqlfirstrow("
				SELECT TOP 1 original
				FROM countermeasure_state
				WHERE object_owner IN ({$org_sql}, 0x00)
				  AND record_type = 'A'
				  AND removed = 0
				  AND inactive = 0
				  AND is_default = 1
				ORDER BY CASE WHEN object_owner = {$org_sql} THEN 0 ELSE 1 END, sort_code
			");                                                              // Dohledání výchozího stavu opatření
			if (! empty($def_st['original'])) {                              // Pokud výchozí stav existuje
				$datarow['state_uuid'] = (string) $def_st['original'];       // Předvyplnění výchozího stavu
			}
		}

		if ($update_guid !== '' AND $update_guid !== 'NEW' AND is_array($datarow)) { // Přehledový proužek vypočtených faktorů
			$eff_red = number_format((float) ($datarow['effective_reduction_factor'] ?? 0), 2, '.', ' '); // Efektivní redukce v %
			$eff_rsk = number_format((float) ($datarow['effective_risk_factor'] ?? 0), 2, '.', ' ');      // Efektivní práh rizika v %
			$lbl_red = htmlspecialchars($this->phrase('lbl_summary_eff_reduction', [], 'Efektivní redukce rizika scénářů:')); // Popisek redukce
			$lbl_rsk = htmlspecialchars($this->phrase('lbl_summary_eff_risk', [], 'Efektivní spodní práh rizika (při neimplementaci):')); // Popisek prahu
			echo <<<HTML
			<div style="margin-bottom: 14px; padding: 8px 12px; background-color: #f0fdf4; border: 1px solid #bbf7d0; border-left: 4px solid #16a34a; border-radius: 4px; font-size: 13px; display: flex; gap: 24px; flex-wrap: wrap;">
				<div><strong>{$lbl_red}</strong> <span style="font-family: monospace; font-weight: bold; color: #15803d;">{$eff_red} %</span></div>
				<div><strong>{$lbl_rsk}</strong> <span style="font-family: monospace; font-weight: bold; color: #b91c1c;">{$eff_rsk} %</span></div>
			</div>
HTML;
		}
	}
}