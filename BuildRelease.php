<?php
/**
 * =============================================================================
 * Verze: 2026-11-20 16:45
 * Soubor: ../BuildRelease.php
 * Účel: Společný nástroj pro sestavení databázových (.sql) i aplikačních (.php)
 *       balíčků podle manifestu předaného jako 1. parametr příkazové řádky.
 *       Umístěn v nadřízeném adresáři společném pro SQL i PHP složku.
 *
 * Použití:
 *   V adresáři SQL: php ..\BuildRelease.php BuildListDb.txt Vystup00.sql [maxBajtů]
 *   V adresáři PHP: php ..\BuildRelease.php BuildListPhp.txt Vystup00.txt [maxBajtů]
 * =============================================================================
 *
 * SHRNUTÍ POSTUPU (KDE JSME SKONČILI):
 * - Doplněna automatická kontrola na výskyt znaků cyrilice (azbuky) v metodě
 *   warnOnCyrillicCharacters() volané z readAndNormalizeContent(), která při
 *   nálezu vypíše barevné varování s názvem souboru, číslem řádku a slovem.
 * - Přidáno sjednocení konců řádků na LF (odstranění CRLF i osamocených CR)
 *   v metodě readAndNormalizeContent(), takže výstupní soubory obsahují čistě LF.
 * - Přidány metody buildFileSeparator() a endsWithSqlGo(), které zabraňují
 *   duplicitnímu přidávání příkazu GO na konec .sql souborů (včetně variant bez
 *   koncového odřádkování, s libovolnou velikostí písmen, mezerami, opakováním
 *   typu GO 2 či řádkovým komentářem na stejném řádku).
 * - Zachováno barevné zvýraznění varování a chyb na konzoli (ANSI + Windows
 *   VT100 + stream_isatty + NO_COLOR), skutečný název souboru v hlavičce výstupu
 *   a deterministické nastavení časů přes touch() bez zdržování ve sleep().
 *
 * CO ZBÝVÁ DOŘEŠIT V DALŠÍM KROKU:
 * 1. Zvážit krátký retry pouze při selhání unlink() (pokud by výstupní soubor
 *    na Windows dočasně držel antivirus nebo synchronizační klient).
 * 2. Volitelně doplnit CLI přepínač (např. --warning-style=red) pro volbu barvy
 *    varování bez zásahu do konstanty ReleaseBuilder::WARNING_STYLE.
 * 3. Pokud by se v budoucnu vyskytly prázdné .sql soubory (jen komentáře nebo
 *    prázdné řádky), rozhodnout, zda má smysl do nich doplňovat GO.
 * =============================================================================
 */

declare(strict_types=1);

/**
 * Dostupné ANSI styly pro výpis do konzole.
 */
enum ConsoleStyle: string
{
	case Default            = '';
	case WarningRed         = "\033[1;31m";     // Tučné červené písmo na výchozím pozadí
	case WarningRedOnYellow = "\033[1;31;103m"; // Tučné červené písmo na jasně žlutém pozadí
	case WarningDarkYellow  = "\033[1;31;43m";  // Tučné červené písmo na tmavším žlutém pozadí
	case Error              = "\033[1;97;41m";  // Tučné bílé písmo na červeném pozadí
}

/**
 * Správce konzolového výstupu s bezpečnou podporou ANSI barev na Windows i Unixu.
 */
