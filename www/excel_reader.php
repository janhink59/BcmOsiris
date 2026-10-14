<?php

declare(strict_types=1);

/**
 * =============================================================================
 * Verze: 2026-10-14 13:50
 * Soubor: excel_reader.php
 * Třída: excel_reader
 *
 * Vazby na okolí:
 * - Volána z UI modulu page_excel_reader.php při zpracování nahraného XLSX souboru.
 * - Využívá globální proměnné pro znakovou sadu a logování SQL příkazů a funkce
 *   sqlrun(), sqlfirstrow(), charliteral(), intliteral(), guidliteral(),
 *   array_item(), array_item_ref() z knihovny OsirisLib.php.
 * - Využívá třídu request_message pro sběr a zobrazení validačních a databázových zpráv.
 * - V metodě prepare_package() dynamicky instancuje potomky třídy xlsx_abstract
 *   (např. xlsx_meta_object) podle hodnoty package_code ze záložky CONTENT_INFO.
 * - Na SQL Serveru volá procedury p_drop_excel_tables, p_request_messages_start
 *   a příslušnou balíčkovou proceduru p_xlsx_<package_code>.
 * =============================================================================
 *
 * Třída pro dynamické načítání dat z MS Excel (XLSX) a jejich import do MS SQL Serveru.
 *
 * Zajišťuje:
 * 1. Přečtení Excelu přes úspornou knihovnu OpenSpout.
 * 2. Analýzu dat, ořezání prázdných znaků a odhad/konverzi datových typů.
 * 3. Automatické generování a naplnění dočasných (staging) tabulek v databázi.
 * 4. Spuštění obslužné SQL procedury pro finální zpracování dat v databázi.
 *
 * Změny:
 * 2026-10-12 - Přidána ochrana paměti omezující počet chybových zpráv na 500.
 *            - Striktní validace názvů tabulek a sloupců (pouze alfanumerické znaky a podtržítko),
 *              odstranění závislosti na hranatých závorkách [ ] při generování SQL.
 *            - Neplatně pojmenované záložky (např. s mezerou nebo závorkou) jsou zcela ignorovány.
 *            - Sjednoceny názvy systémových sloupců na snake_case (date_created, date_modified).
 *            - Typování property $import_mode sjednoceno výhradně na string.
 * 2026-10-14 - Navrácena standardní přípona '$' (chr(36)) na konec názvů generovaných
 *              staging tabulek v save_to_tables() pro kompatibilitu s p_drop_excel_tables.
 *            - Opravena kritická chyba v run_package(): doplněno chybějící volání
 *              sqlrun("rollback") při stornování transakce (režim '1' nebo při chybě).
 *            - Rozdělení vícenásobných přiřazení na samostatné řádky s inline komentáři.
 */

// Pro použití OpenSpout je nutný Composer autoloader
require_once 'vendor/autoload.php';

use OpenSpout\Reader\XLSX\Reader;
use OpenSpout\Common\Entity\Cell;
use OpenSpout\Common\Entity\Cell\FormulaCell;

class excel_reader {
	
	public string $inputFileName;               // Cesta k souboru
	public array $data = [];                    // Referenční dvojrozměrné pole s načtenými daty ze všech listů
	public array $datatypes = [];               // Pole specifikovaných datových typů
	public ?string $package_code = null;        // Kód importního balíčku (načítá se ze záložky CONTENT_INFO)
	public bool $package_ready = false;         // Flag určující, zda je balíček připraven ke spuštění
	public ?object $package_class = null;       // Instance specifické obslužné třídy pro daný balíček (např. xlsx_kod)
	public bool $temptables_dropped = false;    // Flag, zda už byly smazány staré dočasné tabulky v SQL
	public object $rqm;                         // Instance třídy request_message pro logování průběhu a chyb
	public bool $prepared = false;              // Flag přípravy
	public string $import_mode = '0';           // Režim: '0'=jen zobrazit, '1'=rollback (test), '2'=commit (zápis), 'D'=distribuce
	
	private int $msg_count = 0;                 // Počitadlo pro omezení chybových zpráv v paměti

