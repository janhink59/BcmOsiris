<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 14:15
 * Soubor: csv_package_simple_class.php
 * Třída: csv_package_simple_class
 * Účel: CSV balíček "simple_class" pro export a dvoufázový import dat jedné
 *       logické třídy aktuální organizace (Varianta 1: pouze záznamy vlastněné
 *       aktuálním tenantem `object_owner = @org`).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Dědí z `abstract_csv_package` (`abstract_csv_package.php`).
 * - Přijímá parametr `class_name` (`builtin_code` logické třídy nebo sekundární
 *   hierarchie), parametr `export_languages` (`ALL` = všechny jazykové mutace
 *   tenanta `A+L1+L2...`, nebo konkrétní kód jednoho jazyka se zápisem této
 *   volby do parametru `language_scope_info` v CSV) a víceřádkový parametr `info`
 *   (popis aplikovaného filtru ve formátu `Label: výraz`).
 * - Ve Fázi 2 importu volá uloženou proceduru `dbo.p_csv_import_simple_class`
 *   (`p_csv_import_simple_class.sql`), která uloží jak záznamy `A`, tak všechny
 *   exportované jazykové verze `L1, L2, L3...`.
 * =============================================================================
 */

declare(strict_types=1);

if (file_exists(__DIR__ . '/filter_manager.php')) {
	require_once __DIR__ . '/filter_manager.php';
}

class csv_package_simple_class extends abstract_csv_package {

	/**
	 * Základní identifikace balíčku simple_class.
	 */
	protected function init_package(): void {
		$this->package_code = 'simple_class';                                // Kód balíčku (odpovídá p_csv_import_simple_class)
		$this->package_title = $this->phrase('pkg_title', 'Export a import dat jedné třídy organizace (simple_class)'); // Název
		$this->description = $this->phrase('pkg_desc', 'Export a dvoufázový import záznamů jedné logické třídy vlastněných aktuální organizací (včetně všech nebo vybrané jazykové mutace a popisu filtru).'); // Popis
		$this->is_system_package = false;                                    // Klientský balíček (podporuje volbu režimu zápisu F / A)
	}