final readonly class ConsoleOutput
{
	private const string ANSI_RESET = "\033[0m";                           // Reset barvy a stylu písma na výchozí

	/** @var resource */
	private mixed $stdout;                                                 // Standardní výstupní proud

	/** @var resource */
	private mixed $stderr;                                                 // Chybový výstupní proud

	public function __construct(mixed $stdout = null, mixed $stderr = null)
	{
		$resolvedStdout = $stdout ?? (defined('STDOUT') ? STDOUT : fopen('php://stdout', 'wb'));
		$resolvedStderr = $stderr ?? (defined('STDERR') ? STDERR : fopen('php://stderr', 'wb'));

		if (!is_resource($resolvedStdout) || !is_resource($resolvedStderr)) {
			throw new RuntimeException('Nepodařilo se inicializovat výstupní proudy konzole.');
		}

		$this->stdout = $resolvedStdout;
		$this->stderr = $resolvedStderr;
	}

	/**
	 * Zapíše text na standardní výstup bez automatického odřádkování.
	 */
	public function write(string $text): void
	{
		fwrite($this->stdout, $text);
	}

	/**
	 * Zapíše řádek na standardní výstup.
	 */
	public function writeln(string $text = ''): void
	{
		fwrite($this->stdout, $text . PHP_EOL);
	}

	/**
	 * Vypíše barevně zvýrazněné varování na STDERR.
	 * Odřádkování je záměrně mimo ANSI sekvenci, aby se pozadí nerozlilo na další řádek.
	 */
	public function warning(
		string $message,
		ConsoleStyle $style = ConsoleStyle::WarningRedOnYellow,
		bool $leadingNewline = true,
	): void {
		fflush($this->stdout);                                             // Vyprázdnění STDOUT před zápisem na STDERR
		$prefix    = $leadingNewline ? PHP_EOL : '';                       // Odsazení od předchozího řádku teček
		$formatted = $this->format($message, $style, $this->stderr);       // Aplikace barvy jen při podpoře ANSI

		fwrite($this->stderr, $prefix . $formatted . PHP_EOL);
	}

	/**
	 * Vypíše barevně zvýrazněnou chybu na STDERR.
	 */
	public function error(string $message, bool $leadingNewline = false): void
	{
		fflush($this->stdout);                                             // Vyprázdnění STDOUT před zápisem chyby
		$prefix    = $leadingNewline ? PHP_EOL : '';                       // Volitelné oddělení od průběžného výpisu
		$formatted = $this->format($message, ConsoleStyle::Error, $this->stderr);

		fwrite($this->stderr, $prefix . $formatted . PHP_EOL);
	}

	/**
	 * Obalí text ANSI kódy pouze tehdy, pokud cílový proud barvy skutečně podporuje.
	 */
	private function format(string $text, ConsoleStyle $style, mixed $stream): string
	{
		if ($style === ConsoleStyle::Default || !$this->supportsColor($stream)) {
			return $text;
		}

		return $style->value . $text . self::ANSI_RESET;
	}

	/**
	 * Ověří podporu ANSI barev na daném proudu včetně respektování proměnné NO_COLOR.
	 */
	private function supportsColor(mixed $stream): bool
	{
		if (!is_resource($stream)) {
			return false;
		}

		$noColor = getenv('NO_COLOR');                                     // Respektuje standard https://no-color.org/
		if ($noColor !== false && $noColor !== '') {
			return false;
		}

		if (!stream_isatty($stream)) {                                     // Při přesměrování do souboru/roury barvy vypneme
			return false;
		}

		if (function_exists('sapi_windows_vt100_support')) {               // Aktivace VT100 sekvencí v konzoli Windows
			return sapi_windows_vt100_support($stream, true);
		}

		return true;
	}
}

/**
 * Hlavní sestavovač textových balíčků (.sql / .php) podle manifestu.
 */
final class ReleaseBuilder
{
	private const string VERSION             = '2026-11-20';               // Verze nástroje uváděná v hlavičce výstupu
	private const ConsoleStyle WARNING_STYLE = ConsoleStyle::WarningRedOnYellow; // Změň na WarningRed pro čistě červený text
	private const string UTF8_BOM            = "\xEF\xBB\xBF";             // UTF-8 Byte Order Mark pro SSMS a editory
	private const int TIMESTAMP_STEP_SECONDS = 2;                          // Rozestup mtime pro spolehlivé třídění (i FAT32/ZIP)
	private const int MAX_CYRILLIC_WARNINGS  = 5;                          // Maximální počet vypsaných řádků s cyrilicí na soubor

