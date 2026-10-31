<?php
/**
 * =============================================================================
 * Verze: 2026-10-31 16:15
 * Soubor: entity_manager_write.php
 * Trait: entity_manager_write
 * Účel: Zápisová, validační, klonovací a schvalovací (SSC) část třídy entity_manager.
 *       Vyčleněno ze souboru entity_manager.php pro snížení velikosti souboru
 *       a přehledné oddělení čtecí/UI logiky od transakčního zápisu do DB.
 *
 * VAZBY NA OKOLÍ:
 * - Inkludován a používán výhradně uvnitř třídy `entity_manager` (`entity_manager.php`).
 * - Využívá vlastnosti třídy `entity_manager` (`storage_table`, `physical_cols`,
 *   `col_types`, `col_nulls`, `columns_meta`, `class_meta`, `is_initialized`)
 *   a její metody `phrase()`, `is_metadata_entity()`, `get_original_key_columns()`,
 *   `is_hierarchy_node_locked()` a `evaluate_remove_permission()`.
 * - Využívá třídu `rich_text` (`rich_text.php`) pro normalizaci, konverzi (Markdown ⇄ HTML)
 *   a bezpečnostní sanitizaci formátovaných sloupců (`is_html = 1`) při ukládání z POSTu.
 * - Volán z `abstract_page_master_detail::process_save()` a `page_approval::process_save()`.
 *
 * KLÍČOVÉ KONCEPTY:
 * 1. Validace neprázdnosti a unikátnosti klíčových sloupců (meta_original_keys / link)
 *    Při zakládání nového záznamu (`update_guid === ''`) se oříznou okrajové mezery
 *    klíčových položek, ověří se jejich neprázdnost a před INSERTem se otestuje,
 *    že v databázi neexistují shodné klíčové údaje vedoucí k výpočtu duplicitního
 *    originálu (včetně kontroly záznamů v koši `removed = 1` a kolize `hierarchy.builtin_code`
 *    s `meta_class.class_name`). Chybové hlášení lze načíst metodou `get_last_save_error()`.
 * 2. Asymetrický zápis překladů (right_translate) a symetrie A-L
 *    Společně se zápisem do 'A' záznamu se vždy udržuje symetrický 'L' záznam.
 * 3. Klonování s modifikací (Override vzor)
 *    Pomocí metod `insert_from_map()` a `clone_with_map()` zakládá kompletní kopii
 *    systémového záznamu, ve které nahradí upravené hodnoty.
 * 4. Ochrana klíčových sloupců a uzamčených větví hierarchií
 *    U existujícího záznamu (update_guid !== '') jsou klíčové sloupce při UPDATE
 *    odfiltrovány, aby nikdy nemohlo dojít k nekonzistenci vůči deterministickému originálu.
 *    U uzamčených větví hierarchie (`is_hierarchy_node_locked`) je blokována změna
 *    `parent_uuid` a zrušení `is_leaf = 1`.
 * 5. Automatická synchronizace odvozených vazeb v `link`
 *    Po uložení/schválení vazby v `link` spouští `p_sync_derived_links @root_link_original`.
 *
 * Změny:
 * 2026-10-31 16:15 - Doplněno ořezávání (`trim`) klíčových sloupců v `extract_post_data()`.
 *                  - Do `save_post_data()` doplněna předběžná kontrola neprázdnosti
 *                    klíčových sloupců (`meta_original_keys`, `link`) a databázový test
 *                    unikátnosti klíčových údajů / `original` před provedením příkazu INSERT.
 *                  - Doplněny metody `set_save_error()` a `get_last_save_error()` pro čisté
 *                    zobrazení validační chyby v detailu bez pádu do `fatal_error()`.
 * 2026-10-31 11:00 - Oprava Delta porovnání s $baseline_row v save_post_data() pouze pro meta_*.
 * =============================================================================
 */

declare(strict_types=1);

if (file_exists(__DIR__ . '/rich_text.php')) {
	require_once __DIR__ . '/rich_text.php';
}

trait entity_manager_write {

	/**
	 * Uloží chybovou zprávu z validace zápisu pro zobrazení v UI formuláři.
	 */
	private function set_save_error(string $msg): void {                     // Nastavení chybové zprávy při ukládání
		$GLOBALS['em_last_save_error'] = $msg;                               // Uložení chyby do globálního kontextu
		if (property_exists($this, 'last_save_error')) {                     // Kontrola existence vlastnosti v objektu
			$this->last_save_error = $msg;                                   // Zápis chyby přímo do vlastnosti instance
		}
	}

	/**
	 * Vrátí poslední chybovou zprávu vzniklou při validaci v save_post_data() (nebo '' pokud zápis prošel).
	 */
	public function get_last_save_error(): string {                          // Získání poslední chyby při ukládání
		if (property_exists($this, 'last_save_error') AND $this->last_save_error !== '') { // Kontrola vlastnosti instance
			return (string)$this->last_save_error;                           // Vrácení chyby z vlastnosti instance
		}
		return (string)($GLOBALS['em_last_save_error'] ?? '');               // Vrácení chyby z globálního kontextu
	}

	/**
	 * Převede SQL literál (např. `'hodnota'` nebo `'NULL'`) zpět na čistou textovou hodnotu pro validaci.
	 */
	private function unquote_sql_literal(string $sql_lit): string {          // Odstranění SQL apostrofů pro validaci
		$trimmed = trim($sql_lit);                                           // Oříznutí bílých znaků kolem literálu
		if ($trimmed === '' OR strtoupper($trimmed) === 'NULL' OR strtolower($trimmed) === '0x00') { // Prázdný literál
			return '';                                                       // Vrácení prázdného řetězce
		}
		if (strlen($trimmed) >= 2 AND str_starts_with($trimmed, "'") AND str_ends_with($trimmed, "'")) { // Text v apostrofech
			$inner = substr($trimmed, 1, -1);                                // Odříznutí vnějších apostrofů
			return trim(str_replace("''", "'", $inner));                     // Odzdvojení vnitřních apostrofů a ořez mezer
		}
		return $trimmed;                                                     // Číselný nebo jiný literál
	}

	/**
	 * Sestaví a spustí příkaz INSERT INTO ... VALUES (...) vyfiltrováním předané mapy
	 * sloupců a SQL výrazů proti skutečným fyzickým sloupcům tabulky (physical_cols).
	 */
	private function insert_from_map(array $row_map): void {                 // Vložení nového záznamu podle mapy sloupců
		$ins_cols = [];                                                      // Seznam vkládaných fyzických sloupců
		$ins_vals = [];                                                      // Seznam odpovídajících SQL hodnot
		foreach ($this->physical_cols as $col) {                             // Průchod fyzickými sloupci tabulky
			if (array_key_exists($col, $row_map)) {                          // Zařazení sloupce, pokud je v mapě definován
				$ins_cols[] = "[$col]";                                      // Název fyzického sloupce v závorkách
				$ins_vals[] = (string)$row_map[$col];                        // SQL literál nebo výraz hodnoty
			}
		}
		$sql = "INSERT INTO {$this->storage_table} (" . implode(', ', $ins_cols) . ") VALUES (" . implode(', ', $ins_vals) . ")"; // Sestavení SQL příkazu INSERT
		sqlrun($sql);                                                        // Provedení příkazu INSERT
	}

	/**
	 * Sestaví a spustí klonovací příkaz INSERT INTO ... SELECT ... FROM ...
	 * Sloupce uvedené v override_map nahradí zadaným SQL výrazem, ostatní fyzické
	 * sloupce převezme beze změny ze zdrojového řádku.
	 */
	private function clone_with_map(array $override_map, string $where_sql, string $top_sql = '', string $order_sql = ''): void { // Klonování záznamu s modifikací
		$ins_cols = [];                                                      // Cílové sloupce klonovaného záznamu
		$sel_vals = [];                                                      // Výrazy v SELECT klauzuli klonu
		foreach ($this->physical_cols as $col) {                             // Průchod všemi fyzickými sloupci tabulky
			$ins_cols[] = "[$col]";                                          // Zařazení fyzického sloupce do INSERTu
			$sel_vals[] = array_key_exists($col, $override_map) ? (string)$override_map[$col] : "[$col]"; // Nová nebo původní hodnota
		}
		$top_part = ($top_sql !== '') ? "{$top_sql} " : "";                  // Případné omezení TOP 1
		$ord_part = ($order_sql !== '') ? " {$order_sql}" : "";              // Případné řazení zdrojového dotazu
		$sql = "INSERT INTO {$this->storage_table} (" . implode(', ', $ins_cols) . ") \nSELECT {$top_part}" . implode(', ', $sel_vals) . " \nFROM {$this->storage_table} \nWHERE {$where_sql}{$ord_part}"; // Sestavení klonovacího SQL dotazu
		sqlrun($sql);                                                        // Provedení klonovacího dotazu
	}

