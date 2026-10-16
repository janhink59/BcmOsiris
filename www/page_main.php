<?php
/**
 * =============================================================================
 * Verze: 2026-10-16 08:25
 * Soubor: page_main.php
 * Stránka: page_main.php
 * Účel: Hlavní rozcestník dynamicky generovaný z databáze metadat (Průzkumník).
 *
 * Vazby na okolí:
 * - Dědí z abstract_page (využívá $this->page_title, $this->access_denied a $this->phrase()).
 * - Využívá globální $menu_manager pro načtení aktivní složky a jejích potomků.
 * 
 * Změny:
 * 2026-10-16 08:25 - Doplněno volání parent::__construct() a lokalizace všech
 *                    výchozích textů přes $this->phrase().
 * 2026-10-13 - Aplikace moderního CSS Grid layoutu (dlaždice/karty) místo 
 *              starého hover-rámečku. Zpracovává menu_code z URL a zobrazuje 
 *              potomky dané složky vyžádané přes globální menu_manager.
 * =============================================================================
 */

declare(strict_types=1);

class page_main extends abstract_page {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		global $dbsession;                                                   // Globální kontext relace uživatele

		$this->page_title = $this->phrase('page_title', [], 'Hlavní panel - BCM Osiris'); // Lokalizovaný titulek stránky

		if (empty($dbsession['user_account'])) {                             // Kontrola přihlášeného uživatele
			$this->access_denied = true;                                     // Odepření přístupu při chybějící relaci
		}
	}

	protected function render_body(): void {
		global $menu_manager;                                                // Globální instance správce navigace

		$menu_code = (string)getinput('menu_code');                          // Kód požadované složky menu z URL
		if ($menu_code === '') {                                             // Pokud nebyl kód složky předán
			$menu_code = 'home';                                             // Výchozí kořenová složka Domů
		}

		$default_heading = $this->phrase('default_heading', [], 'Rozcestník'); // Výchozí nadpis rozcestníku

		// Získání informací o aktuální složce z manageru
		$current_node = $menu_manager->get_node_by_code($menu_code);         // Načtení uzlu složky z menu_manageru
		$title = $current_node ? htmlspecialchars((string)($current_node['caption'] ?? '')) : htmlspecialchars($default_heading); // Nadpis složky
		
		// Oprava: Používáme helptext (ten vrací SQL procedura po COALESCE překladu)
		$desc = $current_node ? htmlspecialchars((string)($current_node['helptext'] ?? '')) : ''; // Popis složky z helptextu
		if ($desc === '') {                                                  // Pokud složka nemá vlastní helptext
			$desc = htmlspecialchars($this->phrase('default_description', [], 'Vyberte požadovanou akci z níže uvedených modulů.')); // Výchozí popis
		}

		echo <<<HTML
		<h1 class="page-heading">{$title}</h1>
		<p style="margin-bottom: 25px; color: #475569;">{$desc}</p>
HTML;

		// Načtení potomků aktuálního uzlu (obsah složky)
		$children = $menu_manager->get_children_by_code($menu_code);         // Seznam podřízených položek menu

		if (empty($children)) {                                              // Pokud složka neobsahuje žádné položky
			$msg_empty = htmlspecialchars($this->phrase('msg_folder_empty', [], 'Tato složka momentálně neobsahuje žádné dostupné moduly.'));
			echo "<div class='msg-info'>{$msg_empty}</div>";
			return;                                                          // Ukončení vykreslování prázdné složky
		}

		// Responzivní CSS Grid pro dlaždice (karty)
		echo "<div style=\"display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px;\">\n";

		foreach ($children as $child) {
			// Skryté položky (bez přístupu) nevykreslujeme
			if (!empty($child['is_disabled'])) {                             // Přeskočení neaktivní položky
				continue;                                                    // Pokračování na další dlaždici
			}

			$caption = htmlspecialchars((string)($child['caption'] ?? ''));  // Ošetřený název dlaždice
			$helptext = htmlspecialchars((string)($child['helptext'] ?? '')); // Ošetřený popis dlaždice
			$icon = !empty($child['svg_icon']) ? '<div style="width: 32px; height: 32px; color: #004488; margin-bottom: 15px;">' . $child['svg_icon'] . '</div>' : '<div style="width: 32px; height: 32px; background: #e2e8f0; border-radius: 4px; margin-bottom: 15px;"></div>'; // Ikona dlaždice
			
			$link = $menu_manager->build_link($child);                       // Cílová URL adresa dlaždice
			$target = !empty($child['target_window']) ? ' target="' . htmlspecialchars((string)$child['target_window']) . '"' : ''; // Cílové okno odkazu

			echo <<<HTML
			<a href="{$link}"{$target} style="display: block; background: #fff; border: 1px solid #cbd5e1; border-radius: 6px; padding: 20px; text-decoration: none; color: #334155; transition: all 0.2s ease; box-shadow: 0 1px 3px rgba(0,0,0,0.05);" onmouseover="this.style.boxShadow='0 4px 12px rgba(0,0,0,0.1)'; this.style.borderColor='#94a3b8';" onmouseout="this.style.boxShadow='0 1px 3px rgba(0,0,0,0.05)'; this.style.borderColor='#cbd5e1';">
				{$icon}
				<h3 style="margin: 0 0 8px 0; font-size: 16px; color: #0f172a;">{$caption}</h3>
				<div style="font-size: 13px; color: #64748b; line-height: 1.4;">{$helptext}</div>
			</a>
HTML;
		}

		echo "</div>\n";
	}
}