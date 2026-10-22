<?php
/**
 * =============================================================================
 * Verze: 2026-10-22 17:45
 * Soubor: language_manager.php
 * Třída: language_manager
 * Účel: Izolovaná služba pro správu aktuálního jazyka, generování UI prvku
 *       a sestavení bezpečného fallback řetězce (dědičnosti) pro entity_manager.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována v `phrase_manager`, `entity_manager` a `user_context`.
 * - Čte globální pole `$dbsession` a databázovou funkci `dbo.f_language_list()`.
 * - Pro uložení preference jazyka do prohlížeče volá funkci `set_secure_cookie()`
 *   z knihovny `OsirisLib.php`.
 * 
 * Změny:
 * 2026-10-22 17:45 - Propojení s databázovou funkcí dbo.f_language_list() a oprava
 *                    chybějících mezer před znakem $ v celém souboru.
 * 2026-10-19 23:40 - Čtení tabulky [language] v load_languages() převedeno ze
 *                    sqlrun/fetch na sqlarray_simple() (ochrana globálního $dbquery).
 * 2026-10-17 01:40 - Doplněna statická keš `$cached_languages` zabraňující opakovaným
 *                    SQL dotazům při vícenásobné inicializaci během jednoho requestu.
 *                  - V `save_cookie()` doplněna kontrola `!headers_sent()` a porovnání
 *                    s aktuální hodnotou `$_COOKIE['bcm_language']`.
 * =============================================================================
 */

declare(strict_types=1);

class language_manager {

	private static ?array $cached_languages = null;                          // Statická keš jazyků pro aktuální HTTP request
	private string $current_lang;                                            // Kód aktuálně vybraného jazyka relace
	private array $languages = [];                                           // Asociativní pole všech jazyků z databáze
	private array $fallback_chain = [];                                      // Řetězec záložních jazyků (fallback_order < 1000)

	/**
	 * @param string|null $requested_lang Explicitní požadavek na změnu jazyka (např. z GET parametru)
	 */
	public function __construct(?string $requested_lang = null) {            // Konstruktor správce jazyků
		$this->load_languages();                                             // Načtení seznamu jazyků z keše nebo DB
		$this->resolve_current_language($requested_lang);                    // Vyhodnocení aktivního jazyka relace
		$this->build_fallback_chain();                                       // Sestavení řetězce dědičnosti jazyků
	}

