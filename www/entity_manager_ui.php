<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 11:45
 * Soubor: entity_manager_ui.php
 * Trait: entity_manager_ui
 * Účel: Prezentační a UI vrstva třídy entity_manager.
 *       Zajišťuje kontrolu uzamčení hierarchie (is_hierarchy_node_locked přes
 *       databázovou funkci dbo.f_is_hierarchy_node_locked), vyhodnocení oprávnění
 *       pro rušení záznamů (evaluate_remove_permission, render_removed_section)
 *       a vykreslování dynamických vstupních prvků (render_dynamic_input přes
 *       databázovou proceduru dbo.p_em_get_select_options a službu rich_text).
 *
 * VAZBY NA OKOLÍ:
 * - Inkludován a používán výhradně uvnitř třídy `entity_manager` (`entity_manager.php`).
 * - Volá databázovou funkci `dbo.f_is_hierarchy_node_locked` (`p_sync_derived_links.sql`)
 *   a uloženou proceduru `dbo.p_em_get_select_options` (`p_em_metadata.sql`).
 * - Využívá třídu `rich_text` (`rich_text.php`) pro sloupce s `is_html = 1`.
 * =============================================================================
 */

declare(strict_types=1);

trait entity_manager_ui {

	/**
	 * Ověří, zda je daný uzel hierarchie uzamčen proti přepodřízení (změně parent_uuid),
	 * zrušení příznaku koncového uzlu (is_leaf: 1 -> 0) nebo smazání (removed = 1),
	 * zavoláním databázové funkce dbo.f_is_hierarchy_node_locked.
	 */
	public function is_hierarchy_node_locked(string $node_original): bool {  // Kontrola uzamčení větve hierarchie
		$clean_orig = strtolower(trim($node_original));                      // Normalizace UUID uzlu
		if ($clean_orig === '' OR $clean_orig === 'new' OR is_zero_guid($clean_orig)) { // Kořen nebo nový záznam
			return false;                                                    // Nový nebo kořenový uzel není uzamčen vazbou
		}
		if (! $this->has_physical_column('parent_uuid') OR $this->storage_table === 'meta_menu') { // Mimo věcné hierarchie CRMM
			return false;                                                    // Navigace menu se neuzamyká tabulkou link
		}
		if (isset($this->hierarchy_lock_cache[$clean_orig])) {               // Kontrola v lokální keši requestu
			return $this->hierarchy_lock_cache[$clean_orig];                 // Vrácení kešovaného výsledku
		}

		$orig_sql = guidliteral($clean_orig);                                // Bezpečný SQL literál kontrolovaného uzlu
		if ($orig_sql === 'NULL') {                                          // Neplatný formát UUID
			return false;                                                    // Ukončení kontroly
		}

		global $dbsession;                                                   // Globální kontext relace
		$org_sql = guidliteral((string)($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace
		$safe_tab = charliteral($this->storage_table, 128);                  // SQL literál názvu tabulky

		$row = sqlfirstrow("SELECT dbo.f_is_hierarchy_node_locked({$safe_tab}, {$orig_sql}, {$org_sql}) AS is_locked"); // Volání DB funkce
		$is_locked = ! empty($row['is_locked']);                             // Výsledek kontroly uzamčení
		$this->hierarchy_lock_cache[$clean_orig] = $is_locked;               // Uložení do keše pro aktuální request
		return $is_locked;                                                   // Vrácení stavu uzamčení větve
	}

	/**
	 * Vyhodnotí, zda má přihlášený uživatel právo označit daný záznam (nebo jeho jazykovou mutaci)
	 * jako zrušený (`removed = 1`) či jej obnovit (`removed = 0`), a vrátí případný důvod uzamčení.
	 */
	public function evaluate_remove_permission(array $datarow, bool $is_mine): array { // Vyhodnocení oprávnění pro removed
		global $dbsession;                                                   // Globální kontext relace
		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role uživatele (U, A, S, D)
		$org_uuid_raw = (string)($dbsession['organization'] ?? '0x00');      // UUID aktivní organizace
		$sess_lang_raw = (string)($dbsession['language'] ?? 'cs');           // Jazyk aktivní relace
		$right_translate = ! empty($dbsession['right_translate']);           // Oprávnění ke globálnímu překladu

		$is_sysadmin_org = is_zero_guid($org_uuid_raw);                      // Zda uživatel pracuje v systémové organizaci 0x00
		$rec_lang = (string)($datarow['native_language'] ?? $datarow['language'] ?? 'cs'); // Mateřský jazyk 'A' záznamu
		$is_native_lang = ($rec_lang === $sess_lang_raw);                    // Zda uživatel pracuje v mateřském jazyce záznamu

		// 1. Práce v sekundárním jazyce (jazyková mutace 'L')
		if (! $is_native_lang) {                                             // Pokud jde o sekundární jazyk
			if ($is_sysadmin_org OR $right_translate OR $is_mine) {          // Oprávněný překladatel nebo vlastník
				$note_l = $this->phrase('msg_remove_lang_mutation_only', 'Ruší pouze jazykovou mutaci ({' . chr(36) . 'lang})', ['lang' => $sess_lang_raw]); // Poznámka k rušení L
				return ['allowed' => true, 'is_lang_only' => true, 'reason' => $note_l]; // Povoleno zrušení překladu L
			}
			$deny_l = $this->phrase('msg_remove_lang_denied', 'Nemáte oprávnění rušit systémové překlady tohoto jazyka'); // Důvod zákazu
			return ['allowed' => false, 'is_lang_only' => true, 'reason' => $deny_l]; // Zákaz rušení cizího překladu
		}

		// 1b. Kontrola pro všechny hierarchické tabulky (zákaz zrušení uzlu 0x00, uzlu s aktivními potomky nebo uzamčené větve)
		$orig_val_raw = (string)($datarow['original'] ?? '');                // Surové UUID originálu záznamu
		$orig_sql = guidliteral($orig_val_raw);                              // SQL literál originálu záznamu
		if (is_zero_guid($orig_val_raw) AND $orig_val_raw !== '') {          // Kořenový záznam 0x00
			$deny_root = $this->phrase('msg_remove_root_0x00_denied', 'Systémový kořenový záznam (0x00) nelze zrušit'); // Důvod zákazu
			return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_root]; // Uzamčeno
		}

		if ($this->has_physical_column('parent_uuid') AND empty($datarow['removed']) AND $orig_sql !== 'NULL') { // Platný uzel hierarchie
			$tab = $this->storage_table;                                     // Fyzická tabulka hierarchie
			$ch_row = sqlfirstrow("SELECT TOP 1 1 AS has_ch FROM [{$tab}] WHERE parent_uuid = {$orig_sql} AND record_type = 'A' AND removed = 0"); // Kontrola aktivních potomků
			if (! empty($ch_row)) {                                          // Uzel má aktivní podřízené položky
				$deny_ch = $this->phrase('msg_remove_node_has_children', 'Uzel hierarchie nelze zrušit, dokud obsahuje aktivní podřízené položky'); // Důvod
				return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_ch]; // Uzamčeno
			}
			if ($this->is_hierarchy_node_locked($orig_val_raw)) {            // Kontrola aktivních vazeb na uzlu nebo podstromu
				$deny_lk = $this->phrase('msg_remove_node_locked_by_links', 'Uzel hierarchie nelze zrušit, protože jsou na něj navázány platné záznamy'); // Důvod
				return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_lk]; // Uzamčeno
			}
		}

