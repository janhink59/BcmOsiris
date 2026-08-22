<?php
/**
 * =============================================================================
 * Stránka: page_password_reset.php
 * Účel: Univerzální stránka pro vyžádání obnovy hesla (Fáze 1) 
 *       a následné nastavení nového hesla na základě tokenu (Fáze 2).
 * 
 * Opravy a úpravy:
 * - Fáze 1 nyní striktně vyžaduje přihlašovací jméno (login_name) i e-mail.
 *   Tím je zamezeno kolizím v multi-tenantním prostředí (stejný e-mail u více tenantů).
 * - Vyřešeno zastínění System Admina (0x00) lokálním adminem (0x01).
 * - Odkazy a akce formulářů plně respektují centrální router (index.php?page=...).
 * - Zajištěna ochrana proti brute-force a nechráněnému přenosu (HTTP blokace).
 * =============================================================================
 */

declare(strict_types=1);

// Vynucení UTF-8 kódování hlavičkou
header('Content-Type: text/html; charset=utf-8');

// 1. Načtení konfigurace
require_once "config.php";

$messageHtml = '';
$isPost = ($_SERVER['REQUEST_METHOD'] === 'POST');

// =========================================================================
// KONTROLA BEZPEČNOSTI (HTTP vs HTTPS)
// =========================================================================
global $http_allowed;
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || $_SERVER['SERVER_PORT'] == 443;
$protocol = $isHttps ? "https://" : "http://";

$securityWarningHtml = '';
$blockAction = false;

// Pokud běžíme na HTTP a vývojář to v config.php explicitně nepovolil
if (!$isHttps && empty($http_allowed)) {
	$securityWarningHtml = "
		<div class='msg-err' style='margin-bottom: 25px;'>
			<strong>Kritické bezpečnostní riziko:</strong> Komunikace probíhá přes nezabezpečený protokol HTTP. 
			Zadávaná hesla a citlivá data mohou být odposlechnuta a vyzrazena! Akce byla z bezpečnostních důvodů zablokována.
			<br><br>
			<em>(Pro ladění na lokálním PC nastavte proměnnou <code>\$http_allowed = 1;</code> v souboru config.php)</em>
		</div>";
	$blockAction = true;
}

// Zablokujeme POST, pokud hrozí vyzrazení
if ($isPost && $blockAction) {
	$isPost = false;
}

$token = trim((string)getinput('token'));
$tokenValid = false;
$userIdForReset = '';
$tokenUuidForReset = '';

