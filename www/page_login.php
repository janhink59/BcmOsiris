<?php
/**
 * =============================================================================
 * Verze: 2026-10-18 12:35
 * Stránka: page_login.php
 * Účel: Zajišťuje autentizaci uživatele proti tabulce user_account 
 *       (podle unikátního login_name nebo neunikátního emailu)
 *       nebo system_constant (System Admin) a úvodní nastavení jazyka.
 *       Podporuje zobrazení přesměrovaných chyb (např. z Google SSO).
 * 
 * Logika a vazby:
 * - Jelikož index.php přeskočí initsession() při $page == 'login', musíme
 *   zde session_start() zavolat sami, abychom získali platné $SID.
 * - Instancuje language_manager pro obsluhu jazyka z cookies a vykreslení UI.
 * - Zpracovává POST požadavek s přihlašovacími údaji přes getinput().
 * - Pokud uživatel zadá místo loginu svůj e-mail, vyhledají se aktivní účty
 *   se zadaným e-mailem seřazené podle last_login_date DESC (nejnověji přihlášený
 *   účet má přednost) a přihlásí se jeho loginem do poslední organizace.
 * - V případě zaškrtnutí "Zůstat přihlášen" generuje kryptograficky bezpečné
 *   tokeny (Selector & Validator) do tabulky auth_tokens a HTTP-only cookie.
 *
 * Změny:
 * 2026-10-18 12:35 - Doplněna podpora přihlášení e-mailem (bez požadavku na unikátnost
 *                    e-mailu v user_account, výběr podle last_login_date DESC).
 *                  - Striktní aplikace Anti-LaTeX pravidel (OR/AND místo ||/&&,
 *                    komentáře s českou diakritikou na všech řádcích se znakem $).
 * =============================================================================
 */

declare(strict_types=1);

// Vynucení kódování UTF-8 pro hlavní výstup
header('Content-Type: text/html; charset=utf-8');

// Globální proměnné z configu a knihoven
global $SID, $http_allowed, $google_client_id, $google_redirect_uri; // Globální konfigurační proměnné

// 1. Zajištění session (pokud jsme přišli přímo přes index.php?page=login)
if (session_status() === PHP_SESSION_NONE) {
	session_start();
}
$SID = session_id();                                                     // Identifikátor aktuální relace prohlížeče

// 2. Inicializace jazykového manažera a ošetření přepnutí jazyka
$requested_lang = (isset($_GET['set_lang']) AND is_string($_GET['set_lang'])) ? $_GET['set_lang'] : null; // Požadovaný jazyk z URL
$lang_manager = new language_manager($requested_lang);                   // Inicializace správce jazyků

// Pokud uživatel přepnul jazyk, manažer zapsal cookie. Provedeme redirect pro čisté URL (PRG vzor).
if ($requested_lang !== null) {                                          // Pokud došlo ke změně jazyka
	header('Location: index.php?page=page_login');
	exit;
}

$current_lang = $lang_manager->get_current_language();                   // Kód aktuálně zvoleného jazyka
$messageHtml = '';                                                       // HTML chybové nebo informační zprávy
$isPost = ($_SERVER['REQUEST_METHOD'] === 'POST');                       // Příznak odeslání formuláře metodou POST

// =========================================================================
// ZOBRAZENÍ CHYBOVÝCH HLÁŠEK Z PŘESMĚROVÁNÍ (Flash messages)
// =========================================================================
if (isset($_SESSION['login_error'])) {                                   // Kontrola chyby uložené v session
	$messageHtml = "<div class='msg-err'>" . $_SESSION['login_error'] . "</div>"; // Sestavení boxu s chybou
	unset($_SESSION['login_error']);                                     // Odstranění po prvním zobrazení
}

