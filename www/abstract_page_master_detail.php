<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 14:15
 * Soubor: abstract_page_master_detail.php
 * Třída: abstract_page_master_detail
 * Účel: Abstraktní třída rozšiřující základní stránku o dvoupanelový layout.
 *       Slouží jako pevný základ pro veškeré administrační obrazovky BCM systému.
 *
 * EXTERNÍ ZÁVISLOSTI PRO AI KONTEXT:
 * - Třída dědí z `abstract_page`, která definuje základní HTML kostru, globální
 *   CSS styly a instancuje horní pruh (`user_context`).
 * - Zpracování POST dat a PRG vzor (Post-Redirect-Get) volá globální funkci 
 *   `autoredirect()` z `OsirisLib.php`.
 * - Bezpečné načítání parametrů z URL zajišťuje funkce `getinput()`.
 * - Databázové dotazy a překlady podle `fallback_order` jsou delegovány na instanci
 *   `entity_manager` (`fetch_rows()` a `fetch_row()`), kterou tato třída inicializuje v metodě `render()`.
 * - Rozšířené vícepoložkové filtrování v modálním okně zajišťuje třída `filter_manager`
 *   (`filter_manager.php`) a přímý přechod na export/import CSV využívá balíček `simple_class`.
 *
 * Změny:
 * 2026-11-06 14:15 - Integrace třídy filter_manager (modální vícepoložkový filtr,
 *                    vlastnost $filter_basic_columns, proužek aktivního filtru),
 *                    tlačítko pro přímý CSV export/import třídy (simple_class)
 *                    a delegování applyMasterFilter() na stromový filtr applyTreeMasterFilter().
 * 2026-11-05 10:15 - Do přenosu kontextových parametrů doplněn parametr 'scale'.
 * =============================================================================
 */

declare(strict_types=1);

if (file_exists(__DIR__ . '/filter_manager.php')) {
	require_once __DIR__ . '/filter_manager.php';
}

abstract class abstract_page_master_detail extends abstract_page {

	/** Identifikátor logické třídy z DB (např. 'meta_object', 'asset_class') */
	protected string $class_name = '';                                       // Název logické třídy
	
	/** Volitelné omezení SQL dotazu pro načítání master panelu (např. "m.parent_object = ...") */
	protected string $master_where = '';                                     // Podmínka WHERE pro levý panel
	
	/** Mapování logických skupin vstupních polí. Očekává: ['Název sekce' => ['sloupec1', 'sloupec2']] */
	protected array $form_groups = [];                                       // Skupiny polí ve formuláři

	/** Seznam prioritních sloupců zobrazených ihned po otevření modálního filtru */
	protected array $filter_basic_columns = [];                              // Základní sloupce modálního filtru

	/** Příznak režimu pouze pro čtení v detailním panelu */
	protected bool $is_readonly = false;                                     // Uzamčení celého detailního panelu

	/** Příznak povolení zakládání nových záznamů (update_guid=NEW) */
	protected bool $allow_insert = true;                                     // Povolení vkládání nových záznamů
	
	/** Instance dynamického správce objektů řídící čtení a zápis */
	protected ?entity_manager $em = null;                                    // Instance správce entit

	/** Instance správce vícepoložkového filtru */
	protected ?filter_manager $filter_manager = null;                        // Instance správce filtrů

	/** Chybová zpráva z validace při ukládání záznamu v process_save() */
	protected string $save_error_message = '';                               // Text chyby při neúspěšném uložení

	/**
	 * Vrátí kanonický název aktuální stránky (např. 'page_meta_class').
	 */
	protected function get_current_page_name(): string {
		$page = trim((string) getinput('page'));                             // Načtení parametru page z požadavku
		if ($page === '') {                                                  // Kontrola prázdného názvu stránky
			return get_class($this);                                         // Fallback na název třídy stránky
		}
		$page = basename($page, '.php');                                     // Očištění názvu stránky
		if (! str_starts_with($page, 'page_')) {                             // Kontrola přítomnosti předpony page_
			$page = 'page_' . $page;                                         // Sjednocení na předponu page_
		}
		return $page;                                                        // Vrácení plného názvu stránky
	}

	/**
	 * Centralizované získání URL parametrů pro udržení kontextu (např. vazba na předka, hierarchii nebo škálu).
	 */
	protected function get_context_url_suffix(): string {
		$url_suffix = '';                                                    // Výchozí prázdný přívažek URL
		foreach (['parent_object', 'parent_class', 'hierarchy', 'scale', 'menu_code', 'show_removed'] as $ctx_param) { // Průchod kontextovými parametry
			$val = (string) getinput($ctx_param);                            // Hodnota kontextového parametru
			if ($val !== '') {                                               // Připojení neprázdného parametru
				$url_suffix .= "&{$ctx_param}=" . urlencode($val);           // Připojení kódovaného parametru
			}
		}
		return $url_suffix;                                                  // Vrácení sestaveného přívažku
	}

	/**
	 * Vrací kontextové parametry ve formě HTML skrytých inputů pro odeslání POSTem.
	 */
	protected function get_context_hidden_inputs(): string {
		$hidden_inputs = '';                                                 // Výchozí prázdný řetězec inputů
		foreach (['parent_object', 'parent_class', 'hierarchy', 'scale', 'menu_code', 'show_removed'] as $ctx_param) { // Průchod kontextovými parametry
			$val = (string) getinput($ctx_param);                            // Hodnota kontextového parametru
			if ($val !== '') {                                               // Vytvoření skrytého pole pro parametr
				$hidden_inputs .= "\n\t\t\t<input type=\"hidden\" name=\"{$ctx_param}\" value=\"" . htmlspecialchars($val) . "\">"; // Skryté pole
			}
		}
		return $hidden_inputs;                                               // Vrácení skrytých polí formuláře
	}

	/**
	 * Zajistí inicializaci správce vícepoložkového filtru (filter_manager) pro aktuální stránku.
	 */
	protected function init_filter_manager(): void {
		if ($this->filter_manager !== null OR $this->em === null OR ! class_exists('filter_manager')) { // Kontrola dostupnosti
			return;                                                          // Již inicializováno nebo není k dispozici
		}
		$basic_cols = $this->filter_basic_columns;                           // Základní sloupce definované potomkem
		if (empty($basic_cols)) {                                            // Pokud potomek nevyjmenoval vlastní sloupce
			$basic_cols = array_keys($this->em->get_list_columns());         // Použijeme sloupce zobrazené v levém panelu
		}
		$this->filter_manager = new filter_manager($this->em, '', $basic_cols); // Vytvoření instance správce filtrů
	}

	/**
	 * Aplikuje aktivní podmínky z filter_manageru na pole načtených záznamů.
	 */
	protected function apply_active_filters_to_rows(array $rows): array {    // Filtrace načtených řádků přes filter_manager
		$this->init_filter_manager();                                        // Pojistka inicializace správce filtrů
		if ($this->filter_manager === null OR ! $this->filter_manager->has_active_filters()) { // Pokud není žádný filtr aktivní
			return $rows;                                                    // Vrácení nezměněného pole záznamů
		}
		if (method_exists($this->filter_manager, 'filter_rows')) {           // Primární metoda filtrace v PHP
			return $this->filter_manager->filter_rows($rows);                // Vyfiltrování záznamů podle zadaných výrazů
		}
		if (method_exists($this->filter_manager, 'apply_to_rows')) {         // Alternativní název metody filtrace
			return $this->filter_manager->apply_to_rows($rows);              // Vyfiltrování záznamů
		}
		return $rows;                                                        // Záložní vrácení původních řádků
	}

	/**
	 * Vrátí víceřádkový čitelný souhrn aktivního filtru ve formátu "Label: výraz" (pro parametr info při exportu).
	 */
	protected function get_active_filter_info_text(): string {
		$this->init_filter_manager();                                        // Pojistka inicializace správce filtrů
		if ($this->filter_manager === null OR ! $this->filter_manager->has_active_filters()) { // Bez aktivního filtru
			return '';                                                       // Prázdný popis filtru
		}
		if (method_exists($this->filter_manager, 'get_info_summary')) {      // Primární metoda pro víceřádkové info
			return (string) $this->filter_manager->get_info_summary("\n");   // Řádky oddělené znakem LF
		}
		if (method_exists($this->filter_manager, 'build_info_text')) {       // Alternativní metoda pro info
			return (string) $this->filter_manager->build_info_text("\n");    // Řádky oddělené znakem LF
		}
		return '';                                                           // Fallback
	}

