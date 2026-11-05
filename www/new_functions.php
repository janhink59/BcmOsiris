<?php
/**
 * =============================================================================
 * Verze: 2026-11-05 10:15
 * Soubor: new_functions.php
 * Účel: Nové a sjednocené globální pomocné funkce pro BCM Osiris.
 *       Vyčleněno do samostatného souboru mimo OsirisLib.php (pro pozdější
 *       ruční sloučení do OsirisLib.php).
 *
 * VAZBY NA OKOLÍ:
 * - Načítán z config.php bezprostředně po OsirisLib.php.
 * - Poskytuje sjednocené funkce pro kontrolu systémového kontextu (is_zero_guid,
 *   is_sys_org, has_role_access, get_session_org, get_session_lang, get_session_role),
 *   funkci generate_builtin_code() pro automatické odvození builtin_code z názvu/zkratky
 *   a univerzální překladovou funkci translate_phrase().
 *
 * Změny:
 * 2026-11-05 10:15 - Doplněna funkce generate_builtin_code() pro převod českého
 *                    názvu/zkratky na platný identifikátor builtin_code (snake_case).
 * 2026-11-04 10:30 - Union typy se svislítkem u translate_phrase() nahrazeny
 *                    typem mixed dle Anti-LaTeX pravidla.
 * =============================================================================
 */

declare(strict_types=1);

/**
 * Ověří, zda předaný identifikátor představuje systémovou nulu (0x00 nebo nulové UUID).
 */
function is_zero_guid(mixed $guid): bool {                                   // Kontrola nulového systémového identifikátoru
	$clean = strtolower(trim((string) ($guid ?? '')));                       // Normalizace řetězce na malá písmena bez mezer
	return ($clean === '' OR $clean === '0x00' OR $clean === '00000000-0000-0000-0000-000000000000'); // Vyhodnocení nulového UUID
}

/**
 * Vrátí surové UUID aktivní organizace z globálního pole $dbsession (výchozí '0x00').
 */
function get_session_org(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$org = trim((string) ($dbsession['organization'] ?? '0x00'));            // Načtení organizace z relace
	return ($org !== '') ? $org : '0x00';                                    // Vrácení organizace nebo 0x00
}

/**
 * Vrátí dvoupísmenný kód aktivního jazyka z $dbsession (výchozí 'cs').
 */
function get_session_lang(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$lang = trim((string) ($dbsession['language'] ?? 'cs'));                 // Načtení kódu jazyka z relace
	return ($lang !== '') ? $lang : 'cs';                                    // Vrácení jazyka nebo 'cs'
}

/**
 * Vrátí kód efektivní aplikační role uživatele z $dbsession ('U', 'A', 'S', 'D').
 */
function get_session_role(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$role = strtoupper(trim((string) ($dbsession['active_role'] ?? 'U')));   // Načtení aktivní role z relace
	return in_array($role, ['U', 'A', 'S', 'D'], true) ? $role : 'U';        // Validace proti povoleným rolím
}

/**
 * Určí, zda zadaná organizace (nebo aktuální organizace v $dbsession) je systémová master organizace (0x00).
 */
function is_sys_org(?string $org_uuid = null): bool {                        // Kontrola systémové organizace 0x00
	$target_org = ($org_uuid !== null) ? $org_uuid : get_session_org();      // Použití předané nebo relací dané organizace
	return is_zero_guid($target_org);                                        // Vyhodnocení přes is_zero_guid
}

/**
 * Ověří, zda aktuální role uživatele (nebo explicitně předaná $active_role)
 * splňuje požadovanou minimální úroveň oprávnění ($required_role: 'U' < 'A' < 'S' < 'D').
 */
function has_role_access(string $required_role, ?string $active_role = null): bool { // Kontrola hierarchie oprávnění role
	$act = ($active_role !== null) ? strtoupper(trim($active_role)) : get_session_role(); // Efektivní role uživatele
	$req = strtoupper(trim($required_role));                                 // Požadovaná minimální role

	if ($act === 'D') {                                                      // Developer má přístup ke všem úrovním (U, A, S, D)
		return true;
	}
	if ($act === 'S') {                                                      // Sysadmin má přístup k úrovním U, A, S
		return in_array($req, ['U', 'A', 'S'], true);                        // Kontrola pro Sysadmina
	}
	if ($act === 'A') {                                                      // OrgAdmin má přístup k úrovním U, A
		return in_array($req, ['U', 'A'], true);                             // Kontrola pro OrgAdmina
	}
	return ($req === 'U');                                                   // Běžný uživatel má přístup pouze k úrovni U
}

