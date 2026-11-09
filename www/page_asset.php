<?php
/**
 * =============================================================================
 * Verze: 2026-11-09 18:30
 * Soubor: page_asset.php
 * Třída: page_asset
 * Účel: Správa prostorů (Okres -> Město -> Lokalita -> Budova -> Místnost při
 *       parametru &group=SPACE) a všech archetypů aktiv organizace (Fyzická
 *       aktiva, Hosté, Kabeláž, Dokumenty, Média, Data, Software, Aplikace,
 *       Služby, Služby typu Interface, Personál a Dodavatelé) nad STI tabulkou asset.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancována dynamicky z routeru `index.php` při `?page=page_asset`.
 * - Dědí ze stromové šablony `abstract_page_tree` (`abstract_page_tree.php`).
 * - V hlavičce detailu (`render_detail_header_buttons`) nabízí přímé prokliky
 *   do vazeb (`page_link`), hodnocení scénářů (`page_scenario_assessment`)
 *   a implementace protiopatření (`page_countermeasure_implementation`).
 *
 * Změny:
 * 2026-11-09 18:30 - Sekce názvů (caption, shortname) přesunuta na začátek detailu,
 *                    rozděleny zobrazované sloupce mezi Prostory (&group=SPACE)
 *                    a Evidence aktiv, roletka asset_archetype omezena na příslušnou
 *                    skupinu a roletka primary_asset_class filtrována pouze na
 *                    koncové třídy podřízené zvolenému archetypu.
 * =============================================================================
 */

declare(strict_types=1);

class page_asset extends abstract_page_tree {

	private string $group_mode = '';                                         // Režim zobrazení ('SPACE' = pouze prostory, '' = evidence aktiv)
	private string $filter_archetype = '__ALL__';                            // Zvolený filtr archetypu v levém panelu

	/** Mapa výchozích kódů tříd aktiv (asset_class.builtin_code) podle archetypu */
	private const ARCHETYPE_CLASS_MAP = [
		'DISTRICT'    => 'ac_district',
		'CITY'        => 'ac_city',
		'SITE'        => 'ac_site',
		'BUILDING'    => 'ac_building',
		'ROOM'        => 'ac_room',
		'PHYSICAL'    => 'ac_physical',
		'HOST'        => 'ac_host',
		'CABLING'     => 'ac_cabling',
		'DOCUMENT'    => 'ac_document',
		'MEDIA'       => 'ac_media',
		'DATA'        => 'ac_data',
		'SOFTWARE'    => 'ac_software',
		'APPLICATION' => 'ac_application',
		'SERVICE'     => 'ac_service',
		'INTERFACE'   => 'ac_interface',
		'PERSONNEL'   => 'ac_personnel',
		'SUPPLIER'    => 'ac_supplier'
	];

	/** Seznam prostorových archetypů pro režim &group=SPACE */
	private const SPACE_ARCHETYPES = ['DISTRICT', 'CITY', 'SITE', 'BUILDING', 'ROOM'];

