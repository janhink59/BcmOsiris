<?php
/**
 * =============================================================================
 * Verze: 2026-09-29 15:00
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit pro čtení i autonomní zápis (STI Architektura).
 *       Načítá logickou vrstvu z meta_class, zjišťuje fyzickou tabulku 
 *       z meta_object a sestavuje strukturu dat z meta_column.
 *
 * Vazby na okolí:
 * - Využívá funkce z OsirisLib.php (sqlrun, fetch, fetch_datarow, charliteral, guidliteral).
 * - Databáze musí obsahovat tabulky meta_class, meta_object, meta_column a v_syscolumns.
 *
 * Změny:
  * 2026-09-29 - Přechod z fyzických tabulek na logické třídy ($class_name).
 *            - Přidána metoda save_post_data() zajišťující autonomní RAC zápis.
 *            - Implementována plná podpora dědičnosti metadat (ancestor).
 *            - Automatické sestavení seznamu sloupců pro master panel vč. fallbacku.
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
					if ($col[$prop] === null && isset($col["anc_$prop"])) {
						$col[$prop] = $col["anc_$prop"];
					}
					// Speciální ošetření pro stringové vlastnosti, které by mohly mít výchozí hodnotu '' místo NULL
					if (($prop === 'referenced_codetable' || $prop === 'input_type') && $col[$prop] === '' && !empty($col["anc_$prop"])) {
						$col[$prop] = $col["anc_$prop"];
					}
				}
				
				$this->columns_meta[$col['column_name']] = $col;

				// Zpracování logiky pro Master (levý) panel s uplatněním zděděného list_order
				if ($col['list_order'] !== null) {
					$list_cols_temp[(int)$col['list_order']] = [
						'name' => $col['column_name'],
						'header' => $col['header'] ?: $col['caption'] ?: $col['column_name']
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
						$this->list_columns[$fc] = $col['header'] ?: $col['caption'] ?: $col['column_name'];
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
	 * Vygeneruje dynamický T-SQL dotaz nahrazující původní view vrepo_*.
	 * Tento dotaz si databáze zkompiluje ad-hoc a využije indexy.
	 * 
	 * @param string $where Volitelná WHERE podmínka pro dotaz
	 * @return string T-SQL dotaz připravený ke spuštění
	 */
	public function build_select_query(string $where = ''): string {
		if (!$this->is_initialized) {
			fatal_error("Entity manager", "Metadata pro logickou třídu '{$this->class_name}' nebyla nalezena.");
		}

		$table = $this->storage_table;
		$select_list = "";
		
		// Průchod sloupci a sestavení klauzule SELECT na základě jejich překladových vlastností
		foreach ($this->columns_meta as $colname => $meta) {
			$is_metadata = in_array($colname, ['uuid', 'object_owner', 'original', 'record_type', 'approval_status', 'language', 'inactive', 'removed', 'valid_from', 'valid_to', 'is_template', 'template', 'date_created', 'who_created', 'date_modified', 'who_modified']);
			$translate = (bool)$meta['translate'];
			
			if ($is_metadata) {
				// Technické RAC sloupce bereme přímo z vyhodnoceného mixu
				$select_list .= "\n\t\t, m.[{$colname}]";
			} elseif ($translate) {
				// Sloupce s překladem vyžadují kaskádové COALESCE a generují pomocné sloupce
				$select_list .= "\n\t\t, COALESCE(NULLIF(CAST(v.[{$colname}] AS VARCHAR(MAX)), ''), NULLIF(CAST(l.[{$colname}] AS VARCHAR(MAX)), ''), CAST(m.[{$colname}] AS VARCHAR(MAX)), CAST(o.[{$colname}] AS VARCHAR(MAX)), '') AS [{$colname}]";
				$select_list .= "\n\t\t, CAST(l.[{$colname}] AS VARCHAR(MAX)) AS [{$colname}_translated]";
				$select_list .= "\n\t\t, CAST(m.[{$colname}] AS VARCHAR(MAX)) AS [{$colname}_original]";
				$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]";
			} else {
				$select_list .= "\n\t\t, m.[{$colname}]";
				$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]";
			}
		}
		
		// Odstranění první oddělovací čárky a přidání příznaku tenanta
		$select_list = substr($select_list, 4);
		$select_list .= "\n\t\t, m.object_is_mine";

		// CTE dotaz (session -> system -> my -> mix)
		$sql = "
		WITH s AS (
			SELECT organization AS organization_uuid, language 
			FROM dbsession 
			WHERE spid = @@SPID
		),
		sy AS (
			SELECT rc.*, CAST(0 AS BIT) AS object_is_mine
			FROM s JOIN {$table} rc ON rc.object_owner = 0x00 AND rc.record_type = 'A'
		),
		my AS (
			SELECT rc.*, CAST(1 AS BIT) AS object_is_mine
			FROM s JOIN {$table} rc ON rc.object_owner = s.organization_uuid AND rc.record_type = 'A'
			WHERE rc.removed = 0
		),
		mix AS (
			SELECT sy.* 
			FROM sy LEFT JOIN my ON my.original = sy.original
			WHERE sy.removed = 0 AND my.original IS NULL
			UNION ALL
			SELECT * FROM my
		)
		SELECT {$select_list}
		FROM s
		CROSS JOIN mix m
		LEFT JOIN {$table} o ON o.original = m.original AND o.object_owner = 0x00 AND o.record_type = 'A'
		LEFT JOIN {$table} l ON l.original = m.original AND l.object_owner = 0x00 AND l.language = s.language AND l.record_type = 'L' AND l.removed = 0
		LEFT JOIN {$table} v ON v.original = m.original AND v.object_owner = s.organization_uuid AND v.language = s.language AND v.record_type = 'L' AND v.removed = 0
		";

		if ($where !== '') {
			$sql .= "\n\t\tWHERE {$where}";
		}

		return $sql;
	}

	/**
	 * Dynamický HTML generátor vstupních prvků na základě metadat.
	 * Řeší i zděděné hodnoty a zamykání (readonly) pro systémově chráněné sloupce.
	 * 
	 * @param string $column_name Název sloupce (klíč v databázi)
	 * @param string $value Aktuální hodnota
	 * @param bool $is_mine Příznak, zda tenant přepsal tento záznam
	 * @return string Vygenerovaný HTML tag
	 */
	public function render_dynamic_input(string $column_name, string $value, bool $is_mine = true): string {
		$meta = $this->get_column_meta($column_name);
		
		if (empty($meta)) {
			return "<!-- Neznámý sloupec: {$column_name} -->";
		}

		$type = $meta['input_type'] ?: 'text';
		$safe_name = htmlspecialchars($column_name);
		$safe_val = htmlspecialchars($value);
		
		// Sestavení vizuálních a omezujících atributů
		$attrs = [];
		if (!empty($meta['placeholder'])) $attrs[] = "placeholder=\"" . htmlspecialchars((string)$meta['placeholder']) . "\"";
		if (!empty($meta['max_length'])) $attrs[] = "maxlength=\"{$meta['max_length']}\"";
		if (!empty($meta['is_mandatory'])) $attrs[] = "required";
		
		// Zpracování oprávnění k editaci (is_protected, is_computed)
		if (!empty($meta['is_computed']) || (!$is_mine && !empty($meta['is_protected']))) {
			$attrs[] = "readonly style=\"background-color: #f4f4f4; width: " . ($meta['input_width'] ?: '100%') . ";\"";
		} else {
			$attrs[] = "style=\"width: " . ($meta['input_width'] ?: '100%') . ";\"";
		}

		$attr_string = implode(' ', $attrs);

		// Zpracování rozevíracích seznamů (číselníky)
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

		// Větvení podle input_type definovaného v databázi pro standardní hodnoty
		switch ($type) {
			case 'textarea':
				$rows = !empty($meta['input_rows']) ? "rows=\"{$meta['input_rows']}\"" : "rows=\"3\"";
				return "<textarea name=\"{$safe_name}\" {$rows} {$attr_string}>{$safe_val}</textarea>";
				
			case 'checkbox':
				$checked = ($value === '1' || strtolower($value) === 'true') ? 'checked' : '';
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"0\">
						<input type=\"checkbox\" name=\"{$safe_name}\" value=\"1\" {$checked} {$attr_string}>";
				
			case 'date':
				return "<input type=\"date\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>";
				
			case 'number':
				return "<input type=\"number\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>";
				
			case 'text':
			default:
				return "<input type=\"text\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>";
		}
	}

	/**
	 * Získá odeslaná POST data vztahující se k aktuální entitě a zajistí jejich
	 * odpovídající typovou sanitizaci pro T-SQL.
	 */
	public function extract_post_data(): array {
		$data = [];
		foreach ($this->columns_meta as $colname => $meta) {
			$is_metadata = in_array($colname, ['uuid', 'object_owner', 'original', 'record_type', 'approval_status', 'language', 'inactive', 'removed', 'valid_from', 'valid_to', 'is_template', 'template', 'date_created', 'who_created', 'date_modified', 'who_modified']);
			
			// Ignorujeme vypočítávané a architektonické metadatové sloupce
			if (!empty($meta['is_computed']) || $is_metadata) continue;
			
			// Checkboxy nemusí být v POSTu odeslány, pokud nejsou zaškrtnuty
			if (!isset($_POST[$colname]) && $meta['input_type'] === 'checkbox') {
				$data[$colname] = 0;
				continue;
			}
			
			if (!isset($_POST[$colname])) continue;

			$raw_val = (string)$_POST[$colname];

			// Transformace hodnot dle datového typu sloupce
			if ($meta['input_type'] === 'checkbox') {
				$data[$colname] = ($raw_val === '1' || strtolower($raw_val) === 'true') ? 1 : 0;
			} elseif ($meta['input_type'] === 'number') {
				$data[$colname] = ($raw_val === '') ? 'NULL' : (float)$raw_val;
			} elseif (!empty($meta['referenced_codetable']) || !empty($meta['referenced_class'])) {
				// Pokud napojený číselník nebo třída používá jako klíč UUID, formátujeme přes guidliteral
				$data[$colname] = ($raw_val === '') ? 'NULL' : (preg_match('/^[a-f0-9]{8}-/i', $raw_val) ? guidliteral($raw_val) : charliteral($raw_val));
			} else {
				$data[$colname] = charliteral($raw_val);
			}
		}
		return $data;
	}

	/**
	 * Zpracuje POST data, načte kontext uživatele a provede autonomní zápis.
	 * Automaticky řeší RAC logiku (INSERT vs UPDATE) pro tenant override,
	 * nebo vytvoření zcela nového záznamu, a to pro jakoukoliv tabulku.
	 * 
	 * @param string $update_guid Původní UUID záznamu (original). Pokud je prázdné, tvoří se nový.
	 */
	public function save_post_data(string $update_guid = ''): void {
		if (!$this->is_initialized) return;

		$post_data = $this->extract_post_data();
		if (empty($post_data)) return;

		// 1. Zjištění kontextu přihlášeného uživatele a organizace (Tenanta)
		$q_session = sqlrun("SELECT organization, user_access_uuid FROM dbsession WHERE spid = @@SPID");
		$session = fetch($q_session);
		free_result($q_session);

		if (!$session) {
			fatal_error("Uložení selhalo", "Nepodařilo se načíst kontext uživatele z dbsession.");
		}

		$org_uuid = guidliteral($session['organization']);
		$user_uuid = guidliteral($session['user_access_uuid']);
		
		// Zápis směřuje do fyzické tabulky zjištěné přes meta_class
		$table = $this->storage_table;

		// 2. Získání skutečných fyzických sloupců (ignorujeme computed a identity)
		$q_cols = sqlrun("SELECT colname FROM v_syscolumns WHERE tabname = " . charliteral($table) . " AND iscomputed = 0 AND is_identity = 0");
		$physical_cols = [];
		while ($c = fetch($q_cols)) {
			$physical_cols[] = $c['colname'];
		}
		free_result($q_cols);

		sqlrun("BEGIN TRAN");

		// --- A) INSERT ZCELA NOVÉHO ZÁZNAMU ---
		if ($update_guid === '') {
			$new_uuid = "NEWID()";
			$insert_cols = [];
			$insert_vals = [];
			
			foreach ($physical_cols as $col) {
				if ($col === 'uuid' || $col === 'original') {
					$insert_cols[] = "[$col]"; $insert_vals[] = $new_uuid;
				} elseif ($col === 'object_owner') {
					$insert_cols[] = "[$col]"; $insert_vals[] = $org_uuid;
				} elseif ($col === 'record_type') {
					$insert_cols[] = "[$col]"; $insert_vals[] = "'A'";
				} elseif ($col === 'date_created' || $col === 'date_modified') {
					$insert_cols[] = "[$col]"; $insert_vals[] = "GETDATE()";
				} elseif ($col === 'who_created' || $col === 'who_modified') {
					$insert_cols[] = "[$col]"; $insert_vals[] = $user_uuid;
				} elseif (array_key_exists($col, $post_data)) {
					$insert_cols[] = "[$col]"; $insert_vals[] = $post_data[$col];
				}
			}

			$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") VALUES (" . implode(', ', $insert_vals) . ")";
			sqlrun($sql);
			sqlrun("COMMIT");
			return;
		}

		// --- B) UPDATE LOKÁLNÍHO ZÁZNAMU NEBO C) INSERT TENANT OVERRIDE ---
		$orig_guid = guidliteral($update_guid);

		$q_check = sqlrun("SELECT uuid FROM {$table} WHERE original = {$orig_guid} AND object_owner = {$org_uuid} AND record_type = 'A' AND removed = 0");
		$exists = fetch($q_check);
		free_result($q_check);

		if ($exists) {
			// UPDATE existujícího lokálního záznamu (overridu tenanta)
			$set_clauses = [];
			foreach ($post_data as $col => $val) {
				$set_clauses[] = "[$col] = $val";
			}
			$set_clauses[] = "date_modified = GETDATE()";
			$set_clauses[] = "who_modified = {$user_uuid}";

			$sql = "UPDATE {$table} SET " . implode(', ', $set_clauses) . " WHERE uuid = " . guidliteral($exists['uuid']);
			sqlrun($sql);
		} else {
			// INSERT nového tenant overridu zkopírováním předka a přepsáním novými daty z POSTu
			$insert_cols = [];
			$select_vals = [];
			
			foreach ($physical_cols as $col) {
				$insert_cols[] = "[$col]";
				
				if ($col === 'uuid') {
					$select_vals[] = "NEWID()";
				} elseif ($col === 'object_owner') {
					$select_vals[] = $org_uuid;
				} elseif ($col === 'record_type') {
					$select_vals[] = "'A'";
				} elseif ($col === 'date_created' || $col === 'date_modified') {
					$select_vals[] = "GETDATE()";
				} elseif ($col === 'who_created' || $col === 'who_modified') {
					$select_vals[] = $user_uuid;
				} elseif ($col === 'original') {
					$select_vals[] = "original"; 
				} elseif (array_key_exists($col, $post_data)) {
					$select_vals[] = $post_data[$col]; 
				} else {
					$select_vals[] = "[$col]"; 
				}
			}

			$sql = "INSERT INTO {$table} (" . implode(', ', $insert_cols) . ") \nSELECT " . implode(', ', $select_vals) . " \nFROM {$table} \nWHERE original = {$orig_guid} AND object_owner = 0x00 AND record_type = 'A'";
			sqlrun($sql);
		}

		sqlrun("COMMIT");
	}
}