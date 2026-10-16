<?php
/**
 * =============================================================================
 * Verze: 2026-10-16 10:15
 * Soubor: user_context.php
 * Třída: user_context
 * Účel: Kompaktní vizuální komponenta (logo, uživatel, organizace, role, odhlášení)
 *       zobrazená jako standardní fixovaný horní pruh na stránce.
 * 
 * Vazby na okolí:
 * - Instancuje se a vykresluje výhradně uvnitř metody render() v `abstract_page`.
 * - Spoléhá na existenci globálního pole `$dbsession` a správce frází `$phrase_manager`.
 * - Dynamicky reaguje na efektivní roli (active_role: U, A, S, D), kterou si uživatel
 *   zvolil při přihlášení nebo explicitní změně kontextu.
 * - Využívá `language_manager` pro zobrazení přepínače jazyků s vlaječkami
 *   a plně odbavuje PRG přesměrování při změně jazyka (včetně zápisu do DB).
 * - Využívá `abstract_button` pro vykreslení odhlašovacího tlačítka.
 *
 * Změny:
 * 2026-10-16 10:15 - Nahrazení symbolických operátorů || a && slovními OR a AND (Anti-LaTeX).
 * 2026-10-16 09:55 - Rozdělení spojeného řádku v metodě phrase() a doplnění diakritiky
 *                    do inline komentářů (Anti-LaTeX ochrana).
 * 2026-10-16 08:50 - Oprava komentářů s diakritikou ve switch ($active_role) bránící
 *                    spojení řádků s proměnnou $roleClass a doplnění výchozí inicializace.
 * =============================================================================
 */

declare(strict_types=1);

class user_context {

