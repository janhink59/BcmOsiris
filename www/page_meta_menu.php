<?php
/**
 * =============================================================================
 * Verze: 2026-10-24 13:15
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
 * - V levém panelu (`render_master()`) sestavuje z načtených položek vizuální
 *   stromovou hierarchii seřazenou podle `parent_uuid` a `sort_code`, aby byla
 *   struktura a pořadí položek okamžitě přehledné.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_menu extends abstract_page_master_detail {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		global $dbsession;                                                   // Globální kontext relace uživatele
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role přihlášeného uživatele

		$this->class_name = 'meta_menu';                                     // Logická třída pro entity_manager
		$this->allow_insert = ($active_role === 'D');                        // Zakládání nových položek menu pouze pro roli Developer
		$this->page_title = $this->phrase('page_title', [], 'Správa položek menu (Navigace)'); // Lokalizovaný titulek stránky

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
	 * Vykreslí nadpisovou poznámku v detailu s vysvětlením chování složek vs. koncových listů.
	 */
	protected function render_detail_top(): void {
		$note = htmlspecialchars($this->phrase('msg_menu_hierarchy_hint', [], 'Tip: Položky, které mají podřízené uzly, fungují v navigaci automaticky jako složky (rozcestníky). Cílová stránka (target_object) se uplatní u koncových položek.')); // Text nápovědy
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy
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
	 * jejich kódem (`builtin_code`), pořadím (`sort_code`) a rolí (`system_role`).
	 */
	protected function render_master(): void {
		if ($this->em === null) {                                            // Kontrola inicializace správce entit
			return;                                                          // Ukončení při chybějícím správci
		}

		$update_guid = (string)getinput('update_guid');                      // Aktuálně vybraná položka v detailu
		$show_removed = ((string)getinput('show_removed') === '1');          // Příznak zobrazení zrušených položek

		$rows = $this->em->fetch_rows($this->master_where, 'sort_code ASC, builtin_code ASC', false, $show_removed); // Načtení položek s překlady

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

		$th_caption = htmlspecialchars($this->phrase('th_menu_caption', [], 'Položka menu (Strom)')); // Záhlaví sloupce názvu
		$th_code    = htmlspecialchars($this->phrase('th_builtin_code', [], 'Kód'));                  // Záhlaví sloupce kódu
		$th_sort    = htmlspecialchars($this->phrase('th_sort_code', [], 'Pořadí'));                  // Záhlaví sloupce pořadí
		$th_role    = htmlspecialchars($this->phrase('th_system_role', [], 'Role'));                  // Záhlaví sloupce role

		$badge_txt_d = htmlspecialchars($this->phrase('badge_draft', [], 'Koncept'));         // Štítek konceptu
		$badge_txt_f = htmlspecialchars($this->phrase('badge_forwarded', [], 'Ke schválení')); // Štítek postoupeného návrhu
		$badge_txt_r = htmlspecialchars($this->phrase('badge_rejected', [], 'Vráceno'));      // Štítek vráceného návrhu
		$badge_txt_rem = htmlspecialchars($this->phrase('badge_removed', [], 'Zrušeno'));     // Štítek zrušeného záznamu

		echo <<<HTML
		<div class="md-master-header">
HTML;

		$this->render_master_top();                                          // Vykreslení tlačítka + Nová položka menu

		echo <<<HTML
			<div style="display: flex; justify-content: space-between; align-items: center; margin: 0 0 10px 0;">
				<h2 style="font-size: 16px; margin: 0; border: none; padding: 0;">{$master_heading}</h2>
				<label style="font-size: 12px; color: #555; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; user-select: none;">
					<input type="checkbox" {$chk_show_rem} onchange="toggleShowRemoved(this.checked);"> {$lbl_show_rem}
				</label>
			</div>
			<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>

		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
						<th>{$th_caption}</th>
						<th>{$th_code}</th>
						<th style="width: 55px; text-align: center;">{$th_sort}</th>
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
			$has_children = !empty($children_map[$orig_low]);                // Zda je položka složkou (má podřízené položky)
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
			$branch_prefix = ($level > 0) ? '<span style="color: #94a3b8; margin-right: 4px;">└─</span>' : ''; // Vizuální značka větve
			$cap_raw = (string)($row['caption'] ?: $row['builtin_code']);    // Zobrazovaný název položky
			$safe_cap = htmlspecialchars($cap_raw);                          // Ošetřený název položky
			$cap_html = $has_children ? "<strong>{$safe_cap}</strong>" : $safe_cap; // Složky zvýrazníme tučně

			$safe_code = htmlspecialchars((string)($row['builtin_code'] ?? '')); // Ošetřený technický kód
			$safe_sort = htmlspecialchars((string)($row['sort_code'] ?? ''));    // Ošetřený řadicí kód
			$safe_role = htmlspecialchars((string)($row['system_role'] ?? 'S')); // Ošetřená systémová role

			$row_url = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$uuid}"); // Cílová URL řádku

			echo <<<HTML
					<tr class="{$rowClass}" {$rowIdAttr} style="cursor: pointer;" onclick="document.location='{$row_url}'">
						<td style="padding-left: calc(6px + {$indent_px}px);">{$branch_prefix}{$cap_html}{$ssc_badge}</td>
						<td style="font-family: monospace; font-size: 12px; color: #475569;">{$safe_code}</td>
						<td style="text-align: center; font-family: monospace; font-size: 12px;">{$safe_sort}</td>
						<td style="text-align: center; font-weight: bold; font-size: 11px;">{$safe_role}</td>
					</tr>
HTML;
		}

		echo <<<HTML
				</tbody>
			</table>
		</div>
HTML;
	}
}