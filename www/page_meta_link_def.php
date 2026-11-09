<?php
/**
 * =============================================================================
 * Verze: 2026-11-09 16:30
 * Soubor: page_meta_link_def.php
 * Třída: page_meta_link_def
 * Účel: Správa katalogu povolených typů relací a vazeb M:N mezi logickými
 *       třídami v tabulce meta_link_def (modul CRMM).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_meta_link_def`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'meta_link_def'`.
 * - Definice vazeb v této tabulce řídí chování a výběr cílových tříd na stránce
 *   `page_link.php` a při šíření odvozených vazeb v `p_sync_derived_links.sql`.
 * =============================================================================
 */

declare(strict_types=1);

class page_meta_link_def extends abstract_page_master_detail {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'meta_link_def';                                 // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových definic vazeb
		$this->page_title = $this->phrase('page_title', [], 'Definice typů vazeb (CRMM)'); // Lokalizovaný titulek stránky

		if (! $this->access_denied AND $this->em === null) {                 // Inicializace entity_manageru pro nastavení sloupců seznamu
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance správce entit
			$this->em->set_list_columns([                                    // Přehledné sloupce v levém Master panelu
				'link_code'       => $this->phrase('th_link_code', [], 'Kód vazby'),
				'caption_forward' => $this->phrase('th_caption_forward', [], 'Název vazby (tam)')
			]);                                                              // Konec definice sloupců Master panelu
		}

		$grp_id    = $this->phrase('grp_identification', [], 'Kód vazby a propojované logické třídy'); // Sekce identifikace
		$grp_pres  = $this->phrase('grp_presentation', [], 'Prezentační názvy vazby (tam / zpět) a nápověda'); // Sekce textů
		$grp_rules = $this->phrase('grp_rules_protection', [], 'Pravidla navazování, váha a ochrana'); // Sekce pravidel

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_id    => ['link_code', 'from_class', 'to_class'],           // Klíčový kód a zdrojová/cílová třída
			$grp_pres  => ['caption_forward', 'caption_backward', 'description', 'helptext'], // Lokalizované názvy oběma směry
			$grp_rules => ['is_multiple', 'is_mandatory', 'leaf_only', 'link_weight_enabled', 'transfer_roles', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Pravidla
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Vykreslí tlačítko "+ Nový typ vazby" v horní části levého panelu.
	 */
	protected function render_master_top(): void {
		if (! $this->allow_insert) {                                         // Pokud zakládání nových záznamů není povoleno
			return;                                                          // Tlačítko nevykreslujeme
		}

		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL s kontextem
		$new_url = "index.php?page=page_meta_link_def{$url_suffix}&update_guid=NEW"; // Cílová adresa pro novou definici vazby
		$btn_new = new abstract_button('btn_new_link_def', '+ Nový typ vazby', 'page_meta_link_def'); // Tlačítko
		$btn_new->set_href($new_url)                                         // Nastavení cílové URL
			->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
			->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Roztažení na šířku panelu

		echo $btn_new->render();                                             // Vykreslení tlačítka
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s kódem vybrané definice vazby.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Zakládání nového typu vazby
			return htmlspecialchars($this->phrase('header_new_link_def', [], 'Nová definice typu vazby')); // Nadpis pro nový záznam
		}
		$code = htmlspecialchars((string) ($datarow['link_code'] ?? ''));    // Ošetřený technický kód vazby
		$lbl = htmlspecialchars($this->phrase('header_edit_link_def', [], 'Typ vazby')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$code}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Předvyplní výchozí příznaky `is_multiple = 1` a `leaf_only = 1` u nového záznamu.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu z požadavku

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_multiple'] = '1';                                   // Výchozí povolení vazby M:N
			$datarow['leaf_only'] = '1';                                     // Výchozí omezení na koncové uzly
		}
	}
}