<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 22:48
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
 * 4. Automatizované skupiny ve formuláři ($form_groups):
 *    - Potomek může v konstruktoru definovat pole `$this->form_groups`,
 *      čímž se formulář dynamicky rozdělí do vizuálních sekcí s vlastními nadpisy.
 *
 * 5. Hook metody pro customizaci (Rozšiřitelnost bez přepisování jádra):
 *    - `render_master_top()`: Pro vložení tlačítek a HTML nad vyhledávací pole vlevo.
 *    - `get_detail_header()`: Pro dynamickou změnu velkého nadpisu vpravo.
 *    - `render_detail_header_buttons()`: Pro vložení doplňkových tlačítek do hlavičky detailu.
 *    - `render_detail_top()`: Pro vložení upozornění/notifikací nad editační formulář.
 *
 * Změny:
 * 2026-10-15 22:48 - Odstraněno duplicitní volání process_save() v render() (volá rodič při POST).
 *                  - Doplněna pojistka isset($_POST['btn_save']) v process_save() a skryté pole update_guid.
 *                  - Sjednoceny CSS třídy .md-detail-header a .md-sticky-header-detail.
 *                  - Přidán hook render_detail_header_buttons() pro podřízené stránky.
 * 2026-10-15 09:55 - Oprava řádků spojených post-procesorem a doplnění Anti-LaTeX komentářů.
 * 2026-10-12 - Extrahováno sestavování URL parametrů do metody get_context_url_suffix a get_context_hidden_inputs,
 *              zjednodušeno formátování dat u audit trailu pomocí date_format4 z OsirisLib.
 * 2026-10-09 - Zamezení zpracování POST dat a AJAXu při odepřeném přístupu ($access_denied).
 * 2026-10-08 - Ošetřen stav NEW pro zakládání nových záznamů a zabráněno cyklení redirectu.
 *            - Odstraněn memory leak doplněním uvolňování SQL resultů (free_result).
 *            - Opravena sanitizace kontextových URL parametrů z htmlspecialchars na urlencode.
 * 2026-10-07 - Přidána dynamická propagace kontextových parametrů (parent_class, parent_object)
 *              do URL a skrytých polí formuláře pro správný běh entity_manageru.
 * 2026-09-30 - Obohaceno o architektonické komentáře pro AI kontext.
 *            - Odstraněno řetězení příkazů na jeden řádek pro lepší čitelnost.
 *            - Doplněna vizuální signalizace povinných polí a podpory překladu do UI.
 * 2026-09-29 - Přepracován CSS layout na Flexbox (fixní hlavičky, posuvné tělo).
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
	
	/** Instance dynamického správce objektů řídící čtení a zápis */
	protected ?entity_manager $em = null;                                    // Instance správce entit

	/**
	 * Vrátí kanonický název aktuální stránky (např. 'page_meta_class').
	 */
	protected function get_current_page_name(): string {
		$page = trim((string)getinput('page'));                              // Načtení parametru page z requestu
		if ($page === '') {
			return get_class($this);                                         // Fallback na název třídy stránky
		}
		$page = basename($page, '.php');                                     // Očištění názvu stránky
		if (!str_starts_with($page, 'page_')) {
			$page = 'page_' . $page;                                         // Sjednocení na prefix page_
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
		foreach (['parent_object', 'parent_class', 'menu_code'] as $ctx_param) {
			$val = (string)getinput($ctx_param);                             // Hodnota kontextového parametru
			if ($val !== '') {
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
		foreach (['parent_object', 'parent_class', 'menu_code'] as $ctx_param) {
			$val = (string)getinput($ctx_param);                             // Hodnota kontextového parametru
			if ($val !== '') {
				$hidden_inputs .= "\n\t\t\t<input type=\"hidden\" name=\"{$ctx_param}\" value=\"" . htmlspecialchars($val) . "\">";
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
		if ($this->access_denied) {
			parent::render();
			return;
		}

		// Inicializace správce entit PŘED voláním parent::render(), aby byl připraven pro process_save()
		if ($this->class_name !== '' && $this->em === null) {
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance entity_manageru
		}

		// Záchyt pro asynchronní obnovu pouze levého panelu
		if (isset($_GET['ajax_panel']) && $_GET['ajax_panel'] === 'master') {
			$this->render_master();                                          // Vykreslení pouze levého panelu
			exit;
		}
		
		// Vykreslení obálky z `abstract_page`, která při POST zavolá `process_save()` a následně `render_body()`
		parent::render();
	}

	/**
	 * Zajišťuje zpracování POST dat z formuláře a následný redirect.
	 */
	protected function process_save(): void {
		if ($this->em === null || !isset($_POST['btn_save'])) {
			return;
		}

		$update_guid = trim((string)getinput('update_guid'));                // Identifikátor upravovaného záznamu
		if ($update_guid === '') {
			return;                                                          // Bez vybraného záznamu ani NEW neukládáme
		}

		$save_guid = ($update_guid === 'NEW') ? '' : $update_guid;           // Pro nový záznam předáme prázdný řetězec
		
		$this->em->save_post_data($save_guid);                               // Autonomní uložení dat přes entity_manager
		
		$page_param = urlencode($this->get_current_page_name());             // Kanonický název aktuální stránky
		$url_suffix = $this->get_context_url_suffix();                       // Kontextové parametry URL

		// Zamezení uvíznutí na prázdném formuláři po uložení nového záznamu
		if ($update_guid === 'NEW') {
			autoredirect("index.php?page={$page_param}{$url_suffix}");
		} else {
			// Autoredirect čistí POST kontext pro bezpečný refresh (F5)
			autoredirect("index.php?page={$page_param}{$url_suffix}&update_guid=" . urlencode($update_guid));
		}
	}

	/**
	 * Implementace abstraktní metody rodiče. 
	 * Obsahuje CSS a základní dvoupanelový HTML skelet.
	 */
	final protected function render_body(): void {
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
					if (!response.ok) throw new Error("Chyba sítě při AJAX volání");
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
					console.error('Chyba při obnově master panelu:', error);
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
		if ($this->em === null) {
			return;
		}
		
		$list_columns = $this->em->get_list_columns();                       // Sloupce pro zobrazení v seznamu
		
		if (empty($list_columns)) {
			echo "<div class='msg-info'>Master panel nemá v metadatech (list_order) definované žádné sloupce.</div>";
			return;
		}

		$update_guid = (string)getinput('update_guid');                      // Aktuálně vybraný záznam
		
		$class_meta = $this->em->get_class_meta();                           // Metadata aktuální třídy
		$caption_plural = (string)($class_meta['caption_plural'] ?? '');     // Množné číslo názvu třídy
		
		if ($caption_plural === '') {
			$caption_plural = 'Seznam záznamů';                              // Výchozí nadpis seznamu
		}

		$safe_caption_plural = htmlspecialchars($caption_plural);            // Ošetřený nadpis seznamu

		// Obálka fixní hlavičky levého panelu
		echo <<<HTML
		<div class="md-master-header">
HTML;
		
		// Výzva pro specifický kód potomka (tlačítka apod.)
		$this->render_master_top();                                          // Vykreslení horních prvků potomka

		echo <<<HTML
			<h2 style="font-size: 16px; margin: 0 0 10px 0; border: none; padding: 0;">{$safe_caption_plural}</h2>
			<input type="text" id="master-filter" placeholder="Hledat..." style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>
		
		<!-- Scrollovatelná obálka výpisu (Flexbox child) -->
		<div class="md-master-content">
			<table class="md-table">
				<thead>
					<tr>
HTML;
		
		// Sestavení dynamických <th> ze struktury $list_columns
		foreach ($list_columns as $col => $header) {
			echo "\t\t\t\t\t\t<th>" . htmlspecialchars($header) . "</th>\n";
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

		while ($row = fetch($q)) {
			$uuid = (string)$row['original'];                                // Originální UUID řádku
			$rowClass = ($uuid === $update_guid) ? 'md-row-active' : '';     // Třída pro aktivní řádek
			$rowIdAttr = ($uuid === $update_guid) ? 'id="active-row"' : '';  // Atribut id pro aktivní řádek

			$row_url = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$uuid}");
			echo "\t\t\t\t\t\t<tr class=\"{$rowClass}\" {$rowIdAttr} style=\"cursor: pointer;\" onclick=\"document.location='{$row_url}'\">\n";
			
			// Vykreslení konkrétních buněk (bez ohledu na to, v jakém pořadí přišly z DB)
			foreach ($list_columns as $col => $header) {
				$val = htmlspecialchars((string)($row[$col] ?? ''));         // Hodnota buňky v seznamu
				echo "\t\t\t\t\t\t\t<td>{$val}</td>\n";
			}
			echo "\t\t\t\t\t\t</tr>\n";
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
		return 'Detail záznamu';
	}

	/**
	 * Hook pro potomky: umožňuje vložit další akční tlačítka do hlavičky detailu
	 * (mezi tlačítko "Zahodit změny" a "Uložit změny").
	 */
	protected function render_detail_header_buttons(string $update_guid): string {
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
		if ($this->em === null) {
			echo "<div class='msg-info'>Detail panel není nakonfigurován.</div>";
			return;
		}

		$update_guid = (string)getinput('update_guid');                      // Získání ID vybraného záznamu
		if ($update_guid === '') {
			echo "<div class='msg-info'>Vyberte záznam z levého panelu.</div>";
			return;
		}

		global $datarow;                                                     // Globální pole pro aktuální řádek

		if ($update_guid === 'NEW') {
			$datarow = [];                                                   // Inicializace prázdného záznamu
			foreach ($this->em->get_columns() as $colname => $meta) {
				$type = $meta['input_type'] ?? 'text';                       // Typ vstupního prvku
				$datarow[$colname] = ($type === 'checkbox') ? '0' : '';      // Výchozí hodnota pole
			}
			$datarow['object_is_mine'] = 1;                                  // Nový záznam patří vždy uživateli
			$is_mine = true;                                                 // Příznak vlastnictví záznamu
		} else {
			// Načtení dat přes T-SQL (včetně překladových mechanismů pro stringy)
			$sql = $this->em->build_select_query("m.original = " . guidliteral($update_guid));
			$q = sqlrun($sql);                                               // Spuštění dotazu pro detail
			
			$datarow = fetch($q);                                            // Načtení dat detailu
			free_result($q);                                                 // Nutné pro zamezení memory leaků
			
			if (!$datarow) {
				echo "<div class='msg-err'>Záznam nebyl nalezen.</div>";
				return;
			}
			
			$is_mine = (bool)$datarow['object_is_mine'];                     // Zda záznam vlastní aktuální tenant
		}

		$page_param = urlencode($this->get_current_page_name());             // Kanonický název aktuální stránky
		
		// Dynamická propagace kontextových parametrů do URL i do skrytých polí
		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL s kontextem
		$hidden_inputs = $this->get_context_hidden_inputs();                 // Skrytá pole s kontextem
		$discard_url = htmlspecialchars("index.php?page={$page_param}{$url_suffix}");
		$form_action = htmlspecialchars("index.php?page={$page_param}{$url_suffix}&update_guid={$update_guid}");
		$safe_update_guid = htmlspecialchars($update_guid);                  // Ošetřené UUID pro hidden input
		
		$header_html = $this->get_detail_header();                           // Nadpis detailního panelu
		$extra_buttons = $this->render_detail_header_buttons($update_guid);  // Doplňková tlačítka potomka

		echo <<<HTML
		<!-- Obalový form využívá celou výšku (flex) pro rolovatelný obsah -->
		<form method="post" action="{$form_action}" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="update_guid" value="{$safe_update_guid}">{$hidden_inputs}
			
			<!-- Fixní hlavička (Zahodit / Doplňková tlačítka / Uložit) -->
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$header_html}</h2>
				<div style="display: flex; gap: 10px; align-items: center;">
					<a href="{$discard_url}" class="btn btn-danger" onclick="isFormDirty = false;">Zahodit změny</a>
					{$extra_buttons}
					<button type="submit" name="btn_save" value="1" class="btn btn-success">Uložit změny</button>
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
		if (empty($groups)) {
			$all_cols = [];                                                  // Seznam všech viditelných sloupců
			foreach ($this->em->get_columns() as $colname => $meta) {
				if (empty($meta['hidden'])) {
					$all_cols[] = $colname;                                  // Zařazení neskrytého sloupce
				}
			}
			$groups = ['' => $all_cols];                                     // Jedna bezejmenná skupina
		}

		// Iterace přes bloky a generování tabulek s input prvky
		foreach ($groups as $group_title => $columns) {
			if ($group_title !== '') {
				echo "\t\t\t\t<h3 style=\"margin-top: 20px; color: #004488; font-size: 15px;\">" . htmlspecialchars($group_title) . "</h3>\n";
			}
			
			echo "\t\t\t\t<table class=\"md-table\" style=\"margin-bottom: 30px;\">\n";
			
			foreach ($columns as $colname) {
				$meta = $this->em->get_column_meta($colname);                // Načtení metadat sloupce
				
				// Ignorovat neexistující nebo skryté prvky
				if (empty($meta)) {
					continue;
				}
				if (!empty($meta['hidden'])) {
					continue;
				}
				
				// Názvosloví s fallback mechanismem (Label -> Caption -> Colname)
				$label = htmlspecialchars((string)($meta['label'] ?: $meta['caption'] ?: $colname));
				$helptext = (string)($meta['helptext'] ?? '');               // Text nápovědy k poli
				
				// Nápověda vložená jako bublinový tooltip do obalové <td>
				$title_attr = $helptext !== '' ? " title=\"" . htmlspecialchars($helptext) . "\"" : "";
				
				// Nové vizuální indikátory převzaté ze starého systému
				$req_html = !empty($meta['is_mandatory']) ? '<span style="color: #b91c1c; margin-left: 3px;" title="Povinné pole">*</span>' : '';
				$trans_html = !empty($meta['translate']) ? '<br><small style="color: #2563eb; font-size: 10px;" title="Tato hodnota může být přeložena do jiných jazyků">(Podporuje překlad)</small>' : '';
				
				// Generování konkrétního tagu (<input>, <select>, <textarea>) dle metadat
				$input_html = $this->em->render_dynamic_input($colname, (string)$datarow[$colname], $is_mine);
				
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
		
		if (empty($datarow) || (empty($datarow['date_created']) && empty($datarow['date_modified']))) {
			return;
		}

		$html = '';                                                          // Výstupní HTML auditní stopy
		
		if (!empty($datarow['date_created'])) {
			$date_c = date_format4($datarow['date_created'], 16);            // Zformátované datum vytvoření
			$who_c_name = !empty($datarow['who_created_info']) ?$datarow['who_created_info'] : 'Neznámý uživatel';
			$html .= "<div>Vytvořil {$date_c} " . htmlspecialchars((string)$who_c_name) . "</div>";
		}

		if (!empty($datarow['date_modified'])) {
			$date_m = date_format4($datarow['date_modified'], 16);           // Zformátované datum úpravy
			$who_m_name = !empty($datarow['who_modified_info']) ?$datarow['who_modified_info'] : 'Neznámý uživatel';
			$html .= "<div>Změnil &nbsp;&nbsp;{$date_m} " . htmlspecialchars((string)$who_m_name) . "</div>";
		}

		if ($html !== '') {
			echo "<div style=\"margin-top: 30px; font-size: 11px; color: #94a3b8; line-height: 1.6; font-family: monospace;\">{$html}</div>";
		}
	}
}