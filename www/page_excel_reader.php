<?php
/**
 * =============================================================================
 * Verze: 2026-10-20 11:50
 * Soubor: page_excel_reader.php
 * Třída: page_excel_reader
 * Účel: Uživatelské rozhraní pro nahrávání, validaci, náhled a import dat z XLSX
 *       a zpětný export systémových metadat do XLSX pomocí PhpSpreadsheet.
 * Architektura: Potomek abstract_page.
 *
 * Vazby na okolí:
 * - Instancována dynamicky z index.php při požadavku ?page=page_excel_reader.
 * - Dědí z třídy abstract_page (využívá $this->page_title, $this->access_denied,
 *   $this->full_width, $this->phrase(), parent::render() a implementuje render_body()).
 * - Využívá komponentu abstract_button pro vykreslení odesílacích tlačítek.
 * - Využívá globální proměnné $dbsession (kontrola active_role přes předka)
 *   a $charset (kódování pro HTTP hlavičku distribuce).
 * - Využívá funkce regfile(), getinput(), charliteral() a sqlarray_simple()
 *   z knihovny OsirisLib.php.
 * - Instancuje a řídí třídu excel_reader (z excel_reader.php) a načítá
 *   abstraktního předka balíčků xlsx_abstract (z xlsx_abstract.php).
 * - Pro zpětný export metadat (meta_object, meta_menu, meta_phrase, meta_class,
 *   meta_column) využívá knihovnu PhpOffice\PhpSpreadsheet. Zděděné hodnoty
 *   z předků (ancestor_class / sys_global_columns) i zděděné texty ve sloupcích
 *   s příponou _l (při definovaném second_language) uzavírá <do stříšek>.
 * - V režimu distribuce ('D') volá databázovou proceduru p_export_to_sql
 *   nad dočasnými tabulkami s prefixem XLSX_ a příponou $ (chr(36)) a skládá
 *   výstupní dávku volající p_request_messages_start a p_xlsx_<package_code>.
 *
 * Změny:
 * 2026-10-20 11:50 - Doplněn export sloupce removed na všechny záložky (page, menu,
 *                    phrase, class, column) a sloupce inactive na záložku phrase.
 *                  - Položky s příponou _l na všech záložkách jsou při definovaném
 *                    druhém jazyce (second_language) a chybějícím překladu vyplněny
 *                    zděděnou hodnotou <v stříškách>; prázdné zůstávají pouze tehdy,
 *                    pokud druhý jazyk není definován (nebo je prázdný i předek).
 *                  - Zákaz bezejmenných záznamů na page a phrase (mapování na global_phrase).
 * 2026-10-19 14:45 - Doplněno chybějící načtení require_once pro excel_reader.php
 *                    a xlsx_abstract.php (zprovoznění autoloaderu pro xlsx_meta_object,
 *                    režimu Distribuce 'D' i Kontrolního běhu '1' a Importu '2').
 *                  - Zapnut režim plné šířky okna ($this->full_width = true) při
 *                    zobrazení výsledků a doplněno přehledné CSS stylování tabulek
 *                    po vzoru původního systému (mřížka, žluté nepovinné sloupce
 *                    a tabulky, střídání řádků, nl2br).
 *                  - Všechna čtení result-setů převedena na sqlarray_simple().
 *                  - Při volání p_export_to_sql doplněno SET NOCOUNT ON pro zamezení
 *                    prázdných result-setů v ovladači sqlsrv.
 * 2026-10-18 17:30 - Rozšířen zpětný export meta_object.xlsx o záložky class
 *                    (meta_class) a column (meta_column) s mnemotechnickými
 *                    identifikátory a zobrazením zděděných hodnot <do stříšek>.
 * 2026-10-18 12:35 - Doplněn zpětný export metadat do Excelu (meta_object.xlsx)
 *                    pomocí PhpOffice\PhpSpreadsheet s volbou základního jazyka
 *                    (language) a druhého jazyka (second_language) z tabulky language.
 *                  - Striktní aplikace Anti-LaTeX pravidel (OR/AND místo ||/&&,
 *                    komentáře s českou diakritikou na všech řádcích se znakem $).
 * 2026-10-16 08:25 - Doplněno volání parent::__construct() a odstraněna duplicitní
 *                    kontrola active_role (řeší centrálně abstract_page přes meta_object).
 *                  - Zapojena komponenta abstract_button a lokalizace všech textů
 *                    přes $this->phrase().
 * 2026-10-12 - Doplněna kontrola oprávnění v konstruktoru (přístup pouze pro S a D).
 *            - Kompletní refaktoring do objektové podoby (Single Responsibility).
 *            - Výpis dat a formulářů využívá nativní CSS třídy systému (md-table).
 *            - Odstraněna závislost na zastaralých HTML helper funkcích.
 *            - Korektní řízení hlaviček pro režim "Distribuce" (stahování SQL).
 * 2026-10-14 - Odstraněn volitelný checkbox use_prefix, prefix 'XLSX_' je nyní pevný.
 *            - Doplněna přípona '$' přes chr(36) při volání p_export_to_sql.
 *            - Odstraněn zápis do neexistující tabulky service_logbook v distribuci.
 * =============================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/excel_reader.php';
require_once __DIR__ . '/xlsx_abstract.php';

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use PhpOffice\PhpSpreadsheet\Style\Fill;

class page_excel_reader extends abstract_page {

	protected ?excel_reader $reader = null;             // Instance čteče XLSX souborů
	protected string $import_mode = '0';                // Zvolený režim zpracování ('0', '1', '2', 'D')
	protected string $table_prefix = 'XLSX_';           // Pevná předpona zakládaných staging tabulek
	protected bool $has_file = false;                   // Příznak úspěšného nahrání souboru z formuláře

	public function __construct() {
		parent::__construct();                          // Inicializace správce frází a kontroly přístupu v předkovi
		
		$this->page_title = $this->phrase('page_title', [], 'Import a export dat z Excelu - BCM Osiris'); // Nastavení lokalizovaného titulku stránky
	}

	/**
	 * Zpracuje požadavek na export XLSX nebo nahraný soubor před generováním HTML hlaviček.
	 * Je to klíčové pro streamování XLSX souboru i pro režim Distribuce (D).
	 */
	public function render(): void {
		$this->init_phrases();                          // Pojistka inicializace správce frází
		$this->check_system_role_access();              // Pojistka kontroly přístupu podle meta_object

		if ($this->access_denied) {                     // Kontrola zamítnutí přístupu před zpracováním
			parent::render();                           // Vykreslení chybové obrazovky z předka
			return;                                     // Ukončení zpracování při odepřeném přístupu
		}

		// 1. Zpracování požadavku na zpětný export metadat do Excelu (.xlsx)
		if (isset($_POST['btn_export_excel']) OR getinput('action') === 'export_xlsx') { // Detekce akce exportu do XLSX
			$this->process_xlsx_export();               // Vygenerování a odeslání XLSX souboru do prohlížeče
			return;                                     // Ukončení běhu po odeslání souboru
		}

		// 2. Zpracování nahraného XLSX souboru pro import
		$tmpfile = regfile("file_xlsx");                // Získání cesty k dočasnému uploadovanému souboru

		if ($tmpfile) {                                 // Pokud byl soubor úspěšně odeslán
			$this->has_file = true;                     // Označení přítomnosti souboru pro vykreslení výsledků
			$this->full_width = true;                   // Roztažení panelu na celou šířku okna pro přehledné tabulky
			$this->import_mode = (string)getinput('import_mode'); // Načtení zvoleného režimu zpracování

			$this->reader = new excel_reader($tmpfile); // Vytvoření instance čteče pro nahraný soubor

			$orig_name = (string)($_FILES['file_xlsx']['name'] ?? basename((string)$tmpfile)); // Původní název souboru
			$msg_proc = $this->phrase('msg_processing_data', [], 'Zpracování dat'); // Text úvodní zprávy zpracování
			$lbl_infile = $this->phrase('lbl_input_file', [], 'Vstupní soubor'); // Popisek objektu vstupního souboru
			$this->reader->rqm->add_message($msg_proc, 0)->setobject($lbl_infile, $orig_name); // Zápis hlavičky do logu
			
			// Provedení hlavní sady operací nad souborem
			$this->reader->setImportMode($this->import_mode) // Nastavení režimu importu
				->get_data()                            // Proudové načtení všech listů
				->prepare_package()                     // Validace balíčku podle CONTENT_INFO
				->save_to_tables($this->table_prefix);  // Uložení načtených listů do staging tabulek XLSX_*$

			// Pokud je režim D, vygenerujeme SQL a okamžitě ukončíme běh
			if ($this->import_mode === 'D') {           // Detekce požadavku na vygenerování distribučního skriptu
				$this->process_distribution();          // Odeslání SQL skriptu ke stažení
				return;                                 // Zabráníme vykreslení HTML obálky
			}

			// Běh samotného importního skriptu na DB (1 = Test, 2 = Ostrý zápis)
			if (in_array($this->import_mode, ['1', '2'], true)) { // Kontrola databázového režimu
				$this->reader->run_package($this->import_mode); // Spuštění obslužné procedury balíčku
			}
		}

		parent::render();                               // Standardní vykreslení stránky
	}

	/**
	 * Rozcestník vykreslování vnitřku stránky.
	 */
	protected function render_body(): void {
		if ($this->has_file) {                          // Rozhodnutí dle přítomnosti zpracovaného souboru
			$this->render_results();                    // Vykreslení zpráv a náhledu dat
		} else {
			$this->render_form();                       // Vykreslení vstupního nahrávacího a exportního formuláře
		}
	}

	/**
	 * Zobrazí formulář pro výběr souboru k importu a formulář pro zpětný export metadat do XLSX.
	 */
	protected function render_form(): void {
		$raw_page = trim((string)getinput('page'));     // Načtení parametru stránky z požadavku
		if ($raw_page === '') {                         // Pokud parametr nebyl zadán
			$raw_page = 'page_excel_reader';            // Výchozí kanonický název stránky
		}
		$page_param = htmlspecialchars($raw_page);      // Očištěný název stránky do URL formuláře

		$heading = htmlspecialchars($this->phrase('form_heading', [], 'Načtení dat z excelu pro účely distribuce a importu')); // Nadpis formuláře importu
		$intro = htmlspecialchars($this->phrase('form_intro', [], 'Vyberte zdrojový soubor XLSX a zvolte požadovaný režim zpracování.')); // Úvodní instrukce
		$lbl_file = htmlspecialchars($this->phrase('lbl_xlsx_file', [], 'Soubor XLSX:')); // Popisek pole souboru
		$lbl_mode = htmlspecialchars($this->phrase('lbl_import_mode', [], 'Režim zpracování:')); // Popisek pole režimu
		$opt_0 = htmlspecialchars($this->phrase('opt_mode_preview', [], 'Pouze zobrazit data')); // Volba náhledu dat
		$opt_1 = htmlspecialchars($this->phrase('opt_mode_rollback', [], 'Kontrolní běh (Rollback)')); // Volba testovacího běhu
		$opt_2 = htmlspecialchars($this->phrase('opt_mode_commit', [], 'Import se zápisem (Commit)')); // Volba ostrého importu
		$opt_d = htmlspecialchars($this->phrase('opt_mode_dist', [], 'Distribuce (SQL skript)')); // Volba generování distribuce

		$btn_submit = new abstract_button('btn_submit_excel', 'Načíst a zpracovat', 'page_excel_reader', '', 'btn-success'); // Tlačítko odeslání formuláře
		$btn_submit->set_type('submit');                // Nastavení typu tlačítka na submit
		$submit_html = $btn_submit->render();           // Vykreslení HTML kódu tlačítka importu

		// Příprava voleb jazyků z tabulky [language] pro exportní formulář (načteno přes sqlarray_simple)
		$lang_opts_primary = '';                        // HTML opce pro základní jazyk exportu
		$lang_opts_second = '';                         // HTML opce pro druhý překladový jazyk exportu
		$lbl_no_sec_lang = htmlspecialchars($this->phrase('opt_no_second_lang', [], '--- Bez druhého jazyka (režim jádra) ---')); // Volba bez druhého jazyka
		$lang_opts_second .= "<option value=\"\">{$lbl_no_sec_lang}</option>"; // Prázdná volba druhého jazyka

		$lang_rows = sqlarray_simple("SELECT [language], caption FROM [language] ORDER BY sort_code"); // Načtení všech jazyků do pole
		if (is_array($lang_rows)) {                     // Kontrola platného pole jazyků
			foreach ($lang_rows as $l_row) {            // Průchod jazyky v paměti
				$l_code = (string)$l_row['language'];   // Dvoupísmenný kód jazyka
				$l_cap = (string)$l_row['caption'];     // Název jazyka
				$safe_l_code = htmlspecialchars($l_code); // Ošetřený kód jazyka
				$safe_l_label = htmlspecialchars("{$l_code} - {$l_cap}"); // Ošetřený popisek v roletce
				$sel_prim = ($l_code === 'cs') ? 'selected' : ''; // Výchozí primární jazyk je cs
				$sel_sec = ($l_code === 'en') ? 'selected' : '';  // Výchozí druhý jazyk je en
				$lang_opts_primary .= "<option value=\"{$safe_l_code}\" {$sel_prim}>{$safe_l_label}</option>"; // Volba primárního jazyka
				$lang_opts_second .= "<option value=\"{$safe_l_code}\" {$sel_sec}>{$safe_l_label}</option>";   // Volba druhého jazyka
			}
		}

		$exp_heading = htmlspecialchars($this->phrase('export_heading', [], 'Zpětný export systémových metadat do Excelu (XLSX)')); // Nadpis sekce exportu
		$exp_intro = htmlspecialchars($this->phrase('export_intro', [], 'Vygeneruje aktuální soubor meta_object.xlsx přímo z databáze (záložky page, menu, phrase, class, column; zděděné hodnoty jsou uzavřeny <do stříšek>).')); // Popis exportu
		$lbl_pkg = htmlspecialchars($this->phrase('lbl_export_package', [], 'Balíček metadat:')); // Popisek balíčku
		$opt_pkg_mo = htmlspecialchars($this->phrase('opt_pkg_meta_object', [], 'meta_object (Stránky, menu, fráze, logické třídy a sloupce)')); // Název balíčku meta_object
		$lbl_prim_lang = htmlspecialchars($this->phrase('lbl_primary_language', [], 'Základní jazyk (language):')); // Popisek základního jazyka
		$lbl_sec_lang = htmlspecialchars($this->phrase('lbl_second_language', [], 'Druhý jazyk (*_l):')); // Popisek druhého jazyka
		$lbl_origin = htmlspecialchars($this->phrase('lbl_import_origin', [], 'Označení původu (import_origin):')); // Popisek původu dat

		$btn_export = new abstract_button('btn_export_excel', 'Stáhnout meta_object.xlsx', 'page_excel_reader'); // Tlačítko pro export XLSX
		$btn_export->set_type('submit')->set_name_value('btn_export_excel', '1'); // Nastavení atributů tlačítka exportu
		$export_html = $btn_export->render();           // Vykreslení tlačítka exportu

		echo <<<HTML
		<style>
			.xlsx-form-table { border-collapse: collapse; margin-bottom: 20px; }
			.xlsx-form-table td { border: 1px solid #cbd5e1; padding: 8px 12px; font-size: 13px; }
		</style>
		<h1 class="page-heading">{$heading}</h1>
		<p style="margin-bottom: 20px;">{$intro}</p>

		<form id="f" name="f" action="index.php?page={$page_param}" method="post" enctype="multipart/form-data" target="_blank" style="margin-bottom: 35px;">
			<table class="xlsx-form-table">
				<tr>
					<td style="font-weight: bold; width: 220px; background-color: #f8fafc;">{$lbl_file}</td>
					<td><input type="file" name="file_xlsx" id="file_xlsx" accept=".xlsx" style="height:30px; width: 320px;" required></td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_mode}</td>
					<td>
						<select name="import_mode" id="import_mode" style="width: 320px; padding: 4px;">
							<option value="0">{$opt_0}</option>
							<option value="1">{$opt_1}</option>
							<option value="2">{$opt_2}</option>
							<option value="D">{$opt_d}</option>
						</select>
					</td>
				</tr>
			</table>
			{$submit_html}
		</form>

		<hr style="border: 0; border-top: 2px solid #eee; margin: 30px 0;">

		<h2 style="color: #004488; margin-top: 0;">{$exp_heading}</h2>
		<p style="margin-bottom: 20px;">{$exp_intro}</p>

		<form id="f_export" name="f_export" action="index.php?page={$page_param}" method="post">
			<input type="hidden" name="action" value="export_xlsx">
			<table class="xlsx-form-table">
				<tr>
					<td style="font-weight: bold; width: 220px; background-color: #f8fafc;">{$lbl_pkg}</td>
					<td>
						<select name="export_package" style="width: 320px; padding: 4px;">
							<option value="meta_object">{$opt_pkg_mo}</option>
						</select>
					</td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_prim_lang}</td>
					<td>
						<select name="export_language" style="width: 320px; padding: 4px;">
							{$lang_opts_primary}
						</select>
					</td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_sec_lang}</td>
					<td>
						<select name="export_second_language" style="width: 320px; padding: 4px;">
							{$lang_opts_second}
						</select>
					</td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_origin}</td>
					<td>
						<input type="text" name="export_origin" value="BCM Osiris Core Team" style="width: 320px; padding: 4px; box-sizing: border-box;">
					</td>
				</tr>
			</table>
			{$export_html}
		</form>
