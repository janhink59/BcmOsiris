<?php
/**
 * =============================================================================
 * Verze: 2026-10-21 15:00
 * Soubor: page_excel_reader.php
 * Třída: page_excel_reader
 * Účel: Uživatelské rozhraní pro nahrávání, validaci, náhled a import dat z XLSX
 *       a generování distribučních SQL skriptů.
 *       (Zpětný export systémových metadat do XLSX byl vyčleněn do samostatné
 *       stránky page_xlsx_export_meta.php).
 * Architektura: Potomek abstract_page.
 *
 * Vazby na okolí:
 * - Instancována dynamicky z index.php při požadavku ?page=page_excel_reader.
 * - Dědí z třídy abstract_page (využívá $this->page_title, $this->access_denied,
 *   $this->full_width, $this->phrase(), parent::render() a implementuje render_body()).
 * - Využívá komponentu abstract_button pro vykreslení odesílacího tlačítka
 *   a odkazu na stránku exportu metadat (page_xlsx_export_meta).
 * - Využívá globální proměnné $dbsession (kontrola active_role přes předka)
 *   a $charset (kódování pro HTTP hlavičku distribuce).
 * - Využívá funkce regfile(), getinput(), charliteral() a sqlarray_simple()
 *   z knihovny OsirisLib.php.
 * - Instancuje a řídí třídu excel_reader (z excel_reader.php) a načítá
 *   abstraktního předka balíčků xlsx_abstract (z xlsx_abstract.php).
 * - V režimu distribuce ('D') volá databázovou proceduru p_export_to_sql
 *   nad dočasnými tabulkami s prefixem XLSX_ a příponou $ (chr(36)) a skládá
 *   výstupní dávku volající p_request_messages_start a p_xlsx_<package_code>.
 *
 * Změny:
 * 2026-10-21 15:00 - Vyčlenění zpětného exportu metadat do samostatné stránky
 *                    page_xlsx_export_meta.php (výrazné zjednodušení a zkrácení).
 * 2026-10-19 14:45 - Doplněno načtení require_once pro excel_reader.php a xlsx_abstract.php.
 *                  - Zapnut režim plné šířky okna ($this->full_width = true) při
 *                    zobrazení výsledků a přehledné CSS stylování tabulek.
 *                  - Všechna čtení result-setů převedena na sqlarray_simple().
 * =============================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/excel_reader.php';
require_once __DIR__ . '/xlsx_abstract.php';

class page_excel_reader extends abstract_page {

	protected ?excel_reader $reader = null;             // Instance čteče XLSX souborů
	protected string $import_mode = '0';                // Zvolený režim zpracování ('0', '1', '2', 'D')
	protected string $table_prefix = 'XLSX_';           // Pevná předpona zakládaných staging tabulek
	protected bool $has_file = false;                   // Příznak úspěšného nahrání souboru z formuláře

	public function __construct() {
		parent::__construct();                          // Inicializace správce frází a kontroly přístupu v předkovi
		$this->page_title = $this->phrase('page_title', [], 'Import dat z Excelu - BCM Osiris'); // Lokalizovaný titulek stránky
	}

	/**
	 * Zpracuje nahraný soubor před generováním HTML hlaviček (klíčové pro režim Distribuce 'D').
	 */
	public function render(): void {
		$this->init_phrases();                          // Pojistka inicializace správce frází
		$this->check_system_role_access();              // Pojistka kontroly přístupu podle meta_object

		if ($this->access_denied) {                     // Kontrola zamítnutí přístupu před zpracováním
			parent::render();                           // Vykreslení chybové obrazovky z předka
			return;                                     // Ukončení zpracování při odepřeném přístupu
		}

		$tmpfile = regfile("file_xlsx");                // Získání cesty k dočasnému uploadovanému souboru

		if ($tmpfile !== '') {                          // Pokud byl soubor úspěšně odeslán
			$this->has_file = true;                     // Označení přítomnosti souboru pro vykreslení výsledků
			$this->full_width = true;                   // Roztažení panelu na celou šířku okna pro přehledné tabulky
			$this->import_mode = (string)getinput('import_mode'); // Načtení zvoleného režimu zpracování

			$this->reader = new excel_reader($tmpfile); // Vytvoření instance čteče pro nahraný soubor

			$orig_name = (string)($_FILES['file_xlsx']['name'] ?? basename($tmpfile)); // Původní název souboru
			$msg_proc = $this->phrase('msg_processing_data', [], 'Zpracování dat');    // Text úvodní zprávy zpracování
			$lbl_infile = $this->phrase('lbl_input_file', [], 'Vstupní soubor');       // Popisek objektu vstupního souboru
			$this->reader->rqm->add_message($msg_proc, 0)->setobject($lbl_infile, $orig_name); // Zápis hlavičky do logu
			
			// Provedení hlavní sady operací nad souborem
			$this->reader->setImportMode($this->import_mode) // Nastavení režimu importu
				->get_data()                            // Proudové načtení všech listů
				->prepare_package()                     // Validace balíčku podle CONTENT_INFO
				->save_to_tables($this->table_prefix);  // Uložení načtených listů do staging tabulek XLSX_*$

			// Pokud je režim D, vygenerujeme SQL a okamžitě ukončíme běh
			if ($this->import_mode === 'D') {           // Detekce požadavku na vygenerování distribučního skriptu
				$this->process_distribution();          // Odeslání SQL skriptu ke stažení
				return;                                 // Zabráníme vykreslení HTML obálky
			}

			// Běh samotného importního skriptu na DB (1 = Test, 2 = Ostrý zápis)
			if (in_array($this->import_mode, ['1', '2'], true)) { // Kontrola databázového režimu
				$this->reader->run_package($this->import_mode);   // Spuštění obslužné procedury balíčku
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
	 * Zobrazí formulář pro výběr souboru XLSX k importu.
	 */
	protected function render_form(): void {
		$heading = htmlspecialchars($this->phrase('form_heading', [], 'Načtení dat z excelu pro účely distribuce a importu')); // Nadpis formuláře
		$intro = htmlspecialchars($this->phrase('form_intro', [], 'Vyberte zdrojový soubor XLSX a zvolte požadovaný režim zpracování.')); // Instrukce
		$lbl_file = htmlspecialchars($this->phrase('lbl_xlsx_file', [], 'Soubor XLSX:'));       // Popisek pole souboru
		$lbl_mode = htmlspecialchars($this->phrase('lbl_import_mode', [], 'Režim zpracování:')); // Popisek pole režimu
		$opt_0 = htmlspecialchars($this->phrase('opt_mode_preview', [], 'Pouze zobrazit data')); // Volba náhledu dat
		$opt_1 = htmlspecialchars($this->phrase('opt_mode_rollback', [], 'Kontrolní běh (Rollback)')); // Volba testovacího běhu
		$opt_2 = htmlspecialchars($this->phrase('opt_mode_commit', [], 'Import se zápisem (Commit)')); // Volba ostrého importu
		$opt_d = htmlspecialchars($this->phrase('opt_mode_dist', [], 'Distribuce (SQL skript)'));      // Volba generování distribuce

		$btn_submit = new abstract_button('btn_submit_excel', 'Načíst a zpracovat', 'page_excel_reader', '', 'btn-success'); // Tlačítko odeslání
		$btn_submit->set_type('submit');                // Nastavení typu tlačítka na submit
		$submit_html = $btn_submit->render();           // Vykreslení HTML kódu tlačítka importu

		$btn_go_exp = new abstract_button('btn_goto_export_meta', 'Přejít na export metadat do Excelu →', 'page_excel_reader', '', 'btn-secondary'); // Odkaz na export
		$btn_go_exp->set_href('index.php?page=page_xlsx_export_meta')->set_style('margin-left: 10px;'); // Cílová adresa exportu
		$export_link_html = $btn_go_exp->render();      // Vykreslení tlačítka přechodu na export

		echo <<<HTML
		<style>
			.xlsx-form-table { border-collapse: collapse; margin-bottom: 20px; }
			.xlsx-form-table td { border: 1px solid #cbd5e1; padding: 8px 12px; font-size: 13px; }
		</style>
		<h1 class="page-heading">{$heading}</h1>
		<p style="margin-bottom: 20px;">{$intro}</p>

		<form id="f" name="f" action="index.php?page=page_excel_reader" method="post" enctype="multipart/form-data" target="_blank">
			<table class="xlsx-form-table">
				<tr>
					<td style="font-weight: bold; width: 220px; background-color: #f8fafc;">{$lbl_file}</td>
					<td><input type="file" name="file_xlsx" id="file_xlsx" accept=".xlsx" style="height:30px; width: 320px;" required></td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_mode}</td>
					<td>
						<select name="import_mode" id="import_mode" style="width: 320px; padding: 4px;">
							<option value="0">{$opt_0}</option>
							<option value="1">{$opt_1}</option>
							<option value="2">{$opt_2}</option>
							<option value="D">{$opt_d}</option>
						</select>
					</td>
				</tr>
			</table>
			<div>
				{$submit_html}
				{$export_link_html}
			</div>
		</form>
HTML;
	}

	/**
	 * Vykreslí načtená data a případné logovací zprávy.
	 */
	protected function render_results(): void {
		echo <<<HTML
		<style>
			.xlsx-msg-wrap table { border-collapse: collapse; border: 1px solid #64748b; font-size: 12px; margin-bottom: 18px; }
			.xlsx-msg-wrap th { background-color: #a5c4d4; color: #000; border: 1px solid #64748b; padding: 4px 8px; text-align: center; font-weight: bold; }
			.xlsx-msg-wrap td { background-color: #dbe4f0; border: 1px solid #64748b; padding: 4px 8px; }
			table.xlsx-preview { border-collapse: collapse; border: 1px solid #64748b; font-size: 12px; margin: 5px 0 22px 0; width: auto; }
			table.xlsx-preview th, table.xlsx-preview td { border: 1px solid #888; padding: 3px 6px; vertical-align: top; }
			table.xlsx-preview td { max-width: 300px; white-space: pre-wrap; word-break: break-word; overflow-wrap: break-word; }
			table.xlsx-preview tr.sheet-title th { text-align: left; font-size: 13px; font-weight: bold; padding: 4px 8px; }
			table.xlsx-preview tr.sheet-title th.mand-sheet { background-color: #cbd5e1; color: #000; }
			table.xlsx-preview tr.sheet-title th.opt-sheet { background-color: yellow; color: #000; }
			table.xlsx-preview tr.col-headers th { position: sticky; top: 0; z-index: 2; font-weight: bold; text-align: center; }
			table.xlsx-preview tr.col-headers th.mandatory { background-color: #a5c4d4; color: #000; }
			table.xlsx-preview tr.col-headers th.optional { background-color: yellow; color: #000; }
			table.xlsx-preview tbody tr.row-odd td { background-color: #ffffff; }
			table.xlsx-preview tbody tr.row-even td { background-color: #e2e8f0; }
			table.xlsx-preview tbody tr:hover td { background-color: #dbeafe; }
		</style>
HTML;

		echo "<div class='xlsx-msg-wrap' style='margin: 5px 0 15px 0;'>{$this->reader->rqm}</div>"; // Výpis tabulky výsledkových zpráv

		if ($this->import_mode === '0') {               // Kontrola, zda je zvolen režim pouhého zobrazení
			$max_display_rows = 500;                    // Maximální počet vykreslovaných řádků v náhledu
			$msg_outside = htmlspecialchars($this->phrase('msg_data_outside_table', [], 'Data jsou i mimo tabulku')); // Varování mimo tabulku

			foreach ($this->reader->data as $tn => $table) { // Průchod načtenými záložkami
				if (!$table) {                          // Přeskočení prázdné definice tabulky
					continue;                           // Pokračování na další záložku
				}
				
				$col_count = (int)$table['column_count']; // Počet sloupců aktuální záložky
				$row_count = (int)$table['row_count'];    // Počet datových řádků aktuální záložky
				$span_cols = ($col_count > 0) ? $col_count : 1; // Bezpečný colspan i pro prázdnou záložku
				$mimo_text = !empty($table['mimo']) ? " <span style='color: red; font-weight: bold;'>{$msg_outside}</span>" : ""; // Varování
				
				$is_mandatory_table = $this->reader->is_mandatory_table((string)$tn); // Zda je záložka povinná
				$sheet_cls = $is_mandatory_table ? "mand-sheet" : "opt-sheet";        // CSS třída záhlaví tabulky
				$safe_tn = htmlspecialchars((string)$tn); // Ošetřený název záložky
				$rozmer = " [{$row_count},{$col_count}]"; // Rozměr tabulky ve formátu [řádky,sloupce]
				
				echo "<table class='xlsx-preview'><thead>";
				echo "<tr class='sheet-title'><th colspan='{$span_cols}' class='{$sheet_cls}'>{$safe_tn}{$rozmer}{$mimo_text}</th></tr>";
				echo "<tr class='col-headers'>";
				
				foreach ($table['column_list'] as $colname) { // Výpis názvů sloupců záložky
					$is_mand_col = isset($table['mandatory_column_list'][$colname]); // Kontrola povinnosti sloupce
					$th_class = $is_mand_col ? "class='mandatory'" : "class='optional'"; // Přiřazení CSS třídy
					echo "<th {$th_class}>" . htmlspecialchars((string)$colname) . "</th>"; // Buňka záhlaví sloupce
				}
				echo "</tr></thead><tbody>";

				$num = 0;                               // Počitadlo vypsaných řádků v tabulce
				foreach ($table['rows'] as $rv) {       // Průchod řádky záložky
					if ($num >= $max_display_rows) {    // Omezení výpisu při překročení limitu řádků
						$trunc_msg = htmlspecialchars($this->phrase(
							'msg_rows_truncated',       // Kód fráze omezení řádků
							['max' => $max_display_rows, 'total' => $row_count], // Proměnné pro interpolaci
							'... Zobrazeno pouze prvních {' . chr(36) . 'max} z celkových {' . chr(36) . 'total} řádků ...' // Výchozí text
						));
						echo "<tr><td colspan='{$span_cols}' style='text-align:center; font-style:italic; background-color:#f0f0f0; color: #333;'>{$trunc_msg}</td></tr>"; // Řádek zkrácení
						break;                          // Ukončení výpisu řádků záložky
					}
					
					$row_cls = (($num % 2) === 0) ? 'row-odd' : 'row-even'; // Střídání barev lichých a sudých řádků
					echo "<tr class='{$row_cls}'>";
					foreach ($table['column_list'] as $cn) { // Výpis hodnot buněk v řádku
						$val = (string)($rv[$cn] ?? ''); // Hodnota buňky pro zobrazení v tabulce
						echo "<td>" . nl2br(htmlspecialchars($val)) . "</td>"; // Buňka dat se zachováním konců řádků
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

		if (!$this->reader->package_ready OR !$pc) {    // Ověření připravenosti balíčku a existence třídy
			$err_not_ready = $this->phrase('err_pkg_not_ready', [], 'Balíček není připraven pro distribuci'); // Chybová zpráva
			$warn_switched = $this->phrase('warn_mode_switched', [], 'Režim byl automaticky přepnut na zobrazení dat'); // Varování
			$this->reader->rqm->add_message($err_not_ready, 3); // Zápis chyby do fronty zpráv
			$this->reader->rqm->add_message($warn_switched, 2); // Zápis varování do fronty zpráv
			$this->import_mode = '0';                   // Nouzové přepnutí do režimu náhledu
			parent::render();                           // Vykreslíme chybové hlášky standardní cestou
			return;                                     // Ukončení distribuční metody
		}

		header("Content-Type: application/sql; charset={$charset}"); // Hlavička SQL souboru
		header("Content-Disposition: attachment; filename=\"fillup_{$code}.sql\""); // Název stahovaného skriptu
		header("Cache-Control: public");

		echo "-- {$pc->import_name} \n";                // Název importního balíčku v záhlaví skriptu
		echo "-- Tato dávka vkládá data do dočasných tabulek a v závěru volá proceduru pro jejich import.\n";
		echo "-- Případné chyby hlaste dodavateli RAMSES (hink@rac.cz).\n\n";
		echo "/* Content description:\n\n{$pc->description}\n\n*/\n\n"; // Popis obsahu balíčku
		echo "execute p_drop_excel_tables @print_message=0\nGO\n\n";
		echo "-- Creating temporary tables\n";

		foreach ($pc->mandatory_tables as $t) {         // Export jednotlivých staging tabulek
			$safe_table = charliteral($this->table_prefix . $t . chr(36)); // Sestavení názvu staging tabulky včetně znaku '$'
			$a = sqlarray_simple("SET NOCOUNT ON; execute p_export_to_sql {$safe_table}, {$safe_table}, @output_as_sqlresult=1"); // Získání DDL a INSERTů
			
			if (is_array($a)) {                         // Pokud procedura vrátila řádky SQL skriptu
				foreach ($a as $row) {                  // Výpis jednotlivých řádků skriptu
					$txt = (string)($row['txt'] ?? $row[0] ?? ''); // Bezpečné přečtení sloupce txt
					echo "\n{$txt}";                    // Výpis vygenerovaného řádku DDL/DML
				}
			}
			echo "\n";
		}

		$n = charliteral((string)$pc->import_name);     // Název importu jako bezpečný SQL literál
		$v = charliteral((string)$pc->version_date);    // Datum verze balíčku jako bezpečný SQL literál

		echo "\nGO\nset xact_abort on\nbegin tran\nexecute p_request_messages_start\nexecute p_xlsx_{$code} @import_mode='2'\nexecute insert_request_message {$n}, 1, @charvalue={$v}\ncommit\nGO\nexecute p_drop_excel_tables @print_message=0\nGO\n"; // Závěrečný blok dávky
		exit;                                           // Okamžité ukončení běhu PHP skriptu
	}
}