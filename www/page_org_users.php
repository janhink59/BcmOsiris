<?php
/**
 * =============================================================================
 * Verze: 2026-10-27 19:55
 * Soubor: page_org_users.php
 * Stránka: page_org_users.php
 * Účel: Master-Detail rozhraní pro správu uživatelů aktuálního tenanta.
 *       Odděluje osobní údaje globálního účtu (user_account) od oprávnění
 *       v aktuální organizaci (user_organization_access) a podporuje
 *       obousměrné schvalování přístupu mezi organizacemi (žádosti a pozvánky).
 *
 * Vazby na okolí:
 * - Dědí z abstract_page_master_detail (využívá $this->phrase(), render_audit_trail(),
 *   asynchronní načítání detailu loadDetailPanel() a centrální JS filtrování levého panelu).
 * - Využívá abstract_button pro vykreslení akčních tlačítek.
 * - Využívá rich_text pro vykreslení a editaci formátované poznámky (note).
 * - Volá uložené procedury page_org_users (čtení seznamu i detailu přes
 *   sqlarray_simple a sqlfirstrow) a form_org_users (zápis).
 *
 * Změny:
 * 2026-10-27 19:55 - Napojení řádků v render_master() a tlačítek "+ Nový / Pozvat uživatele"
 *                    a "Zahodit změny" na asynchronní funkci loadDetailPanel() (zamezení
 *                    nechtěného refreshe levého panelu a ztráty filtru #master-filter).
 *                  - Pole poznámky (note) napojeno na třídu rich_text (Preview + modální editor).
 * 2026-10-22 16:15 - Odstraněn duplicitní inline <script> pro #master-filter
 *                    v render_master() (filtrování řeší centrálně předek).
 * 2026-10-18 18:15 - Oprava kolize otevřeného SQLSRV statementu ($dbquery v OsirisLib.php)
 *                    při vnořeném auto-discovery zápisu frází: čtení seznamu uživatelů
 *                    převedeno na sqlarray_simple() a čtení detailu na sqlfirstrow().
 * 2026-10-18 12:55 - Kompletní oddělení sekce osobních údajů účtu (user_account)
 *                    od sekce oprávnění v organizaci (user_organization_access:
 *                    is_orgadmin, right_translate, remove_access) a globální správy.
 *                  - Podpora obousměrného schvalování přístupu (koncepty 'D'):
 *                    schválení/odmítnutí žádosti uživatele a odeslání/zrušení pozvánky
 *                    pro existujícího uživatele z jiné organizace (bez přepsání jeho dat).
 * =============================================================================
 */

declare(strict_types=1);

