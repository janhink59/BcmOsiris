<?php
/**
 * =============================================================================
 * Verze: 2026-10-17 00:50
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit pro čtení i autonomní zápis (STI Architektura).
 * 
 * VAZBY NA OKOLÍ:
 * - Instancován z potomků `abstract_page_master_detail` (v metodě `render()`)
 *   a z univerzální schvalovací stránky `page_approval.php`.
 * - Využívá globální pole `$dbsession` (inicializované v `OsirisLib.php` přes `initsession()`).
 * - Využívá třídu `language_manager` (`language_manager.php`) pro získání fallback řetězce jazyků.
 * - Využívá globální `$phrase_manager` (`phrase_manager.php`) pro lokalizaci systémových hlášek a voleb.
 * - Využívá databázové funkce z `OsirisLib.php` (`sqlrun`, `fetch`, `free_result`,
 *   `charliteral`, `guidliteral`, `fatal_error`, `getinput`).
 * - Čte metadata z tabulek `meta_class`, `meta_object`, `meta_column`, `meta_codetable`,
 *   `meta_original_keys` a systémového pohledu `v_syscolumns`.
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
 * 4. Ochranné zámky (is_final, is_protected a role Developer 'D' u metadat)
 *    - is_final: Je-li nastaveno na třídě, tenant (vyjma 0x00) NESMÍ vůbec 
 *      založit vlastní 'A' záznam (tzv. override). Může dělat jen 'L' překlady.
 *    - is_protected: Je-li nastaveno na sloupci, tenant NESMÍ tento sloupec
 *      přepsat. V SQL (při čtení) i v PHP (při zápisu) se tvrdě vynucuje 
 *      hodnota ze systémového originálu (0x00).
 *    - Ochrana metadat (meta_*): Funkčně významné atributy metadat (translate = 0)
 *      smí upravovat výhradně uživatel s active_role = 'D' (Developer). Překladové
 *      sloupce (translate = 1) mohou upravovat všichni uživatelé.
 * 
 * 5. Asymetrický zápis překladů (right_translate)
 *    Překlady do 'L' záznamů může dělat každý tenant. Pokud ale uživatel patří 
 *    k organizaci garantující překlad (translator_org) a má 'right_translate=1',
 *    jeho 'L' záznam získá object_owner=0x00 a stane se globálním překladem.
 *    Zároveň se kvůli symetrii k 'A' záznamu vždy zakládá paralelní 'L' záznam.
 * 
 * 6. Klonování s modifikací (Override vzor)
 *    Při prvním zásahu tenanta do systémového záznamu se vytvoří kompletní fyzická kopie
 *    záznamu ('A' i 'L'), ve které se nahradí upravené hodnoty. Databáze tak obsahuje vždy 
 *    kompletní data bez nutnosti plošného využívání NULL.
 * 
 * 7. Schvalovací cyklus (SSC) a koncepty (record_type = 'D')
 *    - Koncepty a návrhy se ukládají jako samostatné řádky s `record_type = 'D'`,
 *      identifikací autora `draft_author` (user_account.original) a stavem
 *      `approval_status` ('D' = rozpracovaný, 'F' = postoupený ke schválení, 'R' = vrácený).
 *    - Při schválení nového záznamu se přepíše `who_modified` -> `who_created`
 *      a `date_modified` -> `date_created` (původní autor návrhu je evidován jako tvůrce),
 *      zatímco `who_modified` a `date_modified` jdou za schvalovatelem. U update
 *      existujícího záznamu zůstává původní `who_created` a `date_created` zachováno.
 *    - Souběžné návrhy ostatních uživatelů pro stejný `(original, object_owner, language)`
 *      jsou při schválení vybraného návrhu automaticky odmítnuty (`approval_status = 'R'`).
 * 
 * Změny:
 * 2026-10-17 00:50 - Implementace kompletního schvalovacího cyklu (SSC) s `record_type = 'D'`,
 *                    metodami `delete_draft()`, `approve_draft()`, `reject_draft()`
 *                    a podporou čtení/zápisu stavů 'D', 'F', 'R' v `build_select_query()`
 *                    a `save_post_data()`.
 *                  - Důsledná náhrada všech symbolických operátorů || a && za OR a AND (Anti-LaTeX).
 * 2026-10-16 07:45 - Doplněna ochrana funkčních atributů metadat (meta_*) výhradně pro roli 'D',
 *                    zatímco překlady (translate = 1) mohou upravovat všichni uživatelé.
 *                  - Doplněno automatické generování <select> prvků pro referenced_class
 *                    a pro sloupec source_code v tabulce meta_phrase.
 *                  - Zapojen phrase_manager pro lokalizaci textů a chybových zpráv.
 * 2026-10-15 - Oprava spojených řádků v save_post_data() a build_select_query() (Anti-LaTeX ochrana).
 *            - Doplněna aktualizace date_modified a who_modified na hlavním 'A' záznamu
 *              i při samostatné úpravě 'L' záznamu.
 *            - Doplněn filtr inactive = 0 při načítání položek z meta_codetable.
 * 2026-10-12 - Odstraněn zbytečný databázový dotaz na relaci v save_post_data(),
 *              nyní se využívá globální pole $dbsession načtené přes initsession().
 * 2026-10-11 - load_metadata plně podporuje kaskádový COALESCE z jazykových vrstev ('L')
 *              a opravuje dědičnost z předka při uložení přesměrovaných prázdných stringů.
 * =============================================================================
 */

declare(strict_types=1);

class entity_manager {

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
		// Nejdříve načítáme mc.* a až za ním mc.caption (přeložené přes COALESCE), čímž
		// asociativní pole $row převezme právě tu přeloženou hodnotu.
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
		