	/**
	 * Konstruktor - inicializuje logování a uloží cestu k souboru.
	 *
	 * @param string $inputFileName Cesta k analyzovanému XLSX souboru.
	 */
	public function __construct(string $inputFileName) {
		$this->rqm = new request_message();     // Inicializace objektu pro sběr zpráv
		$this->inputFileName = $inputFileName;  // Uložení cesty ke vstupnímu souboru
	}
	
	/**
	 * Interní wrapper pro přidávání zpráv do logu.
	 * Chrání RAM před vyčerpáním při masivním množství chyb z Excelu.
	 * 
	 * @param string $msg Zpráva
	 * @param int $severity Úroveň závažnosti
	 * @return object Vrací referenci pro zachování chainování (fluent interface)
	 */
	private function log_message(string $msg, int $severity = 0): object {
		$this->msg_count++;                     // Inkrementace počitadla vygenerovaných zpráv
		if ($this->msg_count <= 500) {
			return $this->rqm->add_message($msg, $severity);
		} elseif ($this->msg_count === 501) {
			return $this->rqm->add_message("Dosažen limit 500 zpráv. Další chybové zprávy byly potlačeny z důvodu úspory paměti.", 3);
		}
		
		// Pro zprávy nad limit vracíme dummy referenci, aby nespadlo navázané volání ->setobject()
		return $this->rqm;
	}
	
