<?php
/**
 * =============================================================================
 * Verze: 2026-10-18 17:15
 * Soubor: page_meta_class.php
 * Účel: Editace metadat logických tříd (STI architektura).
 * Nahrazuje původní page_meta_object.php.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'meta_class'`.
 * - Využívá standardní datově řízený formulář z předka (`$this->form_groups`),
 *   včetně generování `<select>` pro `ancestor_class` přes `referenced_class` v `entity_manager`.
 * - Využívá hook `render_detail_header_buttons()` a `abstract_button` pro přechod
 *   do podřízené stránky `page_meta_column`.
 * 
 * Změny:
 * 2026-10-18 17:15 - Doplněn sloupec editor_note do prezentační sekce formuláře.
 * 2026-10-16 00:12 - Odstraněna duplicitní metoda render_detail() a ruční kontrola role.
 *                  - Formulář převeden na $this->form_groups, zapojen abstract_button
 *                    a phrase_manager přes $this->phrase().
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

		$this->class_name = 'meta_class';                                    // Logická třída pro entity_manager
		$this->page_title =$this->phrase('page_title', [], 'Správa metadat logických tříd'); // Lokalizovaný titulek stránky

		$grp_pres =$this->phrase('grp_presentation', [], 'Prezentační texty a nápověda'); // Nadpis prezentační sekce
		$grp_tech =$this->phrase('grp_technical', [], 'Dědičnost, vzhled a ochrana třídy'); // Nadpis technické sekce

		$this->form_groups = [                                               // Rozdělení polí do sekcí formuláře
			$grp_pres => ['caption', 'caption_plural', 'description', 'helptext', 'editor_note'], // Překládané popisky třídy a AI kontext
			$grp_tech => ['class_name', 'ancestor_class', 'sort_code', 'iconname', 'is_final', 'is_protected', 'inactive'] // Technické atributy pro roli 'D'
		];                                                                   // Konec definice skupin formuláře
	}

	protected function get_detail_header(): string {
		global $datarow;                                                     // Globální pole pro aktuální záznam
		$code = htmlspecialchars((string)($datarow['class_name'] ?? ''));    // Technický název třídy
		$lbl = htmlspecialchars($this->phrase('header_edit_class', [], 'Editace třídy')); // Lokalizovaný popisek nadpisu
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$code}</span>"; // Výsledný HTML nadpis detailu
	}

	protected function render_detail_header_buttons(string $update_guid): string { // Vykreslení tlačítka správy sloupců
		if ($update_guid === '' OR $update_guid === 'NEW') {                 // U nového záznamu sloupce ještě nejsou
			return '';                                                       // Nevykreslujeme tlačítko sloupců
		}

		// Zjištění počtu sloupců evidovaných u této logické třídy
		$col_count = 0;                                                      // Výchozí počet sloupců třídy
		$q_cnt = sqlrun("SELECT COUNT(DISTINCT original) AS cnt FROM meta_column WHERE parent_class = " . guidliteral($update_guid) . " AND record_type = 'A' AND removed = 0"); // Dotaz na počet sloupců
		if ($r_cnt = fetch($q_cnt)) {                                        // Načtení výsledku dotazu
			$col_count = (int)$r_cnt['cnt'];                                 // Uložení počtu sloupců
		}
		free_result($q_cnt);                                                 // Uvolnění výsledku dotazu

		$columns_url = "index.php?page=page_meta_column&parent_class=" . urlencode($update_guid); // Odkaz na správu sloupců
		$btn_cols = new abstract_button(                                     // Vytvoření tlačítka přes abstract_button
			'btn_manage_columns',                                            // Kód fráze tlačítka v meta_phrase
			'Spravovat sloupce ({' . chr(36) . 'count}) →',                  // Výchozí popisek s proměnnou počtu
			'page_meta_class',                                               // Zdrojová třída fráze
			'',                                                              // Výchozí ikona (prázdná)
			'btn-secondary'                                                  // Výchozí CSS třída tlačítka
		);
		$btn_cols->set_href($columns_url)->set_vars(['count' =>$col_count]); // Nastavení odkazu a proměnné {$count}

		return $btn_cols->render();                                          // Vrácení HTML kódu tlačítka
	}
}