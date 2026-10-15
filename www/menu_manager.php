<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 22:15
 * Soubor: menu_manager.php
 * Třída: menu_manager
 * Účel: Globální správce uživatelského menu. 
 *       Zajišťuje načtení hierarchie, dohledání aktivního kontextu (best-match)
 *       a vykreslování navigačních prvků (drobečkové menu, dlaždice).
 * 
 * Vazby na okolí:
 * - Instancuje se typicky v index.php po volání initsession().
 * - Čerpá data z procedury p_get_menu_hierarchy.
 * - Využívá se v abstract_page pro vykreslení navigace pod hlavičkou.
 * - Pro překlad nouzového odkazu využívá globální $phrase_manager.
 * 
 * Změny:
 * 2026-10-13 - Přidány metody get_node_by_code a get_children_by_code pro 
 *              vykreslování obsahu složek v page_main.php (CSS Grid dlaždice).
 *            - Úprava build_link() tak, aby pro uzly bez cílové stránky 
 *              (složky) generovala odkaz drill-down do page_main.
 * 2026-10-15 - Sjednocení detekce aktivní stránky a odkazů složek na plné názvy
 *              s prefixem 'page_' (při zachování zpětné kompatibility URL).
 * =============================================================================
 */

declare(strict_types=1);

class menu_manager {

	protected array $items = [];                                             // Všechny načtené položky menu podle UUID
	protected array $by_code = [];                                           // Vyhledávací index podle builtin_code
	protected array $by_page = [];                                           // Vyhledávací index podle target_page
	protected array $children_map = [];                                      // Mapa potomků podle parent_uuid
	protected ?string $active_uuid = null;                                   // UUID aktuálně aktivní položky menu

	public function __construct() {
		$this->load_hierarchy();                                             // Načtení stromu menu z databáze
		$this->resolve_active_node();                                        // Určení aktivního uzlu podle URL
	}

	/**
	 * Načte plochý výsledek ze SQL a postaví z něj vnitřní strom a vyhledávací indexy.
	 */
	protected function load_hierarchy(): void {
		$q = sqlrun("EXEC p_get_menu_hierarchy");                            // Spuštění procedury pro načtení menu
		if (!$q) {
			return;
		}

		while ($row = fetch($q)) {
			$uuid = (string)$row['original'];                                // Originální UUID položky menu
			$this->items[$uuid] = $row;                                      // Uložení dat položky
			$this->by_code[(string)$row['builtin_code']] = $uuid;            // Indexace podle textového kódu
			
			$page = (string)$row['target_page'];                             // Cílová stránka (např. page_meta_class)
			if ($page !== '') {
				$this->by_page[$page][] = $uuid;                             // Indexace podle cílové stránky
			}
			
			$parent = (string)$row['parent_uuid'];                           // UUID nadřízené položky menu
			$this->children_map[$parent][] = $uuid;                          // Zařazení do seznamu potomků rodiče
		}
		free_result($q);                                                     // Uvolnění výsledku dotazu
	}