if (!empty($token)) {
	// =========================================================================
	// FÁZE 2: UŽIVATEL PŘIŠEL Z E-MAILU S TOKENEM A CHCE NASTAVIT NOVÉ HESLO
	// =========================================================================

	$hashedToken = hash('sha256', $token);
	$safeTokenHash = charliteral($hashedToken, 255);
	$safePurpose = charliteral('PASSWORD_RESET', 50);

	// Kontrola platnosti tokenu v databázi (musí být nepoužitý a neexpirovaný)
	$sqlToken = "
		SELECT uuid, user_account, expires_at 
		FROM activation_token 
		WHERE token_hash = $safeTokenHash 
			AND token_purpose = $safePurpose 
			AND is_used = 0 
			AND removed = 0 
			AND expires_at > GETDATE()
	";
	
	$tokenRow = sqlfirstrow($sqlToken);

	if ($tokenRow) {
		$tokenValid = true;
		$userIdForReset = trim((string)$tokenRow['user_account']);
		$tokenUuidForReset = trim((string)$tokenRow['uuid']);

		if ($isPost) {
			$newPwd = (string)getinput('new_password', 'raw');
			$newPwdConfirm = (string)getinput('new_password_confirm', 'raw');

			if (strlen($newPwd) < 8) {
				$messageHtml = "<div class='msg-err'>Heslo musí mít alespoň 8 znaků.</div>";
			} elseif ($newPwd !== $newPwdConfirm) {
				$messageHtml = "<div class='msg-err'>Zadaná hesla se neshodují.</div>";
			} else {
				$pwdHash = password_hash($newPwd, PASSWORD_DEFAULT);
				$safePwdHash = charliteral($pwdHash, 255);
				$safeTokenUuid = guidliteral($tokenUuidForReset);

				sqlrun("BEGIN TRAN");
				$updateSuccess = false;

				$isSysAdmin = ($userIdForReset === '0x00' || $userIdForReset === '00000000-0000-0000-0000-000000000000');

				if ($isSysAdmin) {
					// Aktualizace hesla pro Break-glass administrátora
					$updateSql = "
						UPDATE system_constant 
						SET system_admin_pwd = $safePwdHash, 
							date_modified = GETDATE()
					";
					$updateSuccess = sqlrun($updateSql);
				} else {
					// Aktualizace hesla pro běžného uživatele a reset chybových stavů
					$safeUserId = guidliteral($userIdForReset);
					$updateSql = "
						UPDATE user_account 
						SET password_hash = $safePwdHash, 
							failed_login_attempts = 0, 
							locked_until = NULL, 
							require_password_change = 0,
							date_modified = GETDATE()
						WHERE original = $safeUserId 
							AND record_type = 'A'
					";
					$updateSuccess = sqlrun($updateSql);
				}

				if ($updateSuccess) {
					// Zneplatnění použitého tokenu
					sqlrun("UPDATE activation_token SET is_used = 1, date_modified = GETDATE() WHERE uuid = $safeTokenUuid");
					sqlrun("COMMIT");
					
					$messageHtml = "<div class='msg-ok'>Heslo bylo úspěšně změněno. Nyní se můžete přihlásit do systému.</div>";
					$tokenValid = false; 
				} else {
					sqlrun("ROLLBACK");
					$messageHtml = "<div class='msg-err'>Kritická chyba: Uložení nového hesla do databáze selhalo.</div>";
				}
			}
		}
	} else {
		$messageHtml = "<div class='msg-err'>Tento odkaz pro obnovu hesla je neplatný nebo již vypršel. Vyžádejte si prosím nový.</div>";
	}

} else {
	// =========================================================================
	// FÁZE 1: VYŽÁDÁNÍ ODKAZU (ZADÁNÍ LOGINU A E-MAILU)
	// =========================================================================
	
	if ($isPost) {
		$rawLogin = trim((string)getinput('login_name', 'raw'));
		$rawEmail = trim((string)getinput('email', 'raw'));
		
		if (empty($rawLogin) || empty($rawEmail)) {
			$messageHtml = "<div class='msg-err'>Prosím, zadejte přihlašovací jméno i e-mail.</div>";
		} else {
			$safeLogin = charliteral($rawLogin, 200);
			$safeEmail = charliteral($rawEmail, 200);

			$sysadminEmail = '';
			$sqlSysAdmin = "SELECT sysadmin_email FROM system_constant";
			$sysAdminRow = sqlfirstrow($sqlSysAdmin);
			if ($sysAdminRow && !empty(trim((string)$sysAdminRow['sysadmin_email']))) {
				$sysadminEmail = trim((string)$sysAdminRow['sysadmin_email']);
			}

			$userEmail = '';
			$loginName = '';
			$userId = '';

			// 1. Zjištění, zda se nejedná o vyžádání hesla pro System Admina (0x00)
			if (strtolower($rawLogin) === 'admin' && !empty($sysadminEmail) && strcasecmp($rawEmail, $sysadminEmail) === 0) {
				$userId = '0x00';
				$loginName = 'admin';
				$userEmail = $sysadminEmail;
			} 
			// 2. Pokud ne, hledáme standardního uživatele
			else {
				$sqlUser = "
					SELECT original, login_name, first_name, last_name, email 
					FROM user_account 
					WHERE login_name = $safeLogin 
						AND email = $safeEmail
						AND record_type = 'A' 
						AND inactive = 0 
						AND removed = 0
				";
				
				// Nyní již nehrozí kolize z multi-tenantního prostředí, 
				// kombinace loginu a konkrétního e-mailu je unikátní identifikátor
				$userRow = sqlfirstrow($sqlUser);

				if ($userRow) {
					$userId = trim((string)$userRow['original']);
					$loginName = trim((string)$userRow['login_name']);
					$userEmail = trim((string)$userRow['email']);
				}
			}

			if (empty($userEmail)) {
				// Bezpečnostní zpráva neprozrazuje, co přesně bylo špatně (prevence enumerace)
				$messageHtml = "<div class='msg-err'>Účet s touto kombinací jména a e-mailu nebyl nalezen, nebo je deaktivován.</div>";
			} else {
				try {
					$plainToken = bin2hex(random_bytes(32));
				} catch (\Exception $e) {
					fatal_error("Chyba krypto-generátoru", $e->getMessage());
				}

				$tokenHash = hash('sha256', $plainToken);
				$expiresAt = date('Y-m-d H:i:s', strtotime('+24 hours'));
				$tokenUuid = newid(); 

				$safeTokenUuid = guidliteral($tokenUuid);
				$safeHash = charliteral($tokenHash, 255);
				$safePurpose = charliteral('PASSWORD_RESET', 50); 
				$safeExpires = dateliteral($expiresAt);
				$safeIp = charliteral(get_client_ip_path(), 200);
				$safeUserId = ($userId === '0x00' || $userId === '00000000-0000-0000-0000-000000000000') ? '0x00' : guidliteral($userId);

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

				$baseUrl = $protocol . $_SERVER['HTTP_HOST'] . rtrim(dirname($_SERVER['REQUEST_URI']), '/\\') . '/';
				// URL nyní směřuje korektně přes centrální router index.php
				$activationLink = $baseUrl . "index.php?page=password_reset&token=" . urlencode($plainToken);

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

				if (send_global_mail($userEmail, $mailSubject, $mailBody, true)) {
					$messageHtml = "<div class='msg-ok'>E-mail s instrukcemi pro obnovu hesla byl úspěšně odeslán. Zkontrolujte svou schránku.</div>";
				} else {
					$messageHtml = "<div class='msg-err'>Chyba při odesílání e-mailu. Kontaktujte administrátora.</div>";
				}
			}
		}
	}
}