// =========================================================================
// INICIALIZACE GOOGLE SSO (Příprava URL pro tlačítko)
// =========================================================================
$googleAuthUrl = '';                                                     // Výchozí prázdná URL pro Google OAuth
if (
	!empty($google_client_id)                                            // Kontrola existence Google Client ID
	AND !empty($google_redirect_uri)                                     // Kontrola existence návratové URI
	AND filter_var($google_redirect_uri, FILTER_VALIDATE_URL)            // Validace formátu návratové URI
	AND class_exists('Google\Client')
) {
	try {
		// Vytvoření klienta pro získání autorizační URL s potřebnými scopes
		$client = new Google\Client();                                   // Instance Google API klienta
		$client->setClientId($google_client_id);                         // Nastavení identifikátoru aplikace
		$client->setRedirectUri($google_redirect_uri);                   // Nastavení callback URL adresy
		$client->addScope('email');                                      // Požadavek na e-mail uživatele
		$client->addScope('profile');                                    // Požadavek na základní profil
		
		// Vygenerování URL pro přesměrování uživatele
		$googleAuthUrl = $client->createAuthUrl();                       // Sestavení přihlašovacího odkazu Google
	} catch (InvalidArgumentException $e) {                              // Zachycení chyby konfigurace klienta
		// Tiše zachytíme případnou chybu z Google knihovny
		$googleAuthUrl = '';                                             // Vypnutí tlačítka při neplatné konfiguraci
	}
}

// =========================================================================
// KONTROLA BEZPEČNOSTI (HTTP vs HTTPS)
// =========================================================================
$isHttps = ((!empty($_SERVER['HTTPS']) AND $_SERVER['HTTPS'] !== 'off') OR $_SERVER['SERVER_PORT'] == 443); // Detekce šifrovaného spojení
$blockAction = false;                                                    // Příznak zablokování přihlášení

