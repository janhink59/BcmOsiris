<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 22:50
 * Stránka: page_organization_licence.php
 * Účel: Master-Detail rozhraní pro evidenci žádostí a licencí organizací.
 * 
 * Logika a byznys procesy:
 * - Modul je dostupný exkluzivně pro Sysadminy ('S') a Developery ('D'), řídí zakládání nových tenantů.
 * - Jakmile je žádosti (licence) nastaven stav 'APPROVED', při uložení se
 *   automaticky triggeruje procedura p_process_organization_licence.
 * - Procedura obratem licenci zpracuje (vygeneruje organizaci, orgadmina
 *   a propojí jejich záznamy v DB) a stav finálně přepne na 'PROCESSED'.
 *
 * Změny:
 * 2026-10-15 22:50 - Přechod na objektovou architekturu (extends abstract_page_master_detail).
 *                  - Oprava kontroly oprávnění ze zrušeného right_sysadmin na active_role ('S', 'D').
 *                  - Oprava auditního klíče ze zrušeného user_access_uuid na login_session_uuid.
 *                  - Doplněn sloupec builtin_code (pro deterministický trigger) a is_developer.
 * =============================================================================
 */

declare(strict_types=1);

class page_organization_licence extends abstract_page_master_detail {

	private ?string $update_guid = null;                                     // Aktuálně vybraná licence nebo 'NEW'
	private array $states_opt = [];                                          // Číselník stavů licence
	private array $levels_opt = [];                                          // Číselník úrovní licence z DB

	public function __construct() {
		parent::__construct();                                               // Inicializace frází a kontroly role v předkovi

		global $dbsession;                                                   // Globální kontext relace
		$this->page_title = 'Správa licencí organizací';                     // Titulek stránky

		// Ochrana před nepovolaným přístupem (povoleno pro Sysadmin 'S' a Developer 'D')
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		if (!in_array($active_role, ['S', 'D'], true)) {
			$this->access_denied = true;                                     // Zamezení přístupu pro nižší role
			return;
		}

		$this->update_guid = getinput('update_guid', 'raw') ?: null;         // Načtení identifikátoru záznamu

		// Manuální mapování proměnných pro OsirisLib formovací vrstvu
		pageitem('builtin_code', 'Kód licence (zkratka)', 'Kód', 'Unikátní identifikátor licence', 'text', 'varchar', '200px', 0, 0, 80);
		pageitem('caption', 'Název organizace', 'Název organizace', 'Plný název nové organizace', 'text', 'varchar', '100%', 0, 0, 200);
		pageitem('login_domain', 'Login doména', 'Doména', 'Doména pro SSO (např. firma.cz)', 'text', 'varchar', '100%', 0, 0, 200);
		pageitem('licence_level', 'Úroveň licence', 'Úroveň', 'Zvolte požadovanou úroveň licence z číselníku', 'select', 'int', '200px', 0, 0, 0);
		pageitem('licence_state', 'Stav licence', 'Stav', 'Životní cyklus licence', 'select', 'varchar', '220px', 0, 0, 0);
		pageitem('is_developer', 'Vývojářská licence', 'Developer', 'Povolit vývojářský režim', 'checkbox', 'bit', '', 0, 0, 0);
		pageitem('admin_login', 'Login admina', 'Admin login', 'Přihlašovací jméno správce', 'text', 'varchar', '100%', 0, 0, 100);
		pageitem('admin_first_name', 'Jméno admina', 'Jméno', 'Křestní jméno správce', 'text', 'varchar', '100%', 0, 0, 100);
		pageitem('admin_last_name', 'Příjmení admina', 'Příjmení', 'Příjmení správce', 'text', 'varchar', '100%', 0, 0, 100);
		pageitem('admin_email', 'E-mail admina', 'E-mail', 'Kontaktní e-mail', 'text', 'varchar', '100%', 0, 0, 200);

		// Nastavení dynamických hodnot pro drop-down nabídky
		$this->states_opt = [                                                // Stavy životního cyklu licence
			'DRAFT'     => 'Koncept',
			'APPROVED'  => 'Schváleno (spustí aktivaci)',
			'PROCESSED' => 'Zpracováno (Aktivní)',
			'REJECTED'  => 'Zamítnuto'
		];
		$this->levels_opt = sqlarray("SELECT licence_level, name FROM licence_level ORDER BY licence_level");
	}

