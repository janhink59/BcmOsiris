<?php
/**
 * =============================================================================
 * Verze: 2026-10-23 16:20
 * Soubor: page_csv_package.php
 * Třída: page_csv_package
 * Účel: Uživatelské rozhraní pro export a dvoufázový import víceblokových
 *       CSV/TSV balíčků mezi instancemi systému BCM Osiris.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_csv_package`.
 * - Dědí z `abstract_page` (využívá `$this->page_title`, `$this->access_denied`,
 *   `$this->full_width`, `$this->phrase()` a `parent::render()`).
 * - Načítá `abstract_csv_package.php` a dynamicky instancuje konkrétní třídu
 *   balíčku `csv_package_{$package_code}` (výchozí `'metadata'`).
 * - Využívá `abstract_button` pro vykreslení tlačítek a `regfile()` z `OsirisLib.php`
 *   pro zpracování nahraného CSV/TSV souboru.
 * =============================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/abstract_csv_package.php';

class page_csv_package extends abstract_page {

	private string $package_code = 'metadata';                               // Zvolený kód CSV balíčku
	private ?abstract_csv_package $pkg = null;                               // Instance aktivního CSV balíčku
	private string $step = 'FORM';                                           // Aktuální krok UI ('FORM', 'PHASE1', 'PHASE2')

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->page_title =$this->phrase('page_title', [], 'Přenos datových balíčků (CSV/TSV) - BCM Osiris'); // Titulek stránky

		if ($this->access_denied) {                                          // Pokud předek zamítl přístup ke stránce
			return;                                                          // Ukončení inicializace
		}

		$req_pkg = trim((string)getinput('package_code'));                   // Načtení kódu balíčku z GET/POST
		if ($req_pkg !== '' AND preg_match('/^[a-zA-Z0-9_]+$/',$req_pkg)) { // Validace kódu balíčku
			$this->package_code =$req_pkg;                                  // Uložení zvoleného kódu balíčku
		}

		$cls_name = 'csv_package_' .$this->package_code;                    // Odvození názvu třídy balíčku
		if (class_exists($cls_name)) {                                       // Kontrola existence třídy balíčku
			$this->pkg = new $cls_name($_REQUEST);                           // Instancování balíčku s předanými parametry
		}
	}

	/**
	 * Zpracuje přímý export souboru (před odesláním HTML hlaviček) nebo Fázi 1 a Fázi 2 importu.
	 */
	public function render(): void {
		$this->init_phrases();                                               // Pojistka inicializace správce frází
		$this->check_system_role_access();                                   // Pojistka kontroly přístupu podle meta_object

		if ($this->access_denied OR$this->pkg === null) {                   // Kontrola přístupu a platného balíčku
			parent::render();                                                // Vykreslení chybového stavu předkem
			return;                                                          // Ukončení
		}

		// 1. Požadavek na export balíčku do TSV souboru (musí proběhnout před výpisem HTML)
		if (isset($_POST['btn_export_csv'])) {                               // Detekce stisku tlačítka Exportovat
			$this->pkg->set_parameters_from_request($_POST);                 // Nastavení parametrů z formuláře
			$this->pkg->export_to_browser("\t");                             // Odeslání TSV souboru do prohlížeče a exit
			return;                                                          // Pojistka ukončení
		}

		// 2. Požadavek na Fázi 1 importu (nahrání CSV/TSV souboru do session_import_*)
		$tmpfile = regfile('file_csv');                                      // Cesta k nahranému souboru z $_FILES
		if ($tmpfile !== '') {                                               // Pokud uživatel odeslal soubor k importu
			$this->full_width = true;                                        // Široký panel pro přehledové tabulky
			$this->step = 'PHASE1';                                          // Přepnutí do zobrazení Fáze 1
			$orig_name = (string)($_FILES['file_csv']['name'] ?? basename($tmpfile)); // Původní jméno souboru
			$msg_file =$this->phrase('msg_uploaded_file', [], 'Nahrán vstupní soubor'); // Zpráva o nahrání souboru
			$this->pkg->rqm->add_message($msg_file, 0)->setobject('Soubor',$orig_name); // Zápis do logu
			$this->pkg->load_file_to_session($tmpfile);                      // Rozpitvání souboru do session_import_*
		}

		// 3. Požadavek na Fázi 2 importu (spuštění uložené procedury p_csv_import_*)
		if (isset($_POST['btn_run_phase2'])) {                               // Detekce potvrzení Fáze 2
			$this->full_width = true;                                        // Široký panel pro výpis výsledků
			$this->step = 'PHASE2';                                          // Přepnutí do zobrazení výsledku Fáze 2
			$overrides = (isset($_POST['override_param']) AND is_array($_POST['override_param'])) ?$_POST['override_param'] : []; // Změněné parametry
			$this->pkg->run_import($overrides);                              // Spuštění procedury v databázi
		}

		parent::render();                                                    // Vykreslení HTML stránky
	}

	/**
	 * Vykreslí obsah stránky podle aktuální fáze (vstupní formuláře, Fáze 1 nebo Fáze 2).
	 */
	protected function render_body(): void {
		$heading = htmlspecialchars($this->phrase('heading_csv_packages', [], 'Přenos datových balíčků mezi instancemi (CSV / TSV)')); // Nadpis
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

		// C. Výchozí zobrazení: 1. Exportní formulář parametrů + 2. Formulář pro nahrání souboru (Fáze 1)
		echo $this->pkg->render_parameters_div($action_url);                 // Vykreslení sekce pro export balíčku

		$hdr_imp = htmlspecialchars($this->phrase('hdr_import_section', [], 'Dvoufázový import balíčku ze souboru TSV / CSV')); // Nadpis importu
		$desc_imp = htmlspecialchars($this->phrase('desc_import_section', [], 'Nahrajte soubor balíčku (.tsv nebo .csv). V 1. fázi systém ověří elektronický podpis, zkontroluje strukturu a zobrazí přehled dat před samotným zápisem do databáze.')); // Popis
		$lbl_file = htmlspecialchars($this->phrase('lbl_csv_file', [], 'Soubor balíčku (TSV/CSV):')); // Popisek pole souboru
		$safe_action = htmlspecialchars($action_url);                        // Ošetřená URL akce formuláře
		$safe_code = htmlspecialchars($this->package_code);                  // Ošetřený kód balíčku

		$btn_up = new abstract_button('btn_upload_phase1', 'Načíst a zkontrolovat soubor (Fáze 1)', 'page_csv_package'); // Tlačítko Fáze 1
		$btn_up->set_type('submit')->set_name_value('btn_upload_phase1', '1'); // Submit atributy
		$btn_up_html =$btn_up->render();                                    // HTML tlačítka Fáze 1

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
						<td><input type="file" name="file_csv" accept=".tsv,.csv,.txt" required style="width: 100%; max-width: 380px;"></td>
					</tr>
				</table>
				<div>{$btn_up_html}</div>
			</form>
		</div>
HTML;
	}
}