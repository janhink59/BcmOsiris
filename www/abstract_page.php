<?php
/**
 * =============================================================================
 * Verze: 2026-10-19 14:45
 * Soubor: abstract_page.php
 * Třída: abstract_page
 * Účel: Základní abstraktní třída pro objektově orientované stránky.
 *       Zajišťuje jednotný layout, centrální CSS styly, zobrazení kontextu 
 *       uživatele (horní pruh) a dynamickou drobečkovou navigaci.
 * 
 * ARCHITEKTONICKÉ VAZBY (Pro AI a budoucí kontext):
 * - Je volána z centrálního routeru `index.php`, který instancuje jejího potomka
 *   a spouští metodu `render()`.
 * - Slouží jako přímý předek pro další šablony (např. `abstract_page_master_detail`) 
 *   nebo konkrétní jednoúčelové stránky.
 * - Závislosti:
 *   1. Instancuje třídu `phrase_manager` (a ukládá ji i do `$GLOBALS['phrase_manager']`)
 *      pro dávkové načtení všech frází v hierarchii dědičnosti stránky.
 *   2. Ověřuje oprávnění k zobrazení stránky proti sloupci `system_role` v `meta_object`.
 *   3. Volá metodu `process_save()` při POST požadavku před vykreslením HTML (PRG vzor).
 *   4. Instancuje třídu `user_context` pro vykreslení horního informačního panelu 
 *      (kdo je přihlášen, jakou má roli, přepínač jazyků).
 *   5. Očekává existenci globálního objektu `$menu_manager` (inicializovaného 
 *      typicky v index.php po initsession), ze kterého volá `render_breadcrumbs()` 
 *      pro vykreslení cesty v menu a dropdown roletek.
 * 
 * Změny:
 * 2026-10-19 14:45 - Přidána vlastnost $full_width umožňující potomkům (např. náhledu
 *                    tabulek v page_excel_reader) roztáhnout .page-panel na plnou šířku.
 *                  - Doplněno centrální stylování tabulek .md-table.
 *                  - V check_system_role_access() nahrazeno sqlrun/fetch za sqlfirstrow()
 *                    a operátory &&/|| nahrazeny za AND/OR (Anti-LaTeX pravidlo).
 * 2026-10-15 22:45 - Oprava podmínky volání process_save() v render() výhradně
 *                    na HTTP metodu POST (zamezení spouštění při GET požadavcích).
 * 2026-10-15 22:20 - Integrace phrase_manager, metody process_save() a fail-safe
 *                    kontroly přístupu podle meta_object.system_role.
 * 2026-10-13 - Integrace globálního $menu_manager pro vykreslení drobečkové navigace.
 * 2026-10-09 - Přidána podpora pro centralizované řízení přístupu ($access_denied).
 * 2026-09-27 - Přidána plošná JS ochrana proti opuštění stránky s neuloženým formulářem.
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page {

	/**
	 * Titulek stránky (lze přepsat v konstruktoru potomka).
	 */
	protected string $page_title = 'BCM Osiris';                             // Výchozí titulek v prohlížeči

	/**
	 * Příznak zamezení přístupu. Vyhodnocuje předek dle meta_object i potomek v konstruktoru.
	 */
	protected bool $access_denied = false;                                   // Příznak odepření přístupu ke stránce

	/**
	 * Příznak roztažení hlavního panelu (.page-panel) na plnou šířku okna prohlížeče.
	 */
	protected bool $full_width = false;                                      // Příznak plné šířky obsahu stránky

	/**
	 * Instance správce frází načtená pro hierarchii aktuální stránky.
	 */
	protected ?phrase_manager $phrases = null;                               // Lokální reference na správce frází

	/**
	 * Konstruktor základní stránky. Inicializuje správce frází a ověří system_role.
	 */
	public function __construct() {
		$this->init_phrases();                                               // Inicializace frází pro hierarchii třídy
		$this->check_system_role_access();                                   // Fail-safe kontrola oprávnění z meta_object
	}

	/**
	 * Zajistí vytvoření instance phrase_manager pro aktuální stránku.
	 */
	protected function init_phrases(): void {
		if ($this->phrases === null) {
			$this->phrases = new phrase_manager($this);                      // Dávkové načtení frází přes reflexi
			$GLOBALS['phrase_manager'] = $this->phrases;                     // Zpřístupnění pro tlačítka a komponenty
		}
	}

	/**
	 * Ověří v tabulce meta_object (object_type = 'P'), zda má přihlášený uživatel
	 * dostatečnou active_role pro přístup k této stránce (Fail-safe autorizace).
	 */
	protected function check_system_role_access(): void {
		global $dbsession;                                                   // Globální kontext relace
		if (empty($dbsession) OR !isset($dbsession['active_role'])) {
			return;                                                          // Pokud relace není inicializována, neblokujeme
		}

		$active_role = (string)$dbsession['active_role'];                    // Aktuální role uživatele (U, A, S, D)
		if ($active_role === 'S' OR $active_role === 'D') {
			return;                                                          // Sysadmin a Developer mají přístup vždy
		}

		$class_name = get_class($this);                                      // Název třídy aktuální stránky
		$safe_code = charliteral($class_name, 80);                           // SQL literál názvu třídy

		$sql = "
		SELECT TOP 1 system_role
		FROM meta_object
		WHERE object_type = 'P'
		  AND builtin_code = {$safe_code}
		  AND record_type = 'A'
		  AND removed = 0
		ORDER BY CASE WHEN object_owner = 0x00 THEN 1 ELSE 0 END
		";                                                                   // Dotaz na požadovanou roli stránky

		$row = sqlfirstrow($sql);                                            // Načtení prvního řádku bez otevřeného kurzoru
		if (!empty($row) AND isset($row['system_role'])) {
			$req_role = (string)$row['system_role'];                         // Minimální vyžadovaná role (U, A, S, D)
			if ($active_role === 'A' AND !in_array($req_role, ['U', 'A'], true)) {
				$this->access_denied = true;                                 // Orgadmin nesmí na stránky S a D
			} elseif ($active_role === 'U' AND $req_role !== 'U') {
				$this->access_denied = true;                                 // Běžný uživatel smí pouze na stránky U
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
	public function phrase(string $builtin_code, array $vars = [], string $default_caption = ''): string {
		$this->init_phrases();                                               // Pojistka inicializace správce frází
		return $this->phrases->get($builtin_code, $vars, $default_caption);  // Vrácení přeložené a interpolované fráze
	}

	/**
	 * Metoda pro zpracování POST dat (PRG vzor).
	 * Volá se automaticky na začátku render() při HTTP POST před odesláním jakéhokoliv HTML.
	 * Potomci tuto metodu překrývají místo zachytávání POST v konstruktoru.
	 */
	protected function process_save(): void {
		// Výchozí prázdná implementace pro překrytí v potomcích
	}

	/**
	 * Hlavní renderovací metoda volaná z index.php.
	 */
	public function render(): void {
		$this->init_phrases();                                               // Pojistka inicializace frází (pokud potomek nevolal parent::__construct)
		$this->check_system_role_access();                                   // Pojistka kontroly oprávnění

		// Zpracování formulářových akcí (POST / PRG přesměrování) před výpisem HTML
		if (!$this->access_denied AND ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
			$this->process_save();                                           // Spuštění ukládací logiky potomka pouze při POST
		}

		// Instancováním třídy vyvoláme autoloader pro horní kontextový pruh
		$user_context = new user_context();                                  // Horní lišta s kontextem uživatele
		
		// Načtení globálního správce menu pro drobečkovou navigaci
		global $menu_manager, $dbsession;                                    // Přístup k navigaci a relaci
		$breadcrumbs_html = '';                                              // HTML kód drobečkové navigace
		if (isset($menu_manager) AND is_object($menu_manager)) {
			$breadcrumbs_html = $menu_manager->render_breadcrumbs();         // Vykreslení drobečkové navigace
		}

		$lang_code = htmlspecialchars((string)($dbsession['language'] ?? 'cs')); // Kód jazyka do atributu html
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
		/* Centrální styly sdílené napříč všemi potomky abstract_page */
		body { 
			font-family: Arial, sans-serif; 
			background-color: #f4f4f4; 
			margin: 0; 
			padding: 0; /* Bez odsazení pro dokonalé přilehnutí horního pruhu */
			color: #333; 
		}
		.page-panel { 
			background-color: #fff; 
			padding: 20px; 
			border-radius: 5px; 
			box-shadow: 0 0 10px rgba(0,0,0,0.1); 
			margin: 15px auto; /* Dynamické odsazení od pruhu a okrajů */
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
		.btn-icon svg, .btn svg { width: 16px; height: 16px; fill: currentColor; flex-shrink: 0; }
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
	<!-- Globální kontextový panel (vykreslí se jako kompaktní blockový horní pruh) -->
	{$user_context}
	
	<!-- Drobečková navigace s dropdown roletkami potomků -->
	{$breadcrumbs_html}
	
	<!-- Hlavní obálka pro obsah specifické stránky -->
	<div class="{$panel_cls}">
HTML;
		
		if ($this->access_denied) {
			$denied_msg = htmlspecialchars($this->phrase('msg_access_denied', [], 'Přístup odepřen. K zobrazení této stránky nemáte dostatečná oprávnění.')); // Chybová zpráva
			echo "<div class='msg-err'>{$denied_msg}</div>\n";
		} else {
			// Vykreslení specifického obsahu konkrétní stránky
			$this->render_body();                                            // Vykreslení těla potomka
		}

		echo <<<HTML
	</div>
	
	<script>
		// Plošná ochrana proti opuštění stránky s neuloženými daty (Dirty state)
		let isFormDirty = false;
		
		// Detekce změny v jakémkoliv inputu, selectu nebo textareji uvnitř formuláře
		document.addEventListener('input', function(e) {
			if (e.target.closest('form')) {
				isFormDirty = true;
			}
		});
		
		// Při korektním odeslání formuláře (tlačítkem Uložit) dirty state zrušíme
		document.addEventListener('submit', function() {
			isFormDirty = false;
		});
		
		// Zachycení pokusu o opuštění stránky (kliknutí na odkaz, zavření okna, zpět v prohlížeči, přechod v levém panelu)
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

	/**
	 * Abstraktní metoda, kterou musí implementovat každá konkrétní stránka.
	 */
	abstract protected function render_body(): void;
}