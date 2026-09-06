<?php
/**
 * =============================================================================
 * Stránka: page_organization_licence.php
 * Účel: Master-Detail rozhraní pro evidenci žádostí a licencí organizací.
 * 
 * Logika a byznys procesy:
 * - Modul je dostupný exkluzivně pro Sysadminy, řídí zakládání nových tenantů.
 * - Jakmile je žádosti (licence) nastaven stav 'APPROVED', při uložení se
 *   automaticky triggeruje procedura p_process_organization_licence.
 * - Procedura obratem licenci zpracuje (vygeneruje organizaci, orgadmina
 *   a propojí jejich záznamy v DB) a stav finálně přepne na 'PROCESSED'.
 * =============================================================================
 */

declare(strict_types=1);

global $dbsession, $dbquery, $datarow;
global $pageitem_array;

// Ochrana před nepovolaným přístupem
if (empty($dbsession['right_sysadmin'])) {
	echo "<div style='padding:50px; text-align:center;'>
			<h2 style='color:red;'>Přístup odepřen / Access denied</h2>
			<h3>Ke vstupu do tohoto modulu je vyžadována role System Administrator.</h3>
			<a href='index.php'>Zpět na hlavní panel</a>
		  </div>";
	return;
}

// Manuální mapování proměnných pro OsirisLib formovací vrstvu (absentují metadata)
pageitem('caption', 'Název organizace', 'Název organizace', 'Plný název nové organizace', 'text', 'varchar', '100%', 0, 0, 200);
pageitem('login_domain', 'Login doména', 'Doména', 'Doména pro SSO (např. firma.cz)', 'text', 'varchar', '100%', 0, 0, 200);
pageitem('licence_level', 'Úroveň licence', 'Úroveň', 'Zvolte požadovanou úroveň licence z číselníku', 'select', 'int', '200px', 0, 0, 0);
pageitem('licence_state', 'Stav licence', 'Stav', 'Životní cyklus licence', 'select', 'varchar', '150px', 0, 0, 0);
pageitem('admin_login', 'Login admina', 'Admin login', 'Přihlašovací jméno správce', 'text', 'varchar', '100%', 0, 0, 100);
pageitem('admin_first_name', 'Jméno admina', 'Jméno', 'Křestní jméno správce', 'text', 'varchar', '100%', 0, 0, 100);
pageitem('admin_last_name', 'Příjmení admina', 'Příjmení', 'Příjmení správce', 'text', 'varchar', '100%', 0, 0, 100);
pageitem('admin_email', 'E-mail admina', 'E-mail', 'Kontaktní e-mail', 'text', 'varchar', '100%', 0, 0, 200);

// Nastavení dynamických hodnot pro drop-down nabídky
$states_opt = [
	'DRAFT' => 'Koncept',
	'APPROVED' => 'Schváleno (spustí aktivaci)',
	'PROCESSED' => 'Zpracováno (Aktivní)',
	'REJECTED' => 'Zamítnuto'
];
$levels_opt = sqlarray("SELECT licence_level, name FROM licence_level ORDER BY licence_level");

// Rozcestník stavů
$update_guid = getinput('update_guid', 'raw');
$mode = $update_guid ? 'detail' : 'list';
$button_save = getinput('button_save', 'raw');

if ($button_save) {
	// Spuštění sanitizace a escapování (reginputs z OsirisLib transformuje data)
	reginputs('caption:varchar,login_domain:varchar,licence_level:int,licence_state:varchar');
	reginputs('admin_login:varchar,admin_first_name:varchar,admin_last_name:varchar,admin_email:varchar');
	
	global $caption, $login_domain, $licence_level, $licence_state, $admin_login, $admin_first_name, $admin_last_name, $admin_email;
	
	$safe_uuid = guidliteral($update_guid);
	$safe_user = guidliteral($dbsession['user_account']);

	if ($update_guid === 'NEW') {
		$new_uuid = generateUUID();
		$safe_new_uuid = guidliteral($new_uuid);
		
		$sql = "INSERT INTO organization_licence (
			uuid, object_owner, original, record_type, approval_status, 
			caption, login_domain, licence_level, licence_state, 
			admin_login, admin_first_name, admin_last_name, admin_email,
			who_created, who_modified
		) VALUES (
			$safe_new_uuid, 0x00, $safe_new_uuid, 'A', 'A',
			$caption, $login_domain, $licence_level, $licence_state,
			$admin_login, $admin_first_name, $admin_last_name, $admin_email,
			$safe_user, $safe_user
		)";
		sqlrun($sql);
	} else {
		$sql = "UPDATE organization_licence SET 
			caption = $caption,
			login_domain = $login_domain,
			licence_level = $licence_level,
			licence_state = $licence_state,
			admin_login = $admin_login,
			admin_first_name = $admin_first_name,
			admin_last_name = $admin_last_name,
			admin_email = $admin_email,
			date_modified = GETDATE(),
			who_modified = $safe_user
		WHERE original = $safe_uuid AND record_type = 'A'";
		sqlrun($sql);
		
		// Detekce triggeru pro aktivaci tenanta (očekáváme stav APPROVED)
		if (trim((string)$licence_state, "'") === 'APPROVED') {
			sqlrun("EXEC p_process_organization_licence @licence_original = $safe_uuid, @who_modified = $safe_user");
		}
	}
	autoredirect('index.php?page=organization_licence');
}