		$q_class = sqlrun($sql_class);                                       // Spuštění dotazu na třídu
		if ($row = fetch($q_class)) {                                        // Načtení řádku metadat třídy
			$this->class_meta = $row;                                        // Uložení metadat třídy
			$this->storage_table = $row['storage_table_name'];               // Název fyzické tabulky
			$class_uuid = guidliteral($row['original']);                     // UUID originálu třídy
			free_result($q_class);                                           // Uvolnění výsledku dotazu
			
			// Načtení fyzického databázového schématu pro přesné parsování a validaci
			$q_syscols = sqlrun("SELECT colname, typename, nulls FROM v_syscolumns WHERE tabname = " . charliteral($this->storage_table) . " AND iscomputed = 0 AND is_identity = 0"); // Dotaz na fyzické sloupce
			while ($c = fetch($q_syscols)) {                                 // Průchod fyzickými sloupci tabulky
				$this->physical_cols[] = $c['colname'];                      // Název fyzického sloupce
				$this->col_types[$c['colname']] = $c['typename'];            // Datový typ sloupce
				$this->col_nulls[$c['colname']] = strtolower(trim((string)$c['nulls'])); // Příznak nullability sloupce
			}
			free_result($q_syscols);                                         // Uvolnění systémových sloupců
			
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
			
			$q_cols = sqlrun($sql_cols);                                     // Dotaz na sloupce třídy
			$list_cols_temp = [];                                            // Dočasné pole pro sloupce seznamu

			while ($col = fetch($q_cols)) {                                  // Průchod načtenými sloupci třídy
				// Seznam vlastností, které se automaticky dědí z nadřízeného sloupce v globálním slovníku
				$inherited_props = [                                         // Seznam děděných vlastností sloupce
					'list_order', 'caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder', 
					'input_type', 'input_width', 'input_rows', 'max_length', 'css_class', 'translate', 'history', 
					'is_html', 'is_mandatory', 'is_url', 'is_computed', 'show_empty', 'hidden', 'customizable', 
					'referenced_codetable', 'referenced_class', 'is_protected'
				];                                                           // Konec seznamu děděných vlastností
				
				// Tyto sloupce se často z UI do DB omylem uloží jako prázdný řetězec, který musí vyvolat fallback
				$str_props = ['caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder', 'referenced_codetable', 'input_type']; // Textové vlastnosti sloupce
				
				foreach ($inherited_props as $prop) {                        // Aplikace dědičnosti vlastností
					// Pokud je lokální hodnota u tenanta NULL, převezmeme hodnotu od předka
					if ($col[$prop] === null AND isset($col["anc_$prop"])) { // Kontrola prázdné hodnoty NULL
						$col[$prop] = $col["anc_$prop"];                     // Dědění při hodnotě NULL
					}
					
					// Speciální ošetření pro stringové vlastnosti, které by mohly mít výchozí hodnotu '' místo NULL
					if (in_array($prop, $str_props, true) AND $col[$prop] === '' AND !empty($col["anc_$prop"])) { // Kontrola prázdného řetězce
						$col[$prop] = $col["anc_$prop"];                     // Dědění při prázdném řetězci
					}
				}
				
				$this->columns_meta[$col['column_name']] = $col;             // Uložení metadat sloupce

				// Příprava dat pro Master (levý) panel podle zjištěného pořadí (list_order)
				if ($col['list_order'] !== null) {                           // Pokud má sloupec pořadí v seznamu
					$header_val = $col['header'] ?: $col['caption'];         // Záhlaví sloupce v seznamu
					$list_cols_temp[(int)$col['list_order']] = [             // Uložení sloupce pod klíčem pořadí
						'name' => $col['column_name'],                       // Technický název sloupce
						'header' => $header_val ?: $col['column_name']       // Zobrazované záhlaví sloupce
					];                                                       // Konec definice položky seznamu
				}
			}
			free_result($q_cols);                                            // Uvolnění výsledku sloupců
			
			// Seřazení sloupců levého panelu dle 'list_order'
			if (!empty($list_cols_temp)) {                                   // Pokud byly nalezeny sloupce seznamu
				ksort($list_cols_temp);                                      // Seřazení podle pořadového čísla
				foreach ($list_cols_temp as $lc) {                           // Přepis do finálního pole
					$this->list_columns[$lc['name']] = $lc['header'];        // Naplnění finálního seznamu
				}
			} else {
				// Bezpečnostní fallback: Pokud nejsou definovány list_order sloupce, vezmeme první smysluplný textový sloupec
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
	 * Tento dotaz si databáze zkompiluje ad-hoc a využije pro něj optimální indexy.
	 * 
	 * Logika a architektura dotazu:
	 * 1. Pomocí CTE bloků (s, sy, my, dr, mix) sjednotí systémová, tenant data a vlastní koncepty uživatele.
	 * 2. Implementuje tvrdou ochranu (is_protected) - vyřadí z výběru data tenanta u chráněných sloupců.
	 * 3. Pomocí masivního COALESCE skládá konečnou hodnotu překládaných (NVARCHAR) polí 
	 *    kaskádovým fallbackem přes případný koncept ('D'), všechny dostupné jazykové mutace a předky.
	 * 
	 * @param string $where          Volitelná WHERE podmínka pro dotaz
	 * @param string $order_by       Volitelné řazení. Pokud prázdné, odvodí se z list_order.
	 * @param bool   $ignore_drafts  Pokud true, načte čistě schválená data ('A'/'L') bez konceptů ('D')
	 * @return string T-SQL dotaz připravený ke spuštění (sqlrun)
	 */
	public function build_select_query(string $where = '', string$order_by = '', bool $ignore_drafts = false): string { // Sestavení SELECT dotazu
		if (!$this->is_initialized) {                                        // Kontrola inicializace správce
			$err_title = $this->phrase('err_em_title', 'Entity manager');    // Lokalizovaný titulek chyby
			$err_msg = $this->phrase('err_meta_not_found', 'Metadata pro logickou třídu {' . chr(36) . 'class} nebyla nalezena.', ['class' => $this->class_name]); // Text chyby
			fatal_error($err_title, $err_msg);                               // Vyvolání fatální chyby
		}

		$table = $this->storage_table;                                       // Název cílové tabulky
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
		$has_trans = false;                                                  // Příznak přítomnosti překladů
		
		foreach ($this->columns_meta as $meta) {                             // Zjištění přítomnosti překládaných polí
			if (!empty($meta['translate'])) {                                // Pokud má sloupec příznak translate
				$has_trans = true;                                           // Alespoň jeden sloupec se překládá
				break;                                                       // Ukončení kontroly překladů
			}
		}

		// Sestavení seznamu tabulkových aliasů, abychom našli to nejvyšší (nejnovější) datum 
		// úpravy napříč všemi vrstvami a jazyky.
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

		// Poskládání T-SQL klauzule pro získání globálního data úpravy řádku
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

		// Průchod sloupci a sestavení klauzule SELECT na základě jejich překladových a bezpečnostních vlastností
		foreach ($this->columns_meta as $colname => $meta) {                 // Iterace přes sloupce třídy
			// Datum modifikace a autora převezmeme z našeho dynamického kalkulátoru nejmladšího záznamu
			if ($colname === 'date_modified') {                              // Speciální ošetření data poslední změny
				$select_list .= "\n\t\t, CASE WHEN m.record_type = 'D' THEN m.date_modified ELSE last_mod.d_mod END AS [date_modified]"; // Datum změny
				continue;                                                    // Přechod na další sloupec
			}
			if ($colname === 'who_modified') {                               // Speciální ošetření autora poslední změny
				$select_list .= "\n\t\t, CASE WHEN m.record_type = 'D' THEN m.who_modified ELSE last_mod.w_mod END AS [who_modified]"; // Autor změny
				continue;                                                    // Přechod na další sloupec
			}

			if (in_array($colname, $meta_columns_list, true)) {              // Kontrola technického RAC/SSC sloupce
				// Technické RAC sloupce bereme přímo z vyhodnoceného mixu (m)
				$select_list .= "\n\t\t, m.[{$colname}]";                    // Přímé zařazení technického sloupce
				continue;                                                    // Přechod na další sloupec
			}
			
			$translate = (bool)$meta['translate'];                           // Zda je sloupec překládaný
			$is_protected = !empty($meta['is_protected']);                   // Zda je sloupec chráněný
			// U stringových a textových polí musíme dělat při skládání COALESCE přetypování na NVARCHAR(MAX),
			// jinak by databáze hlásila chybu na neshodu délek (prec) varcharů.
			$is_string = ($translate OR in_array($meta['input_type'], ['text', 'textarea', null, ''], true)); // Příznak textového sloupce
			
			// Sestavení základního fallbacku pro 'A' záznam (Tenant vs Systém vs Předek)
			$base_coal = [];                                                 // Základní pole pro COALESCE
			if (!$is_protected) {                                            // Pokud sloupec není chráněný
				$base_coal[] = "m.[{$colname}]";                             // Tenant může ovlivnit hodnotu (pokud není chráněná)
			} else {
				$base_coal[] = "CASE WHEN m.record_type = 'D' THEN m.[{$colname}] ELSE NULL END"; // U konceptu vývojáře zobrazíme hodnotu z D
			}
			$base_coal[] = "o.[{$colname}]";                                 // Systémový originál (0x00)
			if ($has_ancestor) {                                             // Pokud existuje vazba na předka
				$base_coal[] = "anc.[{$colname}]";                           // Zděděná hodnota z předka
			}

			if ($is_string) {                                                // Sestavení COALESCE pro textový sloupec
				$coal = [];                                                  // Kaskáda pro textový sloupec
				// 0. Pokud je aktivní řádek rozpracovaným konceptem ('D'), má jeho text přednost před schválenými 'L' záznamy
				$coal[] = "CASE WHEN m.record_type = 'D' THEN NULLIF(CAST(m.[{$colname}] AS NVARCHAR(MAX)), '') ELSE NULL END"; // Hodnota z konceptu

				if ($translate) {                                            // Pokud se sloupec překládá
					// 1. Lokalizace: Cizí jazyky mají absolutní přednost před základními daty,
					// postupně propadáváme přes fallback řetězec definovaný v language_manageru.
					foreach ($lang_chain as $lang) {                         // Průchod fallback jazyky
						$coal[] = "NULLIF(CAST(v_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Překlad tenanta
						$coal[] = "NULLIF(CAST(l_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Systémový překlad
					}
				}
				
				// 2. Primární data: Propadnutí na základní 'A' záznamy (do kterých se propisuje rodný jazyk entity)
				foreach ($base_coal as $b) {                                 // Průchod základními vrstvami
					$coal[] = "NULLIF(CAST({$b} AS NVARCHAR(MAX)), '')";     // Přidání základní vrstvy
				}
				
				// 3. Fallback dědičnosti překladů: Zkusíme vytáhnout jazykové mutace od předka
				if ($has_ancestor AND $translate) {                          // Pokud má předka a překládá se
					foreach ($lang_chain as $lang) {                         // Průchod jazyky předka
						$coal[] = "NULLIF(CAST(anc_v_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Překlad předka u tenanta
						$coal[] = "NULLIF(CAST(anc_l_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')"; // Systémový překlad předka
					}
				}
				
				$coal[] = "''";                                              // Nejzazší nouzový případ, nevracíme NULL.
				$coalesce_str = implode(", ", $coal);                        // Složení textového COALESCE
				$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]"; // Přidání sloupce do SELECTu
				
				// Pro diagnostiku a editor na frontendu vždy vracíme i čisté rozpadlé hodnoty (primární jazyk)
				if ($translate) {                                            // Doplňkové diagnostické sloupce překladu
					$prim_lang = $lang_chain[0] ?? 'cs';                     // Primární jazyk relace
					$select_list .= "\n\t\t, CAST(l_{$prim_lang}.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_translated]"; // Přeložená hodnota
					$select_list .= "\n\t\t, CAST(m.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_original]"; // Původní hodnota
					$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]"; // Systémová hodnota
				}
			} else {
				// Netextové sloupce (čísla, bity, uuid) se nestringují, COALESCE je tak bezpečný.
				$coalesce_str = implode(", ", $base_coal);                   // Složení netextového COALESCE
				$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]"; // Přidání netextového sloupce
			}
		}
		
		// Odstranění první oddělovací čárky z řetězce
		$select_list = substr($select_list, 4);                              // Oříznutí úvodního oddělovače

		// Pojistka: Zajistíme, že klíčové řídicí sloupce SSC jsou vždy přítomny ve výsledku dotazu
		foreach (['uuid', 'original', 'record_type', 'approval_status', 'draft_author', 'approval_note'] as $req_col) { // Kontrola povinných sloupců
			if (!isset($this->columns_meta[$req_col]) AND in_array($req_col, $this->physical_cols, true)) { // Pokud sloupec nebyl v columns_meta
				$select_list .= "\n\t\t, m.[{$req_col}]";                    // Připojení řídicího sloupce z mixu
			}
		}

		// Příznak, zda výsledek (byť vznikl COALESCÍM z vícero zdrojů) obsahuje zásah tenanta v 'A' nebo 'D' vrstvě
		$select_list .= "\n\t\t, m.object_is_mine";                          // Příznak vlastnictví záznamu
		
		// Dynamické připojení zformátovaných informací o uživatelích pro zobrazení auditní stopy
		$select_list .= "\n\t\t, dbo.f_get_user_info(m.who_created) AS [who_created_info]"; // Jméno tvůrce záznamu
		$select_list .= "\n\t\t, dbo.f_get_user_info(CASE WHEN m.record_type = 'D' THEN m.who_modified ELSE last_mod.w_mod END) AS [who_modified_info]"; // Jméno posledního editora

		// JOINy: Složité pole LEFT JOINŮ pro načtení všech jazykových vrstev 
		// s ohledem na aktuální dbsession.language a dynamický fallback řetězec.
		$joins = "
		FROM s
		CROSS JOIN mix m
		LEFT JOIN {$table} o ON o.original = m.original AND o.object_owner = 0x00 AND o.record_type = 'A'"; // Základní FROM a JOIN na originál
		
		if ($has_trans) {                                                    // Připojení jazykových vrstev hlavní tabulky
			foreach ($lang_chain as $lang) {                                 // Průchod řetězcem jazyků
				$joins .= "
		LEFT JOIN {$table} l_{$lang} ON l_{$lang}.original = m.original AND l_{$lang}.object_owner = 0x00 AND l_{$lang}.language = '{$lang}' AND l_{$lang}.record_type = 'L' AND l_{$lang}.removed = 0
		LEFT JOIN {$table} v_{$lang} ON v_{$lang}.original = m.original AND v_{$lang}.object_owner = s.organization_uuid AND v_{$lang}.language = '{$lang}' AND v_{$lang}.record_type = 'L' AND v_{$lang}.removed = 0"; // JOINy pro jazyk
			}
		}

		// Totéž i pro tabulku předka
		if ($has_ancestor) {                                                 // Připojení tabulky předka
			$joins .= "
		LEFT JOIN {$table} anc ON anc.original = m.ancestor AND anc.record_type = 'A' AND anc.object_owner = 0x00"; // JOIN na hlavní záznam předka
			if ($has_trans) {                                                // Připojení jazykových vrstev předka
				foreach ($lang_chain as $lang) {                             // Průchod řetězcem jazyků předka
					$joins .= "
		LEFT JOIN {$table} anc_l_{$lang} ON anc_l_{$lang}.original = m.ancestor AND anc_l_{$lang}.record_type = 'L' AND anc_l_{$lang}.language = '{$lang}' AND anc_l_{$lang}.object_owner = 0x00 AND anc_l_{$lang}.removed = 0
		LEFT JOIN {$table} anc_v_{$lang} ON anc_v_{$lang}.original = m.ancestor AND anc_v_{$lang}.original = m.ancestor AND anc_v_{$lang}.record_type = 'L' AND anc_v_{$lang}.language = '{$lang}' AND anc_v_{$lang}.object_owner = s.organization_uuid AND anc_v_{$lang}.removed = 0"; // JOINy předka
				}
			}
		}

		$joins .= $cross_apply;                                              // Připojení výpočtu poslední změny

		// Sestavení CTE bloku (Common Table Expressions) s podporou vlastních konceptů uživatele ('D')
		$has_draft_author_col = in_array('draft_author', $this->physical_cols, true); // Zda má tabulka sloupec draft_author

