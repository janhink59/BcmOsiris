<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 11:15
 * Soubor: new_functions.php
 * Účel: Nové a sjednocené globální pomocné funkce pro BCM Osiris.
 *       Vyčleněno do samostatného souboru mimo OsirisLib.php (pro pozdější
 *       ruční sloučení do OsirisLib.php).
 *
 * VAZBY NA OKOLÍ:
 * - Načítán z config.php bezprostředně po OsirisLib.php.
 * - Poskytuje sjednocené funkce pro kontrolu systémového kontextu (is_zero_guid,
 *   is_sys_org, has_role_access, get_session_org, get_session_lang, get_session_role)
 *   a univerzální překladovou funkci translate_phrase() eliminující opakování
 *   inicializačního kódu phrase_manageru napříč třídami.
 * =============================================================================
 */

declare(strict_types=1);

/**
 * Ověří, zda předaný identifikátor představuje systémovou nulu (0x00 nebo nulové UUID).
 */
function is_zero_guid(mixed $guid): bool {                                   // Kontrola nulového systémového identifikátoru
	$clean = strtolower(trim((string)($guid ?? '')));                        // Normalizace řetězce na malá písmena bez mezer
	return ($clean === '' OR $clean === '0x00' OR $clean === '00000000-0000-0000-0000-000000000000'); // Vyhodnocení nulového UUID
}

/**
 * Vrátí surové UUID aktivní organizace z globálního pole $dbsession (výchozí '0x00').
 */
function get_session_org(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$org = trim((string)($dbsession['organization'] ?? '0x00'));             // Načtení organizace z relace
	return ($org !== '') ? $org : '0x00';                                    // Vrácení organizace nebo 0x00
}

/**
 * Vrátí dvoupísmenný kód aktivního jazyka z $dbsession (výchozí 'cs').
 */
function get_session_lang(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$lang = trim((string)($dbsession['language'] ?? 'cs'));                  // Načtení kódu jazyka z relace
	return ($lang !== '') ? $lang : 'cs';                                    // Vrácení jazyka nebo 'cs'
}

/**
 * Vrátí kód efektivní aplikační role uživatele z $dbsession ('U', 'A', 'S', 'D').
 */
function get_session_role(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$role = strtoupper(trim((string)($dbsession['active_role'] ?? 'U')));    // Načtení aktivní role z relace
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
 * Sjednocený globální helper pro překlad a interpolaci frází přes $GLOBALS['phrase_manager'].
 * Eliminuje duplicitní metodu phrase() v jednotlivých UI komponentách a třídách.
 *
 * @param string               $builtin_code    Kód fráze v meta_phrase
 * @param string               $default_caption Výchozí český text (pro auto-discovery)
 * @param array<string, mixed> $vars            Proměnné pro interpolaci {$var}
 * @param string               $source_code     Zdrojová třída (prázdné = prohledá lookup_chain)
 * @return string Přeložený a interpolovaný text fráze
 */
function translate_phrase(string $builtin_code, string $default_caption = '', array $vars = [], string $source_code = ''): string { // Překlad fráze
	global $phrase_manager;                                                  // Globální instance správce frází
	if (! isset($phrase_manager) OR ! ($phrase_manager instanceof phrase_manager)) { // Kontrola inicializace správce
		$init_src = ($source_code !== '') ? $source_code : 'global_phrase';  // Výchozí kontext při nouzové inicializaci
		$phrase_manager = new phrase_manager($init_src);                     // Vytvoření instance phrase_manager
		$GLOBALS['phrase_manager'] = $phrase_manager;                        // Uložení do globálního kontextu
	}
	return $phrase_manager->get($builtin_code, $vars, $default_caption, $source_code); // Vrácení přeloženého textu
}