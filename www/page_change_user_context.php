<?php
/**
 * =============================================================================
 * Třída: page_change_user_context
 * Účel: Stránka pro bezpečné přepnutí kontextu organizace a role uživatele.
 * Architektura: Potomek abstract_page, PRG vzor pro zpracování formuláře.
 * 
 * Vazby na okolí:
 * - Volá uloženou proceduru p_set_login, které předává požadované UUID 
 *   organizace a požadovanou roli (@requested_role).
 * - Formulář čte data z procedury page_change_user_context.
 * =============================================================================
 */

declare(strict_types=1);

class page_change_user_context extends abstract_page {

	public function __construct() {
		global $dbsession, $SID;
		$this->page_title = 'Změna kontextu - BCM Osiris';

		// Zpracování POST požadavku a provedení PRG přesměrování
		// Hodnota přichází ve formátu "UUID|ROLE", např. "00000000-0000-0000-0000-000000000000|S"
		$target_input = getinput('target_organization', 'raw'); 
		
		if ($target_input) {
			$parts = explode('|', $target_input);
			$target_org = guidliteral($parts[0]);
			$target_role = isset($parts[1]) ? charliteral($parts[1], 1) : 'NULL';

			$user_uuid = guidliteral((string)$dbsession['user_account']);
			$client_ip = charliteral($_SERVER['REMOTE_ADDR'] ?? '', 200);
			$wwwsession = charliteral($SID, 50);

			// Bezpečný zápis relace včetně explicitně požadované role
			$sql = "EXEC p_set_login 
				@user_uuid = {$user_uuid}, 
				@wwwsession = {$wwwsession}, 
				@client_ip = {$client_ip}, 
				@requested_org = {$target_org},
				@requested_role = {$target_role}";
			
			if (sqlrun($sql)) {
				// Relace v databázi byla změněna, vynutíme znovunačtení do globální proměnné PHP
				initsession();
				
				// Návrat na domovskou obrazovku v novém kontextu
				autoredirect('index.php?page=main');
			} else {
				fatal_error('Chyba při změně kontextu', 'Nepodařilo se zapsat novou relaci.');
			}
		}
	}

