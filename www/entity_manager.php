<?php
/**
 * =============================================================================
 * Verze: 2026-10-22 16:30
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit – čtecí, metadatová a UI vrstva (STI Architektura).
 *       Zápisové a schvalovací metody jsou vyčleněny do traitu entity_manager_write
 *       v souboru entity_manager_write.php.
 * 
 * VAZBY NA OKOLÍ:
 * - Instancován z potomků `abstract_page_master_detail` (v metodě `render()`)
 *   a z univerzální schvalovací stránky `page_approval.php`.
 * - Vkládá trait `entity_manager_write` (`entity_manager_write.php`).
 * - Využívá globální pole `$dbsession` (inicializované v `OsirisLib.php` přes `initsession()`).
 * - Využívá třídu `language_manager` (`language_manager.php`) pro získání fallback řetězce jazyků.
 * - Využívá globální `$phrase_manager` (`phrase_manager.php`) pro lokalizaci systémových hlášek a voleb.
 * - Využívá databázové funkce z `OsirisLib.php` (`sqlrun`, `sqlfirstrow`, `sqlarray_simple`,
 *   `charliteral`, `guidliteral`, `intliteral`, `fatal_error`, `getinput`).
 * - Čte metadata z tabulek `meta_class`, `meta_object`, `meta_column`, `meta_codetable`,
 *   `meta_original_keys`, `licence_level` a systémového pohledu `v_syscolumns`.
 * - V SQL dotazech volá databázové funkce `dbo.f_get_user_info`, `dbo.f_generate_original`
 *   a `dbo.f_link_original`.
 * 
 * KLÍČOVÉ KONCEPTY A ARCHITEKTURA (PRO BUDOUCÍ VÝVOJ):
 * 
 * 1. Single Table Inheritance (STI)
 *    Systém abstrahuje fyzické tabulky (meta_object) do logických tříd (meta_class).
 *    Formuláře a výpisy vždy volají entity_manager s názvem třídy (např. 'asset_class'),
 *    který automaticky získá fyzickou tabulku a vlastnosti sloupců (meta_column).
 * 
 * 2. Dědičnost sloupců (Fallback přes 'ancestor')
 *    Pokud v tabulce meta_column u konkrétní třídy chybí nějaká vlastnost 
 *    (např. input_type, max_length), stáhne se automaticky z předka v 
 *    kontejneru 'sys_global_columns' (object_owner = 0x00).
 * 
 * 3. Čtení a kaskádový COALESCE
 *    Místo statických view (vrepo_*) se dotaz staví ad-hoc.
 *    Pro překládaná pole (translate=1) se tvoří COALESCE, které propadává 
 *    přes všechny dostupné fallback jazyky definované v language_manager,
 *    následně přes vlastní/systémový originál a nakonec přes hodnoty předka.
 * 
 * 4. Ochranné zámky (is_final, is_protected, svg_icon a role Developer 'D' u metadat)
 *    - is_final: Je-li nastaveno na třídě, tenant (vyjma 0x00) NESMÍ vůbec 
 *      založit vlastní 'A' záznam (tzv. override). Může dělat jen 'L' překlady.
 *    - is_protected: Je-li nastaveno na sloupci, tenant NESMÍ tento sloupec
 *      přepsat. V SQL (při čtení) i v PHP (při zápisu) se tvrdě vynucuje 
 *      hodnota ze systémového originálu (0x00).
 *    - svg_icon: V detailním formuláři se zobrazuje výhradně jako
 *      neredigovatelný vizuální náhled ikony; v POST datech je zcela ignorován
 *      pro všechny role, protože SVG kód se spravuje výhradně DB skriptem/importem.
 *    - Ochrana metadat (meta_*): Funkčně významné atributy metadat (translate = 0)
 *      smí upravovat výhradně uživatel s active_role = 'D' (Developer). Překlady
 *      sloupce (translate = 1) mohou upravovat všichni uživatelé.
 * 
 * Změny:
 * 2026-10-22 16:30 - Vyčlenění zápisových a SSC metod do traitu entity_manager_write
 *                    v souboru entity_manager_write.php pro zkrácení a zpřehlednění kódu.
 *                  - Doplněna podpora čtení a správy tabulky organization (kde záznamy
 *                    vlastní samy sebe: object_owner = original) a roletky licence_level.
 *                  - Oprava LEFT JOIN na systémový originál o při zobrazení zrušených
 *                    záznamů a doplnění izolace tenanta u referenced_class.
 * 2026-10-21 14:36 - Sjednocení názvu sloupce vektorové ikony výhradně na svg_icon.
 * 2026-10-20 13:10 - Doplněna podpora pro zrušení a obnovení záznamu či překladu (removed).
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
	 * Načte metadata logické třídy, identifikuje fyzickou tabulku 
	 * a načte definici sloupců včetně uplatnění pravidel dědičnosti a jazykových vrstev.
	 */
	private function load_metadata(): void {
		$safe_class = charliteral($this->class_name);                        // Bezpečný SQL literál názvu třídy
		
		global $dbsession;                                                   // Globální kontext relace
		$org_uuid = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál organizace
		$lang_chain = $this->lang_manager->get_fallback_chain();             // Řetězec jazyků pro překlady

		// Pomocná funkce pro sestavení COALESCE kaskády pro překládaná pole metadat
		$build_trans_col = function(string $col, string $alias, bool $is_anc = false) use ($lang_chain) { // Sestavení COALESCE sloupce
			$coal = [];                                                      // Pole výrazů pro COALESCE
			foreach ($lang_chain as $lang) {                                 // Průchod fallback jazyky
				$coal[] = "NULLIF(CAST({$alias}_v_{$lang}.[{$col}] AS NVARCHAR(MAX)), '')"; // Překlad tenanta
				$coal[] = "NULLIF(CAST({$alias}_l_{$lang}.[{$col}] AS NVARCHAR(MAX)), '')"; // Systémový překlad
			}
			$coal[] = "NULLIF(CAST({$alias}_my.[{$col}] AS NVARCHAR(MAX)), '')"; // Základní override tenanta
			$coal[] = "NULLIF(CAST({$alias}.[{$col}] AS NVARCHAR(MAX)), '')"; // Systémový základ
			$as_name = $is_anc ? "anc_{$col}" : $col;                        // Alias výsledného sloupce
			return "COALESCE(" . implode(", ", $coal) . ") AS {$as_name}";   // Výsledný SQL výraz COALESCE
		};

		// Pomocná funkce pro sestavení LEFT JOINů pro načtení překladů a tenant overrides metadat
		$build_trans_joins = function(string $alias, string $table) use ($lang_chain, $org_uuid) { // Sestavení JOIN klauzulí
			$j = "LEFT JOIN {$table} {$alias}_my ON {$alias}_my.original = {$alias}.original AND {$alias}_my.record_type = 'A' AND {$alias}_my.object_owner = {$org_uuid} AND {$alias}_my.removed = 0\n"; // JOIN na tenant override
			foreach ($lang_chain as $lang) {                                 // Průchod jazyky pro LEFT JOIN
				$j .= "\t\t\tLEFT JOIN {$table} {$alias}_l_{$lang} ON {$alias}_l_{$lang}.original = {$alias}.original AND {$alias}_l_{$lang}.record_type = 'L' AND {$alias}_l_{$lang}.language = '{$lang}' AND {$alias}_l_{$lang}.object_owner = 0x00 AND {$alias}_l_{$lang}.removed = 0\n"; // Systémový jazyk
				$j .= "\t\t\tLEFT JOIN {$table} {$alias}_v_{$lang} ON {$alias}_v_{$lang}.original = {$alias}.original AND {$alias}_v_{$lang}.record_type = 'L' AND {$alias}_v_{$lang}.language = '{$lang}' AND {$alias}_v_{$lang}.object_owner = {$org_uuid} AND {$alias}_v_{$lang}.removed = 0\n"; // Jazyk tenanta
			}
			return $j;                                                       // Vrácení bloku JOIN klauzulí
		};

		$trans_class_fields = ['caption', 'caption_plural', 'description', 'helptext']; // Překládaná pole třídy
		$class_selects = [];                                                 // Překládané sloupce třídy
		foreach ($trans_class_fields as $f) {                                // Sestavení SELECT výrazů třídy
			$class_selects[] = $build_trans_col($f, 'mc');                   // Přidání COALESCE sloupce třídy
		}
		$class_sel_str = implode(",\n\t\t\t\t", $class_selects);             // Spojení sloupců do SELECTu
		$class_joins = $build_trans_joins('mc', 'meta_class');               // JOINy pro překlady třídy

		// 1. Načtení definice logické třídy a zjištění fyzické tabulky přes storage_object
		$sql_class = "
			SELECT 
				mc.*, 
				mo.builtin_code AS storage_table_name, 
				mo.original AS storage_original,
				{$class_sel_str}
			FROM meta_class mc
			{$class_joins}
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
			WHERE mc.class_name = {$safe_class} AND mc.record_type = 'A' AND mc.object_owner = 0x00 AND mc.removed = 0
		";                                                                   // SQL dotaz pro načtení třídy
		
		$row = sqlfirstrow($sql_class);                                      // Načtení prvního řádku metadat třídy
		if (!empty($row)) {                                                  // Kontrola, zda byla třída nalezena
			$this->class_meta = $row;                                        // Uložení metadat třídy
			$this->storage_table = (string)$row['storage_table_name'];       // Název fyzické tabulky
			$class_uuid = guidliteral((string)$row['original']);             // UUID originálu třídy
			
			// Načtení fyzického databázového schématu pro přesné parsování a validaci
			$syscols = sqlarray_simple("SELECT colname, typename, nulls FROM v_syscolumns WHERE tabname = " . charliteral($this->storage_table) . " AND iscomputed = 0 AND is_identity = 0"); // Dotaz na fyzické sloupce
			if (is_array($syscols)) {                                        // Kontrola platného pole fyzických sloupců
				foreach ($syscols as $c) {                                   // Průchod fyzickými sloupci tabulky
					$cname = (string)$c['colname'];                          // Název fyzického sloupce
					$this->physical_cols[] = $cname;                         // Zařazení do seznamu fyzických sloupců
					$this->col_types[$cname] = (string)$c['typename'];       // Datový typ sloupce
					$this->col_nulls[$cname] = strtolower(trim((string)$c['nulls'])); // Příznak nullability sloupce
				}
			}
			
			$trans_col_fields = ['caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder']; // Překládaná pole sloupců
			$col_selects = [];                                               // Překládané sloupce v meta_column
			foreach ($trans_col_fields as $f) {                              // Sestavení COALESCE pro sloupce
				$col_selects[] = $build_trans_col($f, 'c');                  // Překlad vlastního sloupce
				$col_selects[] = $build_trans_col($f, 'a', true);            // Překlad zděděného sloupce předka
			}
			$col_sel_str = implode(",\n\t\t\t\t\t", $col_selects);           // Řetězec sloupců pro SELECT
			
			$c_joins = $build_trans_joins('c', 'meta_column');               // JOINy pro překlady sloupců
			$a_joins = $build_trans_joins('a', 'meta_column');               // JOINy pro překlady předků

			// 2. Načtení sloupců patřících k fyzické tabulce vč. dědičnosti (LEFT JOIN na ancestor)
			$sql_cols = "
				SELECT 
					c.*, 
					a.list_order AS anc_list_order,
					a.input_type AS anc_input_type, 
					a.input_width AS anc_input_width, 
					a.input_rows AS anc_input_rows, 
					a.max_length AS anc_max_length, 
					a.css_class AS anc_css_class,
					a.translate AS anc_translate, 
					a.history AS anc_history,
					a.is_html AS anc_is_html,
					a.is_mandatory AS anc_is_mandatory,
					a.is_url AS anc_is_url,
					a.is_computed AS anc_is_computed, 
					a.show_empty AS anc_show_empty,
					a.hidden AS anc_hidden, 
					a.customizable AS anc_customizable,
					a.referenced_codetable AS anc_referenced_codetable,
					a.referenced_class AS anc_referenced_class,
					a.is_protected AS anc_is_protected,
					{$col_sel_str}
				FROM meta_column c
				{$c_joins}
				LEFT JOIN meta_column a ON a.original = c.ancestor AND a.record_type = 'A' AND a.object_owner = 0x00 AND a.removed = 0
				{$a_joins}
				WHERE c.parent_class = {$class_uuid} 
				  AND c.record_type = 'A' 
				  AND c.object_owner = 0x00 
				  AND c.removed = 0 
				ORDER BY c.parent_order, c.sort_code
			";                                                               // SQL dotaz na metadata sloupců
			
			$cols_rows = sqlarray_simple($sql_cols);                         // Načtení všech sloupců třídy do pole
			$list_cols_temp = [];                                            // Dočasné pole pro sloupce seznamu

			if (is_array($cols_rows)) {                                      // Kontrola platného pole sloupců
				foreach ($cols_rows as $col) {                               // Průchod načtenými sloupci třídy
					// Seznam vlastností, které se automaticky dědí z nadřízeného sloupce v globálním slovníku
					$inherited_props = [                                     // Seznam děděných vlastností sloupce
						'list_order', 'caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder', 
						'input_type', 'input_width', 'input_rows', 'max_length', 'css_class', 'translate', 'history', 
						'is_html', 'is_mandatory', 'is_url', 'is_computed', 'show_empty', 'hidden', 'customizable', 
						'referenced_codetable', 'referenced_class', 'is_protected'
					];                                                       // Konec seznamu děděných vlastností
					
					// Tyto sloupce se často z UI do DB omylem uloží jako prázdný řetězec, který musí vyvolat fallback
					$str_props = ['caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder', 'referenced_codetable', 'input_type']; // Textové vlastnosti sloupce
					
					foreach ($inherited_props as $prop) {                    // Aplikace dědičnosti vlastností
						if ($col[$prop] === null AND isset($col["anc_$prop"])) { // Kontrola prázdné hodnoty NULL
							$col[$prop] = $col["anc_$prop"];                 // Dědění při hodnotě NULL
						}
						if (in_array($prop, $str_props, true) AND $col[$prop] === '' AND !empty($col["anc_$prop"])) { // Kontrola prázdného řetězce
							$col[$prop] = $col["anc_$prop"];                 // Dědění při prázdném řetězci
						}
					}
					
					$this->columns_meta[$col['column_name']] = $col;         // Uložení metadat sloupce

					// Příprava dat pro Master (levý) panel podle zjištěného pořadí (list_order)
					if ($col['list_order'] !== null) {                       // Pokud má sloupec pořadí v seznamu
						$header_val = $col['header'] ?: $col['caption'];     // Záhlaví sloupce v seznamu
						$list_cols_temp[(int)$col['list_order']] = [         // Uložení sloupce pod klíčem pořadí
							'name' => $col['column_name'],                   // Technický název sloupce
							'header' => $header_val ?: $col['column_name']   // Zobrazované záhlaví sloupce
						];                                                   // Konec definice položky seznamu
					}
				}
			}
			
			// Seřazení sloupců levého panelu dle 'list_order'
			if (!empty($list_cols_temp)) {                                   // Pokud byly nalezeny sloupce seznamu
				ksort($list_cols_temp);                                      // Seřazení podle pořadového čísla
				foreach ($list_cols_temp as $lc) {                           // Přepis do finálního pole
					$this->list_columns[$lc['name']] = $lc['header'];        // Naplnění finálního seznamu
				}
			} else {
				$fallback_candidates = ['caption', 'name', 'code', 'builtin_code']; // Kandidáti na náhradní sloupec
				foreach ($fallback_candidates as $fc) {                      // Hledání vhodného sloupce
					if (isset($this->columns_meta[$fc])) {                   // Pokud kandidát v tabulce existuje
						$col = $this->columns_meta[$fc];                     // Vybraný náhradní sloupec
						$header_val = $col['header'] ?: $col['caption'];     // Záhlaví náhradního sloupce
						$this->list_columns[$fc] = $header_val ?: $col['column_name']; // Nastavení náhradního sloupce
						break;                                               // Ukončení hledání po první shodě
					}
				}
			}
			
			$this->is_initialized = true;                                    // Metadata jsou plně připravena
		}
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
	 * Umožňuje z nadřízené třídy ručně přepsat sloupce zobrazené v levém panelu,
	 * čímž se obejde defaultní definice z metadat.
	 */
	public function set_list_columns(array $columns): void {                 // Ruční přepsání sloupců seznamu
		$this->list_columns = $columns;                                      // Ruční nastavení sloupců seznamu
	}

	/**
	 * T-SQL KOUZLO: Vygeneruje dynamický dotaz nahrazující původní statické vrepo_*.
	 * 
	 * @param string $where          Volitelná WHERE podmínka pro dotaz
	 * @param string $order_by       Volitelné řazení. Pokud prázdné, odvodí se z list_order.
	 * @param bool   $ignore_drafts  Pokud true, načte čistě schválená data ('A'/'L') bez konceptů ('D')
	 * @param bool   $show_removed   Pokud true, zahrne i záznamy s removed = 1 (pro zobrazení a obnovu)
	 * @return string T-SQL dotaz připravený ke spuštění (sqlrun)
	 */
	public function build_select_query(string $where = '', string $order_by = '', bool $ignore_drafts = false, bool $show_removed = false): string { // Sestavení SELECT dotazu
		if (!$this->is_initialized) {                                        // Kontrola inicializace správce
			$err_title = $this->phrase('err_em_title', 'Entity manager');    // Lokalizovaný titulek chyby
			$err_msg = $this->phrase('err_meta_not_found', 'Metadata pro logickou třídu {' . chr(36) . 'class} nebyla nalezena.', ['class' => $this->class_name]); // Text chyby
			fatal_error($err_title, $err_msg);                               // Vyvolání fatální chyby
		}

		$table = $this->storage_table;                                       // Název cílové tabulky
		$is_self_owned = ($table === 'organization');                        // V tabulce organization vlastní záznamy samy sebe (object_owner = original)
		$select_list = "";                                                   // Sestavovaný seznam sloupců
		
		// Seznam technických RAC sloupců, na které se neaplikuje COALESCE fallback ani dědičnost
		$meta_columns_list = [                                               // Technické sloupce RAC a SSC
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'draft_author', 'approval_note',
			'language', 'inactive', 'removed', 'valid_from', 'valid_to', 
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified', 'import_origin'
		];                                                                   // Konec seznamu technických sloupců
		
		$has_ancestor = isset($this->columns_meta['ancestor']);              // Zda tabulka podporuje předka
		$lang_chain = $this->lang_manager->get_fallback_chain();             // Fallback řetězec jazyků
		$prim_lang = $lang_chain[0] ?? 'cs';                                 // Primární jazyk aktuální relace
		$has_trans = false;                                                  // Příznak přítomnosti překladů
		
		foreach ($this->columns_meta as $meta) {                             // Zjištění přítomnosti překládaných polí
			if (!empty($meta['translate'])) {                                // Pokud má sloupec příznak translate
				$has_trans = true;                                           // Alespoň jeden sloupec se překládá
				break;                                                       // Ukončení kontroly překladů
			}
		}

		// Sestavení seznamu tabulkových aliasů pro nejvyšší (nejnovější) datum úpravy
		$mod_aliases = ['m', 'o'];                                           // Základní aliasy (mix a originál)
		if ($has_trans) {                                                    // Přidání jazykových aliasů pro datum změny
			foreach ($lang_chain as $lang) {                                 // Průchod řetězcem jazyků
				$mod_aliases[] = "l_{$lang}";                                // Systémová jazyková mutace
				$mod_aliases[] = "v_{$lang}";                                // Tenantova jazyková mutace
			}
		}
		if ($has_ancestor) {                                                 // Přidání aliasů předka pro datum změny
			$mod_aliases[] = 'anc';                                          // Záznam předka
			if ($has_trans) {                                                // Jazykové mutace předka
				foreach ($lang_chain as $lang) {                             // Průchod řetězcem jazyků předka
					$mod_aliases[] = "anc_l_{$lang}";                        // Systémový překlad předka
					$mod_aliases[] = "anc_v_{$lang}";                        // Tenantův překlad předka
				}
			}
		}

		$values_arr = [];                                                    // Pole dvojic (datum, autor)
		foreach ($mod_aliases as $al) {                                      // Sestavení dvojic pro OUTER APPLY
			$values_arr[] = "({$al}.date_modified, {$al}.who_modified)";     // Dvojice sloupce data a autora
		}
		$values_str = implode(', ', $values_arr);                            // Spojení do VALUES klauzule
		
		$cross_apply = "
		OUTER APPLY (
			SELECT TOP 1 d_mod, w_mod 
			FROM (VALUES {$values_str}) AS mods(d_mod, w_mod) 
			WHERE d_mod IS NOT NULL 
			ORDER BY d_mod DESC
		) AS last_mod";                                                      // Klauzule pro výpočet poslední úpravy

		// Průchod sloupci a sestavení klauzule SELECT
		foreach ($this->columns_meta as $colname => $meta) {                 // Iterace přes sloupce třídy
			if ($colname === 'date_modified') {                              // Speciální ošetření data poslední změny
				$select_list .= "\n\t\t, CASE WHEN m.record_type = 'D' THEN m.date_modified ELSE last_mod.d_mod END AS [date_modified]"; // Datum změny
				continue;                                                    // Přechod na další sloupec
			}
			if ($colname === 'who_modified') {                               // Speciální ošetření autora poslední změny
				$select_list .= "\n\t\t, CASE WHEN m.record_type = 'D' THEN m.who_modified ELSE last_mod.w_mod END AS [who_modified]"; // Autor změny
				continue;                                                    // Přechod na další sloupec
			}

			if (in_array($colname, $meta_columns_list, true)) {              // Kontrola technického RAC/SSC sloupce
				$select_list .= "\n\t\t, m.[{$colname}]";                    // Přímé zařazení technického sloupce
				continue;                                                    // Přechod na další sloupec
			}
			
			$translate = (bool)$meta['translate'];                           // Zda je sloupec překládaný
			$is_protected = !empty($meta['is_protected']);                   // Zda je sloupec chráněný
			$is_string = ($translate OR in_array($meta['input_type'], ['text', 'textarea', null, ''], true)); // Příznak textového sloupce
			
			$base_coal = [];                                                 // Základní pole pro COALESCE
			if (!$is_protected) {                                            // Pokud sloupec není chráněný
				$base_coal[] = "m.[{$colname}]";                             // Tenant může ovlivnit hodnotu
			} else {
				$base_coal[] = "CASE WHEN m.record_type = 'D' THEN m.[{$colname}] ELSE NULL END"; // U konceptu zobrazíme hodnotu z D
			}
			$base_coal[] = "o.[{$colname}]";                                 // Systémový originál (0x00)
			if ($has_ancestor) {                                             // Pokud existuje vazba na předka
				$base_coal[] = "anc.[{$colname}]";                           // Zděděná hodnota z předka
			}

			if ($is_string) {                                                // Sestavení COALESCE pro textový sloupec
				$coal = [];                                                  // Kaskáda pro textový sloupec
				$coal[] = "CASE WHEN m.record_type = 'D' THEN NULLIF(CAST(m.[{$colname}] AS NVARCHAR(MAX)), '') ELSE NULL END"; // Hodnota z konceptu

				if ($translate) {                                            // Pokud se sloupec překládá
					foreach ($lang_chain as $lang) {                         // Průchod fallback jazyky
						$coal[] = "NULLIF(CAST(v_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Překlad tenanta
						$coal[] = "NULLIF(CAST(l_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Systémový překlad
					}
				}
				
				foreach ($base_coal as $b) {                                 // Průchod základními vrstvami
					$coal[] = "NULLIF(CAST({$b} AS NVARCHAR(MAX)), '')";     // Přidání základní vrstvy
				}
				
				if ($has_ancestor AND $translate) {                          // Pokud má předka a překládá se
					foreach ($lang_chain as $lang) {                         // Průchod jazyky předka
						$coal[] = "NULLIF(CAST(anc_v_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Překlad předka u tenanta
						$coal[] = "NULLIF(CAST(anc_l_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Systémový překlad předka
					}
				}
				
				$coal[] = "''";                                              // Nejzazší nouzový případ
				$coalesce_str = implode(", ", $coal);                        // Složení textového COALESCE
				$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]"; // Přidání sloupce do SELECTu
				
				if ($translate) {                                            // Doplňkové diagnostické sloupce překladu
					$select_list .= "\n\t\t, CAST(l_{$prim_lang}.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_translated]"; // Přeložená hodnota
					$select_list .= "\n\t\t, CAST(m.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_original]"; // Původní hodnota
					$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]"; // Systémová hodnota
				}
			} else {
				$coalesce_str = implode(", ", $base_coal);                   // Složení netextového COALESCE
				$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]"; // Přidání netextového sloupce
			}
		}
		
		$select_list = substr($select_list, 4);                              // Oříznutí úvodního oddělovače

		// Pojistka: Zajistíme, že klíčové řídicí sloupce SSC jsou vždy přítomny ve výsledku dotazu
		foreach (['uuid', 'original', 'record_type', 'approval_status', 'draft_author', 'approval_note', 'removed'] as $req_col) { // Kontrola povinných sloupců
			if (!isset($this->columns_meta[$req_col]) AND in_array($req_col, $this->physical_cols, true)) { // Pokud sloupec nebyl v columns_meta
				$select_list .= "\n\t\t, m.[{$req_col}]";                    // Připojení řídicího sloupce z mixu
			}
		}

		// Příznak stavu removed pro aktivní jazykovou mutaci ('L')
		if ($has_trans) {                                                    // Pokud tabulka podporuje jazykové překlady
			$select_list .= "\n\t\t, COALESCE(v_{$prim_lang}.removed, l_{$prim_lang}.removed, CAST(0 AS BIT)) AS [l_removed]"; // Příznak zrušení L záznamu
		} else {
			$select_list .= "\n\t\t, CAST(0 AS BIT) AS [l_removed]";         // Výchozí 0 pro nepřekládané tabulky
		}

		$select_list .= "\n\t\t, m.object_is_mine";                          // Příznak vlastnictví záznamu
		$select_list .= "\n\t\t, dbo.f_get_user_info(m.who_created) AS [who_created_info]"; // Jméno tvůrce záznamu
		$select_list .= "\n\t\t, dbo.f_get_user_info(CASE WHEN m.record_type = 'D' THEN m.who_modified ELSE last_mod.w_mod END) AS [who_modified_info]"; // Jméno posledního editora

		// JOINy: Napojení systémového originálu (o) a jazykových vrstev
		$o_owner_cond = $is_self_owned ? "(o.object_owner = 0x00 OR o.object_owner = o.original)" : "o.object_owner = 0x00"; // Podmínka vlastníka originálu
		$joins = "
		FROM s
		CROSS JOIN mix m
		LEFT JOIN {$table} o ON o.original = m.original AND {$o_owner_cond} AND o.record_type = 'A' AND (o.removed = 0 OR o.removed = m.removed)"; // JOIN na originál
		
		if ($has_trans) {                                                    // Připojení jazykových vrstev hlavní tabulky
			$v_owner_expr = $is_self_owned ? "m.object_owner" : "s.organization_uuid"; // Vlastník L záznamu tenanta
			foreach ($lang_chain as $lang) {                                 // Průchod řetězcem jazyků
				if ($show_removed AND $lang === $prim_lang) {                // Při zobrazení zrušených načteme pro aktivní jazyk i případný removed=1 překlad
					$joins .= "
		OUTER APPLY (SELECT TOP 1 * FROM {$table} lx WHERE lx.original = m.original AND lx.object_owner = 0x00 AND lx.language = '{$lang}' AND lx.record_type = 'L' ORDER BY lx.removed ASC, lx.date_modified DESC) l_{$lang}
		OUTER APPLY (SELECT TOP 1 * FROM {$table} vx WHERE vx.original = m.original AND vx.object_owner = {$v_owner_expr} AND vx.language = '{$lang}' AND vx.record_type = 'L' ORDER BY vx.removed ASC, vx.date_modified DESC) v_{$lang}"; // OUTER APPLY pro L záznamy
				} else {
					$joins .= "
		LEFT JOIN {$table} l_{$lang} ON l_{$lang}.original = m.original AND l_{$lang}.object_owner = 0x00 AND l_{$lang}.language = '{$lang}' AND l_{$lang}.record_type = 'L' AND l_{$lang}.removed = 0
		LEFT JOIN {$table} v_{$lang} ON v_{$lang}.original = m.original AND v_{$lang}.object_owner = {$v_owner_expr} AND v_{$lang}.language = '{$lang}' AND v_{$lang}.record_type = 'L' AND v_{$lang}.removed = 0"; // JOINy pro jazyk
				}
			}
		}

		// Totéž i pro tabulku předka
		if ($has_ancestor) {                                                 // Připojení tabulky předka
			$joins .= "
		LEFT JOIN {$table} anc ON anc.original = m.ancestor AND anc.record_type = 'A' AND anc.object_owner = 0x00 AND anc.removed = 0"; // JOIN na hlavní záznam předka
			if ($has_trans) {                                                // Připojení jazykových vrstev předka
				foreach ($lang_chain as $lang) {                             // Průchod řetězcem jazyků předka
					$joins .= "
		LEFT JOIN {$table} anc_l_{$lang} ON anc_l_{$lang}.original = m.ancestor AND anc_l_{$lang}.record_type = 'L' AND anc_l_{$lang}.language = '{$lang}' AND anc_l_{$lang}.object_owner = 0x00 AND anc_l_{$lang}.removed = 0
		LEFT JOIN {$table} anc_v_{$lang} ON anc_v_{$lang}.original = m.ancestor AND anc_v_{$lang}.record_type = 'L' AND anc_v_{$lang}.language = '{$lang}' AND anc_v_{$lang}.object_owner = s.organization_uuid AND anc_v_{$lang}.removed = 0"; // JOINy předka
				}
			}
		}

		$joins .= $cross_apply;                                              // Připojení výpočtu poslední změny

		// Sestavení CTE bloku (Common Table Expressions) s podporou vlastních konceptů uživatele ('D') a volby $show_removed
		$has_draft_author_col = in_array('draft_author', $this->physical_cols, true); // Zda má tabulka sloupec draft_author
		$rem_filter = $show_removed ? "" : "WHERE rc.removed = 0";           // Podmíněný filtr platných záznamů
		$sy_where = $show_removed ? "WHERE my.original IS NULL" : "WHERE sy.removed = 0 AND my.original IS NULL"; // Filtr v kombinaci sy a my

		$my_owner_cond = $is_self_owned
			? "(rc.object_owner = s.organization_uuid OR (s.organization_uuid = 0x00 AND rc.object_owner = rc.original))"
			: "rc.object_owner = s.organization_uuid";                       // V tabulce organization vidí Sysadmin v 0x00 všechny organizace

		$dr_owner_cond = $is_self_owned
			? "(rc.object_owner = s.organization_uuid OR (s.organization_uuid = 0x00 AND rc.object_owner = rc.original))"
			: "rc.object_owner = s.organization_uuid";                       // Podmínka vlastníka konceptu

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

		if (!$ignore_drafts AND $has_draft_author_col) {                     // Standardní režim s podporou vlastních konceptů
			$cte_sql = "
		WITH s AS (
			-- Výběr aktuálního kontextu relace z dbsession
			SELECT organization AS organization_uuid, user_account, [language] AS sess_lang FROM dbsession WHERE spid = @@SPID
		),
		{$sy_cte},
		dr AS (
			-- Vlastní rozpracované, postoupené nebo vrácené koncepty přihlášeného uživatele v aktuálním jazyce
			SELECT rc.*, CAST(1 AS BIT) AS object_is_mine, CAST(1 AS BIGINT) AS rn_rec
			FROM s JOIN {$table} rc ON {$dr_owner_cond} AND rc.record_type = 'D'
			WHERE rc.removed = 0
			  AND rc.[language] = s.sess_lang
			  AND (rc.draft_author = s.user_account OR (rc.draft_author = 0x00 AND rc.approval_status = 'R'))
		),
		base_mix AS (
			-- Kombinace schválených záznamů: tenantovy overridy + systémové záznamy bez overridu
			SELECT sy.* FROM sy LEFT JOIN my ON my.original = sy.original {$sy_where}
			UNION ALL
			SELECT * FROM my
		),
		mix AS (
			-- Koncept přihlášeného uživatele (dr) má pro zobrazení a editaci přednost před schváleným záznamem (base_mix)
			SELECT bm.* FROM base_mix bm LEFT JOIN dr ON dr.original = bm.original WHERE dr.original IS NULL
			UNION ALL
			SELECT * FROM dr
		)";                                                                  // Konec CTE s koncepty
		} else {
			$cte_sql = "
		WITH s AS (
			-- Výběr aktuálního kontextu relace z dbsession
			SELECT organization AS organization_uuid, user_account, [language] AS sess_lang FROM dbsession WHERE spid = @@SPID
		),
		{$sy_cte},
		mix AS (
			-- Kombinace: vezmeme všechny tenantovy overridy a doplníme je 
			-- systémovými záznamy, u kterých tenant dosud neudělal modifikaci.
			SELECT sy.* FROM sy LEFT JOIN my ON my.original = sy.original {$sy_where}
			UNION ALL
			SELECT * FROM my
		)";                                                                  // Konec CTE čistě schválených dat
		}

		$sql = "
		{$cte_sql}
		SELECT {$select_list}
		{$joins}
		";                                                                   // Spojení CTE, SELECT a JOIN částí

		if ($where !== '') {                                                 // Pokud je zadána podmínka WHERE
			$sql .= "\n\t\tWHERE {$where}";                                  // Připojení podmínky WHERE
		}

		if ($order_by !== '') {                                              // Pokud je zadáno vlastní řazení
			$sql .= "\n\t\tORDER BY {$order_by}";                            // Připojení vlastního ORDER BY
		} elseif (!empty($this->list_columns)) {                             // Výchozí řazení podle sloupců seznamu
			$order_cols = [];                                                // Sloupce pro výchozí řazení
			foreach (array_keys($this->list_columns) as $col) {              // Sestavení seznamu sloupců pro ORDER BY
				$order_cols[] = "[{$col}]";                                  // Zařazení sloupce do řazení
			}
			$sql .= "\n\t\tORDER BY " . implode(', ', $order_cols);          // Připojení automatického ORDER BY
		}

		return $sql;                                                         // Vrácení sestaveného SQL dotazu
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
		$rec_lang = (string)($datarow['language'] ?? 'cs');                  // Mateřský jazyk 'A' záznamu
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

			// Ochrana fyzických databázových objektů a systémových kontejnerů před smazáním v metadatech
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
		// Zobrazuje se vždy jen vizuální náhled ikony bez možnosti ruční editace SVG kódu.
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

		$type = $meta['input_type'] ?: 'text';                               // Výchozí typ prvku je text
		$safe_name = htmlspecialchars($column_name);                         // Ošetřený název prvku
		$safe_val = htmlspecialchars($value);                                // Ošetřená hodnota prvku
		
		// Sestavení vizuálních a HTML5 validačních atributů
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
		
		// Zpracování oprávnění k editaci na frontendu
		$is_readonly = $force_readonly;                                      // Výchozí stav uzamčení dle panelu
		
		if (!empty($meta['is_computed'])) {                                  // Kontrola vypočítávaného sloupce
			$is_readonly = true;                                             // Vypočítávaný sloupec nelze měnit
		} elseif ($this->is_metadata_entity() AND $active_role !== 'D' AND empty($meta['translate'])) { // Ochrana metadat mimo roli D
			$is_readonly = true;                                             // Uzamčení funkčního atributu metadat
		} elseif (!$is_mine AND !empty($meta['is_protected']) AND empty($meta['translate'])) { // Ochrana chráněných sloupců
			$is_readonly = true;                                             // Chráněný systémový sloupec
		} 
		
		$input_width = $meta['input_width'] ?: '100%';                       // Šířka vstupního pole
		
		// Aplikace stylů pro zamčená i odemčená pole
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
				SELECT builtin_code, caption
				FROM meta_object
				WHERE object_type = 'P'
				  AND builtin_code <> ''
				  AND builtin_code <> 'global_phrase'
				  AND object_owner = 0x00
				  AND record_type = 'A'
				  AND removed = 0
				ORDER BY builtin_code
			");                                                              // Načtení PHP tříd mimo global_phrase do pole
			if (is_array($src_rows)) {                                       // Kontrola platného pole výsledků
				foreach ($src_rows as $r_src) {                              // Průchod registrovanými PHP třídami
					$b_code = (string)$r_src['builtin_code'];                // Název PHP třídy
					$b_cap = (string)$r_src['caption'];                      // Popisek třídy
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

		// 3. Generování <select> seznamů pro číselníky napojené v metadatech (referenced_codetable)
		if (!empty($meta['referenced_codetable'])) {                         // Pokud je sloupec napojen na číselník
			$options_html = "<option value=\"\">{$lbl_select}</option>";     // Prázdná výchozí volba číselníku
			$safe_ct = charliteral($meta['referenced_codetable']);           // Bezpečný literál číselníku
			$opt_rows = sqlarray_simple("
				SELECT value_code, caption
				FROM meta_codetable
				WHERE codetable_name = {$safe_ct}
				  AND object_owner IN ({$org_sql}, 0x00)
				  AND record_type = 'A'
				  AND removed = 0
				  AND inactive = 0
				ORDER BY sort_code, caption
			");                                                              // Dotaz na položky číselníku s izolací tenanta
			
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

		// 4. Generování <select> seznamů pro relační odkazy na jiné logické třídy (referenced_class)
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
					$exclude_self = " AND original <> " . guidliteral($curr_guid); // Zamezení cyklickému odkazu na sebe
				}

				if ($ref_table === 'meta_class') {                           // Načtení položek z meta_class
					$items = sqlarray_simple("SELECT original, class_name AS code_col, caption FROM meta_class WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0 {$exclude_self} ORDER BY class_name"); // Dotaz na třídy
				} elseif ($ref_table === 'meta_object') {                    // Načtení položek z meta_object
					$items = sqlarray_simple("SELECT original, builtin_code AS code_col, caption FROM meta_object WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0 {$exclude_self} ORDER BY object_type, builtin_code"); // Dotaz na objekty
				} elseif ($ref_table === 'meta_column') {                    // Načtení položek z meta_column
					$items = sqlarray_simple("SELECT original, column_name AS code_col, caption FROM meta_column WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0 {$exclude_self} ORDER BY column_name"); // Dotaz na sloupce
				} else {
					$items = sqlarray_simple("
						WITH ranked_ref AS (
							SELECT original, '' AS code_col, caption,
								ROW_NUMBER() OVER (PARTITION BY original ORDER BY CASE WHEN object_owner = {$org_sql} THEN 0 ELSE 1 END) AS rn
							FROM {$ref_table}
							WHERE (object_owner IN ({$org_sql}, 0x00) OR object_owner = original)
							  AND record_type = 'A'
							  AND removed = 0
							  {$exclude_self}
						)
						SELECT original, code_col, caption FROM ranked_ref WHERE rn = 1 ORDER BY caption
					");                                                      // Obecný dotaz na entitu s izolací tenanta a deduplikací
				}

				if (is_array($items)) {                                      // Kontrola platného pole položek relace
					foreach ($items as $item) {                              // Sestavení voleb relační roletky
						$item_uuid = (string)$item['original'];              // UUID položky v roletce
						$item_code = (string)$item['code_col'];              // Technický kód položky
						$item_cap = (string)$item['caption'];                // Zobrazovaný název položky
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