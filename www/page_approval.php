<?php
/**
 * =============================================================================
 * Verze: 2026-10-27 19:40
 * Soubor: page_approval.php
 * Třída: page_approval
 * Účel: Univerzální schvalovací obrazovka (SSC) pro porovnání původních
 *       a navrhovaných hodnot a jednotlivé i hromadné schvalování či vracení
 *       návrhů napříč logickými třídami.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_approval`.
 * - Dědí z `abstract_page_master_detail`, čímž přebírá kompletní Flexbox dvoupanelový
 *   layout (`.md-master` a `.md-detail`) i asynchronní načítání detailu (`loadDetailPanel`).
 * - Využívá `entity_manager` (inicializovaný v `abstract_page_master_detail::render()`
 *   přes `$this->class_name`) pro načtení metadat cílové logické třídy, získání
 *   původních schválených hodnot (`fetch_row(..., true, true)`) a spuštění
 *   transakčního schválení (`approve_draft()`) nebo vrácení (`reject_draft()`).
 * - Využívá `rich_text` (`rich_text.php`) pro bezpečné vykreslení formátovaných
 *   sloupců (`is_html = 1`, Markdown i HTML) v porovnávací tabulce.
 * - Využívá `abstract_button` a `$this->phrase()` pro plnou lokalizaci.
 * - Načítá návrhy ve stavu `approval_status = 'F'` (`record_type = 'D'`, včetně
 *   návrhů na zrušení záznamu s `removed = 1`), které patří aktuální organizaci
 *   (`dbsession.organization`) a mají stejnou jazykovou verzi jako přihlášený
 *   schvalovatel (`dbsession.language`).
 * - Tabulka `user_organization_access` je z obecného schvalování vyčleněna,
 *   protože podléhá obousměrnému souhlasu (žádost uživatele vs. pozvánka orgadmina)
 *   ve specializovaných modulech `page_org_users` a `page_change_user_context`.
 *
 * Změny:
 * 2026-10-27 19:40 - Náhrada CTE `;WITH fl AS (...)` za indexovanou tabulkovou
 *                    proměnnou `DECLARE @fl TABLE` se `SET NOCOUNT ON`.
 *                  - Napojení řádků v `render_master()` na asynchronní `loadDetailPanel()`
 *                    bez refreshe levého panelu (při zachování funkčnosti checkboxů).
 * 2026-10-26 13:55 - V porovnávací tabulce v render_detail() doplněno vykreslování
 *                    formátovaného textu (Markdown / HTML) pro sloupce s is_html = 1.
 * 2026-10-23 15:15 - Doplněno hromadné schvalování a odmítání vybraných návrhů.
 * =============================================================================
 */

declare(strict_types=1);