	/**
	 * Nastaví režim importu (Fluent interface).
	 *
	 * @param string $import_mode Režim importu ('0', '1', '2', 'D').
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function setImportMode(string $import_mode): self {
		$this->import_mode = $import_mode;      // Uložení požadovaného režimu importu
		return $this;                           // Vrácení instance pro řetězení metod
	}
	
	/**
	 * Zavolá SQL proceduru pro smazání starých dočasných tabulek (aby nedošlo ke kolizi).
	 *
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function drop_temptables(): self {
		if ($this->temptables_dropped) {        // Kontrola, zda již byly dočasné tabulky smazány
			return $this;                       // Pokud ano, krok přeskočíme
		}
		
		sqlrun("execute p_drop_excel_tables");  // Odstranění starých staging tabulek v DB
		$this->temptables_dropped = true;       // Označení, že úklid již proběhl
		
		return $this;                           // Vrácení instance pro řetězení metod
	}
	
	/**
	 * Hlavní motor třídy. Přečte všechny záložky proudově, načte hodnoty a určí strukturu tabulek.
	 * V této fázi se všechna data ukládají do obřího pole v paměti a měří se jejich délky pro SQL.
	 *
	 * @param array|null $ref Volitelná reference, pokud chceme pole vytáhnout i ven.
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function get_data(&$ref = []): self {
		global $charset;                        // Globální proměnná určující kódování aplikace
		
		$ref = [];                              // Vyčištění vstupního pole
		$this->data = &$ref;                    // Napojení vnitřního pole dat přes referenci
		
		$reader = new Reader();                 // Inicializace proudového čteče OpenSpout
		$reader->open($this->inputFileName);    // Otevření souboru XLSX ke čtení
		
		foreach ($reader->getSheetIterator() as $sheet) {
			$name = trim($sheet->getName());    // Získání názvu aktuální záložky bez okrajových mezer
			$name = iconv('utf-8', $charset, $name); // Převod názvu záložky do znakové sady systému
			
			// Ignorování chybně nebo bizarně pojmenovaných listů (např. se závorkami nebo mezerami)
			if (preg_match('/[^a-zA-Z0-9_]/', $name)) {
				continue;                       // Záložku s nepovolenými znaky zcela přeskočíme
			}
			
			$table = [                          // Inicializace struktury pro data a metadata záložky
				'rows'                  => [],  // Pole načtených řádků záložky
				'column_lengths'        => [],  // Maximální zjištěné délky hodnot po sloupcích
				'column_types'          => [],  // Datové typy jednotlivých sloupců
				'column_list'           => [],  // Seznam očištěných názvů sloupců
				'mandatory_column_list' => [],  // Seznam povinných sloupců kontrolovaných balíčkem
			];
			
			$colcount = 0;                      // Počet platných sloupců nalezených v hlavičce
			$colnames = [];                     // Mapování indexu sloupce na jeho název
			
			$rowcount = 0;                      // Počitadlo přečtených řádků v záložce
			$mimo = 0;                          // Příznak výskytu dat mimo ohraničenou tabulku
			$in_table = true;                   // Příznak, že stále čteme souvislý blok tabulky
			$empty_rows_after_table = 0;        // Počet prázdných řádků následujících po konci tabulky
			
			// Streamujeme řádky jeden po druhém (snížení nároků na RAM při čtení XML struktur)
			foreach ($sheet->getRowIterator() as $rowObj) {
				
				$cells = $rowObj->cells;        // Pole buněk aktuálního řádku
				$cellCount = count($cells);     // Celkový počet buněk v řádku
				
				// Fáze 1: Načtení hlavičky (názvy sloupců) z prvního nalezeného neprázdného řádku
				if ($rowcount === 0) {
					for ($col = 0; $col < $cellCount; $col++) {
						$v = $this->formatCellValue($cells[$col] ?? null);
						if ($v === '') {
							break;              // Nalezen prázdný sloupec = konec hlavičky
						}
						
						// Očištění názvu sloupce, aby nevyžadoval hranaté závorky v SQL
						$safe_cn = preg_replace('/[^a-zA-Z0-9_]/', '', $v);
						if ($safe_cn === '') {
							$safe_cn = 'col_' . $col; // Náhradní název sloupce při prázdném výsledku
						}
						
						$colnames[$col] = $safe_cn;               // Uložení názvu sloupce na dané pozici
						$table['column_types'][$safe_cn] = 'varchar'; // Výchozí datový typ sloupce
						$table['column_lengths'][$safe_cn] = 0;   // Inicializace pro budoucí měření max. délky
						$colcount++;                              // Zvýšení počtu nalezených sloupců
					}
					
					// Pokud jsme něco našli, posuneme počitadlo řádků
					if ($colcount > 0) {
						$rowcount++;            // Hlavička byla úspěšně načtena
					}
					continue;
				}
				
				// Fáze 3 (po skončení tabulky): Skenování prázdných řádků pro detekci odpadu (mimo)
				if (!$in_table) {
					$empty_rows_after_table++;  // Zvýšení počitadla prázdných řádků za tabulkou
					if ($empty_rows_after_table > 10) {
						break;                  // Optimalizace: už dál nehledáme a skočíme na další list
					}
					
					if (!$mimo) {               // Pokud jsme zatím nenarazili na data mimo tabulku
						for ($col = 0; $col < $cellCount && $col < $colcount + 10; $col++) {
							if ($this->formatCellValue($cells[$col] ?? null) !== '') {
								$mimo = 1;      // Nalezena hodnota pod ukončenou tabulkou
								break;
							}
						}
					}
					continue;                   // Tohle byl už jen odpadkový řádek, nepůjdeme do zpracování dat
				}
				
				// Fáze 2: Čtení samotných datových řádků
				$v_first = $this->formatCellValue($cells[0] ?? null); // Hodnota v prvním sloupci řádku
				
				// Kontrola prvního sloupce - prázdná buňka znamená konec tabulky
				if ($v_first === '') {
					$in_table = false;          // Prázdný první sloupec ukončuje čtení dat tabulky
					// Rovnou prozkoumáme zbytek aktuálního prázdného řádku, jestli tam někdo nepsal "mimo" tabulku
					if (!$mimo) {
						for ($j = 1; $j < $cellCount && $j < $colcount + 10; $j++) {
							if ($this->formatCellValue($cells[$j] ?? null) !== '') {
								$mimo = 1;      // Nalezena hodnota v řádku s prázdným prvním sloupcem
								break;
							}
						}
					}
					continue;
				}
				
				$rowcount++;                    // Započtení platného datového řádku
				$row = [];                      // Inicializace pole hodnot pro aktuální řádek
				
				for ($col = 0; $col < $colcount; $col++) {
					$cn = $colnames[$col];      // Název zpracovávaného sloupce
					$v = $this->formatCellValue($cells[$col] ?? null); // Načtení zformátované hodnoty buňky
					$row[$cn] = $v;             // Zápis hodnoty do asociativního pole řádku

					// Průběžná detekce "odpadu" vedle sloupců tabulky
					if (!$mimo && $col === $colcount - 1 && $cellCount > $colcount) {
						for ($j = $colcount; $j < $cellCount && $j < $colcount + 10; $j++) {
							if ($this->formatCellValue($cells[$j] ?? null) !== '') {
								$mimo = 1;      // Nalezena hodnota vpravo za posledním sloupcem hlavičky
								break;
							}
						}
					}

					if ($v === '') {
						continue;               // Prázdná hodnota neovlivňuje délku ani typ sloupce
					}
					
					// Dynamické zjišťování maximální délky textu pro cílový SQL typ Varchar(N)
					$len = strlen((string)$v);  // Délka aktuálního řetězce v bajtech
					if ($len > $table['column_lengths'][$cn]) {
						$table['column_lengths'][$cn] = $len; // Aktualizace maximální délky sloupce
					}
					
					$type = &$table['column_types'][$cn]; // Reference na evidovaný datový typ sloupce
					
					// Fallback logika pro detekci historických číselných typů
					switch ($type) {
						case 'varchar':
						case 'bit':
						case 'date':
						case 'datetime':
						case 'uuid':
							break;
						case 'bigint':
							if (($il = intliteral($v, 6)) == 'NULL') { 
								$type = 'varchar'; // Hodnota není číslo, degradujeme typ na varchar
								break; 
							}
							if ($fm = fmod((float)$il, 1)) { 
								$type = 'float';   // Číslo obsahuje desetinnou část, změníme na float
							} else {
								break;
							}
						case 'float':
							if (is_numeric($v)) {
								break;
							}
							$type = 'varchar';     // Hodnota není číselná, změníme na varchar
					}
				}
				$table['rows'][] = $row;           // Nasypání zformátovaného řádku do hlavní paměťové struktury
			}
			
			$table['column_list'] = $colnames;          // Uložení seznamu názvů sloupců záložky
			$table['row_count'] = count($table['rows']); // Uložení celkového počtu datových řádků
			$table['column_count'] = $colcount;         // Uložení celkového počtu sloupců
			$table['mimo'] = $mimo;                     // Uložení příznaku dat mimo tabulku
			$ref[$name] = $table;                       // Zařazení záložky do hlavního výstupního pole
		}
		
		$reader->close();                               // Uzavření čteče XLSX souboru
		
		// Nastavení výchozích datových typů pro systémové/běžné sloupce
		$this
			->setDataType("date_modified", "datetime")  // Systémové datum poslední změny
			->setDataType("date_created", "datetime")   // Systémové datum vytvoření
			->setDataType("version_date", "date")       // Datum verze balíčku v CONTENT_INFO
			->setDataType("valid_from", "date")         // Počátek platnosti záznamu
			->setDataType("valid_to", "date")           // Konec platnosti záznamu
			->setDataType("removed", "bit")             // Příznak smazání záznamu
			->setDataType("inactive", "bit");           // Příznak neaktivního záznamu
			
		return $this;                                   // Vrácení instance pro řetězení metod
	}
	
	/**
	 * Zformátuje hodnotu buňky do čistého textu. 
	 * Pokud najde vzorec (FormulaCell), vyextrahuje předpočítanou hodnotu.
	 *
	 * @param Cell|null $cell Hodnota buňky přímo z OpenSpout.
	 * @return string Vrací vždy očištěný string (nebo prázdný string, pokud je buňka prázdná).
	 */
	public function formatCellValue(?object $cell): string {
		global $charset;                        // Globální nastavení znakové sady
		
		if (!$cell) {
			return '';                          // Prázdný objekt buňky vrátí prázdný řetězec
		}
		
		// Detekce vzorce a získání jeho předpočítaného výsledku
		if ($cell instanceof FormulaCell) {
			$v = $cell->getComputedValue();     // Získání vyhodnoceného výsledku vzorce
		} else {
			$v = $cell->getValue();             // Získání přímé hodnoty buňky
		}
		
		// OpenSpout vrací datumy nativně jako DateTime objekty
		if ($v instanceof \DateTimeInterface) {
			$v = $v->format('Y-m-d H:i:s');     // Naformátování data a času pro SQL
		} elseif ($v instanceof \DateInterval) {
			// Pojistka pro případ, že buňka obsahuje čistý čas/duration (např. 14:30)
			$v = $v->format('%H:%I:%S');        // Naformátování časového intervalu
		} else {
			$v = (string)$v;                    // Přetypování ostatních hodnot na řetězec
		}
		
		// Nahrazení tvrdých mezer (NBSP, \xC2\xA0) klasickou mezerou, aby fungoval trim()
		$v = str_replace("\xC2\xA0", ' ', $v);
		$v = trim(iconv('utf-8', "$charset//TRANSLIT//IGNORE", $v));

		if ($v == 'NULL') {
			$v = '';                            // Textové 'NULL' z Excelu považujeme za prázdnou hodnotu
		}
		
		// Odstranění Excel XML artefaktu pro Carriage Return a sjednocení line-breaků
		$v = str_replace("_x000D_", "", $v);    // Odstranění XML sekvence pro CR
		$v = str_replace("\r", "", $v);         // Vyčištění klasického CR znaku, zbyde jen \n
		$v = str_replace(["<br />", "<br/>", "<br>"], "\n", $v); // Převod HTML odřádkování na LF
		
		return $v;                              // Vrácení očištěné textové hodnoty
	}
	
