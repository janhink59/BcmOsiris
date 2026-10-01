<?php
/**
 * =============================================================================
 * Verze: 2026-10-01 (Asymetrický zápis překladů a ochrana originálu)
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit pro čtení i autonomní zápis (STI Architektura).
 *       Zajišťuje asymetrickou ochranu původního jazyka v 'A' záznamu 
 *       a ukládání cizojazyčných překladů do 'L' záznamů s ohledem 
 *       na oprávnění right_translate.
 *
 * EXTERNÍ ZÁVISLOSTI PRO AI KONTEXT (Pokud chybí referenční soubory):
 * - Kód silně spoléhá na existenci globální knihovny `OsirisLib.php`, která 
 *   dodává funkce: sqlrun(), fetch(), free_result(), charliteral(), 
 *   guidliteral() a fatal_error().
 * - Zápis a čtení kontextu identity očekává globální tabulku `dbsession` 
 *   s primárním klíčem na aktuální `@@SPID`, odkud čerpá `organization`, 
 *   `user_access_uuid` a `language`.
 * - Architektura vyžaduje existenci databázového schématu: `meta_class`, 
 *   `meta_object`, `meta_column`, `meta_codetable` a dynamického systémového 
 *   pohledu `v_syscolumns`.
 *
 * Změny:
 * 2026-10-01 - Asymetrický zápis překladů a oprava who_modified na master záznamu.
 * 2026-09-30 - Vrácení užitečných vývojářských komentářů ztracených při minulé revizi.
 *            - Komplexní přepis build_select_query(): Inteligentní COALESCE kaskáda.
 *            - Fix logických operátorů (využití in_array, and, or pro imunitu proti formátovači).
 *            - Implementován paralelní zápis do překladových záznamů (record_type = 'L').
 *            - Přidána metoda set_list_columns() pro ruční přepsání sloupců v UI.
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
	 * @param string $class_name Identifikátor logické třídy (např. 'asset_class', 'meta_object')
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
		
		// 1. Načtení definice třídy a zjištění fyzické tabulky (storage_object -> builtin_code)
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
				WHERE c.parent_object = {$storage_uuid} 
				  AND c.record_type = 'A' 
				  AND c.object_owner = 0x00 
				  AND c.removed = 0 
				ORDER BY c.parent_order, c.sort_code
			";
			
			$q_cols = sqlrun($sql_cols);
			$list_cols_temp = [];

			while ($col = fetch($q_cols)) {
				// Seznam vlastností, které podléhají dědičnosti (z nadřízeného sloupce v globálním slovníku)
				$inherited_props = [
					'list_order', 'caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder', 
					'input_type', 'input_width', 'input_rows', 'max_length', 'css_class', 'translate', 'history', 
					'is_html', 'is_mandatory', 'is_url', 'is_computed', 'show_empty', 'hidden', 'customizable', 
					'referenced_codetable', 'referenced_class', 'is_protected'
				];
				
				foreach ($inherited_props as $prop) {
					// Pokud je lokální hodnota NULL, převezmeme hodnotu od předka
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

				// Zpracování logiky pro Master (levý) panel s uplatněním zděděného list_order
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
				// Bezpečnostní fallback: Pokud nejsou definovány list_order sloupce, vezmeme první smysluplný
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
	 * Vrátí načtená metadata konkrétní logické třídy.
	 */
	public function get_class_meta(): array {
		return $this->class_meta;
	}

	/**
	 * Vrátí načtená metadata konkrétního sloupce.
	 */
	public function get_column_meta(string $column_name): array {
		return $this->columns_meta[$column_name] ?? [];
	}

	/**
	 * Získá seznam definovaných sloupců entity pro iterace UI formuláře.
	 */
	public function get_columns(): array {
		return $this->columns_meta;
	}

	/**
	 * Získá seznam definovaných sloupců pro Master panel seřazených dle list_order.
	 */
	public function get_list_columns(): array {
		return $this->list_columns;
	}
	
	/**
	 * Umožňuje z nadřízené třídy ručně přepsat sloupce zobrazené v levém panelu.
	 */
	public function set_list_columns(array $columns): void {
		$this->list_columns =$columns;
	}

	/**
	 * Vygeneruje dynamický T-SQL dotaz nahrazující původní view vrepo_*.
	 * Tento dotaz si databáze zkompiluje ad-hoc a využije indexy.
	 * Implementuje kaskádový COALESCE pro fallback jazyků.
	 * 
	 * @param string $where Volitelná WHERE podmínka pro dotaz
	 * @param string $order_by Volitelné řazení. Pokud prázdné, odvodí se z list_order.
	 * @return string T-SQL dotaz připravený ke spuštění
	 */
	public function build_select_query(string $where = '', string$order_by = ''): string {
		if (!$this->is_initialized) {
			fatal_error("Entity manager", "Metadata pro logickou třídu '{$this->class_name}' nebyla nalezena.");
		}

		$table =$this->storage_table;
		$select_list = "";
		
		$meta_columns_list = [
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'language', 'inactive', 'removed', 'valid_from', 'valid_to', 
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified'
		];
		
		$has_ancestor = isset($this->columns_meta['ancestor']);

		// Průchod sloupci a sestavení klauzule SELECT na základě jejich překladových vlastností
		foreach ($this->columns_meta as $colname =>$meta) {
			if (in_array($colname,$meta_columns_list, true)) {
				// Technické RAC sloupce bereme přímo z vyhodnoceného mixu
				$select_list .= "\n\t\t, m.[{$colname}]";
				continue;
			}
			
			$translate = (bool)$meta['translate'];$is_string = $translate or in_array($meta['input_type'], ['text', 'textarea', null, ''], true);
			
			if ($is_string) {
				// Sloupce s překladem vyžadují kaskádové COALESCE a generují pomocné sloupce
				$coal = [];
				if ($translate) {
					$coal[] = "NULLIF(CAST(v.[{$colname}] AS NVARCHAR(MAX)), '')";
					$coal[] = "NULLIF(CAST(l.[{$colname}] AS NVARCHAR(MAX)), '')";
					$coal[] = "NULLIF(CAST(v_fall.[{$colname}] AS NVARCHAR(MAX)), '')";
					$coal[] = "NULLIF(CAST(l_fall.[{$colname}] AS NVARCHAR(MAX)), '')";
				}
				$coal[] = "NULLIF(CAST(m.[{$colname}] AS NVARCHAR(MAX)), '')";
				$coal[] = "NULLIF(CAST(o.[{$colname}] AS NVARCHAR(MAX)), '')";
				
				if ($has_ancestor) {
					if ($translate) {
						$coal[] = "NULLIF(CAST(anc_v.[{$colname}] AS NVARCHAR(MAX)), '')";
						$coal[] = "NULLIF(CAST(anc_l.[{$colname}] AS NVARCHAR(MAX)), '')";
						$coal[] = "NULLIF(CAST(anc_v_fall.[{$colname}] AS NVARCHAR(MAX)), '')";
						$coal[] = "NULLIF(CAST(anc_l_fall.[{$colname}] AS NVARCHAR(MAX)), '')";
					}
					$coal[] = "NULLIF(CAST(anc.[{$colname}] AS NVARCHAR(MAX)), '')";
				}
				
				$coal[] = "''";
				$coalesce_str = implode(", ", $coal);$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]";
				
				if ($translate) {$select_list .= "\n\t\t, CAST(l.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_translated]";
					$select_list .= "\n\t\t, CAST(m.[{$colname}] AS NVARCHAR(MAX)) AS [{$colname}_original]";
					$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]";
				}
			} else {
				// Netextové sloupce používají jednodušší COALESCE bez NVARCHAR přetypování
				$coal = [];
				$coal[] = "m.[{$colname}]";
				$coal[] = "o.[{$colname}]";
				
				if ($has_ancestor) {
					$coal[] = "anc.[{$colname}]";
				}
				
				$coalesce_str = implode(", ", $coal);$select_list .= "\n\t\t, COALESCE({$coalesce_str}) AS [{$colname}]";
			}
		}
		
		// Odstranění první oddělovací čárky a přidání příznaku tenanta
		$select_list = substr($select_list, 4);$select_list .= "\n\t\t, m.object_is_mine";

		// JOINy respektují jazyk relace i jeho případný fallback v tabulce language
		$joins = "
		FROM s
		CROSS JOIN mix m
		LEFT JOIN {$table} o ON o.original = m.original AND o.object_owner = 0x00 AND o.record_type = 'A'
		LEFT JOIN {$table} l ON l.original = m.original AND l.object_owner = 0x00 AND l.language = s.language AND l.record_type = 'L' AND l.removed = 0
		LEFT JOIN {$table} v ON v.original = m.original AND v.object_owner = s.organization_uuid AND v.language = s.language AND v.record_type = 'L' AND v.removed = 0
		LEFT JOIN {$table} l_fall ON l_fall.original = m.original AND l_fall.object_owner = 0x00 AND l_fall.language = s.fallback_language AND l_fall.record_type = 'L' AND l_fall.removed = 0
		LEFT JOIN {$table} v_fall ON v_fall.original = m.original AND v_fall.object_owner = s.organization_uuid AND v_fall.language = s.fallback_language AND v_fall.record_type = 'L' AND v_fall.removed = 0
		";

		if ($has_ancestor) {
			// Připojení předka pro dědičnost hodnot (např. sys_global_columns)
			$joins .= "
		LEFT JOIN {$table} anc ON anc.original = m.ancestor AND anc.record_type = 'A' AND anc.object_owner = 0x00
		LEFT JOIN {$table} anc_l ON anc_l.original = m.ancestor AND anc_l.record_type = 'L' AND anc_l.language = s.language AND anc_l.object_owner = 0x00 AND anc_l.removed = 0
		LEFT JOIN {$table} anc_v ON anc_v.original = m.ancestor AND anc_v.record_type = 'L' AND anc_v.language = s.language AND anc_v.object_owner = s.organization_uuid AND anc_v.removed = 0
		LEFT JOIN {$table} anc_l_fall ON anc_l_fall.original = m.ancestor AND anc_l_fall.record_type = 'L' AND anc_l_fall.language = s.fallback_language AND anc_l_fall.object_owner = 0x00 AND anc_l_fall.removed = 0
		LEFT JOIN {$table} anc_v_fall ON anc_v_fall.original = m.ancestor AND anc_v_fall.record_type = 'L' AND anc_v_fall.language = s.fallback_language AND anc_v_fall.object_owner = s.organization_uuid AND anc_v_fall.removed = 0
		";
		}

		// CTE dotaz (session -> system -> my -> mix)
		$sql = "
		WITH s AS (
			SELECT 
				db.organization AS organization_uuid, 
				db.language, 
				lang.fallback_language
			FROM dbsession db
			LEFT JOIN language lang ON lang.language = db.language
			WHERE db.spid = @@SPID
		),
		sy AS (
			-- Všechny systémové záznamy
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
			-- Kombinace: systémové záznamy bez lokálního override UNION všechny vlastní
			SELECT sy.* 
			FROM sy LEFT JOIN my ON my.original = sy.original
			WHERE sy.removed = 0 AND my.original IS NULL
			UNION ALL
			SELECT * FROM my
		)
		SELECT {$select_list}
		{$joins}
		";

		if ($where !== '') {$sql .= "\n\t\tWHERE {$where}";
		}

		// Automatické odvození klauzule ORDER BY
		if ($order_by !== '') {
			$sql .= "\n\t\tORDER BY {$order_by}";
		} elseif (!empty($this->list_columns)) {$order_cols = [];
			foreach (array_keys($this->list_columns) as$col) {
				$order_cols[] = "[{$col}]";
			}
			$sql .= "\n\t\tORDER BY " . implode(', ', $order_cols);
		}

		return $sql;
	}

	/**
	 * Dynamický HTML generátor vstupních prvků na základě metadat.
	 * Řeší i zděděné hodnoty a zamykání (readonly) pro systémově chráněné sloupce
	 * nebo při absenci oprávnění k překladu (right_translate).
	 * 
	 * @param string $column_name Název sloupce (klíč v databázi)
	 * @param string $value Aktuální hodnota
	 * @param bool $is_mine Příznak, zda tenant přepsal tento záznam
	 * @return string Vygenerovaný HTML tag
	 */
	public function render_dynamic_input(string $column_name, string$value, bool $is_mine = true): string {$meta = $this->get_column_meta($column_name);
		
		if (empty($meta)) {
			return "<!-- Neznámý sloupec: {$column_name} -->";
		}

		// Načtení globálního kontextu relace pro kontrolu práv k překladu
		global $dbsession;
		$right_translate = !empty($dbsession['right_translate']);

		$type =$meta['input_type'] ?: 'text';
		$safe_name = htmlspecialchars($column_name);
		$safe_val = htmlspecialchars($value);
		
		// Sestavení vizuálních a omezujících atributů
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
		if (!empty($meta['is_mandatory'])) {$attrs[] = "required";
		}
		
		// Zpracování oprávnění k editaci (is_protected, is_computed, right_translate)
		$is_readonly = false;
		$no_translate_rights = false;
		
		if (!empty($meta['is_computed'])) {$is_readonly = true;
		} elseif (!$is_mine and !empty($meta['is_protected'])) {$is_readonly = true;
		} elseif (!empty($meta['translate']) and !$right_translate) {$is_readonly = true;
			$no_translate_rights = true;
		}
		
		$input_width =$meta['input_width'] ?: '100%';
		
		if ($is_readonly) {
			$title_attr =$no_translate_rights ? ' title="Nemáte oprávnění k úpravě překladů."' : '';
			$attrs[] = "readonly style=\"background-color: #f4f4f4; width: {$input_width};\"{$title_attr}";
			if ($type === 'checkbox') {
				// HTML specifikace ignoruje readonly pro checkboxy, je nutné je disablovat
				$attrs[] = "disabled";
			}
		} else {
			$attrs[] = "style=\"width: {$input_width};\"";
		}

		$attr_string = implode(' ',$attrs);

		// Zpracování rozevíracích seznamů (číselníky)
		if (!empty($meta['referenced_codetable'])) {$options_html = '<option value="">--- Vyberte ---</option>';
			$safe_ct = charliteral($meta['referenced_codetable']);$q_opt = sqlrun("SELECT value_code, caption FROM meta_codetable WHERE codetable_name = {$safe_ct} AND record_type = 'A' AND removed = 0 ORDER BY sort_code, caption");
			
			while ($opt = fetch($q_opt)) {
				$sel = ($opt['value_code'] === $value) ? 'selected' : '';$options_html .= "<option value=\"" . htmlspecialchars((string)$opt['value_code']) . "\" {$sel}>" . htmlspecialchars((string)$opt['caption']) . "</option>";
			}
			
			free_result($q_opt);
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>";
		}

		// Větvení podle input_type definovaného v databázi pro standardní hodnoty
		switch ($type) {
			case 'textarea':
				$rows = !empty($meta['input_rows']) ? "rows=\"{$meta['input_rows']}\"" : "rows=\"3\"";
				return "<textarea name=\"{$safe_name}\" {$rows} {$attr_string}>{$safe_val}</textarea>";
				
			case 'checkbox':
				$checked = '';
				if ($value === '1' or strtolower($value) === 'true') {$checked = 'checked';
				}
				
				if ($is_readonly) {
					// Zamčené checkboxy se neodesílají do POST, podvrhujeme proto reálný stav přes hidden pole
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
	 * Extrakce a sanitizace POST dat z formuláře podle datových typů definovaných v DB.
	 */
	public function extract_post_data(): array {
		$data = [];$meta_columns_list = [
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status', 
			'language', 'inactive', 'removed', 'valid_from', 'valid_to', 
			'is_template', 'template', 'date_created', 'who_created', 
			'date_modified', 'who_modified'
		];
		
		foreach ($this->columns_meta as $colname =>$meta) {
			// Ignorujeme vypočítávané a architektonické metadatové sloupce
			if (!empty($meta['is_computed'])) {
				continue;
			}
			if (in_array($colname,$meta_columns_list, true)) {
				continue;
			}
			
			// Checkboxy nemusí být v POSTu odeslány, pokud nejsou zaškrtnuty
			if (!isset($_POST[$colname]) and$meta['input_type'] === 'checkbox') {
				$data[$colname] = 0;
				continue;
			}
			
			if (!isset($_POST[$colname])) {
				continue;
			}

			$raw_val = (string)$_POST[$colname];

			// Transformace hodnot dle datového typu sloupce
			if ($meta['input_type'] === 'checkbox') {
				if ($raw_val === '1' or strtolower($raw_val) === 'true') {$data[$colname] = 1;  				} else {$data[$colname] = 0;  				}  			} elseif ($meta['input_type'] === 'number') {
				if ($raw_val === '') {
					$data[$colname] = 'NULL';
				} else {
					$data[$colname] = (float)$raw_val;
				}
			} elseif (!empty($meta['referenced_codetable']) or !empty($meta['referenced_class'])) {
				// Pokud napojený číselník nebo třída používá jako klíč UUID, formátujeme přes guidliteral
				if ($raw_val === '') {
					$data[$colname] = 'NULL';
				} else {
					if (preg_match('/^[a-f0-9]{8}-/i', $raw_val)) {$data[$colname] = guidliteral($raw_val);
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
	 * Zpracuje POST data, načte kontext uživatele a provede autonomní zápis.
	 * Automaticky řeší asymetrickou RAC logiku (INSERT vs UPDATE) pro tenant override včetně
	 * oddělené obsluhy paralelního záznamu (record_type='L') pro překlady.
	 * 
	 * @param string $update_guid Původní UUID záznamu (original). Pokud je prázdné, tvoří se nový.
	 */
	public function save_post_data(string $update_guid = ''): void {
		if (!$this->is_initialized) {
			return;
		}

		$post_data =$this->extract_post_data();
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

		$org_uuid = guidliteral($session['organization']);
		$user_uuid = guidliteral($session['user_access_uuid']);
		$lang_literal = charliteral($session['language']);
		$sess_lang_raw =$session['language'];
		$right_translate = !empty($session['right_translate']);
		
		// Zápis směřuje do fyzické tabulky zjištěné přes meta_class
		$table =$this->storage_table;

		// 2. Získání skutečných fyzických sloupců (ignorujeme computed a identity) vč. datových typů
		$q_cols = sqlrun("SELECT colname, typename FROM v_syscolumns WHERE tabname = " . charliteral($table) . " AND iscomputed = 0 AND is_identity = 0");
		$physical_cols = [];$col_types = [];
		while ($c = fetch($q_cols)) {$physical_cols[] = $c['colname'];$col_types[$c['colname']] =$c['typename'];
		}
		free_result($q_cols);

		$orig_guid = ($update_guid === '') ? '' : guidliteral($update_guid);

		// 3. Zjištění master jazyka záznamu (kvůli asymetrické ochraně překladů v A záznamu)
		$a_exists = false;
		$a_uuid = '';
		$a_lang_raw =$sess_lang_raw; // Výchozí předpoklad pro zcela nový záznam

		if ($orig_guid !== '') {$q_check = sqlrun("SELECT uuid, language FROM {$table} WHERE original = {$orig_guid} AND object_owner = {$org_uuid} AND record_type = 'A' AND removed = 0");
			if ($row = fetch($q_check)) {$a_exists = true;
				$a_uuid = guidliteral($row['uuid']);
				$a_lang_raw =$row['language'];
			}
			free_result($q_check);

			// V případě override čerpáme původní master jazyk ze systémového originálu (0x00)
			if (!$a_exists) {$q_sys = sqlrun("SELECT language FROM {$table} WHERE original = {$orig_guid} AND object_owner = 0x00 AND record_type = 'A' AND removed = 0");
				if ($sys_row = fetch($q_sys)) {
					$a_lang_raw =$sys_row['language'];
				}
				free_result($q_sys);
			}
		}

		// 4. Rozdělení slovníku (Asymetrická filtrace vstupů dle oprávnění a jazyka)
		$a_post_data = [];
		$l_post_data = [];$has_translated_cols = false;
		$is_native_lang = ($a_lang_raw ===$sess_lang_raw);

		foreach ($post_data as$col => $val) {$is_translated = !empty($this->columns_meta[$col]['translate']);
			if ($is_translated) {$has_translated_cols = true;
				$l_post_data[$col] =$val;
				
				// OCHRANA ORIGINÁLU: Do 'A' záznamu propíšeme překlad pouze tehdy, 
				// když relace pracuje ve stejném jazyce, v jakém záznam původně vznikl.
				if ($is_native_lang) {$a_post_data[$col] =$val;
				}
			} else {
				// Univerzální nestringové atributy posíláme do A záznamu vždy
				$a_post_data[$col] =$val; 
			}
		}

		sqlrun("BEGIN TRAN");

		// 5. Zápis 'A' záznamu (Master nositel základních dat a auditní stopy modifikace)
		if ($orig_guid === '') {
			// INSERT: Nový záznam
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
					if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
					}
					$insert_cols[] = "[$col]"; 
					$insert_vals[] =$val;
				}
			}

			// OUTPUT inserted.original je nutné pro navázání 'L' záznamu, 
			// protože original UUID počítá trigger f_generate_original
			$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") OUTPUT inserted.original VALUES (" . implode(', ', $insert_vals) . ")";
			$q_ins = sqlrun($sql);
			if ($ins_row = fetch($q_ins)) {
				$orig_guid = guidliteral($ins_row['original']);
			}
			free_result($q_ins);
		} else {
			if ($a_exists) {
				// UPDATE: Aktualizace existujícího 'A' záznamu u tenanta
				$set_clauses = [];
				foreach ($a_post_data as $col =>$val) {
					if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
					}
					$set_clauses[] = "[$col] =$val";
				}
				
				// Neoddiskutovatelně vynucená aktualizace auditní stopy
				$set_clauses[] = "date_modified = GETDATE()";
				$set_clauses[] = "who_modified = {$user_uuid}";

				$sql = "UPDATE {$table} SET " . implode(', ', $set_clauses) . " WHERE uuid = {$a_uuid}";
				sqlrun($sql);
			} else {
				// INSERT OVERRIDE: Tenant vytváří vlastní 'A' kopii systémového záznamu
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
					} elseif ($col === 'language') {$select_vals[] = "language"; // Necháváme původní jazyk původního master záznamu
					} elseif (array_key_exists($col, $a_post_data)) {$val = $a_post_data[$col];
						if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
						}
						$select_vals[] =$val; 
					} else {
						$select_vals[] = "[$col]"; 
					}
				}

				$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") \nSELECT " . implode(', ', $select_vals) . " \nFROM {$table} \nWHERE original = {$orig_guid} AND object_owner = 0x00 AND record_type = 'A'";
				sqlrun($sql);
			}
		}

		// 6. Zápis 'L' záznamu (Pouze pokud má tabulka překladové sloupce a uživatel má oprávnění)
		if ($has_translated_cols and$right_translate and $orig_guid !== '') {$q_l_check = sqlrun("SELECT uuid FROM {$table} WHERE original = {$orig_guid} AND object_owner = {$org_uuid} AND record_type = 'L' AND language = {$lang_literal} AND removed = 0");
			$l_exists = fetch($q_l_check);
			free_result($q_l_check);

			if ($l_exists) {
				// UPDATE: Aktualizace existující překladové mutace
				$set_l = [];
				foreach ($l_post_data as $col =>$val) {
					if ($val === "''" and in_array($col_types[$col] ?? '', ['uuid', 'uniqueidentifier'])) {$val = 'NULL';
					}
					$set_l[] = "[$col] =$val";
				}
				$set_l[] = "date_modified = GETDATE()";
				$set_l[] = "who_modified = {$user_uuid}";
				
				$sql_l = "UPDATE {$table} SET " . implode(', ', $set_l) . " WHERE uuid = " . guidliteral($l_exists['uuid']);
				sqlrun($sql_l);
			} else {
				// INSERT: Vytvoření nové překladové mutace zkrze klonování aktuálního 'A'
				$insert_cols_l = [];$select_vals_l = [];
				
				foreach ($physical_cols as$col) {
					$insert_cols_l[] = "[$col]";
					
					if ($col === 'uuid') {$select_vals_l[] = "NEWID()";
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

				$sql_l = "INSERT INTO {$table} (" . implode(', ', $insert_cols_l) . ") \nSELECT " . implode(', ', $select_vals_l) . " \nFROM {$table} \nWHERE original = {$orig_guid} AND object_owner = {$org_uuid} AND record_type = 'A' AND removed = 0";
				sqlrun($sql_l);
			}
		}

		sqlrun("COMMIT");
	}
}