<?php
/**
 * =============================================================================
 * Verze: 2026-10-31 11:00
 * Soubor: page_hierarchy_item.php
 * Třída: page_hierarchy_item
 * Účel: Správa uzlů (vnitřních složek is_leaf = 0 i koncových listů is_leaf = 1)
 *       konkrétní sekundární hierarchie nebo stromu štítků (tabulka hierarchy_item).
 *       Funguje jako podřízená stránka registru hierarchií (page_hierarchy.php)
 *       i při přímém otevření z menu (s roletkou pro přepínání aktivní hierarchie).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_hierarchy_item`.
 * - Dědí ze znovupoužitelné stromové šablony `abstract_page_tree` (`abstract_page_tree.php`)
 *   a pracuje s logickou třídou `'hierarchy_item'`.
 * - Kontext vybrané hierarchie se předává v parametru `hierarchy` (UUID originálu
 *   z tabulky `hierarchy`), který je automaticky přenášen v `get_context_url_suffix()`
 *   a `get_context_hidden_inputs()`.
 * - Respektuje uzamčení uzlů hierarchie (`entity_manager::is_hierarchy_node_locked()`):
 *   uzel, na kterém nebo na jehož podřízených uzlech již existují platné vazby
 *   v tabulce `link`, je označen ikonou zámku 🔒 a nelze změnit jeho `parent_uuid`,
 *   odškrtnout `is_leaf = 1` ani jej smazat.
 *
 * Změny:
 * 2026-10-31 11:00 - Vytvoření první verze stránky pro správu uzlů sekundárních hierarchií.
 * =============================================================================
 */

declare(strict_types=1);

class page_hierarchy_item extends abstract_page_tree {

	private string $parent_hierarchy = '';                                   // UUID vybrané nadřazené definice hierarchie (hierarchy.original)
	private string $parent_hierarchy_name = '';                              // Zobrazovaný název vybrané hierarchie

