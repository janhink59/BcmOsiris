<?php
/**
 * =============================================================================
 * Verze: 2026-11-11 22:00
 * Soubor: page_link.php
 * Třída: page_link
 * Účel: Správa provozních, katalogových a prostorových vazeb M:N v tabulce link
 *       (včetně zobrazení vazeb automaticky odvozených děděním po hierarchii,
 *       ze sloupce parent_uuid nebo ze schémat heterogenních sítí s příznakem
 *       is_derived = 1).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_link`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'link'`.
 * - Podle zvoleného typu vazby `link_def` dynamicky naplní roletky `from_object`
 *   a `to_object` záznamy odpovídajících logických tříd (`from_class` a `to_class`).
 * =============================================================================
 */

declare(strict_types=1);

class page_link extends abstract_page_master_detail {

	private string $filter_link_def = '';                                    // Filtr na vybraný typ vazby (meta_link_def.original)
	private string $filter_from_object = '';                                 // Filtr na konkrétní objekt (asset/threat/scenario...)
	private string $filter_diagram_uuid = '';                                // Filtr na schéma heterogenní sítě (link_diagram.original)
	private string $from_object_caption = '';                                // Zobrazovaný název filtrovaného objektu
	private string $diagram_caption = '';                                    // Zobrazovaný název filtrovaného diagramu sítě

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'link';                                          // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových vazeb
		$this->page_title = $this->phrase('page_title', [], 'Vazby a závislosti aktiv (CRMM)'); // Titulek stránky

		if ($this->access_denied) {                                          // Pokud předek zamítl přístup
			return;                                                          // Ukončení inicializace
		}

		$this->filter_link_def = trim((string) getinput('link_def_filter')); // Načtení filtru typu vazby z URL
		$this->filter_from_object = trim((string) getinput('from_object'));  // Načtení filtru objektu z URL
		$this->filter_diagram_uuid = trim((string) getinput('diagram_uuid')); // Načtení filtru diagramu z URL

		$where_parts = [];                                                   // Skládání podmínky master_where
		if ($this->filter_link_def !== '' AND is_guid($this->filter_link_def)) { // Filtr na typ vazby
			$where_parts[] = "m.link_def = " . guidliteral($this->filter_link_def); // Podmínka na link_def
		}
		if ($this->filter_from_object !== '' AND is_guid($this->filter_from_object)) { // Filtr na zdrojový nebo cílový objekt
			$obj_lit = guidliteral($this->filter_from_object);               // SQL literál objektu
			$where_parts[] = "(m.from_object = {$obj_lit} OR m.to_object = {$obj_lit})"; // Všechny vazby daného objektu
			$a_row = sqlfirstrow("SELECT TOP 1 caption, builtin_code FROM asset WHERE original = {$obj_lit} AND record_type = 'A' AND removed = 0"); // Název aktiva
			if (! empty($a_row)) {                                           // Pokud aktivum existuje
				$this->from_object_caption = (string) ($a_row['caption'] ?: $a_row['builtin_code']); // Uložení názvu aktiva
			}
		}
		if ($this->filter_diagram_uuid !== '' AND is_guid($this->filter_diagram_uuid)) { // Filtr na schéma heterogenní sítě
			$dg_lit = guidliteral($this->filter_diagram_uuid);               // SQL literál diagramu
			$where_parts[] = "(m.diagram_uuid = {$dg_lit} OR m.from_object = {$dg_lit})"; // Přímé spojnice i odvozené vazby diagramu
			$d_row = sqlfirstrow("SELECT TOP 1 caption, builtin_code FROM link_diagram WHERE original = {$dg_lit} AND record_type = 'A' AND removed = 0"); // Název diagramu
			if (! empty($d_row)) {                                           // Pokud diagram existuje
				$this->diagram_caption = (string) ($d_row['caption'] ?: $d_row['builtin_code']); // Uložení názvu diagramu
			}
		}

		if (! empty($where_parts)) {                                         // Sestavení výsledné podmínky pro levý panel
			$this->master_where = implode(' AND ', $where_parts);            // Spojení podmínek přes AND
		}

