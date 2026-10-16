<?php
/**
 * =============================================================================
 * Verze: 2026-10-17 01:40
 * Soubor: page_approval.php
 * Třída: page_approval
 * Účel: Univerzální schvalovací obrazovka (SSC) pro porovnání původních
 *       a navrhovaných hodnot a schvalování či vracení návrhů napříč třídami.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_approval`.
 * - Dědí z `abstract_page_master_detail`, čímž přebírá kompletní Flexbox dvoupanelový
 *   layout (`.md-master` a `.md-detail`) bez duplicity CSS a JS kódu.
 * - Využívá `entity_manager` (inicializovaný v `abstract_page_master_detail::render()`
 *   přes `$this->class_name`) pro načtení metadat cílové logické třídy, získání
 *   původních schválených hodnot (`build_select_query(..., true)`) a spuštění
 *   transakčního schválení (`approve_draft()`) nebo vrácení (`reject_draft()`).
 * - Využívá `abstract_button` a `$this->phrase()` pro plnou lokalizaci.
 * - Načítá pouze návrhy ve stavu `approval_status = 'F'` (`record_type = 'D'`),
 *   které patří aktuální organizaci (`dbsession.organization`) a mají stejnou
 *   jazykovou verzi jako přihlášený schvalovatel (`dbsession.language`).
 *
 * Změny:
 * 2026-10-17 01:40 - Nastavení `$this->class_name = $this->target_class` v konstruktoru,
 *                    aby se `$this->em` inicializoval v předkovi před odesláním HTML hlaviček.
 *                  - Doplněna metoda `format_comparison_value()` pro čitelný překlad
 *                    hodnot checkboxů, číselníků a relačních vazeb v porovnávací tabulce.
 * 2026-10-17 01:05 - První verze univerzální schvalovací stránky.
 * =============================================================================
 */

declare(strict_types=1);

class page_approval extends abstract_page_master_detail {

	private string $filter_class = '__ALL__';                                // Zvolený filtr logické třídy v levém panelu
	private string $target_class = '';                                       // Logická třída vybraného návrhu
	private string $draft_uuid = '';                                         // Primární klíč (uuid) vybraného návrhu 'D'

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->page_title = $this->phrase('page_title', [], 'Schvalování navržených změn'); // Lokalizovaný titulek stránky

		if ($this->access_denied) {                                          // Pokud předek zamítl přístup ke stránce
			return;                                                          // Ukončení inicializace
		}

		$req_filter = trim((string)getinput('filter_class'));                // Načtení filtru třídy z URL/POST
		if ($req_filter !== '') {                                            // Pokud byl filtr v požadavku předán
			$this->filter_class = $req_filter;                               // Uložení zvoleného filtru třídy
		}

		$this->target_class = trim((string)getinput('target_class'));        // Načtení třídy vybraného návrhu
		$this->draft_uuid = trim((string)getinput('draft_uuid'));            // Načtení UUID vybraného návrhu