if (file_exists(__DIR__ . '/rich_text.php')) {
	require_once __DIR__ . '/rich_text.php';
}

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
		
		$this->page_title =$this->phrase('page_title', [], 'Správa uživatelů organizace'); // Lokalizovaný titulek stránky
		
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		
		// Ověření oprávnění pro přístup do modulu ('A' = Orgadmin, 'S' = Sysadmin, 'D' = Developer)
		if ($this->access_denied OR !in_array($active_role, ['A', 'S', 'D'], true)) { // Kontrola oprávnění
			$this->access_denied = true;                                     // Odepření přístupu pro běžného uživatele
			return;                                                          // Ukončení inicializace při zamítnutí
		}

		// Načtení kontextu z relace (dbsession)
		$this->is_sysadmin = in_array($active_role, ['S', 'D'], true);       // Příznak systémového správce
		$this->logged_user_uuid = (string)$dbsession['user_account'];        // UUID účtu přihlášeného uživatele
		$this->logged_user_access = (string)($dbsession['login_session_uuid'] ?? ''); // UUID přihlašovací relace
		$this->current_org = guidliteral((string)$dbsession['organization']); // SQL literál aktivní organizace
		
		// Parametry UI z requestu
		$this->show_removed_users = (bool)sessioninput('show_removed_users', 4); // Příznak zobrazení zrušených účtů
		$raw_guid = trim((string)getinput('update_guid', 'raw'));            // Načtení identifikátoru vybraného záznamu
		$this->update_guid = ($raw_guid !== '') ?$raw_guid : null;          // Vybraný záznam z URL/POST
	}

	/**
	 * Zpracování uložení záznamu, pozvánky nebo schválení/odmítnutí žádosti přes proceduru form_org_users.
	 * Překrývá výchozí chování z abstract_page_master_detail.
	 */
	protected function process_save(): void {
		$action = '';                                                        // Výchozí prázdná akce
		if (isset($_POST['btn_save']) OR isset($_POST['button_save'])) {     // Standardní uložení nebo odeslání pozvánky
			$action = 'SAVE';                                                // Akce uložení
		} elseif (isset($_POST['btn_approve_access'])) {                     // Schválení žádosti uživatele o přístup
			$action = 'APPROVE';                                             // Akce schválení přístupu
		} elseif (isset($_POST['btn_reject_access'])) {                      // Odmítnutí žádosti uživatele o přístup
			$action = 'REJECT';                                              // Akce odmítnutí žádosti
		} elseif (isset($_POST['btn_cancel_invite'])) {                      // Zrušení odeslané pozvánky orgadminem
			$action = 'CANCEL_INVITE';                                       // Akce zrušení pozvánky
		}

		if ($action === '') {                                                // Pokud nebylo stisknuto žádné akční tlačítko
			return;                                                          // Bez odeslání formuláře neukládáme
		}

		// Ošetření a případná konverze formátované poznámky (note) přes třídu rich_text
		$raw_note = trim((string)($_POST['note'] ?? ''));                    // Surový text poznámky z formuláře
		if ($raw_note !== '' AND class_exists('rich_text') AND method_exists('rich_text', 'normalize_for_storage')) { // Normalizace rich_text
			$fmt_note = (string)($_POST['note__target_format'] ?? 'auto');   // Zvolený cílový formát poznámky
			$raw_note = (string)rich_text::normalize_for_storage($raw_note, $fmt_note ?: 'auto'); // Konverze a sanitizace
		}

		// Načtení a sanitizace osobních údajů účtu (user_account)
		$login_name        = charliteral(trim((string)($_POST['login_name'] ?? '')), 100);        // Přihlašovací jméno
		$user_title_before = charliteral(trim((string)($_POST['user_title_before'] ?? '')), 40);  // Titul před jménem
		$first_name        = charliteral(trim((string)($_POST['first_name'] ?? '')), 100);        // Křestní jméno
		$last_name         = charliteral(trim((string)($_POST['last_name'] ?? '')), 100);         // Příjmení
		$user_title_after  = charliteral(trim((string)($_POST['user_title_after'] ?? '')), 40);   // Titul za jménem
		$email             = charliteral(trim((string)($_POST['email'] ?? '')), 200);             // Kontaktní e-mail
		$phone             = charliteral(trim((string)($_POST['phone'] ?? '')), 50);              // Telefon
		$mobile            = charliteral(trim((string)($_POST['mobile'] ?? '')), 50);             // Mobilní telefon
		$department_name   = charliteral(trim((string)($_POST['department_name'] ?? '')), 150);   // Oddělení / útvar
		$job_title         = charliteral(trim((string)($_POST['job_title'] ?? '')), 150);         // Pracovní pozice
		$note              = charliteral($raw_note);                         // Poznámka k účtu

		// Načtení oprávnění v organizaci (user_organization_access)
		$is_orgadmin       = (!empty($_POST['is_orgadmin'])) ? 1 : 0;        // Příznak administrátora organizace
		$right_translate   = (!empty($_POST['right_translate'])) ? 1 : 0;    // Příznak oprávnění k překladům
		$remove_access     = (!empty($_POST['remove_access'])) ? 1 : 0;      // Příznak odebrání přístupu do organizace
		$approval_note     = charliteral(trim((string)($_POST['approval_note'] ?? ''))); // Poznámka k pozvánce nebo zamítnutí

		// Načtení globálních příznaků účtu (pouze pro roli S a D)
		$is_system_admin   = (!empty($_POST['is_system_admin'])) ? 1 : 0;    // Globální role Sysadmin
		$is_developer      = (!empty($_POST['is_developer'])) ? 1 : 0;       // Globální role Developer
		$allow_local_login = isset($_POST['allow_local_login']) ? ((!empty($_POST['allow_local_login'])) ? 1 : 0) : 1; // Povolení lokálního hesla
		$deactivate_global = (!empty($_POST['deactivate_global'])) ? 1 : 0;  // Globální deaktivace účtu

		// Hard-coded override pojistka proti odebrání vlastních práv i na úrovni PHP
		if ($this->update_guid !== null AND strcasecmp($this->update_guid, $this->logged_user_uuid) === 0) { // Kontrola vlastního účtu
			$remove_access = 0;                                              // Zákaz odebrání vlastního přístupu
			$deactivate_global = 0;                                          // Zákaz vlastní deaktivace
			$is_orgadmin = 1;                                                // Zachování vlastních admin práv
		}
		
		// Zamezení neoprávněné globální deaktivace účtu běžným orgadminem
		if (!$this->is_sysadmin) {                                           // Pokud uživatel není Sysadmin/Developer
			$deactivate_global = 0;                                          // Běžný orgadmin nemůže globálně deaktivovat
		}
		
		$safe_uuid = ($this->update_guid === 'NEW' OR $this->update_guid === null) ? 'NULL' : guidliteral($this->update_guid); // SQL literál UUID účtu
		$safe_action = charliteral($action, 20);                             // SQL literál prováděné akce

		$sql = "EXEC form_org_users 
			@organization_uuid = {$this->current_org},
			@user_original = {$safe_uuid},
			@action = {$safe_action},
			@login_name = {$login_name},
			@email = {$email},
			@first_name = {$first_name},
			@last_name = {$last_name},
			@user_title_before = {$user_title_before},
			@user_title_after = {$user_title_after},
			@phone = {$phone},
			@mobile = {$mobile},
			@department_name = {$department_name},
			@job_title = {$job_title},
			@note = {$note},
			@is_orgadmin = {$is_orgadmin},
			@right_translate = {$right_translate},
			@is_system_admin = {$is_system_admin},
			@is_developer = {$is_developer},
			@allow_local_login = {$allow_local_login},
			@remove_access = {$remove_access},
			@deactivate_global = {$deactivate_global},
			@approval_note = {$approval_note}";                              // Sestavení volání procedury form_org_users
			
		sqlrun($sql);                                                        // Provedení uložené procedury
		
		if ($this->update_guid === 'NEW' OR $this->update_guid === null OR $action === 'CANCEL_INVITE') { // Po založení nebo zrušení pozvánky
			autoredirect("index.php?page=page_org_users");                   // Návrat na výchozí seznam
		} else {
			autoredirect("index.php?page=page_org_users&update_guid=" . urlencode($this->update_guid)); // Přesměrování na detail
		}
	}

	/**
	 * Vykreslení levého panelu (Master) se seznamem uživatelů, žádostí o přístup a pozvánek.
	 */
	protected function render_master(): void {
		$checked = $this->show_removed_users ? 'checked' : '';               // Stav checkboxu zobrazení odstraněných
		$master_heading = htmlspecialchars($this->phrase('master_heading', [], 'Uživatelé organizace')); // Nadpis levého panelu
		$lbl_show_removed = htmlspecialchars($this->phrase('lbl_show_removed', [], 'Zobrazit odstraněné')); // Popisek filtru odstraněných
		$search_placeholder = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat uživatele...')); // Placeholder hledání
		$th_name = htmlspecialchars($this->phrase('th_full_name', [], 'Jméno a login')); // Záhlaví sloupce jména
		$th_roles = htmlspecialchars($this->phrase('th_org_roles', [], 'Práva')); // Záhlaví sloupce oprávnění
		$th_status = htmlspecialchars($this->phrase('th_status', [], 'Stav')); // Záhlaví sloupce stavu

		$txt_removed  = htmlspecialchars($this->phrase('status_removed', [], 'Přístup zrušen')); // Stav zrušeného přístupu
		$txt_inactive = htmlspecialchars($this->phrase('status_inactive', [], 'Účet neaktivní')); // Stav neaktivního účtu
		$txt_active   = htmlspecialchars($this->phrase('status_active', [], 'Aktivní')); // Stav aktivního účtu
		$txt_req_f    = htmlspecialchars($this->phrase('status_user_request', [], 'Žádost o přístup')); // Žádost uživatele
		$txt_inv_f    = htmlspecialchars($this->phrase('status_invited', [], 'Pozván (čeká se)')); // Pozvánka orgadmina
		$txt_req_r    = htmlspecialchars($this->phrase('status_rejected', [], 'Odmítnuto')); // Odmítnutá žádost nebo pozvánka
		$lbl_b_admin  = htmlspecialchars($this->phrase('badge_role_admin', [], 'Admin')); // Štítek Admin
		$lbl_b_trans  = htmlspecialchars($this->phrase('badge_role_trans', [], 'Překlady')); // Štítek Překlady

		$new_url = 'index.php?page=page_org_users&update_guid=NEW';          // Cílová URL pro nového uživatele
		$btn_new = new abstract_button('btn_new_user', '+ Nový / Pozvat uživatele', 'page_org_users'); // Tlačítko nového uživatele
		$btn_new->set_href($new_url)                                         // Nastavení odkazu tlačítka
			->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}"); // Asynchronní otevření bez refreshe levého panelu
		$btn_new_html = $btn_new->render();                                  // Vykreslení tlačítka
		
		echo <<<HTML
		<div class="md-master-header">
			<h2 style="font-size: 16px; margin: 0 0 10px 0; border: none; padding: 0;">{$master_heading}</h2>
			
			<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
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
			<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>

		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
						<th>{$th_name}</th>
						<th style="width: 90px;">{$th_roles}</th>
						<th style="width: 130px;">{$th_status}</th>
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$show_rem_bit = $this->show_removed_users ? 1 : 0;                   // Bitový parametr pro proceduru
		$rows = sqlarray_simple("EXEC page_org_users 'list', {$show_rem_bit}, NULL"); // Načtení celého result-setu do pole
		
		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as $row) {                                        // Průchod řádky seznamu uživatelů v paměti
				$uuid = (string)$row['user_uuid'];                           // Originální UUID uživatele
				$safe_uuid = htmlspecialchars($uuid);                        // Ošetřené UUID pro atribut data-uuid
				$rec_type = (string)$row['record_type'];                     // Typ záznamu ('A' nebo 'D')
				$app_status = (string)$row['approval_status'];               // Stav schválení ('A', 'F', 'R')
				$is_user_req = !empty($row['is_user_request']);              // Zda žádost podal sám uživatel
				$is_removed = !empty($row['access_removed']);                // Příznak odebraného přístupu
				$is_active_row = ($this->update_guid !== null AND strcasecmp($uuid, $this->update_guid) === 0); // Aktivní vybraný řádek
				
				$row_class = '';                                             // Výchozí třída řádku
				if ($is_active_row) {                                        // Pokud je řádek vybrán v detailu
					$row_class = 'md-row-active';                            // Zvýraznění aktivního řádku
				} elseif ($is_removed) {                                     // Pokud má uživatel odebraný přístup
					$row_class = 'md-row-inactive';                          // Potlačení odebraného řádku
				}
				
				$id_attr = $is_active_row ? "id='active-row'" : "";          // Atribut id pro aktivní řádek

				// Sestavení informace o stavu přístupu
				if ($rec_type === 'D') {                                     // Koncept žádosti nebo pozvánky
					if ($app_status === 'R') {                               // Odmítnutá žádost / pozvánka
						$status_html = "<span class=\"ssc-badge ssc-badge-r\" style=\"margin-left:0;\">{$txt_req_r}</span>"; // Červený štítek
					} elseif ($is_user_req) {                                // Příchozí žádost od uživatele ke schválení
						$status_html = "<span class=\"ssc-badge ssc-badge-f\" style=\"margin-left:0;\">{$txt_req_f}</span>"; // Modrý štítek
					} else {
						$status_html = "<span class=\"ssc-badge ssc-badge-d\" style=\"margin-left:0;\">{$txt_inv_f}</span>"; // Žlutý štítek pozvánky
					}
				} else {
					$status_html = $is_removed
						? $txt_removed
						: (!empty($row['inactive']) ? "<span style=\"color:#b71c1c;\">{$txt_inactive}</span>" : $txt_active); // Stav schváleného účtu
				}

				// Sestavení štítků oprávnění v organizaci
				$roles_badges = [];                                          // Pole štítků oprávnění
				if (!empty($row['is_orgadmin'])) {                           // Pokud je uživatel administrátorem organizace
					$roles_badges[] = "<span style=\"background:#e0f2fe; color:#0369a1; padding:1px 5px; border-radius:3px; font-size:11px; font-weight:bold;\">{$lbl_b_admin}</span>"; // Štítek Admin
				}
				if (!empty($row['right_translate'])) {                       // Pokud má uživatel právo překládat
					$roles_badges[] = "<span style=\"background:#f0fdf4; color:#15803d; padding:1px 5px; border-radius:3px; font-size:11px;\">{$lbl_b_trans}</span>"; // Štítek Překlady
				}
				$roles_html = !empty($roles_badges) ? implode(' ', $roles_badges) : '<span style="color:#94a3b8; font-size:11px;">User</span>'; // Výsledné HTML práv

				$full_name = trim((string)$row['last_name'] . ' ' . (string)$row['first_name']); // Celé jméno uživatele
				$login_str = (string)$row['login_name'];                     // Přihlašovací jméno uživatele
				$display_name = ($full_name !== '') ? htmlspecialchars($full_name) : htmlspecialchars($login_str); // Zobrazované jméno
				$safe_login = htmlspecialchars($login_str);                  // Ošetřený login

				$row_url = htmlspecialchars("index.php?page=page_org_users&update_guid=" . urlencode($uuid)); // Cílová URL řádku
				
				echo "<tr {$id_attr} class='{$row_class}' data-uuid='{$safe_uuid}' style='cursor: pointer;' onclick=\"if(window.loadDetailPanel){loadDetailPanel('{$row_url}', this);}else{document.location='{$row_url}';}\">";
				echo "<td><strong>{$display_name}</strong> <span style=\"color:#64748b; font-size:11px;\">({$safe_login})</span></td>";
				echo "<td>{$roles_html}</td>";
				echo "<td>{$status_html}</td>";
				echo "</tr>\n";
			}
		}

		echo <<<HTML
				</tbody>
			</table>
		</div>