	protected function render_body(): void {
		global $dbsession;
		
		echo '<h1 class="page-heading">Změna pracovní organizace</h1>';
		echo '<p style="margin-bottom: 20px;">Vyberte organizaci a roli, pod kterou se chcete přihlásit pro aktuální sezení:</p>';
		
		// Načtení oprávnění (zajišťuje page_change_user_context.sql)
		$sys_roles = sqlfirstrow("EXEC page_change_user_context 'system_roles'");
		$orgs = sqlarray_simple("EXEC page_change_user_context 'main'");
		
		$is_sysadmin = !empty($sys_roles['is_system_admin']);
		$is_developer = !empty($sys_roles['is_developer']);
		
		if (!$orgs && !$is_sysadmin && !$is_developer) {
			echo '<div class="msg-err">Nemáte přístup do žádných organizací ani k systémovým rolím.</div>';
			return;
		}

		echo '<form action="index.php?page=change_user_context" method="POST">';
		
		echo <<<HTML
		<style>
			.md-table { width: 100%; border-collapse: collapse; margin-bottom: 25px; }
			.md-table th { background-color: #e9f2fa; padding: 10px; border: 1px solid #cbd5e1; text-align: left; }
			.md-table td { padding: 10px; border: 1px solid #cbd5e1; }
			.md-table tr:hover { background-color: #f1f5f9; }
			.md-row-active { background-color: #e6f7ff !important; font-weight: bold; }
			.md-row-inactive { background-color: #ffffff; }
			.md-row-system { background-color: #fff1f2; }
			.md-row-system:hover { background-color: #ffe4e6 !important; }
			.radio-cell { text-align: center; width: 100px; }
			.radio-input { cursor: pointer; transform: scale(1.3); margin-right: 5px; }
			.na-mark { color: #94a3b8; font-weight: normal; font-size: 16px; }
			.sys-mark { color: #e11d48; font-weight: bold; }
		</style>
HTML;

		echo '<table class="md-table">';
		echo '<thead>';
		echo '<tr>';
		echo '<th>Organizace / Oblast</th>';
		echo '<th class="radio-cell">Základní role</th>';
		echo '<th class="radio-cell">Vyšší role</th>';
		echo '</tr>';
		echo '</thead>';
		echo '<tbody>';
		
		$current_org_raw = (string)$dbsession['organization'];
		$current_role = (string)$dbsession['active_role'];
		
		// 1. Systémový řádek (0x00) - zobrazí se pouze, pokud má uživatel příslušná globální oprávnění
		if ($is_sysadmin || $is_developer) {
			$uuid_sys = '00000000-0000-0000-0000-000000000000';
			$isCurrentSys = ($current_org_raw === $uuid_sys);
			$rowClassSys = $isCurrentSys ? 'md-row-active' : 'md-row-system';
			
			echo "<tr class=\"{$rowClassSys}\">";
			echo "<td><label style=\"cursor: default; display: block;\" class=\"sys-mark\">⚙ Systémové jádro (0x00)</label></td>";
			
			// Sloupec Sysadmin
			echo "<td class=\"radio-cell\">";
			if ($is_sysadmin) {
				$valS = "{$uuid_sys}|S";
				$checkedS = ($isCurrentSys && $current_role === 'S') ? 'checked' : '';
				echo "<label><input type=\"radio\" name=\"target_organization\" value=\"{$valS}\" {$checkedS} class=\"radio-input\" title=\"Vstoupit jako Sysadmin\">";
				echo "<span style=\"font-size:11px;\">Sysadmin</span></label>";
			} else {
				echo "<span class=\"na-mark\">—</span>";
			}
			echo "</td>";
			
			// Sloupec Developer
			echo "<td class=\"radio-cell\">";
			if ($is_developer) {
				$valD = "{$uuid_sys}|D";
				$checkedD = ($isCurrentSys && $current_role === 'D') ? 'checked' : '';
				echo "<label><input type=\"radio\" name=\"target_organization\" value=\"{$valD}\" {$checkedD} class=\"radio-input\" title=\"Vstoupit jako Developer\">";
				echo "<span style=\"font-size:11px;\">Developer</span></label>";
			} else {
				echo "<span class=\"na-mark\">—</span>";
			}
			echo "</td>";
			
			echo "</tr>";
		}
		
		// 2. Klientské organizace (Tenanti)
		if ($orgs) {
			foreach ($orgs as $org) {
				$uuid = htmlspecialchars((string)$org['organization'], ENT_QUOTES, 'UTF-8');
				$name = htmlspecialchars((string)$org['organization_name'], ENT_QUOTES, 'UTF-8');
				$isCurrentOrg = ($uuid === $current_org_raw);
				$hasAdmin = !empty($org['is_orgadmin']);
				
				$isCurrentUser = ($isCurrentOrg && $current_role === 'U');
				$isCurrentAdmin = ($isCurrentOrg && $current_role === 'A');

				$rowClass = $isCurrentOrg ? 'md-row-active' : 'md-row-inactive';

				echo "<tr class=\"{$rowClass}\">";
				
				// Název organizace
				echo "<td><label for=\"org_{$uuid}_U\" style=\"cursor: pointer; display: block;\">{$name}</label></td>";
				
				// Sloupec User
				$valUser = "{$uuid}|U";
				$checkedUser = $isCurrentUser ? 'checked' : '';
				echo "<td class=\"radio-cell\">";
				echo "<label><input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}_U\" value=\"{$valUser}\" {$checkedUser} class=\"radio-input\" title=\"Vstoupit jako Uživatel\">";
				echo "<span style=\"font-size:11px;\">User</span></label>";
				echo "</td>";

				// Sloupec Admin
				echo "<td class=\"radio-cell\">";
				if ($hasAdmin) {
					$valAdmin = "{$uuid}|A";
					$checkedAdmin = $isCurrentAdmin ? 'checked' : '';
					echo "<label><input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}_A\" value=\"{$valAdmin}\" {$checkedAdmin} class=\"radio-input\" title=\"Vstoupit jako Administrátor\">";
					echo "<span style=\"font-size:11px;\">Admin</span></label>";
				} else {
					echo "<span class=\"na-mark\" title=\"Nemáte administrátorská práva\">—</span>";
				}
				echo "</td>";
				
				echo "</tr>";
			}
		}
		
		echo '</tbody>';
		echo '</table>';
		
		echo '<div>';
		echo '<button type="submit" class="btn btn-success">Přepnout kontext</button>';
		echo '<a href="index.php?page=main" class="btn" style="background-color: #64748b; margin-left: 10px;">Zrušit</a>';
		echo '</div>';
		echo '</form>';
	}
}