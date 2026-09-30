<?php
/**
 * =============================================================================
 * Třída: abstract_page_master_detail
 * Účel: Abstraktní třída rozšiřující základní stránku o dvoupamelový layout.
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
 *      ihned v metodě `render()` a předáno do `process_save()`.
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
 *    - `render_detail_top()`: Pro vložení upozornění/notifikací nad editační formulář.
 *
 * Změny:
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
	protected string $class_name = '';
	
	/** Volitelné omezení SQL dotazu pro načítání master panelu (např. "m.parent_object = ...") */
	protected string $master_where = '';
	
	/** Mapování logických skupin vstupních polí. Očekává: ['Název sekce' => ['sloupec1', 'sloupec2']] */
	protected array $form_groups = [];
	
	/** Instance dynamického správce objektů řídící čtení a zápis */
	protected ?entity_manager $em = null;

	/**
	 * Hlavní bod vstupu životního cyklu stránky.
	 * Ošetřuje POST data a AJAX požadavky před vykreslením těla.
	 */
	public function render(): void {
		// Inicializace správce entit, pokud potomek specifikoval třídu
		if ($this->class_name !== '') {
			$this->em = new entity_manager($this->class_name);
		}

		// Záchyt uložení dat (PRG vzor)
		if (isset($_POST['btn_save'])) {$this->process_save();
		}

		// Záchyt pro asynchronní obnovu pouze levého panelu
		if (isset($_GET['ajax_panel']) && $_GET['ajax_panel'] === 'master') {$this->render_master();
			exit;
		}
		
		// Vykreslení obálky z `abstract_page`, která nakonec zavolá `render_body()`
		parent::render();
	}

	/**
	 * Zajišťuje zpracování POST dat z formuláře a následný redirect.
	 */
	protected function process_save(): void {
		if ($this->em === null) {
			return;
		}

		$update_guid = (string)getinput('update_guid');
		$this->em->save_post_data($update_guid);
		
		// Autoredirect čistí POST kontext pro bezpečný refresh (F5)
		autoredirect();
	}

	/**
	 * Implementace abstraktní metody rodiče. 
	 * Obsahuje CSS a základní dvoupamelový HTML skelet.
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
			.md-master-header {
				flex: 0 0 auto;
				border-bottom: 2px solid #eee;
				margin-bottom: 10px;
				padding-bottom: 10px;
			}
			/* Dynamicky scrollovatelná oblast s tabulkou (Master) */
			.md-master-content {
				flex: 1 1 auto;
				overflow-y: auto;
				padding-right: 5px;
			}
			/* Fixní hlavička pravého panelu (obsahuje tlačítka Uložit/Zahodit) */
			.md-detail-header {
				flex: 0 0 auto;
				border-bottom: 2px solid #004488;
				display: flex;
				justify-content: space-between;
				align-items: flex-end;
				padding-bottom: 10px;
				margin-bottom: 20px;
			}
			/* Dynamicky scrollovatelná oblast formuláře (Detail) */
			.md-detail-content {
				flex: 1 1 auto;
				overflow-y: auto;
				padding-right: 10px;
			}
			.md-master-header h2, .md-detail-header h2 {
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
				padding: 2px;
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
		$this->render_master();

		echo <<<HTML
		</div>
		<div class="md-detail">
HTML;
		$this->render_detail();

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
		
		$list_columns =$this->em->get_list_columns();
		
		if (empty($list_columns)) {
			echo "<div class='msg-info'>Master panel nemá v metadatech (list_order) definované žádné sloupce.</div>";
			return;
		}

		$update_guid = (string)getinput('update_guid');
		
		$class_meta =$this->em->get_class_meta();
		$caption_plural = (string)($class_meta['caption_plural'] ?? '');
		
		if ($caption_plural === '') {$caption_plural = 'Seznam záznamů';
		}

		$safe_caption_plural = htmlspecialchars($caption_plural);

		// Obálka fixní hlavičky levého panelu
		echo <<<HTML
		<div class="md-master-header">
HTML;
		
		// Výzva pro specifický kód potomka (tlačítka apod.)
		$this->render_master_top();

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
		foreach ($list_columns as $col =>$header) {
			echo "\t\t\t\t\t\t<th>" . htmlspecialchars($header) . "</th>\n";
		}
		
		echo <<<HTML
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		// Spuštění T-SQL dotazu (s automatickým tříděním z entity_manageru)
		$sql = $this->em->build_select_query($this->master_where);
		$q = sqlrun($sql);
		
		while ($row = fetch($q)) {
			$uuid =$row['original'];
			$rowClass = ($uuid === $update_guid) ? 'md-row-active' : '';$rowIdAttr = ($uuid ===$update_guid) ? 'id="active-row"' : '';
			
			$page_param = htmlspecialchars((string)getinput('page'));
			$parent_param = (string)getinput('parent_object');$url_suffix = $parent_param !== '' ? "&parent_object=" . htmlspecialchars($parent_param) : '';

			echo "\t\t\t\t\t\t<tr class=\"{$rowClass}\" {$rowIdAttr} style=\"cursor: pointer;\" onclick=\"document.location='index.php?page={$page_param}{$url_suffix}&update_guid={$uuid}'\">\n";
			
			// Vykreslení konkrétních buněk (bez ohledu na to, v jakém pořadí přišly z DB)
			foreach ($list_columns as$col => $header) {$val = htmlspecialchars((string)($row[$col] ?? ''));
				echo "\t\t\t\t\t\t\t<td>{$val}</td>\n";
			}
			echo "\t\t\t\t\t\t</tr>\n";
		}

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

		$update_guid = (string)getinput('update_guid');
		if ($update_guid === '') {
			echo "<div class='msg-info'>Vyberte záznam z levého panelu.</div>";
			return;
		}

		// Načtení dat přes T-SQL (včetně překladových mechanismů pro stringy)
		$sql = $this->em->build_select_query("m.original = " . guidliteral($update_guid));
		$q = sqlrun($sql);
		
		global $datarow;
		$datarow = fetch($q);
		
		if (!$datarow) {
			echo "<div class='msg-err'>Záznam nebyl nalezen.</div>";
			return;
		}
		
		$is_mine = (bool)$datarow['object_is_mine'];
		$page_param = htmlspecialchars((string)getinput('page'));$parent_param = (string)getinput('parent_object');
		
		$url_suffix =$parent_param !== '' ? "&parent_object=" . htmlspecialchars($parent_param) : '';$discard_url = "index.php?page={$page_param}{$url_suffix}";
		
		$header_html =$this->get_detail_header();

		echo <<<HTML
		<!-- Obalový form využívá celou výšku (flex) pro rolovatelný obsah -->
		<form method="post" action="index.php?page={$page_param}{$url_suffix}&update_guid={$update_guid}" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			
			<!-- Fixní hlavička (Zahodit / Uložit) -->
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$header_html}</h2>
				<div>
					<a href="{$discard_url}" class="btn btn-danger" style="margin-right: 10px;" onclick="isFormDirty = false;">Zahodit změny</a>
					<button type="submit" name="btn_save" class="btn btn-success">Uložit změny</button>
				</div>
			</div>
			
			<!-- Scrollovatelná obálka formulářů -->
			<div class="md-detail-content">
