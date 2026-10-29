<?php
/**
 * =============================================================================
 * Verze: 2026-10-29 16:00
 * Soubor: page_audit_login_session.php
 * Třída: page_audit_login_session
 * Účel: Přehledová stránka pro zobrazení aktivity uživatelů z forenzní tabulky
 *       audit_login_session a navazujících informací účtu (user_account)
 *       a organizace (user_organization_access / organization).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z centrálního routeru index.php při ?page=page_audit_login_session.
 * - Dědí z třídy abstract_page (abstract_page.php), využívá vlastnosti page_title,
 *   access_denied, full_width a lokalizaci přes metodu phrase().
 * - Dostupná pro administrátory (active_role IN ('A', 'S', 'D')), v meta_object
 *   a meta_menu je registrována pod system_role = 'A'.
 * - Využívá komponentu abstract_button (abstract_button.php) pro vykreslení tlačítek
 *   filtrace a obnovy výchozího stavu.
 * - V systémové organizaci (0x00) zobrazuje navíc sloupec s názvem cílové organizace,
 *   do které se uživatel v dané relaci přihlásil. Podporuje rovněž filtrování pouze
 *   právě aktivních (neukončených) relací.
 *
 * Změny:
 * 2026-10-29 16:00 - Doplněn sloupec s názvem cílové organizace při přihlášení
 *                    v systémové organizaci (0x00) a přepínač pro zobrazení pouze
 *                    právě aktivních (neukončených) relací.
 *                  - Čtení department_name a job_title napojeno na user_organization_access.
 * 2026-10-26 10:45 - Vytvoření první verze stránky pro prohlížení aktivity uživatelů.
 * =============================================================================
 */

declare(strict_types=1);

class page_audit_login_session extends abstract_page {

	private int $limit = 100;                                                // Maximální počet zobrazovaných řádků (výchozí 100)
	private string $user_filter = '';                                        // Textový filtr pro jméno nebo login uživatele
	private bool $only_open = false;                                         // Filtr pouze právě aktivních (neukončených) relací
	private bool $is_sys_org = false;                                        // Příznak přihlášení v systémové organizaci (0x00)
	private string $current_org_sql = '0x00';                                // SQL literál aktuální organizace v relaci

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu v předkovi

		global $dbsession;                                                   // Globální kontext relace přihlášeného uživatele

		$this->page_title = $this->phrase('page_title', [], 'Aktivita uživatelů - BCM Osiris'); // Lokalizovaný titulek stránky
		$this->full_width = true;                                            // Roztažení hlavního panelu na plnou šířku okna

		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální efektivní role v relaci
		if ($this->access_denied OR !in_array($active_role, ['A', 'S', 'D'], true)) { // Kontrola oprávnění Admin, Sysadmin nebo Developer
			$this->access_denied = true;                                     // Odepření přístupu pro běžné uživatele
			return;                                                          // Ukončení inicializace při zamítnutí přístupu
		}

		$org_raw = (string)($dbsession['organization'] ?? '0x00');           // Surové UUID aktivní organizace z relace
		$this->is_sys_org = ($org_raw === '0x00' OR $org_raw === '00000000-0000-0000-0000-000000000000'); // Detekce systémové organizace
		$this->current_org_sql = guidliteral($org_raw);                      // Bezpečný SQL literál aktivní organizace

		// Načtení a validace filtru počtu zobrazených řádků (výchozí 100, rozsah 1 až 10 000)
		$raw_limit = trim((string)getinput('limit'));                        // Surová hodnota limitu z požadavku
		if ($raw_limit !== '' AND is_numeric($raw_limit)) {                  // Pokud byl zadán číselný limit
			$parsed_limit = intval($raw_limit);                              // Převod limitu na celé číslo
			if ($parsed_limit >= 1 AND $parsed_limit <= 10000) {             // Kontrola povoleného rozsahu řádků
				$this->limit = $parsed_limit;                                // Uložení platného limitu záznamů
			}
		}

