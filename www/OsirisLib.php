<?php
/**
 * =============================================================================
 * Verze: 2026-10-21 15:15
 * Soubor: OsirisLib.php
 * Účel: Základní systémová a databázová knihovna BCM Osiris (SQLSRV wrapper,
 *       formátování SQL literálů, správa relace, cookies, zpracování vstupů,
 *       logování a ladicí nástroje).
 *
 * VAZBY NA OKOLÍ:
 * - Inkludována centrálně ze souboru `config.php` při každém HTTP requestu.
 * - Využívá globální proměnné `$dbconnection`, `$dbquery`, `$dbsession`, `$SID`,
 *   `$debugmode`, `$charset`, `$sqlcmdlist`, `$logSqlCmdList`, `$lastSql`.
 * - Poskytuje nízkoúrovňové databázové funkce (`sqlrun`, `fetch`, `sqlfirstrow`,
 *   `sqlarray`, `sqlarray2`, `sqlarray3`, `sqlarray_simple`) a funkce pro bezpečné
 *   skládání SQL dotazů (`charliteral`, `guidliteral`, `intliteral`, `dateliteral`)
 *   všem třídám a stránkám aplikace.
 * - Funkce `initsession()` ověřuje relaci přes proceduru `p_init_wwwsession`,
 *   obnovuje trvalé přihlášení přes tabulku `auth_tokens` a proceduru `p_set_login`
 *   a plní globální pole `$dbsession`.
 *
 * Změny:
 * 2026-10-21 15:15 - Odstraněny nepoužívané historické funkce z původního systému
 *                    (sqlpagerun, PageItem, PageTable, td1_*, td2_*, fetch_datarow,
 *                    create_phrases, check_user_access, jqteColumn atd.) a kolizní
 *                    funkce global_phrase() kolidující se třídou global_phrase.
 *                  - Striktní úprava všech řádků dle Anti-LaTeX pravidel (jeden příkaz
 *                    na řádek, náhrada || a && za OR a AND, odstranění znaku svislítka
 *                    a doplnění komentářů s českou diakritikou ke všem řádkům s $).
 * =============================================================================
 */

if (file_exists("test.php")) {
	include_once("test.php");
}
include_once("autoload.php");
if (file_exists("htmLawed.php")) {
	include_once("htmLawed.php");
}
if (file_exists("html_classes.php")) {
	include_once("html_classes.php");
}

/*
################################################################################

		Univerzální knihovna OsirisLib
		
		27.12.2010 - Změna funkce "sqlpagerun", zcela jiná struktura prvního resultu,
					 aby bylo dosaženo nezávislosti na PHP - eval
		04.08.2011 - Přidána funkce "custom_module", která zjišťuje přítomnost modulu
		21.09.2011 - Vylepšení funkce "fetch_datarow"
		19.10.2011 - funkce csv_export má nový parametr na vnucení jiných záhlaví
		02.05.2012 - funkce intliteral - přidán parametr pro počet desetinných míst
		12.06.2012 - Explicitní stanovení typu BUTTON pro jiné prohlížeče
		19.11.2012 - Umožnění zadávat číselné hodnoty s mezerami (oddělovač tisíců)
		10.09.2013 - Funkce pro podporu JSONa: JSON_ENCODE_CP, JSON_DECODE_CP, ICONV_ARRAY
		21.02.2014 - Zařazení jQuery a využití pro textarea.autosize
		24.02.2014 - Vylepšení funkce CHECK_ACCESS
		06.12.2015 - Funkce stripAphostrophes
		03.01.2016 - Propojení stejnoměnné a globální proměnné ve funkci "sessionreg"
		28.01.2016 - Přidání funkcí ramsesEncrypt a ramsesDecrypt
		14.03.2016 - Odstranění funkce "ereg" z dateliteral
		17.08.2016 - Podpora PDO driverů
		02.12.2016 - Memory leak v "csv_export()"
		04.01.2017 - Do výpisu při chybě přidán backtrace
		XX.10.2026 - REFAKTORING BCM Osiris: Odstraněna podpora pro ODBC a PDO. Ponecháno čistě SQLSRV.
					 Oprava kritického bugu inicializace relace. Odstranění result_wwwsession.
		21.10.2026 - Vyčištění od nepoužívaných legacy funkcí a sjednocení Anti-LaTeX syntaxe.
################################################################################
*/

// Funkce numberFormat nastavuje default ceske separatory, nastavuje uvodni nulu
// a neciselne hodnoty vraci beze změny
function numberFormat($n, $dec = 0, $sep = '.', $th = ' ') {                // Formátování číselné hodnoty
	if (is_numeric($n)) {                                                   // Kontrola, zda je vstup číslo
		$r = number_format((float)$n, $dec, $sep, $th);                     // Standardní zformátování čísla
		return ($r[0] == $sep) ? "0$r" : $r;                                // Doplnění úvodní nuly před oddělovač
	}
	return (string)($n ?? '');                                              // Nečíselnou hodnotu vrátíme jako text
}

function fform($url, $body, $params = '') {                                 // Pomocná funkce pro obalení formuláře
	return "<form name=f id=f action=\"$url\" method=post enctype=\"multipart/form-data\" $params>$body</form>"; // HTML tag form
}

// attrliteral vytvoří z předané hodnoty textový literál v uvozovkách, vhodný pro použití jako atribut pro script HTML
function htmlliteral($xml) {                                                // Textový literál v uvozovkách pro HTML atribut
	return '"' . htmlspecialchars((string)($xml ?? '')) . '"';              // Ošetřený HTML atribut v uvozovkách
}

function htmlvalue($v) {                                                    // Alias pro hodnotu HTML atributu v uvozovkách
	return '"' . htmlspecialchars((string)($v ?? '')) . '"';                // Ošetřená hodnota v uvozovkách
}

// xmlliteral vytvoří z předané hodnoty textový literál v uvozovkách, vhodný pro použití jako atribut v XML
// zatím se používá pouze ve FusionCharts, který vyžaduje navíc replacnout procento sekvencí '%25'
function xmlliteral($xml) {                                                 // Textový literál pro XML atributy
	$escaped = str_replace('&', '%26', str_replace('%', '%25', (string)($xml ?? ''))); // Nahrazení procent a ampersandu
	return jsliteral(htmlspecialchars($escaped));                           // Převod na JS literál
}

// jsliteral vytvoří z předané hodnoty textový literál pro použití v JavaScriptu, nahrazuje pouze nové řádky a dvojité uvozovky
function jsliteral($s) {                                                    // Textový literál pro JavaScript
	if ($s === null) {                                                      // Kontrola prázdné hodnoty null
		return '""';                                                        // Vrácení prázdných uvozovek
	}
	$s = str_replace("\\", "\\\\", (string)$s);                             // Zdvojení zpětných lomítek
	$s = str_replace('"', '\"', $s);                                        // Ošetření dvojitých uvozovek
	$s = str_replace("\n", "\\n", $s);                                      // Ošetření znaku nového řádku LF
	$s = str_replace("\r", "\\r", $s);                                      // Ošetření znaku návratu vozíku CR
	return '"' . $s . '"';                                                  // Vrácení řetězce v uvozovkách
}