	/** @var resource|null */
	private mixed $outHandle        = null;                                // Handle aktuálně otevřeného výstupního souboru
	private int $fileCount          = 0;                                   // Počet vložených souborů v aktuálním výstupu
	private int $convertedCount     = 0;                                   // Počet souborů zkonvertovaných z Windows-1250
	private int $currentOutputBytes = 0;                                   // Aktuální velikost otevřeného výstupu v bajtech
	private int $autoPartIndex      = 0;                                   // Počítadlo automaticky odlomených částí (01, 02...)

	/** @var array<string, true> */
	private array $processedFiles   = [];                                  // Globální registr vložených nebo vyloučených souborů

	/** @var list<string> */
	private array $generatedFiles   = [];                                  // Pořadí vytvořených výstupních souborů pro touch()

	public function __construct(
		private readonly ConsoleOutput $console,
		private readonly string $manifestFile,
		private string $outputFile,
		private int $maxOutputBytes,
	) {
		$this->maxOutputBytes = max(0, $this->maxOutputBytes);             // Zajištění nezáporného limitu velikosti
	}

	public function __destruct()
	{
		if (is_resource($this->outHandle)) {                               // Bezpečné uzavření souboru při neočekávaném ukončení
			fclose($this->outHandle);
			$this->outHandle = null;
		}
	}

	/**
	 * Spustí zpracování manifestu a vrátí návratový kód procesu (0 = OK, 1 = chyba).
	 */
	public function run(): int
	{
		$this->console->writeln('----------------------------------------------------------');
		$this->console->writeln("Ramses / BCM Osiris Auto-Deploy Build ({$this->manifestFile})");
		$this->console->writeln('----------------------------------------------------------');

		if ($this->manifestFile === '' || !is_file($this->manifestFile) || !is_readable($this->manifestFile)) {
			$this->console->error("[CHYBA] Soubor manifestu '{$this->manifestFile}' nebyl nalezen nebo jej nelze číst!");
			return 1;
		}

		if ($this->outputFile === '') {
			$this->console->error('[CHYBA] Nebyl zadán výstupní soubor (2. parametr příkazové řádky).');
			return 1;
		}

		$readFlags     = FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES;    // Čtení řádků manifestu bez prázdných řádků
		$manifestLines = file($this->manifestFile, $readFlags);            // Načtení všech řádků manifestu do pole

		if ($manifestLines === false) {                                    // Ochrana před smazáním starého výstupu při chybě čtení
			$this->console->error("[CHYBA] Nelze načíst obsah manifestu '{$this->manifestFile}'.");
			return 1;
		}

		try {
			if (!$this->openOutput()) {
				return 1;
			}

			foreach ($manifestLines as $rawLine) {
				$line = trim($rawLine);                                    // Oříznutí bílých znaků včetně případného CR

				if ($line === '') {                                        // Přeskočení řádků obsahujících jen mezery/taby
					continue;
				}

				if ($line === 'return;') {                                 // Direktiva pro předčasné ukončení manifestu
					$this->console->writeln("[INFO] Narazeno na 'return;' v manifestu, zpracovani preruseno.");
					break;
				}

				if (str_starts_with($line, '#')) {                         // Komentářové řádky vyhodnocujeme před direktivami
					$this->console->write("\n\n{$line}");
					continue;
				}

				$directiveResult = $this->tryHandleDirective($line);
				if ($directiveResult === false) {                          // Chyba při provádění direktivy (např. openOutput)
					return 1;
				}
				if ($directiveResult === true) {                           // Řádek byl zpracován jako konfigurační direktiva
					continue;
				}

				if (!$this->processMask($line)) {                          // Chyba při zápisu nebo otevírání další části
					return 1;
				}
			}

			$this->closeOutput();
			return 0;
		} finally {
			if (is_resource($this->outHandle)) {                           // Uzavření handle před úpravou časů při předčasném konci
				fclose($this->outHandle);
				$this->outHandle = null;
			}
			$this->applySequentialTimestamps();                            // Nastavení rostoucích časů bez použití sleep()
		}
	}