	/**
	 * Získání, očištění a sanitizace odeslaných POST dat.
	 * Přebírá hodnoty z $_POST, ověřuje s metadaty, ořezává klíčové sloupce a balí je do bezpečných SQL literálů.
	 */
	public function extract_post_data(): array {
		$data = [];                                                          // Výstupní pole sanitizovaných dat
		$meta_columns_list = [                                               // Seznam technických a chráněných sloupců mimo POST
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'draft_author', 'approval_note',
			'language',
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified', 'import_origin',
			'svg_icon', 'logo_data', 'logo_filename', 'logo_mime_type'
		];                                                                   // Konec seznamu technických sloupců

		$key_cols = $this->get_original_key_columns();                       // Klíčové sloupce určující deterministický originál
		$trim_cols = array_unique(array_merge($key_cols, [                   // Sloupce, které se vždy ořezávají od okrajových mezer
			'builtin_code', 'class_name', 'column_name', 'source_code',
			'codetable_name', 'value_code', 'link_code', 'sort_code', 'external_code'
		]));                                                                 // Konec seznamu ořezávaných sloupců
		
		foreach ($this->columns_meta as $colname => $meta) {                 // Průchod všemi sloupci třídy
			if (! empty($meta['is_computed']) OR in_array($colname, $meta_columns_list, true)) { // Přeskočení technických a computed polí
				continue;                                                    // Pokračování na další sloupec
			}
			
			if (! isset($_POST[$colname])) {                                 // Pokud pole nebylo ve formuláři odesláno
				continue;                                                    // Pokračování na další sloupec
			}

			$raw_val = (string)$_POST[$colname];                             // Surová hodnota z formuláře
			if (in_array($colname, $trim_cols, true)) {                      // Pokud jde o klíčový nebo kódový sloupec
				$raw_val = trim($raw_val);                                   // Vždy odstraníme počáteční a koncové mezery
				$_POST[$colname] = $raw_val;                                 // Propíšeme očištěnou hodnotu zpět do $_POST
			}

			if ($this->storage_table === 'meta_phrase' AND $colname === 'source_code' AND $raw_val === '') { // Zákaz prázdného source_code
				$raw_val = 'global_phrase';                                  // Přesměrování prázdného zdroje na global_phrase
			}

			// Ošetření a případná konverze formátovaného textu (Markdown / HTML) přes třídu rich_text
			if (! empty($meta['is_html']) AND class_exists('rich_text')) {   // Pokud sloupec podporuje formátovaný text
				$fmt_key_target = $colname . '__target_format';              // Primární klíč cílového formátu z rich_text
				$fmt_key_a = $colname . '_format';                           // Záložní klíč formátu 1
				$fmt_key_b = $colname . '__format';                          // Záložní klíč formátu 2
				$fmt_key_c = 'rt_format_' . $colname;                        // Záložní klíč formátu 3
				$fmt_hint = (string)($_POST[$fmt_key_target] ?? $_POST[$fmt_key_a] ?? $_POST[$fmt_key_b] ?? $_POST[$fmt_key_c] ?? 'auto'); // Zvolený režim
				if ($fmt_hint === '') {                                      // Pokud nebyl formát explicitně zvolen
					$fmt_hint = 'auto';                                      // Automatická detekce formátu
				}
				if (method_exists('rich_text', 'normalize_for_storage')) {   // Primární metoda v rich_text.php
					$raw_val = (string)rich_text::normalize_for_storage($raw_val, $fmt_hint); // Konverze a sanitizace pro DB
				} elseif (method_exists('rich_text', 'sanitize_html') AND method_exists('rich_text', 'detect_format')) { // Záložní kombinace
					$det_fmt = (string)rich_text::detect_format($raw_val);   // Detekce formátu uloženého textu
					if ($det_fmt === 'html') {                               // Pokud je obsah ve formátu HTML
						$raw_val = (string)rich_text::sanitize_html($raw_val); // Bezpečnostní sanitizace HTML
					}
				}
			}

			$phys_type = $this->col_types[$colname] ?? '';                   // Fyzický typ sloupce v DB
			$is_not_null = (($this->col_nulls[$colname] ?? '') === 'not null'); // Zda fyzický sloupec zakazuje NULL

			// Typově přesné parsování podle fyzického schématu databáze a metadat
			if (in_array($phys_type, ['uuid', 'uniqueidentifier'], true)) {  // Pokud jde o UUID sloupec
				$guid_lit = guidliteral($raw_val);                           // Převod na bezpečný UUID literál
				$data[$colname] = ($guid_lit === 'NULL' AND $is_not_null) ? '0x00' : $guid_lit; // Ošetření NOT NULL UUID (např. ancestor_link)
			} elseif ($meta['input_type'] === 'checkbox' OR $phys_type === 'bit') { // Pokud jde o bitový checkbox
				$data[$colname] = ($raw_val === '1' OR strtolower($raw_val) === 'true') ? 1 : 0; // Bitová hodnota 1 nebo 0
			} elseif (in_array($phys_type, ['int', 'smallint', 'tinyint', 'bigint'], true)) { // Celočíselné sloupce
				$int_lit = intliteral($raw_val, 0);                          // Převod na celé číslo nebo NULL
				$data[$colname] = ($int_lit === 'NULL' AND $is_not_null) ? '0' : $int_lit; // Ošetření NOT NULL sloupců
			} elseif ($meta['input_type'] === 'number' OR in_array($phys_type, ['decimal', 'numeric', 'float', 'real', 'money'], true)) { // Desetinná čísla
				$data[$colname] = (trim($raw_val) === '') ? ($is_not_null ? '0' : 'NULL') : (string)(float)$raw_val; // Číselný literál
			} elseif (in_array($phys_type, ['date', 'datetime', 'datetime2', 'smalldatetime'], true)) { // Datumové sloupce
				$dt_lit = dateliteral($raw_val);                             // Převod na bezpečný datumový SQL literál
				$data[$colname] = ($dt_lit === 'NULL' AND $is_not_null) ? "'1970-01-01'" : $dt_lit; // Fallback pro NOT NULL datum
			} else {
				$data[$colname] = charliteral($raw_val);                     // Převod na bezpečný textový literál
			}
		}

		// Pojistka: Pokud by sloupec removed chyběl v columns_meta, ale fyzicky v tabulce existuje a přišel v POSTu
		if (! isset($data['removed']) AND isset($_POST['removed']) AND in_array('removed', $this->physical_cols, true)) { // Kontrola removed v POSTu
			$raw_rem = (string)$_POST['removed'];                            // Surová hodnota removed z formuláře
			$data[$colname = 'removed'] = ($raw_rem === '1' OR strtolower($raw_rem) === 'true') ? 1 : 0; // Převod na bit 1/0
		}
		
		return $data;                                                        // Vrácení připravených dat
	}

	/**
	 * Spustí post-processing proceduru po zápisu schváleného záznamu ('A')
	 * do tabulky `link` (materializace odvozených vazeb přes `ancestor_link`).
	 */
	private function run_post_save_hooks(string $orig_guid_sql): void {      // Spuštění návazných SQL procedur
		if ($orig_guid_sql === '' OR $orig_guid_sql === 'NULL') {            // Kontrola platného SQL literálu originálu
			return;                                                          // Ukončení bez volání procedur
		}

		if ($this->storage_table === 'link') {                               // Materializace zděděných vazeb v tabulce link
			$p_row = sqlfirstrow("SELECT OBJECT_ID('p_sync_derived_links', 'P') AS pid"); // Ověření existence procedury
			if (! empty($p_row['pid'])) {                                    // Pokud procedura v DB existuje
				sqlrun("EXEC dbo.p_sync_derived_links @root_link_original = {$orig_guid_sql}"); // Přepočet odvozených vazeb
			}
		}
	}

