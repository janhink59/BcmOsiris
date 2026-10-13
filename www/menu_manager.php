<?php
/**
 * =============================================================================
 * Verze: 2026-10-13
 * Třída: menu_manager
 * Účel: Globální správce uživatelského menu. 
 *       Zajišťuje načtení hierarchie, dohledání aktivního kontextu (best-match)
 *       a vykreslování navigačních prvků (drobečkové menu, dlaždice).
 * 
 * Vazby na okolí:
 * - Instancuje se typicky v index.php po volání initsession().
 * - Čerpá data z procedury p_get_menu_hierarchy.
 * - Využívá se v abstract_page pro vykreslení navigace pod hlavičkou.
 * 
 * Změny:
 * 2026-10-13 - Přidány metody get_node_by_code a get_children_by_code pro 
 *              vykreslování obsahu složek v page_main.php (CSS Grid dlaždice).
 *            - Úprava build_link() tak, aby pro uzly bez cílové stránky 
 *              (složky) generovala odkaz drill-down do page_main.
 * =============================================================================
 */

declare(strict_types=1);

class menu_manager {

	protected array $items = [];
	protected array $by_code = [];
	protected array $by_page = [];
	protected array $children_map = [];
	protected ?string $active_uuid = null;

	public function __construct() {
		$this->load_hierarchy();
		$this->resolve_active_node();
	}

	/**
	 * Načte plochý výsledek ze SQL a postaví z něj vnitřní strom a vyhledávací indexy.
	 */
	protected function load_hierarchy(): void {
		$q = sqlrun("EXEC p_get_menu_hierarchy");
		if (!$q) {
			return;
		}

		while ($row = fetch($q)) {
			$uuid = (string)$row['original'];
			$this->items[$uuid] = $row;
			$this->by_code[(string)$row['builtin_code']] = $uuid;
			
			$page = (string)$row['target_page'];
			if ($page !== '') {
				$this->by_page[$page][] = $uuid;
			}
			
			$parent = (string)$row['parent_uuid'];
			$this->children_map[$parent][] = $uuid;
		}
		free_result($q);
	}

	/**
	 * Vyhledá aktivní uzel. Preferuje &menu_code=. Pokud chybí, hledá přes &page=
	 * a vybírá "nejlepší shodu" na základě dodatečných URL parametrů.
	 */
	protected function resolve_active_node(): void {
		$req_menu = (string)getinput('menu_code');
		$req_page = (string)getinput('page');

		// 1. Explicitní menu_code v URL
		if ($req_menu !== '' && isset($this->by_code[$req_menu])) {
			$this->active_uuid = $this->by_code[$req_menu];
			return;
		}

		// 2. Fallback na vyhledání podle target_page s heuristikou pro best-match
		if ($req_page !== '' && isset($this->by_page[$req_page])) {
			$candidates = $this->by_page[$req_page];
			$best_match = $candidates[0];                            // Výchozí první shoda

			foreach ($candidates as $uuid) {
				$params_str = (string)$this->items[$uuid]['url_parameters'];
				if ($params_str !== '') {
					// Převedení parametrů v menu (&parent_class=123) na asociativní pole
					parse_str(ltrim($params_str, '&?'), $parsed_params);
					$match = true;
					foreach ($parsed_params as $k => $v) {
						if ((string)getinput($k) !== (string)$v) {
							$match = false;
							break;
						}
					}
					// Pokud všechny parametry z DB sedí s $_GET, máme perfektní shodu
					if ($match) {
						$best_match = $uuid;
						break;
					}
				}
			}
			
			$this->active_uuid = $best_match;
			return;
		}

		// 3. Totální fallback na domovskou stránku
		if (isset($this->by_code['home'])) {
			$this->active_uuid = $this->by_code['home'];
		}
	}

