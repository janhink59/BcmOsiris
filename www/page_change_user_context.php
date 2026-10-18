<?php
/**
 * =============================================================================
 * Verze: 2026-10-18 12:55
 * Soubor: page_change_user_context.php
 * Třída: page_change_user_context
 * Účel: Stránka pro bezpečné přepnutí kontextu organizace a role uživatele
 *       a pro správu žádostí o přístup / pozvánek do dalších organizací.
 * Architektura: Potomek abstract_page, PRG vzor pro zpracování formuláře.
 * 
 * Vazby na okolí:
 * - Volá uloženou proceduru p_set_login, které předává požadované UUID 
 *   organizace a požadovanou roli (@requested_role).
 * - Formulář čte data a spouští akce žádostí přes proceduru page_change_user_context.
 * - Využívá $this->phrase() a abstract_button pro plnou lokalizaci UI.
 *
 * Změny:
 * 2026-10-18 12:55 - Doplněno obousměrné schvalování přístupu mezi organizacemi:
 *                    přehled čekajících/zamítnutých žádostí a pozvánek od orgadminů
 *                    a formulář pro podání žádosti o přístup do další organizace.
 *                  - Striktní aplikace Anti-LaTeX pravidel (chr(124) místo svislítka,
 *                    OR/AND místo ||/&&, komentáře s diakritikou u všech řádků s $).
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
	 * Hodnota přepnutí přichází ve formátu "UUID|ROLE", např. "00000000-0000-0000-0000-000000000000|S".
	 */
	protected function process_save(): void {
		global $dbsession, $SID;                                             // Globální kontext relace a identifikátor SID

		// 1. Zpracování akcí obousměrného schvalování přístupu (žádosti uživatele a pozvánky od orgadminů)
		$req_org_raw = trim((string)getinput('request_org_uuid', 'raw'));    // Cílová organizace pro žádost nebo pozvánku
		$req_note_raw = trim((string)getinput('request_note', 'raw'));       // Volitelná poznámka k žádosti nebo odmítnutí

		if (isset($_POST['btn_request_access']) AND $req_org_raw !== '') {   // Odeslání nové žádosti o přístup do organizace
			$safe_org = guidliteral($req_org_raw);                           // SQL literál cílové organizace
			$safe_note = charliteral($req_note_raw);                         // SQL literál poznámky žadatele
			sqlrun("EXEC page_change_user_context 'request_access', {$safe_org}, {$safe_note}"); // Založení konceptu žádosti
			autoredirect('index.php?page=page_change_user_context');         // PRG přesměrování zpět na stránku kontextu
			return;                                                          // Ukončení zpracování
		}

		if (isset($_POST['btn_accept_invite'])) {                            // Přijetí pozvánky od orgadmina
			$acc_org = guidliteral((string)$_POST['btn_accept_invite']);     // SQL literál organizace z hodnoty tlačítka
			sqlrun("EXEC page_change_user_context 'accept_invitation', {$acc_org}"); // Schválení pozvánky uživatelem
			initsession();                                                   // Obnovení relace (aktualizace change_context_allowed)
			autoredirect('index.php?page=page_change_user_context');         // PRG přesměrování
			return;                                                          // Ukončení zpracování
		}

		if (isset($_POST['btn_reject_invite'])) {                            // Odmítnutí pozvánky od orgadmina
			$rej_org_raw = (string)$_POST['btn_reject_invite'];              // Surové UUID odmítané organizace
			$rej_org = guidliteral($rej_org_raw);                            // SQL literál odmítané organizace
			$note_key = 'reject_note_' . $rej_org_raw;                       // Klíč textového pole důvodu odmítnutí
			$rej_note = charliteral(trim((string)($_POST[$note_key] ?? ''))); // SQL literál důvodu odmítnutí
			sqlrun("EXEC page_change_user_context 'reject_invitation', {$rej_org}, {$rej_note}"); // Odmítnutí pozvánky
			autoredirect('index.php?page=page_change_user_context');         // PRG přesměrování
			return;                                                          // Ukončení zpracování
		}

		if (isset($_POST['btn_cancel_request'])) {                           // Stažení / smazání vlastní žádosti
			$can_org = guidliteral((string)$_POST['btn_cancel_request']);    // SQL literál organizace ke zrušení žádosti
			sqlrun("EXEC page_change_user_context 'cancel_request', {$can_org}"); // Odstranění konceptu žádosti
			autoredirect('index.php?page=page_change_user_context');         // PRG přesměrování
			return;                                                          // Ukončení zpracování
		}

		// 2. Standardní přepnutí aktivního kontextu (organizace a role)
		$target_input = (string)getinput('target_organization', 'raw');      // Načtení zvolené kombinace organizace a role
		
		if ($target_input !== '') {                                          // Pokud byla hodnota ve formuláři odeslána
			$parts = explode(chr(124), $target_input);                       // Rozdělení na UUID organizace a kód role
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
				@requested_role = {$target_role}";                           // Sestavení volání procedury p_set_login
			
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
		
		// Načtení oprávnění a žádostí (zajišťuje page_change_user_context.sql)
		$sys_roles = sqlfirstrow("EXEC page_change_user_context 'system_roles'"); // Načtení globálních rolí uživatele
		$orgs = sqlarray_simple("EXEC page_change_user_context 'main'");     // Načtení dostupných klientských organizací
		$pending_reqs = sqlarray_simple("EXEC page_change_user_context 'pending_requests'"); // Načtení žádostí a pozvánek
		$avail_orgs = sqlarray_simple("EXEC page_change_user_context 'available_orgs'"); // Načtení organizací pro novou žádost
		
		$is_sysadmin = !empty($sys_roles['is_system_admin']);                // Příznak oprávnění Sysadmin
		$is_developer = !empty($sys_roles['is_developer']);                  // Příznak oprávnění Developer
		
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
			.ssc-badge { display: inline-block; font-size: 11px; font-weight: bold; padding: 2px 6px; border-radius: 3px; }
			.ssc-badge-f { background-color: #dbeafe; color: #1e40af; border: 1px solid #3b82f6; }
			.ssc-badge-r { background-color: #fee2e2; color: #991b1b; border: 1px solid #ef4444; }
			.ssc-badge-inv { background-color: #fef3c7; color: #92400e; border: 1px solid #f59e0b; }
		</style>
HTML;

		if (!$orgs AND !$is_sysadmin AND !$is_developer) {                   // Pokud uživatel nemá žádný platný přístup
			$msg_no_access = htmlspecialchars($this->phrase('msg_no_org_access', [], 'Nemáte přístup do žádných organizací ani k systémovým rolím.')); // Chybová hláška
			echo "<div class=\"msg-err\">{$msg_no_access}</div>";
		} else {
			echo '<form action="index.php?page=page_change_user_context" method="POST">';

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
			
			$current_org_raw = (string)$dbsession['organization'];           // Aktuálně zvolená organizace v relaci
			$current_role = (string)$dbsession['active_role'];               // Aktuálně zvolená role v relaci
			$pipe = chr(124);                                                // Znak svislítka pro složení hodnoty přepínače

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
			if ($is_sysadmin OR $is_developer) {                             // Kontrola systémových oprávnění
				$uuid_sys = '00000000-0000-0000-0000-000000000000';          // Nulové UUID systémové organizace
				$isCurrentSys = ($current_org_raw === $uuid_sys);            // Zda je uživatel právě v systémovém jádru
				$rowClassSys = $isCurrentSys ? 'md-row-active' : 'md-row-system'; // CSS třída systémového řádku
				
				echo "<tr class=\"{$rowClassSys}\">";
				echo "<td><label style=\"cursor: default; display: block;\" class=\"sys-mark\">{$lbl_sys_core}</label></td>";
				
				// Sloupec Sysadmin
				echo "<td class=\"radio-cell\">";
				if ($is_sysadmin) {                                          // Pokud má uživatel právo Sysadmin
					$valS = $uuid_sys . $pipe . 'S';                         // Hodnota přepínače pro roli S
					$checkedS = ($isCurrentSys AND $current_role === 'S') ? 'checked' : ''; // Označení aktivní volby S
					echo "<label><input type=\"radio\" name=\"target_organization\" value=\"{$valS}\" {$checkedS} class=\"radio-input\" title=\"{$tip_sysadmin}\">";
					echo "<span style=\"font-size:11px;\">{$lbl_sysadmin}</span></label>";
				} else {
					echo "<span class=\"na-mark\">—</span>";
				}
				echo "</td>";
				
				// Sloupec Developer
				echo "<td class=\"radio-cell\">";
				if ($is_developer) {                                         // Pokud má uživatel právo Developer
					$valD = $uuid_sys . $pipe . 'D';                         // Hodnota přepínače pro roli D
					$checkedD = ($isCurrentSys AND $current_role === 'D') ? 'checked' : ''; // Označení aktivní volby D
					echo "<label><input type=\"radio\" name=\"target_organization\" value=\"{$valD}\" {$checkedD} class=\"radio-input\" title=\"{$tip_dev}\">";
					echo "<span style=\"font-size:11px;\">{$lbl_dev}</span></label>";
				} else {
					echo "<span class=\"na-mark\">—</span>";
				}
				echo "</td>";
				
				echo "</tr>";
			}
			
			// 2. Klientské organizace (Tenanti)
			if (is_array($orgs)) {                                           // Pokud existují dostupné organizace
				foreach ($orgs as $org) {                                    // Průchod schválenými organizacemi
					$uuid = htmlspecialchars((string)$org['organization'], ENT_QUOTES, 'UTF-8'); // UUID organizace
					$name = htmlspecialchars((string)$org['organization_name'], ENT_QUOTES, 'UTF-8'); // Název organizace
					$isCurrentOrg = ($uuid === $current_org_raw);            // Shoda s aktuální organizací
					$hasAdmin = !empty($org['is_orgadmin']);                 // Zda je uživatel adminem této organizace
					
					$isCurrentUser = ($isCurrentOrg AND $current_role === 'U'); // Zda je aktivní v roli User
					$isCurrentAdmin = ($isCurrentOrg AND $current_role === 'A'); // Zda je aktivní v roli Admin

					$rowClass = $isCurrentOrg ? 'md-row-active' : 'md-row-inactive'; // CSS třída řádku organizace

					echo "<tr class=\"{$rowClass}\">";
					
					// Název organizace
					echo "<td><label for=\"org_{$uuid}_U\" style=\"cursor: pointer; display: block;\">{$name}</label></td>";
					
					// Sloupec User
					$valUser = $uuid . $pipe . 'U';                          // Hodnota přepínače pro roli U
					$checkedUser = $isCurrentUser ? 'checked' : '';          // Označení aktivní volby U
					echo "<td class=\"radio-cell\">";
					echo "<label><input type=\"radio\" name=\"target_organization\" id=\"org_{$uuid}_U\" value=\"{$valUser}\" {$checkedUser} class=\"radio-input\" title=\"{$tip_user}\">";
					echo "<span style=\"font-size:11px;\">{$lbl_user}</span></label>";
					echo "</td>";

					// Sloupec Admin
					echo "<td class=\"radio-cell\">";
					if ($hasAdmin) {                                         // Pokud má v organizaci roli Admin
						$valAdmin = $uuid . $pipe . 'A';                     // Hodnota přepínače pro roli A
						$checkedAdmin = $isCurrentAdmin ? 'checked' : '';    // Označení aktivní volby A
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
			$btn_switch->set_type('submit');                                 // Nastavení typu tlačítka na submit

			$btn_cancel = new abstract_button('btn_cancel', 'Zrušit', 'abstract_button', '', 'btn-secondary'); // Tlačítko zrušení změny
			$btn_cancel->set_href('index.php?page=page_main')->set_style('margin-left: 10px;'); // Odkaz zpět na hlavní panel
			
			echo '<div style="margin-bottom: 30px;">';
			echo $btn_switch->render();                                      // Vykreslení tlačítka Přepnout kontext
			echo $btn_cancel->render();                                      // Vykreslení tlačítka Zrušit
			echo '</div>';
			echo '</form>';
		}

		// =====================================================================
		// SEKCE 2: Nevyřízené žádosti o přístup a pozvánky od orgadminů ('D')
		// =====================================================================
		if (is_array($pending_reqs) AND count($pending_reqs) > 0) {          // Pokud existují otevřené žádosti nebo pozvánky
			$hdr_pending = htmlspecialchars($this->phrase('heading_pending_access', [], 'Žádosti o přístup a pozvánky do organizací')); // Nadpis sekce
			$th_p_org = htmlspecialchars($this->phrase('th_pending_org', [], 'Organizace')); // Sloupec organizace
			$th_p_state = htmlspecialchars($this->phrase('th_pending_status', [], 'Stav a poznámka')); // Sloupec stavu
			$th_p_act = htmlspecialchars($this->phrase('th_pending_action', [], 'Akce')); // Sloupec akcí

			$badge_inv = htmlspecialchars($this->phrase('badge_invitation', [], 'Pozvánka od administrátora')); // Štítek pozvánky
			$badge_wait = htmlspecialchars($this->phrase('badge_waiting_approval', [], 'Čeká na schválení v organizaci')); // Štítek čekající žádosti
			$badge_rej = htmlspecialchars($this->phrase('badge_request_rejected', [], 'Zamítnuto / Vráceno')); // Štítek zamítnuté žádosti
			$ph_rej_note = htmlspecialchars($this->phrase('ph_reject_invite_reason', [], 'Volitelný důvod odmítnutí...')); // Placeholder odmítnutí

			echo "<hr style=\"border: 0; border-top: 2px solid #eee; margin: 25px 0;\">";
			echo "<h2 style=\"color: #004488; font-size: 18px; margin-top: 0;\">{$hdr_pending}</h2>";
			echo '<form action="index.php?page=page_change_user_context" method="POST">';
			echo '<table class="md-table">';
			echo "<thead><tr><th>{$th_p_org}</th><th>{$th_p_state}</th><th style=\"width: 280px;\">{$th_p_act}</th></tr></thead>";
			echo '<tbody>';

			foreach ($pending_reqs as $req) {                                // Průchod otevřenými žádostmi a pozvánkami
				$org_uuid = (string)$req['organization_uuid'];               // UUID cílové organizace
				$safe_org_uuid = htmlspecialchars($org_uuid);                // Ošetřené UUID organizace
				$safe_org_name = htmlspecialchars((string)$req['organization_name']); // Název organizace
				$app_status = (string)$req['approval_status'];               // Stav ('F' nebo 'R')
				$is_invite = !empty($req['is_invitation']);                  // Zda jde o pozvánku od orgadmina
				$note_txt = trim((string)$req['approval_note']);             // Poznámka nebo důvod zamítnutí
				$safe_note = htmlspecialchars($note_txt);                    // Ošetřený text poznámky

				if ($is_invite AND $app_status === 'F') {                    // Aktivní pozvánka čekající na souhlas uživatele
					$status_html = "<span class=\"ssc-badge ssc-badge-inv\">{$badge_inv}</span>"; // Žlutý štítek pozvánky
				} elseif ($app_status === 'R') {                             // Zamítnutá žádost nebo pozvánka
					$status_html = "<span class=\"ssc-badge ssc-badge-r\">{$badge_rej}</span>"; // Červený štítek zamítnutí
				} else {
					$status_html = "<span class=\"ssc-badge ssc-badge-f\">{$badge_wait}</span>"; // Modrý štítek čekání
				}

				if ($safe_note !== '') {                                     // Připojení poznámky pod štítek stavu
					$status_html .= "<div style=\"margin-top: 6px; font-size: 12px; color: #475569;\">{$safe_note}</div>"; // Výpis poznámky
				}

				$actions_html = '';                                          // HTML ovládacích tlačítek v řádku
				if ($is_invite AND $app_status === 'F') {                    // Tlačítka pro přijetí nebo odmítnutí pozvánky
					$btn_acc = new abstract_button('btn_accept_invite', 'Přijmout pozvánku', 'page_change_user_context', '', 'btn-success'); // Tlačítko přijetí
					$btn_acc->set_type('submit')->set_name_value('btn_accept_invite', $org_uuid); // Nastavení hodnoty UUID organizace

					$btn_rej = new abstract_button('btn_reject_invite', 'Odmítnout', 'page_change_user_context', '', 'btn-danger'); // Tlačítko odmítnutí
					$btn_rej->set_type('submit')->set_name_value('btn_reject_invite', $org_uuid)->set_style('margin-left: 6px;'); // Nastavení odmítnutí

					$actions_html = "<div style=\"margin-bottom: 6px;\">" . $btn_acc->render() . $btn_rej->render() . "</div>"; // Tlačítka akcí
					$actions_html .= "<input type=\"text\" name=\"reject_note_{$safe_org_uuid}\" placeholder=\"{$ph_rej_note}\" style=\"width: 100%; padding: 4px; font-size: 12px; box-sizing: border-box;\">"; // Pole důvodu
				} else {
					// Vlastní žádost uživatele (čekající 'F' nebo zamítnutá 'R') -> možnost zrušit / smazat
					$btn_del = new abstract_button('btn_cancel_request', 'Zrušit / Smazat žádost', 'page_change_user_context', '', 'btn-danger'); // Tlačítko smazání žádosti
					$btn_del->set_type('submit')->set_name_value('btn_cancel_request', $org_uuid); // Nastavení hodnoty UUID organizace
					$actions_html = $btn_del->render();                      // Vykreslení tlačítka smazání
				}

				echo "<tr>";
				echo "<td><strong>{$safe_org_name}</strong></td>";
				echo "<td>{$status_html}</td>";
				echo "<td>{$actions_html}</td>";
				echo "</tr>";
			}

			echo '</tbody></table></form>';
		}

		// =====================================================================
		// SEKCE 3: Formulář pro podání žádosti o přístup do další organizace
		// =====================================================================
		if (is_array($avail_orgs) AND count($avail_orgs) > 0) {              // Pokud v systému existují další organizace
			$hdr_req = htmlspecialchars($this->phrase('heading_request_new_org', [], 'Požádat o přístup do další organizace')); // Nadpis sekce
			$desc_req = htmlspecialchars($this->phrase('desc_request_new_org', [], 'Pokud potřebujete pracovat i v jiné organizaci, odešlete žádost jejímu administrátorovi ke schválení:')); // Popis
			$lbl_sel_org = htmlspecialchars($this->phrase('lbl_select_target_org', [], 'Cílová organizace:')); // Popisek roletky organizace
			$lbl_req_note = htmlspecialchars($this->phrase('lbl_request_note', [], 'Poznámka pro administrátora:')); // Popisek poznámky
			$ph_req_note = htmlspecialchars($this->phrase('ph_request_note', [], 'Volitelně uveďte důvod žádosti o přístup...')); // Placeholder poznámky

			$org_options = '';                                               // HTML opcí dostupných organizací
			foreach ($avail_orgs as $ao) {                                   // Průchod dostupnými organizacemi
				$ao_uuid = htmlspecialchars((string)$ao['organization_uuid']); // Ošetřené UUID organizace
				$ao_name = htmlspecialchars((string)$ao['organization_name']); // Ošetřený název organizace
				$ao_short = htmlspecialchars((string)$ao['shortname']);      // Ošetřená zkratka organizace
				$ao_label = ($ao_short !== '' AND $ao_short !== $ao_name) ? "{$ao_name} ({$ao_short})" : $ao_name; // Popisek volby
				$org_options .= "<option value=\"{$ao_uuid}\">{$ao_label}</option>"; // Přidání položky do roletky
			}

			$btn_req = new abstract_button('btn_request_access', 'Odeslat žádost o přístup', 'page_change_user_context'); // Tlačítko odeslání žádosti
			$btn_req->set_type('submit')->set_name_value('btn_request_access', '1'); // Nastavení submit atributů
			$req_btn_html = $btn_req->render();                              // Vykreslení tlačítka žádosti

			echo <<<HTML
			<hr style="border: 0; border-top: 2px solid #eee; margin: 25px 0;">
			<h2 style="color: #004488; font-size: 18px; margin-top: 0;">{$hdr_req}</h2>
			<p style="margin-bottom: 15px;">{$desc_req}</p>
			<form action="index.php?page=page_change_user_context" method="POST">
				<table class="md-table" style="margin-bottom: 15px;">
					<tr>
						<td style="width: 30%; font-weight: bold; background-color: #f8fafc;">{$lbl_sel_org}</td>
						<td>
							<select name="request_org_uuid" style="width: 100%; padding: 6px; box-sizing: border-box;" required>
								{$org_options}
							</select>
						</td>
					</tr>
					<tr>
						<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_req_note}</td>
						<td>
							<input type="text" name="request_note" placeholder="{$ph_req_note}" style="width: 100%; padding: 6px; box-sizing: border-box;">
						</td>
					</tr>
				</table>
				{$req_btn_html}
			</form>
HTML;
		}
	}
}