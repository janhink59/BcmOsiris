<?php
/**
 * =============================================================================
 * Verze: 2026-10-29 16:40
 * Soubor: page_organization_licence.php
 * Stránka: page_organization_licence.php
 * Účel: Master-Detail rozhraní pro evidenci žádostí a licencí organizací.
 * 
 * Logika a byznys procesy:
 * - Modul je dostupný pro Sysadminy ('S'), Developery ('D') a pro administrátory
 *   organizací ('A') se zvláštní licenční úrovní Enterprise (40) nebo Developer (255).
 * - Výhradně zde se nastavuje sloupec licence_level (0=Demo, 10=Standard,
 *   20=Expert, 30=Custom, 40=Enterprise, 255=Developer) a příznak login_disabled.
 * - Organizace s úrovní Enterprise (40) smí vytvářet licence dalším organizacím
 *   nejvýše do úrovně 40; úroveň 255 (Developer) smí přidělit pouze globální
 *   Sysadmin/Developer nebo organizace s úrovní 255.
 * - Jakmile je žádosti nastaven stav 'APPROVED', při uložení se automaticky
 *   spustí procedura p_process_organization_licence a přepne stav na 'PROCESSED'.
 *
 * Vazby na okolí:
 * - Dědí z abstract_page_master_detail (využívá $this->phrase(), render_audit_trail(),
 *   asynchronní načítání detailu loadDetailPanel() a centrální JS filtrování levého panelu).
 * - Využívá abstract_button pro vykreslení akčních tlačítek.
 * - Čte data přes sqlarray_simple() a sqlfirstrow() (bez otevřených kurzorů).
 * - Volá proceduru p_process_organization_licence při schválení licence.
 *
 * Změny:
 * 2026-10-29 16:40 - Doplněna podpora pro organizace s licencí Enterprise (40)
 *                    a Developer (255), roletka pro preferred_language, příznak
 *                    login_disabled a uzamčení klíčového sloupce builtin_code
 *                    (readonly) u již existujících záznamů.
 * 2026-10-27 19:55 - Napojení řádků a tlačítek na asynchronní loadDetailPanel().
 * =============================================================================
 */

declare(strict_types=1);

class page_organization_licence extends abstract_page_master_detail {

	private ?string $update_guid = null;                                     // Aktuálně vybraná licence nebo 'NEW'
	private bool $is_sys_user = false;                                       // Zda má uživatel globální roli S nebo D
	private int $session_licence_level = 0;                                  // Úroveň licence aktivní organizace v relaci
	private string $current_org_sql = '0x00';                                // SQL literál aktivní organizace
	private array $states_opt = [];                                          // Číselník stavů licence
	private array $levels_opt = [];                                          // Číselník povolených úrovní licence z DB
	private array $langs_opt = [];                                           // Číselník podporovaných jazyků z DB