	/**
	 * Zkusí zpracovat řádek jako direktivu (output=, limit=, exclude=).
	 * Vrací: null = není direktiva, true = direktiva zpracována, false = fatální chyba.
	 */
	private function tryHandleDirective(string $line): ?bool
	{
		$command = explode('=', $line, 2);                                 // Rozdělení na klíč a hodnotu direktivy
		if (count($command) !== 2) {
			return null;
		}

		$cmdKey = trim($command[0]);                                       // Název direktivy
		$cmdVal = trim($command[1]);                                       // Hodnota direktivy

		if ($cmdKey === 'output') {                                        // Ruční přepnutí výstupního souboru
			if ($cmdVal === '') {
				$this->console->warning("[VAROVANI] Direktiva 'output=' ma prazdnou hodnotu, ignoruji.", self::WARNING_STYLE);
				return true;
			}

			$this->closeOutput();
			$this->outputFile    = $cmdVal;                                // Nastavení nové báze názvu výstupu
			$this->autoPartIndex = 0;                                      // Reset počítadla automaticky dělených částí
			$this->console->writeln("\nZmena vystupniho souboru na '{$this->outputFile}' (reset pocitadla)");
			return $this->openOutput();
		}

		if ($cmdKey === 'limit') {                                         // Změna maximální velikosti výstupního souboru
			$this->maxOutputBytes = max(0, (int)$cmdVal);                  // Nastavení nového limitu v bajtech
			$limitText            = ($this->maxOutputBytes === 0) ? 'bez limitu (0 B)' : "{$this->maxOutputBytes} B";
			$this->console->writeln("\n[INFO] Nastaven novy limit velikosti vystupniho souboru: {$limitText}");
			return true;
		}

		if ($cmdKey === 'exclude') {                                       // Vyloučení souborů podle masky
			$excludedFiles = glob($cmdVal);                                // Vyhledání souborů odpovídajících masce
			$excludedCount = 0;                                            // Počítadlo vyloučených souborů

			if ($excludedFiles !== false) {
				foreach ($excludedFiles as $exFile) {
					if (!is_file($exFile)) {
						continue;
					}

					$realPath = realpath($exFile);                         // Kanonická absolutní cesta souboru
					if ($realPath !== false && !isset($this->processedFiles[$realPath])) {
						$this->processedFiles[$realPath] = true;           // Označení souboru jako vyloučeného
						$excludedCount++;
					}
				}
			}

			$this->console->writeln("\n[INFO] Vylouceno {$excludedCount} souboru dle masky '{$cmdVal}'");
			return true;
		}

		return null;                                                       // Neznámý text s '=' zpracujeme jako masku souboru
	}