		$grp_rel  = $this->phrase('grp_link_endpoints', [], 'Typ vazby, zdrojový a cílový objekt'); // Sekce koncových bodů vazby
		$grp_meta = $this->phrase('grp_weight_note', [], 'Váha přenosu rizika, původ, poznámka a platnost'); // Sekce váhy a poznámky

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_rel  => ['link_def', 'from_object', 'to_object'],           // Klíčové složky vazby
			$grp_meta => ['link_weight', 'reverse_link_weight', 'diagram_uuid', 'note', 'valid_from', 'valid_to', 'inactive'] // Váha, diagram, poznámka a platnost
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Rozšíří kontextový přívažek URL o parametry `link_def_filter`, `from_object` a `diagram_uuid`.
	 */
	protected function get_context_url_suffix(): string {
		$suffix = parent::get_context_url_suffix();                          // Základní kontextové parametry z předka
		if ($this->filter_link_def !== '' AND ! str_contains($suffix, '&link_def_filter=')) { // Zachování filtru typu vazby
			$suffix .= '&link_def_filter=' . urlencode($this->filter_link_def); // Připojení link_def_filter
		}
		if ($this->filter_from_object !== '' AND ! str_contains($suffix, '&from_object=')) { // Zachování filtru objektu
			$suffix .= '&from_object=' . urlencode($this->filter_from_object); // Připojení from_object
		}
		if ($this->filter_diagram_uuid !== '' AND ! str_contains($suffix, '&diagram_uuid=')) { // Zachování filtru diagramu
			$suffix .= '&diagram_uuid=' . urlencode($this->filter_diagram_uuid); // Připojení diagram_uuid
		}
		return $suffix;                                                      // Vrácení přívažku URL
	}

