<?php
declare(strict_types=1);

// -----------------------------------------------------------------------------
// RamsesDB - Nástroj pro sestavení databázových skriptů (PHP verze)
// -----------------------------------------------------------------------------

$manifestFile   = 'BuildListPhp.txt';                              // Soubor se seznamem skriptů nebo masek (wildcards)
$outputFile     = 'BcmOsirisPhp1.txt';                               // Výsledný sloučený soubor

echo "----------------------------------------------------------\n";
echo "RamsesDB Auto-Deploy Build\n";
echo "----------------------------------------------------------\n";

// 1. Kontrola existence manifestu
if (!file_exists($manifestFile)) {
	echo "[CHYBA] Soubor manifestu '{$manifestFile}' nebyl nalezen!\n";
	echo "Vytvorte soubor '{$manifestFile}' se seznamem PHP skriptu.\n";
	exit(1);
}

function open_output(){
	global $outputFile, $outHandle;
	if (file_exists($outputFile)) {
		unlink($outputFile);                                        // Smazání předchozího buildu
	}

	$outHandle = fopen($outputFile, 'wb');
	if (!$outHandle) {
		echo "[CHYBA] Nelze vytvorit vystupni soubor '{$outputFile}'.\n";
		exit(1);
	}

	echo "Sestavuji skript '{$outputFile}'...\n\n";

}

function close_output(){
	global $outHandle,$outputFile,$fileCount;
	fclose($outHandle);
	echo "\n==========================================================\n";
	echo "HOTOVO! Bylo spojeno {$fileCount} souboru do '{$outputFile}'.\n";
	echo "==========================================================\n";
	$fileCount=0;
}


// 2. Zpracování manifestu a expanze zástupných znaků (wildcards)
$manifestLines = file($manifestFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

$fileCount = 0;
$processedFiles = [];                                           // Globální registr pro sledování již vložených souborů

// 3. Příprava výstupního souboru

open_output();

// 4. Vložení BOM (Byte Order Mark) pro UTF-8 na úplný začátek souboru
// Toto donutí SSMS automaticky otevřít soubor v UTF-8 kódování
fwrite($outHandle, "\xEF\xBB\xBF");

// 4. Zápis hlavičky (čisté ASCII)
$dateStr = date('Y-m-d H:i');
$hostStr = gethostname();                                       // Získání identifikace počítače (hostname)
$header  = "/* ==========================================\n";
$header .= " * OsirisPHP Auto-Deploy Build v. 21.10.2026\n";
$header .= " * Tento soubor obsahuje všechny PHP soubory předávané AI na začátku chatu\n";
$header .= " * Datum vygenerování: {$dateStr}\n";
$header .= " * Počítač: {$hostStr}\n";
$header .= " * Kontrola kódování UTF-8 😊 (Příšerně žluťoučký kůň úpěl ďábelské ódy)\n";
$header .= " * ========================================== */\n\n--------\n";
fwrite($outHandle, $header);

/**
 * Pomocná funkce pro bezpečné přečtení souboru, odstranění BOM z paměti
 * a konverzi z Windows-1250 do UTF-8 v případě nalezení 8bitové diakritiky.
 * @param string $filePath Cesta k souboru
 * @param bool &$converted Indikátor, zda došlo ke konverzi kódování
 * @return string Obsah souboru v čistém UTF-8 bez BOM
 */
$processContent = function(string $filePath, bool &$converted): string {
	$content = file_get_contents($filePath);
	$converted = false;
	
	// Pokud řetězec začíná UTF-8 BOM, odřízneme první 3 bajty
	if (str_starts_with($content, "\xEF\xBB\xBF")) {
		$content = substr($content, 3);
	}
	
	// Kontrola platnosti UTF-8 sekvencí. Pokud selže, překódujeme přes nativní iconv.
	if (!mb_check_encoding($content, 'UTF-8')) {
		$content = iconv('WINDOWS-1250', 'UTF-8', $content);
		$converted = true;
	}
	

	return $content;
};

foreach ($manifestLines as $line) {
	$line = trim($line);
	
	if($line==='return;'){
		echo "[INFO] Narazeno na 'return;' v manifestu, zpracovani preruseno.\n";
		break;
	}

	$command=explode("=",$line);
	if(count($command)==2 AND $command[0]=="output") {
		close_output();
		echo "\nZměna výstupního souboru\n";
		$outputFile=$command[1];
		open_output();
		continue;
	}
	
	// Ignorování komentářů v manifestu
	if (str_starts_with($line, '#')) {
		echo "\n\n$line";
		continue;
	}
	
	// Získání seznamu souborů na základě masky (např. "tools/mcp_*.sql" nebo "db_schema.sql")
	$files = glob($line);
	
	if ($files === false || count($files) === 0) {
		echo "\n[VAROVANI] Zadne soubory nenalezeny pro polozku/masku: '{$line}'\n";
		continue;
	}
	
	// APLIKACE PŘIROZENÉHO TŘÍDĚNÍ (SHODNÉ S WINDOWS TYPE)
	natcasesort($files);
	
	echo "\n$line ";
	foreach ($files as $file) {
		if (is_file($file)) {
			echo ".";
			// Získání absolutní cesty pro 100% zamezení duplicit i při různých formátech zápisu cest
			$realPath = realpath($file);
			
			// Ochrana proti duplicitnímu vložení souboru (pokud již je v asociativním poli)
			if (isset($processedFiles[$realPath])) {
				continue;                                       // Soubor byl zařazen dříve přes konkrétní zápis, ignorujeme
			}
			
			// Přečtení obsahu s odříznutím BOM a validací/konverzí kódování
			$wasConverted = false;
			$cleanContent = "-- Následující kód je zkopírován ze souboru $file:\n--------\n". $processContent($file, $wasConverted);
			
			// Výpis informace o zpracování
			// $conversionInfo = $wasConverted ? " [konvertovano z Windows-1250]" : "";
			// echo "Pridavam: {$file}{$conversionInfo}\n";
			
			// Zápis metadatového komentáře
			// fwrite($outHandle, "/* --- Nacteno z: {$file}{$conversionInfo} --- */\n");
			
			// Zápis vyčištěného obsahu do výstupního DB skriptu
			fwrite($outHandle, $cleanContent);
			
			// Vložení separátoru dávky
			fwrite($outHandle, "\n-------- Konec souboru $file\n\n--------\n");
			
			$processedFiles[$realPath] = true;                  // Registrace souboru do paměti jako "zpracováno"
			$fileCount++;
		}
	}
}

close_output();
