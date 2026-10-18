<?php
/**
 * =============================================================================
 * Verze: 2026-10-18 17:15
 * Soubor: xlsx_meta_object.php
 * Třída: xlsx_meta_object
 * Účel: Konfigurační a validační třída importního balíčku "meta_object"
 *       pro hromadný import systémových stránek (page), struktury menu (menu),
 *       globálních i třídních frází (phrase), logických tříd (class)
 *       a definic sloupců (column) z Excelu.
 *
 * Vazby na okolí:
 * - Dědí z abstraktní třídy xlsx_abstract (definované v xlsx_abstract.php).
 * - Automaticky načítána přes spl_autoload_register v xlsx_abstract.php
 *   a instancována v excel_reader::prepare_package() při package_code = 'meta_object'.
 * - Volá $this->setDataType() pro registraci záložek (page, menu, phrase, class, column),
 *   kontrolu přítomnosti všech sloupců (včetně překladových sloupců *_l)
 *   a nastavení datových typů před vytvořením staging tabulek XLSX_page$,
 *   XLSX_menu$, XLSX_phrase$, XLSX_class$ a XLSX_column$ v excel_reader::save_to_tables().
 * - Sloupce záložek class a column využívající dědičnost (<v stříškách>) jsou
 *   ponechány jako varchar, aby procedura p_xlsx_meta_object mohla bezpečně
 *   odstranit stříšky < > a porovnat hodnoty s předkem.
 *
 * Změny:
 * 2026-10-14 - Vytvoření samostatné třídy xlsx_meta_object pro záložky
 *              page, menu a phrase se striktní validací sloupců základního
 *              jazyka i překladových sloupců s příponou _l.
 * 2026-10-15 - Rozšíření validace záložky phrase o sloupce source_code,
 *              svg_icon a css_class pro napojení na novou tabulku meta_phrase.
 * 2026-10-18 17:15 - Rozšíření balíčku o záložky class (meta_class) a column
 *                    (meta_column) s mnemotechnickými identifikátory vazeb.
 * =============================================================================
 */

declare(strict_types=1);

class xlsx_meta_object extends xlsx_abstract {

	/**
	 * Definuje záložky, sloupce a jejich datové typy pro balíček meta_object.
	 * Kontroluje i přítomnost sloupců s příponou _l, aby uložená procedura
	 * p_xlsx_meta_object měla vždy garantovanou strukturu staging tabulek.
	 */
	public function prepare(): void {
		$this->package_name = "Import systémových objektů, stránek, menu, frází, logických tříd a sloupců"; // Název balíčku pro logování a distribuci

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

		// 3. Validace záložky "phrase" (textové fráze -> tabulka meta_phrase)
		$this->setDataType(                                 // Registrace textových sloupců záložky phrase pro meta_phrase
			'source_code,builtin_code,module,svg_icon,css_class,editor_note,caption,helptext,caption_l,helptext_l',
			'varchar',
			'phrase'
		);

		// 4. Validace záložky "class" (logické třídy -> tabulka meta_class), pokud je v sešitu přítomna
		if (array_key_exists('class', $this->reader->data)) { // Kontrola přítomnosti záložky class v XLSX
			$this->setDataType(                             // Registrace všech sloupců záložky class jako varchar (kvůli <stříškám>)
				'class_name,storage_type,storage_code,ancestor_code,sort_code,iconname,is_final,is_protected,inactive,editor_note,caption,caption_plural,description,helptext,caption_l,caption_plural_l,description_l,helptext_l',
				'varchar',
				'class'
			);
		}

		// 5. Validace záložky "column" (sloupce metadat -> tabulka meta_column), pokud je v sešitu přítomna
		if (array_key_exists('column', $this->reader->data)) { // Kontrola přítomnosti záložky column v XLSX
			$this->setDataType(                             // Registrace všech sloupců záložky column jako varchar (kvůli <stříškám>)
				'class_name,column_name,parent_order,sort_code,list_order,input_type,input_width,input_rows,max_length,css_class,translate,history,is_html,is_mandatory,is_url,is_computed,show_empty,hidden,customizable,ancestor_column,referenced_codetable,referenced_class_code,is_final,is_protected,inactive,editor_note,caption,caption_plural,description,label,header,helptext,placeholder,caption_l,caption_plural_l,description_l,label_l,header_l,helptext_l,placeholder_l',
				'varchar',
				'column'
			);
		}

		if ($this->rqm->get_severity() > 2) {               // Kontrola, zda při validaci sloupců nevznikla kritická chyba
			$this->rqm->add_message("Errors detected");     // Zápis souhrnné chybové zprávy do logu
			return;
		}
	}
}