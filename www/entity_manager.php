<?php
/**
 * =============================================================================
 * Verze: 2026-09-28
 * Soubor: entity_manager.php
 * Účel: Dynamický správce entit nahrazující pevně kódovaná SQL view (vrepo_*).
 *       Načítá definice z meta_object a meta_column, dynamicky skládá T-SQL 
 *       dotazy pro čtení dat s ohledem na překlady a tenant overridy (RAC/SSC)
 *       a automaticky generuje odpovídající HTML prvky formulářů.
 *
 * Vazby na okolí:
 * - Využívá funkce z OsirisLib.php (sqlrun, fetch, fetch_datarow, htmlliteral, charliteral, guidliteral).
 * - Databáze musí obsahovat tabulky meta_object, meta_column a meta_codetable.
 * - Třída je navržena k použití uvnitř potomků abstract_page_master_detail,
 *   přičemž usnadňuje vykreslování i zpracování POST požadavků.
 *
 * Změny:
 * 2026-09-28 - Přidána podpora pro referenced_codetable (generování selectů).
 *            - Přidány metody extract_post_data() a build_save_procedure_call() 
 *              pro automatizaci form_... procedur v abstraktních potomcích.
 * =============================================================================
 */

declare(strict_types=1);

class entity_manager {

	private string $object_code;
	private array $object_meta = [];
	private array $columns_meta = [];
	private bool $is_initialized = false;

	/**
	 * Konstruktor třídy.
	 * 
	 * @param string $object_code Fyzický název objektu v DB (např. 'asset_class' z builtin_code)
	 */
	public function __construct(string $object_code) {
		$this->object_code = $object_code;
		$this->load_metadata();
	}

	/**
	 * Načte kompletní metadata objektu a jeho sloupců jedním voláním.
	 */
	private function load_metadata(): void {
		$safe_code = charliteral($this->object_code);
		
		// 1. Načtení definice samotného objektu (meta_object)
		$q_obj = sqlrun("SELECT * FROM meta_object WHERE builtin_code = {$safe_code} AND record_type = 'A' AND object_owner = 0x00 AND removed = 0");
		if ($row = fetch($q_obj)) {
			$this->object_meta = $row;
			$parent_uuid = guidliteral($row['original']);
			free_result($q_obj);
			
			// 2. Načtení definice všech jeho sloupců, řazeno dle sort_code / parent_order
			$q_cols = sqlrun("SELECT * FROM meta_column WHERE parent_object = {$parent_uuid} AND record_type = 'A' AND object_owner = 0x00 AND removed = 0 ORDER BY parent_order, sort_code");
			while ($col = fetch($q_cols)) {
				$this->columns_meta[$col['column_name']] = $col;
			}
			free_result($q_cols);
			
			$this->is_initialized = true;
		}
	}

	/**
	 * Vygeneruje dynamický T-SQL dotaz nahrazující původní view vrepo_*.
	 * Tento dotaz si databáze zkompiluje ad-hoc a využije indexy tabulky.
	 * 
	 * @param string $where Volitelná WHERE podmínka pro dotaz
	 * @return string T-SQL dotaz připravený ke spuštění
	 */
	public function build_select_query(string $where = ''): string {
		if (!$this->is_initialized) {
			fatal_error("Entity manager", "Metadata pro objekt '{$this->object_code}' nebyla nalezena.");
		}

		$table = $this->object_code;
		$select_list = "";
		
		// Průchod sloupci a sestavení klauzule SELECT na základě jejich vlastností
		foreach ($this->columns_meta as $colname => $meta) {
			$is_metadata = in_array($colname, ['uuid', 'object_owner', 'original', 'record_type', 'approval_status', 'language', 'inactive', 'removed', 'valid_from', 'valid_to', 'is_template', 'template', 'date_created', 'who_created', 'date_modified', 'who_modified']);
			$translate = (bool)$meta['translate'];
			
			if ($is_metadata) {
				// Technické RAC sloupce bereme přímo z vyhodnoceného mixu (m)
				$select_list .= "\n\t\t, m.[{$colname}]";
			} elseif ($translate) {
				// Sloupce určené k překladu využívají kaskádu COALESCE (lokální překlad -> globální překlad -> lokální hodnota -> globální hodnota)
				$select_list .= "\n\t\t, COALESCE(NULLIF(CAST(v.[{$colname}] AS VARCHAR(MAX)), ''), NULLIF(CAST(l.[{$colname}] AS VARCHAR(MAX)), ''), CAST(m.[{$colname}] AS VARCHAR(MAX)), CAST(o.[{$colname}] AS VARCHAR(MAX)), '') AS [{$colname}]";
				$select_list .= "\n\t\t, CAST(l.[{$colname}] AS VARCHAR(MAX)) AS [{$colname}_translated]";
				$select_list .= "\n\t\t, CAST(m.[{$colname}] AS VARCHAR(MAX)) AS [{$colname}_original]";
				$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]";
			} else {
				// Ostatní standardní a byznys sloupce
				$select_list .= "\n\t\t, m.[{$colname}]";
				$select_list .= "\n\t\t, o.[{$colname}] AS [{$colname}_system]";
			}
		}
		
