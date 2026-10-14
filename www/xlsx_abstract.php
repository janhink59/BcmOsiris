<?php
/**
 * =============================================================================
 * Verze: 2026-10-14 22:30
 * Soubor: xlsx_abstract.php
 * Třída: xlsx_abstract
 * Účel: Abstraktní předek pro všechny validační a konfigurační třídy
 *       excelovských importních balíčků (xlsx_*).
 *
 * Vazby na okolí:
 * - Soubor registruje autoloader pro potomky s prefixem xlsx_ (např. xlsx_meta_object
 *   v souboru xlsx_meta_object.php), které dynamicky instancuje excel_reader::prepare_package().
 * - Třída přijímá v konstruktoru instanci třídy excel_reader (z excel_reader.php)
 *   a asociativní pole prvního řádku řídicí záložky CONTENT_INFO.
 * - Volá metodu $reader->setDataType() pro vynucení přítomnosti povinných
 *   tabulek a sloupců a pro konverzi jejich datových typů.
 * - Využívá třídu request_message (z html_classes.php) pro zápis chybových
 *   a stavových zpráv.
 * - Využívá funkce sqlfirstrow() a charliteral() z knihovny OsirisLib.php
 *   pro validaci kódů jazyků (language, second_language) proti tabulce [language].
 *
 * Změny:
 * 2026-10-14 - Refaktoring do PHP 8.3 (strict_types, typované vlastnosti a metody).
 *            - Doplněna validace povinného sloupce language a volitelného
 *              second_language v CONTENT_INFO proti databázové tabulce language.
 *            - Přidán autoloader pro samostatné soubory balíčků xlsx_*.php.
 *            - Odstraněna nepoužívaná třída xlsx_tag_attribute.
 * =============================================================================
 */

declare(strict_types=1);

// Tridy uvedene v tomto souboru zabezpecují pouze kontrolu pritomnosti tabulek a sloupcu

// Automatické načítání samostatných souborů pro konkrétní importní balíčky (např. xlsx_meta_object.php)
spl_autoload_register(function (string $class_name): void {
	if (str_starts_with($class_name, 'xlsx_')) {            // Kontrola, zda jde o třídu importního balíčku
		$file = __DIR__ . '/' . $class_name . '.php';       // Sestavení cesty k souboru ve stejném adresáři
		if (is_file($file)) {                               // Ověření fyzické existence souboru na disku
			require_once $file;                             // Načtení definice třídy balíčku
		}
	}
});

abstract class xlsx_abstract {

	public excel_reader $reader;                            // Reference na nadřízenou instanci čteče Excelu
	public array $mandatory_tables = [];                    // Seznam povinných záložek registrovaných balíčkem
	public string $last_table = '';                         // Naposledy použitá tabulka při řetězení setDataType()
	public string $package_code = '';                       // Kód balíčku načtený z CONTENT_INFO
	public string $package_name = '';                       // Lidsky čitelný název balíčku nastavený v potomkovi
	public string $import_name = '';                        // Výsledný název importu pro výpis a logování
	public string $description = '';                        // Popis obsahu balíčku z CONTENT_INFO
	public string $version_date = '';                       // Datum verze balíčku z CONTENT_INFO
	public string $language = '';                           // Povinný primární kód jazyka dat z CONTENT_INFO
	public string $second_language = '';                    // Volitelný druhý kód jazyka pro sloupce s příponou _l
	public string $import_origin = '';                      // Volitelná identifikace autora/původu dat z CONTENT_INFO
	public array $parameters = [];                          // Doplňkové parametry balíčku
	public bool $prepared = false;                          // Příznak dokončení přípravy balíčku
	public array $content = [];                             // Surová data prvního řádku záložky CONTENT_INFO
	public object $rqm;                                     // Instance request_message pro sběr validačních zpráv