		if (!$ignore_drafts AND $has_draft_author_col) {                     // Standardní režim s podporou vlastních konceptů
			$cte_sql = "
		WITH s AS (
			-- Výběr aktuálního kontextu relace z dbsession
			SELECT organization AS organization_uuid, user_account, [language] AS sess_lang FROM dbsession WHERE spid = @@SPID
		),
		sy AS (
			-- Všechny čistě systémové 'A' záznamy zkoumané tabulky
			SELECT rc.*, CAST(0 AS BIT) AS object_is_mine
			FROM s JOIN {$table} rc ON rc.object_owner = 0x00 AND rc.record_type = 'A'
		),
		my AS (
			-- Vlastní platné schválené záznamy (overridy tenanta)
			SELECT rc.*, CAST(1 AS BIT) AS object_is_mine
			FROM s JOIN {$table} rc ON rc.object_owner = s.organization_uuid AND rc.record_type = 'A'
			WHERE rc.removed = 0
		),
		dr AS (
			-- Vlastní rozpracované, postoupené nebo vrácené koncepty přihlášeného uživatele v aktuálním jazyce
			SELECT rc.*, CAST(1 AS BIT) AS object_is_mine
			FROM s JOIN {$table} rc ON rc.object_owner = s.organization_uuid AND rc.record_type = 'D'
			WHERE rc.removed = 0
			  AND rc.[language] = s.sess_lang
			  AND (rc.draft_author = s.user_account OR (rc.draft_author = 0x00 AND rc.approval_status = 'R'))
		),
		base_mix AS (
			-- Kombinace schválených záznamů: tenantovy overridy + systémové záznamy bez overridu
			SELECT sy.* FROM sy LEFT JOIN my ON my.original = sy.original WHERE sy.removed = 0 AND my.original IS NULL
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
		sy AS (
			-- Všechny čistě systémové 'A' záznamy zkoumané tabulky
			SELECT rc.*, CAST(0 AS BIT) AS object_is_mine
			FROM s JOIN {$table} rc ON rc.object_owner = 0x00 AND rc.record_type = 'A'
		),
		my AS (
			-- Vlastní platné záznamy (overridy tenanta)
			SELECT rc.*, CAST(1 AS BIT) AS object_is_mine
			FROM s JOIN {$table} rc ON rc.object_owner = s.organization_uuid AND rc.record_type = 'A'
			WHERE rc.removed = 0
		),
		mix AS (
			-- Kombinace: vezmeme všechny tenantovy overridy a doplníme je 
			-- systémovými záznamy, u kterých tenant dosud neudělal modifikaci.
			SELECT sy.* FROM sy LEFT JOIN my ON my.original = sy.original WHERE sy.removed = 0 AND my.original IS NULL
			UNION ALL
			SELECT * FROM my
		)";                                                                  // Konec CTE čistě schválených dat
		}

		$sql = "
		{$cte_sql}
		SELECT {$select_list}
		{$joins}
		";                                                                   // Spojení CTE, SELECT a JOIN částí

		// Aplikace filtrů na finální datovou množinu
		if ($where !== '') {                                                 // Pokud je zadána podmínka WHERE
			$sql .= "\n\t\tWHERE {$where}";                                  // Připojení podmínky WHERE
		}

		// Automatické odvození klauzule ORDER BY
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

		global $dbsession;                                                   // Globální kontext relace
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role uživatele v relaci

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
			// U metadatových tabulek (meta_*) smí funkčně významné atributy (translate = 0)
			// upravovat výhradně uživatel s rolí Developer ('D'). Překlady mohou upravovat všichni.
			$is_readonly = true;                                             // Uzamčení funkčního atributu metadat
		} elseif (!$is_mine AND !empty($meta['is_protected']) AND empty($meta['translate'])) { // Ochrana chráněných sloupců
			$is_readonly = true;                                             // Chráněný systémový sloupec
		} 
		
		$input_width = $meta['input_width'] ?: '100%';                       // Šířka vstupního pole
		
		// Aplikace stylů pro zamčená i odemčená pole
		if ($is_readonly) {                                                  // Nastavení atributů pro zamčené pole
			$attrs[] = "readonly style=\"background-color: #f4f4f4; width: {$input_width};\""; // Vizuální odlišení readonly
			if ($type === 'checkbox') {                                      // Speciální ošetření pro checkbox
				// Checkboxy nemají nativní attribut 'readonly', používá se 'disabled'
				$attrs[] = "disabled";                                       // Deaktivace checkboxu
			}
		} else {
			$attrs[] = "style=\"width: {$input_width};\"";                   // Standardní šířka aktivního prvku
		}

		$attr_string = implode(' ', $attrs);                                 // Spojení atributů do řetězce
		$lbl_select = htmlspecialchars($this->phrase('opt_select_default', '--- Vyberte ---')); // Výchozí volba roletky

