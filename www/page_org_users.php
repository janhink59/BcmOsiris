<?php
/**
 * =============================================================================
 * Stránka: page_org_users.php
 * Účel: Master-Detail rozhraní pro správu uživatelů aktuálního tenanta.
 * =============================================================================
 */

declare(strict_types=1);

class page_org_users extends abstract_page_master_detail {

	private bool $access_denied = false;
	private string $current_org;
	private string $logged_user_uuid;
	private ?string $update_guid;
	private bool $show_removed_users;
	private bool $is_sysadmin;

	public function __construct() {
		global $dbsession;
		
		$this->page_title = 'Správa uživatelů organizace';
		
		if (empty($dbsession['right_orgadmin'])) {
			$this->access_denied = true;
			return;
		}

		$this->is_sysadmin = !empty($dbsession['right_sysadmin']);
		$this->logged_user_uuid = (string)$dbsession['user_account'];
		$this->current_org = guidliteral($dbsession['organization']);
		$this->show_removed_users = (bool)sessioninput('show_removed_users', 4);
		$this->update_guid = getinput('update_guid', 'raw') ?: null;

		pageitem('login_name', 'Přihlašovací jméno', 'Login', 'Unikátní login do systému', 'text', 'varchar', '100%', 0, 0, 100);
		pageitem('first_name', 'Jméno', 'Jméno', 'Křestní jméno', 'text', 'varchar', '100%', 0, 0, 100);
		pageitem('last_name', 'Příjmení', 'Příjmení', 'Příjmení', 'text', 'varchar', '100%', 0, 0, 100);
		pageitem('email', 'E-mail', 'E-mail', 'Kontaktní e-mail', 'text', 'varchar', '100%', 0, 0, 200);
		pageitem('is_orgadmin', 'Je administrátor', 'Admin', 'Má uživatel správcovská práva?', 'checkbox', 'bit', '', 0, 0, 0);
		pageitem('remove_access', 'Odstranit přístup', 'Zrušit', 'Zamezí uživateli přístup do organizace', 'checkbox', 'bit', '', 0, 0, 0);
		pageitem('deactivate_global', 'Deaktivovat účet', 'Neaktivní', 'Globálně zablokuje účet (Sysadmin)', 'checkbox', 'bit', '', 0, 0, 0);

		// Zavedení globální proměnné musí proběhnout AŽ PO spuštění funkcí pageitem()
		if ($this->update_guid !== null && strcasecmp($this->update_guid, $this->logged_user_uuid) === 0) {
			global $pageitem_is_orgadmin;
			$pageitem_is_orgadmin->displayonly = 1;
		}

		if (getinput('button_save', 'raw')) {
			$this->handle_save();
		}
	}

	private function handle_save(): void {
		reginputs('login_name:varchar,first_name:varchar,last_name:varchar,email:varchar');
		reginputs('is_orgadmin:bit,remove_access:bit,deactivate_global:bit');
		
		global $login_name, $first_name, $last_name, $email, $is_orgadmin, $remove_access, $deactivate_global;
		
		if ($this->update_guid !== null && strcasecmp($this->update_guid, $this->logged_user_uuid) === 0) {
			$remove_access = 0;
			$deactivate_global = 0;
			$is_orgadmin = 1; 
		}
		
		if (!$this->is_sysadmin) {
			$deactivate_global = 0;
		}
		
		$safe_uuid = ($this->update_guid === 'NEW') ? 'NULL' : guidliteral($this->update_guid);
		$safe_user = guidliteral($this->logged_user_uuid);

		$sql = "EXEC p_save_org_user 
			@organization_uuid = {$this->current_org},
			@user_original = {$safe_uuid},
			@login_name = {$login_name},
			@email = {$email},
			@first_name = {$first_name},
			@last_name = {$last_name},
			@is_orgadmin = {$is_orgadmin},
			@remove_access = {$remove_access},
			@deactivate_global = {$deactivate_global},
			@who_modified = {$safe_user}";
			
		sqlrun($sql);
		
		autoredirect("index.php?page=org_users&update_guid={$this->update_guid}");
	}

