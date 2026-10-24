<?php
/**
 * =============================================================================
 * Verze: 2026-10-24 14:35
 * Soubor: abstract_csv_package.php
 * Třída: abstract_csv_package
 * Účel: Abstraktní předek pro víceblokový CSV export a dvoufázový import
 *       aplikačních balíčků mezi instancemi systému BCM Osiris.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Registruje autoloader pro potomky s prefixem `csv_package_` (např. `csv_package_metadata`
 *   v souboru `csv_package_metadata.php`).
 * - Využívá nativní streamové funkce PHP `fputcsv()` a `fgetcsv()` s parametrem
 *   `$escape = ''` (RFC 4180 kompatibilní zdvojování uvozovek `""`; hodnoty obsahující
 *   středník, nový řádek `\n` nebo uvozovky jsou vždy uzavřeny v dvojitých uvozovkách `"`,
 *   znaky `\r` jsou vypuštěny). Výchozím oddělovačem je středník `;` a příponou `.csv`
 *   pro přímé otevření v MS Excelu.
 * - Zabezpečení proti změnám zajišťuje HMAC-SHA256 podpis (`signature`). Při exportu lze
 *   nastavit podepsaný parametr `verify_data = 1` (podpis chrání parametry i všechna data)
 *   nebo `verify_data = 0` (podpis chrání hlavičku parametrů, data lze upravit v Excelu).
 *   Ověření podpisu při importu nelze obejít.
 * - Ve Fázi 1 importu v jediné databázové transakci vyčistí a naplní tabulky
 *   `session_import_parameter`, `session_import_table`, `session_import_column`
 *   a `session_import_data` (definované v `table_session_import.sql`) a zapíše
 *   statistiku a případné chyby do `request_message`.
 * - Ve Fázi 2 importu spustí uloženou proceduru `p_csv_import_{$package_code}`, která
 *   pomocí `p_csv_fill_table` a `dbo.f_csv_param` zpracuje načtená data.
 *
 * Změny:
 * 2026-10-24 14:35 - Změna výchozího oddělovače na středník `;` a přípony na `.csv`
 *                    pro přímou kontrolu a úpravy v MS Excelu.
 *                  - Zjišťování názvů sloupců při exportu přímo přes `sqlsrv_field_metadata()`
 *                    (garantuje přesnou hlavičku ze SELECT dotazu i u prázdných tabulek).
 *                  - Plnění `session_import_*` v `load_file_to_session()` obaleno transakcí
 *                    `BEGIN TRAN ... COMMIT` s dávkovým vkládáním buněk.
 *                  - Rozšířena automatická detekce oddělovače při importu o středník `;`.
 * =============================================================================
 */

declare(strict_types=1);

// Automatické načítání samostatných souborů pro konkrétní CSV balíčky (např. csv_package_metadata.php)
spl_autoload_register(function (string $class_name): void {                  // Registrace autoloaderu CSV balíčků
	if (str_starts_with($class_name, 'csv_package_')) {                      // Kontrola prefixu třídy CSV balíčku
		$file = __DIR__ . '/' . $class_name . '.php';                        // Cesta k souboru balíčku ve stejném adresáři
		if (is_file($file)) {                                                // Ověření existence souboru na disku
			require_once $file;                                              // Načtení definice třídy balíčku
		}
	}
});

abstract class abstract_csv_package {

	/** Výchozí interní klíč pro HMAC-SHA256 podpis CSV balíčků */
	private const DEFAULT_HMAC_KEY = 'BcmOsiris_CSV_Package_HMAC_Key_2026';

	public string $package_code = '';                                        // Technický kód balíčku (např. 'metadata')
	public string $package_title = '';                                       // Lidsky čitelný název balíčku
	public string $description = '';                                         // Popis účelu a obsahu balíčku
	public bool $is_system_package = false;                                  // true = Systémová data (0x00), nevytvářejí koncepty 'D'
	public array $params = [];                                               // Aktuální hodnoty parametrů balíčku
	public request_message $rqm;                                             // Instance třídy request_message pro logování
	public bool $phase1_ready = false;                                       // Příznak úspěšného dokončení Fáze 1 bez chyb

	/**
	 * Konstruktor balíčku. Přijímá volitelné výchozí parametry (např. z detailu záznamu).
	 *
	 * @param array<string, mixed> $initial_params Výchozí hodnoty parametrů pro export/import
	 */
	public function __construct(array $initial_params = []) {                // Inicializace CSV balíčku
		$this->rqm = new request_message();                                  // Založení kontejneru zpráv
		$this->init_package();                                               // Nastavení kódu a názvu v potomkovi

		foreach ($this->get_all_parameters_def() as $p_code => $p_def) {     // Inicializace výchozích hodnot parametrů
			$this->params[$p_code] = (string)($p_def['default'] ?? '');      // Nastavení výchozí hodnoty z definice
		}
		foreach ($initial_params as $k => $v) {                              // Přepsání hodnotami předanými do konstruktoru
			$this->params[(string)$k] = (string)$v;                          // Uložení předaného parametru
		}
	}

