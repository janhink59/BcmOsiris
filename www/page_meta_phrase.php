<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 12:15
 * Soubor: page_meta_phrase.php
 * Třída: page_meta_phrase
 * Účel: Správa a lokalizace systémových i klientských textových frází,
 *       popisků tlačítek, tooltipů a náhledu SVG ikon přes entity_manager.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_meta_phrase`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'meta_phrase'`.
 * - Využívá `dbo.p_em_get_select_options @mode = 'source_code'` pro načtení
 *   lokalizovaného seznamu zdrojových PHP tříd v levém panelu.
 *
 * Změny:
 * 2026-11-01 12:15 - V render_master_top() nahrazen přímý SQL dotaz do meta_object
 *                    voláním procedury dbo.p_em_get_select_options @mode = 'source_code'
 *                    a nastaveno $this->allow_insert podle role Developer ('D').
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_phrase extends abstract_page_master_detail {

	private string $filter_source = '__ALL__';                               // Zvolený filtr zdrojového objektu

	public function __construct() {
		parent::__construct();                                               // Inicializace frází a kontroly přístupu

		$this->class_name = 'meta_phrase';                                   // Logická třída pro entity_manager
		$this->allow_insert = (get_session_role() === 'D');                  // Zakládání nových frází pouze pro roli Developer ('D')
		$this->page_title = $this->phrase('page_title', [], 'Správa textových frází a překladů'); // Lokalizovaný titulek

		$grp_id = $this->phrase('grp_identification', [], 'Identifikace a zařazení fráze'); // Nadpis sekce identifikace
		$grp_txt = $this->phrase('grp_texts', [], 'Texty a kontext pro překlad'); // Nadpis sekce překladů
		$grp_vis = $this->phrase('grp_visual', [], 'Vizuální atributy a ochrana'); // Nadpis sekce vzhledu

		$this->form_groups = [                                               // Rozdělení formuláře do logických sekcí
			$grp_id  => ['source_code', 'builtin_code', 'module'],           // Identifikační klíče fráze
			$grp_txt => ['caption', 'helptext', 'editor_note'],              // Překládané texty a AI kontext
			$grp_vis => ['svg_icon', 'css_class', 'is_final', 'is_protected', 'inactive'] // Vzhled tlačítka a zámky
		];                                                                   // Konec definice skupin formuláře

		$req_source = trim((string)getinput('parent_object'));               // Načtení filtru zdrojové třídy z URL
		if ($req_source !== '') {                                            // Pokud byl filtr v URL předán
			if ($req_source === '__GLOBAL__') {                              // Zpětná kompatibilita pro starý parametr
				$req_source = 'global_phrase';                               // Převod na pevný identifikátor global_phrase
			}
			$this->filter_source = $req_source;                              // Uložení vybraného filtru
			if ($this->filter_source !== '__ALL__') {                        // Filtrování na konkrétní PHP třídu vč. global_phrase
				$this->master_where = "m.source_code = " . charliteral($this->filter_source, 80); // SQL podmínka třídy
			}
		}
	}

	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$src = (string)($datarow['source_code'] ?? '');                      // Zdrojová třída fráze
		$code = (string)($datarow['builtin_code'] ?? '');                    // Kód konkrétní fráze
		$full_code = ($src !== '') ? "{$src}.{$code}" : $code;               // Složený identifikátor pro nadpis
		if ($full_code === '') {                                             // Pokud zakládáme novou frázi
			return htmlspecialchars($this->phrase('header_new_phrase', [], 'Nová textová fráze')); // Nadpis pro nový záznam
		}
		$safe_code = htmlspecialchars($full_code);                           // Ošetření speciálních znaků
		$lbl = htmlspecialchars($this->phrase('header_phrase', [], 'Fráze')); // Lokalizované návěstí nadpisu
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_code}</span>"; // Výsledný HTML nadpis
	}

	protected function render_master_top(): void {
		if ($this->allow_insert) {                                           // Pouze Developer ('D') smí zakládat nové systémové fráze v UI
			$url_suffix = $this->get_context_url_suffix();                   // Přívažek URL pro zachování filtru
			$new_url = "index.php?page=page_meta_phrase{$url_suffix}&update_guid=NEW"; // Cílová adresa pro novou frázi
			$btn_new = new abstract_button('btn_new_phrase', '+ Nová fráze', 'page_meta_phrase'); // Tlačítko nové fráze
			$btn_new->set_href($new_url)                                     // Nastavení cílové URL
				->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření detailu
				->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Stylování tlačítka
			echo $btn_new->render();                                         // Vykreslení tlačítka nad filtrem
		}

		$lbl_all = htmlspecialchars($this->phrase('opt_all_sources', [], '--- Všechny třídy a stránky ---')); // Volba všech tříd
		$lbl_glob = htmlspecialchars($this->phrase('opt_global_phrases', [], 'global_phrase (Globální fráze systému)')); // Volba globálních frází
		$sel_all = ($this->filter_source === '__ALL__') ? 'selected' : '';   // Označení volby všech zdrojů
		$sel_glob = ($this->filter_source === 'global_phrase') ? 'selected' : ''; // Označení globálních frází

		$options_html = "<option value=\"__ALL__\" {$sel_all}>{$lbl_all}</option>"; // První položka roletky
		$options_html .= "<option value=\"global_phrase\" {$sel_glob}>{$lbl_glob}</option>"; // Druhá položka roletky pro global_phrase

		$src_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'source_code'"); // Načtení lokalizovaných PHP tříd přes proceduru
		if (is_array($src_rows)) {                                           // Kontrola platného pole výsledků
			foreach ($src_rows as $r_src) {                                  // Iterace přes nalezené třídy a stránky
				$b_code = (string)$r_src['value_code'];                      // Technický název třídy
				$b_cap = (string)$r_src['caption'];                          // Lokalizovaný popisek třídy z metadat
				$safe_code = htmlspecialchars($b_code);                      // Ošetřený kód třídy
				$safe_cap = htmlspecialchars($b_cap);                        // Ošetřený popisek třídy
				$sel = ($b_code === $this->filter_source) ? 'selected' : ''; // Kontrola shody s aktivním filtrem
				$label = ($safe_cap !== '' AND $safe_cap !== $safe_code) ? "{$safe_code} ({$safe_cap})" : $safe_code; // Text položky
				$options_html .= "<option value=\"{$safe_code}\" {$sel}>{$label}</option>"; // Přidání položky do roletky
			}
		}

		$lbl_filter = htmlspecialchars($this->phrase('lbl_filter_source', [], 'Zdrojová třída / stránka (source_code):')); // Popisek roletky

		echo <<<HTML
		<div style="margin-bottom: 12px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_filter}</label>
			<select onchange="document.location='index.php?page=page_meta_phrase&parent_object=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;
	}
}