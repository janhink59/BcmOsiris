<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 00:20
 * Soubor: abstract_page.php
 * Třída: abstract_page
 * Účel: Základní abstraktní třída pro objektově orientované stránky.
 *       Zajišťuje jednotný layout, centrální CSS styly, zobrazení kontextu 
 *       uživatele (horní pruh) a dynamickou drobečkovou navigaci.
 * 
 * ARCHITEKTONICKÉ VAZBY:
 * - Volána z centrálního routeru `index.php`.
 * - Instancuje `phrase_manager` (`$GLOBALS['phrase_manager']`), `user_context`
 *   a volá `has_role_access()` z `new_functions.php` a `$menu_manager->render_breadcrumbs()`.
 * 
 * Změny:
 * 2026-11-06 00:20 - Oprava sloučených řádků v metodách phrase() a render() a doplnění
 *                    mezer před znakem $ a diakritiky v komentářích (Anti-LaTeX).
 * 2026-11-05 16:45 - Sjednocení chování barev SVG ikon v tlačítkách (.btn svg:not([fill]))
 *                    pro zachování vlastních barev ikon i podpory currentColor.
 * 2026-11-01 12:15 - V check_system_role_access() využita sdílená funkce
 *                    has_role_access() z new_functions.php.
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page {

	protected string $page_title = 'BCM Osiris';                             // Výchozí titulek v prohlížeči
	protected bool $access_denied = false;                                   // Příznak odepření přístupu ke stránce
	protected bool $full_width = false;                                      // Příznak plné šířky obsahu stránky
	protected ?phrase_manager $phrases = null;                               // Lokální reference na správce frází

	public function __construct() {
		$this->init_phrases();                                               // Inicializace frází pro hierarchii třídy
		$this->check_system_role_access();                                   // Fail-safe kontrola oprávnění z meta_object
	}

	/**
	 * Zajistí vytvoření instance phrase_manager pro aktuální stránku.
	 */
	protected function init_phrases(): void {
		if ($this->phrases === null) {                                       // Pokud správce frází ještě není vytvořen
			$this->phrases = new phrase_manager($this);                      // Dávkové načtení frází přes reflexi
			$GLOBALS['phrase_manager'] = $this->phrases;                     // Zpřístupnění pro tlačítka a komponenty
		}
	}

	/**
	 * Ověří v tabulce meta_object (object_type = 'P'), zda má přihlášený uživatel
	 * dostatečnou active_role pro přístup k této stránce (Fail-safe autorizace).
	 */
	protected function check_system_role_access(): void {
		global $dbsession;                                                   // Globální kontext relace uživatele
		if (empty($dbsession) OR ! isset($dbsession['active_role'])) {       // Kontrola platné inicializace relace
			return;                                                          // Pokud relace není inicializována, neblokujeme
		}

		$active_role = (string) $dbsession['active_role'];                   // Aktuální role uživatele (U, A, S, D)
		if ($active_role === 'S' OR $active_role === 'D') {                  // Kontrola nejvyšších systémových rolí
			return;                                                          // Sysadmin a Developer mají přístup vždy
		}

		$class_name = get_class($this);                                      // Název třídy aktuální stránky
		$safe_code = charliteral($class_name, 80);                           // SQL literál názvu třídy

		$row = sqlfirstrow("
			SELECT TOP 1 system_role
			FROM meta_object
			WHERE object_type = 'P'
			  AND builtin_code = {$safe_code}
			  AND record_type = 'A'
			  AND removed = 0
			ORDER BY CASE WHEN object_owner = 0x00 THEN 1 ELSE 0 END
		");                                                                  // Dotaz na požadovanou roli stránky

		if (! empty($row) AND isset($row['system_role'])) {                  // Pokud je stránka v meta_object registrována
			$req_role = (string) $row['system_role'];                        // Minimální vyžadovaná role (U, A, S, D)
			if (! has_role_access($req_role, $active_role)) {                // Vyhodnocení přes sdílenou funkci has_role_access
				$this->access_denied = true;                                 // Odepření přístupu při nedostatečné roli
			}
		}
	}

	/**
	 * Pomocná metoda pro pohodlné získání přeložené fráze v potomcích.
	 *
	 * @param string               $builtin_code    Kód fráze
	 * @param array<string, mixed> $vars            Proměnné pro interpolaci {$var}
	 * @param string               $default_caption Výchozí text při neexistenci v DB
	 * @return string Přeložený text fráze
	 */
	public function phrase(string $builtin_code, array $vars = [], string $default_caption = ''): string { // Překlad fráze stránky
		$this->init_phrases();                                               // Pojistka inicializace správce frází
		return $this->phrases->get($builtin_code, $vars, $default_caption);  // Vrácení přeložené a interpolované fráze
	}

	/**
	 * Metoda pro zpracování POST dat (PRG vzor).
	 */
	protected function process_save(): void {
		// Výchozí prázdná implementace pro překrytí v potomcích
	}

	/**
	 * Hlavní renderovací metoda volaná z index.php.
	 */
	public function render(): void {
		$this->init_phrases();                                               // Pojistka inicializace frází
		$this->check_system_role_access();                                   // Pojistka kontroly oprávnění

		if (! $this->access_denied AND ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') { // Kontrola odeslání formuláře metodou POST
			$this->process_save();                                           // Spuštění ukládací logiky potomka pouze při POST
		}

		$user_context = new user_context();                                  // Horní lišta s kontextem uživatele

		global $menu_manager, $dbsession;                                    // Přístup k navigaci a relaci
		$breadcrumbs_html = '';                                              // HTML kód drobečkové navigace
		if (isset($menu_manager) AND is_object($menu_manager)) {             // Kontrola existence správce navigace
			$breadcrumbs_html = $menu_manager->render_breadcrumbs();         // Vykreslení drobečkové navigace
		}

		$lang_code = htmlspecialchars((string) ($dbsession['language'] ?? 'cs')); // Kód jazyka do atributu html
		$safe_title = htmlspecialchars($this->page_title);                   // Bezpečný titulek stránky
		$unsaved_msg = addslashes($this->phrase('msg_unsaved_changes', [], 'Máte neuložené změny. Opravdu chcete stránku opustit?')); // Text varování
		$panel_cls = $this->full_width ? 'page-panel page-panel-full' : 'page-panel'; // Volba šířky hlavního panelu

		echo <<<HTML
<!DOCTYPE html>
<html lang="{$lang_code}">
<head>
	<meta charset="utf-8">
	<title>{$safe_title}</title>
	<style>
		body { 
			font-family: Arial, sans-serif; 
			background-color: #f4f4f4; 
			margin: 0; 
			padding: 0;
			color: #333; 
		}
		.page-panel { 
			background-color: #fff; 
			padding: 20px; 
			border-radius: 5px; 
			box-shadow: 0 0 10px rgba(0,0,0,0.1); 
			margin: 15px auto;
			max-width: 800px; 
		}
		.page-panel.page-panel-full {
			max-width: none;
			margin: 10px 15px;
			overflow-x: auto;
		}
		h1.page-heading { 
			color: #004488; 
			margin-top: 0; 
			border-bottom: 2px solid #eee; 
			padding-bottom: 10px; 
		}
		.md-table {
			width: 100%;
			border-collapse: collapse;
			font-size: 13px;
		}
		.md-table th, .md-table td {
			border: 1px solid #cbd5e1;
			padding: 6px 10px;
			text-align: left;
			vertical-align: top;
		}
		.md-table th {
			background-color: #f1f5f9;
			font-weight: bold;
		}
		.btn { 
			display: inline-flex; 
			align-items: center; 
			gap: 6px; 
			padding: 10px 15px; 
			background-color: #004488; 
			color: #fff; 
			text-decoration: none; 
			border: none; 
			border-radius: 3px; 
			font-weight: bold; 
			font-size: 13px; 
			line-height: 1.2; 
			cursor: pointer; 
			box-sizing: border-box; 
		}
		.btn:hover { background-color: #003366; }
		.btn:disabled, .btn.disabled { opacity: 0.6; cursor: not-allowed; pointer-events: none; }
		.btn-icon { display: inline-flex; align-items: center; }
		.btn-icon svg, .btn svg { width: 16px; height: 16px; display: block; flex-shrink: 0; }
		.btn-icon svg:not([fill]), .btn svg:not([fill]) { fill: currentColor; }
		.btn-danger { background-color: #b71c1c; }
		.btn-danger:hover { background-color: #8e1515; }
		.btn-success { background-color: #4CAF50; }
		.btn-success:hover { background-color: #388E3C; }
		.btn-secondary { background-color: #64748b; }
		.btn-secondary:hover { background-color: #475569; }
		.msg-err { 
			color: #b71c1c; 
			font-weight: bold; 
			padding: 10px; 
			border-left: 4px solid #b71c1c; 
			background-color: #ffebee; 
			line-height: 1.4; 
			margin-bottom: 20px;
		}
		.msg-info { 
			color: #004488; 
			font-weight: bold; 
			padding: 10px; 
			border-left: 4px solid #004488; 
			background-color: #e6f7ff; 
			line-height: 1.4; 
			margin-bottom: 20px;
		}
	</style>
</head>
<body>
	{$user_context}
	{$breadcrumbs_html}
	<div class="{$panel_cls}">
HTML;

		if ($this->access_denied) {                                          // Pokud uživatel nemá dostatečná oprávnění
			$denied_msg = htmlspecialchars($this->phrase('msg_access_denied', [], 'Přístup odepřen. K zobrazení této stránky nemáte dostatečná oprávnění.')); // Chybová zpráva
			echo "<div class='msg-err'>{$denied_msg}</div>\n";               // Výpis chyby odepřeného přístupu
		} else {
			$this->render_body();                                            // Vykreslení těla potomka
		}

		echo <<<HTML
	</div>
	<script>
		let isFormDirty = false;
		document.addEventListener('input', function(e) {
			if (e.target.closest('form')) {
				isFormDirty = true;
			}
		});
		document.addEventListener('submit', function() {
			isFormDirty = false;
		});
		window.addEventListener('beforeunload', function(e) {
			if (isFormDirty) {
				e.preventDefault();
				e.returnValue = '{$unsaved_msg}';
			}
		});
	</script>
</body>
</html>
HTML;
	}

	abstract protected function render_body(): void;
}