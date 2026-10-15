<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 22:22
 * Soubor: abstract_button.php
 * Třída: abstract_button
 * Účel: Univerzální komponenta pro vykreslování tlačítek (<button> i <a>)
 *       s automatickým napojením na tabulku meta_phrase přes phrase_manager.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Využívá globální instanci `$GLOBALS['phrase_manager']` (vytvářenou v `abstract_page`).
 * - Načítá přeložený popisek (`caption`), tooltip (`helptext`), vektorovou ikonu
 *   (`svg_icon`) a doplňkovou CSS třídu (`css_class`) z `meta_phrase`.
 * - Výchozí `source_code` je `'abstract_button'`, ale podporuje i přímé předání
 *   specifické třídy stránky nebo fallback na globální fráze (`''`).
 * - Lze ji instancovat přímo (`new abstract_button('btn_save', 'Uložit')`)
 *   nebo z ní dědit specializovaná tlačítka.
 * =============================================================================
 */

declare(strict_types=1);

class abstract_button {

	protected string $builtin_code;                                          // Identifikátor fráze tlačítka
	protected string $default_caption;                                       // Výchozí text pro auto-discovery
	protected string $source_code;                                           // Zdrojová třída v meta_phrase
	protected string $default_svg;                                           // Výchozí SVG ikona pro auto-discovery
	protected string $default_css;                                           // Výchozí CSS třída pro auto-discovery

	protected string $type = 'submit';                                       // Typ tlačítka (submit, button, reset)
	protected string $name = '';                                             // Atribut name u <button>
	protected string $value = '';                                            // Atribut value u <button>
	protected string $href = '';                                             // Pokud je vyplněno, vykreslí se jako <a>
	protected string $target = '';                                           // Atribut target pro odkaz <a>
	protected string $onclick = '';                                          // JS handler události onclick
	protected string $confirm_message = '';                                  // Potvrzovací dotaz před provedením akce
	protected string $extra_css = '';                                        // Dodatečné CSS třídy přidané v kódu
	protected string $id = '';                                               // HTML atribut id
	protected bool $disabled = false;                                        // Příznak neaktivního tlačítka
	protected array $vars = [];                                              // Proměnné pro interpolaci v popisku

	/**
	 * Konstruktor tlačítka.
	 *
	 * @param string $builtin_code    Kód tlačítka v meta_phrase (např. 'btn_save', 'btn_discard')
	 * @param string $default_caption Výchozí český popisek (použije se pro auto-discovery)
	 * @param string $source_code     Zdrojová třída (výchozí 'abstract_button')
	 * @param string $default_svg     Výchozí SVG ikona
	 * @param string $default_css     Výchozí doplňková CSS třída (např. 'btn-success', 'btn-danger')
	 */
	public function __construct(
		string $builtin_code,
		string $default_caption = '',
		string $source_code = 'abstract_button',
		string $default_svg = '',
		string $default_css = ''
	) {
		$this->builtin_code = $builtin_code;                                 // Uložení kódu fráze
		$this->default_caption = $default_caption;                           // Uložení výchozího popisku
		$this->source_code = $source_code;                                   // Uložení zdrojové třídy
		$this->default_svg = $default_svg;                                   // Uložení výchozí SVG ikony
		$this->default_css = $default_css;                                   // Uložení výchozí CSS třídy
	}

	/**
	 * Nastaví HTML typ tlačítka ('submit', 'button', 'reset').
	 */
	public function set_type(string $type): self {
		$this->type = $type;                                                 // Nastavení atributu type
		return $this;
	}

	/**
	 * Nastaví atributy name a value pro odeslání formuláře.
	 */
	public function set_name_value(string $name, string $value = '1'): self {
		$this->name = $name;                                                 // Nastavení atributu name
		$this->value = $value;                                               // Nastavení atributu value
		return $this;
	}

	/**
	 * Přepne tlačítko do režimu odkazu <a href="..."> (volitelně s target oknem).
	 */
	public function set_href(string $href, string $target = ''): self {
		$this->href = $href;                                                 // Nastavení cílové URL adresy
		$this->target = $target;                                             // Nastavení cílového okna
		return $this;
	}

	/**
	 * Nastaví vlastní JavaScript pro událost onclick.
	 */
	public function set_onclick(string $onclick): self {
		$this->onclick = $onclick;                                           // Nastavení JS kódu pro onclick
		return $this;
	}

	/**
	 * Nastaví potvrzovací dialog confirm(...) před provedením akce tlačítka.
	 */
	public function set_confirm(string $message): self {
		$this->confirm_message = $message;                                   // Text potvrzovacího dialogu
		return $this;
	}

	/**
	 * Přidá doplňkovou CSS třídu k tlačítku.
	 */
	public function add_class(string $css_class): self {
		$this->extra_css = trim($this->extra_css . ' ' . $css_class);        // Připojení další CSS třídy
		return $this;
	}

	/**
	 * Nastaví HTML atribut id.
	 */
	public function set_id(string $id): self {
		$this->id = $id;                                                     // Nastavení identifikátoru elementu
		return $this;
	}

