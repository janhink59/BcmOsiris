<?php
/**
 * =============================================================================
 * Třída: page_excel_reader
 * Účel: Uživatelské rozhraní pro nahrávání, validaci, náhled a import dat z XLSX.
 * Architektura: Potomek abstract_page.
 * 
 * Změny:
 * 2026-10-12 - Doplněna kontrola oprávnění v konstruktoru (přístup pouze pro S a D).
 *            - Kompletní refaktoring do objektové podoby (Single Responsibility).
 *            - Výpis dat a formulářů využívá nativní CSS třídy systému (md-table).
 *            - Odstraněna závislost na zastaralých HTML helper funkcích.
 *            - Korektní řízení hlaviček pro režim "Distribuce" (stahování SQL).
 * =============================================================================
 */

declare(strict_types=1);

class page_excel_reader extends abstract_page {

	protected ?excel_reader $reader = null;
	protected string $import_mode = '0';
	protected string $table_prefix = '';
	protected bool $has_file = false;

	public function __construct() {
		global $dbsession;
		
		$this->page_title = 'Import dat z Excelu - BCM Osiris';
		
		// Ochrana stránky před neoprávněným spuštěním
		$active_role = $dbsession['active_role'] ?? 'U';
		if (!in_array($active_role, ['S', 'D'], true)) {
			$this->access_denied = true;
		}
	}

	/**
	 * Zpracuje nahraný soubor před generováním HTML hlaviček.
	 * Je to klíčové pro režim Distribuce (D), který musí odeslat raw SQL.
	 */
	public function render(): void {
		if ($this->access_denied) {
			parent::render();
			return;
		}

		$tmpfile = regfile("file_xlsx");

		if ($tmpfile) {
			$this->has_file = true;
			$this->import_mode = (string)getinput('import_mode');
			$this->table_prefix = isset($_POST['use_prefix']) ? 'XLSX_' : '';

			$this->reader = new excel_reader($tmpfile);
			
			// Provedení hlavní sady operací nad souborem
			$this->reader->setImportMode($this->import_mode)
				->get_data()
				->prepare_package()
				->save_to_tables($this->table_prefix);

			// Pokud je režim D, vygenerujeme SQL a okamžitě ukončíme běh
			if ($this->import_mode === 'D') {
				$this->process_distribution();
				return;                                                  // Zabráníme vykreslení HTML obálky
			}

			// Běh samotného importního skriptu na DB (1 = Test, 2 = Ostrý zápis)
			if (in_array($this->import_mode, ['1', '2'], true)) {
				$this->reader->run_package($this->import_mode);
			}
		}

		parent::render();
	}

	/**
	 * Rozcestník vykreslování vnitřku stránky.
	 */
	protected function render_body(): void {
		if ($this->has_file) {
			$this->render_results();
		} else {
			$this->render_form();
		}
	}

