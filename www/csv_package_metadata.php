<?php
/**
 * =============================================================================
 * Verze: 2026-10-23 16:00
 * Soubor: csv_package_metadata.php
 * Třída: csv_package_metadata
 * Účel: Konkrétní implementace CSV/TSV balíčku "metadata" pro přenos systémových
 *       metadat (`object_owner = 0x00`: `meta_object`, `meta_class`, `meta_column`,
 *       `meta_menu`, `meta_phrase`, `meta_codetable`, `meta_link_def`) mezi
 *       instancemi systému BCM Osiris.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Dědí z `abstract_csv_package` (`abstract_csv_package.php`).
 * - Nastavuje `$this->is_system_package = true`, protože systémová metadata (`0x00`)
 *   se při importu zapisují přímo do `'A'` a `'L'` záznamů (nevytvářejí koncepty `'D'`).
 * - Podporuje volitelný filtrační parametr `class_name` (umožňuje vyexportovat
 *   buď kompletní systémová metadata, nebo pouze vybranou logickou třídu a s ní
 *   související objekty, sloupce a fráze) a parametr `language` (všechny jazyky
 *   nebo jen vybranou jazykovou mutaci).
 * - Ve Fázi 2 importu volá uloženou proceduru `p_csv_import_metadata`.
 * =============================================================================
 */

declare(strict_types=1);

class csv_package_metadata extends abstract_csv_package {

	/**
	 * Základní identifikace systémového balíčku metadat.
	 */
	protected function init_package(): void {
		$this->package_code = 'metadata';                                    // Kód balíčku (odpovídá p_csv_import_metadata)
		$this->package_title = $this->phrase('pkg_title', 'Systémová metadata (třídy, sloupce, menu, fráze, číselníky)'); // Název
		$this->description = $this->phrase('pkg_desc', 'Export a dvoufázový import systémových metadat (object_owner = 0x00) ve víceblokovém TSV/CSV formátu.'); // Popis
		$this->is_system_package = true;                                     // Systémová data (0x00) nevytvářejí koncepty ke schválení
	}

	/**
	 * Vrátí definici filtračních parametrů pro export metadat.
	 *
	 * @return array<string, array<string, mixed>>
	 */
	public function get_filter_parameters_def(): array {
		// Sestavení voleb jazyků z tabulky [language]
		$lang_opts = [                                                       // Výchozí volba všech jazyků
			'ALL' => $this->phrase('opt_all_languages', '--- Všechny jazykové verze (A + L) ---')
		];                                                                   // Konec výchozí volby jazyka
		$l_rows = sqlarray_simple("SELECT [language], caption FROM [language] ORDER BY sort_code"); // Načtení jazyků
		if (is_array($l_rows)) {                                             // Průchod jazyky v paměti
			foreach ($l_rows as $lr) {                                       // Přidání jazyka do roletky
				$l_code = (string)$lr['language'];                           // Kód jazyka
				$l_cap = (string)$lr['caption'];                             // Název jazyka
				$lang_opts[$l_code] = "{$l_code} - {$l_cap}";                // Text volby jazyka
			}
		}

		// Sestavení voleb logických tříd pro volitelný filtr jedné třídy
		$cls_opts = [                                                        // Výchozí volba všech tříd
			'' => $this->phrase('opt_all_classes', '--- Kompletní systémová metadata (všechny třídy) ---')
		];                                                                   // Konec výchozí volby tříd
		$c_rows = sqlarray_simple("SELECT class_name, caption FROM meta_class WHERE object_owner = 0x00 AND record_type = 'A' AND removed = 0 ORDER BY class_name"); // Třídy
		if (is_array($c_rows)) {                                             // Průchod třídami v paměti
			foreach ($c_rows as $cr) {                                       // Přidání třídy do roletky
				$c_name = (string)$cr['class_name'];                         // Technický název třídy
				$c_cap = (string)$cr['caption'];                             // Popisek třídy
				$cls_opts[$c_name] = ($c_cap !== '' AND $c_cap !== $c_name) ? "{$c_name} ({$c_cap})" : $c_name; // Text volby
			}
		}

		return [                                                             // Pole filtračních parametrů balíčku metadata
			'language_filter' => [
				'label'     => $this->phrase('lbl_language_filter', 'Jazykový rozsah exportu'),
				'type'      => 'varchar',
				'mandatory' => true,
				'default'   => 'ALL',
				'options'   => $lang_opts
			],
			'class_filter' => [
				'label'     => $this->phrase('lbl_class_filter', 'Filtr logické třídy (volitelně)'),
				'type'      => 'varchar',
				'mandatory' => false,
				'default'   => '',
				'options'   => $cls_opts
			]
		];                                                                   // Konec definice parametrů
	}