	/**
	 * Zapne nebo vypne disabled stav tlačítka.
	 */
	public function set_disabled(bool $disabled = true): self {
		$this->disabled = $disabled;                                         // Nastavení příznaku deaktivace
		return $this;
	}

	/**
	 * Nastaví proměnné pro interpolaci {$var} v popisku nebo tooltipu tlačítka.
	 *
	 * @param array<string, mixed> $vars Asociativní pole proměnných
	 */
	public function set_vars(array $vars): self {
		$this->vars = $vars;                                                 // Uložení proměnných pro interpolaci
		return $this;
	}

	/**
	 * Sestaví a vrátí výsledný HTML kód tlačítka (<button> nebo <a>).
	 */
	public function render(): string {
		global $phrase_manager;                                              // Globální instance správce frází
		if (!isset($phrase_manager) || !($phrase_manager instanceof phrase_manager)) {
			$phrase_manager = new phrase_manager();                          // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] = $phrase_manager;                    // Uložení do globálního kontextu
		}

		$meta = $phrase_manager->get_meta(                                   // Načtení metadat tlačítka z DB
			$this->builtin_code,
			$this->default_caption,
			$this->source_code,
			$this->default_svg,
			$this->default_css
		);

		$caption = $phrase_manager->interpolate($meta['caption'], $this->vars);   // Interpolace popisku
		$helptext = $phrase_manager->interpolate($meta['helptext'], $this->vars); // Interpolace tooltipu
		$svg_icon = trim($meta['svg_icon']);                                 // Kód SVG ikony
		$db_css = trim($meta['css_class']);                                  // CSS třída z databáze

		// Složení výsledného seznamu CSS tříd
		$classes = ['btn'];                                                  // Základní třída všech tlačítek
		if ($db_css !== '') {
			$classes[] = $db_css;                                            // Přidání třídy z meta_phrase
		}
		if ($this->extra_css !== '') {
			$classes[] = $this->extra_css;                                   // Přidání třídy z PHP kódu
		}
		if ($this->disabled && $this->href !== '') {
			$classes[] = 'disabled';                                         // Vizuální deaktivace pro odkaz <a>
		}
		$class_attr = htmlspecialchars(implode(' ', array_unique($classes)));

		// Sestavení společných atributů (id, title, onclick)
		$attrs = "class=\"{$class_attr}\"";                                  // Atribut class
		if ($this->id !== '') {
			$attrs .= ' id="' . htmlspecialchars($this->id) . '"';           // Atribut id
		}
		if ($helptext !== '') {
			$attrs .= ' title="' . htmlspecialchars($helptext) . '"';        // Tooltip z helptextu
		}

		// Sestavení JS obsluhy onclick (včetně případného confirm dotazu)
		$js_parts = [];                                                      // Části výsledného onclick atributu
		if ($this->confirm_message !== '') {
			$safe_confirm = addslashes($this->confirm_message);              // Ošetření uvozovek pro JS confirm
			$js_parts[] = "if(!confirm('{$safe_confirm}')) return false;";   // Podmínka potvrzení akce
		}
		if ($this->onclick !== '') {
			$js_parts[] = $this->onclick;                                    // Vlastní JS kód
		}
		if (!empty($js_parts)) {
			$attrs .= ' onclick="' . htmlspecialchars(implode(' ', $js_parts)) . '"';
		}

		// Vnitřní obsah tlačítka (SVG ikona + text popisku)
		$inner_html = '';                                                    // Vnitřní HTML tlačítka
		if ($svg_icon !== '') {
			$inner_html .= '<span class="btn-icon">' . $svg_icon . '</span>'; // Vložení vektorové ikony
		}
		if ($caption !== '') {
			$inner_html .= '<span>' . htmlspecialchars($caption) . '</span>'; // Vložení popisku tlačítka
		}

		// Vykreslení jako odkaz <a> nebo jako formulářový <button>
		if ($this->href !== '') {
			$safe_href =$this->disabled ? '#' : htmlspecialchars($this->href);$target_attr = ($this->target !== '') ? ' target="' . htmlspecialchars($this->target) . '"' : '';
			return "<a href=\"{$safe_href}\" {$attrs}{$target_attr}>{$inner_html}</a>";
		}

		$type_attr = htmlspecialchars($this->type);                          // Typ tlačítka (submit/button)
		$name_attr = ($this->name !== '') ? ' name="' . htmlspecialchars($this->name) . '"' : '';
		$val_attr = ($this->name !== '') ? ' value="' . htmlspecialchars($this->value) . '"' : '';
		$dis_attr =$this->disabled ? ' disabled' : '';                      // HTML atribut disabled

		return "<button type=\"{$type_attr}\" {$attrs}{$name_attr}{$val_attr}{$dis_attr}>{$inner_html}</button>";
	}

	/**
	 * Magická metoda pro přímý výpis objektu tlačítka v šablonách (echo $btn).
	 */
	public function __toString(): string {
		return $this->render();                                              // Přímé vykreslení do řetězce
	}
}