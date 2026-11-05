<?php
/**
 * =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: page_countermeasure.php
 * Třída: page_countermeasure
 * Účel: Správa hierarchického katalogu protiopatření (tabulka countermeasure)
 *       v modulu CRMM. Obsahuje dva výpočtové faktory typu decimal(9,4):
 *       - reduction_factor: snížení zbytkového rizika scénáře při aplikaci opatření,
 *       - risk_factor: výsledné skóre rizika, pod které nesmí riziko scénáře
 *         klesnout, pokud opatření není implementováno.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_countermeasure`.
 * - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree` (`abstract_page_tree.php`)
 *   a pracuje s logickou třídou `'countermeasure'`.
 * =============================================================================
 */

declare(strict_types=1);

class page_countermeasure extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'countermeasure';                                // Logická třída pro entity_manager
		$this->can_edit_structure = ! $this->is_readonly;                    // Povolení úpravy stromu a D&D v editačním režimu
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových protiopatření
		$this->storage_key_prefix = 'bcm_tree_countermeasure';               // Klíč v sessionStorage pro sbalené větve

		$this->page_title = $this->phrase('page_title', [], 'Katalog protiopatření (CRMM)'); // Lokalizovaný titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Strom katalogu protiopatření'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_cm_caption', [], 'Protiopatření / Skupina'); // Záhlaví stromového sloupce
		$this->new_button_code = 'btn_new_countermeasure';                   // Kód fráze tlačítka pro nové opatření
		$this->new_button_default_caption = '+ Nové protiopatření';          // Výchozí popisek tlačítka

		$this->tree_extra_columns = [                                        // Doplňkové sloupce faktorů ve stromovém přehledu
			'reduction_factor' => [
				'header' => $this->phrase('th_reduction_pct', [], 'Redukce'), // Záhlaví redukčního faktoru
				'width'  => '65px',                                          // Šířka sloupce
				'align'  => 'right'                                          // Zarovnání doprava
			],
			'risk_factor' => [
				'header' => $this->phrase('th_risk_pct', [], 'Min. riz.'),   // Záhlaví prahového rizikového faktoru
				'width'  => '65px',                                          // Šířka sloupce
				'align'  => 'right'                                          // Zarovnání doprava
			]
		];                                                                   // Konec definice doplňkových sloupců

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier = $this->phrase('grp_hierarchy_factors', [], 'Zařazení ve stromu a výpočtové faktory (0 až 100 %)'); // Sekce stromu a faktorů
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy opatření
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'reduction_factor', 'risk_factor', 'external_code'], // Strom a faktory
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Ikona, platnost a ochrana
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybraného protiopatření.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme nové protiopatření
			return htmlspecialchars($this->phrase('header_new_cm', [], 'Nové protiopatření')); // Nadpis pro nový záznam
		}
		$title_val = (string) ($datarow['builtin_code'] ?: $datarow['caption'] ?: ''); // Kód nebo název protiopatření
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_cm', [], 'Protiopatření')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Předvyplní příznak `is_leaf = 1` u nového záznamu (`update_guid === 'NEW'`).
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_leaf'] = '1';                                       // Výchozí stav nového protiopatření = koncový uzel (1)
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka
	}
}