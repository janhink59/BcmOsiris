<?php
/**
 * =============================================================================
 * Verze: 2026-11-11 22:00
 * Soubor: page_link_diagram.php
 * Třída: page_link_diagram
 * Účel: Správa schémat (diagramů) heterogenních sítí vztahů (tabulka link_diagram).
 *       Umožňuje skládat orientované vztahy (meta_link_def) do diagramu sítě,
 *       kontrolovat acykličnost a vrcholové třídy přes dbo.f_resolve_link_diagram
 *       a spouštět projekci (materializaci) nepřímých vztahů do meta_link_def
 *       a nepřímých vazeb mezi objekty do tabulky link (dbo.p_rebuild_link_diagram).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_link_diagram`.
 * - Dědí z `abstract_page_master_detail` a pracuje s logickou třídou `'link_diagram'`.
 * - Volá proceduru `dbo.p_rebuild_link_diagram` (`p_sync_derived_links.sql`)
 *   a funkci `dbo.f_resolve_link_diagram` (`f_resolve_link_diagram.sql`).
 * =============================================================================
 */

declare(strict_types=1);

class page_link_diagram extends abstract_page_master_detail {

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'link_diagram';                                  // Logická třída pro entity_manager
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových diagramů sítě
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
	 * Zpracuje případný požadavek na přepočet a projekci nepřímých vztahů a vazeb diagramu (`btn_rebuild_diagram`).
	 */
	protected function process_save(): void {
		if (! $this->is_readonly AND isset($_POST['btn_rebuild_diagram'])) { // Stisk tlačítka Přepočítat a promítnout síť
			$upd_guid = trim((string) getinput('update_guid'));              // UUID vybraného diagramu
			if ($upd_guid !== '' AND $upd_guid !== 'NEW' AND is_guid($upd_guid)) { // Platné UUID existujícího diagramu
				$safe_dg = guidliteral($upd_guid);                           // SQL literál originálu diagramu
				$org_sql = guidliteral(get_session_org());                   // SQL literál aktivní organizace
				sqlrun("BEGIN TRAN; EXEC dbo.p_rebuild_link_diagram @diagram_uuid = {$safe_dg}, @org_uuid = {$org_sql}; COMMIT;"); // Přepočet sítě
				$url_suffix = $this->get_context_url_suffix();               // Kontextové parametry URL
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
	 * Vloží do hlavičky detailu tlačítka pro správu spojnic diagramu (`page_link`),
	 * prohlížení vygenerovaných nepřímých vztahů (`page_meta_link_def`) a přepočet sítě (`btn_rebuild_diagram`).
	 */
	protected function render_detail_header_buttons(string $update_guid): string { // Akční tlačítka v hlavičce detailu
		if ($update_guid === '' OR $update_guid === 'NEW') {                 // U neuloženého záznamu tlačítka nezobrazujeme
			return '';                                                       // Prázdný výstup
		}

		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace
		$dg_sql = guidliteral($update_guid);                                 // SQL literál originálu diagramu

		$r_edges = sqlfirstrow("
			SELECT COUNT(1) AS cnt
			FROM link l
			JOIN meta_link_def mld ON mld.original = l.link_def AND mld.link_code = 'diagram_includes_link_def' AND mld.record_type = 'A' AND mld.removed = 0
			WHERE l.from_object = {$dg_sql}
			  AND l.object_owner IN ({$org_sql}, 0x00)
			  AND l.record_type = 'A'
			  AND l.removed = 0
		");                                                                  // Počet přímých spojnic zařazených do diagramu
		$r_defs = sqlfirstrow("SELECT COUNT(1) AS cnt FROM meta_link_def WHERE diagram_uuid = {$dg_sql} AND is_derived = 1 AND object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0"); // Počet odvozených vztahů
		$r_lnks = sqlfirstrow("SELECT COUNT(1) AS cnt FROM link WHERE diagram_uuid = {$dg_sql} AND is_derived = 1 AND object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0"); // Počet odvozených vazeb uzlů

		$cnt_edges = (int) ($r_edges['cnt'] ?? 0);                           // Počet přímých spojnic diagramu
		$cnt_defs  = (int) ($r_defs['cnt'] ?? 0);                            // Počet vygenerovaných nepřímých vztahů
		$cnt_lnks  = (int) ($r_lnks['cnt'] ?? 0);                            // Počet vygenerovaných nepřímých vazeb uzlů

		$btn_edges = new abstract_button('btn_diagram_edges', 'Spojnice a vazby sítě ({' . chr(36) . 'edges} / {' . chr(36) . 'links}) →', 'page_link_diagram', '', 'btn-secondary'); // Tlačítko spojnic
		$btn_edges->set_href('index.php?page=page_link&diagram_uuid=' . urlencode($update_guid)) // Odkaz na vazby diagramu
			->set_vars(['edges' => $cnt_edges, 'links' => $cnt_lnks]);       // Dosazení počtů do popisku

		$btn_defs = new abstract_button('btn_diagram_derived_defs', 'Odvozené vztahy ({' . chr(36) . 'count}) →', 'page_link_diagram', '', 'btn-secondary'); // Tlačítko odvozených vztahů
		$btn_defs->set_href('index.php?page=page_meta_link_def&diagram_uuid=' . urlencode($update_guid)) // Odkaz na meta_link_def
			->set_vars(['count' => $cnt_defs]);                              // Dosazení počtu odvozených vztahů

		$btns = [$btn_edges->render(), $btn_defs->render()];                 // Pole navigačních tlačítek

		if (! $this->is_readonly) {                                          // Tlačítko pro spuštění projekce a přepočtu sítě
			$btn_reb = new abstract_button('btn_rebuild_diagram', '↻ Přepočítat a promítnout síť', 'page_link_diagram'); // Tlačítko přepočtu
			$btn_reb->set_type('submit')                                     // Odeslání formuláře metodou POST
				->set_name_value('btn_rebuild_diagram', '1')                 // Jméno a hodnota pro process_save()
				->set_onclick('isFormDirty = false;');                       // Vypnutí varování neuložených změn
			$btns[] = $btn_reb->render();                                    // Přidání tlačítka přepočtu
		}

		return implode("\n\t\t\t\t\t", $btns);                               // Spojení tlačítek hlavičky
	}

	/**
	 * Vykreslí v horní části detailu přehled topologicky seřazených tříd v diagramu
	 * (vyhodnocených přes `dbo.f_resolve_link_diagram`), vyznačí vrcholové třídy,
	 * povolené vnitrotřídní реkurze (`from_class = to_class`) a případné zacyklení.
	 */
	protected function render_detail_top(): void {
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === '' OR $update_guid === 'NEW' OR ! is_guid($update_guid)) { // U nového neuloženého diagramu
			$msg_hint = htmlspecialchars($this->phrase('msg_new_diagram_hint', [], 'Tip: Po uložení schématu sítě k němu tlačítkem „Spojnice a vazby sítě“ přiřaďte orientované vztahy (vztah diagram_includes_link_def) a stiskněte „Přepočítat a promítnout síť“.')); // Nápověda
			echo "<div style=\"color: #475569; font-size: 12px; margin-bottom: 12px;\">{$msg_hint}</div>\n"; // Výpis nápovědy
			return;                                                          // Ukončení
		}

		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace
		$lang_sql = charliteral(get_session_lang(), 2);                      // SQL literál aktivního jazyka
		$dg_sql = guidliteral($update_guid);                                 // SQL literál originálu diagramu

		// Vyhodnocení topologického průchodu třídami v diagramu přes dbo.f_resolve_link_diagram
		$cls_tree = sqlarray_simple("
			SET NOCOUNT ON;
			DECLARE @edges TABLE (
				from_class uniqueidentifier NOT NULL,
				to_class uniqueidentifier NOT NULL,
				link_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL
			);

			INSERT INTO @edges (from_class, to_class, link_code)
			SELECT DISTINCT mld.from_class, mld.to_class, mld.link_code
			FROM link l
			JOIN meta_link_def mld_inc
				ON mld_inc.original = l.link_def
				AND mld_inc.link_code = 'diagram_includes_link_def'
				AND mld_inc.record_type = 'A'
				AND mld_inc.removed = 0
			JOIN meta_link_def mld
				ON mld.original = l.to_object
				AND mld.object_owner IN ({$org_sql}, 0x00)
				AND mld.record_type = 'A'
				AND mld.removed = 0
				AND mld.inactive = 0
				AND mld.is_derived = 0
			WHERE l.from_object = {$dg_sql}
			  AND l.object_owner IN ({$org_sql}, 0x00)
			  AND l.record_type = 'A'
			  AND l.removed = 0
			  AND l.inactive = 0;

			DECLARE @inp tt_resolve_link_diagram;

			INSERT INTO @inp (node_id, from_id, sort_order)
			SELECT DISTINCT LOWER(CAST(c.original AS varchar(36))), '', c.class_name
			FROM (
				SELECT from_class AS cls_uuid FROM @edges
				UNION
				SELECT to_class AS cls_uuid FROM @edges
			) u
			JOIN meta_class c ON c.original = u.cls_uuid AND c.record_type = 'A' AND c.removed = 0;

			INSERT INTO @inp (node_id, from_id, sort_order)
			SELECT DISTINCT LOWER(CAST(e.to_class AS varchar(36))), LOWER(CAST(e.from_class AS varchar(36))), c.class_name
			FROM @edges e
			JOIN meta_class c ON c.original = e.to_class AND c.record_type = 'A' AND c.removed = 0
			WHERE e.from_class <> e.to_class;

			SELECT
				r.node_id,
				r.from_id,
				r.sort_order,
				r.level,
				r.bad,
				r.circular,
				r.hidden_root,
				mc.class_name,
				COALESCE(NULLIF(l.caption, ''), mc.caption, mc.class_name) AS class_caption,
				CASE WHEN EXISTS (SELECT 1 FROM @edges s WHERE s.from_class = mc.original AND s.to_class = mc.original) THEN 1 ELSE 0 END AS has_self_loop
			FROM dbo.f_resolve_link_diagram(@inp) r
			JOIN meta_class mc ON LOWER(CAST(mc.original AS varchar(36))) = r.node_id AND mc.record_type = 'A' AND mc.removed = 0
			LEFT JOIN meta_class l ON l.original = mc.original AND l.record_type = 'L' AND l.[language] = {$lang_sql} AND l.removed = 0 AND l.object_owner IN ({$org_sql}, 0x00)
			WHERE r.hidden_root = 0
			ORDER BY r.sort_order ASC;
		");                                                                  // Načtení stromu tříd diagramu

		if (! is_array($cls_tree) OR empty($cls_tree)) {                     // Pokud diagram zatím neobsahuje žádné spojnice
			$msg_empty = htmlspecialchars($this->phrase('msg_diagram_no_edges', [], 'V tomto schématu sítě zatím nejsou zařazeny žádné orientované vztahy. Klikněte na „Spojnice a vazby sítě“ v záhlaví detailu a přidejte vztahy pomocí „diagram_includes_link_def“.')); // Výzva
			echo "<div class=\"msg-info\" style=\"margin-bottom: 14px; font-weight: normal; font-size: 12px;\">{$msg_empty}</div>\n"; // Modrý box
			return;                                                          // Ukončení
		}

		$hdr_tree = htmlspecialchars($this->phrase('hdr_diagram_class_topology', [], 'Topologie tříd v heterogenní síti (vrcholové třídy → podřízené třídy):')); // Nadpis topologie
		$lbl_top  = htmlspecialchars($this->phrase('badge_top_class', [], 'Vrcholová třída')); // Štítek vrcholové třídy
		$lbl_self = htmlspecialchars($this->phrase('badge_self_loop', [], 'Vnitrotřídní průchod (self-referencing)')); // Štítek rekurze
		$lbl_cyc  = htmlspecialchars($this->phrase('badge_cycle_error', [], 'Zacyklení tříd!')); // Štítek chyby cyklu

		echo "<div style=\"margin-bottom: 18px; padding: 10px 14px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px;\">\n";
		echo "\t<div style=\"font-weight: bold; color: #004488; font-size: 13px; margin-bottom: 8px;\">{$hdr_tree}</div>\n";

		foreach ($cls_tree as $ct) {                                         // Výpis jednotlivých úrovní tříd v diagramu
			$lvl = (int) ($ct['level'] ?? 0);                                // Úroveň zanoření třídy v diagramu
			$pad_px = $lvl * 22;                                             // Odsazení zleva v pixelech
			$c_name = htmlspecialchars((string) $ct['class_name']);          // Technický kód třídy
			$c_cap  = htmlspecialchars((string) $ct['class_caption']);       // Lokalizovaný název třídy
			$is_bad = ! empty($ct['bad']);                                   // Zda uzel způsobuje mezitřídní cyklus
			$has_self = ! empty($ct['has_self_loop']);                       // Zda má třída vnitrotřídní vztah sama se sebou

			$prefix = ($lvl === 0) ? '● ' : '↳ ';                            // Symbol kořene nebo návazného kroku
			$badges = '';                                                    // Štítky vlastností uzlu v diagramu
			if ($lvl === 0) {                                                // Vrcholová třída na úrovni 0
				$badges .= " <span class=\"ssc-badge ssc-badge-f\">{$lbl_top}</span>"; // Modrý štítek vrcholové třídy
			}
			if ($has_self) {                                                 // Povolený vnitrotřídní průchod (např. Aplikace -> Aplikace)
				$badges .= " <span class=\"ssc-badge ssc-badge-d\">↻ {$lbl_self}</span>"; // Žlutý štítek vnitrotřídní реkurze
			}
			if ($is_bad) {                                                   // Detekováno zakázané zacyklení mezi třídami
				$badges .= " <span class=\"ssc-badge ssc-badge-r\">⚠ {$lbl_cyc}</span>"; // Červený štítek zacyklení
			}

			echo "\t<div style=\"padding: 3px 0 3px {$pad_px}px; font-size: 13px;\">{$prefix}<strong>{$c_cap}</strong> <span style=\"font-family: monospace; font-size: 11px; color: #64748b;\">({$c_name})</span>{$badges}</div>\n"; // Řádek třídy
		}

		echo "</div>\n";
	}
}