// regfile: vrátí jméno dočasného souboru, pokud byl úspěšně uploadnut
function regfile($fn, &$full_name = null) {                                 // Získání cesty k nahranému souboru z $_FILES
	if (array_key_exists($fn, $_FILES)) {                                   // Kontrola existence klíče v poli $_FILES
		$F = &$_FILES[$fn];                                                 // Reference na záznam nahrávaného souboru
		$tmpname = (string)($F['tmp_name'] ?? '');                          // Cesta k dočasnému souboru na serveru
		if ($tmpname !== '' AND is_uploaded_file($tmpname) AND is_readable($tmpname) AND !empty($F['size'])) { // Validace uploadu
			$full_name = array_item($F, 'full_path', '');                   // Uložení plného názvu souboru
			return $tmpname;                                                // Vrácení cesty k dočasnému souboru
		}
	}
	return '';                                                              // Soubor nebyl nahrán nebo je prázdný
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
// SQLRUN: funguje stejně jako mssql_query, navíc ošetřuje chyby a zapisuje historii příkazů kvůli ladění //
////////////////////////////////////////////////////////////////////////////////////////////////////////////

function sqlrun($cmd) {                                                     // Spuštění SQL příkazu nad databází SQLSRV
	global $sqlcmdlist, $dbconnection, $debugmode, $dbquery, $sqlrun_debugonly, $dbsession, $logSqlCmdList, $lastSql; // Globální kontext DB

	$org_lit = guidliteral(array_item($dbsession, 'organization', '0x00')); // SQL literál aktivní organizace
	$cmd = str_replace('@o@', $org_lit, (string)$cmd);                      // Nahrazení makra @o@ organizací
	$lastSql = $cmd;                                                        // Uložení posledního prováděného příkazu

	if ($sqlrun_debugonly) {                                                // Pokud běží pouze ladicí výpis bez exekuce
		debugitem('sqlrun', $cmd);                                          // Zápis příkazu do debug logu
		return true;                                                        // Ukončení bez volání databáze
	}

	if ($debugmode AND $logSqlCmdList) {                                    // Zápis do historie příkazů v ladicím režimu
		$sqlcmdlist .= "\r\n$cmd";                                          // Připojení dotazu do historie
	}

	if (is_resource($dbquery) OR is_object($dbquery)) {                     // Pokud zůstal otevřený předchozí SQLSRV statement
		sqlsrv_free_stmt($dbquery);                                         // Okamžité uvolnění předchozího statementu
	}
	
	$options = ['ReturnDatesAsStrings' => true];                            // Volba pro vracení datumů jako textových řetězců
	$dbquery = sqlsrv_query($dbconnection, $cmd, [], $options);             // Provedení SQL dotazu přes ovladač sqlsrv
	
	if ($dbquery !== false) {                                               // Pokud dotaz proběhl bez chyby
		return $dbquery;                                                    // Vrácení identifikátoru otevřeného statementu
	}
	
	$e = sqlsrv_errors(SQLSRV_ERR_ERRORS);                                  // Načtení pole chyb z ovladače SQLSRV
	if ($e) {                                                               // Pokud ovladač vrátil popis chyby
		$m = '';                                                            // Sběrný řetězec chybových hlášení
		foreach ($e as $ei) {                                               // Průchod jednotlivými chybami SQL Serveru
			$m .= var_export($ei, true) . "\n";                             // Připojení detailu chyby
		}
		if (!$m) {                                                          // Pokud je chybový výpis prázdný
			return false;                                                   // Návrat s neúspěchem
		}
		$msg = "\r\nError at SQL command:\r\n$cmd\r\n\r\nSQL command history:\r\n$sqlcmdlist\r\n\r\n$m"; // Sestavení kompletní zprávy
		fatal_error("Ramses SQL Error", $msg, strpos($m, "deadlock"));      // Vyvolání fatální chyby s výpisem
	}
	
	return false;                                                           // Dotaz selhal
}

// NEXT_RESULT: Odstíní platformově toto volání
function next_result($res = null, $force = true) {                          // Posun na další result-set v dávce
	global $dbquery;                                                        // Globální identifikátor dotazu
	if ($res === null) {                                                    // Pokud nebyl předán vlastní statement
		$res = $dbquery;                                                    // Použijeme globální statement
	}
	if ($res === false OR (!is_resource($res) AND !is_object($res))) {      // Ochrana proti neplatnému statementu
		return false;                                                       // Nelze posunout na další výsledek
	}
	return sqlsrv_next_result($res);                                        // Posun na další result-set v SQLSRV
}

// DATA_SEEK: Odstíní platformově toto volání
function data_seek($res, $num) {                                            // Historická funkce pro posun kurzoru
	// SQLSRV nepodporuje přímý data_seek na defaultních server-side kurzorech.
	// V nové STI architektuře BCM Osiris tuto funkci již nepotřebujeme.
	return false;                                                           // Vždy vrací false
}

// FREE_RESULT: Odstíní platformově toto volání
function free_result($res = null) {                                         // Uvolnění výsledku SQL dotazu
	global $dbquery;                                                        // Globální identifikátor dotazu
	if ($res === null) {                                                    // Pokud nebyl předán statement
		$res = $dbquery;                                                    // Použijeme globální statement
	}
	if (!is_resource($res) AND !is_object($res)) {                          // Pokud již statement není platný
		return true;                                                        // Považujeme za uvolněno
	}
	return @sqlsrv_cancel($res);                                            // Zrušení nevyčtených výsledků statementu
}

/*
 * function cleanup_result()
 * Uvolní aktuální SQL výsledek podle použitého databázového driveru.
 * Funkce používá globální proměnnou $dbquery.
 */
function cleanup_result() {                                                 // Úplné vyčištění globálního statementu
	global $dbquery;                                                        // Globální identifikátor dotazu
	if (is_resource($dbquery) OR is_object($dbquery)) {                     // Kontrola platného zdroje
		@sqlsrv_cancel($dbquery);                                           // Zrušení aktivního výsledku
		$dbquery = null;                                                    // Vynulování globální proměnné
	}
}

// NUM_ROWS: Odstíní platformově toto volání
function num_rows($res) {                                                   // Počet ovlivněných řádků dotazu
	return sqlsrv_rows_affected($res);                                      // Vrácení počtu řádků z SQLSRV
}

function db_field_type($colname) {                                          // Zjištění datového typu sloupce v otevřeném dotazu
	global $dbquery;                                                        // Globální identifikátor dotazu

	$fields = sqlsrv_field_metadata($dbquery);                              // Načtení metadat sloupců výsledku
	if ($fields !== false) {                                                // Pokud jsou metadata dostupná
		$names = array_column($fields, 'Name');                             // Pole názvů všech sloupců
		$index = array_search($colname, $names);                            // Vyhledání indexu požadovaného sloupce
		if ($index !== false) {                                             // Pokud byl sloupec nalezen
			$typeNum = $fields[$index]['Type'];                             // Číselný kód typu z ovladače SQLSRV
			return sqlsrv_type_to_string($typeNum);                         // Převod číselného kódu na název typu
		}
	}
	
	return null;                                                            // Sloupec nebo typ nebyl nalezen
}

function sqlsrv_type_to_string($type) {                                     // Převod číselného kódu typu SQLSRV na textový název
	static $map = [                                                         // Mapa kódů datových typů
		// === PŮVODNÍ KLÍČE (Legacy / System ID) ===
		56 => 'int',
		127 => 'bigint',
		62 => 'float',
		59 => 'real',
		108 => 'numeric',
		106 => 'decimal',
		175 => 'char',
		167 => 'varchar',
		231 => 'nvarchar',
		239 => 'nchar',
		61 => 'datetime',
		58 => 'smalldatetime',
		40 => 'date',
		41 => 'time',
		104 => 'bit',
		128 => 'binary',
		129 => 'varbinary',
		130 => 'image',

		// === NOVÉ KLÍČE (Nutné pro PHP 8.x + sqlsrv driver) ===
		// 1. Binární data
		-4  => 'image',      // SQL_LONGVARBINARY -> reprezentuje Image / Varbinary(max)
		-3  => 'varbinary',  // SQL_VARBINARY
		-2  => 'binary',     // SQL_BINARY
		
		// 2. Textová data
		-1  => 'text',       // SQL_LONGVARCHAR -> reprezentuje Text / Varchar(max)
		1   => 'char',       // SQL_CHAR
		12  => 'varchar',    // SQL_VARCHAR
		-8  => 'nchar',      // SQL_WCHAR
		-9  => 'nvarchar',   // SQL_WVARCHAR
		-10 => 'ntext',      // SQL_WLONGVARCHAR
		
		// 3. Čísla
		4   => 'int',        // SQL_INTEGER
		5   => 'smallint',   // SQL_SMALLINT
		-6  => 'tinyint',    // SQL_TINYINT
		-5  => 'bigint',     // SQL_BIGINT
		6   => 'float',      // SQL_FLOAT
		7   => 'real',       // SQL_REAL
		2   => 'numeric',    // SQL_NUMERIC
		3   => 'decimal',    // SQL_DECIMAL
		-7  => 'bit',        // SQL_BIT
		
		// 4. Datum a čas
		91  => 'date',       // SQL_TYPE_DATE
		93  => 'datetime',   // SQL_TYPE_TIMESTAMP
		-154 => 'time',      // SQL_SS_TIME2
		-155 => 'datetimeoffset',
	];                                                                      // Konec mapy datových typů

	return $map[$type] ?? "unknown type: $type";                            // Vrácení názvu typu nebo informace o neznámém kódu
}

/*
	FETCH: fetchne řádek do pole, přičemž odstraní MSSQL chybu, která vrací mezeru místo empty
	zároveň konvertuje datum z objektu DateTime
*/
function fetch($q = null) {                                                 // Načtení jednoho řádku z otevřeného result-setu
	global $dbquery;                                                        // Globální identifikátor dotazu
	if ($q === null) {                                                      // Pokud nebyl předán vlastní statement
		$q = $dbquery;                                                      // Použijeme globální statement
	}
	if (!is_resource($q) AND !is_object($q)) {                              // Ochrana proti neplatnému nebo uvolněnému statementu
		return [];                                                          // Vrácení prázdného pole
	}
	
	while (true) {                                                          // Smyčka pro přeskočení prázdných mezivýsledků v dávce
		$r = sqlsrv_fetch_array($q, SQLSRV_FETCH_BOTH);                     // Načtení řádku s číselnými i asociativními klíči
		if ($r !== false) {                                                 // Pokud se čtení zdařilo (řádek nebo null na konci)
			break;                                                          // Vystoupíme ze čtecí smyčky
		}
		$m = sqlsrv_errors();                                               // Zjištění chyby při čtení result-setu
		$m1 = is_array($m) ? end($m) : [];                                  // Poslední chybový záznam
		$err_code = (int)array_item($m1, 'code', 0);                        // Číselný kód chyby SQLSRV
		if ($err_code === -26) {                                            // Kód -26 znamená prázdný result-set bez sloupců
			return [];                                                      // Vrácení prázdného pole
		}
		if (in_array($err_code, [-28, -22], true)) {                        // Kódy vyžadující posun na další result-set
			$next = next_result($q);                                        // Posun na další result-set
			if ($next) {                                                    // Pokud další result-set existuje
				continue;                                                   // Zkusíme načíst řádek znovu
			}
			return [];                                                      // Žádný další result-set není k dispozici
		}
		debugitem("ERROR", $m);                                             // Zápis neočekávané chyby do ladicího výpisu
		break;                                                              // Ukončení smyčky při chybě
	}
	
	if ($r) {                                                               // Pokud byl načten platný datový řádek
		foreach ($r as $k => &$v) {                                         // Průchod hodnotami načteného řádku
			if (is_object($v) AND method_exists($v, 'format')) {            // Pokud ovladač vrátil datum jako objekt DateTime
				$v = $v->format('Y-m-d H:i:s');                             // Převod objektu DateTime na řetězec
				if (substr($v, -3) == ':00') {                              // Pokud jsou vteřiny nulové
					$v = substr($v, 0, -3);                                 // Oříznutí nulových vteřin
				}
			}
			if ($v === ' ') {                                               // Historická korekce jediné mezery na prázdný řetězec
				$r[$k] = '';                                                // Nahrazení mezery prázdným řetězcem
			}
		}
	}
	
	return $r;                                                              // Vrácení načteného řádku (nebo null na konci)
}

// SQLARRAY: Funkce přečte result set a připraví z něj jednoduché indexované pole (klíč => hodnota)
function sqlarray($p = null, $continue = 0) {                               // Načtení dvojic [sloupec0 => sloupec1] do pole
	global $dbquery;                                                        // Globální identifikátor dotazu
	if (!isset($p)) {                                                       // Pokud nebyl předán SQL příkaz ani statement
		$p = $dbquery;                                                      // Použijeme globální statement
	}
	$continue = (is_resource($p) OR is_object($p));                         // Zda čteme z již otevřeného statementu
	$res = (!$continue) ? sqlrun($p) : $p;                                  // Spuštění dotazu nebo převzetí statementu
	$r = [];                                                                // Výsledné asociativní pole
	while ($d = fetch($res)) {                                              // Čtení všech řádků výsledku
		$r[$d[0]] = $d[1];                                                  // Uložení hodnoty druhého sloupce pod klíč prvního
	}
	next_result($res);                                                      // Posun na případný další result-set
	if ($continue) {                                                        // Pokud šlo o externě předaný statement
		return $r;                                                          // Neuzavíráme statement a vrátíme pole
	}
	free_result($res);                                                      // Uvolnění statementu
	return $r;                                                              // Vrácení načteného pole
}

// SQLFIRSTROW: Funkce přečte první řádek resultu do jednoduchého pole
function sqlfirstrow($p = null) {                                           // Načtení prvního řádku výsledku do pole
	global $dbquery;                                                        // Globální identifikátor dotazu
	if (!isset($p)) {                                                       // Pokud nebyl předán dotaz ani statement
		$p = $dbquery;                                                      // Použijeme globální statement
	}
	$continue = (is_resource($p) OR is_object($p));                         // Zda čteme z již otevřeného statementu
	if (!$continue) {                                                       // Pokud byl předán textový SQL dotaz
		$res = sqlrun($p);                                                  // Spuštění SQL dotazu
		$dbquery = $res;                                                    // Uložení do globální proměnné
	} else {
		$res = $p;                                                          // Převzetí otevřeného statementu
	}
	$d = fetch($res);                                                       // Načtení prvního řádku výsledku
	if ($d) {                                                               // Pokud první řádek existuje
		next_result($res);                                                  // Posun na další result-set
		if ($continue) {                                                    // Při pokračování v otevřeném statementu
			return $d;                                                      // Vrátíme načtený řádek bez uzavření
		}
		cleanup_result();                                                   // Uvolnění statementu po přečtení řádku
		return $d;                                                          // Vrácení prvního řádku
	}
	next_result($res);                                                      // Posun při prázdném výsledku
	if (!$continue) {                                                       // Pokud jsme dotaz otevírali zde
		cleanup_result();                                                   // Uvolnění prázdného statementu
	}
	return [];                                                              // Vrácení prázdného pole
}

// SQLARRAY2: Funkce přečte result set a připraví z řádků dvojrozměrné pole indexované prvním sloupcem
function sqlarray2($p = null, $continue = 0) {                              // Načtení řádků indexovaných prvním sloupcem
	global $dbquery;                                                        // Globální identifikátor dotazu
	if (!isset($p)) {                                                       // Pokud nebyl předán dotaz
		$p = $dbquery;                                                      // Použijeme globální statement
	}
	if (is_resource($p) OR is_object($p)) {                                 // Kontrola otevřeného statementu
		$res = $p;                                                          // Převzetí statementu
		$continue = 1;                                                      // Příznak pokračování
	} else {
		$res = sqlrun($p);                                                  // Spuštění nového SQL dotazu
	}
	$r = [];                                                                // Výsledné pole řádků
	while ($d = fetch($res)) {                                              // Čtení všech řádků výsledku
		$r[$d[0]] = $d;                                                     // Uložení celého řádku pod klíč prvního sloupce
	}
	next_result($res);                                                      // Posun na další result-set
	if ($continue) {                                                        // Pokud šlo o otevřený statement
		return $r;                                                          // Vrátíme pole bez uvolnění statementu
	}
	free_result($res);                                                      // Uvolnění statementu
	return $r;                                                              // Vrácení načteného pole
}

// SQLARRAY3: Funkce přečte result set a připraví z řádků trojrozměrné pole seskupené podle prvního sloupce
function sqlarray3($p = null) {                                             // Načtení řádků seskupených podle prvního sloupce
	global $dbquery;                                                        // Globální identifikátor dotazu
	if ($p === null) {                                                      // Pokud nebyl předán dotaz
		$p = $dbquery;                                                      // Použijeme globální statement
	}
	$continue = 0;                                                          // Výchozí příznak nového dotazu
	if (is_resource($p) OR is_object($p)) {                                 // Kontrola otevřeného statementu
		$res = $p;                                                          // Převzetí statementu
		$continue = 1;                                                      // Příznak pokračování
	} else {
		$res = sqlrun($p);                                                  // Spuštění nového SQL dotazu
	}
	$r = [];                                                                // Výsledné seskupené pole
	while ($d = fetch($res)) {                                              // Čtení všech řádků výsledku
		$key = $d[0];                                                       // Klíč skupiny z prvního sloupce
		if (array_key_exists($key, $r)) {                                   // Pokud skupina již existuje
			array_push($r[$key], $d);                                       // Přidání řádku do existující skupiny
		} else {
			$r[$key] = [$d];                                                // Založení nové skupiny s prvním řádkem
		}
	}
	next_result($res);                                                      // Posun na další result-set
	if ($continue) {                                                        // Pokud šlo o otevřený statement
		return $r;                                                          // Vrátíme pole bez uvolnění statementu
	}
	free_result($res);                                                      // Uvolnění statementu
	return $r;                                                              // Vrácení seskupeného pole
}

// SQLARRAY_SIMPLE: Funkce přečte result set a připraví z řádků prosté pole
function sqlarray_simple($p = null) {                                       // Načtení celého result-setu do prostého pole řádků
	global $dbquery;                                                        // Globální identifikátor dotazu
	if ($p === null) {                                                      // Pokud nebyl předán dotaz
		$p = $dbquery;                                                      // Použijeme globální statement
	}
	$continue = 0;                                                          // Výchozí příznak nového dotazu
	$i = 0;                                                                 // Počitadlo indexů pole
	if (is_resource($p) OR is_object($p)) {                                 // Kontrola otevřeného statementu
		$res = $p;                                                          // Převzetí statementu
		$continue = 1;                                                      // Příznak pokračování
	} else {
		$res = sqlrun($p);                                                  // Spuštění nového SQL dotazu
	}
	$r = [];                                                                // Výsledné pole řádků
	while ($d = fetch($res)) {                                              // Čtení všech řádků do paměti
		$r[$i++] = $d;                                                      // Uložení řádku do pole
	}
	next_result($res);                                                      // Posun na další result-set
	if ($continue) {                                                        // Pokud šlo o otevřený statement
		return $r;                                                          // Vrátíme pole bez uvolnění statementu
	}
	free_result($res);                                                      // Uvolnění statementu
	return $r;                                                              // Vrácení pole všech řádků
}

// FATAL_ERROR: oznámí chybu a skončí.
function fatal_error($usr = '', $x = "Unspecified error", $deadlock = 0) {  // Zpracování kritické chyby aplikace
	global $debugmode, $dbsession, $error_mailto, $SID, $ORIGINAL_REMOTE_ADDR, $dbserver, $use_dbname; // Globální proměnné

	$get = to_string($_GET);                                                // Serializace GET parametrů
	foreach (['pwd', 'password', 'new_password', 'new_password_confirm'] as $pwd_key) { // Seznam citlivých klíčů hesel
		if (isset($_POST) AND array_key_exists($pwd_key, $_POST)) {         // Ochrana hesla před zalogováním v čitelné podobě
			$_POST[$pwd_key] = '*** Password is hidden for security reasons ***'; // Maskování hesla v POSTu
		}
	}
	$post = (isset($_POST)) ? "\r\nPOST=" . to_string($_POST) : "";         // Serializace POST parametrů
	$sess = (isset($_SESSION)) ? "\r\nSESSION=" . to_string($_SESSION) : ""; // Serializace SESSION dat
	$cn = getenv('COMPUTERNAME');                                           // Název počítače serveru
	$cookie = @$_SERVER['HTTP_COOKIE'];                                     // Hlavička cookies
	$time = date("d.m.Y H:i:s");                                            // Čas vzniku chyby
	$host = gethostname();                                                  // Hostname serveru
	
	ob_start();                                                             // Zahájení zachytávání výstupu pro backtrace
	debug_print_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS);                     // Výpis zásobníku volání
	$bt = ob_get_clean();                                                   // Uložení zásobníku volání do proměnné
	
	$srv_name = $_SERVER['SERVER_NAME'] ?? '';                              // Název webového serveru
	$req_uri = $_SERVER['REQUEST_URI'] ?? '';                               // URI požadavku
	$rem_addr = $_SERVER['REMOTE_ADDR'] ?? '';                              // IP adresa klienta
	$usr_login = array_item($dbsession, 'user_name');                       // Přihlašovací jméno z relace
	$usr_disp = array_item($dbsession, 'organization_name') . '/' . array_item($dbsession, 'display_name'); // Organizace a jméno

	$msg = "
Time=$time
Server=$srv_name on \"$host\" $cn
DbServer=$dbserver
Database=$use_dbname
Login=$usr_login
Name=$usr_disp

BackTrace:
$bt

Error: $usr
Detail:
$x

Request properties:
URL=$req_uri
REMOTE_ADDR=$rem_addr
ORIGINAL_REMOTE_ADDR=$ORIGINAL_REMOTE_ADDR
SESSIONID=$SID
COOKIES=$cookie
GET=$get$post$sess";                                                        // Sestavení textu chybového hlášení

	$msg = str_replace('<br />', "\r\n", $msg);                             // Nahrazení HTML odřádkování
	$msg = str_replace("\n", "\r\n", $msg);                                 // Sjednocení LF na CRLF
	$msg = str_replace("\r\r", "\r", $msg);                                 // Odstranění zdvojených CR
	write_log($msg);                                                        // Zápis chyby do souboru Ramses.log
	syslog(LOG_ERR, $msg);                                                  // Zápis chyby do systémového logu

	if ($debugmode) {                                                       // V ladicím režimu vypíšeme detail přímo na obrazovku
		debugprint();                                                       // Výpis nasbíraných debug položek
		$x_html = nl2br(htmlspecialchars($msg));                            // Ošetřený HTML výpis detailu chyby
		print "<DIV align=\"left\"><H1>Unexpected error</H1>
		<H2>$usr</H2>
		<p style=color:magenta>This report is displayed thanks your debug setting.<br />If you are not a developer team member, send the information to the provider.</p>
		<p style=color:brown>$x_html</p>
		</DIV></body></HTML>";                                              // Výpis ladicí chybové obrazovky
	} else {
		if (!$error_mailto) {                                               // Výchozí příjemce chybových hlášení
			$error_mailto = 'hink@rac.cz';                                  // Vývojářský e-mail
		}
		$t = time();                                                        // Čas před odesláním e-mailu
		$i = true;                                                          // Výchozí stav odeslání
		if ($ORIGINAL_REMOTE_ADDR !== '212.24.158.131') {                   // Nezasílat e-maily při testu Nagiosu
			$sent = send_global_mail($error_mailto, "Osiris error report", $msg, false); // Odeslání chybového e-mailu
			$i = $sent ? "OK" : "Error, message saved into log file";       // Stav odeslání e-mailu
		}
		if ($deadlock) {                                                    // Speciální hlášení při databázovém deadlocku
			print "<DIV style=text-align:left><H1>System overload / systém je přetížen</H1>
			<DIV style=color:blue>Try to repeat action in a while / Zkuste akci za chvíli zopakovat</DIV></DIV></body></HTML>"; // Výzva k opakování
		} else {
			$time_after = time();                                           // Čas po odeslání e-mailu
			if ($i AND ($time_after > $t + 10)) {                           // Detekce prodlevy poštovního serveru
				$i = "Služba pro odeslání mailu neodpověděla včas. Zpráva nemusela být řádně odeslána."; // Česká informace
				$ien = "The mail sending service did not respond in time. The message may not have been sent properly."; // Anglická informace
			} else {
				$ien = $i ? "OK" : "ERROR";                                 // Anglický stav odeslání
				$i = $i ? "OK" : "Chyba";                                   // Český stav odeslání
			}
			print "
			<DIV align=\"left\">
			<H2>Na serveru nastal problém</H2>
			<div>Detaily o problému byly zapsány do deníku a budou zaslány vývojovému týmu k řešení.<div>Odeslání mailu .... $i</div>
			</div></DIV>

			<DIV align=\"left\">
			<H2>A problem ocurred</H2>
			<div>The details of the issue have been logged and will be sent to the development team for resolution.<div>Mail-status: $ien</div>
			</div></DIV>

			</body></HTML>";                                                // Produkční chybová obrazovka
		}
	}
	die();                                                                  // Okamžité ukončení běhu skriptu
}

function to_string($val) {                                                  // Bezpečný převod pole nebo objektu na řetězec
	if (is_array($val) OR is_object($val)) {                                // Kontrola složeného typu
		ob_start();                                                         // Zahájení zachytávání výstupu
		print_r($val);                                                      // Výpis struktury proměnné
		return ob_get_clean();                                              // Vrácení zachyceného textu
	}
	return (string)$val;                                                    // Skalární hodnotu vrátíme jako string
}

// CHARLITERAL: Převede znaky na literál v apostrofech
function charliteral($c, $len = 0) {                                        // Vytvoření bezpečného textového SQL literálu
	if ($c === null) {                                                      // Hodnota null se převádí na SQL klíčové slovo NULL
		return "NULL";                                                      // SQL NULL
	}
	$c = (string)$c;                                                        // Přetypování na řetězec
	if ($len > 0) {                                                         // Pokud je zadáno omezení maximální délky
		$c = substr($c, 0, $len);                                           // Oříznutí řetězce na požadovanou délku
	}
	$c = str_replace("\r\n", "\n", $c);                                     // Sjednocení odřádkování na LF
	$c = str_replace("\x00", "\n", $c);                                     // Odstranění nulových bajtů
	return "'" . str_replace("'", "''", $c) . "'";                          // Zdvojení apostrofů a obalení apostrofy
}

