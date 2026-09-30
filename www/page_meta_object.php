<?php
/**
 * =============================================================================
 * Verze: 2026-09-30
 * Soubor: page_meta_object.php
 * Účel: Editace metadat databázových objektů.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_object extends abstract_page_master_detail {

	public function __construct() {
		$this->page_title = 'Správa metadat objektů';
		$this->class_name = 'meta_object';
	}

	protected function process_save(): void {
		if (isset($_POST['column_ancestor']) and $_POST['column_ancestor'] === '') {
			$_POST['column_ancestor'] = '00000000-0000-0000-0000-000000000000';
		}
		parent::process_save();
	}

	protected function render_detail(): void {
		if ($this->em === null) return;

		$update_guid = (string)getinput('update_guid');
		if ($update_guid === '') {
			echo "<div class='msg-info'>Vyberte objekt z levého panelu.</div>";
			return;
		}

		$sql = $this->em->build_select_query("m.original = " . guidliteral($update_guid));
		$q = sqlrun($sql);
		
		global $datarow;
		$datarow = fetch($q);
		
		if (!$datarow) {
			echo "<div class='msg-err'>Objekt nebyl nalezen.</div>";
			return;
		}
		
		$is_mine = (bool)$datarow['object_is_mine'];
		$code = htmlspecialchars((string)$datarow['builtin_code']);
		
		$current_ancestor = (string)$datarow['column_ancestor'];
		if ($current_ancestor === '00000000-0000-0000-0000-000000000000') {
			$current_ancestor = '';
		}

		$ancestor_options = '<option value="">--- Bez dědičnosti (vlastní sloupce) ---</option>';
		$q_anc = sqlrun("SELECT original, builtin_code, caption FROM meta_object WHERE original <> " . guidliteral($update_guid) . " AND object_owner = 0x00 AND record_type = 'A' AND removed = 0 ORDER BY object_type, builtin_code");
		while ($anc = fetch($q_anc)) {
			$a_uuid = (string)$anc['original'];
			$a_code = htmlspecialchars((string)$anc['builtin_code']);
			$a_caption = htmlspecialchars((string)$anc['caption']);
			$selected = ($a_uuid === $current_ancestor) ? 'selected' : '';
			$ancestor_options .= "<option value=\"{$a_uuid}\" {$selected}>{$a_code} ({$a_caption})</option>";
		}

		$page_param = htmlspecialchars((string)getinput('page'));
		$discard_url = "index.php?page={$page_param}";

		echo <<<HTML
		<form method="post" action="index.php?page={$page_param}&update_guid={$update_guid}">
			<div class="md-sticky-header-detail">
				<h2 style="margin: 0; border: none; padding: 0;">Editace: {$code}</h2>
				<div>
					<a href="{$discard_url}" class="btn btn-danger" style="margin-right: 10px;" onclick="isFormDirty = false;">Zahodit změny</a>
					<a href="index.php?page=meta_column&parent_object={$update_guid}" class="btn btn-secondary" style="margin-right: 10px;">Spravovat sloupce</a>
					<button type="submit" name="btn_save" class="btn btn-success">Uložit změny</button>
				</div>
			</div>

			<table class="md-table" style="margin-bottom: 30px;">
				<tr>
					<td style="width: 30%;"><strong>Zobrazovaný název (j. č.):</strong></td>
					<td>{$this->em->render_dynamic_input('caption', (string)$datarow['caption'], $is_mine)}</td>
				</tr>
				<tr>
					<td><strong>Zobrazovaný název (mn. č.):</strong><br><small style="color: #666;">Zobrazí se v hlavičce levého panelu</small></td>
					<td>{$this->em->render_dynamic_input('caption_plural', (string)$datarow['caption_plural'], $is_mine)}</td>
				</tr>
				<tr>
					<td><strong>Předek (dědičnost sloupců):</strong><br><small style="color: #666;">View/Tabulka ze které se zkopírují vlastnosti</small></td>
					<td>
						<select name="column_ancestor" style="width: 100%; padding: 4px;">
							{$ancestor_options}
						</select>
					</td>
				</tr>
				<tr>
					<td><strong>Popis (interní):</strong></td>
					<td>{$this->em->render_dynamic_input('description', (string)$datarow['description'], $is_mine)}</td>
				</tr>
				<tr>
					<td><strong>Nápověda (UI):</strong></td>
					<td>{$this->em->render_dynamic_input('helptext', (string)$datarow['helptext'], $is_mine)}</td>
				</tr>
			</table>
		</form>
HTML;
		
		$this->render_audit_trail();
	}
}