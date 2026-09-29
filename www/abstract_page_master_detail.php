<?php
/**
 * =============================================================================
 * Třída: abstract_page_master_detail
 * Účel: Abstraktní třída rozšiřující základní stránku o dvoupamelový layout.
 *       Plně napojena na STI architekturu (Single Table Inheritance).
 *
 * Změny:
 * 2026-09-29 - Přechod z fyzických tabulek na logické třídy ($class_name).
 *            - Odstraněna manuální konfigurace list_columns. Levý panel se 
 *              generuje čistě automaticky na základě metadat (list_order).
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page_master_detail extends abstract_page {

	// --- Konfigurace pro data-driven vrstvu (nastavují potomci v konstruktoru) ---
	protected string $class_name = '';           // Identifikátor logické třídy (např. 'meta_object')
	protected string $master_where = '';         // Volitelné omezení (např. "m.parent_object = ...")
	
	protected ?entity_manager $em = null;

	public function render(): void {
		if ($this->class_name !== '') {
			$this->em = new entity_manager($this->class_name);
		}

		if (isset($_POST['btn_save'])) {
			$this->process_save();
		}

		if (isset($_GET['ajax_panel']) && $_GET['ajax_panel'] === 'master') {
			$this->render_master();
			exit;
		}
		parent::render();
	}

	protected function process_save(): void {
		if ($this->em === null) {
			return;
		}

		$update_guid = (string)getinput('update_guid');
		$this->em->save_post_data($update_guid);
		
		autoredirect();
	}

	final protected function render_body(): void {
		echo <<<HTML
		<style>
			.page-panel { 
				max-width: 95% !important; 
				padding: 0 !important; 
				display: flex; 
				flex-direction: row; 
				height: calc(100vh - 120px); 
				overflow: hidden; 
			}
			.md-master { 
				flex: 0 0 45%; 
				min-width: 400px;
				border-right: 1px solid #ddd; 
				background-color: #fafafa; 
				padding: 20px; 
				overflow-y: auto; 
				position: relative; 
			}
			.md-detail { 
				flex: 1; 
				padding: 20px 30px; 
				background-color: #ffffff; 
				overflow-y: auto; 
			}
			.md-master h2, .md-detail h2 {
				color: #004488;
				margin-top: 0;
				border-bottom: 2px solid #eee;
				padding-bottom: 10px;
			}
			.md-sticky-header-master {
				position: sticky;
				top: -20px;
				background-color: #fafafa;
				padding: 20px 0 10px 0;
				margin-top: -20px;
				z-index: 10;
				border-bottom: 2px solid #eee;
				margin-bottom: 10px;
			}
			.md-sticky-header-detail {
				position: sticky;
				top: -20px;
				background-color: #ffffff;
				padding: 20px 0 10px 0;
				margin-top: -20px;
				z-index: 100;
				border-bottom: 2px solid #004488;
				display: flex;
				justify-content: space-between;
				align-items: flex-end;
				margin-bottom: 20px;
			}
			.md-table {
				width: 100%;
				border-collapse: collapse;
				margin-top: 10px;
			}
			.md-table th {
				background-color: #e9f2fa;
				padding: 2px;
				border: 1px solid #ddd;
				text-align: left;
			}
			.md-table td {
				padding: 2px;
				border: 1px solid #ddd;
			}
			.md-table tr {
				background-color: #fff;
				color: #333;
			}
			.md-table tr:hover {
				background-color: #f1f1f1;
			}
			.md-row-active {
				background-color: #e6f7ff !important;
				color: #333 !important;
			}
			.md-row-inactive {
				background-color: #f9f9f9 !important;
				color: #999 !important;
			}
		</style>

		<div class="md-master" id="md-master-container">
HTML;
		$this->render_master();

		echo <<<HTML
		</div>
		<div class="md-detail">
HTML;
		$this->render_detail();

		echo <<<HTML
		</div>
		
		<script>
			function scrollToActiveRow() {
				const activeRow = document.getElementById("active-row");
				const masterPanel = document.getElementById("md-master-container");
				
				if (activeRow && masterPanel) {
					const panelRect = masterPanel.getBoundingClientRect();
					const rowRect = activeRow.getBoundingClientRect();
					const offset = rowRect.top - panelRect.top;
					masterPanel.scrollTop += offset - (panelRect.height / 2) + (rowRect.height / 2);
				}
			}

			function refreshMasterPanel() {
				const url = new URL(window.location.href);
				url.searchParams.set('ajax_panel', 'master');
				
				fetch(url.toString(), {
					headers: {
						'X-Requested-With': 'XMLHttpRequest'
					}
				})
				.then(response => {
					if (!response.ok) throw new Error("Chyba sítě při AJAX volání");
					return response.text();
				})
				.then(html => {
					const masterPanel = document.getElementById("md-master-container");
					if (masterPanel) {
						masterPanel.innerHTML = html;
						scrollToActiveRow();
					}
				})
				.catch(error => {
					console.error('Chyba při obnově master panelu:', error);
				});
			}

			document.addEventListener("DOMContentLoaded", function() {
				setTimeout(scrollToActiveRow, 50);
			});
		</script>
HTML;
	}

	protected function render_master(): void {
		if ($this->em === null) return;
		
		$list_columns = $this->em->get_list_columns();
		if (empty($list_columns)) {
			echo "<div class='msg-info'>Master panel nemá v metadatech (list_order) definované žádné sloupce.</div>";
			return;
		}

		$update_guid = (string)getinput('update_guid');
		
		$class_meta = $this->em->get_class_meta();
		$caption_plural = (string)($class_meta['caption_plural'] ?? '');
		if ($caption_plural === '') {
			$caption_plural = 'Seznam záznamů';
		}

		$safe_caption_plural = htmlspecialchars($caption_plural);

		echo <<<HTML
		<div class="md-sticky-header-master">
			<h2 style="font-size: 16px; margin: 0 0 10px 0; border: none; padding: 0;">{$safe_caption_plural}</h2>
			<input type="text" id="master-filter" placeholder="Hledat..." style="width: 100%; padding: 6px; box-sizing: border-box;">
		</div>
		
		<table class="md-table" style="margin-top: 0;">
			<thead>
				<tr>
HTML;
		foreach ($list_columns as $col => $header) {
			echo "<th>" . htmlspecialchars($header) . "</th>\n";
		}
		echo <<<HTML
				</tr>
			</thead>
			<tbody id="master-list">
HTML;

		$sql = $this->em->build_select_query($this->master_where);
		$q = sqlrun($sql);
		while ($row = fetch($q)) {
			$uuid = $row['original'];
			$rowClass = ($uuid === $update_guid) ? 'md-row-active' : '';
			$rowIdAttr = ($uuid === $update_guid) ? 'id="active-row"' : '';
			
			$page_param = htmlspecialchars((string)getinput('page'));
			$parent_param = (string)getinput('parent_object');
			$url_suffix = $parent_param !== '' ? "&parent_object=" . htmlspecialchars($parent_param) : '';

			echo "\t\t\t\t\t<tr class=\"{$rowClass}\" {$rowIdAttr} style=\"cursor: pointer;\" onclick=\"document.location='index.php?page={$page_param}{$url_suffix}&update_guid={$uuid}'\">\n";
			foreach ($list_columns as $col => $header) {
				$val = htmlspecialchars((string)($row[$col] ?? ''));
				echo "\t\t\t\t\t\t<td>{$val}</td>\n";
			}
			echo "\t\t\t\t\t</tr>\n";
		}

		echo <<<HTML
			</tbody>
		</table>
		<script>
			document.getElementById('master-filter').addEventListener('input', function() {
				const term = this.value.toLowerCase();
				const rows = document.getElementById('master-list').querySelectorAll('tr');
				rows.forEach(row => {
					row.style.display = row.textContent.toLowerCase().includes(term) ? '' : 'none';
				});
			});
		</script>
HTML;
	}

	protected function render_detail(): void {
		if ($this->em === null) {
			echo "<div class='msg-info'>Detail panel není nakonfigurován.</div>";
			return;
		}

		$update_guid = (string)getinput('update_guid');
		if ($update_guid === '') {
			echo "<div class='msg-info'>Vyberte záznam z levého panelu.</div>";
			return;
		}

		$sql = $this->em->build_select_query("m.original = " . guidliteral($update_guid));
		$q = sqlrun($sql);
		
		global $datarow;
		$datarow = fetch($q);
		
		if (!$datarow) {
			echo "<div class='msg-err'>Záznam nebyl nalezen.</div>";
			return;
		}
		
		$is_mine = (bool)$datarow['object_is_mine'];
		$page_param = htmlspecialchars((string)getinput('page'));
		$parent_param = (string)getinput('parent_object');
		$url_suffix = $parent_param !== '' ? "&parent_object=" . htmlspecialchars($parent_param) : '';
		
		$discard_url = "index.php?page={$page_param}{$url_suffix}";

		echo <<<HTML
		<form method="post" action="index.php?page={$page_param}{$url_suffix}&update_guid={$update_guid}">
			<div class="md-sticky-header-detail">
				<h2 style="margin: 0; border: none; padding: 0;">Detail záznamu</h2>
				<div>
					<a href="{$discard_url}" class="btn btn-danger" style="margin-right: 10px;" onclick="isFormDirty = false;">Zahodit změny</a>
					<button type="submit" name="btn_save" class="btn btn-success">Uložit změny</button>
				</div>
			</div>
			
			<table class="md-table" style="margin-bottom: 30px;">
HTML;
		
		foreach ($this->em->get_columns() as $colname => $meta) {
			if (!empty($meta['hidden'])) continue;
			
			$label = htmlspecialchars((string)($meta['label'] ?: $meta['caption'] ?: $colname));
			$input_html = $this->em->render_dynamic_input($colname, (string)$datarow[$colname], $is_mine);
			
			echo <<<HTML
				<tr>
					<td style="width: 30%;"><strong>{$label}:</strong></td>
					<td>{$input_html}</td>
				</tr>
HTML;
		}

		echo <<<HTML
			</table>
		</form>
HTML;

		$this->render_audit_trail();
	}

	protected function render_audit_trail(): void {
		global $datarow;
		
		if (empty($datarow) || (empty($datarow['date_created']) && empty($datarow['date_modified']))) {
			return;
		}

		$html = '';
		
		if (!empty($datarow['date_created'])) {
			$dt_val = $datarow['date_created'];
			$date_c = ($dt_val instanceof DateTime) ? $dt_val->format('d.m.Y H:i') : date('d.m.Y H:i', strtotime((string)$dt_val));
			$who_c_name = !empty($datarow['who_created_info']) ? $datarow['who_created_info'] : 'Neznámý uživatel';
			
			$html .= "<div>Vytvořil {$date_c} " . htmlspecialchars((string)$who_c_name) . "</div>";
		}

		if (!empty($datarow['date_modified'])) {
			$dt_val = $datarow['date_modified'];
			$date_m = ($dt_val instanceof DateTime) ? $dt_val->format('d.m.Y H:i') : date('d.m.Y H:i', strtotime((string)$dt_val));
			$who_m_name = !empty($datarow['who_modified_info']) ? $datarow['who_modified_info'] : 'Neznámý uživatel';
			
			$html .= "<div>Změnil &nbsp;&nbsp;{$date_m} " . htmlspecialchars((string)$who_m_name) . "</div>";
		}

		if ($html !== '') {
			echo "<div style=\"margin-top: 30px; font-size: 11px; color: #94a3b8; line-height: 1.6; font-family: monospace;\">{$html}</div>";
		}
	}
}