HTML;
	}

	/**
	 * Vykreslení pravého panelu (Detail) s oddělením osobních dat (user_account)
	 * a oprávnění v organizaci (user_organization_access).
	 */
	protected function render_detail(): void {
		if ($this->update_guid === null) {                                   // Pokud není vybrán žádný uživatel
			$msg_sel = htmlspecialchars($this->phrase('msg_select_or_create_user', [], 'Vyberte uživatele ze seznamu vlevo nebo vytvořte / pozvěte nového.')); // Výzva
			echo "<div class='msg-info'>{$msg_sel}</div>";
			return;                                                          // Ukončení při nevybraném uživateli
		}

		global $datarow;                                                     // Globální pole pro aktuální záznam (využívá i render_audit_trail)
		$is_new = ($this->update_guid === 'NEW');                            // Příznak zakládání nebo pozvání nového uživatele

		if ($is_new) {                                                       // Výchozí prázdné hodnoty pro nového uživatele
			$datarow = [                                                     // Inicializace pole pro nového uživatele
				'login_name'        => '',                                   // Prázdný login
				'user_title_before' => '',                                   // Prázdný titul před
				'first_name'        => '',                                   // Prázdné křestní jméno
				'last_name'         => '',                                   // Prázdné příjmení
				'user_title_after'  => '',                                   // Prázdný titul za
				'email'             => '',                                   // Prázdný e-mail
				'phone'             => '',                                   // Prázdný telefon
				'mobile'            => '',                                   // Prázdný mobil
				'department_name'   => '',                                   // Prázdné oddělení
				'job_title'         => '',                                   // Prázdná pracovní pozice
				'note'              => '',                                   // Prázdná poznámka
				'is_system_admin'   => 0,                                    // Výchozí bez role Sysadmin
				'is_developer'      => 0,                                    // Výchozí bez role Developer
				'allow_local_login' => 1,                                    // Výchozí povolené lokální přihlášení
				'deactivate_global' => 0,                                    // Účet není globálně deaktivován
				'record_type'       => 'A',                                  // Výchozí typ záznamu
				'approval_status'   => 'A',                                  // Výchozí stav schválení
				'draft_author'      => '',                                   // Prázdný autor konceptu
				'approval_note'     => '',                                   // Prázdná poznámka schvalování
				'is_orgadmin'       => 0,                                    // Výchozí stav bez práv admina
				'right_translate'   => 0,                                    // Výchozí stav bez práva překladu
				'remove_access'     => 0,                                    // Přístup není odebrán
				'is_user_request'   => 0,                                    // Nejde o příchozí žádost
				'date_created'      => null,                                 // Datum vytvoření zatím neexistuje
				'who_created_info'  => null,                                 // Autor vytvoření zatím neexistuje
				'date_modified'     => null,                                 // Datum změny zatím neexistuje
				'who_modified_info' => null                                  // Autor změny zatím neexistuje
			];                                                               // Konec inicializace nového uživatele
		} else {
			$safe_uuid = guidliteral($this->update_guid);                    // SQL literál vybraného uživatele
			$datarow = sqlfirstrow("EXEC page_org_users 'detail', 1, {$safe_uuid}"); // Načtení detailu do pole přes sqlfirstrow()

			if (empty($datarow)) {                                           // Pokud záznam nebyl nalezen
				$msg_nf = htmlspecialchars($this->phrase('msg_user_not_found', [], 'Uživatel nebyl v této organizaci nalezen.')); // Chybová hláška
				echo "<div class='msg-err'>{$msg_nf}</div>";
				return;                                                      // Ukončení vykreslování detailu
			}
		}

		$is_me = (!$is_new AND strcasecmp($this->update_guid, $this->logged_user_uuid) === 0); // Zda uživatel upravuje sám sebe
		$rec_type = (string)($datarow['record_type'] ?? 'A');                // Typ záznamu ('A' nebo 'D')
		$app_status = (string)($datarow['approval_status'] ?? 'A');          // Stav schválení ('A', 'F', 'R')
		$is_user_req = !empty($datarow['is_user_request']);                  // Zda jde o žádost podanou samotným uživatelem
		$is_draft = (!$is_new AND $rec_type === 'D');                        // Zda jde o dosud neschválený přístup ('D')

		// Osobní údaje v user_account smí orgadmin měnit u zcela nového účtu nebo až po oboustranném schválení přístupu (record_type = 'A')
		$personal_readonly = ($is_draft AND !$this->is_sysadmin);            // Uzamčení osobních dat před schválením přístupu
		$pers_ro_attr = $personal_readonly ? 'readonly style="width: 100%; padding: 6px; box-sizing: border-box; background-color: #f4f4f4;"' : 'style="width: 100%; padding: 6px; box-sizing: border-box;"'; // Styl osobních polí
		$login_ro_attr = (!$is_new) ? 'readonly style="width: 100%; padding: 6px; box-sizing: border-box; background-color: #f4f4f4;"' : 'required style="width: 100%; padding: 6px; box-sizing: border-box;"'; // Login nelze u existujícího měnit

		$safe_update_guid = htmlspecialchars($this->update_guid);            // Ošetřené UUID pro skryté pole
		$detail_heading = $is_new
			? htmlspecialchars($this->phrase('detail_heading_new', [], 'Nový uživatel / Pozvánka do organizace'))
			: htmlspecialchars($this->phrase('detail_heading', [], 'Detail uživatele a oprávnění')); // Nadpis detailu

		// Sestavení tlačítek v hlavičce detailu podle stavu záznamu
		$header_buttons = [];                                                // Pole HTML tlačítek v hlavičce
		$discard_url = 'index.php?page=page_org_users';                      // URL pro zahození změn

		$btn_discard = new abstract_button('btn_discard', 'Zahodit změny', 'abstract_button', '', 'btn-danger'); // Tlačítko zahození změn
		$btn_discard->set_href($discard_url)                                 // Cílová URL při zahození změn
			->set_onclick("isFormDirty = false; if(window.loadDetailPanel){loadDetailPanel('{$discard_url}');return false;}"); // Asynchronní zavření detailu
		$header_buttons[] = $btn_discard->render();                          // Přidání tlačítka Zahodit změny

		if ($is_draft AND $is_user_req) {                                    // Příchozí žádost uživatele o přístup -> Schválit / Odmítnout
			$btn_rej = new abstract_button('btn_reject_access', 'Odmítnout žádost', 'page_org_users', '', 'btn-danger'); // Tlačítko odmítnutí
			$btn_rej->set_type('submit')->set_name_value('btn_reject_access', '1'); // Nastavení submit atributů
			$header_buttons[] = $btn_rej->render();                          // Přidání tlačítka Odmítnout žádost

			$btn_app = new abstract_button('btn_approve_access', 'Schválit přístup', 'page_org_users', '', 'btn-success'); // Tlačítko schválení
			$btn_app->set_type('submit')->set_name_value('btn_approve_access', '1'); // Nastavení submit atributů
			$header_buttons[] = $btn_app->render();                          // Přidání tlačítka Schválit přístup
		} elseif ($is_draft AND !$is_user_req) {                             // Odchozí pozvánka vystavená orgadminem -> Zrušit / Aktualizovat
			$btn_can = new abstract_button('btn_cancel_invite', 'Zrušit pozvánku', 'page_org_users', '', 'btn-danger'); // Tlačítko zrušení pozvánky
			$btn_can->set_type('submit')->set_name_value('btn_cancel_invite', '1')->set_onclick('isFormDirty = false;'); // Submit zrušení
			$header_buttons[] = $btn_can->render();                          // Přidání tlačítka Zrušit pozvánku

			$btn_save = new abstract_button('btn_save', 'Aktualizovat pozvánku', 'page_org_users', '', 'btn-success'); // Tlačítko uložení pozvánky
			$btn_save->set_type('submit')->set_name_value('btn_save', '1');  // Submit uložení
			$header_buttons[] = $btn_save->render();                         // Přidání tlačítka Aktualizovat
		} else {
			$btn_save = new abstract_button('btn_save', 'Uložit změny', 'abstract_button', '', 'btn-success'); // Standardní tlačítko uložení
			$btn_save->set_type('submit')->set_name_value('btn_save', '1');  // Nastavení submit atributů
			$header_buttons[] = $btn_save->render();                         // Přidání tlačítka Uložit změny
		}

		$buttons_html = implode("\n\t\t\t\t\t", $header_buttons);            // Spojení tlačítek hlavičky

		echo <<<HTML
		<form method="POST" action="index.php?page=page_org_users" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="update_guid" value="{$safe_update_guid}">
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$detail_heading}</h2>
				<div style="display: flex; gap: 8px; flex-wrap: wrap;">
					{$buttons_html}
				</div>
			</div>

			<div class="md-detail-content">
