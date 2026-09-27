<?php
/**
 * =============================================================================
 * Verze: 2026-09-27
 * Soubor: page_meta_object.php
 * Účel: Editace metadat databázových objektů (Master-Detail).
 * Změna: Oprava dvojité sanitizace textových hodnot (odstraněn 2. parametr z getinput).
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_object extends abstract_page_master_detail {

	private string $update_guid;

	public function __construct() {
		$this->page_title = 'Správa metadat objektů';

		// Extrakce ID upravovaného záznamu (pokud je)
		$this->update_guid = (string)getinput('update_guid');

		// Zpracování uložení detailu objektu
		if (isset($_POST['btn_save'])) {
			$this->process_save();
		}
	}

	private function process_save(): void {
		$obj_guid = guidliteral($this->update_guid);
		
		// OPRAVA: Striktní přetypování na string a odstranění parametru "1", 
		// který způsoboval dvojité přidávání apostrofů.
		$caption = charliteral((string)getinput('obj_caption'));
		$description = charliteral((string)getinput('obj_description'));
		$helptext = charliteral((string)getinput('obj_helptext'));
		
		$ancestor_input = (string)getinput('obj_ancestor');
		$column_ancestor = ($ancestor_input === '') ? 'NULL' : guidliteral($ancestor_input);

		sqlrun("EXEC form_meta_object @object_original=$obj_guid, @caption=$caption, @description=$description, @helptext=$helptext, @column_ancestor=$column_ancestor");

		autoredirect();
	}

	protected function render_master(): void {
		echo <<<HTML
		<h2>Seznam objektů</h2>
		<input type="text" id="object-filter" placeholder="Hledat objekt..." style="width: 100%; margin-bottom: 10px; padding: 6px; box-sizing: border-box;">
		
		<table class="md-table">
			<thead>
				<tr>
					<th>Kód (DB jméno)</th>
					<th>Zobrazovaný název</th>
				</tr>
			</thead>
			<tbody id="object-list">
HTML;

		$q = sqlrun("EXEC page_meta_object @subpage='list'");
		while ($row = fetch($q)) {
			$uuid = $row['object_uuid'];
			$code = htmlspecialchars($row['builtin_code']);
			$caption = htmlspecialchars($row['caption']);
			
			$rowClass = ($uuid === $this->update_guid) ? 'md-row-active' : '';
			$rowIdAttr = ($uuid === $this->update_guid) ? 'id="active-row"' : '';
			
			echo <<<HTML
				<tr class="{$rowClass}" {$rowIdAttr} style="cursor: pointer;" onclick="document.location='index.php?page=meta_object&update_guid={$uuid}'">
					<td>{$code}</td>
					<td>{$caption}</td>
				</tr>
HTML;
		}
		free_result($q);

		echo <<<HTML
			</tbody>
		</table>

		<script>
			// Rychlý klientský live-filter
			document.getElementById('object-filter').addEventListener('input', function() {
				const term = this.value.toLowerCase();
				const rows = document.getElementById('object-list').querySelectorAll('tr');
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

		if (!$this->update_guid) {
			echo "<div class='msg-info'>Vyberte objekt z levého panelu.</div>";
			return;
		}

		// Načtení detailu objektu a číselníku předků
		$q = sqlrun("EXEC page_meta_object @subpage='detail', @update_guid=" . guidliteral($this->update_guid));
		if (!fetch_datarow($q)) {
			echo "<div class='msg-err'>Objekt nebyl nalezen.</div>";
			free_result($q);
			return;
		}

		// Přednačtení vlastností objektu
		$caption = htmlspecialchars((string)$datarow['caption']);
		$code = htmlspecialchars((string)$datarow['builtin_code']);
		$description = htmlspecialchars((string)$datarow['description']);
		$helptext = htmlspecialchars((string)$datarow['helptext']);
		$current_ancestor = (string)$datarow['column_ancestor'];

		// Sestavení options pro rozevírací seznam předků (využije 2. resultset)
		$ancestor_options = '<option value="">--- Bez dědičnosti (vlastní sloupce) ---</option>';
		next_result($q);
		while (fetch_datarow($q)) {
			$a_uuid = (string)$datarow['ancestor_uuid'];
			$a_code = htmlspecialchars((string)$datarow['builtin_code']);
			$a_caption = htmlspecialchars((string)$datarow['caption']);
			
			$selected = ($a_uuid === $current_ancestor) ? 'selected' : '';
			$ancestor_options .= "<option value=\"{$a_uuid}\" {$selected}>{$a_code} ({$a_caption})</option>";
		}
		free_result($q);

		// Sticky kontejner pro hlavičku s tlačítky
		echo <<<HTML
		<form method="post" action="index.php?page=meta_object&update_guid={$this->update_guid}">
			<div style="position: sticky; top: -20px; background: #fff; padding: 20px 0 10px 0; z-index: 100; border-bottom: 2px solid #004488; display: flex; justify-content: space-between; align-items: flex-end;">
				<h2 style="margin: 0; border: none; padding: 0;">Editace: {$code}</h2>
				<div>
					<a href="index.php?page=meta_column&parent_object={$this->update_guid}" class="btn btn-secondary" style="margin-right: 10px;">Spravovat sloupce</a>
					<button type="submit" name="btn_save" class="btn btn-success">Uložit změny</button>
				</div>
			</div>

			<table class="md-table" style="margin-bottom: 30px;">
				<tr>
					<td style="width: 25%;"><strong>Zobrazovaný název:</strong></td>
					<td><input type="text" name="obj_caption" value="{$caption}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Předek (dědičnost sloupců):</strong><br><small style="color: #666;">View/Tabulka ze které se zkopírují vlastnosti</small></td>
					<td>
						<select name="obj_ancestor" style="width: 100%; padding: 4px;">
							{$ancestor_options}
						</select>
					</td>
				</tr>
				<tr>
					<td><strong>Popis (interní):</strong></td>
					<td><input type="text" name="obj_description" value="{$description}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Nápověda (UI):</strong></td>
					<td><textarea name="obj_helptext" style="width: 100%; height: 80px;">{$helptext}</textarea></td>
				</tr>
			</table>
		</form>
HTML;
		
		// Renderování standardní auditní stopy
		$this->render_audit_trail();
	}
}