	/**
	 * JÁDRO BACKENDU: Provede autonomní zápis dat s podporou schvalovacího cyklu (SSC),
	 * validací neprázdnosti a unikátnosti klíčových položek a architektury "Klonování s modifikací".
	 */
	public function save_post_data(string $update_guid = '', string $target_status = 'A'): string { // Autonomní uložení dat
		$this->set_save_error('');                                           // Vynulování předchozí chybové zprávy
		if (! $this->is_initialized) {                                       // Kontrola inicializace metadat
			return $update_guid;                                             // Návrat při neinicializované třídě
		}

		if (! in_array($target_status, ['A', 'D', 'F'], true)) {             // Validace cílového stavu
			$target_status = 'A';                                            // Fallback na schválený stav
		}

		$post_data = $this->extract_post_data();                             // Extrakce hodnot z POSTu
		if (empty($post_data)) {                                             // Pokud nepřišla žádná data
			return $update_guid;                                             // Ukončení bez zápisu
		}

		global $dbsession;                                                   // Načtení globální relace

		if (empty($dbsession) OR empty($dbsession['login_session_uuid'])) {  // Kontrola platné relace v dbsession
			$err_save_title = $this->phrase('err_save_failed_title', 'Uložení selhalo'); // Titulek chyby uložení
			$err_save_msg = $this->phrase('err_save_no_session', 'Nepodařilo se načíst kontext uživatele z globální relace dbsession.'); // Text chyby relace
			fatal_error($err_save_title, $err_save_msg);                     // Vyvolání chyby při ztrátě relace
		}

		$org_uuid_raw = (string)$dbsession['organization'];                  // Surové UUID organizace v relaci
		$user_uuid_raw = (string)$dbsession['login_session_uuid'];           // Surové UUID relace pro audit
		$user_acc_raw = (string)($dbsession['user_account'] ?? '0x00');      // Surové UUID účtu uživatele (pro draft_author)
		$sess_lang_raw = (string)$dbsession['language'];                     // Surový kód jazyka relace
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		$right_translate = ! empty($dbsession['right_translate']);           // Oprávnění ke globálnímu překladu

		$org_uuid_sql = guidliteral($org_uuid_raw);                          // SQL literál organizace v relaci
		$user_uuid_sql = guidliteral($user_uuid_raw);                        // SQL literál uživatelské relace
		$user_acc_sql = guidliteral($user_acc_raw);                          // SQL literál uživatelského účtu
		$lang_literal_sql = charliteral($sess_lang_raw);                     // SQL literál jazyka
		
		$table = $this->storage_table;                                       // Cílová fyzická tabulka
		$is_meta_table = $this->is_metadata_entity();                        // Zda jde o tabulku metadat (meta_*)
		$is_self_owned = ($table === 'organization');                        // V tabulce organization vlastní záznam sám sebe

		$orig_guid_raw = $update_guid;                                       // Surové UUID upravovaného záznamu
		$orig_guid_sql = ($update_guid === '') ? '' : guidliteral($update_guid); // SQL literál originálu

		// BACKENDOVÁ POJISTKA: Zakládání zcela nových záznamů v tabulce organization přes entity_manager je zakázáno.
		if ($is_self_owned AND $orig_guid_sql === '') {                      // Zákaz přímého INSERTu do organization
			return '';                                                       // Ukončení bez založení organizace
		}

		// BACKENDOVÁ POJISTKA METADAT: Zakládání zcela nových záznamů v metadatových tabulkách smí jen Developer ('D').
		if ($is_meta_table AND $orig_guid_sql === '' AND $active_role !== 'D') { // Kontrola práv pro nový záznam metadat
			return '';                                                       // Zákaz INSERTu do metadat mimo roli D
		}

		$is_sysadmin_org = ($org_uuid_raw === '0x00' OR $org_uuid_raw === '00000000-0000-0000-0000-000000000000'); // Příznak systémového tenanta

		// Určení efektivního vlastníka záznamu (u tabulky organization je vlastníkem samotný original organizace)
		$rec_owner_raw = ($is_self_owned AND $orig_guid_raw !== '') ? $orig_guid_raw : $org_uuid_raw; // Surový vlastník záznamu
		$rec_owner_sql = guidliteral($rec_owner_raw);                        // SQL literál vlastníka záznamu

		// 2. Zjištění vlastníka a master jazyka původního 'A' záznamu
		$a_exists = false;                                                   // Zda již existuje vlastní 'A' záznam
		$a_uuid_sql = '';                                                    // SQL literál primárního klíče 'A' záznamu
		$a_lang_raw = $sess_lang_raw;                                        // Výchozí pro zcela nový záznam
		$orig_owner_raw = $rec_owner_raw;                                    // Vlastník nalezeného záznamu
		$baseline_row = [];                                                  // Předloha pro porovnání změn (pouze pro metadata / ancestor)
		$current_row = [];                                                   // Aktuální řádek v DB

		if ($orig_guid_sql !== '') {                                         // Pokud upravujeme existující záznam
			$current_row = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND (object_owner = {$rec_owner_sql} OR object_owner = 0x00) ORDER BY object_owner DESC, removed ASC, date_modified DESC"); // Dotaz na existující A záznam
			if (! empty($current_row)) {                                     // Pokud schválený záznam existuje
				$a_exists = ((string)$current_row['object_owner'] === $rec_owner_raw OR $is_sysadmin_org); // Zda záznam patří tenantovi
				$orig_owner_raw = (string)$current_row['object_owner'];      // Uložení vlastníka záznamu
				$a_uuid_sql = guidliteral((string)$current_row['uuid']);     // Uložení UUID 'A' záznamu
				$a_lang_raw = (string)$current_row['language'];              // Mateřský jazyk 'A' záznamu
			}
			
			// Příprava dat pro Delta zápis (NULL dědičnost se uplatňuje výhradně u metadat nebo při vazbě ancestor)
			if ($is_meta_table) {                                            // Pouze pro metadatové tabulky (meta_column, meta_class)
				if (! $is_sysadmin_org) {                                    // Klientský tenant upravující metadata
					$base = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00"); // Dotaz na systémovou předlohu
					if (! empty($base)) {                                    // Načtení systémové předlohy
						$baseline_row = $base;                               // Systémová předloha pro tenanta
					}
				} else {
					$anc_val = $post_data['ancestor'] ?? ($current_row['ancestor'] ?? null); // Zjištění vazby na předka v sys_global_columns
					if (! empty($anc_val) AND $anc_val !== "''" AND $anc_val !== 'NULL') { // Pokud má záznam předka
						$anc_raw = trim((string)$anc_val, "'");              // Očištění UUID předka
						$anc_guid = guidliteral($anc_raw);                   // SQL literál UUID předka
						$anc_row = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$anc_guid} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00"); // Dotaz na předka
						if (! empty($anc_row)) {                             // Načtení dat předka
							$baseline_row = $anc_row;                        // Předloha z globálního předka
						}
					}
				}
			}
		}

		// BACKENDOVÁ OCHRANA UZAMČENÉ HIERARCHIE (proti přepodřízení parent_uuid a změně is_leaf):
		if ($orig_guid_sql !== '' AND ! empty($current_row) AND $this->has_physical_column('parent_uuid')) { // Existující uzel stromu
			$node_locked = $this->is_hierarchy_node_locked($orig_guid_raw);  // Zjištění uzamčení větve vazbami
			if ($node_locked) {                                              // Pokud je větev uzamčena platnými vazbami
				unset($post_data['parent_uuid']);                            // Zákaz změny nadřízeného uzlu (přepodřízení)
				if (! empty($current_row['is_leaf'])) {                      // Pokud byl uzel koncovým listem
					$post_data['is_leaf'] = 1;                               // Zákaz přepnutí obsazeného koncového uzlu na složku
				}
			}
			if (isset($post_data['is_leaf']) AND (int)$post_data['is_leaf'] === 1) { // Pokus o nastavení is_leaf = 1
				$has_ch = sqlfirstrow("SELECT TOP 1 1 AS ex FROM [{$table}] WHERE parent_uuid = {$orig_guid_sql} AND record_type = 'A' AND removed = 0"); // Kontrola potomků
				if (! empty($has_ch)) {                                      // Uzel má aktivní podřízené položky
					$post_data['is_leaf'] = 0;                               // Složka s potomky musí mít is_leaf = 0
				}
			}
		}

		// Vyhodnocení oprávnění pro změnu příznaku removed
		$requested_removed = null;                                           // Požadovaná hodnota removed z formuláře
		if (array_key_exists('removed', $post_data)) {                       // Pokud formulář odeslal sloupec removed
			$requested_removed = (int)$post_data['removed'];                 // Požadovaný stav 0 nebo 1
			unset($post_data['removed']);                                    // Vyjmeme z běžné smyčky a ošetříme cíleně níže
		}

		// OCHRANA KLÍČOVÝCH SLOUPCŮ: U existujícího záznamu nesmí být klíčové sloupce přepsány.
		$key_cols = $this->get_original_key_columns();                       // Seznam klíčových sloupců tabulky

		// 3. Filtrace struktury: Rozdělení dat na 'A' (Základ), 'L' (Lokalizace) a 'D' (Koncept)
		$a_post_data = [];                                                   // Data určená pro hlavní 'A' záznam
		$l_post_data = [];                                                   // Data určená pro překladový 'L' záznam
		$d_post_data = [];                                                   // Data určená pro řádek konceptu 'D'
		$has_translated_cols = false;                                        // Zda formulář obsahuje překládaná pole
		$is_native_lang = ($a_lang_raw === $sess_lang_raw);                  // Zda se edituje v mateřském jazyce

