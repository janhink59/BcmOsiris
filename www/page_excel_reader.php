<?php
/**
 * =============================================================================
 * Verze: 2026-10-14 22:25
 * Soubor: page_excel_reader.php
 * Třída: page_excel_reader
 * Účel: Uživatelské rozhraní pro nahrávání, validaci, náhled a import dat z XLSX.
 * Architektura: Potomek abstract_page.
 *
 * Vazby na okolí:
 * - Instancována dynamicky z index.php při požadavku ?page=excel_reader.
 * - Dědí z třídy abstract_page (využívá $this->page_title, $this->access_denied,
 *   parent::render() a implementuje abstraktní metodu render_body()).
 * - Využívá globální proměnné $dbsession (kontrola active_role), $T_SUBMIT
 *   (popisek tlačítka) a $charset (kódování pro HTTP hlavičku distribuce).
 * - Využívá funkce regfile(), getinput(), charliteral() a sqlarray_simple()
 *   z knihovny OsirisLib.php.
 * - Instancuje a řídí třídu excel_reader (z excel_reader.php) a přistupuje
 *   k jejím vlastnostem $reader->data, $reader->rqm, $reader->package_class,
 *   $reader->package_code a $reader->package_ready.
 * - V režimu distribuce ('D') volá databázovou proceduru p_export_to_sql
 *   nad dočasnými tabulkami s prefixem XLSX_ a příponou $ (chr(36)) a skládá
 *   výstupní dávku volající p_request_messages_start a p_xlsx_<package_code>.
 *
 * Změny:
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

class page_excel_reader extends abstract_page {

	protected ?excel_reader $reader = null;             // Instance čteče XLSX souborů
	protected string $import_mode = '0';                // Zvolený režim zpracování ('0', '1', '2', 'D')
	protected string $table_prefix = 'XLSX_';           // Pevná předpona zakládaných staging tabulek
	protected bool $has_file = false;                   // Příznak úspěšného nahrání souboru z formuláře

	public function __construct() {
		global $dbsession;                              // Globální pole s kontextem přihlášeného uživatele
		
		$this->page_title = 'Import dat z Excelu - BCM Osiris'; // Nastavení titulku stránky
		
		// Ochrana stránky před neoprávněným spuštěním
		$active_role = $dbsession['active_role'] ?? 'U'; // Zjištění aktivní role ze sezení
		if (!in_array($active_role, ['S', 'D'], true)) {
			$this->access_denied = true;                // Odepření přístupu pro běžné uživatele a orgadminy
		}
	}

	/**
	 * Zpracuje nahraný soubor před generováním HTML hlaviček.
	 * Je to klíčové pro režim Distribuce (D), který musí odeslat raw SQL.
	 */
	public function render(): void {
		if ($this->access_denied) {                     // Kontrola zamítnutí přístupu před zpracováním
			parent::render();                           // Vykreslení chybové obrazovky z předka
			return;
		}

		$tmpfile = regfile("file_xlsx");                // Získání cesty k dočasnému uploadovanému souboru

		if ($tmpfile) {                                 // Pokud byl soubor úspěšně odeslán
			$this->has_file = true;                     // Označení přítomnosti souboru pro vykreslení výsledků
			$this->import_mode = (string)getinput('import_mode'); // Načtení zvoleného režimu zpracování

			$this->reader = new excel_reader($tmpfile); // Vytvoření instance čteče pro nahraný soubor
			
			// Provedení hlavní sady operací nad souborem
			$this->reader->setImportMode($this->import_mode)
				->get_data()
				->prepare_package()
				->save_to_tables($this->table_prefix);  // Uložení načtených listů do staging tabulek XLSX_*$

			// Pokud je režim D, vygenerujeme SQL a okamžitě ukončíme běh
			if ($this->import_mode === 'D') {           // Detekce požadavku na vygenerování distribučního skriptu
				$this->process_distribution();          // Odeslání SQL skriptu ke stažení
				return;                                 // Zabráníme vykreslení HTML obálky
			}

			// Běh samotného importního skriptu na DB (1 = Test, 2 = Ostrý zápis)
			if (in_array($this->import_mode, ['1', '2'], true)) {
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
			$this->render_form();                       // Vykreslení vstupního nahrávacího formuláře
		}
	}

	/**
	 * Zobrazí formulář pro výběr souboru a režimu zpracování.
	 */
	protected function render_form(): void {
		global $T_SUBMIT;                               // Globální fráze pro popisek odesílacího tlačítka
		
		$submit_text = $T_SUBMIT ?? 'Načíst a zpracovat'; // Výchozí český text tlačítka
		$page_param = htmlspecialchars((string)getinput('page')); // Očištěný název stránky do URL formuláře

		echo <<<HTML
		<h1 class="page-heading">Načtení dat z excelu pro účely distribuce a importu</h1>
		<p style="margin-bottom: 20px;">Vyberte zdrojový soubor XLSX a zvolte požadovaný režim zpracování.</p>

		<form id="f" name="f" action="index.php?page={$page_param}" method="post" enctype="multipart/form-data" target="_blank">
			<table class="md-table" style="width: auto; margin-bottom: 20px;">
				<tr>
					<td style="font-weight: bold; width: 150px; background-color: #f8fafc;">Soubor XLSX:</td>
					<td><input type="file" name="file_xlsx" id="file_xlsx" accept=".xlsx" style="height:30px; width: 300px;" required></td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">Režim zpracování:</td>
					<td>
						<select name="import_mode" id="import_mode" style="width: 300px; padding: 4px;">
							<option value="0">Pouze zobrazit data</option>
							<option value="1">Kontrolní běh (Rollback)</option>
							<option value="2">Import se zápisem (Commit)</option>
							<option value="D">Distribuce (SQL skript)</option>
						</select>
					</td>
				</tr>
			</table>
			<button type="submit" class="btn btn-success">{$submit_text}</button>
		</form>
HTML;
	}

	/**
	 * Vykreslí načtená data a případné logovací zprávy.
	 */
	protected function render_results(): void {
		// Vypsání zpráv nasbíraných třídou request_message
		echo "<div style='margin: 15px 0;'>{$this->reader->rqm}</div>"; // Výpis tabulky výsledkových zpráv

		// Zobrazení dat v HTML tabulkách pro režim náhledu
		if ($this->import_mode === '0') {               // Kontrola, zda je zvolen režim pouhého zobrazení
			$max_display_rows = 500;                    // Maximální počet vykreslovaných řádků v náhledu
			
			echo <<<HTML
			<style>
				.md-table td { max-width: 300px; white-space: pre-wrap; word-break: break-word; }
				.md-table th.optional { background-color: #fef08a !important; color: #854d0e; }
				.md-table th.mandatory { background-color: #e9f2fa !important; }
			</style>
HTML;

			foreach ($this->reader->data as $tn => $table) {
				if (!$table) {                          // Přeskočení prázdné definice tabulky
					continue;
				}
				
				$col_count = $table['column_count'];    // Počet sloupců aktuální záložky
				$row_count = $table['row_count'];       // Počet datových řádků aktuální záložky
				$mimo_text = !empty($table['mimo']) ? "<span style='color: #dc2626; margin-left: 10px;'>(Data zasahují i mimo rozeznanou tabulku)</span>" : ""; // Varování při datech mimo tabulku
				
				$is_mandatory_table = $this->reader->is_mandatory_table($tn); // Zjištění, zda je záložka povinná
				$header_bg = $is_mandatory_table ? "background-color: #e2e8f0; color: #0f172a;" : "background-color: #fef08a; color: #854d0e;"; // Styl záhlaví tabulky
				
				echo "<table class='md-table' style='margin-bottom: 30px;'>";
				echo "<thead>";
				echo "<tr><th colspan='{$col_count}' style='font-size: 14px; {$header_bg}'>Záložka: {$tn} [{$row_count} řádků, {$col_count} sloupců] {$mimo_text}</th></tr>";
				echo "<tr>";
				
				foreach ($table['column_list'] as $colname) {
					$is_mand_col = isset($table['mandatory_column_list'][$colname]); // Kontrola povinnosti sloupce
					$th_class = $is_mand_col ? "class='mandatory'" : "class='optional'"; // Přiřazení CSS třídy buňce záhlaví
					echo "<th {$th_class}>" . htmlspecialchars($colname) . "</th>";
				}
				echo "</tr>";
				echo "</thead>";
				echo "<tbody>";

				$num = 0;                               // Počitadlo vypsaných řádků v tabulce
				foreach ($table['rows'] as $rn => $rv) {
					if ($num >= $max_display_rows) {    // Omezení výpisu při překročení limitu řádků
						echo "<tr><td colspan='{$col_count}' style='text-align:center; font-style:italic; background-color:#f8fafc; color: #64748b;'>... Zobrazeno pouze prvních {$max_display_rows} z celkových {$row_count} řádků ...</td></tr>";
						break;
					}
					
					echo "<tr>";
					foreach ($table['column_list'] as $cn) {
						$val = $rv[$cn] ?? '';          // Hodnota buňky pro zobrazení v tabulce
						echo "<td>" . htmlspecialchars((string)$val) . "</td>";
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
		if (!$this->reader->package_ready || !$pc) {    // Ověření připravenosti balíčku a existence třídy
			$this->reader->rqm->add_message("Balíček není připraven pro distribuci", 3);
			$this->reader->rqm->add_message("Režim byl automaticky přepnut na zobrazení dat", 2);
			$this->import_mode = '0';                   // Nouzové přepnutí do režimu náhledu
			parent::render();                           // Vykreslíme chybové hlášky standardní cestou
			return;
		}

		// Nastavení hlaviček pro okamžité stažení textového souboru
		header("Content-Type: application/sql; charset={$charset}");
		header("Content-Disposition: attachment; filename=\"fillup_{$code}.sql\"");
		header("Cache-Control: public");

		echo "-- {$pc->import_name} \n";                // Název importního balíčku v záhlaví skriptu
		echo "-- Tato dávka vkládá data do dočasných tabulek a v závěru volá proceduru pro jejich import.\n";
		echo "-- Případné chyby hlaste dodavateli RAMSES (hink@rac.cz).\n\n";
		echo "/* Content description:\n\n{$pc->description}\n\n*/\n\n";
		echo "-- Creating temporary tables\n";

		// Průchod mandatory tabulkami a export jejich INSERT struktury
		foreach ($pc->mandatory_tables as $t) {
			$safe_table = charliteral($this->table_prefix . $t . chr(36)); // Sestavení názvu staging tabulky včetně znaku '$'
			$a = sqlarray_simple("execute p_export_to_sql {$safe_table}, {$safe_table}, @output_as_sqlresult=1");
			
			if (is_array($a)) {                         // Pokud procedura vrátila řádky SQL skriptu
				foreach ($a as $row) {
					echo "\n{$row['txt']}";             // Výpis vygenerovaného řádku DDL/DML
				}
			}
			echo "\n";
		}

		$n = charliteral((string)$pc->import_name);     // Název importu jako bezpečný SQL literál
		$v = charliteral((string)$pc->version_date);    // Datum verze balíčku jako bezpečný SQL literál

		// Závěr SQL skriptu s voláním distribuční procedury
		echo "\nGO\nset xact_abort on\nbegin tran\nexecute p_request_messages_start\nexecute p_xlsx_{$code}\nexecute insert_request_message {$n}, 1, @charvalue={$v}\ncommit\nGO\n";
		exit;                                           // Okamžité ukončení běhu PHP skriptu
	}
}