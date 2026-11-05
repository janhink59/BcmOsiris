<?php
/**
 * =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: page_countermeasure_state.php
 * Třída: page_countermeasure_state
 * Účel: Správa plochého (nehierarchického) číselníku stavů implementace
 *       protiopatření CRMM (tabulka countermeasure_state) se sloupci
 *       reduction_factor (váha redukčního faktoru opatření v %) a
 *       risk_factor (váha prahového rizikového faktoru neimplementovaného opatření v %).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_countermeasure_state`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'countermeasure_state'`.
 * =============================================================================
 */

declare(strict_types=1);

class page_countermeasure_state extends abstract_page_master_detail {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'countermeasure_state';                          // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových stavů opatření
		$this->page_title = $this->phrase('page_title', [], 'Stavy protiopatření (CRMM)'); // Lokalizovaný titulek stránky

		if (! $this->access_denied AND $this->em === null) {                 // Inicializace entity_manageru pro nastavení sloupců seznamu
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance správce entit
			$this->em->set_list_columns([                                    // Sloupce v levém Master panelu
				'sort_code'        => $this->phrase('th_sort_code', [], 'Pořadí'),
				'caption'          => $this->phrase('th_state_caption', [], 'Stav opatření'),
				'reduction_factor' => $this->phrase('th_reduction_pct', [], 'Redukce (%)'),
				'risk_factor'      => $this->phrase('th_risk_pct', [], 'Riziko (%)'),
				'is_default'       => $this->phrase('th_is_default', [], 'Výchozí')
			]);                                                              // Konec nastavení sloupců Master panelu
		}

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_calc = $this->phrase('grp_factors_ordering', [], 'Výpočtové faktory stavu (0 až 100 %) a řazení'); // Sekce faktorů
		$grp_vis  = $this->phrase('grp_visual_validity', [], 'Vizuální atributy, platnost a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy stavu
			$grp_calc => ['builtin_code', 'sort_code', 'is_default', 'reduction_factor', 'risk_factor', 'external_code'], // Faktory a řazení
			$grp_vis  => ['color_code', 'svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Barva, ikona a platnost
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Vykreslí tlačítko "+ Nový stav opatření" nad vyhledávacím polem v levém panelu.
	 */
	protected function render_master_top(): void {
		if (! $this->allow_insert) {                                         // Pokud zakládání nových záznamů není povoleno
			return;                                                          // Tlačítko nevykreslujeme
		}

		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL s kontextem
		$new_url = "index.php?page=page_countermeasure_state{$url_suffix}&update_guid=NEW"; // Cílová adresa pro nový stav
		$btn_new = new abstract_button('btn_new_cm_state', '+ Nový stav opatření', 'page_countermeasure_state'); // Tlačítko
		$btn_new->set_href($new_url)                                         // Nastavení cílové URL
			->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
			->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Roztažení na šířku levého panelu

		echo $btn_new->render();                                             // Vykreslení tlačítka
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybraného stavu opatření.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme nový stav opatření
			return htmlspecialchars($this->phrase('header_new_cm_state', [], 'Nový stav protiopatření')); // Nadpis pro nový záznam
		}
		$title_val = (string) ($datarow['caption'] ?: $datarow['builtin_code'] ?: ''); // Název nebo kód stavu
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_cm_state', [], 'Stav protiopatření')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}
}