	/**
	 * Vyhledá a vloží všechny soubory odpovídající masce v manifestu.
	 */
	private function processMask(string $mask): bool
	{
		$files = glob($mask);                                              // Expanze masky souborů v aktuálním adresáři

		if ($files === false || count($files) === 0) {                     // Masce neodpovídá žádný soubor
			$this->console->warning(
				"[VAROVANI] Zadne soubory nenalezeny pro polozku/masku: '{$mask}'",
				self::WARNING_STYLE,
			);
			return true;
		}

		natcasesort($files);                                               // Přirozené abecední seřazení souborů
		$this->console->write("\n{$mask} ");                               // Výpis zpracovávané masky

		foreach ($files as $file) {
			if (!is_file($file)) {                                         // Zpracujeme pouze běžné soubory
				continue;
			}

			$realPath = realpath($file);                                   // Kanonická absolutní cesta k souboru
			if ($realPath === false || isset($this->processedFiles[$realPath])) {
				continue;                                                  // Přeskočení již vloženého či vyloučeného souboru
			}

			$normalizedContent = $this->readAndNormalizeContent($file);
			if ($normalizedContent === null) {                             // Soubor nešlo načíst; varování už bylo vypsáno
				continue;
			}

			$this->console->write('.');                                    // Indikace reálně vloženého souboru

			$cleanContent = "-- Následující kód je zkopírován ze souboru {$file}:\n--------\n" . $normalizedContent;
			$separator    = $this->buildFileSeparator($file, $normalizedContent);
			$footer       = "{$separator}-------- Konec souboru {$file}\n\n--------\n";

			$fullEntry  = $cleanContent . $footer;                         // Celý záznam souboru s čistými LF konci řádků
			$entryBytes = strlen($fullEntry);                              // Velikost záznamu v bajtech

			if (
				$this->maxOutputBytes > 0
				&& $this->fileCount > 0
				&& ($this->currentOutputBytes + $entryBytes) > $this->maxOutputBytes
			) {
				$this->closeOutput();
				$this->autoPartIndex++;                                    // Posun indexu další části
				$this->outputFile = $this->getNextOutputFilename($this->outputFile, $this->autoPartIndex);
				$this->console->writeln("\n[INFO] Prekrocen limit {$this->maxOutputBytes} B, automaticke prepnuti na '{$this->outputFile}'");

				if (!$this->openOutput()) {
					return false;
				}
			}

			if ($this->maxOutputBytes > 0 && ($this->currentOutputBytes + $entryBytes) > $this->maxOutputBytes) {
				$this->console->warning(
					"[VAROVANI] Samotny soubor '{$file}' ({$entryBytes} B) prekracuje nastaveny limit {$this->maxOutputBytes} B!",
					self::WARNING_STYLE,
				);
			}

			if (!$this->writeOutput($fullEntry)) {
				return false;
			}

			$this->currentOutputBytes        += $entryBytes;               // Přičtení zapsaných bajtů
			$this->processedFiles[$realPath]  = true;                      // Zápis do registru zpracovaných souborů
			$this->fileCount++;                                            // Zvýšení počtu vložených souborů
		}

		return true;
	}

	/**
	 * Bezpečně načte textový soubor, odstraní UTF-8 BOM, převede případné
	 * Windows-1250 do UTF-8, sjednotí konce řádků na LF (odstraní všechny CR)
	 * a upozorní na případný nechtěný výskyt znaků cyrilice (azbuky).
	 * Při chybě čtení vypíše barevné varování a vrátí null.
	 */
	private function readAndNormalizeContent(string $filePath): ?string
	{
		$content = file_get_contents($filePath);                           // Přečtení obsahu souboru
		if ($content === false) {
			$this->console->warning(
				"[VAROVANI] Nelze precist soubor '{$filePath}', bude preskocen.",
				self::WARNING_STYLE,
			);
			return null;
		}

		if (str_starts_with($content, self::UTF8_BOM)) {                   // Odříznutí případného UTF-8 BOM na začátku
			$content = substr($content, 3);
		}

		if (!mb_check_encoding($content, 'UTF-8')) {                       // Pokud soubor není platný UTF-8, převedeme z CP1250
			$converted = iconv('WINDOWS-1250', 'UTF-8', $content);
			if ($converted === false) {
				$this->console->warning(
					"[VAROVANI] Konverze souboru '{$filePath}' z WINDOWS-1250 do UTF-8 selhala, pouzit puvodni obsah.",
					self::WARNING_STYLE,
				);
			} else {
				$content = $converted;
				$this->convertedCount++;                                   // Evidence zkonvertovaných souborů pro souhrn
			}
		}

		$normalized = str_replace(["\r\n", "\r"], "\n", $content);         // Sjednocení CRLF i samostatného CR na LF
		$this->warnOnCyrillicCharacters($filePath, $normalized);           // Kontrola na nechtěné znaky cyrilice (azbuky)
		return $normalized;                                                // Vrácení normalizovaného obsahu souboru
	}