	public function __construct() {
		parent::__construct();                                               // Inicializace frází a kontroly role v předkovi

		global $dbsession;                                                   // Globální kontext relace
		$this->page_title =$this->phrase('page_title', [], 'Správa licencí organizací'); // Lokalizovaný titulek stránky

		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		$this->session_licence_level = intval($dbsession['licence_level'] ?? 0); // Úroveň licence organizace v relaci
		$this->is_sys_user = in_array($active_role, ['S', 'D'], true);       // Globální správce nebo vývojář
		$can_enterprise = ($active_role === 'A' AND in_array($this->session_licence_level, [40, 255], true)); // Enterprise/Developer tenant

		if ($this->access_denied OR (!$this->is_sys_user AND !$can_enterprise)) { // Kontrola oprávnění ke správě licencí
			$this->access_denied = true;                                     // Zamezení přístupu pro nižší role a licence
			return;                                                          // Ukončení inicializace při zamítnutí
		}

		$org_raw = (string)($dbsession['organization'] ?? '0x00');           // Surové UUID aktivní organizace
		$this->current_org_sql = guidliteral($org_raw);                      // SQL literál aktivní organizace

		$raw_guid = trim((string)getinput('update_guid', 'raw'));            // Načtení identifikátoru záznamu
		$this->update_guid = ($raw_guid !== '') ?$raw_guid : null;          // Uložení vybraného identifikátoru

		$this->states_opt = [                                                // Stavy životního cyklu licence
			'DRAFT'     => $this->phrase('state_draft', [], 'Koncept'),      // Rozpracovaná licence
			'APPROVED'  => $this->phrase('state_approved', [], 'Schváleno (spustí aktivaci)'), // Stav ke zpracování
			'PROCESSED' => $this->phrase('state_processed', [], 'Zpracováno (Aktivní)'), // Zpracovaná aktivní licence
			'REJECTED'  => $this->phrase('state_rejected', [], 'Zamítnuto')  // Zamítnutá žádost o licenci
		];                                                                   // Konec definice stavů licence

		$max_allowed_lvl = ($this->is_sys_user OR$this->session_licence_level === 255) ? 255 : 40; // Maximální povolená úroveň
		$this->levels_opt = sqlarray("SELECT licence_level, name FROM licence_level WHERE licence_level <= {$max_allowed_lvl} ORDER BY licence_level"); // Načtení úrovní
		$this->langs_opt = sqlarray("SELECT [language], caption FROM [language] ORDER BY sort_code"); // Načtení jazyků
	}

	/**
	 * Sestaví SQL podmínku viditelnosti licencí (Sysadmin vidí vše, Enterprise organizace vidí jí vystavené licence).
	 */
	private function get_owner_where_sql(): string {
		if ($this->is_sys_user) {                                            // Globální Sysadmin/Developer vidí všechny licence
			return "1 = 1";                                                  // Bez omezení vlastníka
		}
		return "object_owner = {$this->current_org_sql}";                    // Enterprise tenant vidí pouze jím vystavené licence
	}

