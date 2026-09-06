<?php
/**
 * =============================================================================
 * Stránka: page_org_users.php
 * Účel: Master-Detail rozhraní pro správu uživatelů aktuálního tenanta.
 * 
 * Bezpečnostní a aplikační logika:
 * - Přístup je povolen pouze uživatelům s rolí right_orgadmin.
 * - Ochrana vlastního účtu (is_me): Skript zablokuje UI ovládací prvky i backend
 *   proměnné, pokud by se administrátor pokusil deaktivovat sám sebe nebo si
 *   odebrat orgadmin práva.
 * - Sysadmin (right_sysadmin) má jako jediný možnost globálně zablokovat účet 
 *   v celém systému (inactive = 1). Orgadmin řeší pouze lokální přístup (removed = 1).
 * - Filtr `show_removed_users` dynamicky překresluje dotaz na databázi 
 *   a je udržován v rámci relace přes funkci sessioninput().
 * =============================================================================
 */

declare(strict_types=1);

global $dbsession, $dbquery, $datarow;
global $pageitem_array, $pageitem_is_orgadmin;

// Validace přístupu
if (empty($dbsession['right_orgadmin'])) {
	echo "<div style='padding:50px; text-align:center;'>
			<h2 style='color:red;'>Přístup odepřen / Access denied</h2>
			<h3>Vyžadována role Organization Administrator.</h3>
			<a href='index.php'>Zpět na hlavní panel</a>
		  </div>";
	return;
}

$isSysadmin = !empty($dbsession['right_sysadmin']);
$logged_user_uuid = (string)$dbsession['user_account'];

// Načtení filtru s pamětí v session (udržuje hodnotu i po návratu z detailu)
$show_removed_users = sessioninput('show_removed_users', 4);

// UI Definice datových položek (OsirisLib Form Helpers)
pageitem('login_name', 'Přihlašovací jméno', 'Login', 'Unikátní login do systému', 'text', 'varchar', '100%', 0, 0, 100);
pageitem('first_name', 'Jméno', 'Jméno', 'Křestní jméno', 'text', 'varchar', '100%', 0, 0, 100);
pageitem('last_name', 'Příjmení', 'Příjmení', 'Příjmení', 'text', 'varchar', '100%', 0, 0, 100);
pageitem('email', 'E-mail', 'E-mail', 'Kontaktní e-mail', 'text', 'varchar', '100%', 0, 0, 200);
pageitem('is_orgadmin', 'Je administrátor', 'Admin', 'Má uživatel správcovská práva v této organizaci?', 'checkbox', 'bit', '', 0, 0, 0);
pageitem('remove_access', 'Odstranit přístup', 'Zrušit', 'Zamezí uživateli přístup do této organizace', 'checkbox', 'bit', '', 0, 0, 0);
pageitem('deactivate_global', 'Deaktivovat účet', 'Neaktivní', 'Globálně zablokuje účet (Sysadmin)', 'checkbox', 'bit', '', 0, 0, 0);

// Identifikace kontextu editace
$update_guid = getinput('update_guid', 'raw');
$mode = $update_guid ? 'detail' : 'list';
$current_org = guidliteral($dbsession['organization']);

// Blokace oprávnění pro případ editace vlastního účtu
$is_me = ($update_guid === $logged_user_uuid);
if ($is_me) {
	$pageitem_is_orgadmin->displayonly = 1;
}