	public function __construct() {
		parent::__construct();                                               // Inicializace správce frází a kontroly přístupu

		$this->class_name = 'asset';                                         // Bázová logická třída pro entity_manager
		$this->can_edit_structure = ! $this->is_readonly;                    // Povolení úpravy stromu a D&D
		$this->allow_insert = ! $this->is_readonly;                          // Povolení zakládání nových aktiv a prostorů

		$this->group_mode = strtoupper(trim((string) getinput('group')));    // Režim z URL (&group=SPACE)
		$req_arch = strtoupper(trim((string) getinput('archetype')));        // Filtr konkrétního archetypu z URL
		if ($req_arch !== '') {                                              // Pokud byl archetyp v URL předán
			$this->filter_archetype = $req_arch;                             // Uložení vybraného archetypu
		}

		$grp_pres = $this->phrase('grp_presentation', [], 'Prezentační texty, popis a poznámky'); // Sekce názvu a popisů
		$grp_id   = $this->phrase('grp_identification', [], 'Klasifikace, archetyp a identifikace'); // Sekce klasifikace a kódů
		$grp_loc  = $this->phrase('grp_placement_relations', [], 'Prostorové umístění, strom a přímé vazby (1:N)'); // Sekce umístění
		$grp_bia  = $this->phrase('grp_bia_risk_scores', [], 'Parametry dostupnosti (BIA) a agregované skóre rizik (0 až 100 %)'); // Sekce BIA a rizik
		$grp_perm = $this->phrase('grp_validity_protection', [], 'Platnost, ikona a ochrana záznamu'); // Sekce platnosti a ikony

		if ($this->group_mode === 'SPACE') {                                 // Režim Prostory a lokality (&group=SPACE)
			$this->storage_key_prefix = 'bcm_tree_asset_space';              // Klíč v sessionStorage pro strom prostorů
			$this->page_title = $this->phrase('page_title_space', [], 'Prostory a lokality (CRMM)'); // Titulek prostorů
			$this->tree_heading = $this->phrase('master_heading_space', [], 'Strom prostorů a lokalit'); // Nadpis stromu
			$this->tree_caption_header = $this->phrase('th_space_caption', [], 'Prostor / Lokalita'); // Záhlaví 1. sloupce
			$this->new_button_code = 'btn_new_space';                        // Kód tlačítka nového prostoru
			$this->new_button_default_caption = '+ Nový prostor / lokalita'; // Výchozí popisek tlačítka prostoru

			if ($this->filter_archetype !== '__ALL__' AND in_array($this->filter_archetype, self::SPACE_ARCHETYPES, true)) { // Konkrétní typ prostoru
				$this->master_where = "m.asset_archetype = " . charliteral($this->filter_archetype, 30); // Filtr na vybraný typ prostoru
			} else {
				$this->master_where = "m.asset_archetype IN ('DISTRICT', 'CITY', 'SITE', 'BUILDING', 'ROOM')"; // Všechny prostory
			}

			$this->form_groups = [                                           // Sekce formuláře pro Prostory a lokality (bez IT/BIA polí)
				$grp_pres => ['caption', 'shortname', 'description_text', 'help_text', 'note'], // Názvy a popisy na prvním místě
				$grp_id   => ['asset_archetype', 'primary_asset_class', 'builtin_code', 'external_code', 'owner_user_uuid'], // Klasifikace prostoru
				$grp_loc  => ['parent_uuid', 'sort_code', 'is_leaf', 'building_uuid'], // Strom prostorů a budova pro místnost
				$grp_bia  => ['inherent_risk_score', 'residual_risk_score'], // Agregované riziko prostoru
				$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Ikona a platnost
			];                                                               // Konec definice skupin pro Prostory
		} else {
			$this->storage_key_prefix = 'bcm_tree_asset_inv';                // Klíč v sessionStorage pro evidenci aktiv
			$this->page_title = $this->phrase('page_title', [], 'Evidence aktiv (CRMM)'); // Titulek evidence aktiv
			$this->tree_heading = $this->phrase('master_heading', [], 'Strom a seznam aktiv'); // Nadpis stromu aktiv
			$this->tree_caption_header = $this->phrase('th_asset_caption', [], 'Aktivum / Služba'); // Záhlaví 1. sloupce
			$this->new_button_code = 'btn_new_asset';                        // Kód tlačítka nového aktiva
			$this->new_button_default_caption = '+ Nové aktivum';            // Výchozí popisek tlačítka aktiva

			if ($this->filter_archetype !== '__ALL__' AND isset(self::ARCHETYPE_CLASS_MAP[$this->filter_archetype]) AND ! in_array($this->filter_archetype, self::SPACE_ARCHETYPES, true)) { // Věcný archetyp
				$this->master_where = "m.asset_archetype = " . charliteral($this->filter_archetype, 30); // Filtr na vybraný archetyp
			} else {
				$this->master_where = "m.asset_archetype NOT IN ('DISTRICT', 'CITY', 'SITE', 'BUILDING', 'ROOM')"; // Všechna věcná aktiva mimo prostory
			}

			$this->form_groups = [                                           // Sekce formuláře pro Evidenci věcných aktiv
				$grp_pres => ['caption', 'shortname', 'description_text', 'help_text', 'note'], // Názvy a popisy na prvním místě
				$grp_id   => ['asset_archetype', 'primary_asset_class', 'builtin_code', 'inventory_number', 'external_code', 'owner_user_uuid'], // Klasifikace aktiva
				$grp_loc  => ['parent_uuid', 'sort_code', 'is_leaf', 'building_uuid', 'room_uuid', 'host_uuid', 'software_uuid', 'supplier_uuid'], // Umístění a vazby 1:N
				$grp_bia  => ['rto_hours', 'rpo_hours', 'confidentiality_score', 'integrity_score', 'availability_score', 'inherent_risk_score', 'residual_risk_score'], // BIA a skóre rizik
				$grp_perm => ['svg_icon', 'valid_from', 'valid_to', 'is_final', 'is_protected', 'inactive'] // Ikona a platnost
			];                                                               // Konec definice skupin pro Evidenci aktiv
		}

		$this->tree_extra_columns = [                                        // Doplňkové sloupce v tabulce stromu
			'asset_archetype' => [
				'header' => $this->phrase('th_archetype', [], 'Archetyp'),   // Záhlaví sloupce archetypu
				'width'  => '85px',                                          // Šířka sloupce
				'align'  => 'center'                                         // Zarovnání na střed
			],
			'residual_risk_score' => [
				'header' => $this->phrase('th_res_risk', [], 'Rez. riz.'),   // Záhlaví zbytkového rizika
				'width'  => '65px',                                          // Šířka sloupce
				'align'  => 'right',                                         // Zarovnání doprava
				'bold'   => true                                             // Tučné zvýraznění rizika
			]
		];                                                                   // Konec definice doplňkových sloupců
	}