	/**
	 * Určí efektivní logickou třídu pro export/import simple_class (zohlední sekundární hierarchii).
	 */
	protected function get_export_class_code(): string {
		if ($this->class_name === 'hierarchy_item') {                        // U položek sekundární hierarchie zjistíme builtin_code hierarchie
			$hier_uuid = trim((string) getinput('hierarchy'));               // UUID vybrané sekundární hierarchie
			if ($hier_uuid !== '' AND is_guid($hier_uuid)) {                 // Pokud máme platné UUID hierarchie
				$h_row = sqlfirstrow("SELECT TOP 1 builtin_code FROM hierarchy WHERE original = " . guidliteral($hier_uuid) . " AND record_type = 'A' AND removed = 0"); // Dotaz na kód
				if (! empty($h_row['builtin_code'])) {                       // Pokud byl kód hierarchie nalezen
					return (string) $h_row['builtin_code'];                  // Vrátíme kód konkrétní sekundární hierarchie
				}
			}
		}
		return $this->class_name;                                            // Standardní název logické třídy
	}

	/**
	 * Vykreslí ovládací lištu vyhledávání (pole #master-filter + tlačítko modálního filtru + tlačítko CSV)
	 * a případný proužek aktivního filtru.
	 */
	protected function render_master_filter_controls(string $search_placeholder): void { // Vykreslení lišty filtrů a CSV
		$this->init_filter_manager();                                        // Inicializace správce filtrů
		$page_param = urlencode($this->get_current_page_name());             // Název aktuální stránky
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL
		$base_url = "index.php?page={$page_param}{$url_suffix}";             // Základní URL pro odeslání nebo vymazání filtru

		$has_adv = ($this->filter_manager !== null AND $this->filter_manager->has_active_filters()); // Zda je rozšířený filtr aktivní
		$adv_cnt = ($this->filter_manager !== null) ? $this->filter_manager->get_active_count() : 0; // Počet aktivních podmínek
		$flt_btn_bg = $has_adv ? '#2563eb' : '#f8fafc';                      // Barva pozadí tlačítka filtru
		$flt_btn_col = $has_adv ? '#ffffff' : '#334155';                     // Barva textu a ikony tlačítka filtru
		$flt_btn_brd = $has_adv ? '#1d4ed8' : '#cbd5e1';                     // Barva rámečku tlačítka filtru
		$tip_adv_flt = htmlspecialchars($this->phrase('tip_open_adv_filter', [], 'Rozšířený filtr podle více položek')); // Tooltip filtru
		$badge_cnt_html = ($adv_cnt > 0) ? "<span style=\"font-size: 11px; font-weight: bold; margin-left: 3px;\">({$adv_cnt})</span>" : ''; // Počet

		// Tlačítko pro přímý přechod na CSV export/import aktuální třídy (simple_class)
		$csv_btn_html = '';                                                  // Výchozí prázdný HTML kód tlačítka CSV
		$storage_tab = ($this->em !== null) ? $this->em->get_storage_table() : ''; // Fyzická tabulka třídy
		if ($this->class_name !== '' AND ! str_starts_with($storage_tab, 'meta_') AND $storage_tab !== 'organization') { // Pro věcné třídy tenanta
			$exp_cls = $this->get_export_class_code();                       // Kód exportované třídy
			$info_txt = $this->get_active_filter_info_text();                // Víceřádkový popis aktivního filtru
			$csv_url = "index.php?page=page_csv_package&package_code=simple_class&class_name=" . urlencode($exp_cls); // URL CSV balíčku
			if ($info_txt !== '') {                                          // Pokud je aktivní filtr, předáme jeho popis do parametru info
				$csv_url .= "&info=" . urlencode($info_txt);                 // Připojení parametru info
			}
			$safe_csv_url = htmlspecialchars($csv_url);                      // Ošetřená URL pro HTML atribut
			$tip_csv = htmlspecialchars($this->phrase('tip_csv_export_import', [], 'Export / Import dat této třídy (CSV balíček simple_class)')); // Tooltip CSV
			$csv_btn_html = "<a href=\"{$safe_csv_url}\" id=\"btn-master-csv-link\" data-base-csv-url=\"" . htmlspecialchars("index.php?page=page_csv_package&package_code=simple_class&class_name=" . urlencode($exp_cls)) . "\" title=\"{$tip_csv}\" onclick=\"return openSimpleClassCsv(this);\" style=\"display: inline-flex; align-items: center; justify-content: center; padding: 0 8px; height: 31px; border: 1px solid #cbd5e1; border-radius: 3px; background-color: #f8fafc; color: #0f172a; text-decoration: none; font-size: 11px; font-weight: bold; white-space: nowrap; box-sizing: border-box;\">CSV ⇅</a>"; // Tlačítko CSV
		}

		$funnel_svg = '<svg viewBox="0 0 24 24" style="width:15px; height:15px; fill:currentColor;"><path d="M10 18h4v-2h-4v2zM3 6v2h18V6H3zm3 7h12v-2H6v2z"/></svg>'; // Ikona filtru

		echo <<<HTML
			<div style="display: flex; align-items: center; gap: 5px;">
				<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="flex: 1; padding: 6px; box-sizing: border-box; height: 31px;">
				<button type="button" id="btn-open-adv-filter" title="{$tip_adv_flt}" onclick="if(window.bcmOpenFilterModal){window.bcmOpenFilterModal();}else{var m=document.getElementById('bcm-flt-modal-overlay');if(m)m.style.display='flex';}" style="display: inline-flex; align-items: center; justify-content: center; padding: 0 8px; height: 31px; border: 1px solid {$flt_btn_brd}; border-radius: 3px; background-color: {$flt_btn_bg}; color: {$flt_btn_col}; cursor: pointer; box-sizing: border-box;">
					{$funnel_svg}{$badge_cnt_html}
				</button>
				{$csv_btn_html}
			</div>
HTML;

		// Vykreslení proužku aktivního filtru a modálního okna z filter_manageru
		if ($this->filter_manager !== null) {                                // Pokud je správce filtrů inicializován
			if ($has_adv) {                                                  // Zobrazení proužku s aktivními podmínkami
				$summary_line = str_replace("\n", " ; ", $this->get_active_filter_info_text()); // Jednořádkový souhrn do proužku
				$safe_sum = htmlspecialchars($summary_line);                 // Ošetřený text souhrnu
				$clear_url = htmlspecialchars($base_url . "&clear_adv_filter=1"); // URL pro zrušení filtru
				$tip_clear = htmlspecialchars($this->phrase('tip_clear_adv_filter', [], 'Zrušit rozšířený filtr')); // Tooltip zrušení
				echo <<<HTML
			<div style="margin-top: 6px; padding: 4px 8px; background-color: #eff6ff; border: 1px solid #bfdbfe; border-radius: 3px; font-size: 11px; color: #1e40af; display: flex; justify-content: space-between; align-items: center; gap: 6px;">
				<span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title="{$safe_sum}"><strong>Filtr:</strong> {$safe_sum}</span>
				<a href="{$clear_url}" title="{$tip_clear}" style="color: #b91c1c; font-weight: bold; text-decoration: none; font-size: 14px; line-height: 1; padding: 0 3px;">×</a>
			</div>
HTML;
			}

			$errs = $this->filter_manager->get_validation_errors();          // Kontrola validačních chyb ve výrazu filtru
			if (! empty($errs)) {                                            // Výpis případné chyby syntaxe filtru
				foreach ($errs as $e_msg) {                                  // Průchod chybami
					echo "<div style=\"margin-top: 5px; padding: 4px 8px; background-color: #fef2f2; border-left: 3px solid #b91c1c; color: #991b1b; font-size: 11px;\">" . htmlspecialchars((string) $e_msg) . "</div>\n"; // Chyba
				}
			}

			if (method_exists($this->filter_manager, 'render_modal')) {      // Vykreslení samotného modálního okna filtru
				echo $this->filter_manager->render_modal($base_url);         // Modální okno filtru
			} elseif (method_exists($this->filter_manager, 'render_filter_modal')) { // Alternativní metoda
				echo $this->filter_manager->render_filter_modal($base_url);  // Modální okno filtru
			}
		}
	}

