<?php
/**
 * =============================================================================
 * Verze: 2026-10-08
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
 *    Pro překládaná pole (translate=1) se tvoří COALESCE, které propadává 
 *    přes všechny dostupné fallback jazyky definované v language_manager,
 *    následně přes vlastní/systémový originál a nakonec přes hodnoty předka.
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
 * 
 * 6. Klonování s modifikací (Override vzor)
 *    Při prvním zásahu tenanta do systémového záznamu se vytvoří kompletní fyzická kopie
 *    záznamu ('A' i 'L'), ve které se nahradí upravené hodnoty. Databáze tak obsahuje vždy 
 *    kompletní data bez nutnosti plošného využívání NULL.
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
	private language_manager $lang_manager;
	
	private array $physical_cols = [];
	private array $col_types = [];
	private array $col_nulls = [];

	/**
	 * Konstruktor třídy.
	 * 
	 * @param string $class_name Identifikátor logické třídy z DB (např. 'asset_class')
	 */
	public function __construct(string $class_name) {
		$this->class_name = $class_name;
		$this->lang_manager = new language_manager();
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
			$class_uuid = guidliteral($row['original']);
			free_result($q_class);
			
			// Načtení fyzického databázového schématu pro přesné parsování a validaci
			$q_syscols = sqlrun("SELECT colname, typename, nulls FROM v_syscolumns WHERE tabname = " . charliteral($this->storage_table) . " AND iscomputed = 0 AND is_identity = 0");
			while ($c = fetch($q_syscols)) {
				$this->physical_cols[] = $c['colname'];
				$this->col_types[$c['colname']] = $c['typename'];
				$this->col_nulls[$c['colname']] = strtolower(trim((string)$c['nulls']));
			}
			free_result($q_syscols);
			
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
					if ($col[$prop] === null && isset($col["anc_$prop"])) {
						$col[$prop] = $col["anc_$prop"];
					}
					
					// Speciální ošetření pro stringové vlastnosti, které by mohly mít výchozí hodnotu '' místo NULL
					if (($prop === 'referenced_codetable' || $prop === 'input_type') && $col[$prop] === '' && !empty($col["anc_$prop"])) {
						$col[$prop] = $col["anc_$prop"];
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
		$lang_chain = $this->lang_manager->get_fallback_chain();
		$has_trans = false;
		
		foreach ($this->columns_meta as $meta) {
			if (!empty($meta['translate'])) {
				$has_trans = true;
				break;
			}
		}

		// Sestavení seznamu tabulkových aliasů, abychom našli to nevyšší (nejnovější) datum 
		// úpravy napříč všemi vrstvami a jazyky.
		$mod_aliases = ['m', 'o'];
		if ($has_trans) {
			foreach ($lang_chain as $lang) {
				$mod_aliases[] = "l_{$lang}";
				$mod_aliases[] = "v_{$lang}";
			}
		}
		if ($has_ancestor) {
			$mod_aliases[] = 'anc';
			if ($has_trans) {
				foreach ($lang_chain as $lang) {
					$mod_aliases[] = "anc_l_{$lang}";
					$mod_aliases[] = "anc_v_{$lang}";
				}
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
			$is_string = $translate || in_array($meta['input_type'], ['text', 'textarea', null, ''], true);
			
			// Sestavení základního fallbacku pro 'A' záznam (Tenant vs Systém vs Předek)
			$base_coal = [];
			if (!$is_protected) {
				$base_coal[] = "m.[{$colname}]";                                          // Tenant může ovlivnit hodnotu (pokud není chráněná)
			}
			$base_coal[] = "o.[{$colname}]";                                              // Systémový originál (0x00)
			if ($has_ancestor) {
				$base_coal[] = "anc.[{$colname}]";                                        // Zděděná hodnota z předka
			}

			if ($is_string) {
				$coal = [];
				if ($translate) {
					// 1. Lokalizace: Cizí jazyky mají absolutní přednost před základními daty,
					// postupně propadáváme přes fallback řetězec definovaný v language_manageru.
					foreach ($lang_chain as $lang) {
						$coal[] = "NULLIF(CAST(v_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')";
						$coal[] = "NULLIF(CAST(l_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')";
					}
				}
				
				// 2. Primární data: Propadnutí na základní 'A' záznamy (do kterých se propisuje rodný jazyk entity)
				foreach ($base_coal as $b) {
					$coal[] = "NULLIF(CAST({$b} AS NVARCHAR(MAX)), '')";
				}
				
				// 3. Fallback dědičnosti překladů: Zkusíme vytáhnout jazykové mutace od předka
				if ($has_ancestor && $translate) {
					foreach ($lang_chain as $lang) {
						$coal[] = "NULLIF(CAST(anc_v_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')";
						$coal[] = "NULLIF(CAST(anc_l_{$lang}.[{$colname}] AS NVARCHAR(MAX)), '')";
					}
				}
				
				$coal[] = "''"; // Nejzazší nouzový případ, nevracíme NULL.
				$coalesce_str = implode(", ", $coal);
				$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]";
				
				// Pro diagnostiku a editor na frontendu vždy vracíme i čisté rozpadlé hodnoty (primární jazyk)
				if ($translate) {
					$prim_lang = $lang_chain[0] ?? 'cs';
					$select_list .= "\n\t\t, CAST(l_{$prim_lang}.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_translated]";
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
		// s ohledem na aktuální dbsession.language a dynamický fallback řetězec.
		$joins = "
		FROM s
		CROSS JOIN mix m
		LEFT JOIN {$table} o ON o.original = m.original AND o.object_owner = 0x00 AND o.record_type = 'A'";
		
		if ($has_trans) {
			foreach ($lang_chain as $lang) {
				$joins .= "
		LEFT JOIN {$table} l_{$lang} ON l_{$lang}.original = m.original AND l_{$lang}.object_owner = 0x00 AND l_{$lang}.language = '{$lang}' AND l_{$lang}.record_type = 'L' AND l_{$lang}.removed = 0
		LEFT JOIN {$table} v_{$lang} ON v_{$lang}.original = m.original AND v_{$lang}.object_owner = s.organization_uuid AND v_{$lang}.language = '{$lang}' AND v_{$lang}.record_type = 'L' AND v_{$lang}.removed = 0";
			}
		}

		// Totéž i pro tabulku předka
		if ($has_ancestor) {
			$joins .= "
		LEFT JOIN {$table} anc ON anc.original = m.ancestor AND anc.record_type = 'A' AND anc.object_owner = 0x00";
			if ($has_trans) {
				foreach ($lang_chain as $lang) {
					$joins .= "
		LEFT JOIN {$table} anc_l_{$lang} ON anc_l_{$lang}.original = m.ancestor AND anc_l_{$lang}.record_type = 'L' AND anc_l_{$lang}.language = '{$lang}' AND anc_l_{$lang}.object_owner = 0x00 AND anc_l_{$lang}.removed = 0
		LEFT JOIN {$table} anc_v_{$lang} ON anc_v_{$lang}.original = m.ancestor AND anc_v_{$lang}.record_type = 'L' AND anc_v_{$lang}.language = '{$lang}' AND anc_v_{$lang}.object_owner = s.organization_uuid AND anc_v_{$lang}.removed = 0";
				}
			}
		}

		$joins .= $cross_apply;

		// Sestavení CTE bloku (Common Table Expressions) s dynamickými dotazy
		$sql = "
		WITH s AS (
			-- Výběr aktuálního kontextu relace z dbsession
			SELECT organization AS organization_uuid FROM dbsession WHERE spid = @@SPID
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
		} elseif (!$is_mine && !empty($meta['is_protected'])) {
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
				$checked = ($value === '1' || strtolower($value) === 'true') ? 'checked' : '';
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
			if (!isset($_POST[$colname]) && $meta['input_type'] === 'checkbox') {
				$data[$colname] = 0;
				continue;
			}
			
			if (!isset($_POST[$colname])) {
				continue;
			}

			$raw_val = (string)$_POST[$colname];
			$phys_type = $this->col_types[$colname] ?? '';

			// Typově přesné parsování podle fyzického schématu databáze a metadat
			if (in_array($phys_type, ['uuid', 'uniqueidentifier'], true)) {
				$data[$colname] = guidliteral($raw_val);
			} elseif ($meta['input_type'] === 'checkbox') {
				$data[$colname] = ($raw_val === '1' || strtolower($raw_val) === 'true') ? 1 : 0;
			} elseif ($meta['input_type'] === 'number') {
				$data[$colname] = ($raw_val === '') ? 'NULL' : (string)(float)$raw_val;
			} else {
				$data[$colname] = charliteral($raw_val);
			}
		}
		
		return $data;
	}

	/**
	 * JÁDRO BACKENDU: Provede autonomní zápis dat s uplatněním architektury "Klonování s modifikací".
	 * 
	 * 1. Zjistí aktuální oprávnění ze session (right_translate) a master data.
	 * 2. Zfiltruje chráněná pole (`is_protected`), do kterých tenant nesmí zapisovat.
	 * 3. Zjistí shodu s předlohou (systémovým originálem) a uloží záznam s plně obsazenými 
	 *    datovými poli, včetně případné dědičnosti z předka.
	 * 4. Vyčlení přeložená data (`translate=1`) a zapíše je do paralelního 'L' záznamu.
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
		$q_session = sqlrun("SELECT organization, login_session_uuid, language, right_translate FROM dbsession WHERE spid = @@SPID");
		$session = fetch($q_session);
		free_result($q_session);

		if (!$session) {
			fatal_error("Uložení selhalo", "Nepodařilo se načíst kontext uživatele z dbsession.");
		}

		// Identita uživatele: zachování surových hodnot pro PHP logiku a tvorba bezpečných SQL literálů
		$org_uuid_raw = (string)$session['organization'];
		$user_uuid_raw = (string)$session['login_session_uuid'];
		$sess_lang_raw = (string)$session['language'];
		$right_translate = !empty($session['right_translate']);

		$org_uuid_sql = guidliteral($org_uuid_raw);
		$user_uuid_sql = guidliteral($user_uuid_raw);
		$lang_literal_sql = charliteral($sess_lang_raw);
		
		$table = $this->storage_table;

		$orig_guid_raw = $update_guid;
		$orig_guid_sql = ($update_guid === '') ? '' : guidliteral($update_guid);

		// 2. Zjištění vlastníka a master jazyka původního 'A' záznamu
		$a_exists = false;
		$a_uuid_sql = '';
		$a_lang_raw = $sess_lang_raw; // Výchozí pro zcela nový záznam
		$orig_owner_raw = $org_uuid_raw;
		$baseline_row = [];

		$is_sysadmin_org = ($org_uuid_raw === '0x00' || $org_uuid_raw === '00000000-0000-0000-0000-000000000000');

		if ($orig_guid_sql !== '') {
			// Dohledání existujícího záznamu (buď tenantův override, nebo systémový originál)
			$q_check = sqlrun("SELECT * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND removed = 0 AND (object_owner = {$org_uuid_sql} OR object_owner = 0x00) ORDER BY object_owner DESC");
			$current_row = null;
			if ($current_row = fetch($q_check)) {
				$a_exists = ((string)$current_row['object_owner'] === $org_uuid_raw || $is_sysadmin_org);
				$orig_owner_raw = (string)$current_row['object_owner'];
				$a_uuid_sql = guidliteral((string)$current_row['uuid']);
				$a_lang_raw = (string)$current_row['language'];
			}
			free_result($q_check);
			
			// Příprava dat pro Delta zápis (Override).
			if (!$is_sysadmin_org) {
				// Tenant vždy kopíruje čistý systémový záznam
				$q_base = sqlrun("SELECT * FROM {$table} WHERE original = {$orig_guid_sql} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00");
				if ($base = fetch($q_base)) {
					$baseline_row = $base;
				}
				free_result($q_base);
			} else {
				// Systémový administrátor dědí záznam výhradně z předka (pokud nějakého má)
				$anc_val = $post_data['ancestor'] ?? ($current_row['ancestor'] ?? null);
				if (!empty($anc_val) && $anc_val !== "''" && $anc_val !== 'NULL') {
					$anc_raw = trim((string)$anc_val, "'");
					$anc_guid = guidliteral($anc_raw);
					$q_anc = sqlrun("SELECT * FROM {$table} WHERE original = {$anc_guid} AND record_type = 'A' AND removed = 0 AND object_owner = 0x00");
					if ($anc_row = fetch($q_anc)) {
						$baseline_row = $anc_row;
					}
					free_result($q_anc);
				}
			}
		}

		// 3. Filtrace struktury: Rozdělení dat na 'A' (Základ) a 'L' (Lokalizace) podle Override vzoru
		$a_post_data = [];
		$l_post_data = [];
		$has_translated_cols = false;
		$is_native_lang = ($a_lang_raw === $sess_lang_raw);

		foreach ($post_data as $col => $val) {
			// BACKENDOVÁ POJISTKA (is_protected): Pokud se nejedná o sysadmina (0x00),
			// všechny chráněné sloupce vyhodíme. Ignorujeme i případné podvrhy přes HTTP nástroje.
			if (!$is_sysadmin_org && !empty($this->columns_meta[$col]['is_protected'])) {
				continue;
			}

			// Implementace vzoru Override (Klonování s modifikací)
			// Pro netknuté sloupce (shodné s předlohou) nahradíme NULL pouze v případě, 
			// že to databázové schéma fyzicky podporuje (podmínka odstraněna, protože
			// zapisujeme vždy kompletní data).
			if (!empty($baseline_row) && isset($baseline_row[$col])) {
				$baseline_val = $baseline_row[$col];
				$compare_val = trim((string)$val, "'");
				
				if (isset($this->col_nulls[$col]) && $this->col_nulls[$col] !== 'not null') {
					if ((string)$compare_val === (string)$baseline_val) {
						$val = 'NULL';
					}
				}
			}

			$is_translated = !empty($this->columns_meta[$col]['translate']);

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
				$a_post_data[$col] = $val; 
			}
		}

		// BACKENDOVÁ POJISTKA 2 (is_final): Pokud je celá třída nedotknutelná (číselníky),
		// tenantovi zamezíme jakémukoli vytváření vlastního 'A' overridu vymazáním polí.
		if (!$is_sysadmin_org && !empty($this->class_meta['is_final'])) {
			$a_post_data = []; 
		}

		// Obalení operací transakcí, aby se zamezilo nekonzistentním zápisům L bez A.
		sqlrun("BEGIN TRAN");

		// 4. Zápis do 'A' záznamu (Správa Master dat a auditních stop)
		if ($orig_guid_sql === '') {
			// A) INSERT: Zcela nová identita vytvářená uživatelem
			
			// VÝPOČET DETERMINISTICKÉHO ORIGINÁLU PŘED INSERTEM
			$q_keys = sqlrun("SELECT key1_column, key2_column FROM meta_original_keys WHERE table_name = " . charliteral($table));
			$key_info = fetch($q_keys);
			free_result($q_keys);

			if ($key_info) {
				$k1_col = $key_info['key1_column'];$k2_col = $key_info['key2_column'];$k1_val = array_key_exists($k1_col,$a_post_data) ? $a_post_data[$k1_col] : "''";
				$k2_val = ($k2_col && array_key_exists($k2_col,$a_post_data)) ? $a_post_data[$k2_col] : 'NULL';

				$q_orig = sqlrun("SELECT dbo.f_generate_original(" . charliteral($table) . ", {$org_uuid_sql}, CAST({$k1_val} AS VARCHAR(MAX)), CAST({$k2_val} AS VARCHAR(MAX))) AS orig_guid");
				if ($row = fetch($q_orig)) {
					$orig_guid_sql = guidliteral((string)$row['orig_guid']);
				}
				free_result($q_orig);
			} elseif ($table === 'link') {$link_def = array_key_exists('link_def', $a_post_data) ?$a_post_data['link_def'] : "''";
				$from_obj = array_key_exists('from_object', $a_post_data) ?$a_post_data['from_object'] : "''";
				$to_obj = array_key_exists('to_object', $a_post_data) ?$a_post_data['to_object'] : "''";

				$q_orig = sqlrun("SELECT dbo.f_link_original(CAST({$org_uuid_sql} AS varchar(36)), CAST({$link_def} AS varchar(36)), CAST({$from_obj} AS varchar(36)), CAST({$to_obj} AS varchar(36))) AS orig_guid");
				if ($row = fetch($q_orig)) {
					$orig_guid_sql = guidliteral((string)$row['orig_guid']);
				}
				free_result($q_orig);
			} else {
				$q_orig = sqlrun("SELECT NEWID() AS orig_guid");
				if ($row = fetch($q_orig)) {
					$orig_guid_sql = guidliteral((string)$row['orig_guid']);
				}
				free_result($q_orig);
			}

			$insert_cols = [];$insert_vals = [];
			
			foreach ($this->physical_cols as$col) {
				if (in_array($col, ['uuid', 'original'], true)) {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$orig_guid_sql;
				} elseif ($col === 'object_owner') {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$org_uuid_sql;
				} elseif ($col === 'record_type') {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] = "'A'";
				} elseif ($col === 'language') {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$lang_literal_sql;
				} elseif (in_array($col, ['date_created', 'date_modified'], true)) {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] = "GETDATE()";
				} elseif (in_array($col, ['who_created', 'who_modified'], true)) {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$user_uuid_sql;
				} elseif (array_key_exists($col,$a_post_data)) {
					$insert_cols[] = "[$col]"; 
					$insert_vals[] = $a_post_data[$col];
				}
			}

			$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") VALUES (" . implode(', ', $insert_vals) . ")";
			sqlrun($sql);
			
		} elseif (!empty($a_post_data)) {
			// B) UPDATE NEBO OVERRIDE 'A' ZÁZNAMU
			if ($a_exists) {$set_clauses = [];
				foreach ($a_post_data as$col => $val) {$set_clauses[] = "[$col] =$val";
				}
				$set_clauses[] = "date_modified = GETDATE()";
				$set_clauses[] = "who_modified = {$user_uuid_sql}";

				$sql = "UPDATE {$table} SET " . implode(', ', $set_clauses) . " WHERE uuid = {$a_uuid_sql}";
				sqlrun($sql);
			} else {
				// OVERRIDE: Tenant zasahuje do systémového záznamu poprvé.
				$insert_cols = [];$select_vals = [];
				
				foreach ($this->physical_cols as$col) {
					$insert_cols[] = "[$col]";
					
					if ($col === 'uuid') {$select_vals[] = "NEWID()";
					} elseif ($col === 'object_owner') {
						$select_vals[] =$org_uuid_sql;
					} elseif ($col === 'record_type') {$select_vals[] = "'A'";
					} elseif (in_array($col, ['date_created', 'date_modified'], true)) {$select_vals[] = "GETDATE()";
					} elseif (in_array($col, ['who_created', 'who_modified'], true)) {
						$select_vals[] =$user_uuid_sql;
					} elseif ($col === 'original') {$select_vals[] = "original"; 
					} elseif ($col === 'language') {$select_vals[] = "language";
					} elseif (array_key_exists($col, $a_post_data)) {$select_vals[] = $a_post_data[$col]; 
					} else {
						$select_vals[] = "[$col]"; 
					}
				}

				$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") \nSELECT " . implode(', ', $select_vals) . " \nFROM {$table} \nWHERE original = {$orig_guid_sql} AND object_owner = 0x00 AND record_type = 'A'";
				sqlrun($sql);
			}
		}

		// 5. Zápis 'L' záznamu
		if ($has_translated_cols &&$orig_guid_sql !== '') {
			
			$l_owner_sql =$org_uuid_sql;
			if ($orig_owner_raw === '0x00' ||$orig_owner_raw === '00000000-0000-0000-0000-000000000000') {
				if ($right_translate) {$l_owner_sql = '0x00';
				}
			}

			$q_l_check = sqlrun("SELECT uuid FROM {$table} WHERE original = {$orig_guid_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND language = {$lang_literal_sql} AND removed = 0");
			$l_exists = fetch($q_l_check);
			free_result($q_l_check);

			if ($l_exists) {
				if (!empty($l_post_data)) {$set_l = [];
					foreach ($l_post_data as$col => $val) {$set_l[] = "[$col] =$val";
					}
					$set_l[] = "date_modified = GETDATE()";
					$set_l[] = "who_modified = {$user_uuid_sql}";
					
					$sql_l = "UPDATE {$table} SET " . implode(', ', $set_l) . " WHERE uuid = " . guidliteral((string)$l_exists['uuid']);
					sqlrun($sql_l);
				}
			} else {
				$insert_cols_l = [];$select_vals_l = [];
				
				foreach ($this->physical_cols as$col) {
					$insert_cols_l[] = "[$col]";
					
					if ($col === 'uuid') {$select_vals_l[] = "NEWID()";
					} elseif ($col === 'object_owner') {
						$select_vals_l[] =$l_owner_sql;
					} elseif ($col === 'record_type') {$select_vals_l[] = "'L'";
					} elseif ($col === 'language') {
						$select_vals_l[] =$lang_literal_sql;
					} elseif (in_array($col, ['date_created', 'date_modified'], true)) {$select_vals_l[] = "GETDATE()";
					} elseif (in_array($col, ['who_created', 'who_modified'], true)) {
						$select_vals_l[] =$user_uuid_sql;
					} elseif (array_key_exists($col, $l_post_data)) {$select_vals_l[] = $l_post_data[$col]; 
					} else {
						$select_vals_l[] = "[$col]"; 
					}
				}

				$source_owner_sql = (!$is_sysadmin_org) ? "object_owner IN ({$org_uuid_sql}, 0x00)" : "object_owner = 0x00";
				$sql_l = "INSERT INTO {$table} (" . implode(', ', $insert_cols_l) . ") \nSELECT TOP 1 " . implode(', ', $select_vals_l) . " \nFROM {$table} \nWHERE original = {$orig_guid_sql} AND {$source_owner_sql} AND record_type = 'A' AND removed = 0 ORDER BY object_owner DESC";
				sqlrun($sql_l);
			}
		}

		sqlrun("COMMIT");
	}
}