	public function __construct() {
		parent::__construct();                                               // Inicializace frází, kontroly přístupu a D&D v předkovi

		$this->class_name = 'hierarchy_item';                                // Logická třída pro entity_manager
		$this->can_edit_structure = !$this->is_readonly;                     // Povolení úpravy stromu a D&D v editačním režimu
		$this->allow_insert = !$this->is_readonly;                           // Povolení vkládání nových uzlů
		$this->page_title = $this->phrase('page_title', [], 'Položky sekundární hierarchie'); // Výchozí titulek stránky
		$this->tree_heading = $this->phrase('master_heading', [], 'Strom položek hierarchie'); // Nadpis levého panelu
		$this->tree_caption_header = $this->phrase('th_item_caption', [], 'Uzel hierarchie (Strom)'); // Záhlaví sloupce stromu
		$this->new_button_code = 'btn_new_hierarchy_item';                   // Kód fráze tlačítka pro nový uzel
		$this->new_button_default_caption = '+ Nová položka hierarchie';     // Výchozí popisek tlačítka

		if ($this->access_denied) {                                          // Pokud předek zamítl přístup ke stránce
			return;                                                          // Neprovádíme dotazy do databáze
		}

		global $dbsession;                                                   // Globální kontext relace uživatele
		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace

		$this->parent_hierarchy = trim((string)getinput('hierarchy'));       // Načtení vybrané hierarchie z URL nebo POSTu

		// Pokud v požadavku nebyla předána konkrétní hierarchie, vybereme první dostupnou koncovou hierarchii (is_leaf = 1)
		if ($this->parent_hierarchy === '') {                                // Hledání výchozí koncové hierarchie
			$r_def = sqlfirstrow("
				SELECT TOP 1 original
				FROM hierarchy
				WHERE object_owner IN (0x00, {$org_sql})
				  AND record_type = 'A'
				  AND removed = 0
				  AND inactive = 0
				  AND is_leaf = 1
				ORDER BY CASE WHEN object_owner = {$org_sql} THEN 0 ELSE 1 END, sort_code, builtin_code
			");                                                              // Dotaz na první platnou hierarchii
			if (!empty($r_def)) {                                            // Pokud byla nalezena alespoň jedna hierarchie
				$this->parent_hierarchy = (string)$r_def['original'];        // Nastavení výchozí hierarchie
				$_GET['hierarchy'] = $this->parent_hierarchy;                // Zápis do $_GET pro přenos kontextu v odkazech
			}
		}

		if ($this->parent_hierarchy !== '' AND is_guid($this->parent_hierarchy)) { // Pokud máme platné UUID hierarchie
			$this->master_where = "m.hierarchy = " . guidliteral($this->parent_hierarchy); // Omezení levého stromu na vybranou hierarchii
			$this->storage_key_prefix = 'bcm_tree_hi_' . strtolower($this->parent_hierarchy); // Samostatný klíč v sessionStorage pro každou hierarchii

			$em_parent = new entity_manager('hierarchy');                    // Správce entit pro načtení nadřazené hierarchie
			$where_par = "m.original = " . guidliteral($this->parent_hierarchy); // Podmínka pro vyhledání hierarchie
			$par_row = $em_parent->fetch_row($where_par);                    // Načtení hierarchie s vyhodnocením překladů
			if (!empty($par_row)) {                                          // Pokud byla definice hierarchie nalezena
				$this->parent_hierarchy_name = (string)$par_row['caption'] !== '' ? (string)$par_row['caption'] : (string)$par_row['builtin_code']; // Název
				$this->page_title = $this->phrase('page_title_with_hier', ['hierarchy' => $this->parent_hierarchy_name], 'Položky hierarchie: {' . chr(36) . 'hierarchy}'); // Titulek
			}
		} else {
			$this->master_where = "1 = 0";                                   // Žádná koncová hierarchie zatím neexistuje -> prázdný seznam
			$this->allow_insert = false;                                     // Bez nadřazené hierarchie nelze zakládat uzly
		}

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_hier = $this->phrase('grp_tree_placement', [], 'Zařazení v hierarchii a stromová struktura'); // Sekce stromového zařazení
		$grp_vis  = $this->phrase('grp_visual_validity', [], 'Vizuální atributy a platnost'); // Sekce vzhledu a platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy uzlu
			$grp_hier => ['hierarchy', 'builtin_code', 'parent_uuid', 'sort_code', 'is_leaf', 'external_code'], // Stromové zařazení uzlu
			$grp_vis  => ['color_code', 'svg_icon', 'valid_from', 'valid_to', 'inactive'] // Barva, ikona a platnost
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s kódem vybraného uzlu hierarchie.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek uzlu
		$code = (string)($datarow['builtin_code'] ?? '');                    // Technický kód uzlu v hierarchii
		if ($code === '') {                                                  // Pokud zakládáme nový uzel
			return htmlspecialchars($this->phrase('header_new_item', [], 'Nová položka hierarchie')); // Nadpis pro nový uzel
		}
		$safe_code = htmlspecialchars($code);                                // Ošetřený kód uzlu
		$lbl = htmlspecialchars($this->phrase('header_edit_item', [], 'Položka hierarchie')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_code}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Vykreslí v horní části levého panelu návratové tlačítko do registru hierarchií (page_hierarchy),
	 * roletku pro rychlé přepnutí vybrané hierarchie a tlačítko pro založení nového uzlu.
	 */
	protected function render_master_top(): void {
		global $dbsession;                                                   // Globální kontext relace uživatele
		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace
		$lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka relace

		// 1. Návratové tlačítko do nadřízené stránky page_hierarchy (Registr hierarchií)
		$back_url = "index.php?page=page_hierarchy" . ($this->parent_hierarchy !== '' ? "&update_guid=" . urlencode($this->parent_hierarchy) : ""); // URL návratu
		$btn_back = new abstract_button(                                     // Tlačítko návratu přes abstract_button
			'btn_back_to_hierarchy',                                         // Kód fráze v meta_phrase
			'← Zpět na hierarchii: {' . chr(36) . 'parent}',                 // Výchozí český popisek s proměnnou
			'page_hierarchy_item',                                           // Zdrojová třída fráze
			'',                                                              // Bez ikony
			'btn-secondary'                                                  // Sekundární šedý styl tlačítka
		);
		$btn_back->set_href($back_url)                                       // Nastavení cílové URL adresy
			->set_vars(['parent' => $this->parent_hierarchy_name ?: 'Registr']) // Dosazení názvu hierarchie
			->set_style('width: 100%; justify-content: center;');            // Roztažení na šířku levého panelu

		echo "<div style=\"margin-bottom: 10px;\">" . $btn_back->render() . "</div>\n"; // Výpis návratového tlačítka

		// 2. Roletka <select> pro výběr aktivní koncové hierarchie (is_leaf = 1) s překlady přes @fl
		$hier_rows = sqlarray_simple("
			SET NOCOUNT ON;
			DECLARE @fl TABLE ([language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, fallback_order int NOT NULL);
			INSERT INTO @fl ([language], fallback_order) SELECT [language], fallback_order FROM dbo.f_language_list({$lang_sql}) WHERE fallback_order < 1000;

			SELECT h.original, h.builtin_code, COALESCE(tr.caption, h.caption, h.builtin_code) AS caption
			FROM (
				SELECT a.original, a.builtin_code, a.caption, a.sort_code,
					ROW_NUMBER() OVER (PARTITION BY a.original ORDER BY CASE WHEN a.object_owner = {$org_sql} THEN 0 ELSE 1 END) AS rn
				FROM hierarchy a
				WHERE a.object_owner IN (0x00, {$org_sql})
				  AND a.record_type = 'A'
				  AND a.removed = 0
				  AND a.inactive = 0
				  AND a.is_leaf = 1
			) h
			OUTER APPLY (
				SELECT TOP 1 l.caption
				FROM hierarchy l
				JOIN @fl fl ON fl.[language] = l.[language]
				WHERE l.original = h.original
				  AND l.record_type = 'L'
				  AND l.removed = 0
				  AND l.object_owner IN ({$org_sql}, 0x00)
				  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
				ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
			) tr
			WHERE h.rn = 1
			ORDER BY h.sort_code, h.builtin_code;
		");                                                                  // Načtení dostupných koncových hierarchií

		$options_html = '';                                                  // HTML položek roletky hierarchií
		if (is_array($hier_rows) AND !empty($hier_rows)) {                   // Pokud existují koncové hierarchie
			foreach ($hier_rows as $h_row) {                                 // Průchod hierarchiemi
				$h_uuid = (string)$h_row['original'];                        // UUID hierarchie
				$h_code = htmlspecialchars((string)$h_row['builtin_code']);  // Ošetřený kód hierarchie
				$h_cap  = htmlspecialchars((string)$h_row['caption']);       // Ošetřený přeložený název hierarchie
				$sel = (strcasecmp($h_uuid, $this->parent_hierarchy) === 0) ? 'selected' : ''; // Označení právě vybrané hierarchie
				$label = ($h_cap !== '' AND $h_cap !== $h_code) ? "{$h_cap} ({$h_code})" : $h_code; // Text volby v roletce
				$options_html .= "<option value=\"" . htmlspecialchars($h_uuid) . "\" {$sel}>{$label}</option>"; // Přidání volby
			}
		} else {
			$lbl_none = htmlspecialchars($this->phrase('opt_no_hierarchy_defined', [], '--- Nejprve založte koncovou hierarchii v registru ---')); // Prázdný stav
			$options_html = "<option value=\"\">{$lbl_none}</option>";       // Informace o chybějící hierarchii
		}

		$lbl_select_hier = htmlspecialchars($this->phrase('lbl_select_hierarchy', [], 'Zvolená hierarchie / sada štítků:')); // Popisek roletky

		echo <<<HTML
		<div style="margin-bottom: 10px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_select_hier}</label>
			<select onchange="if(this.value) document.location='index.php?page=page_hierarchy_item&hierarchy=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;

		// 3. Tlačítko "+ Nová položka hierarchie" z předka abstract_page_tree
		parent::render_master_top();                                         // Vykreslení tlačítka pro vložení nového uzlu
	}

	/**
	 * Předvyplní vazbu na aktuální hierarchii (`hierarchy`) u nového záznamu (`update_guid=NEW`),
	 * uzamkne roletku `hierarchy` proti nechtěnému přesunu do jiného stromu a zavolá předka.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený datový řádek detailu
		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor záznamu v detailu

		if ($update_guid === 'NEW' AND is_array($datarow)) {                 // Při zakládání nového uzlu hierarchie
			if ($this->parent_hierarchy !== '') {                            // Pokud máme vybranou nadřazenou hierarchii
				$datarow['hierarchy'] = $this->parent_hierarchy;             // Pevné předvyplnění příslušnosti k vybrané hierarchii
			}
			if (($datarow['is_leaf'] ?? '') === '') {                        // Výchozí stav koncového uzlu
				$datarow['is_leaf'] = '1';                                   // Nová položka je ve výchozím stavu koncovým listem (1)
			}
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot, předvyplnění rodiče a výpis banneru

		// U nového záznamu uzamkneme v DOMu pole `hierarchy` na vybranou hierarchii (u existujícího záznamu jej již zamyká meta_original_keys)
		if ($update_guid === 'NEW' AND $this->parent_hierarchy !== '') {     // Pojistka uzamčení roletky hierarchy u nového uzlu
			echo <<<HTML
			<script>
				setTimeout(function() {
					const hSel = document.querySelector('.md-detail form select[name="hierarchy"]');
					if (hSel && hSel.value !== '') {
						const hid = document.createElement('input');
						hid.type = 'hidden';
						hid.name = 'hierarchy';
						hid.value = hSel.value;
						hSel.parentNode.insertBefore(hid, hSel);
						hSel.disabled = true;
						hSel.style.backgroundColor = '#f4f4f4';
					}
				}, 20);
			</script>
HTML;
		}
	}
}