	/**
	 * Zobrazí formulář pro výběr souboru a režimu zpracování.
	 */
	protected function render_form(): void {
		global $T_SUBMIT;
		
		$submit_text = $T_SUBMIT ?? 'Načíst a zpracovat';
		$page_param = htmlspecialchars((string)getinput('page'));

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
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">Předpona tabulek:</td>
					<td>
						<label style="cursor:pointer;">
							<input type="checkbox" name="use_prefix" id="use_prefix" value="1" checked> 
							Přidat předponu <strong>XLSX_</strong>
						</label>
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
		echo "<div style='margin: 15px 0;'>{$this->reader->rqm}</div>";

		if ($this->import_mode === 'error') {
			echo "<div class='msg-err'>Soubor obsahuje kritické chyby a nemůže být zpracován.</div>";
			return;
		}

		// Zobrazení dat v HTML tabulkách pro režim náhledu
		if ($this->import_mode === '0') {
			$max_display_rows = 500;
			
			echo <<<HTML
			<style>
				.md-table td { max-width: 300px; white-space: pre-wrap; word-break: break-word; }
				.md-table th.optional { background-color: #fef08a !important; color: #854d0e; }
				.md-table th.mandatory { background-color: #e9f2fa !important; }
			</style>
HTML;

			foreach ($this->reader->data as $tn => $table) {
				if (!$table) {
					continue;
				}
				
				$col_count = $table['column_count'];
				$row_count = $table['row_count'];
				$mimo_text = !empty($table['mimo']) ? "<span style='color: #dc2626; margin-left: 10px;'>(Data zasahují i mimo rozeznanou tabulku)</span>" : "";
				
				$is_mandatory_table = $this->reader->is_mandatory_table($tn);
				$header_bg = $is_mandatory_table ? "background-color: #e2e8f0; color: #0f172a;" : "background-color: #fef08a; color: #854d0e;";
				
				echo "<table class='md-table' style='margin-bottom: 30px;'>";
				echo "<thead>";
				echo "<tr><th colspan='{$col_count}' style='font-size: 14px; {$header_bg}'>Záložka: {$tn} [{$row_count} řádků, {$col_count} sloupců] {$mimo_text}</th></tr>";
				echo "<tr>";
				
				foreach ($table['column_list'] as $colname) {
					$is_mand_col = isset($table['mandatory_column_list'][$colname]);
					$th_class = $is_mand_col ? "class='mandatory'" : "class='optional'";
					echo "<th {$th_class}>" . htmlspecialchars($colname) . "</th>";
				}
				echo "</tr>";
				echo "</thead>";
				echo "<tbody>";

				$num = 0;
				foreach ($table['rows'] as $rn => $rv) {
					if ($num >= $max_display_rows) {
						echo "<tr><td colspan='{$col_count}' style='text-align:center; font-style:italic; background-color:#f8fafc; color: #64748b;'>... Zobrazeno pouze prvních {$max_display_rows} z celkových {$row_count} řádků ...</td></tr>";
						break;
					}
					
					echo "<tr>";
					foreach ($table['column_list'] as $cn) {
						$val = $rv[$cn] ?? '';
						echo "<td>" . htmlspecialchars((string)$val) . "</td>";
					}
					echo "</tr>";
					$num++;
				}

				echo "</tbody></table>";
			}
		}
	}

	/**
	 * Generuje T-SQL dávku pro distribuci a odesílá ji jako soubor ke stažení.
	 */
	private function process_distribution(): void {
		global $charset;
		
		$pc = $this->reader->package_class;
		$code = $this->reader->package_code;

		// Fallback pro případ, že distribuce není možná
		if (!$this->reader->package_ready || !$pc) {
			$this->reader->rqm->add_message("Balíček není připraven pro distribuci", 3);
			$this->reader->rqm->add_message("Režim byl automaticky přepnut na zobrazení dat", 2);
			$this->import_mode = '0';
			parent::render();                                            // Vykreslíme chybové hlášky standardní cestou
			return;
		}

		// Nastavení hlaviček pro okamžité stažení textového souboru
		header("Content-Type: application/sql; charset={$charset}");
		header("Content-Disposition: attachment; filename=\"fillup_{$code}.sql\"");
		header("Cache-Control: public");

		echo "-- {$pc->import_name} \n";
		echo "-- Tato dávka vkládá data do dočasných tabulek a v závěru volá proceduru pro jejich import.\n";
		echo "-- Případné chyby hlaste dodavateli RAMSES (hink@rac.cz).\n\n";
		echo "/* Content description:\n\n{$pc->description}\n\n*/\n\n";
		echo "-- Creating temporary tables\n";

		// Průchod mandatory tabulkami a export jejich INSERT struktury
		foreach ($pc->mandatory_tables as $t) {
			$safe_table = charliteral($this->table_prefix . $t);
			$a = sqlarray_simple("execute p_export_to_sql {$safe_table}, {$safe_table}, @output_as_sqlresult=1");
			
			if (is_array($a)) {
				foreach ($a as $row) {
					echo "\n{$row['txt']}";
				}
			}
			echo "\n";
		}

		$n = charliteral((string)$pc->import_name);
		$v = charliteral((string)$pc->version_date);

		// Závěr SQL skriptu s voláním distribuční procedury
		echo "\nGO\nset xact_abort on\nbegin tran\nexecute p_request_messages_start\nexecute p_xlsx_{$code}\ninsert into service_logbook(name,version) values({$n},{$v})\ncommit\nGO\n";
		exit;                                                            // Okamžité ukončení běhu PHP skriptu
	}
}