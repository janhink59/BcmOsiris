<?php
/**
 * =============================================================================
 * Třída: abstract_page
 * Účel: Základní abstraktní třída pro objektově orientované stránky.
 *       Zajišťuje jednotný layout, centrální CSS styly a zobrazení kontextu 
 *       uživatele (horní pruh).
 * 
 * Vazby na okolí:
 * - Je volána z centrálního routeru `index.php`, který instancuje jejího potomka
 *   a spouští metodu `render()`.
 * - Slouží jako předek pro další šablony (např. `abstract_page_master_detail`) 
 *   nebo konkrétní stránky.
 * - Instancuje třídu `user_context` pro vykreslení horního informačního panelu.
 * 
 * Změny:
 * 2026-10-09 - Přidána podpora pro centralizované řízení přístupu ($access_denied).
 * 2026-09-27 - Přidána plošná JS ochrana proti opuštění stránky s neuloženým formulářem.
 * =============================================================================
 */

declare(strict_types=1);

abstract class abstract_page {

	/**
	 * Titulek stránky (lze přepsat v konstruktoru potomka).
	 */
	protected string $page_title = 'BCM Osiris';

	/**
	 * Příznak zamezení přístupu. Vyhodnocuje potomek v konstruktoru.
	 */
	protected bool $access_denied = false;

	/**
	 * Hlavní renderovací metoda volaná z index.php.
	 */
	public function render(): void {
		// Instancováním třídy vyvoláme autoloader
		$user_context = new user_context();

		echo <<<HTML
<!DOCTYPE html>
<html lang="cs">
<head>
	<meta charset="utf-8">
	<title>{$this->page_title}</title>
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
		h1.page-heading { 
			color: #004488; 
			margin-top: 0; 
			border-bottom: 2px solid #eee; 
			padding-bottom: 10px; 
		}
		.btn { 
			display: inline-block; 
			padding: 10px 15px; 
			background-color: #004488; 
			color: #fff; 
			text-decoration: none; 
			border: none; 
			border-radius: 3px; 
			font-weight: bold; 
			cursor: pointer; 
		}
		.btn:hover { background-color: #003366; }
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
	
	<!-- Hlavní obálka pro obsah specifické stránky -->
	<div class="page-panel">
HTML;
		
		if ($this->access_denied) {
			echo "<div class='msg-err'>Přístup odepřen. K zobrazení této stránky nemáte dostatečná oprávnění.</div>\n";
		} else {
			// Vykreslení specifického obsahu konkrétní stránky
			$this->render_body();
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
				e.returnValue = 'Máte neuložené změny. Opravdu chcete stránku opustit?';
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