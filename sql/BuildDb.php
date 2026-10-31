<?php
declare(strict_types=1);

// -----------------------------------------------------------------------------
// RamsesDB - Nástroj pro sestavení databázových skriptů (PHP verze)
// -----------------------------------------------------------------------------

$manifestFile   = 'BuildListDb.txt';                              // Soubor se seznamem skriptů nebo masek (wildcards)
$outputFile     = 'BcmOsirisDb00.txt';                            // Výchozí sloučený soubor (poslední 2 znaky před příponou nahradí číslování 01, 02...)
$maxOutputBytes = 360000;                                          // Maximální velikost výstupního souboru v bajtech (0 = bez limitu)

echo "----------------------------------------------------------\n";
echo "RamsesDB Auto-Deploy Build\n";
echo "----------------------------------------------------------\n";

// 1. Kontrola existence manifestu
if (!file_exists($manifestFile)) {
	echo "[CHYBA] Soubor manifestu '{$manifestFile}' nebyl nalezen!\n";
	echo "Vytvorte soubor '{$manifestFile}' se seznamem PHP skriptu.\n";
	exit(1);
}

$outHandle          = null;                                        // Handle aktuálně otevřeného výstupního souboru
$fileCount          = 0;                                           // Počet vložených souborů v aktuálním výstupním souboru
$currentOutputBytes = 0;                                           // Aktuální velikost otevřeného výstupního souboru v bajtech
$autoPartIndex      = 0;                                           // Počítadlo automaticky odlomených částí (01, 02, ...)
$processedFiles     = [];                                          // Globální registr pro sledování již vložených nebo vyloučených souborů

// Vytvoří název dalšího výstupního souboru při překročení limitu bajtů.
// Odebere poslední 2 znaky z názvu souboru před příponou a nahradí je pořadovým číslem (01, 02...).
function get_next_output_filename(string $currentFile, int $partIndex): string {
	$pathInfo = pathinfo($currentFile);
	$dir      = ($pathInfo['dirname'] !== '.' && $pathInfo['dirname'] !== '') ? $pathInfo['dirname'] . DIRECTORY_SEPARATOR : '';
	$filename = $pathInfo['filename'];                             // Název souboru bez přípony
	$ext      = isset($pathInfo['extension']) ? '.' . $pathInfo['extension'] : '';

	// Odebrání posledních dvou znaků z názvu před příponou
	$baseName = (mb_strlen($filename) >= 2) ? mb_substr($filename, 0, -2) : $filename;

	return $dir . $baseName . sprintf('%02d', $partIndex) . $ext;
}

// Otevře nový výstupní soubor, zapíše UTF-8 BOM + hlavičku a inicializuje počítadlo bajtů.
function open_output(): void {
	global $outputFile, $outHandle, $currentOutputBytes;
	sleep(1);
	if (file_exists($outputFile)) {
		unlink($outputFile);                                       // Smazání předchozího buildu
	}

	$outHandle = fopen($outputFile, 'wb');
	if (!$outHandle) {
		echo "[CHYBA] Nelze vytvorit vystupni soubor '{$outputFile}'.\n";
		exit(1);
	}

	echo "Sestavuji skript '{$outputFile}'...\n\n";

	// Vložení BOM (Byte Order Mark) pro UTF-8 na úplný začátek souboru
	// Toto donutí SSMS a další nástroje automaticky otevřít soubor v UTF-8 kódování
	$bom = "\xEF\xBB\xBF";

	// Zápis hlavičky
	$dateStr = date('Y-m-d H:i');
	$hostStr = gethostname();                                      // Získání identifikace počítače (hostname)
	$header  = "/* ==========================================\n";
	$header .= " * OsirisPHP Auto-Deploy Build v. 21.10.2026\n";
	$header .= " * Tento soubor obsahuje všechny PHP soubory předávané AI na začátku chatu\n";
	$header .= " * Datum vygenerování: {$dateStr}\n";
	$header .= " * Počítač: {$hostStr}\n";
	$header .= " * Kontrola kódování UTF-8 😊 (Příšerně žluťoučký kůň úpěl ďábelské ódy)\n";
	$header .= " * ========================================== */\n\n--------\n";

	fwrite($outHandle, $bom . $header);
	$currentOutputBytes = strlen($bom) + strlen($header);          // strlen() v PHP vrací přesný počet bajtů
}

// Uzavře aktuální výstupní soubor, vypíše souhrn a vynuluje počítadla aktuálního souboru.
function close_output(): void {
	global $outHandle, $outputFile, $fileCount, $currentOutputBytes;

	if (is_resource($outHandle)) {
		fclose($outHandle);
	}

	echo "\n==========================================================\n";
	echo "HOTOVO! Bylo spojeno {$fileCount} souboru do '{$outputFile}' ({$currentOutputBytes} B).\n";
	echo "==========================================================\n";

	$fileCount          = 0;
	$currentOutputBytes = 0;
}

