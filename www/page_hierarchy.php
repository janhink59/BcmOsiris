<?php
/**
 * =============================================================================
 * Verze: 2026-10-31 11:00
 * Soubor: page_hierarchy.php
 * Třída: page_hierarchy
 * Účel: Správa registru sekundárních hierarchií a stromů štítků / tagů (tabulka hierarchy).
 *       Samotný registr je stromově uspořádán (složky hierarchií is_leaf = 0 a
 *       koncové definice hierarchií is_leaf = 1). Koncové hierarchie se automaticky
 *       promítají do meta_class (s úložnou tabulkou hierarchy_item) a jejich uzly
 *       se spravují v podřízené stránce page_hierarchy_item.php.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_hierarchy`.
 * - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree` (`abstract_page_tree.php`)
 *   a pracuje s logickou třídou `'hierarchy'`.
 * - V hlavičce detailu (`render_detail_header_buttons`) zobrazuje u uložených
 *   koncových hierarchií (`is_leaf = 1`) tlačítko pro přechod do správy uzlů
 *   dané hierarchie (`page_hierarchy_item.php&hierarchy=<original>`).
 * - Respektuje uzamčení hierarchie (`entity_manager::is_hierarchy_node_locked()`):
 *   jakmile jsou na položkách dané hierarchie v `hierarchy_item` platné vazby
 *   v tabulce `link`, nelze hierarchii přepodřizovat ani smazat.
 *
 * Změny:
 * 2026-10-31 11:00 - Vytvoření první verze stránky pro správu registru hierarchií a tagů.
 * =============================================================================
 */

declare(strict_types=1);

class page_hierarchy extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'hierarchy';                                     // Logická třída pro entity_manager
		$this->can_edit_structure = !$this->is_readonly;                     // Povolení úpravy struktury a D&D v editačním režimu
		$this->allow_insert = !$this->is_readonly;                           // Povolení zakládání nových hierarchií a složek
		$this->storage_key_prefix = 'bcm_tree_hierarchy';                    // Klíč v sessionStorage pro sbalené větve

		$this->page_title = $this->phrase('page_title', [], 'Sekundární hierarchie a štítky (Tagy)'); // Lokalizovaný titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Registr hierarchií a tagů'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_hierarchy_caption', [], 'Hierarchie / Složka'); // Záhlaví stromového sloupce
		$this->new_button_code = 'btn_new_hierarchy';                        // Kód fráze tlačítka pro novou hierarchii
		$this->new_button_default_caption = '+ Nová hierarchie / složka';    // Výchozí popisek tlačítka

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier = $this->phrase('grp_hierarchy_rules', [], 'Zařazení ve stromu a pravidla navazování'); // Sekce stromu a pravidel
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti a ochrany

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'multiple', 'leaf_only', 'external_code'], // Strom a pravidla vazeb
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Platnost a příznaky ochrany
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s kódem vybrané hierarchie.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$code = (string)($datarow['builtin_code'] ?? '');                    // Technický kód hierarchie
		if ($code === '') {                                                  // Pokud zakládáme novou hierarchii
			return htmlspecialchars($this->phrase('header_new_hierarchy', [], 'Nová hierarchie / složka')); // Nadpis pro nový záznam
		}
		$safe_code = htmlspecialchars($code);                                // Ošetřený kód hierarchie
		$lbl = htmlspecialchars($this->phrase('header_edit_hierarchy', [], 'Hierarchie')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_code}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Vloží do hlavičky detailu tlačítko pro přechod do správy uzlů (page_hierarchy_item)
	 * u uložených koncových hierarchií (is_leaf = 1).
	 */
	protected function render_detail_header_buttons(string $update_guid): string { // Tlačítko pro správu položek hierarchie
		if ($update_guid === '' OR $update_guid === 'NEW') {                 // U nového neuloženého záznamu tlačítko nezobrazujeme
			return '';                                                       // Prázdný výstup
		}

		global $datarow, $dbsession;                                         // Aktuální záznam detailu a relace uživatele
		if (empty($datarow['is_leaf'])) {                                    // Vnitřní složka (is_leaf = 0) nemá vlastní položky v hierarchy_item
			return '';                                                       // Tlačítko zobrazujeme pouze u koncových hierarchií (is_leaf = 1)
		}

		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace
		$hier_sql = guidliteral($update_guid);                               // SQL literál originálu vybrané hierarchie

		$r_cnt = sqlfirstrow("
			SELECT COUNT(DISTINCT original) AS cnt
			FROM hierarchy_item
			WHERE hierarchy = {$hier_sql}
			  AND object_owner IN (0x00, {$org_sql})
			  AND record_type = 'A'
			  AND removed = 0
		");                                                                  // Dotaz na počet aktivních uzlů této hierarchie
		$item_count = (int)($r_cnt['cnt'] ?? 0);                             // Počet položek hierarchie

		$items_url = "index.php?page=page_hierarchy_item&hierarchy=" . urlencode($update_guid); // Cílová URL pro správu položek
		$btn_items = new abstract_button(                                    // Tlačítko přechodu na položky hierarchie
			'btn_manage_hierarchy_items',                                    // Kód fráze v meta_phrase
			'Spravovat položky ({' . chr(36) . 'count}) →',                  // Výchozí český popisek s počtem
			'page_hierarchy',                                                // Zdrojová třída fráze
			'',                                                              // Bez ikony
			'btn-secondary'                                                  // Sekundární šedý styl tlačítka
		);
		$btn_items->set_href($items_url)->set_vars(['count' => $item_count]); // Nastavení URL a proměnné {$count}

		return $btn_items->render();                                         // Vrácení HTML kódu tlačítka
	}

	/**
	 * Vykreslí v horní části detailu banner Drag & Dropu a metodickou nápovědu.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($datarow['is_leaf'] ?? '') === '') { // Výchozí hodnoty pro novou hierarchii
			$datarow['is_leaf'] = '1';                                       // Výchozí stav = koncová hierarchie (1)
			$datarow['multiple'] = '1';                                      // Výchozí povolení vícenásobného přiřazení (1)
			$datarow['leaf_only'] = '1';                                     // Výchozí povolení vazeb pouze na koncové listy (1)
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka

		$note = htmlspecialchars($this->phrase('msg_hierarchy_type_hint', [], 'Tip: Záznamy s příznakem „Koncový uzel (is_leaf = 1)“ představují samostatné hierarchie nebo sady štítků (tagů), které se automaticky registrují do logických tříd (meta_class) a v nichž lze spravovat jednotlivé položky. Záznamy s is_leaf = 0 slouží jako organizační složky tohoto registru.')); // Metodická nápověda
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy
	}
}