if (file_exists(__DIR__ . '/rich_text.php')) {
	require_once __DIR__ . '/rich_text.php';
}

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

		if ($this->target_class !== '' AND $this->target_class !== 'user_organization_access') { // Ochrana proti přímému volání
			$this->class_name = $this->target_class;                         // Předání třídy předkovi pro včasnou inicializaci $this->em
		}
	}

	/**
	 * Zpracuje jednotlivé nebo hromadné schválení či odmítnutí návrhů (PRG vzor).
	 */
	protected function process_save(): void {
		$filter_suffix = ($this->filter_class !== '' AND $this->filter_class !== '__ALL__') ? '&filter_class=' . urlencode($this->filter_class) : ''; // Zachování filtru třídy

		// 1. Hromadné schválení nebo odmítnutí zaškrtnutých návrhů z levého panelu
		$is_bulk_approve = isset($_POST['btn_bulk_approve']);                // Zda schvalovatel klikl na Schválit vybrané
		$is_bulk_reject = isset($_POST['btn_bulk_reject']);                  // Zda schvalovatel klikl na Odmítnout vybrané

		if ($is_bulk_approve OR $is_bulk_reject) {                           // Zpracování hromadné akce
			$selected = $_POST['selected_drafts'] ?? [];                     // Pole vybraných položek ve tvaru "class_name|draft_uuid"
			$bulk_note = trim((string)($_POST['bulk_approval_note'] ?? '')); // Poznámka pro hromadné odmítnutí
			$em_cache = [];                                                  // Keš instancí entity_manageru podle názvu třídy
			$pipe = chr(124);                                                // Oddělovač názvu třídy a UUID návrhu

			if (is_array($selected)) {                                       // Kontrola platného pole vybraných návrhů
				foreach ($selected as $sel_item) {                           // Průchod vybranými návrhy
					$parts = explode($pipe, (string)$sel_item, 2);           // Rozdělení na třídu a UUID návrhu
					if (count($parts) !== 2) {                               // Kontrola kompletní dvojice
						continue;                                            // Přeskočení neplatné položky
					}
					$b_cls = trim($parts[0]);                                // Název logické třídy návrhu
					$b_uuid = trim($parts[1]);                               // Primární klíč (uuid) návrhu
					if ($b_cls === '' OR $b_cls === 'user_organization_access' OR !is_guid($b_uuid)) { // Bezpečnostní kontrola
						continue;                                            // Přeskočení nepovolené třídy nebo neplatného UUID
					}
					if (!isset($em_cache[$b_cls])) {                         // Inicializace správce entit pro danou třídu
						$em_cache[$b_cls] = new entity_manager($b_cls);      // Vytvoření a uložení instance do keše
					}
					if ($is_bulk_approve) {                                  // Hromadné schválení položky
						$em_cache[$b_cls]->approve_draft($b_uuid);           // Schválení návrhu a odmítnutí souběžných
					} else {
						$em_cache[$b_cls]->reject_draft($b_uuid, $bulk_note); // Vrácení návrhu autorovi s poznámkou
					}
				}
			}

			autoredirect("index.php?page=page_approval{$filter_suffix}");    // PRG přesměrování po dokončení hromadné akce
			return;                                                          // Ukončení zpracování
		}

		// 2. Jednotlivé schválení nebo odmítnutí otevřeného návrhu v pravém panelu
		if ($this->target_class === '' OR $this->target_class === 'user_organization_access' OR $this->draft_uuid === '' OR $this->em === null) { // Kontrola cílové třídy
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

		autoredirect("index.php?page=page_approval{$filter_suffix}");        // Přesměrování na vyčištěný seznam ke schválení
	}

	/**
	 * Sestaví SQL podmínku vlastnictví návrhu pro zadanou fyzickou tabulku.
	 * Zohledňuje výjimku tabulky `organization`, kde záznamy vlastní samy sebe (`object_owner = original`).
	 */
	private function get_owner_filter_sql(string $table_name, string $alias = ''): string { // Podmínka vlastníka návrhu
		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$org_raw = (string)($dbsession['organization'] ?? '0x00');           // Surové UUID organizace v relaci
		$org_sql = guidliteral($org_raw);                                    // SQL literál organizace
		$is_sys_org = ($org_raw === '0x00' OR $org_raw === '00000000-0000-0000-0000-000000000000'); // Zda je schvalovatel v 0x00
		$pfx = ($alias !== '') ? "{$alias}." : '';                           // Volitelný prefix tabulkového aliasu

		if ($table_name === 'organization' AND $is_sys_org) {                // V tabulce organization vlastní záznamy samy sebe
			return "({$pfx}object_owner = {$org_sql} OR {$pfx}object_owner = {$pfx}original)"; // Povolení všech organizací v 0x00
		}
		return "{$pfx}object_owner = {$org_sql}";                            // Standardní izolace podle aktivního tenanta
	}

	/**
	 * Načte seznam logických tříd (vázaných na fyzické RAC tabulky) a k nim
	 * všechny čekající návrhy (`record_type = 'D'`, `approval_status = 'F'`, včetně návrhů na `removed = 1`)
	 * pro aktuálního tenanta a aktuální jazyk relace.
	 *
	 * @return array{classes: array<string, string>, items: array<int, array<string, mixed>>}
	 */
	private function load_pending_proposals(): array {
		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka relace
		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace

		$classes = [];                                                       // Mapa dostupných tříd: [class_name => caption]
		$items = [];                                                         // Seznam nalezených návrhů ke schválení

		// 1. Zjištění všech logických tříd (přes indexovanou tabulkovou proměnnou @fl bez CTE)
		$raw_cls = sqlarray_simple("
			SET NOCOUNT ON;
			DECLARE @fl TABLE (
				[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
				fallback_order int NOT NULL
			);
			INSERT INTO @fl ([language], fallback_order)
			SELECT [language], fallback_order FROM dbo.f_language_list({$lang_sql}) WHERE fallback_order < 1000;

			SELECT mc.class_name, COALESCE(tr.caption, mc.caption, mc.class_name) AS caption, mo.builtin_code AS table_name
			FROM meta_class mc
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_type = 'T' AND mo.record_type = 'A' AND mo.removed = 0
			JOIN v_syscolumns sc ON sc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT AND sc.colname = 'draft_author'
			OUTER APPLY (
				SELECT TOP 1 l.caption
				FROM meta_class l
				JOIN @fl fl ON fl.[language] = l.[language]
				WHERE l.original = mc.original
				  AND l.record_type = 'L'
				  AND l.removed = 0
				  AND l.object_owner IN ({$org_sql}, 0x00)
				  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
				ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
			) tr
			WHERE mc.object_owner = 0x00
			  AND mc.record_type = 'A'
			  AND mc.removed = 0
			  AND mc.class_name NOT IN ('sys_global_columns', 'user_organization_access')
			  AND mo.builtin_code <> 'user_organization_access'
			ORDER BY mc.class_name;
		");                                                                  // Načtení všech logických tříd do pole

		$class_rows = [];                                                    // Pomocné pole načtených tříd
		if (is_array($raw_cls)) {                                            // Kontrola platného pole tříd
			foreach ($raw_cls as $r_cls) {                                   // Průchod nalezenými třídami
				$c_name = (string)$r_cls['class_name'];                      // Technický název třídy
				$c_cap = (string)$r_cls['caption'] !== '' ? (string)$r_cls['caption'] : $c_name; // Popisek třídy
				$classes[$c_name] = $c_cap;                                  // Uložení do mapy tříd
				$class_rows[] = [                                            // Uložení definice pro dotazování návrhů
					'class_name' => $c_name,                                 // Název logické třídy
					'caption'    => $c_cap,                                  // Zobrazovaný název třídy
					'table_name' => (string)$r_cls['table_name']             // Fyzická tabulka v DB
				];                                                           // Konec položky třídy
			}
		}

		// 2. Načtení čekajících návrhů ('F') v jednotlivých tabulkách (včetně návrhů s removed = 1)
		foreach ($class_rows as $cr) {                                       // Průchod třídami
			$c_name = $cr['class_name'];                                     // Název aktuální třídy
			if ($this->filter_class !== '__ALL__' AND $this->filter_class !== $c_name) { // Aplikace filtru třídy
				continue;                                                    // Přeskočení nefiltrované třídy
			}

			$tab = $cr['table_name'];                                        // Fyzická tabulka třídy
			$owner_cond_cnt = $this->get_owner_filter_sql($tab, '');         // Podmínka vlastníka bez aliasu
			$owner_cond_d = $this->get_owner_filter_sql($tab, 'd');          // Podmínka vlastníka s aliasem d

			$r_cnt = sqlfirstrow("
				SELECT COUNT(1) AS cnt
				FROM [{$tab}]
				WHERE record_type = 'D'
				  AND approval_status = 'F'
				  AND {$owner_cond_cnt}
				  AND [language] = {$lang_sql}
			");                                                              // Rychlý dotaz na počet čekajících návrhů

			if (empty($r_cnt) OR (int)$r_cnt['cnt'] === 0) {                 // Pokud v tabulce žádné návrhy nečekají
				continue;                                                    // Přechod na další třídu
			}

			// Tabulka obsahuje návrhy -> načteme je do pole přes sqlarray_simple()
			$dr_list = sqlarray_simple("
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
					) AS competing_count
				FROM [{$tab}] d
				WHERE d.record_type = 'D'
				  AND d.approval_status = 'F'
				  AND {$owner_cond_d}
				  AND d.[language] = {$lang_sql}
				ORDER BY d.original, d.date_modified DESC
			");                                                              // Načtení čekajících návrhů v tabulce do pole

			if (is_array($dr_list)) {                                        // Kontrola platného pole návrhů
				foreach ($dr_list as $dr) {                                  // Průchod nalezenými návrhy
					$rec_label = '';                                         // Označení záznamu v seznamu
					foreach (['caption', 'builtin_code', 'class_name', 'column_name', 'login_name', 'value_code'] as $cand) { // Kandidáti popisku
						if (!empty($dr[$cand])) {                            // Pokud je kandidátní sloupec neprázdný
							$rec_label = (string)$dr[$cand];                 // Použití hodnoty jako popisku
							break;                                           // Ukončení hledání popisku
						}
					}
					if ($rec_label === '') {                                 // Fallback pokud nebyl nalezen textový sloupec
						$rec_label = (string)$dr['original'];                // Použití UUID originálu
					}

					$items[] = [                                             // Přidání návrhu do výsledného pole
						'class_name'         => $c_name,                     // Název logické třídy
						'class_caption'      => $cr['caption'],              // Popisek logické třídy
						'draft_uuid'         => (string)$dr['uuid'],         // Primární klíč návrhu
						'original'           => (string)$dr['original'],     // Originální UUID záznamu
						'record_label'       => $rec_label,                  // Zobrazovaný název záznamu
						'author_info'        => (string)($dr['author_info'] ?: $dr['import_origin']), // Autor nebo původ importu
						'date_modified'      => (string)$dr['date_modified'], // Datum postoupení ke schválení
						'competing_count'    => (int)$dr['competing_count'], // Počet návrhů pro stejný original
						'is_remove_proposal' => !empty($dr['removed'])       // Zda návrh požaduje zrušení záznamu (removed = 1)
					];                                                       // Konec položky návrhu
				}
			}
		}

		return ['classes' => $classes, 'items' => $items];                   // Vrácení tříd a nalezených návrhů
	}

	/**
	 * Převede databázovou hodnotu sloupce na čitelný řetězec pro porovnávací tabulku
	 * (překlad checkboxů 0/1, úrovně licence, položek z meta_codetable a vazeb referenced_class).
	 */
	private function format_comparison_value(array $meta, string $raw_val): string { // Formátování hodnoty pro porovnání
		if ($raw_val === '') {                                               // Prázdná hodnota zůstává prázdná
			return '';                                                       // Vrácení prázdného řetězce
		}

		global $dbsession;                                                   // Globální kontext relace
		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace
		$lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka relace

		$col_name = (string)($meta['column_name'] ?? '');                    // Technický název sloupce
		$type = (string)($meta['input_type'] ?? 'text');                     // Typ formulářového prvku sloupce

		if ($type === 'checkbox' OR $col_name === 'removed') {               // Překlad bitové hodnoty checkboxu
			$is_true = ($raw_val === '1' OR strtolower($raw_val) === 'true'); // Vyhodnocení pravdivostní hodnoty
			$yes_txt = $this->phrase('val_checkbox_yes', [], 'Ano');         // Lokalizované Ano
			$no_txt = $this->phrase('val_checkbox_no', [], 'Ne');            // Lokalizované Ne
			return $is_true ? "{$yes_txt} (1)" : "{$no_txt} (0)";            // Čitelný výpis stavu checkboxu
		}

		if ($col_name === 'licence_level' AND is_numeric($raw_val)) {        // Překlad číselníku úrovní licencí
			$lvl_int = (int)$raw_val;                                        // Číselná hodnota úrovně licence
			$r_lvl = sqlfirstrow("SELECT TOP 1 name FROM licence_level WHERE licence_level = {$lvl_int}"); // Dotaz na název úrovně
			if (!empty($r_lvl) AND (string)$r_lvl['name'] !== '') {          // Pokud byl název úrovně nalezen
				return (string)$r_lvl['name'] . " [{$lvl_int}]";             // Výpis názvu i číselného kódu
			}
		}

		if (!empty($meta['referenced_codetable'])) {                         // Překlad kódu z číselníku meta_codetable s lokalizací
			$safe_ct = charliteral((string)$meta['referenced_codetable']);   // SQL literál názvu číselníku
			$safe_val = charliteral($raw_val);                               // SQL literál hodnoty číselníku
			$r_ct = sqlfirstrow("
				SET NOCOUNT ON;
				DECLARE @fl TABLE (
					[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
					fallback_order int NOT NULL
				);
				INSERT INTO @fl ([language], fallback_order)
				SELECT [language], fallback_order FROM dbo.f_language_list({$lang_sql}) WHERE fallback_order < 1000;

				SELECT TOP 1 COALESCE(tr.caption, c.caption, '') AS caption
				FROM meta_codetable c
				OUTER APPLY (
					SELECT TOP 1 l.caption
					FROM meta_codetable l
					JOIN @fl fl ON fl.[language] = l.[language]
					WHERE l.original = c.original
					  AND l.record_type = 'L'
					  AND l.removed = 0
					  AND l.object_owner IN ({$org_sql}, 0x00)
					  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
					ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
				) tr
				WHERE c.codetable_name = {$safe_ct}
				  AND c.value_code = {$safe_val}
				  AND c.object_owner IN ({$org_sql}, 0x00)
				  AND c.record_type = 'A'
				  AND c.removed = 0
				ORDER BY CASE WHEN c.object_owner = {$org_sql} THEN 0 ELSE 1 END;
			");                                                              // Dotaz na lokalizovaný popisek číselníku
			if (!empty($r_ct) AND (string)$r_ct['caption'] !== '') {         // Pokud byl nalezen popisek v číselníku
				return (string)$r_ct['caption'] . " [{$raw_val}]";           // Výpis popisku i kódu
			}
		}

		if (!empty($meta['referenced_class']) AND is_guid($raw_val)) {       // Překlad relačního odkazu referenced_class s lokalizací
			$ref_cls_sql = guidliteral((string)$meta['referenced_class']);   // SQL literál odkazované třídy
			$target_sql = guidliteral($raw_val);                             // SQL literál cílového záznamu
			$r_rc = sqlfirstrow("
				SELECT mo.builtin_code AS ref_table
				FROM meta_class mc
				JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
				WHERE mc.original = {$ref_cls_sql} AND mc.object_owner = 0x00 AND mc.record_type = 'A' AND mc.removed = 0
			");                                                              // Zjištění cílové fyzické tabulky

			if (!empty($r_rc) AND !empty($r_rc['ref_table'])) {              // Pokud cílová tabulka existuje
				$ref_tab = (string)$r_rc['ref_table'];                       // Název odkazované tabulky
				$t_row = sqlfirstrow("
					SET NOCOUNT ON;
					DECLARE @fl TABLE (
						[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
						fallback_order int NOT NULL
					);
					INSERT INTO @fl ([language], fallback_order)
					SELECT [language], fallback_order FROM dbo.f_language_list({$lang_sql}) WHERE fallback_order < 1000;

					SELECT TOP 1 a.*, tr.caption AS trans_caption
					FROM [{$ref_tab}] a
					OUTER APPLY (
						SELECT TOP 1 l.caption
						FROM [{$ref_tab}] l
						JOIN @fl fl ON fl.[language] = l.[language]
						WHERE l.original = a.original
						  AND l.record_type = 'L'
						  AND l.removed = 0
						  AND (l.object_owner IN ({$org_sql}, 0x00) OR l.object_owner = l.original)
						  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
						ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
					) tr
					WHERE a.original = {$target_sql}
					  AND (a.object_owner IN ({$org_sql}, 0x00) OR a.object_owner = a.original)
					  AND a.record_type = 'A'
					  AND a.removed = 0
					ORDER BY CASE WHEN a.object_owner = {$org_sql} THEN 0 ELSE 1 END;
				");                                                          // Načtení cílového řádku s překladem a izolací tenanta
				if (!empty($t_row)) {                                        // Sestavení čitelného popisku cílového záznamu
					$cap = (string)($t_row['trans_caption'] ?? $t_row['caption'] ?? ''); // Lokalizovaný popisek cíle
					foreach (['class_name', 'builtin_code', 'column_name', 'caption'] as $c_col) { // Hledání vhodného sloupce
						if (!empty($t_row[$c_col])) {                        // Pokud sloupec obsahuje hodnotu
							$code = ($c_col === 'caption' AND $cap !== '') ? $cap : (string)$t_row[$c_col]; // Kód záznamu
							return ($cap !== '' AND $cap !== $code) ? "{$code} ({$cap})" : $code; // Čitelný název cíle
						}
					}
				}
			}
		}

		return $raw_val;                                                     // Výchozí vrácení původního textu
	}

	/**
	 * Vykreslí buňku porovnávací tabulky pro formátovaný sloupec (`is_html = 1`)
	 * s bezpečně vyrenderovaným HTML výstupem a rozbalovacím náhledem zdrojového kódu (Markdown / HTML).
	 */
	private function render_formatted_comparison_cell(string $raw_text): string { // Vykreslení buňky s is_html = 1
		if (trim($raw_text) === '') {                                        // Prázdný text nevyžaduje vykreslování
			return '';                                                       // Vrácení prázdného řetězce
		}

		$rendered_html = '';                                                 // Vykreslený HTML obsah
		$fmt_badge = '';                                                     // Štítek rozpoznaného formátu (MD / HTML)
		if (class_exists('rich_text')) {                                     // Pokud je třída rich_text k dispozici
			if (method_exists('rich_text', 'detect_format')) {               // Zjištění formátu textu
				$det = (string)rich_text::detect_format($raw_text);          // Detekovaný formát ('markdown' nebo 'html')
				$fmt_label = ($det === 'html') ? 'HTML' : 'MD';              // Zkratka formátu do štítku
				$fmt_badge = "<span style=\"float: right; font-size: 10px; background: #e2e8f0; color: #334155; padding: 1px 5px; border-radius: 3px; font-family: monospace;\">{$fmt_label}</span>"; // Štítek
			}
			if (method_exists('rich_text', 'to_html')) {                     // Převod na bezpečné HTML přes to_html()
				$rendered_html = (string)rich_text::to_html($raw_text);      // Vyrenderované HTML
			} elseif (method_exists('rich_text', 'render_formatted')) {      // Fallback na render_formatted()
				$rendered_html = (string)rich_text::render_formatted($raw_text, false); // Vyrenderované HTML
			}
		}

		if ($rendered_html === '') {                                         // Nouzový fallback pokud rich_text není dostupný
			return nl2br(htmlspecialchars($raw_text));                       // Klasický escapovaný výpis
		}

		$lbl_src = htmlspecialchars($this->phrase('lbl_show_raw_source', [], 'Zobrazit zdrojový text (Markdown / HTML)')); // Popisek rozbalení zdroje
		$safe_raw = htmlspecialchars($raw_text);                             // Ošetřený zdrojový kód

		return "<div class=\"bcm-rt-Rendered\">{$fmt_badge}{$rendered_html}</div>"
			. "<details style=\"margin-top: 6px; font-size: 11px; color: #64748b;\">"
			. "<summary style=\"cursor: pointer; user-select: none;\">{$lbl_src}</summary>"
			. "<pre style=\"margin: 4px 0 0 0; padding: 6px; background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 3px; white-space: pre-wrap; word-break: break-word; font-family: monospace; color: #334155;\">{$safe_raw}</pre>"
			. "</details>";                                                  // Složená buňka s náhledem a zdrojem
	}

	/**
	 * Vykreslí levý panel se seznamem všech návrhů čekajících na schválení ('F')
	 * a ovládací lištou pro hromadné schválení nebo odmítnutí vybraných položek.
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
		$tip_sel_all = htmlspecialchars($this->phrase('tip_select_all_proposals', [], 'Označit / odznačit všechny zobrazené návrhy')); // Tooltip hromadného výběru

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
HTML;

		if (empty($items)) {                                                 // Pokud neexistují žádné návrhy ke schválení
			$msg_empty = htmlspecialchars($this->phrase('msg_no_pending_approvals', [], 'V aktuálním jazyce momentálně nečekají žádné návrhy na schválení.')); // Hláška
			echo "<div class=\"md-master-content\"><div class='msg-info'>{$msg_empty}</div></div>"; // Výpis zprávy
			return;                                                          // Ukončení vykreslování seznamu
		}

		$filter_suffix = ($this->filter_class !== '' AND $this->filter_class !== '__ALL__') ? '&filter_class=' . urlencode($this->filter_class) : ''; // Přívažek filtru
		$bulk_action_url = htmlspecialchars("index.php?page=page_approval{$filter_suffix}"); // Cílová URL pro hromadný formulář
		$safe_filter = htmlspecialchars($this->filter_class);                // Ošetřený filtr pro skryté pole
		$ph_bulk_note = htmlspecialchars($this->phrase('ph_bulk_approval_note', [], 'Důvod při hromadném odmítnutí...')); // Placeholder hromadné poznámky
		$msg_no_sel = addslashes($this->phrase('msg_select_at_least_one', [], 'Zaškrtněte prosím alespoň jeden návrh v seznamu.')); // JS výzva při prázdném výběru
		$badge_rem_prop = htmlspecialchars($this->phrase('badge_remove_proposal', [], 'Zrušení')); // Štítek návrhu na zrušení

		$btn_bulk_app = new abstract_button('btn_bulk_approve', 'Schválit vybrané', 'page_approval', '', 'btn-success'); // Tlačítko hromadného schválení
		$btn_bulk_app->set_type('submit')                                    // Nastavení typu submit
			->set_name_value('btn_bulk_approve', '1')                        // Atributy name a value
			->set_style('padding: 6px 10px; font-size: 12px;')               // Kompaktní velikost tlačítka
			->set_onclick("if(document.querySelectorAll('.chk-draft-item:checked').length===0){alert('{$msg_no_sel}');return false;}"); // Kontrola zaškrtnutí

		$btn_bulk_rej = new abstract_button('btn_bulk_reject', 'Odmítnout vybrané', 'page_approval', '', 'btn-danger'); // Tlačítko hromadného odmítnutí
		$btn_bulk_rej->set_type('submit')                                    // Nastavení typu submit
			->set_name_value('btn_bulk_reject', '1')                         // Atributy name a value
			->set_style('padding: 6px 10px; font-size: 12px;')               // Kompaktní velikost tlačítka
			->set_onclick("if(document.querySelectorAll('.chk-draft-item:checked').length===0){alert('{$msg_no_sel}');return false;}"); // Kontrola zaškrtnutí

		$bulk_app_html = $btn_bulk_app->render();                            // HTML tlačítka Schválit vybrané
		$bulk_rej_html = $btn_bulk_rej->render();                            // HTML tlačítka Odmítnout vybrané

		echo <<<HTML
		<form method="post" action="{$bulk_action_url}" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="filter_class" value="{$safe_filter}">
			<div style="display: flex; gap: 6px; align-items: center; margin-bottom: 8px; flex-wrap: wrap;">
				{$bulk_app_html}
				{$bulk_rej_html}
				<input type="text" name="bulk_approval_note" placeholder="{$ph_bulk_note}" style="flex: 1; min-width: 140px; padding: 5px 6px; font-size: 12px; box-sizing: border-box;">
			</div>

			<div class="md-master-content">
				<table class="md-table">
					<thead>
						<tr>
							<th style="width: 26px; text-align: center;">
								<input type="checkbox" id="chk-select-all" title="{$tip_sel_all}" style="cursor: pointer;" onchange="document.querySelectorAll('#master-list tr').forEach(function(r){if(r.style.display!=='none'){var c=r.querySelector('.chk-draft-item');if(c)c.checked=this.checked;}}.bind(this));">
							</th>
							<th>{$th_record}</th>
							<th>{$th_author}</th>
							<th style="width: 110px;">{$th_date}</th>
						</tr>
					</thead>
					<tbody id="master-list">
HTML;

		$pipe = chr(124);                                                    // Znak svislítka pro složení hodnoty checkboxu

		foreach ($items as $item) {                                          // Vykreslení řádků čekajících návrhů
			$d_uuid = $item['draft_uuid'];                                   // UUID návrhu
			$c_name = $item['class_name'];                                   // Název třídy návrhu
			$is_active = (strcasecmp($d_uuid, $this->draft_uuid) === 0);     // Zda je tento návrh právě otevřen vpravo
			$rowClass = $is_active ? 'md-row-active' : '';                   // CSS třída aktivního řádku
			$rowIdAttr = $is_active ? 'id="active-row"' : '';                // ID aktivního řádku pro scroll

			$row_url = htmlspecialchars("index.php?page=page_approval{$filter_suffix}&target_class=" . urlencode($c_name) . "&draft_uuid=" . urlencode($d_uuid)); // URL detailu
			$safe_d_uuid = htmlspecialchars($d_uuid);                        // Ošetřené UUID návrhu pro data-uuid
			$safe_bulk_val = htmlspecialchars($c_name . $pipe . $d_uuid);    // Hodnota pro hromadné zpracování
			$safe_cls = htmlspecialchars($item['class_caption']);            // Ošetřený název třídy
			$safe_rec = htmlspecialchars($item['record_label']);             // Ošetřené označení záznamu
			$safe_auth = htmlspecialchars($item['author_info']);             // Ošetřené jméno autora
			$safe_date = htmlspecialchars(date_format4($item['date_modified'], 16)); // Zformátované datum předání

			$badges_html = '';                                               // Štítky ke stavu návrhu
			if (!empty($item['is_remove_proposal'])) {                       // Pokud návrh požaduje zrušení záznamu (removed = 1)
				$badges_html .= "<span class=\"ssc-badge ssc-badge-rem\">{$badge_rem_prop}</span>"; // Červený štítek Zrušení
			}
			if ($item['competing_count'] > 1) {                              // Pokud k záznamu existuje více návrhů
				$comp_tip = htmlspecialchars($this->phrase('tip_competing_proposals', ['count' => $item['competing_count']], 'K tomuto záznamu sešlo {' . chr(36) . 'count} souběžných návrhů')); // Tooltip souběhu
				$badges_html .= "<span class=\"ssc-badge ssc-badge-d\" title=\"{$comp_tip}\">{$item['competing_count']}×</span>"; // Štítek počtu
			}

			echo <<<HTML
						<tr class="{$rowClass}" {$rowIdAttr} data-uuid="{$safe_d_uuid}" data-row-url="{$row_url}" style="cursor: pointer;" onclick="if (window.loadDetailPanel) { window.loadDetailPanel('{$row_url}', this); } else { document.location='{$row_url}'; }">
							<td style="text-align: center;" onclick="event.stopPropagation();">
								<input type="checkbox" class="chk-draft-item" name="selected_drafts[]" value="{$safe_bulk_val}" style="cursor: pointer;">
							</td>
							<td>
								<div style="font-size: 11px; color: #64748b;">{$safe_cls}</div>
								<strong>{$safe_rec}</strong>{$badges_html}
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
		</form>
HTML;
	}

	/**
	 * Vykreslí pravý panel s porovnáním původních (schválených) a navrhovaných hodnot
	 * a ovládacími prvky pro schválení nebo vrácení návrhu.
	 */
	protected function render_detail(): void {
		if ($this->target_class === '' OR $this->draft_uuid === '' OR $this->em === null) { // Pokud není vybrán žádný návrh
			$msg_sel = htmlspecialchars($this->phrase('msg_select_proposal_from_left', [], 'Vyberte návrh ke schválení z levého panelu.')); // Výzva
			echo "<div class='msg-info'>{$msg_sel}</div>";                   // Výpis výzvy
			return;                                                          // Ukončení vykreslování detailu
		}

		$em = $this->em;                                                     // Použití již inicializovaného správce entit z předka
		$table = $em->get_storage_table();                                   // Zjištění fyzické tabulky třídy
		if ($table === '') {                                                 // Kontrola platnosti třídy
			$msg_err = htmlspecialchars($this->phrase('msg_invalid_target_class', [], 'Cílová logická třída nebyla nalezena.')); // Chybová hláška
			echo "<div class='msg-err'>{$msg_err}</div>";                    // Výpis chyby
			return;                                                          // Ukončení
		}

		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$sess_lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka relace
		$owner_cond_d = $this->get_owner_filter_sql($table, 'd');            // Striktní podmínka vlastnictví návrhu

		$draft_uuid_sql = guidliteral($this->draft_uuid);                    // SQL literál UUID návrhu
		$draft_row = sqlfirstrow("
			SELECT d.*, dbo.f_get_user_info(d.who_modified) AS author_info
			FROM [{$table}] d
			WHERE d.uuid = {$draft_uuid_sql}
			  AND d.record_type = 'D'
			  AND d.approval_status = 'F'
			  AND {$owner_cond_d}
			  AND d.[language] = {$sess_lang_sql}
		");                                                                  // Načtení vybraného návrhu (včetně návrhu s removed = 1)

		if (empty($draft_row)) {                                             // Pokud návrh v DB již neexistuje nebo nepatří tenantovi
			$msg_nf = htmlspecialchars($this->phrase('msg_proposal_not_found', [], 'Návrh nebyl nalezen nebo již byl zpracován.')); // Hláška
			echo "<div class='msg-err'>{$msg_nf}</div>";                     // Výpis chyby
			return;                                                          // Ukončení
		}

		$orig_raw = (string)$draft_row['original'];                          // Surové UUID originálu záznamu
		$orig_sql = guidliteral($orig_raw);                                  // SQL literál originálu
		$owner_sql = guidliteral((string)$draft_row['object_owner']);        // SQL literál vlastníka záznamu
		$lang_sql = charliteral((string)$draft_row['language'], 2);          // SQL literál jazyka návrhu

		// Načtení současného schváleného stavu ('A'/'L') se zapnutým $ignore_drafts = true a $show_removed = true
		$where_app = "m.original = {$orig_sql}";                             // Podmínka pro načtení schváleného stavu
		$approved_row = $em->fetch_row($where_app, true, true);              // Načtení schváleného záznamu (i zrušeného při návrhu obnovy)

		$is_new_record = empty($approved_row);                               // Zda jde o návrh zcela nového záznamu
		$is_sec_lang = (!$is_new_record AND (string)($approved_row['language'] ?? 'cs') !== (string)$draft_row['language']); // Zda jde o překlad v sekundárním jazyce

		// Zjištění souběžných návrhů jiných uživatelů pro stejný (original, object_owner, language)
		$competing_list = sqlarray_simple("
			SELECT uuid, date_modified, dbo.f_get_user_info(who_modified) AS author_info
			FROM [{$table}]
			WHERE original = {$orig_sql}
			  AND object_owner = {$owner_sql}
			  AND [language] = {$lang_sql}
			  AND record_type = 'D'
			  AND approval_status = 'F'
			  AND uuid <> {$draft_uuid_sql}
			ORDER BY date_modified DESC
		");                                                                  // Načtení souběžných návrhů do pole

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

		$reject_html = $btn_reject->render();                                // HTML tlačítka Odmítnout
		$approve_html = $btn_approve->render();                              // HTML tlačítka Schválit

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
		$type_badge = $is_new_record
			? htmlspecialchars($this->phrase('lbl_proposal_new_record', [], 'Návrh nového záznamu (INSERT)'))
			: htmlspecialchars($this->phrase('lbl_proposal_update_record', [], 'Návrh úpravy existujícího záznamu (UPDATE)')); // Text typu změny
		$lbl_author = htmlspecialchars($this->phrase('lbl_proposal_author', [], 'Autor návrhu:')); // Popisek autora
		$lbl_date   = htmlspecialchars($this->phrase('lbl_proposal_date', [], 'Datum předání:')); // Popisek data
		$safe_author = htmlspecialchars((string)($draft_row['author_info'] ?: $draft_row['import_origin'])); // Jméno autora
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
		if (is_array($competing_list) AND !empty($competing_list)) {         // Pokud existují další souběžné návrhy
			$warn_comp = htmlspecialchars($this->phrase('msg_competing_proposals_warning', [], 'Upozornění: K tomuto záznamu existují i další souběžné návrhy. Schválením tohoto návrhu budou ostatní souběžné návrhy automaticky odmítnuty:')); // Varování
			echo "<div class=\"msg-err\" style=\"margin-bottom: 15px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e;\"><div>{$warn_comp}</div><ul style=\"margin: 6px 0 0 20px; padding: 0; font-weight: normal; font-size: 12px;\">"; // Začátek seznamu
			foreach ($competing_list as $comp) {                             // Výpis odkazů na souběžné návrhy
				$c_uuid = (string)$comp['uuid'];                             // UUID souběžného návrhu
				$c_url = htmlspecialchars("index.php?page=page_approval{$filter_suffix}&target_class=" . urlencode($this->target_class) . "&draft_uuid=" . urlencode($c_uuid)); // Odkaz
				$c_auth = htmlspecialchars((string)$comp['author_info']);    // Autor souběžného návrhu
				$c_dt = htmlspecialchars(date_format4((string)$comp['date_modified'], 16)); // Datum souběžného návrhu
				echo "<li><a href=\"{$c_url}\" onclick=\"if(window.loadDetailPanel){window.loadDetailPanel('{$c_url}');return false;}\" style=\"color: #004488; font-weight: bold;\">{$c_auth} ({$c_dt})</a></li>"; // Položka seznamu
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

		$meta_skip = [                                                       // Technické sloupce, které nezobrazujeme v porovnání (removed je povoleno)
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note',
			'date_created', 'who_created', 'date_modified', 'who_modified'
		];                                                                   // Konec seznamu technických sloupců

		foreach ($em->get_columns() as $colname => $meta) {                  // Průchod všemi sloupci logické třídy
			if (in_array($colname, $meta_skip, true) OR (!empty($meta['hidden']) AND $colname !== 'removed')) { // Přeskočení skrytých polí kromě removed
				continue;                                                    // Pokračování na další sloupec
			}

			$label = htmlspecialchars((string)($meta['label'] ?: $meta['caption'] ?: $colname)); // Popisek pole
			if ($colname === 'removed') {                                    // Vyhodnocení původního stavu sloupce removed
				$old_val = $is_new_record ? '0' : ($is_sec_lang ? (string)($approved_row['l_removed'] ?? '0') : (string)($approved_row['removed'] ?? '0')); // Stav removed v A nebo L
			} else {
				$old_val = $is_new_record ? '' : (string)($approved_row[$colname] ?? ''); // Původní schválená hodnota sloupce
			}

			$raw_draft_val = $draft_row[$colname] ?? null;                   // Surová hodnota v řádku konceptu
			$new_val = ($raw_draft_val === null AND !$is_new_record) ? $old_val : (string)$raw_draft_val; // Efektivní nová hodnota

			$is_changed = ($is_new_record ? ($new_val !== '' AND !($colname === 'removed' AND $new_val === '0')) : ($old_val !== $new_val)); // Zjištění změny hodnoty
			$is_rem_row = ($colname === 'removed' AND $is_changed);          // Zvýraznění změny příznaku removed
			$row_style = $is_rem_row ? ' style="background-color: #fef2f2;"' : ($is_changed ? ' style="background-color: #f0fdf4;"' : ''); // Podbarvení řádku
			$new_style = $is_rem_row ? ' style="font-weight: bold; color: #991b1b;"' : ($is_changed ? ' style="font-weight: bold; color: #166534;"' : ''); // Barva nové hodnoty

			if (!empty($meta['is_html'])) {                                  // Vykreslení formátovaného sloupce (Markdown / HTML)
				$safe_old = $is_new_record
					? "<span style=\"color: #94a3b8; font-style: italic;\">{$txt_none}</span>"
					: $this->render_formatted_comparison_cell($old_val);     // Formátovaná původní hodnota
				$safe_new = $this->render_formatted_comparison_cell($new_val); // Formátovaná navrhovaná hodnota
			} else {
				$disp_old = $this->format_comparison_value($meta, $old_val); // Čitelná původní hodnota
				$disp_new = $this->format_comparison_value($meta, $new_val); // Čitelná navrhovaná hodnota

				$safe_old = $is_new_record ? "<span style=\"color: #94a3b8; font-style: italic;\">{$txt_none}</span>" : nl2br(htmlspecialchars($disp_old)); // HTML staré hodnoty
				$safe_new = nl2br(htmlspecialchars($disp_new));              // HTML navrhované hodnoty
			}

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