		// 2. Práce v primárním jazyce u systémové organizace (0x00)
		if ($is_sysadmin_org) {                                              // Systémová organizace 0x00
			if ($this->is_metadata_entity() AND $active_role !== 'D') {      // Metadata smí rušit jen Developer ('D')
				$deny_d = $this->phrase('msg_remove_meta_only_dev', 'Systémová metadata smí rušit pouze vývojář (Developer)'); // Důvod pro roli
				return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_d]; // Uzamčeno mimo roli D
			}

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
					if (! empty($stg_row) AND (string)$stg_row['builtin_code'] === $cls_name) { // Primitivní třída existující tabulky
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
					if (! empty($phys_row)) {                                // Sloupec fyzicky existuje v databázi
						$deny_col = $this->phrase('msg_remove_phys_col_denied', 'Fyzicky existující sloupec databázové tabulky nelze v metadatech zrušit'); // Důvod
						return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_col]; // Uzamčeno
					}
				}
			} elseif ($this->storage_table === 'meta_menu') {                // Kontrola tabulky meta_menu
				$b_code = (string)($datarow['builtin_code'] ?? '');          // Kód položky menu
				if ($b_code === 'home') {                                    // Kořenovou položku Domů nelze zrušit
					$deny_hm = $this->phrase('msg_remove_menu_home_denied', 'Kořenovou položku menu (home) nelze zrušit'); // Důvod
					return ['allowed' => false, 'is_lang_only' => false, 'reason' => $deny_hm]; // Uzamčeno
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
	 */
	public function render_removed_section(array $datarow, bool $is_mine, bool $force_readonly = false): string { // Vykreslení sekce removed
		$perm = $this->evaluate_remove_permission($datarow, $is_mine);       // Vyhodnocení oprávnění ke zrušení záznamu
		$can_remove = (! $force_readonly AND $perm['allowed']);              // Zda je checkbox aktivní pro editaci
		$is_lang_only = $perm['is_lang_only'];                               // Zda se ruší pouze jazyková mutace 'L'
		$reason_note = $perm['reason'];                                      // Doplňková poznámka nebo důvod uzamčení
		$is_draft_rec = ((string)($datarow['record_type'] ?? 'A') === 'D');  // Zda jde o rozpracovaný koncept 'D'

		$rem_val = ($is_lang_only AND ! $is_draft_rec)
			? (! empty($datarow['l_removed']) ? '1' : '0')                   // Hodnota removed pro schválenou jazykovou mutaci 'L'
			: (! empty($datarow['removed']) ? '1' : '0');                    // Hodnota removed pro hlavní záznam 'A' nebo koncept 'D'

		$checked = ($rem_val === '1') ? 'checked' : '';                      // Atribut checked
		$row_bg = ($rem_val === '1') ? 'background-color: #fef2f2;' : '';    // Červené podbarvení při aktivním zrušení
		$lbl_rem = htmlspecialchars($this->phrase('lbl_record_removed', 'Zrušený záznam (removed)')); // Popisek pole removed
		$confirm_msg = addslashes($this->phrase('confirm_mark_removed', 'Potvrďte, že chcete tuto položku označit jako zrušenou.')); // Text JS confirm

		$note_html = ($reason_note !== '')
			? "<span style=\"margin-left: 10px; font-size: 12px; color: #64748b; font-style: italic;\">(" . htmlspecialchars($reason_note) . ")</span>"
			: "";                                                            // HTML poznámky vedle checkboxu

		if (! $can_remove) {                                                 // Vykreslení uzamčeného checkboxu removed
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
	 * Využívá proceduru dbo.p_em_get_select_options pro plnění roletek a službu rich_text pro is_html = 1.
	 */
	public function render_dynamic_input(string $column_name, string $value, bool $is_mine = true, bool $force_readonly = false): string { // Vykreslení formulářového prvku
		$meta = $this->get_column_meta($column_name);                        // Načtení metadat sloupce
		if (empty($meta)) {                                                  // Kontrola existence metadat sloupce
			return "<!-- Neznámý sloupec: {$column_name} -->";               // HTML komentář pro neznámý sloupec
		}

		if ($column_name === 'svg_icon') {                                   // Speciální neredigovatelný náhled pro svg_icon
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
		$curr_guid = trim((string)getinput('update_guid'));                  // Identifikátor právě otevřeného záznamu

		$type = $meta['input_type'] ?: 'text';                               // Výchozí typ prvku je text
		$safe_name = htmlspecialchars($column_name);                         // Ošetřený název prvku
		$safe_val = htmlspecialchars($value);                                // Ošetřená hodnota prvku

		$attrs = [];                                                         // Pole HTML atributů
		if (! empty($meta['css_class'])) {                                   // Pokud má sloupec CSS třídu
			$attrs[] = "class=\"" . htmlspecialchars((string)$meta['css_class']) . "\""; // Atribut class
		}
		if (! empty($meta['placeholder'])) {                                 // Pokud má sloupec placeholder
			$attrs[] = "placeholder=\"" . htmlspecialchars((string)$meta['placeholder']) . "\""; // Atribut placeholder
		}
		if (! empty($meta['max_length'])) {                                  // Pokud má sloupec omezení délky
			$attrs[] = "maxlength=\"{$meta['max_length']}\"";                // Atribut maxlength
		}

		$is_key_col = (in_array($column_name, $this->original_key_cols, true) AND $column_name !== 'ancestor_link'); // Povinný klíčový sloupec
		if (! empty($meta['is_mandatory']) OR $is_key_col) {                 // Pokud je sloupec povinný v metadatech nebo je klíčem originálu
			$attrs[] = "required";                                           // HTML5 atribut required
		}

		$is_readonly = $force_readonly;                                      // Výchozí stav uzamčení dle panelu
		if ($curr_guid !== '' AND $curr_guid !== 'NEW' AND in_array($column_name, $this->original_key_cols, true)) { // Existující záznam
			$is_readonly = true;                                             // Uzamčení klíčového sloupce u existujícího záznamu
		} elseif ($this->storage_table === 'hierarchy_item' AND $column_name === 'hierarchy' AND $value !== '') { // Předvyplněná hierarchie v hierarchy_item
			$is_readonly = true;                                             // Uzamčení nadřízené hierarchie proti nechtěnému přepnutí
		} elseif (! empty($meta['is_computed'])) {                           // Kontrola vypočítávaného sloupce
			$is_readonly = true;                                             // Vypočítávaný sloupec nelze měnit
		} elseif ($this->is_metadata_entity() AND $active_role !== 'D' AND empty($meta['translate'])) { // Ochrana metadat mimo roli D
			$is_readonly = true;                                             // Uzamčení funkčního atributu metadat
		} elseif (! $is_mine AND ! empty($meta['is_protected']) AND empty($meta['translate'])) { // Ochrana chráněných sloupců
			$is_readonly = true;                                             // Chráněný systémový sloupec
		}

		if (! $is_readonly AND $curr_guid !== '' AND $curr_guid !== 'NEW') { // Kontrola uzamčení u existujícího uzlu stromu
			if ($column_name === 'parent_uuid' AND $this->is_hierarchy_node_locked($curr_guid)) { // Přepodřizování uzamčené větve
				$is_readonly = true;                                         // Uzamčení parent_uuid kvůli existujícím vazbám
			} elseif ($column_name === 'is_leaf') {                          // Kontrola příznaku koncového uzlu
				$curr_sql = guidliteral($curr_guid);                         // SQL literál aktuálního uzlu
				if ($value === '1' AND $this->is_hierarchy_node_locked($curr_guid)) { // Koncový uzel s navázanými záznamy
					$is_readonly = true;                                     // Nelze odškrtnout is_leaf u obsazeného listu
				} elseif ($this->has_physical_column('parent_uuid') AND $curr_sql !== 'NULL') { // Kontrola, zda nemá podřízené uzly
					$tab = $this->storage_table;                             // Fyzická tabulka hierarchie
					$has_ch = sqlfirstrow("SELECT TOP 1 1 AS ex FROM [{$tab}] WHERE parent_uuid = {$curr_sql} AND record_type = 'A' AND removed = 0"); // Dotaz na potomky
					if (! empty($has_ch)) {                                  // Uzel již obsahuje podřízené položky
						$is_readonly = true;                                 // Složku s potomky nelze označit jako list (is_leaf = 1)
					}
				}
			}
		}

		$input_width = $meta['input_width'] ?: '100%';                       // Šířka vstupního pole
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

		// 1. Speciální podpora pro sloupec licence_level
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

		// 1b. Speciální podpora pro sloupec preferred_language
		if ($column_name === 'preferred_language') {                         // Roletka pro preferovaný jazyk organizace
			$eff_lang = ($value !== '') ? $value : 'cs';                     // Výchozí hodnota čeština
			$safe_eff_lang = htmlspecialchars($eff_lang);                    // Ošetřený kód jazyka pro hidden pole
			$options_html = '';                                              // HTML voleb jazyků
			foreach ($this->lang_manager->get_languages() as $l_code => $l_row) { // Průchod podporovanými jazyky z keše
				$l_cap = (string)($l_row['caption'] ?? $l_code);             // Název jazyka
				$sel = ((string)$l_code === $eff_lang) ? 'selected' : '';    // Označení vybraného jazyka
				$options_html .= "<option value=\"" . htmlspecialchars((string)$l_code) . "\" {$sel}>" . htmlspecialchars("{$l_cap} ({$l_code})") . "</option>"; // Volba jazyka
			}
			$lng_style = $is_readonly ? "disabled style=\"background-color: #f4f4f4; width: 220px; padding: 6px;\"" : "style=\"width: 220px; padding: 6px;\""; // Styl roletky
			if ($is_readonly) {                                              // Zamčená roletka jazyka
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_eff_lang}\"><select {$lng_style}>{$options_html}</select>"; // Zamčený select
			}
			return "<select name=\"{$safe_name}\" {$lng_style}>{$options_html}</select>"; // Aktivní select jazyka
		}

		// 2. Speciální podpora pro sloupec source_code v tabulce meta_phrase (přes dbo.p_em_get_select_options)
		if ($this->storage_table === 'meta_phrase' AND $column_name === 'source_code') { // Roletka pro source_code
			$eff_value = ($value === '') ? 'global_phrase' : $value;         // Prázdný source_code mapujeme na global_phrase
			$safe_eff_val = htmlspecialchars($eff_value);                    // Ošetřená hodnota pro hidden pole
			$lbl_global = htmlspecialchars($this->phrase('opt_global_phrase_source', 'global_phrase (Globální fráze systému)')); // Popisek globální fráze
			$sel_global = ($eff_value === 'global_phrase') ? 'selected' : ''; // Označení globální fráze
			$options_html = "<option value=\"global_phrase\" {$sel_global}>{$lbl_global}</option>"; // Výchozí volba global_phrase

			$src_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'source_code'"); // Načtení PHP tříd přes proceduru
			if (is_array($src_rows)) {                                       // Kontrola platného pole výsledků
				foreach ($src_rows as $r_src) {                              // Průchod registrovanými PHP třídami
					$b_code = (string)$r_src['value_code'];                  // Název PHP třídy
					$b_cap = (string)$r_src['caption'];                      // Přeložený popisek třídy
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

		// 3. Generování <select> seznamů pro číselníky (referenced_codetable přes dbo.p_em_get_select_options)
		if (! empty($meta['referenced_codetable'])) {                        // Pokud je sloupec napojen na číselník
			$options_html = "<option value=\"\">{$lbl_select}</option>";     // Prázdná výchozí volba číselníku
			$safe_ct = charliteral((string)$meta['referenced_codetable'], 80); // Bezpečný literál číselníku
			$opt_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'codetable', @param_code = {$safe_ct}"); // Volání procedury

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

		// 4. Generování <select> seznamů pro relační odkazy (referenced_class přes dbo.p_em_get_select_options)
		if (! empty($meta['referenced_class'])) {                            // Pokud sloupec odkazuje na jinou třídu
			$options_html = "<option value=\"\">{$lbl_select}</option>";     // Prázdná výchozí volba relace
			$ref_class_uuid = guidliteral((string)$meta['referenced_class']); // UUID odkazované logické třídy
			$curr_sql = ($curr_guid !== '' AND $curr_guid !== 'NEW') ? guidliteral($curr_guid) : 'NULL'; // Aktuální záznam
			$val_sql = guidliteral($value);                                  // Aktuální hodnota pole
			$safe_col = charliteral($column_name, 80);                       // Název sloupce
			$safe_stg = charliteral($this->storage_table, 128);              // Fyzická tabulka aktuální třídy

			if ($column_name === 'parent_uuid' AND $this->has_physical_column('parent_uuid')) { // Stromová vazba na rodiče
				global $datarow;                                             // Aktuální řádek detailu
				$h_uuid = trim((string)($datarow['hierarchy'] ?? getinput('hierarchy'))); // Případná nadřazená hierarchie
				$hier_sql = ($h_uuid !== '') ? guidliteral($h_uuid) : 'NULL'; // SQL literál hierarchie
				$items = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'parent_tree', @param_code = {$safe_col}, @ref_class_uuid = {$ref_class_uuid}, @curr_guid = {$curr_sql}, @current_val = {$val_sql}, @hier_uuid = {$hier_sql}, @storage_table = {$safe_stg}"); // Stromové položky
			} else {
				$items = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'ref_class', @param_code = {$safe_col}, @ref_class_uuid = {$ref_class_uuid}, @curr_guid = {$curr_sql}, @current_val = {$val_sql}, @storage_table = {$safe_stg}"); // Položky odkazované třídy
			}

			if (is_array($items)) {                                          // Kontrola platného pole položek relace
				foreach ($items as $item) {                                  // Sestavení voleb relační roletky
					$item_uuid = (string)$item['original'];                  // UUID položky v roletce
					$item_code = (string)$item['code_col'];                  // Technický kód položky
					$item_cap = (string)$item['caption'];                    // Přeložený název položky
					$sel = (strcasecmp($item_uuid, $value) === 0) ? 'selected' : ''; // Porovnání UUID bez ohledu na velikost písmen
					$item_label = ($item_code !== '' AND $item_cap !== '' AND $item_cap !== $item_code) ? "{$item_code} ({$item_cap})" : ($item_code ?: $item_cap ?: $item_uuid); // Text položky
					$options_html .= "<option value=\"" . htmlspecialchars($item_uuid) . "\" {$sel}>" . htmlspecialchars($item_label) . "</option>"; // Přidání volby
				}
			}

			if ($is_readonly) {                                              // Vykreslení zamčené relační roletky
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_val}\"><select disabled {$attr_string}>{$options_html}</select>"; // Zamčený select relace
			}
			return "<select name=\"{$safe_name}\" {$attr_string}>{$options_html}</select>"; // Aktivní select relace
		}

		// 5. Podpora formátovaného textu (Markdown / HTML) pro sloupce s příznakem is_html = 1:
		if (! empty($meta['is_html'])) {                                     // Sloupec podporuje formátovaný text (Markdown / HTML)
			if ($is_readonly) {                                              // V uzamčeném režimu vykreslíme bezpečný náhled bez tlačítka Upravit
				$rendered_view = rich_text::render_formatted($value, true);  // Zformátovaný náhled se štítkem formátu
				if ($rendered_view === '') {                                 // Pokud je hodnota v readonly režimu prázdná
					$lbl_empty = htmlspecialchars($this->phrase('lbl_empty_richtext', '(Prázdné)')); // Popisek prázdné hodnoty
					$rendered_view = "<span style=\"color: #94a3b8; font-style: italic; font-size: 12px;\">{$lbl_empty}</span>"; // Šedý text
				}
				return "<input type=\"hidden\" name=\"{$safe_name}\" value=\"{$safe_val}\">"
					. "<div style=\"padding: 8px 10px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; min-height: 36px;\">{$rendered_view}</div>"; // Readonly Preview box
			}
			return rich_text::render_editor($column_name, $value, $meta);    // Preview box s tlačítkem Upravit a modálním editorem na popředí
		}

		// 6. Standardní HTML prvky podle 'input_type'
		switch ($type) {                                                     // Rozlišení podle typu vstupního prvku
			case 'textarea':
				$rows = ! empty($meta['input_rows']) ? "rows=\"{$meta['input_rows']}\"" : "rows=\"3\""; // Počet řádků textarea
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
				$inputType = ! empty($meta['is_url']) ? 'url' : 'text';      // Rozlišení URL a běžného textu
				return "<input type=\"{$inputType}\" name=\"{$safe_name}\" value=\"{$safe_val}\" {$attr_string}>"; // Jednořádkové pole
		}
	}
}