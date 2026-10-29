<?php
/**
 * =============================================================================
 * Verze: 2026-10-29 16:40
 * Soubor: page_organization.php
 * Třída: page_organization
 * Účel: Master-Detail obrazovka pro správu a nastavení organizace (tenanta).
 *       - Administrátor organizace ('A') zde upravuje identifikační, fakturační,
 *         adresní, regionální a CRMM výpočtové parametry své vlastní organizace.
 *       - Sysadmin ('S') a Developer ('D') v systémové organizaci (0x00) vidí
 *         a mohou upravovat všechny organizace v systému.
 *       - Zakládání nových organizací je zde zakázáno ($this->allow_insert = false),
 *         protože organizace vznikají výhradně aktivací licence v modulu
 *         page_organization_licence.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_organization`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'organization'`.
 * - Využívá `entity_manager`, který u tabulky `organization` zohledňuje, že každý
 *   záznam organizace vlastní sám sebe (`object_owner = original`), a pro sloupec
 *   `preferred_language` vykresluje roletku z tabulky `language`.
 * - Využívá `abstract_button` a `$this->phrase()` pro plnou lokalizaci UI.
 *
 * Změny:
 * 2026-10-29 16:40 - Zpřístupnění stránky pro roli OrgAdmin ('A') nad vlastní
 *                    organizací (s automatickým předvýběrem organizace v detailu).
 *                  - Odstraněny vyčleněné licenční sloupce licence_level a login_disabled.
 *                  - Doplněny sekce pro regionální formátování a výpočtové limity CRMM.
 * 2026-10-22 16:15 - Vytvoření první verze stránky pro editaci seznamu organizací.
 * =============================================================================
 */

declare(strict_types=1);

class page_organization extends abstract_page_master_detail {

	private bool $can_manage_licences = false;                               // Zda má uživatel přístup do správy licencí

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu v předkovi

		global $dbsession;                                                   // Globální kontext relace uživatele

		$this->class_name = 'organization';                                  // Logická třída pro entity_manager
		$this->allow_insert = false;                                         // Zákaz zakládání nových organizací mimo licenční modul
		$this->page_title = $this->phrase('page_title', [], 'Správa a nastavení organizace'); // Lokalizovaný titulek stránky

		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální role v relaci
		$lic_level = intval($dbsession['licence_level'] ?? 0);               // Úroveň licence organizace v relaci
		$org_raw = (string)($dbsession['organization'] ?? '0x00');           // UUID aktivní organizace v relaci
		$is_sys_org = ($org_raw === '0x00' OR $org_raw === '00000000-0000-0000-0000-000000000000'); // Zda je v 0x00

		if ($this->access_denied OR !in_array($active_role, ['A', 'S', 'D'], true)) { // Kontrola oprávnění Admin, Sysadmin nebo Developer
			$this->access_denied = true;                                     // Odepření přístupu pro běžné uživatele
			return;                                                          // Ukončení inicializace
		}

		$this->can_manage_licences = (in_array($active_role, ['S', 'D'], true) OR in_array($lic_level, [40, 255], true)); // Právo na licence

		// Pokud správce nepracuje v systémové organizaci (0x00), omezíme Master seznam na jeho vlastní organizaci
		// a pokud ještě nemá v URL vybraný záznam, rovnou jeho organizaci předvybereme.
		if (!$is_sys_org) {                                                  // Izolace na vlastní organizaci tenanta
			$this->master_where = "m.original = " . guidliteral($org_raw);   // Filtr na vlastní organizaci
			if (trim((string)getinput('update_guid')) === '') {              // Pokud v URL není vybrán záznam
				$_GET['update_guid'] = $org_raw;                             // Automatické otevření detailu vlastní organizace
			}
		}

		$grp_basic = $this->phrase('grp_basic_info', [], 'Základní identifikace organizace'); // Sekce základních údajů
		$grp_reg   = $this->phrase('grp_regional_settings', [], 'Regionální a formátovací nastavení'); // Sekce formátování
		$grp_crmm  = $this->phrase('grp_crmm_parameters', [], 'Metodické a výpočtové parametry CRMM'); // Sekce CRMM limitů
		$grp_bill  = $this->phrase('grp_billing_info', [], 'Registrační, daňové a fakturační údaje'); // Sekce fakturace
		$grp_addr  = $this->phrase('grp_address_info', [], 'Sídlo a kontaktní údaje'); // Sekce adresy
		$grp_texts = $this->phrase('grp_texts_notes', [], 'Popis, nápověda a interní poznámky'); // Sekce textů

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_basic => ['caption', 'shortname', 'external_code', 'login_domain', 'inactive', 'valid_from', 'valid_to'], // Identifikace
			$grp_reg   => ['preferred_language', 'currency_unit', 'currency_digits', 'currency_before', 'format_date', 'format_time', 'time_zone', 'thousand_separator', 'decimal_separator', 'export_delimiter'], // Regionální volby
			$grp_crmm  => ['evaluation_method', 'max_threat_score', 'max_vulnerability_score', 'max_impact_score', 'max_risk_score', 'max_impact_financial', 'residual_risk_min_financial'], // Parametry CRMM
			$grp_bill  => ['register_id', 'tax_id', 'invoice_info'],         // IČO, DIČ a fakturační informace
			$grp_addr  => ['address_name', 'address_street', 'address_city', 'address_zip', 'address_state', 'www_address'], // Adresa a web
			$grp_texts => ['description_text', 'help_text', 'note']          // Překládané popisy a poznámka
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Vykreslí nad vyhledávacím polem v levém panelu odkaz do správy licencí
	 * (pouze pokud má uživatel roli S/D nebo licenci Enterprise/Developer).
	 */
	protected function render_master_top(): void {
		if (!$this->can_manage_licences) {                                   // Běžný tenant bez Enterprise licence tlačítko nevidí
			return;                                                          // Ukončení bez vykreslení tlačítka
		}

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