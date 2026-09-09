<?php
/**
 * =============================================================================
 * Třída: abstract_page_master_detail
 * Účel: Abstraktní třída rozšiřující základní stránku o dvoupamelový layout.
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page_master_detail extends abstract_page {

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
				position: relative; /* Důležité pro přesný výpočet rolování */
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
		</style>

		<div class="md-master">
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
			document.addEventListener("DOMContentLoaded", function() {
				// Krátký timeout zajistí, že flexbox už plně spočítal výšku elementů
				setTimeout(function() {
					const activeRow = document.getElementById("active-row");
					const masterPanel = document.querySelector(".md-master");
					
					if (activeRow && masterPanel) {
						const panelRect = masterPanel.getBoundingClientRect();
						const rowRect = activeRow.getBoundingClientRect();
						
						// Vypočteme fyzický posun řádku vůči viditelnému okraji panelu
						const offset = rowRect.top - panelRect.top;
						
						// Nastavíme vnitřní rolování tak, aby byl řádek vizuálně uprostřed
						masterPanel.scrollTop += offset - (panelRect.height / 2) + (rowRect.height / 2);
					}
				}, 50);
			});
		</script>
HTML;
	}

	abstract protected function render_master(): void;
	abstract protected function render_detail(): void;
}