	/**
	 * Zpracování uložení formuláře (PRG vzor volaný z abstract_page::render při POST).
	 */
	protected function process_save(): void {
		if (!isset($_POST['button_save']) && !isset($_POST['btn_save'])) {
			return;
		}

		global $dbsession;                                                   // Globální kontext relace

		// Spuštění sanitizace a escapování (reginputs z OsirisLib transformuje data)
		reginputs('builtin_code:varchar,caption:varchar,login_domain:varchar,licence_level:int,licence_state:varchar,is_developer:bit');
		reginputs('admin_login:varchar,admin_first_name:varchar,admin_last_name:varchar,admin_email:varchar');
		
		global $builtin_code, $caption, $login_domain, $licence_level, $licence_state, $is_developer;
		global $admin_login, $admin_first_name, $admin_last_name, $admin_email;
		
		// Pokud nebyl zadán builtin_code, odvodíme ho z názvu organizace
		$raw_code = trim((string)getinput('builtin_code'));                  // Textová hodnota kódu licence
		if ($raw_code === '') {
			$raw_code = substr(trim((string)getinput('caption')), 0, 80);    // Odvození kódu z názvu organizace
			$builtin_code = charliteral($raw_code, 80);                      // Převod na bezpečný SQL literál
		}

		// Používáme login_session_uuid z dbsession pro auditní stopu
		$safe_access = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00'));

		if ($this->update_guid === 'NEW') {
			$sys_owner = guidliteral('0x00');                                // Systémový vlastník záznamu
			$q_orig = sqlrun("SELECT dbo.f_generate_original('organization_licence', {$sys_owner}, {$builtin_code}, NULL) AS orig");
			$row_orig = fetch($q_orig);                                      // Načtení deterministického originálu
			free_result($q_orig);                                            // Uvolnění výsledku dotazu

			$new_uuid = (string)($row_orig['orig'] ?? generateUUID());       // Deterministické UUID nové licence
			$safe_new_uuid = guidliteral($new_uuid);                         // Bezpečný SQL literál UUID
			
			$sql = "INSERT INTO organization_licence (
				uuid, object_owner, original, record_type, approval_status, 
				builtin_code, caption, login_domain, licence_level, licence_state, is_developer,
				admin_login, admin_first_name, admin_last_name, admin_email,
				who_created, who_modified
			) VALUES (
				{$safe_new_uuid}, 0x00, {$safe_new_uuid}, 'A', 'A',
				{$builtin_code}, {$caption}, {$login_domain}, {$licence_level}, {$licence_state}, {$is_developer},
				{$admin_login}, {$admin_first_name}, {$admin_last_name}, {$admin_email},
				{$safe_access}, {$safe_access}
			)";
			sqlrun($sql);                                                    // Vložení nové licence do DB
			$safe_uuid = $safe_new_uuid;                                     // Nastavení UUID pro případnou aktivaci
			$redirect_guid = $new_uuid;                                      // Cílové UUID pro přesměrování
		} else {
			$safe_uuid = guidliteral((string)$this->update_guid);            // SQL literál upravované licence
			$redirect_guid = (string)$this->update_guid;                     // Cílové UUID pro přesměrování

			$sql = "UPDATE organization_licence SET 
				builtin_code = {$builtin_code},
				caption = {$caption},
				login_domain = {$login_domain},
				licence_level = {$licence_level},
				licence_state = {$licence_state},
				is_developer = {$is_developer},
				admin_login = {$admin_login},
				admin_first_name = {$admin_first_name},
				admin_last_name = {$admin_last_name},
				admin_email = {$admin_email},
				date_modified = GETDATE(),
				who_modified = {$safe_access}
			WHERE original = {$safe_uuid} AND record_type = 'A'";
			sqlrun($sql);                                                    // Aktualizace licence v DB
		}

		// Detekce triggeru pro aktivaci tenanta (očekáváme stav APPROVED)
		if (trim((string)$licence_state, "'") === 'APPROVED') {
			// Parametr @who_modified byl odstraněn, procedura si kontext načítá sama z dbsession
			sqlrun("EXEC p_process_organization_licence @licence_original = {$safe_uuid}");
		}

