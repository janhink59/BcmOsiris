<?php
/**
 * =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: entity_manager_write.php
 * Trait: entity_manager_write
 * Účel: Zápisová, validační, klonovací a schvalovací (SSC) část třídy entity_manager.
 *       Vyčleněno ze souboru entity_manager.php pro snížení velikosti souboru
 *       a přehledné oddělení čtecí/UI logiky od transakčního zápisu do DB.
 *
 * VAZBY NA OKOLÍ:
 * - Inkludován a používán výhradně uvnitř třídy `entity_manager` (`entity_manager.php`).
 * - Využívá třídu `rich_text` (`rich_text.php`) pro formátované sloupce (`is_html = 1`)
 *   a třídu `svg_icon_editor` (`svg_icon_editor.php`) pro validaci a sanitizaci `svg_icon`.
 * - Volán z `abstract_page_master_detail::process_save()` a `page_approval::process_save()`.
 *
 * Změny:
 * 2026-11-04 15:15 - Doplněno ukládání a serverová validace svg_icon, automatické
 *                    odvození builtin_code z názvu/zkratky u NEW (s rozlišovacím
 *                    sufixem _2, _3 při kolizi), kontrola jednoznačnosti is_default = 1,
 *                    automatické vygenerování n stupňů v scale_value při založení škály
 *                    a validace intervalu 0..100 % a přísné monotonie v scale_value.
 * 2026-11-04 10:30 - Sjednocení validace klíčového sloupce builtin_code.
 * =============================================================================
 */

declare(strict_types=1);

if (file_exists(__DIR__ . '/rich_text.php')) {
	require_once __DIR__ . '/rich_text.php';
}
if (file_exists(__DIR__ . '/svg_icon_editor.php')) {
	require_once __DIR__ . '/svg_icon_editor.php';
}