// Zpracování POST požadavků a volání uložené procedury
$button_save = getinput('button_save', 'raw');
if ($button_save) {
	reginputs('login_name:varchar,first_name:varchar,last_name:varchar,email:varchar');
	reginputs('is_orgadmin:bit,remove_access:bit,deactivate_global:bit');
	
	global $login_name, $first_name, $last_name, $email, $is_orgadmin, $remove_access, $deactivate_global;
	
	// Bezpečnostní override PHP vrstvy proti podvržení HTTP POST dat na vlastní účet
	if ($is_me) {
		$remove_access = 0;
		$deactivate_global = 0;
		$is_orgadmin = 1; 
	}
	
	// Ochrana před nepovoleným globálním blokováním účtů
	if (!$isSysadmin) {
		$deactivate_global = 0;
	}
	
	$safe_uuid = ($update_guid === 'NEW') ? 'NULL' : guidliteral($update_guid);
	$safe_user = guidliteral($logged_user_uuid);

	$sql = "EXEC p_save_org_user 
		@organization_uuid = $current_org,
		@user_original = $safe_uuid,
		@login_name = $login_name,
		@email = $email,
		@first_name = $first_name,
		@last_name = $last_name,
		@is_orgadmin = $is_orgadmin,
		@remove_access = $remove_access,
		@deactivate_global = $deactivate_global,
		@who_modified = $safe_user";
		
	sqlrun($sql);
	autoredirect('index.php?page=org_users');
}

