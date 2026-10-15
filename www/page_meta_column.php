<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 22:55
 * Soubor: page_meta_column.php
 * Účel: Detailní editace metadat konkrétního sloupce (tenant override nebo překlad).
 *       Funguje jako podřízená stránka editoru logických tříd (page_meta_class)
 *       i při přímém otevření z menu (s přepínačem nadřízené logické třídy).
 * Změny:
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
	private bool $opened_from_class = false;                                 // Zda byl parent_class předán v URL

	public function __construct() {
		parent::__construct();                                               // Inicializace frází a kontroly přístupu

		global $dbsession;                                                   // Globální kontext relace

		$this->page_title = 'Správa metadat sloupce';                        // Výchozí titulek stránky
		$this->class_name = 'meta_column';                                   // Logická třída pro entity_manager
		
		// Přístup povolen pro systémové administrátory ('S', 'D') i administrátory organizací ('A')
		$active_role = $dbsession['active_role'] ?? 'U';                     // Aktuální role v relaci
		if (!in_array($active_role, ['S', 'D', 'A'], true)) {
			$this->access_denied = true;                                     // Odepření přístupu pro roli U
			return;
		}

		$this->form_groups = [                                               // Rozdělení polí do sekcí formuláře
			'Základní prezentační údaje' => ['caption', 'caption_plural', 'description', 'label', 'header', 'placeholder', 'helptext'],
			'Formulářové vlastnosti a vazby (UI)' => ['input_type', 'input_width', 'max_length', 'input_rows', 'sort_code', 'list_order', 'referenced_codetable', 'referenced_class', 'css_class'],
			'Behaviorální příznaky' => ['translate', 'history', 'is_mandatory', 'is_html', 'hidden', 'is_url', 'show_empty', 'is_computed', 'customizable']
		];
		
		$this->parent_class = trim((string)getinput('parent_class'));        // Načtení nadřízené třídy z URL/POST
		$this->opened_from_class = ($this->parent_class !== '');             // Příznak přechodu z page_meta_class

		// Pokud nebyla v URL předána žádná třída, předvybereme globální slovník sys_global_columns
		if ($this->parent_class === '') {
			$q_def = sqlrun("SELECT TOP 1 original FROM meta_class WHERE class_name = 'sys_global_columns' AND object_owner = 0x00 AND record_type = 'A' AND removed = 0");
			if ($r_def = fetch($q_def)) {
				$this->parent_class = (string)$r_def['original'];            // Výchozí UUID pro sys_global_columns
				$_GET['parent_class'] = $this->parent_class;                 // Zápis do GET pro propagaci kontextu
			}
			free_result($q_def);                                             // Uvolnění výsledku dotazu
		}
		
		if ($this->parent_class !== '') {
			$this->master_where = "m.parent_class = " . guidliteral($this->parent_class);
			
			// Zjištění názvu nadřízeného objektu pro titulek přes dynamický dotaz z entity_manageru
			$em_parent = new entity_manager('meta_class');                   // Správce pro načtení nadřízené třídy
			$q = sqlrun($em_parent->build_select_query("m.original = " . guidliteral($this->parent_class)));
			
			if ($row = fetch($q)) {
				$this->parent_name = (string)$row['caption'] !== '' ? (string)$row['caption'] : (string)$row['class_name'];
				$this->page_title = 'Sloupce: ' . $this->parent_name;        // Aktualizace titulku stránky
			}
			free_result($q);                                                 // Uvolnění výsledku dotazu
		}
	}

	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuální řádek sloupce
		$c_name = htmlspecialchars((string)($datarow['column_name'] ?? '')); // Technický název sloupce
		return "Sloupec: <span style=\"font-family: monospace; color: #555;\">{$c_name}</span>";
	}

	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuální řádek sloupce
		if (!empty($datarow['ancestor'])) {
			echo "<div style='color: #d97706; font-size: 12px; margin-bottom: 10px;'><b>Poznámka:</b> Tento sloupec dědí vlastnosti od svého předka. Můžete je zde přepsat (tenant override).</div>\n";
		}
	}

	protected function render_master_top(): void {
		// 1. Návratové tlačítko do nadřízené stránky page_meta_class (Editor objektů)
		if ($this->parent_class !== '') {
			$safe_parent = htmlspecialchars($this->parent_name);             // Ošetřený název nadřízené třídy
			$back_url = htmlspecialchars("index.php?page=page_meta_class&update_guid=" . urlencode($this->parent_class));
			echo <<<HTML
			<div style="margin-bottom: 10px;">
				<a href="{$back_url}" class="btn btn-secondary" style="width: 100%; justify-content: center;">&larr; Zpět na třídu: {$safe_parent}</a>
			</div>
HTML;
		}

		// 2. Rychlý výběr logické třídy pro filtrování sloupců
		$options_html = '';                                                  // HTML opcí pro výběr třídy
		$q_cls = sqlrun("
			SELECT original, class_name, caption
			FROM meta_class
			WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0
			ORDER BY CASE WHEN class_name = 'sys_global_columns' THEN 0 ELSE 1 END, class_name
		");
		while ($cls = fetch($q_cls)) {
			$c_uuid = (string)$cls['original'];                              // UUID logické třídy
			$c_code = htmlspecialchars((string)$cls['class_name']);          // Kód logické třídy
			$c_cap = htmlspecialchars((string)$cls['caption']);              // Popisek logické třídy
			$sel = (strcasecmp($c_uuid, $this->parent_class) === 0) ? 'selected' : '';
			$label = ($c_cap !== '' && $c_cap !== $c_code) ? "{$c_code} ({$c_cap})" : $c_code;
			$options_html .= "<option value=\"{$c_uuid}\" {$sel}>{$label}</option>";
		}
		free_result($q_cls);                                                 // Uvolnění výsledku dotazu

		echo <<<HTML
		<div style="margin-bottom: 12px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">Logická třída (objekt):</label>
			<select onchange="if(this.value) document.location='index.php?page=page_meta_column&parent_class=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;
	}
}