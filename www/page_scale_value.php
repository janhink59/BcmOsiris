<?php
/**
 * =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: page_scale_value.php
 * Třída: page_scale_value
 * Účel: Správa jednotlivých stupňů hodnotících škál CRMM (tabulka scale_value)
 *       v procentuálním intervalu 0 až 100 %.
 *       Tabulka nemá sort_code – stupně jsou vždy tříděny vzestupně podle
 *       dolní prahové hodnoty threshold_value ASC a kontroluje se přísná
 *       monotonie prahů i skóre.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_scale_value`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'scale_value'`.
 * - V levém panelu nabízí návratové tlačítko do nadřazené stránky `page_scale`
 *   a roletku pro rychlé přepnutí vybrané hodnotící škály.
 * =============================================================================
 */

declare(strict_types=1);

class page_scale_value extends abstract_page_master_detail {

	private string $parent_scale = '';                                       // UUID vybrané nadřazené škály (scale.original)
	private string $parent_scale_name = '';                                  // Zobrazovaný název vybrané škály
	private ?entity_manager $em_scale = null;                                // Správce entit pro nadřazenou třídu scale

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'scale_value';                                   // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení vkládání nových stupňů škály
		$this->page_title = $this->phrase('page_title', [], 'Stupně hodnotících škál (CRMM)'); // Výchozí titulek stránky

		if ($this->access_denied) {                                          // Pokud předek zamítl přístup ke stránce
			return;                                                          // Neprovádíme dotazy do databáze
		}

		$this->em_scale = new entity_manager('scale');                       // Inicializace správce pro nadřazenou třídu scale
		$this->parent_scale = trim((string) getinput('scale'));              // Načtení vybrané škály z URL nebo POSTu

		// Pokud v požadavku nebyla předána konkrétní škála, vybereme první dostupnou aktivní škálu
		if ($this->parent_scale === '') {                                    // Hledání výchozí hodnotící škály
			$scales = $this->em_scale->fetch_rows('m.inactive = 0', 'scale_type ASC, priority ASC, sort_code ASC, builtin_code ASC', true); // Načtení škál
			if (! empty($scales)) {                                          // Pokud byla nalezena alespoň jedna škála
				$this->parent_scale = (string) $scales[0]['original'];       // Nastavení výchozí škály
				$_GET['scale'] = $this->parent_scale;                        // Zápis do $_GET pro přenos kontextu
			}
		}

		if ($this->parent_scale !== '' AND is_guid($this->parent_scale)) {   // Pokud máme platné UUID škály
			$this->master_where = "m.scale = " . guidliteral($this->parent_scale); // Omezení levého seznamu na vybranou škálu

			$where_par = "m.original = " . guidliteral($this->parent_scale); // Podmínka pro vyhledání škály
			$par_row = $this->em_scale->fetch_row($where_par);               // Načtení škály s vyhodnocením překladů
			if (! empty($par_row)) {                                         // Pokud byla definice škály nalezena
				$this->parent_scale_name = (string) $par_row['caption'] !== '' ? (string) $par_row['caption'] : (string) $par_row['builtin_code']; // Název
				$this->page_title = $this->phrase('page_title_with_scale', ['scale' => $this->parent_scale_name], 'Stupně škály: {' . chr(36) . 'scale}'); // Titulek
			}
		} else {
			$this->master_where = "1 = 0";                                   // Žádná škála zatím neexistuje -> prázdný seznam
			$this->allow_insert = false;                                     // Bez nadřazené škály nelze zakládat stupně
		}

