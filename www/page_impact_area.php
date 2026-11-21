<?php
/**
 * =============================================================================
 * Verze: 2026-11-21 11:20
 * Soubor: page_impact_area.php
 * Třída: page_impact_area
 *
 * 1. Role souboru v celém systému:
 *    Správa hierarchického katalogu měřitelných oblastí dopadů (tabulka
 *    impact_area) rozčleněného podle perspektiv (organizace, stát, subjekt
 *    údajů / obyvatelstvo) s volitelným přiřazením individuální hodnotící
 *    škály vodítek (scale_uuid). Tvoří sloupce matice hodnocení dopadů (BIA).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Instancována dynamicky z routeru `index.php` při `?page=page_impact_area`.
 *    - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree`
 *      (`abstract_page_tree.php`) a pracuje s logickou třídou `'impact_area'`
 *      (`table_impact_area.sql`).
 *    - Sloupec `scale_uuid` využívá filtrovaný výběr z `scale` (`scale_type = 'IMPACT'`)
 *      v `dbo.p_em_get_select_options` (`p_em_metadata.sql`).
 *    - Lokalizační fráze a položka menu jsou registrovány v
 *      `page_impact_area#phrase.sql`; výchozí katalog plní `fillup_impact_area*.sql`.
 *
 * 3. Očekávaná kontextová data:
 *    - Využívá kontext přihlášeného uživatele v globálním poli `$dbsession`
 *      (v databázi `dbsession` pro aktuální `@@SPID`) a stav sbalených větví
 *      stromu v klientském `sessionStorage` pod klíčem `bcm_tree_impact_area`.
 * =============================================================================
 */

declare(strict_types=1);

class page_impact_area extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'impact_area';                                   // Logická třída pro entity_manager
		$this->can_edit_structure = ! $this->is_readonly;                    // Povolení úpravy stromu a D&D v editačním režimu
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových oblastí dopadů
		$this->storage_key_prefix = 'bcm_tree_impact_area';                  // Klíč v sessionStorage pro sbalené větve

		$this->page_title = $this->phrase('page_title', [], 'Oblasti dopadů (Katalog CRMM)'); // Lokalizovaný titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Strom oblastí dopadů'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_impact_area_caption', [], 'Oblast dopadu / Perspektiva'); // Záhlaví stromového sloupce
		$this->new_button_code = 'btn_new_impact_area';                      // Kód fráze tlačítka pro novou oblast dopadu
		$this->new_button_default_caption = '+ Nová oblast dopadu';          // Výchozí popisek tlačítka

		$this->tree_extra_columns = [                                        // Doplňkový sloupec zkratky pro záhlaví matice BIA
			'shortname' => [
				'header' => $this->phrase('th_shortname', [], 'Zkratka'),    // Záhlaví sloupce zkratky
				'width'  => '110px',                                         // Šířka sloupce
				'align'  => 'left'                                           // Zarovnání doleva
			]
		];                                                                   // Konec definice doplňkových sloupců

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier = $this->phrase('grp_hierarchy_scale', [], 'Zařazení ve stromu a škála vodítek'); // Sekce stromu a škály
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'scale_uuid', 'external_code'], // Strom a volitelná škála
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Platnost a ochrana
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybrané oblasti dopadu.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme novou oblast dopadu
			return htmlspecialchars($this->phrase('header_new_impact_area', [], 'Nová oblast dopadu')); // Nadpis pro nový záznam
		}
		$title_val = (string) ($datarow['builtin_code'] ?: $datarow['caption'] ?: ''); // Kód nebo název oblasti dopadu
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_impact_area', [], 'Oblast dopadu')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Předvyplní příznak `is_leaf = 1` u nového záznamu a zobrazí metodickou nápovědu ke škále vodítek.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_leaf'] = '1';                                       // Výchozí stav nové oblasti dopadu = koncový uzel (1)
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka

		$note = htmlspecialchars($this->phrase('msg_impact_area_scale_hint', [], 'Tip: Pokud ponecháte pole „Individuální škála vodítek (scale_uuid)“ prázdné, použije se výchozí škála dopadů organizace (organization.default_impact_scale_uuid). Oblasti nebo celé perspektivy, které vaše organizace nevyhodnocuje, lze skrýt zaškrtnutím příznaku Neaktivní (inactive).')); // Metodická nápověda
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy
	}
}