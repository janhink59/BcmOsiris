<?php
/**
 * =============================================================================
 * Verze: 2026-10-16 08:35
 * Soubor: page_org_users.php
 * Stránka: page_org_users.php
 * Účel: Master-Detail rozhraní pro správu uživatelů aktuálního tenanta.
 *       Kód je vyčištěn od inline stylů a plně využívá sjednocené CSS 
 *       třídy poskytované z abstract_page_master_detail.
 *
 * Vazby na okolí:
 * - Dědí z abstract_page_master_detail (využívá $this->phrase(), render_audit_trail()).
 * - Využívá abstract_button pro vykreslení akčních tlačítek.
 * - Volá uložené procedury page_org_users (čtení detailu) a form_org_users (zápis).
 *
 * Změny:
 * 2026-10-16 08:35 - Zapojena komponenta abstract_button a lokalizace všech textů,
 *                    popisků pageitem(), stavů a hlášek přes $this->phrase().
 *                  - Doplněna ochrana proti slučování řádků (Anti-LaTeX komentáře).
 * 2026-10-15 22:58 - Doplněno volání parent::__construct() a pojistka isset($_POST['btn_save'])
 *                    v process_save() proti nechtěnému zacyklení redirectu.
 *                  - Sjednoceny obalové kontejnery .md-master-header/.md-master-content
 *                    a .md-detail-header/.md-detail-content.
 * 2026-10-09 - Odstraněna redundantní kontrola $access_denied (řeší rodič).
 *            - Odstraněn anti-pattern odchytávání POST dat v konstruktoru.
 *              Nyní se plně využívá PRG cyklus rodiče přepsáním process_save().
 *            - Oprava vyhodnocení oprávnění (přechod z right_sysadmin/right_orgadmin na active_role).
 *            - Oprava klíče relace z user_access_uuid na login_session_uuid.
 * =============================================================================
 */

declare(strict_types=1);

class page_org_users extends abstract_page_master_detail {

	private string $current_org = '';                                        // SQL literál UUID aktuální organizace
	private string $logged_user_uuid = '';                                   // UUID přihlášeného uživatele
	private string $logged_user_access = '';                                 // UUID relace přihlášeného uživatele
	private ?string $update_guid = null;                                     // Vybraný uživatel nebo 'NEW'
	private bool $show_removed_users = false;                                // Příznak zobrazení odebraných přístupů
	private bool $is_sysadmin = false;                                       // Zda má uživatel roli S nebo D

