<?php
/**
 * =============================================================================
 * Verze: 2026-11-04 15:15
 * Soubor: page_scale.php
 * Třída: page_scale
 * Účel: Správa definic hodnotících škál CRMM (tabulka scale) pro veličiny
 *       THREAT, VULNERABILITY, IMPACT a RISK.
 *       Při prvním uložení nové škály se podle sloupce initial_levels (výchozí 4)
 *       automaticky vygeneruje n rovnoměrných stupňů v tabulce scale_value
 *       v procentuálním intervalu 0 až 100 %.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_scale`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'scale'`.
 * - V hlavičce detailu (`render_detail_header_buttons`) zobrazuje tlačítko pro
 *   přechod do správy stupňů vybrané škály (`page_scale_value.php&scale=<original>`).
 * =============================================================================
 */

declare(strict_types=1);

class page_scale extends abstract_page_master_detail {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'scale';                                         // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových škál
		$this->page_title = $this->phrase('page_title', [], 'Hodnotící škály (CRMM)'); // Lokalizovaný titulek stránky

		if (! $this->access_denied AND $this->em === null) {                 // Inicializace entity_manageru pro úpravu sloupců seznamu
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance správce entit
			$this->em->set_list_columns([                                    // Přehledné sloupce v levém Master panelu
				'caption'      => $this->phrase('th_scale_caption', [], 'Název škály'),
				'scale_type'   => $this->phrase('th_scale_type', [], 'Veličina'),
				'priority'     => $this->phrase('th_priority', [], 'Priorita'),
				'builtin_code' => $this->phrase('th_builtin_code', [], 'Kód')
			]);                                                              // Konec nastavení sloupců Master panelu
		}

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Sekce překládaných textů
		$grp_meth = $this->phrase('grp_methodology', [], 'Metodické zařazení a generování stupňů'); // Sekce metodiky
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, vzhled a ochrana'); // Sekce platnosti

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_meth => ['builtin_code', 'scale_type', 'priority', 'initial_levels', 'is_default', 'sort_code', 'external_code'], // Řídicí atributy škály
			$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Ikona, platnost a ochrana
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Vykreslí tlačítko "+ Nová hodnotící škála" nad vyhledávacím polem v levém panelu.
	 */
	protected function render_master_top(): void {
		if (! $this->allow_insert) {                                         // Pokud zakládání nových záznamů není povoleno
			return;                                                          // Tlačítko nevykreslujeme
		}

		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL s kontextem
		$new_url = "index.php?page=page_scale{$url_suffix}&update_guid=NEW"; // Cílová adresa pro novou škálu
		$btn_new = new abstract_button('btn_new_scale', '+ Nová hodnotící škála', 'page_scale'); // Tlačítko nové škály
		$btn_new->set_href($new_url)                                         // Nastavení cílové URL
			->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
			->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Roztažení na šířku levého panelu

		echo $btn_new->render();                                             // Vykreslení tlačítka
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybrané škály.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Pokud zakládáme novou škálu
			return htmlspecialchars($this->phrase('header_new_scale', [], 'Nová hodnotící škála')); // Nadpis pro nový záznam
		}
		$title_val = (string) ($datarow['builtin_code'] ?: $datarow['caption'] ?: ''); // Kód nebo název škály
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor pro nadpis
		$lbl = htmlspecialchars($this->phrase('header_edit_scale', [], 'Hodnotící škála')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Vloží do hlavičky detailu tlačítko pro přechod do správy stupňů (page_scale_value)
	 * u již uložené hodnotící škály.
	 */
	protected function render_detail_header_buttons(string $update_guid): string { // Tlačítko pro správu stupňů škály
		if ($update_guid === '' OR $update_guid === 'NEW') {                 // U nového neuloženého záznamu tlačítko nezobrazujeme
			return '';                                                       // Prázdný výstup
		}

		global $dbsession;                                                   // Globální kontext relace
		$org_sql = guidliteral((string) ($dbsession['organization'] ?? '0x00')); // SQL literál aktivní organizace
		$scale_sql = guidliteral($update_guid);                              // SQL literál originálu vybrané škály

		$r_cnt = sqlfirstrow("
			SELECT COUNT(DISTINCT original) AS cnt
			FROM scale_value
			WHERE scale = {$scale_sql}
			  AND object_owner IN (0x00, {$org_sql})
			  AND record_type = 'A'
			  AND removed = 0
		");                                                                  // Dotaz na počet aktivních stupňů této škály
		$val_count = (int) ($r_cnt['cnt'] ?? 0);                             // Počet stupňů škály

		$vals_url = "index.php?page=page_scale_value&scale=" . urlencode($update_guid); // Cílová URL pro správu stupňů škály
		$btn_vals = new abstract_button(                                     // Tlačítko přechodu na stupně škály
			'btn_manage_scale_values',                                       // Kód fráze v meta_phrase
			'Spravovat stupně škály ({' . chr(36) . 'count}) →',             // Výchozí český popisek s počtem
			'page_scale',                                                    // Zdrojová třída fráze
			'',                                                              // Bez ikony
			'btn-secondary'                                                  // Sekundární šedý styl tlačítka
		);
		$btn_vals->set_href($vals_url)->set_vars(['count' => $val_count]);   // Nastavení URL a proměnné {$count}

		return $btn_vals->render();                                         // Vrácení HTML kódu tlačítka
	}

	/**
	 * Předvyplní výchozí hodnoty `scale_type = 'IMPACT'`, `priority = 0` a `initial_levels = 4`
	 * u nového záznamu (`update_guid === 'NEW'`) a vypíše metodickou nápovědu.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			if (($datarow['scale_type'] ?? '') === '') {                     // Výchozí druh měřené veličiny
				$datarow['scale_type'] = 'IMPACT';                           // Výchozí veličina Dopad
			}
			if (($datarow['priority'] ?? '') === '') {                       // Výchozí priorita škály
				$datarow['priority'] = '0';                                  // 0 = primární škála
			}
			if (($datarow['initial_levels'] ?? '') === '') {                 // Výchozí počet generovaných stupňů
				$datarow['initial_levels'] = '4';                            // 4 rovnoměrné stupně (0, 25, 50, 75 %)
			}
		}

		$note = htmlspecialchars($this->phrase('msg_scale_generation_hint', [], 'Tip: Při prvním uložení nové škály se podle pole „Počet stupňů (initial_levels)“ automaticky vygeneruje odpovídající počet rovnoměrných stupňů v procentuálním intervalu 0 až 100 % (např. pro 4 stupně prahy 0, 25, 50, 75 % a skóre uprostřed intervalů 12.5, 37.5, 62.5, 87.5 %). Stupně lze následně upravit tlačítkem „Spravovat stupně škály“.')); // Nápověda
		echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$note}</div>\n"; // Výpis nápovědy
	}
}