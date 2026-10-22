<?php
/**
 * =============================================================================
 * Verze: 2026-10-22 16:15
 * Stránka: page_password_reset.php
 * Účel: Univerzální stránka pro vyžádání obnovy hesla (Fáze 1) 
 *       a následné nastavení nového hesla na základě tokenu (Fáze 2).
 * 
 * Vazby na okolí:
 * - Volána z centrálního routeru index.php při ?page=page_password_reset.
 * - Využívá language_manager pro volbu jazyka v pravém horním rohu.
 * - Pracuje s tabulkami activation_token, user_account a system_constant.
 * - Odesílá odkaz pro obnovu hesla pomocí funkce send_global_mail().
 * 
 * Změny:
 * 2026-10-22 16:15 - Sjednocení všech URL na prefix page_ (page_password_reset, page_login).
 *                  - Odstraněno duplicitní volání require_once "config.php".
 *                  - Doplněna podpora vyhledání účtu i při zadání e-mailu do pole loginu
 *                    (výběr naposledy přihlášeného účtu dle last_login_date DESC).
 *                  - Zapojen language_manager a striktně aplikována Anti-LaTeX pravidla
 *                    (OR/AND místo ||/&&, komentáře s českou diakritikou u všech řádků s $).
 * =============================================================================
 */

declare(strict_types=1);

// Vynucení UTF-8 kódování hlavičkou
header('Content-Type: text/html; charset=utf-8');

global $http_allowed;                                                    // Globální příznak povolení nezabezpečeného HTTP

// Inicializace správce jazyků a ošetření přepnutí jazyka
$requested_lang = (isset($_GET['set_lang']) AND is_string($_GET['set_lang'])) ? $_GET['set_lang'] : null; // Požadovaný jazyk z URL
$lang_manager = new language_manager($requested_lang);                   // Inicializace správce jazyků
$token_in_url = trim((string)getinput('token'));                         // Případný token v URL při přepnutí jazyka

if ($requested_lang !== null) {                                          // PRG přesměrování po změně jazyka
	$tok_suffix = ($token_in_url !== '') ? '&token=' . urlencode($token_in_url) : ''; // Zachování tokenu v URL
	header('Location: index.php?page=page_password_reset' . $tok_suffix); // Přesměrování na čistou URL adresu
	exit;                                                                // Ukončení běhu skriptu
}