// 2. Zpracování manifestu a expanze zástupných znaků (wildcards)
$manifestLines = file($manifestFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

// 3. Příprava prvního výstupního souboru (včetně BOM a hlavičky)
open_output();

// Pomocná funkce pro bezpečné přečtení souboru, odstranění BOM z paměti
// a konverzi z Windows-1250 do UTF-8 v případě nalezení 8bitové diakritiky.
$processContent = function(string $filePath, bool &$converted): string {
	$content   = file_get_contents($filePath);
	$converted = false;

	// Pokud řetězec začíná UTF-8 BOM, odřízneme první 3 bajty
	if (str_starts_with($content, "\xEF\xBB\xBF")) {
		$content = substr($content, 3);
	}

	// Kontrola platnosti UTF-8 sekvencí. Pokud selže, překódujeme přes nativní iconv.
	if (!mb_check_encoding($content, 'UTF-8')) {
		$content   = iconv('WINDOWS-1250', 'UTF-8', $content);
		$converted = true;
	}

	return $content;
};

foreach ($manifestLines as $line) {
	$line = trim($line);

	if ($line === 'return;') {
		echo "[INFO] Narazeno na 'return;' v manifestu, zpracovani preruseno.\n";
		break;
	}

	// Zpracování konfiguračních direktiv v manifestu (output=..., limit=..., exclude=...)
	$command = explode('=', $line, 2);
	if (count($command) === 2) {
		$cmdKey = trim($command[0]);
		$cmdVal = trim($command[1]);

		// Ruční přepnutí výstupního souboru direktivou output=...
		if ($cmdKey === 'output') {
			close_output();
			$outputFile    = $cmdVal;                              // Nastavení nové báze názvu souboru
			$autoPartIndex = 0;                                    // Reset počítadla automaticky dělených souborů
			echo "\nZmena vystupniho souboru na '{$outputFile}' (reset pocitadla)\n";
			open_output();
			continue;
		}

		// Změna limitu velikosti výstupního souboru direktivou limit=... (0 = bez limitu)
		if ($cmdKey === 'limit') {
			$maxOutputBytes = max(0, (int)$cmdVal);
			$limitText      = ($maxOutputBytes === 0) ? 'bez limitu (0 B)' : "{$maxOutputBytes} B";
			echo "\n[INFO] Nastaven novy limit velikosti vystupniho souboru: {$limitText}\n";
			continue;
		}

		// Vyloučení souborů vyhovujících masce direktivou exclude=... (označí se jako již zpracované)
		if ($cmdKey === 'exclude') {
			$excludedFiles = glob($cmdVal);
			$excludedCount = 0;
			if ($excludedFiles !== false) {
				foreach ($excludedFiles as $exFile) {
					if (is_file($exFile)) {
						$realPath = realpath($exFile);
						if ($realPath !== false && !isset($processedFiles[$realPath])) {
							$processedFiles[$realPath] = true;     // Zápis do registru zabrání pozdějšímu vložení do výstupu
							$excludedCount++;
						}
					}
				}
			}
			echo "\n[INFO] Vylouceno {$excludedCount} souboru dle masky '{$cmdVal}'\n";
			continue;
		}
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

			// Ochrana proti duplicitnímu vložení nebo vložení vyloučeného souboru (exclude=...)
			if (isset($processedFiles[$realPath])) {
				continue;                                          // Soubor byl zařazen či vyloučen dříve, ignorujeme
			}

			// Přečtení obsahu s odříznutím BOM a validací/konverzí kódování
			$wasConverted = false;
			$cleanContent = "-- Následující kód je zkopírován ze souboru $file:\n--------\n" . $processContent($file, $wasConverted);

			// Volba separátoru dávky podle přípony souboru (.sql vyžaduje GO na novém řádku)
			$separator = str_ends_with(strtolower($file), '.sql') ? "\nGO\n\n" : "\n";
			$footer    = "{$separator}-------- Konec souboru $file\n\n--------\n";

			// Celý blok připravený k zápisu a jeho přesná velikost v bajtech
			$fullEntry  = $cleanContent . $footer;
			$entryBytes = strlen($fullEntry);

			// Kontrola, zda by zápis aktuálního souboru překročil povolený limit bajtů
			// ($maxOutputBytes > 0 znamená aktivní limit; přepínáme jen pokud už v souboru alespoň 1 položka je)
			if ($maxOutputBytes > 0 && $fileCount > 0 && ($currentOutputBytes + $entryBytes) > $maxOutputBytes) {
				close_output();
				$autoPartIndex++;
				$outputFile = get_next_output_filename($outputFile, $autoPartIndex);
				echo "\n[INFO] Prekrocen limit {$maxOutputBytes} B, automaticke prepnuti na '{$outputFile}'\n";
				open_output();
			}

			// Varování v případě, že by samotný jeden vstupní soubor + hlavička přesáhl aktivní limit
			if ($maxOutputBytes > 0 && ($currentOutputBytes + $entryBytes) > $maxOutputBytes) {
				echo "\n[VAROVANI] Samotny soubor '{$file}' ({$entryBytes} B) prekracuje nastaveny limit {$maxOutputBytes} B!\n";
			}

			// Zápis vyčištěného obsahu a separátoru do výstupního skriptu
			fwrite($outHandle, $fullEntry);
			$currentOutputBytes += $entryBytes;

			$processedFiles[$realPath] = true;                     // Registrace souboru do paměti jako "zpracováno"
			$fileCount++;
		}
	}
}

close_output();