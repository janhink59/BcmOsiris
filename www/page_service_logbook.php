<?php
/**
 * =============================================================================
 * Verze: 2026-10-25 11:30
 * Soubor: page_service_logbook.php
 * Třída: page_service_logbook
 * Účel: Přehledová stránka pro prohlížení záznamů v provozním deníku
 *       service_logbook (historie spuštěných změnových skriptů changes_YYYY.sql
 *       a importů systémových dávek).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z centrálního routeru index.php při ?page=page_service_logbook.
 * - Dědí z třídy abstract_page (abstract_page.php), využívá vlastnosti page_title,
 *   access_denied, full_width a lokalizaci přes metodu phrase().
 * - Stránka je dostupná pro systémové administrátory (active_role = 'S' nebo 'D'),
 *   v meta_object a meta_menu je registrována pod system_role = 'S'.
 * - Využívá komponentu abstract_button (abstract_button.php) pro vykreslení tlačítek
 *   filtrace a obnovy výchozího stavu.
 * - Čte data z tabulky service_logbook (definované v system_constant.sql) pomocí
 *   funkcí sqlfirstrow() a sqlarray_simple() z knihovny OsirisLib.php.
 *
 * Změny:
 * 2026-10-25 11:30 - Vytvoření první verze stránky pro prohlížení tabulky service_logbook
 *                    s filtrací podle počtu záznamů (výchozí 100) a textového vzorku.
 * =============================================================================
 */

declare(strict_types=1);

class page_service_logbook extends abstract_page {

	private int $limit = 100;                                                // Maximální počet zobrazovaných záznamů (výchozí 100)
	private string $search_text = '';                                        // Textový vzorek pro fulltextové filtrování

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu v předkovi

		global $dbsession;                                                   // Globální kontext relace přihlášeného uživatele

		$this->page_title =$this->phrase('page_title', [], 'Provozní deník (service_logbook) - BCM Osiris'); // Lokalizovaný titulek stránky
		$this->full_width = true;                                            // Roztažení hlavního panelu na plnou šířku okna

		$active_role = (string)($dbsession['active_role'] ?? 'U');           // Aktuální efektivní role v relaci
		if ($this->access_denied OR !in_array($active_role, ['S', 'D'], true)) { // Kontrola oprávnění Sysadmin nebo Developer
			$this->access_denied = true;                                     // Odepření přístupu pro nižší role
			return;                                                          // Ukončení inicializace při zamítnutí přístupu
		}

		// Načtení a validace filtru počtu záznamů (přednastaveno 100, rozsah 1 až 10 000)
		$raw_limit = trim((string)getinput('limit'));                        // Surová hodnota limitu z požadavku
		if ($raw_limit !== '' AND is_numeric($raw_limit)) {                  // Pokud byl zadán číselný limit
			$parsed_limit = intval($raw_limit);                              // Převod limitu na celé číslo
			if ($parsed_limit >= 1 AND$parsed_limit <= 10000) {             // Kontrola povoleného rozsahu
				$this->limit =$parsed_limit;                                // Uložení platného limitu záznamů
			}
		}