	/**
	 * Vyhledá aktivní uzel. Preferuje &menu_code=. Pokud chybí, hledá přes &page=
	 * a vybírá "nejlepší shodu" na základě dodatečných URL parametrů.
	 */
	protected function resolve_active_node(): void {
		$req_menu = trim((string)getinput('menu_code'));                     // Požadovaný kód menu z URL
		$req_page = trim((string)getinput('page'));                          // Požadovaná stránka z URL

		// 1. Explicitní menu_code v URL
		if ($req_menu !== '' && isset($this->by_code[$req_menu])) {
			$this->active_uuid = $this->by_code[$req_menu];                  // Přímá shoda přes menu_code
			return;
		}

		// Normalizace názvu stránky na plný formát s prefixem 'page_'
		if ($req_page === '') {
			$req_page = 'page_main';                                         // Výchozí stránka při prázdném URL
		} else {
			$req_page = basename($req_page, '.php');                         // Očištění od cesty a přípony
			if (!str_starts_with($req_page, 'page_')) {
				$req_page = 'page_' . $req_page;                             // Doplnění prefixu page_ pro kompatibilitu
			}
		}

		// 2. Fallback na vyhledání podle target_page s heuristikou pro best-match
		if ($req_page !== '' && isset($this->by_page[$req_page])) {
			$candidates = $this->by_page[$req_page];                         // Seznam položek mířících na tuto stránku
			$best_match = $candidates[0];                                    // Výchozí první shoda

			foreach ($candidates as $uuid) {
				$params_str = (string)$this->items[$uuid]['url_parameters']; // Dodatečné parametry URL u položky
				if ($params_str !== '') {
					// Převedení parametrů v menu (&parent_class=123) na asociativní pole
					parse_str(ltrim($params_str, '&?'), $parsed_params);     // Rozparsování parametrů z DB
					$match = true;                                           // Příznak shody všech parametrů
					foreach ($parsed_params as $k => $v) {
						if ((string)getinput($k) !== (string)$v) {
							$match = false;                                  // Parametr v URL neodpovídá položce
							break;
						}
					}
					// Pokud všechny parametry z DB sedí s $_GET, máme perfektní shodu
					if ($match) {
						$best_match = $uuid;                                 // Nalezena přesná shoda parametrů
						break;
					}
				}
			}
			
			$this->active_uuid = $best_match;                                // Nastavení nejlepší nalezené položky
			return;
		}

		// 3. Totální fallback na domovskou stránku
		if (isset($this->by_code['home'])) {
			$this->active_uuid = $this->by_code['home'];                     // Nouzové nastavení na kořen Domů
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
				$url .= $item['url_parameters'];                             // Připojení dodatečných GET parametrů
			}
			return htmlspecialchars($url);
		}
		
		// 2. Odkaz na externí / absolutní URL
		if ((string)$item['target_url'] !== '') {
			return htmlspecialchars((string)$item['target_url']);
		}
		