HTML;

		// Informační pruhy pro režim nového uživatele nebo rozpracované žádosti / pozvánky ('D')
		$app_note_val = htmlspecialchars((string)($datarow['approval_note'] ?? '')); // Ošetřená poznámka schvalování
		if ($is_new) {                                                       // Nápověda při přidávání uživatele
			$msg_new_info = htmlspecialchars($this->phrase('msg_new_or_invite_info', [], 'Pokud přidáváte uživatele, který již má účet v jiné organizaci, zadejte pouze jeho Přihlašovací jméno (login) a nastavte mu oprávnění níže – systém mu odešle pozvánku ke schválení a jeho osobní údaje nepřepíše. Pokud login dosud neexistuje, vyplňte i osobní údaje pro založení nového účtu.')); // Text nápovědy
			echo "<div class=\"msg-info\" style=\"margin-bottom: 15px; font-weight: normal; font-size: 13px;\">{$msg_new_info}</div>";
		} elseif ($is_draft) {                                               // Informační pruh pro koncept přístupu ('D')
			if ($app_status === 'R') {                                       // Odmítnutá žádost nebo pozvánka
				$msg_r = htmlspecialchars($this->phrase('msg_access_rejected_banner', [], 'Tento návrh přístupu byl odmítnut.')); // Hláška odmítnutí
				echo "<div class=\"msg-err\" style=\"margin-bottom: 15px;\">{$msg_r}" . ($app_note_val !== '' ? "<div style=\"margin-top:4px; font-weight:normal;\">{$app_note_val}</div>" : "") . "</div>";
			} elseif ($is_user_req) {                                        // Žádost podaná samotným uživatelem
				$msg_u_req = htmlspecialchars($this->phrase('msg_user_requested_access_banner', [], 'Tento uživatel požádal o přístup do vaší organizace. Zkontrolujte jeho oprávnění níže a klikněte na „Schválit přístup“ nebo „Odmítnout žádost“. Osobní údaje účtu budou zpřístupněny k úpravám až po schválení přístupu.')); // Hláška žádosti
				echo "<div class=\"msg-info\" style=\"margin-bottom: 15px;\">{$msg_u_req}" . ($app_note_val !== '' ? "<div style=\"margin-top:6px; font-weight:normal;\"><strong>Poznámka žadatele:</strong> {$app_note_val}</div>" : "") . "</div>";
			} else {
				$msg_inv = htmlspecialchars($this->phrase('msg_orgadmin_invited_banner', [], 'Tomuto existujícímu uživateli byla odeslána pozvánka do vaší organizace. Přístup i možnost úpravy osobních údajů se aktivují, jakmile uživatel pozvánku přijme ve svém okně „Změna kontextu“.')); // Hláška pozvánky
				echo "<div class=\"msg-info\" style=\"margin-bottom: 15px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e;\">{$msg_inv}</div>";
			}
		}

		// =====================================================================
		// SEKCE 1: Oprávnění a přístup v této organizaci (user_organization_access)
		// =====================================================================
		$grp_perm = htmlspecialchars($this->phrase('grp_org_permissions', [], '1. Oprávnění a přístup v této organizaci (user_organization_access)')); // Nadpis sekce oprávnění
		$lbl_orgadmin = htmlspecialchars($this->phrase('lbl_is_orgadmin', [], 'Administrátor organizace (is_orgadmin)')); // Popisek admina
		$tip_orgadmin = htmlspecialchars($this->phrase('tip_is_orgadmin', [], 'Umožňuje spravovat uživatele a nastavení v rámci této organizace')); // Tooltip admina
		$lbl_trans = htmlspecialchars($this->phrase('lbl_right_translate', [], 'Právo pořizovat překlady (right_translate)')); // Popisek překladatele
		$tip_trans = htmlspecialchars($this->phrase('tip_right_translate', [], 'Opravňuje uživatele k ukládání překladů (v garantující organizaci i globálně)')); // Tooltip překladatele
		$lbl_rem = htmlspecialchars($this->phrase('lbl_remove_access', [], 'Odebrat přístup do této organizace')); // Popisek odebrání přístupu
		$lbl_app_note = htmlspecialchars($this->phrase('lbl_access_approval_note', [], 'Poznámka k pozvánce / důvod zamítnutí:')); // Popisek poznámky

		$chk_orgadmin = (!empty($datarow['is_orgadmin'])) ? 'checked' : '';  // Zaškrtnutí is_orgadmin
		$chk_trans = (!empty($datarow['right_translate'])) ? 'checked' : ''; // Zaškrtnutí right_translate
		$chk_rem = (!empty($datarow['remove_access'])) ? 'checked' : '';     // Zaškrtnutí remove_access
		$dis_me_admin = $is_me ? 'disabled' : '';                            // Vlastní admin příznak nelze odškrtnout

		echo "<h3 style=\"margin-top: 5px; color: #004488; font-size: 15px;\">{$grp_perm}</h3>";
		echo "<table class=\"md-table\" style=\"margin-bottom: 25px;\">";
		echo "<tr title=\"{$tip_orgadmin}\"><td style=\"width: 35%;\"><strong>{$lbl_orgadmin}:</strong></td><td>";
		if ($is_me) {                                                        // Pojistka pro skryté odeslání vlastního is_orgadmin = 1
			echo "<input type=\"hidden\" name=\"is_orgadmin\" value=\"1\">";
		} else {
			echo "<input type=\"hidden\" name=\"is_orgadmin\" value=\"0\">";
		}
		echo "<input type=\"checkbox\" name=\"is_orgadmin\" value=\"1\" {$chk_orgadmin} {$dis_me_admin}></td></tr>";

		echo "<tr title=\"{$tip_trans}\"><td><strong>{$lbl_trans}:</strong></td><td>";
		echo "<input type=\"hidden\" name=\"right_translate\" value=\"0\">";
		echo "<input type=\"checkbox\" name=\"right_translate\" value=\"1\" {$chk_trans}></td></tr>";

		if ($is_new OR $is_draft) {                                          // Pole poznámky pro pozvánku nebo zamítnutí žádosti
			echo "<tr><td><strong>{$lbl_app_note}</strong></td><td>";
			echo "<input type=\"text\" name=\"approval_note\" value=\"{$app_note_val}\" style=\"width: 100%; padding: 6px; box-sizing: border-box;\"></td></tr>";
		}

		if (!$is_new AND !$is_draft) {                                       // Možnost odebrání již schváleného přístupu
			if ($is_me) {                                                    // Ochrana vlastního účtu před odebráním přístupu
				$msg_self_prot = htmlspecialchars($this->phrase('msg_self_protection', [], 'Ochrana účtu: Vlastní přístup ani administrátorská práva nelze odebrat.')); // Hláška
				echo "<tr style=\"background-color: #ffebee;\"><td colspan=\"2\" style=\"border-left: 4px solid #b71c1c; padding: 10px; color: #b71c1c; font-weight: bold;\">{$msg_self_prot}<input type=\"hidden\" name=\"remove_access\" value=\"0\"></td></tr>";
			} else {
				echo "<tr style=\"background-color: #ffebee;\"><td style=\"border-left: 4px solid #b71c1c; color: #b71c1c;\"><strong>{$lbl_rem}:</strong></td><td>";
				echo "<input type=\"hidden\" name=\"remove_access\" value=\"0\">";
				echo "<input type=\"checkbox\" name=\"remove_access\" value=\"1\" {$chk_rem}></td></tr>";
			}
		}
		echo "</table>";

		// =====================================================================
		// SEKCE 2: Osobní a kontaktní údaje účtu (user_account)
		// =====================================================================
		$grp_pers = htmlspecialchars($this->phrase('grp_personal_data', [], '2. Osobní a kontaktní údaje účtu (user_account)')); // Nadpis osobní sekce
		$lbl_login = htmlspecialchars($this->phrase('lbl_login_name', [], 'Přihlašovací jméno (login)')); // Popisek loginu
		$lbl_t_bef = htmlspecialchars($this->phrase('lbl_title_before', [], 'Titul před jménem')); // Popisek titulu před
		$lbl_fname = htmlspecialchars($this->phrase('lbl_first_name', [], 'Křestní jméno')); // Popisek jména
		$lbl_lname = htmlspecialchars($this->phrase('lbl_last_name', [], 'Příjmení')); // Popisek příjmení
		$lbl_t_aft = htmlspecialchars($this->phrase('lbl_title_after', [], 'Titul za jménem')); // Popisek titulu za
		$lbl_email = htmlspecialchars($this->phrase('lbl_email', [], 'E-mail (nemusí být unikátní)')); // Popisek e-mailu
		$lbl_phone = htmlspecialchars($this->phrase('lbl_phone', [], 'Telefon')); // Popisek telefonu
		$lbl_mob   = htmlspecialchars($this->phrase('lbl_mobile', [], 'Mobil')); // Popisek mobilu
		$lbl_dept  = htmlspecialchars($this->phrase('lbl_department', [], 'Oddělení / Útvar')); // Popisek oddělení
		$lbl_job   = htmlspecialchars($this->phrase('lbl_job_title', [], 'Pracovní pozice')); // Popisek pozice
		$lbl_note_raw = $this->phrase('lbl_user_note', [], 'Poznámka');      // Surový popisek poznámky
		$lbl_note  = htmlspecialchars($lbl_note_raw);                        // Ošetřený popisek poznámky

		$v_login = htmlspecialchars((string)($datarow['login_name'] ?? ''));        // Hodnota login_name
		$v_tbef  = htmlspecialchars((string)($datarow['user_title_before'] ?? '')); // Hodnota user_title_before
		$v_fname = htmlspecialchars((string)($datarow['first_name'] ?? ''));        // Hodnota first_name
		$v_lname = htmlspecialchars((string)($datarow['last_name'] ?? ''));         // Hodnota last_name
		$v_taft  = htmlspecialchars((string)($datarow['user_title_after'] ?? ''));  // Hodnota user_title_after
		$v_email = htmlspecialchars((string)($datarow['email'] ?? ''));             // Hodnota email
		$v_phone = htmlspecialchars((string)($datarow['phone'] ?? ''));             // Hodnota phone
		$v_mob   = htmlspecialchars((string)($datarow['mobile'] ?? ''));            // Hodnota mobile
		$v_dept  = htmlspecialchars((string)($datarow['department_name'] ?? ''));   // Hodnota department_name
		$v_job   = htmlspecialchars((string)($datarow['job_title'] ?? ''));         // Hodnota job_title
		$raw_note_val = (string)($datarow['note'] ?? '');                           // Surová hodnota poznámky
		$v_note  = htmlspecialchars($raw_note_val);                                 // Ošetřená hodnota note

		// Vykreslení poznámky přes rich_text (Preview + modální editor na popředí)
		if (class_exists('rich_text')) {                                     // Pokud je dostupná třída rich_text
			if ($personal_readonly) {                                        // V uzamčeném režimu před schválením přístupu
				$ro_view = rich_text::render_formatted($raw_note_val, true); // Zformátovaný readonly náhled
				$note_input_html = "<input type=\"hidden\" name=\"note\" value=\"{$v_note}\">"
					. "<div style=\"padding: 8px 10px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; min-height: 36px;\">{$ro_view}</div>"; // Readonly box
			} else {
				$note_input_html = rich_text::render_editor('note', $raw_note_val, ['label' => $lbl_note_raw, 'input_rows' => 4]); // Preview s modálním editorem
			}
		} else {
			$note_input_html = "<textarea name=\"note\" rows=\"3\" {$pers_ro_attr}>{$v_note}</textarea>"; // Fallback textarea
		}

		echo <<<HTML
				<h3 style="margin-top: 20px; color: #004488; font-size: 15px;">{$grp_pers}</h3>
				<table class="md-table" style="margin-bottom: 25px;">
					<tr>
						<td style="width: 35%;"><strong>{$lbl_login}: *</strong></td>
						<td><input type="text" name="login_name" maxlength="100" value="{$v_login}" {$login_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_t_bef}:</strong></td>
						<td><input type="text" name="user_title_before" maxlength="40" value="{$v_tbef}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_fname}:</strong></td>
						<td><input type="text" name="first_name" maxlength="100" value="{$v_fname}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_lname}:</strong></td>
						<td><input type="text" name="last_name" maxlength="100" value="{$v_lname}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_t_aft}:</strong></td>
						<td><input type="text" name="user_title_after" maxlength="40" value="{$v_taft}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_email}:</strong></td>
						<td><input type="text" name="email" maxlength="200" value="{$v_email}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_phone}:</strong></td>
						<td><input type="text" name="phone" maxlength="50" value="{$v_phone}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_mob}:</strong></td>
						<td><input type="text" name="mobile" maxlength="50" value="{$v_mob}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_dept}:</strong></td>
						<td><input type="text" name="department_name" maxlength="150" value="{$v_dept}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_job}:</strong></td>
						<td><input type="text" name="job_title" maxlength="150" value="{$v_job}" {$pers_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_note}:</strong></td>
						<td>{$note_input_html}</td>
					</tr>
				</table>
