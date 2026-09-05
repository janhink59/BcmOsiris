<?php
// =============================================================================
// Stránka: page_main.php
// Účel: Hlavní dashboard po přihlášení uživatele s výpisem kontextu.
// =============================================================================

declare(strict_types=1);

global $dbsession;

// Bezpečnostní kontrola, zda máme k dispozici data relace
if (!isset($dbsession) || !is_array($dbsession)) {
	echo "<div class='msg-err'>Chyba: Nepodařilo se načíst kontext uživatele.</div>";
	return;
}

// Získání primárních hodnot z pole $dbsession
$userName = $dbsession['display_name'] ?: $dbsession['user_name'];
$orgName = $dbsession['organization_name'] ?: 'Systémová organizace';

// Sestavení dynamického seznamu rolí
$roles = [];
if (!empty($dbsession['right_sysadmin'])) {
	$roles[] = 'System Admin';
}
if (!empty($dbsession['right_orgadmin'])) {
	$roles[] = 'Organization Admin';
}
if (!empty($dbsession['right_debug'])) {
	$roles[] = 'Debug Mode';
}

$rolesStr = !empty($roles) ? implode(', ', $roles) : 'Běžný uživatel';

// Ošetření výstupu pro HTML (XSS ochrana pro jistotu, i když htmlspec() už proběhl v initsession)
$safeUserName = htmlspecialchars((string)$userName);
$safeOrgName = htmlspecialchars((string)$orgName);
$safeRolesStr = htmlspecialchars((string)$rolesStr);

// Výstup HTML pomocí HEREDOC (využíváme plně možností PHP 8.3)
echo <<<HTML
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="utf-8">
	<title>Hlavní panel - RAMSES ISMS</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 50px; }
		.dashboard-container { background-color: #fff; padding: 30px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); max-width: 600px; margin: auto; }
		h1 { color: #004488; margin-top: 0; border-bottom: 2px solid #eee; padding-bottom: 10px; }
		.user-info { margin-top: 20px; padding: 15px; background-color: #e9f2fa; border-left: 4px solid #004488; border-radius: 3px; }
		.user-info p { margin: 10px 0; font-size: 16px; }
		.user-info strong { color: #333; display: inline-block; width: 120px; }
		.logout-link { display: inline-block; margin-top: 25px; padding: 12px 15px; background-color: #b71c1c; color: #fff; text-decoration: none; border-radius: 3px; font-weight: bold; }
		.logout-link:hover { background-color: #8e1515; }
	</style>
</head>
<body>
	<div class="dashboard-container">
		<h1>Vítejte v systému RAMSES</h1>
		
		<div class="user-info">
			<p><strong>Uživatel:</strong> {$safeUserName}</p>
			<p><strong>Organizace:</strong> {$safeOrgName}</p>
			<p><strong>Aktivní role:</strong> {$safeRolesStr}</p>
		</div>
		
		<a href="index.php?page=logout" class="logout-link">Odhlásit se</a>
	</div>
</body>
</html>
HTML;