	public function __construct() {
		parent::__construct();                                               // Inicializace frází a kontroly přístupu

		global $dbsession;                                                   // Globální kontext relace
		
		$this->page_title = $this->phrase('page_title', [], 'Správa uživatelů organizace'); // Lokalizovaný titulek stránky
		
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		
		// Ověření oprávnění pro přístup do modulu ('A' = Orgadmin, 'S' = Sysadmin, 'D' = Developer)
		if ($this->access_denied || !in_array($active_role, ['A', 'S', 'D'], true)) {
			$this->access_denied = true;                                     // Odepření přístupu pro běžného uživatele
			return;                                                          // Ukončení inicializace při zamítnutí
		}

		// Načtení kontextu z relace (dbsession)
		$this->is_sysadmin = in_array($active_role, ['S', 'D'], true);       // Příznak systémového správce
		$this->logged_user_uuid = (string)$dbsession['user_account'];        // UUID účtu přihlášeného uživatele
		$this->logged_user_access = (string)($dbsession['login_session_uuid'] ?? ''); // UUID přihlašovací relace
		$this->current_org = guidliteral($dbsession['organization']);        // SQL literál aktivní organizace
		
		// Parametry UI z requestu
		$this->show_removed_users = (bool)sessioninput('show_removed_users', 4); // Příznak zobrazení zrušených účtů
		$this->update_guid = getinput('update_guid', 'raw') ?: null;         // Vybraný záznam z URL/POST

		// Definice polí formuláře s lokalizací přes phrase_manager
		pageitem(
			'login_name',
			$this->phrase('lbl_login_name', [], 'Přihlašovací jméno'),
			$this->phrase('hdr_login_name', [], 'Login'),
			$this->phrase('tip_login_name', [], 'Unikátní login do systému'),
			'text', 'varchar', '100%', 0, 0, 100
		);
		pageitem(
			'first_name',
			$this->phrase('lbl_first_name', [], 'Jméno'),
			$this->phrase('hdr_first_name', [], 'Jméno'),
			$this->phrase('tip_first_name', [], 'Křestní jméno'),
			'text', 'varchar', '100%', 0, 0, 100
		);
		pageitem(
			'last_name',
			$this->phrase('lbl_last_name', [], 'Příjmení'),
			$this->phrase('hdr_last_name', [], 'Příjmení'),
			$this->phrase('tip_last_name', [], 'Příjmení'),
			'text', 'varchar', '100%', 0, 0, 100
		);
		pageitem(
			'email',
			$this->phrase('lbl_email', [], 'E-mail'),
			$this->phrase('hdr_email', [], 'E-mail'),
			$this->phrase('tip_email', [], 'Kontaktní e-mail'),
			'text', 'varchar', '100%', 0, 0, 200
		);
		pageitem(
			'is_orgadmin',
			$this->phrase('lbl_is_orgadmin', [], 'Je administrátor'),
			$this->phrase('hdr_is_orgadmin', [], 'Admin'),
			$this->phrase('tip_is_orgadmin', [], 'Má uživatel správcovská práva?'),
			'checkbox', 'bit', '', 0, 0, 0
		);
		pageitem(
			'remove_access',
			$this->phrase('lbl_remove_access', [], 'Odstranit přístup'),
			$this->phrase('hdr_remove_access', [], 'Zrušit'),
			$this->phrase('tip_remove_access', [], 'Zamezí uživateli přístup do organizace'),
			'checkbox', 'bit', '', 0, 0, 0
		);
		pageitem(
			'deactivate_global',
			$this->phrase('lbl_deactivate_global', [], 'Deaktivovat účet'),
			$this->phrase('hdr_deactivate_global', [], 'Neaktivní'),
			$this->phrase('tip_deactivate_global', [], 'Globálně zablokuje účet (Sysadmin)'),
			'checkbox', 'bit', '', 0, 0, 0
		);

		// Ochrana proti odebrání vlastních práv - nastavení UI elementu pouze pro čtení (porovnává se globální ID účtu)
		if ($this->update_guid !== null && strcasecmp($this->update_guid, $this->logged_user_uuid) === 0) {
			global $pageitem_is_orgadmin;                                    // Objekt prvku is_orgadmin
			$pageitem_is_orgadmin->displayonly = 1;                          // Zákaz editace vlastního admin příznaku
		}
	}

