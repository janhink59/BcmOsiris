<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 14:00
 * Soubor: entity_manager_write.php
 * Trait: entity_manager_write
 * Účel: Zápisová, validační a klonovací část třídy entity_manager.
 *       Metody schvalovacího cyklu (SSC), kontroly monotonie scale_value a
 *       post-save hooky jsou vyčleněny do sesterského traitu entity_manager_ssc
 *       (v souboru entity_manager_ssc.php) pro udržení přehledné velikosti modulů.
 *
 * VAZBY NA OKOLÍ:
 * - Inkludován a používán výhradně uvnitř třídy `entity_manager` (`entity_manager.php`).
 * - Spolupracuje s traitem `entity_manager_ssc` (`validate_scale_value_monotonicity`,
 *   `run_post_save_hooks`).
 * - Využívá třídy `rich_text` (`rich_text.php`), `svg_icon_editor` (`svg_icon_editor.php`)
 *   a funkci `generate_builtin_code()` (`new_functions.php`).
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
	private function unquote_sql_literal(string $sql_lit): string { // Odstranění SQL apostrofů pro validaci
		$trimmed = trim($sql_lit); // Oříznutí bílých znaků kolem literálu
		if ($trimmed === '' OR strtoupper($trimmed) === 'NULL' OR strtolower($trimmed) === '0x00') { // Prázdný literál
			return ''; // Vrácení prázdného řetězce
		}
		if (strlen($trimmed) >= 2 AND str_starts_with($trimmed, "'") AND str_ends_with($trimmed, "'")) { // Text v apostrofech
			$inner = substr($trimmed, 1, -1); // Odříznutí vnějších apostrofů
			return trim(str_replace("''", "'", $inner)); // Odzdvojení vnitřních apostrofů a ořez mezer
		}
		return $trimmed; // Číselný nebo jiný literál
	}

	/**
	 * Odvodí bezpečný ASCII identifikátor `builtin_code` ze zkratky nebo názvu.
	 */
	private function derive_builtin_code_from_post(): string { // Automatické odvození builtin_code z názvu/zkratky
		$src = trim((string) ($_POST['shortname'] ?? '')); // Přednost má vyplněná zkratka (shortname)
		if ($src === '') { // Pokud zkratka není vyplněna
			$src = trim((string) ($_POST['caption'] ?? '')); // Použijeme hlavní název (caption)
		}
		if ($src === '') { // Pokud není vyplněn ani název
			return ''; // Nelze odvodit
		}
		if (function_exists('generate_builtin_code')) { // Primární konverzní funkce z new_functions.php
			$code = generate_builtin_code($src, 60); // Převod diakritiky a sestavení snake_case kódu
			return ($code !== '') ? $code : 'item'; // Vrácení neprázdného identifikátoru
		}
		$ascii = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $src); // Nouzový převod diakritiky na ASCII
		$clean = strtolower((string) ($ascii !== false ? $ascii : $src)); // Převod na malá písmena
		$clean = (string) preg_replace('/[^a-z0-9]+/', '_', $clean); // Nahrazení nečíselných a nepísmenných znaků podtržítkem
		$clean = trim($clean, '_'); // Oříznutí okrajových podtržítek
		return substr($clean !== '' ? $clean : 'item', 0, 60); // Vrácení neprázdného kódu (max 60 znaků)
	}

	/**
	 * Sestaví a spustí příkaz INSERT INTO ... VALUES (...) vyfiltrováním předané mapy
	 * sloupců a SQL výrazů proti skutečným fyzickým sloupcům tabulky (physical_cols).
	 */
	private function insert_from_map(array $row_map): void { // Vložení nového záznamu podle mapy sloupců
		$ins_cols = []; // Seznam vkládaných fyzických sloupců
		$ins_vals = []; // Seznam odpovídajících SQL hodnot
		foreach ($this->physical_cols as $col) { // Průchod fyzickými sloupci tabulky
			if (array_key_exists($col, $row_map)) { // Zařazení sloupce, pokud je v mapě definován
				$ins_cols[] = "[$col]"; // Název fyzického sloupce v závorkách
				$ins_vals[] = (string) $row_map[$col]; // SQL literál nebo výraz hodnoty
			}
		}
		$sql = "INSERT INTO {$this->storage_table} (" . implode(', ', $ins_cols) . ") VALUES (" . implode(', ', $ins_vals) . ")"; // Sestavení SQL příkazu INSERT
		sqlrun($sql); // Provedení příkazu INSERT
	}

	/**
	 * Sestaví a spustí klonovací příkaz INSERT INTO ... SELECT ... FROM ...
	 */
	private function clone_with_map(array $override_map, string $where_sql, string $top_sql = '', string $order_sql = ''): void { // Klonování záznamu s modifikací
		$ins_cols = []; // Cílové sloupce klonovaného záznamu
		$sel_vals = []; // Výrazy v SELECT klauzuli klonu
		foreach ($this->physical_cols as $col) { // Průchod všemi fyzickými sloupci tabulky
			$ins_cols[] = "[$col]"; // Zařazení fyzického sloupce do INSERTu
			$sel_vals[] = array_key_exists($col, $override_map) ? (string) $override_map[$col] : "[$col]"; // Nová nebo původní hodnota
		}
		$top_part = ($top_sql !== '') ? "{$top_sql} " : ""; // Případné omezení TOP 1
		$ord_part = ($order_sql !== '') ? " {$order_sql}" : ""; // Případné řazení zdrojového dotazu
		$sql = "INSERT INTO {$this->storage_table} (" . implode(', ', $ins_cols) . ") \nSELECT {$top_part}" . implode(', ', $sel_vals) . " \nFROM {$this->storage_table} \nWHERE {$where_sql}{$ord_part}"; // Sestavení klonovacího SQL dotazu
		sqlrun($sql); // Provedení klonovacího dotazu
	}

	/**
	 * Získání, očištění a sanitizace odeslaných POST dat podle metadat a fyzického schématu.
	 */
	public function extract_post_data(): array {
		$data = []; // Výstupní pole sanitizovaných dat
		$meta_columns_list = [ // Seznam technických a chráněných sloupců mimo POST
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note', 'language',
			'is_template', 'template', 'date_created', 'who_created',
			'date_modified', 'who_modified', 'import_origin',
			'logo_data', 'logo_filename', 'logo_mime_type'
		]; // Konec seznamu technických sloupců

		$key_cols = $this->get_original_key_columns(); // Klíčové sloupce určující deterministický originál
		$trim_cols = array_unique(array_merge($key_cols, [ // Sloupce, které se vždy ořezávají od okrajových mezer
			'builtin_code', 'class_name', 'column_name', 'source_code',
			'codetable_name', 'value_code', 'link_code', 'sort_code', 'external_code'
		])); // Konec seznamu ořezávaných sloupců

		foreach ($this->columns_meta as $colname => $meta) { // Průchod všemi sloupci třídy
			if (! empty($meta['is_computed']) OR in_array($colname, $meta_columns_list, true)) { // Přeskočení technických a computed polí
				continue; // Pokračování na další sloupec
			}
			if (! isset($_POST[$colname])) { // Pokud pole nebylo ve formuláři odesláno
				continue; // Pokračování na další sloupec
			}

			$raw_val = (string) $_POST[$colname]; // Surová hodnota z formuláře
			if (in_array($colname, $trim_cols, true)) { // Pokud jde o klíčový nebo kódový sloupec
				$raw_val = trim($raw_val); // Vždy odstraníme počáteční a koncové mezery
				$_POST[$colname] = $raw_val; // Propíšeme očištěnou hodnotu zpět do $_POST
			}

			if ($this->storage_table === 'meta_phrase' AND $colname === 'source_code' AND $raw_val === '') { // Zákaz prázdného source_code
				$raw_val = 'global_phrase'; // Přesměrování prázdného zdroje na global_phrase
			}

			if ($colname === 'svg_icon') { // Serverová validace a sanitizace vektorové ikony svg_icon
				$raw_val = trim($raw_val); // Oříznutí bílých znaků kolem SVG
				if ($raw_val !== '' AND class_exists('svg_icon_editor')) { // Pokud je k dispozici validátor SVG
					$svg_err = null; // Proměnná pro zachycení chyby XML syntaxe
					$clean_svg = svg_icon_editor::validate_svg($raw_val, $svg_err); // Validace a XSS sanitizace SVG
					if ($svg_err !== null AND $svg_err !== '') { // Pokud XML/SVG syntaxe není platná
						$this->set_last_save_error((string) $svg_err); // Uložení chybové hlášky pro zobrazení v detailu
						return []; // Přerušení extrakce při chybě SVG
					}
					$raw_val = $clean_svg; // Použití očištěného SVG kódu
				}
			}

			if (! empty($meta['is_html']) AND class_exists('rich_text')) { // Ošetření formátovaného textu (Markdown / HTML)
				$fmt_key_target = $colname . '__target_format'; // Primární klíč cílového formátu z rich_text
				$fmt_hint = (string) ($_POST[$fmt_key_target] ?? 'auto'); // Zvolený režim formátu
				if ($fmt_hint === '') { // Pokud nebyl formát explicitně zvolen
					$fmt_hint = 'auto'; // Automatická detekce formátu
				}
				if (method_exists('rich_text', 'normalize_for_storage')) { // Primární metoda v rich_text.php
					$raw_val = (string) rich_text::normalize_for_storage($raw_val, $fmt_hint); // Konverze a sanitizace pro DB
				}
			}

			$phys_type = $this->col_types[$colname] ?? ''; // Fyzický typ sloupce v DB
			$is_not_null = (($this->col_nulls[$colname] ?? '') === 'not null'); // Zda fyzický sloupec zakazuje NULL

			if (in_array($phys_type, ['uuid', 'uniqueidentifier'], true)) { // Pokud jde o UUID sloupec
				$guid_lit = guidliteral($raw_val); // Převod na bezpečný UUID literál
				$data[$colname] = ($guid_lit === 'NULL' AND $is_not_null) ? '0x00' : $guid_lit; // Ošetření NOT NULL UUID
			} elseif ($meta['input_type'] === 'checkbox' OR $phys_type === 'bit') { // Pokud jde o bitový checkbox
				$data[$colname] = ($raw_val === '1' OR strtolower($raw_val) === 'true') ? 1 : 0; // Bitová hodnota 1 nebo 0
			} elseif (in_array($phys_type, ['int', 'smallint', 'tinyint', 'bigint'], true)) { // Celočíselné sloupce
				$int_lit = intliteral($raw_val, 0); // Převod na celé číslo nebo NULL
				$data[$colname] = ($int_lit === 'NULL' AND $is_not_null) ? '0' : $int_lit; // Ošetření NOT NULL sloupců
			} elseif ($meta['input_type'] === 'number' OR in_array($phys_type, ['decimal', 'numeric', 'float', 'real', 'money'], true)) { // Desetinná čísla
				$norm_num = str_replace(',', '.', trim($raw_val)); // Podpora desetinné čárky i tečky
				$data[$colname] = ($norm_num === '' OR ! is_numeric($norm_num)) ? ($is_not_null ? '0' : 'NULL') : (string) (float) $norm_num; // Číselný literál
			} elseif (in_array($phys_type, ['date', 'datetime', 'datetime2', 'smalldatetime'], true)) { // Datumové sloupce
				$dt_lit = dateliteral($raw_val); // Převod na bezpečný datumový SQL literál
				$data[$colname] = ($dt_lit === 'NULL' AND $is_not_null) ? "'1970-01-01'" : $dt_lit; // Fallback pro NOT NULL datum
			} else {
				$data[$colname] = charliteral($raw_val); // Převod na bezpečný textový literál
			}
		}

		if (! isset($data['removed']) AND isset($_POST['removed']) AND in_array('removed', $this->physical_cols, true)) { // Kontrola removed v POSTu
			$raw_rem = (string) $_POST['removed']; // Surová hodnota removed z formuláře
			$data['removed'] = ($raw_rem === '1' OR strtolower($raw_rem) === 'true') ? 1 : 0; // Převod na bit 1/0
		}

		return $data; // Vrácení připravených dat
	}

	/**
	 * Provede autonomní zápis dat s podporou schvalovacího cyklu (SSC),
	 * validací neprázdnosti a unikátnosti klíčových položek a klonováním s modifikací.
	 */
	public function save_post_data(string $update_guid = '', string $target_status = 'A'): string { // Autonomní uložení dat
		$this->set_last_save_error(''); // Vynulování předchozí chybové zprávy
		if (! $this->is_initialized) { // Kontrola inicializace metadat
			return $update_guid; // Návrat při neinicializované třídě
		}

		if (! in_array($target_status, ['A', 'D', 'F'], true)) { // Validace cílového stavu
			$target_status = 'A'; // Fallback na schválený stav
		}

		$post_data = $this->extract_post_data(); // Extrakce a validace hodnot z POSTu
		if ($this->get_last_save_error() !== '') { // Pokud při extrakci (např. validaci SVG ikony) vznikla chyba
			return ''; // Zastavení zápisu se zachováním chybové zprávy
		}
		if (empty($post_data)) { // Pokud nepřišla žádná data
			return $update_guid; // Ukončení bez zápisu
		}

		global $dbsession; // Načtení globální relace
		if (empty($dbsession) OR empty($dbsession['login_session_uuid'])) { // Kontrola platné relace v dbsession
			$err_save_title = $this->phrase('err_save_failed_title', 'Uložení selhalo'); // Titulek chyby uložení
			$err_save_msg = $this->phrase('err_save_no_session', 'Nepodařilo se načíst kontext uživatele z globální relace dbsession.'); // Text chyby
			fatal_error($err_save_title, $err_save_msg); // Vyvolání chyby při ztrátě relace
		}

		$org_uuid_raw = (string) $dbsession['organization']; // Surové UUID organizace v relaci
		$user_uuid_raw = (string) $dbsession['login_session_uuid']; // Surové UUID relace pro audit
		$user_acc_raw = (string) ($dbsession['user_account'] ?? '0x00'); // Surové UUID účtu uživatele (pro draft_author)
		$sess_lang_raw = (string) $dbsession['language']; // Surový kód jazyka relace
		$active_role = (string) ($dbsession['active_role'] ?? 'U'); // Aktuální role v relaci
		$right_translate = ! empty($dbsession['right_translate']); // Oprávnění ke globálnímu překladu

		$user_uuid_sql = guidliteral($user_uuid_raw); // SQL literál uživatelské relace
		$user_acc_sql = guidliteral($user_acc_raw); // SQL literál uživatelského účtu
		$lang_literal_sql = charliteral($sess_lang_raw); // SQL literál jazyka

		$table = $this->storage_table; // Cílová fyzická tabulka
		$is_meta_table = $this->is_metadata_entity(); // Zda jde o tabulku metadat (meta_*)
		$is_self_owned = ($table === 'organization'); // V tabulce organization vlastní záznam sám sebe

		$orig_guid_raw = $update_guid; // Surové UUID upravovaného záznamu
		$orig_guid_sql = ($update_guid === '') ? '' : guidliteral($update_guid); // SQL literál originálu

		if ($is_self_owned AND $orig_guid_sql === '') { // Zákaz přímého INSERTu do organization
			return ''; // Ukončení bez založení organizace
		}
		if ($is_meta_table AND $orig_guid_sql === '' AND $active_role !== 'D') { // Kontrola práv pro nový záznam metadat
			return ''; // Zákaz INSERTu do metadat mimo roli D
		}

		$is_sysadmin_org = is_sys_org($org_uuid_raw); // Příznak systémového tenanta (0x00)
		$rec_owner_raw = ($is_self_owned AND $orig_guid_raw !== '') ? $orig_guid_raw : $org_uuid_raw; // Surový vlastník záznamu
		$rec_owner_sql = guidliteral($rec_owner_raw); // SQL literál vlastníka záznamu

		$was_code_auto_derived = false; // Příznak automaticky odvozeného kódu
		if ($orig_guid_sql === '' AND ! $is_meta_table AND in_array('builtin_code', $this->physical_cols, true)) { // Nový věcný záznam
			$cur_bcode = $this->unquote_sql_literal((string) ($post_data['builtin_code'] ?? '')); // Zadaný builtin_code
			$auto_candidate = $this->derive_builtin_code_from_post(); // Kandidát odvozený ze shortname / caption
			if ($cur_bcode === '' AND $auto_candidate !== '') { // Pokud zůstal prázdný, dosadíme odvozený
				$post_data['builtin_code'] = charliteral($auto_candidate, 80); // SQL literál odvozeného kódu
				$_POST['builtin_code'] = $auto_candidate; // Propis do $_POST
				$was_code_auto_derived = true; // Označení pro případné rozlišení sufixem _2, _3
			} elseif ($cur_bcode !== '' AND $cur_bcode === $auto_candidate) { // Vygenerováno klientským JS ze stejného názvu
				$was_code_auto_derived = true; // Povolíme automatický sufix při kolizi
			}
		}

		$a_exists = false; // Zda již existuje vlastní 'A' záznam
		$a_uuid_sql = ''; // SQL literál primárního klíče 'A' záznamu
		$a_lang_raw = $sess_lang_raw; // Výchozí pro zcela nový záznam
		$orig_owner_raw = $rec_owner_raw; // Vlastník nalezeného záznamu
		$baseline_row = []; // Předloha pro porovnání změn (pouze pro metadata / ancestor)
		$current_row = []; // Aktuální řádek v DB

		if ($orig_guid_sql !== '') { // Pokud upravujeme existující záznam
			$current_row = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND (object_owner = {$rec_owner_sql} OR object_owner = 0x00) ORDER BY object_owner DESC, removed ASC, date_modified DESC"); // Dotaz na existující A záznam
			if (! empty($current_row)) { // Pokud schválený záznam existuje
				$a_exists = ((string) $current_row['object_owner'] === $rec_owner_raw OR $is_sysadmin_org); // Zda záznam patří tenantovi
				$orig_owner_raw = (string) $current_row['object_owner']; // Uložení vlastníka záznamu
				$a_uuid_sql = guidliteral((string) $current_row['uuid']); // Uložení UUID 'A' záznamu
				$a_lang_raw = (string) $current_row['language']; // Mateřský jazyk 'A' záznamu
			}

			if ($is_meta_table) { // Pouze pro metadatové tabulky (meta_column, meta_class)
				if (! $is_sysadmin_org) { // Klientský tenant upravující metadata
					$base = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00"); // Dotaz na systémovou předlohu
					if (! empty($base)) { // Načtení systémové předlohy
						$baseline_row = $base; // Systémová předloha pro tenanta
					}
				} else {
					$anc_val = $post_data['ancestor'] ?? ($current_row['ancestor'] ?? null); // Zjištění vazby na předka v sys_global_columns
					if (! empty($anc_val) AND $anc_val !== "''" AND $anc_val !== 'NULL') { // Pokud má záznam předka
						$anc_raw = trim((string) $anc_val, "'"); // Očištění UUID předka
						$anc_guid = guidliteral($anc_raw); // SQL literál UUID předka
						$anc_row = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$anc_guid} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00"); // Dotaz na předka
						if (! empty($anc_row)) { // Načtení dat předka
							$baseline_row = $anc_row; // Předloha z globálního předka
						}
					}
				}
			}
		}

		if ($orig_guid_sql !== '' AND ! empty($current_row) AND $this->has_physical_column('parent_uuid')) { // Ochrana uzamčené hierarchie
			$node_locked = $this->is_hierarchy_node_locked($orig_guid_raw); // Zjištění uzamčení větve vazbami
			if ($node_locked) { // Pokud je větev uzamčena platnými vazbami
				unset($post_data['parent_uuid']); // Zákaz změny nadřízeného uzlu (přepodřízení)
				if (! empty($current_row['is_leaf'])) { // Pokud byl uzel koncovým listem
					$post_data['is_leaf'] = 1; // Zákaz přepnutí obsazeného koncového uzlu na složku
				}
			}
			if (isset($post_data['is_leaf']) AND (int) $post_data['is_leaf'] === 1) { // Pokus o nastavení is_leaf = 1
				$has_ch = sqlfirstrow("SELECT TOP 1 1 AS ex FROM [{$table}] WHERE parent_uuid = {$orig_guid_sql} AND record_type = 'A' AND removed = 0"); // Kontrola potomků
				if (! empty($has_ch)) { // Uzel má aktivní podřízené položky
					$post_data['is_leaf'] = 0; // Složka s potomky musí mít is_leaf = 0
				}
			}
		}

		$requested_removed = null; // Požadovaná hodnota removed z formuláře
		if (array_key_exists('removed', $post_data)) { // Pokud formulář odeslal sloupec removed
			$requested_removed = (int) $post_data['removed']; // Požadovaný stav 0 nebo 1
			unset($post_data['removed']); // Vyjmeme z běžné smyčky a ošetříme cíleně níže
		}

		$key_cols = $this->get_original_key_columns(); // Seznam klíčových sloupců tabulky
		$a_post_data = []; // Data určená pro hlavní 'A' záznam
		$l_post_data = []; // Data určená pro překladový 'L' záznam
		$d_post_data = []; // Data určená pro řádek konceptu 'D'
		$has_translated_cols = false; // Zda formulář obsahuje překládaná pole
		$is_native_lang = ($a_lang_raw === $sess_lang_raw); // Zda se edituje v mateřském jazyce

		foreach ($post_data as $col => $val) { // Průchod odeslanými hodnotami
			if ($orig_guid_sql !== '' AND in_array($col, $key_cols, true) AND (! empty($current_row) OR $target_status !== 'A')) { // Ochrana klíče
				continue; // Klíčový sloupec se u existujícího záznamu nemění
			}
			$is_translated = ! empty($this->columns_meta[$col]['translate']); // Zda sloupec podléhá překladu
			if ($is_meta_table AND $active_role !== 'D' AND ! $is_translated) { // Ochrana funkčních polí metadat
				continue; // Odfiltrování funkčního atributu metadat
			}
			if (! $is_sysadmin_org AND ! empty($this->columns_meta[$col]['is_protected']) AND ! $is_translated) { // Ochrana is_protected
				continue; // Odfiltrování chráněného sloupce
			}

			if (! empty($baseline_row) AND isset($baseline_row[$col])) { // Porovnání s výchozí předlohou u metadat
				$baseline_val = $baseline_row[$col]; // Hodnota v předloze
				$compare_val = str_replace("''", "'", trim((string) $val, "'")); // Hodnota k porovnání bez vnějších apostrofů
				if (isset($this->col_nulls[$col]) AND $this->col_nulls[$col] !== 'not null') { // Pokud sloupec povoluje NULL
					if ((string) $compare_val === (string) $baseline_val) { // Shoda s hodnotou předlohy
						$val = 'NULL'; // Shodná hodnota v metadatech se uloží jako NULL pro dědění
					}
				}
			}

			$d_post_data[$col] = $val; // Koncept 'D' drží jak věcné, tak překladové změny
			if ($is_translated) { // Pokud jde o překládaný sloupec
				$has_translated_cols = true; // Evidujeme přítomnost překladu
				$l_post_data[$col] = $val; // Zápis hodnoty do jazykové vrstvy
				if ($is_native_lang) { // Pokud jde o mateřský jazyk záznamu
					$a_post_data[$col] = $val; // Zápis do 'A' v mateřském jazyce
				}
			} else {
				$a_post_data[$col] = $val; // Zápis nepřekládaného sloupce do 'A'
			}
		}

		if (! $is_sysadmin_org AND ! empty($this->class_meta['is_final'])) { // Kontrola příznaku is_final
			$a_post_data = []; // Zákaz modifikace 'A' záznamu pro tenanta
			$d_post_data = $l_post_data; // V konceptu tenanta ponecháme jen překládaná pole
		}

		if ($requested_removed !== null AND ! empty($current_row)) { // Pokud uživatel mění existující záznam
			$perm = $this->evaluate_remove_permission($current_row, $a_exists); // Kontrola oprávnění ke zrušení/obnovení
			if ($perm['allowed']) { // Pokud má uživatel oprávnění měnit removed
				$d_post_data['removed'] = $requested_removed; // Zápis návrhu removed do konceptu 'D'
				if ($perm['is_lang_only']) { // V sekundárním jazyce měníme removed pouze na 'L'
					$l_post_data['removed'] = $requested_removed; // Nastavení removed pro jazykovou mutaci 'L'
					$has_translated_cols = true; // Vynutíme průchod zápisem 'L' záznamu
				} else {
					$a_post_data['removed'] = $requested_removed; // Nastavení removed pro hlavní 'A' záznam
					$l_post_data['removed'] = $requested_removed; // Symetrické přenesení removed i na primární 'L'
				}
			}
		}

		if ($table === 'scale_value') { // Kontrola monotonie a rozsahu 0..100 % pro tabulku scale_value
			$sv_check_data = $current_row; // Výchozí hodnoty z existujícího řádku
			foreach (($a_post_data + $d_post_data) as $k_sv => $v_sv) { // Přepsání novými hodnotami z POSTu
				$sv_check_data[$k_sv] = $v_sv; // Aktualizovaná hodnota sloupce
			}
			if (isset($sv_check_data['scale']) AND ! str_starts_with((string) $sv_check_data['scale'], "'") AND (string) $sv_check_data['scale'] !== '0x00') { // Normalizace UUID škály
				$sv_check_data['scale'] = guidliteral((string) $sv_check_data['scale']); // SQL literál škály
			}
			$is_being_removed = (! empty($a_post_data['removed']) OR ! empty($d_post_data['removed'])); // Při rušení stupně neblokujeme
			if (! $is_being_removed AND ! $this->validate_scale_value_monotonicity($orig_guid_sql, $rec_owner_sql, $sv_check_data)) { // Validace
				return ''; // Zastavení zápisu při porušení monotonie
			}
		}

		if ($orig_guid_sql === '') { // Validace klíčových položek a unikátnosti originálu u nového záznamu (NEW)
			$src_key_data = ! empty($a_post_data) ? $a_post_data : $d_post_data; // Pole hodnot pro výpočet klíče
			$key_info = sqlfirstrow("SELECT key1_column, key2_column FROM meta_original_keys WHERE table_name = " . charliteral($table)); // Klíčové sloupce

			if (! empty($key_info)) { // Tabulka má deterministický klíč v meta_original_keys
				$k1_col = (string) $key_info['key1_column']; // Název 1. klíčového sloupce
				$k2_col = (string) ($key_info['key2_column'] ?? ''); // Název volitelného 2. klíčového sloupce

				$k1_val = array_key_exists($k1_col, $src_key_data) ? (string) $src_key_data[$k1_col] : "''"; // SQL literál 1. klíče
				$k1_plain = $this->unquote_sql_literal($k1_val); // Čistá textová hodnota 1. klíče
				$k1_mand = $this->is_key_column_mandatory($k1_col) OR ! empty($src_key_data['is_template']); // Zda je 1. klíč povinný

				if ($k1_plain === '' AND $k1_mand) { // Povinný 1. klíčový sloupec je prázdný
					$k1_meta = $this->columns_meta[$k1_col] ?? []; // Metadata 1. klíčového sloupce
					$k1_lbl = (string) ($k1_meta['label'] ?? $k1_meta['caption'] ?? $k1_col); // Popisek sloupce
					$this->set_last_save_error($this->phrase('err_key_col_empty', 'Klíčová položka „{' . chr(36) . 'label}“ ({' . chr(36) . 'col}) nesmí být prázdná.', ['label' => $k1_lbl, 'col' => $k1_col])); // Chyba
					return ''; // Zastavení zápisu
				}

				$k2_val = 'NULL'; // Výchozí SQL hodnota 2. klíče
				$k2_plain = ''; // Výchozí čistá hodnota 2. klíče
				if ($k2_col !== '') { // Pokud má tabulka definovaný i 2. klíčový sloupec
					$k2_val = array_key_exists($k2_col, $src_key_data) ? (string) $src_key_data[$k2_col] : "''"; // SQL literál 2. klíče
					$k2_plain = $this->unquote_sql_literal($k2_val); // Čistá textová hodnota 2. klíče
					$k2_mand = $this->is_key_column_mandatory($k2_col) OR ! empty($src_key_data['is_template']); // Zda je 2. klíč povinný
					if ($k2_plain === '' AND $k2_mand) { // Povinný 2. klíčový sloupec je prázdný
						$k2_meta = $this->columns_meta[$k2_col] ?? []; // Metadata 2. klíčového sloupce
						$k2_lbl = (string) ($k2_meta['label'] ?? $k2_meta['caption'] ?? $k2_col); // Popisek sloupce
						$this->set_last_save_error($this->phrase('err_key_col_empty', 'Klíčová položka „{' . chr(36) . 'label}“ ({' . chr(36) . 'col}) nesmí být prázdná.', ['label' => $k2_lbl, 'col' => $k2_col])); // Chyba
						return ''; // Zastavení zápisu
					}
				}

				if ($k1_plain !== '' AND ($k2_col === '' OR $k2_plain !== '')) { // Klíče jsou vyplněny -> výpočet originálu
					$base_auto_code = ($k2_col === 'builtin_code') ? $k2_plain : $k1_plain; // Základ pro případný sufix _2, _3
					$attempt = 1; // Počitadlo pokusů při automatickém rozlišení kolize
					$dup_row = []; // Nalezený kolizní řádek

					while ($attempt <= 50) { // Hledání volného sufixu u automaticky odvozeného builtin_code
						$orig_row = sqlfirstrow("SELECT dbo.f_generate_original(" . charliteral($table) . ", {$rec_owner_sql}, CAST({$k1_val} AS VARCHAR(MAX)), CAST({$k2_val} AS VARCHAR(MAX))) AS orig_guid"); // Výpočet hashe
						if (! empty($orig_row)) { // Načtení vypočteného originálu
							$orig_guid_raw = (string) $orig_row['orig_guid']; // Surové UUID originálu
							$orig_guid_sql = guidliteral($orig_guid_raw); // Deterministické UUID originálu
						}

						$k1_cond_sql = "LOWER(LTRIM(RTRIM(CAST([{$k1_col}] AS VARCHAR(MAX))))) = LOWER(LTRIM(RTRIM(CAST({$k1_val} AS VARCHAR(MAX)))))"; // Podmínka 1. klíče
						$k2_cond_sql = ($k2_col !== '') ? " AND LOWER(LTRIM(RTRIM(CAST([{$k2_col}] AS VARCHAR(MAX))))) = LOWER(LTRIM(RTRIM(CAST({$k2_val} AS VARCHAR(MAX)))))" : ""; // Podmínka 2. klíče

						$dup_row = sqlfirstrow("
							SELECT TOP 1 uuid, original, record_type, removed, object_owner
							FROM [{$table}]
							WHERE uuid = {$orig_guid_sql}
							   OR (original = {$orig_guid_sql} AND object_owner IN (0x00, {$rec_owner_sql}) AND record_type IN ('A', 'D'))
							   OR (record_type IN ('A', 'D') AND object_owner IN (0x00, {$rec_owner_sql}) AND {$k1_cond_sql}{$k2_cond_sql})
							ORDER BY removed ASC, CASE WHEN record_type = 'A' THEN 0 ELSE 1 END ASC
						"); // Kontrola duplicitního záznamu v tabulce

						if (empty($dup_row) OR ! $was_code_auto_derived) { // Pokud je kód unikátní nebo byl zadán ručně
							break; // Ukončíme smyčku
						}

						$attempt++; // Zkusíme další rozlišovací příponu (_2, _3...)
						$next_code = substr($base_auto_code, 0, 70) . '_' . $attempt; // Nový kandidátní builtin_code
						$next_lit = charliteral($next_code, 80); // SQL literál nového kandidáta
						if ($k2_col === 'builtin_code') { // Pokud je builtin_code druhým klíčem
							$k2_plain = $next_code; // Aktualizace čisté hodnoty 2. klíče
							$k2_val = $next_lit; // Aktualizace SQL literálu 2. klíče
						} else {
							$k1_plain = $next_code; // Aktualizace čisté hodnoty 1. klíče
							$k1_val = $next_lit; // Aktualizace SQL literálu 1. klíče
						}
						if (isset($a_post_data['builtin_code'])) { // Propis rozlišeného kódu do ukládaných A dat
							$a_post_data['builtin_code'] = $next_lit; // Nový builtin_code pro A
						}
						if (isset($d_post_data['builtin_code'])) { // Propis rozlišeného kódu do ukládaných D dat
							$d_post_data['builtin_code'] = $next_lit; // Nový builtin_code pro D
						}
						$_POST['builtin_code'] = $next_code; // Propis do $_POST
					}

					if (! empty($dup_row)) { // Nalezen kolizní záznam se shodným klíčem / originálem
						$key_desc = ($k2_col !== '') ? "{$k1_col}='{$k1_plain}', {$k2_col}='{$k2_plain}'" : "{$k1_col}='{$k1_plain}'"; // Popis klíče
						if (! empty($dup_row['removed'])) { // Kolizní záznam leží v koši (removed = 1)
							$this->set_last_save_error($this->phrase('err_duplicate_key_in_trash', 'Záznam se zadanou klíčovou položkou ({' . chr(36) . 'keys}) již existuje v koši (zrušené záznamy). Zapněte v levém panelu „Zobrazit i zrušené“ a záznam obnovte, nebo zvolte jiný unikátní kód.', ['keys' => $key_desc])); // Hláška
						} else {
							$this->set_last_save_error($this->phrase('err_duplicate_key_active', 'Záznam se zadanou klíčovou položkou ({' . chr(36) . 'keys}) již v databázi existuje. Zadejte unikátní hodnotu, aby nedošlo k výpočtu duplicitního originálu.', ['keys' => $key_desc])); // Hláška
						}
						return ''; // Zastavení zápisu před vznikem SQL chyby
					}

					if ($table === 'hierarchy') { // Kontrola kolize kódu hierarchie s tabulkou meta_class
						$cls_dup = sqlfirstrow("SELECT TOP 1 class_name FROM meta_class WHERE LOWER(LTRIM(RTRIM(class_name))) = LOWER(LTRIM(RTRIM(CAST({$k1_val} AS VARCHAR(80))))) AND object_owner IN (0x00, {$rec_owner_sql}) AND record_type = 'A'"); // Dotaz do meta_class
						if (! empty($cls_dup)) { // Kód již obsadila jiná logická třída v meta_class
							$this->set_last_save_error($this->phrase('err_hierarchy_code_collides_class', 'Kód hierarchie „{' . chr(36) . 'code}“ koliduje s názvem již existující logické třídy v meta_class. Zvolte prosím jiný unikátní kód.', ['code' => $k1_plain])); // Chyba
							return ''; // Zastavení zápisu
						}
					}
				} else {
					$orig_row = sqlfirstrow("SELECT NEWID() AS orig_guid"); // Náhodný identifikátor při prázdném klíči
					$orig_guid_raw = (string) ($orig_row['orig_guid'] ?? generateUUID()); // Surové náhodné UUID
					$orig_guid_sql = guidliteral($orig_guid_raw); // SQL literál náhodného UUID
				}
			} elseif ($table === 'link') { // Speciální 4složkový výpočet a validace pro tabulku link
				$link_def = array_key_exists('link_def', $src_key_data) ? (string) $src_key_data['link_def'] : 'NULL'; // Definice vazby
				$from_obj = array_key_exists('from_object', $src_key_data) ? (string) $src_key_data['from_object'] : 'NULL'; // Zdroj vazby
				$to_obj = array_key_exists('to_object', $src_key_data) ? (string) $src_key_data['to_object'] : 'NULL'; // Cíl vazby
				$anc_link = (array_key_exists('ancestor_link', $src_key_data) AND $src_key_data['ancestor_link'] !== 'NULL') ? (string) $src_key_data['ancestor_link'] : '0x00'; // Předek vazby

				if ($this->unquote_sql_literal($link_def) === '' OR $this->unquote_sql_literal($from_obj) === '' OR $this->unquote_sql_literal($to_obj) === '') { // Chybí složka vazby
					$this->set_last_save_error($this->phrase('err_link_keys_empty', 'Klíčové položky vazby (link_def, from_object, to_object) musí být vyplněny.')); // Hláška
					return ''; // Zastavení zápisu
				}

				$orig_row = sqlfirstrow("SELECT dbo.f_link_original(CAST({$rec_owner_sql} AS varchar(36)), CAST({$link_def} AS varchar(36)), CAST({$from_obj} AS varchar(36)), CAST({$to_obj} AS varchar(36)), CAST({$anc_link} AS varchar(36))) AS orig_guid"); // Výpočet originálu vazby
				$orig_guid_raw = (string) ($orig_row['orig_guid'] ?? generateUUID()); // Surové UUID vazby
				$orig_guid_sql = guidliteral($orig_guid_raw); // Deterministické UUID vazby

				$dup_lnk = sqlfirstrow("SELECT TOP 1 uuid FROM [link] WHERE uuid = {$orig_guid_sql} OR (original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type IN ('A', 'D')) OR (object_owner = {$rec_owner_sql} AND link_def = {$link_def} AND from_object = {$from_obj} AND to_object = {$to_obj} AND ancestor_link = {$anc_link} AND record_type IN ('A', 'D'))"); // Kontrola duplicity
				if (! empty($dup_lnk)) { // Vazba již existuje
					$this->set_last_save_error($this->phrase('err_duplicate_link', 'Tato vazba mezi zvolenými záznamy již existuje.')); // Hláška
					return ''; // Zastavení zápisu
				}
			} else {
				$orig_row = sqlfirstrow("SELECT NEWID() AS orig_guid"); // Náhodné UUID pro globální tabulky bez deterministického klíče
				$orig_guid_raw = (string) ($orig_row['orig_guid'] ?? generateUUID()); // Surové náhodné UUID
				$orig_guid_sql = guidliteral($orig_guid_raw); // Nově vygenerované UUID
			}
		}

		sqlrun("BEGIN TRAN"); // Zahájení databázové transakce

		$audit_base_map = ['date_created' => 'GETDATE()', 'date_modified' => 'GETDATE()', 'who_created' => $user_uuid_sql, 'who_modified' => $user_uuid_sql]; // Základní auditní mapa

		if ($target_status === 'D' OR $target_status === 'F') { // VĚTEV A: Zápis konceptu nebo postoupení ke schválení ('D' / 'F')
			$safe_status = charliteral($target_status, 1); // SQL literál cílového stavu ('D' nebo 'F')
			$dr_row = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type = 'D' AND [language] = {$lang_literal_sql} AND (draft_author = {$user_acc_sql} OR (draft_author = 0x00 AND approval_status = 'R')) ORDER BY removed ASC, date_modified DESC"); // Hledání konceptu

			if (! empty($dr_row)) { // Pokud koncept uživatele již existuje -> UPDATE
				$dr_uuid_sql = guidliteral((string) $dr_row['uuid']); // UUID existujícího řádku konceptu
				$set_dr = []; // Pole změn pro UPDATE konceptu
				foreach ($d_post_data as $col => $val) { // Průchod ukládanými sloupci konceptu
					if (! in_array($col, $key_cols, true)) { // Ochrana klíčového sloupce v existujícím konceptu
						$set_dr[] = "[$col] = $val"; // Nastavení hodnoty sloupce
					}
				}
				$set_dr[] = "approval_status = {$safe_status}"; // Nastavení stavu ('D' nebo 'F')
				$set_dr[] = "draft_author = {$user_acc_sql}"; // Zajištění autora konceptu
				$set_dr[] = "approval_note = ''"; // Vyčištění předchozí poznámky odmítnutí
				$set_dr[] = "date_modified = GETDATE()"; // Aktualizace času úpravy konceptu
				$set_dr[] = "who_modified = {$user_uuid_sql}"; // Aktualizace relace autora konceptu
				sqlrun("UPDATE {$table} SET " . implode(', ', $set_dr) . " WHERE uuid = {$dr_uuid_sql}"); // Provedení UPDATE konceptu
			} else {
				$src_a_row = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND object_owner IN ({$rec_owner_sql}, 0x00) ORDER BY object_owner DESC, removed ASC, date_modified DESC"); // Kontrola předlohy A
				$d_ssc_map = ['record_type' => "'D'", 'approval_status' => $safe_status, 'draft_author' => $user_acc_sql, 'approval_note' => "''", 'language' => $lang_literal_sql]; // SSC sloupce konceptu
				if (! empty($src_a_row)) { // Klonování existujícího 'A' záznamu do 'D'
					$src_a_uuid = guidliteral((string) $src_a_row['uuid']); // UUID zdrojového 'A' řádku
					$d_sys_map = ['uuid' => 'NEWID()', 'object_owner' => $rec_owner_sql, 'original' => 'original']; // Identifikátory klonovaného konceptu
					$this->clone_with_map($d_sys_map + $d_ssc_map + $audit_base_map + $d_post_data, "uuid = {$src_a_uuid}"); // Vložení klonovaného konceptu
				} else {
					$d_sys_map = ['uuid' => 'NEWID()', 'original' => $orig_guid_sql, 'object_owner' => $rec_owner_sql]; // Identifikátory nového konceptu
					$this->insert_from_map($d_sys_map + $d_ssc_map + $audit_base_map + $d_post_data); // Provedení INSERTu nového konceptu
				}
			}
			sqlrun("COMMIT"); // Potvrzení transakce uložení konceptu
			return $orig_guid_raw; // Vrácení originálu uloženého konceptu
		}

		// VĚTEV B: Přímý zápis schváleného záznamu ('A' + symetrické 'L')
		$a_new_hdr = ['uuid' => $orig_guid_sql, 'original' => $orig_guid_sql, 'object_owner' => $rec_owner_sql, 'record_type' => "'A'", 'approval_status' => "'A'", 'language' => $lang_literal_sql]; // Hlavička nového A záznamu

		if ($update_guid === '' AND ! $a_exists) { // Zcela nový záznam ukládaný rovnou jako schválený
			$this->insert_from_map($a_new_hdr + $audit_base_map + $a_post_data); // Provedení INSERTu nového 'A' záznamu
		} elseif (! empty($a_post_data)) { // UPDATE nebo OVERRIDE existujícího 'A' záznamu
			if ($a_exists) { // Záznam 'A' již pro tohoto vlastníka existuje
				$set_clauses = []; // Pole přiřazení pro UPDATE
				foreach ($a_post_data as $col => $val) { // Průchod změněnými sloupci
					$set_clauses[] = "[$col] = $val"; // Nastavení nové hodnoty sloupce
				}
				$set_clauses[] = "date_modified = GETDATE()"; // Aktualizace času změny
				$set_clauses[] = "who_modified = {$user_uuid_sql}"; // Aktualizace autora změny
				sqlrun("UPDATE {$table} SET " . implode(', ', $set_clauses) . " WHERE uuid = {$a_uuid_sql}"); // Provedení UPDATE existujícího 'A' záznamu
			} else {
				$sys_row = sqlfirstrow("SELECT 1 AS ex FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = 0x00 AND record_type = 'A' AND removed = 0"); // Kontrola systémového originálu
				if (! empty($sys_row)) { // Klonování ze systémového originálu 0x00
					$ov_hdr = ['uuid' => 'NEWID()', 'object_owner' => $rec_owner_sql, 'original' => 'original', 'record_type' => "'A'", 'approval_status' => "'A'", 'language' => 'language']; // Hlavička klonu A
					$this->clone_with_map($ov_hdr + $audit_base_map + $a_post_data, "original = {$orig_guid_sql} AND object_owner = 0x00 AND record_type = 'A'", 'TOP 1', 'ORDER BY removed ASC, date_modified DESC'); // Vytvoření tenantova 'A' overridu
				} else {
					$this->insert_from_map($a_new_hdr + $audit_base_map + $a_post_data); // Vložení nového 'A' záznamu
				}
			}
		}

		if ($has_translated_cols AND $orig_guid_sql !== '' AND $table !== 'link') { // Zápis 'L' záznamu (mimo tabulku link)
			$l_owner_sql = $rec_owner_sql; // Výchozím vlastníkem překladu je vlastník záznamu
			if (is_zero_guid($orig_owner_raw) AND $right_translate) { // Oprávněný překladatel u systémového záznamu
				$l_owner_sql = '0x00'; // Oprávněný překladatel zapisuje globálně
			}
			$l_exists = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND language = {$lang_literal_sql} ORDER BY removed ASC, date_modified DESC"); // Kontrola existence L

			if (! empty($l_exists)) { // Pokud 'L' záznam již existuje -> UPDATE
				if (! empty($l_post_data)) { // Pokud jsou k dispozici přeložená data
					$set_l = []; // Pole změn pro UPDATE 'L' záznamu
					foreach ($l_post_data as $col => $val) { // Průchod překládanými sloupci
						$set_l[] = "[$col] = $val"; // Přiřazení přeložené hodnoty
					}
					$set_l[] = "date_modified = GETDATE()"; // Čas úpravy překladu
					$set_l[] = "who_modified = {$user_uuid_sql}"; // Autor úpravy překladu
					sqlrun("UPDATE {$table} SET " . implode(', ', $set_l) . " WHERE uuid = " . guidliteral((string) $l_exists['uuid'])); // Provedení UPDATE 'L' záznamu
				}
			} else {
				$l_hdr = ['uuid' => 'NEWID()', 'object_owner' => $l_owner_sql, 'record_type' => "'L'", 'approval_status' => "'A'", 'language' => $lang_literal_sql]; // Hlavička nového L záznamu
				$source_owner_sql = (! $is_sysadmin_org OR $is_self_owned) ? "object_owner IN ({$rec_owner_sql}, 0x00)" : "object_owner = 0x00"; // Podmínka vlastníka zdroje
				$this->clone_with_map($l_hdr + $audit_base_map + $l_post_data, "original = {$orig_guid_sql} AND {$source_owner_sql} AND record_type = 'A'", 'TOP 1', 'ORDER BY object_owner DESC, removed ASC, date_modified DESC'); // Založení nového 'L' záznamu
			}

			if (empty($a_post_data) AND $a_uuid_sql !== '' AND ($a_exists OR $l_owner_sql === '0x00')) { // Jednotná auditní stopa na hlavním 'A' záznamu
				sqlrun("UPDATE {$table} SET date_modified = GETDATE(), who_modified = {$user_uuid_sql} WHERE uuid = {$a_uuid_sql}"); // Aktualizace auditu na A
			}
		}

		if ($is_self_owned AND isset($a_post_data['caption']) AND $orig_guid_sql !== '') { // Propis přejmenování organizace do relací
			$new_org_cap = (string) $a_post_data['caption']; // SQL literál nového názvu organizace
			sqlrun("UPDATE wwwsession SET organization_name = {$new_org_cap} WHERE organization = {$orig_guid_sql} AND organization <> 0x00; UPDATE dbsession SET organization_name = {$new_org_cap} WHERE organization = {$orig_guid_sql} AND organization <> 0x00;"); // Aktualizace názvu
		}

		if (in_array('draft_author', $this->physical_cols, true) AND $orig_guid_sql !== '') { // Úklid konceptů ('D') při přímém uložení ('A')
			sqlrun("DELETE FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type = 'D' AND [language] = {$lang_literal_sql} AND (draft_author = {$user_acc_sql} OR draft_author = 0x00)"); // Smazání vlastního konceptu
			$safe_auto_rej = charliteral($this->phrase('msg_auto_rejected_other_approved', 'Byl schválen záznam jiného uživatele.')); // Text automatického odmítnutí
			sqlrun("UPDATE {$table} SET approval_status = 'R', approval_note = {$safe_auto_rej}, date_modified = GETDATE(), who_modified = {$user_uuid_sql} WHERE original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type = 'D' AND [language] = {$lang_literal_sql}"); // Odmítnutí souběžných konceptů
		}

		$this->run_post_save_hooks($orig_guid_sql, $rec_owner_sql, $lang_literal_sql, $user_uuid_sql); // Návazné operace po uložení

		sqlrun("COMMIT"); // Potvrzení transakce zápisu
		return $orig_guid_raw; // Vrácení originálu uloženého záznamu
	}
}