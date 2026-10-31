<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 11:15
 * Soubor: config.php
 * Účel: Výchozí konfigurační hodnoty a inicializace připojení k databázi.
 *       Inkluduje se na každé stránce aplikace. Následně se načte lokální
 *       config_{SERVER_NAME}.php, který tyto hodnoty přepíše.
 *
 * Změny:
 * 2026-11-01 11:15 - Doplněno načtení souboru new_functions.php hned za OsirisLib.php
 *                    a sjednocení komentářů u řádků se znakem $ (Anti-LaTeX).
 * =============================================================================
 */

// 1. Inicializace session a předdefinování globálních proměnných
if (session_status() === PHP_SESSION_NONE) {
	session_start();
}

$dbsession = [];                                                             // Globální proměnná pro uložení dat relace uživatele
$debugmode = 0;                                                              // Globální proměnná, která povoluje ladicí režim
$SID = session_id();                                                         // Globální proměnná $SID pro initsession() v OsirisLib.php

// 2. Načtení autoloaderu pro Composer (Google API, PhpSpreadsheet, OpenSpout, CommonMark atd.)
require_once __DIR__ . '/vendor/autoload.php';

// 2.5 Nativní Autoloader pro lokální třídy (např. abstract_page, user_context, entity_manager)
spl_autoload_register(function (string $class_name): void {                  // Registrace autoloaderu aplikačních tříd
	$file = __DIR__ . '/' . $class_name . '.php';                            // Cesta ke zdrojovému souboru třídy
	if (file_exists($file)) {                                                // Kontrola existence souboru na disku
		require_once $file;                                                  // Načtení souboru třídy
	}
});

// 3. Výchozí konfigurace databáze
$dbms = "sqlsrv";                                                            // Typ databázového driveru
$dbserver = "název serveru";                                                 // Výchozí adresa SQL Serveru
$charset = 'UTF-8';                                                          // Znaková sada aplikace
$sqlsrv_charset = 'UTF-8';                                                   // Znaková sada SQLSRV spojení
$dblogin = "uživatel";                                                       // Přihlašovací jméno k DB
$dbpassword = "zadej heslo";                                                 // Heslo k DB
$debugmode = 1;                                                              // Výchozí zapnutí ladicího režimu
$use_dbname = "název databáze";                                              // Název cílové databáze
$CONFIGURATION_NAME = "Výchozí konfigurace";                                 // Popis konfigurace

// 4. Nastavení odesílání e-mailů (SMTP)
$smtp_server = 'sandbox.smtp.mailtrap.io';                                   // Výchozí vývojový SMTP server
$smtp_port = 2525;                                                           // Port SMTP serveru
$smtp_user = 'tvoje_mailtrap_jmeno';                                         // Uživatelské jméno SMTP
$smtp_password = 'tvoje_mailtrap_heslo';                                     // Heslo SMTP
$smtp_sender = 'noreply@tvojedomena.cz';                                     // Adresa odesílatele
$smtp_sender_name = 'BCM Osiris';                                            // Jméno odesílatele
$smtp_forward = 'honza.hink@gmail.com';                                      // Ochrana proti spamu při testování
$http_allowed = 0;                                                           // Příznak povolení nezabezpečeného HTTP

// 5. Nastavení Single Sign-On (SSO) - Google OAuth 2.0
$google_client_id = '';                                                      // Google OAuth Client ID (přepíše lokální config)
$google_client_secret = '';                                                  // Google OAuth Client Secret
$google_redirect_uri = '';                                                   // Návratová URI adresa pro Google callback

// 6. Načtení konfigurace specifické pro aktuální instanci (přepisuje výchozí hodnoty výše)
$http_host = (string)($_SERVER['HTTP_HOST'] ?? 'localhost');                 // Aktuální HTTP hostitel
$CONFIG_SERVER_NAME = explode(':', $http_host)[0];                           // Odříznutí případného portu z názvu serveru
require_once "config_{$CONFIG_SERVER_NAME}.php";                             // Načtení lokálního konfiguračního souboru

// 7. Načtení sdílených aplikačních knihoven
require_once 'OsirisLib.php';
require_once 'new_functions.php';
require_once 'send_global_mail.php';

// 8. Inicializační SQL příkaz pro MSSQL (striktní nastavení ANSI a transakcí)
$first_command = "while @@trancount>0 rollback
set xact_abort on
set ansi_padding on
set ansi_warnings on
set ansi_nulls on
set concat_null_yields_null on
set arithabort on set ansi_null_dflt_on on
set implicit_transactions off";                                              // Výchozí nastavení relace SQL Serveru

// 9. Připojení k databázi
$dbconnection = @sqlsrv_connect($dbserver, [                                 // Otevření spojení s MS SQL Serverem
	'UID'                    => $dblogin,                                    // Databázový uživatel
	'PWD'                    => $dbpassword,                                 // Databázové heslo
	'APP'                    => 'Ramses',                                    // Název aplikace v SQL Profileru
	'CharacterSet'           => $sqlsrv_charset,                             // Kódování komunikace UTF-8
	'TrustServerCertificate' => true,                                        // Povolení lokálního SSL certifikátu v PHP 8.3
	'MultipleActiveResultSets' => false                                      // Vypnutí MARS
]);

if (! $dbconnection) {                                                       // Kontrola úspěšného připojení k databázi
	fatal_error("Connect to SQL server failed, (SQLSRV configuration for {$CONFIG_SERVER_NAME}: {$CONFIGURATION_NAME})", "Server={$dbserver} as {$dblogin}"); // Fatální chyba spojení
}

if (! empty($use_dbname)) {                                                  // Pokud je zadán název databáze
	sqlrun("use {$use_dbname}");                                             // Přepnutí kontextu do cílové databáze
}
sqlrun($first_command);                                                      // Spuštění úvodního nastavení relace