		if ($this->target_class !== '') {                                    // Pokud je vybrána konkrétní třída návrhu
			$this->class_name = $this->target_class;                         // Předání třídy předkovi pro včasnou inicializaci $this->em
		}
	}

	/**
	 * Zpracuje schválení nebo odmítnutí vybraného návrhu (PRG vzor).
	 */
	protected function process_save(): void {
		if ($this->target_class === '' OR $this->draft_uuid === '' OR $this->em === null) { // Kontrola cílové třídy a správce
			return;                                                          // Bez kompletní identifikace neprovádíme akci
		}

		$is_approve = isset($_POST['btn_approve_draft']);                    // Zda schvalovatel klikl na Schválit
		$is_reject = isset($_POST['btn_reject_draft']);                      // Zda schvalovatel klikl na Odmítnout / Vrátit

		if (!$is_approve AND !$is_reject) {                                  // Pokud nebylo stisknuto žádné akční tlačítko
			return;                                                          // Ukončení bez akce
		}

		if ($is_approve) {                                                   // Provedení schválení návrhu
			$this->em->approve_draft($this->draft_uuid);                     // Schválení návrhu a odmítnutí souběžných
		} elseif ($is_reject) {                                              // Provedení vrácení / odmítnutí návrhu
			$note = (string)($_POST['approval_note'] ?? '');                 // Načtení důvodu vrácení z formuláře
			$this->em->reject_draft($this->draft_uuid, $note);               // Vrácení návrhu autorovi s poznámkou
		}

		$filter_suffix = ($this->filter_class !== '' AND $this->filter_class !== '__ALL__') ? '&filter_class=' . urlencode($this->filter_class) : ''; // Zachování filtru třídy
		autoredirect("index.php?page=page_approval{$filter_suffix}");        // Přesměrování na vyčištěný seznam ke schválení
	}

	/**
	 * Načte seznam logických tříd (vázaných na fyzické RAC tabulky) a k nim
	 * všechny čekající návrhy (`record_type = 'D'`, `approval_status = 'F'`)
	 * pro aktuálního tenanta a aktuální jazyk relace.
	 *
	 * @return array{classes: array<string, string>, items: array<int, array<string, mixed>>}
	 */
	private function load_pending_proposals(): array {
		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál organizace
		$lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka relace

		$classes = [];                                                       // Mapa dostupných tříd: [class_name => caption]
		$items = [];                                                         // Seznam nalezených návrhů ke schválení

		// 1. Zjištění všech logických tříd, jejichž fyzická tabulka má sloupec draft_author
		$q_cls = sqlrun("
			SELECT mc.class_name, mc.caption, mo.builtin_code AS table_name
			FROM meta_class mc
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_type = 'T' AND mo.record_type = 'A' AND mo.removed = 0
			JOIN v_syscolumns sc ON sc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT AND sc.colname = 'draft_author'
			WHERE mc.object_owner = 0x00
			  AND mc.record_type = 'A'
			  AND mc.removed = 0
			  AND mc.class_name <> 'sys_global_columns'
			ORDER BY mc.class_name
		");                                                                  // Dotaz na logické třídy podporující SSC

		$class_rows = [];                                                    // Pomocné pole načtených tříd
		while ($r_cls = fetch($q_cls)) {                                     // Průchod nalezenými třídami
			$c_name = (string)$r_cls['class_name'];                          // Technický název třídy
			$c_cap = (string)$r_cls['caption'] !== '' ? (string)$r_cls['caption'] : $c_name; // Popisek třídy
			$classes[$c_name] = $c_cap;                                      // Uložení do mapy tříd
			$class_rows[] = [                                                // Uložení definice pro dotazování návrhů
				'class_name' => $c_name,                                     // Název logické třídy
				'caption'    => $c_cap,                                      // Zobrazovaný název třídy
				'table_name' => (string)$r_cls['table_name']                 // Fyzická tabulka v DB
			];                                                               // Konec položky třídy
		}
		free_result($q_cls);                                                 // Uvolnění výsledku tříd

		// 2. Načtení čekajících návrhů ('F') v jednotlivých tabulkách
		foreach ($class_rows as $cr) {                                       // Průchod třídami
			$c_name = $cr['class_name'];                                     // Název aktuální třídy
			if ($this->filter_class !== '__ALL__' AND $this->filter_class !== $c_name) { // Aplikace filtru třídy
				continue;                                                    // Přeskočení nefiltrované třídy
			}

			$tab = $cr['table_name'];                                        // Fyzická tabulka třídy
			$q_cnt = sqlrun("
				SELECT COUNT(1) AS cnt
				FROM [{$tab}]
				WHERE record_type = 'D'
				  AND approval_status = 'F'
				  AND removed = 0
				  AND object_owner = {$org_sql}
				  AND [language] = {$lang_sql}
			");                                                              // Rychlý dotaz na počet čekajících návrhů
			$r_cnt = fetch($q_cnt);                                          // Načtení počtu návrhů
			free_result($q_cnt);                                             // Uvolnění dotazu počtu

			if (!$r_cnt OR (int)$r_cnt['cnt'] === 0) {                       // Pokud v tabulce žádné návrhy nečekají
				continue;                                                    // Přechod na další třídu
			}

			// Tabulka obsahuje návrhy -> načteme je včetně informací o autorovi a počtu souběžných návrhů
			$q_dr = sqlrun("
				SELECT
					d.*,
					dbo.f_get_user_info(d.who_modified) AS author_info,
					(
						SELECT COUNT(1)
						FROM [{$tab}] d2
						WHERE d2.original = d.original
						  AND d2.object_owner = d.object_owner
						  AND d2.[language] = d.[language]
						  AND d2.record_type = 'D'
						  AND d2.approval_status = 'F'
						  AND d2.removed = 0
					) AS competing_count
				FROM [{$tab}] d
				WHERE d.record_type = 'D'
				  AND d.approval_status = 'F'
				  AND d.removed = 0
				  AND d.object_owner = {$org_sql}
				  AND d.[language] = {$lang_sql}
				ORDER BY d.original, d.date_modified DESC
			");                                                              // Dotaz na čekající návrhy v tabulce

			while ($dr = fetch($q_dr)) {                                     // Průchod nalezenými návrhy
				// Určení čitelného označení záznamu z nejvhodnějšího sloupce
				$rec_label = '';                                             // Označení záznamu v seznamu
				foreach (['caption', 'builtin_code', 'class_name', 'column_name', 'login_name', 'value_code'] as $cand) { // Kandidáti popisku
					if (!empty($dr[$cand])) {                                // Pokud je kandidátní sloupec neprázdný
						$rec_label = (string)$dr[$cand];                     // Použití hodnoty jako popisku
						break;                                               // Ukončení hledání popisku
					}
				}
				if ($rec_label === '') {                                     // Fallback pokud nebyl nalezen textový sloupec
					$rec_label = (string)$dr['original'];                    // Použití UUID originálu
				}

				$items[] = [                                                 // Přidání návrhu do výsledného pole
					'class_name'      => $c_name,                            // Název logické třídy
					'class_caption'   => $cr['caption'],                     // Popisek logické třídy
					'draft_uuid'      => (string)$dr['uuid'],                // Primární klíč návrhu
					'original'        => (string)$dr['original'],            // Originální UUID záznamu
					'record_label'    => $rec_label,                         // Zobrazovaný název záznamu
					'author_info'     => (string)($dr['author_info'] ?: $dr['import_origin']), // Autor nebo původ importu
					'date_modified'   => (string)$dr['date_modified'],       // Datum postoupení ke schválení
					'competing_count' => (int)$dr['competing_count']         // Počet návrhů pro stejný original
				];                                                           // Konec položky návrhu
			}
			free_result($q_dr);                                              // Uvolnění dotazu návrhů
		}

		return ['classes' => $classes, 'items' => $items];                   // Vrácení tříd a nalezených návrhů
	}

	/**
	 * Převede databázovou hodnotu sloupce na čitelný řetězec pro porovnávací tabulku
	 * (překlad checkboxů 0/1, položek z meta_codetable a vazeb referenced_class).
	 */
	private function format_comparison_value(array $meta, string $raw_val): string { // Formátování hodnoty pro porovnání
		if ($raw_val === '') {                                               // Prázdná hodnota zůstává prázdná
			return '';                                                       // Vrácení prázdného řetězce
		}

		$type = (string)($meta['input_type'] ?? 'text');                     // Typ formulářového prvku sloupce
		if ($type === 'checkbox') {                                          // Překlad bitové hodnoty checkboxu
			$is_true = ($raw_val === '1' OR strtolower($raw_val) === 'true'); // Vyhodnocení pravdivostní hodnoty
			$yes_txt = $this->phrase('val_checkbox_yes', [], 'Ano');         // Lokalizované Ano
			$no_txt = $this->phrase('val_checkbox_no', [], 'Ne');            // Lokalizované Ne
			return $is_true ? "{$yes_txt} (1)" : "{$no_txt} (0)";            // Čitelný výpis stavu checkboxu
		}

		if (!empty($meta['referenced_codetable'])) {                         // Překlad kódu z číselníku meta_codetable
			$safe_ct = charliteral((string)$meta['referenced_codetable']);   // SQL literál názvu číselníku
			$safe_val = charliteral($raw_val);                               // SQL literál hodnoty číselníku
			$q_ct = sqlrun("SELECT TOP 1 caption FROM meta_codetable WHERE codetable_name = {$safe_ct} AND value_code = {$safe_val} AND record_type = 'A' AND removed = 0"); // Dotaz na popisek číselníku
			$r_ct = fetch($q_ct);                                            // Načtení popisku z číselníku
			free_result($q_ct);                                              // Uvolnění dotazu číselníku
			if ($r_ct AND (string)$r_ct['caption'] !== '') {                 // Pokud byl nalezen popisek v číselníku
				return (string)$r_ct['caption'] . " [{$raw_val}]";           // Výpis popisku i kódu
			}
		}

		if (!empty($meta['referenced_class']) AND is_guid($raw_val)) {       // Překlad relačního odkazu referenced_class
			$ref_cls_sql = guidliteral((string)$meta['referenced_class']);   // SQL literál odkazované třídy
			$target_sql = guidliteral($raw_val);                             // SQL literál cílového záznamu
			$q_rc = sqlrun("
				SELECT mo.builtin_code AS ref_table
				FROM meta_class mc
				JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
				WHERE mc.original = {$ref_cls_sql} AND mc.object_owner = 0x00 AND mc.record_type = 'A' AND mc.removed = 0
			");                                                              // Zjištění cílové fyzické tabulky
			$r_rc = fetch($q_rc);                                            // Načtení cílové tabulky
			free_result($q_rc);                                              // Uvolnění dotazu

			if ($r_rc AND !empty($r_rc['ref_table'])) {                      // Pokud cílová tabulka existuje
				$ref_tab = (string)$r_rc['ref_table'];                       // Název odkazované tabulky
				$q_row = sqlrun("SELECT TOP 1 * FROM [{$ref_tab}] WHERE original = {$target_sql} AND record_type = 'A' AND removed = 0 ORDER BY object_owner DESC"); // Načtení cílového řádku
				$t_row = fetch($q_row);                                      // Data cílového řádku
				free_result($q_row);                                         // Uvolnění dotazu cílového řádku
				if ($t_row) {                                                // Sestavení čitelného popisku cílového záznamu
					foreach (['class_name', 'builtin_code', 'column_name', 'caption'] as $c_col) { // Hledání vhodného sloupce
						if (!empty($t_row[$c_col])) {                        // Pokud sloupec obsahuje hodnotu
							$cap = (string)($t_row['caption'] ?? '');        // Případný český popisek
							$code = (string)$t_row[$c_col];                  // Technický kód záznamu
							return ($cap !== '' AND $cap !== $code) ? "{$code} ({$cap})" : $code; // Čitelný název cíle
						}
					}
				}
			}
		}

		return $raw_val;                                                     // Výchozí vrácení původního textu
	}

	/**
	 * Vykreslí levý panel se seznamem všech návrhů čekajících na schválení ('F').
	 */
	protected function render_master(): void {
		$data = $this->load_pending_proposals();                             // Načtení tříd a čekajících návrhů
		$classes = $data['classes'];                                         // Mapa dostupných logických tříd
		$items = $data['items'];                                             // Seznam čekajících návrhů

		$master_heading = htmlspecialchars($this->phrase('master_heading', [], 'Návrhy čekající na schválení')); // Nadpis levého panelu
		$lbl_filter = htmlspecialchars($this->phrase('lbl_filter_class', [], 'Filtrovat podle logické třídy:')); // Popisek filtru třídy
		$opt_all = htmlspecialchars($this->phrase('opt_all_classes', [], '--- Všechny logické třídy ---')); // Volba všech tříd
		$search_placeholder = htmlspecialchars($this->phrase('placeholder_search', [], 'Hledat v návrzích...')); // Placeholder hledání

		$sel_all = ($this->filter_class === '__ALL__') ? 'selected' : '';    // Označení volby všech tříd
		$options_html = "<option value=\"__ALL__\" {$sel_all}>{$opt_all}</option>"; // Výchozí položka roletky

		foreach ($classes as $c_code => $c_cap) {                            // Sestavení voleb roletky tříd
			$safe_code = htmlspecialchars($c_code);                          // Ošetřený kód třídy
			$safe_cap = htmlspecialchars($c_cap);                            // Ošetřený popisek třídy
			$sel = ($c_code === $this->filter_class) ? 'selected' : '';      // Označení vybrané třídy
			$label = ($safe_cap !== '' AND $safe_cap !== $safe_code) ? "{$safe_code} ({$safe_cap})" : $safe_code; // Text volby
			$options_html .= "<option value=\"{$safe_code}\" {$sel}>{$label}</option>"; // Přidání volby do roletky
		}

		$th_record = htmlspecialchars($this->phrase('th_class_and_record', [], 'Třída / Záznam')); // Záhlaví sloupce záznamu
		$th_author = htmlspecialchars($this->phrase('th_author', [], 'Autor návrhu')); // Záhlaví sloupce autora
		$th_date   = htmlspecialchars($this->phrase('th_date_forwarded', [], 'Předáno')); // Záhlaví sloupce data

		echo <<<HTML
		<div class="md-master-header">
			<h2 style="font-size: 16px; margin: 0 0 10px 0; border: none; padding: 0;">{$master_heading}</h2>
			<div style="margin-bottom: 10px;">
				<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_filter}</label>
				<select onchange="document.location='index.php?page=page_approval&filter_class=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
					{$options_html}
				</select>
			</div>
			<input type="text" id="master-filter" placeholder="{$search_placeholder}" style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>

		<div class="md-master-content">
HTML;

		if (empty($items)) {                                                 // Pokud neexistují žádné návrhy ke schválení
			$msg_empty = htmlspecialchars($this->phrase('msg_no_pending_approvals', [], 'V aktuálním jazyce momentálně nečekají žádné návrhy na schválení.')); // Hláška
			echo "<div class='msg-info'>{$msg_empty}</div></div>";           // Výpis zprávy a uzavření kontejneru
			return;                                                          // Ukončení vykreslování seznamu
		}

		echo <<<HTML
			<table class="md-table">
				<thead>
					<tr>
						<th>{$th_record}</th>
						<th>{$th_author}</th>
						<th style="width: 115px;">{$th_date}</th>
					</tr>
				</thead>
				<tbody id="master-list">
HTML;

		$filter_suffix = ($this->filter_class !== '' AND $this->filter_class !== '__ALL__') ? '&filter_class=' . urlencode($this->filter_class) : ''; // Přívažek filtru

		foreach ($items as $item) {                                          // Vykreslení řádků čekajících návrhů
			$d_uuid = $item['draft_uuid'];                                   // UUID návrhu
			$c_name = $item['class_name'];                                   // Název třídy návrhu
			$is_active = (strcasecmp($d_uuid, $this->draft_uuid) === 0);     // Zda je tento návrh právě otevřen vpravo
			$rowClass = $is_active ? 'md-row-active' : '';                   // CSS třída aktivního řádku
			$rowIdAttr = $is_active ? 'id="active-row"' : '';                // ID aktivního řádku pro scroll

			$row_url = htmlspecialchars("index.php?page=page_approval{$filter_suffix}&target_class=" . urlencode($c_name) . "&draft_uuid=" . urlencode($d_uuid)); // URL detailu
			$safe_cls = htmlspecialchars($item['class_caption']);            // Ošetřený název třídy
			$safe_rec = htmlspecialchars($item['record_label']);             // Ošetřené označení záznamu
			$safe_auth = htmlspecialchars($item['author_info']);             // Ošetřené jméno autora
			$safe_date = htmlspecialchars(date_format4($item['date_modified'], 16)); // Zformátované datum předání

			$comp_badge = '';                                                // Štítek při souběhu více návrhů k témuž záznamu
			if ($item['competing_count'] > 1) {                              // Pokud k záznamu existuje více návrhů
				$comp_tip = htmlspecialchars($this->phrase('tip_competing_proposals', ['count' => $item['competing_count']], 'K tomuto záznamu sešlo {' . chr(36) . 'count} souběžných návrhů')); // Tooltip souběhu
				$comp_badge = "<span class=\"ssc-badge ssc-badge-d\" title=\"{$comp_tip}\">{$item['competing_count']}×</span>"; // Štítek počtu
			}

			echo <<<HTML
					<tr class="{$rowClass}" {$rowIdAttr} style="cursor: pointer;" onclick="document.location='{$row_url}'">
						<td>
							<div style="font-size: 11px; color: #64748b;">{$safe_cls}</div>
							<strong>{$safe_rec}</strong>{$comp_badge}
						</td>
						<td style="font-size: 12px;">{$safe_auth}</td>
						<td style="font-size: 12px; white-space: nowrap;">{$safe_date}</td>
					</tr>
HTML;
		}

		echo <<<HTML
				</tbody>
			</table>
		</div>
		<script>
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
	 * Vykreslí pravý panel s porovnáním původních (schválených) a navrhovaných hodnot
	 * a ovládacími prvky pro schválení nebo vrácení návrhu.
	 */
	protected function render_detail(): void {
		if ($this->target_class === '' OR $this->draft_uuid === '' OR$this->em === null) { // Pokud není vybrán žádný návrh
			$msg_sel = htmlspecialchars($this->phrase('msg_select_proposal_from_left', [], 'Vyberte návrh ke schválení z levého panelu.')); // Výzva
			echo "<div class='msg-info'>{$msg_sel}</div>";                   // Výpis výzvy
			return;                                                          // Ukončení vykreslování detailu
		}

		$em =$this->em;                                                     // Použití již inicializovaného správce entit z předka
		$table =$em->get_storage_table();                                   // Zjištění fyzické tabulky třídy
		if ($table === '') {                                                 // Kontrola platnosti třídy
			$msg_err = htmlspecialchars($this->phrase('msg_invalid_target_class', [], 'Cílová logická třída nebyla nalezena.')); // Chybová hláška
			echo "<div class='msg-err'>{$msg_err}</div>";                    // Výpis chyby
			return;                                                          // Ukončení
		}

		$draft_uuid_sql = guidliteral($this->draft_uuid);                    // SQL literál UUID návrhu
		$q_dr = sqlrun("
			SELECT d.*, dbo.f_get_user_info(d.who_modified) AS author_info
			FROM [{$table}] d
			WHERE d.uuid = {$draft_uuid_sql}
			  AND d.record_type = 'D'
			  AND d.removed = 0
		");                                                                  // Dotaz na vybraný návrh
		$draft_row = fetch($q_dr);                                           // Načtení řádku návrhu
		free_result($q_dr);                                                  // Uvolnění výsledku dotazu

		if (!$draft_row) {                                                   // Pokud návrh v DB již neexistuje
			$msg_nf = htmlspecialchars($this->phrase('msg_proposal_not_found', [], 'Návrh nebyl nalezen nebo již byl zpracován.')); // Hláška
			echo "<div class='msg-err'>{$msg_nf}</div>";                     // Výpis chyby
			return;                                                          // Ukončení
		}

		$orig_raw = (string)$draft_row['original'];                          // Surové UUID originálu záznamu
		$orig_sql = guidliteral($orig_raw);                                  // SQL literál originálu
		$owner_sql = guidliteral((string)$draft_row['object_owner']);        // SQL literál vlastníka záznamu
		$lang_sql = charliteral((string)$draft_row['language'], 2);          // SQL literál jazyka návrhu

		// Načtení současného schváleného stavu ('A'/'L') se zapnutým $ignore_drafts = true
		$sql_approved = $em->build_select_query("m.original = {$orig_sql}", '', true); // Dotaz na schválený stav
		$q_app = sqlrun($sql_approved);                                      // Spuštění dotazu schváleného stavu
		$approved_row = fetch($q_app);                                       // Načtení schválených hodnot
		free_result($q_app);                                                 // Uvolnění dotazu

		$is_new_record = empty($approved_row);                               // Zda jde o návrh zcela nového záznamu

		// Zjištění souběžných návrhů jiných uživatelů pro stejný (original, object_owner, language)
		$competing_list = [];                                                // Pole souběžných návrhů k témuž záznamu
		$q_comp = sqlrun("
			SELECT uuid, date_modified, dbo.f_get_user_info(who_modified) AS author_info
			FROM [{$table}]
			WHERE original = {$orig_sql}
			  AND object_owner = {$owner_sql}
			  AND [language] = {$lang_sql}
			  AND record_type = 'D'
			  AND approval_status = 'F'
			  AND removed = 0
			  AND uuid <> {$draft_uuid_sql}
			ORDER BY date_modified DESC
		");                                                                  // Dotaz na souběžné návrhy
		while ($c_row = fetch($q_comp)) {                                    // Průchod souběžnými návrhy
			$competing_list[] =$c_row;                                      // Přidání souběžného návrhu do seznamu
		}
		free_result($q_comp);                                                // Uvolnění dotazu souběžných návrhů

		$filter_suffix = ($this->filter_class !== '' AND $this->filter_class !== '__ALL__') ? '&filter_class=' . urlencode($this->filter_class) : ''; // Přívažek filtru
		$form_action = htmlspecialchars("index.php?page=page_approval{$filter_suffix}&target_class=" . urlencode($this->target_class) . "&draft_uuid=" . urlencode($this->draft_uuid)); // URL formuláře
		$safe_target_class = htmlspecialchars($this->target_class);          // Ošetřený název třídy
		$safe_draft_uuid = htmlspecialchars($this->draft_uuid);              // Ošetřené UUID návrhu
		$safe_filter = htmlspecialchars($this->filter_class);                // Ošetřený filtr

		$detail_heading = htmlspecialchars($this->phrase('detail_heading', [], 'Posouzení návrhu')); // Nadpis detailu

		$btn_reject = new abstract_button('btn_reject_draft', 'Odmítnout / Vrátit', 'page_approval', '', 'btn-danger'); // Tlačítko odmítnutí
		$btn_reject->set_type('submit')->set_name_value('btn_reject_draft', '1'); // Submit atributy odmítnutí

		$btn_approve = new abstract_button('btn_approve_draft', 'Schválit návrh', 'page_approval', '', 'btn-success'); // Tlačítko schválení
		$btn_approve->set_type('submit')->set_name_value('btn_approve_draft', '1'); // Submit atributy schválení

		$reject_html =$btn_reject->render();                                // HTML tlačítka Odmítnout
		$approve_html =$btn_approve->render();                              // HTML tlačítka Schválit

		echo <<<HTML
		<form method="post" action="{$form_action}" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="filter_class" value="{$safe_filter}">
			<input type="hidden" name="target_class" value="{$safe_target_class}">
			<input type="hidden" name="draft_uuid" value="{$safe_draft_uuid}">

			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">{$detail_heading}</h2>
				<div style="display: flex; gap: 10px; align-items: center;">
					{$reject_html}
					{$approve_html}
				</div>
			</div>

			<div class="md-detail-content">
HTML;

		// Informační box o typu návrhu (Nový záznam vs. Úprava existujícího) a autorovi
		$type_badge =$is_new_record
			? htmlspecialchars($this->phrase('lbl_proposal_new_record', [], 'Návrh nového záznamu (INSERT)'))
			: htmlspecialchars($this->phrase('lbl_proposal_update_record', [], 'Návrh úpravy existujícího záznamu (UPDATE)')); // Text typu změny
		$lbl_author = htmlspecialchars($this->phrase('lbl_proposal_author', [], 'Autor návrhu:')); // Popisek autora
		$lbl_date   = htmlspecialchars($this->phrase('lbl_proposal_date', [], 'Datum předání:')); // Popisek data
		$safe_author = htmlspecialchars((string)($draft_row['author_info'] ?:$draft_row['import_origin'])); // Jméno autora
		$safe_date   = htmlspecialchars(date_format4((string)$draft_row['date_modified'], 16)); // Datum předání

		echo <<<HTML
				<div class="msg-info" style="margin-bottom: 15px;">
					<div><strong>{$type_badge}</strong></div>
					<div style="margin-top: 4px; font-weight: normal; font-size: 12px;">
						<strong>{$lbl_author}</strong> {$safe_author} &nbsp;&#124;&nbsp; <strong>{$lbl_date}</strong> {$safe_date}
					</div>
				</div>
HTML;

		// Upozornění na souběžné návrhy jiných autorů k témuž záznamu
		if (!empty($competing_list)) {                                       // Pokud existují další souběžné návrhy
			$warn_comp = htmlspecialchars($this->phrase('msg_competing_proposals_warning', [], 'Upozornění: K tomuto záznamu existují i další souběžné návrhy. Schválením tohoto návrhu budou ostatní souběžné návrhy automaticky odmítnuty:')); // Varování
			echo "<div class=\"msg-err\" style=\"margin-bottom: 15px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e;\"><div>{$warn_comp}</div><ul style=\"margin: 6px 0 0 20px; padding: 0; font-weight: normal; font-size: 12px;\">"; // Začátek seznamu
			foreach ($competing_list as$comp) {                             // Výpis odkazů na souběžné návrhy
				$c_uuid = (string)$comp['uuid'];                             // UUID souběžného návrhu
				$c_url = htmlspecialchars("index.php?page=page_approval{$filter_suffix}&target_class=" . urlencode($this->target_class) . "&draft_uuid=" . urlencode($c_uuid)); // Odkaz
				$c_auth = htmlspecialchars((string)$comp['author_info']);    // Autor souběžného návrhu
				$c_dt = htmlspecialchars(date_format4((string)$comp['date_modified'], 16)); // Datum souběžného návrhu
				echo "<li><a href=\"{$c_url}\" style=\"color: #004488; font-weight: bold;\">{$c_auth} ({$c_dt})</a></li>"; // Položka seznamu
			}
			echo "</ul></div>\n";                                            // Uzavření seznamu souběžných návrhů
		}

		// Porovnávací tabulka: Položka | Původní schválená hodnota | Navrhovaná hodnota
		$th_field = htmlspecialchars($this->phrase('th_field_name', [], 'Položka (Sloupec)')); // Záhlaví sloupce názvu pole
		$th_old   = htmlspecialchars($this->phrase('th_approved_value', [], 'Původní schválená hodnota')); // Záhlaví původní hodnoty
		$th_new   = htmlspecialchars($this->phrase('th_proposed_value', [], 'Navrhovaná hodnota')); // Záhlaví nové hodnoty
		$txt_none = htmlspecialchars($this->phrase('txt_not_existing_yet', [], '(Nový záznam)')); // Text pro neexistující starou hodnotu

		echo <<<HTML
				<table class="md-table" style="margin-bottom: 20px;">
					<thead>
						<tr>
							<th style="width: 28%;">{$th_field}</th>
							<th style="width: 36%;">{$th_old}</th>
							<th style="width: 36%;">{$th_new}</th>
						</tr>
					</thead>
					<tbody>
HTML;

		$meta_skip = [                                                       // Technické sloupce, které nezobrazujeme v porovnání
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note', 'removed',
			'date_created', 'who_created', 'date_modified', 'who_modified'
		];                                                                   // Konec seznamu technických sloupců

		foreach ($em->get_columns() as $colname =>$meta) {                  // Průchod všemi sloupci logické třídy
			if (in_array($colname, $meta_skip, true) OR !empty($meta['hidden'])) { // Přeskočení skrytých a technických polí
				continue;                                                    // Pokračování na další sloupec
			}

			$label = htmlspecialchars((string)($meta['label'] ?: $meta['caption'] ?:$colname)); // Popisek pole
			$old_val =$is_new_record ? '' : (string)($approved_row[$colname] ?? ''); // Původní schválená hodnota

			// Pokud je v konceptu hodnota NULL (kvůli dědění ze systémového originálu), zobrazíme výslednou efektivní hodnotu
			$raw_draft_val = $draft_row[$colname] ?? null;                   // Surová hodnota v řádku konceptu
			$new_val = ($raw_draft_val === null AND !$is_new_record) ? $old_val : (string)$raw_draft_val; // Efektivní nová hodnota

			$is_changed = ($is_new_record ? ($new_val !== '') : ($old_val !==$new_val)); // Zjištění, zda došlo ke změně hodnoty
			$row_style =$is_changed ? ' style="background-color: #f0fdf4;"' : ''; // Zelené podbarvení změněného řádku
			$new_style =$is_changed ? ' style="font-weight: bold; color: #166534;"' : ''; // Zvýraznění nové hodnoty

			$disp_old =$this->format_comparison_value($meta,$old_val);     // Čitelná původní hodnota
			$disp_new =$this->format_comparison_value($meta,$new_val);     // Čitelná navrhovaná hodnota

			$safe_old =$is_new_record ? "<span style=\"color: #94a3b8; font-style: italic;\">{$txt_none}</span>" : nl2br(htmlspecialchars($disp_old)); // HTML staré hodnoty
			$safe_new = nl2br(htmlspecialchars($disp_new));                  // HTML navrhované hodnoty

			echo <<<HTML
						<tr{$row_style}>
							<td><strong>{$label}</strong> <span style="color: #94a3b8; font-size: 11px;">({$colname})</span></td>
							<td>{$safe_old}</td>
							<td{$new_style}>{$safe_new}</td>
						</tr>
HTML;
		}

		$lbl_note = htmlspecialchars($this->phrase('lbl_approval_note', [], 'Poznámka schvalovatele (důvod vrácení / odmítnutí):')); // Popisek poznámky
		$ph_note  = htmlspecialchars($this->phrase('placeholder_approval_note', [], 'Zadejte důvod v případě vrácení návrhu k přepracování...')); // Placeholder poznámky
		$safe_existing_note = htmlspecialchars((string)($draft_row['approval_note'] ?? '')); // Případná dřívější poznámka

		echo <<<HTML
					</tbody>
				</table>

				<div style="margin-bottom: 20px;">
					<label style="font-weight: bold; display: block; margin-bottom: 6px; color: #004488;">{$lbl_note}</label>
					<textarea name="approval_note" rows="3" placeholder="{$ph_note}" style="width: 100%; padding: 8px; box-sizing: border-box;">{$safe_existing_note}</textarea>
				</div>
			</div>
		</form>
HTML;
	}
}