$current_lang = $lang_manager->get_current_language();                   // Kód aktuálního jazyka
$messageHtml = '';                                                       // HTML chybové nebo potvrzovací zprávy
$isPost = (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST');               // Příznak odeslání formuláře metodou POST

// =========================================================================
// KONTROLA BEZPEČNOSTI (HTTP vs HTTPS)
// =========================================================================
$isHttps = ((!empty($_SERVER['HTTPS']) AND $_SERVER['HTTPS'] !== 'off') OR ($_SERVER['SERVER_PORT'] ?? 80) == 443); // Detekce HTTPS
$protocol = $isHttps ? "https://" : "http://";                           // Schéma protokolu pro sestavení odkazu

$securityWarningHtml = '';                                               // HTML varování při nezabezpečeném protokolu
$blockAction = false;                                                    // Příznak zablokování odeslání formuláře

// Pokud běžíme na HTTP a vývojář to v config.php explicitně nepovolil
if (!$isHttps AND empty($http_allowed)) {                                // Kontrola povolení HTTP v konfiguraci
	$securityWarningHtml = "
		<div class='msg-err' style='margin-bottom: 25px;'>
			<strong>Kritické bezpečnostní riziko:</strong> Komunikace probíhá přes nezabezpečený protokol HTTP. 
			Zadávaná hesla a citlivá data mohou být odposlechnuta a vyzrazena! Akce byla z bezpečnostních důvodů zablokována.
			<br><br>
			<em>(Pro ladění na lokálním PC nastavte proměnnou <code>&#36;http_allowed = 1;</code> v souboru config.php)</em>
		</div>";                                                         // Chybová hláška při nezabezpečeném HTTP
	$blockAction = true;                                                 // Zablokování akce
}

// Zablokujeme POST, pokud hrozí vyzrazení
if ($isPost AND $blockAction) {                                          // Zahození POST požadavku při blokaci
	$isPost = false;                                                     // Vypnutí zpracování POSTu
}

$token = $token_in_url;                                                  // Aktivní token z požadavku
$tokenValid = false;                                                     // Příznak platnosti tokenu
$userIdForReset = '';                                                    // UUID účtu, kterému se mění heslo
$tokenUuidForReset = '';                                                 // UUID záznamu tokenu v activation_token
$displayUserInfo = '';                                                   // Informace o uživateli pro zobrazení ve formuláři

if ($token !== '') {                                                     // Rozlišení Fáze 2 (s tokenem) a Fáze 1 (bez tokenu)
	// =========================================================================
	// FÁZE 2: UŽIVATEL PŘIŠEL Z E-MAILU S TOKENEM A CHCE NASTAVIT NOVÉ HESLO
	// =========================================================================

	$hashedToken = hash('sha256', $token);                               // SHA-256 hash přijatého tokenu
	$safeTokenHash = charliteral($hashedToken, 255);                     // SQL literál hashe tokenu
	$safePurpose = charliteral('PASSWORD_RESET', 50);                    // SQL literál účelu tokenu

	// Kontrola platnosti tokenu v databázi (musí být nepoužitý a neexpirovaný)
	$sqlToken = "
		SELECT uuid, user_account, expires_at 
		FROM activation_token 
		WHERE token_hash = {$safeTokenHash} 
			AND token_purpose = {$safePurpose} 
			AND is_used = 0 
			AND removed = 0 
			AND expires_at > GETDATE()
	";                                                                   // Dotaz na platný token v databázi
	
	$tokenRow = sqlfirstrow($sqlToken);                                  // Načtení tokenu přes sqlfirstrow()

	if (!empty($tokenRow)) {                                             // Pokud je token platný a neexpirovaný
		$tokenValid = true;                                              // Označení tokenu jako platného
		$userIdForReset = trim((string)$tokenRow['user_account']);       // UUID cílového uživatelského účtu
		$tokenUuidForReset = trim((string)$tokenRow['uuid']);            // Primární klíč tokenu
		
		// Zjištění informací o uživateli pro UI (UX vylepšení)
		$isSysAdmin = ($userIdForReset === '0x00' OR $userIdForReset === '00000000-0000-0000-0000-000000000000'); // Zda jde o účet admin
		if ($isSysAdmin) {                                               // Nouzový systémový administrátor
			$displayUserInfo = "Systémový administrátor (admin)";        // Popisek pro systémového administrátora
		} else {
			$safeUserIdForResetInfo = guidliteral($userIdForReset);      // SQL literál UUID uživatele
			$sqlUserInfo = "
				SELECT login_name, first_name, last_name, email 
				FROM user_account 
				WHERE original = {$safeUserIdForResetInfo} 
					AND record_type = 'A'
			";                                                           // Dotaz na identitu uživatele
			$userInfoRow = sqlfirstrow($sqlUserInfo);                    // Načtení údajů uživatele
			
			if (!empty($userInfoRow)) {                                  // Pokud byl uživatel nalezen
				$uLogin = htmlspecialchars(trim((string)$userInfoRow['login_name'])); // Ošetřený login
				$uEmail = htmlspecialchars(trim((string)$userInfoRow['email']));      // Ošetřený e-mail
				$uFirst = htmlspecialchars(trim((string)$userInfoRow['first_name'])); // Ošetřené jméno
				$uLast = htmlspecialchars(trim((string)$userInfoRow['last_name']));   // Ošetřené příjmení
				
				if ($uFirst !== '' OR $uLast !== '') {                   // Pokud má vyplněné jméno nebo příjmení
					$displayUserInfo = "{$uFirst} {$uLast} ({$uLogin}) &lt;{$uEmail}&gt;"; // Jméno, login a e-mail
				} else {
					$displayUserInfo = "{$uLogin} &lt;{$uEmail}&gt;";    // Login a e-mail
				}
			} else {
				$displayUserInfo = "Neznámý uživatel (ID: " . htmlspecialchars($userIdForReset) . ")"; // Fallback
			}
		}

		if ($isPost) {                                                   // Zpracování odeslaného nového hesla
			$newPwd = (string)getinput('new_password', 'raw');           // Nové heslo v surovém tvaru
			$newPwdConfirm = (string)getinput('new_password_confirm', 'raw'); // Potvrzení nového hesla

			if (strlen($newPwd) < 8) {                                   // Kontrola minimální délky hesla
				$messageHtml = "<div class='msg-err'>Heslo musí mít alespoň 8 znaků.</div>"; // Chyba krátkého hesla
			} elseif ($newPwd !== $newPwdConfirm) {                      // Kontrola shody obou hesel
				$messageHtml = "<div class='msg-err'>Zadaná hesla se neshodují.</div>"; // Chyba neshody hesel
			} else {
				$pwdHash = password_hash($newPwd, PASSWORD_DEFAULT);     // Выpočet bcrypt/argon2 hashe hesla
				$safePwdHash = charliteral($pwdHash, 255);               // SQL literál hashe hesla
				$safeTokenUuid = guidliteral($tokenUuidForReset);        // SQL literál UUID tokenu

				sqlrun("BEGIN TRAN");                                    // Zahájení transakce uložení hesla
				$updateSuccess = false;                                  // Výchozí stav uložení

				if ($isSysAdmin) {                                       // Aktualizace hesla pro Break-glass administrátora
					$updateSql = "
						UPDATE system_constant 
						SET system_admin_pwd = {$safePwdHash}, 
							date_modified = GETDATE()
					";                                                   // SQL příkaz pro system_constant
					$updateSuccess = (bool)sqlrun($updateSql);           // Provedení aktualizace
				} else {
					// Aktualizace hesla pro běžného uživatele a reset chybových stavů
					$safeUserIdForUpdate = guidliteral($userIdForReset); // SQL literál UUID uživatele
					$updateSql = "
						UPDATE user_account 
						SET password_hash = {$safePwdHash}, 
							failed_login_attempts = 0, 
							locked_until = NULL, 
							require_password_change = 0,
							last_password_change = GETDATE(),
							date_modified = GETDATE()
						WHERE original = {$safeUserIdForUpdate} 
							AND record_type = 'A'
					";                                                   // SQL příkaz pro user_account
					$updateSuccess = (bool)sqlrun($updateSql);           // Provedení aktualizace účtu
				}

				if ($updateSuccess) {                                    // Pokud uložení hesla proběhlo úspěšně
					sqlrun("UPDATE activation_token SET is_used = 1, date_modified = GETDATE() WHERE uuid = {$safeTokenUuid}"); // Zneplatnění tokenu
					sqlrun("COMMIT");                                    // Potvrzení transakce
					
					$messageHtml = "<div class='msg-ok'>Heslo bylo úspěšně změněno. Nyní se můžete přihlásit do systému.</div>"; // Potvrzení
					$tokenValid = false;                                 // Skrytí formuláře po změně
				} else {
					sqlrun("ROLLBACK");                                  // Stornování transakce při chybě
					$messageHtml = "<div class='msg-err'>Kritická chyba: Uložení nového hesla do databáze selhalo.</div>"; // Chybová zpráva
				}
			}
		}
	} else {
		$messageHtml = "<div class='msg-err'>Tento odkaz pro obnovu hesla je neplatný nebo již vypršel. Vyžádejte si prosím nový.</div>"; // Neplatný token
	}

} else {
	// =========================================================================
	// FÁZE 1: VYŽÁDÁNÍ ODKAZU (ZADÁNÍ E-MAILU A VOLITELNĚ PŘIHLAŠOVACÍHO JMÉNA)
	// =========================================================================
	
	if ($isPost) {                                                       // Zpracování žádosti o zaslání odkazu
		$rawLogin = trim((string)getinput('login_name', 'raw'));         // Volitelně zadané přihlašovací jméno
		$rawEmail = trim((string)getinput('email', 'raw'));              // Zadaná e-mailová adresa
		
		if ($rawEmail === '') {                                          // E-mail musí být vždy vyplněn
			$messageHtml = "<div class='msg-err'>Prosím, zadejte e-mailovou adresu účtu.</div>"; // Chybová hláška
		} else {
			$safeLogin = charliteral($rawLogin, 200);                    // SQL literál přihlašovacího jména
			$safeEmail = charliteral($rawEmail, 200);                    // SQL literál e-mailu

			$sysadminEmail = '';                                         // E-mail systémového správce
			$sysAdminRow = sqlfirstrow("SELECT sysadmin_email FROM system_constant"); // Načtení e-mailu ze system_constant
			if (!empty($sysAdminRow) AND trim((string)$sysAdminRow['sysadmin_email']) !== '') { // Pokud je e-mail nastaven
				$sysadminEmail = trim((string)$sysAdminRow['sysadmin_email']); // Uložení e-mailu správce
			}

			$userEmail = '';                                             // Nalezený e-mail cílového účtu
			$loginName = '';                                             // Nalezené přihlašovací jméno účtu
			$userId = '';                                                // Nalezené UUID účtu

			// 1. Zjištění, zda se nejedná o vyžádání hesla pro System Admina (0x00)
			if (strtolower($rawLogin) === 'admin' AND $sysadminEmail !== '' AND strcasecmp($rawEmail, $sysadminEmail) === 0) { // Účet admin
				$userId = '0x00';                                        // Identifikátor systémového admina
				$loginName = 'admin';                                    // Login systémového admina
				$userEmail = $sysadminEmail;                             // E-mail systémového admina
			} else {
				// 2. Hledání standardního uživatele (pokud zadal login odlišný od e-mailu, filtrujeme i dle login_name,
				//    jinak vybereme naposledy přihlášený aktivní účet s tímto e-mailem stejně jako v page_login.php)
				$loginCond = ($rawLogin !== '' AND strcasecmp($rawLogin, $rawEmail) !== 0)
					? "AND login_name = {$safeLogin}"
					: "";                                                // Volitelná podmínka na přihlašovací jméno

				$sqlUser = "
					SELECT TOP 1 original, login_name, first_name, last_name, email 
					FROM user_account 
					WHERE email = {$safeEmail}
						AND email <> ''
						{$loginCond}
						AND record_type = 'A' 
						AND inactive = 0 
						AND removed = 0
					ORDER BY
						CASE WHEN last_login_date IS NULL THEN 1 ELSE 0 END ASC,
						last_login_date DESC,
						date_created DESC
				";                                                       // Dotaz na nejnověji používaný aktivní účet
				
				$userRow = sqlfirstrow($sqlUser);                        // Načtení nalezeného účtu

				if (!empty($userRow)) {                                  // Pokud byl aktivní účet nalezen
					$userId = trim((string)$userRow['original']);        // Originální UUID účtu
					$loginName = trim((string)$userRow['login_name']);   // Přihlašovací jméno účtu
					$userEmail = trim((string)$userRow['email']);        // E-mail účtu
				}
			}

			if ($userEmail === '') {                                     // Pokud žádný odpovídající účet neexistuje
				$messageHtml = "<div class='msg-err'>Účet s těmito údaji nebyl nalezen nebo je deaktivován.</div>"; // Obecná hláška
			} else {
				try {
					$plainToken = bin2hex(random_bytes(32));             // Vygenerování kryptografického tokenu
				} catch (\Exception $e) {                                // Zachycení chyby generátoru
					fatal_error("Chyba krypto-generátoru", $e->getMessage()); // Fatální chyba
				}

				$tokenHash = hash('sha256', $plainToken);                // SHA-256 hash tokenu pro uložení v DB
				$expiresAt = date('Y-m-d H:i:s', strtotime('+24 hours')); // Platnost tokenu 24 hodin
				$tokenUuid = newid();                                    // Nové UUID pro záznam tokenu

				$safeTokenUuid = guidliteral($tokenUuid);                // SQL literál UUID tokenu
				$safeHash = charliteral($tokenHash, 255);                // SQL literál hashe tokenu
				$safePurpose = charliteral('PASSWORD_RESET', 50);        // SQL literál účelu tokenu
				$safeExpires = dateliteral($expiresAt);                  // SQL literál času expirace
				$safeIp = charliteral(get_client_ip_path(), 45);         // SQL literál IP adresy žadatele
				$safeUserIdForInsert = ($userId === '0x00' OR $userId === '00000000-0000-0000-0000-000000000000') ? '0x00' : guidliteral($userId); // UUID účtu

				$sqlInsert = "
					INSERT INTO activation_token (
						uuid, token_hash, token_purpose, user_account, 
						expires_at, is_used, request_ip, 
						date_created, date_modified, removed
					) VALUES (
						{$safeTokenUuid}, {$safeHash}, {$safePurpose}, {$safeUserIdForInsert}, 
						{$safeExpires}, 0, {$safeIp}, 
						GETDATE(), GETDATE(), 0
					)
				";                                                       // Sestavení příkazu INSERT pro token

				if (!sqlrun($sqlInsert)) {                               // Uložení tokenu do databáze
					fatal_error("Chyba DB", "Uložení tokenu selhalo.");  // Chyba při zápisu tokenu
				}

				$reqUriDir = rtrim(dirname((string)($_SERVER['REQUEST_URI'] ?? '')), '/\\'); // Adresář aplikace z URI
				$baseUrl = $protocol . ($_SERVER['HTTP_HOST'] ?? 'localhost') . $reqUriDir . '/'; // Základní URL adresa
				$activationLink = $baseUrl . "index.php?page=page_password_reset&token=" . urlencode($plainToken); // Odkaz pro obnovu
				$safeLink = htmlspecialchars($activationLink);           // Ošetřený odkaz pro HTML tělo e-mailu
				$safeLoginName = htmlspecialchars($loginName);           // Ošetřené přihlašovací jméno pro e-mail

				$mailSubject = "Obnova hesla v systému RAMSES";          // Předmět odesílaného e-mailu
				$mailBody = "
					<div style='font-family: Arial, sans-serif;'>
						<p>Dobrý den,</p>
						<p>byl vyžádán odkaz pro nastavení nového hesla k vašemu účtu <strong>{$safeLoginName}</strong>.</p>
						<p>Pro nastavení hesla klikněte na odkaz níže:</p>
						<p><a href='{$safeLink}'>{$safeLink}</a></p>
						<p>Odkaz platí 24 hodin.</p>
						<p>Pokud jste akci nevyžádali, ignorujte prosím tento e-mail.</p>
					</div>
				";                                                       // HTML tělo e-mailu s odkazem

				if (send_global_mail($userEmail, $mailSubject, $mailBody, true)) { // Odeslání e-mailu přes PHPMailer
					$messageHtml = "<div class='msg-ok'>E-mail s instrukcemi pro obnovu hesla byl úspěšně odeslán. Zkontrolujte svou schránku.</div>"; // Úspěch
				} else {
					$messageHtml = "<div class='msg-err'>Chyba při odesílání e-mailu. Kontaktujte administrátora.</div>"; // Chyba SMTP
				}
			}
		}
	}
}

$disabledAttr = $blockAction ? 'disabled' : '';                          // HTML atribut pro deaktivaci prvků při HTTP
$safeCurrentLang = htmlspecialchars($current_lang);                      // Ošetřený kód jazyka pro tag html
$retUrl = 'index.php?page=page_password_reset' . ($token !== '' ? '&token=' . urlencode($token) : ''); // Návratová URL pro jazyk
$langSelectorHtml = $lang_manager->render_language_selector($retUrl);    // Vykreslení přepínače jazyků
$safeTokenVal = htmlspecialchars($token);                                // Ošetřený token do skrytého pole
$safePostLogin = htmlspecialchars((string)($_POST['login_name'] ?? '')); // Ošetřený předvyplněný login
$safePostEmail = htmlspecialchars((string)($_POST['email'] ?? ''));      // Ošetřený předvyplněný e-mail
?>
<!DOCTYPE html>
<html lang="<?php echo $safeCurrentLang; // Výpis kódu jazyka dokumentu ?>">
<head>
	<meta charset="utf-8">
	<title>Obnova hesla - BCM Osiris</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 50px; position: relative; }
		.container { background-color: #fff; padding: 30px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); max-width: 450px; margin: auto; }
		h1 { font-size: 22px; color: #333; margin-top: 0; }
		label { display: block; margin-top: 15px; margin-bottom: 5px; color: #666; font-weight: bold; }
		input[type="text"], input[type="email"], input[type="password"] { width: 100%; padding: 10px; border: 1px solid #ccc; box-sizing: border-box; border-radius: 3px; }
		button { margin-top: 25px; padding: 12px 15px; background-color: #004488; color: #fff; border: none; border-radius: 3px; cursor: pointer; width: 100%; font-size: 16px; font-weight: bold; }
		button:hover { background-color: #003366; }
		button:disabled { background-color: #999; cursor: not-allowed; }
		input:disabled { background-color: #eee; cursor: not-allowed; }
		.message { margin-bottom: 20px; }
		.msg-err { color: #b71c1c; font-weight: bold; padding: 10px; border-left: 4px solid #b71c1c; background-color: #ffebee; line-height: 1.4; }
		.msg-ok { color: #1b5e20; font-weight: bold; padding: 10px; border-left: 4px solid #1b5e20; background-color: #e8f5e9; }
		.back-link { display: block; text-align: center; margin-top: 20px; font-size: 14px; color: #004488; text-decoration: none; }
		.back-link:hover { text-decoration: underline; }
		.user-identity-box { background-color: #e9f2fa; border-left: 4px solid #004488; padding: 12px; margin-top: 10px; margin-bottom: 20px; font-weight: bold; color: #004488; border-radius: 0 3px 3px 0; word-break: break-all; }
		.lang-switcher-wrapper { position: absolute; top: 15px; right: 20px; }
	</style>
</head>
<body>
	<div class="lang-switcher-wrapper">
		<?php echo $langSelectorHtml; // Vykreslení přepínače jazyků ?>
	</div>

	<div class="container">
		
		<?php if ($securityWarningHtml !== ''): // Kontrola přítomnosti bezpečnostního varování ?>
			<?php echo $securityWarningHtml; // Výpis bezpečnostního varování ?>
		<?php endif; ?>

		<?php if ($messageHtml !== ''): // Kontrola přítomnosti stavové zprávy ?>
			<div class="message"><?php echo $messageHtml; // Výpis stavové zprávy ?></div>
		<?php endif; ?>

		<?php if ($token !== '' AND $tokenValid): // Fáze 2: Formulář pro zadání nového hesla ?>
			<h1>Nastavení nového hesla</h1>
			
			<p style="color: #555; font-size: 14px; margin-bottom: 5px;">Měníte heslo pro účet:</p>
			<div class="user-identity-box">
				<?php echo $displayUserInfo; // Výpis identifikace účtu ?>
			</div>

			<p style="color: #555; font-size: 14px;">Zadejte své nové heslo. Z bezpečnostních důvodů musí obsahovat minimálně 8 znaků.</p>
			
			<form method="POST" action="index.php?page=page_password_reset">
				<input type="hidden" name="token" value="<?php echo $safeTokenVal; // Skrytý token pro Fázi 2 ?>">
				
				<label for="new_password">Nové heslo:</label>
				<input type="password" id="new_password" name="new_password" required minlength="8" <?php echo $disabledAttr; // Případná blokace ?>>
				
				<label for="new_password_confirm">Potvrzení nového hesla:</label>
				<input type="password" id="new_password_confirm" name="new_password_confirm" required minlength="8" <?php echo $disabledAttr; // Případná blokace ?>>
				
				<button type="submit" <?php echo $disabledAttr; // Případná blokace tlačítka ?>>Uložit heslo</button>
			</form>

		<?php elseif ($token === ''): // Fáze 1: Formulář pro vyžádání odkazu ?>
			<h1>Obnova zapomenutého hesla</h1>
			<p style="color: #555; font-size: 14px;">Zadejte svou e-mailovou adresu (a volitelně uživatelské jméno). Na e-mail vám bude zaslán odkaz k nastavení nového hesla.</p>
			<form method="POST" action="index.php?page=page_password_reset">
				<label for="email">E-mailová adresa: *</label>
				<input type="email" id="email" name="email" required value="<?php echo $safePostEmail; // Předvyplněný e-mail ?>" <?php echo $disabledAttr; // Případná blokace ?>>

				<label for="login_name">Uživatelské jméno (volitelné):</label>
				<input type="text" id="login_name" name="login_name" value="<?php echo $safePostLogin; // Předvyplněný login ?>" <?php echo $disabledAttr; // Případná blokace ?>>
				
				<button type="submit" <?php echo $disabledAttr; // Případná blokace tlačítka ?>>Odeslat odkaz</button>
			</form>
		<?php endif; ?>
		
		<a href="index.php?page=page_login" class="back-link">Zpět na úvodní obrazovku (Přihlášení)</a>
	</div>
</body>
</html>