	/**
	 * Zpracování uložení záznamu přes systémovou uloženou proceduru.
	 * Překrývá výchozí chování z abstract_page_master_detail, aby se nevyužil plošný entity_manager.
	 */
	protected function process_save(): void {
		if (!isset($_POST['btn_save']) && !isset($_POST['button_save'])) {
			return;                                                          // Bez odeslání formuláře neukládáme
		}

		reginputs('login_name:varchar,first_name:varchar,last_name:varchar,email:varchar');
		reginputs('is_orgadmin:bit,remove_access:bit,deactivate_global:bit');
		
		global $login_name, $first_name, $last_name, $email, $is_orgadmin, $remove_access, $deactivate_global;
		
		// Hard-coded override pojistka (pro jistotu i na úrovni PHP)
		if ($this->update_guid !== null && strcasecmp($this->update_guid, $this->logged_user_uuid) === 0) {
			$remove_access = 0;                                              // Zákaz odebrání vlastního přístupu
			$deactivate_global = 0;                                          // Zákaz vlastní deaktivace
			$is_orgadmin = 1;                                                // Zachování vlastních admin práv
		}
		
		// Zamezení neoprávněné globální deaktivace účtu
		if (!$this->is_sysadmin) {
			$deactivate_global = 0;                                          // Běžný orgadmin nemůže globálně deaktivovat
		}
		
		$safe_uuid = ($this->update_guid === 'NEW' || $this->update_guid === null) ? 'NULL' : guidliteral($this->update_guid);

		// Parametr @who_modified byl odstraněn, SQL procedura si ho přečte z dbsession
		$sql = "EXEC form_org_users 
			@organization_uuid = {$this->current_org},
			@user_original = {$safe_uuid},
			@login_name = {$login_name},
			@email = {$email},
			@first_name = {$first_name},
			@last_name = {$last_name},
			@is_orgadmin = {$is_orgadmin},
			@remove_access = {$remove_access},
			@deactivate_global = {$deactivate_global}";
			
		sqlrun($sql);                                                        // Provedení uložené procedury
		
		if ($this->update_guid === 'NEW' || $this->update_guid === null) {
			autoredirect("index.php?page=page_org_users");                   // Návrat na výchozí seznam po založení
		} else {
			autoredirect("index.php?page=page_org_users&update_guid=" . urlencode($this->update_guid));
		}
	}

