<?php
/**
 * =============================================================================
 * Stránka: password_reset.php
 * Účel: Univerzální stránka pro vyžádání obnovy hesla komukoliv.
 * =============================================================================
 */

declare(strict_types=1);

// Vynucení UTF-8 kódování hlavičkou pro jistotu
header('Content-Type: text/html; charset=utf-8');

// 1. Načtení konfigurace
// Soubor config.php automaticky natahuje RamsesLib.php, send_global_mail.php 
// a inicializuje připojení k databázi.
require_once "config.php";

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

		// Zjištění e-mailu pro sysadmina z tabulky system_constant (nultý bod / break-glass)
		$sysadminEmail = '';
		$sqlSysAdmin = "SELECT sysadmin_email FROM system_constant";
		$sysAdminRow = sqlfirstrow($sqlSysAdmin);
		if ($sysAdminRow && !empty(trim((string)$sysAdminRow['sysadmin_email']))) {
			$sysadminEmail = trim((string)$sysAdminRow['sysadmin_email']);
		}

		// Hledáme aktivního uživatele v user_account
		$sqlUser = "
			SELECT original, login_name, first_name, last_name, email 
			FROM user_account 
			WHERE (email = $safeInput OR login_name = $safeInput)
				AND record_type = 'A' 
				AND inactive = 0 
				AND removed = 0
		";
		$userRow = sqlfirstrow($sqlUser);

		$userEmail = '';
		$loginName = '';
		$userId = '';

		if ($userRow) {
			$userId = trim((string)$userRow['original']);
			$loginName = trim((string)$userRow['login_name']);
			
			// Pokud systém identifikuje účet jako systémového admina (0x00), 
			// přesměrujeme e-mail na záchrannou adresu z tabulky system_constant.
			if ($userId === '00000000-0000-0000-0000-000000000000' || $userId === '0x00') {
				$userEmail = $sysadminEmail;
			} else {
				$userEmail = trim((string)$userRow['email']);
			}
		} elseif (!empty($sysadminEmail) && strcasecmp($rawInput, $sysadminEmail) === 0) {
			// Uživatel zadal e-mail odpovídající sysadminovi, i když účet 'system' primárně 
			// používá 'system@localhost'. Provedeme fallback na záchranný přístup.
			$userId = '0x00';
			$loginName = 'System Admin';
			$userEmail = $sysadminEmail;
		}

		if (empty($userEmail)) {
			$messageHtml = "<div style='color: red; font-weight: bold;'>Účet s tímto jménem či e-mailem nebyl nalezen, nebo nemá e-mail nastaven.</div>";
		} else {
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

			// Sanitizace dat pro uložení do transakční tabulky activation_token
			$safeTokenUuid = guidliteral($tokenUuid);
			$safeHash = charliteral($tokenHash, 255);
			$safePurpose = charliteral('PASSWORD_RESET', 50); 
			$safeExpires = dateliteral($expiresAt);
			$safeIp = charliteral(get_client_ip_path(), 200);
			$safeUserId = ($userId === '0x00') ? '0x00' : guidliteral($userId);

			// Vložení do databáze (záznam nepodléhá SSC)
			// Kód je plně kompatibilní s DB-compatibility 110 (SQL Server 2012)
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
			$baseUrl = $protocol . $_SERVER['HTTP_HOST'] . rtrim(dirname($_SERVER['REQUEST_URI']), '/\\') . '/';
			
			$activationLink = $baseUrl . "password_reset.php?token=" . urlencode($plainToken) . "&purpose=PASSWORD_RESET";

			// Příprava HTML e-mailu.
			$mailSubject = "Obnova hesla v systému RAMSES";
			$mailBody = "
				<div style='font-family: Arial, sans-serif;'>
					<p>Dobrý den,</p>
					<p>byl vyžádán odkaz pro nastavení nového hesla k vašemu účtu <strong>" . htmlspecialchars($loginName) . "</strong>.</p>
					<p>Pro nastavení hesla klikněte na odkaz níže:</p>
					<p><a href='" . htmlspecialchars($activationLink) . "'>" . htmlspecialchars($activationLink) . "</a></p>
					<p>Odkaz platí 24 hodin.</p>
					<p>Pokud jste akci nevyžádali, ignorujte prosím tento e-mail.</p>
				</div>
			";

			// Volání tvé globální funkce, která interně řeší inicializaci PHPMaileru i případný $smtp_forward
			if (send_global_mail($userEmail, $mailSubject, $mailBody, true)) {
				$messageHtml = "<div style='color: green; font-weight: bold;'>E-mail s instrukcemi pro obnovu hesla byl úspěšně odeslán.</div>";
			} else {
				$messageHtml = "<div style='color: red; font-weight: bold;'>Chyba při odesílání e-mailu. Zkontrolujte logy.</div>";
			}
		}
	}
}
?>
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="utf-8">
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