// GUIDLITERAL: Převede UUID ve stringu na literál v apostrofech
function guidliteral($c) {                                                  // Vytvoření bezpečného UUID SQL literálu
	$c = trim((string)($c ?? ''));                                          // Očištění vstupního řetězce
	if ($c === '' OR strtolower($c) === 'null') {                           // Prázdný řetězec vrací SQL NULL
		return 'NULL';                                                      // SQL NULL
	}
	if ($c === '0x00') {                                                    // Systémová konstanta 0x00 se vrací přímo
		return '0x00';                                                      // Systémový vlastník 0x00
	}
	if ($c[0] === '{') {                                                    // Odstranění případných složených závorek kolem GUIDu
		$c = substr($c, 1, -1);                                             // Oříznutí složených závorek
	}
	return is_guid($c) ? "'$c'" : 'NULL';                                   // Ověření formátu UUID a obalení apostrofy
}

// INTLITERAL: Převede znaky na číselný literál
function intliteral($c, $prec = 0) {                                        // Vytvoření bezpečného číselného SQL literálu
	$str = (string)($c ?? '');                                              // Převod vstupu na řetězec
	if ($str === "") {                                                      // Prázdný vstup vrací SQL NULL
		return 'NULL';                                                      // SQL NULL
	}
	if (substr($str, 0, 2) === 'ID') {                                      // Odstranění historického prefixu ID
		$str = substr($str, 2);                                             // Oříznutí prefixu ID
	}
	$str = str_replace(' ', '', $str);                                      // Odstranění mezer (oddělovačů tisíců)
	$str = str_replace(',', '.', $str);                                     // Nahrazení desetinné čárky tečkou
	if (!is_numeric($str)) {                                                // Kontrola platného čísla
		return 'NULL';                                                      // Nečíselná hodnota vrací SQL NULL
	}
	return bcadd($str, "0", $prec);                                         // Přesné zaokrouhlení přes bcmath
}

// INTLITERALLIST: Převede znaky na seznam čísel v apostrofech
function intliterallist($c) {                                               // Seznam celých čísel oddělených čárkou v apostrofech
	$c = (string)($c ?? '');                                                // Přetypování na řetězec
	if ($c !== '') {                                                        // Pokud vstup není prázdný
		$a = explode(',', $c);                                              // Rozdělení podle čárky
		foreach ($a as $i => $cls) {                                        // Průchod jednotlivými položkami
			$cls = str_replace(' ', '', $cls);                              // Odstranění mezer
			$a[$i] = bcadd($cls, '0');                                      // Normalizace na celé číslo
		}
		return "'" . implode(',', $a) . "'";                                // Spojení do SQL literálu
	}
	return "''";                                                            // Prázdný seznam
}

// Vrati datum v ODBC formatu nebo false
function date_from_string($s) {                                             // Parsování textového data do ODBC formátu
	$s = (string)($s ?? '');                                                // Přetypování na řetězec
	if (!$s OR strtolower($s) === 'null') {                                 // Kontrola prázdného data
		return false;                                                       // Neplatné datum
	}
	$formatList = [                                                         // Podporované vstupní formáty data
		"j.n.Y", "j.n.y", "j.n.y H:i", "j.n.Y H:i",
		"Y-m-d H:i:s", "Y-m-d H:i", "dmy", "dmy H:i", "Y-m-d"
	];                                                                      // Konec seznamu formátů
	foreach ($formatList as $format) {                                      // Zkoušení jednotlivých formátů
		$d = date_parse_from_format($format, $s);                           // Pokus o rozparsování data
		if ($d['error_count']) {                                            // Pokud formát neodpovídá
			continue;                                                       // Zkusíme další formát
		}
		$year = (int)$d['year'];                                            // Zjištěný rok
		if ($year < 30) {                                                   // Dvoumístný rok do 29
			$year += 2000;                                                  // Přičtení 2000
		}
		if ($year < 100) {                                                  // Dvoumístný rok nad 30
			$year += 1900;                                                  // Přičtení 1900
		}
		$month = substr("00" . $d['month'], -2);                            // Měsíc zarovnaný nulou
		$day = substr("00" . $d['day'], -2);                                // Den zarovnaný nulou
		$hour = substr("00" . $d['hour'], -2);                              // Hodina zarovnaná nulou
		$minute = substr("00" . $d['minute'], -2);                          // Minuta zarovnaná nulou
		$second = substr("00" . $d['second'], -2);                          // Sekunda zarovnaná nulou
		return "$year-$month-$day $hour:$minute:$second";                   // Výsledný ODBC formát data
	}
	return false;                                                           // Žádný formát nevyhověl
}

// DATELITERAL: Převádí datum do formátu vhodného pro zápis do databáze
function dateliteral($input) {                                              // Převod data na SQL literál v apostrofech
	$input = trim((string)($input ?? ''));                                  // Očištění vstupního řetězce
	while (($temp = str_replace('  ', ' ', $input)) != $input) {            // Odstranění vícenásobných mezer
		$input = $temp;                                                     // Uložení zkráceného řetězce
	}
	if (strpos($input, ".") !== false) {                                    // České datum oddělené tečkami
		$a = explode(".", $input);                                          // Rozpad podle teček
		if (count($a) < 2) {                                                // Nedostatečný počet složek
			return 'NULL';                                                  // Neplatné datum
		}
		if (count($a) < 3) {                                                // Pokud chybí rok, doplníme aktuální
			$a[2] = date("Y");                                              // Doplnění aktuálního roku
		}
		$den = (int)$a[0];                                                  // Den z prvního prvku
		$mesic = (int)$a[1];                                                // Měsíc z druhého prvku
		$rok = (int)$a[2];                                                  // Rok ze třetího prvku
	} else {
		$a = explode("-", $input);                                          // ISO datum oddělené pomlčkami
		if (count($a) < 3) {                                                // Nedostatečný počet složek
			return 'NULL';                                                  // Neplatné datum
		}
		$rok = (int)$a[0];                                                  // Rok z prvního prvku
		$mesic = (int)$a[1];                                                // Měsíc z druhého prvku
		$den = (int)$a[2];                                                  // Den ze třetího prvku
	}
	if ($rok < 100) {                                                       // Korekce dvoumístného roku
		$rok += 2000;                                                       // Přičtení 2000
		if ($rok > (int)date("Y") + 2) {                                    // Korekce pro minulé století
			$rok -= 100;                                                    // Odečtení 100 let
		}
	}
	if (!checkdate($mesic, $den, $rok)) {                                   // Ověření kalendářní platnosti data
		return 'NULL';                                                      // Neplatné kalendářní datum
	}
	
	$hodina = 0;                                                            // Výchozí hodina
	$minuta = 0;                                                            // Výchozí minuta
	$has_time = false;                                                      // Příznak přítomnosti času
	$i = strrpos($input, " ");                                              // Hledání mezery oddělující čas
	$time_part = ($i > 0) ? substr($input, $i) : "";                        // Oddělení časové části
	$casti = explode(':', $time_part);                                      // Rozdělení času podle dvojtečky
	if (count($casti) > 1) {                                                // Pokud byla nalezena hodina a minuta
		$hodina = (int)$casti[0];                                           // Hodina jako číslo
		$minuta = (int)$casti[1];                                           // Minuta jako číslo
		$has_time = true;                                                   // Časová složka byla zadána
	}
	$datum = sprintf("%04d-%02d-%02d", $rok, $mesic, $den);                 // Sestavení ISO data
	if ($has_time) {                                                        // Připojení času, pokud byl zadán
		$datum .= sprintf(" %02d:%02d", $hodina, $minuta);                  // Připojení hodin a minut
	}
	return "'$datum'";                                                      // Vrácení SQL literálu data
}

// BinLiteral: Převádí a kontroluje binární string
function varbinliteral($input) {                                            // Převod hexadecimálního řetězce na binární SQL literál
	$output = '0x';                                                         // Prefix binárního literálu
	$input = trim(strtolower((string)$input));                              // Očištění a převod na malá písmena
	if (substr($input, 0, 2) === '0x') {                                    // Kontrola hexadecimálního prefixu 0x
		$blank = [' ', "\n", "\r", "\t"];                                   // Povolené bílé znaky uvnitř hex řetězce
		$len = strlen($input);                                              // Délka vstupního řetězce
		for ($i = 2; $i < $len; $i++) {                                     // Průchod znaky za prefixem 0x
			$c = (string)$input[$i];                                        // Aktuální znak
			if (($c >= '0' AND $c <= '9') OR ($c >= 'a' AND $c <= 'f')) {   // Kontrola platné hex číslice
				$output .= $c;                                              // Připojení platného znaku
			} elseif (!in_array($c, $blank, true)) {                        // Nepovolený znak mimo bílé znaky
				return 'NULL';                                              // Neplatný binární literál
			}
		}
		return $output;                                                     // Vrácení ověřeného binárního literálu
	}
	return 'NULL';                                                          // Chybí prefix 0x
}

function logged() {}                                                        // Historická prázdná funkce pro zpětnou kompatibilitu

function active($stav) {                                                    // Ikona stavu aktivity
	return ($stav == 0) ? "images/16x16/BulbOff.png" : "images/16x16/BulbOn.png"; // Cesta k obrázku žárovky
}

// SESSREG: jednoduchá registrace session proměnné jako globální
function sessreg($nazev) {                                                  // Propojení globální proměnné s $_SESSION
	if (isset($_SESSION[$nazev])) {                                         // Pokud je již v session uložena
		$GLOBALS[$nazev] = &$_SESSION[$nazev];                              // Napojení globální proměnné referencí
		return 1;                                                           // Nalezeno v session
	}
	$r = isset($GLOBALS[$nazev]);                                           // Zda již existuje v $GLOBALS
	if (!$r) {                                                              // Pokud neexistuje
		$GLOBALS[$nazev] = "";                                              // Inicializace prázdným řetězcem
	}
	$_SESSION[$nazev] = &$GLOBALS[$nazev];                                  // Uložení reference do $_SESSION
	return $r;                                                              // Vrácení původního stavu existence
}

/////////////////////////////////////////////////////////////////////////////
// SESSIONINPUT: Registrace proměnné předané v POST nebo GET jako session  //
//               POST má přednost                                          //
//               Není-li předána, zachovává se původní hodnota v $_SESSION //
/////////////////////////////////////////////////////////////////////////////
function sessioninput($name, $opt = 0) {                                    // Načtení vstupu s trvalým uložením v $_SESSION
	$v = '';                                                                // Výchozí prázdná hodnota
	if (array_key_exists($name, $_SESSION)) {                               // Hodnota z předchozího požadavku v session
		$v = $_SESSION[$name];                                              // Převzetí ze session
	}
	if (array_key_exists($name, $_GET)) {                                   // Hodnota předaná v URL (GET)
		$v = $_GET[$name];                                                  // Přepsání hodnotou z GET
	}
	if (array_key_exists($name, $_POST)) {                                  // Hodnota předaná formulářem (POST má přednost)
		$v = $_POST[$name];                                                 // Přepsání hodnotou z POST
	}
	$_SESSION[$name] = &$v;                                                 // Uložení do session
	$v = stripsl($v, $opt);                                                 // Očištění a případná konverze typu
	$GLOBALS[$name] = &$v;                                                  // Zápis do globální proměnné
	return $v;                                                              // Vrácení výsledné hodnoty
}

// POSTGETREG: jednoduchá registrace globální proměnné předané pomocí POST nebo GET
function postgetreg($nazev, $opt = 0) {                                     // Registrace vstupu z POST nebo GET do $GLOBALS
	if (isset($_POST[$nazev])) {                                            // Přednost má POST
		$GLOBALS[$nazev] = stripsl($_POST[$nazev], $opt);                   // Očištění a uložení z POST
		return 1;                                                           // Nalezeno v POST
	}
	if (isset($_GET[$nazev])) {                                             // Druhá volba je GET
		$GLOBALS[$nazev] = stripsl($_GET[$nazev], $opt);                    // Očištění a uložení z GET
		return 1;                                                           // Nalezeno v GET
	}
	if (!isset($GLOBALS[$nazev])) {                                         // Pokud proměnná vůbec neexistuje
		$GLOBALS[$nazev] = "";                                              // Inicializace prázdným řetězcem
		return 0;                                                           // Nenalezeno
	}
	return 1;                                                               // Ponechána existující globální hodnota
}

// HTMLSPEC: vylepšená funkce HTMLSpecialChars, která žere i pole
function htmlspec($a) {                                                     // Rekurzivní htmlspecialchars pro řetězce i pole
	if ($a === null) {                                                      // Hodnota null se mění na prázdný řetězec
		return '';                                                          // Prázdný řetězec
	}
	if (is_resource($a) OR is_object($a)) {                                 // Objekty a zdroje nemodifikujeme
		return $a;                                                          // Vrácení beze změny
	}
	if (is_array($a)) {                                                     // Rekurzivní průchod polem
		foreach ($a as $arg => $v) {                                        // Průchod prvky pole
			$a[$arg] = htmlspec($v);                                        // Ošetření prvku pole
		}
		return $a;                                                          // Vrácení ošetřeného pole
	}
	return htmlspecialchars((string)$a);                                    // Ošetření skalárního řetězce
}

// HTMLSPECBR: vylepšená funkce HTMLSpecialChars, která žere i pole, navíc s br
function htmlspecbr($a) {                                                   // Rekurzivní htmlspecialchars spojené s nl2br
	if ($a === null) {                                                      // Hodnota null vrací prázdný řetězec
		return '';                                                          // Prázdný řetězec
	}
	if (is_resource($a) OR is_object($a)) {                                 // Objekty a zdroje nemodifikujeme
		return $a;                                                          // Vrácení beze změny
	}
	if (is_array($a)) {                                                     // Rekurzivní průchod polem
		foreach ($a as $arg => $v) {                                        // Průchod prvky pole
			$a[$arg] = htmlspecbr($v);                                      // Ošetření prvku pole s nl2br
		}
		return $a;                                                          // Vrácení ošetřeného pole
	}
	return nl2br(htmlspecialchars((string)$a));                             // Ošetření řetězce a převod konců řádků na <br>
}

/*
	stripsl: vylepšená funkce stripslashes, která žere i pole a umožňuje převod na literály
*/
function stripsl($a, $opt = 0, $len = 0) {                                  // Sanitizace vstupu a konverze na SQL literály
	if (is_array($a)) {                                                     // Rekurzivní zpracování pole
		foreach ($a as $arg => $v) {                                        // Průchod prvky pole
			$a[$arg] = stripsl($v, $opt, $len);                             // Konverze prvku pole
		}
		return $a;                                                          // Vrácení zpracovaného pole
	}
	if ($opt === 'date' OR $opt === 'datetime' OR $opt === 'smalldatetime') { // Normalizace datumových voleb
		$opt = 3;                                                           // Kód 3 pro datumový literál
	}
	
	switch ("$opt") {                                                       // Rozlišení podle požadovaného cílového typu
		case 'trim':
			return charliteral(trim((string)$a), $len);                     // Oříznutý textový SQL literál
		case '1':
		case 'char':
		case 'varchar':
		case 'nvarchar':
		case 'text':
		case 'ntext':
			return charliteral($a, $len);                                   // Textový SQL literál v apostrofech
		case 'guid':
		case 'uuid':
		case 'uniqueidentifier':
			return guidliteral($a);                                         // UUID SQL literál
		case 'tinyint':
			if ($a > 255 OR $a < 0) {                                       // Kontrola rozsahu tinyint (0..255)
				$a = '';                                                    // Mimo rozsah -> NULL
			}
			return intliteral($a);                                          // Číselný literál
		case 'smallint':
			if ($a > 32767 OR $a < -32768) {                                // Kontrola rozsahu smallint
				$a = '';                                                    // Mimo rozsah -> NULL
			}
			return intliteral($a);                                          // Číselný literál
		case 'int':
			if ($a > 2147483647 OR $a < -2147483648) {                      // Kontrola rozsahu 32-bit int
				$a = '';                                                    // Mimo rozsah -> NULL
			}
			return intliteral($a, $len);                                    // Číselný literál
		case 'varbin':
		case 'varbinary':
		case 'hex':
			return varbinliteral($a);                                       // Binární hexadecimální literál
		case '2':
		case 'bigint':
			$a = intliteral($a, $len);                                      // Převod na číselný řetězec
			if (!is_numeric($a) OR bccomp($a, "9223372036854775807") > 0 OR bccomp($a, "-9223372036854775808") < 0) { // Rozsah bigint
				return 'NULL';                                              // Mimo rozsah 64-bit bigint
			}
			return $a;                                                      // Platný bigint literál
		case '3':
		case 'date':
		case 'datetime':
		case 'smalldatetime':
			return dateliteral($a);                                         // Datumový SQL literál
		case '4':
		case 'bit':
		case 'checkbox':
			return $a ? 1 : 0;                                              // Bitová hodnota 1 nebo 0
		case '5':
			return intliterallist($a);                                      // Seznam celých čísel v apostrofech
		case '6':
			return htmlvalue($a);                                           // Hodnota pro HTML atribut
		case '0':
			break;                                                          // Základní očištění od nebezpečných znaků
		case 'raw':
			return $a;                                                      // Surová hodnota bez úprav (např. pro heslo)
		default:
			return intliteral($a, $len);                                    // Výchozí převod na číslo
	}
	// Pokud má být získána hodnota bez konverze, musí se očistit od speciálních znaků, které by se mohly dostat do URL
	static $unsafe_characters = ['"', "'", '<', '>', '\\', '&', ';', '\0', '{', '}', '/']; // Nebezpečné znaky
	return str_replace($unsafe_characters, '', (string)$a);                 // Vrácení očištěného řetězce
}

