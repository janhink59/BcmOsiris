<?php
/**
 * =============================================================================
 * Verze: 2026-10-31 11:30
 * Soubor: abstract_page_tree.php
 * Třída: abstract_page_tree
 * Účel: Znovupoužitelná abstraktní šablona pro všechny stromové (hierarchické)
 *       stránky v systému BCM Osiris (page_meta_menu, page_hierarchy,
 *       page_hierarchy_item a v dalších krocích page_asset_class, page_threat,
 *       page_impact, page_scenario).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Dědí z `abstract_page_master_detail` (`abstract_page_master_detail.php`).
 * - Využívá `entity_manager` (`entity_manager.php`) pro načtení záznamů
 *   (`fetch_rows()`) a vyhodnocení uzamčení větví hierarchie
 *   (`is_hierarchy_node_locked()`).
 * - V levém panelu (`render_master()`) sestaví strom v paměti podle `parent_uuid`
 *   a `sort_code` a vykreslí stromovou tabulku s:
 *   1. Klientským sbalováním a rozbalováním větví (Collapse / Expand) v `sessionStorage`.
 *   2. Vizuálním rozlišením složek (`is_leaf = 0`, ikona 📁) a koncových listů
 *      (`is_leaf = 1`) a indikací uzamčených uzlů (🔒).
 *   3. Podporou Drag & Drop (Varianta 1): přetažení uzlu v levém stromu vypočítá
 *      nový `parent_uuid` a lexikografický `sort_code` a předvyplní je do pravého
 *      detailního formuláře se zapnutím `isFormDirty = true` a `window.isTreeDomDirty = true`
 *      (bez přímého zápisu do DB).
 *   4. Ochranou pravidel hierarchie při Drag & Dropu:
 *      - Vložit uzel dovnitř (`inside`) lze pouze do složky (`is_leaf = 0`).
 *      - U uzamčeného uzlu (`data-locked="1"`) lze měnit pouze jeho pořadí (`sort_code`)
 *        mezi sourozenci pod stejným rodičem (`parent_uuid`), nikoliv jej přepodřizovat.
 *
 * Změny:
 * 2026-10-31 11:30 - Explicitní deklarace všech konfigurovatelných vlastností třídy
 *                    (`$storage_key_prefix`, `$tree_heading`, `$tree_caption_header`,
 *                    `$new_button_code`, `$new_button_default_caption`, `$tree_extra_columns`,
 *                    `$protected_root_codes`, `$can_edit_structure`) pro plnou kompatibilitu
 *                    s PHP 8.3 (odstranění varování Creation of dynamic property).
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page_tree extends abstract_page_master_detail {

	// --- Konfigurovatelné vlastnosti stromové šablony (nastavují potomci v konstruktoru) ---
	protected string $parent_column = 'parent_uuid';                         // Název sloupce odkazu na nadřízený uzel
	protected string $sort_column = 'sort_code';                             // Název sloupce pro řazení sourozenců
	protected string $code_column = 'builtin_code';                          // Název sloupce s technickým kódem uzlu
	protected string $leaf_column = 'is_leaf';                               // Název sloupce příznaku koncového listu (1 = list, 0 = složka)

	protected bool $can_edit_structure = true;                               // Zda má uživatel právo měnit hierarchii a pořadí (D&D)
	protected array $protected_root_codes = [];                              // Seznam kódů kořenových uzlů chráněných proti přesunu (např. ['home'])
	protected string $storage_key_prefix = 'bcm_tree_collapsed';             // Prefix klíče v sessionStorage pro uložení sbalených větví

	protected string $tree_heading = '';                                     // Nadpis levého stromového panelu
	protected string $tree_caption_header = '';                              // Záhlaví prvního (stromového) sloupce tabulky
	protected string $new_button_code = 'btn_new_tree_item';                 // Kód fráze tlačítka pro založení nového uzlu
	protected string $new_button_default_caption = '+ Nová položka';         // Výchozí popisek tlačítka pro založení nového uzlu
	protected array $tree_extra_columns = [];                                // Volitelné doplňkové sloupce v tabulce stromu

	// --- Interní stav pro přenos neuloženého Drag & Drop přesunu do detailu ---
	protected bool $has_dnd_preview = false;                                 // Zda byl detail otevřen přetažením (Drag & Drop)
	protected string $dnd_parent = '';                                       // Předvyplněný parent_uuid z Drag & Dropu (nebo nadřazené složky)
	protected string $dnd_sort = '';                                         // Předvyplněný sort_code z Drag & Dropu

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu v předkovi

		$this->can_edit_structure = !$this->is_readonly;                     // Výchozí povolení úpravy stromu podle readonly stavu

		if (isset($_GET['dnd_sort']) OR isset($_GET['dnd_parent'])) {        // Detekce parametrů z Drag & Drop přetažení nebo nové položky pod složkou
			$this->dnd_parent = trim((string)getinput('dnd_parent'));        // Nový nadřízený uzel z URL
			$this->dnd_sort = trim((string)getinput('dnd_sort'));            // Nový řadicí kód z URL
			if (isset($_GET['dnd_sort']) AND (string)getinput('update_guid') !== 'NEW') { // Pouze při přesunu existujícího uzlu
				$this->has_dnd_preview = true;                               // Zapnutí režimu neuloženého náhledu po přetažení
			}
		}
	}

	/**
	 * Určí, zda daný řádek představuje složku (vnitřní uzel), do které lze vkládat podřízené položky.
	 * Potomek (např. page_meta_menu) může tuto metodu překrýt, pokud tabulka nemá sloupec is_leaf.
	 */
	protected function is_node_folder(array $row, bool $has_children): bool { // Vyhodnocení, zda je uzel složkou
		if ($this->em !== null AND $this->em->has_physical_column($this->leaf_column)) { // Pokud tabulka obsahuje sloupec is_leaf
			return ($has_children OR empty($row[$this->leaf_column]));       // Složkou je uzel s is_leaf = 0 nebo s existujícími potomky
		}
		return $has_children;                                                // Výchozí chování bez sloupce is_leaf
	}

	/**
	 * Určí, zda je uzel chráněným kořenem, který nelze přetahovat myší (např. 0x00 nebo 'home').
	 */
	protected function is_protected_root_node(array $row): bool {            // Kontrola chráněného kořenového uzlu
		$orig = strtolower(trim((string)($row['original'] ?? '')));          // UUID originálu uzlu
		if ($orig === '0x00' OR $orig === '00000000-0000-0000-0000-000000000000') { // Systémový kořen 0x00
			return true;                                                     // Kořen 0x00 nelze přesouvat
		}
		$code = (string)($row[$this->code_column] ?? '');                    // Technický kód uzlu
		return ($code !== '' AND in_array($code, $this->protected_root_codes, true)); // Kontrola v poli chráněných kódů
	}

	/**
	 * Vykreslí tlačítko pro založení nové položky v horní části levého panelu.
	 * Pokud je v levém stromu právě vybrána složka (`is_leaf = 0`), tlačítko předá její UUID
	 * v parametru `dnd_parent`, aby se v novém záznamu rovnou předvyplnila jako nadřízený uzel.
	 */
	protected function render_master_top(): void {
		if (!$this->allow_insert) {                                          // Pokud zakládání nových záznamů není povoleno
			return;                                                          // Tlačítko nevykreslujeme
		}

		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL pro zachování kontextu (např. hierarchy)
		$page_param = urlencode($this->get_current_page_name());             // Kanonický název aktuální stránky
		$new_url = "index.php?page={$page_param}{$url_suffix}&update_guid=NEW"; // Základní cílová adresa pro novou položku
		$js_new_url = addslashes($new_url);                                  // Ošetřená URL pro JS handler

		$js_onclick = "
			var targetUrl = '{$js_new_url}';
			var actRow = document.getElementById('active-row');
			if (actRow && actRow.getAttribute('data-is-folder') === '1' && actRow.getAttribute('data-uuid')) {
				targetUrl += '&dnd_parent=' + encodeURIComponent(actRow.getAttribute('data-uuid'));
			}
			if (window.loadDetailPanel) {
				window.loadDetailPanel(targetUrl);
				return false;
			}
			window.location.href = targetUrl;
			return false;
		";                                                                   // JS pro převzetí vybrané složky jako rodiče nového záznamu
		$js_onclick_inline = trim((string)preg_replace('/\s+/', ' ', $js_onclick)); // Zploštění JS na jeden řádek

		$btn_new = new abstract_button(                                      // Vytvoření tlačítka přes abstract_button
			$this->new_button_code,                                          // Kód fráze tlačítka
			$this->new_button_default_caption,                               // Výchozí český popisek tlačítka
			get_class($this)                                                 // Zdrojová třída fráze
		);
		$btn_new->set_href($new_url)                                         // Nastavení výchozího href atributu
			->set_onclick($js_onclick_inline)                                // Asynchronní otevření nového detailu
			->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Roztažení na celou šířku levého panelu

		echo $btn_new->render();                                             // Vykreslení tlačítka nad stromem
	}

	/**
	 * Aplikuje předvyplněné hodnoty z Drag & Dropu (nebo nadřazené složky u NEW) do `$datarow`
	 * a vykreslí informační pruh pro potvrzení přesunu či upozornění na uzamčenou větev.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený datový řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu v detailu

		// 1. Při založení nového záznamu (NEW) pod vybranou složkou předvyplníme parent_uuid a další volný sort_code
		if ($update_guid === 'NEW' AND is_array($datarow)) {                 // Režim zakládání nového uzlu
			if ($this->dnd_parent !== '' AND ($datarow[$this->parent_column] ?? '') === '') { // Pokud byla předána nadřazená složka
				$datarow[$this->parent_column] = $this->dnd_parent;          // Předvyplnění nadřízeného uzlu
			}
			if ($this->dnd_sort !== '' AND ($datarow[$this->sort_column] ?? '') === '') { // Pokud byl předán řadicí kód
				$datarow[$this->sort_column] = $this->dnd_sort;              // Předvyplnění řadicího kódu
			}
		}

		// 2. Při přetažení existujícího záznamu myší (Drag & Drop) propíšeme nové hodnoty do $datarow bez zápisu do DB
		if ($this->has_dnd_preview AND $this->can_edit_structure AND is_array($datarow)) { // Náhled po přetažení
			$is_locked = ($this->em !== null AND $update_guid !== '' AND $update_guid !== 'NEW' AND $this->em->is_hierarchy_node_locked($update_guid)); // Kontrola zámku
			if (!$is_locked) {                                               // U neuzamčeného uzlu propíšeme i změnu rodiče
				$datarow[$this->parent_column] = $this->dnd_parent;          // Přepsání parent_uuid v detailu
			}
			$datarow[$this->sort_column] = $this->dnd_sort;                  // Přepsání sort_code v detailu
		}

		// 3. Informační pruh o neuloženém přesunu Drag & Drop
		$msg_dnd = htmlspecialchars($this->phrase('msg_dnd_unsaved_notice', [], 'Nadřízená položka (parent_uuid) a pořadí (sort_code) byly upraveny přetažením. Zkontrolujte údaje a potvrďte je tlačítkem Uložit změny (příp. Uložit koncept / Předat ke schválení).')); // Text výzvy
		$disp_dnd = ($this->has_dnd_preview AND $this->can_edit_structure) ? 'block' : 'none'; // Viditelnost pruhu
		echo "<div id=\"tree-dnd-banner\" class=\"msg-info\" style=\"display: {$disp_dnd}; margin-bottom: 12px; background-color: #f0fdf4; border-left-color: #16a34a; color: #166534;\">{$msg_dnd}</div>\n"; // Zelený informační pruh

		// 4. Informační pruh u uzlu, který je uzamčen platnými vazbami v tabulce link
		if ($this->em !== null AND $update_guid !== '' AND $update_guid !== 'NEW' AND $this->em->is_hierarchy_node_locked($update_guid)) { // Pokud je větev uzamčena
			$msg_lck = htmlspecialchars($this->phrase('msg_node_locked_notice', [], '🔒 Tento uzel (nebo jeho podřízený uzel) má již navázané platné záznamy. Změna nadřízeného uzlu (přepodřízení) a smazání jsou uzamčeny; měnit lze pouze pořadí v rámci sourozenců a textové popisky.')); // Text uzamčení
			echo "<div class=\"msg-info\" style=\"margin-bottom: 12px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e; font-weight: normal; font-size: 12px;\">{$msg_lck}</div>\n"; // Žlutý pruh uzamčení
		}

		if ($this->has_dnd_preview AND $this->can_edit_structure) {          // Zvýraznění změněných polí po AJAX D&D přetažení
			$p_col = addslashes($this->parent_column);                       // Název sloupce rodiče pro JS selektor
			$s_col = addslashes($this->sort_column);                         // Název sloupce pořadí pro JS selektor
			echo <<<HTML
			<script>
				setTimeout(function() {
					isFormDirty = true;
					window.isTreeDomDirty = true;
					const pSel = document.querySelector('.md-detail form [name="{$p_col}"]');
					const sInp = document.querySelector('.md-detail form [name="{$s_col}"]');
					[pSel, sInp].forEach(function(el) {
						if (el && !el.disabled && !el.readOnly) {
							el.style.backgroundColor = '#dcfce7';
							el.style.borderColor = '#16a34a';
						}
					});
				}, 20);
			</script>
HTML;
		}
	}

	/**
	 * Pomocná rekurzivní metoda pro seřazení záznamů do stromové posloupnosti.
	 *
	 * @param string                           $parent_key   UUID rodiče ('' pro kořeny)
	 * @param int                              $level        Úroveň zanoření (0, 1, 2...)
	 * @param array<string, array<int, array>> $children_map Mapa potomků podle parent_uuid
	 * @param array<int, array<string, mixed>> $flat_out     Výstupní seřazené pole se sloupcem _tree_level
	 * @param array<string, bool>              $visited      Ochrana proti zacyklení
	 */
	protected function append_tree_children(string $parent_key, int $level, array &$children_map, array &$flat_out, array &$visited): void { // Rekurzivní stavba stromu
		if (!isset($children_map[$parent_key])) {                            // Pokud uzel nemá žádné potomky
			return;                                                          // Ukončení větve
		}

		$sort_col = $this->sort_column;                                      // Sloupec pro primární řazení sourozenců
		$code_col = $this->code_column;                                      // Sloupec pro sekundární řazení sourozenců

		usort($children_map[$parent_key], function(array $a, array $b) use ($sort_col, $code_col): int { // Řazení sourozenců
			$cmp = strnatcasecmp((string)($a[$sort_col] ?? ''), (string)($b[$sort_col] ?? '')); // Porovnání sort_code
			if ($cmp !== 0) {                                                // Pokud se sort_code liší
				return $cmp;                                                 // Vrácení výsledku porovnání sort_code
			}
			return strnatcasecmp((string)($a[$code_col] ?? $a['caption'] ?? ''), (string)($b[$code_col] ?? $b['caption'] ?? '')); // Sekundární řazení
		});

		foreach ($children_map[$parent_key] as $row) {                       // Průchod potomky daného rodiče
			$orig = strtolower((string)$row['original']);                    // Normalizované UUID položky
			if (isset($visited[$orig])) {                                    // Ochrana proti případnému cyklu v datech
				continue;                                                    // Přeskočení již navštíveného uzlu
			}
			$visited[$orig] = true;                                          // Označení uzlu jako navštíveného
			$row['_tree_level'] = $level;                                    // Uložení vypočtené úrovně zanoření
			$flat_out[] = $row;                                              // Přidání uzlu do výstupního seznamu
			$this->append_tree_children($orig, $level + 1, $children_map, $flat_out, $visited); // Rekurzivní průchod potomky
		}
	}

	/**
	 * Vykreslí levý panel (Master) se stromově odsazenou hierarchií,
	 * ovládáním pro sbalení/rozbalení větví (Collapse/Expand) a podporou Drag & Drop.
	 */
	protected function render_master(): void {
		if ($this->em === null) {                                            // Kontrola inicializace správce entit
			return;                                                          // Ukončení při chybějícím správci
		}

		$update_guid = (string)getinput('update_guid');                      // Aktuálně vybraná položka v detailu
		$show_removed = ((string)getinput('show_removed') === '1');          // Příznak zobrazení zrušených položek

		$order_sql = $this->sort_column . ' ASC';                            // Základní řazení podle sort_code
		if ($this->em->has_physical_column($this->code_column)) {            // Pokud má tabulka kódový sloupec
			$order_sql .= ', ' . $this->code_column . ' ASC';                // Sekundární řazení podle kódu
		}

		$rows = $this->em->fetch_rows($this->master_where, $order_sql, false, $show_removed); // Načtení položek s překlady

		// Pokud přišel neuložený náhled z Drag & Dropu, promítneme jej i do paměťového stromu vlevo
		if ($this->has_dnd_preview AND $this->can_edit_structure AND $update_guid !== '' AND is_array($rows)) { // Aplikace D&D náhledu
			$is_locked_act = $this->em->is_hierarchy_node_locked($update_guid); // Kontrola uzamčení přesouvaného uzlu
			foreach ($rows as &$r_ref) {                                     // Hledání přetaženého záznamu v poli
				if (strcasecmp((string)$r_ref['original'], $update_guid) === 0) { // Shoda s aktivním záznamem
					if (!$is_locked_act) {                                   // U neuzamčeného uzlu upravíme i rodiče
						$r_ref[$this->parent_column] = $this->dnd_parent;    // Nový nadřízený uzel pro zobrazení ve stromu
					}
					$r_ref[$this->sort_column] = $this->dnd_sort;            // Nové pořadí pro zobrazení ve stromu
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
				$orig_key = strtolower((string)$r['original']);              // Klíč aktuálního uzlu
				$par_raw = strtolower(trim((string)($r[$this->parent_column] ?? ''))); // Klíč rodiče malými písmeny
				$par_key = ($par_raw !== '' AND $par_raw !== $orig_key AND isset($all_by_orig[$par_raw])) ? $par_raw : ''; // Sirotky zařadíme do kořene
				$children_map[$par_key][] = $r;                              // Přidání do seznamu potomků rodiče
			}
		}

		$tree_rows = [];                                                     // Výsledné stromově seřazené pole řádků
		$visited = [];                                                       // Evidence navštívených uzlů
		$this->append_tree_children('', 0, $children_map, $tree_rows, $visited); // Sestavení stromu od kořenových položek

		// Pojistka pro případné zbylé uzly (např. při kruhové vazbě v datech)
		foreach ($all_by_orig as $orig_key => $r) {                          // Kontrola nenavštívených uzlů
			if (!isset($visited[$orig_key])) {                               // Pokud uzel nebyl zařazen
				$r['_tree_level'] = 0;                                       // Zařazení na úroveň 0
				$tree_rows[] = $r;                                           // Přidání na konec seznamu
			}
		}

		$class_meta = $this->em->get_class_meta();                           // Metadata aktuální logické třídy
		$default_heading = (string)($class_meta['caption_plural'] ?: $this->phrase('default_tree_heading', [], 'Strom záznamů')); // Výchozí nadpis
		$master_heading = htmlspecialchars($this->tree_heading !== '' ? $this->tree_heading : $default_heading); // Nadpis levého panelu
		$lbl_show_rem = htmlspecialchars($this->phrase('lbl_show_removed', [], 'Zobrazit i zrušené')); // Popisek přepínače zrušených
		$search_placeholder = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat ve stromu...')); // Placeholder hledání
		$chk_show_rem = $show_removed ? 'checked' : '';                      // Stav zaškrtnutí přepínače zrušených

		$lbl_expand_all    = htmlspecialchars($this->phrase('btn_expand_all', [], 'Rozbalit vše'));   // Tlačítko rozbalení větví
		$lbl_collapse_all  = htmlspecialchars($this->phrase('btn_collapse_all', [], 'Sbalit vše'));   // Tlačítko sbalení větví
		$tip_toggle_branch = htmlspecialchars($this->phrase('tip_toggle_branch', [], 'Sbalit / rozbalit podřízené položky')); // Tooltip větve
		$tip_drag_handle   = htmlspecialchars($this->phrase('tip_drag_handle', [], 'Přetažením myší (Drag & Drop) upravíte pořadí nebo nadřízenou složku v detailu')); // Tooltip D&D
		$tip_locked_node   = htmlspecialchars($this->phrase('tip_locked_node', [], 'Uzel má navázané záznamy – změna nadřízené složky je uzamčena (lze měnit pouze pořadí mezi sourozenci)')); // Tooltip zámku
		$tip_folder_node   = htmlspecialchars($this->phrase('tip_folder_node', [], 'Vnitřní složka hierarchie (is_leaf = 0)')); // Tooltip složky

		$th_caption = htmlspecialchars($this->tree_caption_header !== '' ? $this->tree_caption_header : $this->phrase('th_tree_caption', [], 'Název položky (Strom)')); // Záhlaví 1. sloupce
		$th_code    = htmlspecialchars($this->phrase('th_builtin_code', [], 'Kód'));   // Záhlaví sloupce kódu
		$th_sort    = htmlspecialchars($this->phrase('th_sort_code', [], 'Pořadí'));   // Záhlaví sloupce pořadí

		$has_code_col = $this->em->has_physical_column($this->code_column);  // Zda tabulka obsahuje kódový sloupec
		$has_leaf_col = $this->em->has_physical_column($this->leaf_column);  // Zda tabulka obsahuje sloupec is_leaf

		$badge_txt_d   = htmlspecialchars($this->phrase('badge_draft', [], 'Koncept'));         // Štítek konceptu
		$badge_txt_f   = htmlspecialchars($this->phrase('badge_forwarded', [], 'Ke schválení')); // Štítek postoupeného návrhu
		$badge_txt_r   = htmlspecialchars($this->phrase('badge_rejected', [], 'Vráceno'));      // Štítek vráceného návrhu
		$badge_txt_rem = htmlspecialchars($this->phrase('badge_removed', [], 'Zrušeno'));       // Štítek zrušeného záznamu

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
			.tree-folder-icon { font-size: 12px; margin-right: 4px; vertical-align: middle; }
			.tree-lock-icon { font-size: 11px; margin-left: 5px; vertical-align: middle; cursor: help; }
			tr.dnd-dragging { opacity: 0.45; }
			tr.dnd-drop-before td { border-top: 2px solid #2563eb !important; }
			tr.dnd-drop-after td { border-bottom: 2px solid #2563eb !important; }
			tr.dnd-drop-inside td { background-color: #dbeafe !important; outline: 1px dashed #2563eb; }
		</style>
		<div class="md-master-header">
HTML;

		$this->render_master_top();                                          // Vykreslení horních prvků a tlačítka + Nová položka

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
HTML;

		if ($has_code_col) {                                                 // Sloupec technického kódu
			echo "\t\t\t\t\t\t<th>{$th_code}</th>\n";                        // Záhlaví sloupce kódu
		}
		echo "\t\t\t\t\t\t<th style=\"width: 60px; text-align: center;\">{$th_sort}</th>\n"; // Záhlaví sloupce pořadí

		foreach ($this->tree_extra_columns as $ex_col => $ex_cfg) {          // Vykreslení záhlaví volitelných sloupců potomka
			$ex_hdr = htmlspecialchars((string)($ex_cfg['header'] ?? $ex_col)); // Text záhlaví
			$ex_w   = !empty($ex_cfg['width']) ? "width: {$ex_cfg['width']}; " : ""; // Šířka sloupce
			$ex_al  = !empty($ex_cfg['align']) ? "text-align: {$ex_cfg['align']};" : ""; // Zarovnání sloupce
			echo "\t\t\t\t\t\t<th style=\"{$ex_w}{$ex_al}\">{$ex_hdr}</th>\n"; // Buňka záhlaví
		}

		echo <<<HTML
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$page_param = urlencode($this->get_current_page_name());             // Kanonický název stránky do URL
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		foreach ($tree_rows as $row) {                                       // Vykreslení stromově seřazených řádků
			$uuid = (string)$row['original'];                                // Originální UUID položky
			$orig_low = strtolower($uuid);                                   // Normalizované UUID pro kontrolu potomků
			$par_raw = trim((string)($row[$this->parent_column] ?? ''));     // Původní UUID rodiče
			$par_low = strtolower($par_raw);                                 // Normalizované UUID rodiče
			$par_valid = ($par_low !== '' AND $par_low !== $orig_low AND isset($all_by_orig[$par_low])) ? $par_low : ''; // Platný rodič
			$b_code = (string)($row[$this->code_column] ?? $row['shortname'] ?? ''); // Technický kód nebo zkratka položky
			$has_children = !empty($children_map[$orig_low]);                // Zda má položka podřízené uzly
			$is_folder = $this->is_node_folder($row, $has_children);         // Zda funguje jako složka (může přijímat podpoložky)
			$is_prot_root = $this->is_protected_root_node($row);             // Zda jde o chráněný kořenový uzel
			$is_locked = $this->em->is_hierarchy_node_locked($uuid);         // Zda je uzel uzamčen platnými vazbami v link
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

			$can_drag_row = ($this->can_edit_structure AND !$is_prot_root);  // Chráněný kořen nelze přesouvat
			$drag_attr = $can_drag_row ? 'draggable="true"' : '';            // HTML5 atribut draggable
			$grip_html = $can_drag_row ? "<span class=\"dnd-grip\" title=\"{$tip_drag_handle}\">⋮⋮</span>" : ""; // Úchyt pro Drag & Drop

			$folder_icon_html = ($has_leaf_col AND $is_folder)
				? "<span class=\"tree-folder-icon\" title=\"{$tip_folder_node}\">📁</span>"
				: "";                                                        // Ikona složky u tabulek se sloupcem is_leaf
			$lock_icon_html = $is_locked
				? "<span class=\"tree-lock-icon\" title=\"{$tip_locked_node}\">🔒</span>"
				: "";                                                        // Ikona zámku u uzamčené větve hierarchie

			$cap_raw = (string)($row['caption'] ?: $b_code ?: $uuid);        // Zobrazovaný název položky
			$safe_cap = htmlspecialchars($cap_raw);                          // Ošetřený název položky
			$cap_html = ($is_folder OR $has_children) ? "<strong>{$safe_cap}</strong>" : $safe_cap; // Složky zvýrazníme tučně

			$safe_uuid = htmlspecialchars($uuid);                            // Ošetřené původní UUID
			$safe_par_uuid = htmlspecialchars($par_raw);                     // Ošetřené původní UUID rodiče
			$safe_code = htmlspecialchars($b_code);                          // Ošetřený technický kód
			$safe_sort = htmlspecialchars((string)($row[$this->sort_column] ?? '')); // Ošetřený řadicí kód
			$folder_flag = $is_folder ? '1' : '0';                           // Příznak složky pro Drag & Drop
			$prot_flag = $is_prot_root ? '1' : '0';                          // Příznak chráněného kořene pro Drag & Drop
			$lock_flag = $is_locked ? '1' : '0';                             // Příznak uzamčení změny rodiče

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
						data-prot-root="{$prot_flag}"
						data-locked="{$lock_flag}"
						data-row-url="{$row_url}"
						style="cursor: pointer;"
						onclick="if (window.loadDetailPanel) { window.loadDetailPanel('{$row_url}', this); } else { document.location='{$row_url}'; }">
						<td class="cell-tree-caption" style="padding-left: calc(6px + {$indent_px}px);">{$grip_html}{$toggle_html}{$folder_icon_html}<span class="tree-caption-text">{$cap_html}</span>{$lock_icon_html}{$ssc_badge}</td>
HTML;

			if ($has_code_col) {                                             // Buňka technického kódu
				echo "\t\t\t\t\t\t<td style=\"font-family: monospace; font-size: 12px; color: #475569;\">{$safe_code}</td>\n"; // Kód
			}
			echo "\t\t\t\t\t\t<td class=\"cell-tree-sort\" style=\"text-align: center; font-family: monospace; font-size: 12px;\">{$safe_sort}</td>\n"; // Pořadí

			foreach ($this->tree_extra_columns as $ex_col => $ex_cfg) {      // Vykreslení buněk volitelných sloupců
				$ex_val = htmlspecialchars((string)($row[$ex_col] ?? ''));   // Hodnota volitelného sloupce
				$ex_al  = !empty($ex_cfg['align']) ? "text-align: {$ex_cfg['align']}; " : ""; // Zarovnání
				$ex_fw  = !empty($ex_cfg['bold']) ? "font-weight: bold; " : ""; // Tučné písmo
				echo "\t\t\t\t\t\t<td style=\"{$ex_al}{$ex_fw}font-size: 11px;\">{$ex_val}</td>\n"; // Buňka
			}

			echo "\t\t\t\t\t</tr>\n";
		}

		$js_storage_key = addslashes($this->storage_key_prefix);             // Unikátní klíč v sessionStorage pro daný strom
		$js_base_url    = addslashes("index.php?page={$page_param}{$url_suffix}"); // Základní URL pro AJAX načtení detailu
		$js_curr_guid   = addslashes(strtolower($update_guid));              // Výchozí normalizované UUID právě otevřeného záznamu
		$js_can_dnd     = $this->can_edit_structure ? 'true' : 'false';      // Zda je povolen Drag & Drop
		$js_parent_col  = addslashes($this->parent_column);                  // Název sloupce rodiče ve formuláři
		$js_sort_col    = addslashes($this->sort_column);                    // Název sloupce pořadí ve formuláři

		echo <<<HTML
				</tbody>
			</table>
		</div>

		<script>
			(function() {
				const STORAGE_KEY = '{$js_storage_key}';
				const initialOpenOrig = '{$js_curr_guid}';
				const canDragDrop = {$js_can_dnd};
				const basePageUrl = '{$js_base_url}';
				const parentColName = '{$js_parent_col}';
				const sortColName = '{$js_sort_col}';

				// Dynamicky zjistí právě otevřenou položku v detailu (odolné vůči AJAX přepínání detailu)
				function getCurrentOpenOrig() {
					const inp = document.querySelector('.md-detail form input[name="update_guid"]');
					if (inp && inp.value && inp.value !== 'NEW') {
						return inp.value.toLowerCase();
					}
					const actRow = document.getElementById('active-row');
					if (actRow && actRow.dataset.orig) {
						return actRow.dataset.orig.toLowerCase();
					}
					return initialOpenOrig;
				}

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
					const openOrig = getCurrentOpenOrig();
					if (!openOrig) return;
					const rowsMap = {};
					document.querySelectorAll('#master-list tr[data-orig]').forEach(function(r) {
						rowsMap[r.dataset.orig] = r.dataset.parent ? r.dataset.parent : '';
					});
					let p = rowsMap[openOrig] ? rowsMap[openOrig] : '';
					let guard = 0;
					while (p !== '' && guard < 50) {
						collapsedSet.delete(p);
						p = rowsMap[p] ? rowsMap[p] : '';
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
						parentLookup[r.dataset.orig] = r.dataset.parent ? r.dataset.parent : '';
						const btn = r.querySelector('.tree-toggle-btn');
						if (btn) {
							btn.textContent = collapsedSet.has(r.dataset.orig) ? '▶' : '▼';
						}
					});

					allRows.forEach(function(r) {
						let p = r.dataset.parent ? r.dataset.parent : '';
						let hiddenByAncestor = false;
						let guard = 0;
						while (p !== '' && guard < 50) {
							if (collapsedSet.has(p)) {
								hiddenByAncestor = true;
								break;
							}
							p = parentLookup[p] ? parentLookup[p] : '';
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
							if (!row ? true : row.dataset.protRoot !== '1') {
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
							const p = r.dataset.parent ? r.dataset.parent : '';
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
					const cleanPrev = (prevCode ? prevCode : '').replace(/[^0-9]/g, '');
					const cleanNext = (nextCode ? nextCode : '').replace(/[^0-9]/g, '');

					// 1. Prázdná větev -> '010'
					if (cleanPrev === '' && cleanNext === '') {
						return '010';
					}

					// 2. Vložení na konec větve -> zaokrouhlení na další desítku ('010' -> '020')
					if (cleanNext === '') {
						const padLen = Math.max(cleanPrev.length, 3);
						const paddedPrev = cleanPrev.padEnd(padLen, '0');
						const prevNum = parseInt(paddedPrev, 10) ? parseInt(paddedPrev, 10) : 0;
						const nextTen = (Math.floor(prevNum / 10) + 1) * 10;
						return String(nextTen).padStart(padLen, '0');
					}

					// 3. Vložení před první položku nebo mezi dvě položky
					let len = Math.max(cleanPrev.length, cleanNext.length, 3);
					while (len <= 18) {
						const pStr = cleanPrev === '' ? ''.padEnd(len, '0') : cleanPrev.padEnd(len, '0');
						const nStr = cleanNext.padEnd(len, '0');
						const pNum = parseInt(pStr, 10) ? parseInt(pStr, 10) : 0;
						const nNum = parseInt(nStr, 10) ? parseInt(nStr, 10) : 0;

						if (nNum - pNum > 1) {
							const mid = Math.floor((pNum + nNum) / 2);
							let res = String(mid).padStart(len, '0');
							if (res.length > 3) {
								res = res.replace(/0+$/, '');
								if (res.length < 3) res = res.padEnd(3, '0');
							}
							if ((cleanPrev === '' ? true : res > prevCode) && res < nextCode) {
								return res;
							}
						}
						len++;
					}

					return (prevCode ? prevCode : '000') + '5';
				}

				// Určí zónu puštění myši nad cílovým řádkem ('before', 'after', 'inside' nebo null pokud zakázáno)
				function resolveDropMode(targetRow, clientY) {
					const rect = targetRow.getBoundingClientRect();
					const relY = clientY - rect.top;
					const height = rect.height ? rect.height : 30;
					const isFolder = (targetRow.dataset.isFolder === '1');
					const isProtRoot = (targetRow.dataset.protRoot === '1');
					const isDraggedLocked = (draggedRow && draggedRow.dataset.locked === '1');
					const dragParent = (draggedRow && draggedRow.dataset.parent) ? draggedRow.dataset.parent : '';
					const targetParent = targetRow.dataset.parent ? targetRow.dataset.parent : '';

					// Pokud je tažený uzel uzamčen vazbami, smí měnit pouze pořadí pod stejným rodičem
					if (isDraggedLocked) {
						if (isFolder && targetRow.dataset.orig === dragParent) {
							return 'inside';
						}
						if (targetParent !== dragParent || isProtRoot) {
							return null;
						}
						return (relY < height * 0.5) ? 'before' : 'after';
					}

					if (isProtRoot) {
						return isFolder ? 'inside' : 'after';
					}
					if (isFolder) {
						if (relY < height * 0.25) return 'before';
						if (relY > height * 0.75) return 'after';
						return 'inside';
					}
					return (relY < height * 0.5) ? 'before' : 'after';
				}

				// Přepočet pořadí a odsazení všech řádků v tabulce #master-list v DOMu
				function reorderTreeDom(movedRow, newParentOrig, newParentUuid, newSortCode) {
					movedRow.dataset.parent = newParentOrig;
					movedRow.dataset.parentUuid = newParentUuid;
					movedRow.dataset.sort = newSortCode;
					const sortCell = movedRow.querySelector('.cell-tree-sort');
					if (sortCell) {
						sortCell.textContent = newSortCode;
					}

					if (newParentOrig !== '') {
						const cSet = getCollapsedSet();
						if (cSet.has(newParentOrig)) {
							cSet.delete(newParentOrig);
							saveCollapsedSet(cSet);
						}
					}

					const allRows = Array.from(tbody.querySelectorAll('tr[data-orig]'));
					const byParent = {};
					allRows.forEach(function(r) {
						const p = r.dataset.parent ? r.dataset.parent : '';
						if (!byParent[p]) byParent[p] = [];
						byParent[p].push(r);
					});

					Object.keys(byParent).forEach(function(p) {
						byParent[p].sort(function(a, b) {
							const sa = a.dataset.sort ? a.dataset.sort : '';
							const sb = b.dataset.sort ? b.dataset.sort : '';
							if (sa !== sb) return sa.localeCompare(sb, undefined, { numeric: true, sensitivity: 'base' });
							return (a.dataset.code ? a.dataset.code : '').localeCompare(b.dataset.code ? b.dataset.code : '');
						});
					});

					const orderedRows = [];
					const visitedSet = new Set();
					function walkDomTree(pKey, lvl) {
						const list = byParent[pKey] ? byParent[pKey] : [];
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

					window.isTreeDomDirty = true;
					window.applyMenuTreeVisibility();
				}

				tbody.addEventListener('dragstart', function(e) {
					const tr = e.target.closest('tr[data-orig]');
					if (!tr ? true : tr.dataset.protRoot === '1') {
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
					if (!targetRow ? true : draggedDescendants.has(targetRow.dataset.orig)) {
						clearDropIndicators();
						return;
					}
					const mode = resolveDropMode(targetRow, e.clientY);
					if (!mode) {
						clearDropIndicators();
						return;
					}
					e.preventDefault();
					if (e.dataTransfer) {
						e.dataTransfer.dropEffect = 'move';
					}
					clearDropIndicators();
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
					if (!targetRow ? true : draggedDescendants.has(targetRow.dataset.orig)) {
						return;
					}
					const mode = resolveDropMode(targetRow, e.clientY);
					if (!mode) {
						return;
					}
					e.preventDefault();
					e.stopPropagation();

					const dragOrig = draggedRow.dataset.orig;
					const dragUuid = draggedRow.dataset.uuid;

					let newParentOrig = '';
					let newParentUuid = '';
					let prevSort = '';
					let nextSort = '';

					if (mode === 'inside') {
						newParentOrig = targetRow.dataset.orig;
						newParentUuid = targetRow.dataset.uuid;
						const existingChildren = Array.from(tbody.querySelectorAll('tr[data-orig]')).filter(function(r) {
							return (r.dataset.parent ? r.dataset.parent : '') === newParentOrig && r.dataset.orig !== dragOrig;
						});
						if (existingChildren.length > 0) {
							const lastChild = existingChildren[existingChildren.length - 1];
							prevSort = lastChild.dataset.sort ? lastChild.dataset.sort : '';
						}
					} else {
						newParentOrig = targetRow.dataset.parent ? targetRow.dataset.parent : '';
						newParentUuid = targetRow.dataset.parentUuid ? targetRow.dataset.parentUuid : '';
						const siblings = Array.from(tbody.querySelectorAll('tr[data-orig]')).filter(function(r) {
							return (r.dataset.parent ? r.dataset.parent : '') === newParentOrig && r.dataset.orig !== dragOrig;
						});
						const tIdx = siblings.indexOf(targetRow);
						if (mode === 'before') {
							prevSort = (tIdx > 0 && siblings[tIdx - 1].dataset.sort) ? siblings[tIdx - 1].dataset.sort : '';
							nextSort = targetRow.dataset.sort ? targetRow.dataset.sort : '';
						} else {
							prevSort = targetRow.dataset.sort ? targetRow.dataset.sort : '';
							nextSort = (tIdx >= 0 && tIdx + 1 < siblings.length && siblings[tIdx + 1].dataset.sort) ? siblings[tIdx + 1].dataset.sort : '';
						}
					}

					const newSortCode = computeBetweenSortCode(prevSort, nextSort);
					const activeOrig = getCurrentOpenOrig();

					// Aktualizujeme pořadí a odsazení v levém stromu ihned
					reorderTreeDom(draggedRow, newParentOrig, newParentUuid, newSortCode);

					// Pokud přetahujeme položku, která ještě není vpravo otevřená, načteme její detail přes AJAX s předvyplněnými poli
					if (dragOrig !== activeOrig) {
						const targetUrl = basePageUrl
							+ '&update_guid=' + encodeURIComponent(dragUuid)
							+ '&dnd_parent=' + encodeURIComponent(newParentUuid)
							+ '&dnd_sort=' + encodeURIComponent(newSortCode);
						if (window.loadDetailPanel) {
							window.loadDetailPanel(targetUrl, draggedRow);
						} else {
							window.location.href = targetUrl;
						}
						return;
					}

					// Položka je již otevřená v pravém panelu -> přímo upravíme obě pole v DOM formuláře bez reloadu
					const parentSelect = document.querySelector('.md-detail form [name="' + parentColName + '"]');
					const sortInput = document.querySelector('.md-detail form [name="' + sortColName + '"]');

					if (parentSelect && !parentSelect.disabled && !parentSelect.readOnly) {
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

					if (sortInput && !sortInput.disabled && !sortInput.readOnly) {
						sortInput.value = newSortCode;
						sortInput.style.backgroundColor = '#dcfce7';
						sortInput.style.borderColor = '#16a34a';
					}

					const banner = document.getElementById('tree-dnd-banner');
					if (banner) {
						banner.style.display = 'block';
					}

					isFormDirty = true;
				});
			})();
		</script>
HTML;
	}
}