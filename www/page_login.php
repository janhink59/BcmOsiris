<?php
/**
 * =============================================================================
 * Stránka: page_login.php
 * Účel: Zajišťuje autentizaci uživatele proti tabulce user_account 
 *       nebo system_constant (System Admin).
 * 
 * Logika a vazby:
 * - Jelikož index.php přeskočí initsession() při $page == 'login', musíme
 *   zde session_start() zavolat sami, abychom získali platné $SID.
 * - Zpracovává POST požadavek s přihlašovacími údaji přes getinput().
 * - Z databáze získá pouze nezbytný identifikátor a hash hesla.
 * - Ověřuje heslo pomocí bezpečné PHP funkce password_verify().
 * - Po úspěšném ověření deleguje zápis a načtení detailů do wwwsession 
 *   voláním uložené procedury p_set_login.
 * =============================================================================
 */

declare(strict_types=1);

// Vynucení kódování UTF-8 pro hlavní výstup
header('Content-Type: text/html; charset=utf-8');

// Globální proměnné z configu a knihoven
global $SID, $http_allowed;

// 1. Zajištění session (pokud jsme přišli přímo přes index.php?page=login)
if (session_status() === PHP_SESSION_NONE) {
	session_start();
}
$SID = session_id();

$messageHtml = '';
$isPost = ($_SERVER['REQUEST_METHOD'] === 'POST');

// =========================================================================
// KONTROLA BEZPEČNOSTI (HTTP vs HTTPS)
// =========================================================================
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || $_SERVER['SERVER_PORT'] == 443;
$blockAction = false;

// Blokování nezabezpečeného přenosu hesla, pokud není explicitně povolen
if (!$isHttps && empty($http_allowed)) {
	$messageHtml = "
		<div class='msg-err' style='margin-bottom: 25px;'>
			<strong>Kritické bezpečnostní riziko:</strong> Komunikace probíhá přes nezabezpečený protokol HTTP. 
			Zadávaná hesla by mohla být odposlechnuta. Akce byla zablokována.
			<br><br>
			<em>(Pro ladění lokálně povolte proměnnou <code>\$http_allowed = 1;</code> v config.php)</em>
		</div>";
	$blockAction = true;
}

if ($isPost && $blockAction) {
	$isPost = false; // Zahození POSTu při blokaci
}

