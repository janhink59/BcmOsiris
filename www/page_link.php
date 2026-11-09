<?php
/**
 * =============================================================================
 * Verze: 2026-11-09 16:30
 * Soubor: page_link.php
 * Třída: page_link
 * Účel: Správa provozních, katalogových a prostorových vazeb M:N v tabulce link
 *       (včetně zobrazení vazeb automaticky odvozených děděním po hierarchii
 *       s příznakem is_derived = 1).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_link`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'link'`.
 * - Při otevření z detailu aktiva (`&from_object=<uuid>`) zobrazuje návratové
 *   tlačítko zpět na aktivum a předvyplňuje zdrojový objekt u nové vazby.
 * =============================================================================
 */

declare(strict_types=1);

class page_link extends abstract_page_master_detail {

	private string $filter_link_def = '';                                    // Filtr na vybraný typ vazby (meta_link_def.original)
	private string $filter_from_object = '';                                 // Filtr na konkrétní objekt (asset/threat/scenario...)
	private string $from_object_caption = '';                                // Zobrazovaný název filtrovaného objektu

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

		if (! empty($where_parts)) {                                         // Sestavení výsledné podmínky pro levý panel
			$this->master_where = implode(' AND ', $where_parts);            // Spojení podmínek přes AND
		}

		$grp_rel  = $this->phrase('grp_link_endpoints', [], 'Typ vazby, zdrojový a cílový objekt'); // Sekce koncových bodů
		$grp_meta = $this->phrase('grp_weight_note', [], 'Váha přenosu rizika, poznámka a platnost'); // Sekce váhy a poznámky

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_rel  => ['link_def', 'from_object', 'to_object'],           // Klíčové složky vazby
			$grp_meta => ['link_weight', 'note', 'valid_from', 'valid_to', 'inactive'] // Váha, poznámka a platnost
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Rozšíří kontextový přívažek URL o parametry `link_def_filter` a `from_object`.
	 */
	protected function get_context_url_suffix(): string {
		$suffix = parent::get_context_url_suffix();                          // Základní kontextové parametry z předka
		if ($this->filter_link_def !== '' AND ! str_contains($suffix, '&link_def_filter=')) { // Zachování filtru typu vazby
			$suffix .= '&link_def_filter=' . urlencode($this->filter_link_def); // Připojení link_def_filter
		}
		if ($this->filter_from_object !== '' AND ! str_contains($suffix, '&from_object=')) { // Zachování filtru objektu
			$suffix .= '&from_object=' . urlencode($this->filter_from_object); // Připojení from_object
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
		");                                                                  // Jednorázové načtení názvů propojovaných objektů
		if (is_array($obj_rows)) {                                           // Naplnění mapy objektů
			foreach ($obj_rows as $or) {                                     // Průchod objekty
				$objs[strtolower((string) $or['original'])] = (string) $or['cap']; // Uložení názvu pod klíčem original
			}
		}

		return ['defs' => $defs, 'objs' => $objs];                           // Vrácení vyhledávacích map
	}

	/**
	 * Vykreslí horní ovládací prvky levého panelu (návrat na aktivum, filtr typu vazby a tlačítko + Nová vazba).
	 */
	protected function render_master_top(): void {
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

		echo <<<HTML
		<div style="margin-bottom: 10px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_flt}</label>
			<select onchange="document.location='index.php?page=page_link{$from_part}&link_def_filter=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
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
	 * Předvyplní kontextové hodnoty u nové vazby a uzamkne zděděné vazby (`is_derived = 1`).
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nová vazba
			if ($this->filter_link_def !== '') {                             // Předvyplnění typu vazby z filtru
				$datarow['link_def'] = $this->filter_link_def;               // Nastavení link_def
			}
			if ($this->filter_from_object !== '') {                          // Předvyplnění zdrojového objektu z filtru
				$datarow['from_object'] = $this->filter_from_object;         // Nastavení from_object
			}
		}

		if ($update_guid !== '' AND $update_guid !== 'NEW' AND ! empty($datarow['is_derived'])) { // Zděděná vazba
			$this->is_readonly = true;                                       // Uzamčení zděděné vazby v detailu
			$msg_der = htmlspecialchars($this->phrase('msg_derived_link_readonly', [], 'Tato vazba vznikla automatickým děděním z nadřízeného uzlu hierarchie (is_derived = 1). Zděděnou vazbu nelze ručně přepisovat; upravte ji na zdrojovém nadřízeném uzlu.')); // Info
			echo "<div class=\"msg-info\" style=\"margin-bottom: 12px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e;\">{$msg_der}</div>\n"; // Žlutý pruh
		}
	}
}