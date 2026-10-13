<?php
/**
 * =============================================================================
 * Verze: 2026-10-13
 * Stránka: page_main.php
 * Účel: Hlavní rozcestník dynamicky generovaný z databáze metadat (Průzkumník).
 * 
 * Změny:
 * 2026-10-13 - Aplikace moderního CSS Grid layoutu (dlaždice/karty) místo 
 *              starého hover-rámečku. Zpracovává menu_code z URL a zobrazuje 
 *              potomky dané složky vyžádané přes globální menu_manager.
 * =============================================================================
 */

declare(strict_types=1);

class page_main extends abstract_page {

	public function __construct() {
		global $dbsession;

		$this->page_title = 'Hlavní panel - BCM Osiris';

		if (empty($dbsession['user_account'])) {
			$this->access_denied = true;
		}
	}

	protected function render_body(): void {
		global $menu_manager;

		$menu_code = (string)getinput('menu_code');
		if ($menu_code === '') {
			$menu_code = 'home';
		}

		// Získání informací o aktuální složce z manageru
		$current_node = $menu_manager->get_node_by_code($menu_code);
		$title = $current_node ? htmlspecialchars((string)($current_node['caption'] ?? '')) : 'Rozcestník';
		
		// Oprava: Používáme helptext (ten vrací SQL procedura po COALESCE překladu)
		$desc = $current_node ? htmlspecialchars((string)($current_node['helptext'] ?? '')) : '';
		if ($desc === '') {
			$desc = 'Vyberte požadovanou akci z níže uvedených modulů.';
		}

		echo <<<HTML
		<h1 class="page-heading">{$title}</h1>
		<p style="margin-bottom: 25px; color: #475569;">{$desc}</p>
HTML;

		// Načtení potomků aktuálního uzlu (obsah složky)
		$children = $menu_manager->get_children_by_code($menu_code);

		if (empty($children)) {
			echo "<div class='msg-info'>Tato složka momentálně neobsahuje žádné dostupné moduly.</div>";
			return;
		}

		// Responzivní CSS Grid pro dlaždice (karty)
		echo "<div style=\"display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px;\">\n";

		foreach ($children as $child) {
			// Skryté položky (bez přístupu) nevykreslujeme
			if (!empty($child['is_disabled'])) {
				continue;
			}

			$caption = htmlspecialchars((string)($child['caption'] ?? ''));
			$helptext = htmlspecialchars((string)($child['helptext'] ?? ''));
			$icon = !empty($child['svg_icon']) ? '<div style="width: 32px; height: 32px; color: #004488; margin-bottom: 15px;">' . $child['svg_icon'] . '</div>' : '<div style="width: 32px; height: 32px; background: #e2e8f0; border-radius: 4px; margin-bottom: 15px;"></div>';
			
			$link = $menu_manager->build_link($child);
			$target = !empty($child['target_window']) ? ' target="' . htmlspecialchars((string)$child['target_window']) . '"' : '';

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