		// 1. Speciální podpora pro sloupec source_code v tabulce meta_phrase (výběr PHP třídy/stránky z meta_object)
		if ($this->storage_table === 'meta_phrase' AND $column_name === 'source_code') { // Roletka pro source_code
			$lbl_global = htmlspecialchars($this->phrase('opt_global_phrase_source', '(Globální fráze bez třídy)')); // Popisek globální fráze
			$sel_empty = ($value === '') ? 'selected' : '';                  // Označení globální fráze
			$options_html = "<option value=\"\" {$sel_empty}>{$lbl_global}</option>"; // Volba pro prázdný source_code

			$q_src = sqlrun("SELECT builtin_code, caption FROM meta_object WHERE object_type = 'P' AND builtin_code <> '' AND object_owner = 0x00 AND record_type = 'A' AND removed = 0 ORDER BY builtin_code"); // Dotaz na PHP třídy
			while ($r_src = fetch($q_src)) {                                 // Průchod registrovanými PHP třídami
				$b_code = (string)$r_src['builtin_code'];                    // Název PHP třídy
				$b_cap = (string)$r_src['caption'];                          // Popisek třídy
				$sel = ($b_code === $value) ? 'selected' : '';               // Shoda s aktuální hodnotou
				$opt_label = ($b_cap !== '' AND $b_cap !== $b_code) ? "{$b_code} ({$b_cap})" : $b_code; // Popisek volby
				$options_html .= "<option value=\"" . htmlspecialchars($b_code) . "\" {$sel}>" . htmlspecialchars($opt_label) . "</option>"; // Položka roletky
			}
			free_result($q_src);                                             // Uvolnění dotazu objektů

			if ($is_readonly) {                                              // Vykreslení zamčené roletky source_code
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_val}\"><select disabled {$attr_string}>{$options_html}</select>"; // Zamčený select
			}
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>"; // Aktivní select
		}

		// 2. Generování <select> seznamů pro číselníky napojené v metadatech (referenced_codetable)
		if (!empty($meta['referenced_codetable'])) {                         // Pokud je sloupec napojen na číselník
			$options_html = "<option value=\"\">{$lbl_select}</option>";     // Prázdná výchozí volba číselníku
			$safe_ct = charliteral($meta['referenced_codetable']);           // Bezpečný literál číselníku
			$q_opt = sqlrun("SELECT value_code, caption FROM meta_codetable WHERE codetable_name = {$safe_ct} AND record_type = 'A' AND removed = 0 AND inactive = 0 ORDER BY sort_code, caption"); // Dotaz na položky číselníku
			
			while ($opt = fetch($q_opt)) {                                   // Průchod položkami číselníku
				$sel = ($opt['value_code'] === $value) ? 'selected' : '';    // Označení vybrané položky
				$options_html .= "<option value=\"" . htmlspecialchars((string)$opt['value_code']) . "\" {$sel}>" . htmlspecialchars((string)$opt['caption']) . "</option>"; // Položka číselníku
			}
			
			free_result($q_opt);                                             // Uvolnění dotazu číselníku
			if ($is_readonly) {                                              // Vykreslení zamčené roletky číselníku
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_val}\"><select disabled {$attr_string}>{$options_html}</select>"; // Zamčený select číselníku
			}
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>"; // Aktivní select číselníku
		}

		// 3. Generování <select> seznamů pro relační odkazy na jiné logické třídy (referenced_class)
		if (!empty($meta['referenced_class'])) {                             // Pokud sloupec odkazuje na jinou třídu
			$options_html = "<option value=\"\">{$lbl_select}</option>";     // Prázdná výchozí volba relace
			$ref_class_uuid = guidliteral((string)$meta['referenced_class']); // UUID odkazované logické třídy

			$q_rc = sqlrun("
				SELECT mc.class_name, mo.builtin_code AS ref_table
				FROM meta_class mc
				JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
				WHERE mc.original = {$ref_class_uuid} AND mc.object_owner = 0x00 AND mc.record_type = 'A' AND mc.removed = 0
			");                                                              // Dotaz na cílovou tabulku relace
			if ($rc_row = fetch($q_rc)) {                                    // Pokud byla cílová třída nalezena
				$ref_table = (string)$rc_row['ref_table'];                   // Fyzická tabulka cílové třídy
				free_result($q_rc);                                          // Uvolnění dotazu cílové třídy

				$exclude_self = '';                                          // Podmínka vyloučení sebe sama u stromů
				$curr_guid = trim((string)getinput('update_guid'));          // Aktuálně editovaný záznam
				if ($ref_table === $this->storage_table AND $curr_guid !== '' AND $curr_guid !== 'NEW') { // Kontrola rekurzivní vazby
					$exclude_self = " AND original <> " . guidliteral($curr_guid); // Zamezení cyklickému odkazu na sebe
				}

				if ($ref_table === 'meta_class') {                           // Načtení položek z meta_class
					$q_items = sqlrun("SELECT original, class_name AS code_col, caption FROM meta_class WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0 {$exclude_self} ORDER BY class_name"); // Dotaz na třídy
				} elseif ($ref_table === 'meta_object') {                    // Načtení položek z meta_object
					$q_items = sqlrun("SELECT original, builtin_code AS code_col, caption FROM meta_object WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0 {$exclude_self} ORDER BY object_type, builtin_code"); // Dotaz na objekty
				} elseif ($ref_table === 'meta_column') {                    // Načtení položek z meta_column
					$q_items = sqlrun("SELECT original, column_name AS code_col, caption FROM meta_column WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0 {$exclude_self} ORDER BY column_name"); // Dotaz na sloupce
				} else {
					$q_items = sqlrun("SELECT original, '' AS code_col, caption FROM {$ref_table} WHERE record_type = 'A' AND removed = 0 {$exclude_self} ORDER BY caption"); // Obecný dotaz na entitu
				}

				while ($item = fetch($q_items)) {                            // Sestavení voleb relační roletky
					$item_uuid = (string)$item['original'];                  // UUID položky v roletce
					$item_code = (string)$item['code_col'];                  // Technický kód položky
					$item_cap = (string)$item['caption'];                    // Zobrazovaný název položky
					$sel = (strcasecmp($item_uuid, $value) === 0) ? 'selected' : ''; // Porovnání UUID bez ohledu na velikost písmen
					$item_label = ($item_code !== '' AND $item_cap !== '' AND $item_cap !== $item_code) ? "{$item_code} ({$item_cap})" : ($item_code ?: $item_cap ?: $item_uuid); // Text položky
					$options_html .= "<option value=\"" . htmlspecialchars($item_uuid) . "\" {$sel}>" . htmlspecialchars($item_label) . "</option>"; // Přidání volby
				}
				free_result($q_items);                                       // Uvolnění položek relace
			} else {
				free_result($q_rc);                                          // Uvolnění dotazu při nenalezení třídy
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
					// Zamčené checkboxy se neodesílají při POSTu. Podvrhujeme proto systémový stav 
					// přes hidden pole, aby nedošlo k falešnému zahození záznamu.
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

	/**
	 * Získání, očištění a sanitizace odeslaných POST dat.
	 * Přebírá hodnoty z $_POST, ověřuje s metadaty a balí je do bezpečných SQL literálů.
	 */
	public function extract_post_data(): array {
		$data = [];                                                          // Výstupní pole sanitizovaných dat
		// Ignorujeme technické parametry (o ty se stará save_post_data autonomně)
		$meta_columns_list = [                                               // Seznam technických sloupců mimo POST
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'draft_author', 'approval_note',
			'language', 'inactive', 'removed', 'valid_from', 'valid_to', 
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified', 'import_origin'
		];                                                                   // Konec seznamu technických sloupců
		
		foreach ($this->columns_meta as $colname => $meta) {                 // Průchod všemi sloupci třídy
			if (!empty($meta['is_computed']) OR in_array($colname, $meta_columns_list, true)) { // Přeskočení technických a computed polí
				continue;                                                    // Pokračování na další sloupec
			}
			
			// Nativní chování HTML formulářů u checkboxů (neodesílá se, pokud není zaškrtnuto)
			if (!isset($_POST[$colname]) AND $meta['input_type'] === 'checkbox') { // Ošetření nezaškrtnutého checkboxu
				$data[$colname] = 0;                                         // Nezaškrtnutý checkbox má hodnotu 0
				continue;                                                    // Pokračování na další sloupec
			}
			
			if (!isset($_POST[$colname])) {                                  // Pokud pole nebylo vůbec ve formuláři
				continue;                                                    // Pokračování na další sloupec
			}

			$raw_val = (string)$_POST[$colname];                             // Surová hodnota z formuláře
			$phys_type = $this->col_types[$colname] ?? '';                   // Fyzický typ sloupce v DB

			// Typově přesné parsování podle fyzického schématu databáze a metadat
			if (in_array($phys_type, ['uuid', 'uniqueidentifier'], true)) {  // Pokud jde o UUID sloupec
				$data[$colname] = guidliteral($raw_val);                     // Převod na bezpečný UUID literál
			} elseif ($meta['input_type'] === 'checkbox') {                  // Pokud jde o bitový checkbox
				$data[$colname] = ($raw_val === '1' OR strtolower($raw_val) === 'true') ? 1 : 0; // Bitová hodnota 1 nebo 0
			} elseif ($meta['input_type'] === 'number') {                    // Pokud jde o číselný sloupec
				$data[$colname] = ($raw_val === '') ? 'NULL' : (string)(float)$raw_val; // Číselný literál nebo NULL
			} else {
				$data[$colname] = charliteral($raw_val);                     // Převod na bezpečný textový literál
			}
		}
		
		return $data;                                                        // Vrácení připravených dat
	}

	/**
	 * JÁDRO BACKENDU: Provede autonomní zápis dat s podporou schvalovacího cyklu (SSC)
	 * a architektury "Klonování s modifikací".
	 * 
	 * @param string $update_guid   Originální UUID záznamu (Prázdné pro INSERT)
	 * @param string $target_status Cílový stav zápisu: 'A' = schválený, 'D' = koncept, 'F' = ke schválení
	 * @return string Uložené nebo nově vypočtené `original` UUID záznamu
	 */
	public function save_post_data(string $update_guid = '', string $target_status = 'A'): string { // Autonomní uložení dat
		if (!$this->is_initialized) {                                        // Kontrola inicializace metadat
			return $update_guid;                                             // Návrat při neinicializované třídě
		}

		if (!in_array($target_status, ['A', 'D', 'F'], true)) {              // Validace cílového stavu
			$target_status = 'A';                                            // Fallback na schválený stav
		}

		$post_data = $this->extract_post_data();                             // Extrakce hodnot z POSTu
		if (empty($post_data)) {                                             // Pokud nepřišla žádná data
			return $update_guid;                                             // Ukončení bez zápisu
		}

		// 1. Zjištění kontextu přihlášeného uživatele a organizace (Tenanta) z globální proměnné
		global $dbsession;                                                   // Načtení globální relace

		if (empty($dbsession) OR empty($dbsession['login_session_uuid'])) {  // Kontrola platné relace v dbsession
			$err_save_title = $this->phrase('err_save_failed_title', 'Uložení selhalo'); // Titulek chyby uložení
			$err_save_msg = $this->phrase('err_save_no_session', 'Nepodařilo se načíst kontext uživatele z globální relace dbsession.'); // Text chyby relace
			fatal_error($err_save_title, $err_save_msg);                     // Vyvolání chyby při ztrátě relace
		}

		// Identita uživatele: zachování surových hodnot pro PHP logiku a tvorba bezpečných SQL literálů
		$org_uuid_raw = (string)$dbsession['organization'];                  // Surové UUID organizace
		$user_uuid_raw = (string)$dbsession['login_session_uuid'];           // Surové UUID relace pro audit
		$user_acc_raw = (string)($dbsession['user_account'] ?? '0x00');      // Surové UUID účtu uživatele (pro draft_author)
		$sess_lang_raw = (string)$dbsession['language'];                     // Surový kód jazyka relace
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		$right_translate = !empty($dbsession['right_translate']);            // Oprávnění ke globálnímu překladu

		$org_uuid_sql = guidliteral($org_uuid_raw);                          // SQL literál organizace
		$user_uuid_sql = guidliteral($user_uuid_raw);                        // SQL literál uživatelské relace
		$user_acc_sql = guidliteral($user_acc_raw);                          // SQL literál uživatelského účtu
		$lang_literal_sql = charliteral($sess_lang_raw);                     // SQL literál jazyka
		
		$table = $this->storage_table;                                       // Cílová fyzická tabulka
		$is_meta_table = $this->is_metadata_entity();                        // Zda jde o tabulku metadat (meta_*)

		$orig_guid_raw = $update_guid;                                       // Surové UUID upravovaného záznamu
		$orig_guid_sql = ($update_guid === '') ? '' : guidliteral($update_guid); // SQL literál originálu

		// BACKENDOVÁ POJISTKA METADAT: Zakládání zcela nových záznamů v metadatových tabulkách
		// je povoleno výhradně pro roli Developer ('D').
		if ($is_meta_table AND $orig_guid_sql === '' AND $active_role !== 'D') { // Kontrola práv pro nový záznam metadat
			return '';                                                       // Zákaz INSERTu do metadat mimo roli D
		}

		// 2. Zjištění vlastníka a master jazyka původního 'A' záznamu
		$a_exists = false;                                                   // Zda již existuje vlastní 'A' záznam
		$a_uuid_sql = '';                                                    // SQL literál primárního klíče 'A' záznamu
		$a_lang_raw = $sess_lang_raw;                                        // Výchozí pro zcela nový záznam
		$orig_owner_raw = $org_uuid_raw;                                     // Vlastník nalezeného záznamu
		$baseline_row = [];                                                  // Předloha pro porovnání změn

		$is_sysadmin_org = ($org_uuid_raw === '0x00' OR $org_uuid_raw === '00000000-0000-0000-0000-000000000000'); // Příznak systémového tenanta

		if ($orig_guid_sql !== '') {                                         // Pokud upravujeme existující záznam
			// Dohledání existujícího záznamu (buď tenantův override, nebo systémový originál)
			$q_check = sqlrun("SELECT * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND removed = 0 AND (object_owner = {$org_uuid_sql} OR object_owner = 0x00) ORDER BY object_owner DESC"); // Dotaz na existující A záznam
			$current_row = null;                                             // Nalezený aktuální řádek
			if ($current_row = fetch($q_check)) {                            // Pokud schválený záznam existuje
				$a_exists = ((string)$current_row['object_owner'] === $org_uuid_raw OR $is_sysadmin_org); // Zda záznam patří tenantovi
				$orig_owner_raw = (string)$current_row['object_owner'];      // Uložení vlastníka záznamu
				$a_uuid_sql = guidliteral((string)$current_row['uuid']);     // Uložení UUID 'A' záznamu
				$a_lang_raw = (string)$current_row['language'];              // Mateřský jazyk 'A' záznamu
			}
			free_result($q_check);                                           // Uvolnění kontroly existence
			
			// Příprava dat pro Delta zápis (Override).
			if (!$is_sysadmin_org) {                                         // Běžný klientský tenant
				// Tenant vždy kopíruje čistý systémový záznam
				$q_base = sqlrun("SELECT * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00"); // Dotaz na systémovou předlohu
				if ($base = fetch($q_base)) {                                // Načtení systémové předlohy
					$baseline_row = $base;                                   // Systémová předloha pro tenanta
				}
				free_result($q_base);                                        // Uvolnění dotazu předlohy
			} else {
				// Systémový administrátor dědí záznam výhradně z předka (pokud nějakého má)
				$anc_val = $post_data['ancestor'] ?? ($current_row['ancestor'] ?? null); // Zjištění vazby na předka
				if (!empty($anc_val) AND $anc_val !== "''" AND $anc_val !== 'NULL') { // Pokud má záznam předka
					$anc_raw = trim((string)$anc_val, "'");                  // Očištění UUID předka
					$anc_guid = guidliteral($anc_raw);                       // SQL literál UUID předka
					$q_anc = sqlrun("SELECT * FROM {$table} WHERE original = {$anc_guid} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00"); // Dotaz na předka
					if ($anc_row = fetch($q_anc)) {                          // Načtení dat předka
						$baseline_row = $anc_row;                            // Předloha z globálního předka
					}
					free_result($q_anc);                                     // Uvolnění dotazu předka
				}
			}
		}

		// 3. Filtrace struktury: Rozdělení dat na 'A' (Základ), 'L' (Lokalizace) a 'D' (Koncept)
		$a_post_data = [];                                                   // Data určená pro hlavní 'A' záznam
		$l_post_data = [];                                                   // Data určená pro překladový 'L' záznam
		$d_post_data = [];                                                   // Data určená pro řádek konceptu 'D'
		$has_translated_cols = false;                                        // Zda formulář obsahuje překládaná pole
		$is_native_lang = ($a_lang_raw === $sess_lang_raw);                  // Zda se edituje v mateřském jazyce

		foreach ($post_data as $col => $val) {                               // Průchod odeslanými hodnotami
			$is_translated = !empty($this->columns_meta[$col]['translate']); // Zda sloupec podléhá překladu

			// BACKENDOVÁ POJISTKA METADAT: U metadatových tabulek (meta_*) smí funkčně
			// významné atributy (translate = 0) měnit výhradně role Developer ('D').
			if ($is_meta_table AND $active_role !== 'D' AND !$is_translated) { // Ochrana funkčních polí metadat
				continue;                                                    // Odfiltrování funkčního atributu metadat
			}

			// BACKENDOVÁ POJISTKA (is_protected): Pokud se nejedná o sysadmina (0x00),
			// všechny chráněné nepřekládané sloupce vyhodíme. Ignorujeme i případné podvrhy přes HTTP nástroje.
			if (!$is_sysadmin_org AND !empty($this->columns_meta[$col]['is_protected']) AND !$is_translated) { // Ochrana is_protected
				continue;                                                    // Odfiltrování chráněného sloupce
			}

			// Implementace vzoru Override (Klonování s modifikací)
			if (!empty($baseline_row) AND isset($baseline_row[$col])) {      // Porovnání s výchozí předlohou
				$baseline_val = $baseline_row[$col];                         // Hodnota v předloze
				$compare_val = trim((string)$val, "'");                      // Hodnota k porovnání bez apostrofů
				
				if (isset($this->col_nulls[$col]) AND $this->col_nulls[$col] !== 'not null') { // Pokud sloupec povoluje NULL
					if ((string)$compare_val === (string)$baseline_val) {    // Shoda s hodnotou předlohy
						$val = 'NULL';                                       // Shodná hodnota se uloží jako NULL pro dědění
					}
				}
			}

			$d_post_data[$col] = $val;                                       // Koncept 'D' drží jak věcné, tak překladové změny

			if ($is_translated) {                                            // Pokud jde o překládaný sloupec
				$has_translated_cols = true;                                 // Evidujeme přítomnost překladu
				$l_post_data[$col] = $val;                                   // Zápis hodnoty do jazykové vrstvy
				// OCHRANA ORIGINÁLU: Text, který je označen k překladu, zapíšeme do master 'A' 
				// záznamu POUZE pokud jazyk session sedí na výchozí "mateřský" jazyk entity.
				if ($is_native_lang) {                                       // Pokud jde o mateřský jazyk záznamu
					$a_post_data[$col] = $val;                               // Zápis do 'A' v mateřském jazyce
				}
			} else {
				// Číselná/Vazební data jdou do Master záznamu bez ohledu na jazyk vždy
				$a_post_data[$col] = $val;                                   // Zápis nepřekládaného sloupce do 'A'
			}
		}

		// BACKENDOVÁ POJISTKA 2 (is_final): Pokud je celá třída nedotknutelná (číselníky, metadata),
		// tenantovi zamezíme jakémukoli vytváření vlastního 'A' overridu vymazáním polí.
		if (!$is_sysadmin_org AND !empty($this->class_meta['is_final'])) {   // Kontrola příznaku is_final
			$a_post_data = [];                                               // Zákaz modifikace 'A' záznamu pro tenanta
			$d_post_data = $l_post_data;                                     // V konceptu tenanta ponecháme jen překládaná pole
		}

		// Obalení operací transakcí, aby se zamezilo nekonzistentním zápisům.
		sqlrun("BEGIN TRAN");                                                // Zahájení databázové transakce

		// Pokud zakládáme zcela nový záznam (ať už jako 'A', 'D' nebo 'F'), musíme nejprve spočítat jeho original
		if ($orig_guid_sql === '') {                                         // Výpočet deterministického originálu pro nový záznam
			$src_key_data = !empty($a_post_data) ? $a_post_data : $d_post_data; // Pole hodnot pro výpočet klíče
			$q_keys = sqlrun("SELECT key1_column, key2_column FROM meta_original_keys WHERE table_name = " . charliteral($table)); // Dotaz na klíčové sloupce
			$key_info = fetch($q_keys);                                      // Definice klíčů tabulky
			free_result($q_keys);                                            // Uvolnění dotazu na klíče

			if ($key_info) {                                                 // Pokud je tabulka v meta_original_keys
				$k1_col = $key_info['key1_column'];                          // První klíčový sloupec
				$k2_col = $key_info['key2_column'];                          // Druhý klíčový sloupec
				$k1_val = array_key_exists($k1_col, $src_key_data) ? $src_key_data[$k1_col] : "''"; // Hodnota klíče 1
				$k2_val = ($k2_col AND array_key_exists($k2_col, $src_key_data)) ? $src_key_data[$k2_col] : 'NULL'; // Hodnota klíče 2

				$q_orig = sqlrun("SELECT dbo.f_generate_original(" . charliteral($table) . ", {$org_uuid_sql}, CAST({$k1_val} AS VARCHAR(MAX)), CAST({$k2_val} AS VARCHAR(MAX))) AS orig_guid"); // Výpočet hashe
				if ($row = fetch($q_orig)) {                                 // Načtení vypočteného originálu
					$orig_guid_raw = (string)$row['orig_guid'];              // Surové UUID originálu
					$orig_guid_sql = guidliteral($orig_guid_raw);            // Deterministické UUID originálu
				}
				free_result($q_orig);                                        // Uvolnění výpočtu originálu
			} elseif ($table === 'link') {                                   // Speciální výpočet pro tabulku link
				$link_def = array_key_exists('link_def', $src_key_data) ? $src_key_data['link_def'] : "''"; // Definice vazby
				$from_obj = array_key_exists('from_object', $src_key_data) ? $src_key_data['from_object'] : "''"; // Zdroj vazby
				$to_obj = array_key_exists('to_object', $src_key_data) ? $src_key_data['to_object'] : "''"; // Cíl vazby

				$q_orig = sqlrun("SELECT dbo.f_link_original(CAST({$org_uuid_sql} AS varchar(36)), CAST({$link_def} AS varchar(36)), CAST({$from_obj} AS varchar(36)), CAST({$to_obj} AS varchar(36))) AS orig_guid"); // Výpočet originálu vazby
				if ($row = fetch($q_orig)) {                                 // Načtení originálu vazby
					$orig_guid_raw = (string)$row['orig_guid'];              // Surové UUID vazby
					$orig_guid_sql = guidliteral($orig_guid_raw);            // Deterministické UUID vazby
				}
				free_result($q_orig);                                        // Uvolnění výpočtu vazby
			} else {
				$q_orig = sqlrun("SELECT NEWID() AS orig_guid");             // Náhodné UUID pro globální tabulky
				if ($row = fetch($q_orig)) {                                 // Načtení nového UUID
					$orig_guid_raw = (string)$row['orig_guid'];              // Surové náhodné UUID
					$orig_guid_sql = guidliteral($orig_guid_raw);            // Nově vygenerované UUID
				}
				free_result($q_orig);                                        // Uvolnění dotazu NEWID
			}
		}

		// =====================================================================
		// VĚTEV A: ZÁPIS KONCEPTU NEBO POSTOUPENÍ KE SCHVÁLENÍ ('D' / 'F')
		// =====================================================================
		if ($target_status === 'D' OR $target_status === 'F') {              // Pokud ukládáme koncept nebo postupujeme ke schválení
			$safe_status = charliteral($target_status, 1);                   // SQL literál cílového stavu ('D' nebo 'F')

			// Zjistíme, zda uživatel již má pro tento (original, object_owner, language) rozpracovaný řádek 'D'
			$q_dr = sqlrun("
				SELECT uuid
				FROM {$table}
				WHERE original = {$orig_guid_sql}
				  AND object_owner = {$org_uuid_sql}
				  AND record_type = 'D'
				  AND [language] = {$lang_literal_sql}
				  AND (draft_author = {$user_acc_sql} OR (draft_author = 0x00 AND approval_status = 'R'))
				  AND removed = 0
			");                                                              // Dotaz na existující koncept uživatele
			$dr_row = fetch($q_dr);                                          // Načtení existujícího konceptu
			free_result($q_dr);                                              // Uvolnění dotazu konceptu

			if ($dr_row) {                                                   // Pokud koncept uživatele již existuje -> UPDATE
				$dr_uuid_sql = guidliteral((string)$dr_row['uuid']);         // UUID existujícího řádku konceptu
				$set_dr = [];                                                // Pole změn pro UPDATE konceptu
				foreach ($d_post_data as $col => $val) {                     // Průchod ukládanými sloupci konceptu
					$set_dr[] = "[$col] = $val";                             // Nastavení hodnoty sloupce
				}
				$set_dr[] = "approval_status = {$safe_status}";              // Nastavení stavu ('D' nebo 'F')
				$set_dr[] = "draft_author = {$user_acc_sql}";                // Zajištění autora konceptu
				$set_dr[] = "approval_note = ''";                            // Vyčištění předchozí poznámky odmítnutí
				$set_dr[] = "date_modified = GETDATE()";                     // Aktualizace času úpravy konceptu
				$set_dr[] = "who_modified = {$user_uuid_sql}";               // Aktualizace relace autora konceptu

				sqlrun("UPDATE {$table} SET " . implode(', ', $set_dr) . " WHERE uuid = {$dr_uuid_sql}"); // Provedení UPDATE konceptu
			} else {
				// Koncept ještě neexistuje -> pokud v DB existuje schválený 'A' záznam, naklonujeme ho do 'D', jinak provedeme čistý INSERT
				$q_src_a = sqlrun("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND removed = 0 AND object_owner IN ({$org_uuid_sql}, 0x00) ORDER BY object_owner DESC"); // Kontrola předlohy A
				$src_a_row = fetch($q_src_a);                                // Načtení předlohy A
				free_result($q_src_a);                                       // Uvolnění dotazu předlohy A

				if ($src_a_row) {                                            // Klonování existujícího 'A' záznamu do 'D'
					$src_a_uuid = guidliteral((string)$src_a_row['uuid']);   // UUID zdrojového 'A' řádku
					$ins_cols = [];                                          // Cílové sloupce klonovaného konceptu
					$sel_vals = [];                                          // Výrazy v SELECT klauzuli klonu

					foreach ($this->physical_cols as $col) {                 // Sestavení sloupců pro klonování do 'D'
						$ins_cols[] = "[$col]";                              // Zařazení fyzického sloupce
						if ($col === 'uuid') {                               // Primární klíč konceptu
							$sel_vals[] = "NEWID()";                         // Koncept má vždy unikátní NEWID()
						} elseif ($col === 'object_owner') {                 // Vlastník konceptu
							$sel_vals[] = $org_uuid_sql;                     // Vlastníkem je organizace uživatele
						} elseif ($col === 'original') {                     // Originál záznamu
							$sel_vals[] = "original";                        // Zachování společného originálu
						} elseif ($col === 'record_type') {                  // Typ záznamu
							$sel_vals[] = "'D'";                             // Označení konceptu 'D'
						} elseif ($col === 'approval_status') {              // Stav schválení
							$sel_vals[] = $safe_status;                      // Stav 'D' nebo 'F'
						} elseif ($col === 'draft_author') {                 // Autor konceptu
							$sel_vals[] = $user_acc_sql;                     // UUID účtu přihlášeného uživatele
						} elseif ($col === 'approval_note') {                // Poznámka schvalování
							$sel_vals[] = "''";                              // Výchozí prázdná poznámka
						} elseif ($col === 'language') {                     // Jazyk konceptu
							$sel_vals[] = $lang_literal_sql;                 // Aktuální jazyk relace
						} elseif (in_array($col, ['date_created', 'date_modified'], true)) { // Časová razítka konceptu
							$sel_vals[] = "GETDATE()";                       // Čas pořízení konceptu
						} elseif (in_array($col, ['who_created', 'who_modified'], true)) { // Auditní sloupce konceptu
							$sel_vals[] = $user_uuid_sql;                    // Relace autora konceptu
						} elseif (array_key_exists($col, $d_post_data)) {    // Změněný sloupec z formuláře
							$sel_vals[] = $d_post_data[$col];                // Nová hodnota z formuláře
						} else {
							$sel_vals[] = "[$col]";                          // Převzetí nezměněné hodnoty z 'A' záznamu
						}
					}

					$sql_clone_d = "INSERT INTO {$table} (" . implode(', ', $ins_cols) . ") \nSELECT " . implode(', ', $sel_vals) . " \nFROM {$table} \nWHERE uuid = {$src_a_uuid}"; // SQL klonování do D
					sqlrun($sql_clone_d);                                    // Vložení klonovaného konceptu
				} else {
					// Zcela nový záznam zakládaný rovnou jako koncept ('D' nebo 'F')
					$ins_cols = [];                                          // Sloupce pro INSERT nového konceptu
					$ins_vals = [];                                          // Hodnoty pro INSERT nového konceptu

					foreach ($this->physical_cols as $col) {                 // Sestavení sloupců nového konceptu
						if ($col === 'uuid') {                               // Primární klíč řádku
							$ins_cols[] = "[$col]";                          // Sloupec uuid
							$ins_vals[] = "NEWID()";                         // Unikátní NEWID() pro koncept
						} elseif ($col === 'original') {                     // Logický identifikátor záznamu
							$ins_cols[] = "[$col]";                          // Sloupec original
							$ins_vals[] = $orig_guid_sql;                    // Vypočtené deterministické UUID
						} elseif ($col === 'object_owner') {                 // Vlastník záznamu
							$ins_cols[] = "[$col]";                          // Sloupec object_owner
							$ins_vals[] = $org_uuid_sql;                     // UUID organizace uživatele
						} elseif ($col === 'record_type') {                  // Typ záznamu
							$ins_cols[] = "[$col]";                          // Sloupec record_type
							$ins_vals[] = "'D'";                             // Typ 'D' (koncept)
						} elseif ($col === 'approval_status') {              // Stav schválení
							$ins_cols[] = "[$col]";                          // Sloupec approval_status
							$ins_vals[] = $safe_status;                      // Stav 'D' nebo 'F'
						} elseif ($col === 'draft_author') {                 // Autor konceptu
							$ins_cols[] = "[$col]";                          // Sloupec draft_author
							$ins_vals[] = $user_acc_sql;                     // UUID účtu autora
						} elseif ($col === 'approval_note') {                // Poznámka schvalovatele
							$ins_cols[] = "[$col]";                          // Sloupec approval_note
							$ins_vals[] = "''";                              // Prázdná poznámka
						} elseif ($col === 'language') {                     // Jazyk konceptu
							$ins_cols[] = "[$col]";                          // Sloupec language
							$ins_vals[] = $lang_literal_sql;                 // Jazyk relace
						} elseif (in_array($col, ['date_created', 'date_modified'], true)) { // Časová razítka
							$ins_cols[] = "[$col]";                          // Sloupec data
							$ins_vals[] = "GETDATE()";                       // Aktuální čas
						} elseif (in_array($col, ['who_created', 'who_modified'], true)) { // Auditní vazby
							$ins_cols[] = "[$col]";                          // Sloupec autora
							$ins_vals[] = $user_uuid_sql;                    // Relace autora
						} elseif (array_key_exists($col, $d_post_data)) {    // Datový sloupec z formuláře
							$ins_cols[] = "[$col]";                          // Název datového sloupce
							$ins_vals[] = $d_post_data[$col];                // Hodnota datového sloupce
						}
					}

					$sql_ins_d = "INSERT INTO {$table} (" . implode(', ', $ins_cols) . ") VALUES (" . implode(', ', $ins_vals) . ")"; // SQL příkaz INSERT konceptu
					sqlrun($sql_ins_d);                                      // Provedení INSERTu nového konceptu
				}
			}

			sqlrun("COMMIT");                                                // Potvrzení transakce uložení konceptu
			return $orig_guid_raw;                                           // Vrácení originálu uloženého konceptu
		}

		// =====================================================================
		// VĚTEV B: PŘÍMÝ ZÁPIS SCHVÁLENÉHO ZÁZNAMU ('A' + symetrické 'L')
		// =====================================================================
		// 4. Zápis do 'A' záznamu (Správa Master dat a auditních stop)
		if ($update_guid === '' AND !$a_exists) {                            // Zcela nový záznam ukládaný rovnou jako schválený
			$insert_cols = [];                                               // Sloupce pro INSERT nového 'A' záznamu
			$insert_vals = [];                                               // Hodnoty pro INSERT nového 'A' záznamu
			
			foreach ($this->physical_cols as $col) {                         // Sestavení polí pro nový 'A' záznam
				if (in_array($col, ['uuid', 'original'], true)) {            // Primární klíč a originál
					$insert_cols[] = "[$col]";                               // Identifikátory záznamu
					$insert_vals[] = $orig_guid_sql;                         // Hodnota spočteného originálu
				} elseif ($col === 'object_owner') {                         // Vlastník záznamu
					$insert_cols[] = "[$col]";                               // Sloupec vlastníka
					$insert_vals[] = $org_uuid_sql;                          // UUID organizace uživatele
				} elseif ($col === 'record_type') {                          // Typ záznamu
					$insert_cols[] = "[$col]";                               // Typ záznamu
					$insert_vals[] = "'A'";                                  // Hlavní schválený záznam
				} elseif ($col === 'approval_status') {                      // Stav schválení
					$insert_cols[] = "[$col]";                               // Sloupec stavu schválení
					$insert_vals[] = "'A'";                                  // Schválený stav
				} elseif ($col === 'language') {                             // Jazyk záznamu
					$insert_cols[] = "[$col]";                               // Výchozí jazyk záznamu
					$insert_vals[] = $lang_literal_sql;                      // Aktuální jazyk relace
				} elseif (in_array($col, ['date_created', 'date_modified'], true)) { // Časová razítka
					$insert_cols[] = "[$col]";                               // Časové razítko
					$insert_vals[] = "GETDATE()";                            // Aktuální databázový čas
				} elseif (in_array($col, ['who_created', 'who_modified'], true)) { // Auditní identifikátory
					$insert_cols[] = "[$col]";                               // Auditní identifikátor autora
					$insert_vals[] = $user_uuid_sql;                         // UUID přihlášené relace
				} elseif (array_key_exists($col, $a_post_data)) {            // Datové pole z formuláře
					$insert_cols[] = "[$col]";                               // Datový sloupec z formuláře
					$insert_vals[] = $a_post_data[$col];                     // Hodnota datového sloupce
				}
			}

			$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") VALUES (" . implode(', ', $insert_vals) . ")"; // Sestavení INSERT dotazu
			sqlrun($sql);                                                    // Provedení INSERTu nového 'A' záznamu
			
		} elseif (!empty($a_post_data)) {                                    // UPDATE nebo OVERRIDE existujícího 'A' záznamu
			// B) UPDATE NEBO OVERRIDE 'A' ZÁZNAMU
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
				// OVERRIDE: Tenant zasahuje do systémového záznamu poprvé (nebo schvaluje nový koncept, kde ještě 'A' nebylo).
				$q_sys_check = sqlrun("SELECT 1 AS ex FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = 0x00 AND record_type = 'A' AND removed = 0"); // Kontrola systémového originálu
				$sys_exists = (bool)fetch($q_sys_check);                     // Zda existuje systémový záznam 0x00
				free_result($q_sys_check);                                   // Uvolnění kontroly

				if ($sys_exists) {                                           // Klonování ze systémového originálu 0x00
					$insert_cols = [];                                       // Cílové sloupce klonovaného záznamu
					$select_vals = [];                                       // Zdrojové výrazy v SELECT klauzuli
					
					foreach ($this->physical_cols as $col) {                 // Průchod fyzickými sloupci tabulky
						$insert_cols[] = "[$col]";                           // Zařazení fyzického sloupce
						
						if ($col === 'uuid') {                               // Primární klíč klonu
							$select_vals[] = "NEWID()";                      // Dočasné UUID (přepíše trigger trgo_)
						} elseif ($col === 'object_owner') {                 // Vlastník klonu
							$select_vals[] = $org_uuid_sql;                  // Vlastníkem klonu je tenant
						} elseif ($col === 'record_type') {                  // Typ záznamu klonu
							$select_vals[] = "'A'";                          // Klon je rovněž typu 'A'
						} elseif ($col === 'approval_status') {              // Stav schválení klonu
							$select_vals[] = "'A'";                          // Schválený stav
						} elseif (in_array($col, ['date_created', 'date_modified'], true)) { // Čas vytvoření klonu
							$select_vals[] = "GETDATE()";                    // Čas vytvoření klonu
						} elseif (in_array($col, ['who_created', 'who_modified'], true)) { // Autor vytvoření klonu
							$select_vals[] = $user_uuid_sql;                 // Autor vytvoření klonu
						} elseif ($col === 'original') {                     // Vazba na originál
							$select_vals[] = "original";                     // Zachování vazby na společný originál
						} elseif ($col === 'language') {                     // Jazyk záznamu
							$select_vals[] = "language";                     // Zachování původního jazyka záznamu
						} elseif (array_key_exists($col, $a_post_data)) {    // Změněná hodnota tenanta
							$select_vals[] = $a_post_data[$col];             // Aplikace změněné hodnoty tenanta
						} else {
							$select_vals[] = "[$col]";                       // Převzetí nezměněné hodnoty ze systému
						}
					}

					$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") \nSELECT " . implode(', ', $select_vals) . " \nFROM {$table} \nWHERE original = {$orig_guid_sql} AND object_owner = 0x00 AND record_type = 'A'"; // SQL klonování
					sqlrun($sql);                                            // Vytvoření tenantova 'A' overridu
				} else {
					// Případ, kdy záznam dosud existoval pouze jako 'D' (koncept nového záznamu) a uživatel klikl na "Uložit jako schválené"
					$insert_cols = [];                                       // Sloupce pro nový 'A' záznam
					$insert_vals = [];                                       // Hodnoty pro nový 'A' záznam

					foreach ($this->physical_cols as $col) {                 // Sestavení polí pro 'A' záznam
						if (in_array($col, ['uuid', 'original'], true)) {    // Klíč a originál
							$insert_cols[] = "[$col]";                       // Sloupec identifikátoru
							$insert_vals[] = $orig_guid_sql;                 // Deterministický originál
						} elseif ($col === 'object_owner') {                 // Vlastník záznamu
							$insert_cols[] = "[$col]";                       // Sloupec vlastníka
							$insert_vals[] = $org_uuid_sql;                  // Organizace uživatele
						} elseif ($col === 'record_type') {                  // Typ záznamu
							$insert_cols[] = "[$col]";                       // Sloupec record_type
							$insert_vals[] = "'A'";                          // Schválený záznam 'A'
						} elseif ($col === 'approval_status') {              // Stav schválení
							$insert_cols[] = "[$col]";                       // Sloupec approval_status
							$insert_vals[] = "'A'";                          // Schválený stav 'A'
						} elseif ($col === 'language') {                     // Jazyk záznamu
							$insert_cols[] = "[$col]";                       // Sloupec language
							$insert_vals[] = $lang_literal_sql;              // Jazyk relace
						} elseif (in_array($col, ['date_created', 'date_modified'], true)) { // Časová razítka
							$insert_cols[] = "[$col]";                       // Sloupec data
							$insert_vals[] = "GETDATE()";                    // Aktuální čas
						} elseif (in_array($col, ['who_created', 'who_modified'], true)) { // Auditní sloupce
							$insert_cols[] = "[$col]";                       // Sloupec autora
							$insert_vals[] = $user_uuid_sql;                 // Relace uživatele
						} elseif (array_key_exists($col, $a_post_data)) {    // Datové pole z formuláře
							$insert_cols[] = "[$col]";                       // Název sloupce
							$insert_vals[] = $a_post_data[$col];             // Hodnota sloupce
						}
					}

					$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") VALUES (" . implode(', ', $insert_vals) . ")"; // SQL INSERT
					sqlrun($sql);                                            // Vložení nového 'A' záznamu
				}
			}
		}

		// 5. Zápis 'L' záznamu
		if ($has_translated_cols AND $orig_guid_sql !== '') {                // Pokud formulář obsahuje překládané sloupce
			
			$l_owner_sql = $org_uuid_sql;                                    // Výchozím vlastníkem překladu je tenant
			if ($orig_owner_raw === '0x00' OR $orig_owner_raw === '00000000-0000-0000-0000-000000000000') { // Pokud je originál systémový
				if ($right_translate) {                                      // Pokud má uživatel právo globálního překladu
					$l_owner_sql = '0x00';                                   // Oprávněný překladatel zapisuje globálně
				}
			}

			$q_l_check = sqlrun("SELECT uuid FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND language = {$lang_literal_sql} AND removed = 0"); // Kontrola existence L
			$l_exists = fetch($q_l_check);                                   // Kontrola existence 'L' záznamu
			free_result($q_l_check);                                         // Uvolnění dotazu kontroly 'L'

			if ($l_exists) {                                                 // Pokud 'L' záznam již existuje -> UPDATE
				if (!empty($l_post_data)) {                                  // Pokud jsou k dispozici přeložená data
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
				$insert_cols_l = [];                                         // Sloupce pro nový 'L' záznam
				$select_vals_l = [];                                         // Hodnoty pro nový 'L' záznam
				
				foreach ($this->physical_cols as $col) {                     // Sestavení polí pro klonování do 'L'
					$insert_cols_l[] = "[$col]";                             // Zařazení fyzického sloupce
					
					if ($col === 'uuid') {                                   // Primární klíč 'L' záznamu
						$select_vals_l[] = "NEWID()";                        // Unikátní PK pro 'L' záznam
					} elseif ($col === 'object_owner') {                     // Vlastník jazykové mutace
						$select_vals_l[] = $l_owner_sql;                     // Vlastník jazykové mutace
					} elseif ($col === 'record_type') {                      // Typ záznamu
						$select_vals_l[] = "'L'";                            // Označení jazykového záznamu
					} elseif ($col === 'approval_status') {                  // Stav schválení
						$select_vals_l[] = "'A'";                            // Schválený stav 'L' záznamu
					} elseif ($col === 'language') {                         // Kód jazyka překladu
						$select_vals_l[] = $lang_literal_sql;                // Kód jazyka překladu
					} elseif (in_array($col, ['date_created', 'date_modified'], true)) { // Časová razítka 'L'
						$select_vals_l[] = "GETDATE()";                      // Čas pořízení překladu
					} elseif (in_array($col, ['who_created', 'who_modified'], true)) { // Auditní sloupce 'L'
						$select_vals_l[] = $user_uuid_sql;                   // Autor pořízení překladu
					} elseif (array_key_exists($col, $l_post_data)) {        // Přeložená hodnota sloupce
						$select_vals_l[] = $l_post_data[$col];               // Přeložená hodnota sloupce
					} else {
						$select_vals_l[] = "[$col]";                         // Převzetí ostatních polí z 'A' záznamu
					}
				}

				$source_owner_sql = (!$is_sysadmin_org) ? "object_owner IN ({$org_uuid_sql}, 0x00)" : "object_owner = 0x00"; // Podmínka vlastníka zdroje
				$sql_l = "INSERT INTO {$table} (" . implode(', ', $insert_cols_l) . ") \nSELECT TOP 1 " . implode(', ', $select_vals_l) . " \nFROM {$table} \nWHERE original = {$orig_guid_sql} AND {$source_owner_sql} AND record_type = 'A' AND removed = 0 ORDER BY object_owner DESC"; // SQL INSERT L
				sqlrun($sql_l);                                              // Založení nového 'L' záznamu
			}

			// Jednotná auditní stopa: Pokud nebyl hlavní 'A' záznam aktualizován v kroku 4
			// (např. při úpravě samotného překladu v sekundárním jazyce nebo u třídy s is_final = 1),
			// povinně zaktualizujeme date_modified a who_modified na hlavním 'A' záznamu.
			if (empty($a_post_data) AND $a_uuid_sql !== '' AND ($a_exists OR $l_owner_sql === '0x00')) { // Kontrola potřeby aktualizace auditu na A
				sqlrun("UPDATE {$table} SET date_modified = GETDATE(), who_modified = {$user_uuid_sql} WHERE uuid = {$a_uuid_sql}"); // Aktualizace auditu na A
			}
		}

		// 6. Úklid konceptů ('D') při přímém uložení jako schválené ('A'):
		// Vlastní koncept aktuálního uživatele smažeme a případné cizí souběžné koncepty odmítneme ('R').
		if (in_array('draft_author', $this->physical_cols, true) AND $orig_guid_sql !== '') { // Pokud tabulka podporuje koncepty
			sqlrun("
				DELETE FROM {$table}
				WHERE original = {$orig_guid_sql}
				  AND object_owner = {$org_uuid_sql}
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
				  AND object_owner = {$org_uuid_sql}
				  AND record_type = 'D'
				  AND [language] = {$lang_literal_sql}
				  AND removed = 0
			");                                                              // Odmítnutí souběžných konceptů jiných uživatelů
		}

		sqlrun("COMMIT");                                                    // Potvrzení transakce zápisu
		return $orig_guid_raw;                                               // Vrácení originálu uloženého záznamu
	}

	/**
	 * Odstraní rozpracovaný nebo vrácený koncept ('D') přihlášeného uživatele
	 * bez náhrady a bez zápisu do historie ('H').
	 *
	 * @param string $original_guid UUID originálu záznamu
	 */
	public function delete_draft(string $original_guid): void {              // Smazání konceptu uživatele podle original
		if (!$this->is_initialized OR trim($original_guid) === '') {         // Kontrola platného vstupu
			return;                                                          // Ukončení při prázdném identifikátoru
		}

		global $dbsession;                                                   // Globální kontext relace
		$org_uuid_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál organizace
		$user_acc_sql = guidliteral((string)($dbsession['user_account'] ?? '0x00')); // SQL literál účtu uživatele
		$lang_sql = charliteral((string)($dbsession['language'] ?? 'cs'));   // SQL literál jazyka relace
		$orig_sql = guidliteral($original_guid);                             // SQL literál mazaného originálu
		$table = $this->storage_table;                                       // Fyzická tabulka entity

		sqlrun("
			DELETE FROM {$table}
			WHERE original = {$orig_sql}
			  AND object_owner = {$org_uuid_sql}
			  AND record_type = 'D'
			  AND [language] = {$lang_sql}
			  AND (draft_author = {$user_acc_sql} OR draft_author = 0x00)
		");                                                                  // Fyzické odstranění konceptu z DB
	}

	/**
	 * Schválí vybraný návrh (`record_type = 'D'`) identifikovaný svým primárním klíčem `uuid`.
	 * - U zcela nového záznamu přepíše `who_modified` -> `who_created` a `date_modified` -> `date_created`,
	 *   aby byl původní autor návrhu evidován jako tvůrce, zatímco `who_modified` a `date_modified`
	 *   jdou za schvalovatelem.
	 * - U změny existujícího záznamu zachová původní `who_created` a `date_created` a zaktualizuje
	 *   `who_modified` a `date_modified` na schvalovatele.
	 * - Všechny ostatní návrhy (`record_type = 'D'`) pro stejný `(original, object_owner, language)`
	 *   automaticky odmítne (`approval_status = 'R'`) s poznámkou v `approval_note`.
	 *
	 * @param string $draft_uuid Primární klíč (`uuid`) schvalovaného řádku s `record_type = 'D'`
	 */
	public function approve_draft(string $draft_uuid): void {                // Schválení vybraného návrhu
		if (!$this->is_initialized OR trim($draft_uuid) === '') {            // Kontrola inicializace a platného UUID
			return;                                                          // Ukončení při chybějícím UUID návrhu
		}

		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$approver_session_sql = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$right_translate = !empty($dbsession['right_translate']);            // Oprávnění ke globálnímu překladu
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid);                          // SQL literál primárního klíče návrhu

		// 1. Načtení schvalovaného návrhu ('D')
		$q_dr = sqlrun("SELECT * FROM {$table} WHERE uuid = {$draft_uuid_sql} AND record_type = 'D' AND removed = 0"); // Dotaz na návrh
		$draft_row = fetch($q_dr);                                           // Data schvalovaného návrhu
		free_result($q_dr);                                                  // Uvolnění dotazu návrhu

		if (!$draft_row) {                                                   // Pokud návrh nebyl nalezen
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
		$is_final_class = (!$is_sys_owner AND !empty($this->class_meta['is_final'])); // Zda třída zakazuje A override tenantovi

		// 2. Zjištění existence schváleného 'A' záznamu
		$q_a = sqlrun("SELECT * FROM {$table} WHERE original = {$orig_sql} AND record_type = 'A' AND removed = 0 AND object_owner IN ({$owner_sql}, 0x00) ORDER BY object_owner DESC"); // Hledání schváleného A záznamu
		$existing_a = fetch($q_a);                                           // Nalezený schválený A záznam
		free_result($q_a);                                                   // Uvolnění dotazu A záznamu

		$own_a_exists = ($existing_a AND ((string)$existing_a['object_owner'] === $owner_raw OR $is_sys_owner)); // Zda má vlastník vlastní A záznam
		$a_lang_raw = $existing_a ? (string)$existing_a['language'] : $draft_lang_raw; // Mateřský jazyk A záznamu
		$is_native_lang = ($a_lang_raw === $draft_lang_raw);                 // Zda je návrh v mateřském jazyce záznamu

		$skip_data_cols = [                                                  // Technické sloupce, které se nekopírují jako běžná data
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note', 'language',
			'date_created', 'who_created', 'date_modified', 'who_modified'
		];                                                                   // Konec seznamu vynechaných sloupců

		sqlrun("BEGIN TRAN");                                                // Zahájení transakce schválení

		// 3. Zápis do schváleného 'A' záznamu (pokud třída není pro tenanta uzamčena přes is_final)
		if (!$is_final_class) {                                              // Pokud je povolen zápis do 'A' vrstvy
			if ($own_a_exists) {                                             // UPDATE existujícího 'A' záznamu (date_created a who_created se NEMĚNÍ!)
				$a_uuid_sql = guidliteral((string)$existing_a['uuid']);      // Primární klíč existujícího A záznamu
				$set_a = [];                                                 // Pole změn pro UPDATE A záznamu

				foreach ($this->physical_cols as $col) {                     // Průchod fyzickými sloupci tabulky
					if (in_array($col, $skip_data_cols, true)) {             // Přeskočení technických sloupců
						continue;                                            // Pokračování na další sloupec
					}
					$is_trans = !empty($this->columns_meta[$col]['translate']); // Zda je sloupec překládaný
					if ($is_trans AND !$is_native_lang) {                    // Ochrana mateřského jazyka v A záznamu
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
				$ins_cols = [];                                              // Sloupce pro INSERT nového A záznamu
				$sel_vals = [];                                              // Výrazy v SELECT klauzuli z návrhu

				foreach ($this->physical_cols as $col) {                     // Sestavení sloupců pro nový A záznam
					$ins_cols[] = "[$col]";                                  // Zařazení fyzického sloupce
					if ($col === 'uuid') {                                   // Primární klíč nového A záznamu
						$sel_vals[] = ($existing_a ? "NEWID()" : "original"); // Pro zcela nový záznam uuid = original
					} elseif ($col === 'object_owner') {                     // Vlastník záznamu
						$sel_vals[] = $owner_sql;                            // Vlastník návrhu
					} elseif ($col === 'original') {                         // Originál záznamu
						$sel_vals[] = "original";                            // Originál z návrhu
					} elseif ($col === 'record_type') {                      // Typ záznamu
						$sel_vals[] = "'A'";                                 // Schválený záznam 'A'
					} elseif ($col === 'approval_status') {                  // Stav schválení
						$sel_vals[] = "'A'";                                 // Schválený stav 'A'
					} elseif ($col === 'draft_author') {                     // Autor konceptu
						$sel_vals[] = "0x00";                                // U schváleného záznamu vždy 0x00
					} elseif ($col === 'approval_note') {                    // Poznámka schvalování
						$sel_vals[] = "''";                                  // U schváleného záznamu prázdná
					} elseif ($col === 'date_created') {                     // Datum vytvoření (z návrhu autora)
						$sel_vals[] = $author_date_sql;                      // Datum postoupení návrhu autorem
					} elseif ($col === 'who_created') {                      // Autor vytvoření (z návrhu autora)
						$sel_vals[] = $author_session_sql;                   // Relace původního autora návrhu
					} elseif ($col === 'date_modified') {                    // Datum schválení
						$sel_vals[] = "GETDATE()";                           // Okamžik schválení
					} elseif ($col === 'who_modified') {                     // Schvalovatel
						$sel_vals[] = $approver_session_sql;                 // Relace schvalovatele
					} else {
						$sel_vals[] = "[$col]";                              // Hodnota datového sloupce z návrhu
					}
				}

				$sql_ins_a = "INSERT INTO {$table} (" . implode(', ', $ins_cols) . ") \nSELECT " . implode(', ', $sel_vals) . " \nFROM {$table} \nWHERE uuid = {$draft_uuid_sql}"; // SQL INSERT A
				sqlrun($sql_ins_a);                                          // Založení schváleného A záznamu
			}
		}

		// 4. Zápis do symetrického 'L' záznamu pro jazyk návrhu
		$l_owner_sql = $owner_sql;                                           // Vlastník jazykové mutace
		if ($existing_a AND ((string)$existing_a['object_owner'] === '0x00' OR (string)$existing_a['object_owner'] === '00000000-0000-0000-0000-000000000000')) { // Pokud je A záznam systémový
			if ($right_translate) {                                          // Pokud má schvalovatel právo globálního překladu
				$l_owner_sql = '0x00';                                       // Globální systémový překlad
			}
		}

		$q_l = sqlrun("SELECT uuid FROM {$table} WHERE original = {$orig_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND [language] = {$draft_lang_sql} AND removed = 0"); // Kontrola existence L
		$existing_l = fetch($q_l);                                           // Nalezený L záznam
		free_result($q_l);                                                   // Uvolnění dotazu L záznamu

		if ($existing_l) {                                                   // UPDATE existujícího 'L' záznamu
			$l_uuid_sql = guidliteral((string)$existing_l['uuid']);          // Primární klíč L záznamu
			$set_l = [];                                                     // Pole změn pro UPDATE L záznamu

			foreach ($this->physical_cols as $col) {                         // Průchod fyzickými sloupci
				if (in_array($col, $skip_data_cols, true)) {                 // Přeskočení technických sloupců
					continue;                                                // Pokračování na další sloupec
				}
				$set_l[] = "[$col] = d.[$col]";                              // Převzetí hodnoty z návrhu d
			}

			$set_l[] = "approval_status = 'A'";                              // Schválený stav L záznamu
			$set_l[] = "draft_author = 0x00";                                // Vynulování autora konceptu
			$set_l[] = "approval_note = ''";                                 // Vyčištění poznámky
			$set_l[] = "date_modified = GETDATE()";                          // Datum schválení překladu
			$set_l[] = "who_modified = {$approver_session_sql}";             // Relace schvalovatele

			$sql_upd_l = "UPDATE l SET " . implode(', ', $set_l) . " FROM {$table} l JOIN {$table} d ON d.uuid = {$draft_uuid_sql} WHERE l.uuid = {$l_uuid_sql}"; // SQL UPDATE L
			sqlrun($sql_upd_l);                                              // Provedení UPDATE L záznamu
		} else {
			// INSERT nového 'L' záznamu (who_created = autor návrhu, who_modified = schvalovatel)
			$ins_cols_l = [];                                                // Sloupce pro nový L záznam
			$sel_vals_l = [];                                                // Výrazy v SELECT klauzuli pro L

			foreach ($this->physical_cols as $col) {                         // Sestavení sloupců pro nový L záznam
				$ins_cols_l[] = "[$col]";                                    // Zařazení fyzického sloupce
				if ($col === 'uuid') {                                       // Primární klíč L záznamu
					$sel_vals_l[] = "NEWID()";                               // Unikátní NEWID() pro L záznam
				} elseif ($col === 'object_owner') {                         // Vlastník L záznamu
					$sel_vals_l[] = $l_owner_sql;                            // Vlastník překladu
				} elseif ($col === 'original') {                             // Originál záznamu
					$sel_vals_l[] = "original";                              // Společný originál
				} elseif ($col === 'record_type') {                          // Typ záznamu
					$sel_vals_l[] = "'L'";                                   // Jazykový záznam 'L'
				} elseif ($col === 'approval_status') {                      // Stav schválení
					$sel_vals_l[] = "'A'";                                   // Schválený stav 'A'
				} elseif ($col === 'draft_author') {                         // Autor konceptu
					$sel_vals_l[] = "0x00";                                  // Vynulovaný autor konceptu
				} elseif ($col === 'approval_note') {                        // Poznámka schvalování
					$sel_vals_l[] = "''";                                    // Prázdná poznámka
				} elseif ($col === 'language') {                             // Jazyk překladu
					$sel_vals_l[] = $draft_lang_sql;                         // Kód jazyka z návrhu
				} elseif ($col === 'date_created') {                         // Datum vytvoření překladu
					$sel_vals_l[] = $author_date_sql;                        // Datum postoupení návrhu autorem
				} elseif ($col === 'who_created') {                          // Autor překladu
					$sel_vals_l[] = $author_session_sql;                     // Relace autora návrhu
				} elseif ($col === 'date_modified') {                        // Datum schválení
					$sel_vals_l[] = "GETDATE()";                             // Okamžik schválení
				} elseif ($col === 'who_modified') {                         // Schvalovatel
					$sel_vals_l[] = $approver_session_sql;                   // Relace schvalovatele
				} else {
					$sel_vals_l[] = "[$col]";                                // Datový sloupec z návrhu
				}
			}

			$sql_ins_l = "INSERT INTO {$table} (" . implode(', ', $ins_cols_l) . ") \nSELECT " . implode(', ', $sel_vals_l) . " \nFROM {$table} \nWHERE uuid = {$draft_uuid_sql}"; // SQL INSERT L
			sqlrun($sql_ins_l);                                              // Založení schváleného L záznamu
		}

		// Pokud šlo o překlad u třídy s is_final = 1 (kde se neměnil A záznam), zaktualizujeme alespoň audit na hlavním A záznamu
		if ($is_final_class AND $existing_a) {                               // Kontrola potřeby aktualizace auditu na A
			$a_uuid_sql = guidliteral((string)$existing_a['uuid']);          // UUID hlavního A záznamu
			sqlrun("UPDATE {$table} SET date_modified = GETDATE(), who_modified = {$approver_session_sql} WHERE uuid = {$a_uuid_sql}"); // Aktualizace auditu na A
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
			  AND removed = 0
		");                                                                  // Automatické odmítnutí ostatních návrhů

		sqlrun("COMMIT");                                                    // Potvrzení transakce schválení
	}

	/**
	 * Odmítne / vrátí k přepracování vybraný návrh (`record_type = 'D'`)
	 * a uloží k němu poznámku schvalovatele (`approval_note`).
	 * Původní `draft_author` zůstává zachován, takže se záznam vrátí svému autorovi.
	 *
	 * @param string $draft_uuid    Primární klíč (`uuid`) odmítaného návrhu
	 * @param string $approval_note Důvod vrácení / odmítnutí zadaný schvalovatelem
	 */
	public function reject_draft(string $draft_uuid, string $approval_note = ''): void { // Odmítnutí návrhu schvalovatelem
		if (!$this->is_initialized OR trim($draft_uuid) === '') {            // Kontrola platného vstupu
			return;                                                          // Ukončení při chybějícím UUID
		}

		global $dbsession;                                                   // Globální kontext relace schvalovatele
		$approver_session_sql = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid);                          // SQL literál UUID návrhu

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
			  AND removed = 0
		");                                                                  // Přepnutí návrhu do stavu 'R' (Vráceno)
	}
}