<?php
/**
 * =============================================================================
 * Verze: 2026-10-16 09:55
 * Soubor: page_meta_column.php
 * Účel: Detailní editace metadat konkrétního sloupce (tenant override nebo překlad).
 *       Funguje jako podřízená stránka editoru logických tříd (page_meta_class)
 *       i při přímém otevření z menu (s přepínačem nadřízené logické třídy).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'meta_column'`.
 * - Využívá `abstract_button` pro návratové tlačítko do `page_meta_class`
 *   a `$this->phrase()` pro lokalizaci všech nadpisů, sekcí a upozornění.
 *
 * Změny:
 * 2026-10-16 09:55 - Oprava spojených řádků u definice sekce $grp_beh a u plnění
 *                    proměnné $options_html (doplněna diakritika do inline komentářů).
 * 2026-10-16 00:15 - Zapojení abstract_button a phrase_manager ($this->phrase).
 *                  - Odstraněna ruční kontrola role v konstruktoru (řeší předek a entity_manager).
 * 2026-10-15 22:55 - Doplněno volání parent::__construct(), výchozí napojení na
 *                    sys_global_columns při prázdném parent_class, přepínač třídy
 *                    v hlavičce Master panelu a návratové tlačítko do page_meta_class.
 * 2026-10-09 - Odstraněna redundantní vlastnost $access_denied a překrývané metody (řeší rodič).
 *            - Optimalizace konstruktoru: nevolá DB, pokud je přístup odepřen.
 *            - Oprava vyhodnocení oprávnění (přechod z right_sysadmin/right_orgadmin na active_role).
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_column extends abstract_page_master_detail {

	private string $parent_class = '';                                       // UUID vybrané nadřízené logické třídy
	private string $parent_name = '';                                        // Zobrazovaný název nadřízené třídy

	public function __construct() {
		parent::__construct();                                               // Inicializace frází a kontroly přístupu

		$this->class_name = 'meta_column';                                   // Logická třída pro entity_manager
		$this->page_title = $this->phrase('page_title', [], 'Správa metadat sloupce'); // Výchozí titulek stránky

		if ($this->access_denied) {                                          // Pokud předek zamítl přístup
			return;                                                          // Neprovádíme dotazy do databáze
		}

		$grp_pres = $this->phrase('grp_presentation', [], 'Základní prezentační údaje'); // Sekce textů
		$grp_ui   = $this->phrase('grp_ui_props', [], 'Formulářové vlastnosti a vazby (UI)'); // Sekce UI vlastností
		$grp_beh  = $this->phrase('grp_behavior', [], 'Behaviorální příznaky a ochrana'); // Sekce příznaků

		$this->form_groups = [                                               // Rozdělení polí do sekcí formuláře
			$grp_pres => ['caption', 'caption_plural', 'description', 'label', 'header', 'placeholder', 'helptext'], // Překládané texty
			$grp_ui   => ['input_type', 'input_width', 'max_length', 'input_rows', 'sort_code', 'list_order', 'referenced_codetable', 'referenced_class', 'css_class'], // Vlastnosti formulářového prvku
			$grp_beh  => ['translate', 'history', 'is_mandatory', 'is_html', 'hidden', 'is_url', 'show_empty', 'is_computed', 'customizable', 'is_final', 'is_protected'] // Příznaky chování a ochrany
		];                                                                   // Konec definice skupin formuláře
		
		$this->parent_class = trim((string)getinput('parent_class'));        // Načtení nadřízené třídy z URL/POST

		// Pokud nebyla v URL předána žádná třída, předvybereme globální slovník sys_global_columns
		if ($this->parent_class === '') {                                    // Kontrola prázdného parametru třídy
			$q_def = sqlrun("SELECT TOP 1 original FROM meta_class WHERE class_name = 'sys_global_columns' AND object_owner = 0x00 AND record_type = 'A' AND removed = 0"); // Dotaz na výchozí třídu
			if ($r_def = fetch($q_def)) {                                    // Načtení výchozí třídy
				$this->parent_class = (string)$r_def['original'];            // Výchozí UUID pro sys_global_columns
				$_GET['parent_class'] = $this->parent_class;                 // Zápis do GET pro propagaci kontextu
			}
			free_result($q_def);                                             // Uvolnění výsledku dotazu
		}
		
		if ($this->parent_class !== '') {                                    // Pokud máme platnou nadřízenou třídu
			$this->master_where = "m.parent_class = " . guidliteral($this->parent_class); // Podmínka pro levý panel
			
			// Zjištění názvu nadřízeného objektu pro titulek přes dynamický dotaz z entity_manageru
			$em_parent = new entity_manager('meta_class');                   // Správce pro načtení nadřízené třídy
			$q = sqlrun($em_parent->build_select_query("m.original = " . guidliteral($this->parent_class))); // Dotaz na nadřízenou třídu
			
			if ($row = fetch($q)) {                                          // Načtení dat nadřízené třídy
				$this->parent_name = (string)$row['caption'] !== '' ? (string)$row['caption'] : (string)$row['class_name']; // Určení názvu třídy
				$this->page_title = $this->phrase('page_title_class', ['class' => $this->parent_name], 'Sloupce: {' . chr(36) . 'class}'); // Aktualizace titulku stránky
			}
			free_result($q);                                                 // Uvolnění výsledku dotazu
		}
	}

	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuální řádek sloupce
		$c_name = htmlspecialchars((string)($datarow['column_name'] ?? '')); // Technický název sloupce
		$lbl = htmlspecialchars($this->phrase('header_column', [], 'Sloupec')); // Lokalizované návěstí sloupce
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$c_name}</span>"; // Výsledný nadpis detailu
	}

	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuální řádek sloupce
		if (!empty($datarow['ancestor'])) {                                  // Pokud sloupec dědí z globálního slovníku
			$note = htmlspecialchars($this->phrase('msg_inherited_column', [], 'Poznámka: Tento sloupec dědí vlastnosti od svého předka. Můžete zde upravit jeho překlady (nebo v roli Developer přepsat jeho vlastnosti).')); // Text poznámky o dědičnosti
			echo "<div style='color: #d97706; font-size: 12px; margin-bottom: 10px;'><b>{$note}</b></div>\n"; // Výpis poznámky
		}
	}

	protected function render_master_top(): void {
		// 1. Návratové tlačítko do nadřízené stránky page_meta_class (Editor objektů)
		if ($this->parent_class !== '') {                                    // Vykreslení návratového tlačítka
			$back_url = "index.php?page=page_meta_class&update_guid=" . urlencode($this->parent_class); // URL nadřízené třídy
			$btn_back = new abstract_button(                                 // Tlačítko návratu přes abstract_button
				'btn_back_to_class',                                         // Kód fráze v meta_phrase
				'← Zpět na třídu: {' . chr(36) . 'parent}',                  // Výchozí český popisek s proměnnou
				'page_meta_column',                                          // Zdrojová třída fráze
				'',                                                          // Bez SVG ikony
				'btn-secondary'                                              // Sekundární šedý styl tlačítka
			);
			$btn_back->set_href($back_url)                                   // Nastavení cílové URL adresy
				->set_vars(['parent' => $this->parent_name])                 // Dosazení názvu třídy do popisku
				->set_style('width: 100%; justify-content: center;');        // Roztáhnutí tlačítka na šířku panelu

			echo "<div style=\"margin-bottom: 10px;\">" . $btn_back->render() . "</div>\n"; // Výpis návratového tlačítka
		}

		// 2. Rychlý výběr logické třídy pro filtrování sloupců
		$options_html = '';                                                  // HTML opcí pro výběr třídy
		$q_cls = sqlrun("
			SELECT original, class_name, caption
			FROM meta_class
			WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0
			ORDER BY CASE WHEN class_name = 'sys_global_columns' THEN 0 ELSE 1 END, class_name
		");                                                                  // Dotaz na seznam logických tříd
		while ($cls = fetch($q_cls)) {                                       // Sestavení položek roletky tříd
			$c_uuid = (string)$cls['original'];                              // UUID logické třídy
			$c_code = htmlspecialchars((string)$cls['class_name']);          // Kód logické třídy
			$c_cap = htmlspecialchars((string)$cls['caption']);              // Popisek logické třídy
			$sel = (strcasecmp($c_uuid, $this->parent_class) === 0) ? 'selected' : ''; // Označení aktivní třídy
			$label = ($c_cap !== '' && $c_cap !== $c_code) ? "{$c_code} ({$c_cap})" : $c_code; // Text položky v roletce tříd
			$options_html .= "<option value=\"{$c_uuid}\" {$sel}>{$label}</option>"; // Přidání volby do seznamu
		}
		free_result($q_cls);                                                 // Uvolnění výsledku dotazu

		$lbl_class = htmlspecialchars($this->phrase('lbl_select_class', [], 'Logická třída (objekt):')); // Popisek roletky

		echo <<<HTML
		<div style="margin-bottom: 12px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_class}</label>
			<select onchange="if(this.value) document.location='index.php?page=page_meta_column&parent_class=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;
	}
}