	/**
	 * Definuje, jaký datový typ má mít konkrétní sloupec.
	 * Voláno uživatelem nebo v závěru get_data().
	 *
	 * @param string|array $colname Název sloupce (nebo pole názvů).
	 * @param string $datatype Požadovaný datový typ SQL.
	 * @param string $tabname Specifická tabulka, pokud chceme omezit jen na ni.
	 * @param string $msgdetail Textový detail pro logování chyby.
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function setDataType(string|array $colname, string $datatype = 'varchar', string $tabname = '', string $msgdetail = 'Kontrola přítomnosti povinných sloupců'): self {
		if (is_string($colname) && strpos($colname, ',') !== false) {
			$colname = explode(',', $colname);  // Rozpad seznamu sloupců oddělených čárkou na pole
		}
		
		// Podpora rekurze pro pole názvů sloupců
		if (is_array($colname)) {
			foreach ($colname as $cn) {
				$this->setDataType(trim((string)$cn), $datatype, $tabname, $msgdetail);
			}
			return $this;                       // Vrácení instance po zpracování celého pole sloupců
		}
		
		// Kontrola, zda nechybí celá povinná tabulka (záložka)
		if ($tabname && !array_key_exists($tabname, $this->data)) {
			$this->log_message("Mandatory table is missing", 3)->setobject($tabname, $colname)->setdetail($msgdetail);
			return $this;                       // Tabulka v souboru neexistuje, ukončíme kontrolu
		}
		
		foreach ($this->data as $tn => &$table) {
			if ($tn == $tabname || $tabname == '') {
				
				// Kontrola přítomnosti povinného sloupce
				if ($tabname) {
					$table['mandatory_column_list'][$colname] = $colname; // Zařazení mezi povinné sloupce
					if (!in_array($colname, $table['column_list'])) {
						$this->log_message("Mandatory column is missing", 3)->setobject($tn, $colname)->setdetail($msgdetail);
					}
				}
				
				// Transformace hodnot v již načtených datech na požadovaný typ
				foreach ($table['column_list'] as $cn) {
					if ($cn == $colname) {
						$table['column_types'][$cn] = $datatype; // Nastavení požadovaného datového typu
						foreach ($table['rows'] as $row_number => &$row) {
							$v = $row[$cn];     // Původní hodnota buňky v řádku
							switch ($datatype) {
								case 'date':
								case 'datetime':
								case 'smalldatetime':
									// Voláme naši interní metodu pro převod data
									$row[$cn] = $this->excel_date_to_odbc($v);
									break;
								case 'bit':
									$row[$cn] = $v ? '1' : '0'; // Normalizace boolean hodnoty na 1/0
									break;
								default:
									continue 2; // Rychlé přeskočení pro varchar atd.
							}
						}
					}
				}
			}
		}
		return $this;                           // Vrácení instance pro řetězení metod
	}
	
	/**
	 * Fyzicky vytvoří staging tabulky v SQL Serveru a vloží do nich data.
	 * Bere v úvahu zjištěné maximální délky sloupců s přidanou rezervou.
	 * Očekává čisté bezpečné názvy tabulek bez potřeby [ ].
	 *
	 * @param string $prefix Prefix názvu vytvářených tabulek.
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function save_to_tables(string $prefix = 'XLSX_'): self {
		global $logSqlCmdList, $sqlcmdlist;     // Globální proměnné pro logování SQL příkazů
		
		if ($this->rqm->get_severity() > 2 && $this->import_mode !== '0') {
			return $this;                       // Při kritické chybě nezakládáme tabulky
		}
		
		$this->drop_temptables();               // Úklid případných zbytků
		$logSqlCmdList = 0;                     // Dočasné vypnutí logování jednotlivých INSERTů
		
		foreach ($this->data as $tn => $table) {
			// Skládáme název cílové tabulky pro SQL bez hranatých závorek, se znakem '$' (chr(36)) na konci
			$dbt = $prefix . $tn . chr(36);     // Výsledný název tabulky (např. XLSX_page$)
			$cols = [];                         // Pole definic sloupců pro příkaz CREATE TABLE
			$cols_insert = [];                  // Pole názvů sloupců pro vkládání
			$unique_cols = [];                  // Kontrolní pole pro odhalení duplicitních sloupců
			
			// Sestavení definic sloupců pro CREATE TABLE
			foreach ($table['column_list'] as $cn) {
				$ct = $table['column_types'][$cn]; // Zjištěný datový typ sloupce
				if ($ct == 'varchar') {
					// Zdvojnásobení zjištěné délky jako prevence proti oříznutí multibyte (UTF-8) znaků
					// a přidání rezervy 100 znaků pro bezpečné přesuny dat uvnitř SQL procedur
					$len = ($table['column_lengths'][$cn] * 2) + 100;
					
					// Pojistka pro limity SQL Serveru a prázdné sloupce
					if ($len > 8000) {
						$len = "max";           // Překročen limit 8000 bajtů, použijeme varchar(max)
					} elseif ($table['column_lengths'][$cn] == 0) {
						$len = 255;             // Pojistka pro zcela prázdné sloupce
					}
					$ct .= "($len)";            // Doplnění délky k datovému typu varchar
				}
				
				// Názvy sloupců do definice také posíláme rovnou bez závorek
				$cols[] = "$cn $ct";            // Přidání definice sloupce do pole
				$cols_insert[] = $cn;           // Přidání názvu sloupce do seznamu
				
				// Kontrola na duplicitu názvů sloupců (ignoruje velikost písmen)
				$lcn = strtolower($cn);         // Název sloupce převedený na malá písmena
				if (array_key_exists($lcn, $unique_cols)) {
					$cols = [];                 // Zrušení generování tabulky kvůli duplicitě
					$this->log_message("Duplicita", 3)->setobject('Sloupec na záložce', "$tn.$cn");
					break;
				}
				$unique_cols[$lcn] = $cn;       // Zaevidování unikátního názvu sloupce
			}
			
			// Generování CREATE TABLE a masivní INSERT
			if ($cols) {
				$sql = "create table $dbt(" . implode(', ', $cols) . ")";
				$sqlcmdlist .= "\n$sql";        // Zápis CREATE TABLE do historie příkazů
				sqlrun($sql);                   // Spuštění CREATE TABLE
				
				if ($table['row_count']) {
					foreach ($table['rows'] as $row) {
						$vals = [];             // Pole SQL literálů pro aktuální vkládaný řádek
						foreach ($table['column_list'] as $cn) {
							$ct = $table['column_types'][$cn]; // Typ aktuálního sloupce
							$v = $row[$cn];                    // Hodnota buňky
							
							// Formátování literálů pro SQL v závislosti na explicitním typu
							switch ($ct) {
								case 'bigint': 
									$v = intliteral($v);       // Převod na číselný SQL literál
									break;
								case 'uniqueidentifier': 
									$v = guidliteral($v);      // Převod na UUID SQL literál
									break;
								default:
									$v = charliteral($v);      // Výchozí zabalení do apostrofů pro text a datumy
							}
							$vals[] = $v;       // Přidání zformátované hodnoty do seznamu
						}
						sqlrun("insert into $dbt values(" . implode(", ", $vals) . ")");
						$sqlcmdlist = "";       // Vyčištění historie příkazů pro úsporu paměti
					}
				}
			}
		}
		
		// Potvrzení transakce, pokud nějaké zbyly z externích funkcí
		sqlrun("while @@trancount>0 commit");
		return $this;                           // Vrácení instance pro řetězení metod
	}
	
	/**
	 * Čte systémovou záložku 'CONTENT_INFO', vyhledá implementační třídu pro balíček 
	 * a zkontroluje existenci SQL procedury v databázi.
	 *
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function prepare_package(): self {
		$this->package_ready = false;           // Výchozí stav před ověřením balíčku
		
		// Pokus o nalezení záložky CONTENT_INFO
		if (!($info = &array_item_ref($this->data, 'CONTENT_INFO'))) {
			// Žádná zpráva, absence je v pořádku - tabulky se prostě jen nalijí bez následné procedury
		} else {
			$row = array_item($info['rows'], 0, []);              // První datový řádek v CONTENT_INFO
			$package_code = (string)array_item($row, 'package_code'); // Načtení kódu balíčku
			$this->package_code = $package_code;                  // Uložení kódu balíčku do vlastnosti objektu
			
			if ($package_code !== '') {
				$class = "xlsx_$package_code";  // Odvození názvu obslužné PHP třídy
				if (class_exists($class)) {
					$this->package_class = new $class($this, $row); // Instancování validační třídy balíčku
					
					// Kontrola, zda v SQL Serveru reálně existuje zpracující procedura
					$a = sqlfirstrow("select COUNT(*) cnt
						from INFORMATION_SCHEMA.ROUTINES r
						where SPECIFIC_NAME=" . charliteral("p_xlsx_$package_code") . "
							and ROUTINE_TYPE='PROCEDURE'
							and ROUTINE_CATALOG=DB_NAME()
							and ROUTINE_SCHEMA='dbo'");
					
					if ($a[0] == 1) {
						$this->package_ready = true; // Třída i SQL procedura existují
					} else {
						// Pouze INFO - neexistující procedura nesmí blokovat nahrání do stagingu
						$this->log_message("SQL procedura 'p_xlsx_$package_code' nebyla nalezena. Balíček nebude automaticky spuštěn.", 1);
					}
				} else {
					// Pouze INFO - neexistující modul nesmí blokovat nahrání do stagingu
					$this->log_message("Modul pro import \"$package_code\" není implementován. Data budou pouze nahrána do tabulek.", 1);
				}
			}
		}
		return $this;                           // Vrácení instance pro řetězení metod
	}
	
	/**
	 * Závěrečný krok: Spustí na SQL Serveru samotný import dat ze staging tabulek do produkčních dat.
	 *
	 * @param string $import_mode Režim běhu procedury (zápis vs test).
	 * @return void
	 */
	public function run_package(string $import_mode): void {
		// Striktní kontrola povolených stavů pro spuštění na DB.
		if (in_array($import_mode, ['1', '2'], true) && $this->package_ready && $this->rqm->get_severity() < 3) {
			// Start transakce a reset logování zpráv v databázi
			sqlrun("begin tran execute p_request_messages_start @reset=0");
			
			$this->log_message("Provádí se import")->setobject("Režim", ($import_mode === '2') ? "Write and commit" : "Write then rollback");
				
			// Zavolání obslužné procedury s příslušným módem
			sqlrun("execute p_xlsx_{$this->package_code} @import_mode=" . charliteral($import_mode));
			
			// Natažení chybových a informačních zpráv
			$this->rqm->add_from_db();          // Převzetí zpráv z tabulky request_message
			$this->log_message("Procedura provedena", 1);
			
			// Rozhodování o Commit / Rollback
			if ($import_mode === '2' && $this->rqm->get_severity() < 3) {
				sqlrun("commit");               // Potvrzení transakce při ostrém importu bez chyb
			} else {
				sqlrun("rollback");             // Stornování transakce v testovacím režimu nebo při chybě
				$nep = $this->rqm->get_severity() >= 3; // Zjištění, zda příčinou byly kritické chyby
				$m = $this->log_message("Transakce byla stornována", 3);
				if ($nep) {
					$m->setdetail("Zjištěny nepropustné chyby");
				}
			}
		}
	}
	