// =========================================================================
// ZPRACOVÁNÍ PŘIHLÁŠENÍ
// =========================================================================
if ($isPost) {
	// Získání raw vstupů, protože hesla mohou obsahovat speciální znaky
	$login = (string)getinput('login_name', 'raw');
	$password = (string)getinput('password', 'raw');
	
	if (empty($login) || empty($password)) {
		$messageHtml = "<div class='msg-err'>Prosím, zadejte přihlašovací jméno i heslo.</div>";
	} else {
		$safeLogin = charliteral($login, 200);
		$isAuthenticated = false;
		$userUuid = '';
		
		// A. Pokus o přihlášení jako System Admin (break-glass účet) z tabulky system_constant
		$sqlSysAdmin = "SELECT system_admin_pwd FROM system_constant";
		$sysAdminRow = sqlfirstrow($sqlSysAdmin);
		
		// Kontrola, zda uživatel zadal striktně admin login (odstraněna možnost přihlášení přes e-mail)
		if ($sysAdminRow && strtolower($login) === 'admin') {
			$hash = trim((string)$sysAdminRow['system_admin_pwd']);
			if (password_verify($password, $hash)) {
				$isAuthenticated = true;
				$userUuid = '00000000-0000-0000-0000-000000000000'; // Rezervovaný NULL UUID pro systém
			}
		}
		
		// B. Pokus o přihlášení jako běžný uživatel z tabulky user_account
		if (!$isAuthenticated) {
			$userSql = "
				SELECT original, password_hash, inactive, require_password_change, allow_local_login, locked_until 
				FROM user_account 
				WHERE login_name = $safeLogin 
					AND record_type = 'A' 
					AND removed = 0
			";
			
			// Zjištění, zda jméno nekoliduje ve více tenantech (ověření exkluzivity)
			$userRows = sqlarray_simple($userSql);
			
			if (count($userRows) > 1) {
				$messageHtml = "<div class='msg-err'>Přihlašovací jméno není unikátní (kolize identit). Kontaktujte administrátora.</div>";
			} elseif (count($userRows) === 1) {
				$userRow = $userRows[0];
				
				// Kontrola časového uzamčení proti Brute-Force útokům
				if (!empty($userRow['locked_until']) && strtotime($userRow['locked_until']) > time()) {
					$messageHtml = "<div class='msg-err'>Účet je dočasně uzamčen z důvodu mnoha neúspěšných pokusů o přihlášení.</div>";
				} elseif ($userRow['inactive']) {
					$messageHtml = "<div class='msg-err'>Tento účet je momentálně deaktivován.</div>";
				} elseif (isset($userRow['allow_local_login']) && $userRow['allow_local_login'] == 0) {
					$messageHtml = "<div class='msg-err'>Přihlášení jménem a heslem není povoleno. Použijte jednotné přihlášení (SSO).</div>";
				} else {
					$hash = trim((string)$userRow['password_hash']);
					if (password_verify($password, $hash)) {
						$isAuthenticated = true;
						$userUuid = trim((string)$userRow['original']);
					} else {
						// Inkrementace pokusů a případné uzamčení na 15 minut po 5 neúspěšných pokusech (T-SQL syntaxe)
						$safeUserOriginal = guidliteral(trim((string)$userRow['original']));
						sqlrun("
							UPDATE user_account 
							SET failed_login_attempts = ISNULL(failed_login_attempts, 0) + 1,
								locked_until = CASE 
									WHEN ISNULL(failed_login_attempts, 0) + 1 >= 5 THEN DATEADD(minute, 15, GETDATE()) 
									ELSE locked_until 
								END
							WHERE original = $safeUserOriginal AND record_type = 'A'
						");
					}
				}
			}
		}
		
		// C. Vyhodnocení stavu a volání uložené procedury
		if ($isAuthenticated && empty($messageHtml)) {
			// Převod hodnot na bezpečné literály pro MSSQL syntaxi
			$safeSid = charliteral($SID, 100);
			$safeUserUuid = guidliteral($userUuid);
			$safeIp = charliteral(get_client_ip_path(), 200);
			
			// Volání T-SQL procedury, která zapíše kontext do wwwsession
			$procSql = "EXEC p_set_login @user_uuid = $safeUserUuid, @wwwsession = $safeSid, @client_ip = $safeIp";
			
			if (sqlrun($procSql)) {
				// PRG Pattern: Po úspěšném POST přesměrujeme na GET hlavní stránky
				header("Location: index.php?page=main");
				exit;
			} else {
				$messageHtml = "<div class='msg-err'>Kritická chyba: Uložená procedura p_set_login selhala při zakládání sezení.</div>";
			}
		} elseif (!$isAuthenticated && empty($messageHtml)) {
			// Schválně nespecifikujeme, zda je špatné jméno nebo heslo (prevence enumerace uživatelů)
			$messageHtml = "<div class='msg-err'>Nesprávné přihlašovací jméno nebo heslo.</div>";
		}
	}
}

// Frontend disabling v případě nezabezpečeného HTTP
$disabledAttr = $blockAction ? 'disabled' : '';
?>
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="utf-8">
	<title>Přihlášení - RAMSES ISMS</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 50px; }
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
	</style>
</head>
<body>
	<div class="container">
		<h1>Přihlášení do systému RAMSES</h1>
		
		<?php if ($messageHtml): ?>
			<div class="message"><?php echo $messageHtml; ?></div>
		<?php endif; ?>
		
		<form method="POST" action="index.php?page=login">
			<label for="login_name">Uživatelské jméno:</label>
			<input type="text" id="login_name" name="login_name" required value="<?php echo htmlspecialchars($_POST['login_name'] ?? ''); ?>" <?php echo $disabledAttr; ?>>
			
			<label for="password">Heslo:</label>
			<input type="password" id="password" name="password" required <?php echo $disabledAttr; ?>>
			
			<button type="submit" <?php echo $disabledAttr; ?>>Přihlásit se</button>
		</form>
		
		<a href="index.php?page=password_reset" class="forgot-pwd">Zapomněli jste heslo?</a>
	</div>
</body>
</html>