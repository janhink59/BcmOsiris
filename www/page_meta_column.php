<?php
/**
 * =============================================================================
 * Verze: 2026-09-27
 * Soubor: page_meta_column.php
 * Účel: Detailní editace metadat konkrétního sloupce.
 * Vazby: 
 * - Voláno z page_meta_object.php přes parametr parent_object.
 * - Formulář čte a zapisuje data přes SQL procedury page_meta_column a form_meta_column.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_column extends abstract_page_master_detail {

	private string $parent_object;
	private string $update_guid;
	private string $parent_name = '';

	public function __construct() {
		$this->page_title = 'Správa metadat sloupce';

		$this->parent_object = (string)getinput('parent_object');
		$this->update_guid = (string)getinput('update_guid');

		// Zjištění informací o předkovi pro uživatelské rozhraní
		if ($this->parent_object !== '') {
			$q = sqlrun("EXEC page_meta_column @subpage='parent_info', @parent_object=" . guidliteral($this->parent_object));
			if ($row = fetch($q)) {
				$this->parent_name = $row['builtin_code'];
				$this->page_title = 'Sloupce: ' . $this->parent_name;
			}
			free_result($q);
		}

		if (isset($_POST['btn_save'])) {
			$this->process_save();
		}
	}

	private function process_save(): void {
		$col_original = guidliteral($this->update_guid);
		
		// Textové vlastnosti
		$sort_code = charliteral((string)getinput('c_sort_code'));
		$caption = charliteral((string)getinput('c_caption'));
		$label = charliteral((string)getinput('c_label'));
		$header = charliteral((string)getinput('c_header'));
		$helptext = charliteral((string)getinput('c_helptext'));
		$placeholder = charliteral((string)getinput('c_placeholder'));
		$input_type = charliteral((string)getinput('c_input_type'));
		$input_width = charliteral((string)getinput('c_input_width'));
		$css_class = charliteral((string)getinput('c_css_class'));
		
		// Číselné vlastnosti
		$input_rows = (string)getinput('c_input_rows') !== '' ? (int)getinput('c_input_rows') : 'NULL';
		$max_length = (string)getinput('c_max_length') !== '' ? (int)getinput('c_max_length') : 'NULL';
		
		// Příznaky (bity)
		$translate = getinput('c_translate') ? 1 : 0;
		$history = getinput('c_history') ? 1 : 0;
		$is_html = getinput('c_is_html') ? 1 : 0;
		$is_mandatory = getinput('c_is_mandatory') ? 1 : 0;
		$is_url = getinput('c_is_url') ? 1 : 0;
		$is_computed = getinput('c_is_computed') ? 1 : 0;
		$show_empty = getinput('c_show_empty') ? 1 : 0;
		$hidden = getinput('c_hidden') ? 1 : 0;
		$customizable = getinput('c_customizable') ? 1 : 0;

		sqlrun("EXEC form_meta_column 
			@col_original=$col_original, 
			@sort_code=$sort_code, 
			@caption=$caption, 
			@label=$label, 
			@header=$header, 
			@helptext=$helptext, 
			@placeholder=$placeholder, 
			@input_type=$input_type, 
			@input_width=$input_width, 
			@input_rows=$input_rows, 
			@max_length=$max_length, 
			@css_class=$css_class, 
			@translate=$translate, 
			@history=$history, 
			@is_html=$is_html, 
			@is_mandatory=$is_mandatory, 
			@is_url=$is_url, 
			@is_computed=$is_computed, 
			@show_empty=$show_empty, 
			@hidden=$hidden, 
			@customizable=$customizable"
		);

		autoredirect();
	}

	protected function render_master(): void {
		$safe_parent = htmlspecialchars($this->parent_name);
		
		echo <<<HTML
		<div style="margin-bottom: 20px;">
			<a href="index.php?page=meta_object&update_guid={$this->parent_object}" class="btn btn-secondary" style="display: block; text-align: center; margin-bottom: 15px;">&larr; Zpět na detail objektu</a>
			<h2 style="font-size: 16px; margin: 0;">Sloupce objektu: {$safe_parent}</h2>
		</div>
		
		<input type="text" id="column-filter" placeholder="Hledat sloupec..." style="width: 100%; margin-bottom: 10px; padding: 6px; box-sizing: border-box;">
		
		<table class="md-table">
			<thead>
				<tr>
					<th style="width: 30px;">Poř.</th>
					<th>DB Název</th>
				</tr>
			</thead>
			<tbody id="column-list">
HTML;

		if ($this->parent_object !== '') {
			$q = sqlrun("EXEC page_meta_column @subpage='list', @parent_object=" . guidliteral($this->parent_object));
			while ($row = fetch($q)) {
				$uuid = $row['column_uuid'];
				$name = htmlspecialchars($row['column_name']);
				$order = (int)$row['parent_order'];
				
				$rowClass = ($uuid === $this->update_guid) ? 'md-row-active' : '';
				$rowIdAttr = ($uuid === $this->update_guid) ? 'id="active-row"' : '';
				
				echo <<<HTML
					<tr class="{$rowClass}" {$rowIdAttr} style="cursor: pointer;" onclick="document.location='index.php?page=meta_column&parent_object={$this->parent_object}&update_guid={$uuid}'">
						<td style="text-align: center; color: #888;">{$order}</td>
						<td style="font-family: monospace;">{$name}</td>
					</tr>
HTML;
			}
			free_result($q);
		}

		echo <<<HTML
			</tbody>
		</table>

		<script>
			// Rychlý klientský live-filter
			document.getElementById('column-filter').addEventListener('input', function() {
				const term = this.value.toLowerCase();
				const rows = document.getElementById('column-list').querySelectorAll('tr');
				rows.forEach(row => {
					const text = row.textContent.toLowerCase();
					row.style.display = text.includes(term) ? '' : 'none';
				});
			});
		</script>
HTML;
	}

	protected function render_detail(): void {
		global $datarow;

		if ($this->update_guid === '') {
			echo "<div class='msg-info'>Vyberte sloupec z levého panelu k editaci jeho vlastností.</div>";
			return;
		}

		$q = sqlrun("EXEC page_meta_column @subpage='detail', @update_guid=" . guidliteral($this->update_guid));
		if (!fetch_datarow($q)) {
			echo "<div class='msg-err'>Sloupec nebyl nalezen.</div>";
			free_result($q);
			return;
		}

		// Přednačtení hodnot formuláře
		$c_name = htmlspecialchars((string)$datarow['column_name']);
		$c_sort = htmlspecialchars((string)$datarow['sort_code']);
		$c_cap = htmlspecialchars((string)$datarow['caption']);
		$c_lab = htmlspecialchars((string)$datarow['label']);
		$c_head = htmlspecialchars((string)$datarow['header']);
		$c_help = htmlspecialchars((string)$datarow['helptext']);
		$c_place = htmlspecialchars((string)$datarow['placeholder']);
		$c_type = htmlspecialchars((string)$datarow['input_type']);
		$c_width = htmlspecialchars((string)$datarow['input_width']);
		$c_rows = htmlspecialchars((string)$datarow['input_rows']);
		$c_max = htmlspecialchars((string)$datarow['max_length']);
		$c_css = htmlspecialchars((string)$datarow['css_class']);
		
		// Pomocná funkce pro checked
		$chk = fn($key) => !empty($datarow[$key]) ? 'checked' : '';
		
		// Zpracování dědičnosti (readonly příznaky)
		$is_protected_attr = !empty($datarow['is_protected']) ? 'readonly style="background: #f4f4f4;"' : '';
		$has_ancestor = !empty($datarow['ancestor']);
		
		$inherited_notice = $has_ancestor ? "<div style='color: #d97706; font-size: 12px; margin-bottom: 10px;'><b>Poznámka:</b> Tento sloupec dědí vlastnosti od svého předka. Můžete je zde přepsat (tenant override).</div>" : "";

		// Rozložení formuláře do sekcí
		echo <<<HTML
		<form method="post" action="index.php?page=meta_column&parent_object={$this->parent_object}&update_guid={$this->update_guid}">
			<div style="position: sticky; top: -20px; background: #fff; padding: 20px 0 10px 0; z-index: 100; border-bottom: 2px solid #004488; display: flex; justify-content: space-between; align-items: flex-end;">
				<h2 style="margin: 0; border: none; padding: 0;">Sloupec: <span style="font-family: monospace; color: #555;">{$c_name}</span></h2>
				<button type="submit" name="btn_save" class="btn btn-success">Uložit změny sloupce</button>
			</div>
			
			{$inherited_notice}

			<h3 style="margin-top: 20px; color: #004488; font-size: 15px;">Základní prezentační údaje</h3>
			<table class="md-table">
				<tr>
					<td style="width: 25%;"><strong>Zobrazovaný název (Caption):</strong></td>
					<td><input type="text" name="c_caption" value="{$c_cap}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Štítek (Label ve formuláři):</strong></td>
					<td><input type="text" name="c_label" value="{$c_lab}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Hlavička (Grid/Seznamy):</strong></td>
					<td><input type="text" name="c_header" value="{$c_head}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Placeholder (Šedý text):</strong></td>
					<td><input type="text" name="c_placeholder" value="{$c_place}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Text nápovědy (Helptext):</strong></td>
					<td><textarea name="c_helptext" style="width: 100%; height: 60px;">{$c_help}</textarea></td>
				</tr>
			</table>

			<h3 style="margin-top: 30px; color: #004488; font-size: 15px;">Formulářové vlastnosti (UI)</h3>
			<table class="md-table">
				<tr>
					<td style="width: 25%;"><strong>Typ vstupu (input_type):</strong></td>
					<td><input type="text" name="c_input_type" value="{$c_type}" style="width: 100%;" placeholder="text, number, date, checkbox, textarea..." {$is_protected_attr}></td>
				</tr>
				<tr>
					<td><strong>Šířka vstupu (input_width):</strong></td>
					<td><input type="text" name="c_input_width" value="{$c_width}" style="width: 100%;" placeholder="např. 100%, 250px" {$is_protected_attr}></td>
				</tr>
				<tr>
					<td><strong>Max. délka znaků (max_length):</strong></td>
					<td><input type="number" name="c_max_length" value="{$c_max}" style="width: 150px;" {$is_protected_attr}></td>
				</tr>
				<tr>
					<td><strong>Počet řádků (pro textarea):</strong></td>
					<td><input type="number" name="c_input_rows" value="{$c_rows}" style="width: 150px;" {$is_protected_attr}></td>
				</tr>
				<tr>
					<td><strong>Kód řazení (sort_code):</strong></td>
					<td><input type="text" name="c_sort_code" value="{$c_sort}" style="width: 150px;"></td>
				</tr>
				<tr>
					<td><strong>Custom CSS třída:</strong></td>
					<td><input type="text" name="c_css_class" value="{$c_css}" style="width: 100%;" placeholder="např. text-right, bold"></td>
				</tr>
			</table>

			<h3 style="margin-top: 30px; color: #004488; font-size: 15px;">Behaviorální příznaky</h3>
			<table class="md-table">
				<tr>
					<td style="width: 50%;"><label><input type="checkbox" name="c_translate" value="1" {$chk('translate')}> Překládat hodnoty sloupce</label></td>
					<td><label><input type="checkbox" name="c_history" value="1" {$chk('history')}> Uchovávat historii hodnot (Audit)</label></td>
				</tr>
				<tr>
					<td><label><input type="checkbox" name="c_is_mandatory" value="1" {$chk('is_mandatory')}> Povinné pole ve formuláři (is_mandatory)</label></td>
					<td><label><input type="checkbox" name="c_is_html" value="1" {$chk('is_html')} {$is_protected_attr}> Hodnota obsahuje RAW HTML (vypíná escapování)</label></td>
				</tr>
				<tr>
					<td><label><input type="checkbox" name="c_hidden" value="1" {$chk('hidden')}> Skrýt v UI (technické pole)</label></td>
					<td><label><input type="checkbox" name="c_is_url" value="1" {$chk('is_url')}> Formátovat jako odkaz (URL)</label></td>
				</tr>
				<tr>
					<td><label><input type="checkbox" name="c_show_empty" value="1" {$chk('show_empty')}> Zobrazovat label i u prázdné hodnoty</label></td>
					<td><label><input type="checkbox" name="c_is_computed" value="1" {$chk('is_computed')} {$is_protected_attr}> Počítaný sloupec (neukládá se zpět do DB)</label></td>
				</tr>
				<tr>
					<td><label><input type="checkbox" name="c_customizable" value="1" {$chk('customizable')}> Povolit uživateli zobrazení / skrytí pole</label></td>
					<td></td>
				</tr>
			</table>
		</form>
HTML;

		$this->render_audit_trail();
		free_result($q);
	}
}