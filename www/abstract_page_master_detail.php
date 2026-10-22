<?php
/**
 * =============================================================================
 * Verze: 2026-10-22 17:45
 * Soubor: abstract_page_master_detail.php
 * Třída: abstract_page_master_detail
 * Účel: Abstraktní třída rozšiřující základní stránku o dvoupanelový layout.
 *       Slouží jako pevný základ pro veškeré administrační obrazovky BCM systému.
 *
 * EXTERNÍ ZÁVISLOSTI PRO AI KONTEXT (Pokud chybí referenční soubory):
 * - Třída dědí z `abstract_page`, která definuje základní HTML kostru, globální
 *   CSS styly a instancuje horní pruh (`user_context`).
 * - Zpracování POST dat a PRG vzor (Post-Redirect-Get) volá globální funkci 
 *   `autoredirect()` z `OsirisLib.php`.
 * - Bezpečné načítání parametrů z URL zajišťuje funkce `getinput()`.
 * - Databázové dotazy a překlady podle `fallback_order` jsou delegovány na instanci
 *   `entity_manager` (`fetch_records()`), kterou tato třída inicializuje v metodě `render()`.
 * - Vykreslování akčních tlačítek využívá komponentu `abstract_button`
 *   a lokalizaci textů zajišťuje `$this->phrase()` přes `phrase_manager`.
 *
 * KLÍČOVÉ KONCEPTY A ARCHITEKTURA (PRO BUDOUCÍ VÝVOJ):
 *
 * 1. Plně datově řízená architektura (STI - Single Table Inheritance):
 *    - Potomek pouze definuje chráněnou proměnnou `$this->class_name`.
 *    - Pomocí objektu `entity_manager` je z databáze automaticky zjištěno, 
 *      jaké sloupce se mají zobrazit, jak se validují a jak se ukládají.
 *
 * 2. PRG Vzor (Post-Redirect-Get):
 *    - Každé odeslání formuláře (`POST` s tlačítkem `btn_save`) je zachyceno
 *      v `abstract_page::render()` a předáno do `process_save()`.
 *    - Metoda `process_save()` zavolá autonomní RAC zápis a NÁSLEDNĚ provede
 *      striktní přesměrování, čímž zabrání dvojitému uložení při stisku F5.
 *
 * 3. Moderní Flexbox CSS (Bez závislosti na vnějších frameworcích):
 *    - Layout používá `flex-direction: column` pro interní panely (`md-master`
 *      a `md-detail`), což umožňuje fixní hlavičky a rolovatelný obsah.
 *    - Tabulky v obou panelech drží záhlaví vizuálně připnutá přes `position: sticky`.
 *
 * 4. Automatizované skupiny ve formuláři ($form_groups), Readonly ($is_readonly) a vkládání ($allow_insert):
 *    - Potomek může v konstruktoru definovat pole `$this->form_groups`,
 *      čímž se formulář dynamicky rozdělí do vizuálních sekcí s vlastními nadpisy.
 *    - Vlastnost `$this->is_readonly` umožňuje přepnout celý detailní panel do režimu
 *      pouze pro čtení (příprava na budoucí vyčlenění `abstract_detail_panel`).
 *    - Vlastnost `$this->allow_insert` určuje, zda je na stránce povoleno zakládání
 *      nových záznamů (`update_guid=NEW`).
 *
 * 5. Hook metody pro customizaci (Rozšiřitelnost bez přepisování jádra):
 *    - `render_master_top()`: Pro vložení tlačítek a HTML nad vyhledávací pole vlevo.
 *    - `get_detail_header()`: Pro dynamickou změnu velkého nadpisu vpravo.
 *    - `render_detail_header_buttons()`: Pro vložení doplňkových tlačítek do hlavičky detailu.
 *    - `render_detail_top()`: Pro vložení upozornění/notifikací nad editační formulář.
 *
 * Změny:
 * 2026-10-22 17:45 - Napojení render_master() a render_detail() na metodu
 *                    $this->em->fetch_records() vyhodnocující jazykové verze v PHP.
 *                  - Přidána vlastnost $allow_insert pro zákaz vkládání nových
 *                    záznamů (update_guid=NEW) u vybraných tříd (např. page_organization).
 *                  - Opraveny všechny chybějící mezery před znakem $.
 * 2026-10-21 15:05 - Klientské filtrování #master-filter přesunuto do centrálního
 *                    delegovaného listeneru v render_body() (funguje pro všechny potomky
 *                    i po AJAX obnově levého panelu bez duplikace <script> bloku).
 * 2026-10-20 13:10 - Doplněn přepínač "Zobrazit i zrušené" (show_removed) do hlavičky
 *                    levého Master panelu s vizuálním odlišením zrušených záznamů.
 *                  - V detailním panelu doplněno automatické vykreslení checkboxu
 *                    removed (s JS potvrzením a kontrolou oprávnění v entity_manager)
 *                    pro zrušení nebo obnovení záznamu či jazykové mutace.
 * 2026-10-18 18:15 - Převedení čtení dat v render_master() na sqlarray_simple()
 *                    a v render_detail() na sqlfirstrow(), aby vnořené dotazy
 *                    nikdy neuvolnily globální $dbquery v OsirisLib.php.
 * 2026-10-17 01:05 - Integrace schvalovacího cyklu (SSC): podpora tlačítek pro uložení
 *                    konceptu ('D'), postoupení ke schválení ('F'), přímé uložení ('A')
 *                    a smazání konceptu bez zápisu do historie.
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page_master_detail extends abstract_page {

	// --- Konfigurace pro data-driven vrstvu (nastavují potomci v konstruktoru) ---
	
	/** Identifikátor logické třídy z DB (např. 'meta_object', 'asset_class') */
	protected string $class_name = '';                                       // Název logické třídy
	
	/** Volitelné omezení SQL dotazu pro načítání master panelu (např. "m.parent_object = ...") */
	protected string $master_where = '';                                     // Podmínka WHERE pro levý panel
	
	/** Mapování logických skupin vstupních polí. Očekává: ['Název sekce' => ['sloupec1', 'sloupec2']] */
	protected array $form_groups = [];                                       // Skupiny polí ve formuláři

	/** Příznak režimu pouze pro čtení v detailním panelu */
	protected bool $is_readonly = false;                                     // Uzamčení celého detailního panelu

	/** Příznak povolení zakládání nových záznamů (update_guid=NEW) */
	protected bool $allow_insert = true;                                     // Povolení vkládání nových záznamů
	
	/** Instance dynamického správce objektů řídící čtení a zápis */
	protected ?entity_manager $em = null;                                    // Instance správce entit

	/**
	 * Vrátí kanonický název aktuální stránky (např. 'page_meta_class').
	 */
	protected function get_current_page_name(): string {
		$page = trim((string)getinput('page'));                              // Načtení parametru page z požadavku
		if ($page === '') {                                                  // Kontrola prázdného názvu stránky
			return get_class($this);                                         // Fallback na název třídy stránky
		}
		$page = basename($page, '.php');                                     // Očištění názvu stránky
		if (!str_starts_with($page, 'page_')) {                              // Kontrola přítomnosti předpony page_
			$page = 'page_' . $page;                                         // Sjednocení na předponu page_
		}
		return $page;                                                        // Vrácení plného názvu stránky
	}

	/**
	 * Centralizované získání URL parametrů pro udržení kontextu (např. vazba na předka).
	 * Zabraňuje duplicitě kódu při generování odkazů a přesměrování.
	 * 
	 * @return string Řetězec parametrů pro URL (např. '&parent_class=123')
	 */
	protected function get_context_url_suffix(): string {
		$url_suffix = '';                                                    // Výchozí prázdný přívažek URL
		foreach (['parent_object', 'parent_class', 'menu_code', 'show_removed'] as $ctx_param) { // Průchod kontextovými parametry
			$val = (string)getinput($ctx_param);                             // Hodnota kontextového parametru
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
		foreach (['parent_object', 'parent_class', 'menu_code', 'show_removed'] as $ctx_param) { // Průchod kontextovými parametry
			$val = (string)getinput($ctx_param);                             // Hodnota kontextového parametru
			if ($val !== '') {                                               // Vytvoření skrytého pole pro parametr
				$hidden_inputs .= "\n\t\t\t<input type=\"hidden\" name=\"{$ctx_param}\" value=\"" . htmlspecialchars($val) . "\">"; // Skryté pole
			}
		}
		return $hidden_inputs;                                               // Vrácení skrytých polí formuláře
	}

	/**
	 * Hlavní bod vstupu životního cyklu stránky.
	 * Ošetřuje inicializaci entity_manageru a AJAX požadavky před vykreslením těla.
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

		if (isset($_GET['ajax_panel']) AND $_GET['ajax_panel'] === 'master') { // Detekce AJAX požadavku pro levý panel
			$this->render_master();                                          // Vykreslení pouze levého panelu
			exit;                                                            // Okamžité ukončení skriptu
		}
		
		parent::render();                                                    // Spuštění vykreslení v předkovi
	}

	/**
	 * Zajišťuje zpracování POST dat z formuláře (včetně SSC stavů a mazání konceptu) a následný redirect.
	 */
	protected function process_save(): void {
		if ($this->is_readonly OR $this->em === null) {                      // Kontrola readonly režimu a správce entit
			return;                                                          // V readonly režimu nebo bez správce neukládáme
		}

		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor upravovaného záznamu
		if ($update_guid === '') {                                           // Kontrola prázdného identifikátoru
			return;                                                          // Bez vybraného záznamu ani NEW neukládáme
		}

		if ($update_guid === 'NEW' AND !$this->allow_insert) {               // Ochrana proti zakázanému vkládání nových záznamů
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
		$was_marked_removed = (isset($_POST['removed']) AND (string)$_POST['removed'] === '1'); // Zda uživatel zaškrtl zrušení
		
		$saved_orig = $this->em->save_post_data($save_guid, $target_status); // Autonomní uložení dat s cílovým stavem SSC
		
		$show_rem_active = ((string)getinput('show_removed') === '1');       // Zda je zapnuto zobrazování zrušených záznamů
		if ($was_marked_removed AND !$show_rem_active AND $target_status === 'A') { // Pokud byl záznam zrušen a zrušené se nezobrazují
			autoredirect("index.php?page={$page_param}{$url_suffix}");       // Přesměrování na čistý seznam bez detailu
		} elseif ($saved_orig !== '' AND $saved_orig !== 'NEW') {            // Pokud máme platný originál uloženého záznamu
			autoredirect("index.php?page={$page_param}{$url_suffix}&update_guid=" . urlencode($saved_orig)); // Přesměrování na uložený záznam
		} else {
			autoredirect("index.php?page={$page_param}{$url_suffix}");       // Fallback na výchozí seznam
		}
	}

	/**
	 * Implementace abstraktní metody rodiče. 
	 * Obsahuje CSS, základní dvoupanelový HTML skelet a centrální JS obsluhu levého panelu.
	 */
	final protected function render_body(): void {
		$err_ajax_net = addslashes($this->phrase('err_ajax_network', [], 'Chyba sítě při AJAX volání')); // JS chybová hláška sítě
		$err_ajax_ref = addslashes($this->phrase('err_ajax_refresh', [], 'Chyba při obnově master panelu:')); // JS chybová hláška obnovy

		echo <<<HTML
		<style>
			.page-panel { max-width: 95% !important; padding: 0 !important; display: flex; flex-direction: row; height: calc(100vh - 120px); overflow: hidden; }
			.md-master { flex: 0 0 45%; min-width: 400px; border-right: 1px solid #ddd; background-color: #fafafa; padding: 20px; display: flex; flex-direction: column; overflow: hidden; }
			.md-detail { flex: 1; padding: 20px 30px; background-color: #ffffff; display: flex; flex-direction: column; overflow: hidden; }
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
		<div class="md-detail">
HTML;
		$this->render_detail();                                              // Vykreslení pravého panelu

		echo <<<HTML
		</div>
		
		<script>
			// Javascript: Pokud je levý panel dlouhý, automaticky odscrolluje na právě vybraný aktivní řádek.
			function scrollToActiveRow() {
				const activeRow = document.getElementById("active-row");
				const scrollingContainer = document.querySelector(".md-master-content");
				
				if (activeRow && scrollingContainer) {
					const containerRect = scrollingContainer.getBoundingClientRect();
					const rowRect = activeRow.getBoundingClientRect();
					const offset = rowRect.top - containerRect.top;
					scrollingContainer.scrollTop += offset - (containerRect.height / 2) + (rowRect.height / 2);
				}
			}

			// Javascript: Přepnutí zobrazení zrušených záznamů (show_removed) v URL
			function toggleShowRemoved(checked) {
				const url = new URL(window.location.href);
				if (checked) {
					url.searchParams.set('show_removed', '1');
				} else {
					url.searchParams.delete('show_removed');
				}
				window.location.href = url.toString();
			}

			// Javascript: Centrální klientské filtrování tabulky #master-list přes #master-filter
			document.addEventListener('input', function(e) {
				if (e.target && e.target.id === 'master-filter') {
					const term = e.target.value.toLowerCase();
					const list = document.getElementById('master-list');
					if (list) {
						list.querySelectorAll('tr').forEach(row => {
							row.style.display = row.textContent.toLowerCase().includes(term) ? '' : 'none';
						});
					}
				}
			});

			// Javascript: Voláno pro asynchronní překreslení (refresh) levého panelu.
			function refreshMasterPanel() {
				const url = new URL(window.location.href);
				url.searchParams.set('ajax_panel', 'master');
				
				fetch(url.toString(), {
					headers: {
						'X-Requested-With': 'XMLHttpRequest'
					}
				})
				.then(response => {
					if (!response.ok) throw new Error("{$err_ajax_net}");
					return response.text();
				})
				.then(html => {
					const masterPanel = document.getElementById("md-master-container");
					if (masterPanel) {
						masterPanel.innerHTML = html;
						scrollToActiveRow();
					}
				})
				.catch(error => {
					console.error('{$err_ajax_ref}', error);
				});
			}

			document.addEventListener("DOMContentLoaded", function() {
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

		$update_guid = (string)getinput('update_guid');                      // Aktuálně vybraný záznam
		$show_removed = ((string)getinput('show_removed') === '1');          // Příznak zobrazení zrušených záznamů
		
		$class_meta = $this->em->get_class_meta();                           // Metadata aktuální třídy
		$caption_plural = (string)($class_meta['caption_plural'] ?? '');     // Množné číslo názvu třídy
		
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
			<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="width: 100%; padding: 6px; box-sizing: border-box;">
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

		$rows = method_exists($this->em, 'fetch_records')
			? $this->em->fetch_records($this->master_where, '', false, $show_removed)
			: sqlarray_simple($this->em->build_select_query($this->master_where, '', false, $show_removed)); // Načtení záznamů s překlady
		
		$page_param = urlencode($this->get_current_page_name());             // Kanonický název stránky do URL
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as $row) {                                        // Průchod jednotlivými řádky seznamu
				$uuid = (string)$row['original'];                            // Originální UUID řádku
				$is_rem = (!empty($row['removed']) OR !empty($row['l_removed'])); // Zda je zrušen hlavní záznam nebo překlad
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

				$rec_type = (string)($row['record_type'] ?? 'A');            // Typ záznamu ('A' nebo 'D')
				$app_status = (string)($row['approval_status'] ?? 'A');      // Stav schválení ('A', 'D', 'F', 'R')
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
				echo "\t\t\t\t\t\t<tr class=\"{$rowClass}\" {$rowIdAttr} style=\"cursor: pointer;\" onclick=\"document.location='{$row_url}'\">\n"; // Otevření řádku
				
				$first_col = true;                                           // Příznak prvního sloupce pro vložení štítku
				foreach ($list_columns as $col => $header) {                 // Výpis hodnot buněk aktuálního řádku
					$val = htmlspecialchars((string)($row[$col] ?? ''));     // Hodnota buňky v seznamu
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
		$rec_type = (string)($datarow['record_type'] ?? 'A');                // Typ záznamu ('A' nebo 'D')
		if ($rec_type !== 'D') {                                             // Pokud jde o běžný schválený záznam
			return;                                                          // Pruh nevykreslujeme
		}

		$app_status = (string)($datarow['approval_status'] ?? 'D');          // Stav konceptu ('D', 'F', 'R')
		$app_note = trim((string)($datarow['approval_note'] ?? ''));         // Poznámka schvalovatele

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

		$update_guid = (string)getinput('update_guid');                      // Získání ID vybraného záznamu
		if ($update_guid === '') {                                           // Kontrola prázdného výběru
			$msg_sel = htmlspecialchars($this->phrase('msg_select_from_left', [], 'Vyberte záznam z levého panelu.')); // Výzva k výběru
			echo "<div class='msg-info'>{$msg_sel}</div>";                   // Výpis informační výzvy
			return;                                                          // Ukončení vykreslování detailu
		}

		if ($update_guid === 'NEW' AND !$this->allow_insert) {               // Ochrana proti podvržení update_guid=NEW v URL
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
			if (method_exists($this->em, 'fetch_records')) {                 // Použití dvoupolového vyhodnocení v PHP
				$det_rows = $this->em->fetch_records($where_detail, '', false, true); // Načtení záznamu s překlady
				$datarow = !empty($det_rows) ? reset($det_rows) : [];        // První nalezený záznam
			} else {
				$sql = $this->em->build_select_query($where_detail, '', false, true); // Fallback na SQL dotaz
				$datarow = sqlfirstrow($sql);                                // Načtení řádku detailu
			}
			
			if (empty($datarow)) {                                           // Kontrola existence načteného záznamu
				$msg_nf = htmlspecialchars($this->phrase('msg_record_not_found', [], 'Záznam nebyl nalezen.')); // Chybová hláška
				echo "<div class='msg-err'>{$msg_nf}</div>";                 // Výpis chyby
				return;                                                      // Ukončení při nenalezení záznamu
			}
			
			$is_mine = (bool)$datarow['object_is_mine'];                     // Zda záznam vlastní aktuální tenant
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
		if (!$this->is_readonly) {                                           // Pokud je povolená běžná editace záznamu
			$btn_parts = [];                                                 // Pole tlačítek v hlavičce detailu

			$btn_discard = new abstract_button('btn_discard', 'Zahodit změny', 'abstract_button', '', 'btn-danger'); // Tlačítko zahození změn
			$btn_discard->set_href($discard_url)->set_onclick('isFormDirty = false;'); // Přechod bez varování dirty stavu
			$btn_parts[] = $btn_discard->render();                           // Přidání tlačítka Zahodit změny

			if ($extra_buttons !== '') {                                     // Pokud potomek definoval vlastní tlačítka
				$btn_parts[] = $extra_buttons;                               // Zařazení doplňkových tlačítek potomka
			}

			$is_draft_row = ($update_guid !== 'NEW' AND ((string)($datarow['record_type'] ?? 'A') === 'D')); // Zda jde o uložený koncept
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
				if (!empty($meta['hidden']) AND $colname !== 'removed') {    // Přeskočení skrytého sloupce ve formuláři
					continue;                                                // Pokračování na další sloupec
				}
				
				$label = htmlspecialchars((string)($meta['label'] ?: $meta['caption'] ?: $colname)); // Popisek pole
				$helptext = (string)($meta['helptext'] ?? '');               // Text nápovědy k poli
				$title_attr = $helptext !== '' ? " title=\"" . htmlspecialchars($helptext) . "\"" : ""; // Tooltip buňky
				
				$req_html = !empty($meta['is_mandatory']) ? "<span style=\"color: #b91c1c; margin-left: 3px;\" title=\"{$lbl_req_title}\">*</span>" : ''; // Hvězdička povinnosti
				$trans_html = !empty($meta['translate']) ? "<br><small style=\"color: #2563eb; font-size: 10px;\" title=\"{$lbl_tr_title}\">{$lbl_tr_badge}</small>" : ''; // Štítek překladu
				
				$input_html = $this->em->render_dynamic_input($colname, (string)($datarow[$colname] ?? ''), $is_mine, $this->is_readonly); // HTML vstupního prvku
				
				echo <<<HTML
					<tr>
						<td style="width: 30%;"{$title_attr}><strong>{$label}{$req_html}:</strong>{$trans_html}</td>
						<td>{$input_html}</td>
					</tr>

HTML;
			}
			echo "\t\t\t\t</table>\n";
		}

		if ($update_guid !== 'NEW' AND !$removed_rendered AND $this->em->has_physical_column('removed')) { // Kontrola podpory sloupce removed
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
		
		if (!empty($datarow['date_created'])) {                              // Výpis informace o vytvoření záznamu
			$date_c = date_format4($datarow['date_created'], 16);            // Zformátované datum vytvoření
			$who_c_name = !empty($datarow['who_created_info']) ? $datarow['who_created_info'] : $unknown_user; // Autor vytvoření
			$html .= "<div>{$lbl_created} {$date_c} " . htmlspecialchars((string)$who_c_name) . "</div>"; // Řádek vytvoření
		}

		if (!empty($datarow['date_modified'])) {                             // Výpis informace o poslední úpravě záznamu
			$date_m = date_format4($datarow['date_modified'], 16);           // Zformátované datum úpravy
			$who_m_name = !empty($datarow['who_modified_info']) ? $datarow['who_modified_info'] : $unknown_user; // Autor úpravy
			$html .= "<div>{$lbl_modified} &nbsp;&nbsp;{$date_m} " . htmlspecialchars((string)$who_m_name) . "</div>"; // Řádek úpravy
		}

		if ($html !== '') {                                                  // Vykreslení neprázdného bloku auditní stopy
			echo "<div style=\"margin-top: 30px; font-size: 11px; color: #94a3b8; line-height: 1.6; font-family: monospace;\">{$html}</div>"; // Výpis auditu
		}
	}
}