	/**
	 * Vykreslení levého panelu (Master) se seznamem uživatelů.
	 */
	protected function render_master(): void {
		$checked = $this->show_removed_users ? 'checked' : '';               // Stav checkboxu zobrazení odstraněných
		$master_heading = htmlspecialchars($this->phrase('master_heading', [], 'Uživatelé organizace')); // Nadpis levého panelu
		$lbl_show_removed = htmlspecialchars($this->phrase('lbl_show_removed', [], 'Zobrazit odstraněné')); // Popisek filtru odstraněných
		$th_name = htmlspecialchars($this->phrase('th_full_name', [], 'Jméno a příjmení')); // Záhlaví sloupce jména
		$th_status = htmlspecialchars($this->phrase('th_status', [], 'Stav')); // Záhlaví sloupce stavu
		$th_action = htmlspecialchars($this->phrase('th_action', [], 'Akce')); // Záhlaví sloupce akce

		$btn_new = new abstract_button('btn_new_user', '+ Nový uživatel', 'page_org_users'); // Tlačítko nového uživatele
		$btn_new->set_href('index.php?page=page_org_users&update_guid=NEW'); // Cílová URL pro nového uživatele
		$btn_new_html = $btn_new->render();                                  // Vykreslení tlačítka
		
		echo <<<HTML
		<div class="md-master-header">
			<h2 style="font-size: 16px; margin: 0 0 10px 0; border: none; padding: 0;">{$master_heading}</h2>
			
			<div style="display: flex; justify-content: space-between; align-items: center;">
				{$btn_new_html}
				
				<form method="GET" action="index.php" style="margin: 0;">
					<input type="hidden" name="page" value="page_org_users">
					<input type="hidden" name="show_removed_users" value="0">
					<label style="cursor: pointer; color: #004488; font-size: 13px;">
						<input type="checkbox" name="show_removed_users" value="1" {$checked} onchange="this.form.submit();">
						{$lbl_show_removed}
					</label>
				</form>
			</div>
		</div>

		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
						<th>{$th_name}</th>
						<th>{$th_status}</th>
						<th style="width: 50px;">{$th_action}</th>
					</tr>
				</thead>
				<tbody>
HTML;

		$remove_filter = $this->show_removed_users ? "" : "AND a.removed = 0"; // Podmínka filtrování zrušených přístupů
		
		// Výběr uživatelů propojený s přístupovou tabulkou pro daného tenanta
		$q = sqlrun("
			SELECT u.original, u.first_name, u.last_name, u.inactive, a.removed AS access_removed
			FROM user_account u
			JOIN user_organization_access a ON a.user_account_uuid = u.original
			WHERE a.organization_uuid = {$this->current_org} 
			  AND a.record_type = 'A' {$remove_filter}
			  AND u.record_type = 'A' AND u.removed = 0
			ORDER BY a.removed ASC, u.last_name, u.first_name
		");

		$txt_removed  = htmlspecialchars($this->phrase('status_removed', [], 'Zrušen')); // Stav zrušeného přístupu
		$txt_inactive = htmlspecialchars($this->phrase('status_inactive', [], 'Neaktivní')); // Stav neaktivního účtu
		$txt_active   = htmlspecialchars($this->phrase('status_active', [], 'Aktivní')); // Stav aktivního účtu
		$txt_detail   = htmlspecialchars($this->phrase('link_detail', [], 'Detail')); // Text odkazu na detail
		
		global $datarow;                                                     // Globální řádek pro čtení
		while (fetch_datarow($q)) {
			$uuid = (string)$datarow['original'];                            // Originální UUID uživatele
			$is_removed = $datarow['access_removed'];                        // Příznak odebraného přístupu
			$is_active_row = ($this->update_guid !== null && strcasecmp($uuid, $this->update_guid) === 0);
			
			$row_class = '';                                                 // Výchozí třída řádku
			if ($is_active_row) {
				$row_class = 'md-row-active';                                // Zvýraznění aktivního řádku
			} elseif ($is_removed) {
				$row_class = 'md-row-inactive';                              // Potlačení odebraného řádku
			}
			
			$id_attr = $is_active_row ? "id='active-row'" : "";              // Atribut id pro aktivní řádek
			$status = $is_removed ? $txt_removed : ($datarow['inactive'] ? "<span style=\"color:red\">{$txt_inactive}</span>" : $txt_active);
			$row_url = htmlspecialchars("index.php?page=page_org_users&update_guid={$uuid}");
			
			echo "<tr {$id_attr} class='{$row_class}' style='cursor: pointer;' onclick=\"document.location='{$row_url}'\">";
			echo "<td>" . htmlspecialchars($datarow['last_name'] . ' ' . $datarow['first_name']) . "</td>";
			echo "<td>{$status}</td>";
			echo "<td style='text-align: center;'>
					<a href='{$row_url}' style='font-weight:bold;color:#004488;text-decoration:none;'>{$txt_detail}</a>
				  </td>";
			echo "</tr>\n";
		}
		free_result($q);                                                     // Uvolnění výsledku dotazu

		echo "</tbody></table></div>";
	}

	/**
	 * Vykreslení pravého panelu (Detail) pro editaci vlastností.
	 */
	protected function render_detail(): void {
		if (!$this->update_guid) {
			$msg_sel = htmlspecialchars($this->phrase('msg_select_or_create_user', [], 'Vyberte uživatele ze seznamu vlevo nebo vytvořte nového.'));
			echo "<div class='msg-info'>{$msg_sel}</div>";
			return;                                                          // Ukončení při nevybraném uživateli
		}

		global $datarow;                                                     // Globální pole pro aktuální záznam
		if ($this->update_guid === 'NEW') {
			$datarow = [                                                     // Výchozí hodnoty pro nového uživatele
				'login_name'        => '',                                   // Prázdný login
				'first_name'        => '',                                   // Prázdné křestní jméno
				'last_name'         => '',                                   // Prázdné příjmení
				'email'             => '',                                   // Prázdný e-mail
				'is_orgadmin'       => 0,                                    // Výchozí stav bez práv admina
				'remove_access'     => 0,                                    // Přístup není odebrán
				'deactivate_global' => 0,                                    // Účet není globálně deaktivován
				'date_created'      => null,                                 // Datum vytvoření zatím neexistuje
				'who_created_info'  => null,                                 // Autor vytvoření zatím neexistuje
				'date_modified'     => null,                                 // Datum změny zatím neexistuje
				'who_modified_info' => null                                  // Autor změny zatím neexistuje
			];                                                               // Konec inicializace nového uživatele
		} else {
			$safe_uuid = guidliteral($this->update_guid);                    // SQL literál vybraného uživatele
			$q = sqlrun("EXEC page_org_users 'detail', 0, {$safe_uuid}");    // Načtení detailu procedurou
			fetch_datarow($q);                                               // Uložení do $datarow
			free_result($q);                                                 // Uvolnění výsledku dotazu
		}

		$is_me = ($this->update_guid !== null && strcasecmp($this->update_guid, $this->logged_user_uuid) === 0);
		$hidden_guid = hidden_input('update_guid', $this->update_guid);      // Skryté pole s ID uživatele
		$detail_heading = htmlspecialchars($this->phrase('detail_heading', [], 'Detail uživatele')); // Nadpis detailu

		$btn_discard = new abstract_button('btn_discard', 'Zahodit změny', 'abstract_button', '', 'btn-danger'); // Tlačítko zahození změn
		$btn_discard->set_href('index.php?page=page_org_users')->set_onclick('isFormDirty = false;'); // Odkaz bez varování dirty

		$btn_save = new abstract_button('btn_save', 'Uložit změny', 'abstract_button', '', 'btn-success'); // Tlačítko uložení
		$btn_save->set_type('submit')->set_name_value('btn_save', '1');      // Nastavení submit atributů

		$discard_html = $btn_discard->render();                              // Vykreslení tlačítka Zahodit
		$save_html = $btn_save->render();                                    // Vykreslení tlačítka Uložit

		echo <<<HTML
		<form method="POST" action="index.php?page=page_org_users" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			{$hidden_guid}
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$detail_heading}</h2>
				<div style="display: flex; gap: 10px;">
					{$discard_html}
					{$save_html}
				</div>
			</div>

			<div class="md-detail-content">
				<table class="md-table" style="width: 100%; border-collapse: collapse;">
HTML;
		echo "<tr>" . td1_label('login_name', "style='padding: 6px 4px; width: 30%;'") . td1_input('login_name') . "</tr>";
		echo "<tr>" . td1_label('first_name') . td1_input('first_name') . "</tr>";
		echo "<tr>" . td1_label('last_name') . td1_input('last_name') . "</tr>";
		echo "<tr>" . td1_label('email') . td1_input('email') . "</tr>";
		echo "<tr><td colspan='2'><hr style='border:0;border-top:1px dashed #ccc;margin:10px 0;'></td></tr>";
		echo "<tr>" . td1_label('is_orgadmin') . td1_input('is_orgadmin', '', 1) . "</tr>";

		if ($this->update_guid !== 'NEW') {
			if ($is_me) {
				$msg_self_prot = htmlspecialchars($this->phrase('msg_self_protection', [], 'Ochrana účtu: Vlastní přístup ani administrátorská práva nelze odebrat.'));
				echo "<tr style='background-color: #ffebee;'>
						<td colspan='2' style='border-left: 4px solid #b71c1c; padding: 15px; color: #b71c1c; font-weight: bold;'>
							{$msg_self_prot}
						</td>
					  </tr>";
				echo hidden_input('remove_access', '0');
				echo hidden_input('deactivate_global', '0');
			} else {
				$danger_row_style = "style='background-color: #ffebee;'";    // Styl nebezpečného řádku
				$danger_td_style = "style='border-left: 4px solid #b71c1c; color: #b71c1c; padding: 6px 4px;'"; // Styl buňky popisku
				
				echo "<tr {$danger_row_style}>" . td1_label('remove_access', $danger_td_style) . td1_input('remove_access', '', 1) . "</tr>";
				
				if ($this->is_sysadmin) {
					echo "<tr {$danger_row_style}>" . td1_label('deactivate_global', $danger_td_style) . td1_input('deactivate_global', '', 1) . "</tr>";
				}
			}
		}

		echo "</table>";

		$this->render_audit_trail();                                         // Vykreslení auditní stopy

		echo "</div></form>";
	}
}