<?php
/**
 * =============================================================================
 * Stránka: sysadmin_activation.php
 * Účel: Zcela samostatná stránka pro odeslání aktivačního e-mailu / reset hesla.
 * 
 * Vliv a kontext:
 * - Skript je nezávislý na index.php. Načítá pouze config.php (kde se očekává 
 *   nastavení globálních proměnných a navázání spojení do $dbconnection) 
 *   a RamsesLib.php.
 * - Formulář umožňuje zadat login_name.
 * - Skript vyhledá uživatele, vygeneruje token a uloží ho do activation_token.
 * - Následně odešle e-mail s odkazem.
 * =============================================================================
 */

declare(strict_types=1);

// 1. Načtení konfigurace a knihoven
// Předpokládáme, že config.php nastaví $dbms, $dbconnection a případně $charset.
require_once 'config.php';
require_once 'RamsesLib.php';

// Globální proměnné z RamsesLib a configu
global $dbms, $dbconnection, $charset;

$messageHtml = '';
$isPost = ($_SERVER['REQUEST_METHOD'] === 'POST');

// 2. Zpracování odeslaného formuláře
if ($isPost) {
	// Použijeme getinput() z RamsesLib. Očekáváme, že z $_POST získáme login_name.
	$rawLogin = trim((string)getinput('login_name'));
	
	if (empty($rawLogin)) {
		$messageHtml = "<div style='color: red; font-weight: bold;'>Prosím, zadejte přihlašovací jméno.</div>";
	} else {
		// Bezpečná sanitizace pro SQL
		$safeLogin = charliteral($rawLogin, 100);

		// Vyhledání aktivního uživatele v DB (využíváme RamsesLib)
		$sqlUser = "
			SELECT original, email, first_name, last_name 
			FROM user_account 
			WHERE login_name = $safeLogin 
				AND record_type = 'A' 
				AND inactive = 0 
				AND removed = 0
		";
		
		$userRow = sqlfirstrow($sqlUser);

		if (!$userRow || empty(trim((string)$userRow['email']))) {
			// Z bezpečnostních důvodů (proti enumeraci) lze zobrazit generickou hlášku, 
			// zde pro administrátora uvádíme přesný stav.
			$messageHtml = "<div style='color: red; font-weight: bold;'>Uživatel nebyl nalezen nebo nemá nastavenou e-mailovou adresu.</div>";
		} else {
			$adminEmail = trim($userRow['email']);
			$userId = $userRow['original'];
			
			// Generování tokenu (32 bytů = 64 hex znaků)
			try {
				$plainToken = bin2hex(random_bytes(32));
			} catch (\Exception $e) {
				fatal_error("Chyba krypto-generátoru", $e->getMessage());
			}

			// Příprava dat pro databázi
			$tokenHash = password_hash($plainToken, PASSWORD_DEFAULT);
			$expiresAt = date('Y-m-d H:i:s', strtotime('+24 hours'));
			$tokenUuid = newid(); // Z RamsesLib

			// Sanitizace dat
			$safeTokenUuid = guidliteral($tokenUuid);
			$safeHash = charliteral($tokenHash, 255);
			$safePurpose = charliteral('PASSWORD_RESET', 50); 
			$safeExpires = dateliteral($expiresAt);
			$safeIp = charliteral(get_client_ip_path(), 200);
			$safeUserId = guidliteral($userId);

			// Vložení do databáze (funkce sqlrun)
			$sqlInsert = "
				INSERT INTO activation_token (
					uuid, token_hash, token_purpose, user_account, 
					expires_at, is_used, request_ip, 
					date_created, date_modified, removed
				) VALUES (
					$safeTokenUuid, $safeHash, $safePurpose, $safeUserId, 
					$safeExpires, 0, $safeIp, 
					GETDATE(), GETDATE(), 0
				)
			";

			if (!sqlrun($sqlInsert)) {
				fatal_error("Chyba DB", "Uložení tokenu selhalo.");
			}

			// Sestavení URL pro odkaz (včetně detekce HTTPS)
			$protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || $_SERVER['SERVER_PORT'] == 443 ? "https://" : "http://";
			$baseUrl = $protocol . $_SERVER['HTTP_HOST'] . dirname($_SERVER['REQUEST_URI']) . '/';
			
			// Odkaz směřuje na skript, který bude přijímat samotné heslo (např. sysadmin_reset.php)
			$activationLink = $baseUrl . "sysadmin_reset.php?token=" . urlencode($plainToken) . "&purpose=PASSWORD_RESET";

			// Odeslání e-mailu
			$subject = "Aktivace účtu / Obnova hesla v systému RAMSES";
			$message = "Dobrý den,\n\n";
			$message .= "byl vyžádán přístup pro nastavení hesla k vašemu účtu '$rawLogin'.\n";
			$message .= "Pro nastavení hesla klikněte na odkaz níže:\n\n";
			$message .= $activationLink . "\n\n";
			$message .= "Odkaz platí 24 hodin.\n";
			$message .= "Pokud jste akci nevyžádali, ignorujte tento e-mail.\n";
			
			$mailCharset = ($charset === 'windows-1250' ? 'windows-1250' : 'utf-8');
			$headers = "From: system@ramses.local\r\n";
			$headers .= "Content-Type: text/plain; charset=" . $mailCharset . "\r\n";

			if (@mail($adminEmail, $subject, $message, $headers)) {
				$messageHtml = "<div style='color: green; font-weight: bold;'>Aktivační e-mail byl úspěšně odeslán na adresu účtu.</div>";
			} else {
				$messageHtml = "<div style='color: red; font-weight: bold;'>Chyba při odesílání e-mailu. Zkontrolujte SMTP.</div>";
			}
		}
	}
}

// HTML Výstup samostatné stránky
$pageCharset = isset($charset) && $charset ? $charset : 'utf-8';
?>
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="<?php echo htmlspecialchars($pageCharset); ?>">
	<title>Reset hesla / Aktivace systému</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 50px; }
		.container { background-color: #fff; padding: 30px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); max-width: 400px; margin: auto; }
		h1 { font-size: 20px; color: #333; }
		label { display: block; margin-top: 15px; margin-bottom: 5px; color: #666; }
		input[type="text"] { width: 100%; padding: 10px; border: 1px solid #ccc; box-sizing: border-box; }
		button { margin-top: 20px; padding: 10px 15px; background-color: #004488; color: #fff; border: none; cursor: pointer; width: 100%; }
		button:hover { background-color: #003366; }
		.message { margin-bottom: 20px; }
	</style>
</head>
<body>
	<div class="container">
		<h1>Vyžádání nového hesla</h1>
		
		<?php if ($messageHtml): ?>
			<div class="message"><?php echo $messageHtml; ?></div>
		<?php endif; ?>

		<form method="POST" action="">
			<label for="login_name">Přihlašovací jméno (např. system):</label>
			<input type="text" id="login_name" name="login_name" required value="<?php echo htmlspecialchars($_POST['login_name'] ?? 'system'); ?>">
			
			<button type="submit">Odeslat aktivační e-mail</button>
		</form>
	</div>
</body>
</html>