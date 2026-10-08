<?php
/**
 * =============================================================================
 * Verze: 2026-10-08
 * Soubor: page_meta_column.php
 * Účel: Detailní editace metadat konkrétního sloupce (tenant override nebo překlad).
 * Změny:
 * - Přidána ochrana přístupu pro administrátory (sysadmin i orgadmin).
 * - Přepojení vazby z fyzické tabulky (parent_object) na logickou třídu (parent_class).
 * - Úprava zpětného odkazu a načítání titulku přes entity_manager (náhrada za vrepo_meta_class).
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_column extends abstract_page_master_detail {

	private string $parent_class;
	private string $parent_name = '';
	private bool $access_denied = false;

	public function __construct() {
		global $dbsession;

		$this->page_title = 'Správa metadat sloupce';
		$this->class_name = 'meta_column';
		
		// Přístup povolen pro systémové administrátory (0x00) i administrátory organizací (tenant overridy)
		if (empty($dbsession['right_sysadmin']) && empty($dbsession['right_orgadmin'])) {
			$this->access_denied = true;
		}

		$this->form_groups = [
			'Základní prezentační údaje' => ['caption', 'caption_plural', 'description', 'label', 'header', 'placeholder', 'helptext'],
			'Formulářové vlastnosti a vazby (UI)' => ['input_type', 'input_width', 'max_length', 'input_rows', 'sort_code', 'list_order', 'referenced_codetable', 'referenced_class', 'css_class'],
			'Behaviorální příznaky' => ['translate', 'history', 'is_mandatory', 'is_html', 'hidden', 'is_url', 'show_empty', 'is_computed', 'customizable']
		];
		
		$this->parent_class = (string)getinput('parent_class');
		
		if ($this->parent_class !== '') {
			$this->master_where = "m.parent_class = " . guidliteral($this->parent_class);
			
			// Zjištění názvu nadřízeného objektu pro titulek přes dynamický dotaz z entity_manageru
			$em_parent = new entity_manager('meta_class');
			$q = sqlrun($em_parent->build_select_query("m.original = " . guidliteral($this->parent_class)));
			
			if ($row = fetch($q)) {
				$this->parent_name = (string)$row['caption'] !== '' ? (string)$row['caption'] : (string)$row['class_name'];
				$this->page_title = 'Sloupce: ' . $this->parent_name;
			}
			free_result($q);
		}
	}

	protected function process_save(): void {
		if ($this->access_denied) {
			return;
		}
		parent::process_save();
	}

	protected function render_master(): void {
		if ($this->access_denied) {
			echo "<div class='msg-err'>Přístup odepřen. Modul je dostupný pouze administrátorům.</div>";
			return;
		}
		parent::render_master();
	}

	protected function render_detail(): void {
		if ($this->access_denied) {
			return;
		}
		parent::render_detail();
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