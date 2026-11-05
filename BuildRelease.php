<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 11:15
 * Soubor: ../BuildRelease.php
 * Účel: Společný nástroj pro sestavení databázových (.sql) i aplikačních (.php)
 *       balíčků podle manifestu předaného jako 1. parametr příkazové řádky.
 *       Umístěn v nadřízeném adresáři společném pro SQL i PHP složku.
 *
 * Použití:
 *   V adresáři SQL: php ..\BuildRelease.php BuildListDb.txt
 *   V adresáři PHP: php ..\BuildRelease.php BuildListPhp.txt
 * =============================================================================
 */

declare(strict_types=1);

$cliArg = $argv[1] ?? '';                                                  // Načtení prvního argumentu z příkazové řádky
if ($cliArg !== '') {                                                      // Pokud byl manifest předán parametrem
	$manifestFile = $cliArg;                                               // Použijeme předaný název manifestu
} elseif (file_exists('BuildListDb.txt')) {                                // Fallback při spuštění v SQL adresáři
	$manifestFile = 'BuildListDb.txt';                                     // Výchozí manifest pro databázi
} else {
	$manifestFile = 'BuildListPhp.txt';                                    // Výchozí manifest pro PHP skripty
}

$isPhpManifest = (stripos($manifestFile, 'Php') !== false);                // Detekce, zda sestavujeme PHP nebo DB balíček
$outputFile = $isPhpManifest ? 'BcmOsirisPhp00.txt' : 'BcmOsirisDb00.txt'; // Výchozí jméno prvního výstupního souboru
$maxOutputBytes = 360000;                                                  // Maximální velikost výstupního souboru v bajtech (0 = bez limitu)

echo "----------------------------------------------------------\n";
echo "Ramses / BCM Osiris Auto-Deploy Build ({$manifestFile})\n";          // Výpis zpracovávaného manifestu
echo "----------------------------------------------------------\n";

if (! file_exists($manifestFile)) {                                        // Kontrola existence souboru manifestu
	echo "[CHYBA] Soubor manifestu '{$manifestFile}' nebyl nalezen!\n";    // Chybová hláška při nenalezení manifestu
	exit(1);
}

$outHandle          = null;                                                // Handle aktuálně otevřeného výstupního souboru
$fileCount          = 0;                                                   // Počet vložených souborů v aktuálním výstupním souboru
$currentOutputBytes = 0;                                                   // Aktuální velikost otevřeného výstupního souboru v bajtech
$autoPartIndex      = 0;                                                   // Počítadlo automaticky odlomených částí (01, 02, ...)
$processedFiles     = [];                                                  // Globální registr již vložených nebo vyloučených souborů

/**
 * Vytvoří název dalšího výstupního souboru při překročení limitu bajtů.
 * Odebere poslední 2 znaky z názvu souboru před příponou a nahradí je pořadovým číslem (01, 02...).
 */
function get_next_output_filename(string $currentFile, int $partIndex): string { // Výpočet názvu další části výstupu
	$pathInfo = pathinfo($currentFile);                                    // Rozklad cesty k výstupnímu souboru
	$dirName = (string)($pathInfo['dirname'] ?? '');                       // Adresář výstupního souboru
	$dir = ($dirName !== '.' AND $dirName !== '') ? $dirName . DIRECTORY_SEPARATOR : ''; // Cesta k adresáři
	$filename = (string)($pathInfo['filename'] ?? '');                     // Název souboru bez přípony
	$ext = isset($pathInfo['extension']) ? '.' . $pathInfo['extension'] : ''; // Přípona výstupního souboru

	$baseName = (mb_strlen($filename) >= 2) ? mb_substr($filename, 0, -2) : $filename; // Oříznutí posledních 2 znaků

	return $dir . $baseName . sprintf('%02d', $partIndex) . $ext;          // Složení nového názvu s pořadovým číslem
}

/**
 * Otevře nový výstupní soubor, zapíše UTF-8 BOM + hlavičku a inicializuje počítadlo bajtů.
 */
