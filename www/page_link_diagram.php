<?php
/**
 * =============================================================================
 * Verze: 2026-11-27 15:40
 * Soubor: page_link_diagram.php
 * Třída: page_link_diagram
 *
 * 1. Role souboru v celém systému:
 *    Správa schémat (diagramů) heterogenních sítí vztahů (tabulka link_diagram)
 *    a jejich orientovaných hran (tabulka link_diagram_edge) přímo v menu
 *    Nastavení a katalogy CRMM bez opouštění detailu schématu.
 *    Umožňuje přímo vybírat a odebírat existující orientované vztahy z katalogu
 *    Definice typů vazeb (meta_link_def), průběžně zobrazuje vyhodnocenou
 *    topologii acyklického grafu tříd včetně názvů použitých vztahů a detekce
 *    cyklů a spouští projekci nepřímých vztahů a vazeb (dbo.p_rebuild_link_diagram).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Instancována dynamicky z routeru index.php při ?page=page_link_diagram.
 *    - Dědí z abstract_page_master_detail a pracuje s logickou třídou 'link_diagram'.
 *    - Volá uložené procedury dbo.page_link_diagram (page_link_diagram.sql)
 *      pro načítání a úpravu hran v link_diagram_edge a vyhodnocení topologie
 *      a dbo.p_rebuild_link_diagram (p_rebuild_link_diagram.sql) pro projekci sítě.
 *    - Fráze a položka menu jsou definovány v page_link_diagram#phrase.sql.
 *
 * 3. Očekávaná kontextová data:
 *    - Čte kontext přihlášeného uživatele v globálním poli $dbsession
 *      (v databázi v tabulce dbsession pro aktuální @@SPID) a volitelný GET
 *      parametr include_fk (1 = zobrazit v nabídce i technické 1:N FK vztahy).
 *
 * Změny:
 * 2026-11-27 15:40 - Kompletní integrovaný výběr a správa hran schématu
 *                    (link_diagram_edge) přímo v detailu stránky page_link_diagram;
 *                    odstraněno matoucí tlačítko přesměrovávající do Analýzy rizik
 *                    (page_link.php); doplněna blokace přepočtu při cyklu tříd
 *                    a zobrazení použitých hran u každé větve topologie.
 * 2026-11-16 15:40 - Inline SQL dotazy v render_detail_header_buttons() a
 *                    render_detail_top() vyčleněny do uložené procedury
 *                    dbo.page_link_diagram (page_link_diagram.sql).
 * =============================================================================
 */

declare(strict_types=1);

class page_link_diagram extends abstract_page_master_detail {

	private bool $include_fk = false;                                        // Zda zobrazit v nabídce i technické 1:N FK vztahy

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'link_diagram';                                  // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových diagramů sítě
		$this->include_fk = ((string) getinput('include_fk') === '1');       // Volba zobrazení technických 1:N FK vztahů
		$this->page_title = $this->phrase('page_title', [], 'Schémata sítí vztahů (Diagramy CRMM)'); // Titulek stránky

		if (! $this->access_denied AND $this->em === null) {                 // Inicializace entity_manageru pro nastavení sloupců seznamu
			$this->em = new entity_manager($this->class_name);               // Vytvoření instance správce entit
			$this->em->set_list_columns([                                    // Přehledné sloupce v levém Master panelu
				'sort_code'    => $this->phrase('th_sort_code', [], 'Pořadí'),
				'caption'      => $this->phrase('th_diagram_caption', [], 'Název schématu sítě'),
				'builtin_code' => $this->phrase('th_builtin_code', [], 'Kód')
			]);                                                              // Konec definice sloupců Master panelu
		}

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty a popis schématu sítě'); // Sekce textů
		$grp_id   = $this->phrase('grp_identification', [], 'Identifikace, řazení, vzhled a platnost'); // Sekce identifikace

		$this->form_groups = [                                               // Rozdělení polí do logických sekcí formuláře
			$grp_pres => ['caption', 'shortname', 'description_text', 'help_text'], // Lokalizované názvy a popisy
			$grp_id   => ['builtin_code', 'sort_code', 'external_code', 'svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Kód, ikona a platnost
		];                                                                   // Konec definice skupin formuláře
	}

