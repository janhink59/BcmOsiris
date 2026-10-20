<?php
/**
 * =============================================================================
 * Verze: 2026-10-20 11:35
 * Soubor: global_phrase.php
 * Třída: global_phrase
 * Účel: Samostatná obslužná třída pro správu a čtení celosystémových (globálních)
 *       textových frází vázaných na pevný identifikátor source_code = 'global_phrase'.
 *       Nahrazuje dřívější bezejmenné záznamy (source_code = '') v tabulkách
 *       meta_object a meta_phrase.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Název této třídy ('global_phrase') přímo odpovídá záznamu typu 'P' v tabulce
 *   meta_object (builtin_code = 'global_phrase') a sloupci source_code v tabulce
 *   meta_phrase.
 * - Třída nedědí z entity_manager (který slouží pro generování SQL dotazů a formulářů
 *   nad logickými třídami), ale spolupracuje s globální instancí phrase_manager
 *   ($GLOBALS['phrase_manager']), které deleguje dávkové načítání, kešování,
 *   jazykový fallback (přes language_manager) i automatickou registraci nových
 *   globálních frází (AUTO_DISCOVERED).
 * - Lze ji volat staticky (global_phrase::get(...)) i instančně z libovolného
 *   místa aplikace (včetně tříd excel_reader, xlsx_abstract či knihovny OsirisLib),
 *   které nedědí z abstract_page.
 *
 * Změny:
 * 2026-10-20 11:35 - Vytvoření třídy global_phrase pro správu globálních frází
 *                    s pevným identifikátorem source_code = 'global_phrase'.
 * =============================================================================
 */

declare(strict_types=1);

class global_phrase {

	/** Pevný identifikátor zdrojového objektu pro globální fráze v meta_object a meta_phrase */
	public const SOURCE_CODE = 'global_phrase';

	/**
	 * Zajistí existenci a vrátí globální instanci třídy phrase_manager.
	 *
	 * @return phrase_manager Aktivní instance správce frází
	 */
	private static function get_manager(): phrase_manager {
		global $phrase_manager;                                              // Přístup ke globální instanci správce frází
		if (!isset($phrase_manager) OR !($phrase_manager instanceof phrase_manager)) { // Kontrola existence instance
			$phrase_manager = new phrase_manager(self::SOURCE_CODE);         // Inicializace správce frází pro global_phrase
			$GLOBALS['phrase_manager'] = $phrase_manager;                    // Uložení do globálního kontextu aplikace
		}
		return $phrase_manager;                                              // Vrácení připraveného správce frází
	}

	/**
	 * Vrátí přeložený text globální fráze (source_code = 'global_phrase')
	 * s bezpečnou interpolací proměnných {$var}. Pokud fráze v databázi dosud
	 * neexistuje a je zadán $default_caption, automaticky ji zaregistruje.
	 *
	 * @param string               $builtin_code    Kód globální fráze (např. 'yes', 'no', 'err_db')
	 * @param string               $default_caption Výchozí český text při neexistenci v DB
	 * @param array<string, mixed> $vars            Asociativní pole proměnných pro dosazení {$var}
	 * @return string Přeložený a interpolovaný text globální fráze
	 */
	public static function get(string $builtin_code, string $default_caption = '', array $vars = []): string { // Získání textu globální fráze
		$pm = self::get_manager();                                           // Načtení instance phrase_manager
		return $pm->get($builtin_code, $vars, $default_caption, self::SOURCE_CODE); // Vyhodnocení fráze pod source_code = 'global_phrase'
	}

	/**
	 * Vrátí kompletní metadata globální fráze (caption, helptext, svg_icon, css_class).
	 *
	 * @param string $builtin_code    Kód globální fráze
	 * @param string $default_caption Výchozí český text pro auto-discovery
	 * @param string $default_svg     Výchozí SVG ikona (pouze při prvotním založení)
	 * @param string $default_css     Výchozí CSS třída
	 * @return array{caption: string, helptext: string, svg_icon: string, css_class: string}
	 */
	public static function get_meta(
		string $builtin_code,                                                // Kód požadované globální fráze
		string $default_caption = '',                                        // Výchozí text při neexistenci v DB
		string $default_svg = '',                                            // Výchozí SVG ikona
		string $default_css = ''                                             // Výchozí CSS třída
	): array {
		$pm = self::get_manager();                                           // Načtení instance phrase_manager
		return $pm->get_meta($builtin_code, $default_caption, self::SOURCE_CODE, $default_svg, $default_css); // Vrácení metadat globální fráze
	}

	/**
	 * Instanční wrapper pro získání textu globální fráze.
	 *
	 * @param string               $builtin_code    Kód globální fráze
	 * @param array<string, mixed> $vars            Proměnné pro interpolaci {$var}
	 * @param string               $default_caption Výchozí český text
	 * @return string Přeložený text globální fráze
	 */
	public function phrase(string $builtin_code, array $vars = [], string $default_caption = ''): string { // Instanční metoda pro překlad
		return self::get($builtin_code, $default_caption, $vars);            // Delegování na statickou metodu get()
	}
}