<?php
/**
 * =============================================================================
 * Stránka: password_reset.php
 * Účel: Univerzální stránka pro vyžádání obnovy hesla komukoliv.
 * 
 * Vliv a kontext:
 * - Skript je nezávislý na index.php. Načítá pouze config.php a RamsesLib.php.
 * - Formulář umožňuje uživateli zadat svůj e-mail (nebo login_name).
 * - Skript vyhledá aktivního uživatele v user_account, vygeneruje token
 *   a uloží ho do activation_token.
 * - Načte SMTP konfiguraci z lokálního souboru config.php (přes globální proměnné).
 * - Pokud je definována proměnná $smtp_forward, přesměruje e-mail na tuto 
 *   testovací adresu.
 * =============================================================================
 */

declare(strict_types=1);

// Načtení Composer autoloaderu (pokud používáš Composer)
// require_once 'vendor/autoload.php';

// Pokud nepoužíváš Composer, includuj PHPMailer ručně:
/*
require_once 'PHPMailer/src/Exception.php';
require_once 'PHPMailer/src/PHPMailer.php';
require_once 'PHPMailer/src/SMTP.php';
*/

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

// 1. Načtení konfigurace a knihoven
$CONFIG_SERVER_NAME=explode(':',$_SERVER['HTTP_HOST'])[0];
require_once "config_{$CONFIG_SERVER_NAME}.php";
require_once 'RamsesLib.php';

// Globální proměnné z RamsesLib a configu
global $dbms, $dbconnection, $charset;
global $smtp_server, $smtp_port, $smtp_user, $smtp_password, $smtp_sender, $smtp_sender_name, $smtp_forward;

$messageHtml = '';
$isPost = ($_SERVER['REQUEST_METHOD'] === 'POST');

// 2. Zpracování odeslaného formuláře
if ($isPost) {
	// Použijeme getinput() z RamsesLib. Očekáváme z $_POST login nebo email.
	$rawInput = trim((string)getinput('login_or_email'));
	
	if (empty($rawInput)) {
		$messageHtml = "<div style='color: red; font-weight: bold;'>Prosím, zadejte přihlašovací jméno nebo e-mail.</div>";
	} else {
		// Bezpečná sanitizace pro SQL
		$safeInput = charliteral($rawInput, 200);

		// Hledáme jakéhokoliv aktivního uživatele buď podle e-mailu nebo podle login_name
		$sqlUser = "
			SELECT original, login_name, first_name, last_name, email 
			FROM user_account 
			WHERE (email = $safeInput OR login_name = $safeInput)
				AND record_type = 'A' 
				AND inactive = 0 
				AND removed = 0
		";
		
		$userRow = sqlfirstrow($sqlUser);

		if (!$userRow || empty(trim((string)$userRow['email']))) {
			$messageHtml = "<div style='color: red; font-weight: bold;'>Účet s tímto jménem či e-mailem nebyl nalezen, nebo nemá e-mail nastaven.</div>";
		} else {
			$userEmail = trim($userRow['email']);
			$loginName = trim($userRow['login_name']);
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
			$tokenUuid = newid(); 

			// Sanitizace dat pro uložení do transakční tabulky
			$safeTokenUuid = guidliteral($tokenUuid);
			$safeHash = charliteral($tokenHash, 255);
			$safePurpose = charliteral('PASSWORD_RESET', 50); 
			$safeExpires = dateliteral($expiresAt);
			$safeIp = charliteral(get_client_ip_path(), 200);
			$safeUserId = guidliteral($userId);

			// Vložení do databáze (záznam nepodléhá SSC)
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

			if (empty($smtp_server)) {
				fatal_error("Chyba konfigurace", "SMTP server není nastaven v config.php.");
			}

			// Sestavení URL pro odkaz (včetně detekce HTTPS)
			$protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || $_SERVER['SERVER_PORT'] == 443 ? "https://" : "http://";
			$baseUrl = $protocol . $_SERVER['HTTP_HOST'] . dirname($_SERVER['REQUEST_URI']) . '/';
			
			$activationLink = $baseUrl . "password_reset.php?token=" . urlencode($plainToken) . "&purpose=PASSWORD_RESET";

			// Příprava e-mailu pomocí PHPMailer
			$mail = new PHPMailer(true);

			try {
				// Nastavení SMTP serveru
				$mail->isSMTP();
				$mail->Host = trim((string)$smtp_server);
				$mail->Port = (int)$smtp_port;
				
				// Zpracování autentizace z config.php
				$smtpUsername = trim((string)$smtp_user);
				if (!empty($smtpUsername)) {
					$mail->SMTPAuth = true;
					$mail->Username = $smtpUsername;
					$mail->Password = trim((string)$smtp_password);
				} else {
					$mail->SMTPAuth = false;
				}
				
				$mail->CharSet = 'UTF-8';
				$mail->setFrom(trim((string)$smtp_sender), trim((string)$smtp_sender_name));
				
				// Logika přesměrování (Forward) pro testování
				$mailBodyPrefix = "";
				if (!empty(trim((string)$smtp_forward))) {
					$actualRecipient = trim((string)$smtp_forward);
					$mail->Subject = "[TEST FORWARD] Obnova hesla v systému RAMSES";
					
					$mailBodyPrefix = "=========================================\n"
									. "UPOZORNĚNÍ PRO TESTOVÁNÍ:\n"
									. "Tento e-mail byl přesměrován na testovací adresu.\n"
									. "Původní příjemce: {$userEmail}\n"
									. "=========================================\n\n";
				} else {
					$actualRecipient = $userEmail;
					$mail->Subject = "Obnova hesla v systému RAMSES";
				}
				
				$mail->addAddress($actualRecipient);

				$mail->Body = $mailBodyPrefix 
							. "Dobrý den,\n\n"
							. "byl vyžádán odkaz pro nastavení nového hesla k vašemu účtu '$loginName'.\n"
							. "Pro nastavení hesla klikněte na odkaz níže:\n\n"
							. $activationLink . "\n\n"
							. "Odkaz platí 24 hodin.\n"
							. "Pokud jste akci nevyžádali, ignorujte prosím tento e-mail.\n";

				$mail->send();
				$messageHtml = "<div style='color: green; font-weight: bold;'>E-mail s instrukcemi pro obnovu hesla byl úspěšně odeslán.</div>";
			} catch (Exception $e) {
				$messageHtml = "<div style='color: red; font-weight: bold;'>Chyba při odesílání e-mailu: {$mail->ErrorInfo}</div>";
			}
		}
	}
}

$pageCharset = isset($charset) && $charset ? $charset : 'utf-8';
?>
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="<?php echo htmlspecialchars($pageCharset); ?>">
	<title>Reset hesla do systému</title>
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
			<label for="login_or_email">Uživatelské jméno nebo e-mail:</label>
			<input type="text" id="login_or_email" name="login_or_email" required value="<?php echo htmlspecialchars($_POST['login_or_email'] ?? ''); ?>">
			
			<button type="submit">Odeslat odkaz</button>
		</form>
	</div>
</body>
</html>