	/**
	 * Konstruktor provede základní validaci řídicí záložky CONTENT_INFO
	 * a následně zavolá metodu prepare() konkrétního potomka.
	 *
	 * @param excel_reader $reader       Instance čteče XLSX souboru.
	 * @param array        $content_info První datový řádek ze záložky CONTENT_INFO.
	 */
	final public function __construct(excel_reader $reader, array $content_info) {
		$this->rqm = new request_message();                 // Inicializace objektu pro logování zpráv
		$this->content = $content_info;                     // Uložení řádku z CONTENT_INFO
		$this->package_code = (string)($content_info['package_code'] ?? '');       // Kód importního balíčku
		$this->language = (string)($content_info['language'] ?? '');               // Primární jazyk balíčku
		$this->second_language = (string)($content_info['second_language'] ?? ''); // Volitelný druhý jazyk
		$this->import_origin = (string)($content_info['import_origin'] ?? '');     // Volitelný původ importu
		$this->description = (string)($content_info['description'] ?? '');         // Popis balíčku
		$this->version_date = (string)($content_info['version_date'] ?? '');       // Datum verze balíčku
		$this->reader = $reader;                            // Uložení reference na čteč Excelu
		$this->mandatory_tables = [];                       // Vyčištění seznamu povinných tabulek
		$this->parameters = [];                             // Vyčištění pole parametrů

		// Registrace povinných sloupců v řídicí záložce CONTENT_INFO
		$this->setDataType('package_code,language,description', 'varchar', 'CONTENT_INFO');
		$this->setDataType('version_date', 'date', 'CONTENT_INFO');

		// Pokud záložka CONTENT_INFO obsahuje i volitelné sloupce, zaregistrujeme jejich datový typ
		$info_cols = $this->reader->data['CONTENT_INFO']['column_list'] ?? []; // Seznam sloupců v CONTENT_INFO
		if (in_array('second_language', $info_cols, true)) {
			$this->setDataType('second_language', 'varchar', 'CONTENT_INFO');
		}
		if (in_array('import_origin', $info_cols, true)) {
			$this->setDataType('import_origin', 'varchar', 'CONTENT_INFO');
		}

		//$this->m=new request_message();

		// Kontrola vyplnění povinných hodnot v prvním řádku CONTENT_INFO
		if ($this->description === '') {
			$this->rqm->add_message("Missing mandatory value in CONTENT_INFO", 3)->setobject("Column", "description");
		}
		if ($this->version_date === '') {
			$this->rqm->add_message("Missing mandatory value in CONTENT_INFO", 3)->setobject("Column", "version_date");
		}
		if ($this->language === '') {
			$this->rqm->add_message("Missing mandatory value in CONTENT_INFO", 3)->setobject("Column", "language");
		} else {
			// Ověření existence primárního jazyka v číselníku language
			$lang_row = sqlfirstrow("SELECT [language] FROM [language] WHERE [language] = " . charliteral($this->language));
			if (empty($lang_row)) {
				$this->rqm->add_message("Invalid language code in CONTENT_INFO (not found in table language)", 3)->setobject("Column", "language");
			}
		}

		// Pokud je zadán druhý jazyk, ověříme jeho platnost a odlišnost od primárního jazyka
		if ($this->second_language !== '') {
			if ($this->second_language === $this->language) {
				$this->rqm->add_message("Second language in CONTENT_INFO cannot be identical to primary language", 3)->setobject("Column", "second_language");
			} else {
				$sec_row = sqlfirstrow("SELECT [language] FROM [language] WHERE [language] = " . charliteral($this->second_language));
				if (empty($sec_row)) {
					$this->rqm->add_message("Invalid second_language code in CONTENT_INFO (not found in table language)", 3)->setobject("Column", "second_language");
				}
			}
		}

		$this->reader->package_ready = ($this->rqm->get_severity() <= 2); // Nastavení příznaku připravenosti
		$this->prepare();                                   // Spuštění definice záložek a sloupců v potomkovi
		$this->import_name = ($this->package_name !== '') ? $this->package_name : "Import {$this->package_code}"; // Určení názvu importu

		if ($this->rqm->get_severity() > 2) {               // Kontrola, zda při přípravě nevznikly kritické chyby
			$this->reader->package_ready = false;           // Zablokování spuštění balíčku při chybě
			$this->rqm->add_message("Errors detected");     // Zápis souhrnné informace o chybách
			return;
		}

		$this->rqm->add_message("Import processes", 1)
			->setobject("PHP CLASS", get_class($this), 2);
	}

	/**
	 * Abstraktní metoda, ve které potomek definuje povinné tabulky, sloupce a jejich typy.
	 */
	abstract public function prepare(): void;

	/**
	 * Nastaví datový typ sloupce (nebo seznamu sloupců) a zařadí tabulku mezi povinné.
	 *
	 * @param string|array $columns   Název sloupce nebo čárkami oddělený seznam sloupců.
	 * @param string       $type      Požadovaný SQL datový typ ('varchar', 'bit', 'date', ...).
	 * @param string       $table     Název záložky (pokud je prázdný, použije se poslední zadaná).
	 * @param string       $msgdetail Doplňující text pro chybovou hlášku při absenci sloupce.
	 * @return self                   Vrací instanci pro plynulé řetězení (fluent interface).
	 */
	public function setDataType(string|array $columns, string $type, string $table = '', string $msgdetail = ''): self {
		if ($table === '') {
			$table = $this->last_table;                     // Převzetí názvu naposledy použité tabulky
		}
		if ($msgdetail !== '') {
			$this->reader->setDataType($columns, $type, $table, $msgdetail); // Volání s explicitním detailem zprávy
		} else {
			$this->reader->setDataType($columns, $type, $table);             // Volání s výchozím detailem zprávy
		}
		$this->last_table = $table;                         // Uložení názvu tabulky pro další volání v řetězci
		$this->mandatory_tables[$table] = $table;           // Zařazení tabulky do seznamu povinných tabulek balíčku
		return $this;                                       // Vrácení instance pro řetězení metod
	}

	/**
	 * Vrátí nejvyšší zjištěnou závažnost zpráv v logu.
	 *
	 * @return int Maximální hodnota severity.
	 */
	public function get_severity(): int {
		return (int)$this->rqm->get_severity();             // Získání nejvyšší závažnosti z request_message
	}

	/**
	 * Volitelná metoda pro specifické post-processing operace v PHP.
	 */
	public function run(): void {
	}
}