	/**
	 * Pomocná metoda pro UI. Zkontroluje, zda tabulka patří mezi mandatory.
	 *
	 * @param string $tn Jméno tabulky.
	 * @return bool Vrací TRUE pokud je tabulka povinná, jinak FALSE.
	 */
	public function is_mandatory_table(string $tn): bool {
		if (is_object($c = $this->package_class)) {
			return property_exists($c, 'mandatory_tables') && in_array($tn, $c->mandatory_tables);
		}
		return false;                           // Pokud třída balíčku neexistuje, tabulka není povinná
	}

	/**
	 * Převádí excelovský formát data na platný SQL datumový formát (Y-m-d H:i:s).
	 * Slouží primárně jako fallback pro staré dokumenty, kde OpenSpout nedetekuje buňku jako DateTime,
	 * ale předá nám ji jako klasický "Excel Date Serial Number" (float/int).
	 *
	 * @param string|int|float $dta Hodnota k převodu (ideálně Excel float serial, nebo string z OpenSpout).
	 * @return string Převedený datum ve string formátu.
	 */
	public function excel_date_to_odbc(string|int|float $dta): string {
		// 1. Záchyt už hotových stringů (typický výstup z OpenSpout)
		if (DateTime::createFromFormat('Y-m-d', (string)$dta) !== false
			|| DateTime::createFromFormat('Y-m-d H:i', (string)$dta) !== false
			|| DateTime::createFromFormat('Y-m-d H:i:s', (string)$dta) !== false
		) {
			return (string)$dta;                // Řetězec je již v platném SQL formátu
		}
		
		// 2. Fallback pro surová čísla (pokud v buňce zůstal čistý Excel float)
		if (!is_numeric($dta)) {
			return "";                          // Nečíselnou hodnotu nelze převést na datum
		}
		
		// Excel datumové sériové číslo začíná 30.12.1899 (kvůli známému Lotus bugu)
		$dt = new DateTime('1899-12-30 00:00'); // Počáteční datum sériové řady Excelu
		$date_format = "Y-m-d";                 // Výchozí formát bez časové složky
		
		$d = (int)$dta;                         // Celá část čísla představuje počet dnů
		$di_format = "P{$d}D";                  // Přidání celých dnů (Period Days)
		$hours = ((float)$dta - $d) * 24;       // Desetinná část převedená na hodiny
		
		if (!$hours) {
			$di = new DateInterval($di_format); // Vytvoření intervalu pouze pro dny
			$dt->add($di);                      // Přičtení dnů k počátečnímu datu
			return $dt->format($date_format);   // Čistý objektový přístup
		}
		
		// Výpočet zlomků dnů na hodiny, minuty a vteřiny
		$h = (int)$hours;                       // Celé hodiny
		$minutes = ($hours - $h) * 60;          // Zbytek převedený na minuty
		$m = (int)$minutes;                     // Celé minuty
		
		// round() řeší nešvary floating-point aritmetiky v PHP (např. 59.9999 zaokrouhlí na 60)
		$seconds = round(($minutes - $m) * 60); // Zaokrouhlené vteřiny
		$s = (int)$seconds;                     // Celé vteřiny
		
		$date_format .= " H:i:s";               // Rozšíření formátu o časovou složku
		$di_format .= "T{$h}H{$m}M{$s}S";       // Time Hours Minutes Seconds
		
		$di = new DateInterval($di_format);     // Vytvoření kompletního intervalu
		$dt->add($di);                          // Přičtení intervalu k počátečnímu datu
		return $dt->format($date_format);       // Vrácení výsledného ODBC řetězce
	}
}