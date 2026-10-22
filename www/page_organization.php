<?php
/**
 * =============================================================================
 * Verze: 2026-10-22 16:15
 * Soubor: page_organization.php
 * Třída: page_organization
 * Účel: Master-Detail obrazovka pro správu a editaci existujících organizací (tenantů).
 *       Umožňuje Sysadminovi ('S') a Developerovi ('D') upravovat identifikační,
 *       fakturační, adresní a přihlašovací parametry organizací, avšak neumožňuje
 *       vkládat nové záznamy (nové organizace vznikají výhradně aktivací licence
 *       v modulu page_organization_licence).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_organization`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'organization'`.
 * - Zakazuje vkládání nových záznamů přes `$this->allow_insert = false`.
 * - Využívá `entity_manager`, který u tabulky `organization` zohledňuje, že každý
 *   záznam organizace vlastní sám sebe (`object_owner = original`), a pro sloupec
 *   `licence_level` vykresluje roletku z tabulky `licence_level`.
 * - Využívá `abstract_button` a `$this->phrase()` pro plnou lokalizaci UI.
 *
 * Změny:
 * 2026-10-22 16:15 - Vytvoření první verze stránky pro editaci seznamu organizací.
 * =============================================================================
 */

declare(strict_types=1);

class page_organization extends abstract_page_master_detail {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu v předkovi

		global $dbsession;                                                   // Globální kontext relace uživatele

		$this->class_name = 'organization';                                  // Logická třída pro entity_manager
		$this->allow_insert = false;                                         // Zákaz zakládání nových organizací mimo licenční modul
		$this->page_title = $this->phrase('page_title', [], 'Správa organizací'); // Lokalizovaný titulek stránky

		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		if ($this->access_denied OR !in_array($active_role, ['S', 'D'], true)) { // Kontrola oprávnění Sysadmin nebo Developer
			$this->access_denied = true;                                     // Odepření přístupu pro nižší role
			return;                                                          // Ukončení inicializace
		}

		$grp_basic = $this->phrase('grp_basic_info', [], 'Základní identifikace a stav organizace'); // Sekce základních údajů
		$grp_bill  = $this->phrase('grp_billing_info', [], 'Registrační, daňové a fakturační údaje'); // Sekce fakturačních údajů
		$grp_addr  = $this->phrase('grp_address_info', [], 'Sídlo a kontaktní údaje'); // Sekce adresních údajů
		$grp_texts = $this->phrase('grp_texts_notes', [], 'Popis, nápověda a interní poznámky'); // Sekce popisných textů

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_basic => ['caption', 'shortname', 'external_code', 'login_domain', 'licence_level', 'login_disabled', 'inactive', 'valid_from', 'valid_to'], // Základní parametry
			$grp_bill  => ['register_id', 'tax_id', 'invoice_info'],         // IČO, DIČ a fakturační informace
			$grp_addr  => ['address_name', 'address_street', 'address_city', 'address_zip', 'address_state', 'www_address'], // Adresa a web
			$grp_texts => ['description_text', 'help_text', 'note']          // Překládané popisy a poznámka
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Vykreslí nad vyhledávacím polem v levém panelu odkaz do správy licencí,
	 * kde se zakládají a aktivují nové organizace.
	 */
	protected function render_master_top(): void {
		$btn_lic = new abstract_button(                                      // Tlačítko přechodu do správy licencí
			'btn_goto_licences',                                             // Kód fráze tlačítka v meta_phrase
			'Správa licencí (založení organizace) →',                        // Výchozí český popisek
			'page_organization',                                             // Zdrojová třída fráze
			'',                                                              // Bez ikony
			'btn-secondary'                                                  // Sekundární styl tlačítka
		);
		$btn_lic->set_href('index.php?page=page_organization_licence')       // Cílová URL správy licencí
			->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Roztažení na šířku levého panelu

		echo $btn_lic->render();                                             // Vykreslení tlačítka nad seznamem
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem a zkratkou vybrané organizace.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek organizace
		$cap = htmlspecialchars((string)($datarow['caption'] ?? ''));        // Ošetřený název organizace
		$short = htmlspecialchars((string)($datarow['shortname'] ?? ''));    // Ošetřená zkratka organizace
		$lbl = htmlspecialchars($this->phrase('header_edit_org', [], 'Organizace')); // Lokalizované návěstí nadpisu
		$suffix = ($short !== '' AND $short !== $cap) ? " ({$short})" : '';  // Přípona se zkratkou organizace
		return "{$lbl}: <span style=\"color: #555;\">{$cap}{$suffix}</span>"; // Výsledný HTML nadpis detailu
	}

	/**
	 * Vykreslí upozornění u systémové master organizace (0x00).
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek organizace
		$orig = (string)($datarow['original'] ?? '');                        // UUID originálu vybrané organizace
		if ($orig === '0x00' OR $orig === '00000000-0000-0000-0000-000000000000') { // Detekce systémové organizace 0x00
			$msg_sys = htmlspecialchars($this->phrase('msg_system_org_notice', [], 'Toto je systémová master organizace (0x00). Slouží jako globální kontejner pro systémové administrátory a vývojáře.')); // Text upozornění
			echo "<div class=\"msg-info\" style=\"margin-bottom: 15px; font-weight: normal; font-size: 13px;\">{$msg_sys}</div>\n"; // Výpis infoboxu
		}
	}
}