HTML;
	}

	/**
	 * Pomocná metoda pro formátování potenciálně zděděné hodnoty v Excelu.
	 * Pokud je vlastní hodnota NULL (nebo prázdný řetězec při $treat_empty_as_null)
	 * a předek má neprázdnou hodnotu, uzavře zděděnou hodnotu <do stříšek>.
	 */
	private function format_inherited_val(mixed $own_val, mixed $anc_val, bool $treat_empty_as_null = false): string { // Formátování zděděné hodnoty
		$is_null = ($own_val === null OR ($treat_empty_as_null AND (string)$own_val === '')); // Zda se uplatní dědičnost
		if (!$is_null) {                                // Pokud má záznam vlastní explicitní hodnotu
			return (string)$own_val;                    // Vrátíme vlastní hodnotu bez stříšek
		}
		if ($anc_val !== null AND (string)$anc_val !== '') { // Pokud předek obsahuje neprázdnou hodnotu
			return '<' . (string)$anc_val . '>';        // Zděděnou hodnotu uzavřeme <do stříšek>
		}
		return '';                                      // Předek ani potomek hodnotu nemají
	}

	/**
	 * Pomocná metoda pro formátování překladových sloupců s příponou _l.
	 * Pokud není druhý jazyk ($sec_lang) definován, vrátí vždy prázdný řetězec ''.
	 * Pokud je druhý jazyk definován a vlastní překlad v druhém jazyce chybí,
	 * vrátí zděděnou hodnotu uzavřenou <do stříšek>.
	 */
	private function format_sec_lang_val(string $sec_lang, mixed $own_val_l, mixed $inherited_val): string { // Formátování sloupce *_l
		if ($sec_lang === '') {                         // Pokud druhý jazyk v CONTENT_INFO není definován
			return '';                                  // Položky *_l zůstávají prázdné pouze bez druhého jazyka
		}
		return $this->format_inherited_val($own_val_l, $inherited_val, true); // Jinak vlastní překlad nebo <zděděná hodnota>
	}

	/**
	 * Vygeneruje a odešle XLSX soubor s aktuálními systémovými metadaty
	 * (meta_object, meta_menu, meta_phrase, meta_class, meta_column).
	 */
	protected function process_xlsx_export(): void {
		$lang = trim((string)getinput('export_language')); // Zvolený primární jazyk exportu
		if ($lang === '') {                             // Fallback pokud primární jazyk nebyl zadán
			$lang = 'cs';                               // Výchozí primární jazyk čeština
		}
		$sec_lang = trim((string)getinput('export_second_language')); // Zvolený druhý jazyk exportu
		if ($sec_lang === $lang) {                      // Ochrana proti shodě primárního a druhého jazyka
			$sec_lang = '';                             // Vypnutí druhého jazyka při shodě
		}
		$origin = trim((string)getinput('export_origin')); // Označení původu exportovaných dat
		if ($origin === '') {                           // Výchozí původ při prázdném poli
			$origin = 'BCM Osiris Export';              // Výchozí text původu
		}

		$safe_lang = charliteral($lang, 2);             // Bezpečný SQL literál primárního jazyka
		$safe_sec_lang = charliteral($sec_lang, 2);     // Bezpečný SQL literál druhého jazyka

		$spreadsheet = new Spreadsheet();               // Vytvoření nové instance sešitu PhpSpreadsheet

		// =====================================================================
		// 1. Záložka CONTENT_INFO
		// =====================================================================
		$sheetInfo = $spreadsheet->getActiveSheet();    // Získání prvního aktivního listu
		$sheetInfo->setTitle('CONTENT_INFO');           // Pojmenování řídicí záložky

		$infoHeaders = [                                // Definice sloupců záložky CONTENT_INFO
			'A1' => 'package_code',                     // Kód balíčku
			'B1' => 'language',                         // Základní jazyk
			'C1' => 'second_language',                  // Druhý jazyk pro sloupce *_l
			'D1' => 'version_date',                     // Datum verze exportu
			'E1' => 'import_origin',                    // Původ dat
			'F1' => 'description'                       // Popis balíčku
		];                                              // Konec definice hlaviček CONTENT_INFO
		foreach ($infoHeaders as $cell => $val) {       // Zápis záhlaví CONTENT_INFO
			$sheetInfo->setCellValue($cell, $val);      // Nastavení buňky záhlaví
		}

		$sheetInfo->setCellValue('A2', 'meta_object');  // Kód balíčku meta_object
		$sheetInfo->setCellValue('B2', $lang);          // Zvolený základní jazyk
		$sheetInfo->setCellValue('C2', $sec_lang);      // Zvolený druhý jazyk
		$sheetInfo->setCellValue('D2', date('Y-m-d'));  // Aktuální datum exportu
		$sheetInfo->setCellValue('E2', $origin);        // Zadaný původ dat
		$sheetInfo->setCellValue('F2', 'Export systémových stránek, menu, frází, logických tříd a sloupců z BCM Osiris'); // Popis

		$sheetInfo->getStyle('A1:F1')->getFont()->setBold(true); // Tučné písmo hlavičky CONTENT_INFO
		$sheetInfo->getStyle('A1:F1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Šedé podbarvení
		foreach (range('A', 'F') as $colId) {           // Automatická šířka sloupců CONTENT_INFO
			$sheetInfo->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 2. Záložka page (meta_object, object_type = 'P')
		// =====================================================================
		$sheetPage = $spreadsheet->createSheet();       // Založení listu pro stránky a UI třídy
		$sheetPage->setTitle('page');                   // Název záložky page

		$pageHeaders = [                                // Definice sloupců záložky page (12 sloupců: A až L)
			'A1' => 'builtin_code',                     // Technický kód stránky / třídy
			'B1' => 'system_role',                      // Minimální systémová role
			'C1' => 'module',                           // Modul
			'D1' => 'inactive',                         // Příznak neaktivního objektu
			'E1' => 'removed',                          // Příznak odstraněného objektu
			'F1' => 'editor_note',                      // Poznámka pro překladatele / AI
			'G1' => 'caption',                          // Název v primárním jazyce
			'H1' => 'description',                      // Popis v primárním jazyce
			'I1' => 'helptext',                         // Nápověda v primárním jazyce
			'J1' => 'caption_l',                        // Název ve druhém jazyce
			'K1' => 'description_l',                    // Popis ve druhém jazyce
			'L1' => 'helptext_l'                        // Nápověda ve druhém jazyce
		];                                              // Konec hlaviček záložky page
		foreach ($pageHeaders as $cell => $val) {       // Zápis záhlaví záložky page
			$sheetPage->setCellValue($cell, $val);      // Nastavení buňky záhlaví
		}

		$sheetPage->getStyle('A1:E1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Technické sloupce
		$sheetPage->getStyle('F1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');    // AI kontext
		$sheetPage->getStyle('G1:I1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Primární jazyk
		$sheetPage->getStyle('J1:L1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk
		$sheetPage->getStyle('A1:L1')->getFont()->setBold(true); // Tučné záhlaví záložky page
		$sheetPage->freezePane('A2');                   // Ukotvení prvního řádku záhlaví

		$pages_rows = sqlarray_simple("
			SELECT
				a.builtin_code,
				a.system_role,
				a.module,
				a.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE a.removed END AS removed,
				ISNULL(a.editor_note, '') AS editor_note,
				COALESCE(NULLIF(l1.caption, ''), a.caption, '') AS caption,
				COALESCE(NULLIF(l1.description, ''), a.description, '') AS description,
				COALESCE(NULLIF(l1.helptext, ''), a.helptext, '') AS helptext,
				l2.caption AS own_caption_l,
				l2.description AS own_description_l,
				l2.helptext AS own_helptext_l
			FROM meta_object a
			LEFT JOIN meta_object l1
				ON l1.original = a.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_object l2
				ON l2.original = a.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			WHERE a.object_owner = 0x00
			  AND a.object_type = 'P'
			  AND a.builtin_code <> ''
			  AND a.record_type = 'A'
			ORDER BY CASE WHEN a.builtin_code = 'global_phrase' THEN 0 WHEN a.builtin_code LIKE 'page_%' THEN 2 ELSE 1 END, a.builtin_code
		");                                             // Načtení registrovaných stránek a UI tříd (bez bezejmenného '')

		$row_idx = 2;                                   // Počáteční řádek dat na záložce page
		if (is_array($pages_rows)) {                    // Kontrola platného pole stránek
			foreach ($pages_rows as $r) {               // Průchod načtenými stránkami
				$page_vals = [                          // Pole hodnot aktuálního řádku stránky
					(string)$r['builtin_code'],         // Kód stránky / třídy
					(string)$r['system_role'],          // Role stránky
					(string)$r['module'],               // Modul stránky
					(int)$r['inactive'],                // Příznak deaktivace
					(int)$r['removed'],                 // Příznak odstranění
					(string)$r['editor_note'],          // Kontext pro AI
					(string)$r['caption'],              // Název v primárním jazyce
					(string)$r['description'],          // Popis v primárním jazyce
					(string)$r['helptext'],             // Nápověda v primárním jazyce
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['caption']),         // Název ve 2. jazyce (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_description_l'], $r['description']), // Popis ve 2. jazyce (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['helptext'])        // Nápověda ve 2. jazyce (nebo <zděděná>)
				];                                      // Konec pole hodnot stránky
				$sheetPage->fromArray($page_vals, null, 'A' . $row_idx); // Zápis celého řádku do listu page
				$row_idx++;                             // Posun na další řádek
			}
		}

		foreach (range('A', 'L') as $colId) {           // Automatická šířka sloupců na záložce page
			$sheetPage->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 3. Záložka menu (tabulka meta_menu)
		// =====================================================================
		$sheetMenu = $spreadsheet->createSheet();       // Založení listu pro navigaci
		$sheetMenu->setTitle('menu');                   // Název záložky menu

		$menuHeaders = [                                // Definice sloupců záložky menu (19 sloupců: A až S)
			'A1' => 'builtin_code',                     // Kód položky menu
			'B1' => 'parent_code',                      // Kód nadřízené položky menu
			'C1' => 'sort_code',                        // Pořadí řazení
			'D1' => 'target_page',                      // Kód cílové stránky (meta_object)
			'E1' => 'url_parameters',                   // Dodatečné URL parametry
			'F1' => 'target_url',                       // Externí URL
			'G1' => 'target_window',                    // Cílové okno
			'H1' => 'system_role',                      // Minimální role
			'I1' => 'permanent',                        // Příznak trvalého zobrazení
			'J1' => 'removed',                          // Příznak odstranění položky
			'K1' => 'svg_icon',                         // Vektorová ikona
			'L1' => 'css_class',                        // CSS třída
			'M1' => 'editor_note',                      // Poznámka pro překladatele / AI
			'N1' => 'caption',                          // Popisek v primárním jazyce
			'O1' => 'description',                      // Popis v primárním jazyce
			'P1' => 'helptext',                         // Tooltip v primárním jazyce
			'Q1' => 'caption_l',                        // Popisek ve druhém jazyce
			'R1' => 'description_l',                    // Popis ve druhém jazyce
			'S1' => 'helptext_l'                        // Tooltip ve druhém jazyce
		];                                              // Konec hlaviček záložky menu
		foreach ($menuHeaders as $cell => $val) {       // Zápis záhlaví záložky menu
			$sheetMenu->setCellValue($cell, $val);      // Nastavení buňky záhlaví
		}

		$sheetMenu->getStyle('A1:L1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Technické sloupce
		$sheetMenu->getStyle('M1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');    // AI kontext
		$sheetMenu->getStyle('N1:P1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Primární jazyk
		$sheetMenu->getStyle('Q1:S1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk
		$sheetMenu->getStyle('A1:S1')->getFont()->setBold(true); // Tučné záhlaví záložky menu
		$sheetMenu->freezePane('A2');                   // Ukotvení prvního řádku záhlaví

		$menu_rows = sqlarray_simple("
			SELECT
				m.builtin_code,
				ISNULL(pm.builtin_code, '') AS parent_code,
				m.sort_code,
				ISNULL(mo.builtin_code, '') AS target_page,
				m.url_parameters,
				m.target_url,
				m.target_window,
				m.system_role,
				m.permanent,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE m.removed END AS removed,
				m.svg_icon,
				m.css_class,
				ISNULL(m.editor_note, '') AS editor_note,
				COALESCE(NULLIF(l1.caption, ''), m.caption, '') AS caption,
				COALESCE(NULLIF(l1.description, ''), m.description, '') AS description,
				COALESCE(NULLIF(l1.helptext, ''), m.helptext, '') AS helptext,
				l2.caption AS own_caption_l,
				l2.description AS own_description_l,
				l2.helptext AS own_helptext_l
			FROM meta_menu m
			LEFT JOIN meta_menu pm
				ON pm.original = m.parent_uuid AND pm.object_owner = 0x00 AND pm.record_type = 'A'
			LEFT JOIN meta_object mo
				ON mo.original = m.target_object AND mo.object_owner = 0x00 AND mo.record_type = 'A'
			LEFT JOIN meta_menu l1
				ON l1.original = m.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_menu l2
				ON l2.original = m.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			WHERE m.object_owner = 0x00
			  AND m.record_type = 'A'
			ORDER BY CASE WHEN m.parent_uuid IS NULL THEN 0 ELSE 1 END, m.sort_code, m.builtin_code
		");                                             // Načtení položek systémového menu do pole

		$row_idx = 2;                                   // Počáteční řádek dat na záložce menu
		if (is_array($menu_rows)) {                     // Kontrola platného pole menu
			foreach ($menu_rows as $r) {                // Průchod načtenými položkami menu
				$menu_vals = [                          // Pole hodnot řádku menu
					(string)$r['builtin_code'],         // Kód položky menu
					(string)$r['parent_code'],          // Kód nadřízené položky
					(string)$r['sort_code'],            // Pořadí
					(string)$r['target_page'],          // Kód cílové stránky
					(string)$r['url_parameters'],       // URL parametry
					(string)$r['target_url'],           // Externí URL
					(string)$r['target_window'],        // Cílové okno
					(string)$r['system_role'],          // Minimální role
					(int)$r['permanent'],               // Příznak trvalého zobrazení
					(int)$r['removed'],                 // Příznak odstranění
					(string)$r['svg_icon'],             // SVG ikona
					(string)$r['css_class'],            // CSS třída
					(string)$r['editor_note'],          // Poznámka pro AI
					(string)$r['caption'],              // Popisek v primárním jazyce
					(string)$r['description'],          // Popis v primárním jazyce
					(string)$r['helptext'],             // Tooltip v primárním jazyce
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['caption']),         // Popisek ve 2. jazyce (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_description_l'], $r['description']), // Popis ve 2. jazyce (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['helptext'])        // Tooltip ve 2. jazyce (nebo <zděděný>)
				];                                      // Konec pole hodnot menu
				$sheetMenu->fromArray($menu_vals, null, 'A' . $row_idx); // Zápis celého řádku do listu menu
				$row_idx++;                             // Posun na další řádek
			}
		}

		foreach (range('A', 'S') as $colId) {           // Nastavení šířek sloupců na záložce menu
			if ($colId === 'K') {                       // Sloupec se zdrojovým kódem SVG ikony
				$sheetMenu->getColumnDimension($colId)->setWidth(25); // Omezení šířky sloupce SVG
			} else {
				$sheetMenu->getColumnDimension($colId)->setAutoSize(true); // Automatická šířka sloupce
			}
		}

		// =====================================================================
		// 4. Záložka phrase (tabulka meta_phrase)
		// =====================================================================
		$sheetPhrase = $spreadsheet->createSheet();     // Založení listu pro textové fráze
		$sheetPhrase->setTitle('phrase');               // Název záložky phrase

		$phraseHeaders = [                              // Definice sloupců záložky phrase (12 sloupců: A až L)
			'A1' => 'source_code',                      // Zdrojová PHP třída / stránka (pro globální 'global_phrase')
			'B1' => 'builtin_code',                     // Kód fráze
			'C1' => 'module',                           // Modul
			'D1' => 'svg_icon',                         // Vektorová ikona tlačítka
			'E1' => 'css_class',                        // CSS třída tlačítka
			'F1' => 'inactive',                         // Příznak deaktivace fráze
			'G1' => 'removed',                          // Příznak odstranění fráze
			'H1' => 'editor_note',                      // Poznámka pro překladatele / AI
			'I1' => 'caption',                          // Text fráze v primárním jazyce
			'J1' => 'helptext',                         // Tooltip v primárním jazyce
			'K1' => 'caption_l',                        // Text fráze ve druhém jazyce
			'L1' => 'helptext_l'                        // Tooltip ve druhém jazyce
		];                                              // Konec hlaviček záložky phrase
		foreach ($phraseHeaders as $cell => $val) {     // Zápis záhlaví záložky phrase
			$sheetPhrase->setCellValue($cell, $val);    // Nastavení buňky záhlaví
		}

		$sheetPhrase->getStyle('A1:G1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Technické sloupce
		$sheetPhrase->getStyle('H1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');    // AI kontext
		$sheetPhrase->getStyle('I1:J1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Primární jazyk
		$sheetPhrase->getStyle('K1:L1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk
		$sheetPhrase->getStyle('A1:L1')->getFont()->setBold(true); // Tučné záhlaví záložky phrase
		$sheetPhrase->freezePane('A2');                 // Ukotvení prvního řádku záhlaví

		$phrase_rows = sqlarray_simple("
			SELECT
				CASE WHEN ISNULL(LTRIM(RTRIM(a.source_code)), '') = '' THEN 'global_phrase' ELSE a.source_code END AS source_code,
				a.builtin_code,
				a.module,
				a.svg_icon,
				a.css_class,
				a.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE a.removed END AS removed,
				ISNULL(a.editor_note, '') AS editor_note,
				COALESCE(NULLIF(CAST(l1.caption AS NVARCHAR(MAX)), ''), CAST(a.caption AS NVARCHAR(MAX)), '') AS caption,
				COALESCE(NULLIF(CAST(l1.helptext AS NVARCHAR(MAX)), ''), CAST(a.helptext AS NVARCHAR(MAX)), '') AS helptext,
				CAST(l2.caption AS NVARCHAR(MAX)) AS own_caption_l,
				CAST(l2.helptext AS NVARCHAR(MAX)) AS own_helptext_l
			FROM meta_phrase a
			LEFT JOIN meta_phrase l1
				ON l1.original = a.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_phrase l2
				ON l2.original = a.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			WHERE a.object_owner = 0x00
			  AND a.record_type = 'A'
			ORDER BY CASE WHEN ISNULL(LTRIM(RTRIM(a.source_code)), '') IN ('', 'global_phrase') THEN 0 ELSE 1 END, a.source_code, a.builtin_code
		");                                             // Načtení všech systémových frází do pole

		$row_idx = 2;                                   // Počáteční řádek dat na záložce phrase
		if (is_array($phrase_rows)) {                   // Kontrola platného pole frází
			foreach ($phrase_rows as $r) {              // Průchod načtenými frázemi
				$phrase_vals = [                        // Pole hodnot řádku fráze
					(string)$r['source_code'],          // Zdrojová třída fráze (nikdy prázdná)
					(string)$r['builtin_code'],         // Kód fráze
					(string)$r['module'],               // Modul
					(string)$r['svg_icon'],             // SVG ikona
					(string)$r['css_class'],            // CSS třída
					(int)$r['inactive'],                // Příznak deaktivace
					(int)$r['removed'],                 // Příznak odstranění
					(string)$r['editor_note'],          // Kontext pro AI
					(string)$r['caption'],              // Text v primárním jazyce
					(string)$r['helptext'],             // Tooltip v primárním jazyce
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['caption']),   // Text ve 2. jazyce (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['helptext'])  // Tooltip ve 2. jazyce (nebo <zděděný>)
				];                                      // Konec pole hodnot fráze
				$sheetPhrase->fromArray($phrase_vals, null, 'A' . $row_idx); // Zápis celého řádku do listu phrase
				$row_idx++;                             // Posun na další řádek
			}
		}

		foreach (range('A', 'L') as $colId) {           // Nastavení šířek sloupců na záložce phrase
			if ($colId === 'D') {                       // Sloupec s SVG ikonou
				$sheetPhrase->getColumnDimension($colId)->setWidth(25); // Omezení šířky sloupce SVG
			} else {
				$sheetPhrase->getColumnDimension($colId)->setAutoSize(true); // Automatická šířka sloupce
			}
		}

		// =====================================================================
		// 5. Záložka class (tabulka meta_class) s dědičností <do stříšek>
		// =====================================================================
		$sheetClass = $spreadsheet->createSheet();      // Založení listu pro logické třídy
		$sheetClass->setTitle('class');                 // Název záložky class

		$classHeaders = [                               // Definice sloupců záložky class (19 sloupců: A až S)
			'class_name', 'storage_type', 'storage_code', 'ancestor_code',
			'sort_code', 'iconname', 'is_final', 'is_protected', 'inactive', 'removed',
			'editor_note',
			'caption', 'caption_plural', 'description', 'helptext',
			'caption_l', 'caption_plural_l', 'description_l', 'helptext_l'
		];                                              // Konec hlaviček záložky class
		$sheetClass->fromArray($classHeaders, null, 'A1'); // Zápis záhlaví záložky class

		$sheetClass->getStyle('A1:J1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Technické sloupce
		$sheetClass->getStyle('K1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');    // AI kontext
		$sheetClass->getStyle('L1:O1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Primární jazyk
		$sheetClass->getStyle('P1:S1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk
		$sheetClass->getStyle('A1:S1')->getFont()->setBold(true); // Tučné záhlaví záložky class
		$sheetClass->freezePane('A2');                  // Ukotvení prvního řádku záhlaví

		$class_rows = sqlarray_simple("
			SELECT
				c.class_name,
				ISNULL(mo.object_type, 'T') AS storage_type,
				ISNULL(mo.builtin_code, c.class_name) AS storage_code,
				ISNULL(anc.class_name, '') AS ancestor_code,
				c.sort_code,
				c.iconname AS own_iconname,
				anc.iconname AS anc_iconname,
				c.is_final,
				c.is_protected,
				c.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE c.removed END AS removed,
				ISNULL(c.editor_note, '') AS editor_note,
				COALESCE(NULLIF(l1.caption, ''), c.caption) AS own_caption,
				COALESCE(NULLIF(anc_l1.caption, ''), anc.caption) AS anc_caption,
				COALESCE(NULLIF(l1.caption_plural, ''), c.caption_plural) AS own_caption_plural,
				COALESCE(NULLIF(anc_l1.caption_plural, ''), anc.caption_plural) AS anc_caption_plural,
				COALESCE(NULLIF(l1.description, ''), c.description) AS own_description,
				COALESCE(NULLIF(anc_l1.description, ''), anc.description) AS anc_description,
				COALESCE(NULLIF(l1.helptext, ''), c.helptext) AS own_helptext,
				COALESCE(NULLIF(anc_l1.helptext, ''), anc.helptext) AS anc_helptext,
				l2.caption AS own_caption_l,
				COALESCE(NULLIF(anc_l2.caption, ''), NULLIF(l1.caption, ''), NULLIF(c.caption, ''), NULLIF(anc_l1.caption, ''), anc.caption) AS inh_caption_l,
				l2.caption_plural AS own_caption_plural_l,
				COALESCE(NULLIF(anc_l2.caption_plural, ''), NULLIF(l1.caption_plural, ''), NULLIF(c.caption_plural, ''), NULLIF(anc_l1.caption_plural, ''), anc.caption_plural) AS inh_caption_plural_l,
				l2.description AS own_description_l,
				COALESCE(NULLIF(anc_l2.description, ''), NULLIF(l1.description, ''), NULLIF(c.description, ''), NULLIF(anc_l1.description, ''), anc.description) AS inh_description_l,
				l2.helptext AS own_helptext_l,
				COALESCE(NULLIF(anc_l2.helptext, ''), NULLIF(l1.helptext, ''), NULLIF(c.helptext, ''), NULLIF(anc_l1.helptext, ''), anc.helptext) AS inh_helptext_l
			FROM meta_class c
			LEFT JOIN meta_object mo
				ON mo.original = c.storage_object AND mo.object_owner = 0x00 AND mo.record_type = 'A'
			LEFT JOIN meta_class anc
				ON anc.original = c.ancestor_class AND anc.object_owner = 0x00 AND anc.record_type = 'A' AND anc.removed = 0
			LEFT JOIN meta_class l1
				ON l1.original = c.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_class anc_l1
				ON anc_l1.original = anc.original AND anc_l1.object_owner = 0x00 AND anc_l1.record_type = 'L' AND anc_l1.[language] = {$safe_lang} AND anc_l1.removed = 0
			LEFT JOIN meta_class l2
				ON l2.original = c.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			LEFT JOIN meta_class anc_l2
				ON anc_l2.original = anc.original AND anc_l2.object_owner = 0x00 AND anc_l2.record_type = 'L' AND anc_l2.[language] = {$safe_sec_lang} AND anc_l2.removed = 0 AND {$safe_sec_lang} <> ''
			WHERE c.object_owner = 0x00
			  AND c.record_type = 'A'
			ORDER BY CASE WHEN c.class_name = 'sys_global_columns' THEN 0 ELSE 1 END, c.class_name
		");                                             // Načtení logických tříd včetně předků a zděděných hodnot 2. jazyka

		$row_idx = 2;                                   // Počáteční řádek dat na záložce class
		if (is_array($class_rows)) {                    // Kontrola platného pole tříd
			foreach ($class_rows as $r) {               // Průchod načtenými třídami
				$class_vals = [                         // Pole hodnot řádku třídy
					(string)$r['class_name'],           // Název logické třídy
					(string)$r['storage_type'],         // Typ fyzického objektu (T, V, F, C)
					(string)$r['storage_code'],         // Kód fyzické tabulky
					(string)$r['ancestor_code'],        // Kód nadřízené třídy
					(string)$r['sort_code'],            // Pořadí
					$this->format_inherited_val($r['own_iconname'], $r['anc_iconname'], true), // Ikona (příp. <zděděná>)
					(int)$r['is_final'],                // Příznak is_final
					(int)$r['is_protected'],            // Příznak is_protected
					(int)$r['inactive'],                // Příznak inactive
					(int)$r['removed'],                 // Příznak removed
					(string)$r['editor_note'],          // Kontext pro AI
					$this->format_inherited_val($r['own_caption'], $r['anc_caption'], true),               // Název třídy
					$this->format_inherited_val($r['own_caption_plural'], $r['anc_caption_plural'], true), // Množné číslo
					$this->format_inherited_val($r['own_description'], $r['anc_description'], true),       // Popis třídy
					$this->format_inherited_val($r['own_helptext'], $r['anc_helptext'], true),             // Nápověda třídy
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['inh_caption_l']),               // Překlad názvu (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_caption_plural_l'], $r['inh_caption_plural_l']), // Překlad mn. č. (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_description_l'], $r['inh_description_l']),       // Překlad popisu (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['inh_helptext_l'])              // Překlad nápovědy (nebo <zděděný>)
				];                                      // Konec pole hodnot třídy
				$sheetClass->fromArray($class_vals, null, 'A' . $row_idx); // Zápis řádku do listu class
				$row_idx++;                             // Posun na další řádek
			}
		}

		foreach (range('A', 'S') as $colId) {           // Automatická šířka sloupců na záložce class
			$sheetClass->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 6. Záložka column (tabulka meta_column) s dědičností <do stříšek>
		// =====================================================================
		$sheetCol = $spreadsheet->createSheet();        // Založení listu pro sloupce metadat
		$sheetCol->setTitle('column');                  // Název záložky column

		$colHeaders = [                                 // Definice sloupců záložky column (41 sloupců: A až AO)
			'class_name', 'column_name', 'parent_order', 'sort_code', 'list_order',
			'input_type', 'input_width', 'input_rows', 'max_length', 'css_class',
			'translate', 'history', 'is_html', 'is_mandatory', 'is_url', 'is_computed',
			'show_empty', 'hidden', 'customizable',
			'ancestor_column', 'referenced_codetable', 'referenced_class_code',
			'is_final', 'is_protected', 'inactive', 'removed',
			'editor_note',
			'caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder',
			'caption_l', 'caption_plural_l', 'description_l', 'label_l', 'header_l', 'helptext_l', 'placeholder_l'
		];                                              // Konec hlaviček záložky column
		$sheetCol->fromArray($colHeaders, null, 'A1');  // Zápis záhlaví záložky column

		$sheetCol->getStyle('A1:Z1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0');   // Technické sloupce
		$sheetCol->getStyle('AA1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');     // AI kontext
		$sheetCol->getStyle('AB1:AH1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Primární jazyk
		$sheetCol->getStyle('AI1:AO1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk
		$sheetCol->getStyle('A1:AO1')->getFont()->setBold(true); // Tučné záhlaví záložky column
		$sheetCol->freezePane('A2');                    // Ukotvení prvního řádku záhlaví

		$col_rows = sqlarray_simple("
			SELECT
				mcl.class_name,
				c.column_name,
				c.parent_order,
				c.sort_code AS own_sort_code,
				gc.sort_code AS anc_sort_code,
				c.list_order AS own_list_order,
				gc.list_order AS anc_list_order,
				c.input_type AS own_input_type,
				gc.input_type AS anc_input_type,
				c.input_width AS own_input_width,
				gc.input_width AS anc_input_width,
				c.input_rows AS own_input_rows,
				gc.input_rows AS anc_input_rows,
				c.max_length AS own_max_length,
				gc.max_length AS anc_max_length,
				c.css_class AS own_css_class,
				gc.css_class AS anc_css_class,
				c.translate AS own_translate,
				gc.translate AS anc_translate,
				c.history AS own_history,
				gc.history AS anc_history,
				c.is_html AS own_is_html,
				gc.is_html AS anc_is_html,
				c.is_mandatory AS own_is_mandatory,
				gc.is_mandatory AS anc_is_mandatory,
				c.is_url AS own_is_url,
				gc.is_url AS anc_is_url,
				c.is_computed AS own_is_computed,
				gc.is_computed AS anc_is_computed,
				c.show_empty AS own_show_empty,
				gc.show_empty AS anc_show_empty,
				c.hidden AS own_hidden,
				gc.hidden AS anc_hidden,
				c.customizable AS own_customizable,
				gc.customizable AS anc_customizable,
				ISNULL(gc.column_name, '') AS ancestor_column,
				c.referenced_codetable AS own_ref_codetable,
				gc.referenced_codetable AS anc_ref_codetable,
				rc_own.class_name AS own_ref_class_code,
				rc_anc.class_name AS anc_ref_class_code,
				c.is_final,
				c.is_protected,
				c.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE c.removed END AS removed,
				ISNULL(c.editor_note, '') AS editor_note,
				COALESCE(NULLIF(l1.caption, ''), c.caption) AS own_caption,
				COALESCE(NULLIF(gc_l1.caption, ''), gc.caption) AS anc_caption,
				COALESCE(NULLIF(l1.caption_plural, ''), c.caption_plural) AS own_caption_plural,
				COALESCE(NULLIF(gc_l1.caption_plural, ''), gc.caption_plural) AS anc_caption_plural,
				COALESCE(NULLIF(l1.description, ''), c.description) AS own_description,
				COALESCE(NULLIF(gc_l1.description, ''), gc.description) AS anc_description,
				COALESCE(NULLIF(l1.label, ''), c.label) AS own_label,
				COALESCE(NULLIF(gc_l1.label, ''), gc.label) AS anc_label,
				COALESCE(NULLIF(l1.header, ''), c.header) AS own_header,
				COALESCE(NULLIF(gc_l1.header, ''), gc.header) AS anc_header,
				COALESCE(NULLIF(l1.helptext, ''), c.helptext) AS own_helptext,
				COALESCE(NULLIF(gc_l1.helptext, ''), gc.helptext) AS anc_helptext,
				COALESCE(NULLIF(l1.placeholder, ''), c.placeholder) AS own_placeholder,
				COALESCE(NULLIF(gc_l1.placeholder, ''), gc.placeholder) AS anc_placeholder,
				l2.caption AS own_caption_l,
				COALESCE(NULLIF(gc_l2.caption, ''), NULLIF(l1.caption, ''), NULLIF(c.caption, ''), NULLIF(gc_l1.caption, ''), gc.caption) AS inh_caption_l,
				l2.caption_plural AS own_caption_plural_l,
				COALESCE(NULLIF(gc_l2.caption_plural, ''), NULLIF(l1.caption_plural, ''), NULLIF(c.caption_plural, ''), NULLIF(gc_l1.caption_plural, ''), gc.caption_plural) AS inh_caption_plural_l,
				l2.description AS own_description_l,
				COALESCE(NULLIF(gc_l2.description, ''), NULLIF(l1.description, ''), NULLIF(c.description, ''), NULLIF(gc_l1.description, ''), gc.description) AS inh_description_l,
				l2.label AS own_label_l,
				COALESCE(NULLIF(gc_l2.label, ''), NULLIF(l1.label, ''), NULLIF(c.label, ''), NULLIF(gc_l1.label, ''), gc.label) AS inh_label_l,
				l2.header AS own_header_l,
				COALESCE(NULLIF(gc_l2.header, ''), NULLIF(l1.header, ''), NULLIF(c.header, ''), NULLIF(gc_l1.header, ''), gc.header) AS inh_header_l,
				l2.helptext AS own_helptext_l,
				COALESCE(NULLIF(gc_l2.helptext, ''), NULLIF(l1.helptext, ''), NULLIF(c.helptext, ''), NULLIF(gc_l1.helptext, ''), gc.helptext) AS inh_helptext_l,
				l2.placeholder AS own_placeholder_l,
				COALESCE(NULLIF(gc_l2.placeholder, ''), NULLIF(l1.placeholder, ''), NULLIF(c.placeholder, ''), NULLIF(gc_l1.placeholder, ''), gc.placeholder) AS inh_placeholder_l
			FROM meta_column c
			JOIN meta_class mcl
				ON mcl.original = c.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A'
			LEFT JOIN meta_column gc
				ON gc.original = c.ancestor AND gc.object_owner = 0x00 AND gc.record_type = 'A' AND gc.removed = 0
			LEFT JOIN meta_class rc_own
				ON rc_own.original = c.referenced_class AND rc_own.object_owner = 0x00 AND rc_own.record_type = 'A' AND rc_own.removed = 0
			LEFT JOIN meta_class rc_anc
				ON rc_anc.original = gc.referenced_class AND rc_anc.object_owner = 0x00 AND rc_anc.record_type = 'A' AND rc_anc.removed = 0
			LEFT JOIN meta_column l1
				ON l1.original = c.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_column gc_l1
				ON gc_l1.original = gc.original AND gc_l1.object_owner = 0x00 AND gc_l1.record_type = 'L' AND gc_l1.[language] = {$safe_lang} AND gc_l1.removed = 0
			LEFT JOIN meta_column l2
				ON l2.original = c.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			LEFT JOIN meta_column gc_l2
				ON gc_l2.original = gc.original AND gc_l2.object_owner = 0x00 AND gc_l2.record_type = 'L' AND gc_l2.[language] = {$safe_sec_lang} AND gc_l2.removed = 0 AND {$safe_sec_lang} <> ''
			WHERE c.object_owner = 0x00
			  AND c.record_type = 'A'
			ORDER BY CASE WHEN mcl.class_name = 'sys_global_columns' THEN 0 ELSE 1 END, mcl.class_name, c.parent_order, c.column_name
		");                                             // Načtení sloupců metadat včetně hodnot zděděných z globálního slovníku

		$row_idx = 2;                                   // Počáteční řádek dat na záložce column
		if (is_array($col_rows)) {                      // Kontrola platného pole sloupců
			foreach ($col_rows as $r) {                 // Průchod načtenými sloupci metadat
				$col_vals = [                           // Pole hodnot řádku sloupce
					(string)$r['class_name'],           // Logická třída sloupce
					(string)$r['column_name'],          // Název sloupce
					(int)$r['parent_order'],            // Pořadí v tabulce
					$this->format_inherited_val($r['own_sort_code'], $r['anc_sort_code'], true),             // Kód řazení
					$this->format_inherited_val($r['own_list_order'], $r['anc_list_order'], false),          // Pořadí v Master panelu
					$this->format_inherited_val($r['own_input_type'], $r['anc_input_type'], true),           // Typ inputu
					$this->format_inherited_val($r['own_input_width'], $r['anc_input_width'], true),         // Šířka inputu
					$this->format_inherited_val($r['own_input_rows'], $r['anc_input_rows'], false),          // Počet řádků textarea
					$this->format_inherited_val($r['own_max_length'], $r['anc_max_length'], false),          // Maximální délka
					$this->format_inherited_val($r['own_css_class'], $r['anc_css_class'], false),            // CSS třída
					$this->format_inherited_val($r['own_translate'], $r['anc_translate'], false),            // Příznak překladu
					$this->format_inherited_val($r['own_history'], $r['anc_history'], false),                // Příznak historie
					$this->format_inherited_val($r['own_is_html'], $r['anc_is_html'], false),                // Příznak HTML
					$this->format_inherited_val($r['own_is_mandatory'], $r['anc_is_mandatory'], false),      // Příznak povinnosti
					$this->format_inherited_val($r['own_is_url'], $r['anc_is_url'], false),                  // Příznak URL
					$this->format_inherited_val($r['own_is_computed'], $r['anc_is_computed'], false),        // Příznak computed
					$this->format_inherited_val($r['own_show_empty'], $r['anc_show_empty'], false),          // Příznak show_empty
					$this->format_inherited_val($r['own_hidden'], $r['anc_hidden'], false),                  // Příznak skrytí
					$this->format_inherited_val($r['own_customizable'], $r['anc_customizable'], false),      // Příznak customizable
					(string)$r['ancestor_column'],      // Název předka v sys_global_columns
					$this->format_inherited_val($r['own_ref_codetable'], $r['anc_ref_codetable'], true),     // Číselník
					$this->format_inherited_val($r['own_ref_class_code'], $r['anc_ref_class_code'], true),   // Odkazovaná třída
					(int)$r['is_final'],                // Příznak is_final
					(int)$r['is_protected'],            // Příznak is_protected
					(int)$r['inactive'],                // Příznak inactive
					(int)$r['removed'],                 // Příznak removed
					(string)$r['editor_note'],          // Poznámka pro AI
					$this->format_inherited_val($r['own_caption'], $r['anc_caption'], true),                 // Název
					$this->format_inherited_val($r['own_caption_plural'], $r['anc_caption_plural'], true),   // Množné číslo
					$this->format_inherited_val($r['own_description'], $r['anc_description'], true),         // Popis
					$this->format_inherited_val($r['own_label'], $r['anc_label'], true),                     // Návěstí ve formuláři
					$this->format_inherited_val($r['own_header'], $r['anc_header'], true),                   // Záhlaví v tabulce
					$this->format_inherited_val($r['own_helptext'], $r['anc_helptext'], true),               // Nápověda
					$this->format_inherited_val($r['own_placeholder'], $r['anc_placeholder'], true),         // Placeholder
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['inh_caption_l']),               // Překlad názvu (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_caption_plural_l'], $r['inh_caption_plural_l']), // Překlad mn. č. (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_description_l'], $r['inh_description_l']),       // Překlad popisu (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_label_l'], $r['inh_label_l']),                   // Překlad návěstí (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_header_l'], $r['inh_header_l']),                 // Překlad záhlaví (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['inh_helptext_l']),             // Překlad nápovědy (nebo <zděděný>)
					$this->format_sec_lang_val($sec_lang, $r['own_placeholder_l'], $r['inh_placeholder_l'])        // Překlad placeholderu (nebo <zděděný>)
				];                                      // Konec pole hodnot sloupce
				$sheetCol->fromArray($col_vals, null, 'A' . $row_idx); // Zápis řádku do listu column
				$row_idx++;                             // Posun na další řádek
			}
		}

		foreach (range('A', 'Z') as $colId) {           // Automatická šířka sloupců A až Z na záložce column
			$sheetCol->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}
		foreach (range('A', 'O') as $subCol) {          // Automatická šířka sloupců AA až AO na záložce column
			$sheetCol->getColumnDimension('A' . $subCol)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		$spreadsheet->setActiveSheetIndex(0);           // Aktivace prvního listu CONTENT_INFO při otevření

		$file_suffix = ($sec_lang !== '') ? "_{$lang}_{$sec_lang}" : "_{$lang}"; // Přípona souboru dle zvolených jazyků
		$filename = "meta_object{$file_suffix}.xlsx";   // Výsledný název stahovaného souboru

		header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
		header('Content-Disposition: attachment; filename="' . $filename . '"'); // Hlavička s názvem souboru
		header('Cache-Control: max-age=0');

		$writer = new Xlsx($spreadsheet);               // Inicializace XLSX zapisovače
		$writer->save('php://output');                  // Streamování vygenerovaného sešitu do prohlížeče
		exit;                                           // Okamžité ukončení skriptu po odeslání souboru
	}

	/**
	 * Vykreslí načtená data a případné logovací zprávy.
	 */
	protected function render_results(): void {
		echo <<<HTML
		<style>
			.xlsx-msg-wrap table {
				border-collapse: collapse;
				border: 1px solid #64748b;
				font-size: 12px;
				margin-bottom: 18px;
			}
			.xlsx-msg-wrap th {
				background-color: #a5c4d4;
				color: #000;
				border: 1px solid #64748b;
				padding: 4px 8px;
				text-align: center;
				font-weight: bold;
			}
			.xlsx-msg-wrap td {
				background-color: #dbe4f0;
				border: 1px solid #64748b;
				padding: 4px 8px;
			}
			table.xlsx-preview {
				border-collapse: collapse;
				border: 1px solid #64748b;
				font-size: 12px;
				margin: 5px 0 22px 0;
				width: auto;
			}
			table.xlsx-preview th,
			table.xlsx-preview td {
				border: 1px solid #888;
				padding: 3px 6px;
				vertical-align: top;
			}
			table.xlsx-preview td {
				max-width: 300px;
				white-space: pre-wrap;
				word-break: break-word;
				overflow-wrap: break-word;
			}
			table.xlsx-preview tr.sheet-title th {
				text-align: left;
				font-size: 13px;
				font-weight: bold;
				padding: 4px 8px;
			}
			table.xlsx-preview tr.sheet-title th.mand-sheet {
				background-color: #cbd5e1;
				color: #000;
			}
			table.xlsx-preview tr.sheet-title th.opt-sheet {
				background-color: yellow;
				color: #000;
			}
			table.xlsx-preview tr.col-headers th {
				position: sticky;
				top: 0;
				z-index: 2;
				font-weight: bold;
				text-align: center;
			}
			table.xlsx-preview tr.col-headers th.mandatory {
				background-color: #a5c4d4;
				color: #000;
			}
			table.xlsx-preview tr.col-headers th.optional {
				background-color: yellow;
				color: #000;
			}
			table.xlsx-preview tbody tr.row-odd td {
				background-color: #ffffff;
			}
			table.xlsx-preview tbody tr.row-even td {
				background-color: #e2e8f0;
			}
			table.xlsx-preview tbody tr:hover td {
				background-color: #dbeafe;
			}
		</style>
HTML;

		// Vypsání zpráv nasbíraných třídou request_message
		echo "<div class='xlsx-msg-wrap' style='margin: 5px 0 15px 0;'>{$this->reader->rqm}</div>"; // Výpis tabulky výsledkových zpráv

		// Zobrazení dat v HTML tabulkách pro režim náhledu
		if ($this->import_mode === '0') {               // Kontrola, zda je zvolen režim pouhého zobrazení
			$max_display_rows = 500;                    // Maximální počet vykreslovaných řádků v náhledu
			$msg_outside = htmlspecialchars($this->phrase('msg_data_outside_table', [], 'Data jsou i mimo tabulku')); // Text varování mimo tabulku

			foreach ($this->reader->data as $tn => $table) { // Průchod načtenými záložkami
				if (!$table) {                          // Přeskočení prázdné definice tabulky
					continue;                           // Pokračování na další záložku
				}
				
				$col_count = (int)$table['column_count']; // Počet sloupců aktuální záložky
				$row_count = (int)$table['row_count'];    // Počet datových řádků aktuální záložky
				$span_cols = ($col_count > 0) ? $col_count : 1; // Bezpečný colspan i pro prázdnou záložku
				$mimo_text = !empty($table['mimo']) ? " <span style='color: red; font-weight: bold;'>{$msg_outside}</span>" : ""; // Varování při datech mimo tabulku
				
				$is_mandatory_table = $this->reader->is_mandatory_table((string)$tn); // Zjištění, zda je záložka povinná
				$sheet_cls = $is_mandatory_table ? "mand-sheet" : "opt-sheet"; // CSS třída záhlaví tabulky
				$safe_tn = htmlspecialchars((string)$tn); // Ošetřený název záložky
				$rozmer = " [{$row_count},{$col_count}]"; // Rozměr tabulky ve formátu [řádky,sloupce]
				
				echo "<table class='xlsx-preview'>";
				echo "<thead>";
				echo "<tr class='sheet-title'><th colspan='{$span_cols}' class='{$sheet_cls}'>{$safe_tn}{$rozmer}{$mimo_text}</th></tr>";
				echo "<tr class='col-headers'>";
				
				foreach ($table['column_list'] as $colname) { // Výpis názvů sloupců záložky
					$is_mand_col = isset($table['mandatory_column_list'][$colname]); // Kontrola povinnosti sloupce
					$th_class = $is_mand_col ? "class='mandatory'" : "class='optional'"; // Přiřazení CSS třídy buňce záhlaví
					echo "<th {$th_class}>" . htmlspecialchars((string)$colname) . "</th>"; // Buňka záhlaví sloupce
				}
				echo "</tr>";
				echo "</thead>";
				echo "<tbody>";

				$num = 0;                               // Počitadlo vypsaných řádků v tabulce
				foreach ($table['rows'] as $rn => $rv) { // Průchod řádky záložky
					if ($num >= $max_display_rows) {    // Omezení výpisu při překročení limitu řádků
						$trunc_msg = htmlspecialchars($this->phrase(
							'msg_rows_truncated',       // Kód fráze omezení řádků
							['max' => $max_display_rows, 'total' => $row_count], // Proměnné pro interpolaci
							'... Zobrazeno pouze prvních {' . chr(36) . 'max} z celkových {' . chr(36) . 'total} řádků ...' // Výchozí text
						));
						echo "<tr><td colspan='{$span_cols}' style='text-align:center; font-style:italic; background-color:#f0f0f0; color: #333;'>{$trunc_msg}</td></tr>"; // Řádek informace o zkrácení
						break;                          // Ukončení výpisu řádků záložky
					}
					
					$row_cls = (($num % 2) === 0) ? 'row-odd' : 'row-even'; // Střídání barev lichých a sudých řádků
					echo "<tr class='{$row_cls}'>";
					foreach ($table['column_list'] as $cn) { // Výpis hodnot buněk v řádku
						$val = (string)($rv[$cn] ?? ''); // Hodnota buňky pro zobrazení v tabulce
						echo "<td>" . nl2br(htmlspecialchars($val)) . "</td>"; // Buňka dat se zachováním konců řádků
					}
					echo "</tr>";
					$num++;                             // Inkrementace počitadla vypsaných řádků
				}

				echo "</tbody></table>";
			}
		}
	}

	/**
	 * Generuje T-SQL dávku pro distribuci a odesílá ji jako soubor ke stažení.
	 */
	private function process_distribution(): void {
		global $charset;                                // Znaková sada pro hlavičku stahovaného souboru
		
		$pc = $this->reader->package_class;             // Instance validační třídy balíčku
		$code = $this->reader->package_code;            // Kód balíčku z CONTENT_INFO

		// Fallback pro případ, že distribuce není možná
		if (!$this->reader->package_ready OR !$pc) {    // Ověření připravenosti balíčku a existence třídy
			$err_not_ready = $this->phrase('err_pkg_not_ready', [], 'Balíček není připraven pro distribuci'); // Chybová zpráva balíčku
			$warn_switched = $this->phrase('warn_mode_switched', [], 'Režim byl automaticky přepnut na zobrazení dat'); // Varování o přepnutí režimu
			$this->reader->rqm->add_message($err_not_ready, 3); // Zápis chyby do fronty zpráv
			$this->reader->rqm->add_message($warn_switched, 2); // Zápis varování do fronty zpráv
			$this->import_mode = '0';                   // Nouzové přepnutí do režimu náhledu
			parent::render();                           // Vykreslíme chybové hlášky standardní cestou
			return;                                     // Ukončení distribuční metody
		}

		// Nastavení hlaviček pro okamžité stažení textového souboru
		header("Content-Type: application/sql; charset={$charset}"); // Hlavička SQL souboru
		header("Content-Disposition: attachment; filename=\"fillup_{$code}.sql\""); // Název stahovaného skriptu
		header("Cache-Control: public");

		echo "-- {$pc->import_name} \n";                // Název importního balíčku v záhlaví skriptu
		echo "-- Tato dávka vkládá data do dočasných tabulek a v závěru volá proceduru pro jejich import.\n";
		echo "-- Případné chyby hlaste dodavateli RAMSES (hink@rac.cz).\n\n";
		echo "/* Content description:\n\n{$pc->description}\n\n*/\n\n"; // Popis obsahu balíčku
		echo "execute p_drop_excel_tables @print_message=0\nGO\n\n";
		echo "-- Creating temporary tables\n";

		// Průchod mandatory tabulkami a export jejich INSERT struktury
		foreach ($pc->mandatory_tables as $t) {         // Export jednotlivých staging tabulek
			$safe_table = charliteral($this->table_prefix . $t . chr(36)); // Sestavení názvu staging tabulky včetně znaku '$'
			$a = sqlarray_simple("SET NOCOUNT ON; execute p_export_to_sql {$safe_table}, {$safe_table}, @output_as_sqlresult=1"); // Získání DDL a INSERTů
			
			if (is_array($a)) {                         // Pokud procedura vrátila řádky SQL skriptu
				foreach ($a as $row) {                  // Výpis jednotlivých řádků skriptu
					$txt = (string)($row['txt'] ?? $row[0] ?? ''); // Bezpečné přečtení sloupce txt
					echo "\n{$txt}";                    // Výpis vygenerovaného řádku DDL/DML
				}
			}
			echo "\n";
		}

		$n = charliteral((string)$pc->import_name);     // Název importu jako bezpečný SQL literál
		$v = charliteral((string)$pc->version_date);    // Datum verze balíčku jako bezpečný SQL literál

		// Závěr SQL skriptu s voláním distribuční procedury a úklidem staging tabulek
		echo "\nGO\nset xact_abort on\nbegin tran\nexecute p_request_messages_start\nexecute p_xlsx_{$code} @import_mode='2'\nexecute insert_request_message {$n}, 1, @charvalue={$v}\ncommit\nGO\nexecute p_drop_excel_tables @print_message=0\nGO\n"; // Závěrečný blok dávky
		exit;                                           // Okamžité ukončení běhu PHP skriptu
	}
}