	/**
	 * Pomocná metoda pro překlad textů v rámci třídy abstract_csv_package a jejích potomků.
	 *
	 * @param string               $builtin_code    Kód fráze
	 * @param string               $default_caption Výchozí český text
	 * @param array<string, mixed> $vars            Proměnné pro interpolaci
	 * @return string Přeložený text
	 */
	protected function phrase(string $builtin_code, string $default_caption, array $vars = []): string { // Načtení přeložené fráze
		global $phrase_manager;                                              // Globální instance správce frází
		if (!isset($phrase_manager) OR !($phrase_manager instanceof phrase_manager)) { // Kontrola inicializace správce frází
			$phrase_manager = new phrase_manager($this);                     // Inicializace správce frází pro balíček
			$GLOBALS['phrase_manager'] = $phrase_manager;                    // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, $vars, $default_caption, get_class($this)); // Vrácení přeložené fráze
	}

	/**
	 * Potomek zde nastaví $this->package_code, $this->package_title, $this->description a $this->is_system_package.
	 */
	abstract protected function init_package(): void;

	/**
	 * Potomek vrátí definici filtračních parametrů specifických pro daný balíček.
	 * Formát: ['param_code' => ['label' => '...', 'type' => 'varchar|bit|date|uuid|int', 'mandatory' => true|false, 'default' => '...', 'options' => [...]]]
	 *
	 * @return array<string, array<string, mixed>>
	 */
	abstract public function get_filter_parameters_def(): array;

	/**
	 * Potomek vrátí pole SQL dotazů pro export jednotlivých tabulek podle zadaných parametrů.
	 * Formát: ['table_name' => 'SELECT ...']
	 *
	 * @param array<string, string> $params Platné parametry exportu
	 * @return array<string, string>
	 */
	abstract public function get_export_tables_sql(array $params): array;

	/**
	 * Potomek vrátí definici očekávaných tabulek a jejich sloupců pro formální kontrolu při importu.
	 * Formát:
	 * [
	 *   'table_name' => [
	 *     'mandatory' => true|false,
	 *     'columns' => [
	 *       'col_name' => ['datatype' => 'varchar|bit|int|decimal|date|uuid', 'mandatory' => true|false]
	 *     ]
	 *   ]
	 * ]
	 *
	 * @return array<string, array<string, mixed>>
	 */
	abstract public function get_tables_definition(): array;

	/**
	 * Sjednotí standardní hlavičkové parametry balíčku s filtračními parametry potomka.
	 *
	 * @return array<string, array<string, mixed>>
	 */
	public function get_all_parameters_def(): array {
		$std_params = [                                                      // Standardní systémové parametry každého CSV balíčku
			'verify_data' => [                                               // Volba přísnosti podpisu při exportu
				'label'     => $this->phrase('lbl_param_verify_data', 'Vyžadovat nezměnitelnost dat (podpis celého souboru)'),
				'type'      => 'bit',
				'mandatory' => true,
				'default'   => '1'
			],
			'import_origin' => [                                             // Měkký audit původu balíčku
				'label'     => $this->phrase('lbl_param_import_origin', 'Označení původu dat (import_origin)'),
				'type'      => 'varchar',
				'mandatory' => false,
				'default'   => 'CSV Package Export'
			]
		];                                                                   // Konec standardních parametrů

		if (!$this->is_system_package) {                                     // U nesystémových dat nabízíme volbu režimu zápisu
			$std_params['target_status'] = [                                 // Režim zápisu u klientských dat
				'label'     => $this->phrase('lbl_param_target_status', 'Režim zápisu při importu'),
				'type'      => 'varchar',
				'mandatory' => true,
				'default'   => 'F',
				'options'   => [
					'F' => $this->phrase('opt_status_forward', 'Uložit do návrhů ke schválení (F)'),
					'A' => $this->phrase('opt_status_direct', 'Přímý přepis schválených záznamů (A)')
				]
			];                                                               // Konec definice target_status
		}

		return array_merge($this->get_filter_parameters_def(), $std_params); // Spojení filtračních a standardních parametrů
	}

	/**
	 * Nastaví hodnoty parametrů z asociativního pole (např. z $_POST nebo $_GET).
	 *
	 * @param array<string, mixed> $input Vstupní pole parametrů
	 */
	public function set_parameters_from_request(array $input): self {        // Načtení parametrů z požadavku
		foreach ($this->get_all_parameters_def() as $p_code => $p_def) {     // Průchod definovanými parametry
			if (array_key_exists($p_code, $input)) {                         // Pokud byl parametr v požadavku předán
				$val = trim((string)$input[$p_code]);                        // Očištěná textová hodnota
				if (($p_def['type'] ?? '') === 'bit') {                      // Normalizace bitového parametru
					$val = ($val === '1' OR strtolower($val) === 'true') ? '1' : '0'; // Bit 1 nebo 0
				}
				$this->params[$p_code] = $val;                               // Uložení hodnoty parametru
			}
		}
		return $this;                                                        // Vrácení instance pro řetězení
	}

	/**
	 * Vrátí tajný klíč pro výpočet a ověření HMAC-SHA256 podpisu.
	 */
	protected function get_hmac_secret(): string {
		$custom_key = (string)($GLOBALS['csv_package_secret'] ?? '');        // Volitelný klíč z config.php
		return ($custom_key !== '') ? $custom_key : self::DEFAULT_HMAC_KEY;  // Vrácení klíče pro HMAC
	}

	/**
	 * Očistí textovou hodnotu buňky před zápisem do CSV nebo po načtení (odstraní znaky \r).
	 */
	protected function clean_cell_value(mixed $val): string {                // Očištění hodnoty buňky od CR
		if ($val === null) {                                                 // Hodnota NULL se v CSV reprezentuje prázdným řetězcem
			return '';                                                       // Prázdný řetězec
		}
		return str_replace("\r", '', (string)$val);                          // Odstranění všech znaků \r
	}

	/**
	 * Vykreslí vstupní <div> s formulářem pro zadání parametrů exportu balíčku.
	 *
	 * @param string $form_action Cílová URL adresa formuláře
	 * @return string HTML kód bloku parametrů
	 */
	public function render_parameters_div(string $form_action = ''): string { // Vykreslení formuláře parametrů pro export
		$safe_action = htmlspecialchars($form_action);                       // Ošetřená URL akce formuláře
		$safe_code = htmlspecialchars($this->package_code);                  // Ošetřený kód balíčku
		$safe_title = htmlspecialchars($this->package_title ?: $this->package_code); // Ošetřený titulek balíčku
		$safe_desc = htmlspecialchars($this->description);                   // Ošetřený popis balíčku

		$btn_exp = new abstract_button('btn_export_csv', 'Exportovat balíček (CSV)', 'abstract_csv_package', '', 'btn-success'); // Tlačítko exportu
		$btn_exp->set_type('submit')->set_name_value('btn_export_csv', '1'); // Submit atributy
		$btn_exp_html = $btn_exp->render();                                  // HTML tlačítka exportu

		$rows_html = '';                                                     // Sběrný HTML řetězec řádků tabulky parametrů
		foreach ($this->get_all_parameters_def() as $p_code => $p_def) {     // Průchod všemi parametry balíčku
			$label = htmlspecialchars((string)($p_def['label'] ?? $p_code)); // Popisek parametru
			$is_mand = !empty($p_def['mandatory']);                          // Zda je parametr povinný
			$req_mark = $is_mand ? ' <span style="color:#b91c1c;">*</span>' : ''; // Hvězdička povinného parametru
			$req_attr = $is_mand ? 'required' : '';                          // HTML atribut required
			$cur_val = (string)($this->params[$p_code] ?? '');               // Aktuální hodnota parametru
			$safe_p_code = htmlspecialchars($p_code);                        // Ošetřený název pole
			$safe_val = htmlspecialchars($cur_val);                          // Ošetřená hodnota pole
			$p_type = (string)($p_def['type'] ?? 'varchar');                 // Typ parametru

			if (!empty($p_def['options']) AND is_array($p_def['options'])) { // Roletka <select> pro výčtový parametr
				$opts_html = '';                                             // HTML opcí roletky
				foreach ($p_def['options'] as $opt_k => $opt_v) {            // Sestavení položek roletky
					$sel = ((string)$opt_k === $cur_val) ? 'selected' : '';  // Označení vybrané položky
					$opts_html .= '<option value="' . htmlspecialchars((string)$opt_k) . '" ' . $sel . '>' . htmlspecialchars((string)$opt_v) . '</option>'; // Volba
				}
				$input_html = "<select name=\"{$safe_p_code}\" style=\"width: 100%; max-width: 380px; padding: 6px;\">{$opts_html}</select>"; // HTML select
			} elseif ($p_type === 'bit') {                                   // Checkbox pro bitový parametr
				$chk = ($cur_val === '1') ? 'checked' : '';                  // Stav zaškrtnutí
				$input_html = "<input type=\"hidden\" name=\"{$safe_p_code}\" value=\"0\"><input type=\"checkbox\" name=\"{$safe_p_code}\" value=\"1\" {$chk} style=\"cursor: pointer;\">"; // HTML checkbox
			} elseif ($p_type === 'date') {                                  // Datumové pole
				$input_html = "<input type=\"date\" name=\"{$safe_p_code}\" value=\"{$safe_val}\" {$req_attr} style=\"width: 180px; padding: 6px;\">"; // HTML date
			} else {
				$input_html = "<input type=\"text\" name=\"{$safe_p_code}\" value=\"{$safe_val}\" {$req_attr} style=\"width: 100%; max-width: 380px; padding: 6px; box-sizing: border-box;\">"; // Textové pole
			}

			$rows_html .= "<tr><td style=\"width: 35%; font-weight: bold; background-color: #f8fafc;\">{$label}{$req_mark}</td><td>{$input_html}</td></tr>\n"; // Řádek parametru
		}

		return <<<HTML
		<div class="csv-package-params-box" style="margin-bottom: 25px;">
			<h2 style="color: #004488; font-size: 17px; margin: 0 0 6px 0;">{$safe_title}</h2>
			<p style="color: #475569; font-size: 13px; margin: 0 0 15px 0;">{$safe_desc}</p>
			<form method="post" action="{$safe_action}">
				<input type="hidden" name="package_code" value="{$safe_code}">
				<table class="md-table" style="margin-bottom: 15px;">
					{$rows_html}
				</table>
				<div>{$btn_exp_html}</div>
			</form>
		</div>
HTML;
	}

	/**
	 * Provede kompletní export balíčku do víceblokového CSV souboru a odešle jej do prohlížeče.
	 * Všechny hodnoty jsou exportovány jako varchar (očištěné od \r) přes standardní fputcsv()
	 * s dvojitými uvozovkami '"' a výchozím oddělovačem středník ';'.
	 *
	 * @param string $delimiter Oddělovač polí (výchozí ';' pro přímé otevření v MS Excelu)
	 */
	public function export_to_browser(string $delimiter = ';'): void {       // Export balíčku do prohlížeče
		if ($delimiter === '') {                                             // Pojistka při předání prázdného oddělovače
			$delimiter = ';';                                                // Výchozím oddělovačem je středník
		}

		$verify_data = ((string)($this->params['verify_data'] ?? '1') === '1') ? '1' : '0'; // Zda se podepisují i data
		$version_date = date('Y-m-d H:i:s');                                 // Časové razítko exportu

		// 1. Sestavení uspořádaného seznamu parametrů pro 1. blok souboru
		$header_params = [                                                   // Základní identifikační parametry balíčku
			'package_name' => $this->package_code,                           // Kód balíčku na prvním řádku
			'version_date' => $version_date,                                 // Datum a čas pořízení exportu
			'verify_data'  => $verify_data                                   // Příznak kontroly nezměnitelnosti dat
		];                                                                   // Konec základních parametrů

		foreach ($this->get_all_parameters_def() as $p_code => $p_def) {     // Přidání ostatních parametrů balíčku
			if (!isset($header_params[$p_code])) {                           // Zamezení duplicity verify_data
				$header_params[$p_code] = $this->clean_cell_value($this->params[$p_code] ?? ''); // Hodnota parametru
			}
		}

		// 2. Inicializace HMAC-SHA256 kontextu a dočasného streamu pro bloky tabulek
		$hmac_ctx = hash_init('sha256', HASH_HMAC, $this->get_hmac_secret()); // Inicializace HMAC výpočtu
		foreach ($header_params as $pk => $pv) {                             // Zařazení parametrů do podpisu
			if ($pk !== 'target_status') {                                   // target_status smí uživatel při importu změnit
				hash_update($hmac_ctx, "P:{$pk}={$pv}\n");                   // Přidání parametru do HMAC
			}
		}

		$tables_stream = fopen('php://temp', 'r+');                          // Dočasný proud pro zapsání bloků tabulek
		$export_queries = $this->get_export_tables_sql($this->params);       // Získání SQL dotazů z potomka

		foreach ($export_queries as $table_name => $sql) {                   // Postupný export všech tabulek balíčku
			if (trim($sql) === '') {                                         // Přeskočení prázdného dotazu
				continue;                                                    // Další tabulka
			}

			$stmt = sqlrun($sql);                                            // Spuštění exportního dotazu tabulky
			$col_names = [];                                                 // Seznam názvů sloupců z výsledku dotazu
			if (is_resource($stmt) OR is_object($stmt)) {                    // Kontrola platného SQLSRV statementu
				$fields_meta = sqlsrv_field_metadata($stmt);                 // Načtení metadat sloupců přímo ze statementu
				if (is_array($fields_meta)) {                                // Pokud ovladač vrátil metadata sloupců
					foreach ($fields_meta as $fm) {                          // Průchod metadaty sloupců
						if (!empty($fm['Name'])) {                           // Kontrola názvu sloupce
							$col_names[] = (string)$fm['Name'];              // Přidání přesného názvu sloupce ze SELECTu
						}
					}
				}
			}

			$rows = sqlarray_simple($stmt);                                  // Načtení všech řádků do paměti a uvolnění statementu

			if (empty($col_names) AND is_array($rows) AND !empty($rows)) {   // Fallback pro případ nedostupných metadat
				foreach (array_keys($rows[0]) as $rk) {                      // Průchod klíči prvního řádku
					if (!is_numeric($rk)) {                                  // Ignorování číselných indexů z fetch()
						$col_names[] = (string)$rk;                          // Název sloupce z prvního řádku
					}
				}
			}

			if (empty($col_names)) {                                         // Pokud tabulka nemá žádné sloupce
				continue;                                                    // Přeskočení tabulky
			}

			// Zápis názvu tabulky a hlavičky sloupců do dočasného streamu
			fputcsv($tables_stream, [$table_name], $delimiter, '"', '');     // Řádek s názvem tabulky
			fputcsv($tables_stream, $col_names, $delimiter, '"', '');        // Řádek s názvy sloupců oddělenými středníkem

			if ($verify_data === '1') {                                      // Pokud podepisujeme i data tabulek
				hash_update($hmac_ctx, "T:{$table_name}:" . implode(',', $col_names) . "\n"); // Podpis hlavičky tabulky
			}

			$r_idx = 0;                                                      // Pořadové číslo řádku v tabulce
			if (is_array($rows)) {                                           // Průchod datovými řádky tabulky
				foreach ($rows as $row) {                                    // Zpracování jednoho řádku
					$r_idx++;                                                // Inkrementace pořadí řádku
					$line_vals = [];                                         // Pole textových hodnot řádku
					foreach ($col_names as $c_idx => $cn) {                  // Průchod sloupci
						$c_val = $this->clean_cell_value($row[$cn] ?? '');   // Očištěná hodnota jako varchar
						$line_vals[] = $c_val;                               // Přidání do řádku pro fputcsv
						if ($verify_data === '1' AND $c_val !== '') {        // Do podpisu zahrneme každou neprázdnou buňku
							hash_update($hmac_ctx, "D:{$r_idx}:{$c_idx}={$c_val}\n"); // Přidání buňky do HMAC
						}
					}
					fputcsv($tables_stream, $line_vals, $delimiter, '"', ''); // Zápis datového řádku (středníky v buňce jsou v "uvozovkách")
				}
			}

			// Prázdný řádek ukončující blok tabulky
			fwrite($tables_stream, "\n");                                    // Oddělení tabulky prázdným řádkem
		}

		$header_params['signature'] = hash_final($hmac_ctx);                 // Dokončení výpočtu HMAC-SHA256 podpisu

		// 3. Odeslání HTTP hlaviček a sestavení finálního CSV výstupu
		$filename = sanitize_filename($this->package_code . '_' . date('Ymd_His')) . '.csv'; // Bezpečný název souboru s koncovkou .csv

		header('Content-Type: text/csv; charset=UTF-8');
		header('Content-Disposition: attachment; filename="' . $filename . '"'); // Hlavička pro stažení souboru
		header('Cache-Control: max-age=0');

		$out = fopen('php://output', 'w');                                   // Otevření výstupního proudu prohlížeče
		// Zápis UTF-8 BOM pro bezproblémové otevření diakritiky a rozdělení sloupců v MS Excelu
		fwrite($out, "\xEF\xBB\xBF");                                        // Sekvence UTF-8 BOM

		// Zápis 1. bloku (parametry balíčku včetně vypočteného podpisu)
		foreach ($header_params as $pk => $pv) {                             // Výpis parametrů balíčku
			fputcsv($out, [(string)$pk, (string)$pv], $delimiter, '"', '');  // Řádek parametru: kód;hodnota
		}
		fwrite($out, "\n");                                                  // Prázdný řádek ukončující blok parametrů

		// Překopírování připravených bloků tabulek do výstupu
		rewind($tables_stream);                                              // Přesun na začátek dočasného proudu
		stream_copy_to_stream($tables_stream, $out);                         // Proudové odeslání všech tabulek
		fclose($tables_stream);                                              // Uzavření dočasného proudu
		fclose($out);                                                        // Uzavření výstupního proudu
		exit;                                                                // Okamžité ukončení běhu po odeslání souboru
	}

	/**
	 * FÁZE 1 IMPORTU: Přečte nahraný CSV soubor, v jediné transakci vyčistí a naplní
	 * tabulky `session_import_*`, ověří HMAC-SHA256 podpis a provede formální kontrolu
	 * povinných parametrů, tabulek, sloupců a datových typů.
	 *
	 * @param string $filepath  Cesta k uploadovanému souboru
	 * @param string $delimiter Oddělovač (pokud '', detekuje se automaticky z 1. řádku: ';', "\t" nebo ',')
	 * @return bool True pokud je balíček bez kritických chyb (severity < 3)
	 */
	public function load_file_to_session(string $filepath, string $delimiter = ''): bool { // Fáze 1: Načtení do session tabulek
		global $SID;                                                         // Identifikátor aktuální relace prohlížeče
		$this->phase1_ready = false;                                         // Výchozí stav před validací

		if (!is_readable($filepath)) {                                       // Kontrola čitelnosti souboru
			$this->rqm->add_message($this->phrase('err_file_not_readable', 'Vstupní soubor nelze přečíst.'), 3); // Chyba souboru
			return false;                                                    // Ukončení při chybě
		}

		$fh = fopen_bom($filepath, 'r');                                     // Otevření souboru s přeskočením případného UTF-8 BOM
		if (!$fh) {                                                          // Kontrola otevření deskriptoru
			$this->rqm->add_message($this->phrase('err_file_open_failed', 'Nepodařilo se otevřít vstupní soubor.'), 3); // Chyba
			return false;                                                    // Ukončení při chybě
		}

		// Automatická detekce oddělovače (středník vs. tabulátor vs. čárka) z prvního řádku
		if ($delimiter === '') {                                             // Pokud nebyl oddělovač zadán explicitně
			$pos = ftell($fh);                                               // Zapamatování pozice za BOM
			$first_line = (string)fgets($fh);                                // Přečtení prvního řádku souboru
			fseek($fh, (int)$pos);                                           // Návrat ukazatele na začátek dat
			if (str_contains($first_line, ';')) {                            // Prioritní detekce středníku (standard pro Excel)
				$delimiter = ';';                                            // Oddělovačem je středník
			} elseif (str_contains($first_line, "\t")) {                     // Detekce tabulátoru (TSV)
				$delimiter = "\t";                                           // Oddělovačem je tabulátor
			} else {
				$delimiter = ',';                                            // Výchozím oddělovačem je čárka
			}
		}

		// Zahájení transakce a reset rozpracovaných dat v session_import_* pro aktuální relaci
		sqlrun("BEGIN TRAN");                                                // Spuštění transakce pro rychlé naplnění stagingu
		sqlrun("EXEC p_csv_clear_session_import");                           // Vyčištění session tabulek přes uloženou proceduru

		$safe_sid = charliteral($SID, 50);                                   // SQL literál identifikátoru relace
		$state = 'PARAMS';                                                   // Stav automatu: PARAMS -> TABLE_WAIT -> COLS -> DATA
		$loaded_params = [];                                                 // Načtené parametry z 1. bloku
		$param_order = 0;                                                    // Pořadí parametru
		$table_id = 0;                                                       // Pořadové číslo tabulky v souboru
		$global_col_id = 0;                                                  // Globální pořadové číslo sloupce (column_id)
		$current_table = '';                                                 // Název právě čtené tabulky
		$current_cols = [];                                                  // Mapa sloupců aktuální tabulky: [index => ['id' => ..., 'name' => ...]]
		$current_row_id = 0;                                                 // Pořadové číslo řádku v aktuální tabulce
		$pending_cells = [];                                                 // Buffer buněk aktualní tabulky pro dávkový INSERT

		$hmac_header_ctx = hash_init('sha256', HASH_HMAC, $this->get_hmac_secret()); // HMAC pouze pro hlavičku
		$hmac_full_ctx = hash_init('sha256', HASH_HMAC, $this->get_hmac_secret());   // HMAC pro hlavičku i data

		while (($row = fgetcsv($fh, 0, $delimiter, '"', '')) !== false) {    // Proudové čtení CSV řádků
			// Kontrola, zda je řádek prázdný (všechny buňky prázdné)
			$is_empty_row = true;                                            // Příznak prázdného řádku
			foreach ($row as &$cell) {                                       // Očištění všech buněk řádku od \r
				$cell = $this->clean_cell_value($cell);                      // Odstranění CR z buňky
				if (trim($cell) !== '') {                                    // Pokud buňka obsahuje neprázdný znak
					$is_empty_row = false;                                   // Řádek není prázdný
				}
			}
			unset($cell);                                                    // Uvolnění reference

			if ($is_empty_row) {                                             // Prázdný řádek ukončuje aktuální blok
				if ($state === 'PARAMS' AND $param_order > 0) {              // Konec bloku parametrů
					$state = 'TABLE_WAIT';                                   // Přechod na čekání na název první tabulky
				} elseif ($state === 'DATA' OR $state === 'COLS') {          // Konec bloku dat tabulky -> uložíme buffer buněk
					if (!empty($pending_cells)) {                            // Vyprázdnění zbývajících buněk tabulky do DB
						sqlrun("INSERT INTO session_import_data (wwwsession, row_id, column_id, cell_value) VALUES " . implode(', ', $pending_cells)); // Zápis buněk
						$pending_cells = [];                                 // Vyčištění bufferu buněk
					}
					sqlrun("UPDATE session_import_table SET row_count = {$current_row_id} WHERE wwwsession = {$safe_sid} AND table_id = {$table_id}"); // Uložení počtu řádků
					$state = 'TABLE_WAIT';                                   // Přechod na čekání na další tabulku
					$current_table = '';                                     // Vyčištění názvu tabulky
					$current_cols = [];                                      // Vyčištění sloupců
					$current_row_id = 0;                                     // Vynulování počitadla řádků
				}
				continue;                                                    // Pokračování na další řádek souboru
			}

			if ($state === 'PARAMS') {                                       // Čtení 1. bloku parametrů
				$p_key = trim((string)($row[0] ?? ''));                      // Kód parametru v prvním sloupci
				$p_val = (string)($row[1] ?? '');                            // Hodnota parametru ve druhém sloupci
				if ($p_key === '') {                                         // Přeskočení neplatného parametru
					continue;                                                // Další řádek
				}
				$param_order++;                                              // Zvýšení pořadí parametru
				$loaded_params[$p_key] = $p_val;                             // Uložení do pole načtených parametrů
				$this->params[$p_key] = $p_val;                              // Aktualizace v objektu balíčku

				$safe_pk = charliteral($p_key, 80);                          // SQL literál kódu parametru
				$safe_pv = charliteral($p_val);                              // SQL literál hodnoty parametru
				sqlrun("INSERT INTO session_import_parameter (wwwsession, param_order, parameter_code, parameter_value) VALUES ({$safe_sid}, {$param_order}, {$safe_pk}, {$safe_pv})"); // Uložení parametru

				if ($p_key !== 'signature' AND $p_key !== 'target_status') { // Do HMAC vstupují všechny podepsané parametry
					hash_update($hmac_header_ctx, "P:{$p_key}={$p_val}\n");  // Aktualizace hlavičkového HMAC
					hash_update($hmac_full_ctx, "P:{$p_key}={$p_val}\n");    // Aktualizace plného HMAC
				}
			} elseif ($state === 'TABLE_WAIT') {                             // Očekáváme řádek s názvem tabulky
				$current_table = trim((string)($row[0] ?? ''));              // Název tabulky z první buňky
				$table_id++;                                                 // Zvýšení pořadového čísla tabulky
				$current_cols = [];                                          // Vyčištění seznamu sloupců
				$current_row_id = 0;                                         // Vynulování počitadla řádků tabulky
				$safe_tname = charliteral($current_table, 128);              // SQL literál názvu tabulky
				sqlrun("INSERT INTO session_import_table (wwwsession, table_id, table_name, row_count) VALUES ({$safe_sid}, {$table_id}, {$safe_tname}, 0)"); // Založení záznamu tabulky (kvůli FK sloupců)
				$state = 'COLS';                                             // Následující řádek bude hlavička sloupců
			} elseif ($state === 'COLS') {                                   // Čtení řádku s názvy sloupců tabulky
				$col_names_for_hmac = [];                                    // Pole názvů sloupců pro HMAC
				$col_insert_vals = [];                                       // Pole pro dávkový INSERT sloupců
				foreach ($row as $c_idx => $col_raw) {                       // Průchod buňkami hlavičky sloupců
					$col_name = trim((string)$col_raw);                      // Očištěný název sloupce
					if ($col_name === '') {                                  // Konec hlavičky sloupců při prázdné buňce
						break;                                               // Ukončení čtení hlavičky
					}
					$global_col_id++;                                        // Zvýšení globálního column_id o 1
					$current_cols[$c_idx] = [                                // Uložení metadat sloupce
						'id'   => $global_col_id,                            // Globální ID sloupce
						'name' => $col_name                                  // Technický název sloupce
					];                                                       // Konec položky sloupce
					$col_names_for_hmac[] = $col_name;                       // Přidání do seznamu pro podpis
					$safe_cname = charliteral($col_name, 128);               // SQL literál názvu sloupce
					$col_insert_vals[] = "({$safe_sid}, {$global_col_id}, {$table_id}, {$safe_cname})"; // Položka VALUES sloupce
				}
				if (!empty($col_insert_vals)) {                              // Dávkové uložení všech sloupců tabulky
					sqlrun("INSERT INTO session_import_column (wwwsession, column_id, table_id, column_name) VALUES " . implode(', ', $col_insert_vals)); // Zápis sloupců
				}
				hash_update($hmac_full_ctx, "T:{$current_table}:" . implode(',', $col_names_for_hmac) . "\n"); // Podpis hlavičky tabulky
				$state = 'DATA';                                             // Následující řádky jsou datové
			} elseif ($state === 'DATA') {                                   // Čtení datového řádku tabulky
				$current_row_id++;                                           // Zvýšení pořadového čísla datového řádku
				foreach ($current_cols as $c_idx => $c_info) {               // Průchod definovanými sloupci tabulky
					$val = (string)($row[$c_idx] ?? '');                     // Hodnota buňky
					if ($val !== '') {                                       // Ukládáme a podepisujeme neprázdné buňky
						$cid = (int)$c_info['id'];                           // Globální ID sloupce
						$safe_val = charliteral($val);                       // SQL literál hodnoty buňky
						$pending_cells[] = "({$safe_sid}, {$current_row_id}, {$cid}, {$safe_val})"; // Přidání do dávkového bufferu
						hash_update($hmac_full_ctx, "D:{$current_row_id}:{$c_idx}={$val}\n"); // Přidání do HMAC
					}
				}
				if (count($pending_cells) >= 250) {                          // Odeslání dávky buněk při naplnění bufferu (max 1000 v T-SQL)
					sqlrun("INSERT INTO session_import_data (wwwsession, row_id, column_id, cell_value) VALUES " . implode(', ', $pending_cells)); // Dávkový zápis buněk
					$pending_cells = [];                                     // Vyprázdnění bufferu
				}
			}
		}

		// Pokud soubor nebyl na konci ukončen prázdným řádkem, zapíšeme poslední otevřenou tabulku
		if (($state === 'DATA' OR $state === 'COLS') AND $current_table !== '') { // Ošetření neukončeného posledního bloku
			if (!empty($pending_cells)) {                                    // Vyprázdnění zbývajících buněk
				sqlrun("INSERT INTO session_import_data (wwwsession, row_id, column_id, cell_value) VALUES " . implode(', ', $pending_cells)); // Zápis buněk
				$pending_cells = [];                                         // Vyčištění bufferu
			}
			sqlrun("UPDATE session_import_table SET row_count = {$current_row_id} WHERE wwwsession = {$safe_sid} AND table_id = {$table_id}"); // Uložení počtu řádků
		}

		fclose($fh);                                                         // Uzavření čteného souboru
		sqlrun("COMMIT");                                                    // Potvrzení transakce načtení souboru do session tabulek

		// =====================================================================
		// VALIDACE PODPISU, PARAMETRŮ, TABULEK, SLOUPCŮ A POVINNÝCH HODNOT
		// =====================================================================
		$calc_header_sig = hash_final($hmac_header_ctx);                     // Vypočtený podpis hlavičky
		$calc_full_sig = hash_final($hmac_full_ctx);                         // Vypočtený podpis celého souboru
		$file_sig = (string)($loaded_params['signature'] ?? '');             // Podpis uvedený v souboru
		$verify_data = ((string)($loaded_params['verify_data'] ?? '1') === '1'); // Zda soubor vyžaduje kontrolu dat

		$expected_sig = $verify_data ? $calc_full_sig : $calc_header_sig;    // Očekávaný podpis podle režimu verify_data
		if ($file_sig === '' OR !hash_equals($expected_sig, $file_sig)) {    // Striktní kontrola podpisu v konstantním čase
			$this->rqm->add_message($this->phrase('err_invalid_signature', 'Neplatný bezpečnostní podpis souboru (soubor byl neautorizovaně změněn nebo poškozen).'), 3)
				->setobject('Parametr', 'signature');                        // Zápis nepropustné chyby podpisu
		} else {
			$sig_msg = $verify_data
				? $this->phrase('msg_signature_ok_full', 'Bezpečnostní podpis souboru (parametry i data) je platný.')
				: $this->phrase('msg_signature_ok_header', 'Bezpečnostní podpis parametrů je platný (kontrola dat byla při exportu vypnuta).'); // Zpráva o podpisu
			$this->rqm->add_message($sig_msg, 1)->setobject('Parametr', 'signature'); // Potvrzení platnosti podpisu
		}

		// Kontrola shody kódu balíčku
		$file_pkg = (string)($loaded_params['package_name'] ?? '');          // Název balíčku ze souboru
		if ($file_pkg !== $this->package_code) {                             // Kontrola shody s očekávaným balíčkem
			$this->rqm->add_message($this->phrase('err_wrong_package_code', 'Kód balíčku v souboru neodpovídá zvolenému typu importu.'), 3)
				->setobject('package_name', $file_pkg);                      // Chyba neshody balíčku
		}

		// Kontrola povinných parametrů
		foreach ($this->get_all_parameters_def() as $p_code => $p_def) {     // Průchod definicemi parametrů
			if (!empty($p_def['mandatory']) AND trim((string)($loaded_params[$p_code] ?? '')) === '') { // Chybějící povinný parametr
				$this->rqm->add_message($this->phrase('err_missing_mandatory_param', 'Chybí povinný parametr balíčku.'), 3)
					->setobject('Parametr', $p_code);                        // Zápis chyby parametru
			}
		}

		// Kontrola přítomnosti povinných tabulek, povinných sloupců a povinných hodnot
		$loaded_tables = sqlarray2("SELECT table_name, table_id, row_count FROM session_import_table WHERE wwwsession = {$safe_sid}"); // Načtené tabulky
		$loaded_cols = sqlarray3("
			SELECT t.table_name, c.column_name, c.column_id
			FROM session_import_column c
			JOIN session_import_table t ON t.wwwsession = c.wwwsession AND t.table_id = c.table_id
			WHERE c.wwwsession = {$safe_sid}
		");                                                                  // Načtené sloupce seskupené podle tabulky

		foreach ($this->get_tables_definition() as $t_name => $t_def) {      // Průchod definicemi tabulek balíčku
			$is_mand_tab = !empty($t_def['mandatory']);                      // Zda je tabulka v balíčku povinná
			if (!isset($loaded_tables[$t_name])) {                           // Pokud tabulka v souboru vůbec není
				if ($is_mand_tab) {                                          // Chybějící povinná tabulka je kritická chyba
					$this->rqm->add_message($this->phrase('err_missing_mandatory_table', 'V souboru chybí povinná tabulka.'), 3)
						->setobject('Tabulka', $t_name);                     // Zápis chyby chybějící tabulky
				}
				continue;                                                    // Přechod na další tabulku
			}

			$t_row_count = (int)$loaded_tables[$t_name]['row_count'];        // Počet načtených řádků tabulky
			$this->rqm->add_message($this->phrase('msg_table_loaded_rows', 'Tabulka načtena do staging úložiště.'), 0)
				->setobject('Tabulka', $t_name)
				->setdetail((string)$t_row_count);                           // Zápis počtu řádků do logu

			$tab_cols_map = [];                                              // Mapa načtených sloupců tabulky: [col_name => column_id]
			if (isset($loaded_cols[$t_name]) AND is_array($loaded_cols[$t_name])) { // Sestavení mapy sloupců
				foreach ($loaded_cols[$t_name] as $lc_row) {                 // Průchod sloupci tabulky
					$tab_cols_map[(string)$lc_row['column_name']] = (int)$lc_row['column_id']; // Uložení column_id
				}
			}

			$cols_def = $t_def['columns'] ?? [];                             // Definice očekávaných sloupců tabulky
			if (is_array($cols_def)) {                                       // Kontrola platného pole definic sloupců
				foreach ($cols_def as $c_name => $c_props) {                 // Průchod očekávanými sloupci
					$is_mand_col = !empty($c_props['mandatory']);            // Zda je sloupec povinný
					if (!isset($tab_cols_map[$c_name])) {                    // Sloupec v hlavičce CSV chybí
						if ($is_mand_col) {                                  // Chybějící povinný sloupec
							$this->rqm->add_message($this->phrase('err_missing_mandatory_col', 'V tabulce chybí povinný sloupec.'), 3)
								->setobject($t_name, $c_name);               // Zápis chyby sloupce
						}
						continue;                                            // Další sloupec
					}

					// Pokud je sloupec povinný a tabulka má řádky, zkontrolujeme, že v každém řádku 1..row_count je neprázdná hodnota
					if ($is_mand_col AND $t_row_count > 0) {                 // Kontrola vyplnění povinných hodnot
						$cid = $tab_cols_map[$c_name];                       // Globální ID kontrolovaného sloupce
						$cnt_row = sqlfirstrow("SELECT COUNT(1) AS cnt FROM session_import_data WHERE wwwsession = {$safe_sid} AND column_id = {$cid} AND LTRIM(RTRIM(cell_value)) <> ''"); // Počet vyplněných řádků
						$filled_cnt = (int)($cnt_row['cnt'] ?? 0);           // Zjištěný počet neprázdných buněk
						if ($filled_cnt < $t_row_count) {                    // Některé řádky mají povinnou buňku prázdnou
							$missing_cnt = $t_row_count - $filled_cnt;       // Počet chybějících hodnot
							$this->rqm->add_message($this->phrase('err_empty_mandatory_cells', 'Sloupec obsahuje prázdné hodnoty v povinném poli.'), 3)
								->setobject("{$t_name}.{$c_name}", "Chybí v {$missing_cnt} řádcích"); // Zápis chyby
						}
					}
				}
			}
		}

		$this->phase1_ready = ($this->rqm->get_severity() < 3);              // Fáze 1 je připravena, pokud nejsou chyby severity 3
		return $this->phase1_ready;                                          // Vrácení stavu připravenosti
	}

	/**
	 * Vykreslí informační <div> po Fázi 1 importu se statistikou načtených tabulek,
	 * přehledem parametrů, zprávami `request_message` a tlačítkem pro spuštění Fáze 2.
	 *
	 * @param string $form_action Cílová URL adresa formuláře pro potvrzení Fáze 2
	 * @return string HTML kód rekapitulace Fáze 1
	 */
	public function render_import_summary_div(string $form_action = ''): string { // Vykreslení přehledu Fáze 1
		global $SID;                                                         // Identifikátor relace
		$safe_sid = charliteral($SID, 50);                                   // SQL literál relace
		$safe_action = htmlspecialchars($form_action);                       // Ošetřená URL akce formuláře
		$safe_code = htmlspecialchars($this->package_code);                  // Ošetřený kód balíčku

		$params_rows = sqlarray_simple("SELECT parameter_code, parameter_value FROM session_import_parameter WHERE wwwsession = {$safe_sid} ORDER BY param_order"); // Načtené parametry
		$tables_rows = sqlarray_simple("
			SELECT t.table_id, t.table_name, t.row_count, COUNT(c.column_id) AS col_count
			FROM session_import_table t
			LEFT JOIN session_import_column c ON c.wwwsession = t.wwwsession AND c.table_id = t.table_id
			WHERE t.wwwsession = {$safe_sid}
			GROUP BY t.table_id, t.table_name, t.row_count
			ORDER BY t.table_id
		");                                                                  // Načtené tabulky a počty sloupců

		$hdr_summary = htmlspecialchars($this->phrase('hdr_phase1_summary', 'Kontrola načteného balíčku (Fáze 1)')); // Nadpis rekapitulace
		$th_param = htmlspecialchars($this->phrase('th_param_code', 'Parametr balíčku')); // Záhlaví parametru
		$th_pval  = htmlspecialchars($this->phrase('th_param_val', 'Hodnota'));           // Záhlaví hodnoty
		$th_tname = htmlspecialchars($this->phrase('th_table_name', 'Načtená tabulka'));  // Záhlaví tabulky
		$th_tcols = htmlspecialchars($this->phrase('th_col_count', 'Počet sloupců'));     // Záhlaví počtu sloupců
		$th_trows = htmlspecialchars($this->phrase('th_row_count', 'Počet řádků'));       // Záhlaví počtu řádků

		$p_html = '';                                                        // HTML řádků parametrů
		if (is_array($params_rows)) {                                        // Průchod načtenými parametry
			foreach ($params_rows as $pr) {                                  // Zpracování parametru
				$pk = (string)$pr['parameter_code'];                         // Kód parametru
				$pv = (string)$pr['parameter_value'];                        // Hodnota parametru
				$safe_pk = htmlspecialchars($pk);                            // Ošetřený kód parametru
				$safe_pv = htmlspecialchars($pv);                            // Ošetřená hodnota parametru

				if ($pk === 'target_status' AND !$this->is_system_package) { // U nesystémového balíčku umožníme přepnutí režimu F/A
					$sel_f = ($pv === 'F') ? 'selected' : '';                // Označení volby F
					$sel_a = ($pv === 'A') ? 'selected' : '';                // Označení volby A
					$opt_f = htmlspecialchars($this->phrase('opt_status_forward', 'Uložit do návrhů ke schválení (F)')); // Popisek F
					$opt_a = htmlspecialchars($this->phrase('opt_status_direct', 'Přímý přepis schválených záznamů (A)')); // Popisek A
					$val_cell = "<select name=\"override_param[target_status]\" style=\"padding: 4px;\"><option value=\"F\" {$sel_f}>{$opt_f}</option><option value=\"A\" {$sel_a}>{$opt_a}</option></select>"; // Roletka
				} else {
					$val_cell = "<span style=\"font-family: monospace;\">{$safe_pv}</span>"; // Statický výpis hodnoty
				}
				$p_html .= "<tr><td><strong>{$safe_pk}</strong></td><td>{$val_cell}</td></tr>\n"; // Řádek tabulky parametrů
			}
		}

		$t_html = '';                                                        // HTML řádků načtených tabulek
		if (is_array($tables_rows)) {                                        // Průchod načtenými tabulkami
			foreach ($tables_rows as $tr) {                                  // Zpracování řádku statistiky tabulky
				$safe_tn = htmlspecialchars((string)$tr['table_name']);      // Ošetřený název tabulky
				$c_cnt = (int)$tr['col_count'];                              // Počet sloupců tabulky
				$r_cnt = (int)$tr['row_count'];                              // Počet řádků tabulky
				$t_html .= "<tr><td><strong>{$safe_tn}</strong></td><td>{$c_cnt}</td><td><strong>{$r_cnt}</strong></td></tr>\n"; // Řádek statistiky
			}
		}

		$can_proceed = ($this->rqm->get_severity() < 3);                     // Zda lze pokračovat do Fáze 2
		$btn_run = new abstract_button('btn_run_phase2', 'Spustit import do databáze (Fáze 2)', 'abstract_csv_package', '', 'btn-success'); // Tlačítko Fáze 2
		$btn_run->set_type('submit')->set_name_value('btn_run_phase2', '1')->set_disabled(!$can_proceed); // Deaktivace při chybě
		$btn_run_html = $btn_run->render();                                  // HTML tlačítka Fáze 2

		return <<<HTML
		<div class="csv-import-summary-box" style="margin-bottom: 25px;">
			<h2 style="color: #004488; font-size: 17px; margin: 0 0 12px 0;">{$hdr_summary}</h2>
			<div style="margin-bottom: 15px;">{$this->rqm}</div>
			<form method="post" action="{$safe_action}">
				<input type="hidden" name="package_code" value="{$safe_code}">
				<div style="display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 15px;">
					<div style="flex: 1; min-width: 300px;">
						<table class="md-table">
							<thead><tr><th>{$th_param}</th><th>{$th_pval}</th></tr></thead>
							<tbody>{$p_html}</tbody>
						</table>
					</div>
					<div style="flex: 1; min-width: 300px;">
						<table class="md-table">
							<thead><tr><th>{$th_tname}</th><th>{$th_tcols}</th><th>{$th_trows}</th></tr></thead>
							<tbody>{$t_html}</tbody>
						</table>
					</div>
				</div>
				<div>{$btn_run_html}</div>
			</form>
		</div>
HTML;
	}

	/**
	 * FÁZE 2 IMPORTU: Uloží případné povolené změny parametrů do `session_import_parameter`
	 * a spustí databázovou proceduru `p_csv_import_{$this->package_code}` v transakci.
	 *
	 * @param array<string, mixed> $override_params Povolené upravené parametry z formuláře Fáze 1
	 * @return bool True pokud import proběhl úspěšně a transakce byla potvrzena (COMMIT)
	 */
	public function run_import(array $override_params = []): bool {          // Fáze 2: Spuštění procedury p_csv_import_*
		global $SID;                                                         // Identifikátor relace
		$safe_sid = charliteral($SID, 50);                                   // SQL literál relace

		// U nesystémových balíčků povolíme aktualizaci parametru target_status ('F' vs. 'A')
		if (!$this->is_system_package AND isset($override_params['target_status'])) { // Kontrola změny target_status
			$new_status = ((string)$override_params['target_status'] === 'A') ? 'A' : 'F'; // Validace hodnoty A nebo F
			$safe_st = charliteral($new_status, 1);                          // SQL literál cílového stavu
			sqlrun("UPDATE session_import_parameter SET parameter_value = {$safe_st} WHERE wwwsession = {$safe_sid} AND parameter_code = 'target_status'"); // Aktualizace
		}

		// Ověření existence uložené procedury p_csv_import_<package_code> v databázi
		$proc_name = 'p_csv_import_' . $this->package_code;                  // Název cílové SQL procedury
		$safe_proc = charliteral($proc_name, 128);                           // SQL literál názvu procedury
		$proc_row = sqlfirstrow("SELECT OBJECT_ID({$safe_proc}, 'P') AS proc_id"); // Dotaz na existenci procedury

		if (empty($proc_row) OR empty($proc_row['proc_id'])) {               // Pokud procedura v DB neexistuje
			$this->rqm->add_message($this->phrase('err_proc_not_found', 'Uložená procedura pro zpracování balíčku nebyla v databázi nalezena.'), 3)
				->setobject('Procedura', $proc_name);                        // Zápis chyby chybějící procedury
			return false;                                                    // Ukončení bez spuštění
		}

		// Spuštění procedury v transakci se sběrem zpráv přes request_message
		sqlrun("BEGIN TRAN; EXEC p_request_messages_start @reset = 1;");     // Zahájení transakce a inicializace zpráv
		sqlrun("EXEC {$proc_name}");                                         // Spuštění samotné importní procedury balíčku
		$this->rqm->add_from_db();                                           // Načtení zpráv vygenerovaných procedurou

		if ($this->rqm->get_severity() < 3) {                                // Pokud při běhu procedury nevznikla kritická chyba
			sqlrun("EXEC p_csv_clear_session_import; COMMIT;");              // Vyčištění staging tabulek a potvrzení transakce
			$this->rqm->add_message($this->phrase('msg_import_committed', 'Import balíčku byl úspěšně dokončen a uložen (Commit).'), 1)
				->setobject('Balíček', $this->package_code);                 // Potvrzovací zpráva
			return true;                                                     // Úspěšné dokončení importu
		}

		sqlrun("ROLLBACK;");                                                 // Stornování transakce při chybě
		$this->rqm->add_message($this->phrase('err_import_rolled_back', 'Import balíčku byl stornován kvůli chybám (Rollback).'), 3)
			->setobject('Balíček', $this->package_code);                     // Chybová zpráva o rollbacku
		return false;                                                        // Neúspěch importu
	}
}