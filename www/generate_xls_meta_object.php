<?php
/**
 * =============================================================================
 * Verze: 2026-10-14 22:41
 * Soubor: generate_xls_meta_object.php
 * Účel: Generátor vývojářské XLSX šablony (meta_object.xlsx) pro hromadný import
 *       systémových objektů (stránek, globálních frází) a struktury menu.
 *       Využívá existující závislost phpoffice/phpspreadsheet.
 *
 * Vazby na okolí:
 * - Výstupní soubor meta_object.xlsx se nahrává přes UI modul page_excel_reader.php.
 * - Zpracování řídí třída excel_reader.php a balíčková třída xlsx_meta_object
 *   (potomek xlsx_abstract.php v souboru xlsx_meta_object.php) na základě
 *   package_code = 'meta_object'.
 * - Samotný databázový unpivot do 'A' a 'L' záznamů v tabulkách meta_object
 *   a meta_menu provádí uložená procedura p_xlsx_meta_object.
 * - Nepoužívá globální proměnné aplikace, běží jako samostatný CLI/HTTP skript.
 *
 * Změny:
 * 2026-10-14 11:50 - Změna package_code na 'meta_object', doplněn základní jazyk
 *                    (language) a původ importu (import_origin) do CONTENT_INFO.
 *                  - Rozdělení dat na specializované záložky: page (typ P),
 *                    menu (tabulka meta_menu) a phrase (typ G).
 *                  - Doplněn sloupec editor_note pro kontext AI překladů.
 *                  - Naplnění kompletní sadou stránek a menu z BcmOsirisDb.sql.
 * 2026-10-14 22:41 - Sjednocen název souboru na generate_xls_meta_object.php.
 *                  - Do CONTENT_INFO doplněn sloupec second_language ('en').
 *                  - Sloupce základního jazyka změněny na bezpříponové (caption,
 *                    description, helptext) a sloupce druhého jazyka na *_l
 *                    (caption_l, description_l, helptext_l).
 * =============================================================================
 */

declare(strict_types=1);

/**
 * Generátor XLSX šablony pro import systémových objektů.
 * Využívá existující závislost phpoffice/phpspreadsheet.
 */

require_once __DIR__ . '/vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use PhpOffice\PhpSpreadsheet\Style\Fill;

$spreadsheet = new Spreadsheet();                           // Vytvoření nové instance sešitu

// =============================================================================
// 1. Založení a formátování systémové záložky CONTENT_INFO
// =============================================================================
$sheetInfo = $spreadsheet->getActiveSheet();                // Získání aktivního prvního listu
$sheetInfo->setTitle('CONTENT_INFO');                       // Nastavení názvu řídicí záložky

// Hlavičky řídicí záložky
$infoHeaders = [                                            // Definice hlaviček pro CONTENT_INFO
	'A1' => 'package_code',
	'B1' => 'language',
	'C1' => 'second_language',
	'D1' => 'version_date',
	'E1' => 'import_origin',
	'F1' => 'description'
];

foreach ($infoHeaders as $cell => $val) {
	$sheetInfo->setCellValue($cell, $val);                  // Zápis názvu sloupce do buňky záhlaví
}

// Data řídicí záložky (package_code určuje třídu xlsx_meta_object a proceduru p_xlsx_meta_object)
$sheetInfo->setCellValue('A2', 'meta_object');              // Kód importního balíčku
$sheetInfo->setCellValue('B2', 'cs');                       // Základní jazyk dat v šabloně
$sheetInfo->setCellValue('C2', 'en');                       // Druhý jazyk pro sloupce s příponou _l
$sheetInfo->setCellValue('D2', date('Y-m-d'));              // Aktuální datum verze šablony
$sheetInfo->setCellValue('E2', 'BCM Osiris Core Team');     // Identifikace původu importovaných dat
$sheetInfo->setCellValue('F2', 'Import základních stránek, položek menu a globálních frází do meta_object a meta_menu'); // Popis balíčku