		foreach ($post_data as $col => $val) {                               // Průchod odeslanými hodnotami
			if ($orig_guid_sql !== '' AND in_array($col, $key_cols, true) AND (! empty($current_row) OR $target_status !== 'A')) { // Ochrana klíče
				continue;                                                    // Klíčový sloupec se u existujícího záznamu nemění
			}

			$is_translated = ! empty($this->columns_meta[$col]['translate']); // Zda sloupec podléhá překladu

			if ($is_meta_table AND $active_role !== 'D' AND ! $is_translated) { // Ochrana funkčních polí metadat
				continue;                                                    // Odfiltrování funkčního atributu metadat
			}

			if (! $is_sysadmin_org AND ! empty($this->columns_meta[$col]['is_protected']) AND ! $is_translated) { // Ochrana is_protected
				continue;                                                    // Odfiltrování chráněného sloupce
			}

			if (! empty($baseline_row) AND isset($baseline_row[$col])) {     // Porovnání s výchozí předlohou u metadat
				$baseline_val = $baseline_row[$col];                         // Hodnota v předloze
				$compare_val = str_replace("''", "'", trim((string)$val, "'")); // Hodnota k porovnání bez vnějších apostrofů
				
				if (isset($this->col_nulls[$col]) AND $this->col_nulls[$col] !== 'not null') { // Pokud sloupec povoluje NULL
					if ((string)$compare_val === (string)$baseline_val) {    // Shoda s hodnotou předlohy
						$val = 'NULL';                                       // Shodná hodnota v metadatech se uloží jako NULL pro dědění
					}
				}
			}

			$d_post_data[$col] = $val;                                       // Koncept 'D' drží jak věcné, tak překladové změny

			if ($is_translated) {                                            // Pokud jde o překládaný sloupec
				$has_translated_cols = true;                                 // Evidujeme přítomnost překladu
				$l_post_data[$col] = $val;                                   // Zápis hodnoty do jazykové vrstvy
				if ($is_native_lang) {                                       // Pokud jde o mateřský jazyk záznamu
					$a_post_data[$col] = $val;                               // Zápis do 'A' v mateřském jazyce
				}
			} else {
				$a_post_data[$col] = $val;                                   // Zápis nepřekládaného sloupce do 'A'
			}
		}

		if (! $is_sysadmin_org AND ! empty($this->class_meta['is_final'])) { // Kontrola příznaku is_final
			$a_post_data = [];                                               // Zákaz modifikace 'A' záznamu pro tenanta
			$d_post_data = $l_post_data;                                     // V konceptu tenanta ponecháme jen překládaná pole
		}

		// Cílené zařazení sloupce removed podle vyhodnoceného oprávnění a jazyka
		if ($requested_removed !== null AND ! empty($current_row)) {         // Pokud uživatel mění existující záznam
			$perm = $this->evaluate_remove_permission($current_row, $a_exists); // Kontrola oprávnění ke zrušení/obnovení
			if ($perm['allowed']) {                                          // Pokud má uživatel oprávnění měnit removed
				$d_post_data['removed'] = $requested_removed;                // Zápis návrhu removed do konceptu 'D'
				if ($perm['is_lang_only']) {                                 // V sekundárním jazyce měníme removed pouze na 'L'
					$l_post_data['removed'] = $requested_removed;            // Nastavení removed pro jazykovou mutaci 'L'
					$has_translated_cols = true;                             // Vynutíme průchod sekcí 5 (zápis 'L' záznamu)
				} else {
					$a_post_data['removed'] = $requested_removed;            // Nastavení removed pro hlavní 'A' záznam
					$l_post_data['removed'] = $requested_removed;            // Symetrické přenesení removed i na primární 'L'
				}
			}
		}