		autoredirect("index.php?page=page_organization_licence&update_guid=" . urlencode($redirect_guid));
	}

	/**
	 * Vykreslení levého panelu (Master) se seznamem licencí.
	 */
	protected function render_master(): void {
		echo <<<HTML
		<div class="md-master-header">
			<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
				<h2 style="font-size: 16px; margin: 0; border: none; padding: 0;">Evidence organizací a licencí</h2>
				<a href="index.php?page=page_organization_licence&update_guid=NEW" class="btn">+ Nová licence</a>
			</div>
			<input type="text" id="master-filter" placeholder="Hledat..." style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>

		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
						<th>Organizace</th>
						<th>Admin (Login)</th>
						<th>E-mail</th>
						<th>Stav licence</th>
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$q = sqlrun("
			SELECT original, caption, admin_login, admin_email, licence_state 
			FROM organization_licence 
			WHERE record_type = 'A' AND removed = 0 
			ORDER BY date_created DESC
		");
		
		global $datarow;                                                     // Globální řádek pro čtení
		while (fetch_datarow($q)) {
			$uuid = (string)$datarow['original'];                            // Originální UUID licence
			$is_active = ($this->update_guid !== null && strcasecmp($uuid, $this->update_guid) === 0);
			$row_class = $is_active ? 'md-row-active' : '';                  // CSS třída aktivního řádku
			$id_attr = $is_active ? 'id="active-row"' : '';                  // HTML id aktivního řádku
			$row_url = htmlspecialchars("index.php?page=page_organization_licence&update_guid={$uuid}");
			$state_label = htmlspecialchars($this->states_opt[$datarow['licence_state']] ?? (string)$datarow['licence_state']);

			echo "<tr class=\"{$row_class}\" {$id_attr} style=\"cursor: pointer;\" onclick=\"document.location='{$row_url}'\">";
			echo td1_value('caption');
			echo td1_value('admin_login');
			echo td1_value('admin_email');
			echo "<td>{$state_label}</td>";
			echo "</tr>\n";
		}
		free_result($q);                                                     // Uvolnění výsledku dotazu

		echo <<<HTML
				</tbody>
			</table>
		</div>
		<script>
			document.getElementById('master-filter').addEventListener('input', function() {
				const term = this.value.toLowerCase();
				const rows = document.getElementById('master-list').querySelectorAll('tr');
				rows.forEach(row => {
					row.style.display = row.textContent.toLowerCase().includes(term) ? '' : 'none';
				});
			});
		</script>
HTML;
	}

	/**
	 * Vykreslení pravého panelu (Detail) s formulářem licence.
	 */
	protected function render_detail(): void {
		if (!$this->update_guid) {
			echo "<div class='msg-info'>Vyberte licenci ze seznamu vlevo nebo vytvořte novou.</div>";
			return;
		}

		global $datarow;                                                     // Globální pole pro aktuální záznam
		if ($this->update_guid === 'NEW') {
			$datarow = [                                                     // Výchozí hodnoty pro novou licenci
				'builtin_code' => '', 'caption' => '', 'login_domain' => '', 'licence_level' => 10,
				'licence_state' => 'DRAFT', 'is_developer' => 0,
				'admin_login' => '', 'admin_first_name' => '', 'admin_last_name' => '', 'admin_email' => '',
				'date_created' => null, 'who_created_info' => null, 'date_modified' => null, 'who_modified_info' => null
			];
		} else {
			$safe_uuid = guidliteral($this->update_guid);                    // SQL literál vybrané licence
			$q = sqlrun("
				SELECT l.*,
				       dbo.f_get_user_info(l.who_created) AS who_created_info,
				       dbo.f_get_user_info(l.who_modified) AS who_modified_info
				FROM organization_licence l
				WHERE l.original = {$safe_uuid} AND l.record_type = 'A' AND l.removed = 0
			");
			fetch_datarow($q);                                               // Načtení řádku do $datarow
			free_result($q);                                                 // Uvolnění výsledku dotazu

			if (!$datarow) {
				echo "<div class='msg-err'>Licence nebyla nalezena.</div>";
				return;
			}
		}

		$hidden_guid = hidden_input('update_guid', $this->update_guid);      // Skryté pole s ID záznamu

		echo <<<HTML
		<form method="POST" action="index.php?page=page_organization_licence" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			{$hidden_guid}
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">Detail organizace a licencování</h2>
				<div style="display: flex; gap: 10px;">
					<a href="index.php?page=page_organization_licence" class="btn btn-danger" onclick="isFormDirty = false;">Zahodit změny</a>
					<button type="submit" name="button_save" value="1" class="btn btn-success">Uložit záznam</button>
				</div>
			</div>

			<div class="md-detail-content">
				<table class="md-table" style="margin-bottom: 20px;">
HTML;
		echo "<tr>" . td1_label('builtin_code', "style='width: 30%;'") . td1_input('builtin_code') . "</tr>";
		echo "<tr>" . td1_label('caption') . td1_input('caption') . "</tr>";
		echo "<tr>" . td1_label('login_domain') . td1_input('login_domain') . "</tr>";
		echo "<tr>" . td1_label('licence_level') . td1_input('licence_level', '', $this->levels_opt) . "</tr>";
		echo "<tr>" . td1_label('licence_state') . td1_input('licence_state', '', $this->states_opt) . "</tr>";
		echo "<tr>" . td1_label('is_developer') . td1_input('is_developer', '', 1) . "</tr>";
		echo "<tr><td colspan='2'><hr style='border:0; border-top:1px dashed #ccc; margin:10px 0;'></td></tr>";
		echo "<tr>" . td1_label('admin_login') . td1_input('admin_login') . "</tr>";
		echo "<tr>" . td1_label('admin_first_name') . td1_input('admin_first_name') . "</tr>";
		echo "<tr>" . td1_label('admin_last_name') . td1_input('admin_last_name') . "</tr>";
		echo "<tr>" . td1_label('admin_email') . td1_input('admin_email') . "</tr>";
		echo "</table>";

		$this->render_audit_trail();                                         // Vykreslení auditní stopy

		echo "</div></form>";
	}
}