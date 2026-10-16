<?php
/**
 * =============================================================================
 * Verze: 2026-10-16 10:15
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
 * - Databázové dotazy se odesílají pomocí `sqlrun()` a `fetch()`.
 * - Generování UI prvků, SQL dotazů a zápis je plně delegován na instanci
 *   `entity_manager`, kterou tato třída inicializuje v metodě `render()`.
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
 * 4. Automatizované skupiny ve formuláři ($form_groups) a Readonly režim ($is_readonly):
 *    - Potomek může v konstruktoru definovat pole `$this->form_groups`,
 *      čímž se formulář dynamicky rozdělí do vizuálních sekcí s vlastními nadpisy.
 *    - Vlastnost `$this->is_readonly` umožňuje přepnout celý detailní panel do režimu
 *      pouze pro čtení (příprava na budoucí vyčlenění `abstract_detail_panel`).
 *
 * 5. Hook metody pro customizaci (Rozšiřitelnost bez přepisování jádra):
 *    - `render_master_top()`: Pro vložení tlačítek a HTML nad vyhledávací pole vlevo.
 *    - `get_detail_header()`: Pro dynamickou změnu velkého nadpisu vpravo.
 *    - `render_detail_header_buttons()`: Pro vložení doplňkových tlačítek do hlavičky detailu.
 *    - `render_detail_top()`: Pro vložení upozornění/notifikací nad editační formulář.
 *
 * Změny:
 * 2026-10-16 10:15 - Nahrazení symbolických operátorů || a && slovními OR a AND (Anti-LaTeX).
 * 2026-10-16 09:45 - Oprava chyby spojeného řádku u inicializace $btn_discard v render_detail()
 *                    doplněním diakritiky do inline komentářů (Anti-LaTeX ochrana).
 *                  - Předání příznaku $this->is_readonly do metody render_dynamic_input().
 * 2026-10-16 07:45 - Zapojení abstract_button pro tlačítka Uložit a Zahodit změny.
 *                  - Kompletní lokalizace všech textů, hlášek a auditní stopy přes $this->phrase().
 *                  - Přidána vlastnost $is_readonly pro podporu readonly detailního panelu.
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
		foreach (['parent_object', 'parent_class', 'menu_code'] as $ctx_param) { // Průchod kontextovými parametry
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
		foreach (['parent_object', 'parent_class', 'menu_code'] as $ctx_param) { // Průchod kontextovými parametry
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

		// Pokud byl přístup odepřen, přeskočíme veškeré zpracování formulářů
		// a asynchronních požadavků a rovnou vykreslíme chybu přes rodiče.
		if ($this->access_denied) {                                          // Kontrola zamítnutého přístupu
			parent::render();                                                // Vykreslení chybové stránky předkem
			return;                                                          // Ukončení zpracování
		}

		// Inicializace správce entit PŘED voláním parent::render(), aby byl připraven pro process_save()
		if ($this->class_name !== '' AND $this->em === null) {               // Kontrola potřeby inicializace správce
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance entity_manageru
		}

		// Záchyt pro asynchronní obnovu pouze levého panelu
		if (isset($_GET['ajax_panel']) AND $_GET['ajax_panel'] === 'master') { // Detekce AJAX požadavku pro levý panel
			$this->render_master();                                          // Vykreslení pouze levého panelu
			exit;                                                            // Okamžité ukončení skriptu
		}
		
		// Vykreslení obálky z `abstract_page`, která při POST zavolá `process_save()` a následně `render_body()`
		parent::render();                                                    // Spuštění vykreslení v předkovi
	}

	/**
	 * Zajišťuje zpracování POST dat z formuláře a následný redirect.
	 */
	protected function process_save(): void {
		if ($this->is_readonly OR $this->em === null OR !isset($_POST['btn_save'])) { // Kontrola podmínek uložení
			return;                                                          // V readonly režimu nebo bez btn_save neukládáme
		}

		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor upravovaného záznamu
		if ($update_guid === '') {                                           // Kontrola prázdného identifikátoru
			return;                                                          // Bez vybraného záznamu ani NEW neukládáme
		}

		$save_guid = ($update_guid === 'NEW') ? '' : $update_guid;           // Pro nový záznam předáme prázdný řetězec
		
		$this->em->save_post_data($save_guid);                               // Autonomní uložení dat přes entity_manager
		
		$page_param = urlencode($this->get_current_page_name());             // Kanonický název aktuální stránky
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		// Zamezení uvíznutí na prázdném formuláři po uložení nového záznamu
		if ($update_guid === 'NEW') {                                        // Přesměrování po založení nového záznamu
			autoredirect("index.php?page={$page_param}{$url_suffix}");       // Přesměrování na výchozí seznam
		} else {
			// Autoredirect čistí POST kontext pro bezpečný refresh (F5)
			autoredirect("index.php?page={$page_param}{$url_suffix}&update_guid=" . urlencode($update_guid)); // Přesměrování na detail
		}
	}

	/**
	 * Implementace abstraktní metody rodiče. 
	 * Obsahuje CSS a základní dvoupanelový HTML skelet.
	 */
	final protected function render_body(): void {
		$err_ajax_net = addslashes($this->phrase('err_ajax_network', [], 'Chyba sítě při AJAX volání')); // JS chybová hláška sítě
		$err_ajax_ref = addslashes($this->phrase('err_ajax_refresh', [], 'Chyba při obnově master panelu:')); // JS chybová hláška obnovy

		echo <<<HTML
		<style>
			/* Hlavní kontejner pro master-detail zobrazení (omezuje výšku na viewport) */
			.page-panel { 
				max-width: 95% !important; 
				padding: 0 !important; 
				display: flex; 
				flex-direction: row; 
				height: calc(100vh - 120px); 
				overflow: hidden; 
			}
			/* Levý panel (Master) s výpisy */
			.md-master { 
				flex: 0 0 45%; 
				min-width: 400px;
				border-right: 1px solid #ddd; 
				background-color: #fafafa; 
				padding: 20px; 
				display: flex;
				flex-direction: column;
				overflow: hidden; 
			}
			/* Pravý panel (Detail) s editačním formulářem */
			.md-detail { 
				flex: 1; 
				padding: 20px 30px; 
				background-color: #ffffff; 
				display: flex;
				flex-direction: column;
				overflow: hidden; 
			}
			/* Fixní hlavička levého panelu (neodjíždí se scrollováním tabulky) */
			.md-master-header, .md-sticky-header-master {
				flex: 0 0 auto;
				border-bottom: 2px solid #eee;
				margin-bottom: 10px;
				padding-bottom: 10px;
			}
			/* Dynamically scrollovatelná oblast s tabulkou (Master) */
			.md-master-content {
				flex: 1 1 auto;
				overflow-y: auto;
				padding-right: 5px;
			}
			/* Fixní hlavička pravého panelu (obsahuje tlačítka Uložit/Zahodit) */
			.md-detail-header, .md-sticky-header-detail {
				flex: 0 0 auto;
				border-bottom: 2px solid #004488;
				display: flex;
				justify-content: space-between;
				align-items: center;
				padding-bottom: 10px;
				margin-bottom: 20px;
				gap: 10px;
			}
			/* Dynamicky scrollovatelná oblast formuláře (Detail) */
			.md-detail-content {
				flex: 1 1 auto;
				overflow-y: auto;
				padding-right: 10px;
			}
			.md-master-header h2, .md-sticky-header-master h2,
			.md-detail-header h2, .md-sticky-header-detail h2 {
				color: #004488;
			}
			/* Reset vlastností kompaktní tabulky */
			.md-table {
				width: 100%;
				border-collapse: collapse;
				margin-top: 0;
			}
			/* Sticky záhlaví tabulky (zajišťuje, že th prvek zůstane viditelný při scrollu dolů) */
			.md-table th {
				position: sticky;
				top: 0;
				background-color: #e9f2fa;
				padding: 6px 4px;
				border: 1px solid #ddd;
				text-align: left;
				z-index: 5;
				box-shadow: 0 1px 0 #ddd, 0 -1px 0 #ddd;
			}
			.md-table td {
				padding: 4px;
				border: 1px solid #ddd;
			}
			.md-table tr {
				background-color: #fff;
				color: #333;
			}
			.md-table tr:hover {
				background-color: #f1f1f1;
			}
			/* Zvýraznění aktivně vybraného řádku v levém panelu */
			.md-row-active {
				background-color: #e6f7ff !important;
				color: #333 !important;
			}
			/* Potlačené (např. deaktivované) záznamy */
			.md-row-inactive {
				background-color: #f9f9f9 !important;
				color: #999 !important;
			}
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

			// Provede prvotní scroll po úplném načtení DOM stromu
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
		
		$class_meta = $this->em->get_class_meta();                           // Metadata aktuální třídy
		$caption_plural = (string)($class_meta['caption_plural'] ?? '');     // Množné číslo názvu třídy
		
		if ($caption_plural === '') {                                        // Kontrola prázdného nadpisu seznamu
			$caption_plural = $this->phrase('default_list_heading', [], 'Seznam záznamů'); // Výchozí lokalizovaný nadpis seznamu
		}

		$safe_caption_plural = htmlspecialchars($caption_plural);            // Ošetřený nadpis seznamu
		$search_placeholder = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat...')); // Placeholder vyhledávání

		// Obálka fixní hlavičky levého panelu
		echo <<<HTML
		<div class="md-master-header">
HTML;
		
		// Výzva pro specifický kód potomka (tlačítka apod.)
		$this->render_master_top();                                          // Vykreslení horních prvků potomka

		echo <<<HTML
			<h2 style="font-size: 16px; margin: 0 0 10px 0; border: none; padding: 0;">{$safe_caption_plural}</h2>
			<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>
		
		<!-- Scrollovatelná obálka výpisu (Flexbox child) -->
		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
HTML;
		
		// Sestavení dynamických <th> ze struktury $list_columns
		foreach ($list_columns as $col => $header) {                         // Vykreslení záhlaví sloupců tabulky
			echo "\t\t\t\t\t\t<th>" . htmlspecialchars($header) . "</th>\n"; // Buňka záhlaví sloupce
		}
		
		echo <<<HTML
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		// Spuštění T-SQL dotazu (s automatickým tříděním z entity_manageru)
		$sql = $this->em->build_select_query($this->master_where);           // Sestavení SELECT dotazu
		$q = sqlrun($sql);                                                   // Spuštění dotazu pro seznam
		
		$page_param = urlencode($this->get_current_page_name());             // Kanonický název stránky do URL
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		while ($row = fetch($q)) {                                           // Načítání jednotlivých řádků seznamu
			$uuid = (string)$row['original'];                                // Originální UUID řádku
			$rowClass = ($uuid === $update_guid) ? 'md-row-active' : '';     // Třída pro aktivní řádek
			$rowIdAttr = ($uuid === $update_guid) ? 'id="active-row"' : '';  // Atribut id pro aktivní řádek

			$row_url = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$uuid}"); // Cílová URL řádku
			echo "\t\t\t\t\t\t<tr class=\"{$rowClass}\" {$rowIdAttr} style=\"cursor: pointer;\" onclick=\"document.location='{$row_url}'\">\n"; // Otevření řádku
			
			// Vykreslení konkrétních buněk (bez ohledu na to, v jakém pořadí přišly z DB)
			foreach ($list_columns as $col => $header) {                     // Výpis hodnot buněk aktuálního řádku
				$val = htmlspecialchars((string)($row[$col] ?? ''));         // Hodnota buňky v seznamu
				echo "\t\t\t\t\t\t\t<td>{$val}</td>\n";                      // Vykreslení buňky tabulky
			}
			echo "\t\t\t\t\t\t</tr>\n";                                      // Uzavření řádku tabulky
		}
		
		free_result($q);                                                     // Uvolnění paměti pro bezpečný chod serveru

		echo <<<HTML
				</tbody>
			</table>
		</div>
		<script>
			// Rychlé klientské filtrování přímo nad vykresleným DOMem
			document.getElementById('master-filter').addEventListener('input', function() {
				const term = this.value.toLowerCase();
				const rows = document.getElementById('master-list').querySelectorAll('tr');
				rows.forEach(row => {
					row.style.display = row.textContent.toLowerCase().includes(term) ? '' : 'none';
				});
			});
		</script>