/**
 * Odvodí platný technický identifikátor (builtin_code v snake_case) ze zadaného názvu nebo zkratky.
 * Spolehlivě odstraní českou a evropskou diakritiku nezávisle na nastavení OS locale.
 */
function generate_builtin_code(string $text, int $max_len = 40): string {    // Odvození builtin_code z názvu nebo zkratky
	$raw = trim(strip_tags($text));                                          // Odstranění případných HTML značek a okrajových mezer
	if ($raw === '') {                                                       // Prázdný vstup vrací prázdný řetězec
		return '';
	}

	$map = [                                                                 // Převodní tabulka české a slovenské diakritiky
		'á' => 'a', 'č' => 'c', 'ď' => 'd', 'é' => 'e', 'ě' => 'e', 'í' => 'i', 'ľ' => 'l', 'ĺ' => 'l',
		'ň' => 'n', 'ó' => 'o', 'ô' => 'o', 'ř' => 'r', 'ŕ' => 'r', 'š' => 's', 'ť' => 't', 'ú' => 'u',
		'ů' => 'u', 'ý' => 'y', 'ž' => 'z', 'ä' => 'a', 'ö' => 'o', 'ü' => 'u', 'ß' => 'ss',
		'Á' => 'a', 'Č' => 'c', 'Ď' => 'd', 'É' => 'e', 'Ě' => 'e', 'Í' => 'i', 'Ľ' => 'l', 'Ĺ' => 'l',
		'Ň' => 'n', 'Ó' => 'o', 'Ô' => 'o', 'Ř' => 'r', 'Ŕ' => 'r', 'Š' => 's', 'Ť' => 't', 'Ú' => 'u',
		'Ů' => 'u', 'Ý' => 'y', 'Ž' => 'z', 'Ä' => 'a', 'Ö' => 'o', 'Ü' => 'u'
	];                                                                       // Konec převodní tabulky
	$ascii = strtr($raw, $map);                                              // Nahrazení českých a evropských znaků
	$trans = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $ascii);             // Doplňková transliterace zbylých znaků
	if (is_string($trans) AND $trans !== '') {                               // Pokud iconv vrátil platný řetězec
		$ascii = $trans;                                                     // Použijeme výsledek iconv
	}

	$lower = strtolower($ascii);                                             // Převod na malá písmena
	$snake = (string) preg_replace('/[^a-z0-9]+/', '_', $lower);             // Nahrazení mezer a symbolů podtržítkem
	$clean = trim($snake, '_');                                              // Odstranění okrajových podtržítek
	if ($max_len > 0 AND strlen($clean) > $max_len) {                        // Omezení na požadovanou maximální délku
		$clean = rtrim(substr($clean, 0, $max_len), '_');                    // Oříznutí bez koncového podtržítka
	}
	return $clean;                                                           // Vrácení čistého identifikátoru
}

/**
 * Sjednocený globální helper pro překlad a interpolaci frází přes $GLOBALS['phrase_manager'].
 * Podporuje obě konvence volání: ($code,$default_caption, $vars) i ($code, $vars,$default_caption).
 *
 * @param string $builtin_code    Kód fráze v meta_phrase
 * @param mixed  $default_caption Výchozí český text (nebo pole proměnných)
 * @param mixed  $vars            Proměnné pro interpolaci {$var} (nebo výchozí text)
 * @param string $source_code     Zdrojová třída (prázdné = prohledá lookup_chain)
 * @return string Přeložený a interpolovaný text fráze
 */
function translate_phrase(string $builtin_code, mixed $default_caption = '', mixed $vars = [], string $source_code = ''): string { // Překlad fráze
	if (is_array($default_caption)) {                                        // Pokud bylo voláno s konvencí ($code, $vars, $default)
		$actual_vars = $default_caption;                                     // Pole proměnných z 2. parametru
		$actual_default = is_string($vars) ? $vars : '';                     // Výchozí text ze 3. parametru
	} else {
		$actual_default = (string) $default_caption;                         // Výchozí text z 2. parametru
		$actual_vars = is_array($vars) ? $vars : [];                         // Pole proměnných ze 3. parametru
	}
	global $phrase_manager;                                                  // Globální instance správce frází
	if (! isset($phrase_manager) OR ! ($phrase_manager instanceof phrase_manager)) { // Kontrola inicializace správce
		$init_src = ($source_code !== '') ? $source_code : 'global_phrase';  // Výchozí kontext při nouzové inicializaci
		$phrase_manager = new phrase_manager($init_src);                     // Vytvoření instance phrase_manager
		$GLOBALS['phrase_manager'] = $phrase_manager;                        // Uložení do globálního kontextu
	}
	return $phrase_manager->get($builtin_code, $actual_vars, $actual_default, $source_code); // Vrácení přeloženého textu
}