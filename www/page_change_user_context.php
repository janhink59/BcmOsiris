<?php
/**
 * =============================================================================
 * Verze: 2026-10-16 08:25
 * Soubor: page_change_user_context.php
 * Třída: page_change_user_context
 * Účel: Stránka pro bezpečné přepnutí kontextu organizace a role uživatele.
 * Architektura: Potomek abstract_page, PRG vzor pro zpracování formuláře.
 * 
 * Vazby na okolí:
 * - Volá uloženou proceduru p_set_login, které předává požadované UUID 
 *   organizace a požadovanou roli (@requested_role).
 * - Formulář čte data z procedury page_change_user_context.
 * - Využívá $this->phrase() a abstract_button pro plnou lokalizaci UI.
 *
 * Změny:
 * 2026-10-16 08:25 - Přesun zpracování POST dat z konstruktoru do metody process_save()
 *                    (dodržení zákazu zachytávání POST v konstruktorech).
 *                  - Zapojení abstract_button a phrase_manager ($this->phrase).
 *                  - Sjednocení URL odkazů na prefix page_ (page_main, page_change_user_context).
 * =============================================================================
 */

declare(strict_types=1);

class page_change_user_context extends abstract_page {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu
		$this->page_title = $this->phrase('page_title', [], 'Změna kontextu - BCM Osiris'); // Nastavení lokalizovaného titulku
	}

	/**
	 * Zpracování POST požadavku a provedení PRG přesměrování (voláno z abstract_page::render při POST).
	 * Hodnota přichází ve formátu "UUID|ROLE", např. "00000000-0000-0000-0000-000000000000|S"
	 */
	protected function process_save(): void {
		global $dbsession, $SID;                                             // Globální kontext relace a identifikátor SID

		$target_input = (string)getinput('target_organization', 'raw');      // Načtení zvolené kombinace organizace a role
		
		if ($target_input !== '') {                                          // Pokud byla hodnota ve formuláři odeslána
			$parts = explode('|', $target_input);                            // Rozdělení na UUID organizace a kód role
			$target_org = guidliteral($parts[0]);                            // Bezpečný SQL literál cílové organizace
			$target_role = isset($parts[1]) ? charliteral($parts[1], 1) : 'NULL'; // Bezpečný SQL literál požadované role

			$user_uuid = guidliteral((string)$dbsession['user_account']);    // SQL literál přihlášeného uživatele
			$client_ip = charliteral($_SERVER['REMOTE_ADDR'] ?? '', 200);    // SQL literál klientské IP adresy
			$wwwsession = charliteral($SID, 50);                             // SQL literál identifikátoru webové relace

			// Bezpečný zápis relace včetně explicitně požadované role
			$sql = "EXEC p_set_login 
				@user_uuid = {$user_uuid}, 
				@wwwsession = {$wwwsession}, 
				@client_ip = {$client_ip}, 
				@requested_org = {$target_org},
				@requested_role = {$target_role}";
			
			if (sqlrun($sql)) {                                              // Spuštění procedury pro změnu kontextu
				// Relace v databázi byla změněna, vynutíme znovunačtení do globální proměnné PHP
				initsession();                                               // Obnovení dat v $dbsession
				
				// Návrat na domovskou obrazovku v novém kontextu
				autoredirect('index.php?page=page_main');                    // PRG přesměrování na hlavní panel
			} else {
				$err_title = $this->phrase('err_context_title', [], 'Chyba při změně kontextu'); // Titulek chyby
				$err_msg = $this->phrase('err_context_save', [], 'Nepodařilo se zapsat novou relaci.'); // Text chyby
				fatal_error($err_title, $err_msg);                           // Zobrazení fatální chyby
			}
		}
	}

	protected function render_body(): void {
		global $dbsession;                                                   // Globální kontext přihlášeného uživatele
		
		$heading = htmlspecialchars($this->phrase('heading_change_org', [], 'Změna pracovní organizace')); // Hlavní nadpis stránky
		$intro = htmlspecialchars($this->phrase('intro_select_org_role', [], 'Vyberte organizaci a roli, pod kterou se chcete přihlásit pro aktuální sezení:')); // Úvodní text
		
		echo "<h1 class=\"page-heading\">{$heading}</h1>";
		echo "<p style=\"margin-bottom: 20px;\">{$intro}</p>";
		
		// Načtení oprávnění (zajišťuje page_change_user_context.sql)
		$sys_roles = sqlfirstrow("EXEC page_change_user_context 'system_roles'"); // Načtení globálních rolí uživatele
		$orgs = sqlarray_simple("EXEC page_change_user_context 'main'");     // Načtení dostupných klientských organizací
		
		$is_sysadmin = !empty($sys_roles['is_system_admin']);                // Příznak oprávnění Sysadmin
		$is_developer = !empty($sys_roles['is_developer']);                  // Příznak oprávnění Developer
		
		if (!$orgs && !$is_sysadmin && !$is_developer) {                     // Pokud uživatel nemá žádný platný přístup
			$msg_no_access = htmlspecialchars($this->phrase('msg_no_org_access', [], 'Nemáte přístup do žádných organizací ani k systémovým rolím.'));
			echo "<div class=\"msg-err\">{$msg_no_access}</div>";
			return;                                                          // Ukončení vykreslování těla
		}

		echo '<form action="index.php?page=page_change_user_context" method="POST">';
		
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

		$th_org  = htmlspecialchars($this->phrase('th_organization', [], 'Organizace / Oblast')); // Záhlaví sloupce organizace
		$th_base = htmlspecialchars($this->phrase('th_base_role', [], 'Základní role')); // Záhlaví sloupce základní role
		$th_high = htmlspecialchars($this->phrase('th_higher_role', [], 'Vyšší role')); // Záhlaví sloupce vyšší role

		echo '<table class="md-table">';
		echo '<thead>';
		echo '<tr>';
		echo "<th>{$th_org}</th>";
		echo "<th class=\"radio-cell\">{$th_base}</th>";
		echo "<th class=\"radio-cell\">{$th_high}</th>";
		echo '</tr>';
		echo '</thead>';
		echo '<tbody>';
		
		$current_org_raw = (string)$dbsession['organization'];               // Aktuálně zvolená organizace v relaci
		$current_role = (string)$dbsession['active_role'];                   // Aktuálně zvolená role v relaci

		$lbl_sys_core = htmlspecialchars($this->phrase('lbl_system_core', [], '⚙ Systémové jádro (0x00)')); // Popisek systémového jádra
		$tip_sysadmin = htmlspecialchars($this->phrase('tip_enter_sysadmin', [], 'Vstoupit jako Sysadmin')); // Tooltip volby Sysadmin
		$lbl_sysadmin = htmlspecialchars($this->phrase('lbl_role_sysadmin', [], 'Sysadmin')); // Popisek role Sysadmin
		$tip_dev      = htmlspecialchars($this->phrase('tip_enter_developer', [], 'Vstoupit jako Developer')); // Tooltip volby Developer
		$lbl_dev      = htmlspecialchars($this->phrase('lbl_role_developer', [], 'Developer')); // Popisek role Developer
		$tip_user     = htmlspecialchars($this->phrase('tip_enter_user', [], 'Vstoupit jako Uživatel')); // Tooltip volby User
		$lbl_user     = htmlspecialchars($this->phrase('lbl_role_user', [], 'User')); // Popisek role User
		$tip_admin    = htmlspecialchars($this->phrase('tip_enter_admin', [], 'Vstoupit jako Administrátor')); // Tooltip volby Admin
		$lbl_admin    = htmlspecialchars($this->phrase('lbl_role_admin', [], 'Admin')); // Popisek role Admin
		$tip_no_admin = htmlspecialchars($this->phrase('tip_no_admin_rights', [], 'Nemáte administrátorská práva')); // Tooltip chybějících práv
		
		// 1. Systémový řádek (0x00) - zobrazí se pouze, pokud má uživatel příslušná globální oprávnění
		if ($is_sysadmin || $is_developer) {                                 // Kontrola systémových oprávnění
			$uuid_sys = '00000000-0000-0000-0000-000000000000';              // Nulové UUID systémové organizace
			$isCurrentSys = ($current_org_raw === $uuid_sys);                // Zda je uživatel právě v systémovém jádru
			$rowClassSys = $isCurrentSys ? 'md-row-active' : 'md-row-system'; // CSS třída systémového řádku
			
			echo "<tr class=\"{$rowClassSys}\">";
			echo "<td><label style=\"cursor: default; display: block;\" class=\"sys-mark\">{$lbl_sys_core}</label></td>";
			
			// Sloupec Sysadmin
			echo "<td class=\"radio-cell\">";
			if ($is_sysadmin) {                                              // Pokud má uživatel právo Sysadmin
				$valS = "{$uuid_sys}|S";                                     // Hodnota přepínače pro roli S
				$checkedS = ($isCurrentSys && $current_role === 'S') ? 'checked' : ''; // Označení aktivní volby S
				echo "<label><input type=\"radio\" name=\"target_organization\" value=\"{$valS}\" {$checkedS} class=\"radio-input\" title=\"{$tip_sysadmin}\">";
				echo "<span style=\"font-size:11px;\">{$lbl_sysadmin}</span></label>";
			} else {
				echo "<span class=\"na-mark\">—</span>";
			}
			echo "</td>";
			
			// Sloupec Developer
			echo "<td class=\"radio-cell\">";
			if ($is_developer) {                                             // Pokud má uživatel právo Developer
				$valD = "{$uuid_sys}|D";                                     // Hodnota přepínače pro roli D
				$checkedD = ($isCurrentSys && $current_role === 'D') ? 'checked' : ''; // Označení aktivní volby D
				echo "<label><input type=\"radio\" name=\"target_organization\" value=\"{$valD}\" {$checkedD} class=\"radio-input\" title=\"{$tip_dev}\">";
				echo "<span style=\"font-size:11px;\">{$lbl_dev}</span></label>";
			} else {
				echo "<span class=\"na-mark\">—</span>";
			}
			echo "</td>";
			
			echo "</tr>";
		}
		
		// 2. Klientské organizace (Tenanti)
		if ($orgs) {                                                         // Pokud existují dostupné organizace
			foreach ($orgs as $org) {
				$uuid = htmlspecialchars((string)$org['organization'], ENT_QUOTES, 'UTF-8'); // UUID organizace
				$name = htmlspecialchars((string)$org['organization_name'], ENT_QUOTES, 'UTF-8'); // Název organizace
				$isCurrentOrg = ($uuid === $current_org_raw);                // Shoda s aktuální organizací
				$hasAdmin = !empty($org['is_orgadmin']);                     // Zda je uživatel adminem této organizace
				
				$isCurrentUser = ($isCurrentOrg && $current_role === 'U');   // Zda je aktivní v roli User
				$isCurrentAdmin = ($isCurrentOrg && $current_role === 'A');  // Zda je aktivní v roli Admin

				$rowClass = $isCurrentOrg ? 'md-row-active' : 'md-row-inactive'; // CSS třída řádku organizace

				echo "<tr class=\"{$rowClass}\">";
				
				// Název organizace
				echo "<td><label for=\"org_{$uuid}_U\" style=\"cursor: pointer; display: block;\">{$name}</label></td>";
				
				// Sloupec User
				$valUser = "{$uuid}|U";                                      // Hodnota přepínače pro roli U
				$checkedUser = $isCurrentUser ? 'checked' : '';              // Označení aktivní volby U
				echo "<td class=\"radio-cell\">";
				echo "<label><input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}_U\" value=\"{$valUser}\" {$checkedUser} class=\"radio-input\" title=\"{$tip_user}\">";
				echo "<span style=\"font-size:11px;\">{$lbl_user}</span></label>";
				echo "</td>";

				// Sloupec Admin
				echo "<td class=\"radio-cell\">";
				if ($hasAdmin) {                                             // Pokud má v organizaci roli Admin
					$valAdmin = "{$uuid}|A";                                 // Hodnota přepínače pro roli A
					$checkedAdmin = $isCurrentAdmin ? 'checked' : '';        // Označení aktivní volby A
					echo "<label><input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}_A\" value=\"{$valAdmin}\" {$checkedAdmin} class=\"radio-input\" title=\"{$tip_admin}\">";
					echo "<span style=\"font-size:11px;\">{$lbl_admin}</span></label>";
				} else {
					echo "<span class=\"na-mark\" title=\"{$tip_no_admin}\">—</span>";
				}
				echo "</td>";
				
				echo "</tr>";
			}
		}
		
		echo '</tbody>';
		echo '</table>';

		$btn_switch = new abstract_button('btn_switch_context', 'Přepnout kontext', 'page_change_user_context', '', 'btn-success'); // Tlačítko potvrzení změny
		$btn_switch->set_type('submit');                                     // Nastavení typu tlačítka na submit

		$btn_cancel = new abstract_button('btn_cancel', 'Zrušit', 'abstract_button', '', 'btn-secondary'); // Tlačítko zrušení změny
		$btn_cancel->set_href('index.php?page=page_main')->set_style('margin-left: 10px;'); // Odkaz zpět na hlavní panel
		
		echo '<div>';
		echo $btn_switch->render();                                          // Vykreslení tlačítka Přepnout kontext
		echo $btn_cancel->render();                                          // Vykreslení tlačítka Zrušit
		echo '</div>';
		echo '</form>';
	}
}