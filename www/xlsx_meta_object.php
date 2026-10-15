<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 15:05
 * Soubor: xlsx_meta_object.php
 * Třída: xlsx_meta_object
 * Účel: Konfigurační a validační třída importního balíčku "meta_object"
 *       pro hromadný import systémových stránek (page), struktury menu (menu)
 *       a globálních i třídních frází (phrase) z Excelu.
 *
 * Vazby na okolí:
 * - Dědí z abstraktní třídy xlsx_abstract (definované v xlsx_abstract.php).
 * - Automaticky načítána přes spl_autoload_register v xlsx_abstract.php
 *   a instancována v excel_reader::prepare_package() při package_code = 'meta_object'.
 * - Volá $this->setDataType() pro registraci povinných záložek (page, menu, phrase),
 *   kontrolu přítomnosti všech sloupců (včetně překladových sloupců *_l)
 *   a nastavení datových typů před vytvořením staging tabulek XLSX_page$,
 *   XLSX_menu$ a XLSX_phrase$ v excel_reader::save_to_tables().
 * - Připravuje garantovanou datovou strukturu pro uloženou proceduru
 *   p_xlsx_meta_object (v souboru p_xlsx_meta_object.sql), která ukládá data
 *   do tabulek meta_object, meta_menu a meta_phrase.
 *
 * Změny:
 * 2026-10-14 - Vytvoření samostatné třídy xlsx_meta_object pro záložky
 *              page, menu a phrase se striktní validací sloupců základního
 *              jazyka i překladových sloupců s příponou _l.
 * 2026-10-15 - Rozšíření validace záložky phrase o sloupce source_code,
 *              svg_icon a css_class pro napojení na novou tabulku meta_phrase.
 * =============================================================================
 */

declare(strict_types=1);

class xlsx_meta_object extends xlsx_abstract {

	/**
	 * Definuje povinné záložky, sloupce a jejich datové typy pro balíček meta_object.
	 * Kontroluje i přítomnost sloupců s příponou _l, aby uložená procedura
	 * p_xlsx_meta_object měla vždy garantovanou strukturu staging tabulek.
	 */
	public function prepare(): void {
		$this->package_name = "Import systémových objektů, stránek, menu a globálních frází"; // Název balíčku pro logování a distribuci

		// 1. Validace záložky "page" (stránky a třídy aplikace -> meta_object, object_type = 'P')
		$this->setDataType(                                 // Registrace textových sloupců záložky page
			'builtin_code,system_role,module,editor_note,caption,description,helptext,caption_l,description_l,helptext_l',
			'varchar',
			'page'
		);
		$this->setDataType('inactive', 'bit', 'page');      // Převod příznaku deaktivace stránky na bit (0/1)

		// 2. Validace záložky "menu" (struktura navigace -> tabulka meta_menu)
		$this->setDataType(                                 // Registrace textových sloupců záložky menu
			'builtin_code,parent_code,sort_code,target_page,url_parameters,target_url,target_window,system_role,svg_icon,css_class,editor_note,caption,description,helptext,caption_l,description_l,helptext_l',
			'varchar',
			'menu'
		);
		$this->setDataType('permanent', 'bit', 'menu');     // Převod příznaku trvalého zobrazení složky na bit (0/1)

		// 3. Validace záložky "phrase" (globální textové fráze -> meta_object, object_type = 'G' / nově tabulka meta_phrase)
		$this->setDataType(                                 // Registrace textových sloupců záložky phrase pro meta_phrase
			'source_code,builtin_code,module,svg_icon,css_class,editor_note,caption,helptext,caption_l,helptext_l',
			'varchar',
			'phrase'
		);

		if ($this->rqm->get_severity() > 2) {               // Kontrola, zda při validaci sloupců nevznikla kritická chyba
			$this->rqm->add_message("Errors detected");     // Zápis souhrnné chybové zprávy do logu
			return;
		}
	}
}