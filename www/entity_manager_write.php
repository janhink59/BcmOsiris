<?php
/**
 * =============================================================================
 * Verze: 2026-10-23 15:15
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit – čtecí, metadatová a UI vrstva (STI Architektura).
 *       Zápisové a schvalovací metody jsou vyčleněny do traitu entity_manager_write
 *       v souboru entity_manager_write.php.
 * 
 * VAZBY NA OKOLÍ:
 * - Instancován z potomků `abstract_page_master_detail` (v metodě `render()`),
 *   `page_meta_column.php` a z univerzální schvalovací stránky `page_approval.php`.
 * - Vkládá trait `entity_manager_write` (`entity_manager_write.php`).
 * - Využívá globální pole `$dbsession` (inicializované v `OsirisLib.php` přes `initsession()`).
 * - Využívá třídu `language_manager` (`language_manager.php`) a databázovou funkci
 *   `dbo.f_language_list()` s podmínkou `fallback_order < 1000`.
 * - Využívá globální `$phrase_manager` (`phrase_manager.php`) pro lokalizaci hlášek.
 * - Využívá databázové funkce z `OsirisLib.php` (`sqlrun`, `sqlfirstrow`, `sqlarray_simple`,
 *   `charliteral`, `guidliteral`, `intliteral`, `fatal_error`, `getinput`).
 * 
 * KLÍČOVÉ KONCEPTY A ARCHITEKTURA:
 * 1. Single Table Inheritance (STI) a Dědičnost sloupců (ancestor)
 *    Systém abstrahuje fyzické tabulky (meta_object) do logických tříd (meta_class).
 *    Chybějící vlastnosti sloupců v meta_column se dědí z předka v 'sys_global_columns'.
 * 2. Dvoupolové vyhodnocování jazykových verzí v PHP (Konec obřích LEFT JOIN dotazů)
 *    Místo nabalování desítek LEFT JOINů a COALESCE pro každý fallback jazyk a předka
 *    načte `fetch_rows()` (i `load_metadata()`) jedním dotazem záznamy 'A'/'D' a k nim
 *    záznamy 'L' s `fallback_order < 1000` (přes `dbo.f_language_list`).
 *    V PHP z nich vytvoří dvě pole:
 *    - pole hlavních záznamů indexované podle `original`,
 *    - podřízené dvojrozměrné pole `[original][language]` seřazené podle `fallback_order`.
 *    Pro každý `original` pak zjistí překlad:
 *    a) je-li jazyk 'A' shodný s aktuálním jazykem (a tenant nemá vlastní 'L' override),
 *       vezme se rovnou hodnota z 'A' bez hledání v podřízeném poli,
 *    b) jinak projde podřízené pole dle `fallback_order` a vezme první neprázdnou hodnotu
 *       (včetně kontroly 'A' záznamu na dané úrovni `fallback_order`),
 *    c) pokud neprázdnou hodnotu nenajde, použije hodnotu ze záznamu 'A' (i v cizím jazyce),
 *    d) pokud je hodnota prázdná a záznam má `ancestor`, vyhodnotí tutéž logiku pro předka.
 * 
 * Změny:
 * 2026-10-23 15:15 - V metodě fetch_rows() odstraněn filtr `rc.removed = 0` v CTE `dr`
 *                    (zpřístupnění konceptů navrhujících zrušení záznamu) a doplněno
 *                    vyhodnocení `native_language` a `l_removed` pro koncepty `'D'`.
 * 2026-10-23 11:00 - Doplněna plná lokalizace položek roletek <select> v render_dynamic_input()
 *                    pro referenced_codetable i referenced_class pomocí dbo.f_language_list
 *                    (fallback_order < 1000) a tenant overridů.
 * 2026-10-22 22:40 - Oprava projekce sloupců předků ($select_anc_cols) a překladů ($select_l_cols)
 *                    v metodě fetch_rows() a doplněna metoda fetch_records().
 * 2026-10-22 17:45 - Kompletní náhrada masivních LEFT JOIN / COALESCE dotazů v load_metadata()
 *                    a čtení dat za dvoupolové vyhodnocení v metodách fetch_rows() a fetch_row().
 * =============================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/entity_manager_write.php';

class entity_manager {

	use entity_manager_write;

	private string $class_name;                                              // Název logické třídy
	private array $class_meta = [];                                          // Metadata logické třídy
	private string $storage_table = '';                                      // Fyzická tabulka v databázi
	private array $columns_meta = [];                                        // Metadata jednotlivých sloupců
	private array $list_columns = [];                                        // Sloupce pro zobrazení v Master panelu
	private bool $is_initialized = false;                                    // Příznak úspěšného načtení metadat
	private language_manager $lang_manager;                                  // Instance správce jazyků
	
	private array $physical_cols = [];                                       // Seznam fyzických sloupců tabulky
	private array $col_types = [];                                           // Datové typy fyzických sloupců
	private array $col_nulls = [];                                           // Příznaky nullability fyzických sloupců

	/**
	 * Konstruktor třídy.
	 * 
	 * @param string $class_name Identifikátor logické třídy z DB (např. 'asset_class')
	 */
	public function __construct(string $class_name) {                        // Inicializace správce pro danou třídu
		$this->class_name = $class_name;                                     // Uložení identifikátoru třídy
		$this->lang_manager = new language_manager();                        // Inicializace jazykového manažeru
		$this->load_metadata();                                              // Načtení metadat třídy a sloupců
	}

	/**
	 * Pomocná metoda pro překlad interních textů třídy entity_manager.
	 *
	 * @param string               $builtin_code    Kód fráze
	 * @param string               $default_caption Výchozí český text
	 * @param array<string, mixed> $vars            Proměnné pro interpolaci
	 * @return string Přeložený text
	 */
	private function phrase(string $builtin_code, string $default_caption, array $vars = []): string { // Překlad interní fráze
		global $phrase_manager;                                              // Globální instance správce frází
		if (!isset($phrase_manager) OR !($phrase_manager instanceof phrase_manager)) { // Kontrola existence správce frází
			$phrase_manager = new phrase_manager();                          // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] = $phrase_manager;                    // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, $vars, $default_caption, 'entity_manager'); // Vrácení přeložené fráze
	}

	/**
	 * Určuje, zda aktuální entita patří mezi systémové metadatové tabulky (meta_*).
	 */
	private function is_metadata_entity(): bool {
		return str_starts_with($this->storage_table, 'meta_');               // Detekce prefixu meta_ u fyzické tabulky
	}

	/**
	 * Vrátí název fyzické tabulky v databázi.
	 */
	public function get_storage_table(): string {
		return $this->storage_table;                                         // Vrácení názvu fyzické tabulky
	}

	/**
	 * Ověří, zda fyzická tabulka v databázi obsahuje zadaný sloupec.
	 */
	public function has_physical_column(string $column_name): bool {         // Kontrola existence fyzického sloupce
		return in_array($column_name, $this->physical_cols, true);           // Vyhledání v poli fyzických sloupců
	}

	/**
	 * Pomocná metoda: Vyhodnotí přeloženou textovou hodnotu sloupce pro daný 'original'
	 * z hlavního pole 'A' ($a_rows) a podřízeného 2D pole 'L' ($l_rows) seřazeného dle fallback_order.
	 *
	 * @param string $orig        UUID originálu záznamu
	 * @param string $col         Název překládaného sloupce
	 * @param array  $a_rows      Hlavní pole záznamů 'A'/'D' indexované podle original
	 * @param array  $anc_a_rows  Pole 'A' záznamů předků indexované podle original
	 * @param array  $l_rows      Podřízené 2D pole 'L' záznamů: [original][language => row]
	 * @param string $curr_lang   Aktuální jazyk relace (fallback_order = 1)
	 * @param array  $lang_chain  Seznam jazyků s fallback_order < 1000 seřazený vzestupně
	 * @param string $anc_key     Název sloupce odkazujícího na předka (např. 'ancestor' nebo 'ancestor_class')
	 * @return string Výsledná přeložená hodnota
	 */
	private function resolve_field_from_arrays(
		string $orig,                                                        // UUID záznamu
		string $col,                                                         // Název sloupce
		array &$a_rows,                                                      // Pole hlavních 'A'/'D' záznamů
		array &$anc_a_rows,                                                  // Pole předků 'A'
		array &$l_rows,                                                      // Podřízené 2D pole 'L' záznamů
		string $curr_lang,                                                   // Aktuální jazyk relace
		array $lang_chain,                                                   // Řetězec jazyků dle fallback_order
		string $anc_key = 'ancestor'                                         // Sloupec vazby na předka
	): string {
		$row = $a_rows[$orig] ?? $anc_a_rows[$orig] ?? null;                 // Nalezení hlavního záznamu 'A'/'D'
		if ($row === null) {                                                 // Pokud záznam neexistuje
			return '';                                                       // Vrátíme prázdný řetězec
		}

		// 0. Pokud je aktivní řádek rozpracovaným konceptem ('D') a má vyplněnou hodnotu, má přednost
		if (($row['record_type'] ?? 'A') === 'D' AND (string)($row[$col] ?? '') !== '') { // Hodnota z konceptu
			return (string)$row[$col];                                       // Vrácení hodnoty konceptu
		}

		$a_lang = (string)($row['language'] ?? 'cs');                        // Jazyk hlavního 'A' záznamu
		$a_val = (string)($row[$col] ?? '');                                 // Hodnota v hlavním 'A' záznamu
		$has_tenant_l_curr = (!empty($l_rows[$orig][$curr_lang]['is_tenant_l']) AND (string)($l_rows[$orig][$curr_lang][$col] ?? '') !== ''); // Zda má tenant vlastní L

		// 1. Je-li jazyk 'A' shodný s aktuálním jazykem (a tenant nemá vlastní L override), bereme rovnou 'A'
		if ($a_lang === $curr_lang AND $a_val !== '' AND !$has_tenant_l_curr) { // Shoda jazyka 'A' s aktuálním jazykem
			return $a_val;                                                   // Není třeba hledat v podřízeném poli
		}

		// 2. Průchod podřízeným polem 'L' seřazeným podle fallback_order (< 1000)
		foreach ($lang_chain as $fl_lang) {                                  // Průchod jazyky dle fallback_order
			if (isset($l_rows[$orig][$fl_lang])) {                           // Pokud existuje 'L' záznam pro daný jazyk
				$l_val = (string)($l_rows[$orig][$fl_lang][$col] ?? '');     // Hodnota v 'L' záznamu
				$l_rem = !empty($l_rows[$orig][$fl_lang]['removed']);        // Zda je 'L' záznam zrušený
				if (!$l_rem AND $l_val !== '') {                             // Nalezena platná neprázdná hodnota v 'L'
					return $l_val;                                           // Vrácení nalezeného překladu
				}
			}
			if ($a_lang === $fl_lang AND $a_val !== '') {                    // Pokud je samotný 'A' záznam v tomto fallback jazyce
				return $a_val;                                               // Vrácení hodnoty z 'A' na příslušné úrovni fallbacku
			}
		}

		// 3. Pokud se v podřízeném poli nic nenašlo, vezmeme hodnotu ze záznamu 'A' (i v neznámém jazyce)
		if ($a_val !== '') {                                                 // Pokud má 'A' záznam neprázdnou hodnotu
			return $a_val;                                                   // Vrácení hodnoty z 'A'
		}

		// 4. Dědičnost z předka (ancestor / ancestor_class), pokud je vazba vyplněna
		$anc_orig = (string)($row[$anc_key] ?? '');                          // UUID předka
		if ($anc_orig !== '' AND $anc_orig !== $orig) {                      // Ochrana proti zacyklení
			return $this->resolve_field_from_arrays($anc_orig, $col, $a_rows, $anc_a_rows, $l_rows, $curr_lang, $lang_chain, $anc_key); // Rekurze na předka
		}

		return '';                                                           // Nikde nebyla nalezena neprázdná hodnota
	}

	/**
	 * Načte metadata logické třídy, identifikuje fyzickou tabulku 
	 * a načte definici sloupců pomocí dvoupolového vyhodnocení ('A' + podřízené 'L').
	 */
	private function load_metadata(): void {
		$safe_class = charliteral($this->class_name);                        // Bezpečný SQL literál názvu třídy
		
		global $dbsession;                                                   // Globální kontext relace
		$org_uuid = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál organizace
		$curr_lang = $this->lang_manager->get_current_language();            // Aktuální jazyk relace
		$safe_lang = charliteral($curr_lang, 2);                             // SQL literál jazyka
		$lang_chain = $this->lang_manager->get_fallback_chain();             // Řetězec jazyků s fallback_order < 1000

		// 1. Načtení definice logické třídy ('A' i 'L' pro třídu a jejího případného předka ancestor_class)
		$sql_class = "
		WITH fl AS (
			SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
		),
		base_cls AS (
			SELECT mc.*, mo.builtin_code AS storage_table_name, mo.original AS storage_original
			FROM meta_class mc
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
			WHERE mc.class_name = {$safe_class} AND mc.record_type = 'A' AND mc.object_owner = 0x00 AND mc.removed = 0
		)
		SELECT 'A' AS row_kind, 0 AS is_tenant_l, 0 AS fallback_order,
			c.original, c.class_name, c.storage_object, c.ancestor_class, c.sort_code, c.svg_icon,
			c.is_final, c.is_protected, c.inactive, c.[language],
			COALESCE(NULLIF(CAST(c_my.caption AS NVARCHAR(MAX)), ''), CAST(c.caption AS NVARCHAR(MAX)), '') AS caption,
			COALESCE(NULLIF(CAST(c_my.caption_plural AS NVARCHAR(MAX)), ''), CAST(c.caption_plural AS NVARCHAR(MAX)), '') AS caption_plural,
			COALESCE(NULLIF(CAST(c_my.description AS NVARCHAR(MAX)), ''), CAST(c.description AS NVARCHAR(MAX)), '') AS description,
			COALESCE(NULLIF(CAST(c_my.helptext AS NVARCHAR(MAX)), ''), CAST(c.helptext AS NVARCHAR(MAX)), '') AS helptext,
			c.storage_table_name, c.storage_original
		FROM base_cls c
		LEFT JOIN meta_class c_my ON c_my.original = c.original AND c_my.record_type = 'A' AND c_my.object_owner = {$org_uuid} AND c_my.object_owner <> 0x00 AND c_my.removed = 0

		UNION ALL

		SELECT 'L' AS row_kind, CASE WHEN l.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant_l, fl.fallback_order,
			l.original, l.class_name, l.storage_object, l.ancestor_class, l.sort_code, l.svg_icon,
			l.is_final, l.is_protected, l.inactive, l.[language],
			CAST(l.caption AS NVARCHAR(MAX)) AS caption,
			CAST(l.caption_plural AS NVARCHAR(MAX)) AS caption_plural,
			CAST(l.description AS NVARCHAR(MAX)) AS description,
			CAST(l.helptext AS NVARCHAR(MAX)) AS helptext,
			'' AS storage_table_name, 0x00 AS storage_original
		FROM base_cls c
		JOIN meta_class l ON l.original = c.original AND l.record_type = 'L' AND l.removed = 0 AND l.object_owner IN (0x00, {$org_uuid})
		JOIN fl ON fl.[language] = l.[language]
		ORDER BY row_kind ASC, fallback_order ASC, is_tenant_l DESC
		";                                                                   // Jednoduchý dotaz na metadata třídy bez násobných JOINů

		$cls_rows = sqlarray_simple($sql_class);                             // Načtení metadat třídy do paměti
		if (empty($cls_rows)) {                                              // Pokud logická třída neexistuje
			return;                                                          // Ukončení inicializace
		}

		$cls_a_map = [];                                                     // Pole 'A' záznamů třídy
		$cls_anc_map = [];                                                   // Prázdné pole předků třídy
		$cls_l_map = [];                                                     // Podřízené pole 'L' záznamů třídy
		foreach ($cls_rows as $cr) {                                         // Rozdělení na 'A' a 'L' pole
			$c_orig = (string)$cr['original'];                               // UUID třídy
			if ($cr['row_kind'] === 'A') {                                   // Hlavní záznam třídy
				$cls_a_map[$c_orig] = $cr;                                   // Uložení 'A' záznamu třídy
			} else {
				$c_lang = (string)$cr['language'];                           // Jazyk 'L' záznamu třídy
				if (!isset($cls_l_map[$c_orig][$c_lang])) {                  // První záznam pro daný jazyk
					$cls_l_map[$c_orig][$c_lang] = $cr;                      // Uložení do podřízeného pole
				}
			}
		}

		$main_cls_orig = (string)array_key_first($cls_a_map);                // UUID načtené třídy
		$row = $cls_a_map[$main_cls_orig];                                   // Základní data třídy
		foreach (['caption', 'caption_plural', 'description', 'helptext'] as $tf) { // Dosazení přeložených textů třídy
			$row[$tf] = $this->resolve_field_from_arrays($main_cls_orig, $tf, $cls_a_map, $cls_anc_map, $cls_l_map, $curr_lang, $lang_chain, 'ancestor_class'); // Překlad
		}

		$this->class_meta = $row;                                            // Uložení metadat třídy
		$this->storage_table = (string)$row['storage_table_name'];           // Název fyzické tabulky
		$class_uuid = guidliteral($main_cls_orig);                           // SQL literál UUID třídy

		// 2. Načtení fyzického databázového schématu z v_syscolumns
		$syscols = sqlarray_simple("SELECT colname, typename, nulls FROM v_syscolumns WHERE tabname = " . charliteral($this->storage_table) . " AND iscomputed = 0 AND is_identity = 0"); // Fyzické sloupce
		if (is_array($syscols)) {                                            // Kontrola platného pole fyzických sloupců
			foreach ($syscols as $c) {                                       // Průchod fyzickými sloupci tabulky
				$cname = (string)$c['colname'];                              // Název fyzického sloupce
				$this->physical_cols[] = $cname;                             // Zařazení do seznamu fyzických sloupců
				$this->col_types[$cname] = (string)$c['typename'];           // Datový typ sloupce
				$this->col_nulls[$cname] = strtolower(trim((string)$c['nulls'])); // Příznak nullability sloupce
			}
		}

		// 3. Načtení sloupců třídy, jejich předků (ancestor v sys_global_columns) a jazykových verzí ('L' s fallback_order < 1000) jedním dotazem
		$sql_cols = "
		WITH fl AS (
			SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
		),
		cls_cols AS (
			SELECT c.*
			FROM meta_column c
			WHERE c.parent_class = {$class_uuid} AND c.record_type = 'A' AND c.object_owner = 0x00 AND c.removed = 0
		),
		anc_cols AS (
			SELECT a.*
			FROM meta_column a
			WHERE a.record_type = 'A' AND a.object_owner = 0x00 AND a.removed = 0
			  AND a.original IN (SELECT DISTINCT ancestor FROM cls_cols WHERE ancestor IS NOT NULL)
		),
		all_origs AS (
			SELECT original FROM cls_cols
			UNION
			SELECT original FROM anc_cols
		)
		SELECT 'A' AS row_kind, 0 AS is_tenant_l, 0 AS fallback_order, c.*
		FROM cls_cols c

		UNION ALL

		SELECT 'ANC_A' AS row_kind, 0 AS is_tenant_l, 0 AS fallback_order, a.*
		FROM anc_cols a

		UNION ALL

		SELECT 'L' AS row_kind, CASE WHEN l.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant_l, fl.fallback_order, l.*
		FROM meta_column l
		JOIN all_origs ao ON ao.original = l.original
		JOIN fl ON fl.[language] = l.[language]
		WHERE l.record_type = 'L' AND l.removed = 0 AND l.object_owner IN (0x00, {$org_uuid})
		ORDER BY row_kind ASC, parent_order ASC, sort_code ASC, fallback_order ASC, is_tenant_l DESC
		";                                                                   // Jednotný dotaz na sloupce, předky a jejich překlady

		$raw_col_rows = sqlarray_simple($sql_cols);                          // Načtení všech záznamů sloupců do paměti
		$col_a_map = [];                                                     // Hlavní pole 'A' záznamů sloupců: [original => row]
		$col_anc_map = [];                                                   // Pole 'A' záznamů předků sloupců: [original => row]
		$col_l_map = [];                                                     // Podřízené 2D pole 'L' záznamů: [original][language => row]
		$trans_col_fields = ['caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder']; // Překládaná pole

		if (is_array($raw_col_rows)) {                                       // Rozdělení načtených řádků do polí
			foreach ($raw_col_rows as $rc) {                                 // Průchod načtenými řádky
				$orig = (string)$rc['original'];                             // UUID originálu sloupce
				$kind = (string)$rc['row_kind'];                             // Druh řádku ('A', 'ANC_A', 'L')
				if ($kind === 'A') {                                         // Vlastní sloupec třídy
					$col_a_map[$orig] = $rc;                                 // Uložení do hlavního pole sloupců
				} elseif ($kind === 'ANC_A') {                               // Sloupec předka v sys_global_columns
					$col_anc_map[$orig] = $rc;                               // Uložení do pole předků
				} else {
					$lang = (string)$rc['language'];                         // Jazyk 'L' záznamu
					if (!isset($col_l_map[$orig][$lang])) {                  // První záznam pro daný jazyk
						$col_l_map[$orig][$lang] = $rc;                      // Uložení do podřízeného pole
					} else {
						foreach ($trans_col_fields as $tf) {                 // Doplnění případných NULL polí ze systémového 'L'
							if ((string)($col_l_map[$orig][$lang][$tf] ?? '') === '' AND (string)($rc[$tf] ?? '') !== '') { // Fallback
								$col_l_map[$orig][$lang][$tf] = $rc[$tf];    // Převzetí hodnoty ze systémového 'L'
							}
						}
					}
				}
			}
		}

		// 4. Vyhodnocení dědičnosti netextových vlastností a překladů sloupců v PHP
		$tech_inherited_props = [                                            // Technické vlastnosti děděné z ancestor
			'list_order', 'input_type', 'input_width', 'input_rows', 'max_length', 'css_class',
			'translate', 'history', 'is_html', 'is_mandatory', 'is_url', 'is_computed',
			'show_empty', 'hidden', 'customizable', 'referenced_codetable', 'referenced_class', 'is_protected'
		];                                                                   // Konec seznamu technických vlastností
		$str_tech_props = ['referenced_codetable', 'input_type'];            // Textové technické vlastnosti

		$list_cols_temp = [];                                                // Dočasné pole pro sloupce seznamu

		foreach ($col_a_map as $orig => $col) {                              // Průchod sloupci logické třídy
			$anc_orig = (string)($col['ancestor'] ?? '');                    // UUID předka v sys_global_columns
			$anc_row = ($anc_orig !== '' AND isset($col_anc_map[$anc_orig])) ? $col_anc_map[$anc_orig] : null; // Záznam předka

			// A) Dědění technických vlastností z předka
			if ($anc_row !== null) {                                         // Pokud má sloupec předka
				foreach ($tech_inherited_props as $prop) {                   // Průchod technickými vlastnostmi
					if ($col[$prop] === null AND isset($anc_row[$prop])) {   // Dědění při NULL
						$col[$prop] = $anc_row[$prop];                       // Převzetí hodnoty od předka
					}
					if (in_array($prop, $str_tech_props, true) AND $col[$prop] === '' AND !empty($anc_row[$prop])) { // Dědění při ''
						$col[$prop] = $anc_row[$prop];                       // Převzetí textové vlastnosti od předka
					}
				}
			}

			// B) Vyhodnocení překládaných textových vlastností (včetně dědění z předka)
			foreach ($trans_col_fields as $tf) {                             // Průchod překládanými vlastnostmi sloupce
				$col[$tf] = $this->resolve_field_from_arrays($orig, $tf, $col_a_map, $col_anc_map, $col_l_map, $curr_lang, $lang_chain, 'ancestor'); // Překlad
			}

			$this->columns_meta[$col['column_name']] = $col;                 // Uložení kompletních metadat sloupce

			if ($col['list_order'] !== null) {                               // Pokud má sloupec pořadí v Master panelu
				$header_val = $col['header'] ?: $col['caption'];             // Záhlaví sloupce v seznamu
				$list_cols_temp[(int)$col['list_order']] = [                 // Uložení sloupce pod klíčem pořadí
					'name'   => $col['column_name'],                         // Technický název sloupce
					'header' => $header_val ?: $col['column_name']           // Zobrazované záhlaví sloupce
				];                                                           // Konec položky seznamu
			}
		}

		if (!empty($list_cols_temp)) {                                       // Seřazení sloupců levého panelu dle list_order
			ksort($list_cols_temp);                                          // Seřazení podle klíče pořadí
			foreach ($list_cols_temp as $lc) {                               // Přepis do finálního pole
				$this->list_columns[$lc['name']] = $lc['header'];            // Naplnění finálního seznamu
			}
		} else {
			$fallback_candidates = ['caption', 'name', 'code', 'builtin_code']; // Kandidáti na náhradní sloupec
			foreach ($fallback_candidates as $fc) {                          // Hledání vhodného sloupce
				if (isset($this->columns_meta[$fc])) {                       // Pokud kandidát v tabulce existuje
					$col = $this->columns_meta[$fc];                         // Vybraný náhradní sloupec
					$header_val = $col['header'] ?: $col['caption'];         // Záhlaví náhradního sloupce
					$this->list_columns[$fc] = $header_val ?: $col['column_name']; // Nastavení náhradního sloupce
					break;                                                   // Ukončení hledání
				}
			}
		}

		$this->is_initialized = true;                                        // Metadata jsou plně připravena
	}

	/**
	 * Vrátí kompletní metadatový záznam celé logické třídy.
	 */
	public function get_class_meta(): array {
		return $this->class_meta;                                            // Vrácení metadat třídy
	}

	/**
	 * Vrátí metadata jednoho konkrétního sloupce.
	 */
	public function get_column_meta(string $column_name): array {            // Získání metadat vybraného sloupce
		return $this->columns_meta[$column_name] ?? [];                      // Vrácení metadat sloupce
	}

	/**
	 * Získá seznam všech definovaných sloupců entity pro iterace při generování formuláře.
	 */
	public function get_columns(): array {
		return $this->columns_meta;                                          // Vrácení všech sloupců
	}

	/**
	 * Získá asociační pole sloupců určených pro Master panel seřazených dle list_order.
	 */
	public function get_list_columns(): array {
		return $this->list_columns;                                          // Vrácení sloupců pro seznam
	}
	
	/**
	 * Umožňuje z nadřízené třídy ručně přepsat sloupce zobrazené v levém panelu.
	 */
	public function set_list_columns(array $columns): void {                 // Ruční přepsání sloupců seznamu
		$this->list_columns = $columns;                                      // Ruční nastavení sloupců seznamu
	}

	/**
	 * Načte záznamy entity pomocí rychlého dvoupolového algoritmu v PHP:
	 * 1. Jedním SQL příkazem načte záznamy 'A'/'D' (včetně případných předků 'ANC_A')
	 *    a k nim podřízené jazykové záznamy 'L' s `fallback_order < 1000` (z `dbo.f_language_list`).
	 * 2. Vytvoří hlavní pole indexované podle `original` a podřízené 2D pole `[original][language]`
	 *    seřazené podle `fallback_order`.
	 * 3. Pro každý `original` vyhodnotí jazykovou verzi v PHP bez masivních SQL JOINů.
	 *
	 * @param string $where          Volitelná WHERE podmínka (např. "m.original = ...")
	 * @param string $order_by       Volitelné řazení
	 * @param bool   $ignore_drafts  Pokud true, načte čistě schválená data ('A'/'L') bez konceptů ('D')
	 * @param bool   $show_removed   Pokud true, zahrne i záznamy s removed = 1
	 * @return array<int, array<string, mixed>> Pole výsledných řádků
	 */
	public function fetch_rows(string $where = '', string $order_by = '', bool $ignore_drafts = false, bool $show_removed = false): array { // Načtení záznamů přes 2 pole
		if (!$this->is_initialized) {                                        // Kontrola inicializace správce
			$err_title = $this->phrase('err_em_title', 'Entity manager');    // Lokalizovaný titulek chyby
			$err_msg = $this->phrase('err_meta_not_found', 'Metadata pro logickou třídu {' . chr(36) . 'class} nebyla nalezena.', ['class' => $this->class_name]); // Text chyby
			fatal_error($err_title, $err_msg);                               // Vyvolání fatální chyby
		}

		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$is_self_owned = ($table === 'organization');                        // V tabulce organization vlastní záznamy samy sebe
		$curr_lang = $this->lang_manager->get_current_language();            // Aktuální jazyk relace
		$safe_lang = charliteral($curr_lang, 2);                             // SQL literál aktuálního jazyka
		$lang_chain = $this->lang_manager->get_fallback_chain();             // Řetězec jazyků s fallback_order < 1000

		$anc_col_name = '';                                                  // Název sloupce předka (pokud v tabulce existuje)
		if (isset($this->columns_meta['ancestor'])) {                        // Tabulka meta_column
			$anc_col_name = 'ancestor';                                      // Vazba na předka sloupce
		} elseif (isset($this->columns_meta['ancestor_class'])) {            // Tabulka meta_class
			$anc_col_name = 'ancestor_class';                                // Vazba na předka třídy
		}

		$meta_columns_list = [                                               // Technické sloupce RAC a SSC
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'draft_author', 'approval_note',
			'language', 'inactive', 'removed', 'valid_from', 'valid_to', 
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified', 'import_origin'
		];                                                                   // Konec seznamu technických sloupců

		$trans_cols = [];                                                    // Seznam překládaných sloupců třídy
		$select_a_cols = [];                                                 // Sloupce pro SELECT v části 'A'
		$select_anc_cols = [];                                               // Sloupce pro SELECT v části 'ANC_A'
		$select_l_cols = [];                                                 // Sloupce pro SELECT v části 'L'

		foreach ($this->columns_meta as $colname => $meta) {                 // Sestavení projekce sloupců
			$select_anc_cols[] = "anc.[{$colname}]";                         // V 'ANC_A' bereme přímo z tabulky anc
			$select_l_cols[] = "l.[{$colname}]";                             // V 'L' bereme přímo z tabulky l

			if (in_array($colname, $meta_columns_list, true)) {              // Technický sloupec
				$select_a_cols[] = "m.[{$colname}]";                         // V 'A' bereme přímo z m
				continue;                                                    // Další sloupec
			}

			$is_trans = !empty($meta['translate']);                          // Zda je sloupec překládaný
			$is_prot = !empty($meta['is_protected']);                        // Zda je sloupec chráněný
			if ($is_trans) {                                                 // Evidujeme překládaný sloupec
				$trans_cols[] = $colname;                                    // Přidání do seznamu překládaných sloupců
			}

			if ($is_prot) {                                                  // Chráněný sloupec (vynucení systémového originálu o)
				$expr_a = "CASE WHEN m.record_type = 'D' THEN COALESCE(m.[{$colname}], o.[{$colname}]) ELSE COALESCE(o.[{$colname}], m.[{$colname}]) END AS [{$colname}]"; // Výraz
			} else {
				$expr_a = "COALESCE(m.[{$colname}], o.[{$colname}]) AS [{$colname}]"; // Fallback na systémový originál při NULL
			}
			$select_a_cols[] = $expr_a;                                      // Přidání do SELECTu 'A'
		}

		// Pojistka pro povinné řídicí sloupce, pokud by nebyly v columns_meta
		foreach (['uuid', 'original', 'record_type', 'approval_status', 'draft_author', 'approval_note', 'language', 'removed', 'date_created', 'who_created', 'date_modified', 'who_modified'] as $req_c) { // Povinné sloupce
			if (!isset($this->columns_meta[$req_c]) AND in_array($req_c, $this->physical_cols, true)) { // Pokud chybí v columns_meta
				$select_a_cols[] = "m.[{$req_c}]";                           // Přidání z m
				$select_anc_cols[] = "anc.[{$req_c}]";                       // Přidání z anc
				$select_l_cols[] = "l.[{$req_c}]";                           // Přidání z l
			}
		}

		$sel_a_str = implode(",\n\t\t\t", $select_a_cols);                   // Řetězec sloupců pro 'A'
		$sel_anc_str = implode(",\n\t\t\t", $select_anc_cols);               // Řetězec sloupců pro 'ANC_A'
		$sel_l_str = implode(",\n\t\t\t", $select_l_cols);                   // Řetězec sloupců pro 'L'

		$has_draft_author_col = in_array('draft_author', $this->physical_cols, true); // Zda tabulka podporuje koncepty
		$rem_filter = $show_removed ? "" : "WHERE rc.removed = 0";           // Filtr platných záznamů
		$sy_where = $show_removed ? "WHERE my.original IS NULL" : "WHERE sy.removed = 0 AND my.original IS NULL"; // Filtr sy vs my

		$my_owner_cond = $is_self_owned
			? "(rc.object_owner = s.organization_uuid OR (s.organization_uuid = 0x00 AND rc.object_owner = rc.original))"
			: "rc.object_owner = s.organization_uuid AND rc.object_owner <> 0x00"; // Podmínka vlastníka pro my

		$dr_owner_cond = $is_self_owned
			? "(rc.object_owner = s.organization_uuid OR (s.organization_uuid = 0x00 AND rc.object_owner = rc.original))"
			: "rc.object_owner = s.organization_uuid";                       // Podmínka vlastníka pro koncepty dr

		$sy_cte = "
		sy_raw AS (
			SELECT rc.*, CAST(0 AS BIT) AS object_is_mine,
				ROW_NUMBER() OVER (PARTITION BY rc.original ORDER BY rc.removed ASC, rc.date_modified DESC) AS rn_rec
			FROM s JOIN {$table} rc ON rc.object_owner = 0x00 AND rc.record_type = 'A' {$rem_filter}
		),
		sy AS (SELECT * FROM sy_raw WHERE rn_rec = 1),
		my_raw AS (
			SELECT rc.*, CAST(1 AS BIT) AS object_is_mine,
				ROW_NUMBER() OVER (PARTITION BY rc.original ORDER BY rc.removed ASC, rc.date_modified DESC) AS rn_rec
			FROM s JOIN {$table} rc ON {$my_owner_cond} AND rc.record_type = 'A' {$rem_filter}
		),
		my AS (SELECT * FROM my_raw WHERE rn_rec = 1)";                      // Společné CTE pro systémové a vlastní záznamy

		if (!$ignore_drafts AND $has_draft_author_col) {                     // Režim se zahrnutím konceptů ('D')
			$mix_cte = "
		{$sy_cte},
		dr AS (
			SELECT rc.*, CAST(1 AS BIT) AS object_is_mine, CAST(1 AS BIGINT) AS rn_rec
			FROM s JOIN {$table} rc ON {$dr_owner_cond} AND rc.record_type = 'D'
			WHERE rc.[language] = s.sess_lang
			  AND (rc.draft_author = s.user_account OR (rc.draft_author = 0x00 AND rc.approval_status = 'R'))
		),
		base_mix AS (
			SELECT sy.* FROM sy LEFT JOIN my ON my.original = sy.original {$sy_where}
			UNION ALL
			SELECT * FROM my
		),
		mix_all AS (
			SELECT bm.* FROM base_mix bm LEFT JOIN dr ON dr.original = bm.original WHERE dr.original IS NULL
			UNION ALL
			SELECT * FROM dr
		)";                                                                  // CTE mix_all s koncepty (včetně návrhů s removed = 1)
		} else {
			$mix_cte = "
		{$sy_cte},
		mix_all AS (
			SELECT sy.* FROM sy LEFT JOIN my ON my.original = sy.original {$sy_where}
			UNION ALL
			SELECT * FROM my
		)";                                                                  // CTE mix_all bez konceptů
		}

		$where_clause = ($where !== '') ? "WHERE {$where}" : "";             // Volitelná podmínka WHERE nad m

		// Sestavení UNION ALL částí pro předky ('ANC_A') a překlady ('L' s fallback_order < 1000)
		$anc_union_sql = "";                                                 // SQL větev pro načtení předků
		$l_join_anc_sql = "";                                                // SQL podmínka pro 'L' záznamy předků
		if ($anc_col_name !== '') {                                          // Pokud tabulka podporuje dědičnost z předka
			$anc_union_sql = "
		UNION ALL

		SELECT
			2 AS kind_order,
			'ANC_A' AS row_kind,
			0 AS is_tenant_l,
			0 AS fallback_order,
			CAST(0 AS BIT) AS object_is_mine,
			anc.[language] AS native_language,
			'' AS who_created_info,
			'' AS who_modified_info,
			{$sel_anc_str}
		FROM {$table} anc
		WHERE anc.object_owner = 0x00
		  AND anc.record_type = 'A'
		  AND anc.removed = 0
		  AND anc.original IN (SELECT DISTINCT [{$anc_col_name}] FROM mix WHERE [{$anc_col_name}] IS NOT NULL)"; // Načtení předků
			$l_join_anc_sql = "OR l.original IN (SELECT DISTINCT [{$anc_col_name}] FROM mix WHERE [{$anc_col_name}] IS NOT NULL)"; // Překlady předků
		}

		$l_union_sql = "";                                                   // SQL větev pro načtení 'L' záznamů
		if (!empty($trans_cols)) {                                           // Pouze pokud má třída překládané sloupce
			$l_owner_cond = $is_self_owned
				? "(l.object_owner = 0x00 OR l.object_owner = l.original OR l.object_owner = s.organization_uuid)"
				: "(l.object_owner = 0x00 OR l.object_owner = s.organization_uuid)"; // Vlastník L záznamu
			$l_rem_cond = $show_removed ? "" : "AND l.removed = 0";          // Filtr zrušených L záznamů

			$l_union_sql = "
		UNION ALL

		SELECT
			3 AS kind_order,
			'L' AS row_kind,
			CASE WHEN l.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant_l,
			fl.fallback_order,
			CAST(0 AS BIT) AS object_is_mine,
			l.[language] AS native_language,
			'' AS who_created_info,
			dbo.f_get_user_info(l.who_modified) AS who_modified_info,
			{$sel_l_str}
		FROM s
		CROSS JOIN {$table} l
		JOIN fl ON fl.[language] = l.[language]
		LEFT JOIN mix m ON m.original = l.original
		WHERE l.record_type = 'L'
		  {$l_rem_cond}
		  AND {$l_owner_cond}
		  AND (m.original IS NOT NULL {$l_join_anc_sql})";                   // Načtení 'L' záznamů s fallback_order < 1000
		}

		$sql = "
		WITH s AS (
			SELECT
				ISNULL((SELECT TOP 1 organization FROM dbsession WHERE spid = @@SPID), 0x00) AS organization_uuid,
				ISNULL((SELECT TOP 1 user_account FROM dbsession WHERE spid = @@SPID), 0x00) AS user_account,
				ISNULL((SELECT TOP 1 [language] FROM dbsession WHERE spid = @@SPID), {$safe_lang}) AS sess_lang
		),
		fl AS (
			SELECT [language], fallback_order
			FROM dbo.f_language_list({$safe_lang})
			WHERE fallback_order < 1000
		),
		{$mix_cte},
		mix AS (
			SELECT m.*
			FROM mix_all m
			{$where_clause}
		)
		SELECT
			1 AS kind_order,
			'A' AS row_kind,
			0 AS is_tenant_l,
			0 AS fallback_order,
			m.object_is_mine,
			COALESCE(my_base.[language], o.[language], m.[language]) AS native_language,
			dbo.f_get_user_info(m.who_created) AS who_created_info,
			dbo.f_get_user_info(m.who_modified) AS who_modified_info,
			{$sel_a_str}
		FROM mix m
		LEFT JOIN sy o ON o.original = m.original
		LEFT JOIN my my_base ON my_base.original = m.original
		{$anc_union_sql}
		{$l_union_sql}
		ORDER BY kind_order ASC, fallback_order ASC, is_tenant_l DESC, removed ASC
		";                                                                   // Kompletní sjednocený dotaz bez násobných JOINů

		$raw_rows = sqlarray_simple($sql);                                   // Načtení všech dat jedním dotazem
		if (!is_array($raw_rows) OR empty($raw_rows)) {                      // Pokud dotaz nevrátil žádné záznamy
			return [];                                                       // Vrácení prázdného pole
		}

		// 1. Rozdělení načtených dat na dvě pole: $a_rows (podle original) a $l_rows ([original][language])
		$a_rows = [];                                                        // První pole s indexem 'original' (záznamy 'A'/'D')
		$anc_a_rows = [];                                                    // Pomocné pole předků 'A'
		$l_rows = [];                                                        // Druhé 2D pole podřízené originálu s indexem jazyka

		foreach ($raw_rows as $r) {                                          // Průchod načtenými řádky
			$orig = (string)$r['original'];                                  // UUID originálu
			$kind = (string)$r['row_kind'];                                  // Typ řádku ('A', 'ANC_A', 'L')
			if ($kind === 'A') {                                             // Hlavní záznam
				$r['l_removed'] = (($r['record_type'] ?? 'A') === 'D' AND !empty($r['removed'])) ? 1 : 0; // Výchozí stav zrušení překladu (vč. konceptu D)
				$a_rows[$orig] = $r;                                         // Uložení do prvního pole pod klíčem original
			} elseif ($kind === 'ANC_A') {                                   // Záznam předka
				$anc_a_rows[$orig] = $r;                                     // Uložení předka
			} else {
				$lang = (string)$r['language'];                              // Kód jazyka 'L' záznamu
				if (!isset($l_rows[$orig][$lang])) {                         // První záznam pro daný jazyk (díky ORDER BY má přednost tenant a removed=0)
					$l_rows[$orig][$lang] = $r;                              // Uložení do 2D podřízeného pole
				} else {
					foreach ($trans_cols as $tc) {                           // Doplnění případných prázdných hodnot ze systémového 'L'
						if ((string)($l_rows[$orig][$lang][$tc] ?? '') === '' AND (string)($r[$tc] ?? '') !== '') { // Fallback
							$l_rows[$orig][$lang][$tc] = $r[$tc];            // Převzetí hodnoty ze systémového 'L'
						}
					}
				}
			}
		}

		// 2. Vyhodnocení překladů, dědičnosti z předka a nejnovějšího data úpravy pro každý 'original'
		foreach ($a_rows as $orig => &$a_row) {                              // Průchod hlavním polem záznamů
			// A) Aktualizace l_removed a nejnovějšího data modifikace z podřízených 'L' záznamů
			if (isset($l_rows[$orig])) {                                     // Pokud k záznamu existují 'L' mutace
				if (($a_row['record_type'] ?? 'A') !== 'D' AND isset($l_rows[$orig][$curr_lang])) { // U schváleného záznamu bereme l_removed z L
					$a_row['l_removed'] = !empty($l_rows[$orig][$curr_lang]['removed']) ? 1 : 0; // Příznak zrušení L mutace
				}
				if (($a_row['record_type'] ?? 'A') !== 'D') {                // U schválených záznamů zohledníme i změny v 'L'
					foreach ($l_rows[$orig] as $l_item) {                    // Průchod podřízenými 'L' záznamy
						$l_mod = (string)($l_item['date_modified'] ?? '');   // Datum změny 'L' záznamu
						$a_mod = (string)($a_row['date_modified'] ?? '');    // Datum změny 'A' záznamu
						if ($l_mod !== '' AND $l_mod > $a_mod) {             // Pokud je 'L' záznam novější než 'A'
							$a_row['date_modified'] = $l_mod;                // Převzetí novějšího data úpravy
							$a_row['who_modified'] = $l_item['who_modified']; // Převzetí autora úpravy
							$a_row['who_modified_info'] = $l_item['who_modified_info']; // Převzetí jména autora
						}
					}
				}
			}

			// B) Dědění netextových NULL vlastností od předka (pokud má záznam předka)
			if ($anc_col_name !== '') {                                      // Pokud tabulka podporuje předka
				$anc_id = (string)($a_row[$anc_col_name] ?? '');             // UUID předka
				$anc_rec = ($anc_id !== '') ? ($anc_a_rows[$anc_id] ?? $a_rows[$anc_id] ?? null) : null; // Záznam předka
				if ($anc_rec !== null) {                                     // Pokud byl předek nalezen
					foreach ($this->columns_meta as $cn => $cm) {            // Průchod sloupci
						if (empty($cm['translate']) AND !in_array($cn, $meta_columns_list, true)) { // Nepřekládané byznys sloupce
							if ($a_row[$cn] === null AND isset($anc_rec[$cn])) { // Dědění při NULL
								$a_row[$cn] = $anc_rec[$cn];                 // Převzetí hodnoty od předka
							}
						}
					}
				}
			}

			// C) Vyhodnocení všech překládaných sloupců
			foreach ($trans_cols as $tc) {                                   // Průchod překládanými sloupci
				$a_row[$tc] = $this->resolve_field_from_arrays($orig, $tc, $a_rows, $anc_a_rows, $l_rows, $curr_lang, $lang_chain, $anc_col_name ?: 'ancestor'); // Překlad
			}
		}
		unset($a_row);                                                       // Uvolnění reference po smyčce

		$result = array_values($a_rows);                                     // Převod asociativního pole na indexované pole

		// 3. Seřazení výsledného pole podle $order_by nebo podle sloupců Master panelu ($this->list_columns)
		$sort_cols = [];                                                     // Pole sloupců pro řazení: [sloupec => 'ASC'|'DESC']
		if ($order_by !== '') {                                              // Pokud bylo zadáno explicitní řazení
			foreach (explode(',', $order_by) as $ob_part) {                  // Rozpad klauzule ORDER BY
				$ob_clean = trim(str_replace(['[', ']', 'm.'], '', $ob_part)); // Očištění názvu sloupce
				if ($ob_clean !== '') {                                      // Pokud část není prázdná
					$tokens = preg_split('/\s+/', $ob_clean);               // Rozdělení na název a směr
					$sc_name = (string)($tokens[0] ?? '');                   // Název sloupce
					$sc_dir = strtoupper((string)($tokens[1] ?? 'ASC'));     // Směr řazení
					if ($sc_name !== '') {                                   // Zařazení sloupce do řazení
						$sort_cols[$sc_name] = ($sc_dir === 'DESC') ? 'DESC' : 'ASC'; // Uložení směru
					}
				}
			}
		} else {
			foreach (array_keys($this->list_columns) as $lc_name) {          // Výchozí řazení podle sloupců seznamu
				$sort_cols[$lc_name] = 'ASC';                                // Vzestupné řazení
			}
		}

		if (!empty($sort_cols) AND count($result) > 1) {                     // Seřazení výsledků v PHP
			usort($result, function(array $x, array $y) use ($sort_cols): int { // Porovnávací funkce řazení
				foreach ($sort_cols as $sc => $dir) {                        // Průchod řadicími sloupci
					$vx = (string)($x[$sc] ?? '');                           // Hodnota prvního řádku
					$vy = (string)($y[$sc] ?? '');                           // Hodnota druhého řádku
					$cmp = strnatcasecmp($vx, $vy);                          // Přirozené porovnání řetězců bez ohledu na velikost písmen
					if ($cmp !== 0) {                                        // Pokud se hodnoty liší
						return ($dir === 'DESC') ? -$cmp : $cmp;             // Vrácení výsledku dle směru ASC/DESC
					}
				}
				return 0;                                                    // Shoda ve všech řadicích sloupcích
			});
		}

		return $result;                                                      // Vrácení seřazeného pole záznamů
	}

	/**
	 * Zpětně kompatibilní alias pro metodu fetch_rows().
	 */
	public function fetch_records(string $where = '', string $order_by = '', bool $ignore_drafts = false, bool $show_removed = false): array { // Alias pro fetch_rows
		return $this->fetch_rows($where, $order_by, $ignore_drafts, $show_removed); // Delegování na fetch_rows
	}

	/**
	 * Načte jeden konkrétní záznam pomocí dvoupolového vyhodnocení v PHP.
	 *
	 * @param string $where         Podmínka WHERE (např. "m.original = ...")
	 * @param bool   $ignore_drafts Pokud true, ignoruje koncepty ('D')
	 * @param bool   $show_removed  Pokud true, zahrne i záznamy s removed = 1
	 * @return array<string, mixed> Asociativní pole záznamu nebo prázdné pole []
	 */
	public function fetch_row(string $where = '', bool $ignore_drafts = false, bool $show_removed = false): array { // Načtení jednoho záznamu
		$rows = $this->fetch_rows($where, '', $ignore_drafts, $show_removed); // Načtení záznamů přes fetch_rows
		return $rows[0] ?? [];                                               // Vrácení prvního záznamu nebo prázdného pole
	}

	/**
	 * Vyhodnotí, zda má přihlášený uživatel právo označit daný záznam (nebo jeho jazykovou mutaci)
	 * jako zrušený (`removed = 1`) či jej obnovit (`removed = 0`), a vrátí případný důvod uzamčení.
	 *
	 * @param array $datarow Načtený datový řádek detailu
	 * @param bool  $is_mine Zda záznam vlastní aktuální tenant
	 * @return array{allowed: bool, is_lang_only: bool, reason: string}
	 */
	public function evaluate_remove_permission(array $datarow, bool $is_mine): array { // Vyhodnocení oprávnění pro removed
		global $dbsession;                                                   // Globální kontext relace
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role uživatele (U, A, S, D)
		$org_uuid_raw = (string)($dbsession['organization'] ?? '0x00');      // UUID aktivní organizace
		$sess_lang_raw = (string)($dbsession['language'] ?? 'cs');           // Jazyk aktivní relace
		$right_translate = !empty($dbsession['right_translate']);            // Oprávnění ke globálnímu překladu

		$is_sysadmin_org = ($org_uuid_raw === '0x00' OR $org_uuid_raw === '00000000-0000-0000-0000-000000000000'); // Zda je v 0x00
		$rec_lang = (string)($datarow['native_language'] ?? $datarow['language'] ?? 'cs'); // Mateřský jazyk 'A' záznamu
		$is_native_lang = ($rec_lang === $sess_lang_raw);                    // Zda uživatel pracuje v mateřském jazyce záznamu

		// 1. Práce v sekundárním jazyce (jazyková mutace 'L')
		if (!$is_native_lang) {                                              // Pokud jde o sekundární jazyk
			if ($is_sysadmin_org OR $right_translate OR $is_mine) {          // Oprávněný překladatel nebo vlastník
				$note_l = $this->phrase('msg_remove_lang_mutation_only', 'Ruší pouze jazykovou mutaci ({' . chr(36) . 'lang})', ['lang' => $sess_lang_raw]); // Poznámka k rušení L
				return ['allowed' => true, 'is_lang_only' => true, 'reason' => $note_l]; // Povoleno zrušení překladu L
			}
			$deny_l = $this->phrase('msg_remove_lang_denied', 'Nemáte oprávnění rušit systémové překlady tohoto jazyka'); // Důvod zákazu
			return ['allowed' => false, 'is_lang_only' => true, 'reason' => $deny_l]; // Zákaz rušení cizího překladu
		}

		// 2. Práce v primárním jazyce u systémové organizace (0x00)
		if ($is_sysadmin_org) {                                              // Systémová organizace 0x00
			if ($this->storage_table === 'organization') {                   // Speciální ochrana pro tabulku organization
				$orig_val = (string)($datarow['original'] ?? '');            // UUID originálu organizace
				if ($orig_val === '0x00' OR $orig_val === '00000000-0000-0000-0000-000000000000') { // Systémová organizace 0x00
					$deny_sys_org = $this->phrase('msg_remove_sys_org_denied', 'Systémovou master organizaci (0x00) nelze zrušit'); // Důvod
					return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_sys_org]; // Uzamčeno
				}
			}

			if ($this->is_metadata_entity() AND $active_role !== 'D') {      // Metadata smí rušit jen Developer ('D')
				$deny_d = $this->phrase('msg_remove_meta_only_dev', 'Systémová metadata smí rušit pouze vývojář (Developer)'); // Důvod pro roli
				return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_d]; // Uzamčeno mimo roli D
			}

			if ($this->storage_table === 'meta_object') {                    // Kontrola tabulky meta_object
				$obj_type = (string)($datarow['object_type'] ?? '');         // Typ objektu (T, V, F, P, C, M)
				$b_code = (string)($datarow['builtin_code'] ?? '');          // Kód objektu
				if ($obj_type !== 'P' OR $b_code === 'global_phrase') {      // Fyzické objekty a global_phrase nelze rušit
					$deny_mo = $this->phrase('msg_remove_phys_object_denied', 'Fyzický databázový objekt ani kontejner global_phrase nelze v metadatech zrušit'); // Důvod
					return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_mo]; // Uzamčeno
				}
			} elseif ($this->storage_table === 'meta_class') {               // Kontrola tabulky meta_class
				$cls_name = (string)($datarow['class_name'] ?? '');          // Název logické třídy
				$stg_orig = guidliteral((string)($datarow['storage_object'] ?? '')); // UUID úložného objektu
				if ($cls_name === 'sys_global_columns') {                    // Kořenový slovník sloupců nelze zrušit
					$deny_gc = $this->phrase('msg_remove_global_cls_denied', 'Systémový kontejner sys_global_columns nelze zrušit'); // Důvod
					return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_gc]; // Uzamčeno
				}
				if ($stg_orig !== 'NULL') {                                  // Ověření, zda nejde o primitivní třídu žijící tabulky
					$stg_row = sqlfirstrow("
						SELECT mo.builtin_code
						FROM meta_object mo
						JOIN v_syscolumns vc ON vc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
						WHERE mo.original = {$stg_orig} AND mo.object_owner = 0x00 AND mo.record_type = 'A' AND mo.removed = 0
					");                                                      // Kontrola existence fyzické tabulky ve v_syscolumns
					if (!empty($stg_row) AND (string)$stg_row['builtin_code'] === $cls_name) { // Primitivní třída existující tabulky
						$deny_pc = $this->phrase('msg_remove_prim_class_denied', 'Primitivní třídu svázanou s existující fyzickou tabulkou nelze zrušit'); // Důvod
						return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_pc]; // Uzamčeno
					}
				}
			} elseif ($this->storage_table === 'meta_column') {              // Kontrola tabulky meta_column
				$col_name = (string)($datarow['column_name'] ?? '');         // Název sloupce
				$par_cls = guidliteral((string)($datarow['parent_class'] ?? '')); // UUID nadřízené třídy
				if ($par_cls !== 'NULL' AND $col_name !== '') {              // Ověření fyzické existence sloupce v DB
					$safe_col = charliteral($col_name, 80);                  // SQL literál názvu sloupce
					$phys_row = sqlfirstrow("
						SELECT 1 AS is_phys
						FROM meta_class mc
						JOIN meta_object mo ON mo.original = mc.storage_object AND mo.object_owner = 0x00 AND mo.record_type = 'A' AND mo.removed = 0
						JOIN v_syscolumns vc ON vc.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT AND vc.colname = {$safe_col}
						WHERE mc.original = {$par_cls} AND mc.object_owner = 0x00 AND mc.record_type = 'A' AND mc.removed = 0
						  AND mc.class_name = mo.builtin_code
					");                                                      // Kontrola existence sloupce v primitivní třídě
					if (!empty($phys_row)) {                                 // Sloupec fyzicky existuje v databázi
						$deny_col = $this->phrase('msg_remove_phys_col_denied', 'Fyzicky existující sloupec databázové tabulky nelze v metadatech zrušit'); // Důvod
						return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_col]; // Uzamčeno
					}
				}
			}

			return ['allowed' => true, 'is_lang_only' => false, 'reason' => '']; // Povoleno zrušení/obnovení záznamu
		}

		// 3. Práce v běžném klientském tenantovi (object_owner <> 0x00)
		if ($is_mine) {                                                      // Vlastní záznam nebo tenant override
			return ['allowed' => true, 'is_lang_only' => false, 'reason' => '']; // Tenant smí zrušit svůj vlastní záznam
		}

		$deny_sys = $this->phrase('msg_remove_system_record_denied', 'Systémový záznam nelze v organizaci smazat (použijte příznak Neaktivní)'); // Vysvětlení pro tenanta
		return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_sys]; // Systémový záznam tenant nemůže smazat
	}

	/**
	 * Vykreslí samostatnou tabulku s checkboxem `removed` na konci detailního formuláře
	 * včetně JS potvrzení `confirm(...)` při zaškrtnutí a informace o oprávnění.
	 *
	 * @param array $datarow        Načtený datový řádek detailu
	 * @param bool  $is_mine        Příznak vlastnictví záznamu
	 * @param bool  $force_readonly Příznak readonly režimu panelu
	 * @return string HTML kód sekce pro zrušení / obnovení záznamu
	 */
	public function render_removed_section(array $datarow, bool $is_mine, bool $force_readonly = false): string { // Vykreslení sekce removed
		$perm = $this->evaluate_remove_permission($datarow, $is_mine);       // Vyhodnocení oprávnění ke zrušení záznamu
		$can_remove = (!$force_readonly AND $perm['allowed']);               // Zda je checkbox aktivní pro editaci
		$is_lang_only = $perm['is_lang_only'];                               // Zda se ruší pouze jazyková mutace 'L'
		$reason_note = $perm['reason'];                                      // Doplňková poznámka nebo důvod uzamčení

		$rem_val = $is_lang_only
			? (!empty($datarow['l_removed']) ? '1' : '0')                    // Hodnota removed pro jazykovou mutaci 'L'
			: (!empty($datarow['removed']) ? '1' : '0');                     // Hodnota removed pro hlavní záznam 'A'

		$checked = ($rem_val === '1') ? 'checked' : '';                      // Atribut checked
		$row_bg = ($rem_val === '1') ? 'background-color: #fef2f2;' : '';    // Červené podbarvení při aktivním zrušení
		$lbl_rem = htmlspecialchars($this->phrase('lbl_record_removed', 'Zrušený záznam (removed)')); // Popisek pole removed
		$confirm_msg = addslashes($this->phrase('confirm_mark_removed', 'Potvrďte, že chcete tuto položku označit jako zrušenou.')); // Text JS confirm

		$note_html = ($reason_note !== '')
			? "<span style=\"margin-left: 10px; font-size: 12px; color: #64748b; font-style: italic;\">(" . htmlspecialchars($reason_note) . ")</span>"
			: "";                                                            // HTML poznámky vedle checkboxu

		if (!$can_remove) {                                                  // Vykreslení uzamčeného checkboxu removed
			return <<<HTML
				<table class="md-table" style="margin-bottom: 20px;">
					<tr style="{$row_bg}">
						<td style="width: 30%;"><strong>{$lbl_rem}:</strong></td>
						<td>
							<input type="hidden" name="removed" value="{$rem_val}">
							<input type="checkbox" value="1" {$checked} disabled style="width: auto;">
							{$note_html}
						</td>
					</tr>
				</table>
HTML;
		}

		// Aktivní checkbox s JS potvrzením při přechodu z 0 na 1
		$js_onclick = ($rem_val === '0')
			? "onclick=\"if (this.checked) { if (!confirm('{$confirm_msg}')) { this.checked = false; } }\""
			: "";                                                            // Potvrzení vyžadujeme pouze při rušení platného záznamu

		return <<<HTML
				<table class="md-table" style="margin-bottom: 20px;">
					<tr style="{$row_bg}">
						<td style="width: 30%;"><strong>{$lbl_rem}:</strong></td>
						<td>
							<input type="hidden" name="removed" value="0">
							<input type="checkbox" name="removed" value="1" {$checked} {$js_onclick} style="width: auto; cursor: pointer;">
							{$note_html}
						</td>
					</tr>
				</table>
HTML;
	}

	/**
	 * Dynamický HTML generátor formulářových prvků na základě metadat v DB.
	 * Zajišťuje vizuální vykreslení datových typů, maximálních délek a zamykání polí.
	 * 
	 * @param string $column_name    Název sloupce (klíč v databázi, např. 'caption')
	 * @param string $value          Aktuální hodnota k zobrazení
	 * @param bool   $is_mine        Příznak, zda tenant vytvořil pro tento záznam svůj vlastní 'A' override
	 * @param bool   $force_readonly Vynucení režimu pouze pro čtení z nadřazeného panelu
	 * @return string Vygenerovaný HTML string (např. tag <input> nebo <select>)
	 */
	public function render_dynamic_input(string $column_name, string $value, bool $is_mine = true, bool $force_readonly = false): string { // Vykreslení formulářového prvku
		$meta = $this->get_column_meta($column_name);                        // Načtení metadat sloupce
		
		if (empty($meta)) {                                                  // Kontrola existence metadat sloupce
			return "<!-- Neznámý sloupec: {$column_name} -->";               // HTML komentář pro neznámý sloupec
		}

		// Speciální ošetření pro vektorové ikony (svg_icon):
		if ($column_name === 'svg_icon') {                                   // Kontrola sloupce vektorové ikony
			$trimmed_svg = trim($value);                                     // Očištěný SVG řetězec
			$note_svg = htmlspecialchars($this->phrase('msg_svg_readonly_note', 'Nastavuje se pouze databázovým skriptem')); // Informační poznámka
			if ($trimmed_svg !== '' AND str_starts_with($trimmed_svg, '<svg')) { // Pokud obsahuje platnou značku <svg
				return "<div style=\"display: inline-flex; align-items: center; gap: 10px; padding: 6px 10px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px;\">"
					. "<span style=\"display: inline-flex; width: 24px; height: 24px; color: #004488;\">{$trimmed_svg}</span>"
					. "<span style=\"font-size: 12px; color: #64748b; font-style: italic;\">({$note_svg})</span>"
					. "</div>";                                              // Neredigovatelný vizuální náhled SVG ikony
			}
			$lbl_no_svg = htmlspecialchars($this->phrase('lbl_no_svg_icon', 'Ikona není nastavena')); // Popisek prázdné ikony
			return "<div style=\"padding: 6px 10px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 4px; font-size: 12px; color: #64748b; font-style: italic;\">{$lbl_no_svg} ({$note_svg})</div>"; // Box bez ikony
		}

		global $dbsession;                                                   // Globální kontext relace
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role uživatele v relaci
		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace
		$safe_lang = charliteral($this->lang_manager->get_current_language(), 2); // SQL literál aktivního jazyka

		$type = $meta['input_type'] ?: 'text';                               // Výchozí typ prvku je text
		$safe_name = htmlspecialchars($column_name);                         // Ošetřený název prvku
		$safe_val = htmlspecialchars($value);                                // Ošetřená hodnota prvku
		
		$attrs = [];                                                         // Pole HTML atributů
		if (!empty($meta['css_class'])) {                                    // Pokud má sloupec CSS třídu
			$attrs[] = "class=\"" . htmlspecialchars((string)$meta['css_class']) . "\""; // Atribut class
		}
		if (!empty($meta['placeholder'])) {                                  // Pokud má sloupec placeholder
			$attrs[] = "placeholder=\"" . htmlspecialchars((string)$meta['placeholder']) . "\""; // Atribut placeholder
		}
		if (!empty($meta['max_length'])) {                                   // Pokud má sloupec omezení délky
			$attrs[] = "maxlength=\"{$meta['max_length']}\"";                // Atribut maxlength
		}
		if (!empty($meta['is_mandatory'])) {                                 // Pokud je sloupec povinný
			$attrs[] = "required";                                           // HTML5 atribut required
		}
		
		$is_readonly = $force_readonly;                                      // Výchozí stav uzamčení dle panelu
		
		if (!empty($meta['is_computed'])) {                                  // Kontrola vypočítávaného sloupce
			$is_readonly = true;                                             // Vypočítávaný sloupec nelze měnit
		} elseif ($this->is_metadata_entity() AND $active_role !== 'D' AND empty($meta['translate'])) { // Ochrana metadat mimo roli D
			$is_readonly = true;                                             // Uzamčení funkčního atributu metadat
		} elseif (!$is_mine AND !empty($meta['is_protected']) AND empty($meta['translate'])) { // Ochrana chráněných sloupců
			$is_readonly = true;                                             // Chráněný systémový sloupec
		} 
		
		$input_width = $meta['input_width'] ?: '100%';                       // Šířka vstupního pole
		
		if ($is_readonly) {                                                  // Nastavení atributů pro zamčené pole
			$attrs[] = "readonly style=\"background-color: #f4f4f4; width: {$input_width};\""; // Vizuální odlišení readonly
			if ($type === 'checkbox') {                                      // Speciální ošetření pro checkbox
				$attrs[] = "disabled";                                       // Deaktivace checkboxu
			}
		} else {
			$attrs[] = "style=\"width: {$input_width};\"";                   // Standardní šířka aktivního prvku
		}

		$attr_string = implode(' ', $attrs);                                 // Spojení atributů do řetězce
		$lbl_select = htmlspecialchars($this->phrase('opt_select_default', '--- Vyberte ---')); // Výchozí volba roletky

		// 1. Speciální podpora pro sloupec licence_level (roletka z tabulky licence_level)
		if ($column_name === 'licence_level') {                              // Roletka pro úroveň licence
			$options_html = '';                                              // HTML voleb úrovní licence
			$lvl_rows = sqlarray_simple("SELECT licence_level, name FROM licence_level ORDER BY licence_level"); // Načtení úrovní
			if (is_array($lvl_rows)) {                                       // Kontrola platného pole úrovní
				foreach ($lvl_rows as $l_row) {                              // Průchod úrovněmi licencí
					$l_code = (string)$l_row['licence_level'];               // Číselný kód úrovně licence
					$l_name = (string)$l_row['name'];                        // Název úrovně licence
					$sel = ($l_code === $value) ? 'selected' : '';           // Označení vybrané úrovně
					$options_html .= "<option value=\"" . htmlspecialchars($l_code) . "\" {$sel}>" . htmlspecialchars("{$l_name} ({$l_code})") . "</option>"; // Položka roletky
				}
			}
			$lvl_style = $is_readonly ? "disabled style=\"background-color: #f4f4f4; width: 220px; padding: 6px;\"" : "style=\"width: 220px; padding: 6px;\""; // Styl roletky
			if ($is_readonly) {                                              // Zamčená roletka úrovně licence
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_val}\"><select {$lvl_style}>{$options_html}</select>"; // Zamčený select
			}
			return "<select name=\"{$safe_name}\" {$lvl_style}>{$options_html}</select>"; // Aktivní select úrovně licence
		}

		// 2. Speciální podpora pro sloupec source_code v tabulce meta_phrase (výběr PHP třídy/stránky z meta_object)
		if ($this->storage_table === 'meta_phrase' AND $column_name === 'source_code') { // Roletka pro source_code
			$eff_value = ($value === '') ? 'global_phrase' : $value;         // Prázdný source_code mapujeme na global_phrase
			$safe_eff_val = htmlspecialchars($eff_value);                    // Ošetřená hodnota pro hidden pole
			$lbl_global = htmlspecialchars($this->phrase('opt_global_phrase_source', 'global_phrase (Globální fráze systému)')); // Popisek globální fráze
			$sel_global = ($eff_value === 'global_phrase') ? 'selected' : ''; // Označení globální fráze
			$options_html = "<option value=\"global_phrase\" {$sel_global}>{$lbl_global}</option>"; // Výchozí volba global_phrase

			$src_rows = sqlarray_simple("
				WITH fl AS (
					SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
				)
				SELECT a.builtin_code, COALESCE(tr.caption, a.caption, '') AS caption
				FROM meta_object a
				OUTER APPLY (
					SELECT TOP 1 l.caption
					FROM meta_object l
					JOIN fl ON fl.[language] = l.[language]
					WHERE l.original = a.original
					  AND l.record_type = 'L'
					  AND l.removed = 0
					  AND l.object_owner IN ({$org_sql}, 0x00)
					  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
					ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
				) tr
				WHERE a.object_type = 'P'
				  AND a.builtin_code <> ''
				  AND a.builtin_code <> 'global_phrase'
				  AND a.object_owner = 0x00
				  AND a.record_type = 'A'
				  AND a.removed = 0
				ORDER BY a.builtin_code
			");                                                              // Načtení lokalizovaných PHP tříd mimo global_phrase
			if (is_array($src_rows)) {                                       // Kontrola platného pole výsledků
				foreach ($src_rows as $r_src) {                              // Průchod registrovanými PHP třídami
					$b_code = (string)$r_src['builtin_code'];                // Název PHP třídy
					$b_cap = (string)$r_src['caption'];                      // Přeložený popisek třídy
					$sel = ($b_code === $eff_value) ? 'selected' : '';       // Shoda s aktuální hodnotou
					$opt_label = ($b_cap !== '' AND $b_cap !== $b_code) ? "{$b_code} ({$b_cap})" : $b_code; // Popisek volby
					$options_html .= "<option value=\"" . htmlspecialchars($b_code) . "\" {$sel}>" . htmlspecialchars($opt_label) . "</option>"; // Položka roletky
				}
			}

			if ($is_readonly) {                                              // Vykreslení zamčené roletky source_code
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_eff_val}\"><select disabled {$attr_string}>{$options_html}</select>"; // Zamčený select
			}
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>"; // Aktivní select
		}

		// 3. Generování <select> seznamů pro číselníky napojené v metadatech (referenced_codetable) s překlady dle f_language_list
		if (!empty($meta['referenced_codetable'])) {                         // Pokud je sloupec napojen na číselník
			$options_html = "<option value=\"\">{$lbl_select}</option>";     // Prázdná výchozí volba číselníku
			$safe_ct = charliteral($meta['referenced_codetable']);           // Bezpečný literál číselníku
			$opt_rows = sqlarray_simple("
				WITH fl AS (
					SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
				),
				ranked_ct AS (
					SELECT original, value_code, caption, sort_code,
						ROW_NUMBER() OVER (PARTITION BY value_code ORDER BY CASE WHEN object_owner = {$org_sql} THEN 0 ELSE 1 END) AS rn
					FROM meta_codetable
					WHERE codetable_name = {$safe_ct}
					  AND object_owner IN ({$org_sql}, 0x00)
					  AND record_type = 'A'
					  AND removed = 0
					  AND inactive = 0
				)
				SELECT c.value_code, COALESCE(tr.caption, c.caption, c.value_code) AS caption
				FROM ranked_ct c
				OUTER APPLY (
					SELECT TOP 1 l.caption
					FROM meta_codetable l
					JOIN fl ON fl.[language] = l.[language]
					WHERE l.original = c.original
					  AND l.record_type = 'L'
					  AND l.removed = 0
					  AND l.object_owner IN ({$org_sql}, 0x00)
					  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
					ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
				) tr
				WHERE c.rn = 1
				ORDER BY c.sort_code, caption
			");                                                              // Dotaz na položky číselníku s překladem a izolací tenanta
			
			if (is_array($opt_rows)) {                                       // Kontrola platného pole položek číselníku
				foreach ($opt_rows as $opt) {                                // Průchod položkami číselníku
					$sel = ($opt['value_code'] === $value) ? 'selected' : ''; // Označení vybrané položky
					$options_html .= "<option value=\"" . htmlspecialchars((string)$opt['value_code']) . "\" {$sel}>" . htmlspecialchars((string)$opt['caption']) . "</option>"; // Položka číselníku
				}
			}
			
			if ($is_readonly) {                                              // Vykreslení zamčené roletky číselníku
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_val}\"><select disabled {$attr_string}>{$options_html}</select>"; // Zamčený select číselníku
			}
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>"; // Aktivní select číselníku
		}

		// 4. Generování <select> seznamů pro relační odkazy na jiné logické třídy (referenced_class) s překlady dle f_language_list
		if (!empty($meta['referenced_class'])) {                             // Pokud sloupec odkazuje na jinou třídu
			$options_html = "<option value=\"\">{$lbl_select}</option>";     // Prázdná výchozí volba relace
			$ref_class_uuid = guidliteral((string)$meta['referenced_class']); // UUID odkazované logické třídy

			$rc_row = sqlfirstrow("
				SELECT mc.class_name, mo.builtin_code AS ref_table
				FROM meta_class mc
				JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
				WHERE mc.original = {$ref_class_uuid} AND mc.object_owner = 0x00 AND mc.record_type = 'A' AND mc.removed = 0
			");                                                              // Dotaz na cílovou tabulku relace přes sqlfirstrow
			if (!empty($rc_row)) {                                           // Pokud byla cílová třída nalezena
				$ref_table = (string)$rc_row['ref_table'];                   // Fyzická tabulka cílové třídy

				$exclude_self = '';                                          // Podmínka vyloučení sebe sama u stromů
				$curr_guid = trim((string)getinput('update_guid'));          // Aktuálně editovaný záznam
				if ($ref_table === $this->storage_table AND $curr_guid !== '' AND $curr_guid !== 'NEW') { // Kontrola rekurzivní vazby
					$exclude_self = " AND a.original <> " . guidliteral($curr_guid); // Zamezení cyklickému odkazu na sebe
				}

				if ($ref_table === 'meta_class') {                           // Načtení lokalizovaných položek z meta_class
					$items = sqlarray_simple("
						WITH fl AS (
							SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
						)
						SELECT a.original, a.class_name AS code_col, COALESCE(tr.caption, a.caption, '') AS caption
						FROM meta_class a
						OUTER APPLY (
							SELECT TOP 1 l.caption
							FROM meta_class l
							JOIN fl ON fl.[language] = l.[language]
							WHERE l.original = a.original
							  AND l.record_type = 'L'
							  AND l.removed = 0
							  AND l.object_owner IN ({$org_sql}, 0x00)
							  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
							ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
						) tr
						WHERE a.object_owner = 0x00 AND a.record_type = 'A' AND a.removed = 0 {$exclude_self}
						ORDER BY a.class_name
					");                                                      // Dotaz na třídy s překladem
				} elseif ($ref_table === 'meta_object') {                    // Načtení lokalizovaných položek z meta_object
					$items = sqlarray_simple("
						WITH fl AS (
							SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
						)
						SELECT a.original, a.builtin_code AS code_col, COALESCE(tr.caption, a.caption, '') AS caption
						FROM meta_object a
						OUTER APPLY (
							SELECT TOP 1 l.caption
							FROM meta_object l
							JOIN fl ON fl.[language] = l.[language]
							WHERE l.original = a.original
							  AND l.record_type = 'L'
							  AND l.removed = 0
							  AND l.object_owner IN ({$org_sql}, 0x00)
							  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
							ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
						) tr
						WHERE a.object_owner = 0x00 AND a.record_type = 'A' AND a.removed = 0 {$exclude_self}
						ORDER BY a.object_type, a.builtin_code
					");                                                      // Dotaz na objekty s překladem
				} elseif ($ref_table === 'meta_column') {                    // Načtení lokalizovaných položek z meta_column
					$items = sqlarray_simple("
						WITH fl AS (
							SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
						)
						SELECT a.original, a.column_name AS code_col, COALESCE(tr.caption, a.caption, '') AS caption
						FROM meta_column a
						OUTER APPLY (
							SELECT TOP 1 l.caption
							FROM meta_column l
							JOIN fl ON fl.[language] = l.[language]
							WHERE l.original = a.original
							  AND l.record_type = 'L'
							  AND l.removed = 0
							  AND l.object_owner IN ({$org_sql}, 0x00)
							  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
							ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
						) tr
						WHERE a.object_owner = 0x00 AND a.record_type = 'A' AND a.removed = 0 {$exclude_self}
						ORDER BY a.column_name
					");                                                      // Dotaz na sloupce s překladem
				} else {
					$items = sqlarray_simple("
						WITH fl AS (
							SELECT [language], fallback_order FROM dbo.f_language_list({$safe_lang}) WHERE fallback_order < 1000
						),
						ranked_ref AS (
							SELECT a.original, '' AS code_col, a.caption,
								ROW_NUMBER() OVER (PARTITION BY a.original ORDER BY CASE WHEN a.object_owner = {$org_sql} THEN 0 ELSE 1 END) AS rn
							FROM {$ref_table} a
							WHERE (a.object_owner IN ({$org_sql}, 0x00) OR a.object_owner = a.original)
							  AND a.record_type = 'A'
							  AND a.removed = 0
							  {$exclude_self}
						)
						SELECT r.original, r.code_col, COALESCE(tr.caption, r.caption, '') AS caption
						FROM ranked_ref r
						OUTER APPLY (
							SELECT TOP 1 l.caption
							FROM {$ref_table} l
							JOIN fl ON fl.[language] = l.[language]
							WHERE l.original = r.original
							  AND l.record_type = 'L'
							  AND l.removed = 0
							  AND (l.object_owner IN ({$org_sql}, 0x00) OR l.object_owner = l.original)
							  AND NULLIF(CAST(l.caption AS VARCHAR(MAX)), '') IS NOT NULL
							ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC
						) tr
						WHERE r.rn = 1
						ORDER BY caption
					");                                                      // Obecný dotaz na entitu s překladem a izolací tenanta
				}

				if (is_array($items)) {                                      // Kontrola platného pole položek relace
					foreach ($items as $item) {                              // Sestavení voleb relační roletky
						$item_uuid = (string)$item['original'];              // UUID položky v roletce
						$item_code = (string)$item['code_col'];              // Technický kód položky
						$item_cap = (string)$item['caption'];                // Přeložený název položky
						$sel = (strcasecmp($item_uuid, $value) === 0) ? 'selected' : ''; // Porovnání UUID bez ohledu na velikost písmen
						$item_label = ($item_code !== '' AND $item_cap !== '' AND $item_cap !== $item_code) ? "{$item_code} ({$item_cap})" : ($item_code ?: $item_cap ?: $item_uuid); // Text položky
						$options_html .= "<option value=\"" . htmlspecialchars($item_uuid) . "\" {$sel}>" . htmlspecialchars($item_label) . "</option>"; // Přidání volby
					}
				}
			}

			if ($is_readonly) {                                              // Vykreslení zamčené relační roletky
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_val}\"><select disabled {$attr_string}>{$options_html}</select>"; // Zamčený select relace
			}
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>"; // Aktivní select relace
		}

		// Výběr správného prvku podle 'input_type' uloženého v databázi
		switch ($type) {                                                     // Rozlišení podle typu vstupního prvku
			case 'textarea':
				$rows = !empty($meta['input_rows']) ? "rows=\"{$meta['input_rows']}\"" : "rows=\"3\""; // Počet řádků textarea
				return "<textarea name=\"{$safe_name}\" {$rows} {$attr_string}>{$safe_val}</textarea>"; // Víceřádkové textové pole
				
			case 'checkbox':
				$checked = ($value === '1' OR strtolower($value) === 'true') ? 'checked' : ''; // Stav zaškrtnutí
				if ($is_readonly) {                                          // Pokud je checkbox uzamčen
					$real_val = ($checked !== '') ? '1' : '0';               // Skutečná hodnota zamčeného pole
					return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$real_val}\">\n\t\t\t\t\t\t<input type=\"checkbox\" name=\"{$safe_name}\" value=\"1\" {$checked} {$attr_string}>"; // Zamčený checkbox
				}
				
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"0\">\n\t\t\t\t\t\t<input type=\"checkbox\" name=\"{$safe_name}\" value=\"1\" {$checked} {$attr_string}>"; // Aktivní checkbox
				
			case 'date':
				return "<input type=\"date\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>"; // Pole pro datum
				
			case 'number':
				return "<input type=\"number\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>"; // Číselné pole
				
			case 'text':
			default:
				$inputType = !empty($meta['is_url']) ? 'url' : 'text';       // Rozlišení URL a běžného textu
				return "<input type=\"{$inputType}\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>"; // Jednořádkové pole
		}
	}
}