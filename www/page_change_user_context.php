<?php
/**
 * =============================================================================
 * Třída: page_change_user_context
 * Účel: Stránka pro bezpečné přepnutí kontextu organizace a role uživatele.
 * Architektura: Potomek abstract_page, PRG vzor pro zpracování formuláře.
 * =============================================================================
 */

declare(strict_types=1);

class page_change_user_context extends abstract_page {

	public function __construct() {
		global $dbsession, $SID;
		$this->page_title = 'Změna kontextu - BCM Osiris';

		// Zpracování POST požadavku a provedení PRG přesměrování
		$target_org = getinput('target_organization', 'uuid'); // Zajistí formát v apostrofech nebo 'NULL'
		
		if ($target_org && $target_org !== 'NULL') {
			$user_uuid = guidliteral((string)$dbsession['user_account']);
			$client_ip = charliteral(get_client_ip_path(), 200);
			$wwwsession = charliteral($SID, 50);

			// Využití stávající robustní procedury pro bezpečný zápis relace
			$sql = "EXEC p_set_login 
				@user_uuid = {$user_uuid}, 
				@wwwsession = {$wwwsession}, 
				@client_ip = {$client_ip}, 
				@requested_org = {$target_org}";
			
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
		echo '<h1 class="page-heading">Změna pracovní organizace</h1>';
		echo '<p style="margin-bottom: 20px;">Vyberte organizaci, do které se chcete přepnout pro aktuální sezení:</p>';
		
		$orgs = sqlarray_simple("EXEC page_change_user_context 'main'");
		
		if (!$orgs) {
			echo '<div class="msg-err">Nemáte přístup do žádných organizací.</div>';
			return;
		}

		echo '<form action="index.php?page=change_user_context" method="POST">';
		echo '<table class="md-table" style="width: 100%; border-collapse: collapse;">';
		echo '<tbody>';
		
		foreach ($orgs as $org) {
			$uuid = htmlspecialchars((string)$org['organization'], ENT_QUOTES, 'UTF-8');
			$name = htmlspecialchars((string)$org['organization_name'], ENT_QUOTES, 'UTF-8');
			$isCurrent = ($org['organization'] === $org['current_organization']);
			$roleText = !empty($org['is_orgadmin']) ? 'Administrátor' : 'Uživatel';
			
			$checked = $isCurrent ? 'checked' : '';
			$rowClass = $isCurrent ? 'md-row-active' : 'md-row-inactive';
			$bgColor = $isCurrent ? '#f1f5f9' : 'transparent';
			$fontWeight = $isCurrent ? 'bold' : 'normal';
			
			echo "<tr class=\"{$rowClass}\" style=\"border-bottom: 1px solid #e2e8f0; background-color: {$bgColor}; transition: background 0.2s;\">";
			
			echo "<td style=\"padding: 12px; width: 40px; text-align: center;\">";
			echo "<input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}\" value=\"{$uuid}\" {$checked} style=\"cursor: pointer; transform: scale(1.2);\">";
			echo "</td>";
			
			echo "<td style=\"padding: 12px; cursor: pointer;\">";
			echo "<label for=\"org_{$uuid}\" style=\"display: block; cursor: pointer; font-weight: {$fontWeight}; font-size: 14px; color: #1e293b;\">{$name}</label>";
			echo "</td>";

			echo "<td style=\"padding: 12px; text-align: right; color: #64748b; font-size: 12px;\">";
			echo "Role: {$roleText}";
			echo "</td>";
			
			echo "</tr>";
		}
		
		echo '</tbody>';
		echo '</table>';
		
		echo '<div style="margin-top: 25px;">';
		echo '<button type="submit" class="btn btn-success">Přepnout organizaci</button>';
		echo '<a href="index.php?page=main" class="btn" style="background-color: #64748b; margin-left: 10px;">Zrušit</a>';
		echo '</div>';
		echo '</form>';
	}
}