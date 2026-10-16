<?php
/**
 * =============================================================================
 * Verze: 2026-10-16 09:55
 * Stránka: index.php
 * Účel: Centrální rozcestník (router) aplikace RAMSES.
 *
 * Logika a vazby:
 * - Načte konfiguraci (config.php), která následně inkluduje OsirisLib.php.
 * - Pomocí initsession() zajistí ověření sezení a nastavení kontextu uživatele
 *   v globálním poli $dbsession.
 * - Inicializuje globální instanci $menu_manager (třída menu_manager).
 * - Získá a zanese parametr 'page' prostřednictvím bezpečné funkce getinput().
 * - Pokud parametr není zadán, automaticky směruje na 'page_main' (page_main.php).
 * - Zachovává plnou zpětnou kompatibilitu pro URL s prefixem 'page_' i bez něj.
 * - Pokud požadovaný soubor neexistuje, volá fatal_error().
 * 
 * Změny:
 * 2026-10-16 09:55 - Oprava součinnosti s initsession() v OsirisLib.php pro stavy
 *                    'page_logout' -> 'logout' a opětovnou normalizaci prefixu 'page_'
 *                    po návratu z initsession() (zamezení chyby 404 pro 'login.php').
 * 2026-10-13 - Přidána globální inicializace objektu menu_manager.
 * 2026-10-15 - Sjednocení routování na plné názvy stránek s prefixem 'page_'
 *              v souladu s registrací objektů typu 'P' v tabulce meta_object.
 * =============================================================================
 */

declare(strict_types=1);

// Vynucení kódování UTF-8 pro hlavní výstup
header('Content-Type: text/html; charset=utf-8');

// 1. Načtení základní konfigurace, knihoven a inicializace databáze
// Skript config.php zajistí připojení k MSSQL a načtení sdílených funkcí z OsirisLib.php
require_once "config.php";

// 2. Zjištění požadované stránky
// Využíváme standardní knihovní funkci getinput() pro bezpečné zpracování GET/POST požadavků
$page = trim((string)getinput('page'));                                  // Načtení požadované stránky z URL nebo POST

// 3. Výchozí směrování a výjimky pro přihlášení
// Pokud parametr 'page' chybí nebo je prázdný, nastavíme výchozí hodnotu na 'main'
if ($page === '') {                                                      // Kontrola prázdného parametru stránky
	$page = 'page_main';                                                 // Výchozí cílová stránka po přihlášení
}

// 5. Ochrana proti Path Traversal (LFI) a normalizace prefixu 'page_'
// Bezpečnostní pojistka odstraňující lomítka a nepovolené znaky z názvu souboru
$page = basename($page, '.php');                                         // Očištění názvu od cesty a případné přípony

if (!str_starts_with($page, 'page_')) {                                  // Kontrola přítomnosti předpony page_
	$page = 'page_' . $page;                                             // Sjednocení na plný název s prefixem page_
}

// 4. Inicializace session a ověření uživatele
// Funkce initsession() je definována v OsirisLib.php a plní pole $dbsession.
// Výjimka byla rozšířena o 'google_callback', protože při návratu z IdP ještě lokální session neexistuje.
if ($page !== 'page_login' && $page !== 'page_password_reset' && $page !== 'page_google_callback') { // Stránky vyžadující relaci
	if ($page === 'page_logout') {                                       // Překlad názvu odhlášení pro initsession()
		$page = 'logout';                                                // OsirisLib.php testuje hodnotu 'logout'
	}

	initsession();                                                       // Ověření relace nebo přesměrování na login

	// Opětovná normalizace prefixu 'page_' (initsession() při nepřihlášení nastavuje $page = 'login')
	if (!str_starts_with($page, 'page_')) {                              // Kontrola předpony po volání initsession()
		$page = 'page_' . $page;                                         // Doplnění předpony page_ (např. page_login)
	}
	
	// Inicializace globálního správce menu bezprostředně po ustavení platné relace.
	// Třída je načtena přes spl_autoload_register v config.php.
	if ($page !== 'page_login') {                                        // Menu načítáme jen pro přihlášeného uživatele
		global $menu_manager;                                            // Globální instance správce navigace
		$menu_manager = new menu_manager();                              // Načtení hierarchie menu pro přihlášeného uživatele
	}
}

// 6. Sestavení názvu cílového souboru podle dohodnuté jmenné konvence
$page_file = "{$page}.php";                                              // Fyzický název souboru stránky na disku

// 7. Kontrola existence souboru a jeho inkludování do výstupu

if (file_exists($page_file)) {                                           // Ověření existence souboru na disku
	// Pro procedurální stránky se kód provede okamžitě při inkluzi
	require_once $page_file;                                             // Načtení zdrojového souboru stránky
	
	// Dynamická detekce objektové stránky
	$class_name = $page;                                                 // Název třídy odpovídá plnému kódu stránky
	if (class_exists($class_name) && is_subclass_of($class_name, 'abstract_page')) { // Kontrola dědičnosti z abstract_page
		$page_instance = new $class_name();                              // Instancování objektu stránky
		$page_instance->render();                                        // Spuštění zpracování a vykreslení stránky
	}
} else {
	// Pokud stránka neexistuje, využijeme globální handler pro fatální chyby z OsirisLib.php
	fatal_error("Chyba 404 - Nenalezeno", "Požadovaný modul '$page_file' nebyl na serveru nalezen."); // Chybové hlášení 404
}