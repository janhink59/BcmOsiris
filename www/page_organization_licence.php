<?php
/**
 * =============================================================================
 * Verze: 2026-10-21 15:05
 * Soubor: page_organization_licence.php
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
 * Vazby na okolí:
 * - Dědí z abstract_page_master_detail (využívá $this->phrase(), render_audit_trail()
 *   a centrální JS filtrování levého panelu).
 * - Využívá abstract_button pro vykreslení akčních tlačítek.
 * - Čte data přes sqlarray_simple() a sqlfirstrow() (bez otevřených kurzorů).
 * - Volá proceduru p_process_organization_licence při schválení licence.
 *
 * Změny:
 * 2026-10-21 15:05 - Odstraněny historické helpery pageitem(), td1_label(), td1_input(),
 *                    td1_value() a fetch_datarow() z OsirisLib.php.
 *                  - Všechna čtení převedena na sqlarray_simple() a sqlfirstrow().
 *                  - Důsledná aplikace Anti-LaTeX pravidel (OR/AND místo ||/&&).
 * 2026-10-16 08:35 - Zapojena komponenta abstract_button a lokalizace všech textů.
 * 2026-10-15 22:50 - Přechod na objektovou architekturu (extends abstract_page_master_detail).
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
		$this->page_title = $this->phrase('page_title', [], 'Správa licencí organizací'); // Lokalizovaný titulek stránky

		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		if ($this->access_denied OR !in_array($active_role, ['S', 'D'], true)) { // Kontrola oprávnění S nebo D
			$this->access_denied = true;                                     // Zamezení přístupu pro nižší role
			return;                                                          // Ukončení inicializace při zamítnutí
		}

		$raw_guid = trim((string)getinput('update_guid', 'raw'));            // Načtení identifikátoru záznamu
		$this->update_guid = ($raw_guid !== '') ? $raw_guid : null;          // Uložení vybraného identifikátoru

		$this->states_opt = [                                                // Stavy životního cyklu licence
			'DRAFT'     => $this->phrase('state_draft', [], 'Koncept'),      // Rozpracovaná licence
			'APPROVED'  => $this->phrase('state_approved', [], 'Schváleno (spustí aktivaci)'), // Stav ke zpracování
			'PROCESSED' => $this->phrase('state_processed', [], 'Zpracováno (Aktivní)'), // Zpracovaná aktivní licence
			'REJECTED'  => $this->phrase('state_rejected', [], 'Zamítnuto')  // Zamítnutá žádost o licenci
		];                                                                   // Konec definice stavů licence
		$this->levels_opt = sqlarray("SELECT licence_level, name FROM licence_level ORDER BY licence_level"); // Načtení úrovní licencí
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

		$builtin_code     = charliteral($raw_code, 80);                      // SQL literál kódu licence
		$caption          = charliteral($raw_caption, 200);                  // SQL literál názvu organizace
		$login_domain     = charliteral(trim((string)($_POST['login_domain'] ?? '')), 200);     // SQL literál SSO domény
		$licence_level    = (int)($_POST['licence_level'] ?? 10);            // Číselná úroveň licence
		$raw_state        = trim((string)($_POST['licence_state'] ?? 'DRAFT')); // Surový stav licence
		$licence_state    = charliteral($raw_state, 20);                     // SQL literál stavu licence
		$is_developer     = (!empty($_POST['is_developer'])) ? 1 : 0;        // Příznak vývojářské licence
		$admin_login      = charliteral(trim((string)($_POST['admin_login'] ?? '')), 100);      // SQL literál loginu admina
		$admin_first_name = charliteral(trim((string)($_POST['admin_first_name'] ?? '')), 100); // SQL literál jména admina
		$admin_last_name  = charliteral(trim((string)($_POST['admin_last_name'] ?? '')), 100);  // SQL literál příjmení admina
		$admin_email      = charliteral(trim((string)($_POST['admin_email'] ?? '')), 200);      // SQL literál e-mailu admina

		$safe_access = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00')); // Relace pro auditní stopu

		if ($this->update_guid === 'NEW') {                                  // Založení nové licence
			$sys_owner = guidliteral('0x00');                                // Systémový vlastník záznamu
			$row_orig = sqlfirstrow("SELECT dbo.f_generate_original('organization_licence', {$sys_owner}, {$builtin_code}, NULL) AS orig"); // Výpočet originálu
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
			)";                                                              // Sestavení příkazu INSERT
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
			WHERE original = {$safe_uuid} AND record_type = 'A'";            // Sestavení příkazu UPDATE
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
		$th_admin = htmlspecialchars($this->phrase('th_admin_login', [], 'Admin (Login)'));   // Záhlaví sloupce loginu admina
		$th_email = htmlspecialchars($this->phrase('th_email', [], 'E-mail'));                // Záhlaví sloupce e-mailu
		$th_state = htmlspecialchars($this->phrase('th_licence_state', [], 'Stav licence'));  // Záhlaví sloupce stavu licence

		$btn_new = new abstract_button('btn_new_licence', '+ Nová licence', 'page_organization_licence'); // Tlačítko nové licence
		$btn_new->set_href('index.php?page=page_organization_licence&update_guid=NEW'); // Odkaz pro založení licence
		$btn_new_html = $btn_new->render();                                  // Vykreslení HTML tlačítka

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
						<th>{$th_admin}</th>
						<th>{$th_email}</th>
						<th>{$th_state}</th>
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$rows = sqlarray_simple("
			SELECT original, caption, admin_login, admin_email, licence_state 
			FROM organization_licence 
			WHERE record_type = 'A' AND removed = 0 
			ORDER BY date_created DESC
		");                                                                  // Načtení seznamu licencí do pole v paměti
		
		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as $row) {                                        // Průchod načtenými licencemi
				$uuid = (string)$row['original'];                            // Originální UUID licence
				$is_active = ($this->update_guid !== null AND strcasecmp($uuid, $this->update_guid) === 0); // Aktivní záznam
				$row_class = $is_active ? 'md-row-active' : '';              // CSS třída aktivního řádku
				$id_attr = $is_active ? 'id="active-row"' : '';              // HTML id aktivního řádku
				$row_url = htmlspecialchars("index.php?page=page_organization_licence&update_guid=" . urlencode($uuid)); // URL řádku
				$safe_cap = htmlspecialchars((string)$row['caption']);       // Ošetřený název organizace
				$safe_login = htmlspecialchars((string)$row['admin_login']); // Ošetřený login admina
				$safe_email = htmlspecialchars((string)$row['admin_email']); // Ošetřený e-mail admina
				$state_code = (string)$row['licence_state'];                 // Kód stavu licence
				$state_label = htmlspecialchars($this->states_opt[$state_code] ?? $state_code); // Přeložený stav licence

				echo "<tr class=\"{$row_class}\" {$id_attr} style=\"cursor: pointer;\" onclick=\"document.location='{$row_url}'\">";
				echo "<td><strong>{$safe_cap}</strong></td>";
				echo "<td>{$safe_login}</td>";
				echo "<td>{$safe_email}</td>";
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
		if ($this->update_guid === 'NEW') {                                  // Inicializace pro novou licenci
			$datarow = [                                                     // Výchozí hodnoty pro novou licenci
				'builtin_code'      => '',                                   // Prázdný kód licence
				'caption'           => '',                                   // Prázdný název organizace
				'login_domain'      => '',                                   // Prázdná SSO doména
				'licence_level'     => 10,                                   // Výchozí úroveň licence Standard (10)
				'licence_state'     => 'DRAFT',                              // Výchozí stav Koncept
				'is_developer'      => 0,                                    // Výchozí stav bez vývojářské licence
				'admin_login'       => '',                                   // Prázdný login administrátora
				'admin_first_name'  => '',                                   // Prázdné jméno administrátora
				'admin_last_name'   => '',                                   // Prázdné příjmení administrátora
				'admin_email'       => '',                                   // Prázdný e-mail administrátora
				'date_created'      => null,                                 // Datum vytvoření zatím neexistuje
				'who_created_info'  => null,                                 // Autor vytvoření zatím neexistuje
				'date_modified'     => null,                                 // Datum úpravy zatím neexistuje
				'who_modified_info' => null                                  // Autor úpravy zatím neexistuje
			];                                                               // Konec inicializace nové licence
		} else {
			$safe_uuid = guidliteral($this->update_guid);                    // SQL literál vybrané licence
			$datarow = sqlfirstrow("
				SELECT l.*,
				       dbo.f_get_user_info(l.who_created) AS who_created_info,
				       dbo.f_get_user_info(l.who_modified) AS who_modified_info
				FROM organization_licence l
				WHERE l.original = {$safe_uuid} AND l.record_type = 'A' AND l.removed = 0
			");                                                              // Načtení detailu licence přes sqlfirstrow()

			if (empty($datarow)) {                                           // Pokud záznam nebyl nalezen
				$msg_nf = htmlspecialchars($this->phrase('msg_licence_not_found', [], 'Licence nebyla nalezena.')); // Chybová hláška
				echo "<div class='msg-err'>{$msg_nf}</div>";
				return;                                                      // Ukončení při nenalezeném záznamu
			}
		}

		$safe_update_guid = htmlspecialchars($this->update_guid);            // Ošetřené ID záznamu pro skryté pole
		$detail_heading = htmlspecialchars($this->phrase('detail_heading', [], 'Detail organizace a licencování')); // Nadpis detailu

		$btn_discard = new abstract_button('btn_discard', 'Zahodit změny', 'abstract_button', '', 'btn-danger'); // Tlačítko zahození změn
		$btn_discard->set_href('index.php?page=page_organization_licence')->set_onclick('isFormDirty = false;'); // Odkaz bez varování dirty

		$btn_save = new abstract_button('btn_save', 'Uložit změny', 'abstract_button', '', 'btn-success'); // Tlačítko uložení
		$btn_save->set_type('submit')->set_name_value('btn_save', '1');      // Nastavení submit atributů

		$discard_html = $btn_discard->render();                              // Vykreslení tlačítka Zahodit
		$save_html = $btn_save->render();                                    // Vykreslení tlačítka Uložit

		// Lokalizované popisky a nápovědy polí
		$lbl_code   = htmlspecialchars($this->phrase('lbl_builtin_code', [], 'Kód licence (zkratka)'));       // Popisek kódu
		$lbl_cap    = htmlspecialchars($this->phrase('lbl_caption', [], 'Název organizace'));                 // Popisek názvu
		$lbl_dom    = htmlspecialchars($this->phrase('lbl_login_domain', [], 'Login doména'));                // Popisek domény
		$lbl_lvl    = htmlspecialchars($this->phrase('lbl_licence_level', [], 'Úroveň licence'));             // Popisek úrovně
		$lbl_state  = htmlspecialchars($this->phrase('lbl_licence_state', [], 'Stav licence'));               // Popisek stavu
		$lbl_dev    = htmlspecialchars($this->phrase('lbl_is_developer', [], 'Vývojářská licence'));          // Popisek developer
		$lbl_alogin = htmlspecialchars($this->phrase('lbl_admin_login', [], 'Login admina'));                 // Popisek loginu admina
		$lbl_afname = htmlspecialchars($this->phrase('lbl_admin_first_name', [], 'Jméno admina'));            // Popisek jména admina
		$lbl_alname = htmlspecialchars($this->phrase('lbl_admin_last_name', [], 'Příjmení admina'));          // Popisek příjmení admina
		$lbl_aemail = htmlspecialchars($this->phrase('lbl_admin_email', [], 'E-mail admina'));                // Popisek e-mailu admina

		// Hodnoty pro formulářová pole
		$v_code   = htmlspecialchars((string)($datarow['builtin_code'] ?? ''));     // Hodnota builtin_code
		$v_cap    = htmlspecialchars((string)($datarow['caption'] ?? ''));          // Hodnota caption
		$v_dom    = htmlspecialchars((string)($datarow['login_domain'] ?? ''));     // Hodnota login_domain
		$v_lvl    = (string)($datarow['licence_level'] ?? '10');                    // Hodnota licence_level
		$v_state  = (string)($datarow['licence_state'] ?? 'DRAFT');                 // Hodnota licence_state
		$chk_dev  = (!empty($datarow['is_developer'])) ? 'checked' : '';            // Stav zaškrtnutí is_developer
		$v_alogin = htmlspecialchars((string)($datarow['admin_login'] ?? ''));      // Hodnota admin_login
		$v_afname = htmlspecialchars((string)($datarow['admin_first_name'] ?? '')); // Hodnota admin_first_name
		$v_alname = htmlspecialchars((string)($datarow['admin_last_name'] ?? ''));  // Hodnota admin_last_name
		$v_aemail = htmlspecialchars((string)($datarow['admin_email'] ?? ''));      // Hodnota admin_email

		$lvl_opts = '';                                                      // HTML volby pro úroveň licence
		foreach ($this->levels_opt as $lvl_key => $lvl_name) {               // Sestavení roletky úrovní licence
			$sel = ((string)$lvl_key === $v_lvl) ? 'selected' : '';          // Označení vybrané úrovně
			$lvl_opts .= "<option value=\"" . htmlspecialchars((string)$lvl_key) . "\" {$sel}>" . htmlspecialchars((string)$lvl_name) . "</option>"; // Volba úrovně
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
						<td><input type="text" name="builtin_code" maxlength="80" value="{$v_code}" style="width: 220px; padding: 6px; box-sizing: border-box;"></td>
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
						<td><strong>{$lbl_lvl}:</strong></td>
						<td><select name="licence_level" style="width: 220px; padding: 6px;">{$lvl_opts}</select></td>
					</tr>
					<tr>
						<td><strong>{$lbl_state}:</strong></td>
						<td><select name="licence_state" style="width: 240px; padding: 6px;">{$state_opts}</select></td>
					</tr>
					<tr>
						<td><strong>{$lbl_dev}:</strong></td>
						<td><input type="hidden" name="is_developer" value="0"><input type="checkbox" name="is_developer" value="1" {$chk_dev}></td>
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