trait entity_manager_write {

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
	 * Pomocná metoda: Odvodí bezpečný ASCII identifikátor `builtin_code` ze zkratky nebo názvu.
	 */
	private function derive_builtin_code_from_post(): string {               // Automatické odvození builtin_code z názvu/zkratky
		$src = trim((string) ($_POST['shortname'] ?? ''));                   // Přednost má vyplněná zkratka (shortname)
		if ($src === '') {                                                   // Pokud zkratka není vyplněna
			$src = trim((string) ($_POST['caption'] ?? ''));                 // Použijeme hlavní název (caption)
		}
		if ($src === '') {                                                   // Pokud není vyplněn ani název
			return '';                                                       // Nelze odvodit
		}
		if (method_exists($this, 'generate_code_from_text')) {               // Pokud je metoda definována v entity_manager.php
			return (string) $this->generate_code_from_text($src);            // Odvození přes metodu třídy
		}
		if (function_exists('generate_code_from_text')) {                    // Pokud existuje globální helper v new_functions.php
			return (string) generate_code_from_text($src);                   // Odvození přes globální funkci
		}
		$ascii = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $src);           // Převod diakritiky na čisté ASCII
		$clean = strtolower((string) ($ascii !== false ? $ascii : $src));    // Převod na malá písmena
		$clean = (string) preg_replace('/[^a-z0-9]+/', '_', $clean);         // Nahrazení nečíselných a nepísmenných znaků podtržítkem
		$clean = trim($clean, '_');                                          // Oříznutí okrajových podtržítek
		return substr($clean !== '' ? $clean : 'item', 0, 60);               // Vrácení neprázdného kódu (max 60 znaků)
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
				$ins_vals[] = (string) $row_map[$col];                       // SQL literál nebo výraz hodnoty
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
			$sel_vals[] = array_key_exists($col, $override_map) ? (string) $override_map[$col] : "[$col]"; // Nová nebo původní hodnota
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
			'logo_data', 'logo_filename', 'logo_mime_type'
		];                                                                   // Konec seznamu technických sloupců (svg_icon je povolen!)

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

			$raw_val = (string) $_POST[$colname];                            // Surová hodnota z formuláře
			if (in_array($colname, $trim_cols, true)) {                      // Pokud jde o klíčový nebo kódový sloupec
				$raw_val = trim($raw_val);                                   // Vždy odstraníme počáteční a koncové mezery
				$_POST[$colname] = $raw_val;                                 // Propíšeme očištěnou hodnotu zpět do $_POST
			}

			if ($this->storage_table === 'meta_phrase' AND $colname === 'source_code' AND $raw_val === '') { // Zákaz prázdného source_code
				$raw_val = 'global_phrase';                                  // Přesměrování prázdného zdroje na global_phrase
			}

			// Serverová validace a sanitizace vektorové ikony svg_icon
			if ($colname === 'svg_icon') {                                   // Ošetření SVG kódu ikony
				$raw_val = trim($raw_val);                                   // Oříznutí bílých znaků kolem SVG
				if ($raw_val !== '' AND class_exists('svg_icon_editor')) {   // Pokud je k dispozici validátor SVG
					if (method_exists('svg_icon_editor', 'sanitize_svg')) {  // Metoda sanitize_svg
						$raw_val = (string) svg_icon_editor::sanitize_svg($raw_val); // Sanitizace SVG
					} elseif (method_exists('svg_icon_editor', 'validate_and_sanitize')) { // Alternativní metoda
						$raw_val = (string) svg_icon_editor::validate_and_sanitize($raw_val); // Sanitizace SVG
					}
				}
			}

			// Ošetření a případná konverze formátovaného textu (Markdown / HTML) přes třídu rich_text
			if (! empty($meta['is_html']) AND class_exists('rich_text')) {   // Pokud sloupec podporuje formátovaný text
				$fmt_key_target = $colname . '__target_format';              // Primární klíč cílového formátu z rich_text
				$fmt_key_a = $colname . '_format';                           // Záložní klíč formátu 1
				$fmt_key_b = $colname . '__format';                          // Záložní klíč formátu 2
				$fmt_key_c = 'rt_format_' . $colname;                        // Záložní klíč formátu 3
				$fmt_hint = (string) ($_POST[$fmt_key_target] ?? $_POST[$fmt_key_a] ?? $_POST[$fmt_key_b] ?? $_POST[$fmt_key_c] ?? 'auto'); // Zvolený režim
				if ($fmt_hint === '') {                                      // Pokud nebyl formát explicitně zvolen
					$fmt_hint = 'auto';                                      // Automatická detekce formátu
				}
				if (method_exists('rich_text', 'normalize_for_storage')) {   // Primární metoda v rich_text.php
					$raw_val = (string) rich_text::normalize_for_storage($raw_val, $fmt_hint); // Konverze a sanitizace pro DB
				} elseif (method_exists('rich_text', 'sanitize_html') AND method_exists('rich_text', 'detect_format')) { // Záložní kombinace
					$det_fmt = (string) rich_text::detect_format($raw_val);  // Detekce formátu uloženého textu
					if ($det_fmt === 'html') {                               // Pokud je obsah ve formátu HTML
						$raw_val = (string) rich_text::sanitize_html($raw_val); // Bezpečnostní sanitizace HTML
					}
				}
			}

			$phys_type = $this->col_types[$colname] ?? '';                   // Fyzický typ sloupce v DB
			$is_not_null = (($this->col_nulls[$colname] ?? '') === 'not null'); // Zda fyzický sloupec zakazuje NULL

			// Typově přesné parsování podle fyzického schématu databáze a metadat
			if (in_array($phys_type, ['uuid', 'uniqueidentifier'], true)) {  // Pokud jde o UUID sloupec
				$guid_lit = guidliteral($raw_val);                           // Převod na bezpečný UUID literál
				$data[$colname] = ($guid_lit === 'NULL' AND $is_not_null) ? '0x00' : $guid_lit; // Ošetření NOT NULL UUID
			} elseif ($meta['input_type'] === 'checkbox' OR $phys_type === 'bit') { // Pokud jde o bitový checkbox
				$data[$colname] = ($raw_val === '1' OR strtolower($raw_val) === 'true') ? 1 : 0; // Bitová hodnota 1 nebo 0
			} elseif (in_array($phys_type, ['int', 'smallint', 'tinyint', 'bigint'], true)) { // Celočíselné sloupce
				$int_lit = intliteral($raw_val, 0);                          // Převod na celé číslo nebo NULL
				$data[$colname] = ($int_lit === 'NULL' AND $is_not_null) ? '0' : $int_lit; // Ošetření NOT NULL sloupců
			} elseif ($meta['input_type'] === 'number' OR in_array($phys_type, ['decimal', 'numeric', 'float', 'real', 'money'], true)) { // Desetinná čísla
				$norm_num = str_replace(',', '.', trim($raw_val));           // Podpora desetinné čárky i tečky
				$data[$colname] = ($norm_num === '' OR ! is_numeric($norm_num)) ? ($is_not_null ? '0' : 'NULL') : (string) (float) $norm_num; // Číselný literál
			} elseif (in_array($phys_type, ['date', 'datetime', 'datetime2', 'smalldatetime'], true)) { // Datumové sloupce
				$dt_lit = dateliteral($raw_val);                             // Převod na bezpečný datumový SQL literál
				$data[$colname] = ($dt_lit === 'NULL' AND $is_not_null) ? "'1970-01-01'" : $dt_lit; // Fallback pro NOT NULL datum
			} else {
				$data[$colname] = charliteral($raw_val);                     // Převod na bezpečný textový literál
			}
		}

		// Pojistka: Pokud by sloupec removed chyběl v columns_meta, ale fyzicky v tabulce existuje a přišel v POSTu
		if (! isset($data['removed']) AND isset($_POST['removed']) AND in_array('removed', $this->physical_cols, true)) { // Kontrola removed v POSTu
			$raw_rem = (string) $_POST['removed'];                           // Surová hodnota removed z formuláře
			$data['removed'] = ($raw_rem === '1' OR strtolower($raw_rem) === 'true') ? 1 : 0; // Převod na bit 1/0
		}

		return $data;                                                        // Vrácení připravených dat
	}

	/**
	 * Validuje prahové hodnoty (`threshold_value`) a skóre (`score_value`) v tabulce `scale_value`:
	 * 1. Interval `0 <= threshold_value <= score_value <= 100`.
	 * 2. Nejnižší stupeň škály musí mít `threshold_value = 0`.
	 * 3. Přísná monotonie prahů i skóre napříč všemi platnými stupni dané škály.
	 */
	private function validate_scale_value_monotonicity(string $orig_guid_sql, string $rec_owner_sql, array $src_data): bool { // Kontrola monotonie scale_value
		$scale_lit = (string) ($src_data['scale'] ?? 'NULL');                // SQL literál nadřazené škály
		if ($scale_lit === 'NULL' OR $scale_lit === '0x00') {                // Kontrola vyplnění škály
			$this->set_last_save_error($this->phrase('err_scale_missing', 'Musí být zvolena nadřazená hodnotící škála (scale).')); // Chyba
			return false;                                                    // Neplatná škála
		}

		$thr_val = (float) ($src_data['threshold_value'] ?? 0.0);            // Zadaná dolní prahová hodnota v %
		$scr_val = (float) ($src_data['score_value'] ?? 0.0);                // Zadaná hodnota skóre v %

		if ($thr_val < 0.0 OR $thr_val > 100.0 OR $scr_val < 0.0 OR $scr_val > 100.0) { // Kontrola intervalu 0..100 %
			$this->set_last_save_error($this->phrase('err_scale_val_range', 'Prahová hodnota (threshold_value) i skóre (score_value) musí ležet v procentuálním intervalu 0 až 100 %.')); // Chyba rozsahu
			return false;                                                    // Mimo rozsah 0..100
		}

		if ($scr_val < $thr_val) {                                           // Skóre nesmí být menší než dolní práh téhož stupně
			$this->set_last_save_error($this->phrase('err_scale_score_below_threshold', 'Hodnota skóre (score_value) nesmí být menší než dolní prahová hodnota (threshold_value) daného stupně.')); // Chyba
			return false;                                                    // Porušení intervalu stupně
		}

		$excl_self = ($orig_guid_sql !== '' AND $orig_guid_sql !== 'NULL') ? "AND a.original <> {$orig_guid_sql}" : ""; // Vyloučení právě upravovaného stupně
		$existing_levels = sqlarray_simple("
			SELECT original, builtin_code, caption, threshold_value, score_value
			FROM (
				SELECT a.original, a.builtin_code, a.caption, a.threshold_value, a.score_value,
					ROW_NUMBER() OVER (PARTITION BY a.original ORDER BY CASE WHEN a.object_owner = {$rec_owner_sql} THEN 0 ELSE 1 END) AS rn
				FROM scale_value a
				WHERE a.scale = {$scale_lit}
				  AND a.object_owner IN (0x00, {$rec_owner_sql})
				  AND a.record_type = 'A'
				  AND a.removed = 0
				  {$excl_self}
			) x
			WHERE x.rn = 1
			ORDER BY threshold_value ASC
		");                                                                  // Načtení ostatních platných stupňů škály

		$all_levels = [];                                                    // Pole všech stupňů včetně ukládaného záznamu
		if (is_array($existing_levels)) {                                    // Přidání existujících stupňů
			foreach ($existing_levels as $el) {                              // Průchod existujícími stupni
				$el_thr = (float) $el['threshold_value'];                    // Práh existujícího stupně
				if (abs($el_thr - $thr_val) < 0.00005) {                     // Kontrola duplicitního prahu ve škále
					$dup_lbl = (string) ($el['caption'] ?: $el['builtin_code']); // Označení kolidujícího stupně
					$this->set_last_save_error($this->phrase(
						'err_scale_duplicate_threshold',
						'Stupeň se shodnou prahovou hodnotou ({' . chr(36) . 'thr} %) již v této škále existuje ({' . chr(36) . 'name}). Prahové hodnoty musí tvořit rostoucí řadu.',
						['thr' => number_format($thr_val, 2, '.', ''), 'name' => $dup_lbl]
					));                                                      // Chybová hláška duplicitního prahu
					return false;                                            // Zastavení zápisu
				}
				$all_levels[] = [                                            // Zařazení existujícího stupně do kontroly
					'thr'  => $el_thr,
					'scr'  => (float) $el['score_value'],
					'name' => (string) ($el['caption'] ?: $el['builtin_code'])
				];
			}
		}

		$cur_name = $this->unquote_sql_literal((string) ($src_data['caption'] ?? $src_data['builtin_code'] ?? '')); // Název ukládaného stupně
		$all_levels[] = [                                                    // Přidání právě ukládaného stupně
			'thr'  => $thr_val,
			'scr'  => $scr_val,
			'name' => ($cur_name !== '' ? $cur_name : 'Nový stupeň')
		];

		usort($all_levels, function (array $a, array $b): int {              // Seřazení všech stupňů vzestupně podle prahu
			return ($a['thr'] <=> $b['thr']);                                // Porovnání prahových hodnot
		});

		if ($all_levels[0]['thr'] > 0.00005) {                               // Nejnižší stupeň škály musí začínat na 0 %
			$this->set_last_save_error($this->phrase('err_scale_first_threshold_zero', 'Nejnižší stupeň hodnotící škály musí mít dolní prahovou hodnotu (threshold_value) rovnu 0 %.')); // Chyba
			return false;                                                    // Chybí nulový počátek škály
		}

		$cnt = count($all_levels);                                           // Celkový počet stupňů škály
		for ($i = 0; $i < $cnt; $i++) {                                      // Kontrola monotonie a intervalů všech stupňů
			$curr = $all_levels[$i];                                         // Aktuálně kontrolovaný stupeň
			$next_thr = ($i + 1 < $cnt) ? $all_levels[$i + 1]['thr'] : 100.0; // Horní mez intervalu (práh dalšího stupně nebo 100 %)

			if ($curr['scr'] > $next_thr + 0.00005) {                        // Skóre přesahuje práh následujícího stupně
				$this->set_last_save_error($this->phrase(
					'err_scale_score_exceeds_next_threshold',
					'Hodnota skóre ({' . chr(36) . 'scr} %) u stupně „{' . chr(36) . 'name}“ přesahuje prahovou hodnotu následujícího stupně ({' . chr(36) . 'next} %).',
					['scr' => number_format($curr['scr'], 2, '.', ''), 'name' => $curr['name'], 'next' => number_format($next_thr, 2, '.', '')]
				));                                                          // Chybová hláška překročení intervalu
				return false;                                                // Zastavení zápisu
			}

			if ($i > 0 AND $curr['scr'] <= $all_levels[$i - 1]['scr'] + 0.00005) { // Skóre není ostře větší než u předchozího stupně
				$prev = $all_levels[$i - 1];                                 // Předchozí stupeň
				$this->set_last_save_error($this->phrase(
					'err_scale_score_not_monotonic',
					'Hodnoty skóre musí tvořit rostoucí řadu: stupeň „{' . chr(36) . 'name}“ ({' . chr(36) . 'scr} %) musí mít vyšší skóre než předchozí stupeň „{' . chr(36) . 'prev_name}“ ({' . chr(36) . 'prev_scr} %).',
					['name' => $curr['name'], 'scr' => number_format($curr['scr'], 2, '.', ''), 'prev_name' => $prev['name'], 'prev_scr' => number_format($prev['scr'], 2, '.', '')]
				));                                                          // Chybová hláška porušení monotonie skóre
				return false;                                                // Zastavení zápisu
			}
		}

		return true;                                                         // Všechny kontroly monotonie prošly
	}

	/**
	 * Spustí post-processing operace po uložení schváleného záznamu ('A'):
	 * 1. U tabulky `link` zmaterializuje odvozené vazby (`dbo.p_sync_derived_links`).
	 * 2. U číselníků a škál se zaškrtnutým `is_default = 1` vynuluje `is_default` na ostatních sourozencích.
	 * 3. U nově založené hodnotící škály (`scale`) vygeneruje $n$ výchozích stupňů v `scale_value` (`0..100 %`).
	 */
	private function run_post_save_hooks(string $orig_guid_sql, string $rec_owner_sql = '0x00', string $lang_sql = "'cs'", string $user_uuid_sql = '0x00'): void { // Návazné operace
		if ($orig_guid_sql === '' OR $orig_guid_sql === 'NULL') {            // Kontrola platného SQL literálu originálu
			return;                                                          // Ukončení bez volání procedur
		}

		$table = $this->storage_table;                                       // Fyzická tabulka entity

		// 1. Materializace zděděných vazeb v tabulce link
		if ($table === 'link') {                                             // Pouze pro tabulku link
			$p_row = sqlfirstrow("SELECT OBJECT_ID('p_sync_derived_links', 'P') AS pid"); // Ověření existence procedury
			if (! empty($p_row['pid'])) {                                    // Pokud procedura v DB existuje
				sqlrun("EXEC dbo.p_sync_derived_links @root_link_original = {$orig_guid_sql}"); // Přepočet odvozených vazeb
			}
			return;                                                          // Konec pro tabulku link
		}

		// 2. Zajištění jednoznačnosti výchozí položky (is_default = 1) u číselníků a škál
		if (in_array('is_default', $this->physical_cols, true)) {            // Pokud tabulka obsahuje sloupec is_default
			$saved_rec = sqlfirstrow("SELECT TOP 1 * FROM [{$table}] WHERE original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type = 'A' AND removed = 0"); // Načtení uloženého A záznamu
			if (! empty($saved_rec) AND ! empty($saved_rec['is_default'])) { // Pokud má záznam nastaveno is_default = 1
				if ($table === 'countermeasure_state') {                     // Plochý číselník stavů protiopatření
					sqlrun("UPDATE countermeasure_state SET is_default = 0 WHERE object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních
				} elseif ($table === 'scale_value') {                        // Stupně v rámci jedné hodnotící škály
					$sc_sql = guidliteral((string) $saved_rec['scale']);     // SQL literál nadřazené škály
					sqlrun("UPDATE scale_value SET is_default = 0 WHERE scale = {$sc_sql} AND object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních ve škále
				} elseif ($table === 'scale') {                              // Hodnotící škála v rámci téhož scale_type
					$st_sql = charliteral((string) $saved_rec['scale_type'], 20); // SQL literál druhu škály
					sqlrun("UPDATE scale SET is_default = 0 WHERE scale_type = {$st_sql} AND object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních téhož druhu
				} elseif ($table === 'hierarchy_item') {                     // Položka sekundární hierarchie (vynulujeme u jednohodnotových hierarchií s multiple = 0)
					$h_sql = guidliteral((string) $saved_rec['hierarchy']);  // SQL literál nadřazené hierarchie
					$h_row = sqlfirstrow("SELECT TOP 1 multiple FROM hierarchy WHERE original = {$h_sql} AND record_type = 'A' AND removed = 0 ORDER BY CASE WHEN object_owner = {$rec_owner_sql} THEN 0 ELSE 1 END"); // Zjištění příznaku multiple
					if (! empty($h_row) AND empty($h_row['multiple'])) {     // Jednohodnotový číselník (multiple = 0)
						sqlrun("UPDATE hierarchy_item SET is_default = 0 WHERE hierarchy = {$h_sql} AND object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních
					}
				}
			}
		}

		// 3. Automatické vygenerování n rovnoměrných stupňů v scale_value (0..100 %) při prvním uložení nové škály v scale
		if ($table === 'scale' AND in_array('initial_levels', $this->physical_cols, true)) { // Pouze pro tabulku scale
			$sc_row = sqlfirstrow("SELECT TOP 1 initial_levels, [language] FROM scale WHERE original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type = 'A' AND removed = 0"); // Načtení škály
			$cnt_ex = sqlfirstrow("SELECT COUNT(1) AS cnt FROM scale_value WHERE scale = {$orig_guid_sql} AND record_type = 'A' AND removed = 0"); // Počet existujících stupňů
			$existing_cnt = (int) ($cnt_ex['cnt'] ?? 0);                     // Zjištěný počet stupňů

			if (! empty($sc_row) AND $existing_cnt === 0) {                  // Škála zatím nemá žádné stupně -> vygenerujeme je
				$n = (int) ($sc_row['initial_levels'] ?? 4);                 // Požadovaný počet stupňů
				if ($n < 2) {                                                // Minimálně 2 stupně
					$n = 2;                                                  // Dolní mez počtu stupňů
				} elseif ($n > 20) {                                         // Maximálně 20 stupňů
					$n = 20;                                                 // Horní mez počtu stupňů
				}

				$sc_lang = (string) ($sc_row['language'] ?? 'cs');           // Jazyk škály
				$sc_lang_sql = charliteral($sc_lang, 2);                     // SQL literál jazyka škály
				$lbl_prefix = ($sc_lang === 'en') ? 'Level ' : 'Stupeň ';    // Výchozí pojmenování stupně podle jazyka
				$step_w = 100.0 / $n;                                        // Šířka jednoho intervalu v procentech

				for ($i = 1; $i <= $n; $i++) {                               // Generování stupňů 1..n
					$thr = round(($i - 1) * $step_w, 4);                     // Dolní práh intervalu: (i - 1) * (100 / n)
					$scr = round(($i - 0.5) * $step_w, 4);                   // Střed intervalu (skóre): (i - 0.5) * (100 / n)
					$b_code = 'l' . $i;                                      // Kód stupně ('l1', 'l2'...)
					$s_name = 'L' . $i;                                      // Zkratka stupně ('L1', 'L2'...)
					$cap_txt = $lbl_prefix . $i;                             // Název stupně ('Stupeň 1'...)
					$is_def = ($i === 1) ? 1 : 0;                            // První stupeň nastavíme jako výchozí

					$safe_bc = charliteral($b_code, 80);                     // SQL literál builtin_code
					$safe_sn = charliteral($s_name, 40);                     // SQL literál shortname
					$safe_cp = charliteral($cap_txt, 200);                   // SQL literál caption
					$thr_sql = number_format($thr, 4, '.', '');              // SQL literál threshold_value
					$scr_sql = number_format($scr, 4, '.', '');              // SQL literál score_value

					$sv_orig_row = sqlfirstrow("SELECT dbo.f_generate_original('scale_value', {$rec_owner_sql}, CAST({$orig_guid_sql} AS varchar(36)), {$safe_bc}) AS orig"); // Deterministický originál stupně
					$sv_orig_sql = guidliteral((string) ($sv_orig_row['orig'] ?? generateUUID())); // SQL literál originálu stupně

					sqlrun("
						INSERT INTO scale_value (
							uuid, object_owner, original, record_type, approval_status, [language],
							scale, builtin_code, caption, shortname, threshold_value, score_value, is_default,
							date_created, who_created, date_modified, who_modified
						) VALUES (
							{$sv_orig_sql}, {$rec_owner_sql}, {$sv_orig_sql}, 'A', 'A', {$sc_lang_sql},
							{$orig_guid_sql}, {$safe_bc}, {$safe_cp}, {$safe_sn}, {$thr_sql}, {$scr_sql}, {$is_def},
							GETDATE(), {$user_uuid_sql}, GETDATE(), {$user_uuid_sql}
						);
						INSERT INTO scale_value (
							uuid, object_owner, original, record_type, approval_status, [language],
							scale, builtin_code, caption, shortname, threshold_value, score_value, is_default,
							date_created, who_created, date_modified, who_modified
						) VALUES (
							NEWID(), {$rec_owner_sql}, {$sv_orig_sql}, 'L', 'A', {$sc_lang_sql},
							{$orig_guid_sql}, {$safe_bc}, {$safe_cp}, {$safe_sn}, {$thr_sql}, {$scr_sql}, {$is_def},
							GETDATE(), {$user_uuid_sql}, GETDATE(), {$user_uuid_sql}
						);
					");                                                      // Vložení 'A' i symetrického 'L' záznamu stupně škály
				}
			}
		}
	}

	/**
	 * JÁDRO BACKENDU: Provede autonomní zápis dat s podporou schvalovacího cyklu (SSC),
	 * validací neprázdnosti a unikátnosti klíčových položek a architektury "Klonování s modifikací".
	 */
	public function save_post_data(string $update_guid = '', string $target_status = 'A'): string { // Autonomní uložení dat
		$this->set_last_save_error('');                                      // Vynulování předchozí chybové zprávy
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

		$org_uuid_raw = (string) $dbsession['organization'];                 // Surové UUID organizace v relaci
		$user_uuid_raw = (string) $dbsession['login_session_uuid'];          // Surové UUID relace pro audit
		$user_acc_raw = (string) ($dbsession['user_account'] ?? '0x00');     // Surové UUID účtu uživatele (pro draft_author)
		$sess_lang_raw = (string) $dbsession['language'];                    // Surový kód jazyka relace
		$active_role = (string) ($dbsession['active_role'] ?? 'U');          // Aktuální role v relaci
		$right_translate = ! empty($dbsession['right_translate']);           // Oprávnění ke globálnímu překladu

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

		$is_sysadmin_org = is_sys_org($org_uuid_raw);                        // Příznak systémového tenanta (0x00)

		// Určení efektivního vlastníka záznamu (u tabulky organization je vlastníkem samotný original organizace)
		$rec_owner_raw = ($is_self_owned AND $orig_guid_raw !== '') ? $orig_guid_raw : $org_uuid_raw; // Surový vlastník záznamu
		$rec_owner_sql = guidliteral($rec_owner_raw);                        // SQL literál vlastníka záznamu

		// Automatické odvození prázdného builtin_code u nového záznamu (NEW) z názvu/zkratky
		$was_code_auto_derived = false;                                      // Příznak automaticky odvozeného kódu
		if ($orig_guid_sql === '' AND ! $is_meta_table AND in_array('builtin_code', $this->physical_cols, true)) { // Nový věcný záznam
			$cur_bcode = $this->unquote_sql_literal((string) ($post_data['builtin_code'] ?? '')); // Zadaný builtin_code
			$auto_candidate = $this->derive_builtin_code_from_post();        // Kandidát odvozený ze shortname / caption
			if ($cur_bcode === '' AND $auto_candidate !== '') {              // Pokud zůstal prázdný, dosadíme odvozený
				$post_data['builtin_code'] = charliteral($auto_candidate, 80); // SQL literál odvozeného kódu
				$_POST['builtin_code'] = $auto_candidate;                    // Propis do $_POST
				$was_code_auto_derived = true;                               // Označení pro případné rozlišení sufixem _2, _3
			} elseif ($cur_bcode !== '' AND $cur_bcode === $auto_candidate) { // Pokud jej vygeneroval klientský JS ze stejného názvu
				$was_code_auto_derived = true;                               // Povolíme automatický sufix při kolizi
			}
		}

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
				$a_exists = ((string) $current_row['object_owner'] === $rec_owner_raw OR $is_sysadmin_org); // Zda záznam patří tenantovi
				$orig_owner_raw = (string) $current_row['object_owner'];     // Uložení vlastníka záznamu
				$a_uuid_sql = guidliteral((string) $current_row['uuid']);    // Uložení UUID 'A' záznamu
				$a_lang_raw = (string) $current_row['language'];             // Mateřský jazyk 'A' záznamu
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
						$anc_raw = trim((string) $anc_val, "'");             // Očištění UUID předka
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
			if (isset($post_data['is_leaf']) AND (int) $post_data['is_leaf'] === 1) { // Pokus o nastavení is_leaf = 1
				$has_ch = sqlfirstrow("SELECT TOP 1 1 AS ex FROM [{$table}] WHERE parent_uuid = {$orig_guid_sql} AND record_type = 'A' AND removed = 0"); // Kontrola potomků
				if (! empty($has_ch)) {                                      // Uzel má aktivní podřízené položky
					$post_data['is_leaf'] = 0;                               // Složka s potomky musí mít is_leaf = 0
				}
			}
		}

		// Vyhodnocení oprávnění pro změnu příznaku removed
		$requested_removed = null;                                           // Požadovaná hodnota removed z formuláře
		if (array_key_exists('removed', $post_data)) {                       // Pokud formulář odeslal sloupec removed
			$requested_removed = (int) $post_data['removed'];                // Požadovaný stav 0 nebo 1
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
				$compare_val = str_replace("''", "'", trim((string) $val, "'")); // Hodnota k porovnání bez vnějších apostrofů

				if (isset($this->col_nulls[$col]) AND $this->col_nulls[$col] !== 'not null') { // Pokud sloupec povoluje NULL
					if ((string) $compare_val === (string) $baseline_val) {  // Shoda s hodnotou předlohy
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
		// VALIDACE MONOTONIE A ROZSAHU 0..100 % PRO TABULKU scale_value
		// =====================================================================
		if ($table === 'scale_value') {                                      // Kontrola stupně hodnotící škály
			$sv_check_data = $current_row;                                   // Výchozí hodnoty z existujícího řádku (pro UPDATE)
			foreach (($a_post_data + $d_post_data) as $k_sv => $v_sv) {      // Přepsání novými hodnotami z POSTu
				$sv_check_data[$k_sv] = $v_sv;                               // Aktualizovaná hodnota sloupce
			}
			if (isset($sv_check_data['scale']) AND ! str_starts_with((string) $sv_check_data['scale'], "'") AND (string) $sv_check_data['scale'] !== '0x00') { // Normalizace UUID škály
				$sv_check_data['scale'] = guidliteral((string) $sv_check_data['scale']); // SQL literál škály
			}
			$is_being_removed = (! empty($a_post_data['removed']) OR ! empty($d_post_data['removed'])); // Při rušení stupně monotonii neblokujeme
			if (! $is_being_removed AND ! $this->validate_scale_value_monotonicity($orig_guid_sql, $rec_owner_sql, $sv_check_data)) { // Validace
				return '';                                                   // Zastavení zápisu při porušení monotonie nebo rozsahu
			}
		}

		// =====================================================================
		// VALIDACE KLÍČOVÝCH POLOŽEK A UNIKÁTNOSTI ORIGINÁLU U NOVÉHO ZÁZNAMU
		// =====================================================================
		if ($orig_guid_sql === '') {                                         // Zakládání zcela nového záznamu (update_guid === 'NEW')
			$src_key_data = ! empty($a_post_data) ? $a_post_data : $d_post_data; // Pole hodnot pro výpočet klíče
			$key_info = sqlfirstrow("SELECT key1_column, key2_column FROM meta_original_keys WHERE table_name = " . charliteral($table)); // Dotaz na klíčové sloupce

			if (! empty($key_info)) {                                        // Tabulka má deterministický klíč v meta_original_keys
				$k1_col = (string) $key_info['key1_column'];                 // Název 1. klíčového sloupce (např. builtin_code, hierarchy, scale)
				$k2_col = (string) ($key_info['key2_column'] ?? '');         // Název volitelného 2. klíčového sloupce

				$k1_val = array_key_exists($k1_col, $src_key_data) ? (string) $src_key_data[$k1_col] : "''"; // SQL literál 1. klíče
				$k1_plain = $this->unquote_sql_literal($k1_val);             // Čistá textová hodnota 1. klíče
				$k1_mand = $this->is_key_column_mandatory($k1_col) OR ! empty($src_key_data['is_template']); // Zda je 1. klíč povinný

				if ($k1_plain === '' AND $k1_mand) {                         // Povinný 1. klíčový sloupec je prázdný
					$k1_meta = $this->columns_meta[$k1_col] ?? [];           // Metadata 1. klíčového sloupce
					$k1_lbl = (string) ($k1_meta['label'] ?? $k1_meta['caption'] ?? $k1_col); // Popisek sloupce
					$err_empty = $this->phrase(
						'err_key_col_empty',
						'Klíčová položka „{' . chr(36) . 'label}“ ({' . chr(36) . 'col}) nesmí být prázdná.',
						['label' => $k1_lbl, 'col' => $k1_col]
					);                                                       // Lokalizovaná hláška prázdného klíče
					$this->set_last_save_error($err_empty);                  // Uložení chyby pro zobrazení v detailu
					return '';                                               // Zastavení zápisu bez provedení INSERTu
				}

				$k2_val = 'NULL';                                            // Výchozí SQL hodnota 2. klíče
				$k2_plain = '';                                              // Výchozí čistá hodnota 2. klíče
				if ($k2_col !== '') {                                        // Pokud má tabulka definovaný i 2. klíčový sloupec
					$k2_val = array_key_exists($k2_col, $src_key_data) ? (string) $src_key_data[$k2_col] : "''"; // SQL literál 2. klíče
					$k2_plain = $this->unquote_sql_literal($k2_val);         // Čistá textová hodnota 2. klíče
					$k2_mand = $this->is_key_column_mandatory($k2_col) OR ! empty($src_key_data['is_template']); // Zda je 2. klíč povinný

					if ($k2_plain === '' AND $k2_mand) {                     // Povinný 2. klíčový sloupec je prázdný
						$k2_meta = $this->columns_meta[$k2_col] ?? [];       // Metadata 2. klíčového sloupce
						$k2_lbl = (string) ($k2_meta['label'] ?? $k2_meta['caption'] ?? $k2_col); // Popisek sloupce
						$err_empty2 = $this->phrase(
							'err_key_col_empty',
							'Klíčová položka „{' . chr(36) . 'label}“ ({' . chr(36) . 'col}) nesmí být prázdná.',
							['label' => $k2_lbl, 'col' => $k2_col]
						);                                                   // Lokalizovaná hláška prázdného 2. klíče
						$this->set_last_save_error($err_empty2);             // Uložení chyby pro zobrazení v detailu
						return '';                                           // Zastavení zápisu
					}
				}

				$has_all_keys = ($k1_plain !== '' AND ($k2_col === '' OR $k2_plain !== '')); // Zda jsou klíčové sloupce vyplněny

				if ($has_all_keys) {                                         // Klíče jsou vyplněny -> spočítáme deterministický originál a ověříme unikátnost
					$base_auto_code = ($k2_col === 'builtin_code') ? $k2_plain : $k1_plain; // Základ pro případný sufix _2, _3
					$attempt = 1;                                            // Počitadlo pokusů při automatickém rozlišení kolize
					$dup_row = [];                                           // Nalezený kolizní řádek

					while ($attempt <= 50) {                                 // Hledání volného sufixu u automaticky odvozeného builtin_code
						$orig_row = sqlfirstrow("SELECT dbo.f_generate_original(" . charliteral($table) . ", {$rec_owner_sql}, CAST({$k1_val} AS VARCHAR(MAX)), CAST({$k2_val} AS VARCHAR(MAX))) AS orig_guid"); // Výpočet hashe
						if (! empty($orig_row)) {                            // Načtení vypočteného originálu
							$orig_guid_raw = (string) $orig_row['orig_guid']; // Surové UUID originálu
							$orig_guid_sql = guidliteral($orig_guid_raw);    // Deterministické UUID originálu
						}

						$k1_cond_sql = "LOWER(LTRIM(RTRIM(CAST([{$k1_col}] AS VARCHAR(MAX))))) = LOWER(LTRIM(RTRIM(CAST({$k1_val} AS VARCHAR(MAX)))))"; // Podmínka 1. klíče
						$k2_cond_sql = ($k2_col !== '')
							? " AND LOWER(LTRIM(RTRIM(CAST([{$k2_col}] AS VARCHAR(MAX))))) = LOWER(LTRIM(RTRIM(CAST({$k2_val} AS VARCHAR(MAX)))))"
							: "";                                            // Podmínka 2. klíče

						$dup_row = sqlfirstrow("
							SELECT TOP 1 uuid, original, record_type, removed, object_owner
							FROM [{$table}]
							WHERE uuid = {$orig_guid_sql}
							   OR (original = {$orig_guid_sql} AND object_owner IN (0x00, {$rec_owner_sql}) AND record_type IN ('A', 'D'))
							   OR (record_type IN ('A', 'D') AND object_owner IN (0x00, {$rec_owner_sql}) AND {$k1_cond_sql}{$k2_cond_sql})
							ORDER BY removed ASC, CASE WHEN record_type = 'A' THEN 0 ELSE 1 END ASC
						");                                                  // Kontrola duplicitního záznamu v tabulce

						if (empty($dup_row) OR ! $was_code_auto_derived) {   // Pokud je kód unikátní nebo byl zadán ručně
							break;                                           // Ukončíme smyčku
						}

						$attempt++;                                          // Zkusíme další rozlišovací příponu (_2, _3...)
						$next_code = substr($base_auto_code, 0, 70) . '_' . $attempt; // Nový kandidátní builtin_code
						$next_lit = charliteral($next_code, 80);             // SQL literál nového kandidáta
						if ($k2_col === 'builtin_code') {                    // Pokud je builtin_code druhým klíčem (hierarchy_item, scale_value)
							$k2_plain = $next_code;                          // Aktualizace čisté hodnoty 2. klíče
							$k2_val = $next_lit;                             // Aktualizace SQL literálu 2. klíče
						} else {
							$k1_plain = $next_code;                          // Aktualizace čisté hodnoty 1. klíče
							$k1_val = $next_lit;                             // Aktualizace SQL literálu 1. klíče
						}
						if (isset($a_post_data['builtin_code'])) {           // Propis rozlišeného kódu do ukládaných A dat
							$a_post_data['builtin_code'] = $next_lit;        // Nový builtin_code pro A
						}
						if (isset($d_post_data['builtin_code'])) {           // Propis rozlišeného kódu do ukládaných D dat
							$d_post_data['builtin_code'] = $next_lit;        // Nový builtin_code pro D
						}
						$_POST['builtin_code'] = $next_code;                 // Propis do $_POST
					}

					if (! empty($dup_row)) {                                 // Nalezen kolizní záznam se shodným klíčem / originálem
						$key_desc = ($k2_col !== '') ? "{$k1_col}='{$k1_plain}', {$k2_col}='{$k2_plain}'" : "{$k1_col}='{$k1_plain}'"; // Popis klíče
						if (! empty($dup_row['removed'])) {                  // Kolizní záznam leží v koši (removed = 1)
							$err_dup_trash = $this->phrase(
								'err_duplicate_key_in_trash',
								'Záznam se zadanou klíčovou položkou ({' . chr(36) . 'keys}) již existuje v koši (zrušené záznamy). Zapněte v levém panelu „Zobrazit i zrušené“ a záznam obnovte, nebo zvolte jiný unikátní kód.',
								['keys' => $key_desc]
							);                                               // Hláška pro záznam v koši
							$this->set_last_save_error($err_dup_trash);      // Uložení chyby
						} else {
							$err_dup_active = $this->phrase(
								'err_duplicate_key_active',
								'Záznam se zadanou klíčovou položkou ({' . chr(36) . 'keys}) již v databázi existuje. Zadejte unikátní hodnotu, aby nedošlo k výpočtu duplicitního originálu.',
								['keys' => $key_desc]
							);                                               // Hláška pro aktivní duplicitní záznam
							$this->set_last_save_error($err_dup_active);     // Uložení chyby
						}
						return '';                                           // Zastavení zápisu před vznikem SQL chyby
					}

					// Speciální kontrola pro tabulku hierarchy: builtin_code se propisuje jako class_name do meta_class
					if ($table === 'hierarchy') {                            // Kontrola kolize kódu hierarchie s tabulkou meta_class
						$cls_dup = sqlfirstrow("
							SELECT TOP 1 class_name
							FROM meta_class
							WHERE LOWER(LTRIM(RTRIM(class_name))) = LOWER(LTRIM(RTRIM(CAST({$k1_val} AS VARCHAR(80)))))
							  AND object_owner IN (0x00, {$rec_owner_sql})
							  AND record_type = 'A'
						");                                                  // Dotaz na existenci třídy v meta_class
						if (! empty($cls_dup)) {                             // Kód již obsadila jiná logická třída v meta_class
							$err_cls_col = $this->phrase(
								'err_hierarchy_code_collides_class',
								'Kód hierarchie „{' . chr(36) . 'code}“ koliduje s názvem již existující logické třídy v meta_class. Zvolte prosím jiný unikátní kód.',
								['code' => $k1_plain]
							);                                               // Chybová hláška kolize s meta_class
							$this->set_last_save_error($err_cls_col);        // Uložení chyby
							return '';                                       // Zastavení zápisu
						}
					}
				} else {
					$orig_row = sqlfirstrow("SELECT NEWID() AS orig_guid");  // Náhodný identifikátor při prázdném klíči
					if (! empty($orig_row)) {                                // Načtení vygenerovaného UUID
						$orig_guid_raw = (string) $orig_row['orig_guid'];    // Surové náhodné UUID
						$orig_guid_sql = guidliteral($orig_guid_raw);        // SQL literál náhodného UUID
					}
				}
			} elseif ($table === 'link') {                                   // Speciální 4složkový výpočet a validace pro tabulku link
				$link_def = array_key_exists('link_def', $src_key_data) ? (string) $src_key_data['link_def'] : 'NULL'; // Definice vazby
				$from_obj = array_key_exists('from_object', $src_key_data) ? (string) $src_key_data['from_object'] : 'NULL'; // Zdroj vazby
				$to_obj = array_key_exists('to_object', $src_key_data) ? (string) $src_key_data['to_object'] : 'NULL'; // Cíl vazby
				$anc_link = (array_key_exists('ancestor_link', $src_key_data) AND $src_key_data['ancestor_link'] !== 'NULL') ? (string) $src_key_data['ancestor_link'] : '0x00'; // Předek vazby

				if ($this->unquote_sql_literal($link_def) === '' OR $this->unquote_sql_literal($from_obj) === '' OR $this->unquote_sql_literal($to_obj) === '') { // Chybí složka vazby
					$err_lnk_empty = $this->phrase('err_link_keys_empty', 'Klíčové položky vazby (link_def, from_object, to_object) musí být vyplněny.'); // Hláška
					$this->set_last_save_error($err_lnk_empty);              // Uložení chyby
					return '';                                               // Zastavení zápisu
				}

				$orig_row = sqlfirstrow("SELECT dbo.f_link_original(CAST({$rec_owner_sql} AS varchar(36)), CAST({$link_def} AS varchar(36)), CAST({$from_obj} AS varchar(36)), CAST({$to_obj} AS varchar(36)), CAST({$anc_link} AS varchar(36))) AS orig_guid"); // Výpočet originálu vazby
				if (! empty($orig_row)) {                                    // Načtení originálu vazby
					$orig_guid_raw = (string) $orig_row['orig_guid'];        // Surové UUID vazby
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
					$err_dup_lnk = $this->phrase('err_duplicate_link', 'Tato vazba mezi zvolenými záznamy již existuje.'); // Hláška duplicity vazby
					$this->set_last_save_error($err_dup_lnk);                // Uložení chyby
					return '';                                               // Zastavení zápisu
				}
			} else {
				$orig_row = sqlfirstrow("SELECT NEWID() AS orig_guid");      // Náhodné UUID pro globální tabulky bez deterministického klíče
				if (! empty($orig_row)) {                                    // Načtení nového UUID
					$orig_guid_raw = (string) $orig_row['orig_guid'];        // Surové náhodné UUID
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
				$dr_uuid_sql = guidliteral((string) $dr_row['uuid']);        // UUID existujícího řádku konceptu
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
					$src_a_uuid = guidliteral((string) $src_a_row['uuid']);  // UUID zdrojového 'A' řádku
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
			if (is_zero_guid($orig_owner_raw) AND $right_translate) {        // Oprávněný překladatel u systémového záznamu
				$l_owner_sql = '0x00';                                       // Oprávněný překladatel zapisuje globálně
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

					$sql_l = "UPDATE {$table} SET " . implode(', ', $set_l) . " WHERE uuid = " . guidliteral((string) $l_exists['uuid']); // UPDATE L
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
			$new_org_cap = (string) $a_post_data['caption'];                 // SQL literál nového názvu organizace
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

		// 7. Spuštění návazných operací (materializace link, jednoznačnost is_default, vygenerování stupňů škály)
		$this->run_post_save_hooks($orig_guid_sql, $rec_owner_sql, $lang_literal_sql, $user_uuid_sql); // Návazné operace po uložení

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
		$org_raw = (string) ($dbsession['organization'] ?? '0x00');          // Surové UUID organizace v relaci
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$rec_owner_sql = ($table === 'organization') ? guidliteral($original_guid) : guidliteral($org_raw); // Vlastník záznamu
		$user_acc_sql = guidliteral((string) ($dbsession['user_account'] ?? '0x00')); // SQL literál účtu uživatele
		$lang_sql = charliteral((string) ($dbsession['language'] ?? 'cs'));  // SQL literál jazyka relace
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
		$sess_org_raw = (string) ($dbsession['organization'] ?? '0x00');     // Surové UUID organizace schvalovatele
		$sess_org_sql = guidliteral($sess_org_raw);                          // SQL literál organizace schvalovatele
		$sess_lang_sql = charliteral((string) ($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka schvalovatele
		$is_sys_org_flag = is_sys_org($sess_org_raw);                        // Zda je schvalovatel v systémové organizaci 0x00

		$approver_session_sql = guidliteral((string) ($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$right_translate = ! empty($dbsession['right_translate']);           // Oprávnění ke globálnímu překladu
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid);                          // SQL literál primárního klíče návrhu

		$owner_cond = ($table === 'organization' AND $is_sys_org_flag)
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

		$orig_raw = (string) $draft_row['original'];                         // Surové UUID originálu
		$orig_sql = guidliteral($orig_raw);                                  // SQL literál originálu
		$owner_raw = (string) $draft_row['object_owner'];                    // Surové UUID vlastníka návrhu
		$owner_sql = guidliteral($owner_raw);                                // SQL literál vlastníka návrhu
		$draft_lang_raw = (string) $draft_row['language'];                   // Jazyk schvalovaného návrhu
		$draft_lang_sql = charliteral($draft_lang_raw, 2);                   // SQL literál jazyka návrhu
		$author_session_sql = guidliteral((string) $draft_row['who_modified']); // Relace autora v době postoupení návrhu
		$author_date_sql = charliteral((string) $draft_row['date_modified']); // Datum postoupení návrhu autorem

		$is_sys_owner = is_zero_guid($owner_raw);                            // Zda jde o systémového vlastníka 0x00
		$is_final_class = (! $is_sys_owner AND $table !== 'organization' AND ! empty($this->class_meta['is_final'])); // Zda třída zakazuje A override

		// 2. Zjištění existence schváleného 'A' záznamu (včetně případného dříve zrušeného při návrhu obnovy)
		$existing_a = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$orig_sql} AND record_type = 'A' AND object_owner IN ({$owner_sql}, 0x00) ORDER BY object_owner DESC, removed ASC, date_modified DESC"); // Hledání A záznamu

		$own_a_exists = (! empty($existing_a) AND ((string) $existing_a['object_owner'] === $owner_raw OR $is_sys_owner)); // Zda má vlastník vlastní A záznam
		$a_lang_raw = ! empty($existing_a) ? (string) $existing_a['language'] : $draft_lang_raw; // Mateřský jazyk A záznamu
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
				$a_uuid_sql = guidliteral((string) $existing_a['uuid']);     // Primární klíč existujícího A záznamu
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
				$ap_a_pk = (! empty($existing_a) ? 'NEWID()' : 'original');  // Primární klíč nového A záznamu
				$ap_a_hdr = ['uuid' => $ap_a_pk, 'object_owner' => $owner_sql, 'original' => 'original', 'record_type' => "'A'", 'approval_status' => "'A'", 'draft_author' => '0x00', 'approval_note' => "''"]; // Hlavička A záznamu
				$this->clone_with_map($ap_a_hdr + $ap_audit_map, "uuid = {$draft_uuid_sql}"); // Založení schváleného A záznamu
			}
		}

		// 4. Zápis do symetrického 'L' záznamu pro jazyk návrhu (mimo tabulku link)
		if ($table !== 'link') {                                             // Tabulka link nepoužívá jazykové mutace 'L'
			$l_owner_sql = $owner_sql;                                       // Vlastník jazykové mutace
			if (! empty($existing_a) AND is_zero_guid($existing_a['object_owner']) AND $right_translate) { // Systémový A záznam
				$l_owner_sql = '0x00';                                       // Globální systémový překlad
			}

			$existing_l = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND [language] = {$draft_lang_sql} ORDER BY removed ASC, date_modified DESC"); // Kontrola existence L

			if (! empty($existing_l)) {                                      // UPDATE existujícího 'L' záznamu
				$l_uuid_sql = guidliteral((string) $existing_l['uuid']);     // Primární klíč L záznamu
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
				$ap_l_hdr = ['uuid' => 'NEWID()', 'object_owner' => $l_owner_sql, 'original' => 'original', 'record_type' => "'L'", 'approval_status' => "'A'", 'draft_author' => '0x00', 'approval_note' => "''", 'language' => $draft_lang_sql]; // Hlavička L záznamu
				$this->clone_with_map($ap_l_hdr + $ap_audit_map, "uuid = {$draft_uuid_sql}"); // Založení schváleného L záznamu
			}

			// Jednotná auditní stopa na 'A' záznamu, pokud se měnila pouze jazyková vrstva 'L'
			if (($is_final_class OR ! $is_native_lang) AND ! empty($existing_a)) { // Kontrola potřeby aktualizace auditu na A
				$a_uuid_sql = guidliteral((string) $existing_a['uuid']);     // UUID hlavního A záznamu
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

		// 7. Spuštění návazných operací po schválení
		$this->run_post_save_hooks($orig_sql, $owner_sql, $draft_lang_sql, $approver_session_sql); // Návazné operace

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
		$sess_org_raw = (string) ($dbsession['organization'] ?? '0x00');     // Surové UUID organizace schvalovatele
		$sess_org_sql = guidliteral($sess_org_raw);                          // SQL literál organizace schvalovatele
		$sess_lang_sql = charliteral((string) ($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka schvalovatele
		$is_sys_org_flag = is_sys_org($sess_org_raw);                        // Zda je schvalovatel v systémové organizaci 0x00

		$approver_session_sql = guidliteral((string) ($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid);                          // SQL literál UUID návrhu

		$owner_cond = ($table === 'organization' AND $is_sys_org_flag)
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