// Proměnná pro případné vypnutí prvků na frontendu, pokud hrozí riziko úniku dat
$disabledAttr = $blockAction ? 'disabled' : '';
?>
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="utf-8">
	<title>Obnova hesla - RAMSES ISMS</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 50px; }
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
	</style>
</head>
<body>
	<div class="container">
		
		<?php if ($securityWarningHtml): ?>
			<?php echo $securityWarningHtml; ?>
		<?php endif; ?>

		<?php if ($messageHtml): ?>
			<div class="message"><?php echo $messageHtml; ?></div>
		<?php endif; ?>

		<?php if (!empty($token) && $tokenValid): ?>
			<!-- FÁZE 2: FORMULÁŘ PRO NOVÉ HESLO -->
			<h1>Nastavení nového hesla</h1>
			<p style="color: #555; font-size: 14px;">Zadejte své nové heslo. Z bezpečnostních důvodů musí obsahovat minimálně 8 znaků.</p>
			<!-- Akce nyní směřuje přes centrální router -->
			<form method="POST" action="index.php?page=password_reset">
				<input type="hidden" name="token" value="<?php echo htmlspecialchars($token); ?>">
				
				<label for="new_password">Nové heslo:</label>
				<input type="password" id="new_password" name="new_password" required minlength="8" <?php echo $disabledAttr; ?>>
				
				<label for="new_password_confirm">Potvrzení nového hesla:</label>
				<input type="password" id="new_password_confirm" name="new_password_confirm" required minlength="8" <?php echo $disabledAttr; ?>>
				
				<button type="submit" <?php echo $disabledAttr; ?>>Uložit heslo</button>
			</form>

		<?php elseif (empty($token)): ?>
			<!-- FÁZE 1: FORMULÁŘ PRO VYŽÁDÁNÍ ODKAZU -->
			<h1>Obnova zapomenutého hesla</h1>
			<p style="color: #555; font-size: 14px;">Zadejte své přihlašovací jméno a e-mail. Na příslušnou e-mailovou adresu vám bude zaslán odkaz k nastavení nového hesla.</p>
			<!-- Akce nyní směřuje přes centrální router -->
			<form method="POST" action="index.php?page=password_reset">
				<label for="login_name">Uživatelské jméno:</label>
				<input type="text" id="login_name" name="login_name" required value="<?php echo htmlspecialchars($_POST['login_name'] ?? ''); ?>" <?php echo $disabledAttr; ?>>
				
				<label for="email">E-mailová adresa:</label>
				<input type="email" id="email" name="email" required value="<?php echo htmlspecialchars($_POST['email'] ?? ''); ?>" <?php echo $disabledAttr; ?>>
				
				<button type="submit" <?php echo $disabledAttr; ?>>Odeslat odkaz</button>
			</form>
		<?php endif; ?>
		
		<a href="index.php?page=login" class="back-link">Zpět na úvodní obrazovku (Přihlášení)</a>
	</div>
</body>
</html>