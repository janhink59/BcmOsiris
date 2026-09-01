<?php
// =========================================================================
// SOUBOR: page_google_callback.php
// ÚČEL: Zpracování návratu uživatele ze SSO Google autentizace.
// VAZBY: Vyžaduje config.php (kde se inicializuje Composer, klíče i DB).
// =========================================================================

require_once 'config.php';

// Zpracování chybného přístupu (chybí parametr code z přesměrování)
if (!isset($_GET['code'])) {
	header('Location: index.php?page=login');
	exit;
}

// Inicializace Google Klienta
$client = new Google\Client();
$client->setClientId($google_client_id);
$client->setClientSecret($google_client_secret);
$client->setRedirectUri($google_redirect_uri);
$client->addScope('email');
$client->addScope('profile');

// Výměna jednorázového GET kódu za přístupový token
$token = $client->fetchAccessTokenWithAuthCode($_GET['code']);

// Validace vráceného tokenu
if (is_array($token) && isset($token['error'])) {
	$error_msg = isset($token['error_description']) ? $token['error_description'] : $token['error'];
	// Uložení chyby do session a přesměrování zpět na login
	$_SESSION['login_error'] = "Kritická chyba SSO autentizace: " . htmlspecialchars($error_msg);
	header('Location: index.php?page=login');
	exit;
}

// Nastavení tokenu a získání uživatelských informací
$client->setAccessToken($token['access_token']);
$oauth2 = new Google\Service\Oauth2($client);
$google_info = $oauth2->userinfo->get();

$google_email = $google_info->email;

// =========================================================================
// BYZNYS LOGIKA PRO RAMSES ISMS (PŘÍMÉ PÁROVÁNÍ DLE E-MAILU)
// =========================================================================

// Hledáme aktivní účet podle e-mailu. Pokud je jich více, bereme naposledy přihlášený.
$sql = "SELECT TOP 1 original 
		FROM user_account 
		WHERE email = ? 
		  AND record_type = 'A' 
		  AND inactive = 0 
		  AND removed = 0
		ORDER BY last_login_date DESC";

$params = array($google_email);
$stmt = sqlsrv_query($dbconnection, $sql, $params);

if ($stmt && $row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
	
	$user_original_uuid = $row['original'];
	
	// Získání IP adresy pro logování v p_set_login
	$client_ip = function_exists('get_client_ip_path') ? get_client_ip_path() : $_SERVER['REMOTE_ADDR'];
	
	// Aktivace lokální session zavoláním procedury pomocí parametrizovaného dotazu
	$login_sql = "EXEC p_set_login @user_uuid = ?, @wwwsession = ?, @client_ip = ?";
	$login_params = array($user_original_uuid, $SID, $client_ip);
	$login_stmt = sqlsrv_query($dbconnection, $login_sql, $login_params);
	
	if ($login_stmt) {
		// Úspěch - přesměrování do hlavní části aplikace
		header('Location: index.php?page=main');
		exit;
	} else {
		$_SESSION['login_error'] = "Chyba při zakládání lokální session přes uloženou proceduru.";
		header('Location: index.php?page=login');
		exit;
	}
	
} else {
	// Účet neexistuje v systému Ramses pro daný e-mail
	$_SESSION['login_error'] = "Google vás ověřil jako <strong>" . htmlspecialchars($google_email) . "</strong>, ale v systému neexistuje k tomuto e-mailu žádný aktivní účet. Obraťte se na administrátora.";
	header('Location: index.php?page=login');
	exit;
}
?>