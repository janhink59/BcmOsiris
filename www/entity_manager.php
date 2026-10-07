<?php
/**
 * =============================================================================
 * Verze: 2026-10-07 (Aktualizace na STI architekturu - vazba sloupců na třídu)
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit pro čtení i autonomní zápis (STI Architektura).
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
 *    Pro překládaná pole (translate=1) se tvoří COALESCE, které propadává takto:
 *    Vlastní jazyková L mutace -> Systémová jazyková L mutace -> 
 *    Vlastní L mutace fallback jazyka -> Systémová L mutace fallback jazyka ->
 *    Vlastní A záznam -> Systémový A záznam (originál) -> Zděděná hodnota.
 * 
 * 4. Ochranné zámky (is_final a is_protected)
 *    - is_final: Je-li nastaveno na třídě, tenant (vyjma 0x00) NESMÍ vůbec 
 *      založit vlastní 'A' záznam (tzv. override). Může dělat jen 'L' překlady.
 *    - is_protected: Je-li nastaveno na sloupci, tenant NESMÍ tento sloupec
 *      přepsat. V SQL (při čtení) i v PHP (při zápisu) se tvrdě vynucuje 
 *      hodnota ze systémového originálu (0x00).
 * 
 * 5. Asymetrický zápis překladů (right_translate)
 *    Překlady do 'L' záznamů může dělat každý tenant. Pokud ale uživatel patří 
 *    k organizaci garantující překlad (translator_org) a má 'right_translate=1',
 *    jeho 'L' záznam získá object_owner=0x00 a stane se globálním překladem.
 *    Zároveň se kvůli symetrii k 'A' záznamu vždy zakládá paralelní 'L' záznam.
 * =============================================================================
 */

declare(strict_types=1);

class entity_manager {

	private string $class_name;
	private array $class_meta = [];
	private string $storage_table = '';
	private array $columns_meta = [];
	private array $list_columns = [];
	private bool $is_initialized = false;

	/**
	 * Konstruktor třídy.
	 * 
	 * @param string $class_name Identifikátor logické třídy z DB (např. 'asset_class')
	 */
	public function __construct(string $class_name) {
		$this->class_name = $class_name;
		$this->load_metadata();
	}

	/**
	 * Načte metadata logické třídy, identifikuje fyzickou tabulku 
	 * a načte definici sloupců včetně uplatnění pravidel dědičnosti.
	 */
	private function load_metadata(): void {
		$safe_class = charliteral($this->class_name);
		
		// 1. Načtení definice logické třídy a zjištění fyzické tabulky přes storage_object
		$sql_class = "
			SELECT 
				mc.*, 
				mo.builtin_code AS storage_table_name, 
				mo.original AS storage_original
			FROM meta_class mc
			JOIN meta_object mo ON mo.original = mc.storage_object AND mo.record_type = 'A' AND mo.removed = 0
			WHERE mc.class_name = {$safe_class} AND mc.record_type = 'A' AND mc.object_owner = 0x00 AND mc.removed = 0
		";
		
		$q_class = sqlrun($sql_class);
		if ($row = fetch($q_class)) {
			$this->class_meta = $row;
			$this->storage_table = $row['storage_table_name'];
			$storage_uuid = guidliteral($row['storage_original']);
			$class_uuid = guidliteral($row['original']);
			free_result($q_class);
			
			// 2. Načtení sloupců patřících k fyzické tabulce vč. dědičnosti (LEFT JOIN na ancestor)
			$sql_cols = "
				SELECT 
					c.*, 
					a.list_order AS anc_list_order,
					a.caption AS anc_caption, 
					a.caption_plural AS anc_caption_plural, 
					a.description AS anc_description, 
					a.label AS anc_label, 
					a.header AS anc_header,
					a.helptext AS anc_helptext,
					a.placeholder AS anc_placeholder,
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
					a.is_protected AS anc_is_protected
				FROM meta_column c
				LEFT JOIN meta_column a ON a.original = c.ancestor AND a.record_type = 'A' AND a.object_owner = 0x00 AND a.removed = 0
				WHERE c.parent_class = {$class_uuid} 
				  AND c.record_type = 'A' 
				  AND c.object_owner = 0x00 
				  AND c.removed = 0 
				ORDER BY c.parent_order, c.sort_code
			";
			
			$q_cols = sqlrun($sql_cols);
			$list_cols_temp = [];

			while ($col = fetch($q_cols)) {
				// Seznam vlastností, které se automaticky dědí z nadřízeného sloupce v globálním slovníku
				$inherited_props = [
					'list_order', 'caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder', 
					'input_type', 'input_width', 'input_rows', 'max_length', 'css_class', 'translate', 'history', 
					'is_html', 'is_mandatory', 'is_url', 'is_computed', 'show_empty', 'hidden', 'customizable', 
					'referenced_codetable', 'referenced_class', 'is_protected'
				];
				
				foreach ($inherited_props as $prop) {
					// Pokud je lokální hodnota u tenanta NULL, převezmeme hodnotu od předka
					if ($col[$prop] === null and isset($col["anc_$prop"])) {
						$col[$prop] = $col["anc_$prop"];
					}
					
					// Speciální ošetření pro stringové vlastnosti, které by mohly mít výchozí hodnotu '' místo NULL
					if ($prop === 'referenced_codetable' or $prop === 'input_type') {
						if ($col[$prop] === '' and !empty($col["anc_$prop"])) {
							$col[$prop] = $col["anc_$prop"];
						}
					}
				}
				
				$this->columns_meta[$col['column_name']] = $col;

				// Příprava dat pro Master (levý) panel podle zjištěného pořadí (list_order)
				if ($col['list_order'] !== null) {
					$header_val = $col['header'] ?: $col['caption'];
					$list_cols_temp[(int)$col['list_order']] = [
						'name' => $col['column_name'],
						'header' => $header_val ?: $col['column_name']
					];
				}
			}
			free_result($q_cols);
			
			// Seřazení sloupců levého panelu dle 'list_order'
			if (!empty($list_cols_temp)) {
				ksort($list_cols_temp);
				foreach ($list_cols_temp as $lc) {
					$this->list_columns[$lc['name']] = $lc['header'];
				}
			} else {
				// Bezpečnostní fallback: Pokud nejsou definovány list_order sloupce, vezmeme první smysluplný textový sloupec
				$fallback_candidates = ['caption', 'name', 'code', 'builtin_code'];
				foreach ($fallback_candidates as $fc) {
					if (isset($this->columns_meta[$fc])) {
						$col = $this->columns_meta[$fc];
						$header_val = $col['header'] ?: $col['caption'];
						$this->list_columns[$fc] = $header_val ?: $col['column_name'];
						break;
					}
				}
			}
			
			$this->is_initialized = true;
		}
	}