?>
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="utf-8">
	<title>Správa uživatelů organizace</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 30px; }
		.panel { background-color: #fff; padding: 25px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); margin: auto; max-width: 1000px; }
		table.grid { width: 100%; border-collapse: collapse; margin-top: 15px; }
		table.grid th, table.grid td { border: 1px solid #ddd; padding: 10px; text-align: left; }
		table.grid th { background-color: #e9f2fa; color: #004488; }
		table.form-table td { padding: 8px; vertical-align: middle; }
		h1 { color: #2E7D32; margin-top: 0; border-bottom: 2px solid #eee; padding-bottom: 10px; }
		.btn { display: inline-block; padding: 10px 15px; background-color: #4CAF50; color: #fff; text-decoration: none; border: none; border-radius: 3px; font-weight: bold; cursor: pointer; }
		.btn:hover { background-color: #388E3C; }
		.btn-back { background-color: #666; margin-right: 10px; }
		.btn-back:hover { background-color: #444; }
		.danger-zone { background-color: #ffebee; border-left: 4px solid #b71c1c; padding: 10px; margin-top: 20px; }
		.removed-row { background-color: #fcfcfc; color: #999; font-style: italic; }
	</style>
</head>
<body>

<div class="panel">
	
	<?php if ($mode === 'list'): ?>
		<!-- MASTER PANEL -->
		<h1>Uživatelé organizace</h1>
		<div style="margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center;">
			<div>
				<a href="index.php?page=main" class="btn btn-back">Zpět na Dashboard</a>
				<a href="index.php?page=org_users&update_guid=NEW" class="btn">+ Přidat uživatele</a>
			</div>
			
			<form method="GET" action="index.php" style="margin: 0;">
				<input type="hidden" name="page" value="org_users">
				<input type="hidden" name="show_removed_users" value="0">
				<label style="cursor: pointer; color: #004488; font-weight: bold; padding: 5px 10px; background: #e9f2fa; border-radius: 3px;">
					<input type="checkbox" name="show_removed_users" value="1" <?php echo $show_removed_users ? 'checked' : ''; ?> onchange="this.form.submit();">
					Zobrazit i odstraněné přístupy
				</label>
			</form>
		</div>
		
		<table class="grid">
			<tr>
				<th>Login</th>
				<th>Jméno a příjmení</th>
				<th>E-mail</th>
				<th>Org. Admin</th>
				<th>Stav účtu</th>
				<th>Akce</th>
			</tr>
			<?php
			$remove_filter = $show_removed_users ? "" : "AND a.removed = 0";
			
			// Klíčový T-SQL dotaz skládající globální tabulku user_account s lokální user_organization_access
			$q = sqlrun("
				SELECT u.original, u.login_name, u.first_name, u.last_name, u.email, 
					   a.is_orgadmin, u.inactive, a.removed AS access_removed
				FROM user_account u
				JOIN user_organization_access a ON a.user_account_uuid = u.original
				WHERE a.organization_uuid = $current_org 
				  AND a.record_type = 'A' $remove_filter
				  AND u.record_type = 'A' AND u.removed = 0
				ORDER BY a.removed ASC, u.last_name, u.first_name
			");
			
			while (fetch_datarow($q)) {
				$is_removed = $datarow['access_removed'];
				$row_class = $is_removed ? 'removed-row' : '';
				
				if ($is_removed) {
					$status = '<span style="color:#999;font-weight:bold;">Zrušený přístup</span>';
				} elseif ($datarow['inactive']) {
					$status = '<span style="color:red;font-weight:bold;">Neaktivní účet</span>';
				} else {
					$status = '<span style="color:green;">Aktivní</span>';
				}
				
				echo "<tr class='$row_class'>";
				echo td1_value('login_name');
				echo "<td>" . htmlspecialchars($datarow['first_name'] . ' ' . $datarow['last_name']) . "</td>";
				echo td1_value('email');
				echo "<td>" . ($datarow['is_orgadmin'] ? 'Ano' : 'Ne') . "</td>";
				echo "<td>$status</td>";
				echo "<td style='text-align:center;'>
						<a href='index.php?page=org_users&update_guid={$datarow['original']}' style='font-weight:bold;color:#2E7D32;'>Detail</a>
					  </td>";
				echo "</tr>";
			}
			free_result($q);
			?>
		</table>
		
	<?php else: ?>
		<!-- DETAIL PANEL -->
		<h1>Detail uživatele</h1>
		
		<?php
		if ($update_guid === 'NEW') {
			$datarow = [
				'login_name' => '', 'first_name' => '', 'last_name' => '',
				'email' => '', 'is_orgadmin' => 0, 'remove_access' => 0, 'deactivate_global' => 0
			];
		} else {
			$safe_uuid = guidliteral($update_guid);
			$q = sqlrun("
				SELECT u.login_name, u.first_name, u.last_name, u.email, 
					   a.is_orgadmin, a.removed AS remove_access, u.inactive AS deactivate_global
				FROM user_account u
				JOIN user_organization_access a ON a.user_account_uuid = u.original
				WHERE u.original = $safe_uuid AND a.organization_uuid = $current_org
				  AND a.record_type = 'A' AND u.record_type = 'A'
			");
			fetch_datarow($q);
			free_result($q);
		}
		?>
		
		<form method="POST" action="index.php?page=org_users">
			<?php echo hidden_input('update_guid', $update_guid); ?>
			
			<table class="form-table">
				<tr><?php echo td1_label('login_name') . td1_input('login_name'); ?></tr>
				<tr><?php echo td1_label('first_name') . td1_input('first_name'); ?></tr>
				<tr><?php echo td1_label('last_name') . td1_input('last_name'); ?></tr>
				<tr><?php echo td1_label('email') . td1_input('email'); ?></tr>
				<tr><?php echo td1_label('is_orgadmin') . td1_input('is_orgadmin', '', 1); ?></tr>
			</table>
			
			<?php if ($update_guid !== 'NEW'): ?>
				<div class="danger-zone">
					<?php if ($is_me): ?>
						<p style="color: #b71c1c; font-weight: bold; margin: 0;">Ochrana účtu: Vlastní přístup ani administrátorská práva nelze odebrat.</p>
						<?php echo hidden_input('remove_access', '0'); ?>
						<?php echo hidden_input('deactivate_global', '0'); ?>
					<?php else: ?>
						<table class="form-table">
							<tr>
								<?php echo td1_label('remove_access') . td1_input('remove_access', '', 1); ?>
							</tr>
							<?php if ($isSysadmin): ?>
							<tr>
								<?php echo td1_label('deactivate_global') . td1_input('deactivate_global', '', 1); ?>
							</tr>
							<?php endif; ?>
						</table>
					<?php endif; ?>
				</div>
			<?php endif; ?>
			
			<div style="padding-top: 25px;">
				<a href="index.php?page=org_users" class="btn btn-back">Zpět</a>
				<button type="submit" name="button_save" value="1" class="btn">Uložit uživatele</button>
			</div>
		</form>
	<?php endif; ?>
</div>
</body>
</html>