function open_output(): void {
	global $outputFile, $outHandle, $currentOutputBytes;                   // Globální proměnné výstupního souboru

	sleep(1);
	if (file_exists($outputFile)) {                                        // Pokud výstupní soubor z minula existuje
		unlink($outputFile);                                               // Smazání předchozího buildu
	}

	$outHandle = fopen($outputFile, 'wb');                                 // Otevření výstupního souboru pro binární zápis
	if (! $outHandle) {                                                    // Kontrola úspěšného otevření souboru
		echo "[CHYBA] Nelze vytvorit vystupni soubor '{$outputFile}'.\n";  // Chybová hláška při selhání zápisu
		exit(1);
	}

	echo "Sestavuji skript '{$outputFile}'...\n\n";                        // Informace o otevíraném výstupu

	$bom = "\xEF\xBB\xBF";                                                 // UTF-8 Byte Order Mark pro SSMS a editory
	$dateStr = date('Y-m-d H:i');                                          // Aktuální datum a čas sestavení
	$hostStr = (string)gethostname();                                      // Název počítače, na kterém probíhá build

	$header  = "/* ==========================================\n";          // Začátek hlavičky souboru
	$header .= " * OsirisPHP Auto-Deploy Build v. 01.11.2026\n";           // Verze sestavovacího nástroje
	$header .= " * Tento soubor obsahuje zdrojové soubory předávané AI na začátku chatu\n"; // Popis účelu
	$header .= " * Datum vygenerování: {$dateStr}\n";                      // Časová značka vygenerování
	$header .= " * Počítač: {$hostStr}\n";                                 // Identifikace počítače
	$header .= " * Kontrola kódování UTF-8 😊 (Příšerně žluťoučký kůň úpěl ďábelské ódy)\n"; // Kontrola diakritiky
	$header .= " * ========================================== */\n\n--------\n"; // Konec hlavičky souboru

	fwrite($outHandle, $bom . $header);                                    // Zápis BOM a hlavičky do souboru
	$currentOutputBytes = strlen($bom) + strlen($header);                  // Inicializace počítadla zapsaných bajtů
}

/**
 * Uzavře aktuální výstupní soubor, vypíše souhrn a vynuluje počítadla aktuálního souboru.
 */
function close_output(): void {
	global $outHandle, $outputFile, $fileCount, $currentOutputBytes;       // Globální proměnné aktuálního výstupu

	if (is_resource($outHandle)) {                                         // Pokud je výstupní soubor otevřený
		fclose($outHandle);                                                // Uzavření souboru
	}

	echo "\n==========================================================\n";
	echo "HOTOVO! Bylo spojeno {$fileCount} souboru do '{$outputFile}' ({$currentOutputBytes} B).\n"; // Souhrn
	echo "==========================================================\n";

	$fileCount          = 0;                                               // Vynulování počtu souborů
	$currentOutputBytes = 0;                                               // Vynulování počtu bajtů
}

$readFlags = FILE_IGNORE_NEW_LINES + FILE_SKIP_EMPTY_LINES;                // Příznaky pro čtení řádků manifestu bez prázdných řádků
$manifestLines = file($manifestFile, $readFlags);                          // Načtení všech řádků manifestu do pole

open_output();

/**
 * Pomocná funkce pro bezpečné přečtení souboru, odstranění BOM z paměti
 * a konverzi z Windows-1250 do UTF-8 v případě nalezení 8bitové diakritiky.
 */
$processContent = function(string $filePath, bool &$converted): string {   // Načtení a normalizace kódování souboru
	$content   = (string)file_get_contents($filePath);                     // Přečtení obsahu souboru
	$converted = false;                                                    // Výchozí stav konverze kódování

	if (str_starts_with($content, "\xEF\xBB\xBF")) {                       // Kontrola přítomnosti UTF-8 BOM na začátku
		$content = substr($content, 3);                                    // Odříznutí prvních 3 bajtů BOM
	}

	if (! mb_check_encoding($content, 'UTF-8')) {                          // Pokud soubor není platný UTF-8
		$content   = (string)iconv('WINDOWS-1250', 'UTF-8', $content);     // Konverze z Windows-1250 do UTF-8
		$converted = true;                                                 // Označení provedené konverze
	}

	return $content;                                                       // Vrácení čistého UTF-8 obsahu
};