	/**
	 * Sestaví URL odkaz pro konkrétní položku menu.
	 */
	public function build_link(array $item): string {
		if (!empty($item['is_disabled'])) {
			return '#';
		}
		
		// 1. Odkaz na konkrétní modul / stránku
		if ((string)$item['target_page'] !== '') {
			$url = "index.php?page=" . urlencode((string)$item['target_page']) . "&menu_code=" . urlencode((string)$item['builtin_code']);
			if ((string)$item['url_parameters'] !== '') {
				$url .= $item['url_parameters'];
			}
			return htmlspecialchars($url);
		}
		
		// 2. Odkaz na externí / absolutní URL
		if ((string)$item['target_url'] !== '') {
			return htmlspecialchars((string)$item['target_url']);
		}
		
		// 3. Složka (nemá target_page) -> odkazujeme na page_main jako na Průzkumník
		return htmlspecialchars("index.php?page=main&menu_code=" . urlencode((string)$item['builtin_code']));
	}

	/**
	 * Vrátí data uzlu podle jeho textového identifikátoru (builtin_code).
	 * Slouží primárně pro page_main.php
	 */
	public function get_node_by_code(string $code): ?array {
		if (isset($this->by_code[$code])) {
			$uuid = $this->by_code[$code];
			return $this->items[$uuid] ?? null;
		}
		return null;
	}

	/**
	 * Vrátí seznam potomků (asociativní pole uzlů) pro daný kód složky.
	 * Slouží primárně pro vykreslení dlaždic v page_main.php.
	 */
	public function get_children_by_code(string $code): array {
		$node = $this->get_node_by_code($code);
		if (!$node) {
			return [];
		}

		$uuid = $node['original'];
		$children = [];
		
		if (isset($this->children_map[$uuid])) {
			foreach ($this->children_map[$uuid] as $child_uuid) {
				$children[] = $this->items[$child_uuid];
			}
		}
		
		return $children;
	}

	/**
	 * Vrátí pole UUID tvořící cestu od kořene k aktivnímu uzlu.
	 */
	public function get_active_path(): array {
		$path = [];
		$curr = $this->active_uuid;
		$visited = []; 
		
		while ($curr !== null && isset($this->items[$curr]) && !isset($visited[$curr])) {
			array_unshift($path, $curr);
			$visited[$curr] = true;
			$curr = (string)$this->items[$curr]['parent_uuid'] !== '' ? (string)$this->items[$curr]['parent_uuid'] : null;
		}
		
		return $path;
	}