// Blokování nezabezpečeného přenosu hesla, pokud není explicitně povolen
if (!$isHttps AND empty($http_allowed)) {                                // Kontrola povolení HTTP v konfiguraci
	$messageHtml = "
		<div class='msg-err' style='margin-bottom: 25px;'>
			<strong>Kritické bezpečnostní riziko:</strong> Komunikace probíhá přes nezabezpečený protokol HTTP. 
			Zadávaná hesla by mohla být odposlechnuta. Akce byla zablokována.
			<br><br>
			<em>(Pro ladění lokálně povolte proměnnou <code>&#36;http_allowed = 1;</code> v config.php)</em>
		</div>";                                                         // Chybová hláška při nezabezpečeném HTTP
	$blockAction = true;                                                 // Zablokování odeslání formuláře
}

if ($isPost AND $blockAction) {                                          // Zahození POST požadavku při blokaci HTTP
	$isPost = false;                                                     // Zahození POSTu při blokaci
}

// =========================================================================
// ZPRACOVÁNÍ PŘIHLÁŠENÍ (LOKÁLNÍ JMÉNO / E-MAIL A HESLO)
// =========================================================================
if ($isPost) {                                                           // Zpracování odeslaného přihlašovacího formuláře
	// Získání raw vstupů, protože hesla mohou obsahovat speciální znaky
	$login = trim((string)getinput('login_name', 'raw'));                // Zadané přihlašovací jméno nebo e-mail
	$password = (string)getinput('password', 'raw');                     // Zadané heslo v surovém tvaru
	
	if ($login === '' OR $password === '') {                             // Kontrola vyplnění obou polí
		$messageHtml = "<div class='msg-err'>Prosím, zadejte přihlašovací jméno (nebo e-mail) i heslo.</div>"; // Chybová zpráva
	} else {
		$safeLogin = charliteral($login, 200);                           // Bezpečný SQL literál přihlašovacího údaje
		$isAuthenticated = false;                                        // Příznak úspěšného ověření hesla
		$userUuid = '';                                                  // Originální UUID ověřeného účtu
		
		// A. Pokus o přihlášení jako System Admin (break-glass účet) z tabulky system_constant
		$sqlSysAdmin = "SELECT system_admin_pwd FROM system_constant";   // Dotaz na nouzové heslo správce
		$sysAdminRow = sqlfirstrow($sqlSysAdmin);                        // Načtení řádku systémových konstant
		
		// Kontrola, zda uživatel zadal striktně admin login
		if ($sysAdminRow AND strtolower($login) === 'admin') {           // Kontrola přihlášení nouzového účtu admin
			$hash = trim((string)$sysAdminRow['system_admin_pwd']);      // Hash nouzového hesla
			if (password_verify($password, $hash)) {                     // Ověření nouzového hesla
				$isAuthenticated = true;                                 // Označení úspěšné autentizace
				$userUuid = '00000000-0000-0000-0000-000000000000';      // Rezervovaný NULL UUID pro systém
			}
		}
		
		// B. Pokus o přihlášení jako běžný uživatel z tabulky user_account (nejprve podle unikátního login_name)
		if (!$isAuthenticated) {                                         // Pokud nejde o nouzový účet admin
			$userSql = "
				SELECT original, password_hash, inactive, require_password_change, allow_local_login, locked_until 
				FROM user_account 
				WHERE login_name = {$safeLogin} 
					AND record_type = 'A' 
					AND removed = 0
			";                                                           // Dotaz na účet podle login_name
			
			$userRows = sqlarray_simple($userSql);                       // Načtení nalezených účtů podle loginu
			
			// Pokud účet nebyl nalezen podle login_name, zkusíme vyhledat aktivní účty podle e-mailu
			// seřazené od naposledy přihlášeného (last_login_date DESC).
			$searchedByEmail = false;                                    // Příznak vyhledávání podle e-mailu
			if (!is_array($userRows) OR count($userRows) === 0) {        // Pokud podle login_name nebyl nalezen žádný záznam
				$searchedByEmail = true;                                 // Přepnutí do režimu hledání podle e-mailu
				$emailSql = "
					SELECT original, password_hash, inactive, require_password_change, allow_local_login, locked_until
					FROM user_account
					WHERE email = {$safeLogin}
						AND email <> ''
						AND record_type = 'A'
						AND removed = 0
					ORDER BY
						inactive ASC,
						CASE WHEN last_login_date IS NULL THEN 1 ELSE 0 END ASC,
						last_login_date DESC,
						date_created DESC
				";                                                       // Dotaz na účty se zadaným e-mailem
				$userRows = sqlarray_simple($emailSql);                  // Načtení účtů podle e-mailu
			}

			if (is_array($userRows) AND count($userRows) > 0) {          // Pokud byl nalezen alespoň jeden účet
				if (!$searchedByEmail AND count($userRows) > 1) {        // Kontrola duplicity u přihlašovacího jména
					$messageHtml = "<div class='msg-err'>Přihlašovací jméno není unikátní (kolize identit). Kontaktujte administrátora.</div>"; // Chyba kolize loginu
				} else {
					// Projdeme nalezené kandidáty (u login_name je právě 1, u e-mailu seřazeno dle last_login_date DESC)
					$firstCandidateError = '';                           // Chybová hláška prvního kandidáta
					foreach ($userRows as $idx => $userRow) {            // Průchod kandidátními účty
						if (!empty($userRow['locked_until']) AND strtotime((string)$userRow['locked_until']) > time()) { // Kontrola uzamčení účtu
							if ($idx === 0) {                            // Chybu uzamčení si zapamatujeme u prvního účtu
								$firstCandidateError = "<div class='msg-err'>Účet je dočasně uzamčen z důvodu mnoha neúspěšných pokusů o přihlášení.</div>"; // Hláška uzamčení
							}
							continue;                                    // Zkusíme případný další účet se stejným e-mailem
						}
						if (!empty($userRow['inactive'])) {              // Kontrola deaktivovaného účtu
							if ($idx === 0) {                            // Zapamatování chyby deaktivace
								$firstCandidateError = "<div class='msg-err'>Tento účet je momentálně deaktivován.</div>"; // Hláška deaktivace
							}
							continue;                                    // Zkusíme případný další účet
						}
						if (isset($userRow['allow_local_login']) AND (int)$userRow['allow_local_login'] === 0) { // Kontrola zákazu lokálního hesla
							if ($idx === 0) {                            // Zapamatování chyby SSO
								$firstCandidateError = "<div class='msg-err'>Přihlášení jménem a heslem není povoleno. Použijte jednotné přihlášení (SSO).</div>"; // Hláška SSO
							}
							continue;                                    // Zkusíme případný další účet
						}

						$hash = trim((string)$userRow['password_hash']); // Hash hesla kandidáta
						if ($hash !== '' AND password_verify($password, $hash)) { // Ověření shody hesla
							$isAuthenticated = true;                     // Úspěšné ověření hesla
							$userUuid = trim((string)$userRow['original']); // Převzetí originálního UUID účtu
							$firstCandidateError = '';                   // Vyčištění případné chyby předchozího kandidáta
							break;                                       // Máme platný účet, ukončíme hledání
						} else {
							// Inkrementace neúspěšných pokusů a případné uzamčení na 15 minut po 5 pokusech
							$safeUserOriginal = guidliteral(trim((string)$userRow['original'])); // SQL literál UUID účtu
							sqlrun("
								UPDATE user_account 
								SET failed_login_attempts = ISNULL(failed_login_attempts, 0) + 1,
									locked_until = CASE 
										WHEN ISNULL(failed_login_attempts, 0) + 1 >= 5 THEN DATEADD(minute, 15, GETDATE()) 
										ELSE locked_until 
									END
								WHERE original = {$safeUserOriginal} AND record_type = 'A'
							");                                          // Zápis neúspěšného pokusu o přihlášení
						}
					}

					if (!$isAuthenticated AND $firstCandidateError !== '') { // Pokud žádný účet neprošel a máme specifickou chybu
						$messageHtml = $firstCandidateError;             // Zobrazení specifické chyby stavu účtu
					}
				}
			}
		}
		
		// C. Vyhodnocení stavu a volání uložené procedury
		if ($isAuthenticated AND $messageHtml === '') {                  // Pokud autentizace proběhla úspěšně
			// Převod hodnot na bezpečné literály pro MSSQL syntaxi
			$safeSid = charliteral($SID, 100);                           // SQL literál session ID
			$safeUserUuid = guidliteral($userUuid);                      // SQL literál UUID účtu
			$safeIp = charliteral(get_client_ip_path(), 200);            // SQL literál IP adresy klienta
			
			// Volání T-SQL procedury, která zapíše kontext do wwwsession (přihlásí do last_login_organization)
			$procSql = "EXEC p_set_login @user_uuid = {$safeUserUuid}, @wwwsession = {$safeSid}, @client_ip = {$safeIp}"; // Volání p_set_login
			
			if (sqlrun($procSql)) {                                      // Spuštění přihlašovací procedury
				
				// D. Zpracování "Zůstat přihlášen" (Remember Me token)
				$rememberMe = (int)getinput('remember_me');              // Příznak trvalého přihlášení
				if ($rememberMe === 1) {                                 // Pokud uživatel zaškrtl Zůstat přihlášen
					try {
						// Generování kryptograficky silných tokenů
						$selector = bin2hex(random_bytes(12));           // Veřejný identifikátor tokenu
						$validator = bin2hex(random_bytes(32));          // Tajný validátor tokenu
						$hashedValidator = hash('sha256', $validator);   // SHA-256 hash validátoru pro DB
						
						// Platnost 30 dní
						$expiresTime = time() + (30 * 24 * 60 * 60);     // Čas expirace v sekundách
						$expiresStr = date('Y-m-d H:i:s', $expiresTime); // Formátované datum expirace
						
						// Bezpečná příprava parametrů pro SQL
						$safeSelector = charliteral($selector, 64);      // SQL literál selectoru
						$safeHashedValidator = charliteral($hashedValidator, 255); // SQL literál hashe validátoru
						$safeExpires = charliteral($expiresStr);         // SQL literál expirace
						$safeUserAgent = charliteral($_SERVER['HTTP_USER_AGENT'] ?? '', 500); // SQL literál prohlížeče
						$safeLastUsed = charliteral(date('Y-m-d H:i:s')); // SQL literál času vytvoření
						
						$sqlToken = "
							INSERT INTO auth_tokens (
								selector, user_account_uuid, hashed_validator, 
								expires, ip_address, user_agent, last_used
							) VALUES (
								{$safeSelector}, {$safeUserUuid}, {$safeHashedValidator}, 
								{$safeExpires}, {$safeIp}, {$safeUserAgent}, {$safeLastUsed}
							)
						";                                               // Dotaz pro uložení trvalého tokenu
						
						if (sqlrun($sqlToken)) {                         // Zápis tokenu do databáze
							// Odeslání HTTP hlavičky s cookie
							$cookieOptions = [                           // Nastavení bezpečnostních parametrů cookie
								'expires' => $expiresTime,               // Čas vypršení platnosti cookie
								'path' => '/',                           // Dostupnost v celé doméně
								'secure' => $isHttps,                    // True pro HTTPS komunikaci
								'httponly' => true,                      // Skryje cookie před JavaScriptem (prevence XSS)
								'samesite' => 'Strict'                   // Ochrana proti CSRF
							];                                           // Konec nastavení cookie
							setcookie('ramses_remember', $selector . ':' . $validator, $cookieOptions); // Uložení cookie
						}
					} catch (Exception $e) {                             // Zachycení chyby generátoru náhodných bajtů
						// Při chybě generátoru random_bytes se tiše přeskočí zápis a uživatel 
						// bude přihlášen standardně bez trvalé cookie.
					}
				}
				
				// PRG Pattern: Po úspěšném POST přesměrujeme na GET hlavní stránky
				header("Location: index.php?page=page_main");
				exit;
			} else {
				$messageHtml = "<div class='msg-err'>Kritická chyba: Uložená procedura p_set_login selhala při zakládání sezení.</div>"; // Chyba procedury
			}
		} elseif (!$isAuthenticated AND $messageHtml === '') {           // Pokud se ověření nezdařilo
			// Schválně nespecifikujeme, zda je špatné jméno nebo heslo (prevence enumerace uživatelů)
			$messageHtml = "<div class='msg-err'>Nesprávné přihlašovací jméno (e-mail) nebo heslo.</div>"; // Obecná chybová hláška
		}
	}
}

// Frontend disabling v případě nezabezpečeného HTTP
$disabledAttr = $blockAction ? 'disabled' : '';                          // HTML atribut pro deaktivaci prvků
$safeCurrentLang = htmlspecialchars($current_lang);                      // Ošetřený kód jazyka pro HTML tag
$langSelectorHtml = $lang_manager->render_language_selector('index.php?page=page_login'); // HTML přepínače jazyků
$safePostLogin = htmlspecialchars((string)($_POST['login_name'] ?? '')); // Ošetřená hodnota zadaného loginu
$safeGoogleUrl = htmlspecialchars($googleAuthUrl);                       // Ošetřená URL pro Google přihlášení
?>
<!DOCTYPE html>
<html lang="<?php echo $safeCurrentLang; // Výpis jazyka dokumentu ?>">
<head>
	<meta charset="utf-8">
	<title>Přihlášení - BCM Osiris</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 50px; position: relative; }
		.container { background-color: #fff; padding: 30px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); max-width: 400px; margin: auto; }
		h1 { font-size: 22px; color: #333; margin-top: 0; text-align: center; margin-bottom: 25px; }
		label { display: block; margin-top: 15px; margin-bottom: 5px; color: #666; font-weight: bold; }
		input[type="text"], input[type="password"] { width: 100%; padding: 10px; border: 1px solid #ccc; box-sizing: border-box; border-radius: 3px; }
		button { margin-top: 25px; padding: 12px 15px; background-color: #004488; color: #fff; border: none; border-radius: 3px; cursor: pointer; width: 100%; font-size: 16px; font-weight: bold; }
		button:hover { background-color: #003366; }
		button:disabled { background-color: #999; cursor: not-allowed; }
		input:disabled { background-color: #eee; cursor: not-allowed; }
		.message { margin-bottom: 20px; }
		.msg-err { color: #b71c1c; font-weight: bold; padding: 10px; border-left: 4px solid #b71c1c; background-color: #ffebee; line-height: 1.4; }
		.forgot-pwd { display: block; text-align: center; margin-top: 20px; font-size: 14px; color: #004488; text-decoration: none; }
		.forgot-pwd:hover { text-decoration: underline; }
		
		/* Přidané CSS třídy pro oddělovač, Google SSO tlačítko a Remember Me */
		.divider { display: flex; align-items: center; text-align: center; margin: 25px 0 15px 0; color: #999; }
		.divider::before, .divider::after { content: ''; flex: 1; border-bottom: 1px solid #ddd; }
		.divider span { padding: 0 10px; font-size: 14px; }
		.google-btn { display: block; text-align: center; padding: 11px 15px; background-color: #fff; color: #333; border: 1px solid #ccc; border-radius: 3px; cursor: pointer; width: 100%; font-size: 16px; font-weight: bold; text-decoration: none; box-sizing: border-box; }
		.google-btn:hover { background-color: #f9f9f9; }
		.google-btn img { vertical-align: middle; height: 18px; margin-right: 10px; margin-top: -3px; }
		
		.remember-container { display: flex; align-items: center; margin-top: 15px; margin-bottom: 5px; }
		.remember-container input[type="checkbox"] { width: auto; margin-right: 10px; margin-top: 0; cursor: pointer; }
		.remember-container label { margin: 0; font-weight: normal; color: #333; cursor: pointer; }
		
		/* Obalový prvek pro výběr jazyka v pravém horním rohu */
		.lang-switcher-wrapper { position: absolute; top: 15px; right: 20px; }
	</style>
</head>
<body>
	<!-- Integrace vizuální komponenty z language_manageru pro přepínání -->
	<div class="lang-switcher-wrapper">
		<?php echo $langSelectorHtml; // Vykreslení přepínače jazyků ?>
	</div>

	<div class="container">
		<h1>Přihlášení do systému RAMSES</h1>
		
		<?php if ($messageHtml !== ''): // Kontrola přítomnosti chybové hlášky ?>
			<div class="message"><?php echo $messageHtml; // Výpis chybové hlášky ?></div>
		<?php endif; ?>
		
		<form method="POST" action="index.php?page=page_login">
			<label for="login_name">Uživatelské jméno nebo e-mail:</label>
			<input type="text" id="login_name" name="login_name" required value="<?php echo $safePostLogin; // Předvyplněný login ?>" <?php echo $disabledAttr; // Atribut blokace ?>>
			
			<label for="password">Heslo:</label>
			<input type="password" id="password" name="password" required <?php echo $disabledAttr; // Atribut blokace ?>>
			
			<div class="remember-container">
				<input type="checkbox" id="remember_me" name="remember_me" value="1" <?php echo $disabledAttr; // Atribut blokace ?>>
				<label for="remember_me">Zůstat přihlášen na tomto zařízení</label>
			</div>
			
			<button type="submit" <?php echo $disabledAttr; // Atribut blokace tlačítka ?>>Přihlásit se</button>
		</form>

		<!-- Vygenerování sekce s Google tlačítkem, pokud je nakonfigurováno API -->
		<?php if ($googleAuthUrl !== ''): // Kontrola dostupnosti Google SSO ?>
			<div class="divider"><span>Nebo</span></div>
			<a href="<?php echo $safeGoogleUrl; // Odkaz na Google OAuth ?>" class="google-btn">
				<img src="https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg" alt="Google">
				Přihlásit se přes Google
			</a>
		<?php endif; ?>
		
		<a href="index.php?page=page_password_reset" class="forgot-pwd">Zapomněli jste heslo?</a>
	</div>
</body>
</html>