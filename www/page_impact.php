<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 18:00
 * Soubor: page_impact.php
 * Třída: page_impact
 * Účel: Správa hierarchického katalogu dopadů (tabulka impact) v modulu CRMM.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_impact`.
 * - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree` (`abstract_page_tree.php`)
 *   a pracuje s logickou třídou `'impact'`.
 * =============================================================================
 */

declare(strict_types=1);

class page_impact extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'impact';                                        // Logická třída pro entity_manager
		$this->can_edit_structure = ! $this->is_readonly;                    // Povolení úpravy stromu a D&D v editačním režimu
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových dopadů
		$this->storage_key_prefix = 'bcm_tree_impact';                       // Klíč v sessionStorage pro sbalené větve

		$this->page_title = $this->phrase('page_title', [], 'Katalog dopadů (CRMM)'); // Lokalizovaný titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Strom katalogu dopadů'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_impact_caption', [], 'Dopad / Oblast dopadu'); // Záhlaví stromového sloupce
		$this->new_button_code = 'btn_new_impact';                           // Kód fráze tlačítka pro nový dopad
		$this->new_button_default_caption = '+ Nový dopad';                  // Výchozí popisek tlačítka

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier = $this->phrase('grp_hierarchy_placement', [], 'Zařazení ve stromu a identifikace'); // Sekce stromu
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'external_code'], // Strom a identifikace
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Platnost a ochrana
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybraného dopadu.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme nový dopad
			return htmlspecialchars($this->phrase('header_new_impact', [], 'Nový dopad')); // Nadpis pro nový záznam
		}
		$title_val = (string)($datarow['builtin_code'] ?: $datarow['caption'] ?: ''); // Kód nebo název dopadu
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_impact', [], 'Dopad')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Předvyplní příznak `is_leaf = 1` u nového záznamu.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_leaf'] = '1';                                       // Výchozí stav nového dopadu = koncový uzel (1)
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka
	}
}