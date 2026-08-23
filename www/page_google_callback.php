<?php
// =========================================================================
// SOUBOR: page_google_callback.php
// ÚČEL: Zpracování návratu uživatele ze SSO Google autentizace.
// VAZBY: Vyžaduje vendor/autoload.php (Composer) a config.php (klíče).
// =========================================================================

// Načtení naší konfigurace (obsahuje session_start, proměnné a DB spojení)
require_once 'config.php';

// 2. Inicializace Google Klienta
$client = new Google\Client();
$client->setClientId($google_client_id);
$client->setClientSecret($google_client_secret);
$client->setRedirectUri($google_redirect_uri);

// Přidání požadovaných oprávnění (scopes) - musíme se ptát jen na to, co jsme Googlu nahlásili
$client->addScope('email');
$client->addScope('profile');

// 3. Zpracování návratového kódu
if (isset($_GET['code'])) {
	
	// Vyměníme jednorázový GET kód za plnohodnotný přístupový token
	$token = $client->fetchAccessTokenWithAuthCode($_GET['code']);
	
	// Kontrola, zda nedošlo k chybě (např. kód vypršel)
	if (isset($token['error'])) {
		die("Kritická chyba SSO autentizace: " . htmlspecialchars($token['error_description']));
	}
	
	// Nastavení tokenu pro další dotazy na Google API
	$client->setAccessToken($token['access_token']);
	
	// 4. Získání profilu uživatele od Googlu
	$oauth2 = new Google\Service\Oauth2($client);
	$google_info = $oauth2->userinfo->get();
	
	$google_user_id = $google_info->id;			// Unikátní ID z Googlu (nemění se)
	$google_email   = $google_info->email;		// E-mail uživatele
	$google_name    = $google_info->name;		// Celé jméno (volitelné pro synchronizaci)
	
	// =========================================================================
	// 5. BYZNYS LOGIKA PRO RAMSES ISMS (SSO INTEGRACE)
	// =========================================================================
	
	/*
	Následující kód demonstruje napojení na tabulku user_external_identity.
	Striktně dodržujeme pravidla RAC (odkazujeme na UUID v poli original) 
	a hledáme platný záznam.
	*/
	
	$sql = "SELECT original 
			FROM user_external_identity 
			WHERE provider_name = 'Google' 
			  AND provider_user_id = ?
			  AND record_type = 'A' 
			  AND inactive = 0";
			  
	$params = array($google_user_id);
	$stmt = sqlsrv_query($dbconnection, $sql, $params);
	
	if ($stmt && $row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
		
		// Účet jsme našli! Získáme master identifikátor uživatele
		$user_original_uuid = $row['original'];
		
		// Zde zavoláme standardní přihlašovací proceduru pro vytvoření session v tabulce wwwsession
		// Předáme jí nalezené UUID uživatele a aktuální Session ID (připravené v config.php)
		
		/*
		$login_sql = "EXEC p_set_login @user_uuid = ?, @session_id = ?";
		$login_params = array($user_original_uuid, $SID);
		$login_stmt = sqlsrv_query($dbconnection, $login_sql, $login_params);
		
		if ($login_stmt) {
			// Zalogování proběhlo úspěšně, přesměrujeme do aplikace
			header('Location: index.php');
			exit;
		} else {
			die("Chyba při zakládání lokální session přes p_set_login.");
		}
		*/
		
		// ZATÍM JEN PRO TEST (smaž až zapneš p_set_login výše):
		echo "<h1>SSO Úspěch!</h1>";
		echo "Ověřený Google e-mail: <strong>" . htmlspecialchars($google_email) . "</strong><br>";
		echo "Lokální UUID uživatele: <strong>" . htmlspecialchars($user_original_uuid) . "</strong><br>";
		echo "Zde by proběhlo přesměrování do aplikace.";
		
	} else {
		
		// Scénář: Google člověka ověřil, ale my toto Google ID nemáme v databázi napojené na žádný náš účet.
		// Zde by mělo následovat přesměrování na chybovou stránku s hláškou:
		// "Váš Google účet není spárován se systémem Ramses. Přihlaste se lokálně a účet si propojte."
		
		echo "<h1>Účet nenalezen</h1>";
		echo "Google vás ověřil jako <strong>" . htmlspecialchars($google_email) . "</strong>, ";
		echo "ale v ISMS Ramses neexistuje vazba. Obraťte se na administrátora.";
	}
	
} else {
	// 6. Neplatný přístup
	// Pokud v GET není 'code', někdo na tuto adresu přistoupil přímo bez předchozího Google přesměrování.
	header('Location: page_login.php');
	exit;
}