	/**
	 * Pomocná metoda pro získání lokalizované fráze patřící komponentě user_context.
	 */
	private function phrase(string $builtin_code, string $default_caption): string { // Načtení přeložené fráze
		global $phrase_manager;                                              // Globální instance správce frází
		if (!isset($phrase_manager) OR !($phrase_manager instanceof phrase_manager)) { // Kontrola existence správce frází
			$phrase_manager = new phrase_manager();                          // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] = $phrase_manager;                    // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, [], $default_caption, 'user_context'); // Načtení fráze komponenty
	}

	public function __toString(): string {
		return $this->render();                                              // Přímé vykreslení komponenty
	}

	public function render(): string {
		global $dbsession;                                                   // Globální pole relace uživatele

		// Zjednodušená kontrola obcházející copy-paste artefakty s operátorem OR
		if (empty($dbsession['user_account'])) {                             // Pokud uživatel není přihlášen
			return '';                                                       // Horní lištu nevykreslujeme
		}

		// =====================================================================
		// INTEGRACE JAZYKŮ A ZPRACOVÁNÍ ZMĚNY
		// =====================================================================
		
		// Příprava URL pro návrat po změně jazyka (očištění od předchozího set_lang parametru)
		$get_params = $_GET;                                                 // Kopie aktuálních GET parametrů
		unset($get_params['set_lang']);                                      // Odstranění parametru změny jazyka
		$return_url = 'index.php';                                           // Základní návratová adresa
		if (!empty($get_params)) {                                           // Pokud v URL zůstaly další parametry
			$return_url .= '?' . http_build_query($get_params);              // Sestavení čistého query stringu
		}

		// Zpracování případného požadavku na změnu jazyka z UI
		$requested_lang = (isset($_GET['set_lang']) AND is_string($_GET['set_lang'])) ? $_GET['set_lang'] : null; // Požadovaný jazyk z URL
		$lang_manager = new language_manager($requested_lang);               // Inicializace správce jazyků

		// PRG vzor: Po přepnutí uložíme data do DB a přesměrujeme na čisté URL
		if ($requested_lang !== null) {                                      // Pokud došlo k přepnutí jazyka
			// K zápisu použijeme bezpečně zvalidovaný jazyk z objektu language_manager
			$valid_lang = $lang_manager->get_current_language();             // Zvalidovaný kód jazyka
			$safe_lang = charliteral($valid_lang, 2);                        // SQL literál kódu jazyka
			
			// 1. Aktualizace jazyka v běžících relacích aktuálního SPID
			sqlrun("
				UPDATE dbsession SET [language] = {$safe_lang} WHERE spid = @@SPID;
				UPDATE wwwsession SET [language] = {$safe_lang} WHERE spid = @@SPID;
			");                                                              // Aktualizace jazyka v databázové relaci
			
			// 2. Trvalé uložení jazykové preference k uživatelskému účtu
			if (!empty($dbsession['user_account'])) {                        // Kontrola přítomnosti účtu
				$safe_user = guidliteral((string)$dbsession['user_account']); // SQL literál UUID uživatele
				sqlrun("UPDATE user_account SET [language] = {$safe_lang} WHERE original = {$safe_user} AND record_type = 'A'"); // Uložení jazyka k účtu
			}
			
			header('Location: ' . $return_url);                              // Přesměrování bez parametru set_lang
			exit;                                                            // Okamžité ukončení běhu
		}

		// Vygenerování vizuálního přepínače pro hlavičku
		$langSelectorHtml = $lang_manager->render_language_selector($return_url); // HTML přepínače jazyků

		// =====================================================================
		// LOKALIZACE POPISKŮ, ROLÍ A TLAČÍTEK
		// =====================================================================
		$default_user = $this->phrase('lbl_default_user', 'Uživatel');       // Výchozí označení uživatele
		$default_org = $this->phrase('lbl_default_org', 'Organizace');       // Výchozí označení organizace

		$displayName = (string)($dbsession['display_name'] ?? $dbsession['user_name'] ?? $default_user); // Jméno přihlášeného uživatele
		$orgName = (string)($dbsession['organization_name'] ?? $default_org); // Název aktivní organizace

		// Využití stručnějších zkratek rolí pro úsporu místa v panelu dle nové architektury active_role
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktivní role v relaci
		$roleText = 'USER';                                                  // Výchozí popisek uživatelské role
		$roleClass = 'usr';                                                  // Výchozí CSS třída uživatelské role

		switch ($active_role) {                                              // Rozlišení stylu a popisku podle aktivní role
			case 'D':
				$roleText = $this->phrase('role_dev', 'DEV');                // Zkratka vývojářské role Developer
				$roleClass = 'sys';                                          // Červený styl pro systémovou roli
				break;
			case 'S':
				$roleText = $this->phrase('role_sysadmin', 'SYSADMIN');      // Zkratka systémové role Sysadmin
				$roleClass = 'sys';                                          // Červený styl pro systémovou roli
				break;
			case 'A':
				$roleText = $this->phrase('role_admin', 'ADMIN');            // Zkratka správcovské role Admin
				$roleClass = 'org';                                          // Modrý styl pro roli organizace
				break;
			case 'U':
			default:
				$roleText = $this->phrase('role_user', 'USER');              // Zkratka běžného uživatele
				$roleClass = 'usr';                                          // Šedý styl pro běžného uživatele
				break;
		}

		$safeDisplayName = htmlspecialchars($displayName, ENT_QUOTES, 'UTF-8'); // Ošetřené jméno uživatele
		$safeOrgName = htmlspecialchars($orgName, ENT_QUOTES, 'UTF-8');      // Ošetřený název organizace
		$safeRoleText = htmlspecialchars($roleText, ENT_QUOTES, 'UTF-8');    // Ošetřený popisek role

		// Vykreslení organizace s odkazem, pokud je povolená změna kontextu
		if (!empty($dbsession['change_context_allowed'])) {                  // Pokud může uživatel měnit kontext
			$tip_change = htmlspecialchars($this->phrase('tip_change_context', 'Změnit organizaci či roli'), ENT_QUOTES, 'UTF-8'); // Tooltip změny kontextu
			$orgHtml = '<a href="index.php?page=page_change_user_context" class="bcm-context-org link" title="' . $tip_change . '">' . $safeOrgName . ' <span style="font-size: 10px;">▼</span></a>'; // Odkaz na změnu kontextu
		} else {
			$tip_org = htmlspecialchars($this->phrase('tip_current_org', 'Aktuální organizace'), ENT_QUOTES, 'UTF-8'); // Tooltip organizace
			$orgHtml = '<span class="bcm-context-org" title="' . $tip_org . '">' . $safeOrgName . '</span>'; // Statický název organizace
		}

		$tip_user = htmlspecialchars($this->phrase('tip_logged_user', 'Přihlášený uživatel'), ENT_QUOTES, 'UTF-8'); // Tooltip jména uživatele
		$logo_placeholder = htmlspecialchars($this->phrase('lbl_logo_placeholder', '[ Logo / Grafika ]'), ENT_QUOTES, 'UTF-8'); // Text zástupného symbolu loga

		// Tlačítko odhlášení vykreslené přes abstract_button
		$btn_logout = new abstract_button('btn_logout', 'Odhlásit', 'user_context', '', 'ctx-logout'); // Komponenta tlačítka odhlášení
		$btn_logout->set_href('index.php?page=page_logout');                 // Nastavení odkazu na odhlášení
		$logoutHtml = $btn_logout->render();                                 // Vykreslení odhlašovacího odkazu

		// =====================================================================
		// HTML VÝSTUP A STYLY KOMPONENTY
		// =====================================================================
		
		return <<<HTML
<style>
	.bcm-top-bar {
		background: #ffffff;
		border-bottom: 1px solid #cbd5e1;
		padding: 4px 12px;
		font-family: Arial, sans-serif;
		font-size: 12px;
		color: #334155;
		display: flex;
		justify-content: space-between;
		align-items: center;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
	}
	.bcm-top-bar-left {
		display: flex;
		align-items: center;
		gap: 15px;
	}
	.bcm-top-bar-right {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.bcm-context-org { 
		font-weight: bold; 
		color: #0f172a; 
	}
	a.bcm-context-org.link {
		text-decoration: none;
		padding: 2px 6px;
		border-radius: 3px;
		transition: background 0.2s;
	}
	a.bcm-context-org.link:hover {
		background-color: #f1f5f9;
		color: #2563eb;
	}
	.bcm-context-user { 
		color: #475569; 
	}
	.ctx-role { 
		font-size: 10px; 
		font-weight: bold; 
		padding: 2px 6px; 
		border-radius: 3px; 
		color: #fff; 
		letter-spacing: 0.5px;
	}
	.ctx-role.sys { background-color: #b91c1c; }
	.ctx-role.org { background-color: #2563eb; }
	.ctx-role.usr { background-color: #64748b; }
	
	.ctx-logout, .btn.ctx-logout {
		background-color: transparent;
		color: #b91c1c;
		text-decoration: none;
		font-weight: bold;
		font-size: 12px;
		padding: 2px 6px;
		border-left: 1px solid #e2e8f0;
		border-radius: 0;
		margin-left: 5px;
		transition: background 0.2s;
	}
	.ctx-logout:hover, .btn.ctx-logout:hover { 
		background-color: #fee2e2; 
		color: #b91c1c;
		border-radius: 3px;
	}
	.ctx-graphic-placeholder {
		color: #94a3b8;
		font-style: italic;
		font-weight: bold;
		font-size: 14px;
	}
	
	@media print { .bcm-top-bar { display: none !important; } }
</style>

<div class="bcm-top-bar">
	<div class="bcm-top-bar-left">
		<div class="ctx-graphic-placeholder">
			{$logo_placeholder}
		</div>
	</div>
	<div class="bcm-top-bar-right">
		{$langSelectorHtml}
		<span style="color: #cbd5e1;">&#124;</span>
		{$orgHtml}
		<span style="color: #cbd5e1;">&#124;</span>
		<span class="bcm-context-user" title="{$tip_user}">{$safeDisplayName}</span>
		<span class="ctx-role {$roleClass}">{$safeRoleText}</span>
		{$logoutHtml}
	</div>
</div>
HTML;
	}
}