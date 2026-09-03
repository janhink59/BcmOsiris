<?php
// =========================================================================
// SOUBOR: config.php
// Výchozí konfigurační hodnoty. Inkluduje se na každé stránce aplikace.
// Následně se načte lokální config_{SERVER_NAME}.php, který tyto hodnoty přepíše.
// =========================================================================

// 1. Inicializace session
if (session_status() === PHP_SESSION_NONE) {
	session_start();
}
// Globální proměnná $SID pro initsession() v OsirisLib.php
$SID = session_id();

// 2. Načtení autoloaderu pro Composer (Google API, PhpSpreadsheet, atd.)
require_once __DIR__ . '/vendor/autoload.php';

// 3. Výchozí konfigurace databáze
$dbms = "sqlsrv";
$dbserver = "název serveru";
$charset = $sqlsrv_charset = 'UTF-8';
$dblogin = "uživatel";
$dbpassword = "zadej heslo";
$debugmode = 1;
$use_dbname = "název databáze";
$CONFIGURATION_NAME = "Výchozí konfigurace";

// 4. Nastavení odesílání e-mailů (SMTP)
$smtp_server = 'sandbox.smtp.mailtrap.io';
$smtp_port = 2525;
$smtp_user = 'tvoje_mailtrap_jmeno';
$smtp_password = 'tvoje_mailtrap_heslo';
$smtp_sender = 'noreply@tvojedomena.cz';
$smtp_sender_name = 'RAMSES ISMS';
$smtp_forward = 'honza.hink@gmail.com'; // Ochrana proti spamu při testování
$http_allowed = 0;

// 5. Nastavení Single Sign-On (SSO) - Google OAuth 2.0
// Hodnoty necháváme záměrně prázdné. Přepíší se v souboru config_localhost.php (či jiném),
// který musí být vyloučen z verzování v Gitu přes .gitignore.
$google_client_id = '';
$google_client_secret = '';
$google_redirect_uri = ''; // např. 'http://localhost/Ramses/index.php?page=google_callback'

// 6. Načtení konfigurace specifické pro aktuální instanci (přepisuje výchozí hodnoty výše)
$CONFIG_SERVER_NAME = explode(':', $_SERVER['HTTP_HOST'])[0];
require_once "config_{$CONFIG_SERVER_NAME}.php";

// 7. Načtení sdílených aplikačních knihoven
require_once 'OsirisLib.php';
require_once 'send_global_mail.php';

// 8. Inicializační SQL příkaz pro MSSQL (striktní nastavení ANSI a transakcí)
$first_command = "while @@trancount>0 rollback
set xact_abort on
set ansi_padding on
set ansi_warnings on
set ansi_nulls on
set concat_null_yields_null on
set arithabort on set ansi_null_dflt_on on
set implicit_transactions off";

// 9. Připojení k databázi
$dbconnection = @sqlsrv_connect($dbserver, array(
	'UID' => $dblogin,
	'PWD' => $dbpassword,
	'APP' => 'Ramses',
	'CharacterSet' => $sqlsrv_charset,
	'TrustServerCertificate' => true, // Zásadní pro PHP 8.x
	'MultipleActiveResultSets' => false
));

if (!$dbconnection) {
	fatal_error("Connect to SQL server failed, (SQLSRV configuration for $CONFIG_SERVER_NAME: $CONFIGURATION_NAME)", "Server=$dbserver as $dblogin");
}

if (@$use_dbname) {
	sqlrun("use $use_dbname");
}
sqlrun($first_command);
?>