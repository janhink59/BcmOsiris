<?php
/**
 * =============================================================================
 * Verze: 2026-11-05 10:15
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit – jádro třídy a metadatová vrstva (STI Architektura).
 *       Pro přehlednost a malý rozsah jednotlivých zdrojových souborů je třída
 *       rozdělena do 4 modulů:
 *       1. entity_manager.php       - Jádro, načtení metadat (přes p_em_get_*), gettery
 *       2. entity_manager_read.php  - Trait: Čtecí dotazy (fetch_rows, fetch_row) a překlady
 *       3. entity_manager_ui.php    - Trait: Generování UI prvků (render_dynamic_input, removed)
 *       4. entity_manager_write.php - Trait: Autonomní zápis, klonování, validace klíčů a SSC
 *
 * VAZBY NA OKOLÍ:
 * - Instancován z potomků `abstract_page_master_detail` / `abstract_page_tree`,
 *   `page_meta_column.php`, `page_hierarchy_item.php`, `page_scale_value.php` a `page_approval.php`.
 * - Volá databázové procedury `dbo.p_em_get_class_meta` a `dbo.p_em_get_columns_meta`
 *   (definované v `p_em_metadata.sql`).
 * - Využívá třídy `rich_text` (`rich_text.php`), `svg_icon_editor` (`svg_icon_editor.php`),
 *   `language_manager` (`language_manager.php`), funkci `translate_phrase()` (`new_functions.php`)
 *   a `OsirisLib.php`.
 *
 * Změny:
 * 2026-11-05 10:15 - Sjednocena povinnost builtin_code v is_key_column_mandatory()
 *                    (vždy povinný s automatickým odvozením z názvu/zkratky u NEW)
 *                    a doplněno načtení svg_icon_editor.php.
 * =============================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/rich_text.php';
require_once __DIR__ . '/svg_icon_editor.php';
require_once __DIR__ . '/entity_manager_read.php';
require_once __DIR__ . '/entity_manager_ui.php';
require_once __DIR__ . '/entity_manager_write.php';

class entity_manager {

	use entity_manager_read;
	use entity_manager_ui;
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
	private array $original_key_cols = [];                                   // Klíčové sloupce z meta_original_keys (uzamčené mimo NEW)
	private array $hierarchy_lock_cache = [];                                // Keš vyhodnocení uzamčení uzlů hierarchie v requestu
	private string $last_save_error = '';                                    // Text poslední validační chyby při pokusu o uložení

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
	 * Podporuje jak pořadí ($code, $default_caption, $vars), tak pořadí ($code, $vars, $default_caption).
	 */
	private function phrase(string $builtin_code, mixed $default_caption = '', mixed $vars = []): string { // Překlad interní fráze
		if (is_array($default_caption)) {                                    // Pokud bylo pole proměnných předáno jako 2. argument
			$actual_vars = $default_caption;                                 // Pole proměnných pro interpolaci
			$actual_default = is_string($vars) ? $vars : '';                 // Výchozí text ze 3. argumentu
		} else {
			$actual_default = (string) $default_caption;                     // Výchozí text z 2. argumentu
			$actual_vars = is_array($vars) ? $vars : [];                     // Pole proměnných ze 3. argumentu
		}

		if (function_exists('translate_phrase')) {                           // Pokud je načten společný helper z new_functions.php
			return translate_phrase($builtin_code, $actual_default, $actual_vars, 'entity_manager'); // Překlad přes společný helper
		}
		global $phrase_manager;                                              // Záložní přístup ke globální instanci správce frází
		if (! isset($phrase_manager) OR ! ($phrase_manager instanceof phrase_manager)) { // Kontrola existence správce frází
			$phrase_manager = new phrase_manager();                          // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] = $phrase_manager;                    // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, $actual_vars, $actual_default, 'entity_manager'); // Vrácení přeložené fráze
	}

	/**
	 * Určuje, zda aktuální entita patří mezi systémové metadatové tabulky (meta_*).
	 */
	private function is_metadata_entity(): bool {
		return str_starts_with($this->storage_table, 'meta_');               // Detekce prefixu meta_ u fyzické tabulky
	}

	/**
	 * Určí, zda je daný klíčový sloupec z meta_original_keys povinný.
	 * Všechny klíčové sloupce z meta_original_keys (včetně builtin_code, který se
	 * u nových záznamů automaticky předvyplňuje z názvu/zkratky) jsou povinné.
	 */
	public function is_key_column_mandatory(string $column_name): bool {     // Kontrola povinnosti klíčového sloupce
		if (! in_array($column_name, $this->original_key_cols, true) OR $column_name === 'ancestor_link') { // Mimo klíčové sloupce
			return false;                                                    // Nejde o povinný klíčový sloupec
		}
		return true;                                                         // Všechny klíčové sloupce originálu jsou povinné
	}

	/**
	 * Načte metadata logické třídy, fyzické schéma z v_syscolumns, klíčové sloupce z meta_original_keys
	 * a definici sloupců z meta_column pomocí databázových procedur p_em_get_class_meta a p_em_get_columns_meta.
	 */
	private function load_metadata(): void {
		global $dbsession;                                                   // Globální kontext relace
		$safe_class = charliteral($this->class_name, 80);                    // Bezpečný SQL literál názvu třídy
		$org_uuid = guidliteral((string) ($dbsession['organization'] ?? '0x00')); // SQL literál organizace
		$curr_lang = $this->lang_manager->get_current_language();            // Aktuální jazyk relace
		$safe_lang = charliteral($curr_lang, 2);                             // SQL literál jazyka
		$lang_chain = $this->lang_manager->get_fallback_chain();             // Řetězec jazyků s fallback_order < 1000

		// 1. Načtení definice logické třídy přes uloženou proceduru dbo.p_em_get_class_meta
		$cls_rows = sqlarray_simple("EXEC dbo.p_em_get_class_meta @class_name = {$safe_class}, @org_uuid = {$org_uuid}, @requested_lang = {$safe_lang}"); // Volání DB procedury
		if (empty($cls_rows)) {                                              // Pokud logická třída v DB neexistuje
			return;                                                          // Ukončení inicializace
		}

		$cls_a_map = [];                                                     // Pole 'A' záznamů třídy
		$cls_anc_map = [];                                                   // Prázdné pole předků třídy
		$cls_l_map = [];                                                     // Podřízené pole 'L' záznamů třídy
		foreach ($cls_rows as $cr) {                                         // Rozdělení na 'A' a 'L' pole
			$c_orig = (string) $cr['original'];                              // UUID třídy
			if ($cr['row_kind'] === 'A') {                                   // Hlavní záznam třídy
				$cls_a_map[$c_orig] = $cr;                                   // Uložení 'A' záznamu třídy
			} else {
				$c_lang = (string) $cr['language'];                          // Jazyk 'L' záznamu třídy
				if (! isset($cls_l_map[$c_orig][$c_lang])) {                 // První záznam pro daný jazyk
					$cls_l_map[$c_orig][$c_lang] = $cr;                      // Uložení do podřízeného pole
				}
			}
		}

		$main_cls_orig = (string) array_key_first($cls_a_map);               // UUID načtené třídy
		$row = $cls_a_map[$main_cls_orig];                                   // Základní data třídy
		foreach (['caption', 'caption_plural', 'description', 'helptext'] as $tf) { // Dosazení přeložených textů třídy
			$row[$tf] = $this->resolve_field_from_arrays($main_cls_orig, $tf, $cls_a_map, $cls_anc_map, $cls_l_map, $curr_lang, $lang_chain, 'ancestor_class'); // Překlad
		}

		$this->class_meta = $row;                                            // Uložení metadat třídy
		$this->storage_table = (string) $row['storage_table_name'];          // Název fyzické tabulky
		$col_parent_cls_uuid = guidliteral((string) ($row['effective_col_parent_class'] ?? $main_cls_orig)); // Třída pro načtení sloupců

		// 2. Načtení fyzického databázového schématu z v_syscolumns a klíčových sloupců z meta_original_keys
		$safe_tab = charliteral($this->storage_table, 128);                  // SQL literál fyzické tabulky
		$syscols = sqlarray_simple("SELECT colname, typename, nulls FROM v_syscolumns WHERE tabname = {$safe_tab} AND iscomputed = 0 AND is_identity = 0"); // Fyzické sloupce
		if (is_array($syscols)) {                                            // Kontrola platného pole fyzických sloupců
			foreach ($syscols as $c) {                                       // Průchod fyzickými sloupci tabulky
				$cname = (string) $c['colname'];                             // Název fyzického sloupce
				$this->physical_cols[] = $cname;                             // Zařazení do seznamu fyzických sloupců
				$this->col_types[$cname] = (string) $c['typename'];          // Datový typ sloupce
				$this->col_nulls[$cname] = strtolower(trim((string) $c['nulls'])); // Příznak nullability sloupce
			}
		}

		if ($this->storage_table === 'link') {                               // Speciální 4složkový klíč tabulky link
			$this->original_key_cols = ['link_def', 'from_object', 'to_object', 'ancestor_link']; // Klíčové sloupce vazby
		} else {
			$mok_row = sqlfirstrow("SELECT key1_column, key2_column FROM meta_original_keys WHERE table_name = {$safe_tab}"); // Dotaz na klíčové sloupce
			if (! empty($mok_row)) {                                         // Pokud je tabulka v meta_original_keys
				if (! empty($mok_row['key1_column'])) {                      // První klíčový sloupec
					$this->original_key_cols[] = (string) $mok_row['key1_column']; // Zařazení 1. klíčového sloupce
				}
				if (! empty($mok_row['key2_column'])) {                      // Druhý volitelný klíčový sloupec
					$this->original_key_cols[] = (string) $mok_row['key2_column']; // Zařazení 2. klíčového sloupce
				}
			}
		}

		// 3. Načtení sloupců třídy, jejich předků a překladů přes dbo.p_em_get_columns_meta
		$raw_col_rows = sqlarray_simple("EXEC dbo.p_em_get_columns_meta @col_parent_class = {$col_parent_cls_uuid}, @org_uuid = {$org_uuid}, @requested_lang = {$safe_lang}"); // Volání DB procedury
		$col_a_map = [];                                                     // Hlavní pole 'A' záznamů sloupců: [original => row]
		$col_anc_map = [];                                                   // Pole 'A' záznamů předků sloupců: [original => row]
		$col_l_map = [];                                                     // Podřízené 2D pole 'L' záznamů: [original][language => row]
		$trans_col_fields = ['caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder']; // Překládaná pole

		if (is_array($raw_col_rows)) {                                       // Rozdělení načtených řádků do polí
			foreach ($raw_col_rows as $rc) {                                 // Průchod načtenými řádky
				$orig = (string) $rc['original'];                            // UUID originálu sloupce
				$kind = (string) $rc['row_kind'];                            // Druh řádku ('A', 'ANC_A', 'L')
				if ($kind === 'A') {                                         // Vlastní sloupec třídy
					$col_a_map[$orig] = $rc;                                 // Uložení do hlavního pole sloupců
				} elseif ($kind === 'ANC_A') {                               // Sloupec předka v sys_global_columns
					$col_anc_map[$orig] = $rc;                               // Uložení do pole předků
				} else {
					$lang = (string) $rc['language'];                        // Jazyk 'L' záznamu
					if (! isset($col_l_map[$orig][$lang])) {                 // První záznam pro daný jazyk
						$col_l_map[$orig][$lang] = $rc;                      // Uložení do podřízeného pole
					} else {
						foreach ($trans_col_fields as $tf) {                 // Doplnění případných NULL polí ze systémového 'L'
							if ((string) ($col_l_map[$orig][$lang][$tf] ?? '') === '' AND (string) ($rc[$tf] ?? '') !== '') { // Fallback
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
			$anc_orig = (string) ($col['ancestor'] ?? '');                   // UUID předka v sys_global_columns
			$anc_row = ($anc_orig !== '' AND isset($col_anc_map[$anc_orig])) ? $col_anc_map[$anc_orig] : null; // Záznam předka

			if ($anc_row !== null) {                                         // Pokud má sloupec předka
				foreach ($tech_inherited_props as $prop) {                   // Průchod technickými vlastnostmi
					if ($col[$prop] === null AND isset($anc_row[$prop])) {   // Dědění při NULL
						$col[$prop] = $anc_row[$prop];                       // Převzetí hodnoty od předka
					}
					if (in_array($prop, $str_tech_props, true) AND $col[$prop] === '' AND ! empty($anc_row[$prop])) { // Dědění při ''
						$col[$prop] = $anc_row[$prop];                       // Převzetí textové vlastnosti od předka
					}
				}
			}

			$c_name = (string) $col['column_name'];                          // Technický název sloupce
			if ($this->is_key_column_mandatory($c_name)) {                   // Kontrola povinnosti klíčového sloupce
				$col['is_mandatory'] = 1;                                    // Vynucení příznaku povinného sloupce
			}

			foreach ($trans_col_fields as $tf) {                             // Průchod překládanými vlastnostmi sloupce
				$col[$tf] = $this->resolve_field_from_arrays($orig, $tf, $col_a_map, $col_anc_map, $col_l_map, $curr_lang, $lang_chain, 'ancestor'); // Překlad
			}

			$this->columns_meta[$c_name] = $col;                             // Uložení kompletních metadat sloupce

			if ($col['list_order'] !== null) {                               // Pokud má sloupec pořadí v Master panelu
				$header_val = $col['header'] ?: $col['caption'];             // Záhlaví sloupce v seznamu
				$list_cols_temp[(int) $col['list_order']] = [                // Uložení sloupce pod klíčem pořadí
					'name'   => $c_name,                                     // Technický název sloupce
					'header' => $header_val ?: $c_name                       // Zobrazované záhlaví sloupce
				];                                                           // Konec položky seznamu
			}
		}

		if (! empty($list_cols_temp)) {                                      // Seřazení sloupců levého panelu dle list_order
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

	public function get_storage_table(): string {
		return $this->storage_table;                                         // Vrácení názvu fyzické tabulky
	}

	public function has_physical_column(string $column_name): bool {         // Kontrola existence fyzického sloupce
		return in_array($column_name, $this->physical_cols, true);           // Vyhledání v poli fyzických sloupců
	}

	public function get_original_key_columns(): array {
		return $this->original_key_cols;                                     // Vrácení seznamu klíčových sloupců
	}

	public function get_last_save_error(): string {
		return $this->last_save_error;                                       // Vrácení chybové hlášky ze save_post_data()
	}

	public function set_last_save_error(string $msg): void {                 // Nastavení chybové hlášky zápisu
		$this->last_save_error = $msg;                                       // Uložení textu chyby
	}

	public function get_class_meta(): array {
		return $this->class_meta;                                            // Vrácení metadat třídy
	}

	public function get_column_meta(string $column_name): array {            // Získání metadat vybraného sloupce
		return $this->columns_meta[$column_name] ?? [];                      // Vrácení metadat sloupce
	}

	public function get_columns(): array {
		return $this->columns_meta;                                          // Vrácení všech sloupců
	}

	public function get_list_columns(): array {
		return $this->list_columns;                                          // Vrácení sloupců pro seznam
	}

	public function set_list_columns(array $columns): void {                 // Ruční přepsání sloupců seznamu
		$this->list_columns = $columns;                                      // Ruční nastavení sloupců seznamu
	}
}