// GETINPUT: získání proměnné předané pomocí POST nebo GET
function getinput($nazev, $dbLiteralType = 0, $len = 0) {                   // Bezpečné načtení parametru z GET nebo POST
	global $reginputs;                                                      // Evidence načtených vstupů
	if ($dbLiteralType === 'html') {                                        // Speciální volba pro HTML text v POSTu
		if (isset($_POST[$nazev])) {                                        // Pokud byl v POSTu předán
			$dbLiteralType = 1;                                             // Zpracujeme jako varchar literál
		} else {
			return 'NULL';                                                  // Jinak vracíme SQL NULL
		}
	}
	$r = '';                                                                // Výchozí prázdná hodnota
	if (isset($_GET[$nazev])) {                                             // Načtení z GET
		$r = $_GET[$nazev];                                                 // Hodnota z URL
	}
	if (isset($_POST[$nazev])) {                                            // POST má přednost před GET
		$r = $_POST[$nazev];                                                // Hodnota z formuláře
	}
	$reginputs[$nazev] = $r;                                                // Zápis surové hodnoty do evidence
	return stripsl($r, $dbLiteralType, $len);                               // Vrácení očištěné / zformátované hodnoty
}

// REGINPUT: získání proměnné předané pomocí POST nebo GET, registrace globální proměnné
function reginput($nazev, $dbLiteralType = 0, $len = 0) {                   // Načtení vstupu a uložení do $GLOBALS
	global $reginputs;                                                      // Evidence načtených vstupů
	$arr = explode(',', (string)$nazev);                                    // Podpora seznamu názvů oddělených čárkou
	if (count($arr) > 1) {                                                  // Pokud bylo zadáno více názvů najednou
		foreach ($arr as $prvek) {                                          // Průchod jednotlivými názvy
			reginput($prvek, $dbLiteralType, $len);                         // Rekurzivní registrace každého prvku
		}
		return;                                                             // Ukončení hromadné registrace
	}
	$nazev = trim((string)$nazev);                                          // Očištění názvu proměnné
	if ($dbLiteralType === 'html') {                                        // Speciální volba pro HTML vstup
		if (isset($_POST[$nazev])) {                                        // Pokud je v POSTu
			$dbLiteralType = 1;                                             // Převod na varchar literál
		} else {
			$GLOBALS[$nazev] = 'NULL';                                      // Nastavení SQL NULL do globální proměnné
			return 'NULL';                                                  // Vrácení SQL NULL
		}
	}
	$r = '';                                                                // Výchozí prázdná hodnota
	if (isset($_GET[$nazev])) {                                             // Hodnota z GET
		$r = $_GET[$nazev];                                                 // Převzetí z GET
	}
	if (isset($_POST[$nazev])) {                                            // Hodnota z POST (má přednost)
		$r = $_POST[$nazev];                                                // Převzetí z POST
	}
	$reginputs[$nazev] = $r;                                                // Uložení do evidence vstupů
	$clean_val = stripsl($r, $dbLiteralType, $len);                         // Konverze na cílový formát
	$GLOBALS[$nazev] = $clean_val;                                          // Uložení do globální proměnné
	return $clean_val;                                                      // Vrácení zformátované hodnoty
}

// REGINPUT_SUFFIX: Funguje jako REGINPUT s fixním prefixem/suffixem
function reginput_suffix($suffix, $nazvy, $dbLiteralType = 0, $len = 0) {   // Registrace vstupů se společnou příponou
	global $reginputs;                                                      // Evidence načtených vstupů
	$arr = explode(',', (string)$nazvy);                                    // Seznam základních názvů polí
	foreach ($arr as $prvek) {                                              // Průchod názvy polí
		$r = '';                                                            // Výchozí prázdná hodnota
		$prvek = trim($prvek);                                              // Očištění cílového názvu
		$source_name = $prvek . "_$suffix";                                 // Název pole ve formuláři včetně přípony
		if (isset($_GET[$source_name])) {                                   // Kontrola v GET
			$r = $_GET[$source_name];                                       // Hodnota z GET
		}
		if (isset($_POST[$source_name])) {                                  // Kontrola v POST
			$r = $_POST[$source_name];                                      // Hodnota z POST
		}
		$reginputs[$prvek] = $r;                                            // Zápis do evidence vstupů
		$GLOBALS[$prvek] = stripsl($r, $dbLiteralType, $len);               // Uložení konvertované hodnoty do $GLOBALS
	}
}

// REGINPUTS: volá funkci reginput opakovaně, seznam proměnných je v argumentu ve formě "p1:typ,p2,p3:typ"
function reginputs($s) {                                                    // Hromadná registrace vstupů s definicí typů
	$pp = explode(',', (string)$s);                                         // Rozdělení definic podle čárky
	foreach ($pp as $p) {                                                   // Průchod jednotlivými definicemi
		$e = explode(':', $p);                                              // Rozdělení na název a volitelný typ
		if (count($e) > 1) {                                                // Pokud byl zadán i typ po dvojtečce
			reginput($e[0], $e[1]);                                         // Registrace s explicitním typem
		} else {
			reginput($p);                                                   // Registrace s výchozím typem
		}
	}
}

function reginput_array($n, $typ = 2) {                                     // Registrace pole hodnot do SQL seznamu
	reginput($n, $typ);                                                     // Načtení a konverze prvků pole
	$g = &$GLOBALS[$n];                                                     // Reference na výslednou globální proměnnou
	if (is_array($g)) {                                                     // Pokud je výsledkem pole
		if (in_array($typ, [2, 4, 'int', 'bigint', 'bit', 'tinyint', 'smallint', 'uuid', 'guid'], true)) { // Číselné a UUID typy
			return "'" . implode(',', $g) . "'";                            // Spojení do jednoho řetězcového literálu
		}
	}
	return $g;                                                              // Vrácení hodnoty
}

/*
	HTML_SELECT: vrátí HTML syntaxi selectu
*/
function html_select($name, $values, $selectedvalue = "~~--~~", $attributes = "", $addSelectedValue = true) { // Generování tagu <select>
	global $page_readonly;                                                  // Globální příznak stránky pouze pro čtení
	$r = "";                                                                // Sestavovaný HTML kód opcí
	$selectedStyle = "";                                                    // Styl vybrané položky
	if ($selectedvalue === "~~--~~" AND is_array($values)) {                // Pokud nebyla vybraná hodnota předána
		$selectedvalue = @array_keys($values)[0];                           // Vybereme první klíč v poli
	}
	$selectedvalue = (string)$selectedvalue;                                // Přetypování vybrané hodnoty na string
	$selectedOv = htmlliteral($selectedvalue);                              // HTML literál vybrané hodnoty
	
	if ($addSelectedValue AND (!is_array($values) OR !array_key_exists($selectedvalue, $values))) { // Chybějící hodnota v číselníku
		if (!($selectedvalue === 'NULL' AND is_array($values) AND array_key_exists('', $values))) { // Výjimka pro NULL/prázdný klíč
			$empty_option = (is_string($addSelectedValue) AND !$selectedvalue) ? $addSelectedValue : $selectedvalue; // Text volby
			$r = "<option value=\"$selectedvalue\" selected style=\"color:red\">$empty_option</option>"; // Červená opce chybějící hodnoty
		}
	}
	if (is_array($values)) {                                                // Průchod položkami seznamu
		foreach ($values as $optionvalue => $option) {                      // Zpracování každé položky
			$optionvalue = (string)$optionvalue;                            // Klíč položky jako string
			$selected = '';                                                 // Příznak selected
			$optionTitle = '';                                              // Tooltip položky
			$style = '';                                                    // Inline styl položky
			if (is_array($option)) {                                        // Složená položka s dalšími atributy
				if (array_key_exists('optiontext', $option)) {              // Text v klíči optiontext
					$optiontext = $option['optiontext'];                    // Text položky
				} elseif (array_key_exists('name', $option)) {              // Text v klíči name
					$optiontext = $option['name'];                          // Text položky
				} else {
					$optiontext = "$optionvalue optiontext";                // Fallback textu položky
				}
				$opt_title_val = array_item($option, 'optiontitle');        // Hledání titulku položky
				if ($opt_title_val) {                                       // Pokud má položka titulek
					$optionTitle = " title=" . htmlliteral($opt_title_val); // Atribut title
				}
				$style = array_key_exists('backgroundcolor', $option) ? "background-color:$option[backgroundcolor];" : ""; // Pozadí
				$style .= array_key_exists('color', $option) ? "color:$option[color];" : ""; // Barva textu
				if (array_key_exists('style', $option)) {                   // Explicitní styl položky
					$style = $option['style'];                              // Přepsání stylem položky
				}
				if (array_key_exists('selected', $option)) {                // Explicitní označení vybrané položky
					$selected = $option['selected'] ? 'selected' : '';      // Nastavení selected
				}
			} else {
				$optiontext = $option;                                      // Jednoduchá textová položka
			}
			$ov = htmlliteral($optionvalue);                                // Ošetřená hodnota value
			$ot = htmlspecialchars((string)($optiontext ?? ''));            // Ošetřený zobrazovaný text
			if ($style) {                                                   // Obalení stylu do atributu style
				$style = "style=\"$style\"";                                // HTML atribut style
			}
			if ($optionvalue == $selectedvalue) {                           // Shoda s vybranou hodnotou
				$selected = 'selected';                                     // Označení aktivní položky
				$selectedOv = $ov;                                          // Uložení vybrané hodnoty pro hidden input
			}
			if ($selected) {                                                // Převzetí stylu aktivní položky pro select
				$selectedStyle = $style;                                    // Styl pro samotný select
			}
			$r .= "\n\t\t<option value=$ov $selected $style$optionTitle>$ot</option>"; // Přidání tagu <option>
		}
	}
	$id = (strpos((string)$attributes, "multiple") === false) ? "id=\"$name\"" : ""; // Atribut id (pokud nejde o multiple)
	if ($page_readonly) {                                                   // V readonly režimu doplníme hidden pole
		return "\n\t\t<select $id name=\"$name\" $attributes disabled $selectedStyle>$r</select>\n\t\t<input type=hidden id=\"hidden_$name\" name=\"$name\" value=$selectedOv>"; // Readonly select
	}
	return "<select $id name=\"$name\" $attributes $selectedStyle>$r</select>"; // Aktivní select
}

function html_radio($name, $value, $selectedvalue, $attributes = '') {      // Generování tagu <input type=radio>
	$v = htmlspecialchars((string)$value);                                  // Ošetřená hodnota přepínače
	$checked = ($value == $selectedvalue) ? ' checked' : '';                // Označení vybraného přepínače
	return "<input type=radio name=\"$name\" value=\"$v\"$checked $attributes>"; // HTML tag radio
}

function html_textarea($name, $value, $attr = '') {                         // Generování tagu <textarea>
	if (!$attr) {                                                           // Výchozí atribut id
		$attr = "id=\"$name\"";                                             // Nastavení id podle jména
	}
	return "<textarea name=\"$name\" $attr>" . htmlspecialchars((string)$value) . "</textarea>"; // HTML tag textarea
}

/*
	Funkce hidden_input generuje HTML syntaxi pro <input type=hidden ...>
	parametry mohou být předány v poli (jediný parametr jako $_POST) nebo zvlášť.
*/
function hidden_input($name, $value = '', &$append = '') {                  // Generování skrytého formulářového pole
	if (is_array($name)) {                                                  // Hromadné generování z asociativního pole
		$r = '';                                                            // Sběrný HTML řetězec
		foreach ($name as $n => $v) {                                       // Průchod klíči a hodnotami pole
			if (is_array($v)) {                                             // Vnořené pole hodnot
				foreach ($v as $vv) {                                       // Průchod prvky vnořeného pole
					$r .= hidden_input($n . '[]', $vv);                     // Skryté pole pro prvek pole
				}
			} else {
				$r .= hidden_input($n, $v);                                 // Skryté pole pro skalární hodnotu
			}
		}
		$append .= $r;                                                      // Připojení k výstupnímu řetězci
		return $r;                                                          // Vrácení vygenerovaných inputů
	}
	$name = htmlspecialchars((string)$name);                                // Ošetření názvu pole
	if (is_array($value)) {                                                 // Pokud je hodnota polem
		foreach ($value as $v) {                                            // Průchod prvky pole
			$append = hidden_input($name . '[]', $v, $append);              // Rekurzivní přidání položek pole
		}
	} else {
		$value = htmlspecialchars((string)$value);                          // Ošetření hodnoty pole
		$append .= "<input type=hidden name=\"$name\" value=\"$value\">";   // Připojení tagu <input type=hidden>
	}
	return $append;                                                         // Vrácení výsledného HTML
}

function checkbox_input($name, $value, $checkvalue, $label = '', $attr = '') { // Generování jednoduchého checkboxu
	$checked = ($value == $checkvalue) ? 'checked' : '';                    // Vyhodnocení stavu zaškrtnutí
	$val_safe = htmlspecialchars((string)$value);                           // Ošetřená hodnota atributu value
	$input = "<input type=checkbox name=\"$name\" value=\"$val_safe\" $checked $attr>"; // HTML tag checkboxu
	return $label ? "<label>$input$label</label>" : $input;                 // Obalení tagem <label>, pokud je zadán popisek
}

function html_checkbox($name, $checkvalue, $attr = '', $value = 1, $readonly = 0) { // Generování checkboxu s podporou readonly
	global $page_readonly;                                                  // Globální příznak readonly stránky
	$checked = ($value == $checkvalue) ? 'checked' : '';                    // Stav zaškrtnutí
	$val = htmlliteral($value);                                             // HTML literál hodnoty
	$name_lit = htmlliteral($name);                                         // HTML literál jména
	$hidden = $checked ? "<input type=hidden name=$name_lit id=$name_lit value=$val>" : ''; // Skryté pole pro readonly stav
	if ($page_readonly OR $readonly) {                                      // Pokud je prvek pouze pro čtení
		return "<input type=checkbox value=$val $checked disabled>$hidden"; // Deaktivovaný checkbox se skrytou hodnotou
	}
	return "<input type=checkbox id=$name_lit name=$name_lit value=$val $checked $attr>"; // Aktivní checkbox
}

function validateDate($input, $time = true) {                               // Validace a normalizace data pro HTML5 input
	$formats = [                                                            // Podporované formáty data
		'ODBC'  => ['Y-m-d H:i', 'Y-m-d'],
		'local' => ['d.m.Y H:i', 'd.m.Y'],
	];                                                                      // Konec definice formátů

	if ($input !== null) {                                                  // Pokud vstup není null
		foreach ($formats as $formatList) {                                 // Průchod skupinami formátů
			foreach ($formatList as $format) {                              // Průchod jednotlivými formáty
				$dateTime = DateTime::createFromFormat($format, (string)$input); // Pokus o vytvoření objektu DateTime
				if ($dateTime !== null AND $dateTime !== false) {           // Pokud datum odpovídá formátu
					return $time ? $dateTime->format('Y-m-d H:i') : $dateTime->format('Y-m-d'); // Formátovaný výstup
				}
			}
		}
	}
	return '';                                                              // Neplatné nebo prázdné datum
}

// S přechodem na PHP 8 je funkce zcela předělána, protože prohlížeče už nyní podporují input type date nebo datetime-local
function HTML_Calendar($name, $input_value = '', $mandatory = false, $time = false) { // HTML5 kalendářový prvek
	global $page_readonly;                                                  // Globální příznak readonly stránky
	$value = validateDate($input_value, $time);                             // Validace vstupního data
	$m = $mandatory ? 'required' : '';                                      // Atribut povinného pole
	$width = ($time ? 100 : 75) . "px";                                     // Šířka pole podle přítomnosti času
	if ($page_readonly) {                                                   // Readonly zobrazení data
		return "<div style=display:table-cell;white-space:nowrap; class=\"yui-skin-sam\">
			<input type=text name=\"$name\" $m min=\"1900-01-01\" max=\"2120-01-01\" id=\"$name\" style=\"margin:0px;width:$width;padding:0px;background-color:gainsboro;\" value=\"$input_value\" readonly>
		</div>";                                                            // Uzamčené pole data
	}

	$type = $time ? 'datetime-local' : 'date';                              // Volba HTML5 typu inputu
	$style = $value ? "" : "style='color:white;' onkeydown=\"this.style.color='black';\" oninput=\"this.style.color='black';\""; // Styl prázdného pole
	return "<input type=$type $m name=\"$name\" id=\"$name\" min=\"1900-01-01\" max=\"2120-01-01\" value=\"$value\" $style>"; // HTML5 input
}