	/**
	 * Vykreslí HTML drobečkové navigace (Breadcrumbs).
	 */
	public function render_breadcrumbs(): string {
		if (empty($this->items)) {
			return '';
		}

		$path = $this->get_active_path();
		
		$html = <<<HTML
<style>
	/* Drobečková navigace (Breadcrumbs) a rozbalovací menu */
	.bcm-nav-container {
		background-color: #f8fafc;
		border-bottom: 1px solid #e2e8f0;
		padding: 6px 12px;
		font-family: Arial, sans-serif;
		font-size: 13px;
	}
	.bcm-breadcrumb {
		display: flex;
		align-items: center;
		list-style: none;
		margin: 0;
		padding: 0;
		gap: 2px;
	}
	.bcm-breadcrumb-item {
		position: relative;
		display: flex;
		align-items: center;
	}
	.bcm-breadcrumb-link {
		text-decoration: none;
		color: #334155;
		padding: 6px 10px;
		border-radius: 4px;
		transition: background 0.2s, color 0.2s;
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.bcm-breadcrumb-link:hover, .bcm-breadcrumb-item:hover > .bcm-breadcrumb-link {
		background-color: #e2e8f0;
		color: #0f172a;
	}
	.bcm-breadcrumb-link.active {
		font-weight: bold;
		color: #004488;
	}
	.bcm-breadcrumb-separator {
		color: #94a3b8;
		font-size: 16px;
		margin: 0 4px;
		user-select: none;
	}
	.bcm-menu-icon svg {
		width: 16px;
		height: 16px;
		display: block;
	}
	/* Rozbalovací roletka (Dropdown) zobrazující potomky */
	.bcm-menu-dropdown {
		display: none;
		position: absolute;
		top: 100%;
		left: 0;
		background: #fff;
		box-shadow: 0 4px 12px rgba(0,0,0,0.15);
		border: 1px solid #cbd5e1;
		border-radius: 4px;
		min-width: 240px;
		z-index: 1000;
		margin: 0;
		padding: 4px 0;
		list-style: none;
	}
	.bcm-breadcrumb-item:hover .bcm-menu-dropdown {
		display: block;
	}
	.bcm-menu-link {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 16px;
		text-decoration: none;
		color: #334155;
		font-size: 13px;
		transition: background 0.2s;
	}
	.bcm-menu-link:hover {
		background: #f1f5f9;
		color: #004488;
	}
	.bcm-menu-link.disabled {
		color: #94a3b8;
		cursor: default;
		pointer-events: none;
	}
	@media print { .bcm-nav-container { display: none !important; } }
</style>
<div class="bcm-nav-container">
	<ul class="bcm-breadcrumb">
HTML;

		if (empty($path)) {
			// Záchyt pro případ, že URL page nemá v menu vůbec žádný záznam
			$html .= '<li class="bcm-breadcrumb-item"><a href="index.php" class="bcm-breadcrumb-link">Domů</a></li>';
		} else {
			$last_idx = count($path) - 1;
			
			foreach ($path as $idx => $node_id) {
				$node = $this->items[$node_id];
				$children = $this->children_map[$node_id] ?? [];
				
				$caption = htmlspecialchars((string)$node['caption']);
				$helptext = htmlspecialchars((string)$node['helptext']);
				$icon = $node['svg_icon'] ? '<span class="bcm-menu-icon">' . $node['svg_icon'] . '</span>' : '';
				
				$link = $this->build_link($node);
				$target = $node['target_window'] ? ' target="' . htmlspecialchars((string)$node['target_window']) . '"' : '';
				$disabled_attr = !empty($node['is_disabled']) ? ' style="color:#94a3b8; cursor:default;" onclick="return false;"' : '';
				
				$active_class = ($idx === $last_idx) ? ' active' : '';

				$html .= '<li class="bcm-breadcrumb-item">';
				$html .= "<a href=\"{$link}\" class=\"bcm-breadcrumb-link{$active_class}\"{$target}{$disabled_attr} title=\"{$helptext}\">{$icon}{$caption}</a>";
				
				// Sestavení roletky s POTOMKY tohoto uzlu
				if (!empty($children)) {
					$html .= '<ul class="bcm-menu-dropdown">';
					foreach ($children as $child_id) {
						$child = $this->items[$child_id];
						$c_caption = htmlspecialchars((string)$child['caption']);
						$c_helptext = htmlspecialchars((string)$child['helptext']);
						$c_icon = $child['svg_icon'] ? '<span class="bcm-menu-icon">' . $child['svg_icon'] . '</span>' : '';
						
						$c_link = $this->build_link($child);
						$c_target = $child['target_window'] ? ' target="' . htmlspecialchars((string)$child['target_window']) . '"' : '';
						
						$classes = ['bcm-menu-link'];
						if (!empty($child['is_disabled'])) {
							$classes[] = 'disabled';
						}
						if ((string)$child['css_class'] !== '') {
							$classes[] = htmlspecialchars((string)$child['css_class']);
						}
						
						$class_str = implode(' ', $classes);
						$c_disabled_attr = !empty($child['is_disabled']) ? ' onclick="return false;"' : '';
						
						$html .= "<li><a href=\"{$c_link}\" class=\"{$class_str}\"{$c_target}{$c_disabled_attr} title=\"{$c_helptext}\">{$c_icon}{$c_caption}</a></li>";
					}
					$html .= '</ul>';
				}
				$html .= '</li>';

				// Separátor úrovní (šipka)
				if ($idx < $last_idx) {
					$html .= '<li class="bcm-breadcrumb-separator">›</li>';
				}
			}
		}
		
		$html .= "	</ul>\n</div>";
		return $html;
	}
}