		// 3. Složka (nemá target_page) -> odkazujeme na page_main jako na Průzkumník
		return htmlspecialchars("index.php?page=page_main&menu_code=" . urlencode((string)$item['builtin_code']));
	}

	/**
	 * Vrátí data uzlu podle jeho textového identifikátoru (builtin_code).
	 * Slouží primárně pro page_main.php
	 */
	public function get_node_by_code(string $code): ?array {
		if (isset($this->by_code[$code])) {
			$uuid = $this->by_code[$code];                                   // Zjištění UUID podle kódu
			return $this->items[$uuid] ?? null;
		}
		return null;
	}

	/**
	 * Vrátí seznam potomků (asociativní pole uzlů) pro daný kód složky.
	 * Slouží primárně pro vykreslení dlaždic v page_main.php.
	 */
	public function get_children_by_code(string $code): array {
		$node = $this->get_node_by_code($code);                              // Načtení rodičovského uzlu
		if (!$node) {
			return [];
		}

		$uuid = $node['original'];                                           // UUID rodičovského uzlu
		$children = [];                                                      // Výsledné pole potomků
		
		if (isset($this->children_map[$uuid])) {
			foreach ($this->children_map[$uuid] as $child_uuid) {
				$children[] = $this->items[$child_uuid];                     // Přidání potomka do výsledku
			}
		}
		
		return $children;                                                    // Vrácení seznamu potomků
	}

	/**
	 * Vrátí pole UUID tvořící cestu od kořene k aktivnímu uzlu.
	 */
	public function get_active_path(): array {
		$path = [];                                                          // Pole pro sestavení cesty od kořene
		$curr = $this->active_uuid;                                          // Začínáme od aktivního uzlu
		$visited = [];                                                       // Ochrana proti zacyklení v hierarchii
		
		while ($curr !== null && isset($this->items[$curr]) && !isset($visited[$curr])) {
			array_unshift($path, $curr);                                     // Vložení uzlu na začátek cesty
			$visited[$curr] = true;                                          // Označení uzlu jako navštíveného
			$curr = (string)$this->items[$curr]['parent_uuid'] !== '' ? (string)$this->items[$curr]['parent_uuid'] : null;
		}
		
		return $path;                                                        // Vrácení seřazené cesty
	}

	/**
	 * Vykreslí HTML drobečkové navigace (Breadcrumbs).
	 */
	public function render_breadcrumbs(): string {
		if (empty($this->items)) {
			return '';
		}

		$path = $this->get_active_path();                                    // Získání aktivní cesty v menu
		
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
			global $phrase_manager;                                          // Přístup ke globálnímu správci frází
			$home_caption = 'Domů';                                          // Výchozí text odkazu Domů
			if (isset($phrase_manager) && $phrase_manager instanceof phrase_manager) {
				$home_caption = $phrase_manager->get('breadcrumb_home', [], 'Domů', 'menu_manager');
			}
			$safe_home = htmlspecialchars($home_caption);                    // Ošetření HTML entit
			$html .= '<li class="bcm-breadcrumb-item"><a href="index.php" class="bcm-breadcrumb-link">' . $safe_home . '</a></li>';
		} else {
			$last_idx = count($path) - 1;                                    // Index posledního prvku v cestě
			
			foreach ($path as $idx => $node_id) {
				$node = $this->items[$node_id];                              // Data aktuálního uzlu drobečkové cesty
				$children = $this->children_map[$node_id] ?? [];             // Potomci uzlu pro roletku
				
				$caption = htmlspecialchars((string)$node['caption']);       // Ošetřený název uzlu
				$helptext = htmlspecialchars((string)$node['helptext']);     // Ošetřený tooltip uzlu
				$icon = $node['svg_icon'] ? '<span class="bcm-menu-icon">' . $node['svg_icon'] . '</span>' : '';
				
				$link = $this->build_link($node);                            // Sestavení odkazu uzlu
				$target = $node['target_window'] ? ' target="' . htmlspecialchars((string)$node['target_window']) . '"' : '';
				$disabled_attr = !empty($node['is_disabled']) ? ' style="color:#94a3b8; cursor:default;" onclick="return false;"' : '';
				
				$active_class = ($idx === $last_idx) ? ' active' : '';       // Zvýraznění posledního prvku cesty

				$html .= '<li class="bcm-breadcrumb-item">';
				$html .= "<a href=\"{$link}\" class=\"bcm-breadcrumb-link{$active_class}\"{$target}{$disabled_attr} title=\"{$helptext}\">{$icon}{$caption}</a>";
				
				// Sestavení roletky s POTOMKY tohoto uzlu
				if (!empty($children)) {
					$html .= '<ul class="bcm-menu-dropdown">';
					foreach ($children as $child_id) {
						$child = $this->items[$child_id];                    // Data podřízené položky
						$c_caption = htmlspecialchars((string)$child['caption']);
						$c_helptext = htmlspecialchars((string)$child['helptext']);
						$c_icon = $child['svg_icon'] ? '<span class="bcm-menu-icon">' . $child['svg_icon'] . '</span>' : '';
						
						$c_link = $this->build_link($child);                 // URL podřízené položky
						$c_target = $child['target_window'] ? ' target="' . htmlspecialchars((string)$child['target_window']) . '"' : '';
						
						$classes = ['bcm-menu-link'];                        // Základní CSS třída položky v roletce
						if (!empty($child['is_disabled'])) {
							$classes[] = 'disabled';                         // Příznak neaktivní položky
						}
						if ((string)$child['css_class'] !== '') {
							$classes[] = htmlspecialchars((string)$child['css_class']);
						}
						
						$class_str = implode(' ', $classes);                 // Spojení CSS tříd
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
		return $html;                                                        // Vrácení kompletního HTML navigace
	}
}