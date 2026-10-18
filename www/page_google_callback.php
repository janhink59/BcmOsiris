<?php
/**
 * =============================================================================
 * Verze: 2026-10-18 12:35
 * Soubor: page_google_callback.php
 * Účel: Zpracování návratu uživatele ze SSO Google autentizace.
 * Vazby: Vyžaduje config.php (kde se inicializuje Composer, klíče i DB)
 *        a volá uloženou proceduru p_set_login pro přihlášení do poslední
 *        navštívené organizace (last_login_organization).
 *
 * Změny:
 * 2026-10-18 12:35 - Upřesněno řazení účtů při neunikátním e-mailu (účty se
 *                    skutečným last_login_date mají přednost před NULL hodnotami).
 *                  - Striktní aplikace Anti-LaTeX pravidel (AND/OR místo &&/||,
 *                    komentáře s českou diakritikou na všech řádcích se znakem $).
 * =============================================================================
 */

declare(strict_types=1);

require_once 'config.php';

// Zpracování chybného přístupu (chybí parametr code z přesměrování)
if (!isset($_GET['code'])) {                                             // Kontrola přítomnosti autorizačního kódu
	header('Location: index.php?page=page_login');
	exit;
}

// Inicializace Google Klienta
$client = new Google\Client();                                           // Vytvoření instance Google klienta
$client->setClientId($google_client_id);                                 // Nastavení Client ID z konfigurace
$client->setClientSecret($google_client_secret);                         // Nastavení tajného klíče z konfigurace
$client->setRedirectUri($google_redirect_uri);                           // Nastavení návratové URI adresy
$client->addScope('email');                                              // Požadavek na e-mailovou adresu
$client->addScope('profile');                                            // Požadavek na profilová data

// Výměna jednorázového GET kódu za přístupový token
$token = $client->fetchAccessTokenWithAuthCode((string)$_GET['code']);   // Získání přístupového tokenu z Google API

// Validace vráceného tokenu
if (is_array($token) AND isset($token['error'])) {                       // Kontrola chyby při výměně tokenu
	$error_msg = isset($token['error_description']) ? (string)$token['error_description'] : (string)$token['error']; // Text chyby
	// Uložení chyby do session a přesměrování zpět na login
	$_SESSION['login_error'] = "Kritická chyba SSO autentizace: " . htmlspecialchars($error_msg); // Zápis chyby do relace
	header('Location: index.php?page=page_login');
	exit;
}

// Nastavení tokenu a získání uživatelských informací
$client->setAccessToken($token['access_token']);                         // Předání přijatého tokenu klientovi
$oauth2 = new Google\Service\Oauth2($client);                            // Inicializace služby OAuth2
$google_info = $oauth2->userinfo->get();                                 // Stažení profilu přihlášeného uživatele

$google_email = (string)$google_info->email;                             // Ověřený e-mail uživatele z Google účtu

// =========================================================================
// BYZNYS LOGIKA PRO BCM Osiris (PŘÍMÉ PÁROVÁNÍ DLE E-MAILU)
// =========================================================================

// Hledáme aktivní účet podle e-mailu. Pokud je jich více, bereme naposledy přihlášený.
$sql = "SELECT TOP 1 original 
		FROM user_account 
		WHERE email = ? 
		  AND email <> ''
		  AND record_type = 'A' 
		  AND inactive = 0 
		  AND removed = 0
		ORDER BY 
		  CASE WHEN last_login_date IS NULL THEN 1 ELSE 0 END ASC,
		  last_login_date DESC,
		  date_created DESC";                                            // Dotaz na nejnověji používaný účet s daným e-mailem

$params = [$google_email];                                               // Parametr e-mailu pro dotaz
$stmt = sqlsrv_query($dbconnection, $sql, $params);                      // Spuštění parametrizovaného dotazu

if ($stmt AND ($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC))) {  // Pokud byl nalezen odpovídající účet
	
	$user_original_uuid = $row['original'];                              // Originální UUID nalezeného uživatele
	
	// Získání IP adresy pro logování v p_set_login
	$client_ip = function_exists('get_client_ip_path') ? get_client_ip_path() : (string)($_SERVER['REMOTE_ADDR'] ?? ''); // Zjištění IP adresy
	
	// Aktivace lokální session zavoláním procedury pomocí parametrizovaného dotazu
	$login_sql = "EXEC p_set_login @user_uuid = ?, @wwwsession = ?, @client_ip = ?"; // Volání přihlašovací procedury
	$login_params = [$user_original_uuid, $SID, $client_ip];             // Parametry pro proceduru p_set_login
	$login_stmt = sqlsrv_query($dbconnection, $login_sql, $login_params); // Spuštění procedury p_set_login
	
	if ($login_stmt) {                                                   // Pokud založení relace proběhlo úspěšně
		// Úspěch - přesměrování do hlavní části aplikace
		header('Location: index.php?page=page_main');
		exit;
	} else {
		$_SESSION['login_error'] = "Chyba při zakládání lokální session přes uloženou proceduru."; // Chyba procedury
		header('Location: index.php?page=page_login');
		exit;
	}
	
} else {
	// Účet neexistuje v systému Ramses pro daný e-mail
	$_SESSION['login_error'] = "Google vás ověřil jako <strong>" . htmlspecialchars($google_email) . "</strong>, ale v systému neexistuje k tomuto e-mailu žádný aktivní účet. Obraťte se na administrátora."; // Hláška nenalezeného účtu
	header('Location: index.php?page=page_login');
	exit;
}