		// Načtení textového vzorku pro filtrování
		$this->search_text = trim((string)getinput('search_text', 'raw'));   // Očištěný hledaný textový vzorek
	}

	/**
	 * Vykreslí filtrační formulář a tabulku záznamů z tabulky service_logbook.
	 */
	protected function render_body(): void {
		$heading = htmlspecialchars($this->phrase('heading_logbook', [], 'Provozní deník databáze (service_logbook)')); // Hlavní nadpis stránky
		$intro = htmlspecialchars($this->phrase('intro_logbook', [], 'Přehled historie spuštěných změnových skriptů databáze a importů systémových dávek (seřazeno od nejnovějšího záznamu).')); // Popis stránky

		echo "<h1 class=\"page-heading\">{$heading}</h1>\n";                 // Výpis hlavního nadpisu stránky
		echo "<p style=\"margin-bottom: 18px; color: #475569; font-size: 13px;\">{$intro}</p>\n"; // Výpis úvodního popisu

		// Ověření fyzické existence tabulky service_logbook v databázi
		$tbl_check = sqlfirstrow("SELECT OBJECT_ID('service_logbook') AS obj_id"); // Dotaz na přítomnost tabulky v databázi
		if (empty($tbl_check) OR empty($tbl_check['obj_id'])) {              // Pokud tabulka v databázi ještě neexistuje
			$msg_missing = htmlspecialchars($this->phrase('msg_table_missing', [], 'Tabulka service_logbook v databázi dosud neexistuje. Spusťte nejprve změnový skript changes_2026.sql nebo hlavní dávku BcmOsirisDb.sql.')); // Chybová zpráva
			echo "<div class=\"msg-err\">{$msg_missing}</div>\n";            // Výpis chybové zprávy
			return;                                                          // Ukončení vykreslování
		}

		// Sestavení filtračního formuláře
		$menu_code = trim((string)getinput('menu_code'));                    // Kód položky menu pro zachování drobečkové navigace
		$safe_menu_code = htmlspecialchars($menu_code);                      // Ošetřený kód menu pro skryté pole
		$menu_input_html = ($menu_code !== '') ? "<input type=\"hidden\" name=\"menu_code\" value=\"{$safe_menu_code}\">" : ''; // Skryté pole menu_code

		$lbl_limit = htmlspecialchars($this->phrase('lbl_filter_limit', [], 'Počet záznamů:')); // Popisek pole počtu záznamů
		$lbl_search = htmlspecialchars($this->phrase('lbl_filter_search', [], 'Vzorek textu:')); // Popisek pole textového vzorku
		$ph_search = htmlspecialchars($this->phrase('ph_filter_search', [], 'Hledat v názvu, verzi, obsahu, serveru nebo loginu...')); // Placeholder hledání

		$safe_limit = htmlspecialchars(strval($this->limit));                // Ošetřená hodnota počtu záznamů
		$safe_search = htmlspecialchars($this->search_text);                 // Ošetřená hodnota hledaného textu

		$btn_filter = new abstract_button('btn_apply_filter', 'Filtrovat', 'page_service_logbook'); // Tlačítko odeslání filtru
		$btn_filter->set_type('submit')->set_onclick('isFormDirty = false;'); // Vypnutí příznaku změny při filtrování
		$btn_filter_html =$btn_filter->render();                            // Vykreslení tlačítka Filtrovat

		$reset_url = 'index.php?page=page_service_logbook' . ($menu_code !== '' ? '&menu_code=' . urlencode($menu_code) : ''); // URL pro zrušení filtru
		$btn_reset = new abstract_button('btn_reset_filter', 'Zrušit filtr', 'page_service_logbook', '', 'btn-secondary'); // Tlačítko resetu filtru
		$btn_reset->set_href($reset_url)->set_onclick('isFormDirty = false;'); // Odkaz pro návrat na výchozích 100 záznamů
		$btn_reset_html =$btn_reset->render();                              // Vykreslení tlačítka Zrušit filtr

		echo "<form method=\"get\" action=\"index.php\" onsubmit=\"isFormDirty = false;\" style=\"background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; padding: 12px 15px; margin-bottom: 18px; display: flex; align-items: center; gap: 15px; flex-wrap: wrap;\">\n";
		echo "\t<input type=\"hidden\" name=\"page\" value=\"page_service_logbook\">\n";
		echo "\t{$menu_input_html}\n";                                       // Vložení skrytého pole pro kód menu
		echo "\t<div style=\"display: flex; align-items: center; gap: 6px;\">\n";
		echo "\t\t<label for=\"inp_limit\" style=\"font-weight: bold; font-size: 13px; color: #334155;\">{$lbl_limit}</label>\n"; // Popisek počtu řádků
		echo "\t\t<input type=\"number\" id=\"inp_limit\" name=\"limit\" value=\"{$safe_limit}\" min=\"1\" max=\"10000\" oninput=\"isFormDirty = false;\" style=\"width: 90px; padding: 6px 8px; border: 1px solid #cbd5e1; border-radius: 3px; font-size: 13px;\">\n"; // Pole počtu záznamů
		echo "\t</div>\n";
		echo "\t<div style=\"display: flex; align-items: center; gap: 6px; flex: 1; min-width: 260px; max-width: 500px;\">\n";
		echo "\t\t<label for=\"inp_search\" style=\"font-weight: bold; font-size: 13px; color: #334155; white-space: nowrap;\">{$lbl_search}</label>\n"; // Popisek textového vzorku
		echo "\t\t<input type=\"text\" id=\"inp_search\" name=\"search_text\" value=\"{$safe_search}\" placeholder=\"{$ph_search}\" oninput=\"isFormDirty = false;\" style=\"width: 100%; padding: 6px 8px; border: 1px solid #cbd5e1; border-radius: 3px; font-size: 13px; box-sizing: border-box;\">\n"; // Pole hledaného vzorku textu
		echo "\t</div>\n";
		echo "\t<div style=\"display: flex; align-items: center; gap: 8px;\">\n";
		echo "\t\t{$btn_filter_html}\n";                                     // Tlačítko pro potvrzení filtru
		echo "\t\t{$btn_reset_html}\n";                                      // Tlačítko pro vyčištění filtru
		echo "\t</div>\n";
		echo "</form>\n";

		// Sestavení SQL dotazu s TOP (@limit) a volitelnou podmínkou LIKE
		$where_sql = '';                                                     // Výchozí prázdná podmínka WHERE
		if ($this->search_text !== '') {                                     // Pokud uživatel zadal hledaný vzorek textu
			$like_lit = charliteral('%' .$this->search_text . '%');         // Bezpečný SQL literál se znaky % pro LIKE
			$where_sql = "WHERE [name] LIKE {$like_lit}"                     // Hledání v názvu skriptu nebo operace
				. " OR [version] LIKE {$like_lit}"                           // Hledání v označení verze
				. " OR ISNULL(content, '') LIKE {$like_lit}"                 // Hledání v poznámce nebo obsahu
				. " OR servername LIKE {$like_lit}"                          // Hledání v názvu SQL serveru
				. " OR original_login LIKE {$like_lit}"                      // Hledání v přihlašovacím jménu SQL účtu
				. " OR CONVERT(varchar(30), [date], 120) LIKE {$like_lit}";  // Hledání v datu a času provedení
		}

		$top_int = intval($this->limit);                                     // Jistota celočíselného TOP limitu
		$sql = "SELECT TOP ({$top_int}) id, servername, original_login, [date], [name], [version], content" // Výběr sloupců s limitem
			. " FROM service_logbook {$where_sql}"                           // Zdrojová tabulka a volitelný filtr
			. " ORDER BY [date] DESC, id DESC";                              // Seřazení záznamů od nejnovějšího

		$rows = sqlarray_simple($sql);                                       // Načtení celého výsledku do pole v paměti
		$row_count = is_array($rows) ? count($rows) : 0;                     // Počet načtených záznamů

		if ($row_count === 0) {                                              // Pokud dotaz nevrátil žádné záznamy
			$msg_empty = htmlspecialchars($this->phrase('msg_no_records', [], 'Zadaným kritériím neodpovídají v tabulce service_logbook žádné záznamy.')); // Informační hláška
			echo "<div class=\"msg-info\">{$msg_empty}</div>\n";             // Výpis informační hlášky
			return;                                                          // Ukončení vykreslování
		}

		$lbl_found = htmlspecialchars($this->phrase('lbl_displayed_records', ['count' =>$row_count], 'Zobrazeno záznamů: {' . chr(36) . 'count}')); // Počet zobrazených řádků
		$th_id      = htmlspecialchars($this->phrase('th_id', [], 'ID'));                       // Záhlaví sloupce ID
		$th_date    = htmlspecialchars($this->phrase('th_date', [], 'Datum a čas'));            // Záhlaví sloupce data
		$th_name    = htmlspecialchars($this->phrase('th_name', [], 'Skript / Operace (name)')); // Záhlaví sloupce názvu
		$th_version = htmlspecialchars($this->phrase('th_version', [], 'Verze (version)'));     // Záhlaví sloupce verze
		$th_server  = htmlspecialchars($this->phrase('th_servername', [], 'Server'));           // Záhlaví sloupce serveru
		$th_login   = htmlspecialchars($this->phrase('th_original_login', [], 'SQL Login'));    // Záhlaví sloupce loginu
		$th_content = htmlspecialchars($this->phrase('th_content', [], 'Obsah / Poznámka (content)')); // Záhlaví sloupce obsahu

		echo "<div style=\"margin-bottom: 8px; font-size: 12px; color: #64748b; font-weight: bold;\">{$lbl_found}</div>\n"; // Výpis počtu řádků
		echo "<table class=\"md-table\">\n";
		echo "\t<thead>\n";
		echo "\t\t<tr>\n";
		echo "\t\t\t<th style=\"width: 60px; text-align: right;\">{$th_id}</th>\n"; // Buňka záhlaví ID
		echo "\t\t\t<th style=\"width: 135px;\">{$th_date}</th>\n";                 // Buňka záhlaví data
		echo "\t\t\t<th style=\"width: 220px;\">{$th_name}</th>\n";                 // Buňka záhlaví názvu
		echo "\t\t\t<th style=\"width: 130px;\">{$th_version}</th>\n";              // Buňka záhlaví verze
		echo "\t\t\t<th style=\"width: 160px;\">{$th_server}</th>\n";               // Buňka záhlaví serveru
		echo "\t\t\t<th style=\"width: 160px;\">{$th_login}</th>\n";                // Buňka záhlaví loginu
		echo "\t\t\t<th>{$th_content}</th>\n";                                      // Buňka záhlaví poznámky
		echo "\t\t</tr>\n";
		echo "\t</thead>\n";
		echo "\t<tbody>\n";

		foreach ($rows as$row) {                                            // Průchod načtenými záznamy v paměti
			$id_val = intval($row['id']);                                    // Primární klíč záznamu
			$date_val = htmlspecialchars(date_format4((string)($row['date'] ?? ''), 16)); // Zformátované datum a čas
			$name_val = htmlspecialchars((string)($row['name'] ?? ''));      // Název skriptu nebo procedury
			$ver_val = htmlspecialchars((string)($row['version'] ?? ''));    // Verze databáze nebo balíčku
			$srv_val = htmlspecialchars((string)($row['servername'] ?? '')); // Název SQL serveru
			$lgn_val = htmlspecialchars((string)($row['original_login'] ?? '')); // Přihlašovací jméno SQL účtu
			$cnt_val = nl2br(htmlspecialchars((string)($row['content'] ?? ''))); // Ošetřený text poznámky se zachováním odřádkování

			echo "\t\t<tr>\n";
			echo "\t\t\t<td style=\"text-align: right; font-family: monospace; color: #64748b;\">{$id_val}</td>\n"; // Buňka číselného ID
			echo "\t\t\t<td style=\"white-space: nowrap; font-family: monospace;\">{$date_val}</td>\n";             // Buňka data a času
			echo "\t\t\t<td><strong>{$name_val}</strong></td>\n";                                                   // Buňka názvu operace
			echo "\t\t\t<td style=\"font-family: monospace; color: #004488; font-weight: bold;\">{$ver_val}</td>\n"; // Buňka označení verze
			echo "\t\t\t<td style=\"font-size: 12px; color: #475569;\">{$srv_val}</td>\n";                          // Buňka názvu serveru
			echo "\t\t\t<td style=\"font-size: 12px; color: #475569;\">{$lgn_val}</td>\n";                          // Buňka účtu SQL loginu
			echo "\t\t\t<td style=\"font-size: 12px;\">{$cnt_val}</td>\n";                                          // Buňka textového obsahu
			echo "\t\t</tr>\n";
		}

		echo "\t</tbody>\n";
		echo "</table>\n";
	}
}