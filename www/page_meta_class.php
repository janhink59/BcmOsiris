<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 22:52
 * Soubor: page_meta_class.php
 * Účel: Editace metadat logických tříd (STI architektura).
 * Nahrazuje původní page_meta_object.php.
 * 
 * Změny:
 * 2026-10-15 22:52 - Doplněno volání parent::__construct(), skryté pole update_guid,
 *                    sjednocen layout detailu (.md-detail-header / .md-detail-content)
 *                    a propojení na podřízenou stránku page_meta_column (Spravovat sloupce).
 * 2026-10-09 - Oprava vyhodnocení oprávnění (přechod z right_sysadmin na active_role).
 *            - Odstraněny redundantní metody process_save a render_master. 
 *              Kontrolu a blokování ($access_denied) plně přebral rodič.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_class extends abstract_page_master_detail {

	public function __construct() {
		parent::__construct();                                               // Inicializace frází a kontroly přístupu

		global $dbsession;                                                   // Globální kontext relace

		$this->page_title = 'Správa metadat logických tříd';                 // Titulek stránky
		$this->class_name = 'meta_class';                                    // Logická třída pro entity_manager

		$active_role = $dbsession['active_role'] ?? 'U';                     // Aktuální role uživatele
		if (!in_array($active_role, ['S', 'D'], true)) {
			$this->access_denied = true;                                     // Přístup pouze pro S a D
		}
	}

	protected function render_detail(): void {
		if ($this->em === null) {
			return;
		}

		$update_guid = (string)getinput('update_guid');                      // Získání ID vybrané třídy
		if ($update_guid === '') {
			echo "<div class='msg-info'>Vyberte třídu z levého panelu.</div>";
			return;
		}

		$sql = $this->em->build_select_query("m.original = " . guidliteral($update_guid));
		$q = sqlrun($sql);                                                   // Načtení detailu třídy
		
		global $datarow;                                                     // Globální pole pro aktuální záznam
		$datarow = fetch($q);                                                // Načtení dat do $datarow
		
		free_result($q);                                                     // Uvolnění výsledku dotazu
		
		if (!$datarow) {
			echo "<div class='msg-err'>Třída nebyla nalezena.</div>";
			return;
		}
		
		$is_mine = (bool)$datarow['object_is_mine'];                         // Příznak vlastnictví záznamu
		$code = htmlspecialchars((string)$datarow['class_name']);            // Technický název třídy
		
		$current_ancestor = (string)$datarow['ancestor_class'];              // Aktuálně nastavený předek třídy

		$ancestor_options = '<option value="">--- Bez dědičnosti (vlastní sloupce) ---</option>';
		$q_anc = sqlrun("SELECT original, class_name, caption FROM meta_class WHERE original <> " . guidliteral($update_guid) . " AND object_owner = 0x00 AND record_type = 'A' AND removed = 0 ORDER BY class_name");
		while ($anc = fetch($q_anc)) {
			$a_uuid = (string)$anc['original'];                              // UUID kandidáta na předka
			$a_code = htmlspecialchars((string)$anc['class_name']);          // Název třídy předka
			$a_caption = htmlspecialchars((string)$anc['caption']);          // Popisek třídy předka
			$selected = ($a_uuid === $current_ancestor) ? 'selected' : '';   // Označení vybraného předka
			$ancestor_options .= "<option value=\"{$a_uuid}\" {$selected}>{$a_code}" . ($a_caption !== '' ? " ({$a_caption})" : "") . "</option>";
		}
		free_result($q_anc);                                                 // Uvolnění výsledku dotazu

		// Zjištění počtu sloupců evidovaných u této logické třídy
		$col_count = 0;                                                      // Počet sloupců třídy
		$q_cnt = sqlrun("SELECT COUNT(DISTINCT original) AS cnt FROM meta_column WHERE parent_class = " . guidliteral($update_guid) . " AND record_type = 'A' AND removed = 0");
		if ($r_cnt = fetch($q_cnt)) {
			$col_count = (int)$r_cnt['cnt'];                                 // Načtení počtu sloupců
		}
		free_result($q_cnt);                                                 // Uvolnění výsledku dotazu

		$page_param = urlencode($this->get_current_page_name());             // Kanonický název stránky
		$discard_url = htmlspecialchars("index.php?page={$page_param}");
		$columns_url = htmlspecialchars("index.php?page=page_meta_column&parent_class=" . urlencode($update_guid));
		$safe_update_guid = htmlspecialchars($update_guid);                  // Ošetřené UUID pro hidden input

		echo <<<HTML
		<form method="post" action="index.php?page={$page_param}&update_guid={$safe_update_guid}" style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
			<input type="hidden" name="update_guid" value="{$safe_update_guid}">
			<div class="md-detail-header">
				<h2 style="margin: 0; border: none; padding: 0;">Editace: {$code}</h2>
				<div style="display: flex; gap: 10px; align-items: center;">
					<a href="{$discard_url}" class="btn btn-danger" onclick="isFormDirty = false;">Zahodit změny</a>
					<a href="{$columns_url}" class="btn btn-secondary">Spravovat sloupce ({$col_count}) &rarr;</a>
					<button type="submit" name="btn_save" value="1" class="btn btn-success">Uložit změny</button>
				</div>
			</div>

			<div class="md-detail-content">
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
						<td><strong>Předek (dědičnost sloupců):</strong><br><small style="color: #666;">Logická třída, ze které se zkopírují vlastnosti</small></td>
						<td>
							<select name="ancestor_class" style="width: 100%; padding: 4px;">
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
HTML;
		
		$this->render_audit_trail();                                         // Vykreslení auditní stopy

		echo "\t\t\t</div>\n\t\t</form>\n";
	}
}