		// Načtení textového filtru pro jméno nebo login uživatele a přepínače aktivních relací
		$this->user_filter = trim((string)getinput('user_filter', 'raw'));   // Očištěný hledaný vzorek jména/loginu
		$this->only_open = ((string)getinput('only_open') === '1');          // Příznak pouze neukončených relací
	}

	/**
	 * Vykreslí filtrační formulář a tabulku aktivity uživatelů z audit_login_session.
	 */
	protected function render_body(): void {
		$heading = htmlspecialchars($this->phrase('heading_user_activity', [], 'Aktivita a přihlášení uživatelů')); // Hlavní nadpis stránky
		$intro = htmlspecialchars($this->phrase('intro_user_activity', [], 'Přehled přihlášení a aktivity uživatelů z tabulky audit_login_session a navazujících údajů účtu (seřazeno sestupně podle času).')); // Popis

		echo "<h1 class=\"page-heading\">{$heading}</h1>\n";                 // Výpis hlavního nadpisu stránky
		echo "<p style=\"margin-bottom: 18px; color: #475569; font-size: 13px;\">{$intro}</p>\n"; // Výpis úvodního popisu

		// Sestavení filtračního formuláře (GET)
		$menu_code = trim((string)getinput('menu_code'));                    // Kód položky menu pro zachování drobečkové navigace
		$safe_menu_code = htmlspecialchars($menu_code);                      // Ošetřený kód menu pro skryté pole
		$menu_input_html = ($menu_code !== '') ? "<input type=\"hidden\" name=\"menu_code\" value=\"{$safe_menu_code}\">" : ''; // Skryté pole menu_code

		$lbl_user  = htmlspecialchars($this->phrase('lbl_filter_user', [], 'Jméno / login uživatele:')); // Popisek filtru uživatele
		$ph_user   = htmlspecialchars($this->phrase('ph_filter_user', [], 'Zadejte jméno, příjmení, login nebo e-mail...')); // Placeholder
		$lbl_open  = htmlspecialchars($this->phrase('lbl_filter_only_open', [], 'Pouze aktivní (neukončené) relace')); // Popisek přepínače
		$lbl_limit = htmlspecialchars($this->phrase('lbl_filter_limit', [], 'Počet řádků:')); // Popisek pole počtu řádků

		$safe_user  = htmlspecialchars($this->user_filter);                  // Ošetřená hodnota filtru uživatele
		$safe_limit = htmlspecialchars(strval($this->limit));                // Ošetřená hodnota počtu řádků
		$chk_open   = $this->only_open ? 'checked' : '';                     // Stav zaškrtnutí pouze neukončených relací

		$btn_filter = new abstract_button('btn_apply_filter', 'Filtrovat', 'page_audit_login_session'); // Tlačítko odeslání filtru
		$btn_filter->set_type('submit')->set_onclick('isFormDirty = false;'); // Vypnutí příznaku změny při filtrování
		$btn_filter_html = $btn_filter->render();                            // Vykreslení tlačítka Filtrovat

		$reset_url = 'index.php?page=page_audit_login_session' . ($menu_code !== '' ? '&menu_code=' . urlencode($menu_code) : ''); // URL pro zrušení filtru
		$btn_reset = new abstract_button('btn_reset_filter', 'Zrušit filtr', 'page_audit_login_session', '', 'btn-secondary'); // Tlačítko resetu filtru
		$btn_reset->set_href($reset_url)->set_onclick('isFormDirty = false;'); // Odkaz pro návrat na výchozí zobrazení
		$btn_reset_html = $btn_reset->render();                              // Vykreslení tlačítka Zrušit filtr

		echo "<form method=\"get\" action=\"index.php\" onsubmit=\"isFormDirty = false;\" style=\"background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; padding: 12px 15px; margin-bottom: 18px; display: flex; align-items: center; gap: 15px; flex-wrap: wrap;\">\n";
		echo "\t<input type=\"hidden\" name=\"page\" value=\"page_audit_login_session\">\n";
		echo "\t{$menu_input_html}\n";                                       // Vložení skrytého pole pro kód menu
		echo "\t<div style=\"display: flex; align-items: center; gap: 6px; flex: 1; min-width: 280px; max-width: 440px;\">\n";
		echo "\t\t<label for=\"inp_user_filter\" style=\"font-weight: bold; font-size: 13px; color: #334155; white-space: nowrap;\">{$lbl_user}</label>\n"; // Popisek uživatele
		echo "\t\t<input type=\"text\" id=\"inp_user_filter\" name=\"user_filter\" value=\"{$safe_user}\" placeholder=\"{$ph_user}\" oninput=\"isFormDirty = false;\" style=\"width: 100%; padding: 6px 8px; border: 1px solid #cbd5e1; border-radius: 3px; font-size: 13px; box-sizing: border-box;\">\n"; // Pole filtru uživatele
		echo "\t</div>\n";
		echo "\t<div style=\"display: flex; align-items: center; gap: 6px;\">\n";
		echo "\t\t<label style=\"font-size: 13px; color: #334155; cursor: pointer; display: inline-flex; align-items: center; gap: 5px; user-select: none;\">\n";
		echo "\t\t\t<input type=\"checkbox\" name=\"only_open\" value=\"1\" {$chk_open} onchange=\"isFormDirty = false; this.form.submit();\"> {$lbl_open}\n"; // Checkbox aktivních relací
		echo "\t\t</label>\n";
		echo "\t</div>\n";
		echo "\t<div style=\"display: flex; align-items: center; gap: 6px;\">\n";
		echo "\t\t<label for=\"inp_limit\" style=\"font-weight: bold; font-size: 13px; color: #334155; white-space: nowrap;\">{$lbl_limit}</label>\n"; // Popisek počtu řádků
		echo "\t\t<input type=\"number\" id=\"inp_limit\" name=\"limit\" value=\"{$safe_limit}\" min=\"1\" max=\"10000\" oninput=\"isFormDirty = false;\" style=\"width: 90px; padding: 6px 8px; border: 1px solid #cbd5e1; border-radius: 3px; font-size: 13px;\">\n"; // Pole počtu řádků
		echo "\t</div>\n";
		echo "\t<div style=\"display: flex; align-items: center; gap: 8px;\">\n";
		echo "\t\t{$btn_filter_html}\n";                                     // Tlačítko pro potvrzení filtru
		echo "\t\t{$btn_reset_html}\n";                                      // Tlačítko pro vyčištění filtru
		echo "\t</div>\n";
		echo "</form>\n";

		// Sestavení podmínek WHERE (izolace organizace mimo 0x00 + filtr na neukončené relace + filtr na jméno/login)
		$where_parts = [];                                                   // Pole jednotlivých podmínek WHERE
		if (!$this->is_sys_org) {                                            // Pokud správce není v systémové organizaci 0x00
			$where_parts[] = "a.organization_uuid = {$this->current_org_sql}"; // Omezení na aktuální organizaci
		}

		if ($this->only_open) {                                              // Pokud chce uživatel vidět jen právě otevřené relace
			$where_parts[] = "a.logout_time IS NULL";                        // Podmínka neukončené relace
		}

		if ($this->user_filter !== '') {                                     // Pokud uživatel zadal filtr na jméno/login
			$like_lit = charliteral('%' . $this->user_filter . '%');         // Bezpečný SQL literál se znaky % pro LIKE
			$where_parts[] = "("
				. "ISNULL(u.login_name, CASE WHEN a.user_account_uuid = 0x00 THEN 'admin' ELSE '' END) LIKE {$like_lit}"
				. " OR ISNULL(u.caption, CASE WHEN a.user_account_uuid = 0x00 THEN 'System Administrator' ELSE '' END) LIKE {$like_lit}"
				. " OR ISNULL(u.first_name, '') LIKE {$like_lit}"
				. " OR ISNULL(u.last_name, '') LIKE {$like_lit}"
				. " OR (ISNULL(u.first_name, '') + ' ' + ISNULL(u.last_name, '')) LIKE {$like_lit}"
				. " OR (ISNULL(u.last_name, '') + ' ' + ISNULL(u.first_name, '')) LIKE {$like_lit}"
				. " OR ISNULL(u.email, '') LIKE {$like_lit}"
				. ")";                                                       // Komplexní podmínka na login, jméno a e-mail
		}

		$where_sql = !empty($where_parts) ? ('WHERE ' . implode(' AND ', $where_parts)) : ''; // Výsledná klauzule WHERE
		$top_int = intval($this->limit);                                     // Jistota celočíselného TOP limitu

		$sql = "
		SELECT TOP ({$top_int})
			a.uuid,
			a.user_account_uuid,
			a.organization_uuid,
			a.assumed_role,
			a.login_time,
			a.last_request_time,
			a.logout_time,
			a.ip_address,
			DATEDIFF(minute, a.login_time, COALESCE(a.logout_time, a.last_request_time)) AS duration_minutes,
			CASE
				WHEN a.user_account_uuid = 0x00 THEN 'admin'
				ELSE ISNULL(u.login_name, '')
			END AS login_name,
			CASE
				WHEN a.user_account_uuid = 0x00 THEN 'System Administrator'
				ELSE ISNULL(NULLIF(LTRIM(RTRIM(u.caption)), ''), LTRIM(RTRIM(ISNULL(u.first_name, '') + ' ' + ISNULL(u.last_name, ''))))
			END AS user_full_name,
			ISNULL(u.email, '') AS email,
			ISNULL(uoa.department_name, '') AS department_name,
			ISNULL(uoa.job_title, '') AS job_title,
			ISNULL(u.inactive, 0) AS user_inactive,
			CASE
				WHEN a.organization_uuid = 0x00 THEN 'System (0x00)'
				ELSE ISNULL(NULLIF(LTRIM(RTRIM(o.shortname)), ''), ISNULL(o.caption, ''))
			END AS org_display,
			ISNULL(o.caption, '') AS org_full_caption
		FROM audit_login_session a
		LEFT JOIN user_account u
			ON u.original = a.user_account_uuid
			AND u.record_type = 'A'
		LEFT JOIN organization o
			ON o.original = a.organization_uuid
			AND o.record_type = 'A'
		LEFT JOIN user_organization_access uoa
			ON uoa.user_account_uuid = a.user_account_uuid
			AND uoa.organization_uuid = a.organization_uuid
			AND uoa.record_type = 'A'
		{$where_sql}
		ORDER BY a.login_time DESC, a.last_request_time DESC
		";                                                                   // Dotaz na aktivitu uživatelů seřazený sestupně podle času

		$rows = sqlarray_simple($sql);                                       // Načtení celého výsledku do pole v paměti
		$row_count = is_array($rows) ? count($rows) : 0;                     // Počet načtených záznamů

		if ($row_count === 0) {                                              // Pokud dotaz nevrátil žádné záznamy
			$msg_empty = htmlspecialchars($this->phrase('msg_no_records', [], 'Zadaným kritériím neodpovídají v tabulce audit_login_session žádné záznamy.')); // Informační hláška
			echo "<div class=\"msg-info\">{$msg_empty}</div>\n";             // Výpis informační hlášky
			return;                                                          // Ukončení vykreslování
		}

		$lbl_found    = htmlspecialchars($this->phrase('lbl_displayed_records', ['count' => $row_count], 'Zobrazeno záznamů: {' . chr(36) . 'count}')); // Počet zobrazených řádků
		$th_login_tm  = htmlspecialchars($this->phrase('th_login_time', [], 'Čas přihlášení'));       // Záhlaví času přihlášení
		$th_last_req  = htmlspecialchars($this->phrase('th_last_request_time', [], 'Poslední aktivita')); // Záhlaví poslední aktivity
		$th_logout_tm = htmlspecialchars($this->phrase('th_logout_time', [], 'Odhlášení / Expirace')); // Záhlaví času odhlášení
		$th_duration  = htmlspecialchars($this->phrase('th_duration_min', [], 'Trvání'));              // Záhlaví doby trvání
		$th_org       = htmlspecialchars($this->phrase('th_organization', [], 'Organizace'));          // Záhlaví cílové organizace (pro 0x00)
		$th_login     = htmlspecialchars($this->phrase('th_login_name', [], 'Login'));                 // Záhlaví přihlašovacího jména
		$th_user_name = htmlspecialchars($this->phrase('th_user_name', [], 'Jméno uživatele'));        // Záhlaví jména uživatele
		$th_email     = htmlspecialchars($this->phrase('th_email', [], 'E-mail'));                     // Záhlaví e-mailu
		$th_dept_job  = htmlspecialchars($this->phrase('th_dept_job', [], 'Oddělení / Pozice'));       // Záhlaví oddělení a pozice
		$th_role      = htmlspecialchars($this->phrase('th_assumed_role', [], 'Role'));                // Záhlaví zvolené role
		$th_ip        = htmlspecialchars($this->phrase('th_ip_address', [], 'IP adresa'));             // Záhlaví IP adresy

		$txt_open_sess = htmlspecialchars($this->phrase('txt_session_open', [], 'Neukončeno'));        // Text pro dosud neukončenou relaci
		$txt_inactive  = htmlspecialchars($this->phrase('badge_user_inactive', [], 'Neaktivní účet')); // Štítek neaktivního účtu
		$unit_min      = htmlspecialchars($this->phrase('unit_minutes', [], 'min'));                   // Jednotka minut

		$th_org_html = $this->is_sys_org ? "<th>{$th_org}</th>" : '';        // Sloupec organizace vykreslujeme v 0x00

		echo <<<HTML
		<style>
			.role-badge { display: inline-block; font-size: 11px; font-weight: bold; padding: 2px 6px; border-radius: 3px; color: #fff; }
			.role-badge-sys { background-color: #b91c1c; }
			.role-badge-org { background-color: #2563eb; }
			.role-badge-usr { background-color: #64748b; }
		</style>
		<div style="margin-bottom: 8px; font-size: 12px; color: #64748b; font-weight: bold;">{$lbl_found}</div>
		<table class="md-table">
			<thead>
				<tr>
					<th style="width: 135px;">{$th_login_tm}</th>
					<th style="width: 135px;">{$th_last_req}</th>
					<th style="width: 135px;">{$th_logout_tm}</th>
					<th style="width: 70px; text-align: right;">{$th_duration}</th>
					{$th_org_html}
					<th style="width: 130px;">{$th_login}</th>
					<th>{$th_user_name}</th>
					<th>{$th_email}</th>
					<th>{$th_dept_job}</th>
					<th style="width: 85px; text-align: center;">{$th_role}</th>
					<th style="width: 150px;">{$th_ip}</th>
				</tr>
			</thead>
			<tbody>
HTML;

		foreach ($rows as $row) {                                            // Průchod načtenými záznamy v paměti
			$login_tm_raw = (string)($row['login_time'] ?? '');              // Surový čas přihlášení
			$last_req_raw = (string)($row['last_request_time'] ?? '');       // Surový čas poslední aktivity
			$logout_raw   = (string)($row['logout_time'] ?? '');             // Surový čas odhlášení nebo expirace

			$login_tm_val = htmlspecialchars(date_format4($login_tm_raw, 16)); // Zformátovaný čas přihlášení (d.m.Y H:i)
			$login_tm_tip = htmlspecialchars($login_tm_raw);                 // Přesný čas přihlášení včetně sekund do tooltipu
			$last_req_val = htmlspecialchars(date_format4($last_req_raw, 16)); // Zformátovaný čas poslední aktivity
			$last_req_tip = htmlspecialchars($last_req_raw);                 // Přesný čas poslední aktivity do tooltipu

			if ($logout_raw !== '') {                                        // Pokud má relace zaznamenaný čas odhlášení/expirace
				$logout_val = htmlspecialchars(date_format4($logout_raw, 16)); // Zformátovaný čas odhlášení
				$logout_tip = htmlspecialchars($logout_raw);                 // Přesný čas odhlášení do tooltipu
				$logout_html = "<span title=\"{$logout_tip}\">{$logout_val}</span>"; // Výpis času odhlášení
			} else {
				$logout_html = "<span style=\"color: #15803d; font-style: italic; font-size: 12px; font-weight: bold;\">{$txt_open_sess}</span>"; // Relace bez logout_time
			}

			$dur_min = max(0, intval($row['duration_minutes'] ?? 0));        // Délka trvání relace v minutách
			$dur_html = "{$dur_min} {$unit_min}";                            // Zformátovaná doba trvání

			$org_td_html = '';                                               // Buňka cílové organizace pro 0x00
			if ($this->is_sys_org) {                                         // V systémové organizaci vypíšeme název/zkratku tenanta
				$org_disp = htmlspecialchars((string)($row['org_display'] ?? '')); // Zkratka nebo název organizace
				$org_tip  = htmlspecialchars((string)($row['org_full_caption'] ?? '')); // Plný název organizace do tooltipu
				$org_td_html = "<td title=\"{$org_tip}\" style=\"font-weight: bold; color: #334155;\">{$org_disp}</td>"; // Buňka organizace
			}

			$login_val = htmlspecialchars((string)($row['login_name'] ?? '')); // Ošetřené přihlašovací jméno
			$name_val  = htmlspecialchars((string)($row['user_full_name'] ?? '')); // Ošetřené celé jméno uživatele
			$email_val = htmlspecialchars((string)($row['email'] ?? ''));    // Ošetřený e-mail uživatele

			$dept = trim((string)($row['department_name'] ?? ''));           // Oddělení uživatele v organizaci
			$job  = trim((string)($row['job_title'] ?? ''));                 // Pracovní pozice uživatele v organizaci
			$dept_job_raw = ($dept !== '' AND $job !== '') ? "{$dept} / {$job}" : ($dept ?: $job); // Spojení oddělení a pozice
			$dept_job_val = htmlspecialchars($dept_job_raw);                 // Ošetřený text oddělení a pozice

			$inact_badge = !empty($row['user_inactive'])
				? " <span style=\"color: #b91c1c; font-size: 11px;\">({$txt_inactive})</span>"
				: '';                                                        // Případné upozornění na neaktivní účet

			$role_code = (string)($row['assumed_role'] ?? 'U');              // Kód zvolené role v relaci
			$role_cls = 'role-badge-usr';                                    // Výchozí styl odznaku role
			$role_label = 'User';                                            // Výchozí text role
			if ($role_code === 'D') {                                        // Role Developer
				$role_cls = 'role-badge-sys';                                // Červený odznak
				$role_label = 'Developer';                                   // Popisek Developer
			} elseif ($role_code === 'S') {                                  // Role Sysadmin
				$role_cls = 'role-badge-sys';                                // Červený odznak
				$role_label = 'Sysadmin';                                    // Popisek Sysadmin
			} elseif ($role_code === 'A') {                                  // Role Admin organizace
				$role_cls = 'role-badge-org';                                // Modrý odznak
				$role_label = 'Admin';                                       // Popisek Admin
			}
			$safe_role_label = htmlspecialchars($role_label);                // Ošetřený popisek role
			$ip_val = htmlspecialchars((string)($row['ip_address'] ?? ''));  // Ošetřená IP adresa

			echo "\t\t<tr>\n";
			echo "\t\t\t<td style=\"white-space: nowrap; font-family: monospace;\" title=\"{$login_tm_tip}\">{$login_tm_val}</td>\n"; // Buňka času přihlášení
			echo "\t\t\t<td style=\"white-space: nowrap; font-family: monospace;\" title=\"{$last_req_tip}\">{$last_req_val}</td>\n"; // Buňka poslední aktivity
			echo "\t\t\t<td style=\"white-space: nowrap; font-family: monospace;\">{$logout_html}</td>\n";                            // Buňka času odhlášení
			echo "\t\t\t<td style=\"text-align: right; white-space: nowrap; font-family: monospace; color: #475569;\">{$dur_html}</td>\n"; // Buňka trvání
			if ($this->is_sys_org) {                                         // Výpis buňky organizace v 0x00
				echo "\t\t\t{$org_td_html}\n";                               // Buňka organizace
			}
			echo "\t\t\t<td style=\"font-family: monospace; color: #004488; font-weight: bold;\">{$login_val}</td>\n";                // Buňka loginu
			echo "\t\t\t<td><strong>{$name_val}</strong>{$inact_badge}</td>\n";                                                       // Buňka jména uživatele
			echo "\t\t\t<td style=\"font-size: 12px; color: #475569;\">{$email_val}</td>\n";                                          // Buňka e-mailu
			echo "\t\t\t<td style=\"font-size: 12px; color: #475569;\">{$dept_job_val}</td>\n";                                       // Buňka oddělení a pozice
			echo "\t\t\t<td style=\"text-align: center;\"><span class=\"role-badge {$role_cls}\">{$safe_role_label}</span></td>\n";   // Buňka role
			echo "\t\t\t<td style=\"font-family: monospace; font-size: 12px; color: #475569;\">{$ip_val}</td>\n";                     // Buňka IP adresy
			echo "\t\t</tr>\n";
		}

		echo "\t</tbody>\n";
		echo "</table>\n";
	}
}