	/**
	 * Sestaví SQL dotazy pro export jednotlivých metadatových tabulek s uplatněním filtrů.
	 *
	 * @param array<string, string> $params Parametry exportu
	 * @return array<string, string>
	 */
	public function get_export_tables_sql(array $params): array {            // Sestavení exportních dotazů pro tabulky
		$lang_filter = trim((string)($params['language_filter'] ?? 'ALL'));  // Zvolený filtr jazyka
		$class_filter = trim((string)($params['class_filter'] ?? ''));       // Zvolený filtr logické třídy

		$lang_cond = ($lang_filter !== '' AND $lang_filter !== 'ALL')
			? "AND (record_type = 'A' OR (record_type = 'L' AND [language] = " . charliteral($lang_filter, 2) . "))"
			: "AND record_type IN ('A', 'L')";                               // Podmínka záznamů A a L podle jazyka

		// Pokud je zadán filtr konkrétní logické třídy, omezíme export na danou třídu a související záznamy
		if ($class_filter !== '') {                                          // Režim exportu vybrané logické třídy
			$safe_cls = charliteral($class_filter, 80);                      // SQL literál názvu třídy
			return [                                                         // Dotazy omezené na vybranou třídu
				'meta_object' => "
					SELECT uuid, original, record_type, [language], inactive, removed, object_type, builtin_code, system_role, module, caption, caption_plural, description, helptext, editor_note
					FROM meta_object
					WHERE object_owner = 0x00 {$lang_cond}
					  AND original IN (
						SELECT storage_object FROM meta_class WHERE object_owner = 0x00 AND class_name = {$safe_cls}
					  )
					ORDER BY builtin_code, record_type, [language]
				",
				'meta_class' => "
					SELECT uuid, original, record_type, [language], inactive, removed, class_name, storage_object, ancestor_class, sort_code, svg_icon, is_final, is_protected, caption, caption_plural, description, helptext, editor_note
					FROM meta_class
					WHERE object_owner = 0x00 {$lang_cond}
					  AND class_name = {$safe_cls}
					ORDER BY class_name, record_type, [language]
				",
				'meta_column' => "
					SELECT uuid, original, record_type, [language], inactive, removed, parent_class, parent_order, sort_code, column_name, list_order, caption, caption_plural, description, label, header, helptext, placeholder, editor_note, input_type, input_width, input_rows, max_length, css_class, translate, history, is_html, is_mandatory, is_url, is_computed, show_empty, hidden, customizable, ancestor, referenced_codetable, referenced_class, is_final, is_protected
					FROM meta_column
					WHERE object_owner = 0x00 {$lang_cond}
					  AND parent_class IN (
						SELECT original FROM meta_class WHERE object_owner = 0x00 AND class_name = {$safe_cls}
					  )
					ORDER BY parent_order, column_name, record_type, [language]
				",
				'meta_phrase' => "
					SELECT uuid, original, record_type, [language], inactive, removed, source_code, builtin_code, module, caption, helptext, editor_note, svg_icon, css_class, is_final, is_protected
					FROM meta_phrase
					WHERE object_owner = 0x00 {$lang_cond}
					  AND source_code IN ({$safe_cls}, 'page_' + {$safe_cls})
					ORDER BY source_code, builtin_code, record_type, [language]
				"
			];                                                               // Konec filtrovaných dotazů
		}

		// Kompletní export všech systémových metadat (object_owner = 0x00)
		return [                                                             // Dotazy pro kompletní systémová metadata
			'meta_object' => "
				SELECT uuid, original, record_type, [language], inactive, removed, object_type, builtin_code, system_role, module, caption, caption_plural, description, helptext, editor_note
				FROM meta_object
				WHERE object_owner = 0x00 {$lang_cond}
				ORDER BY object_type, builtin_code, record_type, [language]
			",
			'meta_class' => "
				SELECT uuid, original, record_type, [language], inactive, removed, class_name, storage_object, ancestor_class, sort_code, svg_icon, is_final, is_protected, caption, caption_plural, description, helptext, editor_note
				FROM meta_class
				WHERE object_owner = 0x00 {$lang_cond}
				ORDER BY CASE WHEN class_name = 'sys_global_columns' THEN 0 ELSE 1 END, class_name, record_type, [language]
			",
			'meta_column' => "
				SELECT uuid, original, record_type, [language], inactive, removed, parent_class, parent_order, sort_code, column_name, list_order, caption, caption_plural, description, label, header, helptext, placeholder, editor_note, input_type, input_width, input_rows, max_length, css_class, translate, history, is_html, is_mandatory, is_url, is_computed, show_empty, hidden, customizable, ancestor, referenced_codetable, referenced_class, is_final, is_protected
				FROM meta_column
				WHERE object_owner = 0x00 {$lang_cond}
				ORDER BY parent_class, parent_order, column_name, record_type, [language]
			",
			'meta_menu' => "
				SELECT uuid, original, record_type, [language], inactive, removed, builtin_code, parent_uuid, sort_code, target_object, url_parameters, target_url, target_window, caption, description, helptext, editor_note, svg_icon, css_class, system_role, permanent, is_final, is_protected
				FROM meta_menu
				WHERE object_owner = 0x00 {$lang_cond}
				ORDER BY CASE WHEN parent_uuid IS NULL THEN 0 ELSE 1 END, sort_code, builtin_code, record_type, [language]
			",
			'meta_phrase' => "
				SELECT uuid, original, record_type, [language], inactive, removed, source_code, builtin_code, module, caption, helptext, editor_note, svg_icon, css_class, is_final, is_protected
				FROM meta_phrase
				WHERE object_owner = 0x00 {$lang_cond}
				ORDER BY source_code, builtin_code, record_type, [language]
			",
			'meta_codetable' => "
				SELECT uuid, original, record_type, [language], inactive, removed, codetable_name, value_code, caption, description, helptext, sort_code, svg_icon, color_code, is_final, is_protected
				FROM meta_codetable
				WHERE object_owner = 0x00 {$lang_cond}
				ORDER BY codetable_name, sort_code, value_code, record_type, [language]
			",
			'meta_link_def' => "
				SELECT uuid, original, record_type, [language], inactive, removed, link_code, from_class, to_class, caption_forward, caption_backward, description, helptext, is_multiple, is_mandatory, leaf_only, transfer_roles, link_weight_enabled, is_final, is_protected
				FROM meta_link_def
				WHERE object_owner = 0x00 {$lang_cond}
				ORDER BY link_code, record_type, [language]
			"
		];                                                                   // Konec kompletních exportních dotazů
	}