	/**
	 * Zkontroluje normalizovaný UTF-8 obsah na výskyt znaků cyrilice (azbuky).
	 * Při nálezu vypíše barevné varování s přesným číslem řádku a ukázkou slov.
	 */
	private function warnOnCyrillicCharacters(string $filePath, string $normalizedContent): void // Kontrola výskytu cyrilice
	{
		if (preg_match('/\p{Cyrillic}/u', $normalizedContent) !== 1) {     // Rychlý návrat, pokud soubor cyrilici neobsahuje
			return;
		}

		$lines    = explode("\n", $normalizedContent);                     // Rozdělení obsahu na jednotlivé řádky
		$reported = 0;                                                     // Počitadlo vypsaných varování pro tento soubor
		$extra    = 0;                                                     // Počet dalších řádků s cyrilicí nad limit

		foreach ($lines as $idx => $lineText) {                            // Průchod řádky souboru pro určení čísla řádku
			if (preg_match('/\p{Cyrillic}/u', $lineText) !== 1) {          // Přeskočení řádků bez cyrilice
				continue;
			}

			if ($reported >= self::MAX_CYRILLIC_WARNINGS) {                // Omezení počtu varování na jeden soubor
				$extra++;                                                  // Zapamatování počtu potlačených řádků
				continue;
			}

			$lineNo  = $idx + 1;                                           // Číslo řádku v původním souboru (od 1)
			$matches = [];                                                 // Pole zachycených slov obsahujících cyrilici
			preg_match_all('/[\p{L}\p{N}_]*\p{Cyrillic}[\p{L}\p{N}_]*/u', $lineText, $matches); // Extrakce dotčených slov
			$words  = array_values(array_unique($matches[0] ?? []));       // Unikátní seznam slov s cyrilicí na řádku
			$sample = implode(', ', array_slice($words, 0, 4));            // Ukázka nejvýše 4 slov z řádku

			$this->console->warning(
				"[VAROVANI] Nalezena azbuka (cyrilice) v souboru '{$filePath}' na radku {$lineNo}: {$sample}",
				self::WARNING_STYLE,
			);                                                             // Výpis barevného varování na STDERR
			$reported++;                                                   // Zvýšení počitadla vypsaných varování
		}

		if ($extra > 0) {                                                  // Doplňková informace o dalších řádcích nad limit
			$this->console->warning(
				"[VAROVANI] V souboru '{$filePath}' bylo nalezeno dalsich {$extra} radku se znaky cyrilice.",
				self::WARNING_STYLE,
				false,
			);                                                             // Souhrnné varování bez prázdného řádku navíc
		}
	}

	/**
	 * Sestaví oddělovač za obsahem souboru. Pro SQL soubory přidá dávkový oddělovač GO
	 * pouze tehdy, pokud už soubor příkazem GO nekončí.
	 */
	private function buildFileSeparator(string $file, string $normalizedContent): string
	{
		if (!str_ends_with(strtolower($file), '.sql')) {
			return "\n";                                                   // Pro ne-SQL soubory stačí zalomení řádku
		}

		if ($this->endsWithSqlGo($normalizedContent)) {                    // GO už v souboru je, nepřidáváme ho podruhé
			return str_ends_with($normalizedContent, "\n") ? "\n" : "\n\n";
		}

		return "\nGO\n\n";                                                 // Doplnění chybějícího oddělovače dávky
	}

	/**
	 * Ověří, zda normalizovaný SQL obsah (již bez znaků CR) končí samostatným příkazem GO.
	 * Zkoumá pouze poslední neprázdný řádek, takže je rychlý i pro velké SQL soubory.
	 */
	private function endsWithSqlGo(string $normalizedContent): bool
	{
		$trimmed = rtrim($normalizedContent, " \t\n");                     // Oříznutí koncových mezer, tabů a prázdných řádků
		if ($trimmed === '') {
			return false;
		}

		$lastNewlinePos = strrpos($trimmed, "\n");                         // Začátek posledního neprázdného řádku
		$lastLine       = ($lastNewlinePos === false)
			? $trimmed
			: substr($trimmed, $lastNewlinePos + 1);

		// Akceptuje samostatné GO (case-insensitive), volitelný počet opakování (GO 2) a komentář na témže řádku (-- ...)
		return preg_match('/\A[ \t]*GO(?:[ \t]+[1-9]\d*)?[ \t]*(?:--.*)?\z/i', $lastLine) === 1;
	}