	/**
	 * Rozšíří kontextový přívažek URL o parametry `group` a `archetype`.
	 */
	protected function get_context_url_suffix(): string {
		$suffix = parent::get_context_url_suffix();                          // Základní kontextové parametry z předka
		if ($this->group_mode !== '' AND ! str_contains($suffix, '&group=')) { // Zachování režimu group=SPACE
			$suffix .= '&group=' . urlencode($this->group_mode);             // Připojení parametru group
		}
		if ($this->filter_archetype !== '' AND $this->filter_archetype !== '__ALL__' AND ! str_contains($suffix, '&archetype=')) { // Zachování archetypu
			$suffix .= '&archetype=' . urlencode($this->filter_archetype);   // Připojení parametru archetype
		}
		return $suffix;                                                      // Vrácení přívažku URL
	}

	/**
	 * Rozšíří skrytá pole formuláře o parametry `group` a `archetype`.
	 */
	protected function get_context_hidden_inputs(): string {
		$inputs = parent::get_context_hidden_inputs();                       // Základní skrytá pole z předka
		if ($this->group_mode !== '') {                                      // Skryté pole pro group
			$inputs .= "\n\t\t\t<input type=\"hidden\" name=\"group\" value=\"" . htmlspecialchars($this->group_mode) . "\">"; // Pole group
		}
		if ($this->filter_archetype !== '' AND $this->filter_archetype !== '__ALL__') { // Skryté pole pro archetype
			$inputs .= "\n\t\t\t<input type=\"hidden\" name=\"archetype\" value=\"" . htmlspecialchars($this->filter_archetype) . "\">"; // Pole archetype
		}
		return $inputs;                                                      // Vrácení skrytých polí
	}

	/**
	 * Dohledá originální UUID výchozí koncové třídy aktiv (`asset_class.original`) podle kódu archetypu.
	 */
	private function resolve_default_asset_class_uuid(string $archetype): string { // Zjištění výchozí třídy aktiv
		$safe_arch = charliteral(strtoupper($archetype), 30);                // SQL literál archetypu
		$rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'asset_class_by_archetype', @param_code = {$safe_arch}"); // Koncové třídy archetypu
		if (is_array($rows) AND ! empty($rows)) {                            // Pokud existuje koncová třída v podstromu archetypu
			return (string) ($rows[0]['original'] ?? '');                    // Vrátíme první koncovou třídu daného archetypu
		}
		return '';                                                           // Prázdné UUID
	}