	/**
	 * Načte seznam dostupných věcných tříd a sekundárních hierarchií pro roletku `class_name`.
	 *
	 * @return array<string, string>
	 */
	private function get_available_classes_options(): array {
		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace
		$lang_sql = charliteral(get_session_lang(), 2);                      // SQL literál jazyka relace

		$rows = sqlarray_simple("
			SELECT
				mc.class_name,
				mo.builtin_code AS storage_table,
				COALESCE(NULLIF(l.caption, ''), NULLIF(mc.caption, ''), mc.class_name) AS caption
			FROM meta_class mc
			JOIN meta_object mo
				ON mo.original = mc.storage_object
				AND mo.object_type = 'T'
				AND mo.record_type = 'A'
				AND mo.removed = 0
			LEFT JOIN meta_class l
				ON l.original = mc.original
				AND l.record_type = 'L'
				AND l.[language] = {$lang_sql}
				AND l.removed = 0
				AND l.object_owner IN ({$org_sql}, 0x00)
			WHERE mc.object_owner IN (0x00, {$org_sql})
			  AND mc.record_type = 'A'
			  AND mc.removed = 0
			  AND mo.builtin_code NOT LIKE 'meta_%'
			  AND mo.builtin_code NOT IN ('organization', 'user_account', 'user_organization_access')
			ORDER BY CASE WHEN mc.ancestor_class IS NULL THEN 0 ELSE 1 END, mc.sort_code, mc.class_name
		");                                                                  // Načtení věcných a katalogových tříd

		$opts = [];                                                          // Výstupní asociativní pole voleb
		if (is_array($rows)) {                                               // Kontrola platného pole výsledků
			foreach ($rows as $r) {                                          // Průchod třídami
				$c_code = (string) $r['class_name'];                         // Kód logické třídy
				$c_cap = (string) $r['caption'];                             // Lokalizovaný název třídy
				$opts[$c_code] = ($c_cap !== '' AND $c_cap !== $c_code) ? "{$c_cap} ({$c_code})" : $c_code; // Text volby
			}
		}
		if (empty($opts)) {                                                  // Nouzový fallback pokud by dotaz nic nevrátil
			$opts['threat'] = 'threat';                                      // Výchozí katalog hrozeb
		}
		return $opts;                                                        // Vrácení seznamu tříd
	}

	/**
	 * Vrátí volby pro parametr `export_languages` (Všechny jazyky tenanta vs. konkrétní jazyk).
	 *
	 * @return array<string, string>
	 */
	private function get_language_scope_options(): array {
		$opts = [                                                            // Výchozí volba všech jazyků
			'ALL' => $this->phrase('opt_lang_all', 'Všechny jazykové mutace tenanta (A + L1 + L2...)')
		];
		$lm = new language_manager();                                        // Instance správce jazyků
		foreach ($lm->get_languages() as $l_code => $l_row) {                // Průchod podporovanými jazyky
			$l_cap = (string) ($l_row['caption'] ?? $l_code);                // Název jazyka
			$opts[(string) $l_code] = $this->phrase(
				'opt_lang_single',
				'Pouze jedna jazyková verze: {' . chr(36) . 'caption} ({' . chr(36) . 'code})',
				['caption' => $l_cap, 'code' => $l_code]
			);                                                               // Položka pro export jednoho jazyka
		}
		return $opts;                                                        // Vrácení voleb jazykového rozsahu
	}

	/**
	 * Definice filtračních parametrů specifických pro balíček simple_class.
	 *
	 * @return array<string, array<string, mixed>>
	 */
	public function get_filter_parameters_def(): array {
		$cls_opts = $this->get_available_classes_options();                  // Seznam dostupných tříd
		$def_cls = (string) array_key_first($cls_opts);                      // Výchozí první třída v seznamu

		return [                                                             // Specifické parametry balíčku simple_class
			'class_name' => [
				'label'     => $this->phrase('lbl_param_class_name', 'Logická třída (class_name / builtin_code)'),
				'type'      => 'varchar',
				'mandatory' => true,
				'default'   => $def_cls,
				'options'   => $cls_opts
			],
			'export_languages' => [
				'label'     => $this->phrase('lbl_param_export_languages', 'Jazykové mutace k exportu'),
				'type'      => 'varchar',
				'mandatory' => true,
				'default'   => 'ALL',
				'options'   => $this->get_language_scope_options()
			],
			'info' => [
				'label'       => $this->phrase('lbl_param_info', 'Popis aplikovaného filtru (info – víceřádkový ve tvaru Label: výraz)'),
				'type'        => 'textarea',
				'rows'        => 4,
				'mandatory'   => false,
				'default'     => '',
				'placeholder' => "Název: *požár*\nSkóre: >=10"
			]
		];                                                                   // Konec definice parametrů
	}

	/**
	 * Doplní do hlavičky CSV explicitní parametr `language_scope_info`, pokud byla
	 * vyexportována jen jedna jazyková verze (a která), a výchozí popis filtru `info`.
	 *
	 * @param array<string, string> $header_params Hlavičkové parametry CSV
	 */
	protected function customize_export_header_params(array &$header_params): void { // Doplnění parametrů do hlavičky CSV
		$exp_lang = trim((string) ($this->params['export_languages'] ?? 'ALL')); // Zvolený rozsah jazyků
		if ($exp_lang === '' OR strtoupper($exp_lang) === 'ALL') {           // Export všech jazykových mutací tenanta
			$header_params['export_languages'] = 'ALL';                      // Kód pro všechny jazyky
			$header_params['language_scope_info'] = $this->phrase('info_all_langs_exported', 'Exportovány všechny jazykové mutace tenanta (A + L1 + L2...)'); // Popis
		} else {
			$lm = new language_manager();                                    // Správce jazyků pro zjištění názvu jazyka
			$langs = $lm->get_languages();                                   // Mapa jazyků
			$l_cap = (string) ($langs[$exp_lang]['caption'] ?? $exp_lang);   // Název zvoleného jazyka
			$header_params['export_languages'] = $exp_lang;                  // Kód exportovaného jazyka
			$header_params['language_scope_info'] = $this->phrase(
				'info_single_lang_exported',
				'Exportována pouze jedna jazyková verze: {' . chr(36) . 'caption} ({' . chr(36) . 'code})',
				['caption' => $l_cap, 'code' => $exp_lang]
			);                                                               // Explicitní záznam v parametrech o exportu 1 jazyka
		}

		if (trim((string) ($header_params['info'] ?? '')) === '') {          // Pokud nebyl zadán žádný filtr v info
			$header_params['info'] = $this->phrase('info_no_filter_applied', 'Bez filtru (všechny záznamy třídy vlastněné organizací)'); // Výchozí info
		}
	}

	/**
	 * Zjistí fyzickou tabulku (`storage_table`) a případné UUID sekundární hierarchie pro zadanou třídu.
	 *
	 * @return array{storage_table: string, hierarchy_uuid: string}
	 */
	private function resolve_class_storage_info(string $class_code): array { // Zjištění úložné tabulky a hierarchie
		$clean_code = trim($class_code);                                     // Očištěný kód třídy
		if ($clean_code === '') {                                            // Prázdný kód
			return ['storage_table' => '', 'hierarchy_uuid' => ''];          // Neplatná třída
		}

		$em = new entity_manager($clean_code);                               // Inicializace správce entit pro danou třídu
		$stg = $em->get_storage_table();                                     // Fyzická tabulka třídy
		$hier_uuid = '';                                                     // Případné UUID sekundární hierarchie

		if ($stg === 'hierarchy_item' AND $clean_code !== 'hierarchy_item') { // Odvozená třída sekundární hierarchie (STI)
			$org_sql = guidliteral(get_session_org());                       // SQL literál aktivní organizace
			$safe_c = charliteral($clean_code, 80);                          // SQL literál builtin_code hierarchie
			$h_row = sqlfirstrow("
				SELECT TOP 1 original
				FROM hierarchy
				WHERE builtin_code = {$safe_c}
				  AND object_owner IN ({$org_sql}, 0x00)
				  AND record_type = 'A'
				  AND removed = 0
				ORDER BY CASE WHEN object_owner = {$org_sql} THEN 0 ELSE 1 END
			");                                                              // Dohledání originálu sekundární hierarchie
			if (! empty($h_row['original'])) {                               // Pokud byla sekundární hierarchie nalezena
				$hier_uuid = (string) $h_row['original'];                    // Uložení UUID sekundární hierarchie
			}
		}

		return ['storage_table' => $stg, 'hierarchy_uuid' => $hier_uuid];    // Vrácení fyzické tabulky a hierarchie
	}

	/**
	 * Sestaví SQL dotaz pro export jedné tabulky s aplikovaným filtrem a rozsahem jazyků
	 * (Varianta 1: striktně pouze záznamy vlastněné aktuálním tenantem `object_owner = @org`).
	 *
	 * @param array<string, string> $params Parametry exportu
	 * @return array<string, string>
	 */
	public function get_export_tables_sql(array $params): array {            // Sestavení exportního SQL dotazu
		$cls_code = trim((string) ($params['class_name'] ?? ''));            // Zvolená logická třída
		$info_meta = $this->resolve_class_storage_info($cls_code);           // Zjištění fyzické tabulky a hierarchie
		$table = $info_meta['storage_table'];                                // Fyzická tabulka v DB
		if ($table === '' OR str_starts_with($table, 'meta_')) {             // Ochrana proti neplatné nebo metadatové tabulce
			return [];                                                       // Prázdný výsledek
		}

		$org_raw = get_session_org();                                        // Surové UUID aktuální organizace
		$org_sql = guidliteral($org_raw);                                    // SQL literál aktuální organizace
		$em = new entity_manager($cls_code);                                 // Správce entit pro vyhodnocení filtru

		$where_em = '';                                                      // Základní WHERE podmínka pro entity_manager
		if ($info_meta['hierarchy_uuid'] !== '') {                           // Omezení na konkrétní sekundární hierarchii
			$where_em = "m.hierarchy = " . guidliteral($info_meta['hierarchy_uuid']); // Podmínka na sloupec hierarchy
		}

		// Načtení záznamů třídy a případná aplikace filtru zadaného v parametru info (Label: výraz)
		$all_rows = $em->fetch_rows($where_em, '', true, true);              // Načtení záznamů (včetně zrušených, bez konceptů D)
		$filtered_rows = $all_rows;                                          // Výchozí stav před aplikací filtru

		$raw_info = trim((string) ($params['info'] ?? ''));                  // Text parametru info z formuláře
		if ($raw_info !== '' AND class_exists('filter_manager')) {           // Pokud je zadán víceřádkový popis filtru (Label: výraz)
			$fm = new filter_manager($em, 'csv_export_tmp_' . $cls_code);    // Pomocná instance filter_manageru
			if (method_exists($fm, 'parse_info_to_filters')) {               // Převod řádků "Label: výraz" na pole filtrů
				$parsed_flts = $fm->parse_info_to_filters($raw_info);        // Rozparsované podmínky filtru
				if (! empty($parsed_flts)) {                                 // Pokud byly rozpoznány filtrační výrazy
					$fm->set_active_filters($parsed_flts);                   // Nastavení podmínek do filter_manageru
					$filtered_rows = $fm->filter_rows($all_rows);            // Vyfiltrování záznamů
				}
			}
		}

		// Rychlý textový filtr z #master-filter (pokud byl předán v URL nebo v info jako "Rychlý filtr: ...")
		$quick_flt = trim((string) getinput('quick_filter'));                // Rychlý filtr z URL
		if ($quick_flt !== '') {                                             // Pokud byl zadán rychlý filtr
			$q_low = mb_strtolower($quick_flt, 'UTF-8');                     // Hledaný podřetězec malými písmeny
			$tmp_rows = [];                                                  // Pole vyhovujících řádků
			foreach ($filtered_rows as $fr) {                                // Průchod řádky
				$row_concat = mb_strtolower(implode(' ', array_map('strval', $fr)), 'UTF-8'); // Spojení hodnot řádku
				if (str_contains($row_concat, $q_low)) {                     // Shoda s rychlým filtrem
					$tmp_rows[] = $fr;                                       // Zařazení řádku
				}
			}
			$filtered_rows = $tmp_rows;                                      // Aktualizace filtrovaných řádků
		}

		// Sběr identifikátorů original vyhovujících záznamů (u stromových tabulek včetně nadřízených uzlů)
		$full_map = [];                                                      // Mapa všech záznamů podle original
		foreach ($all_rows as $ar) {                                         // Naplnění mapy pro dohledání předků
			$full_map[strtolower((string) $ar['original'])] = $ar;           // Uložení záznamu
		}

		$has_parent_col = $em->has_physical_column('parent_uuid');           // Zda jde o stromovou tabulku
		$selected_origs = [];                                                // Množina vybraných SQL literálů original

		foreach ($filtered_rows as $fr) {                                    // Průchod vyhovujícími záznamy
			$curr_k = strtolower((string) $fr['original']);                  // Klíč original
			$guard = 0;                                                      // Pojistka proti cyklu
			while ($curr_k !== '' AND isset($full_map[$curr_k]) AND $guard < 50) { // Průchod k rodičům u stromu
				$gl = guidliteral($curr_k);                                  // Bezpečný SQL literál UUID
				if ($gl !== 'NULL') {                                        // Pokud je UUID platné
					$selected_origs[$curr_k] = $gl;                          // Přidání do seznamu k exportu
				}
				if (! $has_parent_col) {                                     // Pokud tabulka není stromová
					break;                                                   // Nehledáme nadřízené uzly
				}
				$par_k = strtolower(trim((string) ($full_map[$curr_k]['parent_uuid'] ?? ''))); // Rodič uzlu
				if ($par_k === $curr_k) {                                    // Ochrana proti zacyklení
					break;                                                   // Ukončení
				}
				$curr_k = $par_k;                                            // Posun na rodiče
				$guard++;                                                    // Inkrementace kroku
			}
		}

		// Sestavení seznamu exportovaných fyzických sloupců (bez interních session/auditních sloupců)
		$skip_export_cols = [                                                // Sloupce, které se do přenosového CSV neexportují
			'object_owner', 'approval_status', 'draft_author', 'approval_note',
			'import_origin', 'date_created', 'who_created', 'date_modified', 'who_modified'
		];
		$export_cols = [];                                                   // Seznam sloupců pro SELECT
		$safe_tab = charliteral($table, 128);                                // SQL literál tabulky
		$syscols = sqlarray_simple("SELECT colname FROM v_syscolumns WHERE tabname = {$safe_tab} AND iscomputed = 0 AND is_identity = 0 ORDER BY colid"); // Fyzické sloupce
		if (is_array($syscols)) {                                            // Průchod fyzickými sloupci tabulky
			foreach ($syscols as $sc) {                                      // Zpracování sloupce
				$cn = (string) $sc['colname'];                               // Název sloupce
				if (! in_array($cn, $skip_export_cols, true)) {              // Pokud nejde o vynechaný auditní sloupec
					$export_cols[] = "[{$cn}]";                              // Přidání sloupce do SELECTu
				}
			}
		}

		if (empty($export_cols)) {                                           // Pojistka při nenalezení sloupců
			return [];                                                       // Prázdný výsledek
		}

		$cols_sql = implode(', ', $export_cols);                             // Projekce sloupců pro SELECT
		$orig_in_cond = ! empty($selected_origs)
			? ('AND original IN (' . implode(', ', array_values($selected_origs)) . ')')
			: 'AND 1 = 0';                                                   // Omezení na vyfiltrované záznamy

		$hier_cond = ($info_meta['hierarchy_uuid'] !== '')
			? ('AND hierarchy = ' . guidliteral($info_meta['hierarchy_uuid']))
			: '';                                                            // Případné omezení na sekundární hierarchii

		$exp_lang = trim((string) ($params['export_languages'] ?? 'ALL'));   // Volba jazykových mutací
		if ($exp_lang === '' OR strtoupper($exp_lang) === 'ALL') {           // Všechny jazykové mutace tenanta (A + L1 + L2...)
			$lang_cond = "AND record_type IN ('A', 'L')";                    // Hlavní záznamy i všechny překlady tenanta
		} else {
			$safe_l = charliteral($exp_lang, 2);                             // SQL literál vybraného jazyka
			$lang_cond = "AND (record_type = 'A' OR (record_type = 'L' AND [language] = {$safe_l}))"; // A + vybraný jazyk L
		}

		$order_sql = "ORDER BY original, CASE WHEN record_type = 'A' THEN 0 ELSE 1 END, [language]"; // Řazení A a následně L mutací

		return [                                                             // Výsledný exportní SQL dotaz pro tabulku (Varianta 1: pouze záznamy tenanta)
			$table => "
				SELECT {$cols_sql}
				FROM [{$table}]
				WHERE object_owner = {$org_sql}
				  {$lang_cond}
				  {$hier_cond}
				  {$orig_in_cond}
				{$order_sql}
			"
		];
	}

	/**
	 * Vrátí definici tabulky a povinných sloupců pro formální kontrolu ve Fázi 1 importu.
	 *
	 * @return array<string, array<string, mixed>>
	 */
	public function get_tables_definition(): array {
		$cls_code = trim((string) ($this->params['class_name'] ?? ''));      // Kód třídy z parametrů balíčku
		$info_meta = $this->resolve_class_storage_info($cls_code);           // Zjištění fyzické tabulky
		$table = $info_meta['storage_table'];                                // Název očekávané tabulky v CSV
		if ($table === '') {                                                 // Pokud třída nebyla rozpoznána
			return [];                                                       // Prázdná definice
		}

		$mand_cols = [                                                       // Základní povinné sloupce každé RAC tabulky v CSV
			'original'    => ['datatype' => 'uuid',    'mandatory' => true],
			'record_type' => ['datatype' => 'varchar', 'mandatory' => true],
			'language'    => ['datatype' => 'varchar', 'mandatory' => true]
		];

		$em = new entity_manager($cls_code);                                 // Správce entit pro zjištění klíčových sloupců
		foreach ($em->get_original_key_columns() as $kc) {                   // Průchod klíčovými sloupci z meta_original_keys
			if ($kc !== 'ancestor_link') {                                   // Kromě technického ancestor_link
				$mand_cols[$kc] = ['datatype' => 'varchar', 'mandatory' => true]; // Klíčový sloupec je v CSV povinný
			}
		}

		return [                                                             // Definice očekávané tabulky pro Fázi 1
			$table => [
				'mandatory' => true,
				'columns'   => $mand_cols
			]
		];
	}
}