<?php
/**
 * =============================================================================
 * Verze: 2026-10-21 15:00
 * Soubor: menu_manager.php
 * Třída: menu_manager
 * Účel: Globální správce uživatelského menu. 
 *       Zajišťuje načtení hierarchie, dohledání aktivního kontextu (best-match)
 *       a vykreslování navigačních prvků (drobečkové menu, dlaždice).
 * 
 * Vazby na okolí:
 * - Instancuje se typicky v index.php po volání initsession().
 * - Čerpá data z procedury p_get_menu_hierarchy pomocí sqlarray_simple().
 * - Využívá se v abstract_page pro vykreslení navigace pod hlavičkou.
 * - Pro překlad nouzového odkazu využívá globální $phrase_manager.
 * 
 * Změny:
 * 2026-10-21 15:00 - Čtení procedury p_get_menu_hierarchy převedeno ze sqlrun/fetch
 *                    na sqlarray_simple() (ochrana globálního $dbquery).
 *                  - Všechny operátory && nahrazeny za AND (Anti-LaTeX pravidlo).
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
	 * Načte plochý výsledek ze SQL do pole a postaví z něj vnitřní strom a vyhledávací indexy.
	 */
	protected function load_hierarchy(): void {
		$rows = sqlarray_simple("EXEC p_get_menu_hierarchy");                // Načtení hierarchie menu do pole v paměti
		if (!is_array($rows)) {                                              // Kontrola platného pole výsledků
			return;                                                          // Ukončení při prázdném výsledku
		}

		foreach ($rows as $row) {                                            // Průchod načtenými položkami menu
			$uuid = (string)$row['original'];                                // Originální UUID položky menu
			$this->items[$uuid] = $row;                                      // Uložení dat položky
			$this->by_code[(string)$row['builtin_code']] = $uuid;            // Indexace podle textového kódu
			
			$page = (string)$row['target_page'];                             // Cílová stránka (např. page_meta_class)
			if ($page !== '') {                                              // Pokud položka směřuje na stránku
				$this->by_page[$page][] = $uuid;                             // Indexace podle cílové stránky
			}
			
			$parent = (string)$row['parent_uuid'];                           // UUID nadřízené položky menu
			$this->children_map[$parent][] = $uuid;                          // Zařazení do seznamu potomků rodiče
		}
	}

	/**
	 * Vyhledá aktivní uzel. Preferuje &menu_code=. Pokud chybí, hledá přes &page=
	 * a vybírá "nejlepší shodu" na základě dodatečných URL parametrů.
	 */
	protected function resolve_active_node(): void {
		$req_menu = trim((string)getinput('menu_code'));                     // Požadovaný kód menu z URL
		$req_page = trim((string)getinput('page'));                          // Požadovaná stránka z URL

		// 1. Explicitní menu_code v URL
		if ($req_menu !== '' AND isset($this->by_code[$req_menu])) {         // Kontrola explicitního menu_code
			$this->active_uuid = $this->by_code[$req_menu];                  // Přímá shoda přes menu_code
			return;                                                          // Ukončení vyhledávání
		}

		// Normalizace názvu stránky na plný formát s prefixem 'page_'
		if ($req_page === '') {                                              // Kontrola prázdné stránky
			$req_page = 'page_main';                                         // Výchozí stránka při prázdném URL
		} else {
			$req_page = basename($req_page, '.php');                         // Očištění od cesty a přípony
			if (!str_starts_with($req_page, 'page_')) {                      // Kontrola přítomnosti předpony page_
				$req_page = 'page_' . $req_page;                             // Doplnění prefixu page_ pro kompatibilitu
			}
		}

		// 2. Fallback na vyhledání podle target_page s heuristikou pro best-match
		if ($req_page !== '' AND isset($this->by_page[$req_page])) {         // Hledání položky podle cílové stránky
			$candidates = $this->by_page[$req_page];                         // Seznam položek mířících na tuto stránku
			$best_match = $candidates[0];                                    // Výchozí první shoda

			foreach ($candidates as $uuid) {                                 // Průchod kandidátními položkami
				$params_str = (string)$this->items[$uuid]['url_parameters']; // Dodatečné parametry URL u položky
				if ($params_str !== '') {                                    // Pokud má položka definované parametry
					parse_str(ltrim($params_str, '&?'), $parsed_params);     // Rozparsování parametrů z DB
					$match = true;                                           // Příznak shody všech parametrů
					foreach ($parsed_params as $k => $v) {                   // Porovnání parametrů s aktuálním URL
						if ((string)getinput($k) !== (string)$v) {           // Kontrola shody hodnoty parametru
							$match = false;                                  // Parametr v URL neodpovídá položce
							break;                                           // Ukončení kontroly této položky
						}
					}
					if ($match) {                                            // Pokud všechny parametry sedí
						$best_match = $uuid;                                 // Nalezena přesná shoda parametrů
						break;                                               // Ukončení hledání kandidátů
					}
				}
			}
			
			$this->active_uuid = $best_match;                                // Nastavení nejlepší nalezené položky
			return;                                                          // Ukončení vyhledávání
		}

		// 3. Totální fallback na domovskou stránku
		if (isset($this->by_code['home'])) {                                 // Kontrola existence kořene Domů
			$this->active_uuid = $this->by_code['home'];                     // Nouzové nastavení na kořen Domů
		}
	}

	/**
	 * Sestaví URL odkaz pro konkrétní položku menu.
	 */
	public function build_link(array $item): string {                        // Sestavení odkazu položky menu
		if (!empty($item['is_disabled'])) {                                  // Kontrola deaktivované položky
			return '#';                                                      // Prázdný odkaz pro neaktivní položku
		}
		
		// 1. Odkaz na konkrétní modul / stránku
		if ((string)$item['target_page'] !== '') {                           // Pokud má položka cílovou stránku
			$url = "index.php?page=" . urlencode((string)$item['target_page']) . "&menu_code=" . urlencode((string)$item['builtin_code']); // Základní URL
			if ((string)$item['url_parameters'] !== '') {                    // Pokud jsou zadány další parametry
				$url .= $item['url_parameters'];                             // Připojení dodatečných GET parametrů
			}
			return htmlspecialchars($url);                                   // Vrácení ošetřené interní URL
		}
		
		// 2. Odkaz na externí / absolutní URL
		if ((string)$item['target_url'] !== '') {                            // Pokud má položka externí URL
			return htmlspecialchars((string)$item['target_url']);            // Vrácení ošetřené externí URL
		}
		
		// 3. Složka (nemá target_page) -> odkazujeme na page_main jako na Průzkumník
		return htmlspecialchars("index.php?page=page_main&menu_code=" . urlencode((string)$item['builtin_code'])); // Odkaz na složku
	}

	/**
	 * Vrátí data uzlu podle jeho textového identifikátoru (builtin_code).
	 */
	public function get_node_by_code(string $code): ?array {                 // Vyhledání uzlu podle builtin_code
		if (isset($this->by_code[$code])) {                                  // Pokud kód v indexu existuje
			$uuid = $this->by_code[$code];                                   // Zjištění UUID podle kódu
			return $this->items[$uuid] ?? null;                              // Vrácení dat uzlu
		}
		return null;                                                         // Uzel nebyl nalezen
	}

	/**
	 * Vrátí seznam potomků (asociativní pole uzlů) pro daný kód složky.
	 */
	public function get_children_by_code(string $code): array {              // Získání potomků složky podle kódu
		$node = $this->get_node_by_code($code);                              // Načtení rodičovského uzlu
		if (!$node) {                                                        // Pokud složka neexistuje
			return [];                                                       // Vrácení prázdného pole
		}

		$uuid = (string)$node['original'];                                   // UUID rodičovského uzlu
		$children = [];                                                      // Výsledné pole potomků
		
		if (isset($this->children_map[$uuid])) {                             // Pokud má uzel evidované potomky
			foreach ($this->children_map[$uuid] as $child_uuid) {            // Průchod potomky uzlu
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
		
		while ($curr !== null AND isset($this->items[$curr]) AND !isset($visited[$curr])) { // Průchod k rodičům
			array_unshift($path, $curr);                                     // Vložení uzlu na začátek cesty
			$visited[$curr] = true;                                          // Označení uzlu jako navštíveného
			$curr = (string)$this->items[$curr]['parent_uuid'] !== '' ? (string)$this->items[$curr]['parent_uuid'] : null; // Posun na rodiče
		}
		
		return $path;                                                        // Vrácení seřazené cesty
	}

	/**
	 * Vykreslí HTML drobečkové navigace (Breadcrumbs).
	 */
	public function render_breadcrumbs(): string {
		if (empty($this->items)) {                                           // Kontrola prázdného menu
			return '';                                                       // Nevykreslujeme prázdnou navigaci
		}

		$path = $this->get_active_path();                                    // Získání aktivní cesty v menu
		
		$html = <<<HTML
<style>
	.bcm-nav-container { background-color: #f8fafc; border-bottom: 1px solid #e2e8f0; padding: 6px 12px; font-family: Arial, sans-serif; font-size: 13px; }
	.bcm-breadcrumb { display: flex; align-items: center; list-style: none; margin: 0; padding: 0; gap: 2px; }
	.bcm-breadcrumb-item { position: relative; display: flex; align-items: center; }
	.bcm-breadcrumb-link { text-decoration: none; color: #334155; padding: 6px 10px; border-radius: 4px; transition: background 0.2s, color 0.2s; display: flex; align-items: center; gap: 6px; }
	.bcm-breadcrumb-link:hover, .bcm-breadcrumb-item:hover > .bcm-breadcrumb-link { background-color: #e2e8f0; color: #0f172a; }
	.bcm-breadcrumb-link.active { font-weight: bold; color: #004488; }
	.bcm-breadcrumb-separator { color: #94a3b8; font-size: 16px; margin: 0 4px; user-select: none; }
	.bcm-menu-icon svg { width: 16px; height: 16px; display: block; }
	.bcm-menu-dropdown { display: none; position: absolute; top: 100%; left: 0; background: #fff; box-shadow: 0 4px 12px rgba(0,0,0,0.15); border: 1px solid #cbd5e1; border-radius: 4px; min-width: 240px; z-index: 1000; margin: 0; padding: 4px 0; list-style: none; }
	.bcm-breadcrumb-item:hover .bcm-menu-dropdown { display: block; }
	.bcm-menu-link { display: flex; align-items: center; gap: 8px; padding: 8px 16px; text-decoration: none; color: #334155; font-size: 13px; transition: background 0.2s; }
	.bcm-menu-link:hover { background: #f1f5f9; color: #004488; }
	.bcm-menu-link.disabled { color: #94a3b8; cursor: default; pointer-events: none; }
	@media print { .bcm-nav-container { display: none !important; } }
</style>
<div class="bcm-nav-container">
	<ul class="bcm-breadcrumb">
HTML;

		if (empty($path)) {                                                  // Záchyt pokud stránka není v menu
			global $phrase_manager;                                          // Přístup ke globálnímu správci frází
			$home_caption = 'Domů';                                          // Výchozí text odkazu Domů
			if (isset($phrase_manager) AND ($phrase_manager instanceof phrase_manager)) { // Kontrola správce frází
				$home_caption = $phrase_manager->get('breadcrumb_home', [], 'Domů', 'menu_manager'); // Překlad odkazu Domů
			}
			$safe_home = htmlspecialchars($home_caption);                    // Ošetření HTML entit
			$html .= '<li class="bcm-breadcrumb-item"><a href="index.php" class="bcm-breadcrumb-link">' . $safe_home . '</a></li>'; // Nouzová položka
		} else {
			$last_idx = count($path) - 1;                                    // Index posledního prvku v cestě
			
			foreach ($path as $idx => $node_id) {                            // Průchod uzly drobečkové navigace
				$node = $this->items[$node_id];                              // Data aktuálního uzlu drobečkové cesty
				$children = $this->children_map[$node_id] ?? [];             // Potomci uzlu pro roletku
				
				$caption = htmlspecialchars((string)$node['caption']);       // Ošetřený název uzlu
				$helptext = htmlspecialchars((string)$node['helptext']);     // Ošetřený tooltip uzlu
				$icon = $node['svg_icon'] ? '<span class="bcm-menu-icon">' . $node['svg_icon'] . '</span>' : ''; // SVG ikona uzlu
				
				$link = $this->build_link($node);                            // Sestavení odkazu uzlu
				$target = $node['target_window'] ? ' target="' . htmlspecialchars((string)$node['target_window']) . '"' : ''; // Cílové okno
				$disabled_attr = !empty($node['is_disabled']) ? ' style="color:#94a3b8; cursor:default;" onclick="return false;"' : ''; // Deaktivace
				$active_class = ($idx === $last_idx) ? ' active' : '';       // Zvýraznění posledního prvku cesty

				$html .= '<li class="bcm-breadcrumb-item">';                 // Otevření položky drobečkové cesty
				$html .= "<a href=\"{$link}\" class=\"bcm-breadcrumb-link{$active_class}\"{$target}{$disabled_attr} title=\"{$helptext}\">{$icon}{$caption}</a>"; // Odkaz uzlu
				
				// Sestavení roletky s POTOMKY tohoto uzlu
				if (!empty($children)) {                                     // Pokud uzel obsahuje podpoložky
					$html .= '<ul class="bcm-menu-dropdown">';               // Otevření rozbalovacího seznamu
					foreach ($children as $child_id) {                       // Průchod podpoložkami uzlu
						$child = $this->items[$child_id];                    // Data podřízené položky
						$c_caption = htmlspecialchars((string)$child['caption']); // Název podpoložky
						$c_helptext = htmlspecialchars((string)$child['helptext']); // Tooltip podpoložky
						$c_icon = $child['svg_icon'] ? '<span class="bcm-menu-icon">' . $child['svg_icon'] . '</span>' : ''; // Ikona podpoložky
						
						$c_link = $this->build_link($child);                 // URL podřízené položky
						$c_target = $child['target_window'] ? ' target="' . htmlspecialchars((string)$child['target_window']) . '"' : ''; // Okno
						
						$classes = ['bcm-menu-link'];                        // Základní CSS třída položky v roletce
						if (!empty($child['is_disabled'])) {                 // Kontrola neaktivní podpoložky
							$classes[] = 'disabled';                         // Příznak neaktivní položky
						}
						if ((string)$child['css_class'] !== '') {            // Kontrola vlastní CSS třídy
							$classes[] = htmlspecialchars((string)$child['css_class']); // Přidání vlastní třídy
						}
						
						$class_str = implode(' ', $classes);                 // Spojení CSS tříd
						$c_disabled_attr = !empty($child['is_disabled']) ? ' onclick="return false;"' : ''; // Zákaz kliknutí
						
						$html .= "<li><a href=\"{$c_link}\" class=\"{$class_str}\"{$c_target}{$c_disabled_attr} title=\"{$c_helptext}\">{$c_icon}{$c_caption}</a></li>"; // Položka roletky
					}
					$html .= '</ul>';                                        // Uzavření rozbalovacího seznamu
				}
				$html .= '</li>';                                            // Uzavření položky drobečkové cesty

				if ($idx < $last_idx) {                                      // Pokud nejde o poslední uzel cesty
					$html .= '<li class="bcm-breadcrumb-separator">›</li>';  // Oddělovač úrovní
				}
			}
		}
		
		$html .= "	</ul>\n</div>";                                          // Uzavření kontejneru navigace
		return $html;                                                        // Vrácení kompletního HTML navigace
	}
}