	/**
	 * Zkontroluje povinné prostorové umístění a synchronizuje `primary_asset_class` a `building_uuid` před uložením.
	 */
	protected function process_save(): void {
		if (isset($_POST['btn_save']) OR isset($_POST['btn_save_draft']) OR isset($_POST['btn_forward_approval'])) { // Při ukládání záznamu
			$arch = strtoupper(trim((string) ($_POST['asset_archetype'] ?? ($this->group_mode === 'SPACE' ? 'ROOM' : 'PHYSICAL')))); // Zvolený archetyp
			$pac = trim((string) ($_POST['primary_asset_class'] ?? ''));     // Zvolená primární třída aktiva

			if ($pac === '') {                                               // Pokud uživatel nevybral primární třídu aktiv
				$def_pac = $this->resolve_default_asset_class_uuid($arch);   // Odvození výchozí koncové třídy podle archetypu
				if ($def_pac !== '') {                                       // Pokud výchozí třída v katalogu existuje
					$_POST['primary_asset_class'] = $def_pac;                // Doplnění do $_POST před voláním entity_manageru
				}
			}

			// U místnosti (ROOM) synchronizujeme building_uuid a parent_uuid
			if ($arch === 'ROOM') {                                          // Speciální ošetření pro Místnost
				$bld = trim((string) ($_POST['building_uuid'] ?? ''));       // Zadaná budova
				$par = trim((string) ($_POST['parent_uuid'] ?? ''));         // Zadaný nadřízený uzel ve stromu prostorů
				if ($bld === '' AND $par !== '' AND is_guid($par)) {         // Pokud je vyplněn rodič ve stromu, ověříme zda jde o budovu
					$p_row = sqlfirstrow("SELECT TOP 1 asset_archetype, building_uuid FROM asset WHERE original = " . guidliteral($par) . " AND record_type = 'A' AND removed = 0"); // Rodič
					if (! empty($p_row)) {                                   // Pokud nadřízený prostor existuje
						if ((string) $p_row['asset_archetype'] === 'BUILDING') { // Rodič je přímo budova
							$_POST['building_uuid'] = $par;                  // Nastavení budovy podle rodiče
							$bld = $par;                                     // Aktualizace lokální proměnné
						} elseif (! empty($p_row['building_uuid'])) {        // Rodič je podřízená místnost v budově
							$_POST['building_uuid'] = (string) $p_row['building_uuid']; // Převzetí budovy od nadřízené místnosti
							$bld = (string) $p_row['building_uuid'];         // Aktualizace lokální proměnné
						}
					}
				} elseif ($bld !== '' AND $par === '') {                     // Pokud je vybrána budova, ale není vyplněn rodič ve stromu
					$_POST['parent_uuid'] = $bld;                            // Zařazení místnosti pod budovu i ve stromu prostorů
				}
			}

			// Validace povinného umístění v budově (pro ROOM a CABLING) a v místnosti (pro PHYSICAL, HOST, DOCUMENT, MEDIA)
			if (in_array($arch, ['ROOM', 'CABLING'], true) AND trim((string) ($_POST['building_uuid'] ?? '')) === '') { // Chybí budova
				$this->save_error_message = $this->phrase('err_building_mandatory', [], 'Pro záznam typu Místnost (ROOM) a Kabeláž (CABLING) musí být povinně vybrána Budova (building_uuid).'); // Chyba
				return;                                                      // Zastavení ukládání se zachováním formuláře
			}
			if (in_array($arch, ['PHYSICAL', 'HOST', 'DOCUMENT', 'MEDIA'], true) AND trim((string) ($_POST['room_uuid'] ?? '')) === '') { // Chybí místnost
				$this->save_error_message = $this->phrase('err_room_mandatory', [], 'Pro fyzické aktivum, hostitelský počítač, dokument a médium musí být povinně vybrána Místnost (room_uuid).'); // Chyba
				return;                                                      // Zastavení ukládání se zachováním formuláře
			}
		}

		parent::process_save();                                              // Standardní uložení záznamu v předkovi
	}