	/**
	 * Rozšíří kontextový přívažek URL o parametr `include_fk`.
	 */
	protected function get_context_url_suffix(): string {
		$suffix = parent::get_context_url_suffix();                          // Základní kontextové parametry z předka
		if ($this->include_fk AND ! str_contains($suffix, '&include_fk=')) { // Zachování přepínače FK vztahů
			$suffix .= '&include_fk=1';                                      // Připojení parametru include_fk
		}
		return $suffix;                                                      // Vrácení přívažku URL
	}

	/**
	 * Rozšíří skrytá pole formuláře o parametr `include_fk`.
	 */
	protected function get_context_hidden_inputs(): string {
		$inputs = parent::get_context_hidden_inputs();                       // Základní skrytá pole z předka
		if ($this->include_fk) {                                             // Skryté pole pro include_fk
			$inputs .= "\n\t\t\t<input type=\"hidden\" name=\"include_fk\" value=\"1\">"; // Zachování volby přes POST
		}
		return $inputs;                                                      // Vrácení skrytých polí
	}

	/**
	 * Zpracuje přidání/odebrání hrany schématu (link_diagram_edge) nebo přepočet
	 * a projekci nepřímých vztahů a vazeb diagramu (`btn_rebuild_diagram`).
	 */
	protected function process_save(): void {
		$upd_guid = trim((string) getinput('update_guid'));                  // UUID vybraného diagramu
		$has_valid_dg = ($upd_guid !== '' AND $upd_guid !== 'NEW' AND is_guid($upd_guid)); // Zda jde o uložený diagram

		if (! $this->is_readonly AND $has_valid_dg) {                        // Specifické akce nad uloženým schématem
			$safe_dg = guidliteral($upd_guid);                               // SQL literál originálu diagramu
			$url_suffix = $this->get_context_url_suffix();                   // Kontextové parametry URL

			// 1. Přidání orientovaného vztahu z meta_link_def do tabulky link_diagram_edge
			if (isset($_POST['btn_add_edge'])) {                             // Stisk tlačítka + Přidat vztah
				$add_ld = trim((string) ($_POST['add_link_def_uuid'] ?? '')); // Vybrané UUID vztahu z roletky
				if ($add_ld !== '' AND is_guid($add_ld)) {                   // Platné UUID vztahu
					$safe_ld = guidliteral($add_ld);                         // SQL literál vztahu
					sqlrun("BEGIN TRAN; EXEC dbo.page_link_diagram @subpage = 'add_edge', @diagram_uuid = {$safe_dg}, @link_def_uuid = {$safe_ld}; COMMIT;"); // Zápis hrany
				}
				autoredirect("index.php?page=page_link_diagram{$url_suffix}&update_guid=" . urlencode($upd_guid)); // PRG redirect zpět na tentýž detail
				return;                                                      // Ukončení zpracování
			}

			// 2. Odebrání orientovaného vztahu z tabulky link_diagram_edge
			if (isset($_POST['btn_remove_edge'])) {                          // Stisk tlačítka Odebrat u řádku hrany
				$rem_ld = trim((string) ($_POST['btn_remove_edge'] ?? ''));  // UUID odebíraného vztahu
				if ($rem_ld !== '' AND is_guid($rem_ld)) {                   // Platné UUID vztahu
					$safe_ld = guidliteral($rem_ld);                         // SQL literál vztahu
					sqlrun("BEGIN TRAN; EXEC dbo.page_link_diagram @subpage = 'remove_edge', @diagram_uuid = {$safe_dg}, @link_def_uuid = {$safe_ld}; COMMIT;"); // Odebrání hrany
				}
				autoredirect("index.php?page=page_link_diagram{$url_suffix}&update_guid=" . urlencode($upd_guid)); // PRG redirect zpět na detail
				return;                                                      // Ukončení zpracování
			}

			// 3. Přepočet a projekce nepřímých vztahů tříd (meta_link_def) a vazeb objektů (link)
			if (isset($_POST['btn_rebuild_diagram'])) {                      // Stisk tlačítka Přepočítat a promítnout síť
				$topo = sqlarray_simple("EXEC dbo.page_link_diagram @subpage = 'topology', @diagram_uuid = {$safe_dg}"); // Kontrola cyklu před projekcí
				$has_cycle = false;                                          // Příznak zjištěného cyklu mezi třídami
				if (is_array($topo)) {                                       // Průchod výsledkem topologie
					foreach ($topo as $t_row) {                              // Kontrola každého uzlu
						if (! empty($t_row['bad'])) {                        // Detekováno mezitřídní zacyklení
							$has_cycle = true;                               // Zablokování přepočtu
							break;                                           // Stačí první nalezený cyklus
						}
					}
				}
				if ($has_cycle) {                                            // Při zacyklení zobrazíme chybu bez redirectu
					$this->save_error_message = $this->phrase('err_diagram_cycle_rebuild_blocked', [], 'Schéma sítě obsahuje zacyklení mezi logickými třídami! Odstraňte prosím kolidující vztah a poté spusťte přepočet znovu.'); // Chybová hláška
					return;                                                  // Zastavení projekce
				}
				$org_sql = guidliteral(get_session_org());                   // SQL literál aktivní organizace
				sqlrun("BEGIN TRAN; EXEC dbo.p_rebuild_link_diagram @diagram_uuid = {$safe_dg}, @org_uuid = {$org_sql}; COMMIT;"); // Přepočet sítě
				autoredirect("index.php?page=page_link_diagram{$url_suffix}&update_guid=" . urlencode($upd_guid)); // PRG redirect
				return;                                                      // Ukončení zpracování
			}
		}

		parent::process_save();                                              // Standardní uložení záznamu v předkovi
	}