		// Odstranění první oddělovací čárky
		$select_list = substr($select_list, 4);
		$select_list .= "\n\t\t, m.object_is_mine";

		// Sestavení vrstveného dotazu (CTE: session -> system -> my -> mix)
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
	 * Vrátí načtená metadata konkrétního sloupce.
	 * 
	 * @param string $column_name DB název sloupce
	 * @return array Asociační pole s metadaty nebo prázdné pole
	 */
	public function get_column_meta(string $column_name): array {
		return $this->columns_meta[$column_name] ?? [];
	}

	/**
	 * Získá seznam definovaných sloupců entity pro řízené průchody UI.
	 * 
	 * @return array Seznam sloupců (asociační pole pole metadat)
	 */
	public function get_columns(): array {
		return $this->columns_meta;
	}

	/**
	 * Dynamický HTML generátor vstupních prvků na základě metadat.
	 * Řeší i zděděné hodnoty a zamykání (readonly) pro systémově chráněné sloupce.
	 * Nyní zahrnuje podporu pro napojené rozevírací seznamy z meta_codetable.
	 * 
	 * @param string $column_name Název sloupce (klíč v databázi)
	 * @param string $value Aktuální hodnota (zresolvovaná z pohledu)
	 * @param bool $is_mine Příznak, zda tenant přepsal tento záznam
	 * @return string Vygenerovaný HTML tag pro vložení do formuláře
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
		
		// Zpracování oprávnění k editaci (is_protected, is_computed, is_final)
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
	 * 
	 * @return array Asociační pole formátu [název_sloupce => bezpečně_zapouzdřená_hodnota]
	 */
	public function extract_post_data(): array {
		$data = [];
		foreach ($this->columns_meta as $colname => $meta) {
			$is_metadata = in_array($colname, ['uuid', 'object_owner', 'original', 'record_type', 'approval_status', 'language', 'inactive', 'removed', 'valid_from', 'valid_to', 'is_template', 'template', 'date_created', 'who_created', 'date_modified', 'who_modified']);
			
			// Ignorujeme vypočítávané a architektonické metadatové sloupce
			if (!empty($meta['is_computed']) || $is_metadata) {
				continue;
			}
			
			// Checkbox ošetříme zvlášť - pokud v POSTu vůbec není, nastavíme jej na 0
			if (!isset($_POST[$colname]) && $meta['input_type'] === 'checkbox') {
				$data[$colname] = 0;
				continue;
			}
			
			if (!isset($_POST[$colname])) {
				continue;
			}

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
	 * Vygeneruje automatický řetězec pro volání SQL procedury včetně parametrů.
	 * 
	 * @param string $proc_name Název cílové uložené procedury (např. 'form_meta_column')
	 * @param array $primary_keys Explicitní parametry tvořící klíčové vazby procedury (např. ['col_original' => guidliteral(...)])
	 * @param array $post_data Vyhodnocená POST data z metody extract_post_data()
	 * @return string Hrubý EXEC příkaz připravený pro sqlrun()
	 */
	public function build_save_procedure_call(string $proc_name, array $primary_keys, array $post_data): string {
		$args = [];
		// Nejprve svážeme definiční (primární/cizí) klíče
		foreach ($primary_keys as $k => $v) {
			$args[] = "@{$k}={$v}";
		}
		// Následně přiřadíme dynamicky načtená POST data
		foreach ($post_data as $k => $v) {
			$args[] = "@{$k}={$v}";
		}
		return "EXEC {$proc_name} " . implode(', ', $args);
	}
}