?>
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="utf-8">
	<title>Správa licencí organizací</title>
	<style>
		body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 30px; }
		.panel { background-color: #fff; padding: 25px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); margin: auto; max-width: 900px; }
		table.grid { width: 100%; border-collapse: collapse; margin-top: 15px; }
		table.grid th, table.grid td { border: 1px solid #ddd; padding: 10px; text-align: left; }
		table.grid th { background-color: #e9f2fa; color: #004488; }
		table.form-table td { padding: 8px; vertical-align: top; }
		h1 { color: #004488; margin-top: 0; border-bottom: 2px solid #eee; padding-bottom: 10px; }
		.btn { display: inline-block; padding: 10px 15px; background-color: #004488; color: #fff; text-decoration: none; border: none; border-radius: 3px; font-weight: bold; cursor: pointer; }
		.btn:hover { background-color: #003366; }
		.btn-back { background-color: #666; margin-right: 10px; }
		.btn-back:hover { background-color: #444; }
	</style>
</head>
<body>

<div class="panel">
	
	<?php if ($mode === 'list'): ?>
		<!-- MASTER PANEL: Seznam licencí -->
		<h1>Evidence organizací a licencí</h1>
		<div style="margin-bottom: 20px;">
			<a href="index.php?page=main" class="btn btn-back">Zpět na Dashboard</a>
			<a href="index.php?page=organization_licence&update_guid=NEW" class="btn">+ Vytvořit novou licenci</a>
		</div>
		
		<table class="grid">
			<tr>
				<th>Organizace</th>
				<th>Admin (Login)</th>
				<th>E-mail</th>
				<th>Stav licence</th>
				<th>Akce</th>
			</tr>
			<?php
			$q = sqlrun("
				SELECT original, caption, admin_login, admin_email, licence_state 
				FROM organization_licence 
				WHERE record_type = 'A' AND removed = 0 
				ORDER BY date_created DESC
			");
			
			while (fetch_datarow($q)) {
				echo "<tr>";
				echo td1_value('caption');
				echo td1_value('admin_login');
				echo td1_value('admin_email');
				echo "<td>" . htmlspecialchars($states_opt[$datarow['licence_state']] ?? $datarow['licence_state']) . "</td>";
				echo "<td style='text-align:center;'>
						<a href='index.php?page=organization_licence&update_guid={$datarow['original']}' style='font-weight:bold;color:#004488;'>Detail</a>
					  </td>";
				echo "</tr>";
			}
			free_result($q);
			?>
		</table>
		
	<?php else: ?>
		<!-- DETAIL PANEL: Konkrétní záznam -->
		<h1>Detail organizace a licencování</h1>
		
		<?php
		if ($update_guid === 'NEW') {
			$datarow = [
				'caption' => '', 'login_domain' => '', 'licence_level' => 10,
				'licence_state' => 'DRAFT', 'admin_login' => '', 'admin_first_name' => '',
				'admin_last_name' => '', 'admin_email' => ''
			];
		} else {
			$safe_uuid = guidliteral($update_guid);
			$q = sqlrun("SELECT * FROM organization_licence WHERE original = $safe_uuid AND record_type = 'A' AND removed = 0");
			fetch_datarow($q);
			free_result($q);
		}
		?>
		
		<form method="POST" action="index.php?page=organization_licence">
			<?php echo hidden_input('update_guid', $update_guid); ?>
			
			<table class="form-table">
				<tr><?php echo td1_label('caption') . td1_input('caption'); ?></tr>
				<tr><?php echo td1_label('login_domain') . td1_input('login_domain'); ?></tr>
				<tr><?php echo td1_label('licence_level') . td1_input('licence_level', '', $levels_opt); ?></tr>
				<tr><?php echo td1_label('licence_state') . td1_input('licence_state', '', $states_opt); ?></tr>
				
				<tr><td colspan="2"><hr style="border:0; border-top:1px dashed #ccc; margin:15px 0;"></td></tr>
				
				<tr><?php echo td1_label('admin_login') . td1_input('admin_login'); ?></tr>
				<tr><?php echo td1_label('admin_first_name') . td1_input('admin_first_name'); ?></tr>
				<tr><?php echo td1_label('admin_last_name') . td1_input('admin_last_name'); ?></tr>
				<tr><?php echo td1_label('admin_email') . td1_input('admin_email'); ?></tr>
				
				<tr>
					<td colspan="2" style="padding-top: 25px;">
						<a href="index.php?page=organization_licence" class="btn btn-back">Zpět</a>
						<button type="submit" name="button_save" value="1" class="btn">Uložit záznam</button>
					</td>
				</tr>
			</table>
		</form>
	<?php endif; ?>
</div>

</body>
</html>