	/**
	 * Hlavní bod vstupu životního cyklu stránky.
	 * Ošetřuje inicializaci entity_manageru, filter_manageru a AJAX požadavky pro levý i pravý panel.
	 */
	public function render(): void {
		$this->init_phrases();                                               // Inicializace správce frází
		$this->check_system_role_access();                                   // Fail-safe kontrola oprávnění z meta_object

		if ($this->access_denied) {                                          // Kontrola zamítnutého přístupu
			parent::render();                                                // Vykreslení chybové stránky předkem
			return;                                                          // Ukončení zpracování
		}

		if ($this->class_name !== '' AND $this->em === null) {               // Kontrola potřeby inicializace správce
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance entity_manageru
		}

		$this->init_filter_manager();                                        // Inicializace správce filtrů

		if (isset($_GET['ajax_panel'])) {                                    // Detekce asynchronního požadavku na jeden z panelů
			$ajax_target = (string) $_GET['ajax_panel'];                     // Cílový panel ('master' nebo 'detail')
			if ($ajax_target === 'master') {                                 // Požadavek na překreslení levého panelu
				$this->render_master();                                      // Vykreslení pouze levého panelu
				exit;                                                        // Okamžité ukončení skriptu
			}
			if ($ajax_target === 'detail') {                                 // Požadavek na načtení pouze pravého detailu
				$this->render_detail();                                      // Vykreslení pouze pravého detailního panelu
				exit;                                                        // Okamžité ukončení skriptu
			}
		}
		
		parent::render();                                                    // Spuštění vykreslení celé stránky v předkovi
	}

	/**
	 * Zajišťuje zpracování POST dat z formuláře (včetně SSC stavů, validace klíčů a mazání konceptu) a následný redirect.
	 */
	protected function process_save(): void {
		if (isset($_POST['adv_filter']) AND ! isset($_POST['update_guid'])) { // Pokud byl POSTem odeslán modální filtr
			$this->init_filter_manager();                                    // Načtení a uložení filtru do $_SESSION
			$page_param = urlencode($this->get_current_page_name());         // Kanonický název aktuální stránky
			$url_suffix = $this->get_context_url_suffix();                   // Kontextové parametry URL
			autoredirect("index.php?page={$page_param}{$url_suffix}");       // PRG redirect po nastavení filtru
			return;                                                          // Ukončení
		}

		$this->save_error_message = '';                                      // Vynulování chybové zprávy před uložením
		if ($this->is_readonly OR $this->em === null) {                      // Kontrola readonly režimu a správce entit
			return;                                                          // V readonly režimu nebo bez správce neukládáme
		}

		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor upravovaného záznamu
		if ($update_guid === '') {                                           // Kontrola prázdného identifikátoru
			return;                                                          // Bez vybraného záznamu ani NEW neukládáme
		}

		if ($update_guid === 'NEW' AND ! $this->allow_insert) {              // Ochrana proti zakázanému vkládání nových záznamů
			return;                                                          // Zákaz uložení nového záznamu
		}

		$page_param = urlencode($this->get_current_page_name());             // Kanonický název aktuální stránky
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		if (isset($_POST['btn_delete_draft'])) {                             // Detekce stisku tlačítka Smazat koncept
			if ($update_guid !== 'NEW') {                                    // Pouze pro již uložený záznam
				$this->em->delete_draft($update_guid);                       // Fyzické smazání konceptu z databáze
			}
			autoredirect("index.php?page={$page_param}{$url_suffix}");       // Návrat na výchozí seznam po smazání konceptu
			return;                                                          // Ukončení zpracování
		}

		$target_status = '';                                                 // Výchozí prázdný cílový stav
		if (isset($_POST['btn_save'])) {                                     // Přímé uložení jako schválené
			$target_status = 'A';                                            // Stav Schváleno
		} elseif (isset($_POST['btn_save_draft'])) {                         // Uložení jako rozpracovaný koncept
			$target_status = 'D';                                            // Stav Koncept
		} elseif (isset($_POST['btn_forward_approval'])) {                   // Postoupení ke schválení
			$target_status = 'F';                                            // Stav Postoupeno ke schválení
		}

		if ($target_status === '') {                                         // Pokud nebylo stisknuto žádné ukládací tlačítko
			return;                                                          // Ukončení bez uložení
		}

		$save_guid = ($update_guid === 'NEW') ? '' : $update_guid;           // Pro nový záznam předáme prázdný řetězec
		$was_marked_removed = (isset($_POST['removed']) AND (string) $_POST['removed'] === '1'); // Zda uživatel zaškrtl zrušení
		
		$saved_orig = $this->em->save_post_data($save_guid, $target_status); // Autonomní uložení dat s cílovým stavem SSC

		if (method_exists($this->em, 'get_last_save_error')) {               // Kontrola, zda při ukládání nevznikla validační chyba
			$err_txt = $this->em->get_last_save_error();                     // Načtení textu případné chyby
			if ($err_txt !== '') {                                           // Pokud validace (prázdný klíč / duplicita / monotonie) selhala
				$this->save_error_message = $err_txt;                        // Uložení chyby pro zobrazení v render_detail()
				return;                                                      // Neprovádíme redirect, zachováme rozepsaný formulář
			}
		}
		
		$show_rem_active = ((string) getinput('show_removed') === '1');      // Zda je zapnuto zobrazování zrušených záznamů
		if ($was_marked_removed AND ! $show_rem_active AND $target_status === 'A') { // Pokud byl záznam zrušen a zrušené se nezobrazují
			autoredirect("index.php?page={$page_param}{$url_suffix}");       // Přesměrování na čistý seznam bez detailu
		} elseif ($saved_orig !== '' AND $saved_orig !== 'NEW') {            // Pokud máme platný originál uloženého záznamu
			autoredirect("index.php?page={$page_param}{$url_suffix}&update_guid=" . urlencode($saved_orig)); // Přesměrování na uložený záznam
		} else {
			autoredirect("index.php?page={$page_param}{$url_suffix}");       // Fallback na výchozí seznam
		}
	}