		if ($this->em === null) {                                            // Inicializace entity_manageru pro nastavení sloupců seznamu
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance správce entit
		}
		// Prvním sloupcem v list_columns je threshold_value, takže fetch_rows() řadí stupně vzestupně podle prahu!
		$this->em->set_list_columns([                                        // Sloupce v levém Master panelu
			'threshold_value' => $this->phrase('th_threshold_pct', [], 'Práh (%)'),
			'score_value'     => $this->phrase('th_score_pct', [], 'Skóre (%)'),
			'shortname'       => $this->phrase('th_shortname', [], 'Zkratka'),
			'caption'         => $this->phrase('th_level_caption', [], 'Název stupně')
		]);                                                                  // Konec definice sloupců Master panelu

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a metodický popis stupně'); // Sekce textů
		$grp_calc = $this->phrase('grp_thresholds_scores', [], 'Zařazení do škály, prahová hodnota a skóre (0 až 100 %)'); // Sekce výpočtů
		$grp_vis  = $this->phrase('grp_visual_validity', [], 'Vizuální atributy (semafor), platnost a ochrana'); // Sekce vzhledu

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy stupně
			$grp_calc => ['scale', 'builtin_code', 'threshold_value', 'score_value', 'is_default', 'external_code'], // Práh a skóre v %
			$grp_vis  => ['color_code', 'svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Barva a platnost
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Rozšíří kontextový přívažek URL o parametr `scale`.
	 */
	protected function get_context_url_suffix(): string {
		$suffix = parent::get_context_url_suffix();                          // Základní kontextové parametry z předka
		if ($this->parent_scale !== '' AND ! str_contains($suffix, '&scale=')) { // Připojení parametru scale
			$suffix .= '&scale=' . urlencode($this->parent_scale);           // Přidání vybrané škály do URL
		}
		return $suffix;                                                      // Vrácení přívažku URL
	}

	/**
	 * Rozšíří skrytá pole formuláře o parametr `scale`.
	 */
	protected function get_context_hidden_inputs(): string {
		$inputs = parent::get_context_hidden_inputs();                       // Základní skrytá pole z předka
		if ($this->parent_scale !== '') {                                    // Připojení skrytého pole pro zachování kontextu škály
			$inputs .= "\n\t\t\t<input type=\"hidden\" name=\"scale_ctx\" value=\"" . htmlspecialchars($this->parent_scale) . "\">"; // Skryté pole
		}
		return $inputs;                                                      // Vrácení skrytých polí
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s kódem a názvem vybraného stupně škály.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek stupně
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme nový stupeň škály
			return htmlspecialchars($this->phrase('header_new_scale_value', [], 'Nový stupeň škály')); // Nadpis pro nový stupeň
		}
		$title_val = (string) ($datarow['caption'] ?: $datarow['builtin_code'] ?: ''); // Název nebo kód stupně
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený text nadpisu
		$lbl = htmlspecialchars($this->phrase('header_edit_scale_value', [], 'Stupeň škály')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Vykreslí v horní části levého panelu návratové tlačítko do seznamu škál (`page_scale`),
	 * roletku pro rychlé přepnutí vybrané škály a tlačítko pro založení nového stupně.
	 */
	protected function render_master_top(): void {
		// 1. Návratové tlačítko do nadřízené stránky page_scale (Hodnotící škály)
		$back_url = "index.php?page=page_scale" . ($this->parent_scale !== '' ? "&update_guid=" . urlencode($this->parent_scale) : ""); // URL návratu
		$btn_back = new abstract_button(                                     // Tlačítko návratu přes abstract_button
			'btn_back_to_scale',                                             // Kód fráze v meta_phrase
			'← Zpět na škálu: {' . chr(36) . 'parent}',                      // Výchozí český popisek s proměnnou
			'page_scale_value',                                              // Zdrojová třída fráze
			'',                                                              // Bez ikony
			'btn-secondary'                                                  // Sekundární šedý styl tlačítka
		);
		$btn_back->set_href($back_url)                                       // Nastavení cílové URL adresy
			->set_vars(['parent' => $this->parent_scale_name ?: 'Škály'])    // Dosazení názvu škály
			->set_style('width: 100%; justify-content: center;');            // Roztažení na šířku levého panelu

		echo "<div style=\"margin-bottom: 10px;\">" . $btn_back->render() . "</div>\n"; // Výpis návratového tlačítka

		// 2. Roletka <select> pro výběr aktivní hodnotící škály načtená přes entity_manager
		$scale_rows = ($this->em_scale !== null)
			? $this->em_scale->fetch_rows('m.inactive = 0', 'scale_type ASC, priority ASC, sort_code ASC, builtin_code ASC', true)
			: [];                                                            // Načtení hodnotících škál s překlady

		$options_html = '';                                                  // HTML položek roletky škál
		if (is_array($scale_rows) AND ! empty($scale_rows)) {                // Pokud existují hodnotící škály
			foreach ($scale_rows as $s_row) {                                // Průchod škálami
				$s_uuid = (string) $s_row['original'];                       // UUID škály
				$s_code = htmlspecialchars((string) $s_row['builtin_code']); // Ošetřený kód škály
				$s_cap  = htmlspecialchars((string) $s_row['caption']);      // Ošetřený přeložený název škály
				$s_type = htmlspecialchars((string) $s_row['scale_type']);   // Druh veličiny
				$sel = (strcasecmp($s_uuid, $this->parent_scale) === 0) ? 'selected' : ''; // Označení právě vybrané škály
				$label = ($s_cap !== '' ? "{$s_cap} [{$s_type}]" : "{$s_code} [{$s_type}]"); // Text volby v roletce
				$options_html .= "<option value=\"" . htmlspecialchars($s_uuid) . "\" {$sel}>{$label}</option>"; // Přidání volby
			}
		} else {
			$lbl_none = htmlspecialchars($this->phrase('opt_no_scale_defined', [], '--- Nejprve založte hodnotící škálu ---')); // Prázdný stav
			$options_html = "<option value=\"\">{$lbl_none}</option>";       // Informace o chybějící škále
		}

		$lbl_select_scale = htmlspecialchars($this->phrase('lbl_select_scale', [], 'Zvolená hodnotící škála:')); // Popisek roletky

		echo <<<HTML
		<div style="margin-bottom: 10px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_select_scale}</label>
			<select onchange="if(this.value) document.location='index.php?page=page_scale_value&scale=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;

		// 3. Tlačítko "+ Nový stupeň škály"
		if ($this->allow_insert) {                                           // Pokud je vkládání povoleno
			$url_suffix = $this->get_context_url_suffix();                   // Přívažek URL se škálou
			$new_url = "index.php?page=page_scale_value{$url_suffix}&update_guid=NEW"; // Cílová URL pro nový stupeň
			$btn_new = new abstract_button('btn_new_scale_value', '+ Nový stupeň škály', 'page_scale_value'); // Tlačítko
			$btn_new->set_href($new_url)                                     // Nastavení odkazu
				->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
				->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Stylování tlačítka
			echo $btn_new->render();                                         // Vykreslení tlačítka
		}
	}

	/**
	 * Předvyplní vazbu na vybranou škálu (`scale`) u nového záznamu (`update_guid === 'NEW'`)
	 * a vypíše metodickou nápovědu k prahovým hodnotám a skóre.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený datový řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu

		if ($update_guid === 'NEW' AND is_array($datarow) AND $this->parent_scale !== '') { // Při zakládání nového stupně
			$datarow['scale'] = $this->parent_scale;                         // Pevné předvyplnění příslušnosti k vybrané škále
		}

		$note = htmlspecialchars($this->phrase('msg_scale_value_monotonic_hint', [], 'Pravidlo škály: Stupně jsou vždy seřazeny vzestupně podle dolní prahové hodnoty (threshold_value v %). Nejnižší stupeň musí začínat na 0 % a hodnoty prahů i skóre (0 až 100 %) musí tvořit monotónně rostoucí řadu.')); // Nápověda
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy
	}
}