// DEBUGITEM: Funkce uloží do globálního pole debugitems položku pro pozdější výpis
function debugitem($label, $text = '', $utf8 = false) {                     // Přidání položky do ladicího výpisu
	global $debugitems, $debugmode, $charset;                               // Globální proměnné debugu
	if (!$debugmode) {                                                      // Pokud není aktivní ladicí režim
		return;                                                             // Nic neukládáme
	}
	if (!is_array($debugitems)) {                                           // Inicializace pole debug položek
		$debugitems = [];                                                   // Prázdné pole
	}
	
	$p = new stdClass();                                                    // Objekt ladicí položky
	$p->label = $label;                                                     // Popisek položky
	$p->text = $text;                                                       // Obsah položky
	$p->utf8 = ($utf8 OR ($charset == 'UTF-8'));                            // Příznak UTF-8 kódování
	$p->isres = false;                                                      // Příznak resource typu
	
	if (is_resource($p->text)) {                                            // Pokud jde o systémový resource
		$p->isres = true;                                                   // Označíme jako resource
		$p->text = (string)$p->text;                                        // Převedeme identifikátor na text
	}
	
	array_push($debugitems, $p);                                            // Zařazení do seznamu ladicích položek
}

function debugget() {                                                       // Vložení všech superglobálních polí do debugu
	debugitem('GET', $_GET);                                                // Výpis pole $_GET
	if (isset($_POST)) {                                                    // Pokud existuje $_POST
		debugitem('POST', $_POST);                                          // Výpis pole $_POST
	}
	if (isset($_SESSION)) {                                                 // Pokud existuje $_SESSION
		debugitem('SESSION', $_SESSION);                                    // Výpis pole $_SESSION
	}
	if (isset($_FILES) AND count($_FILES)) {                                // Pokud byly odeslány soubory
		debugitem('FILES', $_FILES);                                        // Výpis pole $_FILES
	}
	if (isset($_COOKIE)) {                                                  // Pokud existují cookies
		debugitem('COOKIE', $_COOKIE);                                      // Výpis pole $_COOKIE
	}
}

function debugg($name) {                                                    // Výpis globální proměnné podle jména do debugu
	debugitem($name, array_item($GLOBALS, $name, 'Undefined variable'));    // Přidání globální proměnné do debugu
}

function debugdatarow($globalVariable = 'datarow') {                        // Výpis datového řádku bez číselných klíčů
	$data = $GLOBALS[$globalVariable] ?? [];                                // Načtení cílové globální proměnné
	if (is_array($data)) {                                                  // Pokud jde o pole
		array_unset_numeric_keys($data);                                    // Odstranění duplicitních číselných indexů
	}
	debugitem($globalVariable, $data);                                      // Zápis do debugu
}

function debugtime($label = '') {                                           // Zápis aktuálního času do debugu
	debugitem("TIME $label", date('H:i:s'));                                // Časová značka
}

function array_unset_numeric_keys(&$array) {                                // Rekurzivní odstranění číselných klíčů z pole
	foreach ($array as $key => &$val) {                                     // Průchod prvky pole
		if (is_array($val)) {                                               // Pokud je prvek vnořeným polem
			array_unset_numeric_keys($val);                                 // Rekurzivní vyčištění vnořeného pole
		} elseif (is_numeric($key)) {                                       // Pokud je klíč číselný
			unset($array[$key]);                                            // Odstranění číselného klíče
		}
	}
}

/*
	Funkce addArrayKeysInfo
	Přidá informace o klíčích pole pro účely debugu, pokud nejsou numerické a je víc nez jeden
*/
function addArrayKeysInfo(&$a, $nk, $recursion) {                           // Doplnění přehledu vnořených polí pro debug
	foreach ($recursion as &$rr) {                                          // Kontrola zacyklení referencí
		if ($a === $rr) {                                                   // Detekce rekurzivní reference
			return;                                                         // Ukončení při rekurzi
		}
	}
	if (is_array($a)) {                                                     // Pouze pokud je vstup pole
		if (array_key_exists('NESTED_ARRAYS', $a)) {                        // Pokud již přehled obsahuje
			return $a;                                                      // Nepřidáváme znovu
		}
		$keyList = [];                                                      // Seznam vnořených polí a jejich velikostí
		$keyCount = 0;                                                      // Počet nalezených vnořených polí
		foreach ($a as $k => &$i) {                                         // Průchod prvky pole
			if (!is_numeric($k) AND is_array($i)) {                         // Asociativní klíč obsahující pole
				$ic = count($i);                                            // Počet prvků vnořeného pole
				$keyList[$k] = $ic;                                         // Uložení počtu prvků
				$recursion[] = &$a;                                         // Zápis do seznamu navštívených uzlů
				addArrayKeysInfo($a[$k], "$nk/$k", $recursion);             // Rekurzivní průchod potomkem
				$keyCount++;                                                // Inkrementace počitadla
			}
		}
		if ($keyCount AND $keyList) {                                       // Pokud byly nalezeny vnořené struktury
			$a = ['NESTED_ARRAYS' => $keyList] + $a;                        // Předřazení přehledu na začátek pole
		}
	}
}

function debugprint($noprint = false) {                                     // Sestavení a volitelný výpis ladicího bloku
	global $debugitems, $debugmode, $debugContent, $charset;                // Globální proměnné ladění
	
	if (is_array($debugitems) AND count($debugitems) > 0 AND $debugmode) {  // Pokud jsou k dispozici ladicí záznamy
		$debugContent = "\n<DIV><H1>DEBUG:</H1>";                           // Záhlaví debug sekce
		foreach ($debugitems as $item) {                                    // Průchod uloženými položkami
			$val = $item->text;                                             // Hodnota ladicí položky
			
			if ($val === null) {                                            // Zobrazení hodnoty null
				$val = '--NULL--';                                          // Textová reprezentace null
			} elseif ($val === false) {                                     // Zobrazení hodnoty false
				$val = '--FALSE--';                                         // Textová reprezentace false
			} elseif ($val === true) {                                      // Zobrazení hodnoty true
				$val = '--TRUE--';                                          // Textová reprezentace true
			}
			
			$debugContent .= "<br /><span style=\"color:blue;font-weight:bold;\">" . htmlspecialchars((string)$item->label) . ": </span>"; // Popisek
			
			if (is_array($val) OR is_object($val)) {                        // Výpis složené struktury (pole/objekt)
				$recursion = [];                                            // Pole pro sledování rekurze
				addArrayKeysInfo($val, $item->label, $recursion);           // Doplnění informací o vnořených polích
				$str_val = to_string($val);                                 // Bezpečný převod struktury na text
				if ($item->utf8 AND $charset != 'UTF-8') {                  // Případný převod znakové sady
					$str_val = from_utf8($str_val);                         // Konverze z UTF-8
				}
				$debugContent .= "<pre style=\"display:inline;margin:0;\">" . htmlspecialchars($str_val) . "</pre>"; // Formátovaný výpis
			} else {
				if ($item->isres OR is_resource($val) OR strpos(gettype($val), 'resource') !== false) { // Výpis resource
					$debugContent .= (string)$val;                          // Přímý převod na řetězec
				} else {
					$debugContent .= nl2br(htmlspecialchars((string)$val)); // Ošetřený výpis běžného textu
				}
			}
		}
		$debugContent .= '</DIV>';                                          // Uzavření debug sekce
	}
	
	if (!$noprint) {                                                        // Pokud není potlačen přímý výpis
		print $debugContent;                                                // Vypsání na výstup
	}
	return $debugContent ?? '';                                             // Vrácení sestaveného HTML
}

function debugerror($context) {                                             // Zápis poslední chyby PHP do debugu
	global $php_errormsg;                                                   // Globální proměnná chyby
	if ($php_errormsg) {                                                    // Pokud je chybová zpráva neprázdná
		debugitem("ERROR $context", $php_errormsg);                         // Zápis do ladicího výpisu
		$php_errormsg = '';                                                 // Vyčištění chybové proměnné
	}
}

function private_file($fn) {                                                // Cesta k soukromému souboru uživatele
	global $private_folder, $dbsession;                                     // Složka a relace
	$u = $dbsession['user_name'] ?? 'unknown';                              // Jméno přihlášeného uživatele
	return "$private_folder/{$u}_$fn";                                      // Sestavená cesta k souboru
}

/**
 * Centrální funkce pro bezpečné odesílání cookies s ohledem na HTTPS a SameSite politiku.
 *
 * @param string $name     Název cookie
 * @param string $value    Hodnota cookie (výchozí prázdná)
 * @param int    $expires  Čas expirace (timestamp, výchozí 0 = do zavření prohlížeče)
 * @param string $samesite Politika SameSite ('Lax', 'Strict', 'None')
 * @param string $path     Cesta platnosti cookie
 */
function set_secure_cookie(string $name, string $value = '', int $expires = 0, string $samesite = 'Lax', string $path = '/'): void { // Nastavení cookie
	$isHttps = ((!empty($_SERVER['HTTPS']) AND $_SERVER['HTTPS'] !== 'off') OR ($_SERVER['SERVER_PORT'] ?? 80) == 443); // Detekce HTTPS
	
	$options = [                                                            // Parametry cookie
		'expires'  => $expires,                                             // Čas vypršení platnosti
		'path'     => $path,                                                // Cesta platnosti
		'domain'   => '',                                                   // Aktuální doména
		'secure'   => $isHttps,                                             // Příznak Secure při HTTPS
		'httponly' => true,                                                 // Ochrana proti přístupu z JS
		'samesite' => $samesite                                             // Politika SameSite
	];                                                                      // Konec parametrů cookie
	
	setcookie($name, $value, $options);                                     // Odeslání hlavičky cookie
}

/**
 * Zkrácený alias pro bezpečné a spolehlivé smazání cookie v prohlížeči.
 */
function delete_secure_cookie(string $name, string $samesite = 'Lax', string $path = '/'): void { // Smazání cookie
	set_secure_cookie($name, '', time() - 3600, $samesite, $path);          // Nastavení expirace do minulosti
}

function initsession() {                                                    // Inicializace a ověření uživatelské relace
	global $dbsession, $page, $SID, $right_sysadmin, $right_orgadmin, $right_developer; // Globální proměnné relace
	
	// Odhlášení uživatele, využíváme globální $page z index.php
	if (!$page) {                                                           // Pokud proměnná $page ještě nebyla nastavena
		$page = getinput('page');                                           // Načtení parametru page z požadavku
	}
	if ($page == "logout") {                                                // Zpracování požadavku na odhlášení
		$safeSid = charliteral($SID, 50);                                   // Bezpečný SQL literál session ID
		sqlrun("DELETE FROM wwwsession WHERE wwwsession = $safeSid");       // Odstranění relace z databáze
		
		// Zpracování trvalého odhlášení ("Remember Me")
		if (isset($_COOKIE['ramses_remember'])) {                           // Pokud existuje trvalá přihlašovací cookie
			$cookieParts = explode(':', (string)$_COOKIE['ramses_remember']); // Rozdělení na selector a validator
			if (count($cookieParts) === 2) {                                // Kontrola platného formátu
				$selector = $cookieParts[0];                                // Veřejný identifikátor tokenu
				$safeSelector = charliteral($selector, 64);                 // SQL literál selectoru
				sqlrun("DELETE FROM auth_tokens WHERE selector = $safeSelector"); // Smazání tokenu z databáze
			}
			set_secure_cookie('ramses_remember', '', time() - 3600, 'Strict'); // Zneplatnění cookie v prohlížeči
		}
	}
	
	// Přenos relace z wwwsession do dbsession pro aktuální @@SPID (načteno přes sqlfirstrow)
	$safeSid = charliteral($SID, 50);                                       // SQL literál session ID
	$raw_sess = sqlfirstrow("SET NOCOUNT ON; EXECUTE p_init_wwwsession @wwwsession = $safeSid, @no_result = 0"); // Inicializace relace v DB
	$dbsession = htmlspec($raw_sess);                                       // Ošetření načtených hodnot relace
	
	// Ošetříme stav, kdy user není přihlášen (wwwsession expirovala nebo neexistuje)
	if (empty($dbsession) OR (isset($dbsession[0]) AND $dbsession[0] < 0)) { // Pokud platná relace neexistuje
		
		// Záchyt - pokus o obnovení relace pomocí "Remember Me" cookie
		if (isset($_COOKIE['ramses_remember']) AND $page !== "logout") {    // Pokus o auto-login přes trvalý token
			$cookieParts = explode(':', (string)$_COOKIE['ramses_remember']); // Rozpad cookie na selector a validator
			
			if (count($cookieParts) === 2) {                                // Pokud má cookie obě části
				$selector = $cookieParts[0];                                // Identifikátor tokenu
				$validator = $cookieParts[1];                               // Tajný validátor z prohlížeče
				
				$safeSelector = charliteral($selector, 64);                 // SQL literál selectoru
				$sql = "SELECT user_account_uuid, hashed_validator FROM auth_tokens WHERE selector = $safeSelector AND expires > SYSDATETIME()"; // Dotaz na token
				$tokenRow = sqlfirstrow($sql);                              // Načtení tokenu z DB
				
				if (!empty($tokenRow)) {                                    // Pokud neexpirovaný token existuje
					$dbHash = trim((string)$tokenRow['hashed_validator']);  // Hash uložený v databázi
					$cookieHash = hash('sha256', $validator);               // SHA-256 hash validátoru z cookie
					
					if (hash_equals($dbHash, $cookieHash)) {                // Bezpečné porovnání hashů v konstantním čase
						$userUuid = trim((string)$tokenRow['user_account_uuid']); // UUID uživatele z tokenu
						$safeUserUuid = guidliteral($userUuid);             // SQL literál UUID uživatele
						$safeIp = charliteral(get_client_ip_path(), 200);   // SQL literál IP adresy klienta
						
						if (sqlrun("EXEC p_set_login @user_uuid = $safeUserUuid, @wwwsession = $safeSid, @client_ip = $safeIp")) { // Obnovení relace
							sqlrun("UPDATE auth_tokens SET last_used = SYSDATETIME(), ip_address = $safeIp WHERE selector = $safeSelector"); // Aktualizace času použití
							
							$raw_rec = sqlfirstrow("SET NOCOUNT ON; EXECUTE p_init_wwwsession @wwwsession = $safeSid, @no_result = 0"); // Načtení obnovené relace
							$dbsession = htmlspec($raw_rec);                // Uložení relace do $dbsession
						}
					} else {
						// Selektor existuje, ale hash validátoru nesedí -> okamžitě smazat token z databáze
						sqlrun("DELETE FROM auth_tokens WHERE selector = $safeSelector"); // Bezpečnostní výmaz kompromitovaného tokenu
					}
				}
			}
			
			// Pokud se obnova přes cookie nezdařila, vymažeme neplatnou cookie z prohlížeče
			if (empty($dbsession) OR (isset($dbsession[0]) AND $dbsession[0] < 0)) { // Kontrola neúspěšné obnovy
				set_secure_cookie('ramses_remember', '', time() - 3600, 'Strict'); // Smazání neplatné cookie
			}
		}
		
		// Pokud ani po pokusu o obnovu není uživatel přihlášen, přesměrujeme na login
		if (empty($dbsession) OR (isset($dbsession[0]) AND $dbsession[0] < 0)) { // Kontrola nepřihlášeného stavu
			$page = 'login';                                                // Nastavení cílové stránky na přihlášení
			return;                                                         // Ukončení inicializace relace
		}
	}

	// Extrakce oprávnění do samostatných globálních proměnných z nové struktury active_role
	$active_role = (string)($dbsession['active_role'] ?? 'U');              // Aktivní role v relaci (U, A, S, D)
	$right_developer = ($active_role === 'D') ? 1 : 0;                      // Příznak vývojáře
	$right_sysadmin  = ($active_role === 'S' OR $active_role === 'D') ? 1 : 0; // Příznak systémového administrátora
	$right_orgadmin  = ($active_role === 'A') ? 1 : 0;                      // Příznak administrátora organizace
}

function sendAlert($time) {                                                 // JS časovač pro upozornění na vypršení relace
	global $T_TIMEOUT_WARNING;                                              // Text varování
	print "<script>setTimeout(\"alert('$T_TIMEOUT_WARNING')\", $time);</script>"; // Výpis JS časovače
}

