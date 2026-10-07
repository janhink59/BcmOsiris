<?php
/**
 * =============================================================================
 * Verze: 2026-10-07
 * Soubor: page_meta_column.php
 * Účel: Detailní editace metadat konkrétního sloupce (tenant override nebo překlad).
 * Změny:
 * - Přepojení vazby z fyzické tabulky (parent_object) na logickou třídu (parent_class).
 * - Úprava zpětného odkazu a načítání titulku z vrepo_meta_class.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_column extends abstract_page_master_detail {

	private string $parent_class;
	private string $parent_name = '';

	public function __construct() {
		$this->page_title = 'Správa metadat sloupce';
		$this->class_name = 'meta_column';
		
		$this->form_groups = [
			'Základní prezentační údaje' => ['caption', 'caption_plural', 'description', 'label', 'header', 'placeholder', 'helptext'],
			'Formulářové vlastnosti a vazby (UI)' => ['input_type', 'input_width', 'max_length', 'input_rows', 'sort_code', 'list_order', 'referenced_codetable', 'referenced_class', 'css_class'],
			'Behaviorální příznaky' => ['translate', 'history', 'is_mandatory', 'is_html', 'hidden', 'is_url', 'show_empty', 'is_computed', 'customizable']
		];
		
		$this->parent_class = (string)getinput('parent_class');
		
		if ($this->parent_class !== '') {
			$this->master_where = "m.parent_class = " . guidliteral($this->parent_class);
			
			// Zjištění názvu nadřízeného objektu pro titulek (primárně caption, fallback na class_name)
			$q = sqlrun("SELECT class_name, caption FROM vrepo_meta_class WHERE original = " . guidliteral($this->parent_class));
			if ($row = fetch($q)) {
				$this->parent_name = (string)$row['caption'] !== '' ? (string)$row['caption'] : (string)$row['class_name'];
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
		if ($this->parent_class !== '') {
			$safe_parent = htmlspecialchars($this->parent_name);
			echo <<<HTML
			<div style="margin-bottom: 15px;">
				<a href="index.php?page=meta_class&update_guid={$this->parent_class}" class="btn btn-secondary" style="display: block; text-align: center;">&larr; Zpět na třídu: {$safe_parent}</a>
			</div>
HTML;
		}
	}
}