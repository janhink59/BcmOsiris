<?php
/**
 * =============================================================================
 * Verze: 2026-11-27 15:40
 * Soubor: page_impact_type.php
 * Třída: page_impact_type
 *
 * 1. Role souboru v celém systému:
 *    Správa hierarchického katalogu druhů dopadů / následků (tabulka impact_type)
 *    v modulu CRMM (prozrazení důvěrnosti, chyby integrity, časové intervaly
 *    nedostupnosti, ztráta dat / fyzické zničení a integrita komunikace).
 *    Tvoří řádky matice hodnocení dopadů (BIA / kritičnosti).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Instancována dynamicky z routeru `index.php` při `?page=page_impact_type`.
 *    - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree`
 *      (`abstract_page_tree.php`) a pracuje s logickou třídou `'impact_type'`
 *      (`table_impact_type.sql`).
 *    - Lokalizační fráze a položka menu jsou registrovány v
 *      `page_impact_type#phrase.sql`; výchozí katalog plní `fillup_impact_type*.sql`.
 *
 * 3. Očekávaná kontextová data:
 *    - Využívá kontext přihlášeného uživatele v globálním poli `$dbsession`
 *      (v databázi `dbsession` pro aktuální `@@SPID`) a stav sbalených větví
 *      stromu v klientském `sessionStorage` pod klíčem `bcm_tree_impact_type`.
 *
 * Změny:
 * 2026-11-27 15:40 - Oprava sloučeného řádku skupiny $grp_perm v $this->form_groups
 *                    (sekce Platnost, vzhled a ochrana byla v komentáři) a doplnění
 *                    chybějících mezer před znakem $ dle Anti-LaTeX pravidla.
 * =============================================================================
 */

declare(strict_types=1);

class page_impact_type extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'impact_type';                                   // Logická třída pro entity_manager
		$this->can_edit_structure = ! $this->is_readonly;                    // Povolení úpravy stromu a D&D v editačním režimu
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových druhů dopadů
		$this->storage_key_prefix = 'bcm_tree_impact_type';                  // Klíč v sessionStorage pro sbalené větve

		$this->page_title = $this->phrase('page_title', [], 'Druhy dopadů (Katalog CRMM)'); // Lokalizovaný titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Strom druhů dopadů (následků)'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_impact_type_caption', [], 'Druh dopadu / Kategorie'); // Záhlaví stromového sloupce
		$this->new_button_code = 'btn_new_impact_type';                      // Kód fráze tlačítka pro nový druh dopadu
		$this->new_button_default_caption = '+ Nový druh dopadu';            // Výchozí popisek tlačítka

		$this->tree_extra_columns = [                                        // Doplňkové sloupce kategorie CIA a délky výpadku ve stromu
			'cia_category' => [
				'header' => $this->phrase('th_cia_category', [], 'CIA'),     // Záhlaví sloupce kategorie CIA
				'width'  => '95px',                                          // Šířka sloupce
				'align'  => 'center'                                         // Zarovnání na střed
			],
			'duration_minutes' => [
				'header' => $this->phrase('th_duration_minutes', [], 'Min.'), // Záhlaví sloupce délky výpadku v minutách
				'width'  => '60px',                                          // Šířka sloupce
				'align'  => 'right'                                          // Zarovnání doprava
			]
		];                                                                   // Konec definice doplňkových sloupců

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier = $this->phrase('grp_hierarchy_classification', [], 'Zařazení ve stromu, kategorie CIA a délka výpadku'); // Sekce klasifikace
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'cia_category', 'duration_minutes', 'external_code'], // Strom a CIA
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Platnost a ochrana
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybraného druhu dopadu.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme nový druh dopadu
			return htmlspecialchars($this->phrase('header_new_impact_type', [], 'Nový druh dopadu (následek)')); // Nadpis pro nový záznam
		}
		$title_val = (string) ($datarow['builtin_code'] ?: $datarow['caption'] ?: ''); // Kód nebo název druhu dopadu
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_impact_type', [], 'Druh dopadu')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Předvyplní příznak `is_leaf = 1` u nového záznamu.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_leaf'] = '1';                                       // Výchozí stav nového druhu dopadu = koncový uzel (1)
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka
	}
}