	/**
	 * Vykreslí v horní části levého panelu roletku pro filtrování podle archetypu a tlačítko pro založení záznamu.
	 */
	protected function render_master_top(): void {
		$lbl_all = ($this->group_mode === 'SPACE')
			? htmlspecialchars($this->phrase('opt_all_spaces', [], '--- Všechny prostory a lokality ---'))
			: htmlspecialchars($this->phrase('opt_all_assets', [], '--- Všechny archetypy aktiv (mimo prostory) ---')); // Výchozí volba
		$sel_all = ($this->filter_archetype === '__ALL__') ? 'selected' : ''; // Označení volby Vše
		$options_html = "<option value=\"__ALL__\" {$sel_all}>{$lbl_all}</option>"; // První položka roletky

		$ct_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'codetable', @param_code = 'asset_archetype'"); // Načtení archetypů
		if (is_array($ct_rows)) {                                            // Průchod položkami číselníku asset_archetype
			foreach ($ct_rows as $r) {                                       // Zpracování položky archetypu
				$v_code = strtoupper((string) $r['value_code']);             // Kód archetypu
				$in_space = in_array($v_code, self::SPACE_ARCHETYPES, true); // Zda jde o prostorový archetyp
				if (($this->group_mode === 'SPACE' AND ! $in_space) OR ($this->group_mode !== 'SPACE' AND $in_space)) { // Filtrace dle režimu stránky
					continue;                                                // Přeskočení archetypu z jiné skupiny
				}
				$v_cap = htmlspecialchars((string) $r['caption']);           // Lokalizovaný název archetypu
				$safe_c = htmlspecialchars($v_code);                         // Ošetřený kód archetypu
				$sel = ($v_code === $this->filter_archetype) ? 'selected' : ''; // Označení aktivního archetypu
				$options_html .= "<option value=\"{$safe_c}\" {$sel}>{$v_cap} [{$safe_c}]</option>"; // Položka roletky
			}
		}

		$lbl_flt = htmlspecialchars($this->phrase('lbl_filter_archetype', [], 'Filtrovat podle archetypu:')); // Popisek roletky s diakritikou
		$grp_param = ($this->group_mode !== '') ? ('&group=' . urlencode($this->group_mode)) : ''; // Zachování parametru group v URL

		echo <<<HTML
		<div style="margin-bottom: 10px;">
			<label style="font-size: 12px; color: #555; display: block; margin-bottom: 4px;">{$lbl_flt}</label>
			<select onchange="document.location='index.php?page=page_asset{$grp_param}&archetype=' + encodeURIComponent(this.value);" style="width: 100%; padding: 6px; box-sizing: border-box;">
				{$options_html}
			</select>
		</div>
HTML;

		parent::render_master_top();                                         // Vykreslení tlačítka + Nové aktivum / prostor
	}

	/**
	 * Sestaví nadpis pravého detailního panelu s názvem nebo kódem vybraného aktiva / prostoru.
	 */
	protected function get_detail_header(): string {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		if ($update_guid === 'NEW') {                                        // Zakládání nového záznamu
			return ($this->group_mode === 'SPACE')
				? htmlspecialchars($this->phrase('header_new_space', [], 'Nový prostor / lokalita'))
				: htmlspecialchars($this->phrase('header_new_asset', [], 'Nové aktivum')); // Nadpis pro nový záznam
		}
		$title_val = (string) ($datarow['caption'] ?: $datarow['builtin_code'] ?: ''); // Název nebo kód aktiva
		$arch_val = (string) ($datarow['asset_archetype'] ?? '');            // Archetyp aktiva
		$safe_val = htmlspecialchars($title_val);                            // Ošetřený identifikátor
		$safe_arch = htmlspecialchars($arch_val);                            // Ošetřený archetyp
		$lbl = ($this->group_mode === 'SPACE')
			? htmlspecialchars($this->phrase('header_edit_space', [], 'Prostor'))
			: htmlspecialchars($this->phrase('header_edit_asset', [], 'Aktivum')); // Návěstí nadpisu
		return "{$lbl} [{$safe_arch}]: <span style=\"font-family: monospace; color: #555;\">{$safe_val}</span>"; // Výsledný nadpis
	}