if (is_array($manifestLines)) {                                            // Kontrola platného pole řádků manifestu
	foreach ($manifestLines as $line) {                                    // Průchod řádky manifestu
		$line = trim((string)$line);                                       // Oříznutí bílých znaků kolem řádku

		if ($line === 'return;') {                                         // Direktiva pro předčasné ukončení manifestu
			echo "[INFO] Narazeno na 'return;' v manifestu, zpracovani preruseno.\n";
			break;
		}

		$command = explode('=', $line, 2);                                 // Rozdělení na klíč a hodnotu direktivy
		if (count($command) === 2) {                                       // Pokud jde o konfigurační direktivu
			$cmdKey = trim($command[0]);                                   // Název direktivy (output, limit, exclude)
			$cmdVal = trim($command[1]);                                   // Hodnota direktivy

			if ($cmdKey === 'output') {                                    // Ruční přepnutí výstupního souboru
				close_output();
				$outputFile    = $cmdVal;                                  // Nastavení nové báze názvu výstupu
				$autoPartIndex = 0;                                        // Reset počítadla automaticky dělených částí
				echo "\nZmena vystupniho souboru na '{$outputFile}' (reset pocitadla)\n"; // Výpis změny
				open_output();
				continue;
			}

			if ($cmdKey === 'limit') {                                     // Změna maximální velikosti výstupního souboru
				$maxOutputBytes = max(0, (int)$cmdVal);                    // Nastavení nového limitu v bajtech
				$limitText = ($maxOutputBytes === 0) ? 'bez limitu (0 B)' : "{$maxOutputBytes} B"; // Textový popis limitu
				echo "\n[INFO] Nastaven novy limit velikosti vystupniho souboru: {$limitText}\n"; // Výpis limitu
				continue;
			}

			if ($cmdKey === 'exclude') {                                   // Vyloučení souborů podle masky
				$excludedFiles = glob($cmdVal);                            // Vyhledání souborů odpovídajících masce
				$excludedCount = 0;                                        // Počítadlo vyloučených souborů
				if ($excludedFiles !== false) {                            // Pokud maska vrátila pole souborů
					foreach ($excludedFiles as $exFile) {                  // Průchod nalezenými soubory k vyloučení
						if (is_file($exFile)) {                            // Kontrola, že jde o fyzický soubor
							$realPath = realpath($exFile);                 // Získání kanonické absolutní cesty
							if ($realPath !== false AND ! isset($processedFiles[$realPath])) { // Pokud ještě není v registru
								$processedFiles[$realPath] = true;         // Označení souboru jako již zpracovaného
								$excludedCount++;                          // Inkrementace počtu vyloučených
							}
						}
					}
				}
				echo "\n[INFO] Vylouceno {$excludedCount} souboru dle masky '{$cmdVal}'\n"; // Výpis počtu vyloučených
				continue;
			}
		}

		if (str_starts_with($line, '#')) {                                 // Ignorování komentářových řádků v manifestu
			echo "\n\n{$line}";                                            // Výpis komentáře do konzole
			continue;
		}

		$files = glob($line);                                              // Expanze masky souborů v aktuálním pracovním adresáři

		if ($files === false OR count($files) === 0) {                     // Pokud masce neodpovídá žádný soubor
			echo "\n[VAROVANI] Zadne soubory nenalezeny pro polozku/masku: '{$line}'\n"; // Výpis varování
			continue;
		}

		natcasesort($files);                                               // Přirozené abecední seřazení souborů

		echo "\n{$line} ";                                                 // Výpis masky do konzole
		foreach ($files as $file) {                                        // Průchod nalezenými soubory
			if (is_file($file)) {                                          // Zpracujeme pouze běžné soubory
				echo ".";
				$realPath = realpath($file);                               // Kanonická absolutní cesta k souboru

				if ($realPath === false OR isset($processedFiles[$realPath])) { // Přeskočení již zpracovaného souboru
					continue;
				}

				$wasConverted = false;                                     // Příznak konverze kódování
				$cleanContent = "-- Následující kód je zkopírován ze souboru {$file}:\n--------\n" . $processContent($file, $wasConverted); // Hlavička a obsah

				$separator = str_ends_with(strtolower($file), '.sql') ? "\nGO\n\n" : "\n"; // Oddělovač GO pro SQL skripty
				$footer    = "{$separator}-------- Konec souboru {$file}\n\n--------\n"; // Patička souboru

				$fullEntry  = $cleanContent . $footer;                     // Celý záznam souboru
				$entryBytes = strlen($fullEntry);                          // Velikost záznamu v bajtech

				if ($maxOutputBytes > 0 AND $fileCount > 0 AND ($currentOutputBytes + $entryBytes) > $maxOutputBytes) { // Překročení limitu
					close_output();
					$autoPartIndex++;                                      // Posun indexu další části
					$outputFile = get_next_output_filename($outputFile, $autoPartIndex); // Název dalšího souboru
					echo "\n[INFO] Prekrocen limit {$maxOutputBytes} B u souboru '{$file} ({$entryBytes} B)',\nautomaticke prepnuti na '{$outputFile}'\n"; // Info o odlomení
					open_output();
				}

				if ($maxOutputBytes > 0 AND ($currentOutputBytes + $entryBytes) > $maxOutputBytes) { // Jeden soubor přesahuje limit
					echo "\n[VAROVANI] Samotny soubor '{$file}' ({$entryBytes} B) prekracuje nastaveny limit {$maxOutputBytes} B!\n"; // Varování
				}

				fwrite($outHandle, $fullEntry);                            // Zápis záznamu do výstupního souboru
				$currentOutputBytes += $entryBytes;                        // Přičtení zapsaných bajtů

				$processedFiles[$realPath] = true;                         // Zápis souboru do registru zpracovaných
				$fileCount++;                                              // Zvýšení počtu vložených souborů
			}
		}
	}
}

close_output();