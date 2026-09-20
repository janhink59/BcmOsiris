<?php
/**
 * =============================================================================
 * Třída: page_change_user_context
 * Účel: Stránka pro bezpečné přepnutí kontextu organizace a role uživatele.
 * Architektura: Potomek abstract_page, PRG vzor pro zpracování formuláře.
 * 
 * Vazby na okolí:
 * - Volá uloženou proceduru p_set_login, které předává požadované UUID 
 *   organizace a požadovanou roli (@requested_admin).
 * - Formulář čte data z procedury page_change_user_context.
 * =============================================================================
 */

declare(strict_types=1);

class page_change_user_context extends abstract_page {

	public function __construct() {
		global $dbsession, $SID;
		$this->page_title = 'Změna kontextu - BCM Osiris';

		// Zpracování POST požadavku a provedení PRG přesměrování
		// Hodnota přichází ve formátu "UUID|ROLE", např. "A1B2...|1"
		$target_input = getinput('target_organization', 'raw'); 
		
		if ($target_input) {
			$parts = explode('|', $target_input);
			$target_org = guidliteral($parts[0]);
			$target_admin = isset($parts[1]) ? (int)$parts[1] : 'NULL';

			$user_uuid = guidliteral((string)$dbsession['user_account']);
			$client_ip = charliteral($_SERVER['REMOTE_ADDR'] ?? '', 200);
			$wwwsession = charliteral($SID, 50);

			// Bezpečný zápis relace včetně explicitně požadované role
			$sql = "EXEC p_set_login 
				@user_uuid = {$user_uuid}, 
				@wwwsession = {$wwwsession}, 
				@client_ip = {$client_ip}, 
				@requested_org = {$target_org},
				@requested_admin = {$target_admin}";
			
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
		
		// Procedura vrací seznam organizací, do kterých má uživatel přístup
		$orgs = sqlarray_simple("EXEC page_change_user_context 'main'");
		
		if (!$orgs) {
			echo '<div class="msg-err">Nemáte přístup do žádných organizací.</div>';
			return;
		}

		echo '<form action="index.php?page=change_user_context" method="POST">';
		
		// Vložení lokálních stylů pro tabulku v rámci této abstraktní stránky
		echo <<<HTML
		<style>
			.md-table { width: 100%; border-collapse: collapse; margin-bottom: 25px; }
			.md-table th { background-color: #e9f2fa; padding: 10px; border: 1px solid #cbd5e1; text-align: left; }
			.md-table td { padding: 10px; border: 1px solid #cbd5e1; }
			.md-table tr:hover { background-color: #f1f5f9; }
			.md-row-active { background-color: #e6f7ff !important; font-weight: bold; }
			.md-row-inactive { background-color: #ffffff; }
			.radio-cell { text-align: center; width: 100px; }
			.radio-input { cursor: pointer; transform: scale(1.3); }
			.na-mark { color: #94a3b8; font-weight: normal; font-size: 16px; }
		</style>
HTML;

		echo '<table class="md-table">';
		echo '<thead>';
		echo '<tr>';
		echo '<th>Organizace</th>';
		echo '<th class="radio-cell">User</th>';
		echo '<th class="radio-cell">Admin</th>';
		echo '</tr>';
		echo '</thead>';
		echo '<tbody>';
		
		foreach ($orgs as $org) {
			$uuid = htmlspecialchars((string)$org['organization'], ENT_QUOTES, 'UTF-8');
			$name = htmlspecialchars((string)$org['organization_name'], ENT_QUOTES, 'UTF-8');
			$isCurrentOrg = ((string)$org['organization'] === (string)$org['current_organization']);
			$hasAdmin = !empty($org['is_orgadmin']);
			$currentEffectiveRole = !empty($dbsession['right_orgadmin']) ? 1 : 0;
			
			$isCurrentUser = ($isCurrentOrg && $currentEffectiveRole === 0);
			$isCurrentAdmin = ($isCurrentOrg && $currentEffectiveRole === 1);

			$rowClass = $isCurrentOrg ? 'md-row-active' : 'md-row-inactive';

			echo "<tr class=\"{$rowClass}\">";
			
			// 1. Sloupec: Organizace (kliknutím na název se může automaticky zvolit role Uživatel)
			echo "<td><label for=\"org_{$uuid}_0\" style=\"cursor: pointer; display: block;\">{$name}</label></td>";
			
			// 2. Sloupec: User
			$valUser = "{$uuid}|0";
			$checkedUser = $isCurrentUser ? 'checked' : '';
			echo "<td class=\"radio-cell\">";
			echo "<input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}_0\" value=\"{$valUser}\" {$checkedUser} class=\"radio-input\" title=\"Vstoupit jako Uživatel\">";
			echo "</td>";

			// 3. Sloupec: Admin
			echo "<td class=\"radio-cell\">";
			if ($hasAdmin) {
				$valAdmin = "{$uuid}|1";
				$checkedAdmin = $isCurrentAdmin ? 'checked' : '';
				echo "<input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}_1\" value=\"{$valAdmin}\" {$checkedAdmin} class=\"radio-input\" title=\"Vstoupit jako Administrátor\">";
			} else {
				echo "<span class=\"na-mark\" title=\"Nemáte administrátorská práva\">—</span>";
			}
			echo "</td>";
			
			echo "</tr>";
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