	/**
	 * Vloží do hlavičky detailu prokliky na Vazby (`page_link`), Hodnocení scénářů (`page_scenario_assessment`)
	 * a Implementaci protiopatření (`page_countermeasure_implementation`) pro vybrané aktivum.
	 */
	protected function render_detail_header_buttons(string $update_guid): string { // Kontextová tlačítka v hlavičce detailu
		$parent_btns = parent::render_detail_header_buttons($update_guid);   // Případné tlačítko rozčlenění uzlu z předka
		if ($update_guid === '' OR $update_guid === 'NEW') {                 // U neuloženého záznamu další tlačítka nezobrazujeme
			return $parent_btns;                                             // Vrácení výchozího výstupu
		}

		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace
		$asset_sql = guidliteral($update_guid);                              // SQL literál originálu aktiva

		$r_lnk = sqlfirstrow("SELECT COUNT(1) AS cnt FROM link WHERE (from_object = {$asset_sql} OR to_object = {$asset_sql}) AND object_owner IN ({$org_sql}, 0x00) AND record_type = 'A' AND removed = 0"); // Počet vazeb
		$r_scn = sqlfirstrow("SELECT COUNT(1) AS cnt FROM scenario_assessment WHERE asset_uuid = {$asset_sql} AND object_owner = {$org_sql} AND record_type = 'A' AND removed = 0"); // Počet scénářů
		$r_cmi = sqlfirstrow("SELECT COUNT(1) AS cnt FROM countermeasure_implementation WHERE asset_uuid = {$asset_sql} AND object_owner = {$org_sql} AND record_type = 'A' AND removed = 0"); // Počet opatření

		$cnt_lnk = (int) ($r_lnk['cnt'] ?? 0);                               // Počet vazeb aktiva
		$cnt_scn = (int) ($r_scn['cnt'] ?? 0);                               // Počet hodnocených scénářů aktiva
		$cnt_cmi = (int) ($r_cmi['cnt'] ?? 0);                               // Počet implementovaných opatření aktiva

		$btn_lnk = new abstract_button('btn_asset_links', 'Vazby ({' . chr(36) . 'count}) →', 'page_asset', '', 'btn-secondary'); // Tlačítko vazeb
		$btn_lnk->set_href('index.php?page=page_link&from_object=' . urlencode($update_guid))->set_vars(['count' => $cnt_lnk]); // Odkaz na vazby

		$btn_scn = new abstract_button('btn_asset_scenarios', 'Scénáře ({' . chr(36) . 'count}) →', 'page_asset', '', 'btn-secondary'); // Tlačítko scénářů
		$btn_scn->set_href('index.php?page=page_scenario_assessment&asset_uuid=' . urlencode($update_guid))->set_vars(['count' => $cnt_scn]); // Odkaz na scénáře

		$btn_cmi = new abstract_button('btn_asset_cms', 'Opatření ({' . chr(36) . 'count}) →', 'page_asset', '', 'btn-secondary'); // Tlačítko opatření
		$btn_cmi->set_href('index.php?page=page_countermeasure_implementation&asset_uuid=' . urlencode($update_guid))->set_vars(['count' => $cnt_cmi]); // Odkaz na opatření

		$extra = $btn_lnk->render() . "\n\t\t\t\t\t" . $btn_scn->render() . "\n\t\t\t\t\t" . $btn_cmi->render(); // Spojení tlačítek
		return ($parent_btns !== '') ? ($parent_btns . "\n\t\t\t\t\t" . $extra) : $extra; // Výsledná sada tlačítek
	}