$sheetInfo->getStyle('A1:F1')->getFont()->setBold(true);    // Tučné písmo pro záhlaví CONTENT_INFO
$sheetInfo->getStyle('A1:F1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Šedé pozadí záhlaví

foreach (range('A', 'F') as $colId) {
	$sheetInfo->getColumnDimension($colId)->setAutoSize(true); // Automatická šířka sloupců v CONTENT_INFO
}

// =============================================================================
// 2. Založení a formátování datové záložky: page (meta_object, object_type = 'P')
// =============================================================================
$sheetPage = $spreadsheet->createSheet();                   // Založení nového listu pro stránky
$sheetPage->setTitle('page');                               // Pojmenování záložky stránek

$pageHeaders = [                                            // Definice sloupců záložky page
	'A1' => 'builtin_code',                     // Fyzický kód stránky bez prefixu page_
	'B1' => 'system_role',                      // Minimální oprávnění (U, A, S, D)
	'C1' => 'module',                           // Volitelný kód modulu
	'D1' => 'inactive',                         // Příznak deaktivace (0/1)
	'E1' => 'editor_note',                      // Kontextová poznámka pro AI překladatele (nepřekládá se)
	'F1' => 'caption',                          // Název stránky v základním jazyce (language)
	'G1' => 'description',                      // Interní popis stránky v základním jazyce (language)
	'H1' => 'helptext',                         // Uživatelská nápověda ke stránce v základním jazyce (language)
	'I1' => 'caption_l',                        // Překlad názvu stránky do druhého jazyka (second_language)
	'J1' => 'description_l',                    // Překlad popisu stránky do druhého jazyka (second_language)
	'K1' => 'helptext_l'                        // Překlad nápovědy do druhého jazyka (second_language)
];

foreach ($pageHeaders as $cell => $val) {
	$sheetPage->setCellValue($cell, $val);                  // Zápis hlavičky sloupce na záložce page
}

// Obarvení hlavičky pro vizuální odlišení technických dat, AI kontextu a jazykových mutací
$sheetPage->getStyle('A1:D1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Technické sloupce
$sheetPage->getStyle('E1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');    // Sloupec pro AI kontext
$sheetPage->getStyle('F1:H1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Základní jazyk
$sheetPage->getStyle('I1:K1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk (_l)
$sheetPage->getStyle('A1:K1')->getFont()->setBold(true);    // Tučné písmo hlavičky záložky page

// Vzorová data (kompletní sada stránek z table_meta_object.sql)
$pageData = [                                               // Pole vzorových řádků pro záložku page
	['main',                 'U', '', 0, 'Úvodní rozcestník aplikace s dlaždicemi menu.',          'Hlavní panel',              'Výchozí rozcestník po přihlášení',             '', 'Main Dashboard',          'Default dashboard after login',            ''],
	['meta_class',           'S', '', 0, 'Administrátorská správa datových entit (STI).',          'Logické třídy (Objekty)',   'Definice datového modelu a logických tříd',    '', 'Logical Classes',         'Data model and logical class definitions', ''],
	['meta_column',          'S', '', 0, 'Administrátorská správa sloupců a formulářových polí.',  'Sloupce metadat',           'Nastavení vlastností sloupců a dědičnosti',    '', 'Metadata Columns',        'Column properties and inheritance setup',  ''],
	['organization_licence', 'S', '', 0, 'Správa licenčních žádostí a aktivace tenantů.',          'Správa licencí organizací', 'Nástroj pro aktivaci a správu tenantů',        '', 'Org. Licence Management', 'Tool for tenant activation and management', ''],
	['org_users',            'A', '', 0, 'Správa uživatelů a oprávnění v rámci organizace.',       'Uživatelé organizace',      'Správa uživatelů a přístupů tenanta',          '', 'Organization Users',      'Tenant user and access management',        ''],
	['excel_reader',         'S', '', 0, 'Vývojářský nástroj pro hromadný import dat z XLSX.',     'Import dat z Excelu',       'Nástroj pro hromadný import datových struktur', '', 'Excel Data Import',       'Mass data structure import tool',          ''],
	['change_user_context',  'U', '', 0, 'Formulář pro přepnutí aktivní organizace nebo role.',    'Změna kontextu uživatele',  'Přepínání tenantů a aplikačních rolí',         '', 'Switch User Context',     'Tenant and application role switching',    ''],
	['logout',               'U', '', 0, 'Systémová akce pro ukončení relace a odhlášení.',        'Odhlášení ze systému',      'Ukončení uživatelské relace',                  '', 'Log Out',                 'Terminate user session',                   '']
];

$row = 2;                                                   // Počáteční řádek pro zápis dat na záložce page
foreach ($pageData as $rowData) {
	$col = 'A';                                             // Počáteční sloupec pro zápis buněk řádku
	foreach ($rowData as $cellData) {
		$sheetPage->setCellValue($col . $row, $cellData);   // Zápis hodnoty do konkrétní buňky
		$col++;                                             // Posun na další sloupec v řádku
	}
	$row++;                                                 // Posun na další datový řádek
}

foreach (range('A', 'K') as $columnID) {
	$sheetPage->getColumnDimension($columnID)->setAutoSize(true); // Automatické přizpůsobení šířky sloupců
}

// =============================================================================
// 3. Založení a formátování datové záložky: menu (tabulka meta_menu)
// =============================================================================
$sheetMenu = $spreadsheet->createSheet();                   // Založení nového listu pro menu
$sheetMenu->setTitle('menu');                               // Pojmenování záložky navigace

$menuHeaders = [                                            // Definice sloupců záložky menu
	'A1' => 'builtin_code',                     // Unikátní kód položky menu
	'B1' => 'parent_code',                      // builtin_code nadřízené položky menu (prázdné = kořen)
	'C1' => 'sort_code',                        // Pořadí v rámci sourozenců
	'D1' => 'target_page',                      // builtin_code cílové stránky ze záložky page (prázdné = složka)
	'E1' => 'url_parameters',                   // Dodatečné GET parametry
	'F1' => 'target_url',                       // Externí URL
	'G1' => 'target_window',                    // Cílové okno (např. _blank)
	'H1' => 'system_role',                      // Minimální role (U, A, S, D)
	'I1' => 'permanent',                        // 1 = Zobrazit disabled i bez dostupných podpoložek
	'J1' => 'svg_icon',                         // Vektorová ikona
	'K1' => 'css_class',                        // Vlastní CSS třídy
	'L1' => 'editor_note',                      // Kontext pro AI překladatele
	'M1' => 'caption',                          // Zobrazovaný text v menu v základním jazyce (language)
	'N1' => 'description',                      // Interní popis položky v základním jazyce (language)
	'O1' => 'helptext',                         // Tooltip položky v menu v základním jazyce (language)
	'P1' => 'caption_l',                        // Překlad textu v menu do druhého jazyka (second_language)
	'Q1' => 'description_l',                    // Překlad popisu do druhého jazyka (second_language)
	'R1' => 'helptext_l'                        // Překlad tooltipu do druhého jazyka (second_language)
];

foreach ($menuHeaders as $cell => $val) {
	$sheetMenu->setCellValue($cell, $val);                  // Zápis hlavičky sloupce na záložce menu
}

$sheetMenu->getStyle('A1:K1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Technické sloupce menu
$sheetMenu->getStyle('L1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');    // Sloupec pro AI kontext
$sheetMenu->getStyle('M1:O1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Základní jazyk
$sheetMenu->getStyle('P1:R1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk (_l)
$sheetMenu->getStyle('A1:R1')->getFont()->setBold(true);    // Tučné písmo hlavičky záložky menu

$svgHome  = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>'; // Ikona domů
$svgAdmin = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.06-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.73,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.06,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62-0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.49-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>'; // Ikona administrace

// Vzorová data menu (odpovídá table_meta_menu.sql + doplněn excel_reader)
$menuData = [                                               // Pole vzorových řádků pro záložku menu
	['home',                 '',             '00', 'main',                 '', '', '', 'U', 0, $svgHome,  '', 'Kořenová položka drobečkové navigace.',          'Domů',                      '', 'Přechod na hlavní panel',                'Home',                    '', 'Go to main dashboard'],
	['admin_folder',         'home',         '90', '',                     '', '', '', 'S', 0, $svgAdmin, '', 'Složka pro systémovou správu a konfiguraci.',    'Systémová administrace',    '', 'Nástroje pro správu systému a metadat',  'System Administration',   '', 'System and metadata administration tools'],
	['meta_class',           'admin_folder', '01', 'meta_class',           '', '', '', 'S', 0, '',        '', 'Položka menu pro správu logických tříd.',        'Logické třídy (Objekty)',   '', 'Správa logických tříd a tabulek',        'Logical Classes',         '', 'Manage logical classes and tables'],
	['meta_column',          'admin_folder', '02', 'meta_column',          '', '', '', 'S', 0, '',        '', 'Položka menu pro správu sloupců metadat.',       'Sloupce metadat',           '', 'Správa vlastností sloupců formulářů',    'Metadata Columns',        '', 'Manage form column properties'],
	['organization_licence', 'admin_folder', '03', 'organization_licence', '', '', '', 'S', 0, '',        '', 'Položka menu pro správu licencí organizací.',    'Správa licencí organizací', '', 'Schvalování a aktivace licencí tenantů', 'Org. Licence Management', '', 'Approve and activate tenant licences'],
	['org_users',            'admin_folder', '04', 'org_users',            '', '', '', 'A', 0, '',        '', 'Položka menu pro správu uživatelů organizace.',  'Uživatelé organizace',      '', 'Správa uživatelů v aktuální organizaci', 'Organization Users',      '', 'Manage users in current organization'],
	['excel_reader',         'admin_folder', '05', 'excel_reader',         '', '', '', 'S', 0, '',        '', 'Položka menu pro nahrávání XLSX balíčků.',       'Import dat z Excelu',       '', 'Hromadný import metadat a dat z XLSX',   'Excel Data Import',       '', 'Bulk metadata and data import from XLSX']
];

$row = 2;                                                   // Počáteční řádek pro zápis dat na záložce menu
foreach ($menuData as $rowData) {
	$col = 'A';                                             // Počáteční sloupec pro zápis buněk řádku
	foreach ($rowData as $cellData) {
		$sheetMenu->setCellValue($col . $row, $cellData);   // Zápis hodnoty buňky na záložce menu
		$col++;                                             // Posun na další sloupec v řádku
	}
	$row++;                                                 // Posun na další datový řádek
}

foreach (range('A', 'R') as $columnID) {
	if ($columnID === 'J') {
		$sheetMenu->getColumnDimension($columnID)->setWidth(25);    // Omezení šířky sloupce s dlouhým SVG kódem
	} else {
		$sheetMenu->getColumnDimension($columnID)->setAutoSize(true); // Automatická šířka ostatních sloupců
	}
}

// =============================================================================
// 4. Založení a formátování datové záložky: phrase (meta_object, object_type = 'G')
// =============================================================================
$sheetPhrase = $spreadsheet->createSheet();                 // Založení nového listu pro globální fráze
$sheetPhrase->setTitle('phrase');                           // Pojmenování záložky globálních frází

$phraseHeaders = [                                          // Definice sloupců záložky phrase
	'A1' => 'builtin_code',                     // Kód globální fráze (např. T_SUBMIT)
	'B1' => 'module',                           // Volitelné zařazení do modulu
	'C1' => 'editor_note',                      // Kontext pro AI překlad (zda jde o tlačítko, nadpis apod.)
	'D1' => 'caption',                          // Krátký text fráze v základním jazyce (language)
	'E1' => 'helptext',                         // Dlouhý text / víceřádková šablona v základním jazyce (language)
	'F1' => 'caption_l',                        // Překlad krátkého textu do druhého jazyka (second_language)
	'G1' => 'helptext_l'                        // Překlad dlouhého textu do druhého jazyka (second_language)
];

foreach ($phraseHeaders as $cell => $val) {
	$sheetPhrase->setCellValue($cell, $val);                // Zápis hlavičky sloupce na záložce phrase
}

$sheetPhrase->getStyle('A1:B1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0'); // Technické sloupce fráze
$sheetPhrase->getStyle('C1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9D2E9');    // Sloupec pro AI kontext
$sheetPhrase->getStyle('D1:E1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3'); // Základní jazyk
$sheetPhrase->getStyle('F1:G1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD'); // Druhý jazyk (_l)
$sheetPhrase->getStyle('A1:G1')->getFont()->setBold(true);  // Tučné písmo hlavičky záložky phrase

$phraseData = [                                             // Pole vzorových řádků pro záložku phrase
	['T_SUBMIT',          '', 'Tlačítko pro odeslání a zpracování formuláře.',             'Načíst a zpracovat', 'Odešle formulář ke zpracování na server.', 'Load and Process', 'Submits the form for server processing.'],
	['T_CLOSE',           '', 'Tlačítko pro zavření modálního nebo detailního okna.',      'Zavřít',             '',                                         'Close',            ''],
	['T_HELP',            '', 'Popisek tlačítka pro zobrazení nápovědy.',                  'Nápověda',           '',                                         'Help',             ''],
	['T_REMOVE',          '', 'Popisek akce nebo checkboxu pro smazání/odebrání položky.', 'Odstranit',          '',                                         'Remove',           ''],
	['T_SERVER_MESSAGES', '', 'Záhlaví tabulky se zprávami z databázového serveru.',       'Zprávy ze serveru',  '',                                         'Server Messages',  ''],
	['T_OBJECT',          '', 'Záhlaví sloupce označujícího typ objektu v logu zpráv.',    'Objekt',             '',                                         'Object',           ''],
	['T_CAPTION',         '', 'Záhlaví sloupce s názvem objektu v logu zpráv.',            'Název',              '',                                         'Caption',          ''],
	['T_DETAIL',          '', 'Záhlaví sloupce s detailem nebo počtem řádků v logu.',      'Detail',             '',                                         'Detail',           '']
];

$row = 2;                                                   // Počáteční řádek pro zápis dat na záložce phrase
foreach ($phraseData as $rowData) {
	$col = 'A';                                             // Počáteční sloupec pro zápis buněk řádku
	foreach ($rowData as $cellData) {
		$sheetPhrase->setCellValue($col . $row, $cellData); // Zápis hodnoty buňky na záložce phrase
		$col++;                                             // Posun na další sloupec v řádku
	}
	$row++;                                                 // Posun na další datový řádek
}

foreach (range('A', 'G') as $columnID) {
	$sheetPhrase->getColumnDimension($columnID)->setAutoSize(true); // Automatická šířka sloupců na záložce phrase
}

// Nastavení první záložky jako aktivní při otevření v Excelu
$spreadsheet->setActiveSheetIndex(0);                       // Aktivace prvního listu CONTENT_INFO

// Odeslání hlaviček pro přímé stažení vygenerovaného souboru do prohlížeče
header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
header('Content-Disposition: attachment;filename="meta_object.xlsx"');
header('Cache-Control: max-age=0');

$writer = new Xlsx($spreadsheet);                           // Inicializace XLSX zapisovače
$writer->save('php://output');                              // Zápis vygenerovaného sešitu přímo na výstup
exit;