	/**
	 * Vrátí kompletní metadatový záznam celé logické třídy.
	 */
	public function get_class_meta(): array {
		return $this->class_meta;
	}

	/**
	 * Vrátí metadata jednoho konkrétního sloupce.
	 */
	public function get_column_meta(string $column_name): array {
		return $this->columns_meta[$column_name] ?? [];
	}

	/**
	 * Získá seznam všech definovaných sloupců entity pro iterace při generování formuláře.
	 */
	public function get_columns(): array {
		return $this->columns_meta;
	}

	/**
	 * Získá asociační pole sloupců určených pro Master panel seřazených dle list_order.
	 */
	public function get_list_columns(): array {
		return $this->list_columns;
	}
	
	/**
	 * Umožňuje z nadřízené třídy ručně přepsat sloupce zobrazené v levém panelu,
	 * čímž se obejde defaultní definice z metadat.
	 */
	public function set_list_columns(array $columns): void {
		$this->list_columns = $columns;
	}

	/**
	 * T-SQL KOUZLO: Vygeneruje dynamický dotaz nahrazující původní statické vrepo_*.
	 * Tento dotaz si databáze zkompiluje ad-hoc a využije pro něj optimální indexy.
	 * 
	 * Logika a architektura dotazu:
	 * 1. Pomocí CTE bloků (s, sy, my, mix) sjednotí systémová a tenant data do jedné množiny.
	 * 2. Implementuje tvrdou ochranu (is_protected) - vyřadí z výběru data tenanta u chráněných sloupců.
	 * 3. Pomocí masivního COALESCE skládá konečnou hodnotu překládaných (NVARCHAR) polí 
	 *    kaskádovým fallbackem přes všechny dostupné jazykové mutace a předky.
	 * 
	 * @param string $where Volitelná WHERE podmínka pro dotaz
	 * @param string $order_by Volitelné řazení. Pokud prázdné, odvodí se z list_order.
	 * @return string T-SQL dotaz připravený ke spuštění (sqlrun)
	 */
	public function build_select_query(string $where = '', string$order_by = ''): string {
		if (!$this->is_initialized) {
			fatal_error("Entity manager", "Metadata pro logickou třídu '{$this->class_name}' nebyla nalezena.");
		}

		$table = $this->storage_table;
		$select_list = "";
		
		// Seznam technických RAC sloupců, na které se neaplikuje COALESCE fallback ani dědičnost
		$meta_columns_list = [
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'language', 'inactive', 'removed', 'valid_from', 'valid_to', 
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified', 'import_origin'
		];
		
		$has_ancestor = isset($this->columns_meta['ancestor']);

		// Sestavení seznamu tabulkových aliasů, abychom našli to nevyšší (nejnovější) datum 
		// úpravy napříč všemi vrstvami a jazyky.
		$mod_aliases = ['m', 'o'];
		$has_trans = false;
		foreach ($this->columns_meta as $meta) {
			if (!empty($meta['translate'])) {
				$has_trans = true;
				break;
			}
		}
		if ($has_trans) {
			array_push($mod_aliases, 'l', 'v', 'l_fall', 'v_fall');
		}
		if ($has_ancestor) {
			array_push($mod_aliases, 'anc');
			if ($has_trans) {
				array_push($mod_aliases, 'anc_l', 'anc_v', 'anc_l_fall', 'anc_v_fall');
			}
		}

		// Poskládání T-SQL klauzule pro získání globálního data úpravy řádku
		$values_arr = [];
		foreach ($mod_aliases as $al) {
			$values_arr[] = "({$al}.date_modified, {$al}.who_modified)";
		}
		$values_str = implode(', ', $values_arr);
		
		$cross_apply = "
		OUTER APPLY (
			SELECT TOP 1 d_mod, w_mod 
			FROM (VALUES {$values_str}) AS mods(d_mod, w_mod) 
			WHERE d_mod IS NOT NULL 
			ORDER BY d_mod DESC
		) AS last_mod";

		// Průchod sloupci a sestavení klauzule SELECT na základě jejich překladových a bezpečnostních vlastností
		foreach ($this->columns_meta as $colname => $meta) {
			// Datum modifikace a autora převezmeme z našeho dynamického kalkulátoru nejmladšího záznamu
			if ($colname === 'date_modified') {
				$select_list .= "\n\t\t, last_mod.d_mod AS [date_modified]";
				continue;
			}
			if ($colname === 'who_modified') {
				$select_list .= "\n\t\t, last_mod.w_mod AS [who_modified]";
				continue;
			}

			if (in_array($colname, $meta_columns_list, true)) {
				// Technické RAC sloupce bereme přímo z vyhodnoceného mixu (m)
				$select_list .= "\n\t\t, m.[{$colname}]";
				continue;
			}
			
			$translate = (bool)$meta['translate'];
			$is_protected = !empty($meta['is_protected']);
			// U stringových a textových polí musíme dělat při skládání COALESCE přetypování na NVARCHAR(MAX),
			// jinak by databáze hlásila chybu na neshodu délek (prec) varcharů.
			$is_string = $translate or in_array($meta['input_type'], ['text', 'textarea', null, ''], true);
			
			// Sestavení základního fallbacku pro 'A' záznam (Tenant vs Systém vs Předek)
			$base_coal = [];
			if (!$is_protected) {
				$base_coal[] = "m.[{$colname}]";                                  // Tenant může ovlivnit hodnotu (pokud není chráněná)
			}
			$base_coal[] = "o.[{$colname}]";                                      // Systémový originál (0x00)
			if ($has_ancestor) {
				$base_coal[] = "anc.[{$colname}]";                                // Zděděná hodnota z předka
			}

			if ($is_string) {
				$coal = [];
				if ($translate) {
					// 1. Lokalizace: Cizí jazyky mají absolutní přednost před základními daty
					$coal[] = "NULLIF(CAST(v.[{$colname}] AS NVARCHAR(MAX)), '')";      // Tenantův override ve zvoleném jazyce
					$coal[] = "NULLIF(CAST(l.[{$colname}] AS NVARCHAR(MAX)), '')";      // Systémový překlad ve zvoleném jazyce
					$coal[] = "NULLIF(CAST(v_fall.[{$colname}] AS NVARCHAR(MAX)), '')"; // Tenantův překlad ve fallback jazyce
					$coal[] = "NULLIF(CAST(l_fall.[{$colname}] AS NVARCHAR(MAX)), '')"; // Systémový překlad ve fallback jazyce
				}
				
				// 2. Primární data: Propadnutí na základní 'A' záznamy (do kterých se propisuje rodný jazyk entity)
				foreach ($base_coal as $b) {
					$coal[] = "NULLIF(CAST({$b} AS NVARCHAR(MAX)), '')";
				}
				
				// 3. Fallback dědičnosti překladů: Zkusíme vytáhnout jazykové mutace od předka
				if ($has_ancestor && $translate) {
					$coal[] = "NULLIF(CAST(anc_v.[{$colname}] AS NVARCHAR(MAX)), '')";
					$coal[] = "NULLIF(CAST(anc_l.[{$colname}] AS NVARCHAR(MAX)), '')";
					$coal[] = "NULLIF(CAST(anc_v_fall.[{$colname}] AS NVARCHAR(MAX)), '')";
					$coal[] = "NULLIF(CAST(anc_l_fall.[{$colname}] AS NVARCHAR(MAX)), '')";
				}
				
				$coal[] = "''"; // Nejzazší nouzový případ, nevracíme NULL.
				$coalesce_str = implode(", ", $coal);
				$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]";
				
				// Pro diagnostiku a editor na frontendu vždy vracíme i čisté rozpadlé hodnoty
				if ($translate) {
					$select_list .= "\n\t\t, CAST(l.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_translated]";
					$select_list .= "\n\t\t, CAST(m.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_original]";
					$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]";
				}
			} else {
				// Netextové sloupce (čísla, bity, uuid) se nestringují, COALESCE je tak bezpečný.
				$coalesce_str = implode(", ", $base_coal);
				$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]";
			}
		}
		
		// Odstranění první oddělovací čárky z řetězce
		$select_list = substr($select_list, 4);
		// Příznak, zda výsledek (byť vznikl COALESCÍM z vícero zdrojů) obsahuje zásah tenanta v 'A' vrstvě
		$select_list .= "\n\t\t, m.object_is_mine";
		
		// Dynamické připojení zformátovaných informací o uživatelích pro zobrazení auditní stopy
		$select_list .= "\n\t\t, dbo.f_get_user_info(m.who_created) AS [who_created_info]";
		$select_list .= "\n\t\t, dbo.f_get_user_info(last_mod.w_mod) AS [who_modified_info]";

		// JOINy: Složité pole LEFT JOINŮ pro načtení všech jazykových vrstev 
		// s ohledem na aktuální dbsession.language a language.fallback_language
		$joins = "
		FROM s
		CROSS JOIN mix m
		LEFT JOIN {$table} o ON o.original = m.original AND o.object_owner = 0x00 AND o.record_type = 'A'
		LEFT JOIN {$table} l ON l.original = m.original AND l.object_owner = 0x00 AND l.language = s.language AND l.record_type = 'L' AND l.removed = 0
		LEFT JOIN {$table} v ON v.original = m.original AND v.object_owner = s.organization_uuid AND v.language = s.language AND v.record_type = 'L' AND v.removed = 0
		LEFT JOIN {$table} l_fall ON l_fall.original = m.original AND l_fall.object_owner = 0x00 AND l_fall.language = s.fallback_language AND l_fall.record_type = 'L' AND l_fall.removed = 0
		LEFT JOIN {$table} v_fall ON v_fall.original = m.original AND v_fall.object_owner = s.organization_uuid AND v_fall.language = s.fallback_language AND v_fall.record_type = 'L' AND v_fall.removed = 0
		";

		// Totéž i pro tabulku předka
		if ($has_ancestor) {
			$joins .= "
		LEFT JOIN {$table} anc ON anc.original = m.ancestor AND anc.record_type = 'A' AND anc.object_owner = 0x00
		LEFT JOIN {$table} anc_l ON anc_l.original = m.ancestor AND anc_l.record_type = 'L' AND anc_l.language = s.language AND anc_l.object_owner = 0x00 AND anc_l.removed = 0
		LEFT JOIN {$table} anc_v ON anc_v.original = m.ancestor AND anc_v.record_type = 'L' AND anc_v.language = s.language AND anc_v.object_owner = s.organization_uuid AND anc_v.removed = 0
		LEFT JOIN {$table} anc_l_fall ON anc_l_fall.original = m.ancestor AND anc_l_fall.record_type = 'L' AND anc_l_fall.language = s.fallback_language AND anc_l_fall.object_owner = 0x00 AND anc_l_fall.removed = 0
		LEFT JOIN {$table} anc_v_fall ON anc_v_fall.original = m.ancestor AND anc_v_fall.record_type = 'L' AND anc_v_fall.language = s.fallback_language AND anc_v_fall.object_owner = s.organization_uuid AND anc_v_fall.removed = 0
		";
		}

		$joins .= $cross_apply;

		// Sestavení CTE bloku (Common Table Expressions) s dynamickými dotazy
		$sql = "
		WITH s AS (
			-- Výběr aktuálního kontextu relace z dbsession a vytažení fallback jazyka z číselníku
			SELECT 
				db.organization AS organization_uuid, 
				db.language, 
				lang.fallback_language
			FROM dbsession db
			LEFT JOIN language lang ON lang.language = db.language
			WHERE db.spid = @@SPID
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
			SELECT sy.* 
			FROM sy LEFT JOIN my ON my.original = sy.original
			WHERE sy.removed = 0 AND my.original IS NULL
			UNION ALL
			SELECT * FROM my
		)
		SELECT {$select_list}
		{$joins}
		";

		// Aplikace filtrů na finální datovou množinu
		if ($where !== '') {
			$sql .= "\n\t\tWHERE {$where}";
		}

		// Automatické odvození klauzule ORDER BY
		if ($order_by !== '') {
			$sql .= "\n\t\tORDER BY {$order_by}";
		} elseif (!empty($this->list_columns)) {
			$order_cols = [];
			foreach (array_keys($this->list_columns) as $col) {
				$order_cols[] = "[{$col}]";
			}
			$sql .= "\n\t\tORDER BY " . implode(', ', $order_cols);
		}

		return $sql;
	}

	/**
	 * Dynamický HTML generátor formulářových prvků na základě metadat v DB.
	 * Zajišťuje vizuální vykreslení datových typů, maximálních délek a zamykání polí.
	 * 
	 * @param string $column_name Název sloupce (klíč v databázi, např. 'caption')
	 * @param string $value Aktuální hodnota k zobrazení
	 * @param bool $is_mine Příznak, zda tenant vytvořil pro tento záznam svůj vlastní 'A' override
	 * @return string Vygenerovaný HTML string (např. tag <input> nebo <select>)
	 */
	public function render_dynamic_input(string $column_name, string $value, bool $is_mine = true): string {
		$meta = $this->get_column_meta($column_name);
		
		if (empty($meta)) {
			return "<!-- Neznámý sloupec: {$column_name} -->";
		}

		$type = $meta['input_type'] ?: 'text';
		$safe_name = htmlspecialchars($column_name);
		$safe_val = htmlspecialchars($value);
		
		// Sestavení vizuálních a HTML5 validačních atributů
		$attrs = [];
		if (!empty($meta['css_class'])) {
			$attrs[] = "class=\"" . htmlspecialchars((string)$meta['css_class']) . "\"";
		}
		if (!empty($meta['placeholder'])) {
			$attrs[] = "placeholder=\"" . htmlspecialchars((string)$meta['placeholder']) . "\"";
		}
		if (!empty($meta['max_length'])) {
			$attrs[] = "maxlength=\"{$meta['max_length']}\"";
		}
		if (!empty($meta['is_mandatory'])) {
			$attrs[] = "required";
		}
		
		// Zpracování oprávnění k editaci na frontendu
		// POZOR: Původní blokování polí s 'translate=1' na základě oprávnění bylo zrušeno.
		// Překládat do UI smí kdokoliv (pro svůj tenant). Zda se to uloží pro 0x00 se řeší až v zápisu.
		$is_readonly = false;
		
		if (!empty($meta['is_computed'])) {
			$is_readonly = true;
		} elseif (!$is_mine and !empty($meta['is_protected'])) {
			$is_readonly = true;
		} 
		
		$input_width = $meta['input_width'] ?: '100%';
		
		// Aplikace stylů pro zamčená i odemčená pole
		if ($is_readonly) {
			$attrs[] = "readonly style=\"background-color: #f4f4f4; width: {$input_width};\"";
			if ($type === 'checkbox') {
				// Checkboxy nemají nativní attribut 'readonly', používá se 'disabled'
				$attrs[] = "disabled";
			}
		} else {
			$attrs[] = "style=\"width: {$input_width};\"";
		}

		$attr_string = implode(' ', $attrs);

		// Generování <select> seznamů pro číselníky napojené v metadatech (STI)
		if (!empty($meta['referenced_codetable'])) {
			$options_html = '<option value="">--- Vyberte ---</option>';
			$safe_ct = charliteral($meta['referenced_codetable']);
			$q_opt = sqlrun("SELECT value_code, caption FROM meta_codetable WHERE codetable_name = {$safe_ct} AND record_type = 'A' AND removed = 0 ORDER BY sort_code, caption");
			
			while ($opt = fetch($q_opt)) {
				$sel = ($opt['value_code'] === $value) ? 'selected' : '';
				$options_html .= "<option value=\"" . htmlspecialchars((string)$opt['value_code']) . "\" {$sel}>" . htmlspecialchars((string)$opt['caption']) . "</option>";
			}
			
			free_result($q_opt);
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>";
		}

		// Výběr správného prvku podle 'input_type' uloženého v databázi
		switch ($type) {
			case 'textarea':
				$rows = !empty($meta['input_rows']) ? "rows=\"{$meta['input_rows']}\"" : "rows=\"3\"";
				return "<textarea name=\"{$safe_name}\" {$rows} {$attr_string}>{$safe_val}</textarea>";
				
			case 'checkbox':
				$checked = '';
				if ($value === '1' or strtolower($value) === 'true') {
					$checked = 'checked';
				}
				
				if ($is_readonly) {
					// Zamčené checkboxy se neodesílají při POSTu. Podvrhujeme proto systémový stav 
					// přes hidden pole, aby nedošlo k falešnému zahození záznamu.
					$real_val = ($checked !== '') ? '1' : '0';
					return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$real_val}\">\n\t\t\t\t\t\t<input type=\"checkbox\" name=\"{$safe_name}\" value=\"1\" {$checked} {$attr_string}>";
				}
				
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"0\">\n\t\t\t\t\t\t<input type=\"checkbox\" name=\"{$safe_name}\" value=\"1\" {$checked} {$attr_string}>";
				
			case 'date':
				return "<input type=\"date\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>";
				
			case 'number':
				return "<input type=\"number\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>";
				
			case 'text':
			default:
				$inputType = !empty($meta['is_url']) ? 'url' : 'text';
				return "<input type=\"{$inputType}\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>";
		}
	}

	/**
	 * Získání, očištění a sanitizace odeslaných POST dat.
	 * Přebírá hodnoty z $_POST, ověřuje s metadaty a balí je do bezpečných SQL literálů.
	 */
	public function extract_post_data(): array {
		$data = [];
		// Ignorujeme technické parametry (o ty se stará save_post_data autonomně)
		$meta_columns_list = [
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'language', 'inactive', 'removed', 'valid_from', 'valid_to', 
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified', 'import_origin'
		];
		
		foreach ($this->columns_meta as $colname => $meta) {
			if (!empty($meta['is_computed']) || in_array($colname, $meta_columns_list, true)) {
				continue;
			}
			
			// Nativní chování HTML formulářů u checkboxů (neodesílá se, pokud není zaškrtnuto)
			if (!isset($_POST[$colname]) and $meta['input_type'] === 'checkbox') {
				$data[$colname] = 0;
				continue;
			}
			
			if (!isset($_POST[$colname])) {
				continue;
			}

			$raw_val = (string)$_POST[$colname];

			// Převody typů pro bezpečný T-SQL zápis
			if ($meta['input_type'] === 'checkbox') {
				if ($raw_val === '1' or strtolower($raw_val) === 'true') {
					$data[$colname] = 1;  
				} else {
					$data[$colname] = 0;  
				}  
			} elseif ($meta['input_type'] === 'number') {
				if ($raw_val === '') {
					$data[$colname] = 'NULL';
				} else {
					$data[$colname] = (float)$raw_val;
				}
			} elseif (!empty($meta['referenced_codetable']) or !empty($meta['referenced_class'])) {
				// Pokud napojený číselník používá UUID klíče, přehodíme literál z textu na GUID
				if ($raw_val === '') {
					$data[$colname] = 'NULL';
				} else {
					if (preg_match('/^[a-f0-9]{8}-/i', $raw_val)) {
						$data[$colname] = guidliteral($raw_val);
					} else {
						$data[$colname] = charliteral($raw_val);
					}
				}
			} else {
				$data[$colname] = charliteral($raw_val);
			}
		}
		
		return $data;
	}

	/**
	 * JÁDRO BACKENDU: Provede autonomní asymetrický zápis rozparsovaných dat.
	 * 
	 * 1. Zjistí aktuální oprávnění ze session (right_translate) a master data.
	 * 2. Zfiltruje chráněná pole (`is_protected`), do kterých tenant nesmí zapisovat.
	 * 3. Uloží nepřevezená data do 'A' záznamu (tvorba nebo aktualizace overridu).
	 * 4. Vyčlení přeložená data (`translate=1`) a zapíše je do paralelního 'L' záznamu, 
	 *    aby udržel konzistentní symetrii schématu. Záznamu L určí vlastníka (`0x00` vs `tenant_uuid`)
	 *    podle systémového oprávnění `right_translate`.
	 * 
	 * @param string $update_guid Originální UUID záznamu (Prázdné pro INSERT)
	 */
	public function save_post_data(string $update_guid = ''): void {
		if (!$this->is_initialized) {
			return;
		}

		$post_data = $this->extract_post_data();
		if (empty($post_data)) {
			return;
		}

		// 1. Zjištění kontextu přihlášeného uživatele a organizace (Tenanta)
		$q_session = sqlrun("SELECT organization, user_access_uuid, language, right_translate FROM dbsession WHERE spid = @@SPID");
		$session = fetch($q_session);
		free_result($q_session);

		if (!$session) {
			fatal_error("Uložení selhalo", "Nepodařilo se načíst kontext uživatele z dbsession.");
		}

		// Převod identity uživatele na SQL literály pro auditní stopu a filtry
		$org_uuid = guidliteral($session['organization']);
		$user_uuid = guidliteral($session['user_access_uuid']);
		$lang_literal = charliteral($session['language']);
		$sess_lang_raw = $session['language'];
		$right_translate = !empty($session['right_translate']);
		
		$table = $this->storage_table;

		// 2. Získání skutečných fyzických sloupců z databáze
		// Vyloučením 'iscomputed' a 'is_identity' zabráníme SQL chybám při zápisu (nelze vkládat do identity)
		$q_cols = sqlrun("SELECT colname, typename FROM v_syscolumns WHERE tabname = " . charliteral($table) . " AND iscomputed = 0 AND is_identity = 0");
		$physical_cols = [];
		$col_types = [];
		while ($c = fetch($q_cols)) {
			$physical_cols[] = $c['colname'];
			$col_types[$c['colname']] = $c['typename'];
		}
		free_result($q_cols);

		$orig_guid = ($update_guid === '') ? '' : guidliteral($update_guid);

		// 3. Zjištění vlastníka a master jazyka původního 'A' záznamu
		$a_exists = false;
		$a_uuid = '';
		$a_lang_raw = $sess_lang_raw; // Výchozí pro zcela nový záznam
		$orig_owner = $org_uuid;

		if ($orig_guid !== '') {
			$q_check = sqlrun("SELECT uuid, language, object_owner FROM {$table} WHERE original = {$orig_guid} AND record_type = 'A' AND removed = 0 AND (object_owner = {$org_uuid} OR object_owner = 0x00) ORDER BY object_owner DESC");
			if ($row = fetch($q_check)) {
				// Vyhodnocení, zda se mění vlastní záznam, nebo se kopíruje systémový originál
				$a_exists = ((string)$row['object_owner'] === (string)$session['organization'] || $org_uuid === '0x00');
				$orig_owner = guidliteral($row['object_owner']);
				$a_uuid = guidliteral($row['uuid']);
				$a_lang_raw = $row['language'];
			}
			free_result($q_check);
		}

		// 4. Filtrace struktury: Rozdělení dat na 'A' (Základ) a 'L' (Lokalizace)
		$a_post_data = [];
		$l_post_data = [];
		$has_translated_cols = false;
		$is_native_lang = ($a_lang_raw === $sess_lang_raw);

		foreach ($post_data as $col => $val) {
			$is_translated = !empty($this->columns_meta[$col]['translate']);
			
			// BACKENDOVÁ POJISTKA (is_protected): Pokud se nejedná o sysadmina (0x00),
			// všechny chráněné sloupce vyhodíme. Ignorujeme i případné podvrhy přes HTTP nástroje.
			if ($org_uuid !== '0x00' && $org_uuid !== '00000000-0000-0000-0000-000000000000' && !empty($this->columns_meta[$col]['is_protected'])) {
				continue;
			}

			if ($is_translated) {
				$has_translated_cols = true;
				$l_post_data[$col] = $val;
				// OCHRANA ORIGINÁLU: Text, který je označen k překladu, zapíšeme do master 'A' 
				// záznamu POUZE pokud jazyk session sedí na výchozí "mateřský" jazyk entity.
				if ($is_native_lang) {
					$a_post_data[$col] = $val;
				}
			} else {
				// Číselná/Vazební data jdou do Master záznamu bez ohledu na jazyk vždy
				$a_post_data[$col] =$val; 
			}
		}

		// BACKENDOVÁ POJISTKA 2 (is_final): Pokud je celá třída nedotknutelná (číselníky),
		// tenantovi zamezíme jakémukoli vytváření vlastního 'A' overridu vymazáním polí.
		if ($org_uuid !== '0x00' &&$org_uuid !== '00000000-0000-0000-0000-000000000000' && !empty($this->class_meta['is_final'])) {$a_post_data = []; 
		}

		// Obalení operací transakcí, aby se zamezilo nekonzistentním zápisům L bez A.
		sqlrun("BEGIN TRAN");

		// 5. Zápis do 'A' záznamu (Správa Master dat a auditních stop)
		if ($orig_guid === '') {
			// A) INSERT: Zcela nová identita vytvářená uživatelem
			$new_uuid = "NEWID()";
			$insert_cols = [];$insert_vals = [];
			
			foreach ($physical_cols as$col) {
				if (in_array($col, ['uuid', 'original'], true)) {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$new_uuid;
				} elseif ($col === 'object_owner') {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$org_uuid;
				} elseif ($col === 'record_type') {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] = "'A'";
				} elseif ($col === 'language') {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$lang_literal;
				} elseif (in_array($col, ['date_created', 'date_modified'], true)) {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] = "GETDATE()";
				} elseif (in_array($col, ['who_created', 'who_modified'], true)) {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$user_uuid;
				} elseif (array_key_exists($col, $a_post_data)) {$val = $a_post_data[$col];
					// Ošetření chyby s ukládáním prázdných řetězců do UUID polí
					if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
					}
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$val;
				}
			}

			// Pro úspěšný zápis paralelního 'L' záznamu potřebujeme získat original.
			// Pošleme T-SQL konstrukci OUTPUT inserted.original, 
			// protože u deterministických triggerů určuje klíč až databáze (trgo_*).
			$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") OUTPUT inserted.original VALUES (" . implode(', ', $insert_vals) . ")";
			$q_ins = sqlrun($sql);
			if ($ins_row = fetch($q_ins)) {
				$orig_guid = guidliteral($ins_row['original']);
			}
			free_result($q_ins);
			
		} elseif (!empty($a_post_data)) {
			// B) UPDATE NEBO OVERRIDE 'A' ZÁZNAMU
			if ($a_exists) {
				// Tenant upravuje již svůj vlastní záznam
				$set_clauses = [];
				foreach ($a_post_data as $col =>$val) {
					if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
					}
					$set_clauses[] = "[$col] =$val";
				}
				// Zaktualizování auditní stopy bezpodmínečně
				$set_clauses[] = "date_modified = GETDATE()";
				$set_clauses[] = "who_modified = {$user_uuid}";

				$sql = "UPDATE {$table} SET " . implode(', ', $set_clauses) . " WHERE uuid = {$a_uuid}";
				sqlrun($sql);
			} else {
				// OVERRIDE: Tenant zasahuje do systémového záznamu poprvé.
				// Provedeme INSERT INTO ... SELECT, který zkopíruje všechna systémová 
				// (is_protected) data, ale nahradí je těmi lokálními uživatelskými.
				$insert_cols = [];$select_vals = [];
				
				foreach ($physical_cols as$col) {
					$insert_cols[] = "[$col]";
					
					if ($col === 'uuid') {$select_vals[] = "NEWID()";
					} elseif ($col === 'object_owner') {
						$select_vals[] =$org_uuid;
					} elseif ($col === 'record_type') {$select_vals[] = "'A'";
					} elseif (in_array($col, ['date_created', 'date_modified'], true)) {$select_vals[] = "GETDATE()";
					} elseif (in_array($col, ['who_created', 'who_modified'], true)) {
						$select_vals[] =$user_uuid;
					} elseif ($col === 'original') {$select_vals[] = "original"; 
					} elseif ($col === 'language') {$select_vals[] = "language"; // Mateřský jazyk dědíme od systému
					} elseif (array_key_exists($col, $a_post_data)) {$val = $a_post_data[$col];
						if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
						}
						$select_vals[] =$val; 
					} else {
						// Veškerá is_protected a nenaplněná data si propíše SQL ze starého záznamu
						$select_vals[] = "[$col]"; 
					}
				}

				$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") \nSELECT " . implode(', ', $select_vals) . " \nFROM {$table} \nWHERE original = {$orig_guid} AND object_owner = 0x00 AND record_type = 'A'";
				sqlrun($sql);
			}
		}

		// 6. Zápis 'L' záznamu (Zajištění asymetrického překladu a DB symetrie A-L)
		if ($has_translated_cols and$orig_guid !== '') {
			
			// VYHODNOCENÍ VLASTNICTVÍ (right_translate)
			// Uživatel si tvoří lokální překlad, ALE pokud má od administrátorů přidělené 
			// právo a zároveň překládá záznam, který patří celému systému (0x00),
			// pak i jeho 'L' záznam bude prohlášen za globální (0x00).
			$l_owner =$org_uuid;
			if ($orig_owner === '0x00' ||$orig_owner === '00000000-0000-0000-0000-000000000000') {
				if ($right_translate) {$l_owner = '0x00';
				}
			}

			$q_l_check = sqlrun("SELECT uuid FROM {$table} WHERE original = {$orig_guid} AND object_owner = {$l_owner} AND record_type = 'L' AND language = {$lang_literal} AND removed = 0");
			$l_exists = fetch($q_l_check);
			free_result($q_l_check);

			if ($l_exists) {
				// L-UPDATE: Mutace ve slovníku existuje, přepíšeme pouze nové texty
				if (!empty($l_post_data)) {$set_l = [];
					foreach ($l_post_data as $col =>$val) {
						if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
						}
						$set_l[] = "[$col] =$val";
					}
					$set_l[] = "date_modified = GETDATE()";
					$set_l[] = "who_modified = {$user_uuid}";
					
					$sql_l = "UPDATE {$table} SET " . implode(', ', $set_l) . " WHERE uuid = " . guidliteral($l_exists['uuid']);
					sqlrun($sql_l);
				}
			} else {
				// ZAJIŠTĚNÍ SYMETRIE: Vždy vložíme klon do 'L', aby paralelně existoval k 'A'.
				// To zamezí chybějícím spojením při LEFT JOINech v COALESCE konstrukci.
				$insert_cols_l = [];$select_vals_l = [];
				
				foreach ($physical_cols as$col) {
					$insert_cols_l[] = "[$col]";
					
					if ($col === 'uuid') {$select_vals_l[] = "NEWID()";
					} elseif ($col === 'object_owner') {
						$select_vals_l[] =$l_owner;
					} elseif ($col === 'record_type') {$select_vals_l[] = "'L'";
					} elseif ($col === 'language') {
						$select_vals_l[] =$lang_literal;
					} elseif (in_array($col, ['date_created', 'date_modified'], true)) {$select_vals_l[] = "GETDATE()";
					} elseif (in_array($col, ['who_created', 'who_modified'], true)) {
						$select_vals_l[] =$user_uuid;
					} elseif (array_key_exists($col, $l_post_data)) {$val = $l_post_data[$col];
						if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
						}
						$select_vals_l[] =$val; 
					} else {
						$select_vals_l[] = "[$col]"; 
					}
				}

				// Zdroj pro kopii 'L' záznamu čerpáme přednostně z vlastního (aktuálního) 'A' záznamu. 
				// Pokud si tenant override nedělal (protože je např. třída is_final), propadne čtení na originál (0x00).
				$source_owner_sql = ($org_uuid !== '0x00') ? "object_owner IN ({$org_uuid}, 0x00)" : "object_owner = 0x00";
				$sql_l = "INSERT INTO {$table} (" . implode(', ', $insert_cols_l) . ") \nSELECT TOP 1 " . implode(', ', $select_vals_l) . " \nFROM {$table} \nWHERE original = {$orig_guid} AND {$source_owner_sql} AND record_type = 'A' AND removed = 0 ORDER BY object_owner DESC";
				sqlrun($sql_l);
			}
		}

		sqlrun("COMMIT");
	}
}