HTML;
	}

	/**
	 * Hook pro potomky: umožňuje přepsat hlavní titulek detailního panelu.
	 */
	protected function get_detail_header(): string {
		return htmlspecialchars($this->phrase('default_detail_heading', [], 'Detail záznamu')); // Výchozí lokalizovaný titulek detailu
	}

	/**
	 * Hook pro potomky: umožňuje vložit další akční tlačítka do hlavičky detailu
	 * (mezi tlačítko "Zahodit změny" a "Uložit změny").
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

		global $datarow;                                                     // Globální pole pro aktuální řádek

		if ($update_guid === 'NEW') {                                        // Příprava výchozích hodnot pro nový záznam
			$datarow = [];                                                   // Inicializace prázdného záznamu
			foreach ($this->em->get_columns() as $colname => $meta) {        // Nastavení výchozích hodnot všech sloupců
				$type = $meta['input_type'] ?? 'text';                       // Typ vstupního prvku
				$datarow[$colname] = ($type === 'checkbox') ? '0' : '';      // Výchozí hodnota pole
			}
			$datarow['object_is_mine'] = 1;                                  // Nový záznam patří vždy uživateli
			$is_mine = true;                                                 // Příznak vlastnictví záznamu
		} else {
			// Načtení dat přes T-SQL (včetně překladových mechanismů pro stringy)
			$sql = $this->em->build_select_query("m.original = " . guidliteral($update_guid)); // Dotaz na detail záznamu
			$q = sqlrun($sql);                                               // Spuštění dotazu pro detail
			
			$datarow = fetch($q);                                            // Načtení dat detailu
			free_result($q);                                                 // Nutné pro zamezení memory leaků
			
			if (!$datarow) {                                                 // Kontrola existence načteného záznamu
				$msg_nf = htmlspecialchars($this->phrase('msg_record_not_found', [], 'Záznam nebyl nalezen.')); // Chybová hláška
				echo "<div class='msg-err'>{$msg_nf}</div>";                 // Výpis chyby
				return;                                                      // Ukončení při nenalezení záznamu
			}
			
			$is_mine = (bool)$datarow['object_is_mine'];                     // Zda záznam vlastní aktuální tenant
		}

		$page_param = urlencode($this->get_current_page_name());             // Kanonický název aktuální stránky
		
		// Dynamická propagace kontextových parametrů do URL i do skrytých polí
		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL s kontextem
		$hidden_inputs = $this->get_context_hidden_inputs();                 // Skrytá pole s kontextem
		$discard_url = "index.php?page={$page_param}{$url_suffix}";          // Cílová URL pro zahození změn
		$form_action = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$update_guid}"); // Cílová URL formuláře
		$safe_update_guid = htmlspecialchars($update_guid);                  // Ošetřené UUID pro hidden input
		
		$header_html = $this->get_detail_header();                           // Nadpis detailního panelu
		$extra_buttons = $this->render_detail_header_buttons($update_guid);  // Doplňková tlačítka potomka

		// Sestavení tlačítek Uložit a Zahodit změny přes abstract_button (pokud není panel readonly)
		$buttons_html = $extra_buttons;                                      // Výchozí sada tlačítek hlavičky
		if (!$this->is_readonly) {                                           // Pokud je povolená běžná editace záznamu
			$btn_discard = new abstract_button('btn_discard', 'Zahodit změny', 'abstract_button', '', 'btn-danger'); // Tlačítko zahození změn
			$btn_discard->set_href($discard_url)->set_onclick('isFormDirty = false;'); // Přechod bez varování dirty stavu

			$btn_save = new abstract_button('btn_save', 'Uložit změny', 'abstract_button', '', 'btn-success'); // Tlačítko uložení formuláře
			$btn_save->set_type('submit')->set_name_value('btn_save', '1');  // Nastavení submit atributů

			$buttons_html = $btn_discard->render() . "\n\t\t\t\t\t" . $extra_buttons . "\n\t\t\t\t\t" . $btn_save->render(); // Spojení tlačítek hlavičky
		}

		echo <<<HTML
		<!-- Obalový form využívá celou výšku (flex) pro rolovatelný obsah -->
		<form method="post" action="{$form_action}" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="update_guid" value="{$safe_update_guid}">{$hidden_inputs}
			
			<!-- Fixní hlavička (Zahodit / Doplňková tlačítka / Uložit) -->
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$header_html}</h2>
				<div style="display: flex; gap: 10px; align-items: center;">
					{$buttons_html}
				</div>
			</div>
			
			<!-- Scrollovatelná obálka formulářů -->
			<div class="md-detail-content">
HTML;

		// Volání hooku pro custom notifikace (např. upozornění na dědičnost)
		$this->render_detail_top();                                          // Vykreslení horní části detailu

		// Vyhodnocení strukturálních bloků definovaných potomkem
		$groups = $this->form_groups;                                        // Skupiny polí definované v potomkovi
		
		// Bezpečnostní fallback pro případ, že potomek skupiny nedefinoval (vysype se vše)
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

		// Iterace přes bloky a generování tabulek s input prvky
		foreach ($groups as $group_title => $columns) {                      // Vykreslení jednotlivých skupin formuláře
			if ($group_title !== '') {                                       // Vykreslení nadpisu neprázdné skupiny
				echo "\t\t\t\t<h3 style=\"margin-top: 20px; color: #004488; font-size: 15px;\">" . htmlspecialchars($group_title) . "</h3>\n"; // Nadpis skupiny
			}
			
			echo "\t\t\t\t<table class=\"md-table\" style=\"margin-bottom: 30px;\">\n"; // Začátek tabulky skupiny
			
			foreach ($columns as $colname) {                                 // Zpracování jednotlivých polí ve skupině
				$meta = $this->em->get_column_meta($colname);                // Načtení metadat sloupce
				
				// Ignorovat neexistující nebo skryté prvky
				if (empty($meta)) {                                          // Přeskočení neznámého sloupce v metadatech
					continue;                                                // Pokračování na další sloupec
				}
				if (!empty($meta['hidden'])) {                               // Přeskočení skrytého sloupce ve formuláři
					continue;                                                // Pokračování na další sloupec
				}
				
				// Názvosloví s fallback mechanismem (Label -> Caption -> Colname)
				$label = htmlspecialchars((string)($meta['label'] ?: $meta['caption'] ?: $colname)); // Popisek pole
				$helptext = (string)($meta['helptext'] ?? '');               // Text nápovědy k poli
				
				// Nápověda vložená jako bublinový tooltip do obalové <td>
				$title_attr = $helptext !== '' ? " title=\"" . htmlspecialchars($helptext) . "\"" : ""; // Tooltip buňky
				
				// Nové vizuální indikátory převzaté ze starého systému
				$req_html = !empty($meta['is_mandatory']) ? "<span style=\"color: #b91c1c; margin-left: 3px;\" title=\"{$lbl_req_title}\">*</span>" : ''; // Hvězdička povinnosti
				$trans_html = !empty($meta['translate']) ? "<br><small style=\"color: #2563eb; font-size: 10px;\" title=\"{$lbl_tr_title}\">{$lbl_tr_badge}</small>" : ''; // Štítek překladu
				
				// Generování konkrétního tagu (<input>, <select>, <textarea>) dle metadat
				$input_html = $this->em->render_dynamic_input($colname, (string)$datarow[$colname], $is_mine, $this->is_readonly); // HTML vstupního prvku
				
				echo <<<HTML
					<tr>
						<td style="width: 30%;"{$title_attr}><strong>{$label}{$req_html}:</strong>{$trans_html}</td>
						<td>{$input_html}</td>
					</tr>

HTML;
			}
			echo "\t\t\t\t</table>\n";
		}

		// Vložení globální auditní stopy
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