function selectColor($x) {                                                  // Střídání CSS tříd řádků tabulky
	return ($x % 2 == 0) ? "tr_even" : "tr_odd";                            // Sudý nebo lichý řádek
}

function even_odd(&$n, $inc = 1) {                                          // Střídání tříd odd a even s inkrementací
	if ($inc == 1) {                                                        // Pokud se má počitadlo zvýšit
		$n = (int)$n + 1;                                                   // Zvýšení počitadla o 1
	}
	return ($n % 2) ? 'odd' : 'even';                                       // Vrácení názvu CSS třídy
}

function even_odd2(&$n, $inc = 1) {                                         // Střídání tříd odd2 a even2
	if ($inc == 1) {                                                        // Pokud se má počitadlo zvýšit
		$n = (int)$n + 1;                                                   // Zvýšení počitadla o 1
	}
	return ($n % 2) ? 'odd2' : 'even2';                                     // Vrácení názvu CSS třídy
}

function normalize_percent($a, $base) {                                     // Normalizace pole hodnot na přesný celočíselný součet
	global $normalize_percent_sum, $normalize_percent_raw;                  // Globální proměnné pro mezivýsledky
	$normalize_percent_sum = 0;                                             // Celkový součet vstupních hodnot
	$t = 0;                                                                 // Součet zaokrouhlených hodnot
	$normalize_percent_raw = [];                                            // Pole přesných nezaokrouhlených podílů
	foreach ($a as $p) {                                                    // Výpočet celkového součtu
		$normalize_percent_sum += $p;                                       // Přičtení položky
	}
	if (!$normalize_percent_sum) {                                          // Ochrana proti dělení nulou
		return $a;                                                          // Vrácení původního pole
	}
	foreach ($a as $i => $p) {                                              // Přepočet položek na cílovou základnu
		$raw = $base * $p / $normalize_percent_sum;                         // Přesný desetinný podíl
		$normalize_percent_raw[$i] = $raw;                                  // Uložení přesného podílu
		$x = ceil($raw);                                                    // Zaokrouhlení nahoru
		$a[$i] = $x;                                                        // Uložení zaokrouhlené hodnoty
		$t += $x;                                                           // Přičtení k součtu
	}
	arsort($a);                                                             // Seřazení sestupně pro korekci odchylky
	$diff = $t - $base;                                                     // Zjištění celkové odchylky od základny
	$i0 = 0;                                                                // Index poslední upravené položky
	if ($diff) {                                                            // Pokud vznikla odchylka zaokrouhlením
		foreach ($a as $i => $x) {                                          // Postupné snižování největších položek
			if ($x > 1) {                                                   // Pouze u položek větších než 1
				$a[$i] = $x - 1;                                            // Snížení o 1
				$diff--;                                                    // Snížení zbývající odchylky
				if ($diff) {                                                // Pokud odchylka ještě není nulová
					$i0 = $i;                                               // Zapamatování indexu
					continue;                                               // Pokračování na další prvek
				}
			} else {
				$a[$i0] = $a[$i0] - $diff;                                  // Odečtení zbytku od poslední větší položky
			}
			break;                                                          // Korekce dokončena
		}
	}
	ksort($a);                                                              // Obnovení původního pořadí klíčů
	return $a;                                                              // Vrácení normalizovaného pole
}

function from_utf8($v) {                                                    // Konverze textu z UTF-8 do interního charsetu
	global $charset;                                                        // Globální znaková sada
	return iconv("utf-8", $charset, (string)$v);                            // Převod přes iconv
}

// SQLPARAMETERS: Funkce sestaví string pro SQL parametry ve tvaru "@par1=$par1, @par2=$par2 ..."
function sqlparameters($list) {                                             // Sestavení seznamu pojmenovaných SQL parametrů z $GLOBALS
	$r = '';                                                                // Výsledný řetězec parametrů
	$pp = explode(',', (string)$list);                                      // Seznam názvů parametrů
	foreach ($pp as $p) {                                                   // Průchod názvy parametrů
		$p = trim($p);                                                      // Očištění názvu parametru
		if (!$p) {                                                          // Přeskočení prázdného názvu
			continue;                                                       // Další parametr
		}
		$val = array_key_exists($p, $GLOBALS) ? $GLOBALS[$p] : '0';         // Hodnota z $GLOBALS nebo výchozí '0'
		if (is_array($val)) {                                               // Pokud je hodnotou pole
			foreach ($val as &$v) {                                         // Průchod prvky pole
				if (is_array($v)) {                                         // Zákaz vnořených polí v SQL parametru
					fatal_error("array in sql-parameter");                  // Vyvolání chyby
				}
				if (substr((string)$v, 0, 1) === "'" AND substr((string)$v, -1, 1) === "'") { // Pokud je prvek v apostrofech
					$v = str_replace("''", "'", substr((string)$v, 1, -1)); // Odstranění vnějších apostrofů
				}
			}
			$val = charliteral(implode(',', $val));                         // Spojení pole do jednoho SQL literálu
		}
		$r .= ",\n@$p=$val";                                                // Připojení parametru do seznamu
	}
	return substr($r, 1);                                                   // Vrácení seznamu bez úvodní čárky
}

// FILL_ARRAY + UPDATE_ARRAY: naplní/updatuje hodnoty ze stringu "A=cosi;B=Cosi jiného"
function fill_array(&$aa, $s, $del2 = '=', $del1 = ';') {                   // Naplnění asociativního pole z řetězce
	$pp = explode($del1, (string)$s);                                       // Rozdělení na jednotlivé páry
	foreach ($pp as $p) {                                                   // Průchod páry
		$vv = explode($del2, $p);                                           // Rozdělení na klíč a hodnotu
		if (count($vv) < 2) {                                               // Přeskočení neúplného páru
			continue;                                                       // Další položka
		}
		$k = trim($vv[0]);                                                  // Očištěný klíč
		$v = trim($vv[1]);                                                  // Očištěná hodnota
		$aa[$k] = $v;                                                       // Zápis do cílového pole
	}
}

function update_array(&$aa, $s, $del2 = '=', $del1 = ';') {                 // Aktualizace existujících klíčů pole z řetězce
	$pp = explode($del1, (string)$s);                                       // Rozdělení na jednotlivé páry
	foreach ($pp as $p) {                                                   // Průchod páry
		$vv = explode($del2, $p, 2);                                        // Rozdělení na klíč a hodnotu
		if (count($vv) < 2) {                                               // Přeskočení neúplného páru
			continue;                                                       // Další položka
		}
		$k = trim($vv[0]);                                                  // Očištěný klíč
		$v = trim($vv[1]);                                                  // Očištěná hodnota
		if (array_key_exists($k, $aa)) {                                    // Pouze pokud klíč v poli již existuje
			$aa[$k] = $v;                                                   // Aktualizace hodnoty
		}
	}
}

function helptext_to_array($s, $del2 = '=', $del1 = ';') {                  // Převod konfiguračního řetězce na asociativní pole
	$aa = [];                                                               // Výstupní pole
	$pp = explode($del1, (string)$s);                                       // Rozdělení podle hlavního oddělovače
	foreach ($pp as $p) {                                                   // Průchod položkami
		$vv = explode($del2, $p, 2);                                        // Rozdělení na klíč a hodnotu
		if (count($vv) < 2) {                                               // Přeskočení neplatné položky
			continue;                                                       // Další položka
		}
		$aa[trim($vv[0])] = trim($vv[1]);                                   // Uložení očištěného klíče a hodnoty
	}
	return $aa;                                                             // Vrácení sestaveného pole
}

function write_log($s, $fileName = "Ramses.log") {                          // Zápis zprávy do logovacího souboru
	$sp = session_save_path();                                              // Cesta k úložišti session
	$dir = $sp ? $sp : ($_SERVER['TEMP'] ?? '.');                           // Volba adresáře pro log
	$fp = @fopen("$dir/$fileName", "a");                                    // Otevření souboru v režimu append
	if ($fp) {                                                              // Pokud se otevření zdařilo
		fputs($fp, date("\r\n===================\r\nY.m.d H:i:s") . "\r\n$s"); // Zápis časové značky a zprávy
		fclose($fp);                                                        // Uzavření souboru
	}
}

function implode_sql(&$a) {                                                 // Spojení pole do SQL literálu odděleného čárkou
	$a = is_array($a) ? charliteral(implode(',', $a)) : "''";               // Převod pole na SQL literál
}

function sqlresult_to_xml($q, $tag) {                                       // Převod otevřeného výsledku dotazu do XML elementů
	$rows = sqlarray_simple($q);                                            // Načtení řádků výsledku do pole
	$r = '';                                                                // Výstupní XML řetězec
	if (is_array($rows)) {                                                  // Kontrola platného pole
		foreach ($rows as $row) {                                           // Průchod řádky
			$att = '';                                                      // Atributy aktuálního XML tagu
			foreach ($row as $cn => $val) {                                 // Průchod sloupci řádku
				if (is_numeric($cn)) {                                      // Přeskočení číselných klíčů
					continue;                                               // Další sloupec
				}
				if ($val OR $val === 0 OR $val === '0') {                   // Pouze neprázdné hodnoty
					$val = str_replace("\n", '\n', str_replace("\r", '\r', (string)$val)); // Escape konců řádků
					$att .= " $cn=\"" . htmlspecialchars($val) . '"';       // Připojení XML atributu
				}
			}
			$r .= "\r\n<$tag$att />";                                       // Připojení XML elementu řádku
		}
	}
	return $r;                                                              // Vrácení XML obsahu
}

function xmloutput($r, $fn = '', $package = '') {                           // Odeslání XML dokumentu ke stažení
	global $charset;                                                        // Znaková sada aplikace
	if (!$fn) {                                                             // Výchozí název souboru
		$fn = "Export.xml";                                                 // Název XML souboru
	}
	if ($package) {                                                         // Volitelný atribut package
		$package = " package=" . xmlliteral($package);                      // Atribut kořenového elementu
	}
	header("Content-Type: text/xml; charset=$charset");                     // HTTP hlavička typu XML
	header("Content-Disposition: attachment; filename=\"$fn\"");            // HTTP hlavička přílohy
	print "<?xml version=\"1.0\" encoding=\"$charset\"?" . ">\n\t<RamsesData$package>\n\t$r\n\t</RamsesData>"; // Výpis XML
}

/*
	Export právě nastaveného result-setu nebo pole do CSV
*/
function csv_export($q = null, $delimiter = '', $headers = [], $excludeColumns = '') { // Export dat do CSV souboru
	global $charset, $dbquery, $exportFileName, $dbsession;                 // Globální kontext exportu
	if (is_string($q)) {                                                    // Posun parametrů při vynechání $q
		$excludeColumns = $headers;                                         // Posun vyloučených sloupců
		$headers = $delimiter;                                              // Posun hlaviček
		$delimiter = $q;                                                    // Posun oddělovače
		$q = null;                                                          // Výchozí dotaz
	} elseif (is_array($q) AND is_string($delimiter)) {                     // Pokud je $q pole dat
		// Ponecháme standardní pořadí
	}
	if (is_string($excludeColumns)) {                                       // Převod seznamu vyloučených sloupců na pole
		$excludeColumns = explode(',', $excludeColumns);                    // Pole vyloučených sloupců
	}
	if ($q === null) {                                                      // Pokud nebyl předán zdroj dat
		$q = sqlarray_simple($dbquery);                                     // Načteme otevřený result-set do pole
	} elseif (is_resource($q) OR is_object($q)) {                           // Pokud byl předán statement
		$q = sqlarray_simple($q);                                           // Načteme statement do pole
	}
	if (!$delimiter) {                                                      // Volba výchozího oddělovače podle jazyka relace
		$delimiter = in_array(($dbsession['language'] ?? ''), ['cs', 'sk'], true) ? ";" : ","; // Středník pro CS/SK
	}
	$n = 0;                                                                 // Počitadlo vypsaných řádků
	$fd = tmpfile();                                                        // Dočasný soubor pro sestavení CSV
	if (strtolower((string)$charset) === 'utf-8') {                         // Zápis UTF-8 BOM pro MS Excel
		fwrite($fd, "\xEF\xBB\xBF");                                        // Sekvence bajtů UTF-8 BOM
	}
	$header = [];                                                           // Pole názvů sloupců v záhlaví CSV
	if (is_array($q)) {                                                     // Průchod datovými řádky v poli
		foreach ($q as $row) {                                              // Zpracování jednoho řádku
			foreach ($excludeColumns as $ec) {                              // Odstranění vyloučených sloupců
				unset($row[$ec]);                                           // Výmaz sloupce z řádku
			}
			$clean_row = [];                                                // Řádek pouze s asociativními klíči
			foreach ($row as $cn => $val) {                                 // Filtrace číselných indexů z fetch()
				if (is_numeric($cn)) {                                      // Přeskočení číselného indexu
					continue;                                               // Další sloupec
				}
				if (!$n) {                                                  // Na prvním řádku posbíráme záhlaví
					$header[] = is_array($headers) ? array_item($headers, $cn, $cn) : $cn; // Název sloupce v záhlaví
				}
				if (is_numeric($val)) {                                     // Převod desetinné tečky na čárku
					$val = str_replace(".", ",", (string)$val);             // Desetinná čárka pro Excel
				}
				if ($delimiter === ';' AND strlen((string)($val ?? '')) > 30000) { // Omezení délky buňky pro Excel
					$val = substr((string)$val, 0, 30000);                  // Oříznutí příliš dlouhého textu
				}
				$clean_row[] = $val;                                        // Přidání hodnoty do řádku CSV
			}
			if (!$n) {                                                      // Zápis záhlaví před prvním datovým řádkem
				fputcsv($fd, $header, $delimiter, '"', '');                 // Zápis řádku záhlaví
			}
			fputcsv($fd, $clean_row, $delimiter, '"', '');                  // Zápis datového řádku
			$n++;                                                           // Inkrementace počitadla řádků
		}
	}
	fseek($fd, 0);                                                          // Přesun ukazatele na začátek dočasného souboru
	$ef = sanitize_filename($exportFileName ?: "Export");                   // Bezpečný název stahovaného souboru
	header("Content-Type: text/csv; charset=$charset");                     // Hlavička CSV souboru
	header("Content-Disposition: attachment; filename=\"$ef.csv\"");        // Hlavička pro stažení souboru
	header("Cache-Control: public");                                        // Povolení kešování stahovaného souboru
	while (!feof($fd)) {                                                    // Proudové odeslání obsahu souboru
		print fread($fd, 20000);                                            // Výpis bloku 20 KB
	}
	fclose($fd);                                                            // Uzavření a smazání dočasného souboru
	die();                                                                  // Ukončení skriptu po odeslání CSV
}

/*
	csv_into_array: funkce přežvýká obsah CSV souboru a výsledek uloží do pole.
*/
function csv_into_array($fn, $titles, &$out, $dbnames = '') {               // Načtení CSV souboru do asociativního pole
	global $errmsg, $csv_delimiter, $dbsession;                             // Globální proměnné pro CSV import
	
	$def_delim = in_array(($dbsession['language'] ?? ''), ['cs', 'sk'], true) ? ";" : ","; // Výchozí oddělovač dle jazyka
	$delimiter = $csv_delimiter ? $csv_delimiter : $def_delim;              // Použitý oddělovač sloupců
	$coltitles = is_array($titles) ? array_values($titles) : explode(',', (string)$titles); // Očekávané titulky sloupců
	$colnames = [];                                                         // Cílové klíče v poli
	if (is_array($titles)) {                                                // Pokud byly předány titulky jako pole
		$keys = array_keys($titles);                                        // Klíče pole titulků
		if (!is_numeric($keys[0])) {                                        // Pokud jsou klíče asociativní
			$colnames = $keys;                                              // Použijeme je jako názvy sloupců
		}
	}
	if ($dbnames OR count($colnames) === 0) {                               // Doplnění cílových názvů sloupců
		$colnames = is_array($dbnames) ? $dbnames : ($dbnames ? explode(',', (string)$dbnames) : $coltitles); // Cílové klíče
	}
	$fd = is_resource($fn) ? $fn : @fopen((string)$fn, 'r');                // Otevření CSV souboru ke čtení
	if ($fd) {                                                              // Pokud se soubor podařilo otevřít
		$cols = fgetcsv($fd, 0, $delimiter, '"', "\xFF");                   // Načtení prvního řádku se záhlavím
		if (is_array($cols)) {                                              // Kontrola platného záhlaví
			foreach ($cols as &$c) {                                        // Očištění názvů sloupců v záhlaví
				$c = trim((string)$c);                                      // Oříznutí bílých znaků
			}
			$colindex = [];                                                 // Mapa indexů požadovaných sloupců
			foreach ($coltitles as $i => $ct) {                             // Hledání požadovaných sloupců v záhlaví
				$ci = array_search($ct, $cols);                             // Index sloupce v CSV souboru
				if ($ci === false) {                                        // Pokud povinný sloupec chybí
					$errmsg .= "<H3 style=color:red>Required column header '$ct' not found</H3>"; // Zápis chyby
				} else {
					$colindex[$i] = $ci;                                    // Uložení nalezeného indexu
				}
			}
			if (!$errmsg) {                                                 // Pokud byly všechny sloupce nalezeny
				while ($a = fgetcsv($fd, 0, $delimiter, '"', "\xFF")) {     // Čtení datových řádků CSV
					$row = [];                                              // Nový datový řádek
					foreach ($coltitles as $i => $ct) {                     // Průchod požadovanými sloupci
						$ci = $colindex[$i];                                // Index sloupce v CSV
						$v = array_key_exists($ci, $a) ? $a[$ci] : "";      // Hodnota buňky
						$cn = $colnames[$i];                                // Cílový klíč sloupce
						$row[$cn] = $v;                                     // Uložení hodnoty do řádku
					}
					$out[] = $row;                                          // Přidání řádku do výstupního pole
				}
			}
		} else {
			print "<H3 style=color:red>Delimiter is not recognized</H3>";   // Chyba nerozpoznaného oddělovače
			fclose($fd);                                                    // Uzavření souboru
			return false;                                                   // Návrat s chybou
		}
		fclose($fd);                                                        // Uzavření CSV souboru
		return $errmsg ? false : true;                                      // Vrácení výsledku načtení
	}
	print "<H3 style=color:red>Unexpected error at opening file</H3>";      // Chyba při otevírání souboru
	return false;                                                           // Návrat s chybou
}