	/**
	 * Vykreslí tlačítko "+ Nové schéma sítě" v horní části levého panelu.
	 */
	protected function render_master_top(): void {
		if (! $this->allow_insert) {                                         // Pokud zakládání nových záznamů není povoleno
			return;                                                          // Tlačítko nevykreslujeme
		}

		$url_suffix = $this->get_context_url_suffix();                       // Přívažek URL s kontextem
		$new_url = "index.php?page=page_link_diagram{$url_suffix}&update_guid=NEW"; // Cílová adresa pro nový diagram
		$btn_new = new abstract_button('btn_new_diagram', '+ Nové schéma sítě (diagram)', 'page_link_diagram'); // Tlačítko
		$btn_new->set_href($new_url)                                         // Nastavení cílové URL
			->set_onclick("if(window.loadDetailPanel){loadDetailPanel('{$new_url}');return false;}") // Asynchronní otevření
			->set_style('width: 100%; justify-content: center; margin-bottom: 10px;'); // Roztažení na šířku panelu

		echo $btn_new->render();                                             // Vykreslení tlačítka
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s kódem vybraného diagramu.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Zakládání nového diagramu
			return htmlspecialchars($this->phrase('header_new_diagram', [], 'Nové schéma sítě vztahů')); // Nadpis nového záznamu
		}
		$code = htmlspecialchars((string) ($datarow['builtin_code'] ?: $datarow['caption'] ?? '')); // Ošetřený kód nebo název
		$lbl = htmlspecialchars($this->phrase('header_edit_diagram', [], 'Schéma sítě')); // Lokalizované návěstí
		return "{$lbl}: <span style=\"font-family: monospace; color: #555;\">{$code}</span>"; // Výsledný HTML nadpis
	}

	/**
	 * Vloží do hlavičky detailu tlačítko pro prohlížení vygenerovaných nepřímých vztahů
	 * tříd (`page_meta_link_def`, zůstává v Nastavení a katalogy CRMM) a tlačítko přepočtu sítě.
	 */
	protected function render_detail_header_buttons(string $update_guid): string { // Akční tlačítka v hlavičce detailu
		if ($update_guid === '' OR $update_guid === 'NEW') {                 // U neuloženého záznamu tlačítka nezobrazujeme
			return '';                                                       // Prázdný výstup
		}

		$dg_sql = guidliteral($update_guid);                                 // SQL literál originálu diagramu
		$cnt_row = sqlfirstrow("EXEC dbo.page_link_diagram @subpage = 'counts', @diagram_uuid = {$dg_sql}"); // Načtení počtů jedním voláním
		$cnt_defs = (int) ($cnt_row['cnt_defs'] ?? 0);                       // Počet vygenerovaných nepřímých vztahů tříd

		$btn_defs = new abstract_button('btn_diagram_derived_defs', 'Odvozené vztahy ({' . chr(36) . 'count}) →', 'page_link_diagram', '', 'btn-secondary'); // Tlačítko odvozených vztahů
		$btn_defs->set_href('index.php?page=page_meta_link_def&diagram_uuid=' . urlencode($update_guid)) // Odkaz do katalogu meta_link_def
			->set_vars(['count' => $cnt_defs]);                              // Dosazení počtu odvozených vztahů

		$btns = [$btn_defs->render()];                                       // Pole akčních tlačítek hlavičky

		if (! $this->is_readonly) {                                          // Tlačítko pro spuštění projekce a přepočtu sítě
			$btn_reb = new abstract_button('btn_rebuild_diagram', '↻ Přepočítat a promítnout síť', 'page_link_diagram'); // Tlačítko přepočtu
			$btn_reb->set_type('submit')                                     // Odeslání formuláře metodou POST
				->set_name_value('btn_rebuild_diagram', '1')                 // Jméno a hodnota pro process_save()
				->set_onclick('isFormDirty = false; this.form.noValidate = true;'); // Odeslání bez falešného dirty varování
			$btns[] = $btn_reb->render();                                    // Přidání tlačítka přepočtu
		}

		return implode("\n\t\t\t\t\t", $btns);                               // Spojení tlačítek hlavičky
	}

	/**
	 * Vykreslí v horní části detailu:
	 * 1. Integrovaný seznam orientovaných vztahů (hran v `link_diagram_edge`)
	 *    s možností přímého přidání z katalogu `meta_link_def` a odebrání hrany.
	 * 2. Vyhodnocenou topologii tříd (`dbo.f_resolve_link_diagram`) s uvedením
	 *    konkrétních použitých vztahů, vrcholových tříd, vnitrotřídních smyček
	 *    a případného zacyklení.
	 */
	protected function render_detail_top(): void {
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === '' OR $update_guid === 'NEW' OR ! is_guid($update_guid)) { // U nového neuloženého diagramu
			$msg_hint = htmlspecialchars($this->phrase('msg_new_diagram_hint', [], 'Tip: Nejprve uložte název a kód nového schématu sítě. Ihned po uložení se zde otevře výběr orientovaných vztahů (hran grafu) z katalogu Definice typů vazeb.')); // Nápověda
			echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$msg_hint}</div>\n"; // Výpis nápovědy
			return;                                                          // Ukončení
		}

		$dg_sql = guidliteral($update_guid);                                 // SQL literál originálu diagramu
		$edges = sqlarray_simple("EXEC dbo.page_link_diagram @subpage = 'edges', @diagram_uuid = {$dg_sql}"); // Zařazené hrany z link_diagram_edge
		$cls_tree = sqlarray_simple("EXEC dbo.page_link_diagram @subpage = 'topology', @diagram_uuid = {$dg_sql}"); // Topologie tříd

		if (! is_array($edges)) {                                            // Pojistka pole hran
			$edges = [];                                                     // Prázdné pole hran
		}
		if (! is_array($cls_tree)) {                                         // Pojistka pole topologie
			$cls_tree = [];                                                  // Prázdné pole topologie
		}

		// Mapa popisků hran podle dvojice (from_class_uuid, to_class_uuid) pro zobrazení u větví topologie
		$edge_via_map = [];                                                  // Mapa: [from_uuid_to_uuid => [popisky hran]]
		foreach ($edges as $ed) {                                            // Sběr popisků zařazených hran
			$pair_k = strtolower((string) $ed['from_class']) . '_' . strtolower((string) $ed['to_class']); // Klíč dvojice tříd
			$ed_lbl = (string) $ed['link_caption'] . ' [' . (string) $ed['link_code'] . ', ' . (string) $ed['direction_type'] . ']'; // Popisek hrany
			$edge_via_map[$pair_k][] = $ed_lbl;                              // Zařazení popisku hrany pod dvojici tříd
		}

		// Kontrola výskytu mezitřídního cyklu v topologii
		$has_cycle = false;                                                  // Příznak zjištěného cyklu
		foreach ($cls_tree as $ct_chk) {                                     // Kontrola všech uzlů topologie
			if (! empty($ct_chk['bad'])) {                                   // Nalezen cyklus
				$has_cycle = true;                                           // Označení cyklu
				break;                                                       // Ukončení smyčky
			}
		}

		if ($has_cycle) {                                                    // Výrazné červené varování při zacyklení grafu tříd
			$msg_cyc = htmlspecialchars($this->phrase('msg_diagram_cycle_banner', [], 'Pozor: Zvolená sada vztahů vytváří cyklus mezi logickými třídami. Acyklický graf nelze s cyklem promítnout – odeberte některou hranu tvořící smyčku.')); // Varování
			echo "<div class=\"msg-err\" style=\"margin-bottom: 14px;\">{$msg_cyc}</div>\n"; // Červený chybový pruh
		}

		// =====================================================================
		// 1. SEKCE: Vztahy (hrany) zařazené do schématu (tabulka link_diagram_edge)
		// =====================================================================
		$edge_cnt = count($edges);                                           // Počet aktuálně zařazených hran
		$hdr_edges = htmlspecialchars($this->phrase('hdr_diagram_edges', ['count' => $edge_cnt], 'Vztahy (hrany) zařazené do schématu ({' . chr(36) . 'count})')); // Nadpis sekce hran

		echo "<div style=\"margin-bottom: 18px; padding: 12px 14px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px;\">\n";
		echo "\t<div style=\"font-weight: bold; color: #004488; font-size: 13px; margin-bottom: 10px;\">{$hdr_edges}</div>\n";

		if ($edge_cnt === 0) {                                               // Pokud diagram ještě nemá žádné hrany
			$msg_empty = htmlspecialchars($this->phrase('msg_diagram_no_edges', [], 'V tomto schématu sítě zatím nejsou zařazeny žádné vztahy. Vyberte orientované vztahy v seznamu níže a klikněte na „+ Přidat vztah“.')); // Výzva
			echo "\t<div class=\"msg-info\" style=\"margin-bottom: 12px; font-weight: normal; font-size: 12px;\">{$msg_empty}</div>\n"; // Modrý box
		} else {
			$th_cls  = htmlspecialchars($this->phrase('th_edge_classes', [], 'Zdrojová třída → Cílová třída')); // Záhlaví tříd
			$th_lnk  = htmlspecialchars($this->phrase('th_edge_link', [], 'Vztah (název a kód)'));              // Záhlaví vztahu
			$th_dir  = htmlspecialchars($this->phrase('th_edge_dir', [], 'Směr'));                              // Záhlaví směru
			$th_act  = htmlspecialchars($this->phrase('th_edge_action', [], 'Akce'));                           // Záhlaví akce
			$act_th_html = ! $this->is_readonly ? "<th style=\"width: 90px; text-align: center;\">{$th_act}</th>" : ''; // Sloupec akce

			echo "\t<table class=\"md-table\" style=\"margin-bottom: 12px; background-color: #fff;\">\n";
			echo "\t\t<thead><tr><th>{$th_cls}</th><th>{$th_lnk}</th><th style=\"width: 55px; text-align: center;\">{$th_dir}</th>{$act_th_html}</tr></thead>\n";
			echo "\t\t<tbody>\n";

			foreach ($edges as $ed) {                                        // Výpis zařazených orientovaných hran
				$ld_uuid = (string) $ed['link_def_uuid'];                    // UUID definice vztahu
				$fc_cap  = htmlspecialchars((string) $ed['from_class_caption']); // Název zdrojové třídy
				$fc_name = htmlspecialchars((string) $ed['from_class_name']);    // Kód zdrojové třídy
				$tc_cap  = htmlspecialchars((string) $ed['to_class_caption']);   // Název cílové třídy
				$tc_name = htmlspecialchars((string) $ed['to_class_name']);      // Kód cílové třídy
				$l_cap   = htmlspecialchars((string) $ed['link_caption']);       // Lokalizovaný název vztahu
				$l_code  = htmlspecialchars((string) $ed['link_code']);          // Kód vztahu
				$dir_raw = (string) $ed['direction_type'];                       // Směr vztahu (P/R/S)
				$dir_cls = ($dir_raw === 'R') ? 'ssc-badge-d' : 'ssc-badge-f';   // Barevné odlišení P vs. R
				$safe_dir = htmlspecialchars($dir_raw);                          // Ošetřený směr

				$act_td_html = '';                                           // Buňka s tlačítkem Odebrat
				if (! $this->is_readonly) {                                  // V editačním režimu povolíme odebrání hrany
					$btn_rem = new abstract_button('btn_remove_edge', 'Odebrat', 'page_link_diagram', '', 'btn-danger'); // Tlačítko odebrání
					$btn_rem->set_type('submit')                             // Odeslání formuláře POSTem
						->set_name_value('btn_remove_edge', $ld_uuid)        // Předání UUID odebíraného vztahu v hodnotě tlačítka
						->set_onclick('isFormDirty = false; this.form.noValidate = true;') // Vypnutí dirty varování i HTML5 validace
						->set_style('padding: 4px 8px; font-size: 11px;');   // Kompaktní rozměr v řádku tabulky
					$act_td_html = "<td style=\"text-align: center;\">" . $btn_rem->render() . "</td>"; // Buňka akce
				}

				echo "\t\t\t<tr>\n";
				echo "\t\t\t\t<td><strong>{$fc_cap}</strong> <span style=\"color:#2563eb; font-weight:bold;\">→</span> <strong>{$tc_cap}</strong><div style=\"font-family: monospace; font-size: 11px; color: #64748b;\">{$fc_name} → {$tc_name}</div></td>\n"; // Dvojice tříd
				echo "\t\t\t\t<td>{$l_cap}<div style=\"font-family: monospace; font-size: 11px; color: #64748b;\">{$l_code}</div></td>\n"; // Název a kód vztahu
				echo "\t\t\t\t<td style=\"text-align: center;\"><span class=\"ssc-badge {$dir_cls}\" style=\"margin-left:0;\">{$safe_dir}</span></td>\n"; // Směr vztahu
				if ($act_td_html !== '') {                                   // Výpis buňky akce
					echo "\t\t\t\t{$act_td_html}\n";                       // Buňka s tlačítkem Odebrat
				}
				echo "\t\t\t</tr>\n";
			}

			echo "\t\t</tbody>\n\t</table>\n";
		}

		// Ovládací prvek pro přímé přidání orientovaného vztahu z katalogu Definice typů vazeb (meta_link_def)
		if (! $this->is_readonly) {                                          // Výběr hran pouze v editačním režimu
			$inc_fk_bit = $this->include_fk ? 1 : 0;                         // Parametr zahrnutí technických 1:N FK vztahů
			$avail_rows = sqlarray_simple("EXEC dbo.page_link_diagram @subpage = 'available_defs', @diagram_uuid = {$dg_sql}, @include_fk = {$inc_fk_bit}"); // Dostupné vztahy

			$avail_items = [];                                               // Pole dostupných vztahů pro JS filtraci a <select>
			$opts_html = '<option value="">' . htmlspecialchars($this->phrase('opt_select_edge', [], '--- Vyberte orientovaný vztah k přidání ---')) . '</option>'; // Výchozí prázdná volba

			if (is_array($avail_rows)) {                                     // Sestavení položek výběru vztahů
				foreach ($avail_rows as $ar) {                               // Průchod dostupnými orientovanými vztahy
					$u_str = (string) $ar['link_def_uuid'];                  // UUID definice vztahu
					$fc_c  = (string) $ar['from_class_caption'];             // Název zdrojové třídy
					$tc_c  = (string) $ar['to_class_caption'];               // Název cílové třídy
					$lc_c  = (string) $ar['link_caption'];                   // Název vztahu
					$l_cd  = (string) $ar['link_code'];                      // Technický kód vztahu
					$dir_c = (string) $ar['direction_type'];                 // Směr vztahu (P/R/S)
					$label = "{$fc_c} → {$tc_c} : {$lc_c} [{$l_cd}, {$dir_c}]"; // Plný přehledný popisek hrany
					$search_txt = mb_strtolower($label . ' ' . (string) $ar['from_class_name'] . ' ' . (string) $ar['to_class_name'], 'UTF-8'); // Text pro rychlé filtrování

					$avail_items[] = [                                       // Záznam pro JS filtr roletky
						'uuid'   => $u_str,
						'label'  => $label,
						'search' => $search_txt
					];
					$opts_html .= '<option value="' . htmlspecialchars($u_str) . '">' . htmlspecialchars($label) . '</option>'; // Položka selectu
				}
			}

			$lbl_add_sel = htmlspecialchars($this->phrase('lbl_add_edge_select', [], 'Přidat orientovaný vztah z katalogu (Definice typů vazeb):')); // Popisek
			$ph_flt_edg  = htmlspecialchars($this->phrase('ph_filter_edges', [], 'Filtrovat dostupné vztahy (název třídy nebo kód)...')); // Placeholder filtru
			$lbl_show_fk = htmlspecialchars($this->phrase('lbl_show_fk_defs', [], 'Zobrazit i technické 1:N FK vztahy')); // Popisek přepínače FK
			$chk_fk      = $this->include_fk ? 'checked' : '';               // Stav zaškrtnutí FK vztahů

			$btn_add = new abstract_button('btn_add_edge', '+ Přidat vztah', 'page_link_diagram'); // Tlačítko přidání vztahu
			$btn_add->set_type('submit')                                     // Odeslání POSTem
				->set_name_value('btn_add_edge', '1')                        // Akce btn_add_edge pro process_save()
				->set_onclick('isFormDirty = false; this.form.noValidate = true;') // Vypnutí dirty hlášky
				->set_style('padding: 7px 12px; white-space: nowrap;');      // Kompaktní styl
			$btn_add_html = $btn_add->render();                              // HTML tlačítka přidání

			$toggle_fk_base = 'index.php?page=page_link_diagram&update_guid=' . urlencode($update_guid); // Základní URL pro přepnutí FK
			$js_fk_url = addslashes($toggle_fk_base);                        // Ošetřená URL pro JS handler
			$json_avail = json_encode($avail_items);                         // JSON seznam dostupných vztahů pro klientský filtr
			$js_empty_opt = addslashes($this->phrase('opt_select_edge', [], '--- Vyberte orientovaný vztah k přidání ---')); // Výchozí volba

			echo <<<HTML
	<div style="padding-top: 8px; border-top: 1px dashed #cbd5e1;">
		<div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px; margin-bottom: 6px;">
			<label for="dg-add-edge-select" style="font-size: 12px; font-weight: bold; color: #334155;">{$lbl_add_sel}</label>
			<label style="font-size: 11px; color: #475569; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; user-select: none;">
				<input type="checkbox" {$chk_fk} onchange="var u='{$js_fk_url}'+(this.checked?'&include_fk=1':''); if(window.loadDetailPanel){loadDetailPanel(u);}else{window.location.href=u;}"> {$lbl_show_fk}
			</label>
		</div>
		<input type="text" id="dg-edge-filter" placeholder="{$ph_flt_edg}" oninput="isFormDirty = false;" style="width: 100%; padding: 5px 8px; margin-bottom: 6px; box-sizing: border-box; font-size: 12px; border: 1px solid #cbd5e1; border-radius: 3px;">
		<div style="display: flex; gap: 8px; align-items: center;">
			<select id="dg-add-edge-select" name="add_link_def_uuid" onchange="isFormDirty = false;" style="flex: 1; padding: 6px; box-sizing: border-box; font-size: 12px;">
				{$opts_html}
			</select>
			{$btn_add_html}
		</div>
	</div>
	<script>
		(function() {
			const allItems = {$json_avail};
			const emptyLbl = '{$js_empty_opt}';
			const fltInp = document.getElementById('dg-edge-filter');
			const selEl  = document.getElementById('dg-add-edge-select');
			if (!fltInp ? true : !selEl) return;

			fltInp.addEventListener('input', function() {
				const term = (this.value ? this.value : '').trim().toLowerCase();
				const prev = selEl.value ? selEl.value : '';
				while (selEl.options.length > 0) {
					selEl.remove(0);
				}
				const defOpt = document.createElement('option');
				defOpt.value = '';
				defOpt.textContent = emptyLbl;
				selEl.appendChild(defOpt);

				let matchCount = 0;
				let firstMatchVal = '';
				allItems.forEach(function(it) {
					if (term === '' ? true : it.search.indexOf(term) !== -1) {
						const opt = document.createElement('option');
						opt.value = it.uuid;
						opt.textContent = it.label;
						selEl.appendChild(opt);
						matchCount++;
						if (firstMatchVal === '') {
							firstMatchVal = it.uuid;
						}
					}
				});

				if (prev !== '' && Array.from(selEl.options).some(function(o) { return o.value === prev; })) {
					selEl.value = prev;
				} else if (matchCount === 1 && firstMatchVal !== '') {
					selEl.value = firstMatchVal;
				}
			});
		})();
	</script>
HTML;
		}

		echo "</div>\n";

		// =====================================================================
		// 2. SEKCE: Vyhodnocená topologie tříd v heterogenní síti
		// =====================================================================
		if (empty($cls_tree)) {                                              // Bez hran nevykreslujeme prázdný blok topologie
			return;                                                          // Ukončení
		}

		$hdr_tree = htmlspecialchars($this->phrase('hdr_diagram_class_topology', [], 'Topologie tříd v heterogenní síti (vrcholové třídy → podřízené třídy):')); // Nadpis topologie
		$lbl_top  = htmlspecialchars($this->phrase('badge_top_class', [], 'Vrcholová třída')); // Štítek vrcholové třídy
		$lbl_self = htmlspecialchars($this->phrase('badge_self_loop', [], 'Vnitrotřídní průchod (self-referencing)')); // Štítek rekurze
		$lbl_cyc  = htmlspecialchars($this->phrase('badge_cycle_error', [], 'Zacyklení tříd!')); // Štítek chyby cyklu
		$lbl_via  = htmlspecialchars($this->phrase('lbl_via_edges', [], 'přes')); // Spojka pro popisek použité hrany

		echo "<div style=\"margin-bottom: 18px; padding: 10px 14px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px;\">\n";
		echo "\t<div style=\"font-weight: bold; color: #004488; font-size: 13px; margin-bottom: 8px;\">{$hdr_tree}</div>\n";

		foreach ($cls_tree as $ct) {                                         // Výpis jednotlivých úrovní tříd v diagramu
			$lvl = (int) ($ct['level'] ?? 0);                                // Úroveň zanoření třídy v diagramu
			$pad_px = $lvl * 22;                                             // Odsazení zleva v pixelech
			$c_name = htmlspecialchars((string) $ct['class_name']);          // Technický kód třídy
			$c_cap  = htmlspecialchars((string) $ct['class_caption']);       // Lokalizovaný název třídy
			$is_bad = ! empty($ct['bad']);                                   // Zda uzel způsobuje mezitřídní cyklus
			$has_self = ! empty($ct['has_self_loop']);                       // Zda má třída vnitrotřídní vztah sama se sebou

			$from_id = strtolower((string) ($ct['from_id'] ?? ''));          // UUID nadřízené třídy na této větvi
			$node_id = strtolower((string) ($ct['node_id'] ?? ''));          // UUID aktuální třídy na této větvi
			$via_html = '';                                                  // Volitelný popis použité hrany z rodiče
			if ($from_id !== '' AND isset($edge_via_map[$from_id . '_' . $node_id])) { // Dohledání konkrétní hrany
				$via_str = htmlspecialchars(implode(', ', $edge_via_map[$from_id . '_' . $node_id])); // Ošetřené názvy hran
				$via_html = " <span style=\"font-size: 11px; color: #0369a1;\">({$lbl_via}: {$via_str})</span>"; // Výpis hrany
			}

			$prefix = ($lvl === 0) ? '● ' : '↳ ';                            // Symbol kořene nebo návazného kroku
			$badges = '';                                                    // Štítky vlastností uzlu v diagramu
			if ($lvl === 0) {                                                // Vrcholová třída na úrovni 0
				$badges .= " <span class=\"ssc-badge ssc-badge-f\">{$lbl_top}</span>"; // Modrý štítek vrcholové třídy
			}
			if ($has_self) {                                                 // Povolený vnitrotřídní průchod (např. Aplikace -> Aplikace)
				$badges .= " <span class=\"ssc-badge ssc-badge-d\">↻ {$lbl_self}</span>"; // Žlutý štítek vnitrotřídní rekurze
			}
			if ($is_bad) {                                                   // Detekováno zakázané zacyklení mezi třídami
				$badges .= " <span class=\"ssc-badge ssc-badge-r\">⚠ {$lbl_cyc}</span>"; // Červený štítek zacyklení
			}

			echo "\t<div style=\"padding: 3px 0 3px {$pad_px}px; font-size: 13px;\">{$prefix}<strong>{$c_cap}</strong> <span style=\"font-family: monospace; font-size: 11px; color: #64748b;\">({$c_name})</span>{$via_html}{$badges}</div>\n"; // Řádek třídy
		}

		echo "</div>\n";
	}
}