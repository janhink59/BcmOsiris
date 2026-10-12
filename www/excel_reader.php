<?php

declare(strict_types=1);

/**
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
		$this->rqm = new request_message();
		$this->inputFileName = $inputFileName;
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
		$this->msg_count++;
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
		$this->import_mode = $import_mode;
		return $this;
	}
	
	/**
	 * Zavolá SQL proceduru pro smazání starých dočasných tabulek (aby nedošlo ke kolizi).
	 *
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function drop_temptables(): self {
		if ($this->temptables_dropped) {
			return $this;
		}
		
		sqlrun("execute p_drop_excel_tables");
		$this->temptables_dropped = true;
		
		return $this;
	}
	
	/**
	 * Hlavní motor třídy. Přečte všechny záložky proudově, načte hodnoty a určí strukturu tabulek.
	 * V této fázi se všechna data ukládají do obřího pole v paměti a měří se jejich délky pro SQL.
	 *
	 * @param array|null $ref Volitelná reference, pokud chceme pole vytáhnout i ven.
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function get_data(&$ref = []): self {
		global $charset;
		
		$ref = [];
		$this->data = &$ref;
		
		$reader = new Reader();
		$reader->open($this->inputFileName);
		
		foreach ($reader->getSheetIterator() as $sheet) {
			$name = trim($sheet->getName());
			$name = iconv('utf-8', $charset, $name);
			
			// Ignorování chybně nebo bizarně pojmenovaných listů (např. se závorkami nebo mezerami)
			if (preg_match('/[^a-zA-Z0-9_]/', $name)) {
				continue;
			}
			
			$table = [
				'rows'                  => [],
				'column_lengths'        => [],
				'column_types'          => [],
				'column_list'           => [],
				'mandatory_column_list' => [],
			];
			
			$colcount = 0;
			$colnames = [];
			
			$rowcount = 0;
			$mimo = 0;
			$in_table = true;
			$empty_rows_after_table = 0;
			
			// Streamujeme řádky jeden po druhém (snížení nároků na RAM při čtení XML struktur)
			foreach ($sheet->getRowIterator() as $rowObj) {
				
				$cells = $rowObj->cells;
				$cellCount = count($cells);
				
				// Fáze 1: Načtení hlavičky (názvy sloupců) z prvního nalezeného neprázdného řádku
				if ($rowcount === 0) {
					for ($col = 0; $col < $cellCount; $col++) {
						$v = $this->formatCellValue($cells[$col] ?? null);
						if ($v === '') {
							break;          // Nalezen prázdný sloupec = konec hlavičky
						}
						
						// Očištění názvu sloupce, aby nevyžadoval hranaté závorky v SQL
						$safe_cn = preg_replace('/[^a-zA-Z0-9_]/', '', $v);
						if ($safe_cn === '') {
							$safe_cn = 'col_' . $col;
						}
						
						$colnames[$col] = $safe_cn;
						$table['column_types'][$safe_cn] = 'varchar'; 
						$table['column_lengths'][$safe_cn] = 0;       // Inicializace pro budoucí měření max. délky
						$colcount++;
					}
					
					// Pokud jsme něco našli, posuneme počitadlo řádků
					if ($colcount > 0) {
						$rowcount++;
					}
					continue;
				}
				
				// Fáze 3 (po skončení tabulky): Skenování prázdných řádků pro detekci odpadu (mimo)
				if (!$in_table) {
					$empty_rows_after_table++;
					if ($empty_rows_after_table > 10) {
						break;              // Optimalizace: už dál nehledáme a skočíme na další list
					}
					
					if (!$mimo) {
						for ($col = 0; $col < $cellCount && $col < $colcount + 10; $col++) {
							if ($this->formatCellValue($cells[$col] ?? null) !== '') {
								$mimo = 1;
								break;
							}
						}
					}
					continue;                 // Tohle byl už jen odpadkový řádek, nepůjdeme do zpracování dat
				}
				
				// Fáze 2: Čtení samotných datových řádků
				$v_first = $this->formatCellValue($cells[0] ?? null);
				
				// Kontrola prvního sloupce - prázdná buňka znamená konec tabulky
				if ($v_first === '') {
					$in_table = false;
					// Rovnou prozkoumáme zbytek aktuálního prázdného řádku, jestli tam někdo nepsal "mimo" tabulku
					if (!$mimo) {
						for ($j = 1; $j < $cellCount && $j < $colcount + 10; $j++) {
							if ($this->formatCellValue($cells[$j] ?? null) !== '') {
								$mimo = 1;
								break;
							}
						}
					}
					continue;
				}
				
				$rowcount++;
				$row = [];
				
				for ($col = 0; $col < $colcount; $col++) {
					$cn = $colnames[$col];
					$v = $row[$cn] = $this->formatCellValue($cells[$col] ?? null);

					// Průběžná detekce "odpadu" vedle sloupců tabulky
					if (!$mimo && $col === $colcount - 1 && $cellCount > $colcount) {
						for ($j = $colcount; $j < $cellCount && $j < $colcount + 10; $j++) {
							if ($this->formatCellValue($cells[$j] ?? null) !== '') {
								$mimo = 1;
								break;
							}
						}
					}

					if ($v === '') {
						continue;
					}
					
					// Dynamické zjišťování maximální délky textu pro cílový SQL typ Varchar(N)
					$len = strlen((string)$v);
					if ($len > $table['column_lengths'][$cn]) {
						$table['column_lengths'][$cn] = $len;
					}
					
					$type = &$table['column_types'][$cn];
					
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
								$type = 'varchar'; 
								break; 
							}
							if ($fm = fmod((float)$il, 1)) { 
								$type = 'float'; 
							} else {
								break;
							}
						case 'float':
							if (is_numeric($v)) {
								break;
							}
							$type = 'varchar';
					}
				}
				$table['rows'][] = $row;      // Nasypání zformátovaného řádku do hlavní paměťové struktury
			}
			
			$table['column_list'] = $colnames;
			$table['row_count'] = count($table['rows']);
			$table['column_count'] = $colcount;
			$table['mimo'] = $mimo;
			$ref[$name] = $table;
		}
		
		$reader->close();
		
		// Nastavení výchozích datových typů pro systémové/běžné sloupce
		$this
			->setDataType("date_modified", "datetime")
			->setDataType("date_created", "datetime")
			->setDataType("version_date", "date")
			->setDataType("valid_from", "date")
			->setDataType("valid_to", "date")
			->setDataType("removed", "bit")
			->setDataType("inactive", "bit");
			
		return $this;
	}
	
	/**
	 * Zformátuje hodnotu buňky do čistého textu. 
	 * Pokud najde vzorec (FormulaCell), vyextrahuje předpočítanou hodnotu.
	 *
	 * @param Cell|null $cell Hodnota buňky přímo z OpenSpout.
	 * @return string Vrací vždy očištěný string (nebo prázdný string, pokud je buňka prázdná).
	 */
	public function formatCellValue(?object $cell): string {
		global $charset;
		
		if (!$cell) {
			return '';
		}
		
		// Detekce vzorce a získání jeho předpočítaného výsledku
		if ($cell instanceof FormulaCell) {
			$v = $cell->getComputedValue();
		} else {
			$v = $cell->getValue();
		}
		
		// OpenSpout vrací datumy nativně jako DateTime objekty
		if ($v instanceof \DateTimeInterface) {
			$v = $v->format('Y-m-d H:i:s');
		} elseif ($v instanceof \DateInterval) {
			// Pojistka pro případ, že buňka obsahuje čistý čas/duration (např. 14:30)
			$v = $v->format('%H:%I:%S');
		} else {
			$v = (string)$v;
		}
		
		// Nahrazení tvrdých mezer (NBSP, \xC2\xA0) klasickou mezerou, aby fungoval trim()
		$v = str_replace("\xC2\xA0", ' ', $v);
		$v = trim(iconv('utf-8', "$charset//TRANSLIT//IGNORE", $v));

		if ($v == 'NULL') {
			$v = '';
		}
		
		// Odstranění Excel XML artefaktu pro Carriage Return a sjednocení line-breaků
		$v = str_replace("_x000D_", "", $v);
		$v = str_replace("\r", "", $v);     // Vyčištění klasického CR znaku, zbyde jen \n
		$v = str_replace(["<br />", "<br/>", "<br>"], "\n", $v);
		
		return $v;
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
			$colname = explode(',', $colname);
		}
		
		// Podpora rekurze pro pole názvů sloupců
		if (is_array($colname)) {
			foreach ($colname as $cn) {
				$this->setDataType(trim((string)$cn), $datatype, $tabname, $msgdetail);
			}
			return $this;
		}
		
		// Kontrola, zda nechybí celá povinná tabulka (záložka)
		if ($tabname && !array_key_exists($tabname, $this->data)) {
			$this->log_message("Mandatory table is missing", 3)->setobject($tabname, $colname)->setdetail($msgdetail);
			return $this;
		}
		
		foreach ($this->data as $tn => &$table) {
			if ($tn == $tabname || $tabname == '') {
				
				// Kontrola přítomnosti povinného sloupce
				if ($tabname) {
					$table['mandatory_column_list'][$colname] = $colname;
					if (!in_array($colname, $table['column_list'])) {
						$this->log_message("Mandatory column is missing", 3)->setobject($tn, $colname)->setdetail($msgdetail);
					}
				}
				
				// Transformace hodnot v již načtených datech na požadovaný typ
				foreach ($table['column_list'] as $cn) {
					if ($cn == $colname) {
						$table['column_types'][$cn] = $datatype;
						foreach ($table['rows'] as $row_number => &$row) {
							$v = $row[$cn];
							switch ($datatype) {
								case 'date':
								case 'datetime':
								case 'smalldatetime':
									// Voláme naši interní metodu pro převod data
									$row[$cn] = $this->excel_date_to_odbc($v);
									break;
								case 'bit':
									$row[$cn] = $v ? '1' : '0';
									break;
								default:
									continue 2;         // Rychlé přeskočení pro varchar atd.
							}
						}
					}
				}
			}
		}
		return $this;
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
		global $logSqlCmdList, $sqlcmdlist;
		
		if ($this->rqm->get_severity() > 2 && $this->import_mode !== '0') {
			return $this;
		}
		
		$this->drop_temptables();                // Úklid případných zbytků
		$logSqlCmdList = 0;
		
		foreach ($this->data as $tn => $table) {
			// Skládáme název cílové tabulky pro SQL bez hranatých závorek
			$dbt = $prefix . $tn;
			$cols = $cols_insert = $unique_cols = [];
			
			// Sestavení definic sloupců pro CREATE TABLE
			foreach ($table['column_list'] as $cn) {
				$ct = $table['column_types'][$cn];
				if ($ct == 'varchar') {
					// Zdvojnásobení zjištěné délky jako prevence proti oříznutí multibyte (UTF-8) znaků
					// a přidání rezervy 100 znaků pro bezpečné přesuny dat uvnitř SQL procedur
					$len = ($table['column_lengths'][$cn] * 2) + 100;
					
					// Pojistka pro limity SQL Serveru a prázdné sloupce
					if ($len > 8000) {
						$len = "max";
					} elseif ($table['column_lengths'][$cn] == 0) {
						$len = 255;              // Pojistka pro zcela prázdné sloupce
					}
					$ct .= "($len)";
				}
				
				// Názvy sloupců do definice také posíláme rovnou bez závorek
				$cols[] = "$cn $ct";
				$cols_insert[] = $cn;
				
				// Kontrola na duplicitu názvů sloupců (ignoruje velikost písmen)
				$lcn = strtolower($cn);
				if (array_key_exists($lcn, $unique_cols)) {
					$cols = [];
					$this->log_message("Duplicita", 3)->setobject('Sloupec na záložce', "$tn.$cn");
					break;
				}
				$unique_cols[$lcn] = $cn;
			}
			
			// Generování CREATE TABLE a masivní INSERT
			if ($cols) {
				$sql = "create table $dbt(" . implode(', ', $cols) . ")";
				$sqlcmdlist .= "\n$sql";
				sqlrun($sql);                    // Spuštění CREATE TABLE
				
				if ($table['row_count']) {
					foreach ($table['rows'] as $row) {
						$vals = [];
						foreach ($table['column_list'] as $cn) {
							$ct = $table['column_types'][$cn];
							$v = $row[$cn];
							
							// Formátování literálů pro SQL v závislosti na explicitním typu
							switch ($ct) {
								case 'bigint': 
									$v = intliteral($v); 
									break;
								case 'uniqueidentifier': 
									$v = guidliteral($v); 
									break;
								default:
									$v = charliteral($v);       // Výchozí zabalení do apostrofů pro text a datumy
							}
							$vals[] = $v;
						}
						sqlrun("insert into $dbt values(" . implode(", ", $vals) . ")");
						$sqlcmdlist="";
					}
				}
			}
		}
		
		// Potvrzení transakce, pokud nějaké zbyly z externích funkcí
		sqlrun("while @@trancount>0 commit");
		return $this;
	}
	
	/**
	 * Čte systémovou záložku 'CONTENT_INFO', vyhledá implementační třídu pro balíček 
	 * a zkontroluje existenci SQL procedury v databázi.
	 *
	 * @return self Vrací instanci třídy pro řetězení.
	 */
	public function prepare_package(): self {
		$this->package_ready = false;
		
		// Pokus o nalezení záložky CONTENT_INFO
		if (!($info = &array_item_ref($this->data, 'CONTENT_INFO'))) {
			// Žádná zpráva, absence je v pořádku - tabulky se prostě jen nalijí bez následné procedury
		} else {
			$row = array_item($info['rows'], 0, []);
			$this->package_code = $package_code = array_item($row, 'package_code');
			
			if ($package_code) {
				if (class_exists(($class = "xlsx_$package_code"))) {
					$this->package_class = new $class($this, $row);
					
					// Kontrola, zda v SQL Serveru reálně existuje zpracující procedura
					$a = sqlfirstrow("select COUNT(*) cnt
						from INFORMATION_SCHEMA.ROUTINES r
						where SPECIFIC_NAME=" . charliteral("p_xlsx_$package_code") . "
							and ROUTINE_TYPE='PROCEDURE'
							and ROUTINE_CATALOG=DB_NAME()
							and ROUTINE_SCHEMA='dbo'");
					
					if ($a[0] == 1) {
						$this->package_ready = true;
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
		return $this;
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
			$this->rqm->add_from_db();
			$this->log_message("Procedura provedena", 1);
			
			// Rozhodování o Commit / Rollback
			if ($import_mode === '2' && $this->rqm->get_severity() < 3) {
				sqlrun("commit");
			} else {
				$nep = $this->rqm->get_severity() >= 3;
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
		return false;
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
			return (string)$dta;
		}
		
		// 2. Fallback pro surová čísla (pokud v buňce zůstal čistý Excel float)
		if (!is_numeric($dta)) {
			return "";
		}
		
		// Excel datumové sériové číslo začíná 30.12.1899 (kvůli známému Lotus bugu)
		$dt = new DateTime('1899-12-30 00:00');
		$date_format = "Y-m-d";
		
		$d = (int)$dta;
		$di_format = "P{$d}D";                  // Přidání celých dnů (Period Days)
		$hours = ((float)$dta - $d) * 24;
		
		if (!$hours) {
			$di = new DateInterval($di_format);
			$dt->add($di);
			return $dt->format($date_format);   // Čistý objektový přístup
		}
		
		// Výpočet zlomků dnů na hodiny, minuty a vteřiny
		$h = (int)$hours;
		$minutes = ($hours - $h) * 60;
		$m = (int)$minutes;
		
		// round() řeší nešvary floating-point aritmetiky v PHP (např. 59.9999 zaokrouhlí na 60)
		$seconds = round(($minutes - $m) * 60); 
		$s = (int)$seconds;
		
		$date_format .= " H:i:s";
		$di_format .= "T{$h}H{$m}M{$s}S";       // Time Hours Minutes Seconds
		
		$di = new DateInterval($di_format);
		$dt->add($di);
		return $dt->format($date_format);
	}
}