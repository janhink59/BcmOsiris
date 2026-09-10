<?php
/**
 * =============================================================================
 * Třída: abstract_page_master_detail
 * Účel: Abstraktní třída rozšiřující základní stránku o dvoupamelový layout.
 *       Nově implementuje AJAX refresh master panelu přes Fetch API a sjednocuje 
 *       styly tabulek a aktivních řádků pro všechny moduly tohoto typu.
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page_master_detail extends abstract_page {

	/**
	 * Přepisujeme globální render(). 
	 * Zajišťuje zachycení AJAX požadavku čistě pro obnovu master panelu bez 
	 * nutnosti stahovat a vykreslovat celou HTML strukturu stránky.
	 */
	public function render(): void {
		// Detekce AJAX požadavku (např. z naší JS funkce refreshMasterPanel)
		if (isset($_GET['ajax_panel']) && $_GET['ajax_panel'] === 'master') {
			$this->render_master();
			exit;
		}
		
		// Běžný běh: vykreslení celé stránky (HTML obálka z abstract_page)
		parent::render();
	}

	final protected function render_body(): void {
		echo <<<HTML
		<style>
			/* ---------------------------------------------------
			   Základní layout Master-Detail
			--------------------------------------------------- */
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
				position: relative; /* Důležité pro offset výpočty při scrollování */
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

			/* ---------------------------------------------------
			   Sjednocené styly pro UI prvky v Master panelu
			   (Odstraňuje nutnost inline stylů v potomcích)
			--------------------------------------------------- */
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
			
			/* Stavy řádků (aktivní výběr a deaktivovaný/smazaný záznam) */
			.md-row-active {
				background-color: #e6f7ff !important;
				color: #333 !important;
			}
			.md-row-inactive {
				background-color: #f9f9f9 !important;
				color: #999 !important;
			}
		</style>

		<!-- Obalíme master obsah do kontejneru s jednoznačným ID pro Fetch API injekce -->
		<div class="md-master" id="md-master-container">
HTML;
		// Synchronní úvodní načtení
		$this->render_master();

		echo <<<HTML
		</div>
		<div class="md-detail">
HTML;
		$this->render_detail();

		echo <<<HTML
		</div>
		
		<script>
			/**
			 * Abstrahovaná logika vycentrování rolování na aktivní prvek.
			 * Lze volat po načtení stránky i po asynchronním AJAX refreshi.
			 */
			function scrollToActiveRow() {
				const activeRow = document.getElementById("active-row");
				const masterPanel = document.getElementById("md-master-container");
				
				if (activeRow && masterPanel) {
					const panelRect = masterPanel.getBoundingClientRect();
					const rowRect = activeRow.getBoundingClientRect();
					
					// Fyzický posun řádku vůči viditelnému okraji panelu
					const offset = rowRect.top - panelRect.top;
					
					// Nastavení vnitřního rolování (vycentruje prvek)
					masterPanel.scrollTop += offset - (panelRect.height / 2) + (rowRect.height / 2);
				}
			}

			/**
			 * Asynchronně obnoví obsah levého (Master) panelu bez přenačtení stránky.
			 * Využívá Fetch API. Doplňuje URL parametr ajax_panel=master pro backend router.
			 */
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
						// Nahrazení starého DOM za aktuální data
						masterPanel.innerHTML = html;
						// Centrování pohledu na potenciálně nově vložený/změněný řádek
						scrollToActiveRow();
					}
				})
				.catch(error => {
					console.error('Chyba při obnově master panelu:', error);
				});
			}

			// Provedeme vycentrování při prvním synchronním načtení dokumentu
			document.addEventListener("DOMContentLoaded", function() {
				setTimeout(scrollToActiveRow, 50);
			});
		</script>
HTML;
	}

	abstract protected function render_master(): void;
	abstract protected function render_detail(): void;
}