	/**
	 * Vytvoří název dalšího výstupního souboru při překročení limitu bajtů.
	 * Odebere poslední 2 znaky z názvu souboru před příponou a nahradí je pořadovým číslem (01, 02...).
	 */
	private function getNextOutputFilename(string $currentFile, int $partIndex): string
	{
		$pathInfo = pathinfo($currentFile);                                // Rozklad cesty k výstupnímu souboru
		$dirName  = (string)($pathInfo['dirname'] ?? '');                  // Adresář výstupního souboru
		$dir      = ($dirName !== '.' && $dirName !== '') ? $dirName . DIRECTORY_SEPARATOR : '';
		$filename = (string)($pathInfo['filename'] ?? '');                 // Název souboru bez přípony
		$ext      = isset($pathInfo['extension']) ? '.' . $pathInfo['extension'] : '';

		$baseName = (mb_strlen($filename, 'UTF-8') >= 2)
			? mb_substr($filename, 0, -2, 'UTF-8')
			: $filename;                                                   // Oříznutí posledních 2 znaků

		return $dir . $baseName . sprintf('%02d', $partIndex) . $ext;      // Složení nového názvu s pořadovým číslem
	}

	/**
	 * Otevře nový výstupní soubor, zapíše UTF-8 BOM + hlavičku a inicializuje počítadlo bajtů.
	 */
	private function openOutput(): bool
	{
		if (file_exists($this->outputFile) && !unlink($this->outputFile)) {
			$this->console->error("[CHYBA] Nelze smazat predchozi vystupni soubor '{$this->outputFile}'.", true);
			return false;
		}

		$handle = fopen($this->outputFile, 'wb');                          // Otevření výstupního souboru pro binární zápis
		if ($handle === false) {
			$this->console->error("[CHYBA] Nelze vytvorit vystupni soubor '{$this->outputFile}'.", true);
			return false;
		}

		$this->outHandle = $handle;
		$this->console->writeln("Sestavuji skript '{$this->outputFile}'...\n");

		$outputBaseName = basename($this->outputFile);                     // Skutečný název aktuálně sestavovaného souboru
		$dateStr        = date('Y-m-d H:i');                               // Aktuální datum a čas sestavení
		$hostStr        = (string)gethostname();                           // Název počítače, na kterém probíhá build

		$header  = "/* ==========================================\n";      // Začátek hlavičky souboru
		$header .= " * {$outputBaseName} Auto-Deploy Build v. " . self::VERSION . "\n"; // Název výstupu a verze nástroje
		$header .= " * Tento soubor obsahuje zdrojové soubory předávané AI na začátku chatu\n";
		$header .= " * Datum vygenerování: {$dateStr}\n";                  // Časová značka vygenerování
		$header .= " * Počítač: {$hostStr}\n";                             // Identifikace počítače
		$header .= " * Kontrola kódování UTF-8 😊 (Příšerně žluťoučký kůň úpěl ďábelské ódy)\n";
		$header .= " * ========================================== */\n\n--------\n";

		$initialData = self::UTF8_BOM . $header;
		if (!$this->writeOutput($initialData)) {
			return false;
		}

		$this->currentOutputBytes = strlen($initialData);                  // Inicializace počítadla zapsaných bajtů
		return true;
	}

