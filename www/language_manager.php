<?php
/**
 * =============================================================================
 * Verze: 2026-10-01
 * Třída: language_manager
 * Účel: Izolovaná služba pro správu aktuálního jazyka, generování UI prvku
 *       a sestavení bezpečného fallback řetězce (dědičnosti) pro entity_manager.
 * =============================================================================
 */

declare(strict_types=1);

class language_manager {

	private string $current_lang;
	private array $languages = [];
	private array $fallback_chain = [];

	/**
	 * @param string|null $requested_lang Explicitní požadavek na změnu jazyka (např. z GET parametru)
	 */
	public function __construct(?string $requested_lang = null) {
		$this->load_languages();
		$this->resolve_current_language($requested_lang);
		$this->build_fallback_chain();
	}

	/**
	 * Jednorázově načte všechny dostupné jazyky a jejich SVG grafiku do paměti.
	 */
	private function load_languages(): void {
		$q = sqlrun("SELECT [language], caption, fallback_language, sort_code, is_default, svg_icon FROM [language] ORDER BY sort_code");
		while ($row = fetch($q)) {
			$this->languages[$row['language']] = $row;
		}
		free_result($q);
	}

	/**
	 * Určí finální jazyk relace na základě priorit: Explicitní žádost > Cookie > Výchozí DB > Nouzový Fallback
	 */
	private function resolve_current_language(?string $requested_lang): void {
		// 1. Explicitní požadavek z UI (přepnutí)
		if ($requested_lang !== null && isset($this->languages[$requested_lang])) {
			$this->current_lang = $requested_lang;
			$this->save_cookie();
			return;
		}

		// 2. Načtení z předchozí relace (cookie)
		if (isset($_COOKIE['bcm_language']) && isset($this->languages[$_COOKIE['bcm_language']])) {
			$this->current_lang = $_COOKIE['bcm_language'];
			return;
		}

		// 3. Fallback na výchozí jazyk systému (z databáze)
		foreach ($this->languages as $code => $lang) {
			if (!empty($lang['is_default'])) {
				$this->current_lang = $code;
				$this->save_cookie();                                    // Uložíme i výchozí, ať je pro příště zapsán
				return;
			}
		}

		// 4. Nouzový fallback, pokud chybí is_default vlajka
		$this->current_lang = isset($this->languages['cs']) ? 'cs' : (string)array_key_first($this->languages);
	}

	/**
	 * Sestaví pole jazyků pro entity_manager (kaskádové COALESCE).
	 * Zabraňuje zacyklení, pokud by databáze obsahovala kruhovou vazbu.
	 */
	private function build_fallback_chain(): void {
		$chain = [];
		$current = $this->current_lang;

		while ($current !== null && $current !== '') {
			if (in_array($current, $chain, true)) {
				break;                                                   // Pojistka proti zacyklení (např. cs -> sk a sk -> cs)
			}
			$chain[] = $current;
			$current = $this->languages[$current]['fallback_language'] ?? null;
		}

		$this->fallback_chain = $chain;
	}

	/**
	 * Zapíše kód jazyka do prohlížeče.
	 */
	private function save_cookie(): void {
		$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || $_SERVER['SERVER_PORT'] == 443;
		// Platnost cookie 1 rok
		setcookie('bcm_language', $this->current_lang, time() + (365 * 24 * 60 * 60), '/', '', $isHttps, true);
	}

	public function get_current_language(): string {
		return $this->current_lang;
	}

	public function get_fallback_chain(): array {
		return $this->fallback_chain;
	}

	public function get_languages(): array {
		return $this->languages;
	}

	/**
	 * Vykreslí kompaktní HTML komponentu pro přepínání jazyka.
	 * Nevyžaduje externí JS knihovny, využívá čisté CSS (hover menu).
	 * 
	 * @param string $return_url URL aktuální stránky, na kterou se uživatel po přepnutí vrátí.
	 */
	public function render_language_selector(string $return_url = ''): string {
		$current = $this->languages[$this->current_lang];
		$current_svg = $current['svg_icon'];
		$current_caption = htmlspecialchars($current['caption']);

		$html = <<<HTML
<style>
	.bcm-lang-selector { position: relative; display: inline-block; font-family: Arial, sans-serif; font-size: 13px; }
	.bcm-lang-btn { display: flex; align-items: center; gap: 8px; background: none; border: 1px solid transparent; cursor: pointer; padding: 4px 8px; border-radius: 4px; color: inherit; font-size: 10px; }
	.bcm-lang-btn:hover { background-color: rgba(0,0,0,0.05); }
	.bcm-lang-btn svg { width: 20px; height: 20px; }
	.bcm-lang-menu { display: none; position: absolute; right: 0; top: 100%; background: #fff; box-shadow: 0 4px 6px rgba(0,0,0,0.1); border: 1px solid #ccc; border-radius: 4px; min-width: 140px; z-index: 1000; overflow: hidden; margin-top: 2px; }
	.bcm-lang-selector:hover .bcm-lang-menu { display: block; }
	.bcm-lang-item { display: flex; align-items: center; gap: 8px; padding: 8px 12px; text-decoration: none; color: #333; transition: background 0.2s; font-size: 13px;}
	.bcm-lang-item:hover { background: #f4f4f4; }
	.bcm-lang-item svg { width: 16px; height: 16px; }
</style>
<div class="bcm-lang-selector">
	<button type="button" class="bcm-lang-btn" title="{$current_caption}">
		{$current_svg} <span>▼</span>
	</button>
	<div class="bcm-lang-menu">
HTML;

		foreach ($this->languages as $code => $lang) {
			$caption = htmlspecialchars($lang['caption']);
			$svg = $lang['svg_icon'];
			
			// Dynamické sestavení parametru pro přepnutí (set_lang)
			$safe_url = htmlspecialchars($return_url);
			$delim = strpos($return_url, '?') === false ? '?' : '&';
			$link = "{$safe_url}{$delim}set_lang={$code}";

			if ($code === $this->current_lang) {
				$html .= "\t\t<div class=\"bcm-lang-item\" style=\"background-color: #e6f7ff; font-weight: bold; cursor: default;\">{$svg} {$caption}</div>\n";
			} else {
				$html .= "\t\t<a href=\"{$link}\" class=\"bcm-lang-item\">{$svg} {$caption}</a>\n";
			}
		}

		$html .= "\t</div>\n</div>";
		return $html;
	}
}