	/**
	 * Zpracování uložení formuláře (PRG vzor volaný z abstract_page::render při POST).
	 */
	protected function process_save(): void {
		if (!isset($_POST['button_save']) AND !isset($_POST['btn_save'])) {  // Kontrola odeslání formuláře
			return;                                                          // Bez odeslání formuláře neukládáme
		}

		global $dbsession;                                                   // Globální kontext relace

		$raw_caption = trim((string)($_POST['caption'] ?? ''));              // Surový název organizace
		$raw_code = trim((string)($_POST['builtin_code'] ?? ''));            // Surový kód licence
		if ($raw_code === '') {                                              // Pokud nebyl zadán builtin_code
			$raw_code = substr($raw_caption, 0, 80);                         // Odvození kódu z názvu organizace
		}

		$max_allowed_lvl = ($this->is_sys_user OR$this->session_licence_level === 255) ? 255 : 40; // Limit úrovně licence
		$req_level = intval($_POST['licence_level'] ?? 10);                  // Požadovaná číselná úroveň licence
		if ($req_level >$max_allowed_lvl) {                                 // Ochrana proti eskalaci úrovně licence v POSTu
			$req_level =$max_allowed_lvl;                                   // Omezení na nejvyšší povolenou úroveň
		}

		$raw_pref_lang = trim((string)($_POST['preferred_language'] ?? 'cs')); // Zvolený preferovaný jazyk organizace
		if (!isset($this->langs_opt[$raw_pref_lang])) {                      // Validace kódu jazyka proti číselníku
			$raw_pref_lang = 'cs';                                           // Výchozí jazyk čeština
		}

		$builtin_code       = charliteral($raw_code, 80);                    // SQL literál kódu licence
		$caption            = charliteral($raw_caption, 200);                // SQL literál názvu organizace
		$login_domain       = charliteral(trim((string)($_POST['login_domain'] ?? '')), 200);   // SQL literál SSO domény
		$preferred_language = charliteral($raw_pref_lang, 2);                // SQL literál preferovaného jazyka
		$licence_level      =$req_level;                                    // Číselná úroveň licence
		$login_disabled     = (!empty($_POST['login_disabled'])) ? 1 : 0;    // Příznak zablokování přihlašování organizace
		$raw_state          = trim((string)($_POST['licence_state'] ?? 'DRAFT')); // Surový stav licence
		$licence_state      = charliteral($raw_state, 20);                   // SQL literál stavu licence
		$admin_login        = charliteral(trim((string)($_POST['admin_login'] ?? '')), 100);    // SQL literál loginu admina
		$admin_first_name   = charliteral(trim((string)($_POST['admin_first_name'] ?? '')), 100); // SQL literál jména admina
		$admin_last_name    = charliteral(trim((string)($_POST['admin_last_name'] ?? '')), 100);  // SQL literál příjmení admina
		$admin_email        = charliteral(trim((string)($_POST['admin_email'] ?? '')), 200);    // SQL literál e-mailu admina

		$safe_access = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00')); // Relace pro auditní stopu
		$owner_sql = $this->is_sys_user ? '0x00' : $this->current_org_sql;   // Vlastník zakládané licence

		if ($this->update_guid === 'NEW') {                                  // Založení nové licence
			$row_orig = sqlfirstrow("SELECT dbo.f_generate_original('organization_licence', {$owner_sql}, {$builtin_code}, NULL) AS orig"); // Výpočet originálu
			$new_uuid = (string)($row_orig['orig'] ?? generateUUID());       // Deterministické UUID nové licence
			$safe_new_uuid = guidliteral($new_uuid);                         // Bezpečný SQL literál UUID
			
			$sql = "INSERT INTO organization_licence (
				uuid, object_owner, original, record_type, approval_status, 
				builtin_code, caption, login_domain, preferred_language, licence_level, login_disabled, licence_state,
				admin_login, admin_first_name, admin_last_name, admin_email,
				who_created, who_modified
			) VALUES (
				{$safe_new_uuid}, {$owner_sql}, {$safe_new_uuid}, 'A', 'A',
				{$builtin_code}, {$caption}, {$login_domain}, {$preferred_language}, {$licence_level}, {$login_disabled}, {$licence_state},
				{$admin_login}, {$admin_first_name}, {$admin_last_name}, {$admin_email},
				{$safe_access}, {$safe_access}
			)";                                                              // Sestavení příkazu INSERT
			sqlrun($sql);                                                    // Vložení nové licence do DB
			$safe_uuid =$safe_new_uuid;                                     // Nastavení UUID pro případnou aktivaci
			$redirect_guid =$new_uuid;                                      // Cílové UUID pro přesměrování
		} else {
			$safe_uuid = guidliteral((string)$this->update_guid);            // SQL literál upravované licence
			$redirect_guid = (string)$this->update_guid;                     // Cílové UUID pro přesměrování
			$owner_cond =$this->get_owner_where_sql();                      // Ochrana vlastnictví při UPDATE

			// Klíčový sloupec builtin_code se u existujícího záznamu NEMĚNÍ (ochrana deterministického originálu)
			$sql = "UPDATE organization_licence SET 
				caption = {$caption},
				login_domain = {$login_domain},
				preferred_language = {$preferred_language},
				licence_level = {$licence_level},
				login_disabled = {$login_disabled},
				licence_state = {$licence_state},
				admin_login = {$admin_login},
				admin_first_name = {$admin_first_name},
				admin_last_name = {$admin_last_name},
				admin_email = {$admin_email},
				date_modified = GETDATE(),
				who_modified = {$safe_access}
			WHERE original = {$safe_uuid} AND record_type = 'A' AND {$owner_cond}"; // Sestavení příkazu UPDATE
			sqlrun($sql);                                                    // Aktualizace licence v DB
		}

		if ($raw_state === 'APPROVED') {                                     // Detekce stavu pro aktivaci nového tenanta
			sqlrun("EXEC p_process_organization_licence @licence_original = {$safe_uuid}"); // Spuštění aktivace organizace
		}

