<?php
/**
 * =============================================================================
 * Verze: 2026-10-24 23:50
 * Soubor: csv_package_metadata.php
 * Třída: csv_package_metadata
 * Účel: Konkrétní implementace CSV balíčku "metadata" pro přenos kompletních
 *       systémových metadat (`object_owner = 0x00`: `meta_object`, `meta_class`,
 *       `meta_column`, `meta_menu`, `meta_phrase`, `meta_codetable`, `meta_link_def`)
 *       ve všech jazykových verzích (`A` + `L`) mezi instancemi systému BCM Osiris.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Dědí z `abstract_csv_package` (`abstract_csv_package.php`).
 * - Nastavuje `$this->is_system_package = true`, protože systémová metadata (`0x00`)
 *   se při importu zapisují přímo do `'A'` a `'L'` záznamů (nevytvářejí koncepty `'D'`).
 * - Nepoužívá žádné filtrační parametry – vždy exportuje všechna metadata vlastněná
 *   systémem (`object_owner = 0x00`) ve všech jazycích.
 * - Ve Fázi 2 importu volá uloženou proceduru `p_csv_import_metadata`.
 *
 * Změny:
 * 2026-10-24 23:50 - Do exportního dotazu tabulky meta_class doplněn sloupec days_in_trash.
 * 2026-10-24 20:05 - Odstraněny filtrační parametry `language_filter` a `class_filter`.
 *                    Balíček vždy exportuje kompletní systémová metadata ve všech jazycích.
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
		$this->description = $this->phrase('pkg_desc', 'Export a dvoufázový import kompletních systémových metadat (object_owner = 0x00) ve všech jazycích ve víceblokovém CSV formátu.'); // Popis
		$this->is_system_package = true;                                     // Systémová data (0x00) nevytvářejí koncepty ke schválení
	}

	/**
	 * Balíček metadat nepoužívá žádné dodatečné filtry (vždy vrací všechna systémová metadata ve všech jazycích).
	 *
	 * @return array<string, array<string, mixed>>
	 */
	public function get_filter_parameters_def(): array {
		return [];                                                           // Žádné filtrační parametry
	}

	/**
	 * Sestaví SQL dotazy pro export všech systémových metadatových tabulek (`object_owner = 0x00`)
	 * ve všech jazykových verzích (`record_type IN ('A', 'L')`).
	 *
	 * @param array<string, string> $params Parametry exportu
	 * @return array<string, string>
	 */
	public function get_export_tables_sql(array $params): array {            // Sestavení exportních dotazů pro tabulky
		return [                                                             // Dotazy pro kompletní systémová metadata ve všech jazycích
			'meta_object' => "
				SELECT uuid, original, record_type, [language], inactive, removed, object_type, builtin_code, system_role, module, caption, caption_plural, description, helptext, editor_note
				FROM meta_object
				WHERE object_owner = 0x00 AND record_type IN ('A', 'L')
				ORDER BY object_type, builtin_code, record_type, [language]
			",
			'meta_class' => "
				SELECT uuid, original, record_type, [language], inactive, removed, class_name, storage_object, ancestor_class, sort_code, days_in_trash, svg_icon, is_final, is_protected, caption, caption_plural, description, helptext, editor_note
				FROM meta_class
				WHERE object_owner = 0x00 AND record_type IN ('A', 'L')
				ORDER BY CASE WHEN class_name = 'sys_global_columns' THEN 0 ELSE 1 END, class_name, record_type, [language]
			",
			'meta_column' => "
				SELECT uuid, original, record_type, [language], inactive, removed, parent_class, parent_order, sort_code, column_name, list_order, caption, caption_plural, description, label, header, helptext, placeholder, editor_note, input_type, input_width, input_rows, max_length, css_class, translate, history, is_html, is_mandatory, is_url, is_computed, show_empty, hidden, customizable, ancestor, referenced_codetable, referenced_class, is_final, is_protected
				FROM meta_column
				WHERE object_owner = 0x00 AND record_type IN ('A', 'L')
				ORDER BY parent_class, parent_order, column_name, record_type, [language]
			",
			'meta_menu' => "
				SELECT uuid, original, record_type, [language], inactive, removed, builtin_code, parent_uuid, sort_code, target_object, url_parameters, target_url, target_window, caption, description, helptext, editor_note, svg_icon, css_class, system_role, permanent, is_final, is_protected
				FROM meta_menu
				WHERE object_owner = 0x00 AND record_type IN ('A', 'L')
				ORDER BY CASE WHEN parent_uuid IS NULL THEN 0 ELSE 1 END, sort_code, builtin_code, record_type, [language]
			",
			'meta_phrase' => "
				SELECT uuid, original, record_type, [language], inactive, removed, source_code, builtin_code, module, caption, helptext, editor_note, svg_icon, css_class, is_final, is_protected
				FROM meta_phrase
				WHERE object_owner = 0x00 AND record_type IN ('A', 'L')
				ORDER BY source_code, builtin_code, record_type, [language]
			",
			'meta_codetable' => "
				SELECT uuid, original, record_type, [language], inactive, removed, codetable_name, value_code, caption, description, helptext, sort_code, svg_icon, color_code, is_final, is_protected
				FROM meta_codetable
				WHERE object_owner = 0x00 AND record_type IN ('A', 'L')
				ORDER BY codetable_name, sort_code, value_code, record_type, [language]
			",
			'meta_link_def' => "
				SELECT uuid, original, record_type, [language], inactive, removed, link_code, from_class, to_class, caption_forward, caption_backward, description, helptext, is_multiple, is_mandatory, leaf_only, transfer_roles, link_weight_enabled, is_final, is_protected
				FROM meta_link_def
				WHERE object_owner = 0x00 AND record_type IN ('A', 'L')
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