	/**
	 * Předvyplní výchozí hodnoty u nového záznamu, zkontroluje existenci alespoň jedné budovy
	 * v organizaci a vloží klientskou obsluhu filtrování `asset_archetype` a `primary_asset_class`.
	 */
	protected function render_detail_top(): void {
		global $datarow;                                                     // Aktuálně načtený řádek detailu
		$update_guid = trim((string) getinput('update_guid'));               // Identifikátor záznamu v detailu
		$org_sql = guidliteral(get_session_org());                           // SQL literál aktivní organizace

		$bld_row = sqlfirstrow("
			SELECT TOP 1 original
			FROM asset
			WHERE asset_archetype = 'BUILDING'
			  AND object_owner IN ({$org_sql}, 0x00)
			  AND record_type = 'A'
			  AND removed = 0
		");                                                                  // Kontrola existence alespoň jedné budovy v organizaci
		$has_building = ! empty($bld_row);                                   // Zda v organizaci existuje alespoň 1 budova

		if ($update_guid === 'NEW' AND is_array($datarow) AND ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { // Nový záznam
			$datarow['is_leaf'] = '1';                                       // Výchozí stav = koncová položka
			$in_space_flt = in_array($this->filter_archetype, self::SPACE_ARCHETYPES, true); // Zda je ve filtru prostorový archetyp

			if ($this->group_mode === 'SPACE') {                             // Předvyplnění archetypu v režimu Prostory
				$datarow['asset_archetype'] = $in_space_flt ? $this->filter_archetype : ($has_building ? 'ROOM' : 'BUILDING'); // Archetyp z filtru nebo výchozí
			} else {
				$valid_inv_flt = ($this->filter_archetype !== '__ALL__' AND isset(self::ARCHETYPE_CLASS_MAP[$this->filter_archetype]) AND ! $in_space_flt); // Věcný filtr
				$datarow['asset_archetype'] = $valid_inv_flt ? $this->filter_archetype : 'PHYSICAL'; // Archetyp z filtru nebo PHYSICAL
			}

			$def_cls = $this->resolve_default_asset_class_uuid((string) $datarow['asset_archetype']); // Výchozí koncová třída aktiv
			if ($def_cls !== '') {                                           // Pokud byla v katalogu nalezena
				$datarow['primary_asset_class'] = $def_cls;                  // Předvyplnění primární třídy aktiv
			}
		}

		parent::render_detail_top();                                         // Aplikace D&D hodnot a vykreslení pruhu z předka

		if (! $has_building) {                                               // Upozornění, pokud organizace ještě nemá ani jednu budovu
			$msg_no_bld = htmlspecialchars($this->phrase('msg_no_building_warning', [], 'Upozornění: V organizaci zatím není definována žádná Budova (archetyp BUILDING). Založte prosím nejprve alespoň jednu budovu (i kdyby byla fiktivní), protože do budov se povinně umisťují místnosti a kabeláž a do místností fyzická aktiva, hostitelské počítače, dokumenty a média.')); // Text varování
			echo "<div class=\"msg-info\" style=\"margin-bottom: 12px; background-color: #fffbeb; border-left-color: #f59e0b; color: #92400e;\">{$msg_no_bld}</div>\n"; // Žlutý varovný pruh
		}

		// Načtení všech koncových tříd aktiv seskupených podle archetypu (pro dynamickou filtraci roletky primary_asset_class)
		$cur_pac_val = guidliteral((string) ($datarow['primary_asset_class'] ?? '')); // Aktuální hodnota primary_asset_class
		$ac_rows = sqlarray_simple("EXEC dbo.p_em_get_select_options @mode = 'asset_class_by_archetype', @param_code = '', @current_val = {$cur_pac_val}"); // Načtení koncových tříd
		$classes_by_arch = [];                                               // Mapa: [ARCHETYPE => [[uuid, label], ...]]
		if (is_array($ac_rows)) {                                            // Seskupení tříd podle archetypu
			foreach ($ac_rows as $acr) {                                     // Průchod koncovými třídami
				$arch_k = strtoupper((string) ($acr['archetype_code'] ?? '')); // Kód archetypu větve
				if ($arch_k === '') {                                        // Přeskočení nezařazené třídy
					continue;                                                // Další třída
				}
				$u_str = (string) $acr['original'];                          // UUID třídy aktiv
				$c_str = (string) $acr['code_col'];                          // Kód třídy aktiv
				$cap_str = (string) $acr['caption'];                         // Název třídy aktiv
				$lbl_str = ($c_str !== '' AND $cap_str !== '' AND $cap_str !== $c_str) ? "{$c_str} ({$cap_str})" : ($cap_str ?: $c_str); // Popisek
				$classes_by_arch[$arch_k][] = [                              // Přidání do seznamu pro daný archetyp
					'uuid'  => $u_str,
					'label' => $lbl_str
				];
			}
		}

		$json_by_arch = json_encode($classes_by_arch);                       // JSON mapa koncových tříd podle archetypu
		$json_space_list = json_encode(self::SPACE_ARCHETYPES);              // JSON pole prostorových archetypů
		$js_is_space = ($this->group_mode === 'SPACE') ? 'true' : 'false';   // Příznak prostorového režimu pro JS

		echo <<<HTML
		<script>
			(function() {
				const classesByArch = {$json_by_arch};
				const spaceArchetypes = new Set({$json_space_list});
				const isSpaceMode = {$js_is_space};
				const form = document.querySelector('.md-detail form');
				if (!form) return;
				const archSel = form.querySelector('select[name="asset_archetype"]');
				const pacSel  = form.querySelector('select[name="primary_asset_class"]');
				if (!archSel) return;

				// 1. Omezení roletky asset_archetype pouze na prostory (v režimu SPACE) nebo věcná aktiva (mimo SPACE)
				const currentArchVal = (archSel.value ? archSel.value : '').toUpperCase();
				Array.from(archSel.options).forEach(function(opt) {
					const val = (opt.value ? opt.value : '').toUpperCase();
					if (val === '') return;
					const inSpace = spaceArchetypes.has(val);
					const allowed = isSpaceMode ? inSpace : !inSpace;
					if (!allowed && val !== currentArchVal) {
						opt.remove();
					}
				});

				// 2. Filtrování roletky primary_asset_class pouze na koncové třídy podřízené zvolenému archetypu
				function rebuildPrimaryAssetClassOptions(preserveCurrent) {
					if (!pacSel) return;
					const a = (archSel.value ? archSel.value : '').toUpperCase();
					const list = classesByArch[a] ? classesByArch[a] : [];
					const prevVal = preserveCurrent && pacSel.value ? pacSel.value.toLowerCase() : '';

					while (pacSel.options.length > 0) {
						pacSel.remove(0);
					}

					let matchedVal = '';
					list.forEach(function(item) {
						const opt = document.createElement('option');
						opt.value = item.uuid;
						opt.textContent = item.label;
						if (prevVal !== '' && item.uuid.toLowerCase() === prevVal) {
							matchedVal = item.uuid;
						}
						pacSel.appendChild(opt);
					});

					if (matchedVal !== '') {
						pacSel.value = matchedVal;
					} else if (pacSel.options.length > 0) {
						pacSel.selectedIndex = 0;
					}

					const hiddenPac = form.querySelector('input[type="hidden"][name="primary_asset_class"]');
					if (hiddenPac && pacSel.value) {
						hiddenPac.value = pacSel.value;
					}
				}

				function setRowVisible(colName, visible) {
					const inp = form.querySelector('[name="' + colName + '"]');
					if (!inp) return;
					const tr = inp.closest('tr');
					if (tr) {
						tr.style.display = visible ? '' : 'none';
					}
				}

				function applyArchetypeVisibility() {
					const a = (archSel.value ? archSel.value : '').toUpperCase();
					const needBld  = (a === 'ROOM' ? true : a === 'CABLING');
					const needRoom = (a === 'PHYSICAL' ? true : (a === 'HOST' ? true : (a === 'DOCUMENT' ? true : a === 'MEDIA')));
					const needHost = (a === 'APPLICATION' ? true : a === 'DATA');
					const needSw   = (a === 'APPLICATION');
					const needSup  = (a === 'INTERFACE' ? true : (a === 'PHYSICAL' ? true : (a === 'HOST' ? true : a === 'SOFTWARE')));

					setRowVisible('building_uuid', needBld);
					setRowVisible('room_uuid', needRoom);
					setRowVisible('host_uuid', needHost);
					setRowVisible('software_uuid', needSw);
					setRowVisible('supplier_uuid', needSup);
				}

				archSel.addEventListener('change', function() {
					rebuildPrimaryAssetClassOptions(false);
					applyArchetypeVisibility();
				});

				rebuildPrimaryAssetClassOptions(true);
				applyArchetypeVisibility();
			})();
		</script>
HTML;
	}
}