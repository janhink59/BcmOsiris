<?php
/**
 * =============================================================================
 * Verze: 2026-09-29
 * Soubor: page_meta_column.php
 * Účel: Detailní editace metadat konkrétního sloupce (tenant override nebo překlad).
 * Změny:
 * - Tlačítko Zpět se dynamicky vkládá do fixní hlavičky přes render_master_top().
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_column extends abstract_page_master_detail {

	private string $parent_object;
	private string $parent_name = '';

	public function __construct() {
		$this->page_title = 'Správa metadat sloupce';
		$this->class_name = 'meta_column';
		
		$this->form_groups = [
			'Základní prezentační údaje' => ['caption', 'caption_plural', 'description', 'label', 'header', 'placeholder', 'helptext'],
			'Formulářové vlastnosti a vazby (UI)' => ['input_type', 'input_width', 'max_length', 'input_rows', 'sort_code', 'list_order', 'referenced_codetable', 'referenced_class', 'css_class'],
			'Behaviorální příznaky' => ['translate', 'history', 'is_mandatory', 'is_html', 'hidden', 'is_url', 'show_empty', 'is_computed', 'customizable']
		];
		
		$this->parent_object = (string)getinput('parent_object');
		
		if ($this->parent_object !== '') {
			$this->master_where = "m.parent_object = " . guidliteral($this->parent_object);
			
			// Zjištění názvu nadřízeného objektu pro titulek (primárně caption, fallback na builtin_code)
			$q = sqlrun("SELECT builtin_code, caption FROM vrepo_meta_object WHERE original = " . guidliteral($this->parent_object));
			if ($row = fetch($q)) {
				$this->parent_name = (string)$row['caption'] !== '' ? (string)$row['caption'] : (string)$row['builtin_code'];
				$this->page_title = 'Sloupce: ' . $this->parent_name;
			}
			free_result($q);
		}
	}

	protected function get_detail_header(): string {
		global $datarow;
		$c_name = htmlspecialchars((string)($datarow['column_name'] ?? ''));
		return "Sloupec: <span style=\"font-family: monospace; color: #555;\">{$c_name}</span>";
	}

	protected function render_detail_top(): void {
		global $datarow;
		if (!empty($datarow['ancestor'])) {
			echo "<div style='color: #d97706; font-size: 12px; margin-bottom: 10px;'><b>Poznámka:</b> Tento sloupec dědí vlastnosti od svého předka. Můžete je zde přepsat (tenant override).</div>\n";
		}
	}

	protected function render_master_top(): void {
		if ($this->parent_object !== '') {
			$safe_parent = htmlspecialchars($this->parent_name);
			echo <<<HTML
			<div style="margin-bottom: 15px;">
				<a href="index.php?page=meta_object&update_guid={$this->parent_object}" class="btn btn-secondary" style="display: block; text-align: center;">&larr; Zpět na objekt: {$safe_parent}</a>
			</div>
HTML;
		}
	}
}