	protected function render_master(): void {
		if ($this->access_denied) {
			echo "<div class='msg-err'>Přístup odepřen. Vyžadována role Organization Administrator.</div>";
			return;
		}

		$checked = $this->show_removed_users ? 'checked' : '';
		
		echo <<<HTML
		<h2>Uživatelé organizace</h2>
		
		<div style="margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center;">
			<a href="index.php?page=org_users&update_guid=NEW" class="btn">+ Nový uživatel</a>
			
			<form method="GET" action="index.php" style="margin: 0;">
				<input type="hidden" name="page" value="org_users">
				<input type="hidden" name="show_removed_users" value="0">
				<label style="cursor: pointer; color: #004488; font-size: 13px;">
					<input type="checkbox" name="show_removed_users" value="1" {$checked} onchange="this.form.submit();">
					Zobrazit odstraněné
				</label>
			</form>
		</div>

		<table style="width: 100%; border-collapse: collapse;">
			<tr style="background-color: #e9f2fa; text-align: left;">
				<th style="padding: 8px; border: 1px solid #ddd;">Jméno a příjmení</th>
				<th style="padding: 8px; border: 1px solid #ddd;">Stav</th>
				<th style="padding: 8px; border: 1px solid #ddd; width: 50px;">Akce</th>
			</tr>
HTML;

		$remove_filter = $this->show_removed_users ? "" : "AND a.removed = 0";
		
		$q = sqlrun("
			SELECT u.original, u.first_name, u.last_name, u.inactive, a.removed AS access_removed
			FROM user_account u
			JOIN user_organization_access a ON a.user_account_uuid = u.original
			WHERE a.organization_uuid = {$this->current_org} 
			  AND a.record_type = 'A' {$remove_filter}
			  AND u.record_type = 'A' AND u.removed = 0
			ORDER BY a.removed ASC, u.last_name, u.first_name
		");
		
		global $datarow;
		while (fetch_datarow($q)) {
			$is_removed = $datarow['access_removed'];
			
			$is_active_row = ($this->update_guid !== null && strcasecmp((string)$datarow['original'], $this->update_guid) === 0);
			
			$bg_color = $is_active_row ? '#e6f7ff' : ($is_removed ? '#f9f9f9' : '#fff');
			$color = $is_removed ? '#999' : '#333';
			$status = $is_removed ? 'Zrušen' : ($datarow['inactive'] ? '<span style="color:red">Neaktivní</span>' : 'Aktivní');
			
			if ($is_active_row) {
				echo "<tr id='active-row' style='background-color: {$bg_color}; color: {$color};'>";
			} else {
				echo "<tr style='background-color: {$bg_color}; color: {$color};'>";
			}
			
			echo "<td style='padding: 8px; border: 1px solid #ddd;'>" . htmlspecialchars($datarow['last_name'] . ' ' . $datarow['first_name']) . "</td>";
			echo "<td style='padding: 8px; border: 1px solid #ddd;'>{$status}</td>";
			echo "<td style='padding: 8px; border: 1px solid #ddd; text-align: center;'>
					<a href='index.php?page=org_users&update_guid={$datarow['original']}' style='font-weight:bold;color:#004488;text-decoration:none;'>Detail</a>
				  </td>";
			echo "</tr>";
		}
		free_result($q);

		echo "</table>";
	}

	protected function render_detail(): void {
		if ($this->access_denied) {
			return;
		}

		if (!$this->update_guid) {
			echo "<div style='color: #666; margin-top: 50px; text-align: center;'>Vyberte uživatele ze seznamu vlevo nebo vytvořte nového.</div>";
			return;
		}

		echo "<h2>Detail uživatele</h2>";

		global $datarow;
		if ($this->update_guid === 'NEW') {
			$datarow = [
				'login_name' => '', 'first_name' => '', 'last_name' => '',
				'email' => '', 'is_orgadmin' => 0, 'remove_access' => 0, 'deactivate_global' => 0
			];
		} else {
			$safe_uuid = guidliteral($this->update_guid);
			$q = sqlrun("
				SELECT u.login_name, u.first_name, u.last_name, u.email, 
					   a.is_orgadmin, a.removed AS remove_access, u.inactive AS deactivate_global
				FROM user_account u
				JOIN user_organization_access a ON a.user_account_uuid = u.original
				WHERE u.original = {$safe_uuid} AND a.organization_uuid = {$this->current_org}
				  AND a.record_type = 'A' AND u.record_type = 'A'
			");
			fetch_datarow($q);
			free_result($q);
		}

		$is_me = ($this->update_guid !== null && strcasecmp($this->update_guid, $this->logged_user_uuid) === 0);

		echo <<<HTML
		<form method="POST" action="index.php?page=org_users">
HTML;
		echo hidden_input('update_guid', $this->update_guid);
		
		echo <<<HTML
			<table style="width: 100%; border-collapse: collapse;">
				<tr><td style="padding: 6px 0; width: 150px;">
HTML;
		echo td1_label('login_name') . td1_input('login_name') . "</tr>";
		echo "<tr>" . td1_label('first_name') . td1_input('first_name') . "</tr>";
		echo "<tr>" . td1_label('last_name') . td1_input('last_name') . "</tr>";
		echo "<tr>" . td1_label('email') . td1_input('email') . "</tr>";
		echo "<tr><td colspan='2'><hr style='border:0;border-top:1px dashed #ccc;margin:15px 0;'></td></tr>";
		echo "<tr>" . td1_label('is_orgadmin') . td1_input('is_orgadmin', '', 1) . "</tr>";
		echo "</table>";

		if ($this->update_guid !== 'NEW') {
			echo "<div style='background-color: #ffebee; border-left: 4px solid #b71c1c; padding: 15px; margin-top: 25px;'>";
			
			if ($is_me) {
				echo "<p style='color: #b71c1c; font-weight: bold; margin: 0;'>Ochrana účtu: Vlastní přístup ani administrátorská práva nelze odebrat.</p>";
				echo hidden_input('remove_access', '0');
				echo hidden_input('deactivate_global', '0');
			} else {
				echo "<table style='width: 100%; border-collapse: collapse;'>";
				echo "<tr>" . td1_label('remove_access') . td1_input('remove_access', '', 1) . "</tr>";
				if ($this->is_sysadmin) {
					echo "<tr>" . td1_label('deactivate_global') . td1_input('deactivate_global', '', 1) . "</tr>";
				}
				echo "</table>";
			}
			echo "</div>";
		}

		echo <<<HTML
			<div style="margin-top: 30px; border-top: 1px solid #eee; padding-top: 15px;">
				<button type="submit" name="button_save" value="1" class="btn btn-success">Uložit záznam</button>
			</div>
		</form>
HTML;
	}
}