	/**
	 * Bezpečně zapíše řetězec do aktuálního výstupního souboru s kontrolou kompletnosti zápisu.
	 */
	private function writeOutput(string $data): bool
	{
		if (!is_resource($this->outHandle)) {
			$this->console->error("[CHYBA] Vystupni soubor '{$this->outputFile}' neni otevren pro zapis.", true);
			return false;
		}

		$written = fwrite($this->outHandle, $data);                        // Kontrola chyb zápisu (např. plný disk)
		if ($written === false || $written !== strlen($data)) {
			$this->console->error("[CHYBA] Selhal zapis do vystupniho souboru '{$this->outputFile}'.", true);
			return false;
		}

		return true;
	}

	/**
	 * Uzavře aktuální výstupní soubor, zaregistruje jej pro nastavení času a vynuluje počítadla.
	 */
	private function closeOutput(): void
	{
		if (is_resource($this->outHandle)) {
			fclose($this->outHandle);
			$this->outHandle = null;
			$this->registerGeneratedFile($this->outputFile);               // Registrace uzavřeného souboru pro sekvenční mtime
		}

		$convertedInfo = ($this->convertedCount > 0)
			? ", z toho {$this->convertedCount} konvertovano z CP1250"
			: '';

		$this->console->writeln("\n==========================================================");
		$this->console->writeln("HOTOVO! Bylo spojeno {$this->fileCount} souboru do '{$this->outputFile}' ({$this->currentOutputBytes} B{$convertedInfo}).");
		$this->console->writeln('==========================================================');

		$this->fileCount          = 0;                                     // Vynulování počtu souborů
		$this->convertedCount     = 0;                                     // Vynulování počtu konverzí
		$this->currentOutputBytes = 0;                                     // Vynulování počtu bajtů
	}

	/**
	 * Zaznamená cestu vytvořeného výstupního souboru v pořadí posledního zápisu.
	 */
	private function registerGeneratedFile(string $filePath): void
	{
		$existingIndex = array_search($filePath, $this->generatedFiles, true);
		if ($existingIndex !== false) {                                    // Při opakovaném přepisu přesuneme soubor na konec
			unset($this->generatedFiles[$existingIndex]);
			$this->generatedFiles = array_values($this->generatedFiles);
		}

		$this->generatedFiles[] = $filePath;
	}

	/**
	 * Nastaví všem vytvořeným výstupním souborům striktně rostoucí čas poslední změny
	 * s rozestupem 2 s směrem dozadu od aktuálního času, aby spolehlivě držely pořadí.
	 */
	private function applySequentialTimestamps(): void
	{
		$totalFiles = count($this->generatedFiles);
		if ($totalFiles <= 1) {                                            // Pro jediný soubor není třeba čas posouvat
			return;
		}

		$endTimestamp = time();                                            // Poslední soubor dostane přesný čas dokončení
		foreach ($this->generatedFiles as $index => $filePath) {
			$offsetSeconds = ($totalFiles - 1 - $index) * self::TIMESTAMP_STEP_SECONDS;
			$targetMtime   = $endTimestamp - $offsetSeconds;

			if (!touch($filePath, $targetMtime)) {
				$this->console->warning(
					"[VAROVANI] Nepodarilo se nastavit cas zmeny u souboru '{$filePath}'.",
					self::WARNING_STYLE,
				);
			}
		}
	}
}

if (PHP_SAPI !== 'cli') {                                                  // Ochrana před spuštěním mimo příkazovou řádku
	fwrite(STDERR, "[CHYBA] Tento skript lze spoustet pouze z prikazove radky (CLI).\n");
	exit(1);
}

$manifestFile   = (string)($argv[1] ?? '');                                // 1. povinný parametr: manifest
$outputFile     = (string)($argv[2] ?? '');                                // 2. povinný parametr: výstupní soubor
$maxOutputBytes = max(0, (int)($argv[3] ?? 0));                            // 3. volitelný parametr: limit velikosti v bajtech

$console = new ConsoleOutput();
$builder = new ReleaseBuilder($console, $manifestFile, $outputFile, $maxOutputBytes);

exit($builder->run());