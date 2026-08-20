<?php
/**
 * =============================================================================
 * Stránka: index.php
 * Účel: Centrální rozcestník (router) aplikace RAMSES.
 *
 * Logika a vazby:
 * - Načte konfiguraci (config.php), která následně inkluduje RamsesLib.php.
 * - Pomocí initsession() zajistí ověření sezení a nastavení kontextu uživatele.
 * - Získá a zanese parametr 'page' prostřednictvím bezpečné funkce getinput().
 * - Pokud parametr není zadán, automaticky směruje na 'main' (page_main.php).
 * - Pokud požadovaný soubor neexistuje, volá fatal_error().
 * =============================================================================
 */

declare(strict_types=1);

// Vynucení kódování UTF-8 pro hlavní výstup
header('Content-Type: text/html; charset=utf-8');

// 1. Načtení základní konfigurace, knihoven a inicializace databáze
// Skript config.php zajistí připojení k MSSQL a načtení sdílených funkcí z RamsesLib.php[cite: 3]
require_once "config.php";

// 2. Zjištění požadované stránky
// Využíváme standardní knihovní funkci getinput() pro bezpečné zpracování GET/POST požadavků
$page = (string)getinput('page');

// 3. Výchozí směrování a výjimky pro přihlášení
// Pokud parametr 'page' chybí nebo je prázdný, nastavíme výchozí hodnotu na 'main'
if ($page === '') {
	$page = 'main';
}

// 4. Inicializace session a ověření uživatele
// Funkce initsession() je definována v RamsesLib.php a plní pole $result_wwwsession[cite: 5].
// Pokud uživatel není přihlášen a nejedná se o pokus o zobrazení přihlašovací stránky 
// nebo o zaslání hesla, initsession() by jej dle historické logiky mohla vyhodit ven.
// Zatím voláme initsession() globálně, jelikož drží kontext pro zbytek běhu systému[cite: 5].
if ($page !== 'login' && $page !== 'password_reset') {
	initsession();
}

// 5. Ochrana proti Path Traversal (LFI)
// Bezpečnostní pojistka odstraňující lomítka a nepovolené znaky z názvu souboru
$page = basename($page);

// 6. Sestavení názvu cílového souboru podle dohodnuté jmenné konvence
$page_file = "page_{$page}.php";

// 7. Kontrola existence souboru a jeho inkludování do výstupu
if (file_exists($page_file)) {
	require_once $page_file;
} else {
	// Pokud stránka neexistuje, využijeme globální handler pro fatální chyby z RamsesLib.php[cite: 5]
	fatal_error("Chyba 404 - Nenalezeno", "Požadovaný modul '$page_file' nebyl na serveru nalezen.");
}