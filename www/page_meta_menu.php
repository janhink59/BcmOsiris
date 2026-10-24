<?php
/**
 * =============================================================================
 * Verze: 2026-10-24 20:35
 * Soubor: page_meta_menu.php
 * Třída: page_meta_menu
 * Účel: Správa struktury uživatelského menu (meta_menu) – úprava nadřízenosti
 *       položek (parent_uuid), pořadí (sort_code), cílových stránek (target_object)
 *       a jazykových mutací (caption, description, helptext).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_meta_menu`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'meta_menu'`.
 * - Využívá `entity_manager`, který u metadatových tabulek umožňuje editaci
 *   funkčně významných atributů (`parent_uuid`, `sort_code`, `target_object`, `system_role`)
 *   výhradně vývojářům (`active_role = 'D'`), zatímco překladové sloupce (`caption`,
 *   `description`, `helptext`) může lokalizovat každý oprávněný uživatel.
 * - Levý panel (`render_master()`) podporuje:
 *   1. Klientské rozbalování a sbalování větví stromu (Collapse / Expand) čistě v JS
 *      s uchováním stavu v `sessionStorage` bez zápisu do databáze.
 *   2. Přesouvání položek metodou Drag & Drop (Varianta 1): přetažení položky v levém
 *      panelu vypočítá nový `parent_uuid` a lexikografický `sort_code` a předvyplní
 *      tyto dvě položky do detailního formuláře vpravo (se zapnutím `isFormDirty = true`)
 *      bez přímého zápisu do databáze.
 *
 * Změny:
 * 2026-10-24 20:35 - Doplněno klientské rozbalování/sbalování větví (Collapse/Expand) v JS.
 *                  - Doplněna podpora Drag & Drop (Varianta 1 – úprava polí `parent_uuid`
 *                    a `sort_code` v detailním formuláři bez okamžitého zápisu do DB).
 * 2026-10-24 11:55 - První verze stránky pro správu stromu menu.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_menu extends abstract_page_master_detail {

	private bool $can_edit_structure = false;                                // Zda má uživatel právo měnit hierarchii a pořadí ('D')
	private bool $has_dnd_preview = false;                                   // Zda byl detail otevřen přetažením (Drag & Drop)
	private string $dnd_parent = '';                                         // Předvyplněný parent_uuid z Drag & Dropu
	private string $dnd_sort = '';                                           // Předvyplněný sort_code z Drag & Dropu

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		global $dbsession;                                                   // Globální kontext relace uživatele
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role přihlášeného uživatele

		$this->can_edit_structure = ($active_role === 'D' AND !$this->is_readonly); // Strukturu metadat mění pouze Developer
		$this->class_name = 'meta_menu';                                     // Logická třída pro entity_manager
		$this->allow_insert = $this->can_edit_structure;                     // Zakládání nových položek menu pouze pro roli Developer
		$this->page_title = $this->phrase('page_title', [], 'Správa položek menu (Navigace)'); // Lokalizovaný titulek stránky

		if ($this->can_edit_structure AND isset($_GET['dnd_sort'])) {        // Detekce parametrů z Drag & Drop přetažení neaktivního řádku
			$this->has_dnd_preview = true;                                   // Zapnutí režimu neuloženého náhledu po přetažení
			$this->dnd_parent = trim((string)getinput('dnd_parent'));        // Nový nadřízený uzel z Drag & Dropu
			$this->dnd_sort = trim((string)getinput('dnd_sort'));            // Nový řadicí kód z Drag & Dropu
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
	 * Vykreslí nadpisovou poznámku v detailu a případně aplikuje neuložené hodnoty
	 * z Drag & Drop přetažení do globálního pole $datarow před vykreslením inputů.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený datový řádek detailu

		if ($this->has_dnd_preview AND is_array($datarow)) {                 // Pokud byl záznam otevřen přetažením myší v levém panelu
			$datarow['parent_uuid'] = $this->dnd_parent;                     // Přepsání parent_uuid v detailu (bez zápisu do DB)
			$datarow['sort_code'] = $this->dnd_sort;                         // Přepsání sort_code v detailu (bez zápisu do DB)
		}

		$msg_dnd = htmlspecialchars($this->phrase('msg_dnd_unsaved_notice', [], 'Nadřízená položka (parent_uuid) a pořadí (sort_code) byly upraveny přetažením. Zkontrolujte údaje a potvrďte je tlačítkem Uložit změny (příp. Uložit koncept / Předat ke schválení).')); // Text výzvy po přetažení
		$disp_dnd = $this->has_dnd_preview ? 'block' : 'none';               // Viditelnost výzvy při přetažení
		echo "<div id=\"menu-dnd-banner\" class=\"msg-info\" style=\"display: {$disp_dnd}; margin-bottom: 12px; background-color: #f0fdf4; border-left-color: #16a34a; color: #166534;\">{$msg_dnd}</div>\n"; // Informační pruh Drag & Dropu

		$note = htmlspecialchars($this->phrase('msg_menu_hierarchy_hint', [], 'Tip: Položky, které mají podřízené uzly, fungují v navigaci automaticky jako složky (rozcestníky). Cílová stránka (target_object) se uplatní u koncových položek.')); // Text nápovědy
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy

		if ($this->has_dnd_preview) {                                        // Při otevření z Drag & Dropu označíme formulář jako neuložený
			echo <<<HTML
			<script>
				document.addEventListener("DOMContentLoaded", function() {
					isFormDirty = true;
					const pSel = document.querySelector('.md-detail form [name="parent_uuid"]');
					const sInp = document.querySelector('.md-detail form [name="sort_code"]');
					[pSel, sInp].forEach(function(el) {
						if (el) {
							el.style.backgroundColor = '#dcfce7';
							el.style.borderColor = '#16a34a';
						}
					});
				});
			</script>
HTML;
		}
	}

	/**
	 * Vykreslí tlačítko pro založení nové položky menu v horní části levého panelu (pouze pro roli Developer).
	 */
	protected function render_master_top(): void {
		if (!$this->allow_insert) {                                          // Kontrola oprávnění k vkládání
			return;                                                          // Pro nižší role tlačítko nevykreslujeme
		}

		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL pro zachování kontextu
		$new_url = "index.php?page=page_meta_menu{$url_suffix}&update_guid=NEW"; // Cílová adresa pro novou položku
		$btn_new = new abstract_button('btn_new_menu_item', '+ Nová položka menu', 'page_meta_menu'); // Tlačítko nové položky
		$btn_new->set_href($new_url)->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Styl tlačítka
		echo $btn_new->render();                                             // Vykreslení tlačítka nad seznamem
	}

	/**
	 * Pomocná rekurzivní metoda pro seřazení položek menu do stromové posloupnosti.
	 *
	 * @param string                             $parent_key   UUID rodiče ('' pro kořeny)
	 * @param int                                $level        Úroveň zanoření (0, 1, 2...)
	 * @param array<string, array<int, array>>   $children_map Mapa potomků podle parent_uuid
	 * @param array<int, array<string, mixed>>   $flat_out     Výstupní seřazené pole se sloupcem _tree_level
	 * @param array<string, bool>                $visited      Ochrana proti zacyklení
	 */
	private function append_tree_children(string $parent_key, int $level, array &$children_map, array &$flat_out, array &$visited): void { // Rekurzivní průchod stromem
		if (!isset($children_map[$parent_key])) {                            // Pokud uzel nemá žádné potomky
			return;                                                          // Ukončení větve
		}

		// Seřazení sourozenců v dané větvi podle sort_code a builtin_code
		usort($children_map[$parent_key], function(array $a, array $b): int { // Řazení sourozenců ve větvi
			$cmp = strcmp((string)($a['sort_code'] ?? ''), (string)($b['sort_code'] ?? '')); // Lexikografické porovnání sort_code
			if ($cmp !== 0) {                                                // Pokud se sort_code liší
				return $cmp;                                                 // Vrácení výsledku porovnání sort_code
			}
			return strcasecmp((string)($a['builtin_code'] ?? ''), (string)($b['builtin_code'] ?? '')); // Sekundární řazení dle kódu
		});

		foreach ($children_map[$parent_key] as $row) {                       // Průchod potomky daného rodiče
			$orig = strtolower((string)$row['original']);                    // Normalizované UUID položky
			if (isset($visited[$orig])) {                                    // Ochrana proti případnému cyklu v datech
				continue;                                                    // Přeskočení již navštíveného uzlu
			}
			$visited[$orig] = true;                                          // Označení uzlu jako navštíveného
			$row['_tree_level'] = $level;                                    // Uložení vypočtené úrovně zanoření
			$flat_out[] = $row;                                              // Přidání uzlu do výstupního seznamu
			$this->append_tree_children($orig, $level + 1, $children_map, $flat_out, $visited); // Rekurzivní přidání podřízených položek
		}
	}

	/**
	 * Vykreslí levý panel (Master) se stromově odsazenou hierarchií položek menu,
	 * ovládáním pro sbalení/rozbalení větví (Collapse/Expand) a podporou Drag & Drop.
	 */
	protected function render_master(): void {
		if ($this->em === null) {                                            // Kontrola inicializace správce entit
			return;                                                          // Ukončení při chybějícím správci
		}

		$update_guid = (string)getinput('update_guid');                      // Aktuálně vybraná položka v detailu
		$show_removed = ((string)getinput('show_removed') === '1');          // Příznak zobrazení zrušených položek

		$rows = $this->em->fetch_rows($this->master_where, 'sort_code ASC, builtin_code ASC', false, $show_removed); // Načtení položek s překlady

		// Pokud přišel neuložený náhled z Drag & Dropu, promítneme jej i do paměťového stromu vlevo
		if ($this->has_dnd_preview AND $update_guid !== '' AND is_array($rows)) { // Aplikace náhledu Drag & Dropu v levém stromu
			foreach ($rows as &$r_ref) {                                     // Hledání přetaženého záznamu v poli
				if (strcasecmp((string)$r_ref['original'], $update_guid) === 0) { // Shoda s aktivním záznamem
					$r_ref['parent_uuid'] = $this->dnd_parent;               // Nový nadřízený uzel pro zobrazení ve stromu
					$r_ref['sort_code'] = $this->dnd_sort;                   // Nové pořadí pro zobrazení ve stromu
					break;                                                   // Ukončení hledání
				}
			}
			unset($r_ref);                                                   // Uvolnění reference
		}

		// Sestavení stromové hierarchie v paměti
		$all_by_orig = [];                                                   // Mapa všech načtených položek podle original
		$children_map = [];                                                  // Mapa potomků: [parent_orig => [rows...]]
		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as $r) {                                          // Evidence všech existujících uzlů
				$orig_key = strtolower((string)$r['original']);              // Klíč originálu malými písmeny
				$all_by_orig[$orig_key] = $r;                                // Uložení do mapy uzlů
			}
			foreach ($rows as $r) {                                          // Rozřazení uzlů pod jejich rodiče
				$par_raw = strtolower(trim((string)($r['parent_uuid'] ?? ''))); // Klíč rodiče malými písmeny
				$par_key = ($par_raw !== '' AND isset($all_by_orig[$par_raw])) ? $par_raw : ''; // Sirotky zařadíme na kořenovou úroveň
				$children_map[$par_key][] = $r;                              // Přidání do seznamu potomků rodiče
			}
		}

		$tree_rows = [];                                                     // Výsledné stromově seřazené pole řádků
		$visited = [];                                                       // Evidence navštívených uzlů
		$this->append_tree_children('', 0, $children_map, $tree_rows, $visited); // Sestavení stromu od kořenových položek

		// Pojistka pro případné zbylé uzly (např. při kruhové vazbě)
		foreach ($all_by_orig as $orig_key => $r) {                          // Kontrola nenavštívených uzlů
			if (!isset($visited[$orig_key])) {                               // Pokud uzel nebyl zařazen
				$r['_tree_level'] = 0;                                       // Zařazení na úroveň 0
				$tree_rows[] = $r;                                           // Přidání na konec seznamu
			}
		}

		$master_heading = htmlspecialchars($this->phrase('master_heading', [], 'Strom položek menu')); // Nadpis levého panelu
		$lbl_show_rem = htmlspecialchars($this->phrase('lbl_show_removed', [], 'Zobrazit i zrušené')); // Popisek přepínače zrušených
		$search_placeholder = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat v menu...')); // Placeholder hledání
		$chk_show_rem = $show_removed ? 'checked' : '';                      // Stav zaškrtnutí přepínače zrušených

		$lbl_expand_all   = htmlspecialchars($this->phrase('btn_expand_all', [], 'Rozbalit vše'));   // Tlačítko rozbalení větví
		$lbl_collapse_all = htmlspecialchars($this->phrase('btn_collapse_all', [], 'Sbalit vše'));   // Tlačítko sbalení větví
		$tip_toggle_branch = htmlspecialchars($this->phrase('tip_toggle_branch', [], 'Sbalit / rozbalit podřízené položky')); // Tooltip větve
		$tip_drag_handle   = htmlspecialchars($this->phrase('tip_drag_handle', [], 'Přetažením myší (Drag & Drop) upravíte pořadí nebo nadřízenou složku v detailu')); // Tooltip D&D

		$th_caption = htmlspecialchars($this->phrase('th_menu_caption', [], 'Položka menu (Strom)')); // Záhlaví sloupce názvu
		$th_code    = htmlspecialchars($this->phrase('th_builtin_code', [], 'Kód'));                  // Záhlaví sloupce kódu
		$th_sort    = htmlspecialchars($this->phrase('th_sort_code', [], 'Pořadí'));                  // Záhlaví sloupce pořadí
		$th_role    = htmlspecialchars($this->phrase('th_system_role', [], 'Role'));                  // Záhlaví sloupce role

		$badge_txt_d = htmlspecialchars($this->phrase('badge_draft', [], 'Koncept'));         // Štítek konceptu
		$badge_txt_f = htmlspecialchars($this->phrase('badge_forwarded', [], 'Ke schválení')); // Štítek postoupeného návrhu
		$badge_txt_r = htmlspecialchars($this->phrase('badge_rejected', [], 'Vráceno'));      // Štítek vráceného návrhu
		$badge_txt_rem = htmlspecialchars($this->phrase('badge_removed', [], 'Zrušeno'));     // Štítek zrušeného záznamu

		echo <<<HTML
		<style>
			.tree-toggle-btn {
				display: inline-flex;
				align-items: center;
				justify-content: center;
				width: 18px;
				height: 18px;
				margin-right: 4px;
				border: 1px solid #cbd5e1;
				border-radius: 3px;
				background-color: #f8fafc;
				color: #334155;
				font-size: 10px;
				line-height: 1;
				cursor: pointer;
				user-select: none;
				padding: 0;
				vertical-align: middle;
			}
			.tree-toggle-btn:hover { background-color: #e2e8f0; color: #004488; }
			.tree-toggle-spacer { display: inline-block; width: 18px; margin-right: 4px; }
			.tree-ctrl-link {
				font-size: 11px;
				color: #004488;
				background: none;
				border: 1px solid #cbd5e1;
				border-radius: 3px;
				padding: 2px 6px;
				cursor: pointer;
				background-color: #fff;
			}
			.tree-ctrl-link:hover { background-color: #e9f2fa; }
			.dnd-grip {
				display: inline-block;
				color: #94a3b8;
				cursor: grab;
				margin-right: 5px;
				font-size: 13px;
				user-select: none;
				vertical-align: middle;
			}
			.dnd-grip:active { cursor: grabbing; }
			tr.dnd-dragging { opacity: 0.45; }
			tr.dnd-drop-before td { border-top: 2px solid #2563eb !important; }
			tr.dnd-drop-after td { border-bottom: 2px solid #2563eb !important; }
			tr.dnd-drop-inside td { background-color: #dbeafe !important; outline: 1px dashed #2563eb; }
		</style>
		<div class="md-master-header">
HTML;

		$this->render_master_top();                                          // Vykreslení tlačítka + Nová položka menu

		echo <<<HTML
			<div style="display: flex; justify-content: space-between; align-items: center; margin: 0 0 8px 0; flex-wrap: wrap; gap: 6px;">
				<h2 style="font-size: 16px; margin: 0; border: none; padding: 0;">{$master_heading}</h2>
				<div style="display: flex; align-items: center; gap: 6px;">
					<button type="button" class="tree-ctrl-link" onclick="expandAllMenuBranches();">{$lbl_expand_all}</button>
					<button type="button" class="tree-ctrl-link" onclick="collapseAllMenuBranches();">{$lbl_collapse_all}</button>
					<label style="font-size: 12px; color: #555; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; user-select: none; margin-left: 4px;">
						<input type="checkbox" {$chk_show_rem} onchange="toggleShowRemoved(this.checked);"> {$lbl_show_rem}
					</label>
				</div>
			</div>
			<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>

		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
						<th>{$th_caption}</th>
						<th>{$th_code}</th>
						<th style="width: 60px; text-align: center;">{$th_sort}</th>
						<th style="width: 45px; text-align: center;">{$th_role}</th>
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$page_param = urlencode($this->get_current_page_name());             // Kanonický název stránky do URL
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		foreach ($tree_rows as $row) {                                       // Vykreslení stromově seřazených řádků menu
			$uuid = (string)$row['original'];                                // Originální UUID položky menu
			$orig_low = strtolower($uuid);                                   // Normalizované UUID pro kontrolu potomků
			$par_raw = trim((string)($row['parent_uuid'] ?? ''));            // Původní UUID rodiče
			$par_low = strtolower($par_raw);                                 // Normalizované UUID rodiče
			$par_valid = ($par_low !== '' AND isset($all_by_orig[$par_low])) ? $par_low : ''; // Platný rodič ve stromu
			$b_code = (string)($row['builtin_code'] ?? '');                  // Technický kód položky
			$has_children = !empty($children_map[$orig_low]);                // Zda má položka podřízené uzly
			$is_folder = ($has_children OR $b_code === 'home' OR (empty($row['target_object']) AND trim((string)($row['target_url'] ?? '')) === '')); // Zda může přijmout podpoložky
			$level = (int)($row['_tree_level'] ?? 0);                        // Úroveň zanoření ve stromu

			$is_rem = (!empty($row['removed']) OR !empty($row['l_removed'])); // Zda je položka nebo překlad zrušený
			$is_act = (strcasecmp($uuid, $update_guid) === 0);               // Zda jde o právě vybranou položku
			if ($is_act AND $is_rem) {                                       // Aktivní zrušený řádek
				$rowClass = 'md-row-active md-row-Active-removed';           // Kombinovaná třída
			} elseif ($is_act) {                                             // Aktivní platný řádek
				$rowClass = 'md-row-active';                                 // Třída aktivního řádku
			} elseif ($is_rem) {                                             // Zrušený řádek
				$rowClass = 'md-row-removed';                                // Třída zrušeného řádku
			} elseif (!empty($row['inactive'])) {                            // Neaktivní položka
				$rowClass = 'md-row-inactive';                               // Třída neaktivního řádku
			} else {
				$rowClass = '';                                              // Standardní řádek
			}
			$rowIdAttr = $is_act ? 'id="active-row"' : '';                   // Atribut id pro automatický scroll

			$rec_type = (string)($row['record_type'] ?? 'A');                // Typ záznamu ('A' nebo 'D')
			$app_status = (string)($row['approval_status'] ?? 'A');          // Stav schválení ('A', 'D', 'F', 'R')
			$ssc_badge = '';                                                 // Vizuální štítky stavu
			if ($is_rem) {                                                   // Štítek zrušené položky
				$ssc_badge .= "<span class=\"ssc-badge ssc-badge-rem\">{$badge_txt_rem}</span>"; // Červený štítek
			}
			if ($rec_type === 'D') {                                         // Štítek konceptu
				if ($app_status === 'F') {                                   // Postoupeno ke schválení
					$ssc_badge .= "<span class=\"ssc-badge ssc-badge-f\">{$badge_txt_f}</span>"; // Modrý štítek
				} elseif ($app_status === 'R') {                             // Vráceno
					$ssc_badge .= "<span class=\"ssc-badge ssc-badge-r\">{$badge_txt_r}</span>"; // Červený štítek
				} else {
					$ssc_badge .= "<span class=\"ssc-badge ssc-badge-d\">{$badge_txt_d}</span>"; // Žlutý štítek
				}
			}

			$indent_px = $level * 18;                                        // Odsazení zleva podle úrovně ve stromu
			$toggle_html = $has_children
				? "<button type=\"button\" class=\"tree-toggle-btn\" data-toggle-orig=\"{$orig_low}\" title=\"{$tip_toggle_branch}\" onclick=\"toggleMenuBranch(event, '{$orig_low}');\">▼</button>"
				: "<span class=\"tree-toggle-spacer\"></span>";              // Tlačítko sbalení/rozbalení nebo odsazení listu

			$can_drag_row = ($this->can_edit_structure AND $b_code !== 'home'); // Kořenovou položku Domů nelze přesouvat
			$drag_attr = $can_drag_row ? 'draggable="true"' : '';            // HTML5 atribut draggable
			$grip_html = $can_drag_row ? "<span class=\"dnd-grip\" title=\"{$tip_drag_handle}\">⋮⋮</span>" : ""; // Úchyt pro Drag & Drop

			$cap_raw = (string)($row['caption'] ?: $b_code);                 // Zobrazovaný název položky
			$safe_cap = htmlspecialchars($cap_raw);                          // Ošetřený název položky
			$cap_html = $has_children ? "<strong>{$safe_cap}</strong>" : $safe_cap; // Složky zvýrazníme tučně

			$safe_uuid = htmlspecialchars($uuid);                            // Ošetřené původní UUID
			$safe_par_uuid = htmlspecialchars($par_raw);                     // Ošetřené původní UUID rodiče
			$safe_code = htmlspecialchars($b_code);                          // Ošetřený technický kód
			$safe_sort = htmlspecialchars((string)($row['sort_code'] ?? '')); // Ošetřený řadicí kód
			$safe_role = htmlspecialchars((string)($row['system_role'] ?? 'S')); // Ošetřená systémová role
			$folder_flag = $is_folder ? '1' : '0';                           // Příznak složky pro Drag & Drop

			$row_url = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$uuid}"); // Cílová URL řádku

			echo <<<HTML
					<tr class="{$rowClass}" {$rowIdAttr} {$drag_attr}
						data-uuid="{$safe_uuid}"
						data-orig="{$orig_low}"
						data-parent="{$par_valid}"
						data-parent-uuid="{$safe_par_uuid}"
						data-sort="{$safe_sort}"
						data-code="{$safe_code}"
						data-level="{$level}"
						data-is-folder="{$folder_flag}"
						style="cursor: pointer;"
						onclick="document.location='{$row_url}'">
						<td class="cell-tree-caption" style="padding-left: calc(6px + {$indent_px}px);">{$grip_html}{$toggle_html}<span class="tree-caption-text">{$cap_html}</span>{$ssc_badge}</td>
						<td style="font-family: monospace; font-size: 12px; color: #475569;">{$safe_code}</td>
						<td class="cell-tree-sort" style="text-align: center; font-family: monospace; font-size: 12px;">{$safe_sort}</td>
						<td style="text-align: center; font-weight: bold; font-size: 11px;">{$safe_role}</td>
					</tr>
HTML;
		}

		$js_base_url = addslashes("index.php?page={$page_param}{$url_suffix}"); // Základní URL pro přechod na neaktivní přetažený řádek
		$js_curr_guid = addslashes(strtolower($update_guid));                // Normalizované UUID právě otevřeného záznamu
		$js_can_dnd = $this->can_edit_structure ? 'true' : 'false';          // Zda je povolen Drag & Drop

		echo <<<HTML
				</tbody>
			</table>
		</div>

		<script>
			(function() {
				const STORAGE_KEY = 'bcm_meta_menu_collapsed';
				const currentOpenOrig = '{$js_curr_guid}';
				const canDragDrop = {$js_can_dnd};
				const basePageUrl = '{$js_base_url}';

				// Načtení sbalených větví ze sessionStorage prohlížeče
				function getCollapsedSet() {
					try {
						const raw = sessionStorage.getItem(STORAGE_KEY);
						const arr = raw ? JSON.parse(raw) : [];
						return new Set(Array.isArray(arr) ? arr : []);
					} catch (e) {
						return new Set();
					}
				}

				function saveCollapsedSet(setObj) {
					try {
						sessionStorage.setItem(STORAGE_KEY, JSON.stringify(Array.from(setObj)));
					} catch (e) {}
				}

				// Zajistí, že předci právě vybraného řádku (#active-row) nebudou sbalení
				function ensureActiveRowVisible(collapsedSet) {
					if (!currentOpenOrig) return;
					const rowsMap = {};
					document.querySelectorAll('#master-list tr[data-orig]').forEach(function(r) {
						rowsMap[r.dataset.orig] = r.dataset.parent || '';
					});
					let p = rowsMap[currentOpenOrig] || '';
					let guard = 0;
					while (p !== '' && guard < 50) {
						collapsedSet.delete(p);
						p = rowsMap[p] || '';
						guard++;
					}
				}

				// Překreslí viditelnost řádků a ikony ▼/▶ podle stavu sbalení
				window.applyMenuTreeVisibility = function() {
					const filterInput = document.getElementById('master-filter');
					if (filterInput && filterInput.value.trim() !== '') {
						return;
					}
					const collapsedSet = getCollapsedSet();
					const parentLookup = {};
					const allRows = document.querySelectorAll('#master-list tr[data-orig]');

					allRows.forEach(function(r) {
						parentLookup[r.dataset.orig] = r.dataset.parent || '';
						const btn = r.querySelector('.tree-toggle-btn');
						if (btn) {
							btn.textContent = collapsedSet.has(r.dataset.orig) ? '▶' : '▼';
						}
					});

					allRows.forEach(function(r) {
						let p = r.dataset.parent || '';
						let hiddenByAncestor = false;
						let guard = 0;
						while (p !== '' && guard < 50) {
							if (collapsedSet.has(p)) {
								hiddenByAncestor = true;
								break;
							}
							p = parentLookup[p] || '';
							guard++;
						}
						r.style.display = hiddenByAncestor ? 'none' : '';
					});
				};

				window.toggleMenuBranch = function(ev, orig) {
					ev.stopPropagation();
					ev.preventDefault();
					const collapsedSet = getCollapsedSet();
					if (collapsedSet.has(orig)) {
						collapsedSet.delete(orig);
					} else {
						collapsedSet.add(orig);
					}
					saveCollapsedSet(collapsedSet);
					window.applyMenuTreeVisibility();
				};

				window.expandAllMenuBranches = function() {
					saveCollapsedSet(new Set());
					window.applyMenuTreeVisibility();
				};

				window.collapseAllMenuBranches = function() {
					const collapsedSet = new Set();
					document.querySelectorAll('#master-list .tree-toggle-btn').forEach(function(btn) {
						const orig = btn.getAttribute('data-toggle-orig');
						if (orig) {
							const row = btn.closest('tr');
							if (!row || row.dataset.code !== 'home') {
								collapsedSet.add(orig);
							}
						}
					});
					saveCollapsedSet(collapsedSet);
					window.applyMenuTreeVisibility();
				};

				// Při vymazání vyhledávacího pole obnovíme sbalení větví
				const fInp = document.getElementById('master-filter');
				if (fInp) {
					fInp.addEventListener('input', function() {
						if (this.value.trim() === '') {
							setTimeout(window.applyMenuTreeVisibility, 10);
						}
					});
				}

				const initSet = getCollapsedSet();
				ensureActiveRowVisible(initSet);
				saveCollapsedSet(initSet);
				window.applyMenuTreeVisibility();

				// =============================================================
				// DRAG & DROP (Varianta 1: Úprava parent_uuid a sort_code v detailu)
				// =============================================================
				if (!canDragDrop) return;

				const tbody = document.getElementById('master-list');
				if (!tbody) return;

				let draggedRow = null;
				let draggedDescendants = new Set();

				// Zjistí všechny potomky taženého uzlu (ochrana proti zacyklení)
				function collectSubtreeOrigs(rootOrig) {
					const set = new Set([rootOrig]);
					let added = true;
					while (added) {
						added = false;
						tbody.querySelectorAll('tr[data-orig]').forEach(function(r) {
							const o = r.dataset.orig;
							const p = r.dataset.parent || '';
							if (p !== '' && set.has(p) && !set.has(o)) {
								set.add(o);
								added = true;
							}
						});
					}
					return set;
				}

				function clearDropIndicators() {
					tbody.querySelectorAll('tr').forEach(function(r) {
						r.classList.remove('dnd-drop-before', 'dnd-drop-after', 'dnd-drop-inside');
					});
				}

				// Výpočet nového lexikografického sort_code (po desítkách nebo půlením intervalu)
				function computeBetweenSortCode(prevCode, nextCode) {
					const cleanPrev = (prevCode || '').replace(/[^0-9]/g, '');
					const cleanNext = (nextCode || '').replace(/[^0-9]/g, '');

					// 1. Prázdná větev -> '010'
					if (cleanPrev === '' && cleanNext === '') {
						return '010';
					}

					// 2. Vložení na konec větve -> zaokrouhlení na další desítku ('010' -> '020')
					if (cleanNext === '') {
						const padLen = Math.max(cleanPrev.length, 3);
						const paddedPrev = cleanPrev.padEnd(padLen, '0');
						const prevNum = parseInt(paddedPrev, 10) || 0;
						const nextTen = (Math.floor(prevNum / 10) + 1) * 10;
						return String(nextTen).padStart(padLen, '0');
					}

					// 3. Vložení před první položku nebo mezi dvě položky
					let len = Math.max(cleanPrev.length, cleanNext.length, 3);
					while (len <= 18) {
						const pStr = cleanPrev === '' ? ''.padEnd(len, '0') : cleanPrev.padEnd(len, '0');
						const nStr = cleanNext.padEnd(len, '0');
						const pNum = parseInt(pStr, 10) || 0;
						const nNum = parseInt(nStr, 10) || 0;

						if (nNum - pNum > 1) {
							const mid = Math.floor((pNum + nNum) / 2);
							let res = String(mid).padStart(len, '0');
							if (res.length > 3) {
								res = res.replace(/0+$/, '');
								if (res.length < 3) res = res.padEnd(3, '0');
							}
							if ((cleanPrev === '' || res > prevCode) && res < nextCode) {
								return res;
							}
						}
						len++;
					}

					return (prevCode || '000') + '5';
				}

				// Určí zónu puštění myši nad cílovým řádkem ('before', 'after', 'inside')
				function resolveDropMode(targetRow, clientY) {
					const rect = targetRow.getBoundingClientRect();
					const relY = clientY - rect.top;
					const height = rect.height || 30;
					const isFolder = (targetRow.dataset.isFolder === '1');
					const isRootHome = (targetRow.dataset.code === 'home');

					if (isRootHome) {
						return 'inside';
					}
					if (isFolder) {
						if (relY < height * 0.25) return 'before';
						if (relY > height * 0.75) return 'after';
						return 'inside';
					}
					return (relY < height * 0.5) ? 'before' : 'after';
				}

				tbody.addEventListener('dragstart', function(e) {
					const tr = e.target.closest('tr[data-orig]');
					if (!tr || tr.dataset.code === 'home') {
						e.preventDefault();
						return;
					}
					draggedRow = tr;
					draggedDescendants = collectSubtreeOrigs(tr.dataset.orig);
					tr.classList.add('dnd-dragging');
					if (e.dataTransfer) {
						e.dataTransfer.effectAllowed = 'move';
						e.dataTransfer.setData('text/plain', tr.dataset.uuid);
					}
				});

				tbody.addEventListener('dragend', function() {
					if (draggedRow) {
						draggedRow.classList.remove('dnd-dragging');
					}
					draggedRow = null;
					draggedDescendants.clear();
					clearDropIndicators();
				});

				tbody.addEventListener('dragover', function(e) {
					if (!draggedRow) return;
					const targetRow = e.target.closest('tr[data-orig]');
					if (!targetRow || draggedDescendants.has(targetRow.dataset.orig)) {
						clearDropIndicators();
						return;
					}
					e.preventDefault();
					if (e.dataTransfer) {
						e.dataTransfer.dropEffect = 'move';
					}
					clearDropIndicators();
					const mode = resolveDropMode(targetRow, e.clientY);
					targetRow.classList.add('dnd-drop-' + mode);
				});

				tbody.addEventListener('dragleave', function(e) {
					const targetRow = e.target.closest('tr[data-orig]');
					if (targetRow) {
						targetRow.classList.remove('dnd-drop-before', 'dnd-drop-after', 'dnd-drop-inside');
					}
				});

				tbody.addEventListener('drop', function(e) {
					if (!draggedRow) return;
					const targetRow = e.target.closest('tr[data-orig]');
					clearDropIndicators();
					if (!targetRow || draggedDescendants.has(targetRow.dataset.orig)) {
						return;
					}
					e.preventDefault();
					e.stopPropagation();

					const mode = resolveDropMode(targetRow, e.clientY);
					const dragOrig = draggedRow.dataset.orig;
					const dragUuid = draggedRow.dataset.uuid;

					let newParentOrig = '';
					let newParentUuid = '';
					let prevSort = '';
					let nextSort = '';

					if (mode === 'inside') {
						newParentOrig = targetRow.dataset.orig;
						newParentUuid = targetRow.dataset.uuid;
						// Najdeme stávající přímé potomky cílové složky (mimo tažený uzel)
						const existingChildren = Array.from(tbody.querySelectorAll('tr[data-orig]')).filter(function(r) {
							return (r.dataset.parent || '') === newParentOrig && r.dataset.orig !== dragOrig;
						});
						if (existingChildren.length > 0) {
							prevSort = existingChildren[existingChildren.length - 1].dataset.sort || '';
						}
					} else {
						newParentOrig = targetRow.dataset.parent || '';
						newParentUuid = targetRow.dataset.parentUuid || '';
						const siblings = Array.from(tbody.querySelectorAll('tr[data-orig]')).filter(function(r) {
							return (r.dataset.parent || '') === newParentOrig && r.dataset.orig !== dragOrig;
						});
						const tIdx = siblings.indexOf(targetRow);
						if (mode === 'before') {
							prevSort = (tIdx > 0) ? (siblings[tIdx - 1].dataset.sort || '') : '';
							nextSort = targetRow.dataset.sort || '';
						} else {
							prevSort = targetRow.dataset.sort || '';
							nextSort = (tIdx >= 0 && tIdx + 1 < siblings.length) ? (siblings[tIdx + 1].dataset.sort || '') : '';
						}
					}

					const newSortCode = computeBetweenSortCode(prevSort, nextSort);

					// Pokud přetahujeme položku, která ještě není vpravo otevřená, otevřeme ji s předvyplněnými poli
					if (dragOrig !== currentOpenOrig) {
						const targetUrl = basePageUrl
							+ '&update_guid=' + encodeURIComponent(dragUuid)
							+ '&dnd_parent=' + encodeURIComponent(newParentUuid)
							+ '&dnd_sort=' + encodeURIComponent(newSortCode);
						window.location.href = targetUrl;
						return;
					}

					// Položka je již otevřená v pravém panelu -> přímo upravíme obě pole v DOM formuláře bez reloadu
					const parentSelect = document.querySelector('.md-detail form [name="parent_uuid"]');
					const sortInput = document.querySelector('.md-detail form [name="sort_code"]');

					if (parentSelect) {
						let matchedVal = newParentUuid;
						if (parentSelect.options) {
							Array.from(parentSelect.options).forEach(function(opt) {
								if (opt.value.toLowerCase() === newParentUuid.toLowerCase()) {
									matchedVal = opt.value;
								}
							});
						}
						parentSelect.value = matchedVal;
						parentSelect.style.backgroundColor = '#dcfce7';
						parentSelect.style.borderColor = '#16a34a';
					}

					if (sortInput) {
						sortInput.value = newSortCode;
						sortInput.style.backgroundColor = '#dcfce7';
						sortInput.style.borderColor = '#16a34a';
					}

					const banner = document.getElementById('menu-dnd-banner');
					if (banner) {
						banner.style.display = 'block';
					}

					isFormDirty = true;

					// Aktualizace datových atributů a vizuální přeskládání stromu v levém panelu
					draggedRow.dataset.parent = newParentOrig;
					draggedRow.dataset.parentUuid = newParentUuid;
					draggedRow.dataset.sort = newSortCode;
					const sortCell = draggedRow.querySelector('.cell-tree-sort');
					if (sortCell) {
						sortCell.textContent = newSortCode;
					}

					// Rozbalíme cílovou složku, pokud do ní byla položka vložena
					if (newParentOrig !== '') {
						const cSet = getCollapsedSet();
						if (cSet.has(newParentOrig)) {
							cSet.delete(newParentOrig);
							saveCollapsedSet(cSet);
						}
					}

					// Přepočet pořadí a odsazení všech řádků v tabulce #master-list
					const allRows = Array.from(tbody.querySelectorAll('tr[data-orig]'));
					const byParent = {};
					allRows.forEach(function(r) {
						const p = r.dataset.parent || '';
						if (!byParent[p]) byParent[p] = [];
						byParent[p].push(r);
					});

					Object.keys(byParent).forEach(function(p) {
						byParent[p].sort(function(a, b) {
							const sa = a.dataset.sort || '';
							const sb = b.dataset.sort || '';
							if (sa !== sb) return sa < sb ? -1 : 1;
							return (a.dataset.code || '').localeCompare(b.dataset.code || '');
						});
					});

					const orderedRows = [];
					const visitedSet = new Set();
					function walkDomTree(pKey, lvl) {
						const list = byParent[pKey] || [];
						list.forEach(function(r) {
							const o = r.dataset.orig;
							if (visitedSet.has(o)) return;
							visitedSet.add(o);
							r.dataset.level = String(lvl);
							const capCell = r.querySelector('.cell-tree-caption');
							if (capCell) {
								capCell.style.paddingLeft = 'calc(6px + ' + (lvl * 18) + 'px)';
							}
							orderedRows.push(r);
							walkDomTree(o, lvl + 1);
						});
					}
					walkDomTree('', 0);
					orderedRows.forEach(function(r) {
						tbody.appendChild(r);
					});

					window.applyMenuTreeVisibility();
				});
			})();
		</script>
HTML;
	}
}