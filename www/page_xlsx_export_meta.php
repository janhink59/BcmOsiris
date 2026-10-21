<?php
/**
 * =============================================================================
 * Verze: 2026-10-21 15:40
 * Soubor: page_xlsx_export_meta.php
 * Třída: page_xlsx_export_meta
 * Účel: Samostatná stránka pro zpětný export systémových metadat (meta_object,
 *       meta_menu, meta_phrase, meta_class, meta_column) do souboru XLSX
 *       s volbou základního jazyka (language) a druhého jazyka (second_language).
 *       Vyčleněno z page_excel_reader.php pro zjednodušení a zpřehlednění kódu.
 *
 * Vazby na okolí:
 * - Instancována dynamicky z index.php při požadavku ?page=page_xlsx_export_meta.
 * - Dědí z abstract_page (využívá $this->page_title, $this->access_denied,
 *   $this->phrase(), parent::render() a implementuje render_body()).
 * - Využívá komponentu abstract_button pro vykreslení tlačítek.
 * - Čte číselník [language] a systémové záznamy (object_owner = 0x00) z tabulek
 *   meta_object, meta_menu, meta_phrase, meta_class a meta_column přes sqlarray_simple().
 * - Generuje XLSX soubor pomocí knihovny PhpOffice\PhpSpreadsheet (plně kompatibilní
 *   s importní třídou xlsx_meta_object a procedurou p_xlsx_meta_object).
 * - Sloupce svg_icon se do Excelu vůbec neexportují (spravují se výhradně SQL skripty).
 * - Zděděné hodnoty na záložkách class a column i dosud nepřeložené položky
 *   ve sloupcích s příponou _l (pokud je definován second_language) uzavírá <do stříšek>.
 *
 * Změny:
 * 2026-10-21 15:40 - Ze záložek menu, phrase a class vyřazen sloupec svg_icon
 *                    (vektorové ikony se neexportují do Excelu ani z něj neimportují).
 * 2026-10-21 15:00 - Vytvoření samostatné stránky vyčleněním z page_excel_reader.php.
 *                  - Výrazné zkrácení generování dotazů a řádků záložek class a column
 *                    pomocí definice polí děděných a překládaných sloupců.
 * =============================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use PhpOffice\PhpSpreadsheet\Style\Fill;

class page_xlsx_export_meta extends abstract_page {

	public function __construct() {
		parent::__construct();                          // Inicializace správce frází a kontroly přístupu v předkovi
		$this->page_title = $this->phrase('page_title', [], 'Export systémových metadat do Excelu - BCM Osiris'); // Titulek stránky
	}

	/**
	 * Zpracuje požadavek na stažení XLSX souboru před odesláním HTML hlaviček.
	 */
	public function render(): void {
		$this->init_phrases();                          // Pojistka inicializace správce frází
		$this->check_system_role_access();              // Pojistka kontroly přístupu podle meta_object

		if ($this->access_denied) {                     // Kontrola zamítnutí přístupu před zpracováním
			parent::render();                           // Vykreslení chybové obrazovky z předka
			return;                                     // Ukončení při odepřeném přístupu
		}

		if (isset($_POST['btn_export_excel']) OR getinput('action') === 'export_xlsx') { // Detekce akce exportu
			$this->process_xlsx_export();               // Vygenerování a odeslání XLSX souboru do prohlížeče
			return;                                     // Ukončení po odeslání souboru
		}

		parent::render();                               // Vykreslení formuláře pro nastavení exportu
	}

	/**
	 * Vykreslí formulář s volbou primárního a druhého jazyka pro export metadat.
	 */
	protected function render_body(): void {
		$lang_opts_primary = '';                        // HTML opce pro základní jazyk exportu
		$lbl_no_sec = htmlspecialchars($this->phrase('opt_no_second_lang', [], '--- Bez druhého jazyka (režim jádra) ---')); // Volba bez 2. jazyka
		$lang_opts_second = "<option value=\"\">{$lbl_no_sec}</option>"; // Výchozí prázdná volba druhého jazyka

		$lang_rows = sqlarray_simple("SELECT [language], caption FROM [language] ORDER BY sort_code"); // Načtení jazyků do pole
		if (is_array($lang_rows)) {                     // Kontrola platného pole jazyků
			foreach ($lang_rows as $l_row) {            // Průchod jazyky v paměti
				$l_code = (string)$l_row['language'];   // Dvoupísmenný kód jazyka
				$l_cap = (string)$l_row['caption'];     // Název jazyka
				$safe_code = htmlspecialchars($l_code); // Ošetřený kód jazyka
				$safe_label = htmlspecialchars("{$l_code} - {$l_cap}"); // Ošetřený popisek v roletce
				$sel_prim = ($l_code === 'cs') ? 'selected' : '';       // Výchozí primární jazyk je cs
				$sel_sec = ($l_code === 'en') ? 'selected' : '';        // Výchozí druhý jazyk je en
				$lang_opts_primary .= "<option value=\"{$safe_code}\" {$sel_prim}>{$safe_label}</option>"; // Volba 1. jazyka
				$lang_opts_second .= "<option value=\"{$safe_code}\" {$sel_sec}>{$safe_label}</option>";   // Volba 2. jazyka
			}
		}

		$exp_heading = htmlspecialchars($this->phrase('export_heading', [], 'Export systémových metadat do Excelu (meta_object.xlsx)')); // Nadpis
		$exp_intro = htmlspecialchars($this->phrase('export_intro', [], 'Vygeneruje aktuální soubor meta_object.xlsx přímo z databáze (záložky page, menu, phrase, class, column; zděděné hodnoty jsou uzavřeny <do stříšek>).')); // Popis
		$lbl_prim_lang = htmlspecialchars($this->phrase('lbl_primary_language', [], 'Základní jazyk (language):')); // Popisek 1. jazyka
		$lbl_sec_lang = htmlspecialchars($this->phrase('lbl_second_language', [], 'Druhý jazyk (*_l):'));           // Popisek 2. jazyka
		$lbl_origin = htmlspecialchars($this->phrase('lbl_import_origin', [], 'Označení původu (import_origin):')); // Popisek původu

		$btn_export = new abstract_button('btn_export_excel', 'Stáhnout meta_object.xlsx', 'page_xlsx_export_meta', '', 'btn-success'); // Tlačítko exportu
		$btn_export->set_type('submit')->set_name_value('btn_export_excel', '1'); // Submit atributy
		$export_html = $btn_export->render();           // Vykreslení tlačítka exportu

		$btn_import = new abstract_button('btn_goto_import_excel', '← Přejít na import z Excelu', 'page_xlsx_export_meta', '', 'btn-secondary'); // Odkaz na import
		$btn_import->set_href('index.php?page=page_excel_reader')->set_style('margin-left: 10px;'); // Cílová adresa importu
		$import_link_html = $btn_import->render();      // Vykreslení odkazu na import

		echo <<<HTML
		<style>
			.xlsx-form-table { border-collapse: collapse; margin-bottom: 20px; }
			.xlsx-form-table td { border: 1px solid #cbd5e1; padding: 8px 12px; font-size: 13px; }
		</style>
		<h1 class="page-heading">{$exp_heading}</h1>
		<p style="margin-bottom: 20px;">{$exp_intro}</p>

		<form id="f_export" name="f_export" action="index.php?page=page_xlsx_export_meta" method="post">
			<input type="hidden" name="action" value="export_xlsx">
			<table class="xlsx-form-table">
				<tr>
					<td style="font-weight: bold; width: 220px; background-color: #f8fafc;">{$lbl_prim_lang}</td>
					<td>
						<select name="export_language" style="width: 320px; padding: 4px;">
							{$lang_opts_primary}
						</select>
					</td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_sec_lang}</td>
					<td>
						<select name="export_second_language" style="width: 320px; padding: 4px;">
							{$lang_opts_second}
						</select>
					</td>
				</tr>
				<tr>
					<td style="font-weight: bold; background-color: #f8fafc;">{$lbl_origin}</td>
					<td>
						<input type="text" name="export_origin" value="BCM Osiris Core Team" style="width: 320px; padding: 4px; box-sizing: border-box;">
					</td>
				</tr>
			</table>
			<div>
				{$export_html}
				{$import_link_html}
			</div>
		</form>
HTML;
	}

	/**
	 * Pomocná metoda pro formátování potenciálně zděděné hodnoty v Excelu (<do stříšek>).
	 */
	private function format_inherited_val(mixed $own_val, mixed $anc_val, bool $treat_empty_as_null = false): string { // Formátování děděné hodnoty
		$is_null = ($own_val === null OR ($treat_empty_as_null AND (string)$own_val === '')); // Zda se uplatní dědičnost
		if (!$is_null) {                                // Pokud má záznam vlastní explicitní hodnotu
			return (string)$own_val;                    // Vrátíme vlastní hodnotu bez stříšek
		}
		if ($anc_val !== null AND (string)$anc_val !== '') { // Pokud předek obsahuje neprázdnou hodnotu
			return '<' . (string)$anc_val . '>';        // Zděděnou hodnotu uzavřeme <do stříšek>
		}
		return '';                                      // Předek ani potomek hodnotu nemají
	}

	/**
	 * Pomocná metoda pro formátování překladových sloupců s příponou _l.
	 */
	private function format_sec_lang_val(string $sec_lang, mixed $own_val_l, mixed $inherited_val): string { // Formátování sloupce *_l
		if ($sec_lang === '') {                         // Pokud druhý jazyk v CONTENT_INFO není definován
			return '';                                  // Položky *_l zůstávají prázdné pouze bez druhého jazyka
		}
		return $this->format_inherited_val($own_val_l, $inherited_val, true); // Vlastní překlad nebo <zděděná hodnota>
	}

	/**
	 * Pomocná metoda pro obarvení a ztučnění hlavičky listu.
	 */
	private function style_sheet_header(object $sheet, string $tech_range, string $note_cell, string $prim_range, string $sec_range, string $full_range): void { // Stylování hlavičky
		$sheet->getStyle($tech_range)->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Šedá pro technické
		$sheet->getStyle($note_cell)->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');  // Fialová pro AI kontext
		$sheet->getStyle($prim_range)->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Zelená pro 1. jazyk
		$sheet->getStyle($sec_range)->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD');  // Oranžová pro 2. jazyk
		$sheet->getStyle($full_range)->getFont()->setBold(true); // Tučné písmo celého záhlaví
		$sheet->freezePane('A2');                       // Ukotvení prvního řádku záhlaví
	}

	/**
	 * Vygeneruje a odešle XLSX soubor s aktuálními systémovými metadaty (bez sloupců svg_icon).
	 */
	protected function process_xlsx_export(): void {
		$lang = trim((string)getinput('export_language')) ?: 'cs'; // Zvolený primární jazyk exportu
		$sec_lang = trim((string)getinput('export_second_language')); // Zvolený druhý jazyk exportu
		if ($sec_lang === $lang) {                      // Ochrana proti shodě primárního a druhého jazyka
			$sec_lang = '';                             // Vypnutí druhého jazyka při shodě
		}
		$origin = trim((string)getinput('export_origin')) ?: 'BCM Osiris Export'; // Označení původu dat

		$safe_lang = charliteral($lang, 2);             // Bezpečný SQL literál primárního jazyka
		$safe_sec_lang = charliteral($sec_lang, 2);     // Bezpečný SQL literál druhého jazyka

		$spreadsheet = new Spreadsheet();               // Vytvoření nové instance sešitu PhpSpreadsheet

		// =====================================================================
		// 1. Záložka CONTENT_INFO
		// =====================================================================
		$sheetInfo = $spreadsheet->getActiveSheet();    // Získání prvního aktivního listu
		$sheetInfo->setTitle('CONTENT_INFO');           // Pojmenování řídicí záložky
		$sheetInfo->fromArray(['package_code', 'language', 'second_language', 'version_date', 'import_origin', 'description'], null, 'A1');
		$sheetInfo->fromArray(['meta_object', $lang, $sec_lang, date('Y-m-d'), $origin, 'Export systémových stránek, menu, frází, logických tříd a sloupců z BCM Osiris'], null, 'A2');
		$sheetInfo->getStyle('A1:F1')->getFont()->setBold(true); // Tučné písmo hlavičky CONTENT_INFO
		$sheetInfo->getStyle('A1:F1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Šedé podbarvení
		foreach (range('A', 'F') as $colId) {           // Automatická šířka sloupců CONTENT_INFO
			$sheetInfo->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 2. Záložka page (meta_object, object_type = 'P')
		// =====================================================================
		$sheetPage = $spreadsheet->createSheet();       // Založení listu pro stránky a UI třídy
		$sheetPage->setTitle('page');                   // Název záložky page
		$sheetPage->fromArray(['builtin_code', 'system_role', 'module', 'inactive', 'removed', 'editor_note', 'caption', 'description', 'helptext', 'caption_l', 'description_l', 'helptext_l'], null, 'A1');
		$this->style_sheet_header($sheetPage, 'A1:E1', 'F1', 'G1:I1', 'J1:L1', 'A1:L1'); // Stylování záhlaví page

		$pages_rows = sqlarray_simple("
			SELECT a.builtin_code, a.system_role, a.module, a.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE a.removed END AS removed,
				ISNULL(a.editor_note, '') AS editor_note,
				COALESCE(NULLIF(l1.caption, ''), a.caption, '') AS caption,
				COALESCE(NULLIF(l1.description, ''), a.description, '') AS description,
				COALESCE(NULLIF(l1.helptext, ''), a.helptext, '') AS helptext,
				l2.caption AS own_caption_l, l2.description AS own_description_l, l2.helptext AS own_helptext_l
			FROM meta_object a
			LEFT JOIN meta_object l1 ON l1.original = a.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_object l2 ON l2.original = a.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			WHERE a.object_owner = 0x00 AND a.object_type = 'P' AND a.builtin_code <> '' AND a.record_type = 'A'
			ORDER BY CASE WHEN a.builtin_code = 'global_phrase' THEN 0 WHEN a.builtin_code LIKE 'page_%' THEN 2 ELSE 1 END, a.builtin_code
		");                                             // Načtení registrovaných stránek a UI tříd

		$row_idx = 2;                                   // Počáteční řádek dat na záložce page
		if (is_array($pages_rows)) {                    // Kontrola platného pole stránek
			foreach ($pages_rows as $r) {               // Průchod načtenými stránkami
				$page_vals = [                          // Pole hodnot aktuálního řádku stránky
					(string)$r['builtin_code'], (string)$r['system_role'], (string)$r['module'], (int)$r['inactive'], (int)$r['removed'],
					(string)$r['editor_note'], (string)$r['caption'], (string)$r['description'], (string)$r['helptext'],
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['caption']),
					$this->format_sec_lang_val($sec_lang, $r['own_description_l'], $r['description']),
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['helptext'])
				];                                      // Konec pole hodnot stránky
				$sheetPage->fromArray($page_vals, null, 'A' . $row_idx); // Zápis řádku do listu page
				$row_idx++;                             // Posun na další řádek
			}
		}
		foreach (range('A', 'L') as $colId) {           // Automatická šířka sloupců na záložce page
			$sheetPage->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 3. Záložka menu (tabulka meta_menu – bez sloupce svg_icon)
		// =====================================================================
		$sheetMenu = $spreadsheet->createSheet();       // Založení listu pro navigaci
		$sheetMenu->setTitle('menu');                   // Název záložky menu
		$sheetMenu->fromArray(['builtin_code', 'parent_code', 'sort_code', 'target_page', 'url_parameters', 'target_url', 'target_window', 'system_role', 'permanent', 'removed', 'css_class', 'editor_note', 'caption', 'description', 'helptext', 'caption_l', 'description_l', 'helptext_l'], null, 'A1');
		$this->style_sheet_header($sheetMenu, 'A1:K1', 'L1', 'M1:O1', 'P1:R1', 'A1:R1'); // Stylování záhlaví menu (18 sloupců: A až R)

		$menu_rows = sqlarray_simple("
			SELECT m.builtin_code, ISNULL(pm.builtin_code, '') AS parent_code, m.sort_code, ISNULL(mo.builtin_code, '') AS target_page,
				m.url_parameters, m.target_url, m.target_window, m.system_role, m.permanent,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE m.removed END AS removed,
				m.css_class, ISNULL(m.editor_note, '') AS editor_note,
				COALESCE(NULLIF(l1.caption, ''), m.caption, '') AS caption,
				COALESCE(NULLIF(l1.description, ''), m.description, '') AS description,
				COALESCE(NULLIF(l1.helptext, ''), m.helptext, '') AS helptext,
				l2.caption AS own_caption_l, l2.description AS own_description_l, l2.helptext AS own_helptext_l
			FROM meta_menu m
			LEFT JOIN meta_menu pm ON pm.original = m.parent_uuid AND pm.object_owner = 0x00 AND pm.record_type = 'A'
			LEFT JOIN meta_object mo ON mo.original = m.target_object AND mo.object_owner = 0x00 AND mo.record_type = 'A'
			LEFT JOIN meta_menu l1 ON l1.original = m.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_menu l2 ON l2.original = m.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			WHERE m.object_owner = 0x00 AND m.record_type = 'A'
			ORDER BY CASE WHEN m.parent_uuid IS NULL THEN 0 ELSE 1 END, m.sort_code, m.builtin_code
		");                                             // Načtení položek systémového menu (bez svg_icon)

		$row_idx = 2;                                   // Počáteční řádek dat na záložce menu
		if (is_array($menu_rows)) {                     // Kontrola platného pole menu
			foreach ($menu_rows as $r) {                // Průchod načtenými položkami menu
				$menu_vals = [                          // Pole hodnot řádku menu
					(string)$r['builtin_code'], (string)$r['parent_code'], (string)$r['sort_code'], (string)$r['target_page'],
					(string)$r['url_parameters'], (string)$r['target_url'], (string)$r['target_window'], (string)$r['system_role'],
					(int)$r['permanent'], (int)$r['removed'], (string)$r['css_class'], (string)$r['editor_note'],
					(string)$r['caption'], (string)$r['description'], (string)$r['helptext'],
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['caption']),
					$this->format_sec_lang_val($sec_lang, $r['own_description_l'], $r['description']),
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['helptext'])
				];                                      // Konec pole hodnot menu
				$sheetMenu->fromArray($menu_vals, null, 'A' . $row_idx); // Zápis řádku do listu menu
				$row_idx++;                             // Posun na další řádek
			}
		}
		foreach (range('A', 'R') as $colId) {           // Automatická šířka sloupců na záložce menu
			$sheetMenu->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 4. Záložka phrase (tabulka meta_phrase – bez sloupce svg_icon)
		// =====================================================================
		$sheetPhrase = $spreadsheet->createSheet();     // Založení listu pro textové fráze
		$sheetPhrase->setTitle('phrase');               // Název záložky phrase
		$sheetPhrase->fromArray(['source_code', 'builtin_code', 'module', 'css_class', 'inactive', 'removed', 'editor_note', 'caption', 'helptext', 'caption_l', 'helptext_l'], null, 'A1');
		$this->style_sheet_header($sheetPhrase, 'A1:F1', 'G1', 'H1:I1', 'J1:K1', 'A1:K1'); // Stylování záhlaví phrase (11 sloupců: A až K)

		$phrase_rows = sqlarray_simple("
			SELECT CASE WHEN ISNULL(LTRIM(RTRIM(a.source_code)), '') = '' THEN 'global_phrase' ELSE a.source_code END AS source_code,
				a.builtin_code, a.module, a.css_class, a.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE a.removed END AS removed,
				ISNULL(a.editor_note, '') AS editor_note,
				COALESCE(NULLIF(CAST(l1.caption AS NVARCHAR(MAX)), ''), CAST(a.caption AS NVARCHAR(MAX)), '') AS caption,
				COALESCE(NULLIF(CAST(l1.helptext AS NVARCHAR(MAX)), ''), CAST(a.helptext AS NVARCHAR(MAX)), '') AS helptext,
				CAST(l2.caption AS NVARCHAR(MAX)) AS own_caption_l, CAST(l2.helptext AS NVARCHAR(MAX)) AS own_helptext_l
			FROM meta_phrase a
			LEFT JOIN meta_phrase l1 ON l1.original = a.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_phrase l2 ON l2.original = a.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			WHERE a.object_owner = 0x00 AND a.record_type = 'A'
			ORDER BY CASE WHEN ISNULL(LTRIM(RTRIM(a.source_code)), '') IN ('', 'global_phrase') THEN 0 ELSE 1 END, a.source_code, a.builtin_code
		");                                             // Načtení všech systémových frází (bez svg_icon)

		$row_idx = 2;                                   // Počáteční řádek dat na záložce phrase
		if (is_array($phrase_rows)) {                   // Kontrola platného pole frází
			foreach ($phrase_rows as $r) {              // Průchod načtenými frázemi
				$phrase_vals = [                        // Pole hodnot řádku fráze
					(string)$r['source_code'], (string)$r['builtin_code'], (string)$r['module'],
					(string)$r['css_class'], (int)$r['inactive'], (int)$r['removed'], (string)$r['editor_note'],
					(string)$r['caption'], (string)$r['helptext'],
					$this->format_sec_lang_val($sec_lang, $r['own_caption_l'], $r['caption']),
					$this->format_sec_lang_val($sec_lang, $r['own_helptext_l'], $r['helptext'])
				];                                      // Konec pole hodnot fráze
				$sheetPhrase->fromArray($phrase_vals, null, 'A' . $row_idx); // Zápis řádku do listu phrase
				$row_idx++;                             // Posun na další řádek
			}
		}
		foreach (range('A', 'K') as $colId) {           // Automatická šířka sloupců na záložce phrase
			$sheetPhrase->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 5. Záložka class (tabulka meta_class – bez sloupce svg_icon)
		// =====================================================================
		$sheetClass = $spreadsheet->createSheet();      // Založení listu pro logické třídy
		$sheetClass->setTitle('class');                 // Název záložky class
		$cls_trans_cols = ['caption', 'caption_plural', 'description', 'helptext']; // Překládané sloupce třídy
		$classHeaders = [                               // Definice sloupců záložky class (18 sloupců: A až R)
			'class_name', 'storage_type', 'storage_code', 'ancestor_code',
			'sort_code', 'is_final', 'is_protected', 'inactive', 'removed', 'editor_note',
			'caption', 'caption_plural', 'description', 'helptext',
			'caption_l', 'caption_plural_l', 'description_l', 'helptext_l'
		];                                              // Konec hlaviček záložky class
		$sheetClass->fromArray($classHeaders, null, 'A1'); // Zápis záhlaví záložky class
		$this->style_sheet_header($sheetClass, 'A1:I1', 'J1', 'K1:N1', 'O1:R1', 'A1:R1'); // Stylování záhlaví class

		$cls_sel = [];                                  // Dynamické výrazy pro děděné a překládané sloupce třídy
		foreach ($cls_trans_cols as $tc) {              // Sestavení SELECT výrazů pro překládané sloupce třídy
			$cls_sel[] = "COALESCE(NULLIF(l1.{$tc}, ''), c.{$tc}) AS own_{$tc}"; // Vlastní hodnota 1. jazyka
			$cls_sel[] = "COALESCE(NULLIF(anc_l1.{$tc}, ''), anc.{$tc}) AS anc_{$tc}"; // Hodnota předka 1. jazyka
			$cls_sel[] = "l2.{$tc} AS own_{$tc}_l";     // Vlastní překlad 2. jazyka
			$cls_sel[] = "COALESCE(NULLIF(anc_l2.{$tc}, ''), NULLIF(l1.{$tc}, ''), NULLIF(c.{$tc}, ''), NULLIF(anc_l1.{$tc}, ''), anc.{$tc}) AS inh_{$tc}_l"; // Zděděná pro 2. jazyk
		}
		$cls_sel_sql = implode(",\n\t\t\t\t", $cls_sel); // Spojení výrazů do SELECTu

		$class_rows = sqlarray_simple("
			SELECT c.class_name, ISNULL(mo.object_type, 'T') AS storage_type, ISNULL(mo.builtin_code, c.class_name) AS storage_code,
				ISNULL(anc.class_name, '') AS ancestor_code, c.sort_code,
				c.is_final, c.is_protected, c.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE c.removed END AS removed,
				ISNULL(c.editor_note, '') AS editor_note,
				{$cls_sel_sql}
			FROM meta_class c
			LEFT JOIN meta_object mo ON mo.original = c.storage_object AND mo.object_owner = 0x00 AND mo.record_type = 'A'
			LEFT JOIN meta_class anc ON anc.original = c.ancestor_class AND anc.object_owner = 0x00 AND anc.record_type = 'A' AND anc.removed = 0
			LEFT JOIN meta_class l1 ON l1.original = c.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_class anc_l1 ON anc_l1.original = anc.original AND anc_l1.object_owner = 0x00 AND anc_l1.record_type = 'L' AND anc_l1.[language] = {$safe_lang} AND anc_l1.removed = 0
			LEFT JOIN meta_class l2 ON l2.original = c.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			LEFT JOIN meta_class anc_l2 ON anc_l2.original = anc.original AND anc_l2.object_owner = 0x00 AND anc_l2.record_type = 'L' AND anc_l2.[language] = {$safe_sec_lang} AND anc_l2.removed = 0 AND {$safe_sec_lang} <> ''
			WHERE c.object_owner = 0x00 AND c.record_type = 'A'
			ORDER BY CASE WHEN c.class_name = 'sys_global_columns' THEN 0 ELSE 1 END, c.class_name
		");                                             // Načtení logických tříd včetně předků (bez svg_icon)

		$row_idx = 2;                                   // Počáteční řádek dat na záložce class
		if (is_array($class_rows)) {                    // Kontrola platného pole tříd
			foreach ($class_rows as $r) {               // Průchod načtenými třídami
				$class_vals = [                         // Základní technické sloupce třídy
					(string)$r['class_name'], (string)$r['storage_type'], (string)$r['storage_code'], (string)$r['ancestor_code'],
					(string)$r['sort_code'], (int)$r['is_final'], (int)$r['is_protected'], (int)$r['inactive'], (int)$r['removed'], (string)$r['editor_note']
				];                                      // Konec technických sloupců třídy
				foreach ($cls_trans_cols as $tc) {      // Přidání sloupců primárního jazyka
					$class_vals[] = $this->format_inherited_val($r["own_{$tc}"], $r["anc_{$tc}"], true); // Hodnota 1. jazyka
				}
				foreach ($cls_trans_cols as $tc) {      // Přidání sloupců druhého jazyka (*_l)
					$class_vals[] = $this->format_sec_lang_val($sec_lang, $r["own_{$tc}_l"], $r["inh_{$tc}_l"]); // Hodnota 2. jazyka
				}
				$sheetClass->fromArray($class_vals, null, 'A' . $row_idx); // Zápis řádku do listu class
				$row_idx++;                             // Posun na další řádek
			}
		}
		foreach (range('A', 'R') as $colId) {           // Automatická šířka sloupců na záložce class
			$sheetClass->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		// =====================================================================
		// 6. Záložka column (tabulka meta_column) s dědičností <do stříšek>
		// =====================================================================
		$sheetCol = $spreadsheet->createSheet();        // Založení listu pro sloupce metadat
		$sheetCol->setTitle('column');                  // Název záložky column

		$col_inh_props = [                              // Mapa děděných technických vlastností: [sloupec => treat_empty_as_null]
			'sort_code' => true, 'list_order' => false, 'input_type' => true, 'input_width' => true,
			'input_rows' => false, 'max_length' => false, 'css_class' => false, 'translate' => false,
			'history' => false, 'is_html' => false, 'is_mandatory' => false, 'is_url' => false,
			'is_computed' => false, 'show_empty' => false, 'hidden' => false, 'customizable' => false
		];                                              // Konec mapy technických vlastností
		$col_trans_cols = ['caption', 'caption_plural', 'description', 'label', 'header', 'helptext', 'placeholder']; // Překládané sloupce

		$colHeaders = array_merge(                      // Sestavení 41 hlaviček záložky column (A až AO)
			['class_name', 'column_name', 'parent_order'],
			array_keys($col_inh_props),
			['ancestor_column', 'referenced_codetable', 'referenced_class_code', 'is_final', 'is_protected', 'inactive', 'removed', 'editor_note'],
			$col_trans_cols,
			array_map(fn(string $c): string => "{$c}_l", $col_trans_cols) // Překladové sloupce s příponou _l
		);                                              // Konec hlaviček záložky column
		$sheetCol->fromArray($colHeaders, null, 'A1');  // Zápis záhlaví záložky column
		$this->style_sheet_header($sheetCol, 'A1:Z1', 'AA1', 'AB1:AH1', 'AI1:AO1', 'A1:AO1'); // Stylování záhlaví column

		$col_sel = [];                                  // Pole dynamických SELECT výrazů pro meta_column
		foreach (array_keys($col_inh_props) as $ip) {   // Sestavení SELECT výrazů pro technické vlastnosti
			$col_sel[] = "c.{$ip} AS own_{$ip}, gc.{$ip} AS anc_{$ip}"; // Vlastní a zděděná hodnota z globálního slovníku
		}
		foreach ($col_trans_cols as $tc) {              // Sestavení SELECT výrazů pro překládané vlastnosti sloupce
			$col_sel[] = "COALESCE(NULLIF(l1.{$tc}, ''), c.{$tc}) AS own_{$tc}"; // Vlastní hodnota 1. jazyka
			$col_sel[] = "COALESCE(NULLIF(gc_l1.{$tc}, ''), gc.{$tc}) AS anc_{$tc}"; // Hodnota předka 1. jazyka
			$col_sel[] = "l2.{$tc} AS own_{$tc}_l";     // Vlastní překlad 2. jazyka
			$col_sel[] = "COALESCE(NULLIF(gc_l2.{$tc}, ''), NULLIF(l1.{$tc}, ''), NULLIF(c.{$tc}, ''), NULLIF(gc_l1.{$tc}, ''), gc.{$tc}) AS inh_{$tc}_l"; // Zděděná pro 2. jazyk
		}
		$col_sel_sql = implode(",\n\t\t\t\t", $col_sel); // Spojení výrazů do SELECTu

		$col_rows = sqlarray_simple("
			SELECT mcl.class_name, c.column_name, c.parent_order,
				{$col_sel_sql},
				ISNULL(gc.column_name, '') AS ancestor_column,
				c.referenced_codetable AS own_ref_codetable, gc.referenced_codetable AS anc_ref_codetable,
				rc_own.class_name AS own_ref_class_code, rc_anc.class_name AS anc_ref_class_code,
				c.is_final, c.is_protected, c.inactive,
				CASE WHEN {$safe_sec_lang} <> '' AND l2.uuid IS NOT NULL THEN l2.removed ELSE c.removed END AS removed,
				ISNULL(c.editor_note, '') AS editor_note
			FROM meta_column c
			JOIN meta_class mcl ON mcl.original = c.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A'
			LEFT JOIN meta_column gc ON gc.original = c.ancestor AND gc.object_owner = 0x00 AND gc.record_type = 'A' AND gc.removed = 0
			LEFT JOIN meta_class rc_own ON rc_own.original = c.referenced_class AND rc_own.object_owner = 0x00 AND rc_own.record_type = 'A' AND rc_own.removed = 0
			LEFT JOIN meta_class rc_anc ON rc_anc.original = gc.referenced_class AND rc_anc.object_owner = 0x00 AND rc_anc.record_type = 'A' AND rc_anc.removed = 0
			LEFT JOIN meta_column l1 ON l1.original = c.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = {$safe_lang} AND l1.removed = 0
			LEFT JOIN meta_column gc_l1 ON gc_l1.original = gc.original AND gc_l1.object_owner = 0x00 AND gc_l1.record_type = 'L' AND gc_l1.[language] = {$safe_lang} AND gc_l1.removed = 0
			LEFT JOIN meta_column l2 ON l2.original = c.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = {$safe_sec_lang} AND {$safe_sec_lang} <> ''
			LEFT JOIN meta_column gc_l2 ON gc_l2.original = gc.original AND gc_l2.object_owner = 0x00 AND gc_l2.record_type = 'L' AND gc_l2.[language] = {$safe_sec_lang} AND gc_l2.removed = 0 AND {$safe_sec_lang} <> ''
			WHERE c.object_owner = 0x00 AND c.record_type = 'A'
			ORDER BY CASE WHEN mcl.class_name = 'sys_global_columns' THEN 0 ELSE 1 END, mcl.class_name, c.parent_order, c.column_name
		");                                             // Načtení sloupců metadat včetně hodnot zděděných z globálního slovníku

		$row_idx = 2;                                   // Počáteční řádek dat na záložce column
		if (is_array($col_rows)) {                      // Kontrola platného pole sloupců
			foreach ($col_rows as $r) {                 // Průchod načtenými sloupci metadat
				$col_vals = [(string)$r['class_name'], (string)$r['column_name'], (int)$r['parent_order']]; // Identifikace sloupce
				foreach ($col_inh_props as $ip => $empty_as_null) { // Přidání děděných technických vlastností
					$col_vals[] = $this->format_inherited_val($r["own_{$ip}"], $r["anc_{$ip}"], $empty_as_null); // Hodnota (příp. <zděděná>)
				}
				$col_vals[] = (string)$r['ancestor_column']; // Název předka v sys_global_columns
				$col_vals[] = $this->format_inherited_val($r['own_ref_codetable'], $r['anc_ref_codetable'], true);   // Číselník
				$col_vals[] = $this->format_inherited_val($r['own_ref_class_code'], $r['anc_ref_class_code'], true); // Odkazovaná třída
				$col_vals[] = (int)$r['is_final'];      // Příznak is_final
				$col_vals[] = (int)$r['is_protected'];  // Příznak is_protected
				$col_vals[] = (int)$r['inactive'];      // Příznak inactive
				$col_vals[] = (int)$r['removed'];       // Příznak removed
				$col_vals[] = (string)$r['editor_note']; // Poznámka pro AI
				foreach ($col_trans_cols as $tc) {      // Přidání sloupců primárního jazyka
					$col_vals[] = $this->format_inherited_val($r["own_{$tc}"], $r["anc_{$tc}"], true); // Text v 1. jazyce
				}
				foreach ($col_trans_cols as $tc) {      // Přidání sloupců druhého jazyka (*_l)
					$col_vals[] = $this->format_sec_lang_val($sec_lang, $r["own_{$tc}_l"], $r["inh_{$tc}_l"]); // Text ve 2. jazyce
				}
				$sheetCol->fromArray($col_vals, null, 'A' . $row_idx); // Zápis řádku do listu column
				$row_idx++;                             // Posun na další řádek
			}
		}

		foreach (range('A', 'Z') as $colId) {           // Automatická šířka sloupců A až Z na záložce column
			$sheetCol->getColumnDimension($colId)->setAutoSize(true); // Nastavení auto-size sloupce
		}
		foreach (range('A', 'O') as $subCol) {          // Automatická šířka sloupců AA až AO na záložce column
			$sheetCol->getColumnDimension('A' . $subCol)->setAutoSize(true); // Nastavení auto-size sloupce
		}

		$spreadsheet->setActiveSheetIndex(0);           // Aktivace prvního listu CONTENT_INFO při otevření

		$file_suffix = ($sec_lang !== '') ? "_{$lang}_{$sec_lang}" : "_{$lang}"; // Přípona souboru dle zvolených jazyků
		$filename = "meta_object{$file_suffix}.xlsx";   // Výsledný název stahovaného souboru

		header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
		header('Content-Disposition: attachment; filename="' . $filename . '"'); // Hlavička s názvem souboru
		header('Cache-Control: max-age=0');

		$writer = new Xlsx($spreadsheet);               // Inicializace XLSX zapisovače
		$writer->save('php://output');                  // Streamování vygenerovaného sešitu do prohlížeče
		exit;                                           // Okamžité ukončení skriptu po odeslání souboru
	}
}