		// =====================================================================
		// VALIDACE KLÍČOVÝCH POLOŽEK A UNIKÁTNOSTI ORIGINÁLU U NOVÉHO ZÁZNAMU
		// =====================================================================
		if ($orig_guid_sql === '') {                                         // Zakládání zcela nového záznamu (update_guid === 'NEW')
			$src_key_data = ! empty($a_post_data) ? $a_post_data : $d_post_data; // Pole hodnot pro výpočet klíče
			$key_info = sqlfirstrow("SELECT key1_column, key2_column FROM meta_original_keys WHERE table_name = " . charliteral($table)); // Dotaz na klíčové sloupce

			if (! empty($key_info)) {                                        // Tabulka má deterministický klíč v meta_original_keys
				$k1_col = (string)$key_info['key1_column'];                  // Název 1. klíčového sloupce (např. builtin_code, hierarchy)
				$k2_col = (string)($key_info['key2_column'] ?? '');          // Název volitelného 2. klíčového sloupce

				$k1_val = array_key_exists($k1_col, $src_key_data) ? (string)$src_key_data[$k1_col] : "''"; // SQL literál 1. klíče
				$k1_plain = $this->unquote_sql_literal($k1_val);             // Čistá textová hodnota 1. klíče
				if ($k1_plain === '') {                                      // První klíčový sloupec nesmí být nikdy prázdný
					$k1_meta = $this->columns_meta[$k1_col] ?? [];           // Metadata 1. klíčového sloupce
					$k1_lbl = (string)($k1_meta['label'] ?? $k1_meta['caption'] ?? $k1_col); // Popisek sloupce
					$err_empty = $this->phrase(
						'err_key_col_empty',
						['label' => $k1_lbl, 'col' => $k1_col],
						'Klíčová položka „{' . chr(36) . 'label}“ ({' . chr(36) . 'col}) nesmí být prázdná.'
					);                                                       // Lokalizovaná hláška prázdného klíče
					$this->set_save_error($err_empty);                       // Uložení chyby pro zobrazení v detailu
					return '';                                               // Zastavení zápisu bez provedení INSERTu
				}

				$k2_val = 'NULL';                                            // Výchozí SQL hodnota 2. klíče
				$k2_plain = '';                                              // Výchozí čistá hodnota 2. klíče
				if ($k2_col !== '') {                                        // Pokud má tabulka definovaný i 2. klíčový sloupec
					$k2_val = array_key_exists($k2_col, $src_key_data) ? (string)$src_key_data[$k2_col] : "''"; // SQL literál 2. klíče
					$k2_plain = $this->unquote_sql_literal($k2_val);         // Čistá textová hodnota 2. klíče
					if ($k2_plain === '') {                                  // Druhý klíčový sloupec rovněž nesmí být prázdný
						$k2_meta = $this->columns_meta[$k2_col] ?? [];       // Metadata 2. klíčového sloupce
						$k2_lbl = (string)($k2_meta['label'] ?? $k2_meta['caption'] ?? $k2_col); // Popisek sloupce
						$err_empty2 = $this->phrase(
							'err_key_col_empty',
							['label' => $k2_lbl, 'col' => $k2_col],
							'Klíčová položka „{' . chr(36) . 'label}“ ({' . chr(36) . 'col}) nesmí být prázdná.'
						);                                                   // Lokalizovaná hláška prázdného 2. klíče
						$this->set_save_error($err_empty2);                   // Uložení chyby pro zobrazení v detailu
						return '';                                           // Zastavení zápisu
					}
				}

				// Výpočet deterministického originálu přes dbo.f_generate_original
				$orig_row = sqlfirstrow("SELECT dbo.f_generate_original(" . charliteral($table) . ", {$rec_owner_sql}, CAST({$k1_val} AS VARCHAR(MAX)), CAST({$k2_val} AS VARCHAR(MAX))) AS orig_guid"); // Výpočet hashe
				if (! empty($orig_row)) {                                    // Načtení vypočteného originálu
					$orig_guid_raw = (string)$orig_row['orig_guid'];         // Surové UUID originálu
					$orig_guid_sql = guidliteral($orig_guid_raw);            // Deterministické UUID originálu
				}

				// Test unikátnosti klíčových položek a výsledného originálu v cílové tabulce (včetně koše removed = 1 a systémových 0x00 záznamů)
				$k1_cond_sql = "LOWER(LTRIM(RTRIM(CAST([{$k1_col}] AS VARCHAR(MAX))))) = LOWER(LTRIM(RTRIM(CAST({$k1_val} AS VARCHAR(MAX)))))"; // Podmínka shody 1. klíče
				$k2_cond_sql = ($k2_col !== '')
					? " AND LOWER(LTRIM(RTRIM(CAST([{$k2_col}] AS VARCHAR(MAX))))) = LOWER(LTRIM(RTRIM(CAST({$k2_val} AS VARCHAR(MAX)))))"
					: "";                                                    // Podmínka shody 2. klíče

				$dup_row = sqlfirstrow("
					SELECT TOP 1 uuid, original, record_type, removed, object_owner
					FROM [{$table}]
					WHERE uuid = {$orig_guid_sql}
					   OR (original = {$orig_guid_sql} AND object_owner IN (0x00, {$rec_owner_sql}) AND record_type IN ('A', 'D'))
					   OR (record_type IN ('A', 'D') AND object_owner IN (0x00, {$rec_owner_sql}) AND {$k1_cond_sql}{$k2_cond_sql})
					ORDER BY removed ASC, CASE WHEN record_type = 'A' THEN 0 ELSE 1 END ASC
				");                                                          // Kontrola duplicitního záznamu v tabulce

				if (! empty($dup_row)) {                                     // Nalezen kolizní záznam se shodným klíčem / originálem
					$key_desc = ($k2_col !== '') ? "{$k1_col}='{$k1_plain}', {$k2_col}='{$k2_plain}'" : "{$k1_col}='{$k1_plain}'"; // Popis klíče
					if (! empty($dup_row['removed'])) {                      // Kolizní záznam leží v koši (removed = 1)
						$err_dup_trash = $this->phrase(
							'err_duplicate_key_in_trash',
							['keys' => $key_desc],
							'Záznam se zadanou klíčovou položkou ({' . chr(36) . 'keys}) již existuje v koši (zrušené záznamy). Zapněte v levém panelu „Zobrazit i zrušené“ a záznam obnovte, nebo zvolte jiný unikátní kód.'
						);                                                   // Hláška pro záznam v koši
						$this->set_save_error($err_dup_trash);               // Uložení chyby
					} else {
						$err_dup_active = $this->phrase(
							'err_duplicate_key_active',
							['keys' => $key_desc],
							'Záznam se zadanou klíčovou položkou ({' . chr(36) . 'keys}) již v databázi existuje. Zadejte unikátní hodnotu, aby nedošlo k výpočtu duplicitního originálu.'
						);                                                   // Hláška pro aktivní duplicitní záznam
						$this->set_save_error($err_dup_active);              // Uložení chyby
					}
					return '';                                               // Zastavení zápisu před vznikem SQL chyby
				}

				// Speciální kontrola pro tabulku hierarchy: builtin_code se propisuje jako class_name do meta_class
				if ($table === 'hierarchy') {                                // Kontrola kolize kódu hierarchie s tabulkou meta_class
					$cls_dup = sqlfirstrow("
						SELECT TOP 1 class_name
						FROM meta_class
						WHERE LOWER(LTRIM(RTRIM(class_name))) = LOWER(LTRIM(RTRIM(CAST({$k1_val} AS VARCHAR(80)))))
						  AND object_owner IN (0x00, {$rec_owner_sql})
						  AND record_type = 'A'
					");                                                      // Dotaz na existenci třídy v meta_class
					if (! empty($cls_dup)) {                                 // Kód již obsadila jiná logická třída v meta_class
						$err_cls_col = $this->phrase(
							'err_hierarchy_code_collides_class',
							['code' => $k1_plain],
							'Kód hierarchie „{' . chr(36) . 'code}“ koliduje s názvem již existující logické třídy v meta_class. Zvolte prosím jiný unikátní kód.'
						);                                                   // Chybová hláška kolize s meta_class
						$this->set_save_error($err_cls_col);                 // Uložení chyby
						return '';                                           // Zastavení zápisu
					}
				}
			} elseif ($table === 'link') {                                   // Speciální 4složkový výpočet a validace pro tabulku link
				$link_def = array_key_exists('link_def', $src_key_data) ? (string)$src_key_data['link_def'] : 'NULL'; // Definice vazby
				$from_obj = array_key_exists('from_object', $src_key_data) ? (string)$src_key_data['from_object'] : 'NULL'; // Zdroj vazby
				$to_obj = array_key_exists('to_object', $src_key_data) ? (string)$src_key_data['to_object'] : 'NULL'; // Cíl vazby
				$anc_link = (array_key_exists('ancestor_link', $src_key_data) AND $src_key_data['ancestor_link'] !== 'NULL') ? (string)$src_key_data['ancestor_link'] : '0x00'; // Předek vazby

				if ($this->unquote_sql_literal($link_def) === '' OR $this->unquote_sql_literal($from_obj) === '' OR $this->unquote_sql_literal($to_obj) === '') { // Chybí složka vazby
					$err_lnk_empty = $this->phrase('err_link_keys_empty', [], 'Klíčové položky vazby (link_def, from_object, to_object) musí být vyplněny.'); // Hláška
					$this->set_save_error($err_lnk_empty);                   // Uložení chyby
					return '';                                               // Zastavení zápisu
				}

				$orig_row = sqlfirstrow("SELECT dbo.f_link_original(CAST({$rec_owner_sql} AS varchar(36)), CAST({$link_def} AS varchar(36)), CAST({$from_obj} AS varchar(36)), CAST({$to_obj} AS varchar(36)), CAST({$anc_link} AS varchar(36))) AS orig_guid"); // Výpočet originálu vazby
				if (! empty($orig_row)) {                                    // Načtení originálu vazby
					$orig_guid_raw = (string)$orig_row['orig_guid'];         // Surové UUID vazby
					$orig_guid_sql = guidliteral($orig_guid_raw);            // Deterministické UUID vazby
				}

				$dup_lnk = sqlfirstrow("
					SELECT TOP 1 uuid, removed
					FROM [link]
					WHERE uuid = {$orig_guid_sql}
					   OR (original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type IN ('A', 'D'))
					   OR (object_owner = {$rec_owner_sql} AND link_def = {$link_def} AND from_object = {$from_obj} AND to_object = {$to_obj} AND ancestor_link = {$anc_link} AND record_type IN ('A', 'D'))
				");                                                          // Kontrola duplicitní vazby v tabulce link
				if (! empty($dup_lnk)) {                                     // Vazba již existuje
					$err_dup_lnk = $this->phrase('err_duplicate_link', [], 'Tato vazba mezi zvolenými záznamy již existuje.'); // Hláška duplicity vazby
					$this->set_save_error($err_dup_lnk);                     // Uložení chyby
					return '';                                               // Zastavení zápisu
				}
			} else {
				$orig_row = sqlfirstrow("SELECT NEWID() AS orig_guid");      // Náhodné UUID pro globální tabulky bez deterministického klíče
				if (! empty($orig_row)) {                                    // Načtení nového UUID
					$orig_guid_raw = (string)$orig_row['orig_guid'];         // Surové náhodné UUID
					$orig_guid_sql = guidliteral($orig_guid_raw);            // Nově vygenerované UUID
				}
			}
		}

		sqlrun("BEGIN TRAN");                                                // Zahájení databázové transakce

		$audit_base_map = ['date_created' => 'GETDATE()', 'date_modified' => 'GETDATE()', 'who_created' => $user_uuid_sql, 'who_modified' => $user_uuid_sql]; // Základní auditní mapa

		// =====================================================================
		// VĚTEV A: ZÁPIS KONCEPTU NEBO POSTOUPENÍ KE SCHVÁLENÍ ('D' / 'F')
		// =====================================================================
		if ($target_status === 'D' OR $target_status === 'F') {              // Pokud ukládáme koncept nebo postupujeme ke schválení
			$safe_status = charliteral($target_status, 1);                   // SQL literál cílového stavu ('D' nebo 'F')

			$dr_row = sqlfirstrow("
				SELECT TOP 1 uuid
				FROM {$table}
				WHERE original = {$orig_guid_sql}
				  AND object_owner = {$rec_owner_sql}
				  AND record_type = 'D'
				  AND [language] = {$lang_literal_sql}
				  AND (draft_author = {$user_acc_sql} OR (draft_author = 0x00 AND approval_status = 'R'))
				ORDER BY removed ASC, date_modified DESC
			");                                                              // Dotaz na existující koncept uživatele (i s removed = 1)

			if (! empty($dr_row)) {                                          // Pokud koncept uživatele již existuje -> UPDATE
				$dr_uuid_sql = guidliteral((string)$dr_row['uuid']);         // UUID existujícího řádku konceptu
				$set_dr = [];                                                // Pole změn pro UPDATE konceptu
				foreach ($d_post_data as $col => $val) {                     // Průchod ukládanými sloupci konceptu
					if (! in_array($col, $key_cols, true)) {                 // Ochrana klíčového sloupce v existujícím konceptu
						$set_dr[] = "[$col] = $val";                         // Nastavení hodnoty sloupce
					}
				}
				$set_dr[] = "approval_status = {$safe_status}";              // Nastavení stavu ('D' nebo 'F')
				$set_dr[] = "draft_author = {$user_acc_sql}";                // Zajištění autora konceptu
				$set_dr[] = "approval_note = ''";                            // Vyčištění předchozí poznámky odmítnutí
				$set_dr[] = "date_modified = GETDATE()";                     // Aktualizace času úpravy konceptu
				$set_dr[] = "who_modified = {$user_uuid_sql}";               // Aktualizace relace autora konceptu

				sqlrun("UPDATE {$table} SET " . implode(', ', $set_dr) . " WHERE uuid = {$dr_uuid_sql}"); // Provedení UPDATE konceptu
			} else {
				$src_a_row = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND object_owner IN ({$rec_owner_sql}, 0x00) ORDER BY object_owner DESC, removed ASC, date_modified DESC"); // Kontrola předlohy A
				$d_ssc_map = ['record_type' => "'D'", 'approval_status' => $safe_status, 'draft_author' => $user_acc_sql, 'approval_note' => "''", 'language' => $lang_literal_sql]; // SSC sloupce konceptu

				if (! empty($src_a_row)) {                                   // Klonování existujícího 'A' záznamu do 'D'
					$src_a_uuid = guidliteral((string)$src_a_row['uuid']);   // UUID zdrojového 'A' řádku
					$d_sys_map = ['uuid' => 'NEWID()', 'object_owner' => $rec_owner_sql, 'original' => 'original']; // Identifikátory klonovaného konceptu
					$this->clone_with_map($d_sys_map + $d_ssc_map + $audit_base_map + $d_post_data, "uuid = {$src_a_uuid}"); // Vložení klonovaného konceptu
				} else {
					$d_sys_map = ['uuid' => 'NEWID()', 'original' => $orig_guid_sql, 'object_owner' => $rec_owner_sql]; // Identifikátory nového konceptu
					$this->insert_from_map($d_sys_map + $d_ssc_map + $audit_base_map + $d_post_data); // Provedení INSERTu nového konceptu
				}
			}

			sqlrun("COMMIT");                                                // Potvrzení transakce uložení konceptu
			return $orig_guid_raw;                                           // Vrácení originálu uloženého konceptu
		}

		// =====================================================================
		// VĚTEV B: PŘÍMÝ ZÁPIS SCHVÁLENÉHO ZÁZNAMU ('A' + symetrické 'L')
		// =====================================================================
		$a_new_hdr = ['uuid' => $orig_guid_sql, 'original' => $orig_guid_sql, 'object_owner' => $rec_owner_sql, 'record_type' => "'A'", 'approval_status' => "'A'", 'language' => $lang_literal_sql]; // Hlavička nového A záznamu

		// 4. Zápis do 'A' záznamu
		if ($update_guid === '' AND ! $a_exists) {                           // Zcela nový záznam ukládaný rovnou jako schválený
			$this->insert_from_map($a_new_hdr + $audit_base_map + $a_post_data); // Provedení INSERTu nového 'A' záznamu
			
		} elseif (! empty($a_post_data)) {                                   // UPDATE nebo OVERRIDE existujícího 'A' záznamu
			if ($a_exists) {                                                 // Záznam 'A' již pro tohoto vlastníka existuje
				$set_clauses = [];                                           // Pole přiřazení pro UPDATE
				foreach ($a_post_data as $col => $val) {                     // Průchod změněnými sloupci
					$set_clauses[] = "[$col] = $val";                        // Nastavení nové hodnoty sloupce
				}
				$set_clauses[] = "date_modified = GETDATE()";                // Aktualizace času změny
				$set_clauses[] = "who_modified = {$user_uuid_sql}";          // Aktualizace autora změny

				$sql = "UPDATE {$table} SET " . implode(', ', $set_clauses) . " WHERE uuid = {$a_uuid_sql}"; // Sestavení UPDATE dotazu
				sqlrun($sql);                                                // Provedení UPDATE existujícího 'A' záznamu
			} else {
				$sys_row = sqlfirstrow("SELECT 1 AS ex FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = 0x00 AND record_type = 'A' AND removed = 0"); // Kontrola systémového originálu
				if (! empty($sys_row)) {                                     // Klonování ze systémového originálu 0x00
					$ov_hdr = ['uuid' => 'NEWID()', 'object_owner' => $rec_owner_sql, 'original' => 'original', 'record_type' => "'A'", 'approval_status' => "'A'", 'language' => 'language']; // Hlavička klonu A
					$this->clone_with_map($ov_hdr + $audit_base_map + $a_post_data, "original = {$orig_guid_sql} AND object_owner = 0x00 AND record_type = 'A'", 'TOP 1', 'ORDER BY removed ASC, date_modified DESC'); // Vytvoření tenantova 'A' overridu
				} else {
					$this->insert_from_map($a_new_hdr + $audit_base_map + $a_post_data); // Vložení nového 'A' záznamu
				}
			}
		}

		// 5. Zápis 'L' záznamu (tabulka link nepoužívá jazykové záznamy 'L')
		if ($has_translated_cols AND $orig_guid_sql !== '' AND $table !== 'link') { // Pokud formulář obsahuje překládané sloupce
			$l_owner_sql = $rec_owner_sql;                                   // Výchozím vlastníkem překladu je vlastník záznamu
			if ($orig_owner_raw === '0x00' OR $orig_owner_raw === '00000000-0000-0000-0000-000000000000') { // Pokud je originál systémový
				if ($right_translate) {                                      // Pokud má uživatel právo globálního překladu
					$l_owner_sql = '0x00';                                   // Oprávněný překladatel zapisuje globálně
				}
			}

			$l_exists = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND language = {$lang_literal_sql} ORDER BY removed ASC, date_modified DESC"); // Kontrola existence L

			if (! empty($l_exists)) {                                        // Pokud 'L' záznam již existuje -> UPDATE
				if (! empty($l_post_data)) {                                 // Pokud jsou k dispozici přeložená data
					$set_l = [];                                             // Pole změn pro UPDATE 'L' záznamu
					foreach ($l_post_data as $col => $val) {                 // Průchod překládanými sloupci
						$set_l[] = "[$col] = $val";                          // Přiřazení přeložené hodnoty
					}
					$set_l[] = "date_modified = GETDATE()";                  // Čas úpravy překladu
					$set_l[] = "who_modified = {$user_uuid_sql}";            // Autor úpravy překladu
					
					$sql_l = "UPDATE {$table} SET " . implode(', ', $set_l) . " WHERE uuid = " . guidliteral((string)$l_exists['uuid']); // UPDATE L
					sqlrun($sql_l);                                          // Provedení UPDATE 'L' záznamu
				}
			} else {
				$l_hdr = ['uuid' => 'NEWID()', 'object_owner' => $l_owner_sql, 'record_type' => "'L'", 'approval_status' => "'A'", 'language' => $lang_literal_sql]; // Hlavička nového L záznamu
				$source_owner_sql = (! $is_sysadmin_org OR $is_self_owned) ? "object_owner IN ({$rec_owner_sql}, 0x00)" : "object_owner = 0x00"; // Podmínka vlastníka zdroje
				$this->clone_with_map($l_hdr + $audit_base_map + $l_post_data, "original = {$orig_guid_sql} AND {$source_owner_sql} AND record_type = 'A'", 'TOP 1', 'ORDER BY object_owner DESC, removed ASC, date_modified DESC'); // Založení nového 'L' záznamu
			}

			// Jednotná auditní stopa na hlavním 'A' záznamu
			if (empty($a_post_data) AND $a_uuid_sql !== '' AND ($a_exists OR $l_owner_sql === '0x00')) { // Kontrola potřeby aktualizace auditu na A
				sqlrun("UPDATE {$table} SET date_modified = GETDATE(), who_modified = {$user_uuid_sql} WHERE uuid = {$a_uuid_sql}"); // Aktualizace auditu na A
			}
		}

		// Pokud došlo k přejmenování organizace v tabulce organization, propíšeme nový název do běžících relací
		if ($is_self_owned AND isset($a_post_data['caption']) AND $orig_guid_sql !== '') { // Přejmenování organizace
			$new_org_cap = (string)$a_post_data['caption'];                  // SQL literál nového názvu organizace
			sqlrun("
				UPDATE wwwsession SET organization_name = {$new_org_cap} WHERE organization = {$orig_guid_sql} AND organization <> 0x00;
				UPDATE dbsession SET organization_name = {$new_org_cap} WHERE organization = {$orig_guid_sql} AND organization <> 0x00;
			");                                                              // Aktualizace názvu organizace v relacích
		}

		// 6. Úklid konceptů ('D') při přímém uložení jako schválené ('A')
		if (in_array('draft_author', $this->physical_cols, true) AND $orig_guid_sql !== '') { // Pokud tabulka podporuje koncepty
			sqlrun("
				DELETE FROM {$table}
				WHERE original = {$orig_guid_sql}
				  AND object_owner = {$rec_owner_sql}
				  AND record_type = 'D'
				  AND [language] = {$lang_literal_sql}
				  AND (draft_author = {$user_acc_sql} OR draft_author = 0x00)
			");                                                              // Smazání vlastního konceptu po přímém schválení

			$auto_rej_msg = $this->phrase('msg_auto_rejected_other_approved', 'Byl schválen záznam jiného uživatele.'); // Text automatického odmítnutí
			$safe_auto_rej = charliteral($auto_rej_msg);                     // SQL literál zprávy odmítnutí
			sqlrun("
				UPDATE {$table}
				SET approval_status = 'R',
					approval_note = {$safe_auto_rej},
					date_modified = GETDATE(),
					who_modified = {$user_uuid_sql}
				WHERE original = {$orig_guid_sql}
				  AND object_owner = {$rec_owner_sql}
				  AND record_type = 'D'
				  AND [language] = {$lang_literal_sql}
			");                                                              // Odmítnutí souběžných konceptů jiných uživatelů
		}

		// 7. Spuštění návazné synchronizace pro tabulku link
		$this->run_post_save_hooks($orig_guid_sql);                          // Přepočet odvozených vazeb (ancestor_link)

		sqlrun("COMMIT");                                                    // Potvrzení transakce zápisu
		return $orig_guid_raw;                                               // Vrácení originálu uloženého záznamu
	}

	/**
	 * Odstraní rozpracovaný nebo vrácený koncept ('D') přihlášeného uživatele
	 * bez náhrady a bez zápisu do historie ('H').
	 */
	public function delete_draft(string $original_guid): void {              // Smazání konceptu uživatele podle original
		if (! $this->is_initialized OR trim($original_guid) === '') {        // Kontrola platného vstupu
			return;                                                          // Ukončení při prázdném identifikátoru
		}

		global $dbsession;                                                   // Globální kontext relace
		$org_raw = (string)($dbsession['organization'] ?? '0x00');           // Surové UUID organizace v relaci
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$rec_owner_sql = ($table === 'organization') ? guidliteral($original_guid) : guidliteral($org_raw); // Vlastník záznamu
		$user_acc_sql = guidliteral((string)($dbsession['user_account'] ?? '0x00')); // SQL literál účtu uživatele
		$lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'));   // SQL literál jazyka relace
		$orig_sql = guidliteral($original_guid);                             // SQL literál mazaného originálu

		sqlrun("
			DELETE FROM {$table}
			WHERE original = {$orig_sql}
			  AND object_owner = {$rec_owner_sql}
			  AND record_type = 'D'
			  AND [language] = {$lang_sql}
			  AND (draft_author = {$user_acc_sql} OR draft_author = 0x00)
		");                                                                  // Fyzické odstranění konceptu z DB
	}

	/**
	 * Schválí vybraný návrh (`record_type = 'D'`, včetně návrhů na zrušení či obnovu `removed`)
	 * identifikovaný svým primárním klíčem `uuid`.
	 */
	public function approve_draft(string $draft_uuid): void {                // Schválení vybraného návrhu
		if (! $this->is_initialized OR trim($draft_uuid) === '') {           // Kontrola inicializace a platného UUID
			return;                                                          // Ukončení při chybějícím UUID návrhu
		}

		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$sess_org_raw = (string)($dbsession['organization'] ?? '0x00');      // Surové UUID organizace schvalovatele
		$sess_org_sql = guidliteral($sess_org_raw);                          // SQL literál organizace schvalovatele
		$sess_lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka schvalovatele
		$is_sys_org = ($sess_org_raw === '0x00' OR $sess_org_raw === '00000000-0000-0000-0000-000000000000'); // Zda je schvalovatel v 0x00

		$approver_session_sql = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$right_translate = ! empty($dbsession['right_translate']);           // Oprávnění ke globálnímu překladu
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid);                          // SQL literál primárního klíče návrhu

		$owner_cond = ($table === 'organization' AND $is_sys_org)
			? "(object_owner = {$sess_org_sql} OR object_owner = original)"
			: "object_owner = {$sess_org_sql}";                              // Izolace schvalovaného návrhu podle tenanta

		// 1. Načtení schvalovaného návrhu ('D', včetně návrhu na zrušení s removed = 1) s kontrolou tenanta a jazyka
		$draft_row = sqlfirstrow("
			SELECT * FROM {$table}
			WHERE uuid = {$draft_uuid_sql}
			  AND record_type = 'D'
			  AND approval_status = 'F'
			  AND {$owner_cond}
			  AND [language] = {$sess_lang_sql}
		");                                                                  // Dotaz na návrh (vč. removed = 1)

		if (empty($draft_row)) {                                             // Pokud návrh nebyl nalezen nebo nepatří tenantovi
			return;                                                          // Ukončení zpracování
		}

		$orig_raw = (string)$draft_row['original'];                          // Surové UUID originálu
		$orig_sql = guidliteral($orig_raw);                                  // SQL literál originálu
		$owner_raw = (string)$draft_row['object_owner'];                     // Surové UUID vlastníka návrhu
		$owner_sql = guidliteral($owner_raw);                                // SQL literál vlastníka návrhu
		$draft_lang_raw = (string)$draft_row['language'];                    // Jazyk schvalovaného návrhu
		$draft_lang_sql = charliteral($draft_lang_raw, 2);                   // SQL literál jazyka návrhu
		$author_session_sql = guidliteral((string)$draft_row['who_modified']); // Relace autora v době postoupení návrhu
		$author_date_sql = charliteral((string)$draft_row['date_modified']); // Datum postoupení návrhu autorem

		$is_sys_owner = ($owner_raw === '0x00' OR $owner_raw === '00000000-0000-0000-0000-000000000000'); // Zda jde o systémového vlastníka
		$is_final_class = (! $is_sys_owner AND $table !== 'organization' AND ! empty($this->class_meta['is_final'])); // Zda třída zakazuje A override

		// 2. Zjištění existence schváleného 'A' záznamu (včetně případného dříve zrušeného při návrhu obnovy)
		$existing_a = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$orig_sql} AND record_type = 'A' AND object_owner IN ({$owner_sql}, 0x00) ORDER BY object_owner DESC, removed ASC, date_modified DESC"); // Hledání A záznamu

		$own_a_exists = (! empty($existing_a) AND ((string)$existing_a['object_owner'] === $owner_raw OR $is_sys_owner)); // Zda má vlastník vlastní A záznam
		$a_lang_raw = ! empty($existing_a) ? (string)$existing_a['language'] : $draft_lang_raw; // Mateřský jazyk A záznamu
		$is_native_lang = ($a_lang_raw === $draft_lang_raw);                 // Zda je návrh v mateřském jazyce záznamu

		$skip_data_cols = array_merge([                                      // Technické a klíčové sloupce, které se při UPDATE nemění
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note', 'language',
			'date_created', 'who_created', 'date_modified', 'who_modified'
		], $this->get_original_key_columns());                               // Ochrana klíčových sloupců i při schválení UPDATE

		if (! empty($existing_a) AND $this->is_hierarchy_node_locked($orig_raw)) { // Ochrana uzamčené větve při schválení návrhu
			$skip_data_cols[] = 'parent_uuid';                               // Zákaz přepodřízení uzamčené větve
			if (! empty($existing_a['is_leaf'])) {                           // Pokud byl uzel koncovým listem
				$skip_data_cols[] = 'is_leaf';                               // Zákaz zrušení koncového uzlu
			}
		}

		$ap_audit_map = ['date_created' => $author_date_sql, 'who_created' => $author_session_sql, 'date_modified' => 'GETDATE()', 'who_modified' => $approver_session_sql]; // Audit autora a schvalovatele

		sqlrun("BEGIN TRAN");                                                // Zahájení transakce schválení

		// 3. Zápis do schváleného 'A' záznamu
		if (! $is_final_class) {                                             // Pokud je povolen zápis do 'A' vrstvy
			if ($own_a_exists) {                                             // UPDATE existujícího 'A' záznamu (date_created a who_created se NEMĚNÍ!)
				$a_uuid_sql = guidliteral((string)$existing_a['uuid']);      // Primární klíč existujícího A záznamu
				$set_a = [];                                                 // Pole změn pro UPDATE A záznamu

				foreach ($this->physical_cols as $col) {                     // Průchod fyzickými sloupci tabulky
					if (in_array($col, $skip_data_cols, true)) {             // Přeskočení technických a klíčových sloupců
						continue;                                            // Pokračování na další sloupec
					}
					if ($col === 'removed' AND ! $is_native_lang) {          // V sekundárním jazyce ruší removed pouze překlad L
						continue;                                            // Hlavní záznam A v primárním jazyce nerušíme
					}
					$is_trans = ! empty($this->columns_meta[$col]['translate']); // Zda je sloupec překládaný
					if ($is_trans AND ! $is_native_lang) {                   // Ochrana mateřského jazyka v A záznamu
						continue;                                            // Cizojazyčný překlad patří pouze do L záznamu
					}
					$set_a[] = "[$col] = d.[$col]";                          // Převzetí hodnoty ze schvalovaného návrhu d
				}

				$set_a[] = "approval_status = 'A'";                          // Nastavení schváleného stavu
				$set_a[] = "draft_author = 0x00";                            // Vynulování autora konceptu
				$set_a[] = "approval_note = ''";                             // Vyčištění poznámky schvalování
				$set_a[] = "date_modified = GETDATE()";                      // Datum schválení
				$set_a[] = "who_modified = {$approver_session_sql}";         // Schvalovatel

				$sql_upd_a = "UPDATE a SET " . implode(', ', $set_a) . " FROM {$table} a JOIN {$table} d ON d.uuid = {$draft_uuid_sql} WHERE a.uuid = {$a_uuid_sql}"; // SQL UPDATE A
				sqlrun($sql_upd_a);                                          // Provedení UPDATE schváleného záznamu
			} else {
				// INSERT nového 'A' záznamu: who_modified -> who_created a date_modified -> date_created (autor návrhu se stává tvůrcem!)
				$ap_a_pk = (! empty($existing_a) ? 'NEWID()' : 'original');  // Primární klíč nového A záznamu
				$ap_a_hdr = ['uuid' => $ap_a_pk, 'object_owner' => $owner_sql, 'original' => 'original', 'record_type' => "'A'", 'approval_status' => "'A'", 'draft_author' => '0x00', 'approval_note' => "''"]; // Hlavička A záznamu
				$this->clone_with_map($ap_a_hdr + $ap_audit_map, "uuid = {$draft_uuid_sql}"); // Založení schváleného A záznamu
			}
		}

		// 4. Zápis do symetrického 'L' záznamu pro jazyk návrhu (mimo tabulku link)
		if ($table !== 'link') {                                             // Tabulka link nepoužívá jazykové mutace 'L'
			$l_owner_sql = $owner_sql;                                       // Vlastník jazykové mutace
			if (! empty($existing_a) AND ((string)$existing_a['object_owner'] === '0x00' OR (string)$existing_a['object_owner'] === '00000000-0000-0000-0000-000000000000')) { // Pokud je A záznam systémový
				if ($right_translate) {                                      // Pokud má schvalovatel právo globálního překladu
					$l_owner_sql = '0x00';                                   // Globální systémový překlad
				}
			}

			$existing_l = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND [language] = {$draft_lang_sql} ORDER BY removed ASC, date_modified DESC"); // Kontrola existence L

			if (! empty($existing_l)) {                                      // UPDATE existujícího 'L' záznamu
				$l_uuid_sql = guidliteral((string)$existing_l['uuid']);      // Primární klíč L záznamu
				$set_l = [];                                                 // Pole změn pro UPDATE L záznamu

				foreach ($this->physical_cols as $col) {                     // Průchod fyzickými sloupci
					if (in_array($col, $skip_data_cols, true)) {             // Přeskočení technických a klíčových sloupců
						continue;                                            // Pokračování na další sloupec
					}
					$set_l[] = "[$col] = d.[$col]";                          // Převzetí hodnoty z návrhu d
				}

				$set_l[] = "approval_status = 'A'";                          // Schválený stav L záznamu
				$set_l[] = "draft_author = 0x00";                            // Vynulování autora konceptu
				$set_l[] = "approval_note = ''";                             // Vyčištění poznámky
				$set_l[] = "date_modified = GETDATE()";                      // Datum schválení překladu
				$set_l[] = "who_modified = {$approver_session_sql}";         // Relace schvalovatele

				$sql_upd_l = "UPDATE l SET " . implode(', ', $set_l) . " FROM {$table} l JOIN {$table} d ON d.uuid = {$draft_uuid_sql} WHERE l.uuid = {$l_uuid_sql}"; // SQL UPDATE L
				sqlrun($sql_upd_l);                                          // Provedení UPDATE L záznamu
			} else {
				// INSERT nového 'L' záznamu (who_created = autor návrhu, who_modified = schvalovatel)
				$ap_l_hdr = ['uuid' => 'NEWID()', 'object_owner' => $l_owner_sql, 'original' => 'original', 'record_type' => "'L'", 'approval_status' => "'A'", 'draft_author' => '0x00', 'approval_note' => "''", 'language' => $draft_lang_sql]; // Hlavička L záznamu
				$this->clone_with_map($ap_l_hdr + $ap_audit_map, "uuid = {$draft_uuid_sql}"); // Založení schváleného L záznamu
			}

			// Jednotná auditní stopa na 'A' záznamu, pokud se měnila pouze jazyková vrstva 'L'
			if (($is_final_class OR ! $is_native_lang) AND ! empty($existing_a)) { // Kontrola potřeby aktualizace auditu na A
				$a_uuid_sql = guidliteral((string)$existing_a['uuid']);      // UUID hlavního A záznamu
				sqlrun("UPDATE {$table} SET date_modified = GETDATE(), who_modified = {$approver_session_sql} WHERE uuid = {$a_uuid_sql}"); // Aktualizace auditu na A
			}
		}

		// 5. Fyzické odstranění právě schváleného návrhu ('D')
		sqlrun("DELETE FROM {$table} WHERE uuid = {$draft_uuid_sql}");       // Smazání schváleného návrhu

		// 6. Automatické odmítnutí všech ostatních souběžných návrhů pro stejný (original, object_owner, language)
		$auto_rej_msg = $this->phrase('msg_auto_rejected_other_approved', 'Byl schválen záznam jiného uživatele.'); // Text automatického odmítnutí
		$safe_auto_rej = charliteral($auto_rej_msg);                         // SQL literál poznámky odmítnutí

		sqlrun("
			UPDATE {$table}
			SET approval_status = 'R',
				approval_note = {$safe_auto_rej},
				date_modified = GETDATE(),
				who_modified = {$approver_session_sql}
			WHERE original = {$orig_sql}
			  AND object_owner = {$owner_sql}
			  AND record_type = 'D'
			  AND [language] = {$draft_lang_sql}
		");                                                                  // Automatické odmítnutí ostatních návrhů

		// 7. Spuštění návazné synchronizace pro tabulku link
		$this->run_post_save_hooks($orig_sql);                               // Přepočet odvozených vazeb (ancestor_link)

		sqlrun("COMMIT");                                                    // Potvrzení transakce schválení
	}

	/**
	 * Odmítne / vrátí k přepracování vybraný návrh (`record_type = 'D'`, včetně návrhů na zrušení)
	 * a uloží k němu poznámku schvalovatele (`approval_note`).
	 */
	public function reject_draft(string $draft_uuid, string $approval_note = ''): void { // Odmítnutí návrhu schvalovatelem
		if (! $this->is_initialized OR trim($draft_uuid) === '') {           // Kontrola platného vstupu
			return;                                                          // Ukončení při chybějícím UUID
		}

		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$sess_org_raw = (string)($dbsession['organization'] ?? '0x00');      // Surové UUID organizace schvalovatele
		$sess_org_sql = guidliteral($sess_org_raw);                          // SQL literál organizace schvalovatele
		$sess_lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka schvalovatele
		$is_sys_org = ($sess_org_raw === '0x00' OR $sess_org_raw === '00000000-0000-0000-0000-000000000000'); // Zda je schvalovatel v 0x00

		$approver_session_sql = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid);                          // SQL literál UUID návrhu

		$owner_cond = ($table === 'organization' AND $is_sys_org)
			? "(object_owner = {$sess_org_sql} OR object_owner = original)"
			: "object_owner = {$sess_org_sql}";                              // Izolace odmítaného návrhu podle tenanta

		$note_text = trim($approval_note);                                   // Očištěný text poznámky
		if ($note_text === '') {                                             // Výchozí text pokud schvalovatel nevyplnil poznámku
			$note_text = $this->phrase('msg_rejected_by_approver', 'Vráceno schvalovatelem k přepracování.'); // Výchozí důvod vrácení
		}
		$safe_note = charliteral($note_text);                                // SQL literál poznámky

		sqlrun("
			UPDATE {$table}
			SET approval_status = 'R',
				approval_note = {$safe_note},
				date_modified = GETDATE(),
				who_modified = {$approver_session_sql}
			WHERE uuid = {$draft_uuid_sql}
			  AND record_type = 'D'
			  AND {$owner_cond}
			  AND [language] = {$sess_lang_sql}
		");                                                                  // Přepnutí návrhu do stavu 'R' (Vráceno)
	}
}