HTML;

		// Volání hooku pro custom notifikace (např. upozornění na dědičnost)
		$this->render_detail_top();

		// Vyhodnocení strukturálních bloků definovaných potomkem
		$groups =$this->form_groups;
		
		// Bezpečnostní fallback pro případ, že potomek skupiny nedefinoval (vysype se vše)
		if (empty($groups)) {$all_cols = [];
			foreach ($this->em->get_columns() as $colname =>$meta) {
				if (empty($meta['hidden'])) {
					$all_cols[] =$colname;
				}
			}
			$groups = ['' =>$all_cols];
		}

		// Iterace přes bloky a generování tabulek s input prvky
		foreach ($groups as $group_title =>$columns) {
			if ($group_title !== '') {
				echo "\t\t\t\t<h3 style=\"margin-top: 20px; color: #004488; font-size: 15px;\">" . htmlspecialchars($group_title) . "</h3>\n";
			}
			
			echo "\t\t\t\t<table class=\"md-table\" style=\"margin-bottom: 30px;\">\n";
			
			foreach ($columns as $colname) {$meta = $this->em->get_column_meta($colname);
				
				// Ignorovat neexistující nebo skryté prvky
				if (empty($meta)) {
					continue;
				}
				if (!empty($meta['hidden'])) {
					continue;
				}
				
				// Názvosloví s fallback mechanismem (Label -> Caption -> Colname)
				$label = htmlspecialchars((string)($meta['label'] ?: $meta['caption'] ?:$colname));
				$helptext = (string)($meta['helptext'] ?? '');
				
				// Nápověda vložená jako bublinový tooltip do obalové <td>
				$title_attr = $helptext !== '' ? " title=\"" . htmlspecialchars($helptext) . "\"" : "";
				
				// Nové vizuální indikátory převzaté ze starého systému
				$req_html = !empty($meta['is_mandatory']) ? '<span style="color: #b91c1c; margin-left: 3px;" title="Povinné pole">*</span>' : '';
				$trans_html = !empty($meta['translate']) ? '<br><small style="color: #2563eb; font-size: 10px;" title="Tato hodnota může být přeložena do jiných jazyků">(Podporuje překlad)</small>' : '';
				
				// Generování konkrétního tagu (<input>, <select>, <textarea>) dle metadat
				$input_html =$this->em->render_dynamic_input($colname, (string)$datarow[$colname],$is_mine);
				
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
		$this->render_audit_trail();

		echo "\t\t\t</div>\n\t\t</form>\n";
	}

	/**
	 * Připojí pod formulář standardizovanou patku o vytvoření a úpravě dat (who/when).
	 */
	protected function render_audit_trail(): void {
		global $datarow;
		
		if (empty($datarow) || (empty($datarow['date_created']) && empty($datarow['date_modified']))) {
			return;
		}

		$html = '';
		
		if (!empty($datarow['date_created'])) {$dt_val = $datarow['date_created'];$date_c = ($dt_val instanceof DateTime) ?$dt_val->format('d.m.Y H:i') : date('d.m.Y H:i', strtotime((string)$dt_val));$who_c_name = !empty($datarow['who_created_info']) ?$datarow['who_created_info'] : 'Neznámý uživatel';
			
			$html .= "<div>Vytvořil {$date_c} " . htmlspecialchars((string)$who_c_name) . "</div>";
		}

		if (!empty($datarow['date_modified'])) {$dt_val = $datarow['date_modified'];$date_m = ($dt_val instanceof DateTime) ?$dt_val->format('d.m.Y H:i') : date('d.m.Y H:i', strtotime((string)$dt_val));$who_m_name = !empty($datarow['who_modified_info']) ?$datarow['who_modified_info'] : 'Neznámý uživatel';
			
			$html .= "<div>Změnil &nbsp;&nbsp;{$date_m} " . htmlspecialchars((string)$who_m_name) . "</div>";
		}

		if ($html !== '') {
			echo "<div style=\"margin-top: 30px; font-size: 11px; color: #94a3b8; line-height: 1.6; font-family: monospace;\">{$html}</div>";
		}
	}
}