function insert_request_message($msgtext, $charvalue) {                     // Vložení zprávy do lokálního PHP seznamu zpráv
	global $request_message_list;                                           // Globální pole zpráv
	if (!is_array($request_message_list)) {                                 // Inicializace pole zpráv
		$request_message_list = [];                                         // Prázdné pole
	}
	$request_message_list[] = ['msgtext' => $msgtext, 'charvalue' => $charvalue]; // Přidání zprávy
}

// request_messages: Funkce vrátí tabulku pro tisk zpráv ze serveru
function request_messages($q = null) {                                      // Vykreslení tabulky zpráv z tabulky request_message
	global $datarow, $htmldatarow, $T_SERVER_MESSAGES, $max_request_message_severity, $requestMsgs, $request_message_list, $T_CAPTION, $T_DETAIL, $T_OBJECT, $rqm; // Globální kontext zpráv
	$rqm = new request_message();                                           // Instance třídy request_message
	$item_header = $T_SERVER_MESSAGES;                                      // Výchozí nadpis tabulky zpráv
	$max_request_message_severity = -1;                                     // Výchozí maximální závažnost
	if (!is_resource($q) AND !is_object($q)) {                              // Pokud nebyl předán otevřený statement
		if (is_string($q) AND $q !== '') {                                  // Pokud byl předán vlastní nadpis
			$item_header = $q;                                              // Použijeme vlastní nadpis
		}
		$a = sqlarray_simple("EXECUTE select_request_message");             // Načtení zpráv ze serveru do pole
	} else {
		$a = sqlarray_simple($q);                                           // Načtení zpráv z předaného statementu
	}
	$r = '';                                                                // Sestavované HTML řádků zpráv
	$hObjtype = '';                                                         // Záhlaví sloupce typu objektu
	$hObjname = '';                                                         // Záhlaví sloupce názvu objektu
	$hDetail = '';                                                          // Záhlaví sloupce detailu
	$existsObjtype = 0;                                                     // Příznak existence sloupce obj_type
	$existsObjname = 0;                                                     // Příznak existence sloupce obj_name
	$existsDetail = 0;                                                      // Příznak existence sloupce detailu
	if (is_array($a)) {                                                     // Kontrola platného pole zpráv
		foreach ($a as $datarow) {                                          // Zjištění nepoužitých sloupců
			if (!$existsObjtype AND !empty($datarow['obj_type'])) {         // Pokud je vyplněn typ objektu
				$existsObjtype = 1;                                         // Zapneme sloupec typu objektu
				$hObjtype = "<th>$T_OBJECT";                                // HTML záhlaví typu objektu
			}
			if (!$existsObjname AND !empty($datarow['obj_name'])) {         // Pokud je vyplněn název objektu
				$existsObjname = 1;                                         // Zapneme sloupec názvu objektu
				$hObjname = "<th>$T_CAPTION";                               // HTML záhlaví názvu objektu
			}
			if (!$existsDetail AND (!empty($datarow['charvalue']) OR !empty($datarow['intvalue']))) { // Pokud je vyplněn detail
				$existsDetail = 1;                                          // Zapneme sloupec detailu
				$hDetail = "<th>$T_DETAIL";                                 // HTML záhlaví detailu
			}
		}
		$default_colors = ['black', 'green', 'blue', 'red'];                // Barvy podle úrovně závažnosti (0..3)
		foreach ($a as $datarow) {                                          // Vykreslení jednotlivých řádků zpráv
			$htmldatarow = htmlspecbr($datarow);                            // Ošetření HTML znaků v řádku
			$indent = 10 * (int)$datarow['indent'] + 2;                     // Výpočet odsazení zleva v pixelech
			$severity = (int)$datarow['severity'];                          // Závažnost zprávy
			if ($severity > $max_request_message_severity) {                // Aktualizace nejvyšší zjištěné závažnosti
				$max_request_message_severity = $severity;                  // Uložení maxima
			}
			
			$cv = $htmldatarow['charvalue'];                                // Textová hodnota detailu
			if (array_key_exists($cv, $GLOBALS)) {                          // Případný překlad přes globální proměnnou
				$cv = $GLOBALS[$cv];                                        // Dosazení globální hodnoty
			}
			$int_c = $datarow['intvalue'];                                  // Číselná hodnota detailu (např. počet řádků)
			$v = ($int_c !== null) ? "<td align=right>$int_c</td>" : "<td>$cv</td>"; // Buňka detailu
			$txt = replace_phrase(array_item($datarow, 'msgtext'));         // Text hlavní zprávy
			$obj_type = replace_phrase(array_item($datarow, 'obj_type'));   // Text typu objektu
			$obj_type_td = $existsObjtype ? "<td>$obj_type" : "";           // Buňka typu objektu
			$obj_name_td = $existsObjname ? "<td>$htmldatarow[obj_name]" : ""; // Buňka názvu objektu
			$color = array_item($datarow, 'color') ?: array_item($default_colors, $severity, 'dimgray'); // Barva řádku
			if (!$existsDetail) {                                           // Skrytí buňky detailu, pokud je prázdná
				$v = '';                                                    // Prázdný detail
			}
			$r .= "<tr style=\"color:$color;$datarow[style]\" ><td style=padding-left:$indent>$txt$obj_type_td$obj_name_td$v</tr>"; // Řádek
		}
	}
	debugprint();                                                           // Výpis případných ladicích informací
	if (is_array($request_message_list)) {                                  // Připojení zpráv přidaných přímo v PHP
		foreach ($request_message_list as $rqm_item) {                      // Průchod lokálními zprávami
			$txt = $rqm_item['msgtext'];                                    // Text lokální zprávy
			if (array_key_exists($txt, $GLOBALS)) {                         // Překlad přes $GLOBALS
				$txt = $GLOBALS[$txt];                                      // Dosazení překladu
			}
			$r .= "<tr><td>$txt<td>$rqm_item[charvalue]</tr>";              // Přidání řádku lokální zprávy
		}
	}
	if ($r) {                                                               // Pokud existují zprávy k zobrazení
		$requestMsgs = "
		<table class='server_messages request_messages' cellpadding=3 border=1>
		<tr style=font-weight:bold><th>$item_header$hObjtype$hObjname$hDetail</tr>
		$r
		</table>";                                                          // Kompletní HTML tabulka zpráv
		return $requestMsgs;                                                // Vrácení tabulky zpráv
	}
	return '';                                                              // Žádné zprávy
}

function replace_phrase($txt) {                                             // Nahrazení kódu fráze z pole $GLOBALS
	return array_item($GLOBALS, $txt, $txt);                                // Vrácení hodnoty z $GLOBALS nebo původního textu
}

// Funkce in_array_fix zkontroluje, zda je parametr v poli; pokud není, nastaví ho na hodnotu prvního prvku
function in_array_fix(&$s, $a) {                                            // Omezení hodnoty proměnné na povolený výčet
	$pole = is_array($a) ? $a : explode(',', (string)$a);                   // Převod výčtu na pole
	if (in_array($s, $pole)) {                                              // Pokud je hodnota v povoleném seznamu
		return $s;                                                          // Vrátíme ji beze změny
	}
	foreach ($pole as $item) {                                              // Jinak vybereme první prvek seznamu
		$s = $item;                                                         // Nastavení výchozí hodnoty
		return $s;                                                          // Vrácení výchozí hodnoty
	}
	return $s;                                                              // Vrácení hodnoty
}

/*
	Funkce pro praci s poli
*/
function array_item($array, $key, $default = '') {                          // Bezpečné čtení prvku z pole s výchozí hodnotou
	if (is_array($array) AND array_key_exists($key, $array)) {              // Kontrola pole a existence klíče
		return $array[$key];                                                // Vrácení nalezené hodnoty
	}
	return $default;                                                        // Vrácení výchozí hodnoty
}

function &array_item_ref(&$array, $key, $default = '') {                    // Bezpečné čtení prvku z pole přes referenci
	if (is_array($array) AND array_key_exists($key, $array)) {              // Kontrola pole a existence klíče
		return $array[$key];                                                // Vrácení reference na prvek pole
	}
	return $default;                                                        // Vrácení reference na výchozí hodnotu
}

function array_push_distinct(&$array, $val) {                               // Přidání unikátní hodnoty na konec pole
	if (is_array($val)) {                                                   // Pokud je přidáváno pole hodnot
		foreach ($val as $v) {                                              // Průchod přidávanými hodnotami
			if (!in_array($v, $array, true)) {                              // Kontrola unikátnosti
				array_push($array, $v);                                     // Přidání na konec pole
			}
		}
	} else {
		if (!in_array($val, $array, true)) {                                // Kontrola unikátnosti skalární hodnoty
			array_push($array, $val);                                       // Přidání na konec pole
		}
	}
}

function array_unshift_distinct(&$array, $val) {                            // Přidání unikátní hodnoty na začátek pole
	if (is_array($val)) {                                                   // Pokud je přidáváno pole hodnot
		foreach ($val as $v) {                                              // Průchod přidávanými hodnotami
			if (!in_array($v, $array, true)) {                              // Kontrola unikátnosti
				array_unshift($array, $v);                                  // Vložení na začátek pole
			}
		}
	} else {
		if (!in_array($val, $array, true)) {                                // Kontrola unikátnosti skalární hodnoty
			array_unshift($array, $val);                                    // Vložení na začátek pole
		}
	}
}

function array_replace_ref(&$a, $b) {                                       // Přepsání klíčů pole $a hodnotami z pole $b
	foreach ($b as $k => $v) {                                              // Průchod zdrojovým polem
		$a[$k] = $v;                                                        // Přepsání prvku v cílovém poli
	}
}

function array_replace_globals($b) {                                        // Zápis prvků pole do globálního pole $GLOBALS
	foreach ($b as $k => $v) {                                              // Průchod asociativním polem
		$GLOBALS[$k] = $v;                                                  // Uložení do $GLOBALS
	}
}

function odbcDate($str) {                                                   // Formátování ISO data (YYYY-MM-DD) na české DD.MM.YYYY
	$str = (string)($str ?? '');                                            // Přetypování na řetězec
	return $str ? (substr($str, 8, 2) . '.' . substr($str, 5, 2) . '.' . substr($str, 0, 4)) : ''; // České datum
}

function odbcDateTime($str) {                                               // Formátování ISO data a času na české DD.MM.YYYY HH:MM
	$str = (string)($str ?? '');                                            // Přetypování na řetězec
	return $str ? (substr($str, 8, 2) . '.' . substr($str, 5, 2) . '.' . substr($str, 0, 4) . substr($str, 10)) : ''; // České datum a čas
}

function date_format4($d, $len = 10) {                                      // Formátování data na d.m.Y H:i s oříznutím délky
	if (!$d) {                                                              // Prázdné datum vrací prázdný řetězec
		return '';                                                          // Prázdný výstup
	}
	return substr(date_format(new DateTime((string)$d), 'd.m.Y H:i'), 0, $len); // Zformátované datum
}

// Funkce provede redirect na aktuální nebo cílovou stránku (PRG vzor zabraňující opětovnému odeslání POST)
function autoredirect($target = '') {                                       // Přesměrování po zpracování formuláře (PRG vzor)
	global $STRIPPED_URI;                                                   // Globální původní URI
	if (count($_POST) OR $target) {                                         // Pokud šlo o POST nebo je zadán cíl
		if (!$target) {                                                     // Výchozí cíl je aktuální URI
			$target = $STRIPPED_URI;                                        // Převzetí aktuální URI
		}
		if (headers_sent()) {                                               // Pokud již byly odeslány HTTP hlavičky
			print "<script>document.location=" . jsliteral($target) . ';</script>'; // Přesměrování přes JavaScript
		} else {
			header("Location: $target");                                    // Standardní HTTP 302 přesměrování
		}
		die();                                                              // Okamžité ukončení běhu skriptu
	}
}

function rebuild_uri($params = null) {                                      // Sestavení URI s upravenými GET parametry
	global $STRIPPED_URI;                                                   // Základní URI
	if ($params === null) {                                                 // Výchozí parametry z $_GET
		$params = &$_GET;                                                   // Reference na $_GET
	}
	$a = parse_url((string)$STRIPPED_URI);                                  // Rozparsování cesty URI
	$path = $a['path'] ?? 'index.php';                                      // Cesta ke skriptu
	return "$path?" . http_build_query($params);                            // Složení nové URI
}

function reload($params = null) {                                           // Okamžité znovunačtení stránky s parametry
	global $STRIPPED_URI;                                                   // Základní URI
	if ($params === null) {                                                 // Výchozí parametry z $_GET
		$params = $_GET;                                                    // Kopie $_GET
	}
	$a = parse_url((string)$STRIPPED_URI);                                  // Rozparsování URI
	$path = $a['path'] ?? 'index.php';                                      // Cesta ke skriptu
	$target = "$path?" . http_build_query($params);                         // Cílová URL adresa
	if (headers_sent()) {                                                   // Kontrola odeslaných hlaviček
		print "<script>document.location=" . jsliteral($target) . ';</script>'; // JS přesměrování
	} else {
		header("location: $target");                                        // HTTP přesměrování
	}
	die();                                                                  // Ukončení skriptu
}

// Skupina jednoduchých funkcí pro práci s proměnnou UNIQUEIDENTIFIER
function newid() {                                                          // Generování náhodného UUID v4
	return generateUUID(true);                                              // Volání generátoru UUID
}

function is_guid($guid) {                                                   // Ověření platného formátu UUID pomocí regulárního výrazu
	return (bool)preg_match("/^(\{)?[a-f\d]{8}(-[a-f\d]{4}){4}[a-f\d]{8}(?(1)\})$/i", (string)$guid); // Kontrola formátu UUID
}

function generateUUID($trim = true) {                                       // Kryptograficky bezpečné generování UUID v4
	if (function_exists('com_create_guid') === true) {                      // Podpora na platformě Windows COM
		$guid = com_create_guid();                                          // Vygenerování GUIDu
		return ($trim === true) ? trim((string)$guid, '{}') : (string)$guid; // Případné oříznutí složených závorek
	}

	if (function_exists('openssl_random_pseudo_bytes') === true) {          // Generování přes OpenSSL
		$data = openssl_random_pseudo_bytes(16);                            // 16 náhodných bajtů
		$b6 = (ord($data[6]) & 0x0f) + 0x40;                                // Nastavení verze 4 bez použití znaku pipe
		$b8 = (ord($data[8]) & 0x3f) + 0x80;                                // Nastavení varianty RFC 4122 bez znaku pipe
		$data[6] = chr($b6);                                                // Zápis 6. bajtu
		$data[8] = chr($b8);                                                // Zápis 8. bajtu
		$raw_uuid = vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4)); // Formátování do UUID
		return $trim ? $raw_uuid : ('{' . $raw_uuid . '}');                 // Vrácení s volitelnými závorkami
	}

	// Fallback
	mt_srand((int)(microtime(true) * 10000));                               // Inicializace generátoru náhodných čísel
	$charid = strtolower(md5(uniqid((string)rand(), true)));                // 32 hexadecimálních znaků z MD5
	$hyphen = chr(45);                                                      // Znak pomlčky '-'
	$lbrace = $trim ? "" : chr(123);                                        // Levá složená závorka '{'
	$rbrace = $trim ? "" : chr(125);                                        // Pravá složená závorka '}'
	$guidv4 = $lbrace
		. substr($charid, 0, 8) . $hyphen
		. substr($charid, 8, 4) . $hyphen
		. substr($charid, 12, 4) . $hyphen
		. substr($charid, 16, 4) . $hyphen
		. substr($charid, 20, 12)
		. $rbrace;                                                          // Sestavení výsledného řetězce UUID
	return $guidv4;                                                         // Vrácení UUID
}

