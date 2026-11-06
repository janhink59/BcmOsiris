<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 15:30
 * Soubor: page_main.php
 * Stránka: page_main.php
 * Účel: Hlavní rozcestník dynamicky generovaný z databáze metadat (Průzkumník).
 *
 * Vazby na okolí:
 * - Dědí z abstract_page (využívá $this->page_title, $this->access_denied a $this->phrase()).
 * - Využívá globální $menu_manager pro načtení aktivní složky a jejích potomků.
 * 
 * Změny:
 * 2026-11-06 15:30 - Umístění ikony a názvu položky menu (<h3>) vedle sebe (.bcm-tile-header)
 *                    pro úsporu výšky dlaždice a sjednocení mezer před znakem $ (Anti-LaTeX).
 * 2026-11-05 16:55 - Kompaktní zobrazení: zkrácení všech hodnot padding, margin a gap
 *                    na polovinu a sjednocení CSS chování barev SVG ikon v dlaždicích.
 * 2026-10-16 08:25 - Doplněno volání parent::__construct() a lokalizace všech
 *                    výchozích textů přes $this->phrase().
 * =============================================================================
 */

declare(strict_types=1);

class page_main extends abstract_page {

	public function __construct() {
		parent::__construct(); // Inicializace správce frází a kontroly přístupu

		global $dbsession; // Globální kontext relace uživatele

		$this->page_title = $this->phrase('page_title', [], 'Hlavní panel - BCM Osiris'); // Lokalizovaný titulek stránky

		if (empty($dbsession['user_account'])) { // Kontrola přihlášeného uživatele
			$this->access_denied = true; // Odepření přístupu při chybějící relaci
		}
	}

	protected function render_body(): void {
		global $menu_manager; // Globální instance správce navigace

		$menu_code = (string) getinput('menu_code'); // Kód požadované složky menu z URL
		if ($menu_code === '') { // Pokud nebyl kód složky předán
			$menu_code = 'home'; // Výchozí kořenová složka Domů
		}

		$default_heading = $this->phrase('default_heading', [], 'Rozcestník'); // Výchozí nadpis rozcestníku

		$current_node = $menu_manager->get_node_by_code($menu_code); // Načtení uzlu složky z menu_manageru
		$title = $current_node ? htmlspecialchars((string) ($current_node['caption'] ?? '')) : htmlspecialchars($default_heading); // Nadpis složky
		
		$desc = $current_node ? htmlspecialchars((string) ($current_node['helptext'] ?? '')) : ''; // Popis složky z helptextu
		if ($desc === '') { // Pokud složka nemá vlastní helptext
			$desc = htmlspecialchars($this->phrase('default_description', [], 'Vyberte požadovanou akci z níže uvedených modulů.')); // Výchozí popis
		}

		echo <<<HTML
		<style>
			.page-panel { padding: 10px; margin: 8px auto; }
			h1.page-heading { padding-bottom: 5px; margin-bottom: 6px; }
			.bcm-tile-header { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
			.bcm-tile-icon { width: 24px; height: 24px; color: #004488; flex-shrink: 0; }
			.bcm-tile-icon svg { width: 100%; height: 100%; display: block; }
			.bcm-tile-icon svg:not([fill]) { fill: currentColor; }
			.bcm-tile-placeholder { width: 24px; height: 24px; background: #e2e8f0; border-radius: 4px; flex-shrink: 0; }
		</style>
		<h1 class="page-heading">{$title}</h1>
		<p style="margin: 0 0 12px 0; color: #475569;">{$desc}</p>
HTML;

		$children = $menu_manager->get_children_by_code($menu_code); // Seznam podřízených položek menu

		if (empty($children)) { // Pokud složka neobsahuje žádné položky
			$msg_empty = htmlspecialchars($this->phrase('msg_folder_empty', [], 'Tato složka momentálně neobsahuje žádné dostupné moduly.')); // Zpráva
			echo "<div class='msg-info'>{$msg_empty}</div>"; // Výpis informační zprávy
			return; // Ukončení vykreslování prázdné složky
		}

		echo "<div style=\"display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 10px;\">\n";

		foreach ($children as $child) { // Průchod podřízenými položkami složky
			if (! empty($child['is_disabled'])) { // Přeskočení neaktivní položky
				continue; // Pokračování na další dlaždici
			}

			$caption = htmlspecialchars((string) ($child['caption'] ?? '')); // Ošetřený název dlaždice
			$helptext = htmlspecialchars((string) ($child['helptext'] ?? '')); // Ošetřený popis dlaždice
			$icon = ! empty($child['svg_icon'])
				? '<div class="bcm-tile-icon">' . $child['svg_icon'] . '</div>'
				: '<div class="bcm-tile-placeholder"></div>'; // Ikona dlaždice nebo zástupný čtverec
			
			$link = $menu_manager->build_link($child); // Cílová URL adresa dlaždice
			$target = ! empty($child['target_window']) ? ' target="' . htmlspecialchars((string) $child['target_window']) . '"' : ''; // Cílové okno odkazu

			echo <<<HTML
			<a href="{$link}"{$target} style="display: block; background: #fff; border: 1px solid #cbd5e1; border-radius: 6px; padding: 10px; text-decoration: none; color: #334155; transition: all 0.2s ease; box-shadow: 0 1px 3px rgba(0,0,0,0.05);" onmouseover="this.style.boxShadow='0 4px 12px rgba(0,0,0,0.1)'; this.style.borderColor='#94a3b8';" onmouseout="this.style.boxShadow='0 1px 3px rgba(0,0,0,0.05)'; this.style.borderColor='#cbd5e1';">
				<div class="bcm-tile-header">
					{$icon}
					<h3 style="margin: 0; font-size: 16px; line-height: 1.25; color: #0f172a;">{$caption}</h3>
				</div>
				<div style="font-size: 13px; color: #64748b; line-height: 1.4;">{$helptext}</div>
			</a>
HTML;
		}

		echo "</div>\n";
	}
}