	/**
	 * Vrátí definici tabulek a povinných sloupců pro formální kontrolu ve Fázi 1 importu.
	 *
	 * @return array<string, array<string, mixed>>
	 */
	public function get_tables_definition(): array {
		return [                                                             // Definice tabulek a klíčových sloupců balíčku metadata
			'meta_object' => [
				'mandatory' => true,
				'columns'   => [
					'original'     => ['datatype' => 'uuid',    'mandatory' => true],
					'record_type'  => ['datatype' => 'varchar', 'mandatory' => true],
					'language'     => ['datatype' => 'varchar', 'mandatory' => true],
					'object_type'  => ['datatype' => 'varchar', 'mandatory' => true],
					'builtin_code' => ['datatype' => 'varchar', 'mandatory' => true]
				]
			],
			'meta_class' => [
				'mandatory' => true,
				'columns'   => [
					'original'       => ['datatype' => 'uuid',    'mandatory' => true],
					'record_type'    => ['datatype' => 'varchar', 'mandatory' => true],
					'language'       => ['datatype' => 'varchar', 'mandatory' => true],
					'class_name'     => ['datatype' => 'varchar', 'mandatory' => true],
					'storage_object' => ['datatype' => 'uuid',    'mandatory' => true]
				]
			],
			'meta_column' => [
				'mandatory' => true,
				'columns'   => [
					'original'     => ['datatype' => 'uuid',    'mandatory' => true],
					'record_type'  => ['datatype' => 'varchar', 'mandatory' => true],
					'language'     => ['datatype' => 'varchar', 'mandatory' => true],
					'parent_class' => ['datatype' => 'uuid',    'mandatory' => true],
					'column_name'  => ['datatype' => 'varchar', 'mandatory' => true]
				]
			],
			'meta_menu' => [
				'mandatory' => false,
				'columns'   => [
					'original'     => ['datatype' => 'uuid',    'mandatory' => true],
					'record_type'  => ['datatype' => 'varchar', 'mandatory' => true],
					'language'     => ['datatype' => 'varchar', 'mandatory' => true],
					'builtin_code' => ['datatype' => 'varchar', 'mandatory' => true]
				]
			],
			'meta_phrase' => [
				'mandatory' => false,
				'columns'   => [
					'original'     => ['datatype' => 'uuid',    'mandatory' => true],
					'record_type'  => ['datatype' => 'varchar', 'mandatory' => true],
					'language'     => ['datatype' => 'varchar', 'mandatory' => true],
					'source_code'  => ['datatype' => 'varchar', 'mandatory' => true],
					'builtin_code' => ['datatype' => 'varchar', 'mandatory' => true]
				]
			],
			'meta_codetable' => [
				'mandatory' => false,
				'columns'   => [
					'original'       => ['datatype' => 'uuid',    'mandatory' => true],
					'record_type'    => ['datatype' => 'varchar', 'mandatory' => true],
					'language'       => ['datatype' => 'varchar', 'mandatory' => true],
					'codetable_name' => ['datatype' => 'varchar', 'mandatory' => true],
					'value_code'     => ['datatype' => 'varchar', 'mandatory' => true]
				]
			],
			'meta_link_def' => [
				'mandatory' => false,
				'columns'   => [
					'original'    => ['datatype' => 'uuid',    'mandatory' => true],
					'record_type' => ['datatype' => 'varchar', 'mandatory' => true],
					'language'    => ['datatype' => 'varchar', 'mandatory' => true],
					'link_code'   => ['datatype' => 'varchar', 'mandatory' => true],
					'from_class'  => ['datatype' => 'uuid',    'mandatory' => true],
					'to_class'    => ['datatype' => 'uuid',    'mandatory' => true]
				]
			]
		];                                                                   // Konec definice tabulek balíčku
	}
}