	/**
	 * Jednorázově načte všechny dostupné jazyky a jejich SVG grafiku přes f_language_list do paměti.
	 */
	private function load_languages(): void {
		if (self::$cached_languages !== null) {                              // Pokud již byly jazyky v tomto requestu načteny
			$this->languages = self::$cached_languages;                      // Převzetí jazyků ze statické keše
			return;                                                          // Ukončení bez opakovaného dotazu do DB
		}

		$rows = sqlarray_simple("SELECT [language], caption, fallback_language, sort_code, is_default, svg_icon, fallback_order FROM dbo.f_language_list(NULL) ORDER BY sort_code"); // Načtení z f_language_list
		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as$row) {                                        // Průchod načtenými řádky jazyků v paměti
				$this->languages[(string)$row['language']] =$row;           // Uložení jazyka pod jeho dvoupísmenný kód
			}
		}

		self::$cached_languages =$this->languages;                          // Uložení načtených jazyků do statické keše
	}

	/**
	 * Určí finální jazyk relace na základě priorit: Explicitní žádost > Databáze relace > Cookie > Výchozí DB > Nouzový Fallback
	 */
	private function resolve_current_language(?string $requested_lang): void { // Určení aktivního jazyka
		global $dbsession;                                                   // Globální pole relace přihlášeného uživatele

		// 1. Explicitní požadavek z UI (přepnutí)
		if ($requested_lang !== null AND isset($this->languages[$requested_lang])) { // Kontrola platnosti požadovaného jazyka
			$this->current_lang =$requested_lang;                           // Nastavení nově zvoleného jazyka
			$this->save_cookie();                                            // Uložení volby do cookie prohlížeče
			return;                                                          // Ukončení vyhodnocování
		}

		// 2. Načtení z existující databázové relace přihlášeného uživatele
		if (!empty($dbsession['language']) AND isset($this->languages[$dbsession['language']])) { // Kontrola jazyka v dbsession
			$this->current_lang = (string)$dbsession['language'];            // Převzetí jazyka z databázové relace
			$this->save_cookie();                                            // Synchronizace cookie v prohlížeči
			return;                                                          // Ukončení vyhodnocování
		}

		// 3. Načtení z předchozí relace (cookie)
		if (isset($_COOKIE['bcm_language']) AND isset($this->languages[$_COOKIE['bcm_language']])) { // Kontrola platné cookie
			$this->current_lang = (string)$_COOKIE['bcm_language'];          // Převzetí jazyka z cookie
			return;                                                          // Ukončení vyhodnocování
		}

		// 4. Fallback na výchozí jazyk systému (z databáze)
		foreach ($this->languages as $code =>$lang) {                       // Hledání výchozího jazyka v číselníku
			if (!empty($lang['is_default'])) {                               // Pokud má jazyk příznak is_default
				$this->current_lang = (string)$code;                         // Nastavení výchozího jazyka systému
				$this->save_cookie();                                        // Uložíme i výchozí, ať je pro příště zapsán
				return;                                                      // Ukončení vyhodnocování
			}
		}

		// 5. Nouzový fallback, pokud chybí is_default vlajka
		$this->current_lang = isset($this->languages['cs']) ? 'cs' : (string)array_key_first($this->languages); // Nouzová volba jazyka
	}

	/**
	 * Sestaví pole jazyků v pořadí fallback_order (od 1 po poslední návazný jazyk < 1000).
	 * Zabraňuje zacyklení, pokud by databáze obsahovala kruhovou vazbu.
	 */
	private function build_fallback_chain(): void {
		$chain = [];                                                         // Pole pro sestavení posloupnosti jazyků
		$current =$this->current_lang;                                      // Výchozím bodem je aktuální jazyk relace

		while ($current !== null AND$current !== '') {                      // Průchod řetězcem fallback jazyků
			if (in_array($current,$chain, true)) {                          // Kontrola duplicity v řetězci
				break;                                                       // Pojistka proti zacyklení (např. cs -> sk a sk -> cs)
			}
			$chain[] =$current;                                             // Zařazení jazyka do fallback řetězce
			$current = $this->languages[$current]['fallback_language'] ?? null; // Posun na nadřazený fallback jazyk
		}

		$this->fallback_chain =$chain;                                      // Uložení hotového řetězce jazyků
	}

	/**
	 * Zapíše kód jazyka do prohlížeče (pouze pokud došlo ke změně a hlavičky ještě nebyly odeslány).
	 */
	private function save_cookie(): void {
		$existing_cookie = (string)($_COOKIE['bcm_language'] ?? '');         // Aktuální hodnota cookie v requestu
		if ($existing_cookie ===$this->current_lang) {                      // Pokud prohlížeč již tuto hodnotu má
			return;                                                          // Neodesíláme zbytečně duplicitní hlavičku Set-Cookie
		}

		$_COOKIE['bcm_language'] =$this->current_lang;                      // Aktualizace v paměti pro další instance v requestu

		if (!headers_sent()) {                                               // Bezpečná kontrola, zda lze ještě modifikovat HTTP hlavičky
			$expires = time() + (365 * 24 * 60 * 60);                        // Platnost cookie na 1 rok
			set_secure_cookie('bcm_language', $this->current_lang,$expires, 'Lax'); // Odeslání cookie prohlížeči
		}
	}

	public function get_current_language(): string {
		return $this->current_lang;                                          // Vrácení kódu aktuálního jazyka
	}

	public function get_fallback_chain(): array {
		return $this->fallback_chain;                                        // Vrácení pole fallback jazyků
	}

	public function get_languages(): array {
		return $this->languages;                                             // Vrácení všech dostupných jazyků
	}

	/**
	 * Vykreslí kompaktní HTML komponentu pro přepínání jazyka.
	 * Nevyžaduje externí JS knihovny, využívá čisté CSS (hover menu).
	 * 
	 * @param string $return_url URL aktuální stránky, na kterou se uživatel po přepnutí vrátí.
	 */
	public function render_language_selector(string $return_url = ''): string { // Vykreslení přepínače jazyků
		$current = $this->languages[$this->current_lang];                    // Data aktuálně vybraného jazyka
		$current_svg =$current['svg_icon'];                                 // SVG ikona vlaječky aktuálního jazyka
		$current_caption = htmlspecialchars((string)$current['caption']);    // Ošetřený název aktuálního jazyka

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

		foreach ($this->languages as $code =>$lang) {                       // Vykreslení položek v rozbalovacím menu
			$caption = htmlspecialchars((string)$lang['caption']);           // Ošetřený název jazyka v roletce
			$svg =$lang['svg_icon'];                                        // SVG vlaječka jazyka
			
			// Dynamické sestavení parametru pro přepnutí (set_lang)
			$safe_url = htmlspecialchars($return_url);                       // Ošetřená návratová URL adresa
			$delim = strpos($return_url, '?') === false ? '?' : '&';         // Volba oddělovače parametrů v URL
			$link = "{$safe_url}{$delim}set_lang={$code}";                   // Cílový odkaz pro změnu jazyka

			if ($code ===$this->current_lang) {                             // Zvýraznění právě aktivního jazyka
				$html .= "\t\t<div class=\"bcm-lang-item\" style=\"background-color: #e6f7ff; font-weight: bold; cursor: default;\">{$svg} {$caption}</div>\n"; // Aktivní položka
			} else {
				$html .= "\t\t<a href=\"{$link}\" class=\"bcm-lang-item\">{$svg} {$caption}</a>\n"; // Odkaz na přepnutí jazyka
			}
		}

		$html .= "\t</div>\n</div>";                                         // Uzavření HTML přepínače jazyků
		return $html;                                                        // Vrácení výsledného HTML kódu
	}
}