	/**
	 * Implementace abstraktní metody rodiče. 
	 * Obsahuje CSS, základní dvoupanelový HTML skelet a centrální JS obsluhu obou panelů.
	 */
	final protected function render_body(): void {
		$err_ajax_net = addslashes($this->phrase('err_ajax_network', [], 'Chyba sítě při AJAX volání')); // JS chybová hláška sítě
		$err_ajax_ref = addslashes($this->phrase('err_ajax_refresh', [], 'Chyba při obnově master panelu:')); // JS chybová hláška obnovy
		$err_ajax_det = addslashes($this->phrase('err_ajax_detail', [], 'Chyba při načítání detailu:')); // JS chybová hláška detailu
		$unsaved_confirm = addslashes($this->phrase('msg_unsaved_changes', [], 'Máte neuložené změny. Opravdu chcete stránku opustit?')); // Varování
		$lbl_quick_flt = addslashes($this->phrase('lbl_quick_filter_info', [], 'Rychlý filtr')); // Popisek rychlého filtru pro CSV info

		echo <<<HTML
		<style>
			.page-panel { max-width: 95% !important; padding: 0 !important; display: flex; flex-direction: row; height: calc(100vh - 120px); overflow: hidden; }
			.md-master { flex: 0 0 45%; min-width: 400px; border-right: 1px solid #ddd; background-color: #fafafa; padding: 20px; display: flex; flex-direction: column; overflow: hidden; }
			.md-detail { flex: 1; padding: 20px 30px; background-color: #ffffff; display: flex; flex-direction: column; overflow: hidden; transition: opacity 0.12s ease; }
			.md-detail.md-loading { opacity: 0.55; pointer-events: none; }
			.md-master-header, .md-sticky-header-master { flex: 0 0 auto; border-bottom: 2px solid #eee; margin-bottom: 10px; padding-bottom: 10px; }
			.md-master-content { flex: 1 1 auto; overflow-y: auto; padding-right: 5px; }
			.md-detail-header, .md-sticky-header-detail { flex: 0 0 auto; border-bottom: 2px solid #004488; display: flex; justify-content: space-between; align-items: center; padding-bottom: 10px; margin-bottom: 20px; gap: 10px; flex-wrap: wrap; }
			.md-detail-content { flex: 1 1 auto; overflow-y: auto; padding-right: 10px; }
			.md-master-header h2, .md-sticky-header-master h2, .md-detail-header h2, .md-sticky-header-detail h2 { color: #004488; }
			.md-table { width: 100%; border-collapse: collapse; margin-top: 0; }
			.md-table th { position: sticky; top: 0; background-color: #e9f2fa; padding: 6px 4px; border: 1px solid #ddd; text-align: left; z-index: 5; box-shadow: 0 1px 0 #ddd, 0 -1px 0 #ddd; }
			.md-table td { padding: 4px; border: 1px solid #ddd; }
			.md-table tr { background-color: #fff; color: #333; }
			.md-table tr:hover { background-color: #f1f1f1; }
			.md-row-active { background-color: #e6f7ff !important; color: #333 !important; }
			.md-row-inactive { background-color: #f9f9f9 !important; color: #999 !important; }
			.md-row-removed td { color: #991b1b !important; text-decoration: line-through; background-color: #fef2f2 !important; }
			.md-row-Active-removed td { color: #991b1b !important; text-decoration: line-through; background-color: #fde8e8 !important; }
			.ssc-badge { display: inline-block; font-size: 10px; font-weight: bold; padding: 1px 5px; border-radius: 3px; margin-left: 6px; vertical-align: middle; text-decoration: none !important; }
			.ssc-badge-d { background-color: #fef3c7; color: #92400e; border: 1px solid #f59e0b; }
			.ssc-badge-f { background-color: #dbeafe; color: #1e40af; border: 1px solid #3b82f6; }
			.ssc-badge-r { background-color: #fee2e2; color: #991b1b; border: 1px solid #ef4444; }
			.ssc-badge-rem { background-color: #991b1b; color: #ffffff; border: 1px solid #7f1d1d; }
		</style>

		<div class="md-master" id="md-master-container">
HTML;
		$this->render_master();                                              // Vykreslení levého panelu

		echo <<<HTML
		</div>
		<div class="md-detail" id="md-detail-container">
HTML;
		$this->render_detail();                                              // Vykreslení pravého panelu

		echo <<<HTML
		</div>
		
		<script>
			window.isTreeDomDirty = false;

			// Sestavení unikátního klíče v sessionStorage pro uchování filtru levého panelu
			function getMasterFilterStorageKey() {
				const u = new URL(window.location.href);
				const page = u.searchParams.get('page') || 'default';
				const pCls = u.searchParams.get('parent_class') || '';
				const pObj = u.searchParams.get('parent_object') || '';
				const hier = u.searchParams.get('hierarchy') || '';
				const scl  = u.searchParams.get('scale') || '';
				const fCls = u.searchParams.get('filter_class') || '';
				return 'bcm_mf_' + page + '_' + pCls + '_' + pObj + '_' + hier + '_' + scl + '_' + fCls;
			}

			// Aplikuje text filtru #master-filter na řádky v #master-list (na stromových stránkách zachová nadřízené uzly)
			function applyMasterFilter(term) {
				const list = document.getElementById('master-list');
				if (!list) return;
				const cleanTerm = (term || '').trim().toLowerCase();
				if (typeof window.applyTreeMasterFilter === 'function') {
					window.applyTreeMasterFilter(cleanTerm);
					return;
				}
				if (cleanTerm === '' && typeof window.applyMenuTreeVisibility === 'function') {
					window.applyMenuTreeVisibility();
					return;
				}
				list.querySelectorAll('tr').forEach(function(row) {
					row.style.display = (cleanTerm === '' || row.textContent.toLowerCase().includes(cleanTerm)) ? '' : 'none';
				});
			}

			// Otevře stránku CSV exportu/importu (simple_class) s přenesením rychlého i rozšířeného filtru do parametru info
			window.openSimpleClassCsv = function(linkEl) {
				if (!linkEl) return true;
				const u = new URL(linkEl.href, window.location.href);
				const quickInp = document.getElementById('master-filter');
				const quickVal = (quickInp && quickInp.value) ? quickInp.value.trim() : '';
				if (quickVal !== '') {
					const existingInfo = u.searchParams.get('info') || '';
					const quickLine = '{$lbl_quick_flt}: ' + quickVal;
					u.searchParams.set('info', existingInfo !== '' ? (existingInfo + '\n' + quickLine) : quickLine);
					u.searchParams.set('quick_filter', quickVal);
				}
				window.location.href = u.toString();
				return false;
			};

			// Obnoví uložený filtr ze sessionStorage (např. po uložení záznamu a PRG redirectu)
			function restoreMasterFilterFromStorage() {
				const input = document.getElementById('master-filter');
				if (!input) return;
				try {
					const saved = sessionStorage.getItem(getMasterFilterStorageKey());
					if (saved !== null && saved !== '') {
						input.value = saved;
						applyMasterFilter(saved);
					}
				} catch (e) {}
			}

			// Pokud je levý panel dlouhý, automaticky odscrolluje na právě vybraný aktivní řádek
			function scrollToActiveRow() {
				const activeRow = document.getElementById("active-row");
				const scrollingContainer = document.querySelector(".md-master-content");
				
				if (activeRow && scrollingContainer && activeRow.style.display !== 'none') {
					const containerRect = scrollingContainer.getBoundingClientRect();
					const rowRect = activeRow.getBoundingClientRect();
					if (rowRect.top < containerRect.top || rowRect.bottom > containerRect.bottom) {
						const offset = rowRect.top - containerRect.top;
						scrollingContainer.scrollTop += offset - (containerRect.height / 2) + (rowRect.height / 2);
					}
				}
			}

			// Přepnutí zobrazení zrušených záznamů (show_removed) v URL
			function toggleShowRemoved(checked) {
				const url = new URL(window.location.href);
				if (checked) {
					url.searchParams.set('show_removed', '1');
				} else {
					url.searchParams.delete('show_removed');
				}
				window.location.href = url.toString();
			}

			// Centrální klientské filtrování tabulky #master-list přes #master-filter s uložením do sessionStorage
			document.addEventListener('input', function(e) {
				if (e.target && e.target.id === 'master-filter') {
					const val = e.target.value;
					try {
						sessionStorage.setItem(getMasterFilterStorageKey(), val);
					} catch (err) {}
					applyMasterFilter(val);
				}
			});

			// Aktualizace zvýraznění aktivního řádku v levém panelu podle cílové URL nebo kliknutého řádku
			function updateActiveMasterRow(targetUrlObj, clickedRow) {
				const list = document.getElementById('master-list');
				if (!list) return;
				const targetGuid = (targetUrlObj.searchParams.get('update_guid') || targetUrlObj.searchParams.get('draft_uuid') || '').toLowerCase();

				list.querySelectorAll('tr').forEach(function(tr) {
					tr.classList.remove('md-row-active', 'md-row-Active-removed');
					if (tr.id === 'active-row') {
						tr.removeAttribute('id');
					}
				});

				let activeTr = clickedRow || null;
				if (!activeTr && targetGuid !== '' && targetGuid !== 'new') {
					list.querySelectorAll('tr').forEach(function(tr) {
						const rowUuid = (tr.getAttribute('data-uuid') || '').toLowerCase();
						if (rowUuid !== '' && rowUuid === targetGuid) {
							activeTr = tr;
						}
					});
				}

				if (activeTr) {
					activeTr.id = 'active-row';
					if (activeTr.classList.contains('md-row-removed')) {
						activeTr.classList.add('md-row-active', 'md-row-Active-removed');
					} else {
						activeTr.classList.add('md-row-active');
					}
				}
			}

			// Spustí vnořené <script> elementy uvnitř asynchronně načteného detailního panelu
			function executeDetailScripts(container) {
				if (!container) return;
				container.querySelectorAll('script').forEach(function(oldScript) {
					const newScript = document.createElement('script');
					Array.from(oldScript.attributes).forEach(function(attr) {
						newScript.setAttribute(attr.name, attr.value);
					});
					newScript.textContent = oldScript.textContent;
					oldScript.parentNode.replaceChild(newScript, oldScript);
				});
			}

			// Asynchronní načtení pouze pravého detailního panelu bez refreshe levého panelu
			window.loadDetailPanel = function(targetUrl, clickedRow, pushHistory) {
				if (typeof pushHistory === 'undefined') {
					pushHistory = true;
				}
				const cleanUrlObj = new URL(targetUrl, window.location.href);
				const hasDndParams = cleanUrlObj.searchParams.has('dnd_sort');

				if (typeof isFormDirty !== 'undefined' && isFormDirty) {
					if (!confirm('{$unsaved_confirm}')) {
						return false;
					}
					isFormDirty = false;
				}

				if (window.isTreeDomDirty && !hasDndParams) {
					window.isTreeDomDirty = false;
					refreshMasterPanel();
				}

				const detailContainer = document.getElementById('md-detail-container');
				if (!detailContainer) {
					window.location.href = targetUrl;
					return false;
				}

				cleanUrlObj.searchParams.delete('ajax_panel');

				const fetchUrlObj = new URL(cleanUrlObj.toString());
				fetchUrlObj.searchParams.set('ajax_panel', 'detail');

				updateActiveMasterRow(cleanUrlObj, clickedRow || null);
				detailContainer.classList.add('md-loading');

				fetch(fetchUrlObj.toString(), {
					headers: {
						'X-Requested-With': 'XMLHttpRequest'
					}
				})
				.then(function(response) {
					if (!response.ok) throw new Error("{$err_ajax_net}");
					return response.text();
				})
				.then(function(html) {
					detailContainer.innerHTML = html;
					detailContainer.classList.remove('md-loading');
					executeDetailScripts(detailContainer);
					if (typeof isFormDirty !== 'undefined' && !hasDndParams) {
						isFormDirty = false;
					}
					if (pushHistory) {
						const histUrlObj = new URL(cleanUrlObj.toString());
						histUrlObj.searchParams.delete('dnd_parent');
						histUrlObj.searchParams.delete('dnd_sort');
						window.history.pushState({ mdUrl: histUrlObj.toString() }, '', histUrlObj.toString());
					}
				})
				.catch(function(error) {
					detailContainer.classList.remove('md-loading');
					console.error('{$err_ajax_det}', error);
					window.location.href = cleanUrlObj.toString();
				});

				return false;
			};

			// Podpora tlačítek Zpět / Vpřed v prohlížeči při asynchronním přepínání záznamů
			window.addEventListener('popstate', function() {
				window.loadDetailPanel(window.location.href, null, false);
			});

			// Delegované zachycení tlačítek "+ Nový" v levém panelu a "Zahodit změny" v pravém panelu
			document.addEventListener('click', function(e) {
				const link = e.target.closest('a.btn');
				if (!link) return;
				const href = link.getAttribute('href');
				if (!href || href === '#' || link.getAttribute('target')) return;

				try {
					const targetUrl = new URL(href, window.location.href);
					const currUrl = new URL(window.location.href);
					if (targetUrl.pathname === currUrl.pathname && targetUrl.searchParams.get('page') === currUrl.searchParams.get('page')) {
						const inMaster = link.closest('#md-master-container');
						const inDetailDiscard = link.closest('#md-detail-container') && link.classList.contains('btn-danger');
						if (inMaster || inDetailDiscard) {
							e.preventDefault();
							if (inDetailDiscard && window.isTreeDomDirty) {
								window.isTreeDomDirty = false;
								refreshMasterPanel();
							}
							window.loadDetailPanel(targetUrl.toString(), null, true);
						}
					}
				} catch (err) {}
			});

			// Asynchronní překreslení (refresh) levého panelu se zachováním filtru a skriptů
			function refreshMasterPanel() {
				const url = new URL(window.location.href);
				url.searchParams.set('ajax_panel', 'master');
				
				fetch(url.toString(), {
					headers: {
						'X-Requested-With': 'XMLHttpRequest'
					}
				})
				.then(function(response) {
					if (!response.ok) throw new Error("{$err_ajax_net}");
					return response.text();
				})
				.then(function(html) {
					const masterPanel = document.getElementById("md-master-container");
					if (masterPanel) {
						masterPanel.innerHTML = html;
						executeDetailScripts(masterPanel);
						restoreMasterFilterFromStorage();
						scrollToActiveRow();
					}
				})
				.catch(function(error) {
					console.error('{$err_ajax_ref}', error);
				});
			}

			document.addEventListener("DOMContentLoaded", function() {
				restoreMasterFilterFromStorage();
				setTimeout(scrollToActiveRow, 50);
			});
		</script>
HTML;
	}

	/**
	 * Hook pro potomky: umožňuje vkládat tlačítka nad nadpis do fixní hlavičky levého panelu.
	 */
	protected function render_master_top(): void {
		// Záměrně prázdné - potomek (konkrétní stránka) zde může vypsat např. tlačítko "Zpět"
	}

	/**
	 * Generuje strukturu levého panelu včetně dynamické stavby tabulky záznamů.
	 */
	protected function render_master(): void {
		if ($this->em === null) {                                            // Kontrola inicializace správce entit
			return;                                                          // Ukončení při chybějícím správci
		}
		
		$list_columns = $this->em->get_list_columns();                       // Sloupce pro zobrazení v seznamu
		
		if (empty($list_columns)) {                                          // Kontrola definovaných sloupců seznamu
			$msg_no_cols = htmlspecialchars($this->phrase('msg_no_list_columns', [], 'Master panel nemá v metadatech (list_order) definované žádné sloupce.')); // Chybová hláška
			echo "<div class='msg-info'>{$msg_no_cols}</div>";               // Výpis informační zprávy
			return;                                                          // Ukončení vykreslování seznamu
		}

		$this->init_filter_manager();                                        // Inicializace správce filtrů
		$update_guid = (string) getinput('update_guid');                     // Aktuálně vybraný záznam
		$show_removed = ((string) getinput('show_removed') === '1');         // Příznak zobrazení zrušených záznamů
		if (! $show_removed AND $this->filter_manager !== null AND method_exists($this->filter_manager, 'should_show_removed') AND $this->filter_manager->should_show_removed()) { // Filtr na koš
			$show_removed = true;                                            // Automatické načtení záznamů v koši při filtru na zrušené
		}
		
		$class_meta = $this->em->get_class_meta();                           // Metadata aktuální třídy
		$caption_plural = (string) ($class_meta['caption_plural'] ?? '');    // Množné číslo názvu třídy
		
		if ($caption_plural === '') {                                        // Kontrola prázdného nadpisu seznamu
			$caption_plural = $this->phrase('default_list_heading', [], 'Seznam záznamů'); // Výchozí lokalizovaný nadpis seznamu
		}

		$safe_caption_plural = htmlspecialchars($caption_plural);            // Ošetřený nadpis seznamu
		$search_placeholder = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat...')); // Placeholder vyhledávání
		$lbl_show_rem = htmlspecialchars($this->phrase('lbl_show_removed', [], 'Zobrazit i zrušené')); // Popisek přepínače zrušených
		$chk_show_rem = $show_removed ? 'checked' : '';                      // Stav zaškrtnutí přepínače zrušených

		$badge_txt_d = htmlspecialchars($this->phrase('badge_draft', [], 'Koncept'));         // Štítek rozpracovaného konceptu
		$badge_txt_f = htmlspecialchars($this->phrase('badge_forwarded', [], 'Ke schválení')); // Štítek postoupeného návrhu
		$badge_txt_r = htmlspecialchars($this->phrase('badge_rejected', [], 'Vráceno'));      // Štítek vráceného návrhu
		$badge_txt_rem = htmlspecialchars($this->phrase('badge_removed', [], 'Zrušeno'));     // Štítek zrušeného záznamu

		echo <<<HTML
		<div class="md-master-header">
HTML;
		
		$this->render_master_top();                                          // Vykreslení horních prvků potomka

		echo <<<HTML
			<div style="display: flex; justify-content: space-between; align-items: center; margin: 0 0 10px 0;">
				<h2 style="font-size: 16px; margin: 0; border: none; padding: 0;">{$safe_caption_plural}</h2>
				<label style="font-size: 12px; color: #555; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; user-select: none;">
					<input type="checkbox" {$chk_show_rem} onchange="toggleShowRemoved(this.checked);"> {$lbl_show_rem}
				</label>
			</div>
HTML;

		$this->render_master_filter_controls($search_placeholder);           // Vykreslení pole #master-filter, tlačítka filtru, CSV a modálu

		echo <<<HTML
		</div>
		
		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
HTML;
		
		foreach ($list_columns as $col => $header) {                         // Vykreslení záhlaví sloupců tabulky
			echo "\t\t\t\t\t\t<th>" . htmlspecialchars($header) . "</th>\n"; // Buňka záhlaví sloupce
		}
		
		echo <<<HTML
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$raw_rows = $this->em->fetch_rows($this->master_where, '', false, $show_removed); // Dvoupolové načtení záznamů s překlady v PHP
		$rows = $this->apply_active_filters_to_rows($raw_rows);              // Aplikace vícepoložkového filtru
		
		$page_param = urlencode($this->get_current_page_name());             // Kanonický název stránky do URL
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as $row) {                                        // Průchod jednotlivými řádky seznamu
				$uuid = (string) $row['original'];                           // Originální UUID řádku
				$safe_uuid = htmlspecialchars($uuid);                        // Ošetřené UUID pro atribut data-uuid
				$is_rem = (! empty($row['removed']) OR ! empty($row['l_removed'])); // Zda je zrušen hlavní záznam nebo překlad
				$is_act = (strcasecmp($uuid, $update_guid) === 0);           // Zda jde o právě vybraný řádek
				if ($is_act AND $is_rem) {                                   // Aktivní zrušený řádek
					$rowClass = 'md-row-active md-row-Active-removed';       // Kombinovaná třída aktivního zrušeného řádku
				} elseif ($is_act) {                                         // Aktivní platný řádek
					$rowClass = 'md-row-active';                             // Třída pro aktivní řádek
				} elseif ($is_rem) {                                         // Neaktivní zrušený řádek
					$rowClass = 'md-row-removed';                            // Třída pro zrušený řádek
				} else {
					$rowClass = '';                                          // Standardní platný řádek
				}
				$rowIdAttr = $is_act ? 'id="active-row"' : '';               // Atribut id pro aktivní řádek

				$rec_type = (string) ($row['record_type'] ?? 'A');           // Typ záznamu ('A' nebo 'D')
				$app_status = (string) ($row['approval_status'] ?? 'A');     // Stav schválení ('A', 'D', 'F', 'R')
				$ssc_badge = '';                                             // Vizuální štítek pro koncepty a zrušené v seznamu
				if ($is_rem) {                                               // Pokud je záznam označen jako zrušený
					$ssc_badge .= "<span class=\"ssc-badge ssc-badge-rem\">{$badge_txt_rem}</span>"; // Červený štítek Zrušeno
				}
				if ($rec_type === 'D') {                                     // Pokud je řádek neuzavřeným konceptem
					if ($app_status === 'F') {                               // Návrh postoupený ke schválení
						$ssc_badge .= "<span class=\"ssc-badge ssc-badge-f\">{$badge_txt_f}</span>"; // Modrý štítek
					} elseif ($app_status === 'R') {                         // Návrh vrácený schvalovatelem
						$ssc_badge .= "<span class=\"ssc-badge ssc-badge-r\">{$badge_txt_r}</span>"; // Červený štítek
					} else {
						$ssc_badge .= "<span class=\"ssc-badge ssc-badge-d\">{$badge_txt_d}</span>"; // Žlutý štítek konceptu
					}
				}

				$row_url = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$uuid}"); // Cílová URL řádku
				echo "\t\t\t\t\t\t<tr class=\"{$rowClass}\" {$rowIdAttr} data-uuid=\"{$safe_uuid}\" style=\"cursor: pointer;\" onclick=\"loadDetailPanel('{$row_url}', this);\">\n"; // Řádek s AJAX načtením detailu
				
				$first_col = true;                                           // Příznak prvního sloupce pro vložení štítku
				foreach ($list_columns as $col => $header) {                 // Výpis hodnot buněk aktuálního řádku
					$val = htmlspecialchars((string) ($row[$col] ?? ''));    // Hodnota buňky v seznamu
					$badge_out = $first_col ? $ssc_badge : '';               // Štítek připojíme k první buňce řádku
					$first_col = false;                                      // Další sloupce již štítek nedostanou
					echo "\t\t\t\t\t\t\t<td>{$val}{$badge_out}</td>\n";      // Vykreslení buňky tabulky
				}
				echo "\t\t\t\t\t\t</tr>\n";                                  // Uzavření řádku tabulky
			}
		}

		echo <<<HTML
				</tbody>
			</table>
		</div>
HTML;
	}

	/**
	 * Hook pro potomky: umožňuje přepsat hlavní titulek detailního panelu.
	 */
	protected function get_detail_header(): string {
		return htmlspecialchars($this->phrase('default_detail_heading', [], 'Detail záznamu')); // Výchozí lokalizovaný titulek detailu
	}

	/**
	 * Hook pro potomky: umožňuje vložit další akční tlačítka do hlavičky detailu.
	 */
	protected function render_detail_header_buttons(string $update_guid): string { // Výchozí prázdná metoda pro tlačítka
		return '';                                                           // Výchozí prázdný prostor pro tlačítka
	}

	/**
	 * Hook pro potomky: vloží libovolné HTML zprávy bezprostředně pod hlavičku (nad tabulky).
	 */
	protected function render_detail_top(): void {
		// Záměrně prázdné
	}

	/**
	 * Vykreslí informační nebo varovný pruh o stavu schvalovacího cyklu (SSC),
	 * pokud je aktuálně načtený záznam v režimu konceptu (`record_type = 'D'`).
	 */
	protected function render_ssc_status_banner(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$rec_type = (string) ($datarow['record_type'] ?? 'A');               // Typ záznamu ('A' nebo 'D')
		if ($rec_type !== 'D') {                                             // Pokud jde o běžný schválený záznam
			return;                                                          // Pruh nevykreslujeme
		}

		$app_status = (string) ($datarow['approval_status'] ?? 'D');         // Stav konceptu ('D', 'F', 'R')
		$app_note = trim((string) ($datarow['approval_note'] ?? ''));        // Poznámka schvalovatele

		if ($app_status === 'R') {                                           // Vrácený / odmítnutý návrh
			$msg_rej = htmlspecialchars($this->phrase('msg_ssc_status_rejected', [], 'Tento návrh byl vrácen / odmítnut schvalovatelem. Můžete jej upravit a znovu postoupit, nebo smazat.')); // Hláška vrácení
			$note_html = '';                                                 // Volitelný výpis důvodu vrácení
			if ($app_note !== '') {                                          // Pokud schvalovatel uvedl důvod
				$lbl_reason = htmlspecialchars($this->phrase('lbl_rejection_reason', [], 'Důvod vrácení:')); // Popisek důvodu
				$safe_note = nl2br(htmlspecialchars($app_note));             // Ošetřený text poznámky
				$note_html = "<div style=\"margin-top: 6px; font-weight: normal; color: #7f1d1d;\"><strong>{$lbl_reason}</strong> {$safe_note}</div>"; // HTML důvodu
			}
			echo "<div class=\"msg-err\" style=\"margin-bottom: 15px;\">{$msg_rej}{$note_html}</div>\n"; // Výpis červeného boxu
		} elseif ($app_status === 'F') {                                     // Návrh postoupený ke schválení
			$msg_fwd = htmlspecialchars($this->phrase('msg_ssc_status_forwarded', [], 'Tento záznam je postoupen ke schválení. Do doby schválení jej můžete dále upravit nebo stáhnout zpět do konceptu.')); // Hláška postoupení
			echo "<div class=\"msg-info\" style=\"margin-bottom: 15px;\">{$msg_fwd}</div>\n"; // Výpis modrého boxu
		} else {
			$msg_drf = htmlspecialchars($this->phrase('msg_ssc_status_draft', [], 'Pracujete s rozpracovaným konceptem, který je viditelný pouze pro vás.')); // Hláška konceptu
			echo "<div class=\"msg-info\" style=\"margin-bottom: 15px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e;\">{$msg_drf}</div>\n"; // Výpis žlutého boxu
		}
	}

	/**
	 * Generuje strukturu formuláře na pravé straně s využitím metadat ($form_groups).
	 */
	protected function render_detail(): void {
		if ($this->em === null) {                                            // Kontrola inicializace správce entit
			$msg_unconf = htmlspecialchars($this->phrase('msg_detail_not_configured', [], 'Detail panel není nakonfigurován.')); // Hláška
			echo "<div class='msg-info'>{$msg_unconf}</div>";                // Výpis zprávy
			return;                                                          // Ukončení vykreslování detailu
		}

		$update_guid = (string) getinput('update_guid');                     // Získání ID vybraného záznamu
		if ($update_guid === '') {                                           // Kontrola prázdného výběru
			$msg_sel = htmlspecialchars($this->phrase('msg_select_from_left', [], 'Vyberte záznam z levého panelu.')); // Výzva k výběru
			echo "<div class='msg-info'>{$msg_sel}</div>";                   // Výpis informační výzvy
			return;                                                          // Ukončení vykreslování detailu
		}

		if ($update_guid === 'NEW' AND ! $this->allow_insert) {              // Ochrana proti podvržení update_guid=NEW v URL
			$msg_no_ins = htmlspecialchars($this->phrase('msg_insert_not_allowed', [], 'Zakládání nových záznamů není v této úloze povoleno.')); // Chybová hláška
			echo "<div class='msg-err'>{$msg_no_ins}</div>";                 // Výpis chyby
			return;                                                          // Ukončení vykreslování detailu
		}

		global $datarow;                                                     // Globální pole pro aktuální řádek

		if ($update_guid === 'NEW') {                                        // Příprava výchozích hodnot pro nový záznam
			$datarow = [];                                                   // Inicializace prázdného záznamu
			foreach ($this->em->get_columns() as $colname => $meta) {        // Nastavení výchozích hodnot všech sloupců
				$type = $meta['input_type'] ?? 'text';                       // Typ vstupního prvku
				$datarow[$colname] = ($type === 'checkbox') ? '0' : '';      // Výchozí hodnota pole
			}
			$datarow['record_type'] = 'A';                                   // Výchozí stav před prvním uložením
			$datarow['approval_status'] = 'A';                               // Výchozí schválený stav
			$datarow['approval_note'] = '';                                  // Prázdná poznámka schvalování
			$datarow['object_is_mine'] = 1;                                  // Nový záznam patří vždy uživateli
			$is_mine = true;                                                 // Příznak vlastnictví záznamu
		} else {
			$where_detail = "m.original = " . guidliteral($update_guid);     // Podmínka pro vyhledání konkrétního záznamu
			$datarow = $this->em->fetch_row($where_detail, false, true);     // Načtení záznamu s překlady přes dvoupolové vyhodnocení
			
			if (empty($datarow)) {                                           // Kontrola existence načteného záznamu
				$msg_nf = htmlspecialchars($this->phrase('msg_record_not_found', [], 'Záznam nebyl nalezen.')); // Chybová hláška
				echo "<div class='msg-err'>{$msg_nf}</div>";                 // Výpis chyby
				return;                                                      // Ukončení při nenalezení záznamu
			}
			
			$is_mine = (bool) $datarow['object_is_mine'];                    // Zda záznam vlastní aktuální tenant
		}

		// Pokud došlo k validační chybě při ukládání (POST), zachováme ve formuláři zadané hodnoty z $_POST
		if ($this->save_error_message !== '' AND ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') { // Obnova hodnot po chybě
			foreach ($this->em->get_columns() as $colname => $meta) {        // Průchod sloupci logické třídy
				if (isset($_POST[$colname])) {                               // Pokud byla hodnota v POSTu odeslána
					$datarow[$colname] = (string) $_POST[$colname];          // Přepsání hodnoty v $datarow odeslaným vstupem
				}
			}
		}

		$page_param = urlencode($this->get_current_page_name());             // Kanonický název aktuální stránky
		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL s kontextem
		$hidden_inputs = $this->get_context_hidden_inputs();                 // Skrytá pole s kontextem
		$discard_url = "index.php?page={$page_param}{$url_suffix}";          // Cílová URL pro zahození změn
		$form_action = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$update_guid}"); // Cílová URL formuláře
		$safe_update_guid = htmlspecialchars($update_guid);                  // Ošetřené UUID pro hidden input
		
		$header_html = $this->get_detail_header();                           // Nadpis detailního panelu
		$extra_buttons = $this->render_detail_header_buttons($update_guid);  // Doplňková tlačítka potomka

		$buttons_html = $extra_buttons;                                      // Výchozí sada tlačítek hlavičky
		if (! $this->is_readonly) {                                          // Pokud je povolená běžná editace záznamu
			$btn_parts = [];                                                 // Pole tlačítek v hlavičce detailu

			$btn_discard = new abstract_button('btn_discard', 'Zahodit změny', 'abstract_button', '', 'btn-danger'); // Tlačítko zahození změn
			$btn_discard->set_href($discard_url)->set_onclick('isFormDirty = false;'); // Přechod bez varování dirty stavu
			$btn_parts[] = $btn_discard->render();                           // Přidání tlačítka Zahodit změny

			if ($extra_buttons !== '') {                                     // Pokud potomek definoval vlastní tlačítka
				$btn_parts[] = $extra_buttons;                               // Zařazení doplňkových tlačítek potomka
			}

			$is_draft_row = ($update_guid !== 'NEW' AND ((string) ($datarow['record_type'] ?? 'A') === 'D')); // Zda jde o uložený koncept
			if ($is_draft_row) {                                             // Pokud má uživatel uložený koncept
				$confirm_del = $this->phrase('confirm_delete_draft', [], 'Opravdu chcete tento koncept bez náhrady odstranit?'); // Dotaz před smazáním
				$btn_del_draft = new abstract_button('btn_delete_draft', 'Smazat koncept', 'abstract_button', '', 'btn-danger'); // Tlačítko smazání konceptu
				$btn_del_draft->set_type('submit')                           // Nastavení typu submit
					->set_name_value('btn_delete_draft', '1')                // Jméno a hodnota pro process_save()
					->set_onclick('isFormDirty = false;')                    // Vypnutí varování před opuštěním
					->set_confirm($confirm_del);                             // Potvrzovací dialog
				$btn_parts[] = $btn_del_draft->render();                     // Přidání tlačítka Smazat koncept
			}

			$btn_draft = new abstract_button('btn_save_draft', 'Uložit koncept', 'abstract_button', '', 'btn-secondary'); // Tlačítko konceptu
			$btn_draft->set_type('submit')->set_name_value('btn_save_draft', '1'); // Submit pro stav 'D'
			$btn_parts[] = $btn_draft->render();                             // Přidání tlačítka Uložit koncept

			$btn_forward = new abstract_button('btn_forward_approval', 'Předat ke schválení', 'abstract_button'); // Tlačítko postoupení
			$btn_forward->set_type('submit')->set_name_value('btn_forward_approval', '1'); // Submit pro stav 'F'
			$btn_parts[] = $btn_forward->render();                           // Přidání tlačítka Předat ke schválení

			$btn_save = new abstract_button('btn_save', 'Uložit změny', 'abstract_button', '', 'btn-success'); // Tlačítko přímého uložení
			$btn_save->set_type('submit')->set_name_value('btn_save', '1');  // Nastavení submit atributů pro stav 'A'
			$btn_parts[] = $btn_save->render();                              // Přidání tlačítka Uložit změny

			$buttons_html = implode("\n\t\t\t\t\t", $btn_parts);             // Spojení všech tlačítek hlavičky
		}

		echo <<<HTML
		<form method="post" action="{$form_action}" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="update_guid" value="{$safe_update_guid}">{$hidden_inputs}
			
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$header_html}</h2>
				<div style="display: flex; gap: 8px; align-items: center; flex-wrap: wrap;">
					{$buttons_html}
				</div>
			</div>
			
			<div class="md-detail-content">
HTML;

		if ($this->save_error_message !== '') {                              // Výpis validační chyby při neúspěšném uložení
			$safe_save_err = htmlspecialchars($this->save_error_message);    // Ošetřený text validační chyby
			echo "\t\t\t\t<div class=\"msg-err\" style=\"margin-bottom: 15px;\">{$safe_save_err}</div>\n"; // Červený chybový box
			echo "\t\t\t\t<script>setTimeout(function() { isFormDirty = true; }, 20);</script>\n"; // Ponechání dirty stavu formuláře
		}

		if ($update_guid !== 'NEW') {                                        // Pouze u existujícího záznamu v DB
			$this->render_ssc_status_banner();                               // Zobrazení pruhu stavu konceptu
		}

		$this->render_detail_top();                                          // Vykreslení horní části detailu

		$groups = $this->form_groups;                                        // Skupiny polí definované v potomkovi
		if (empty($groups)) {                                                // Záložní seskupení všech neskrytých sloupců
			$all_cols = [];                                                  // Seznam všech viditelných sloupců
			foreach ($this->em->get_columns() as $colname => $meta) {        // Průchod všemi sloupci logické třídy
				if (empty($meta['hidden'])) {                                // Zařazení pouze viditelných sloupců
					$all_cols[] = $colname;                                  // Zařazení neskrytého sloupce
				}
			}
			$groups = ['' => $all_cols];                                     // Jedna bezejmenná skupina
		}

		$lbl_req_title = htmlspecialchars($this->phrase('lbl_mandatory_field', [], 'Povinné pole')); // Tooltip povinného pole
		$lbl_tr_title  = htmlspecialchars($this->phrase('lbl_translatable_tooltip', [], 'Tato hodnota může být přeložena do jiných jazyků')); // Tooltip překladu
		$lbl_tr_badge  = htmlspecialchars($this->phrase('lbl_supports_translation', [], '(Podporuje překlad)')); // Štítek podpory překladu

		$removed_rendered = false;                                           // Evidence, zda již byl sloupec removed vykreslen ve skupině

		foreach ($groups as $group_title => $columns) {                      // Vykreslení jednotlivých skupin formuláře
			if ($group_title !== '') {                                       // Vykreslení nadpisu neprázdné skupiny
				echo "\t\t\t\t<h3 style=\"margin-top: 20px; color: #004488; font-size: 15px;\">" . htmlspecialchars($group_title) . "</h3>\n"; // Nadpis skupiny
			}
			
			echo "\t\t\t\t<table class=\"md-table\" style=\"margin-bottom: 30px;\">\n"; // Začátek tabulky skupiny
			
			foreach ($columns as $colname) {                                 // Zpracování jednotlivých polí ve skupině
				if ($colname === 'removed') {                                // Pokud potomek explicitně zařadil removed
					$removed_rendered = true;                                // Označíme, že removed je ve skupině
				}
				$meta = $this->em->get_column_meta($colname);                // Načtení metadat sloupce
				
				if (empty($meta)) {                                          // Přeskočení neznámého sloupce v metadatech
					continue;                                                // Pokračování na další sloupec
				}
				if (! empty($meta['hidden']) AND $colname !== 'removed') {   // Přeskočení skrytého sloupce ve formuláři
					continue;                                                // Pokračování na další sloupec
				}
				
				$label = htmlspecialchars((string) ($meta['label'] ?: $meta['caption'] ?: $colname)); // Popisek pole
				$helptext = (string) ($meta['helptext'] ?? '');              // Text nápovědy k poli
				$title_attr = $helptext !== '' ? " title=\"" . htmlspecialchars($helptext) . "\"" : ""; // Tooltip buňky
				
				$is_mand = (! empty($meta['is_mandatory']) OR $this->em->is_key_column_mandatory($colname)); // Povinné pole nebo klíč
				$req_html = $is_mand ? "<span style=\"color: #b91c1c; margin-left: 3px;\" title=\"{$lbl_req_title}\">*</span>" : ''; // Hvězdička povinnosti
				$trans_html = ! empty($meta['translate']) ? "<br><small style=\"color: #2563eb; font-size: 10px;\" title=\"{$lbl_tr_title}\">{$lbl_tr_badge}</small>" : ''; // Štítek překladu
				
				$input_html = $this->em->render_dynamic_input($colname, (string) ($datarow[$colname] ?? ''), $is_mine, $this->is_readonly); // HTML vstupního prvku
				
				echo <<<HTML
					<tr>
						<td style="width: 30%;"{$title_attr}><strong>{$label}{$req_html}:</strong>{$trans_html}</td>
						<td>{$input_html}</td>
					</tr>

HTML;
			}
			echo "\t\t\t\t</table>\n";
		}

		if ($update_guid !== 'NEW' AND ! $removed_rendered AND $this->em->has_physical_column('removed')) { // Kontrola podpory sloupce removed
			echo $this->em->render_removed_section($datarow, $is_mine, $this->is_readonly); // Vykreslení sekce removed
		}

		$this->render_audit_trail();                                         // Vykreslení informací o změnách

		echo "\t\t\t</div>\n\t\t</form>\n";
	}

	/**
	 * Připojí pod formulář standardizovanou patku o vytvoření a úpravě dat (who/when).
	 */
	protected function render_audit_trail(): void {
		global $datarow;                                                     // Načtený datový řádek
		
		if (empty($datarow) OR (empty($datarow['date_created']) AND empty($datarow['date_modified']))) { // Kontrola dostupnosti auditních údajů
			return;                                                          // Ukončení při chybějících datech auditu
		}

		$html = '';                                                          // Výstupní HTML auditní stopy
		$unknown_user = $this->phrase('audit_unknown_user', [], 'Neznámý uživatel'); // Lokalizovaný fallback jména
		$lbl_created  = htmlspecialchars($this->phrase('audit_created_by', [], 'Vytvořil')); // Lokalizované návěstí vytvoření
		$lbl_modified = htmlspecialchars($this->phrase('audit_modified_by', [], 'Změnil')); // Lokalizované návěstí úpravy
		
		if (! empty($datarow['date_created'])) {                             // Výpis informace o vytvoření záznamu
			$date_c = date_format4($datarow['date_created'], 16);            // Zformátované datum vytvoření
			$who_c_name = ! empty($datarow['who_created_info']) ? $datarow['who_created_info'] : $unknown_user; // Autor vytvoření
			$html .= "<div>{$lbl_created} {$date_c} " . htmlspecialchars((string) $who_c_name) . "</div>"; // Řádek vytvoření
		}

		if (! empty($datarow['date_modified'])) {                            // Výpis informace o poslední úpravě záznamu
			$date_m = date_format4($datarow['date_modified'], 16);           // Zformátované datum úpravy
			$who_m_name = ! empty($datarow['who_modified_info']) ? $datarow['who_modified_info'] : $unknown_user; // Autor úpravy
			$html .= "<div>{$lbl_modified} &nbsp;&nbsp;{$date_m} " . htmlspecialchars((string) $who_m_name) . "</div>"; // Řádek úpravy
		}

		if ($html !== '') {                                                  // Vykreslení neprázdného bloku auditní stopy
			echo "<div style=\"margin-top: 30px; font-size: 11px; color: #94a3b8; line-height: 1.6; font-family: monospace;\">{$html}</div>"; // Výpis auditu
		}
	}
}