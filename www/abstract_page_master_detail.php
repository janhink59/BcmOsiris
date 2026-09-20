<?php
/**
 * =============================================================================
 * Třída: abstract_page_master_detail
 * Účel: Abstraktní třída rozšiřující základní stránku o dvoupamelový layout.
 *       Nyní obsahuje očištěnou metodu pro renderování auditní stopy bez
 *       generování zbytečných dotazů na databázi.
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page_master_detail extends abstract_page {

	public function render(): void {
		if (isset($_GET['ajax_panel']) && $_GET['ajax_panel'] === 'master') {
			$this->render_master();
			exit;
		}
		parent::render();
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
			.md-table {
				width: 100%;
				border-collapse: collapse;
				margin-top: 10px;
			}
			.md-table th {
				background-color: #e9f2fa;
				padding: 8px;
				border: 1px solid #ddd;
				text-align: left;
			}
			.md-table td {
				padding: 8px;
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

	/**
	 * Vykreslí auditní stopu záznamu. Spoléhá na to, že SQL procedura dodá
	 * předformátované hodnoty ve sloupcích who_created_info a who_modified_info.
	 */
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

	abstract protected function render_master(): void;
	abstract protected function render_detail(): void;
}