<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 18:00
 * Soubor: page_scenario.php
 * Třída: page_scenario
 * Účel: Správa hierarchického katalogu rizikových scénářů / událostí (tabulka scenario)
 *       v modulu CRMM. Umožňuje definovat vazbu na hrozbu (threat_uuid), cílovou
 *       třídu aktiv (asset_class_uuid) a minimální mez reziduálního rizika
 *       (residual_risk_min_score).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_scenario`.
 * - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree` (`abstract_page_tree.php`)
 *   a pracuje s logickou třídou `'scenario'`.
 * =============================================================================
 */

declare(strict_types=1);

class page_scenario extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'scenario';                                      // Logická třída pro entity_manager
		$this->can_edit_structure = ! $this->is_readonly;                    // Povolení úpravy stromu a D&D v editačním režimu
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových scénářů
		$this->storage_key_prefix = 'bcm_tree_scenario';                     // Klíč v sessionStorage pro sbalené větve

		$this->page_title = $this->phrase('page_title', [], 'Rizikové scénáře (Katalog CRMM)'); // Lokalizovaný titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Strom rizikových scénářů'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_scenario_caption', [], 'Scénář / Skupina'); // Záhlaví stromového sloupce
		$this->new_button_code = 'btn_new_scenario';                         // Kód fráze tlačítka pro nový scénář
		$this->new_button_default_caption = '+ Nový scénář';                 // Výchozí popisek tlačítka

		$this->tree_extra_columns = [                                        // Doplňkový sloupec meze reziduálního rizika ve stromu
			'residual_risk_min_score' => [
				'header' => $this->phrase('th_min_res_risk', [], 'Min. rez.'), // Záhlaví sloupce
				'width'  => '70px',                                          // Šířka sloupce
				'align'  => 'right'                                          // Zarovnání doprava
			]
		];                                                                   // Konec definice doplňkových sloupců

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier = $this->phrase('grp_hierarchy_relations', [], 'Zařazení ve stromu, vazby a reziduální riziko'); // Sekce stromu a vazeb
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'threat_uuid', 'asset_class_uuid', 'residual_risk_min_score', 'external_code'], // Strom a CRMM vazby
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Platnost a ochrana
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybraného scénáře.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme nový scénář
			return htmlspecialchars($this->phrase('header_new_scenario', [], 'Nový rizikový scénář')); // Nadpis pro nový záznam
		}
		$title_val = (string)($datarow['builtin_code'] ?: $datarow['caption'] ?: ''); // Kód nebo název scénáře
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_scenario', [], 'Scénář')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Předvyplní příznak `is_leaf = 1` u nového záznamu.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_leaf'] = '1';                                       // Výchozí stav nového scénáře = koncový uzel (1)
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka
	}
}