<?php
/**
 * =============================================================================
 * Verze: 2026-10-31 11:00
 * Soubor: page_meta_menu.php
 * Třída: page_meta_menu
 * Účel: Správa struktury uživatelského menu (meta_menu) – úprava nadřízenosti
 *       položek (parent_uuid), pořadí (sort_code), cílových stránek (target_object)
 *       a jazykových mutací (caption, description, helptext).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_meta_menu`.
 * - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree` (`abstract_page_tree.php`)
 *   a pracuje s logickou třídou `'meta_menu'`.
 * - Využívá `entity_manager`, který u metadatových tabulek umožňuje editaci
 *   funkčně významných atributů (`parent_uuid`, `sort_code`, `target_object`, `system_role`)
 *   výhradně vývojářům (`active_role = 'D'`), zatímco překladové sloupce (`caption`,
 *   `description`, `helptext`) může lokalizovat každý oprávněný uživatel.
 * - Veškeré vykreslování stromu, rozbalování/sbalování větví (Collapse/Expand v sessionStorage)
 *   i Drag & Drop (Varianta 1: předvyplnění parent_uuid a sort_code do detailu)
 *   zajišťuje předek `abstract_page_tree`.
 *
 * Změny:
 * 2026-10-31 11:00 - Refaktoring třídy na potomka znovupoužitelné šablony
 *                    `abstract_page_tree` (odstranění duplicitního kódu stromu a D&D).
 * 2026-10-27 19:40 - Napojení řádků stromu a Drag & Dropu na asynchronní loadDetailPanel().
 * 2026-10-24 20:35 - Doplněno klientské rozbalování/sbalování větví a Drag & Drop.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_menu extends abstract_page_tree {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází, kontroly přístupu a D&D v předkovi

		global $dbsession;                                                   // Globální kontext relace uživatele
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role přihlášeného uživatele

		$this->class_name = 'meta_menu';                                     // Logická třída pro entity_manager
		$this->can_edit_structure = ($active_role === 'D' AND !$this->is_readonly); // Strukturu metadat mění pouze Developer
		$this->allow_insert = $this->can_edit_structure;                     // Zakládání nových položek menu pouze pro roli Developer
		$this->protected_root_codes = ['home'];                              // Kořenovou položku Domů nelze přetahovat myší
		$this->storage_key_prefix = 'bcm_meta_menu_collapsed';               // Klíč v sessionStorage pro sbalené větve menu

		$this->page_title = $this->phrase('page_title', [], 'Správa položek menu (Navigace)'); // Lokalizovaný titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Strom položek menu'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_menu_caption', [], 'Položka menu (Strom)'); // Záhlaví sloupce stromu
		$this->new_button_code = 'btn_new_menu_item';                        // Kód fráze tlačítka nové položky
		$this->new_button_default_caption = '+ Nová položka menu';           // Výchozí popisek tlačítka nové položky

		$this->tree_extra_columns = [                                        // Doplňkový sloupec systémové role v tabulce stromu
			'system_role' => [
				'header' => $this->phrase('th_system_role', [], 'Role'),     // Záhlaví sloupce role
				'width'  => '45px',                                          // Šířka sloupce
				'align'  => 'center',                                        // Zarovnání na střed
				'bold'   => true                                             // Tučné písmo kódu role
			]
		];                                                                   // Konec definice doplňkových sloupců

		if (!$this->can_edit_structure) {                                    // Pokud uživatel není Developer, vypneme případný D&D náhled
			$this->has_dnd_preview = false;                                  // Zákaz D&D náhledu mimo roli D
		}

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překladů
		$grp_hier = $this->phrase('grp_hierarchy_target', [], 'Zařazení ve stromu a cíl navigace'); // Sekce hierarchie a cíle
		$grp_perm = $this->phrase('grp_access_visual', [], 'Oprávnění, vzhled a ochrana položky'); // Sekce oprávnění a vzhledu

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'description', 'helptext', 'editor_note'], // Překládané popisky a kontext pro AI
			$grp_hier => ['builtin_code', 'parent_uuid', 'sort_code', 'target_object', 'url_parameters', 'target_url', 'target_window'], // Strom a cíl
			$grp_perm => ['system_role', 'permanent', 'svg_icon', 'css_class', 'is_final', 'is_protected', 'inactive'] // Role a vzhled
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Určí, zda položka menu funguje jako složka (může přijímat podpoložky při Drag & Dropu).
	 * Tabulka meta_menu nemá fyzický sloupec is_leaf – složkou je uzel s potomky nebo bez cílové stránky/URL.
	 */
	protected function is_node_folder(array $row, bool $has_children): bool { // Detekce složky v navigaci menu
		$b_code = (string)($row['builtin_code'] ?? '');                      // Technický kód položky menu
		return ($has_children OR $b_code === 'home' OR (empty($row['target_object']) AND trim((string)($row['target_url'] ?? '')) === '')); // Složka menu
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s kódem vybrané položky menu.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek položky menu
		$code = (string)($datarow['builtin_code'] ?? '');                    // Technický identifikátor položky menu
		if ($code === '') {                                                  // Pokud zakládáme novou položku menu
			return htmlspecialchars($this->phrase('header_new_menu_item', [], 'Nová položka menu')); // Nadpis pro nový záznam
		}
		$safe_code = htmlspecialchars($code);                                // Ošetřený kód položky menu
		$lbl = htmlspecialchars($this->phrase('header_edit_menu_item', [], 'Položka menu')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_code}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Vykreslí informační pruh Drag & Dropu z předka a nápovědu k chování složek v menu.
	 */
	protected function render_detail_top(): void {
		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení zeleného banneru z předka

		$note = htmlspecialchars($this->phrase('msg_menu_hierarchy_hint', [], 'Tip: Položky, které mají podřízené uzly, fungují v navigaci automaticky jako složky (rozcestníky). Cílová stránka (target_object) se uplatní u koncových položek.')); // Text nápovědy
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy
	}
}