		autoredirect("index.php?page=page_organization_licence&update_guid=" . urlencode($redirect_guid)); // PRG přesměrování
	}

	/**
	 * Vykreslení levého panelu (Master) se seznamem licencí.
	 */
	protected function render_master(): void {
		$master_heading = htmlspecialchars($this->phrase('master_heading', [], 'Evidence organizací a licencí')); // Nadpis seznamu
		$search_placeholder = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat...')); // Placeholder vyhledávání
		$th_org   = htmlspecialchars($this->phrase('th_organization', [], 'Organizace'));     // Záhlaví sloupce organizace
		$th_lvl   = htmlspecialchars($this->phrase('th_licence_level', [], 'Úroveň'));        // Záhlaví sloupce úrovně licence
		$th_admin = htmlspecialchars($this->phrase('th_admin_login', [], 'Admin (Login)'));   // Záhlaví sloupce loginu admina
		$th_state = htmlspecialchars($this->phrase('th_licence_state', [], 'Stav licence'));  // Záhlaví sloupce stavu licence

		$new_url = 'index.php?page=page_organization_licence&update_guid=NEW'; // Odkaz pro založení licence
		$btn_new = new abstract_button('btn_new_licence', '+ Nová licence', 'page_organization_licence'); // Tlačítko nové licence
		$btn_new->set_href($new_url)                                         // Nastavení cílové URL
			->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}"); // Asynchronní otevření bez refreshe levého panelu
		$btn_new_html =$btn_new->render();                                  // Vykreslení HTML tlačítka

		echo <<<HTML
		<div class="md-master-header">
			<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
				<h2 style="font-size: 16px; margin: 0; border: none; padding: 0;">{$master_heading}</h2>
				{$btn_new_html}
			</div>
			<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>

		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
						<th>{$th_org}</th>
						<th>{$th_lvl}</th>
						<th>{$th_admin}</th>
						<th>{$th_state}</th>
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$owner_cond =$this->get_owner_where_sql();                          // Podmínka viditelnosti licencí
		$rows = sqlarray_simple("
			SELECT original, caption, licence_level, login_disabled, admin_login, licence_state 
			FROM organization_licence 
			WHERE record_type = 'A' AND removed = 0 AND {$owner_cond}
			ORDER BY date_created DESC
		");                                                                  // Načtení seznamu licencí do pole v paměti
		
		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as$row) {                                        // Průchod načtenými licencemi
				$uuid = (string)$row['original'];                            // Originální UUID licence
				$safe_uuid = htmlspecialchars($uuid);                        // Ošetřené UUID pro atribut data-uuid
				$is_active = ($this->update_guid !== null AND strcasecmp($uuid,$this->update_guid) === 0); // Aktivní záznam
				$is_dis = !empty($row['login_disabled']);                    // Zda je přihlašování zablokováno
				$row_class = $is_active ? 'md-row-active' : ($is_dis ? 'md-row-inactive' : ''); // CSS třída řádku
				$id_attr =$is_active ? 'id="active-row"' : '';              // HTML id aktivního řádku
				$row_url = htmlspecialchars("index.php?page=page_organization_licence&update_guid=" . urlencode($uuid)); // URL řádku
				$safe_cap = htmlspecialchars((string)$row['caption']);       // Ošetřený název organizace
				$lvl_key = (int)$row['licence_level'];                       // Číselný kód úrovně licence
				$lvl_label = htmlspecialchars((string)($this->levels_opt[$lvl_key] ?? $lvl_key)); // Název úrovně licence
				$safe_login = htmlspecialchars((string)$row['admin_login']); // Ošetřený login admina
				$state_code = (string)$row['licence_state'];                 // Kód stavu licence
				$state_label = htmlspecialchars($this->states_opt[$state_code] ?? $state_code); // Přeložený stav licence

				echo "<tr class=\"{$row_class}\" {$id_attr} data-uuid=\"{$safe_uuid}\" style=\"cursor: pointer;\" onclick=\"if(window.loadDetailPanel){loadDetailPanel('{$row_url}', this);}else{document.location='{$row_url}';}\">";
				echo "<td><strong>{$safe_cap}</strong></td>";
				echo "<td>{$lvl_label}</td>";
				echo "<td>{$safe_login}</td>";
				echo "<td>{$state_label}</td>";
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
	 * Vykreslení pravého panelu (Detail) s formulářem licence.
	 */
	protected function render_detail(): void {
		if ($this->update_guid === null) {                                   // Pokud není vybrána žádná licence
			$msg_sel = htmlspecialchars($this->phrase('msg_select_or_create_licence', [], 'Vyberte licenci ze seznamu vlevo nebo vytvořte novou.')); // Výzva
			echo "<div class='msg-info'>{$msg_sel}</div>";
			return;                                                          // Ukončení při nevybrané licenci
		}

		global $datarow;                                                     // Globální pole pro aktuální záznam (pro render_audit_trail)
		$is_new = ($this->update_guid === 'NEW');                            // Příznak zakládání nové licence

		if ($is_new) {                                                       // Inicializace pro novou licenci
			$datarow = [                                                     // Výchozí hodnoty pro novou licenci
				'builtin_code'       => '',                                  // Prázdný kód licence
				'caption'            => '',                                  // Prázdný název organizace
				'login_domain'       => '',                                  // Prázdná SSO doména
				'preferred_language' => 'cs',                                // Výchozí jazyk organizace
				'licence_level'      => 10,                                  // Výchozí úroveň licence Standard (10)
				'login_disabled'     => 0,                                   // Přihlášení povoleno
				'licence_state'      => 'DRAFT',                             // Výchozí stav Koncept
				'admin_login'        => '',                                  // Prázdný login administrátora
				'admin_first_name'   => '',                                  // Prázdné jméno administrátora
				'admin_last_name'    => '',                                  // Prázdné příjmení administrátora
				'admin_email'        => '',                                  // Prázdný e-mail administrátora
				'date_created'       => null,                                // Datum vytvoření zatím neexistuje
				'who_created_info'   => null,                                // Autor vytvoření zatím neexistuje
				'date_modified'      => null,                                // Datum úpravy zatím neexistuje
				'who_modified_info'  => null                                 // Autor úpravy zatím neexistuje
			];                                                               // Konec inicializace nové licence
		} else {
			$safe_uuid = guidliteral($this->update_guid);                    // SQL literál vybrané licence
			$owner_cond = $this->get_owner_where_sql();                      // Podmínka vlastnictví licence
			$datarow = sqlfirstrow("
				SELECT l.*,
				       dbo.f_get_user_info(l.who_created) AS who_created_info,
				       dbo.f_get_user_info(l.who_modified) AS who_modified_info
				FROM organization_licence l
				WHERE l.original = {$safe_uuid} AND l.record_type = 'A' AND l.removed = 0 AND {$owner_cond}
			");                                                              // Načtení detailu licence přes sqlfirstrow()

			if (empty($datarow)) {                                           // Pokud záznam nebyl nalezen
				$msg_nf = htmlspecialchars($this->phrase('msg_licence_not_found', [], 'Licence nebyla nalezena.')); // Chybová hláška
				echo "<div class='msg-err'>{$msg_nf}</div>";
				return;                                                      // Ukončení při nenalezeném záznamu
			}
		}

		$safe_update_guid = htmlspecialchars($this->update_guid);            // Ošetřené ID záznamu pro skryté pole
		$detail_heading = htmlspecialchars($this->phrase('detail_heading', [], 'Detail organizace a licencování')); // Nadpis detailu
		$discard_url = 'index.php?page=page_organization_licence';           // Cílová URL při zahození změn

		$btn_discard = new abstract_button('btn_discard', 'Zahodit změny', 'abstract_button', '', 'btn-danger'); // Tlačítko zahození změn
		$btn_discard->set_href($discard_url)                                 // Nastavení odkazu
			->set_onclick("isFormDirty = false; if(window.loadDetailPanel){loadDetailPanel('{$discard_url}');return false;}"); // Asynchronní zavření detailu

		$btn_save = new abstract_button('btn_save', 'Uložit změny', 'abstract_button', '', 'btn-success'); // Tlačítko uložení
		$btn_save->set_type('submit')->set_name_value('btn_save', '1');      // Nastavení submit atributů

		$discard_html = $btn_discard->render();                              // Vykreslení tlačítka Zahodit
		$save_html = $btn_save->render();                                    // Vykreslení tlačítka Uložit

		// Lokalizované popisky polí
		$lbl_code   = htmlspecialchars($this->phrase('lbl_builtin_code', [], 'Kód licence (zkratka)'));       // Popisek kódu
		$lbl_cap    = htmlspecialchars($this->phrase('lbl_caption', [], 'Název organizace'));                 // Popisek názvu
		$lbl_dom    = htmlspecialchars($this->phrase('lbl_login_domain', [], 'Login doména'));                // Popisek domény
		$lbl_plang  = htmlspecialchars($this->phrase('lbl_preferred_language', [], 'Výchozí jazyk organizace')); // Popisek jazyka
		$lbl_lvl    = htmlspecialchars($this->phrase('lbl_licence_level', [], 'Úroveň licence'));             // Popisek úrovně
		$lbl_state  = htmlspecialchars($this->phrase('lbl_licence_state', [], 'Stav licence'));               // Popisek stavu
		$lbl_dis    = htmlspecialchars($this->phrase('lbl_login_disabled', [], 'Zablokovat přihlašování organizaci (login_disabled)')); // Popisek blokace
		$lbl_alogin = htmlspecialchars($this->phrase('lbl_admin_login', [], 'Login admina'));                 // Popisek loginu admina
		$lbl_afname = htmlspecialchars($this->phrase('lbl_admin_first_name', [], 'Jméno admina'));            // Popisek jména admina
		$lbl_alname = htmlspecialchars($this->phrase('lbl_admin_last_name', [], 'Příjmení admina'));          // Popisek příjmení admina
		$lbl_aemail = htmlspecialchars($this->phrase('lbl_admin_email', [], 'E-mail admina'));                // Popisek e-mailu admina

		// Hodnoty pro formulářová pole
		$v_code   = htmlspecialchars((string)($datarow['builtin_code'] ?? ''));        // Hodnota builtin_code
		$v_cap    = htmlspecialchars((string)($datarow['caption'] ?? ''));             // Hodnota caption
		$v_dom    = htmlspecialchars((string)($datarow['login_domain'] ?? ''));        // Hodnota login_domain
		$v_plang  = (string)($datarow['preferred_language'] ?? 'cs');                  // Hodnota preferred_language
		$v_lvl    = (string)($datarow['licence_level'] ?? '10');                       // Hodnota licence_level
		$v_state  = (string)($datarow['licence_state'] ?? 'DRAFT');                    // Hodnota licence_state
		$chk_dis  = (!empty($datarow['login_disabled'])) ? 'checked' : '';             // Stav zaškrtnutí login_disabled
		$v_alogin = htmlspecialchars((string)($datarow['admin_login'] ?? ''));         // Hodnota admin_login
		$v_afname = htmlspecialchars((string)($datarow['admin_first_name'] ?? ''));    // Hodnota admin_first_name
		$v_alname = htmlspecialchars((string)($datarow['admin_last_name'] ?? ''));     // Hodnota admin_last_name
		$v_aemail = htmlspecialchars((string)($datarow['admin_email'] ?? ''));         // Hodnota admin_email

		$code_ro_attr = (!$is_new)
			? 'readonly style="width: 220px; padding: 6px; box-sizing: border-box; background-color: #f4f4f4;"'
			: 'style="width: 220px; padding: 6px; box-sizing: border-box;"'; // Uzamčení builtin_code u existující licence

		$lang_opts = '';                                                     // HTML volby pro výchozí jazyk organizace
		foreach ($this->langs_opt as $l_code => $l_cap) {                    // Sestavení roletky jazyků
			$sel = ((string)$l_code === $v_plang) ? 'selected' : '';         // Označení vybraného jazyka
			$lang_opts .= "<option value=\"" . htmlspecialchars((string)$l_code) . "\" {$sel}>" . htmlspecialchars((string)$l_cap . " ({$l_code})") . "</option>"; // Volba jazyka
		}

		$lvl_opts = '';                                                      // HTML volby pro úroveň licence
		foreach ($this->levels_opt as $lvl_key => $lvl_name) {               // Sestavení roletky úrovní licence
			$sel = ((string)$lvl_key === $v_lvl) ? 'selected' : '';          // Označení vybrané úrovně
			$lvl_opts .= "<option value=\"" . htmlspecialchars((string)$lvl_key) . "\" {$sel}>" . htmlspecialchars((string)$lvl_name . " ({$lvl_key})") . "</option>"; // Volba úrovně
		}

		$state_opts = '';                                                    // HTML volby pro stav licence
		foreach ($this->states_opt as $st_key => $st_name) {                 // Sestavení roletky stavů licence
			$sel = ((string)$st_key === $v_state) ? 'selected' : '';         // Označení vybraného stavu
			$state_opts .= "<option value=\"" . htmlspecialchars((string)$st_key) . "\" {$sel}>" . htmlspecialchars((string)$st_name) . "</option>"; // Volba stavu
		}

		$inp_style = 'style="width: 100%; padding: 6px; box-sizing: border-box;"'; // Sdílený styl textových polí

		echo <<<HTML
		<form method="POST" action="index.php?page=page_organization_licence" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="update_guid" value="{$safe_update_guid}">
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$detail_heading}</h2>
				<div style="display: flex; gap: 10px;">
					{$discard_html}
					{$save_html}
				</div>
			</div>

			<div class="md-detail-content">
				<table class="md-table" style="margin-bottom: 20px;">
					<tr>
						<td style="width: 30%;"><strong>{$lbl_code}:</strong></td>
						<td><input type="text" name="builtin_code" maxlength="80" value="{$v_code}" {$code_ro_attr}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_cap}: *</strong></td>
						<td><input type="text" name="caption" maxlength="200" value="{$v_cap}" required {$inp_style}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_dom}:</strong></td>
						<td><input type="text" name="login_domain" maxlength="200" value="{$v_dom}" {$inp_style}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_plang}:</strong></td>
						<td><select name="preferred_language" style="width: 240px; padding: 6px;">{$lang_opts}</select></td>
					</tr>
					<tr>
						<td><strong>{$lbl_lvl}:</strong></td>
						<td><select name="licence_level" style="width: 240px; padding: 6px;">{$lvl_opts}</select></td>
					</tr>
					<tr>
						<td><strong>{$lbl_state}:</strong></td>
						<td><select name="licence_state" style="width: 240px; padding: 6px;">{$state_opts}</select></td>
					</tr>
					<tr>
						<td><strong>{$lbl_dis}:</strong></td>
						<td><input type="hidden" name="login_disabled" value="0"><input type="checkbox" name="login_disabled" value="1" {$chk_dis}></td>
					</tr>
					<tr><td colspan="2"><hr style="border:0; border-top:1px dashed #ccc; margin:10px 0;"></td></tr>
					<tr>
						<td><strong>{$lbl_alogin}: *</strong></td>
						<td><input type="text" name="admin_login" maxlength="100" value="{$v_alogin}" required {$inp_style}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_afname}:</strong></td>
						<td><input type="text" name="admin_first_name" maxlength="100" value="{$v_afname}" {$inp_style}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_alname}:</strong></td>
						<td><input type="text" name="admin_last_name" maxlength="100" value="{$v_alname}" {$inp_style}></td>
					</tr>
					<tr>
						<td><strong>{$lbl_aemail}:</strong></td>
						<td><input type="text" name="admin_email" maxlength="200" value="{$v_aemail}" {$inp_style}></td>
					</tr>
				</table>
HTML;

		$this->render_audit_trail();                                         // Vykreslení auditní stopy

		echo "\t\t\t</div>\n\t\t</form>\n";
	}
}