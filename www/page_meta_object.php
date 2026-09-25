<?php
/**
 * =============================================================================
 * Verze: 2026-09-25 16:46
 * Soubor: page_meta_object.php
 * Účel: Hromadná editace metadat objektů a jejich sloupců.
 * Architektura: Master-Detail s rychlým klientským filtrem a hromadným gridem.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_object extends abstract_page_master_detail {

	private string $update_guid;

	public function __construct() {
		$this->page_title = 'Správa metadat objektů a sloupců';

		// Extrakce ID upravovaného záznamu (pokud je)
		$this->update_guid = (string)getinput('update_guid');

		// Zpracování dávkového uložení
		if (isset($_POST['btn_save'])) {
			$this->process_save();
		}
	}

	private function process_save(): void {
		// 1. Zpracování hlavičky objektu
		$obj_guid = guidliteral(getinput('update_guid'));
		$caption = charliteral(getinput('obj_caption', 1));
		$description = charliteral(getinput('obj_description', 1));
		$helptext = charliteral(getinput('obj_helptext', 1));

		sqlrun("EXEC form_meta_object @object_original=$obj_guid, @caption=$caption, @description=$description, @helptext=$helptext");

		// 2. Cyklické zpracování všech odeslaných sloupců
		if (!empty($_POST['col']) && is_array($_POST['col'])) {
			foreach ($_POST['col'] as $col_uuid => $data) {
				$c_guid = guidliteral((string)$col_uuid);
				$c_caption = charliteral($data['caption'] ?? '');
				$c_label = charliteral($data['label'] ?? '');
				$c_header = charliteral($data['header'] ?? '');
				$c_width = charliteral($data['width'] ?? '');
				$c_translate = empty($data['translate']) ? 0 : 1;

				sqlrun("EXEC form_meta_column @col_original=$c_guid, @caption=$c_caption, @label=$c_label, @header=$c_header, @input_width=$c_width, @translate=$c_translate");
			}
		}

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
			// Rychlý klientský live-filter pro zamezení AJAX přetížení
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

		// Načtení detailu objektu (1. resultset) a jeho sloupců (2. resultset)
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

		// Sticky kontejner pro hlavičku s tlačítkem
		echo <<<HTML
		<form method="post" action="index.php?page=meta_object&update_guid={$this->update_guid}">
			<div style="position: sticky; top: -20px; background: #fff; padding: 20px 0 10px 0; z-index: 100; border-bottom: 2px solid #004488; display: flex; justify-content: space-between; align-items: flex-end;">
				<h2 style="margin: 0; border: none; padding: 0;">Editace: {$code}</h2>
				<button type="submit" name="btn_save" class="btn btn-success">Uložit všechny změny</button>
			</div>

			<table class="md-table" style="margin-bottom: 30px;">
				<tr>
					<td style="width: 20%;"><strong>Zobrazovaný název:</strong></td>
					<td><input type="text" name="obj_caption" value="{$caption}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Popis (interní):</strong></td>
					<td><input type="text" name="obj_description" value="{$description}" style="width: 100%;"></td>
				</tr>
				<tr>
					<td><strong>Nápověda (UI):</strong></td>
					<td><input type="text" name="obj_helptext" value="{$helptext}" style="width: 100%;"></td>
				</tr>
			</table>

			<h3>Seznam sloupců</h3>
			<table class="md-table">
				<thead>
					<tr>
						<th style="width: 20%;">Sloupec (DB)</th>
						<th style="width: 20%;">Zobrazovaný název</th>
						<th style="width: 20%;">Štítek / Hlavička</th>
						<th style="width: 15%;">Šířka (UI)</th>
						<th style="width: 5%; text-align: center;">Překlad</th>
					</tr>
				</thead>
				<tbody>
HTML;

		// Přechod na 2. resultset (Sloupce vázané k objektu)
		next_result($q);
		while (fetch_datarow($q)) {
			$c_uuid = htmlspecialchars((string)$datarow['original']);
			$c_name = htmlspecialchars((string)$datarow['column_name']);
			
			$c_cap = htmlspecialchars((string)$datarow['caption']);
			$c_lab = htmlspecialchars((string)$datarow['label']);
			$c_head = htmlspecialchars((string)$datarow['header']);
			$c_width = htmlspecialchars((string)$datarow['input_width']);
			
			$c_trans = !empty($datarow['translate']) ? 'checked' : '';
			$is_protected = !empty($datarow['is_protected']) ? 'readonly style="background: #f4f4f4;"' : '';

			echo <<<HTML
				<tr>
					<td style="font-family: monospace; color: #555;">{$c_name}</td>
					<td><input type="text" name="col[{$c_uuid}][caption]" value="{$c_cap}" style="width: 100%;"></td>
					<td>
						<input type="text" name="col[{$c_uuid}][label]" value="{$c_lab}" style="width: 100%; margin-bottom: 4px;" placeholder="Label ve formuláři"><br>
						<input type="text" name="col[{$c_uuid}][header]" value="{$c_head}" style="width: 100%;" placeholder="Hlavička v tabulce">
					</td>
					<td><input type="text" name="col[{$c_uuid}][width]" value="{$c_width}" style="width: 100%;" {$is_protected}></td>
					<td style="text-align: center;"><input type="checkbox" name="col[{$c_uuid}][translate]" value="1" {$c_trans} {$is_protected}></td>
				</tr>
HTML;
		}
		free_result($q);

		echo <<<HTML
				</tbody>
			</table>
		</form>
HTML;
	}
}