HTML;

		// =====================================================================
		// SEKCE 3: Globální správa účtu (pouze pro Sysadmin / Developer)
		// =====================================================================
		if ($this->is_sysadmin) {                                            // Zobrazení globální sekce pouze pro S a D
			$grp_glob = htmlspecialchars($this->phrase('grp_global_account_admin', [], '3. Globální správa účtu (pouze Sysadmin / Developer)')); // Nadpis sekce
			$lbl_sys  = htmlspecialchars($this->phrase('lbl_is_system_admin', [], 'Globální Sysadmin (is_system_admin)')); // Popisek Sysadmin
			$lbl_dev  = htmlspecialchars($this->phrase('lbl_is_developer', [], 'Globální Developer (is_developer)')); // Popisek Developer
			$lbl_loc  = htmlspecialchars($this->phrase('lbl_allow_local_login', [], 'Povolit přihlášení lokálním heslem')); // Popisek lokálního hesla
			$lbl_deac = htmlspecialchars($this->phrase('lbl_deactivate_global', [], 'Globálně deaktivovat účet ve všech organizacích')); // Popisek deaktivace

			$chk_sys  = (!empty($datarow['is_system_admin'])) ? 'checked' : '';   // Stav is_system_admin
			$chk_dev  = (!empty($datarow['is_developer'])) ? 'checked' : '';      // Stav is_developer
			$chk_loc  = (!isset($datarow['allow_local_login']) OR !empty($datarow['allow_local_login'])) ? 'checked' : ''; // Stav allow_local_login
			$chk_deac = (!empty($datarow['deactivate_global'])) ? 'checked' : ''; // Stav deactivate_global

			echo "<h3 style=\"margin-top: 20px; color: #004488; font-size: 15px;\">{$grp_glob}</h3>";
			echo "<table class=\"md-table\" style=\"margin-bottom: 25px;\">";
			echo "<tr><td style=\"width: 35%;\"><strong>{$lbl_sys}:</strong></td><td><input type=\"hidden\" name=\"is_system_admin\" value=\"0\"><input type=\"checkbox\" name=\"is_system_admin\" value=\"1\" {$chk_sys} {$dis_me_admin}></td></tr>";
			echo "<tr><td><strong>{$lbl_dev}:</strong></td><td><input type=\"hidden\" name=\"is_developer\" value=\"0\"><input type=\"checkbox\" name=\"is_developer\" value=\"1\" {$chk_dev} {$dis_me_admin}></td></tr>";
			echo "<tr><td><strong>{$lbl_loc}:</strong></td><td><input type=\"hidden\" name=\"allow_local_login\" value=\"0\"><input type=\"checkbox\" name=\"allow_local_login\" value=\"1\" {$chk_loc}></td></tr>";
			if (!$is_me AND !$is_new) {                                      // Globální deaktivace cizího účtu
				echo "<tr style=\"background-color: #ffebee;\"><td style=\"border-left: 4px solid #b71c1c; color: #b71c1c;\"><strong>{$lbl_deac}:</strong></td><td><input type=\"hidden\" name=\"deactivate_global\" value=\"0\"><input type=\"checkbox\" name=\"deactivate_global\" value=\"1\" {$chk_deac}></td></tr>";
			}
			echo "</table>";
		}

		$this->render_audit_trail();                                         // Vykreslení auditní stopy

		echo "</div></form>";
	}
}