/*
 * TODO: Tato funkce se bude muset řešit ve třídě user_context, 
 * až budeme vědět, jak nakládat s uživatelskými moduly, 
 * které nebudou k dispozici pro všechny organizace.
 */
function custom_module($name) {                                             // Kontrola povoleného volitelného modulu v relaci
	global $dbsession;                                                      // Globální pole relace
	$modules = (string)($dbsession['php_modules'] ?? '');                   // Seznam aktivních modulů
	return (strpos($modules, "^$name^") !== false);                         // Zda je modul v seznamu přítomen
}

function isValidURL($url) {                                                 // Validace formátu HTTP/HTTPS URL adresy
	return (filter_var((string)$url, FILTER_VALIDATE_URL) !== false);       // Ověření přes nativní filtr PHP
}

// Funkce pro konverzi textových položek v poli
function iconv_array($charset1, $charset2, $item) {                         // Rekurzivní převod kódování prvků pole
	if (is_string($item)) {                                                 // Skalární řetězec
		return iconv($charset1, $charset2, $item);                          // Převod kódování řetězce
	}
	if (is_array($item)) {                                                  // Pole položek
		foreach ($item as &$i) {                                            // Průchod prvky pole
			$i = iconv_array($charset1, $charset2, $i);                     // Rekurzivní převod prvku
		}
		return $item;                                                       // Vrácení převedeného pole
	}
	return $item;                                                           // Ostatní typy beze změny
}

// JSON_ENCODE a JSON_DECODE pro právě nastavený charset
function json_encodeCP($item) {                                             // JSON serializace s převodem do UTF-8
	global $charset;                                                        // Aktuální znaková sada
	return json_encode(iconv_array($charset, 'utf-8', $item));              // Převod do UTF-8 a zakódování do JSON
}

function json_decodeCP($item) {                                             // JSON deserializace s převodem z UTF-8
	global $charset;                                                        // Aktuální znaková sada
	return iconv_array('utf-8', $charset, json_decode((string)$item, true)); // Rozkódování JSON a převod znakové sady
}

function getCurrentUrl() {                                                  // Získání rozparsované aktuální URL adresy
	$isHttps = ((!empty($_SERVER['HTTPS']) AND $_SERVER['HTTPS'] !== 'off') OR ($_SERVER['SERVER_PORT'] ?? 80) == 443); // Detekce HTTPS
	$scheme = $isHttps ? "https" : "http";                                  // Schéma protokolu
	$srv = $_SERVER["SERVER_NAME"] ?? 'localhost';                          // Název serveru
	$pageURL = $scheme . "://" . $srv;                                      // Základ URL adresy
	$port = (string)($_SERVER["SERVER_PORT"] ?? '80');                      // Číslo portu
	if (($scheme === "http" AND $port !== "80") OR ($scheme === "https" AND $port !== "443")) { // Nestandardní port
		$pageURL .= ":" . $port;                                            // Připojení čísla portu
	}
	$pageURL .= ($_SERVER["REQUEST_URI"] ?? '');                            // Připojení cesty a query stringu
	return parse_url($pageURL);                                             // Vrácení rozparsovaného pole URL
}

/*
	Funkce se používá k odstranění apostrofů z klíčové hodnoty, která může být předána s nimi nebo bez nich.
*/
function stripApostrophes(&$keyvalue) {                                     // Odstranění vnějších apostrofů z SQL literálu
	$str = (string)$keyvalue;                                               // Přetypování na řetězec
	if (substr($str, 0, 1) === "'" AND substr($str, -1) === "'") {          // Pokud začíná i končí apostrofem
		$keyvalue = str_replace("''", "'", substr($str, 1, -1));            // Oříznutí a odzdvojení vnitřních apostrofů
	}
}

function ramsesEncrypt($data, $key, $salt = '') {                           // Symetrické šifrování dat pomocí AES-256-CBC
	$iv = hex2bin(md5("RamsesSalt" . $salt));                               // Inicializační vektor ze soli
	return openssl_encrypt((string)$data, 'AES-256-CBC', (string)$key, 0, (string)$iv); // Zašifrování textu
}

function ramsesDecrypt($data, $key, $salt = '') {                           // Symetrické dešifrování dat pomocí AES-256-CBC
	$iv = hex2bin(md5("RamsesSalt" . $salt));                               // Inicializační vektor ze soli
	return openssl_decrypt((string)$data, 'AES-256-CBC', (string)$key, 0, (string)$iv); // Dešifrování textu
}

function array_to_utf8($input, $recurse = 0) {                              // Rekurzivní převod pole nebo objektu do UTF-8
	global $charset;                                                        // Znaková sada aplikace
	if ($recurse > 10) {                                                    // Ochrana proti příliš hluboké rekurzi
		return null;                                                        // Ukončení větve
	}
	if (is_string($input)) {                                                // Řetězec převedeme přes iconv
		return iconv($charset, 'utf-8', $input);                            // Konverze do UTF-8
	}
	if (is_object($input)) {                                                // Objekt převedeme na asociativní pole vlastností
		$input = get_object_vars($input);                                   // Získání vlastností objektu
	}
	if (is_array($input)) {                                                 // Průchod prvky pole
		foreach ($input as $key => &$val) {                                 // Rekurzivní převod prvků
			$val = array_to_utf8($val, $recurse + 1);                       // Převod vnořeného prvku
		}
	}
	return $input;                                                          // Vrácení převedené struktury
}

function array_from_utf8($input, $recurse = 0) {                            // Rekurzivní převod pole nebo objektu z UTF-8
	global $charset;                                                        // Znaková sada aplikace
	if ($recurse > 10) {                                                    // Ochrana proti příliš hluboké rekurzi
		return null;                                                        // Ukončení větve
	}
	if (is_string($input)) {                                                // Řetězec převedeme přes iconv
		return iconv('utf-8', $charset, $input);                            // Konverze z UTF-8
	}
	if (is_object($input)) {                                                // Objekt převedeme na pole vlastností
		$input = get_object_vars($input);                                   // Získání vlastností objektu
	}
	if (is_array($input)) {                                                 // Průchod prvky pole
		foreach ($input as $key => &$val) {                                 // Rekurzivní převod prvků
			$val = array_from_utf8($val, $recurse + 1);                     // Převod vnořeného prvku
		}
	}
	return $input;                                                          // Vrácení převedené struktury
}

function array_total(&$from, &$to) {                                        // Přičtení číselných hodnot z pole $from do pole $to
	foreach ($from as $key => $val) {                                       // Průchod zdrojovým polem
		$num = is_numeric($val) ? $val : 0;                                 // Ošetření nečíselné hodnoty
		$to[$key] = array_item($to, $key, 0) + $num;                        // Přičtení k cílovému součtu
	}
}

function ob_end() {                                                         // Získání a vyčištění výstupního bufferu
	$s = ob_get_contents();                                                 // Přečtení obsahu bufferu
	ob_end_clean();                                                         // Vyčištění a ukončení bufferu
	return $s;                                                              // Vrácení obsahu
}

// Funkce "namelimit" upraví délku předaného stringu na max
function namelimit(&$n, $namelist = null, $max = 40) {                      // Zkrácení dlouhého textu s doplněním dvou teček
	if (is_array($n)) {                                                     // Hromadné zkrácení vybraných klíčů v poli
		$colnames = explode(',', (string)$namelist);                        // Seznam klíčů ke zkrácení
		foreach ($colnames as $colname) {                                   // Průchod klíči
			if (array_key_exists($colname, $n)) {                           // Pokud klíč v poli existuje
				namelimit($n[$colname], $max);                              // Zkrácení hodnoty pod klíčem
			}
		}
		return;                                                             // Ukončení hromadné úpravy
	}
	$max = ($namelist > 0) ? (int)$namelist : 40;                           // Maximální povolená délka textu
	if (strlen((string)($n ?? '')) > $max) {                                // Pokud text překračuje limit
		$n = substr((string)$n, 0, $max - 2) . "..";                        // Oříznutí a připojení '..'
	}
	return $n;                                                              // Vrácení upraveného textu
}

// Extended nl2br for excel
$brex = '<br style="mso-data-placement:same-cell;">';                       // HTML tag odřádkování uvnitř buňky Excelu
function nl2brex($s) {                                                      // Převod odřádkování na br kompatibilní s Excelem
	global $brex;                                                           // Speciální tag pro Excel
	return str_replace('<br>', $brex ?? '', nl2br((string)($s ?? ''), false)); // Nahrazení <br> speciálním tagem
}

function requestDuration() {                                                // Výpočet doby trvání HTTP požadavku
	global $requestStartTime, $show_request_duration;                       // Čas startu a příznak zobrazení
	if ($show_request_duration) {                                           // Pokud je měření zapnuto
		return number_format(round(microtime(true) - $requestStartTime, 3), 3) . " sec"; // Doba běhu v sekundách
	}
	return "";                                                              // Jinak prázdný řetězec
}

/*
	fopen_bom - otevře soubor a nastaví $file_charset dle BOM, při zápisu ho zapíše dle $charset
*/
function fopen_bom(string $filename, string $mode) {                        // Otevření souboru s automatickou obsluhou BOM
	global $charset, $file_charset;                                         // Globální znaková sada

	// Mapa známých BOM signatur pro různé charsety
	$bom_map = [                                                            // Tabulka BOM sekvencí
		'utf-8'    => "\xEF\xBB\xBF",
		'utf-16le' => "\xFF\xFE",
		'utf-16be' => "\xFE\xFF",
		'utf-32le' => "\xFF\xFE\x00\x00",
		'utf-32be' => "\x00\x00\xFE\xFF",
	];                                                                      // Konec tabulky BOM

	if (!isset($charset) OR !$charset) {                                    // Zjištění aktivního kódování
		$charset = strtolower(mb_internal_encoding());                      // Výchozí kódování z PHP
	} else {
		$charset = strtolower((string)$charset);                            // Převedení názvu charsetu na malá písmena
	}

	$has_write = strpbrk($mode, 'wax');                                     // Detekce režimu zápisu
	$has_read  = strpbrk($mode, 'r+');                                      // Detekce režimu čtení

	$fh = fopen($filename, $mode);                                          // Otevření souboru
	if (!$fh) {                                                             // Kontrola úspěšného otevření
		return false;                                                       // Chyba otevření souboru
	}

	// Zápis BOM při vytváření souboru (ne při append!)
	if ($has_write AND isset($bom_map[$charset]) AND strpos($mode, 'a') !== 0) { // Podmínka zápisu BOM
		fwrite($fh, $bom_map[$charset]);                                    // Zápis BOM sekvence na začátek
	}

	// Čtení BOM a detekce charsetu
	if ($has_read) {                                                        // Při čtení zkontrolujeme přítomnost BOM
		$max_len = max(array_map('strlen', $bom_map));                      // Maximální délka BOM sekvence (4 bajty)
		$start = fread($fh, $max_len);                                      // Přečtení prvních bajtů souboru
		rewind($fh);                                                        // Návrat na začátek souboru

		foreach ($bom_map as $enc => $bom) {                                // Porovnání se známými BOM sekvencemi
			if (strncmp((string)$start, $bom, strlen($bom)) === 0) {        // Shoda s BOM sekvencí
				fseek($fh, strlen($bom));                                   // Přeskočení BOM na začátek vlastního textu
				$file_charset = $enc;                                       // Uložení detekovaného kódování
				break;                                                      // Ukončení hledání BOM
			}
		}
	}

	return $fh;                                                             // Vrácení deskriptoru souboru
}

function fseek_bom($fd) {                                                   // Nastavení pozice v souboru těsně za případný BOM
	fseek($fd, 0);                                                          // Přesun na úplný začátek souboru
	$peek = fread($fd, 4);                                                  // Přečtení prvních 4 bajtů

	if (substr((string)$peek, 0, 3) === "\xEF\xBB\xBF") {                   // UTF-8 BOM (3 bajty)
		fseek($fd, 3);                                                      // Posun na 3. bajt
	} elseif ($peek === "\xFF\xFE\x00\x00" OR $peek === "\x00\x00\xFE\xFF") { // UTF-32 BOM (4 bajty)
		// Pozice 4 je již nastavena po fread($fd, 4)
	} elseif (substr((string)$peek, 0, 2) === "\xFF\xFE" OR substr((string)$peek, 0, 2) === "\xFE\xFF") { // UTF-16 BOM
		fseek($fd, 2);                                                      // Posun na 2. bajt
	} else {
		fseek($fd, 0);                                                      // Žádný BOM -> návrat na pozici 0
	}
}

function my_strtolower($s) {                                                // Převod na malá písmena s ohledem na znakovou sadu
	global $charset;                                                        // Globální znaková sada
	if (strtolower((string)$charset) === 'utf-8') {                         // Pro UTF-8 použijeme přímo mb_strtolower
		return mb_strtolower((string)$s, 'UTF-8');                          // Převod v UTF-8
	}
	return iconv('UTF-8', 'CP1250', mb_strtolower((string)iconv('CP1250', 'UTF-8', (string)$s), 'UTF-8')); // Převod pro CP1250
}

function sanitize_filename($filename) {                                     // Očištění názvu souboru pro hlavičku Content-Disposition
	$filename = (string)$filename;                                          // Přetypování na řetězec
	// 1. Pokud je to Windows-1250, převedeme na UTF-8 pro bezpečnou práci
	if (!preg_match('//u', $filename)) {                                    // Detekce neplatného UTF-8 řetězce
		$filename = (string)iconv('CP1250', 'UTF-8//IGNORE', $filename);    // Převod z CP1250 do UTF-8
	}

	// 2. Odstranění bílých znaků (trim)
	$filename = trim($filename);                                            // Oříznutí okrajových mezer
    
	// 3. Odstranění kontrolních znaků (včetně \r, \n, \t)
	$filename = (string)preg_replace('/[\x00-\x1F\x7F]/', '', $filename);   // Odstranění řídicích znaků

	// 4. Odstranění problematických znaků pro souborové systémy (svislítko přes chr(124) kvůli Anti-LaTeX pravidlu)
	$danger_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', chr(124)];    // Seznam nebezpečných znaků v názvu souboru
	$filename = str_replace($danger_chars, '_', $filename);                 // Nahrazení nebezpečných znaků podtržítkem

	// 5. Odstranění diakritiky pro hlavičku Content-Disposition
	$filename = (string)iconv('UTF-8', 'ASCII//TRANSLIT', $filename);       // Převod diakritiky na čisté ASCII
    
	// 6. Pro jistotu vyčistíme vše, co není písmeno, číslo, tečka nebo pomlčka
	$filename = (string)preg_replace('/[^A-Za-z0-9\._\-]/', '_', $filename); // Finální sanitizace znaků

	return $filename;                                                       // Vrácení bezpečného názvu souboru
}

/**
 * Získá kompletní řetězec IP adres klienta (všechny proxy skoky + koncový REMOTE_ADDR).
 * Slouží jako unikátní síťový otisk prstu (path) pro bezpečné párování relací.
 *
 * @return string Síťový řetězec uzlů (max 200 znaků).
 */
function get_client_ip_path(): string {                                     // Sestavení řetězce klientských IP adres
	$ips = [];                                                              // Pole nalezených IP adres

	// 1. Pokud existuje X-Forwarded-For, projdeme a sesbíráme celou proxy trasu
	if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {                         // Kontrola hlavičky proxy serveru
		$forwarded = explode(',', (string)$_SERVER['HTTP_X_FORWARDED_FOR']); // Rozdělení seznamu IP adres
		foreach ($forwarded as $ip) {                                       // Průchod jednotlivými skoky
			$trimmed = trim($ip);                                           // Očištění IP adresy
			if ($trimmed !== '') {                                          // Ignorování prázdných položek
				$ips[] = $trimmed;                                          // Přidání IP adresy do seznamu
			}
		}
	}

	// 2. Přidáme i koncový fyzický uzel, který navázal spojení s webserverem
	if (!empty($_SERVER['REMOTE_ADDR'])) {                                  // Kontrola koncové IP adresy
		$ips[] = trim((string)$_SERVER['REMOTE_ADDR']);                     // Přidání koncové IP adresy
	}

	// Fallback na localhost, pokud by byla pole prázdná
	if (empty($ips)) {                                                      // Pokud nebyla zjištěna žádná IP adresa
		return '127.0.0.1';                                                 // Vrátíme adresu localhostu
	}

	// 3. Odstraníme případné duplicity, spojíme čárkou a ořízneme na max 200 znaků pro MSSQL
	return substr(implode(', ', array_unique($ips)), 0, 200);               // Výsledný řetězec IP adres
}