	/**
	 * Načte mapu čitelných názvů všech odkazovaných objektů a definic vazeb pro zobrazení v levém panelu.
	 *
	 * @return array{defs: array<string, string>, objs: array<string, string>}
	 */
	private function load_lookup_captions(): array {
		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace
		$defs = [];                                                          // Mapa [link_def_orig => caption_forward]
		$objs = [];                                                          // Mapa [object_orig => caption]

		$def_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'ref_class', @param_code = 'link_def', @ref_class_uuid = " . guidliteral((string) ($this->em ? ($this->em->get_column_meta('link_def')['referenced_class'] ?? '') : ''))); // Definice vazeb
		if (is_array($def_rows)) {                                           // Naplnění mapy definic vazeb
			foreach ($def_rows as $dr) {                                     // Průchod definicemi
				$defs[strtolower((string) $dr['original'])] = (string) ($dr['caption'] ?: $dr['code_col']); // Název vazby
			}
		}

		$obj_rows = sqlarray_simple("
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM asset WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM asset_class WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM threat WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM impact WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM scenario WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM countermeasure WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM hierarchy_item WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), shortname) AS cap FROM organization_unit WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption, ''), builtin_code) AS cap FROM link_diagram WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
			UNION ALL
			SELECT original, COALESCE(NULLIF(caption_forward, ''), link_code) AS cap FROM meta_link_def WHERE object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0
		");                                                                  // Jednorázové načtení názvů propojovaných objektů
		if (is_array($obj_rows)) {                                           // Naplnění mapy objektů
			foreach ($obj_rows as $or) {                                     // Průchod objekty
				$objs[strtolower((string) $or['original'])] = (string) $or['cap']; // Uložení názvu pod klíčem original
			}
		}

		return ['defs' => $defs, 'objs' => $objs];                           // Vrácení vyhledávacích map
	}

	/**
	 * Vykreslí horní ovládací prvky levého panelu (návrat na aktivum nebo diagram, filtr typu vazby a tlačítko + Nová vazba).
	 */
	protected function render_master_top(): void {
		if ($this->filter_diagram_uuid !== '') {                             // Návratové tlačítko při příchodu z page_link_diagram
			$back_dg_url = "index.php?page=page_link_diagram&update_guid=" . urlencode($this->filter_diagram_uuid); // URL diagramu
			$btn_back_dg = new abstract_button('btn_back_to_diagram', '← Zpět na schéma sítě: {' . chr(36) . 'diagram}', 'page_link', '', 'btn-secondary'); // Tlačítko
			$btn_back_dg->set_href($back_dg_url)                             // Nastavení cílové URL
				->set_vars(['diagram' => $this->diagram_caption ?: $this->filter_diagram_uuid]) // Název diagramu
				->set_style('width: 100%; justify-content: center; margin-bottom: 8px;'); // Stylování
			echo $btn_back_dg->render();                                     // Vykreslení návratového tlačítka
		}

		if ($this->filter_from_object !== '') {                              // Návratové tlačítko při příchodu z page_asset
			$back_url = "index.php?page=page_asset&update_guid=" . urlencode($this->filter_from_object); // URL aktiva
			$btn_back = new abstract_button('btn_back_to_asset', '← Zpět na aktivum: {' . chr(36) . 'asset}', 'page_link', '', 'btn-secondary'); // Tlačítko
			$btn_back->set_href($back_url)                                   // Nastavení cílové URL
				->set_vars(['asset' => $this->from_object_caption ?: $this->filter_from_object]) // Název aktiva
				->set_style('width: 100%; justify-content: center; margin-bottom: 8px;'); // Stylování
			echo $btn_back->render();                                         // Vykreslení návratového tlačítka
		}

		if ($this->allow_insert) {                                           // Tlačítko pro založení nové vazby
			$url_suffix = $this->get_context_url_suffix();                   // Přívažek URL s kontextem
			$new_url = "index.php?page=page_link{$url_suffix}&update_guid=NEW"; // URL nové vazby
			$btn_new = new abstract_button('btn_new_link', '+ Nová vazba objektů', 'page_link'); // Tlačítko
			$btn_new->set_href($new_url)                                     // Nastavení cílové URL
				->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
				->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Stylování
			echo $btn_new->render();                                         // Vykreslení tlačítka
		}

		$lbl_all = htmlspecialchars($this->phrase('opt_all_link_defs', [], '--- Všechny typy vazeb ---')); // Volba všech typů vazeb
		$options_html = "<option value=\"\">{$lbl_all}</option>";            // První položka roletky
		$ld_meta = ($this->em !== null) ? $this->em->get_column_meta('link_def') : []; // Metadata sloupce link_def
		$ref_cls = guidliteral((string) ($ld_meta['referenced_class'] ?? '')); // UUID třídy meta_link_def
		if ($ref_cls !== 'NULL') {                                           // Načtení typů vazeb přes p_em_get_select_options
			$ld_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'ref_class', @param_code = 'link_def', @ref_class_uuid = {$ref_cls}"); // Dotaz
			if (is_array($ld_rows)) {                                        // Průchod typy vazeb
				foreach ($ld_rows as $lr) {                                  // Zpracování typu vazby
					$u = (string) $lr['original'];                           // UUID typu vazby
					$c = (string) $lr['code_col'];                           // Kód typu vazby
					$cp = (string) $lr['caption'];                           // Název typu vazby
					$sel = (strcasecmp($u, $this->filter_link_def) === 0) ? 'selected' : ''; // Označení vybraného typu
					$lbl = ($cp !== '' AND $cp !== $c) ? "{$cp} ({$c})" : $c; // Popisek volby
					$options_html .= '<option value="' . htmlspecialchars($u) . '" ' . $sel . '>' . htmlspecialchars($lbl) . '</option>'; // Volba
				}
			}
		}

		$lbl_flt = htmlspecialchars($this->phrase('lbl_filter_link_def', [], 'Typ vazby (link_def):')); // Popisek roletky
		$from_part = ($this->filter_from_object !== '') ? ('&from_object=' . urlencode($this->filter_from_object)) : ''; // Zachování from_object
		$diag_part = ($this->filter_diagram_uuid !== '') ? ('&diagram_uuid=' . urlencode($this->filter_diagram_uuid)) : ''; // Zachování diagram_uuid

		echo <<<HTML
		<div style="margin-bottom: 10px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_flt}</label>
			<select onchange="document.location='index.php?page=page_link{$from_part}{$diag_part}&link_def_filter=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;
	}

	/**
	 * Vykreslí levý panel se seznamem vazeb a přeloženými názvy zdrojových a cílových objektů.
	 */
	protected function render_master(): void {
		if ($this->em === null) {                                            // Kontrola inicializace správce entit
			return;                                                          // Ukončení
		}

		$this->init_filter_manager();                                        // Inicializace správce filtrů
		$update_guid = (string) getinput('update_guid');                     // Aktuálně vybraná vazba
		$show_removed = ((string) getinput('show_removed') === '1');         // Příznak zobrazení zrušených vazeb
		$chk_show_rem = $show_removed ? 'checked' : '';                      // Stav zaškrtnutí

		$heading = htmlspecialchars($this->phrase('master_heading', [], 'Seznam vazeb a závislostí')); // Nadpis seznamu
		$lbl_show_rem = htmlspecialchars($this->phrase('lbl_show_removed', [], 'Zobrazit i zrušené')); // Popisek zrušených
		$search_ph = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat ve vazbách...')); // Placeholder hledání

		$th_def  = htmlspecialchars($this->phrase('th_link_def', [], 'Typ vazby'));      // Záhlaví typu vazby
		$th_from = htmlspecialchars($this->phrase('th_from_object', [], 'Zdroj (Odkud)')); // Záhlaví zdroje
		$th_to   = htmlspecialchars($this->phrase('th_to_object', [], 'Cíl (Kam)'));       // Záhlaví cíle
		$badge_der = htmlspecialchars($this->phrase('badge_derived', [], 'Zděděno'));      // Štítek zděděné vazby

		echo "<div class=\"md-master-header\">\n";
		$this->render_master_top();                                          // Horní ovládací prvky a filtr typu vazby
		echo <<<HTML
			<div style="display: flex; justify-content: space-between; align-items: center; margin: 0 0 10px 0;">
				<h2 style="font-size: 16px; margin: 0; border: none; padding: 0;">{$heading}</h2>
				<label style="font-size: 12px; color: #555; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; user-select: none;">
					<input type="checkbox" {$chk_show_rem} onchange="toggleShowRemoved(this.checked);"> {$lbl_show_rem}
				</label>
			</div>
HTML;
		$this->render_master_filter_controls($search_ph);                    // Rychlý a modální filtr + CSV
		echo <<<HTML
		</div>
		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
						<th>{$th_def}</th>
						<th>{$th_from}</th>
						<th>{$th_to}</th>
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$lookups = $this->load_lookup_captions();                            // Načtení čitelných názvů typů vazeb a objektů
		$raw_rows = $this->em->fetch_rows($this->master_where, 'is_derived ASC, date_modified DESC', false, $show_removed); // Načtení vazeb
		$rows = $this->apply_active_filters_to_rows($raw_rows);              // Aplikace rozšířeného filtru
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		if (is_array($rows)) {                                               // Průchod načtenými vazbami
			foreach ($rows as $row) {                                        // Zpracování řádku vazby
				$uuid = (string) $row['original'];                           // Originální UUID vazby
				$safe_uuid = htmlspecialchars($uuid);                        // Ošetřené UUID
				$is_act = (strcasecmp($uuid, $update_guid) === 0);           // Zda je řádek vybrán
				$is_rem = ! empty($row['removed']);                          // Zda je vazba v koši
				$is_der = ! empty($row['is_derived']);                       // Zda jde o zděděnou vazbu
				$rowClass = $is_act ? 'md-row-active' : ($is_rem ? 'md-row-removed' : ($is_der ? 'md-row-inactive' : '')); // Třída
				$rowIdAttr = $is_act ? 'id="active-row"' : '';               // ID aktivního řádku

				$ld_key = strtolower((string) ($row['link_def'] ?? ''));     // Klíč typu vazby
				$fr_key = strtolower((string) ($row['from_object'] ?? ''));  // Klíč zdrojového objektu
				$to_key = strtolower((string) ($row['to_object'] ?? ''));    // Klíč cílového objektu

				$ld_cap = htmlspecialchars($lookups['defs'][$ld_key] ?? (string) $row['link_def']); // Název typu vazby
				$fr_cap = htmlspecialchars($lookups['objs'][$fr_key] ?? (string) $row['from_object']); // Název zdroje
				$to_cap = htmlspecialchars($lookups['objs'][$to_key] ?? (string) $row['to_object']); // Název cíle
				$der_html = $is_der ? "<span class=\"ssc-badge ssc-badge-d\">{$badge_der}</span>" : ''; // Štítek Zděděno

				$row_url = htmlspecialchars("index.php?page=page_link{$url_suffix}&update_guid=" . urlencode($uuid)); // URL detailu
				echo "<tr class=\"{$rowClass}\" {$rowIdAttr} data-uuid=\"{$safe_uuid}\" style=\"cursor: pointer;\" onclick=\"loadDetailPanel('{$row_url}', this);\">";
				echo "<td><strong>{$ld_cap}</strong>{$der_html}</td>";
				echo "<td>{$fr_cap}</td>";
				echo "<td>{$to_cap}</td>";
				echo "</tr>\n";
			}
		}

		echo "\t\t\t\t</tbody>\n\t\t\t</table>\n\t\t</div>\n";
	}

	/**
	 * Sestaví nadpis pravého detailního panelu.
	 */
	protected function get_detail_header(): string {
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Zakládání nové vazby
			return htmlspecialchars($this->phrase('header_new_link', [], 'Nová vazba mezi objekty')); // Nadpis nové vazby
		}
		return htmlspecialchars($this->phrase('header_edit_link', [], 'Detail vazby mezi objekty')); // Nadpis existující vazby
	}

	/**
	 * Předvyplní kontextové hodnoty u nové vazby, uzamkne zděděné vazby (`is_derived = 1`)
	 * a vloží JS obsluhu pro dynamické přepínání cílových tříd u `from_object` a `to_object` podle `link_def`.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nová vazba
			if ($this->filter_link_def !== '') {                             // Předvyplnění typu vazby z filtru
				$datarow['link_def'] = $this->filter_link_def;               // Nastavení link_def
			} elseif ($this->filter_diagram_uuid !== '') {                   // Při přidávání spojnice do diagramu předvyplníme diagram_includes_link_def
				$dg_def = sqlfirstrow("SELECT TOP 1 original FROM meta_link_def WHERE link_code = 'diagram_includes_link_def' AND record_type = 'A' AND removed = 0"); // Vztah diagramu
				if (! empty($dg_def['original'])) {                          // Pokud vztah v DB existuje
					$datarow['link_def'] = (string) $dg_def['original'];     // Nastavení link_def pro spojnici diagramu
				}
				$datarow['from_object'] = $this->filter_diagram_uuid;        // Předvyplnění diagramu jako zdroje
			}
			if ($this->filter_from_object !== '') {                          // Předvyplnění zdrojového objektu z filtru
				$datarow['from_object'] = $this->filter_from_object;         // Nastavení from_object
			}
		}

		if ($update_guid !== '' AND $update_guid !== 'NEW' AND ! empty($datarow['is_derived'])) { // Zděděná nebo stromová vazba
			$this->is_readonly = true;                                       // Uzamčení zděděné vazby v detailu
			$msg_der = htmlspecialchars($this->phrase('msg_derived_link_readonly', [], 'Tato vazba vznikla automatickým děděním po hierarchii, ze sloupce parent_uuid nebo projekcí ze schématu sítě (is_derived = 1). Zděděnou vazbu nelze ručně přepisovat; upravte ji na zdrojovém záznamu nebo diagramu.')); // Info
			echo "<div class=\"msg-info\" style=\"margin-bottom: 12px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e;\">{$msg_der}</div>\n"; // Žlutý pruh
		}

		// Načtení mapy definic vazeb [link_def_orig => [from_class, to_class]] a položek jednotlivých tříd
		$mld_rows = sqlarray_simple("
			SELECT original, from_class, to_class, link_weight_enabled
			FROM meta_link_def
			WHERE object_owner IN ({$org_sql}, 0x00)
			  AND record_type = 'A'
			  AND removed = 0
			  AND inactive = 0
		");                                                                  // Načtení definic typů vazeb
		$link_def_map = [];                                                  // Mapa definic vazeb pro JS
		$distinct_classes = [];                                              // Unikátní UUID odkazovaných tříd
		if (is_array($mld_rows)) {                                           // Zpracování definic vazeb
			foreach ($mld_rows as $mr) {                                     // Průchod definicemi
				$ld_orig = strtolower((string) $mr['original']);             // Klíč definice vazby
				$fc_orig = strtolower((string) $mr['from_class']);           // Klíč zdrojové třídy
				$tc_orig = strtolower((string) $mr['to_class']);             // Klíč cílové třídy
				$link_def_map[$ld_orig] = [                                  // Uložení pravidla definice vazby
					'from_class' => $fc_orig,
					'to_class'   => $tc_orig,
					'weight'     => ! empty($mr['link_weight_enabled']) ? 1 : 0
				];
				$distinct_classes[$fc_orig] = (string) $mr['from_class'];    // Evidence zdrojové třídy
				$distinct_classes[$tc_orig] = (string) $mr['to_class'];      // Evidence cílové třídy
			}
		}

		$class_options_map = [];                                             // Mapa položek roletek: [class_orig => [[uuid, label], ...]]
		foreach ($distinct_classes as $cls_key => $cls_raw) {                // Načtení položek pro každou zapojenou třídu
			$cls_lit = guidliteral($cls_raw);                                // SQL literál třídy
			$opts = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'ref_class', @param_code = 'link_endpoint', @ref_class_uuid = {$cls_lit}"); // Položky třídy
			$class_options_map[$cls_key] = [];                               // Inicializace pole voleb třídy
			if (is_array($opts)) {                                           // Naplnění voleb třídy
				foreach ($opts as $o_row) {                                  // Průchod záznamy třídy
					$u_str = (string) $o_row['original'];                    // UUID záznamu
					$c_str = (string) $o_row['code_col'];                    // Kód záznamu
					$cp_str = (string) $o_row['caption'];                    // Název záznamu
					$lbl = ($c_str !== '' AND $cp_str !== '' AND $cp_str !== $c_str) ? "{$c_str} ({$cp_str})" : ($cp_str ?: $c_str ?: $u_str); // Popisek
					$class_options_map[$cls_key][] = [                       // Uložení volby
						'uuid'  => $u_str,
						'label' => $lbl
					];
				}
			}
		}

		$json_defs = json_encode($link_def_map);                             // JSON mapa definic vazeb
		$json_opts = json_encode($class_options_map);                        // JSON mapa záznamů tříd
		$lbl_sel_def = addslashes($this->phrase('opt_select_default', [], '--- Vyberte ---')); // Výchozí volba roletky

		echo <<<HTML
		<script>
			(function() {
				const linkDefMap = {$json_defs};
				const classOptsMap = {$json_opts};
				const defaultOptLabel = '{$lbl_sel_def}';
				const form = document.querySelector('.md-detail form');
				if (!form) return;

				const defSel  = form.querySelector('select[name="link_def"]');
				const defHid  = form.querySelector('input[type="hidden"][name="link_def"]');
				const fromSel = form.querySelector('select[name="from_object"]');
				const toSel   = form.querySelector('select[name="to_object"]');

				function populateEndpointSelect(selEl, classKey, preserveVal) {
					if (!selEl) return;
					const prev = preserveVal && selEl.value ? selEl.value.toLowerCase() : '';
					const items = (classKey && classOptsMap[classKey]) ? classOptsMap[classKey] : [];

					while (selEl.options.length > 0) {
						selEl.remove(0);
					}

					const emptyOpt = document.createElement('option');
					emptyOpt.value = '';
					emptyOpt.textContent = defaultOptLabel;
					selEl.appendChild(emptyOpt);

					let matched = '';
					items.forEach(function(it) {
						const opt = document.createElement('option');
						opt.value = it.uuid;
						opt.textContent = it.label;
						if (prev !== '' && it.uuid.toLowerCase() === prev) {
							matched = it.uuid;
						}
						selEl.appendChild(opt);
					});

					if (matched !== '') {
						selEl.value = matched;
					}
				}

				function applyLinkDefEndpoints(preserveCurrent) {
					const rawDef = defSel ? defSel.value : (defHid ? defHid.value : '');
					const defKey = (rawDef ? rawDef : '').toLowerCase();
					const cfg = linkDefMap[defKey] ? linkDefMap[defKey] : null;
					if (!cfg) return;

					populateEndpointSelect(fromSel, cfg.from_class, preserveCurrent);
					populateEndpointSelect(toSel, cfg.to_class, preserveCurrent);

					['link_weight', 'reverse_link_weight'].forEach(function(col) {
						const wInp = form.querySelector('[name="' + col + '"]');
						if (wInp) {
							const wTr = wInp.closest('tr');
							if (wTr) {
								wTr.style.display = cfg.weight === 1 ? '' : 'none';
							}
						}
					});
				}

				if (defSel) {
					defSel.addEventListener('change', function() {
						applyLinkDefEndpoints(false);
					});
				}

				applyLinkDefEndpoints(true);
			})();
		</script>
HTML;
	}
}