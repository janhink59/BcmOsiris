<?php
/**
 * =============================================================================
 * Verze: 2026-10-21 15:15
 * Soubor: generate_xls_meta_object.php (resp. generate_xlsx_meta_object.php)
 * Účel: Zpětně kompatibilní vstupní bod pro vygenerování a stažení vývojářské
 *       XLSX šablony systémových metadat (meta_object.xlsx).
 *       Samotná logika živého exportu všech 6 záložek (CONTENT_INFO, page,
 *       menu, phrase, class, column) se zobrazením zděděných hodnot <do stříšek>
 *       a podporou volby jazyků je nyní zapouzdřena v samostatné třídě stránky
 *       page_xlsx_export_meta (v souboru page_xlsx_export_meta.php).
 *
 * Vazby na okolí:
 * - Přesměrovává požadavek na centrální router `index.php?page=page_xlsx_export_meta&action=export_xlsx`.
 * - Výstupní soubor meta_object.xlsx se nahrává přes UI modul page_excel_reader.php.
 * - Zpracování řídí třída excel_reader.php a balíčková třída xlsx_meta_object
 *   (potomek xlsx_abstract.php v souboru xlsx_meta_object.php) na základě
 *   package_code = 'meta_object'.
 * - Samotný databázový unpivot do 'A' a 'L' záznamů v tabulkách meta_object,
 *   meta_phrase, meta_menu, meta_class a meta_column provádí uložená procedura
 *   p_xlsx_meta_object.
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
 * 2026-10-15 22:25 - Sjednocení názvů stránek na plné názvy s prefixem page_
 *                    a doplnění bázových UI tříd na záložku page.
 *                  - Rozšíření záložky phrase o sloupce source_code, svg_icon
 *                    a css_class pro tabulku meta_phrase.
 *                  - Doplněno živé načítání systémových záznamů (0x00) z DB.
 * 2026-10-21 15:15 - Odstraněna duplicitní a zastaralá statická definice záložek
 *                    (obsahovala zakázané bezejmenné záznamy ''); skript nyní
 *                    přímo deleguje generování sešitu na page_xlsx_export_meta.
 * =============================================================================
 */

declare(strict_types=1);

$target_url = 'index.php?page=page_xlsx_export_meta&action=export_xlsx';    // Cílová adresa pro přímé vygenerování XLSX
header('Location: ' . $target_url);                                         // Přesměrování na dedikovanou exportní stránku
exit;                                                                       // Okamžité ukončení skriptu