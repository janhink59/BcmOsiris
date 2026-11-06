<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 14:15
 * Soubor: page_csv_package.php
 * Třída: page_csv_package
 * Účel: Uživatelské rozhraní pro export a dvoufázový import víceblokových
 *       CSV balíčků mezi instancemi systému BCM Osiris (podporuje přepínání
 *       balíčků `metadata` a `simple_class` a automatickou detekci typu
 *       balíčku z 1. řádku nahrávaného CSV souboru).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_csv_package`.
 * - Dědí z `abstract_page` (`abstract_page.php`).
 * - Načítá `abstract_csv_package.php` a dynamicky instancuje konkrétní třídu
 *   balíčku `csv_package_{$package_code}` (`metadata` nebo `simple_class`).
 *
 * Změny:
 * 2026-11-06 14:15 - Doplněn přepínač balíčků (`metadata` / `simple_class`),
 *                    automatická detekce `package_name` z 1. řádku nahraného CSV
 *                    souboru při Fázi 1 a zpřístupnění stránky pro přenos `simple_class`.
 * 2026-10-24 14:35 - Export balíčku přepnut na výchozí oddělovač středník (`;`).
 * =============================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/abstract_csv_package.php';

class page_csv_package extends abstract_page {

	private string $package_code = 'simple_class';                           // Zvolený kód CSV balíčku (výchozí simple_class)
	private ?abstract_csv_package $pkg = null;                               // Instance aktivního CSV balíčku
	private string $step = 'FORM';                                           // Aktuální krok UI ('FORM', 'PHASE1', 'PHASE2')

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->page_title = $this->phrase('page_title', [], 'Přenos datových balíčků (CSV) - BCM Osiris'); // Titulek stránky

		// Povolíme přístup i pro přihlášené uživatele spouštějící export/import simple_class ze seznamu záznamů
		global $dbsession;                                                   // Globální kontext relace
		if (! empty($dbsession['user_account'])) {                           // Pokud je uživatel řádně přihlášen
			$this->access_denied = false;                                    // Odemčení stránky pro práci s CSV balíčky
		}

		if ($this->access_denied) {                                          // Pokud uživatel není přihlášen
			return;                                                          // Ukončení inicializace
		}

		$default_pkg = is_sys_org() ? 'metadata' : 'simple_class';           // V 0x00 výchozí metadata, v tenantovi simple_class
		$req_pkg = trim((string) getinput('package_code')) ?: $default_pkg;  // Načtení kódu balíčku z GET/POST
		if (! is_sys_org() AND ! in_array(get_session_role(), ['S', 'D'], true) AND $req_pkg === 'metadata') { // Ochrana systémových metadat
			$req_pkg = 'simple_class';                                       // Běžný tenant pracuje s balíčkem simple_class
		}

		if ($req_pkg !== '' AND preg_match('/^[a-zA-Z0-9_]+$/', $req_pkg)) { // Validace kódu balíčku
			$this->package_code = $req_pkg;                                  // Uložení zvoleného kódu balíčku
		}

		$this-> instantiate_package($this->package_code);                    // Vytvoření instance balíčku
	}

	/**
	 * Vytvoří instanci třídy `csv_package_{$code}` a předá jí parametry z requestu.
	 */
	private function instantiate_package(string $code): void {               // Instancování třídy CSV balíčku
		$cls_name = 'csv_package_' . $code;                                  // Odvození názvu třídy balíčku
		if (class_exists($cls_name)) {                                       // Kontrola existence třídy balíčku
			$this->package_code = $code;                                     // Aktualizace aktivního kódu balíčku
			$this->pkg = new $cls_name($_REQUEST);                           // Instancování balíčku s předanými parametry
		}
	}

	/**
	 * Nahlédne na první neprázdný řádek nahraného CSV souboru a zjistí hodnotu `package_name`.
	 */
	private function detect_package_code_from_file(string $filepath): string { // Detekce package_name ze souboru
		if (! is_readable($filepath)) {                                      // Kontrola čitelnosti souboru
			return '';                                                       // Nelze přečíst
		}
		$fh = fopen_bom($filepath, 'r');                                     // Otevření souboru s přeskočením UTF-8 BOM
		if (! $fh) {                                                         // Kontrola otevření souboru
			return '';                                                       // Chyba otevření
		}
		$detected = '';                                                      // Zjištěný kód balíčku
		while (($line = fgets($fh)) !== false) {                             // Čtení prvních řádků souboru
			$trimmed = trim($line);                                          // Oříznutí bílých znaků
			if ($trimmed === '') {                                           // Přeskočení prázdného řádku
				continue;                                                    // Další řádek
			}
			$delim = str_contains($trimmed, ';') ? ';' : (str_contains($trimmed, "\t") ? "\t" : ','); // Detekce oddělovače
			$parts = str_getcsv($trimmed, $delim, '"', '');                  // Rozparsování prvního řádku
			$k = trim((string) ($parts[0] ?? ''));                           // Klíč prvního parametru
			$v = trim((string) ($parts[1] ?? ''));                           // Hodnota prvního parametru
			if ($k === 'package_name' AND preg_match('/^[a-zA-Z0-9_]+$/', $v)) { // Nalezen platný identifikátor balíčku
				$detected = $v;                                              // Uložení detekovaného balíčku
			}
			break;                                                           // Stačí zkontrolovat první neprázdný řádek
		}
		fclose($fh);                                                         // Uzavření souboru
		return $detected;                                                    // Vrácení detekovaného kódu balíčku
	}

	/**
	 * Zpracuje přímý export souboru (před odesláním HTML hlaviček) nebo Fázi 1 a Fázi 2 importu.
	 */
	public function render(): void {
		$this->init_phrases();                                               // Pojistka inicializace správce frází

		if ($this->access_denied OR $this->pkg === null) {                   // Kontrola přístupu a platného balíčku
			parent::render();                                                // Vykreslení chybového stavu předkem
			return;                                                          // Ukončení
		}

		// 1. Požadavek na export balíčku do CSV souboru se středníkem (musí proběhnout před výpisem HTML)
		if (isset($_POST['btn_export_csv'])) {                               // Detekce stisku tlačítka Exportovat
			$this->pkg->set_parameters_from_request($_POST);                 // Nastavení parametrů z formuláře
			$this->pkg->export_to_browser(';');                              // Odeslání CSV souboru se středníkem do prohlížeče a exit
			return;                                                          // Pojistka ukončení
		}

		// 2. Požadavek na Fázi 1 importu (nahrání CSV souboru do session_import_*)
		$tmpfile = regfile('file_csv');                                      // Cesta k nahranému souboru z $_FILES
		if ($tmpfile !== '') {                                               // Pokud uživatel odeslal soubor k importu
			$det_code = $this->detect_package_code_from_file($tmpfile);      // Automatická detekce package_name z 1. řádku CSV
			if ($det_code !== '' AND $det_code !== $this->package_code) {    // Pokud nahraný soubor patří jinému balíčku
				if ($det_code !== 'metadata' OR in_array(get_session_role(), ['S', 'D'], true)) { // Kontrola oprávnění pro metadata
					$this->instantiate_package($det_code);                   // Automatické přepnutí na detekovanou třídu balíčku
				}
			}

			$this->full_width = true;                                        // Široký panel pro přehledové tabulky
			$this->step = 'PHASE1';                                          // Přepnutí do zobrazení Fáze 1
			$orig_name = (string) ($_FILES['file_csv']['name'] ?? basename($tmpfile)); // Původní jméno souboru
			$msg_file = $this->phrase('msg_uploaded_file', [], 'Nahrán vstupní soubor'); // Zpráva o nahrání souboru
			$this->pkg->rqm->add_message($msg_file, 0)->setobject('Soubor', $orig_name); // Zápis do logu
			$this->pkg->load_file_to_session($tmpfile);                      // Rozpitvání souboru do session_import_*
		}

		// 3. Požadavek na Fázi 2 importu (spuštění uložené procedury p_csv_import_*)
		if (isset($_POST['btn_run_phase2'])) {                               // Detekce potvrzení Fáze 2
			$this->full_width = true;                                        // Široký panel pro výpis výsledků
			$this->step = 'PHASE2';                                          // Přepnutí do zobrazení výsledku Fáze 2
			$overrides = (isset($_POST['override_param']) AND is_array($_POST['override_param'])) ? $_POST['override_param'] : []; // Změněné parametry
			$this->pkg->run_import($overrides);                              // Spuštění procedury v databázi
		}

		parent::render();                                                    // Vykreslení HTML stránky
	}

	/**
	 * Vykreslí obsah stránky podle aktuální fáze (přepínač balíčků, vstupní formuláře, Fáze 1 nebo Fáze 2).
	 */
	protected function render_body(): void {
		$heading = htmlspecialchars($this->phrase('heading_csv_packages', [], 'Přenos datových balíčků (CSV)')); // Nadpis
		echo "<h1 class=\"page-heading\">{$heading}</h1>\n";

		if ($this->pkg === null) {                                           // Pokud nebyl nalezen platný balíček
			$msg_nf = htmlspecialchars($this->phrase('err_package_not_found', [], 'Požadovaná třída balíčku nebyla nalezena.')); // Chyba
			echo "<div class=\"msg-err\">{$msg_nf}</div>";                   // Výpis chyby
			return;                                                          // Ukončení
		}

		$action_url = 'index.php?page=page_csv_package&package_code=' . urlencode($this->package_code); // Cílová URL formulářů

		// A. Zobrazení rekapitulace a kontroly po Fázi 1 importu
		if ($this->step === 'PHASE1') {                                      // Režim zobrazení Fáze 1
			echo $this->pkg->render_import_summary_div($action_url);         // Vykreslení přehledu Fáze 1 a tlačítka Fáze 2

			$btn_back = new abstract_button('btn_back_to_form', '← Zpět na výběr souboru', 'page_csv_package', '', 'btn-secondary'); // Tlačítko zpět
			$btn_back->set_href($action_url);                                // Odkaz zpět na výchozí formulář
			echo "<div>" . $btn_back->render() . "</div>\n";                 // Výpis tlačítka zpět
			return;                                                          // Ukončení vykreslování
		}

		// B. Zobrazení výsledků po dokončení Fáze 2 importu
		if ($this->step === 'PHASE2') {                                      // Režim zobrazení výsledku Fáze 2
			$hdr_res = htmlspecialchars($this->phrase('hdr_phase2_result', [], 'Výsledek importu balíčku do databáze (Fáze 2)')); // Nadpis výsledku
			echo "<h2 style=\"color: #004488; font-size: 17px; margin: 0 0 12px 0;\">{$hdr_res}</h2>\n";
			echo "<div style=\"margin-bottom: 20px;\">{$this->pkg->rqm}</div>\n"; // Výpis tabulky zpráv z DB

			$btn_done = new abstract_button('btn_back_after_import', '← Zpět na přenos balíčků', 'page_csv_package', '', 'btn-secondary'); // Návratové tlačítko
			$btn_done->set_href($action_url);                                // Cílová URL návratu
			echo "<div>" . $btn_done->render() . "</div>\n";                 // Výpis tlačítka
			return;                                                          // Ukončení vykreslování
		}

		// C. Přepínač typu balíčku (simple_class vs. metadata pro S/D)
		$can_sys_meta = in_array(get_session_role(), ['S', 'D'], true);      // Zda má uživatel právo na systémová metadata
		if ($can_sys_meta) {                                                 // Zobrazení přepínače balíčků
			$lbl_sw = htmlspecialchars($this->phrase('lbl_switch_package', [], 'Typ přenosového balíčku:')); // Popisek přepínače
			$lbl_sc = htmlspecialchars($this->phrase('opt_pkg_simple_class', [], 'Data jedné třídy organizace (simple_class)')); // Volba simple_class
			$lbl_md = htmlspecialchars($this->phrase('opt_pkg_metadata', [], 'Systémová metadata 0x00 (metadata)')); // Volba metadata
			$sel_sc = ($this->package_code === 'simple_class') ? 'selected' : ''; // Označení simple_class
			$sel_md = ($this->package_code === 'metadata') ? 'selected' : '';     // Označení metadata
			echo <<<HTML
			<div style="margin-bottom: 18px; padding: 10px 14px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; display: flex; align-items: center; gap: 10px;">
				<label style="font-weight: bold; font-size: 13px; color: #334155;">{$lbl_sw}</label>
				<select onchange="window.location.href='index.php?page=page_csv_package&package_code=' + encodeURIComponent(this.value);" style="padding: 5px 10px; font-size: 13px;">
					<option value="simple_class" {$sel_sc}>{$lbl_sc}</option>
					<option value="metadata" {$sel_md}>{$lbl_md}</option>
				</select>
			</div>
HTML;
		}

		// D. Výchozí zobrazení: 1. Exportní formulář parametrů + 2. Formulář pro nahrání souboru (Fáze 1)
		echo $this->pkg->render_parameters_div($action_url);                 // Vykreslení sekce pro export balíčku

		$hdr_imp = htmlspecialchars($this->phrase('hdr_import_section', [], 'Dvoufázový import balíčku ze souboru CSV')); // Nadpis importu
		$desc_imp = htmlspecialchars($this->phrase('desc_import_section', [], 'Nahrajte soubor balíčku (.csv). V 1. fázi systém ověří elektronický podpis, zkontroluje oprávnění organizace i strukturu a zobrazí přehled dat před samotným zápisem do databáze.')); // Popis
		$lbl_file = htmlspecialchars($this->phrase('lbl_csv_file', [], 'Soubor balíčku (CSV):')); // Popisek pole souboru
		$safe_action = htmlspecialchars($action_url);                        // Ošetřená URL akce formuláře
		$safe_code = htmlspecialchars($this->package_code);                  // Ošetřený kód balíčku

		$btn_up = new abstract_button('btn_upload_phase1', 'Načíst a zkontrolovat soubor (Fáze 1)', 'page_csv_package'); // Tlačítko Fáze 1
		$btn_up->set_type('submit')->set_name_value('btn_upload_phase1', '1'); // Submit atributy
		$btn_up_html = $btn_up->render();                                    // HTML tlačítka Fáze 1

		echo <<<HTML
		<hr style="border: 0; border-top: 2px solid #eee; margin: 25px 0;">
		<div class="csv-package-import-box">
			<h2 style="color: #004488; font-size: 17px; margin: 0 0 6px 0;">{$hdr_imp}</h2>
			<p style="color: #475569; font-size: 13px; margin: 0 0 15px 0;">{$desc_imp}</p>
			<form method="post" action="{$safe_action}" enctype="multipart/form-data">
				<input type="hidden" name="package_code" value="{$safe_code}">
				<table class="md-table" style="margin-bottom: 15px;">
					<tr>
						<td style="width: 35%; font-weight: bold; background-color: #f8fafc;">{$lbl_file} <span style="color:#b91c1c;">*</span></td>
						<td><input type="file" name="file_csv" accept=".csv,.tsv,.txt" required style="width: 100%; max-width: 380px;"></td>
					</tr>
				</table>
				<div>{$btn_up_html}</div>
			</form>
		</div>
HTML;
	}
}