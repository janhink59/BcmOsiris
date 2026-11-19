<?php
/**
 * =============================================================================
 * Verze: 2026-11-19 15:40
 * Soubor: page_asset_class.php
 * Třída: page_asset_class
 *
 * 1. Role souboru v celém systému:
 *    Správa hierarchického katalogu tříd aktiv (tabulka asset_class) v CRMM.
 *    Umožňuje organizovat třídy aktiv do stromu (vnitřní složky is_leaf = 0
 *    a koncové třídy aktiv is_leaf = 1) a řídit povolení souběžného přiřazení
 *    sourozeneckých tříd jednomu aktivu pomocí příznaku multi_class.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Instancována dynamicky z routeru index.php při ?page=page_asset_class.
 *    - Dědí ze znovupoužitelné stromové šablony abstract_page_tree (abstract_page_tree.php)
 *      a pracuje s logickou třídou 'asset_class' (table_asset_class.sql).
 *    - Fráze a položka menu jsou registrovány v page_asset_class#phrase.sql.
 *    - Respektuje uzamčení hierarchie (entity_manager::is_hierarchy_node_locked()).
 *
 * 3. Očekávaná kontextová data:
 *    - Využívá kontext přihlášeného uživatele v globálním poli $dbsession
 *      (v databázi v tabulce dbsession pro aktuální @@SPID) a stav sbalených
 *      větví v sessionStorage pod klíčem bcm_tree_asset_class.
 *
 * Změny:
 * 2026-11-19 15:40 - Doplněn sloupec multi_class do editačního formuláře i do
 *                    přehledových sloupců levého stromu ($this->tree_extra_columns).
 * 2026-11-04 10:30 - Odstraněn umělý chráněný kořen 'ROOT' ($protected_root_codes).
 * =============================================================================
 */

declare(strict_types=1);

class page_asset_class extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'asset_class';                                   // Logická třída pro entity_manager
		$this->can_edit_structure = !$this->is_readonly;                    // Povolení úpravy stromu a D&D v editačním režimu
		$this->allow_insert = !$this->is_readonly;                          // Povolení zakládání nových tříd aktiv
		$this->storage_key_prefix = 'bcm_tree_asset_class';                  // Klíč v sessionStorage pro sbalené větve

		$this->page_title =$this->phrase('page_title', [], 'Třídy aktiv (Katalog CRMM)'); // Lokalizovaný titulek stránky
		$this->tree_heading =$this->phrase('master_heading', [], 'Strom tříd aktiv'); // Nadpis levého panelu
		$this->tree_caption_header =$this->phrase('th_asset_class_caption', [], 'Třída aktiv / Složka'); // Záhlaví stromového sloupce
		$this->new_button_code = 'btn_new_asset_class';                      // Kód fráze tlačítka pro novou třídu aktiv
		$this->new_button_default_caption = '+ Nová třída aktiv';            // Výchozí popisek tlačítka

		$this->tree_extra_columns = [                                        // Doplňkový sloupec příznaku multi_class ve stromu
			'multi_class' => [
				'header' => $this->phrase('th_multi_class', [], 'Více tříd'), // Záhlaví sloupce multi_class
				'width'  => '60px',                                          // Šířka sloupce
				'align'  => 'center'                                         // Zarovnání na střed
			]
		];                                                                   // Konec definice doplňkových sloupců

		$grp_pres =$this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier =$this->phrase('grp_hierarchy_placement', [], 'Zařazení ve stromu a identifikace'); // Sekce stromu
		$grp_perm =$this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'multi_class', 'external_code', 'instance_class_name'], // Strom, souběh tříd a identifikace
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Platnost a příznaky ochrany
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem třídy aktiv.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme novou třídu aktiv
			return htmlspecialchars($this->phrase('header_new_asset_class', [], 'Nová třída aktiv')); // Nadpis pro nový záznam
		}
		$title_val = (string)($datarow['builtin_code'] ?:$datarow['caption'] ?: ''); // Kód nebo název třídy aktiv
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_asset_class', [], 'Třída aktiv')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Předvyplní příznak koncového uzlu `is_leaf = 1` u nového záznamu a vypíše metodickou nápovědu.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_leaf'] = '1';                                       // Výchozí stav nové třídy aktiv = koncový uzel (1)
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka

		$note = htmlspecialchars($this->phrase('msg_asset_class_leaf_hint', [], 'Tip: Konkrétní aktiva lze zařazovat pouze do koncových tříd aktiv (is_leaf = 1). Vnitřní uzly (is_leaf = 0) slouží jako nadřazené složky, na které však lze vázat společné hrozby a scénáře děděné do podřízených tříd.')); // Nápověda
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy
	}
}