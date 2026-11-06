<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 15:30
 * Soubor: filter_manager.php
 * Třída: filter_manager
 * Účel: Univerzální služba pro poskytování filtrů nad položkami různých datových
 *       typů (vykreslení formulářových polí a modálního okna, trvalé uchování
 *       v $_SESSION, validace výrazů, konstrukce T-SQL podmínek WHERE,
 *       vyhodnocení řádků v PHP a obousměrný převod popisu Label: výraz).
 *
 * PODPOROVANÁ SYNTAXE VÝRAZŮ:
 * 1. Textové položky (filter_type = 'text'):
 *    - slovo       -> obsahuje podřetězec (LIKE '%slovo%')
 *    - slovo*      -> začíná na (LIKE 'slovo%')
 *    - *slovo      -> končí na (LIKE '%slovo')
 *    - =slovo      -> přesná shoda (= 'slovo', příp. ="přesný text")
 *    - =           -> nezadaná / prázdná hodnota (IS NULL OR = '')
 *    - *           -> zadaná neprázdná hodnota (IS NOT NULL AND <> '')
 *    - !výraz / <>výraz -> negace výrazu
 *    - středník ;  -> oddělovač seznamu více výrazů
 * 2. Čísla (filter_type = 'number') a Data (filter_type = 'date') v jednom poli:
 *    - =           -> nezadaná hodnota (IS NULL)
 *    - * nebo <>   -> zadaná hodnota (IS NOT NULL)
 *    - 10..50      -> uzavřený interval (>= 10 AND <= 50)
 *    - 10.. / ..50 -> jednostranný interval (>= 10, resp. <= 50)
 *    - >10, >=10, <50, <=50, <>0, =10, 10 -> porovnávací operátory
 *    - středník ; nebo čárka , -> oddělovač seznamu hodnot/intervalů
 * 3. Výběrové položky ('checkbox', 'select', 'record_state'):
 *    - roletka s volbami (u relací a číselníků včetně '=' pro NULL a '*' pro NOT NULL)
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Registrována v meta_object (object_type = 'P', builtin_code = 'filter_manager').
 * - Spolupracuje s třídou entity_manager, abstract_page_master_detail,
 *   abstract_page_tree a csv_package_simple_class.
 *
 * Změny:
 * 2026-11-06 15:30 - Zpřesnění seznamu základních položek v modálním filtru (ihned po
 *                    otevření pouze caption, stav záznamu a sloupce z basic_columns /
 *                    list_columns; ostatní sloupce pod tlačítkem Zobrazit vše).
 * 2026-11-06 15:00 - Oprava signatury konstruktoru (podpora $session_key i $basic_columns),
 *                    doplnění persistence filtru v $_SESSION a kompletní CSS/JS obsluhy.
 * =============================================================================
 */

declare(strict_types=1);

class filter_manager {

	/** Speciální klíč pro filtrování podle RAC/SSC stavu záznamu */
	public const STATE_FIELD = '__record_state';

	/** Speciální klíč pro přenos rychlého fulltextového filtru v parametru info */
	public const QUICK_FIELD = '__quick_filter';

	private static bool $assets_rendered = false; // Příznak jednorázového vložení CSS/JS modálu
	private ?entity_manager $em = null; // Volitelná reference na správce entit
	private string $session_key = ''; // Klíč v $_SESSION pro uložení aktivního filtru
	private bool $use_session = true; // Zda se má filtr automaticky číst/ukládat do $_SESSION
	private array $fields = []; // Definice filtrovatelných položek: [name => def]
	private array $basic_columns = []; // Seznam prioritních položek zobrazených ihned
	private array $values = []; // Aktuálně zadané výrazy filtru: [name => raw_expr]
	private array $parsed = []; // Rozparsované podmínky pro vyhodnocení: [name => rules]
	private array $errors = []; // Validační chyby jednotlivých položek: [name => msg]
	private string $quick_filter_term = ''; // Případný výraz rychlého filtru z info

	/**
	 * Konstruktor správce filtrů.
	 * Podporuje jak volání ($em, $session_key, $basic_columns), tak ($em, $basic_columns).
	 *
	 * @param ?entity_manager      $em                   Instance entity_manageru (nebo null pro vlastní reportové filtry)
	 * @param mixed                $session_key_or_basic Klíč relace (string) nebo pole základních sloupců (array)
	 * @param array<int, string>   $basic_columns        Seznam základních sloupců zobrazených ihned po otevření
	 * @param array<string, array> $custom_fields        Vlastní definice polí (pro reporty mimo entity_manager)
	 */
	public function __construct(
		?entity_manager $em = null, // Instance správce entit
		mixed $session_key_or_basic = '', // Klíč relace nebo pole základních sloupců
		array $basic_columns = [], // Pole základních sloupců
		array $custom_fields = [] // Vlastní definice polí
	) {
		$this->em = $em; // Uložení reference na správce entit

		if (is_array($session_key_or_basic)) { // Pokud bylo pole sloupců předáno jako 2. argument
			$this->basic_columns = $session_key_or_basic; // Převzetí základních sloupců z 2. argumentu
			$this->session_key = ''; // Klíč relace se odvodí automaticky
		} else {
			$this->session_key = trim((string) $session_key_or_basic); // Převzetí explicitního klíče relace
			$this->basic_columns = $basic_columns; // Převzetí základních sloupců ze 3. argumentu
		}

		if (str_starts_with($this->session_key, 'csv_export_tmp_')) { // Pomocná instance pro CSV export
			$this->use_session = false; // Nezasahuje do $_SESSION
		} elseif ($this->session_key === '') { // Automatické sestavení klíče relace podle kontextu stránky
			$page_part = trim((string) getinput('page')) ?: 'default'; // Název stránky
			$cls_part = ($em !== null) ? $em->get_class_name() : 'custom'; // Název logické třídy
			$ctx_part = trim((string) getinput('parent_class'))
				. '_' . trim((string) getinput('parent_object'))
				. '_' . trim((string) getinput('hierarchy'))
				. '_' . trim((string) getinput('scale')); // Kontextové parametry URL
			$this->session_key = 'bcm_adv_flt_' . $page_part . '_' . $cls_part . '_' . substr(md5($ctx_part), 0, 10); // Unikátní klíč v $_SESSION
		}

		if ($em !== null) { // Automatické načtení položek z entity_manageru
			$this->init_fields_from_entity_manager($em); // Sestavení definic polí podle metadat třídy
		}
		foreach ($custom_fields as $f_name => $f_def) { // Přidání případných vlastních polí reportu
			$this->register_field((string) $f_name, $f_def); // Registrace vlastního pole
		}

		if ($this->use_session) { // Automatická obsluha stavu filtru v $_SESSION
			$this->sync_with_request_and_session(); // Načtení nebo uložení filtru podle requestu
		}
	}

	/**
	 * Synchronizuje stav filtru s požadavkem (`$_GET['clear_adv_filter']`, `$_POST['adv_filter']`) a `$_SESSION`.
	 */
	private function sync_with_request_and_session(): void {
		if (isset($_GET['clear_adv_filter'])) { // Požadavek na vymazání rozšířeného filtru
			unset($_SESSION[$this->session_key]); // Odstranění uloženého filtru ze session
			$this->values = []; // Vyčištění hodnot
			$this->parsed = []; // Vyčištění pravidel
			$this->errors = []; // Vyčištění chyb
			return; // Ukončení synchronizace
		}

		if (isset($_POST['adv_filter']) AND is_array($_POST['adv_filter'])) { // Odeslání modálního filtru metodou POST
			$this->load_from_array($_POST['adv_filter']); // Načtení a validace odeslaných hodnot
			if (empty($this->values)) { // Pokud uživatel odeslal všechna pole prázdná
				unset($_SESSION[$this->session_key]); // Vyčištění klíče v session
			} else {
				$_SESSION[$this->session_key] = $this->values; // Uložení zadaných výrazů do session
			}
			return; // Ukončení synchronizace
		}

		if (isset($_SESSION[$this->session_key]) AND is_array($_SESSION[$this->session_key])) { // Obnovení filtru ze session
			$this->load_from_array($_SESSION[$this->session_key]); // Rozparsování uložených výrazů
		}
	}

	/**
	 * Pomocná metoda pro překlad textů komponenty filter_manager.
	 */
	private function phrase(string $builtin_code, string $default_caption, array $vars = []): string { // Překlad fráze
		if (function_exists('translate_phrase')) { // Globální helper z new_functions.php
			return translate_phrase($builtin_code, $default_caption, $vars, 'filter_manager'); // Překlad přes helper
		}
		global $phrase_manager; // Globální instance správce frází
		if (! isset($phrase_manager) OR ! ($phrase_manager instanceof phrase_manager)) { // Kontrola existence
			$phrase_manager = new phrase_manager('filter_manager'); // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] = $phrase_manager; // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, $vars, $default_caption, 'filter_manager'); // Vrácení přeložené fráze
	}

	/**
	 * Inicializuje filtrovatelné položky podle metadat třídy v entity_manageru.
	 */
	private function init_fields_from_entity_manager(entity_manager $em): void { // Načtení sloupců z entity_manageru
		$list_cols = array_keys($em->get_list_columns()); // Sloupce zobrazené v levém panelu
		$base_cols = ! empty($this->basic_columns) ? $this->basic_columns : $list_cols; // Základní sloupce stránky nebo seznamu
		$priority_names = array_unique(array_merge( // Sjednocení základních sloupců zobrazených ihned po otevření
			['caption', self::STATE_FIELD],
			$base_cols
		)); // Konec seznamu základních sloupců

		// 1. Syntetická položka stavu záznamu (aktivní, neaktivní, zrušené, koncepty, vlastní vs. systémové)
		$this->fields[self::STATE_FIELD] = [ // Definice filtru stavu záznamu
			'name'        => self::STATE_FIELD,
			'label'       => $this->phrase('lbl_record_state', 'Stav záznamu'),
			'filter_type' => 'record_state',
			'sql_type'    => 'varchar',
			'is_basic'    => true,
			'options'     => [
				'ACTIVE'   => $this->phrase('opt_state_active', 'Aktivní platné záznamy'),
				'INACTIVE' => $this->phrase('opt_state_inactive', 'Neaktivní (inactive = 1)'),
				'REMOVED'  => $this->phrase('opt_state_removed', 'Zrušené v koši (removed = 1)'),
				'DRAFT'    => $this->phrase('opt_state_draft_any', 'Rozpracované návrhy (D / F / R)'),
				'DRAFT_F'  => $this->phrase('opt_state_draft_f', 'Předáno ke schválení (F)'),
				'DRAFT_R'  => $this->phrase('opt_state_draft_r', 'Vráceno k přepracování (R)'),
				'MINE'     => $this->phrase('opt_state_mine', 'Pouze vlastní záznamy organizace'),
				'SYSTEM'   => $this->phrase('opt_state_system', 'Pouze systémové záznamy (0x00)')
			]
		]; // Konec definice stavu záznamu

		$skip_cols = [ // Interní sloupce, které se v modálu nenabízejí
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note', 'removed', 'is_template', 'template',
			'who_created', 'who_modified', 'logo_data', 'logo_filename', 'logo_mime_type',
			'svg_icon', 'ancestor_link'
		]; // Konec seznamu vynechaných sloupců

		foreach ($em->get_columns() as $colname => $meta) { // Průchod sloupci logické třídy
			if (in_array($colname, $skip_cols, true)) { // Přeskočení interních technických sloupců
				continue; // Další sloupec
			}
			if (! empty($meta['hidden']) AND ! in_array($colname, $this->basic_columns, true) AND ! in_array($colname, ['date_created', 'date_modified'], true)) { // Skryté sloupce
				continue; // Přeskočení skrytého sloupce
			}

			$label = (string) ($meta['label'] ?: $meta['caption'] ?: $meta['header'] ?: $colname); // Lidsky čitelný popisek
			$input_type = (string) ($meta['input_type'] ?? 'text'); // Typ formulářového prvku z metadat
			$sql_type = $em->get_column_sql_type($colname); // Fyzický SQL typ sloupce
			$is_basic = in_array($colname, $priority_names, true); // Zda patří mezi základní položky

			$filter_type = 'text'; // Výchozí typ filtru je textový výraz
			$options = []; // Volby pro roletku (pokud jde o select)

			if ($colname === 'licence_level' OR $colname === 'preferred_language' OR ($em->get_storage_table() === 'meta_phrase' AND $colname === 'source_code') OR ! empty($meta['referenced_codetable']) OR ! empty($meta['referenced_class'])) { // Výběrové pole
				$filter_type = 'select'; // Roletka s položkami a volbou NULL / NOT NULL
				$options = $em->get_filter_select_options($colname); // Načtení položek roletky ze správce entit
			} elseif ($input_type === 'checkbox' OR $sql_type === 'bit') { // Bitový příznak
				$filter_type = 'checkbox'; // Roletka Vše / Ano / Ne
			} elseif ($input_type === 'number' OR in_array($sql_type, ['int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money'], true)) { // Číselný sloupec
				$filter_type = 'number'; // Jednořádkový číselný filtr s operátory a '..'
			} elseif ($input_type === 'date' OR in_array($sql_type, ['date', 'datetime', 'datetime2', 'smalldatetime'], true)) { // Datumový sloupec
				$filter_type = 'date'; // Jednořádkový datumový filtr s operátory a '..'
			}

			$this->fields[$colname] = [ // Uložení definice filtrovatelného sloupce
				'name'        => $colname,
				'label'       => $label,
				'filter_type' => $filter_type,
				'sql_type'    => $sql_type,
				'is_basic'    => $is_basic,
				'options'     => $options
			]; // Konec položky sloupce
		}
	}

	/**
	 * Zaregistruje vlastní filtrovatelné pole (např. pro reporty nad libovolnými tabulkami).
	 */
	public function register_field(string $name, array $def): self { // Registrace vlastního pole filtru
		$this->fields[$name] = [ // Normalizace struktury pole
			'name'        => $name,
			'sql_col'     => (string) ($def['sql_col'] ?? $name),
			'label'       => (string) ($def['label'] ?? $name),
			'filter_type' => (string) ($def['filter_type'] ?? 'text'),
			'sql_type'    => (string) ($def['sql_type'] ?? 'varchar'),
			'is_basic'    => (bool) ($def['is_basic'] ?? true),
			'options'     => is_array($def['options'] ?? null) ? $def['options'] : []
		]; // Konec registrace pole
		return $this; // Vrácení instance pro řetězení
	}

	/**
	 * Načte, rozparsuje a zvaliduje hodnoty filtru z asociativního pole.
	 */
	public function load_from_array(array $input): bool { // Načtení a validace výrazů filtru
		$this->values = []; // Vyčištění zadaných hodnot
		$this->parsed = []; // Vyčištění rozparsovaných pravidel
		$this->errors = []; // Vyčištění validačních chyb
		$this->quick_filter_term = ''; // Vyčištění rychlého filtru

		if (isset($input[self::QUICK_FIELD])) { // Podpora rychlého filtru z parametru info
			$q_raw = trim((string) $input[self::QUICK_FIELD]); // Očištěný výraz rychlého filtru
			if ($q_raw !== '') { // Pokud je rychlý filtr neprázdný
				$this->quick_filter_term = $q_raw; // Uložení rychlého filtru
			}
		}

		foreach ($this->fields as $name => $def) { // Průchod registrovanými poli
			if (! array_key_exists($name, $input)) { // Pokud pole nebylo na vstupu předáno
				continue; // Další pole
			}
			$raw = trim((string) $input[$name]); // Oříznutý text výrazu
			if ($raw === '') { // Prázdné pole znamená neaktivní filtr
				continue; // Další pole
			}

			$this->values[$name] = $raw; // Uložení zadaného výrazu
			$err_msg = null; // Proměnná pro případnou chybu
			$rules = $this->parse_field_expression($def, $raw, $err_msg); // Rozparsování a validace výrazu

			if ($err_msg !== null AND $err_msg !== '') { // Pokud výraz obsahuje syntaktickou chybu
				$this->errors[$name] = $err_msg; // Uložení chybové hlášky k poli
			} elseif (! empty($rules)) { // Pokud bylo získáno platné pravidlo
				$this->parsed[$name] = $rules; // Uložení rozparsovaného pravidla
			}
		}

		return empty($this->errors); // True pokud nevznikla žádná chyba
	}

	/**
	 * Alias pro load_from_array() (voláno z csv_package_simple_class.php).
	 */
	public function set_active_filters(array $input): bool { // Nastavení aktivních podmínek filtru
		return $this->load_from_array($input); // Delegování na load_from_array
	}

	/**
	 * Vrátí true, pokud je aktivní alespoň jedna filtrační podmínka.
	 */
	public function is_active(): bool {
		return (! empty($this->parsed) OR $this->quick_filter_term !== ''); // Kontrola neprázdných pravidel
	}

	/**
	 * Alias pro is_active() (voláno z abstract_page_master_detail.php a abstract_page_tree.php).
	 */
	public function has_active_filters(): bool {
		return $this->is_active(); // Vrácení příznaku aktivního filtru
	}

	/**
	 * Vrátí počet aktivních položek filtru.
	 */
	public function get_active_count(): int {
		$cnt = count($this->parsed); // Počet aktivně filtrovaných sloupců
		if ($this->quick_filter_term !== '') { // Přičtení případného rychlého filtru
			$cnt++; // Zvýšení počtu o rychlý filtr
		}
		return $cnt; // Celkový počet podmínek
	}

	/**
	 * Určí, zda aktivní filtr vyžaduje načtení zrušených záznamů z koše (`removed = 1`).
	 */
	public function should_show_removed(): bool {
		$st_val = strtoupper(trim((string) ($this->values[self::STATE_FIELD] ?? ''))); // Zvolený stav záznamu
		return ($st_val === 'REMOVED'); // True pokud uživatel filtruje zrušené záznamy
	}

	/**
	 * Vrátí asociativní pole aktuálně zadaných hodnot filtru `[column => expression]`.
	 */
	public function get_active_values(): array {
		return $this->values; // Vrácení zadaných výrazů
	}

	/**
	 * Vrátí pole validačních chyb `[column => error_message]`.
	 */
	public function get_errors(): array {
		return $this->errors; // Vrácení zjištěných chyb
	}

	/**
	 * Alias pro get_errors() (voláno z abstract_page_master_detail.php).
	 */
	public function get_validation_errors(): array {
		return $this->errors; // Vrácení pole validačních chyb
	}

	/**
	 * Vrátí spojený text všech validačních chyb (nebo prázdný řetězec).
	 */
	public function get_error_message(): string {
		return implode(' ', array_values($this->errors)); // Spojení chyb do jednoho řetězce
	}

	/**
	 * Rozparsuje víceřádkový text z parametru `info` (ve formátu `Label: výraz` nebo `column: výraz`)
	 * zpět na asociativní pole `[column_name => raw_expression]` pro vyhodnocení při exportu.
	 */
	public function parse_info_to_filters(string $info_text): array { // Převod popisu info na pole filtrů
		$out = []; // Výstupní pole filtrů
		$lines = explode("\n", str_replace("\r", '', $info_text)); // Rozdělení na jednotlivé řádky

		$label_map = []; // Mapa: [malý_popisek => column_name]
		foreach ($this->fields as $f_name => $f_def) { // Sestavení vyhledávací mapy sloupců
			$name_low = mb_strtolower($f_name, 'UTF-8'); // Technický název malými písmeny
			$lbl_raw = trim((string) ($f_def['label'] ?? $f_name)); // Plný popisek sloupce
			$lbl_low = mb_strtolower($lbl_raw, 'UTF-8'); // Plný popisek malými písmeny
			$label_map[$name_low] = $f_name; // Mapování technického názvu
			$label_map[$lbl_low] = $f_name; // Mapování plného popisku
			$short_lbl = trim((string) preg_replace('/\s*\([^)]*\)\s*$/', '', $lbl_raw)); // Popisek bez závorky na konci
			if ($short_lbl !== '') { // Pokud existuje zkrácený popisek
				$label_map[mb_strtolower($short_lbl, 'UTF-8')] = $f_name; // Mapování zkráceného popisku
			}
		}

		$quick_labels = ['rychlý filtr', 'rychly filtr', 'quick filter', self::QUICK_FIELD]; // Návěstí rychlého filtru
		$yes_labels = ['ano', 'ano (1)', 'yes', 'true', '1']; // Textové varianty pro bit = 1
		$no_labels  = ['ne', 'ne (0)', 'no', 'false', '0']; // Textové varianty pro bit = 0

		foreach ($lines as $line) { // Průchod řádky parametru info
			$trimmed = trim($line); // Oříznutí bílých znaků
			if ($trimmed === '' OR ! str_contains($trimmed, ':')) { // Přeskočení prázdného řádku nebo řádku bez dvojtečky
				continue; // Další řádek
			}
			$parts = explode(':', $trimmed, 2); // Rozdělení na návěstí a výraz
			$key_str = mb_strtolower(trim($parts[0]), 'UTF-8'); // Hledané návěstí malými písmeny
			$val_str = trim($parts[1]); // Zadaný výraz za dvojtečkou
			if ($val_str === '') { // Prázdný výraz
				continue; // Další řádek
			}

			if (in_array($key_str, $quick_labels, true)) { // Detekce řádku rychlého filtru
				$out[self::QUICK_FIELD] = $val_str; // Uložení rychlého filtru
				continue; // Další řádek
			}

			if (! isset($label_map[$key_str])) { // Neznámé návěstí (např. informační text)
				continue; // Přeskočení
			}

			$col_name = $label_map[$key_str]; // Cílový technický název sloupce
			$def = $this->fields[$col_name]; // Definice sloupce
			$ftype = (string) ($def['filter_type'] ?? 'text'); // Typ filtru sloupce
			$val_low = mb_strtolower($val_str, 'UTF-8'); // Hodnota malými písmeny

			if ($ftype === 'checkbox') { // Převod Ano (1) / Ne (0) zpět na 1 / 0
				if (in_array($val_low, $yes_labels, true)) { // Hodnota Ano
					$val_str = '1'; // Bit 1
				} elseif (in_array($val_low, $no_labels, true)) { // Hodnota Ne
					$val_str = '0'; // Bit 0
				}
			} elseif (($ftype === 'select' OR $ftype === 'record_state') AND ! isset($def['options'][$val_str])) { // Hledání klíče podle popisku volby
				foreach ($def['options'] as $opt_k => $opt_v) { // Průchod volbami roletky
					if (mb_strtolower(trim((string) $opt_v), 'UTF-8') === $val_low) { // Shoda s textem volby
						$val_str = (string) $opt_k; // Dosazení klíče volby
						break; // Ukončení hledání
					}
				}
			}

			$out[$col_name] = $val_str; // Uložení rozpoznaného filtru sloupce
		}

		return $out; // Vrácení mapy filtrů
	}

	/**
	 * Rozparsuje a zvaliduje výraz jednoho pole podle jeho `filter_type`.
	 */
	private function parse_field_expression(array $def, string $raw, ?string &$error_msg = null): array { // Parsování výrazu
		$error_msg = null; // Vynulování chyby
		$ftype = (string) ($def['filter_type'] ?? 'text'); // Typ filtru
		$label = (string) ($def['label'] ?? $def['name']); // Popisek pole pro chybová hlášení

		if ($ftype === 'record_state') { // Syntetický filtr stavu záznamu
			return [['op' => 'state', 'val' => strtoupper($raw)]]; // Vrácení pravidla stavu
		}

		if ($ftype === 'checkbox') { // Bitový filtr
			if ($raw === '1' OR strtolower($raw) === 'true' OR strtolower($raw) === 'ano') { // Hodnota Ano (1)
				return [['op' => 'bit', 'val' => 1]]; // Pravidlo pro bit = 1
			}
			if ($raw === '0' OR strtolower($raw) === 'false' OR strtolower($raw) === 'ne') { // Hodnota Ne (0)
				return [['op' => 'bit', 'val' => 0]]; // Pravidlo pro bit = 0
			}
			return []; // Neznámá hodnota = bez filtru
		}

		if ($ftype === 'select') { // Výběr z roletky
			if ($raw === '=' OR $raw === '__NULL__' OR strtolower($raw) === 'null') { // Nezadaná hodnota
				return [['op' => 'is_null']]; // Pravidlo IS NULL / prázdné
			}
			if ($raw === '*' OR $raw === '<>' OR $raw === '__NOT_NULL__') { // Zadaná neprázdná hodnota
				return [['op' => 'not_null']]; // Pravidlo IS NOT NULL
			}
			return [['op' => 'eq_ci', 'val' => $raw]]; // Přesná shoda vybraného klíče/kódu
		}

		if ($ftype === 'text') { // Řetězcový filtr
			return $this->parse_text_expression($raw); // Rozparsování textového výrazu
		}

		if ($ftype === 'number') { // Číselný filtr s operátory a '..'
			$sql_t = (string) ($def['sql_type'] ?? 'decimal'); // Fyzický SQL typ čísla
			return $this->parse_number_expression($raw, $sql_t, $label, $error_msg); // Rozparsování číselného výrazu
		}

		if ($ftype === 'date') { // Datumový filtr s operátory a '..'
			return $this->parse_date_expression($raw, $label, $error_msg); // Rozparsování datumového výrazu
		}

		return $this->parse_text_expression($raw); // Fallback na textový výraz
	}

	/**
	 * Rozparsuje intuitivní textový výraz:
	 * `=` (prázdné), `*` (neprázdné), `=přesný text`, `prefix*`, `*sufix`, `obsahuje`, `!negace`, `<>negace`.
	 */
	private function parse_text_expression(string $raw): array { // Parsování textového filtru
		$tokens = str_contains($raw, ';') ? explode(';', $raw) : [$raw]; // Podpora více výrazů oddělených středníkem
		$rules = []; // Výstupní pole pravidel

		foreach ($tokens as $tok) { // Průchod jednotlivými částmi výrazu
			$t = trim($tok); // Oříznutí bílých znaků
			if ($t === '') { // Přeskočení prázdného tokenu
				continue; // Další token
			}

			if ($t === '=' OR $t === '=""' OR $t === "=''" OR strtolower($t) === 'null') { // Prázdná hodnota
				$rules[] = ['op' => 'is_null', 'neg' => false]; // Podmínka prázdné hodnoty
				continue; // Další token
			}

			if ($t === '*' OR $t === '<>' OR $t === '!=' OR $t === '!' OR strtolower($t) === 'not null') { // Neprázdná
				$rules[] = ['op' => 'not_null', 'neg' => false]; // Podmínka neprázdné hodnoty
				continue; // Další token
			}

			$neg = false; // Příznak negace
			if (str_starts_with($t, '<>') OR str_starts_with($t, '!=')) { // Negace pomocí <> nebo !=
				$neg = true; // Zapnutí negace
				$t = trim(substr($t, 2)); // Odříznutí operátoru negace
			} elseif (str_starts_with($t, '!')) { // Negace pomocí vykřičníku !
				$neg = true; // Zapnutí negace
				$t = trim(substr($t, 1)); // Odříznutí vykřičníku
			}

			if ($t === '' OR $t === '=' OR $t === '""') { // Negace prázdné hodnoty (!= nebo <>"")
				$rules[] = ['op' => $neg ? 'not_null' : 'is_null', 'neg' => false]; // Prázdné / neprázdné
				continue; // Další token
			}

			if (str_starts_with($t, '=')) { // Přesný text začínající rovnítkem
				$val = trim(substr($t, 1)); // Hodnota za rovnítkem
				if (strlen($val) >= 2 AND ((str_starts_with($val, '"') AND str_ends_with($val, '"')) OR (str_starts_with($val, "'") AND str_ends_with($val, "'")))) { // V uvozovkách
					$val = substr($val, 1, -1); // Odstranění vnějších uvozovek
				}
				if ($val === '') { // Samotné ="" znamená prázdnou hodnotu
					$rules[] = ['op' => $neg ? 'not_null' : 'is_null', 'neg' => false]; // Prázdná hodnota
				} else {
					$rules[] = ['op' => 'eq', 'val' => $val, 'neg' => $neg]; // Přesná shoda
				}
				continue; // Další token
			}

			$starts_star = str_starts_with($t, '*'); // Hvězdička na začátku (*konec)
			$ends_star = str_ends_with($t, '*'); // Hvězdička na konci (zacatek*)
			$clean_val = trim($t, '*'); // Očištěný hledaný text bez okrajových hvězdiček

			if (strlen($clean_val) >= 2 AND ((str_starts_with($clean_val, '"') AND str_ends_with($clean_val, '"')) OR (str_starts_with($clean_val, "'") AND str_ends_with($clean_val, "'")))) { // Uvozovky
				$clean_val = substr($clean_val, 1, -1); // Odříznutí uvozovek
			}

			if ($clean_val === '') { // Zbyla jen hvězdička
				$rules[] = ['op' => $neg ? 'is_null' : 'not_null', 'neg' => false]; // Neprázdné / prázdné
			} elseif ($starts_star AND ! $ends_star) { // *konec -> končí na
				$rules[] = ['op' => 'ends', 'val' => $clean_val, 'neg' => $neg]; // Maska %hodnota
			} elseif ($ends_star AND ! $starts_star) { // zacatek* -> začíná na
				$rules[] = ['op' => 'starts', 'val' => $clean_val, 'neg' => $neg]; // Maska hodnota%
			} else {
				$rules[] = ['op' => 'contains', 'val' => $clean_val, 'neg' => $neg]; // Prosté slovo nebo *slovo* -> LIKE %slovo%
			}
		}

		return $rules; // Vrácení seznamu pravidel
	}

	/**
	 * Rozděluje číselný výraz na jednotlivé položky seznamu (podporuje oddělovač `;` i `,`).
	 */
	private function split_number_tokens(string $raw, string $sql_type): array { // Rozdělení seznamu číselných podmínek
		$is_int_col = in_array($sql_type, ['int', 'smallint', 'tinyint', 'bigint'], true); // Zda jde o celé číslo
		if (str_contains($raw, ';')) { // Pokud uživatel použil středník, dělíme podle středníku
			return explode(';', $raw); // Jednoznačné rozdělení středníkem
		}
		if ($is_int_col) { // U celočíselného sloupce je čárka vždy oddělovačem seznamu
			return explode(',', $raw); // Rozdělení čárkou
		}
		if (preg_match('/,\s*(?:[<>!=]' . chr(124) . '\.\.)/', $raw) OR str_contains($raw, ', ')) { // Čárka s mezerou nebo operátorem
			return preg_split('/,\s*/', $raw) ?: [$raw]; // Rozdělení seznamu
		}
		if (substr_count($raw, ',') >= 2 AND ! str_contains($raw, '..')) { // Více čárek bez intervalu (např. 10,20,30)
			return explode(',', $raw); // Rozdělení výčtu hodnot
		}
		return [$raw]; // Jeden výraz (případná čárka je desetinná)
	}

	/**
	 * Převede textový zápis čísla na float (nebo null při neplatném zápisu).
	 */
	private function parse_single_number(string $str): ?float { // Parsování jednoho čísla
		$clean = str_replace([' ', "\xC2\xA0"], '', trim($str)); // Odstranění mezer (oddělovačů tisíců)
		$clean = str_replace(',', '.', $clean); // Převod desetinné čárky na tečku
		if ($clean === '' OR ! is_numeric($clean)) { // Kontrola platného čísla
			return null; // Neplatné číslo
		}
		return (float) $clean; // Vrácení číselné hodnoty
	}

	/**
	 * Rozparsuje a zvaliduje jednořádkový číselný výraz.
	 */
	private function parse_number_expression(string $raw, string $sql_type, string $label, ?string &$error_msg = null): array { // Parsování čísel
		$tokens = $this->split_number_tokens($raw, $sql_type); // Rozdělení na položky seznamu
		$rules = []; // Výstupní pole číselných pravidel

		foreach ($tokens as $tok) { // Průchod položkami seznamu
			$t = trim($tok); // Oříznutí mezer
			if ($t === '') { // Přeskočení prázdné položky
				continue; // Další položka
			}

			if ($t === '=' OR strtolower($t) === 'null') { // Nezadaná hodnota
				$rules[] = ['op' => 'is_null', 'neg' => false]; // Podmínka IS NULL
				continue; // Další položka
			}

			if ($t === '*' OR $t === '<>' OR $t === '!=' OR strtolower($t) === 'not null') { // Zadaná hodnota
				$rules[] = ['op' => 'not_null', 'neg' => false]; // Podmínka IS NOT NULL
				continue; // Další položka
			}

			if (str_contains($t, '..')) { // Detekce operátoru intervalu '..'
				$parts = explode('..', $t, 2); // Rozdělení na dolní a horní mez
				$left_str = trim($parts[0]); // Text dolní meze
				$right_str = trim($parts[1]); // Text horní meze

				$min_v = ($left_str !== '') ? $this->parse_single_number($left_str) : null; // Číslo dolní meze
				$max_v = ($right_str !== '') ? $this->parse_single_number($right_str) : null; // Číslo horní meze

				if (($left_str !== '' AND $min_v === null) OR ($right_str !== '' AND $max_v === null) OR ($left_str === '' AND $right_str === '')) { // Chyba
					$error_msg = $this->phrase('err_invalid_number_range', 'Neplatný číselný interval „{' . chr(36) . 'expr}“ u položky „{' . chr(36) . 'label}“.', ['expr' => $t, 'label' => $label]); // Hláška
					return []; // Ukončení při chybě
				}
				if ($min_v !== null AND $max_v !== null AND $min_v > $max_v) { // Dolní mez je větší než horní mez
					$error_msg = $this->phrase('err_number_range_order', 'Dolní mez intervalu ({' . chr(36) . 'min}) je větší než horní mez ({' . chr(36) . 'max}) u položky „{' . chr(36) . 'label}“.', ['min' => $left_str, 'max' => $right_str, 'label' => $label]); // Hláška
					return []; // Ukončení při chybě
				}

				if ($min_v !== null AND $max_v !== null) { // Oboustranný interval a..b
					$rules[] = ['op' => 'between', 'min' => $min_v, 'max' => $max_v, 'neg' => false]; // Mezi min a max
				} elseif ($min_v !== null) { // Jednostranný interval a..
					$rules[] = ['op' => '>=', 'val' => $min_v, 'neg' => false]; // >= min
				} else {
					$rules[] = ['op' => '<=', 'val' => $max_v, 'neg' => false]; // <= max
				}
				continue; // Další položka
			}

			$op = '='; // Výchozí operátor rovnosti
			$num_part = $t; // Číselná část výrazu
			if (str_starts_with($t, '>=')) { // Operátor >=
				$op = '>='; // Nastavení >=
				$num_part = substr($t, 2); // Odříznutí >=
			} elseif (str_starts_with($t, '<=')) { // Operátor <=
				$op = '<='; // Nastavení <=
				$num_part = substr($t, 2); // Odříznutí <=
			} elseif (str_starts_with($t, '<>') OR str_starts_with($t, '!=')) { // Operátor <>
				$op = '<>'; // Nastavení <>
				$num_part = substr($t, 2); // Odříznutí <>
			} elseif (str_starts_with($t, '>')) { // Operátor >
				$op = '>'; // Nastavení >
				$num_part = substr($t, 1); // Odříznutí >
			} elseif (str_starts_with($t, '<')) { // Operátor <
				$op = '<'; // Nastavení <
				$num_part = substr($t, 1); // Odříznutí <
			} elseif (str_starts_with($t, '!')) { // Negace !čislo
				$op = '<>'; // Nastavení <>
				$num_part = substr($t, 1); // Odříznutí !
			} elseif (str_starts_with($t, '=')) { // Explicitní =číslo
				$op = '='; // Nastavení =
				$num_part = substr($t, 1); // Odříznutí =
			}

			$val = $this->parse_single_number($num_part); // Převod číselné části na float
			if ($val === null) { // Neplatné číslo
				$error_msg = $this->phrase('err_invalid_number_expr', 'Neplatný číselný výraz „{' . chr(36) . 'expr}“ u položky „{' . chr(36) . 'label}“.', ['expr' => $t, 'label' => $label]); // Chybová hláška
				return []; // Ukončení při chybě
			}

			$rules[] = ['op' => $op, 'val' => $val, 'neg' => ($op === '<>')]; // Přidání číselného pravidla
		}

		return $rules; // Vrácení seznamu číselných pravidel
	}

	/**
	 * Převede textový zápis data na normalizovaný ISO formát `YYYY-MM-DD` (nebo `null`).
	 */
	private function parse_single_date(string $str): ?string { // Parsování jednoho data
		$trimmed = trim($str); // Oříznutí bílých znaků
		if ($trimmed === '') { // Prázdný řetězec
			return null; // Není datum
		}
		$lit = dateliteral($trimmed); // Využití knihovní funkce dateliteral() z OsirisLib.php
		if ($lit === 'NULL' OR strlen($lit) < 12) { // Pokud datum není kalendářně platné
			return null; // Neplatné datum
		}
		return substr(trim($lit, "'"), 0, 10); // Vrácení ISO data YYYY-MM-DD
	}

	/**
	 * Rozparsuje a zvaliduje datumový výraz (`=`, `*`, `od..do`, `>=datum`, `<=datum`, seznam oddělený `;` nebo `,`).
	 */
	private function parse_date_expression(string $raw, string $label, ?string &$error_msg = null): array { // Parsování data
		$tokens = preg_split('/[;,]+/', $raw) ?: [$raw]; // Rozdělení podle středníku nebo čárky
		$rules = []; // Výstupní pole datumových pravidel

		foreach ($tokens as $tok) { // Průchod položkami
			$t = trim($tok); // Oříznutí bílých znaků
			if ($t === '') { // Přeskočení prázdné položky
				continue; // Další položka
			}
			if ($t === '=' OR strtolower($t) === 'null') { // Nezadané datum (IS NULL)
				$rules[] = ['op' => 'is_null', 'neg' => false]; // Pravidlo IS NULL
				continue; // Další položka
			}
			if ($t === '*' OR $t === '<>' OR $t === '!=' OR strtolower($t) === 'not null') { // Zadané datum
				$rules[] = ['op' => 'not_null', 'neg' => false]; // Pravidlo IS NOT NULL
				continue; // Další položka
			}

			if (str_contains($t, '..')) { // Datumový interval od..do
				$parts = explode('..', $t, 2); // Rozpad na dolní a horní datum
				$d_min = (trim($parts[0]) !== '') ? $this->parse_single_date($parts[0]) : null; // Datum od
				$d_max = (trim($parts[1]) !== '') ? $this->parse_single_date($parts[1]) : null; // Datum do

				if ((trim($parts[0]) !== '' AND $d_min === null) OR (trim($parts[1]) !== '' AND $d_max === null) OR ($d_min === null AND $d_max === null)) { // Chyba
					$error_msg = $this->phrase('err_invalid_date_range', 'Neplatný datumový interval „{' . chr(36) . 'expr}“ u položky „{' . chr(36) . 'label}“.', ['expr' => $t, 'label' => $label]); // Hláška
					return []; // Ukončení při chybě
				}
				if ($d_min !== null AND $d_max !== null AND $d_min > $d_max) { // Počáteční datum je po koncovém
					$error_msg = $this->phrase('err_date_range_order', 'Počáteční datum ({' . chr(36) . 'min}) je větší než koncové ({' . chr(36) . 'max}) u položky „{' . chr(36) . 'label}“.', ['min' => $d_min, 'max' => $d_max, 'label' => $label]); // Hláška
					return []; // Ukončení při chybě
				}

				if ($d_min !== null AND $d_max !== null) { // Oboustranný datumový interval
					$rules[] = ['op' => 'date_between', 'min' => $d_min, 'max' => $d_max, 'neg' => false]; // Mezi d_min a d_max
				} elseif ($d_min !== null) { // Od data d_min
					$rules[] = ['op' => 'date_>=', 'val' => $d_min, 'neg' => false]; // >= d_min
				} else {
					$rules[] = ['op' => 'date_<=', 'val' => $d_max, 'neg' => false]; // <= d_max
				}
				continue; // Další položka
			}

			$op = '='; // Výchozí operátor data
			$d_part = $t; // Textová část data
			foreach (['>=', '<=', '<>', '!=', '>', '<', '!'] as $cand_op) { // Kontrola operátorů
				if (str_starts_with($t, $cand_op)) { // Nalezen operátor na začátku
					$op = ($cand_op === '!=' OR $cand_op === '!') ? '<>' : $cand_op; // Normalizace negace na <>
					$d_part = substr($t, strlen($cand_op)); // Odříznutí operátoru
					break; // Ukončení hledání operátoru
				}
			}
			if (str_starts_with($d_part, '=')) { // Případné =datum
				$d_part = substr($d_part, 1); // Odříznutí rovnítka
			}

			$iso_d = $this->parse_single_date($d_part); // Převod na YYYY-MM-DD
			if ($iso_d === null) { // Neplatné datum
				$error_msg = $this->phrase('err_invalid_date_expr', 'Neplatné datum „{' . chr(36) . 'expr}“ u položky „{' . chr(36) . 'label}“.', ['expr' => $t, 'label' => $label]); // Hláška
				return []; // Ukončení při chybě
			}

			$rules[] = ['op' => 'date_' . $op, 'val' => $iso_d, 'neg' => ($op === '<>')]; // Přidání datumového pravidla
		}

		return $rules; // Vrácení seznamu datumových pravidel
	}

	/**
	 * Vyhodnotí, zda jeden datový řádek vyhovuje všem aktivním podmínkám filtru.
	 */
	public function matches_row(array $row): bool { // Vyhodnocení všech podmínek nad řádkem v PHP
		if (! $this->is_active()) { // Pokud není aktivní žádný filtr
			return true; // Každý řádek vyhovuje
		}

		if ($this->quick_filter_term !== '') { // Kontrola případného rychlého filtru z info
			$q_low = mb_strtolower($this->quick_filter_term, 'UTF-8'); // Hledaný podřetězec malými písmeny
			$row_concat = mb_strtolower(implode(' ', array_map('strval', $row)), 'UTF-8'); // Spojení hodnot řádku
			if (! str_contains($row_concat, $q_low)) { // Pokud řádek rychlému filtru nevyhovuje
				return false; // Nevyhovuje
			}
		}

		foreach ($this->parsed as $col => $rules) { // Průchod aktivními filtrovanými sloupci (AND)
			if ($col === self::STATE_FIELD) { // Speciální vyhodnocení stavu záznamu
				if (! $this->matches_state_rule($row, (string) ($rules[0]['val'] ?? ''))) { // Kontrola stavu
					return false; // Stav záznamu nevyhovuje
				}
				continue; // Další sloupec
			}

			$cell_raw = $row[$col] ?? null; // Hodnota sloupce v řádku
			if (! $this->matches_field_rules($cell_raw, $rules)) { // Kontrola pravidel jednoho sloupce
				return false; // Řádek nevyhověl podmínce sloupce
			}
		}

		return true; // Řádek vyhověl všem podmínkám
	}

	/**
	 * Vyhodnotí podmínku stavu záznamu (`__record_state`) nad řádkem.
	 */
	private function matches_state_rule(array $row, string $state_code): bool { // Vyhodnocení stavu záznamu
		$is_rem = (! empty($row['removed']) OR ! empty($row['l_removed'])); // Zda je záznam zrušený
		$is_inact = ! empty($row['inactive']); // Zda je záznam neaktivní
		$rec_type = (string) ($row['record_type'] ?? 'A'); // Typ záznamu ('A' nebo 'D')
		$app_st = (string) ($row['approval_status'] ?? 'A'); // Stav schválení ('A', 'D', 'F', 'R')
		$is_mine = ! empty($row['object_is_mine']); // Zda patří aktuální organizaci

		switch ($state_code) { // Rozlišení podle zvoleného stavu
			case 'ACTIVE':
				return (! $is_rem AND ! $is_inact); // Aktivní a nezrušený
			case 'INACTIVE':
				return $is_inact; // Pouze neaktivní
			case 'REMOVED':
				return $is_rem; // Pouze zrušené v koši
			case 'DRAFT':
				return ($rec_type === 'D'); // Libovolný rozpracovaný koncept
			case 'DRAFT_F':
				return ($rec_type === 'D' AND $app_st === 'F'); // Postoupeno ke schválení
			case 'DRAFT_R':
				return ($rec_type === 'D' AND $app_st === 'R'); // Vráceno schvalovatelem
			case 'MINE':
				return $is_mine; // Vlastní záznam organizace
			case 'SYSTEM':
				return ! $is_mine; // Systémový záznam (0x00)
			default:
				return true; // Neznámý stav = neomezujeme
		}
	}

	/**
	 * Vyhodnotí sadu pravidel jednoho sloupce nad hodnotou buňky v PHP.
	 */
	private function matches_field_rules(mixed $cell_raw, array $rules): bool { // Vyhodnocení pravidel jednoho sloupce
		$str_val = trim((string) ($cell_raw ?? '')); // Textová hodnota buňky
		$is_empty = ($cell_raw === null OR $str_val === ''); // Zda je buňka prázdná / NULL

		$pos_rules = []; // Pozitivní podmínky (spojené přes OR)
		$neg_rules = []; // Negativní podmínky (spojené přes AND)
		foreach ($rules as $r) { // Rozdělení na pozitivní a negativní pravidla
			if (! empty($r['neg'])) { // Negativní pravidlo
				$neg_rules[] = $r; // Zařazení do AND-NOT seznamu
			} else {
				$pos_rules[] = $r; // Zařazení do OR seznamu
			}
		}

		foreach ($neg_rules as $nr) { // Kontrola negativních pravidel
			if ($this->eval_single_positive_rule($str_val, $is_empty, $nr)) { // Pokud platí zakázaná podmínka
				return false; // Řádek nevyhovuje
			}
		}

		if (! empty($pos_rules)) { // Kontrola pozitivních pravidel
			$any_matched = false; // Příznak shody alespoň jednoho pravidla
			foreach ($pos_rules as $pr) { // Průchod pozitivními pravidly
				if ($this->eval_single_positive_rule($str_val, $is_empty, $pr)) { // Shoda s pravidlem
					$any_matched = true; // Nalezena shoda
					break; // Stačí jedno splněné pravidlo v OR seznamu
				}
			}
			if (! $any_matched) { // Žádné pozitivní pravidlo nevyhovělo
				return false; // Řádek nevyhovuje
			}
		}

		return true; // Všechny podmínky sloupce splněny
	}

	/**
	 * Vyhodnotí jedno atomické pravidlo (bez negace) nad hodnotou buňky.
	 */
	private function eval_single_positive_rule(string $str_val, bool $is_empty, array $rule): bool { // Atomické vyhodnocení
		$op = (string) ($rule['op'] ?? ''); // Kód operátoru

		if ($op === 'is_null') { // Kontrola prázdné hodnoty
			return $is_empty; // True pokud je prázdná
		}
		if ($op === 'not_null') { // Kontrola neprázdné hodnoty
			return ! $is_empty; // True pokud není prázdná
		}
		if ($op === 'bit') { // Bitové porovnání 0 / 1
			$bit_cell = ($str_val === '1' OR strtolower($str_val) === 'true') ? 1 : 0; // Bit z buňky
			return ($bit_cell === (int) $rule['val']); // Shoda bitu
		}

		if ($is_empty) { // Prázdná buňka nevyhoví žádnému dalšímu pozitivnímu porovnání
			return false; // Prázdná hodnota
		}

		if (in_array($op, ['eq', 'eq_ci', 'contains', 'starts', 'ends'], true)) { // Textové porovnání
			$cell_low = mb_strtolower($str_val, 'UTF-8'); // Hodnota buňky malými písmeny
			$target_low = mb_strtolower((string) ($rule['val'] ?? ''), 'UTF-8'); // Hledaný vzorek malými písmeny
			if ($op === 'eq' OR $op === 'eq_ci') { // Přesná shoda
				return ($cell_low === $target_low); // Shoda celého řetězce
			}
			if ($op === 'starts') { // Začíná na (hodnota*)
				return str_starts_with($cell_low, $target_low); // Kontrola prefixu
			}
			if ($op === 'ends') { // Končí na (*hodnota)
				return str_ends_with($cell_low, $target_low); // Kontrola sufixu
			}
			return str_contains($cell_low, $target_low); // Obsahuje podřetězec (LIKE %hodnota%)
		}

		if (in_array($op, ['=', '<>', '>', '<', '>=', '<=', 'between'], true)) { // Číselné porovnání
			$c_num = $this->parse_single_number($str_val); // Číselná hodnota buňky
			if ($c_num === null) { // Buňka neobsahuje platné číslo
				return false; // Nevyhovuje
			}
			if ($op === 'between') { // Interval min..max
				return ($c_num >= (float) $rule['min'] - 0.000001 AND $c_num <= (float) $rule['max'] + 0.000001); // V intervalu
			}
			$t_num = (float) ($rule['val'] ?? 0.0); // Cílové číslo
			if ($op === '=' OR $op === '<>') { // Rovnost (pro <> se negace provede o úroveň výš)
				return (abs($c_num - $t_num) < 0.000001); // Shoda čísla s tolerancí
			}
			if ($op === '>') { // Ostře větší
				return ($c_num > $t_num); // >
			}
			if ($op === '<') { // Ostře menší
				return ($c_num < $t_num); // <
			}
			if ($op === '>=') { // Větší nebo rovno
				return ($c_num >= $t_num - 0.000001); // >=
			}
			if ($op === '<=') { // Menší nebo rovno
				return ($c_num <= $t_num + 0.000001); // <=
			}
		}

		if (str_starts_with($op, 'date_')) { // Datumové porovnání
			$c_date = substr($str_val, 0, 10); // Prvních 10 znaků YYYY-MM-DD z DB
			if (! preg_match('/^\d{4}-\d{2}-\d{2}$/', $c_date)) { // Pokud není v ISO formátu
				$c_date = $this->parse_single_date($str_val) ?? ''; // Pokus o převod
			}
			if ($c_date === '') { // Neplatné datum v buňce
				return false; // Nevyhovuje
			}
			if ($op === 'date_between') { // Datumový interval od..do
				return ($c_date >= (string) $rule['min'] AND $c_date <= (string) $rule['max']); // V intervalu
			}
			$t_date = (string) ($rule['val'] ?? ''); // Cílové datum YYYY-MM-DD
			$sub_op = substr($op, 5); // Operátor za 'date_'
			if ($sub_op === '=' OR $sub_op === '<>') { // Shoda data
				return ($c_date === $t_date); // Přesná shoda dne
			}
			if ($sub_op === '>') { // Po datu
				return ($c_date > $t_date); // >
			}
			if ($sub_op === '<') { // Před datu
				return ($c_date < $t_date); // <
			}
			if ($sub_op === '>=') { // Od data včetně
				return ($c_date >= $t_date); // >=
			}
			if ($sub_op === '<=') { // Do data včetně
				return ($c_date <= $t_date); // <=
			}
		}

		return false; // Neznámý operátor
	}

	/**
	 * Vyfiltruje pole záznamů (s volitelným zachováním nadřízených uzlů stromu).
	 */
	public function filter_rows(array $rows, bool $preserve_tree_ancestors = false, string $parent_col = 'parent_uuid'): array { // Filtrace pole
		if (! $this->is_active()) { // Pokud není aktivní žádný filtr
			foreach ($rows as &$r_all) { // Označíme všechny řádky jako přímo vyhovující
				$r_all['_filter_matched'] = 1; // Přímá shoda
			}
			unset($r_all); // Uvolnění reference
			return $rows; // Vrácení všech řádků
		}

		$by_orig = []; // Mapa všech řádků podle original (malými písmeny)
		$matched_origs = []; // Množina přímo vyhovujících uzlů
		$visible_origs = []; // Množina všech viditelných uzlů (včetně předků)

		foreach ($rows as $row) { // 1. průchod: vyhodnocení shody pro každý řádek
			$orig = strtolower(trim((string) ($row['original'] ?? ''))); // Klíč originálu malými písmeny
			if ($orig !== '') { // Uložení do mapy pro hledání rodičů
				$by_orig[$orig] = $row; // Uložení řádku
			}
			if ($this->matches_row($row) AND $orig !== '') { // Pokud řádek přímo vyhovuje filtru
				$matched_origs[$orig] = true; // Označení přímé shody
				$visible_origs[$orig] = true; // Zařazení mezi viditelné uzly
			}
		}

		if ($preserve_tree_ancestors AND ! empty($matched_origs)) { // 2. průchod: doplnění všech předků až ke kořeni
			foreach (array_keys($matched_origs) as $m_orig) { // Pro každý vyhovující uzel
				$curr_p = strtolower(trim((string) ($by_orig[$m_orig][$parent_col] ?? ''))); // Rodič uzlu
				$guard = 0; // Pojistka proti případnému cyklu v datech
				while ($curr_p !== '' AND isset($by_orig[$curr_p]) AND $guard < 60) { // Průchod ke kořeni
					$visible_origs[$curr_p] = true; // Zviditelnění nadřízeného uzlu na cestě
					$next_p = strtolower(trim((string) ($by_orig[$curr_p][$parent_col] ?? ''))); // Další předek
					if ($next_p === $curr_p) { // Ochrana proti odkazování na sebe sama
						break; // Ukončení smyčky
					}
					$curr_p = $next_p; // Posun o úroveň výš
					$guard++; // Inkrementace pojistky
				}
			}
		}

		$out = []; // Výsledné vyfiltrované pole
		foreach ($rows as $row) { // 3. průchod: sestavení výstupního pole v původním pořadí
			$orig = strtolower(trim((string) ($row['original'] ?? ''))); // Klíč originálu
			if (isset($visible_origs[$orig])) { // Pokud má být uzel viditelný
				$row['_filter_matched'] = isset($matched_origs[$orig]) ? 1 : 0; // 1 = přímá shoda, 0 = nadřízená složka na cestě
				$out[] = $row; // Přidání do výsledku
			}
		}

		return $out; // Vrácení vyfiltrovaných záznamů
	}

	/**
	 * Alias pro filter_rows() (voláno z abstract_page_master_detail.php).
	 */
	public function apply_to_rows(array $rows): array { // Aplikace filtru na pole řádků
		return $this->filter_rows($rows); // Delegování na filter_rows
	}

	/**
	 * Sestaví bezpečnou T-SQL podmínku `WHERE` (bez klíčového slova `WHERE`).
	 */
	public function build_sql_where(string $table_alias = 'm'): string { // Konstrukce T-SQL příkazu WHERE
		if (empty($this->parsed)) { // Pokud není aktivní žádná podmínka
			return ''; // Prázdná podmínka
		}

		$pfx = ($table_alias !== '') ? "{$table_alias}." : ''; // Prefix tabulkového aliasu
		$and_parts = []; // Pole podmínek jednotlivých sloupců (AND)

		foreach ($this->parsed as $col => $rules) { // Průchod aktivními sloupci
			$def = $this->fields[$col] ?? []; // Definice sloupce
			if ($col === self::STATE_FIELD) { // Podmínka stavu záznamu
				$st = (string) ($rules[0]['val'] ?? ''); // Kód stavu
				if ($st === 'ACTIVE') { // Aktivní platné
					$and_parts[] = "({$pfx}inactive = 0 AND {$pfx}removed = 0)";
				} elseif ($st === 'INACTIVE') { // Neaktivní
					$and_parts[] = "{$pfx}inactive = 1";
				} elseif ($st === 'REMOVED') { // Zrušené
					$and_parts[] = "{$pfx}removed = 1";
				} elseif ($st === 'DRAFT') { // Koncepty
					$and_parts[] = "{$pfx}record_type = 'D'";
				} elseif ($st === 'DRAFT_F') { // Ke schválení
					$and_parts[] = "({$pfx}record_type = 'D' AND {$pfx}approval_status = 'F')";
				} elseif ($st === 'DRAFT_R') { // Vráceno
					$and_parts[] = "({$pfx}record_type = 'D' AND {$pfx}approval_status = 'R')";
				} elseif ($st === 'SYSTEM') { // Systémové
					$and_parts[] = "{$pfx}object_owner = 0x00";
				} elseif ($st === 'MINE') { // Vlastní záznamy organizace
					$and_parts[] = "{$pfx}object_owner <> 0x00";
				}
				continue; // Další sloupec
			}

			$sql_col_raw = (string) ($def['sql_col'] ?? $col); // Název sloupce v SQL
			$col_expr = str_contains($sql_col_raw, '.') ? $sql_col_raw : "{$pfx}[{$sql_col_raw}]"; // Plný SQL identifikátor sloupce
			$ftype = (string) ($def['filter_type'] ?? 'text'); // Typ filtru sloupce

			$pos_sql = []; // Pozitivní SQL výrazy (OR)
			$neg_sql = []; // Negativní SQL výrazy (AND)

			foreach ($rules as $r) { // Průchod pravidly sloupce
				$atom = $this->build_single_sql_condition($col_expr, $ftype, $r); // Sestavení atomické SQL podmínky
				if ($atom === '') { // Přeskočení prázdného výrazu
					continue; // Další pravidlo
				}
				if (! empty($r['neg'])) { // Negativní podmínka
					$neg_sql[] = "NOT ({$atom})"; // Obalení negací NOT (...)
				} else {
					$pos_sql[] = $atom; // Pozitivní podmínka
				}
			}

			$col_parts = []; // Části podmínky pro tento sloupec
			if (! empty($pos_sql)) { // Spojení pozitivních podmínek přes OR
				$col_parts[] = (count($pos_sql) > 1) ? '(' . implode(' OR ', $pos_sql) . ')' : $pos_sql[0];
			}
			foreach ($neg_sql as $ns) { // Připojení negativních podmínek přes AND
				$col_parts[] = $ns; // Negativní podmínka
			}
			if (! empty($col_parts)) { // Zařazení podmínky sloupce do celkového WHERE
				$and_parts[] = (count($col_parts) > 1) ? '(' . implode(' AND ', $col_parts) . ')' : $col_parts[0];
			}
		}

		return implode(' AND ', $and_parts); // Výsledný T-SQL WHERE řetězec
	}

	/**
	 * Sestaví jednu atomickou T-SQL podmínku (bez negace) pro zadaný sloupec a pravidlo.
	 */
	private function build_single_sql_condition(string $col_expr, string $ftype, array $rule): string { // Atomická SQL podmínka
		$op = (string) ($rule['op'] ?? ''); // Operátor pravidla

		if ($op === 'is_null') { // Nezadaná hodnota
			return ($ftype === 'text')
				? "({$col_expr} IS NULL OR LTRIM(RTRIM(CAST({$col_expr} AS VARCHAR(MAX)))) = '')"
				: "{$col_expr} IS NULL"; // Podmínka pro prázdný text nebo NULL
		}
		if ($op === 'not_null') { // Zadaná hodnota
			return ($ftype === 'text')
				? "({$col_expr} IS NOT NULL AND LTRIM(RTRIM(CAST({$col_expr} AS VARCHAR(MAX)))) <> '')"
				: "{$col_expr} IS NOT NULL"; // Podmínka pro neprázdný text nebo NOT NULL
		}
		if ($op === 'bit') { // Bitový sloupec
			$b = (int) ($rule['val'] ?? 0); // 0 nebo 1
			return "{$col_expr} = {$b}"; // Podmínka bitu
		}

		if (in_array($op, ['eq', 'eq_ci', 'contains', 'starts', 'ends'], true)) { // Textová podmínka
			$val = (string) ($rule['val'] ?? ''); // Hledaný text
			if ($op === 'eq' OR $op === 'eq_ci') { // Přesná shoda
				return "{$col_expr} = " . charliteral($val); // Rovnost
			}
			$escaped_like = str_replace(['[', '%', '_'], ['[[]', '[%]', '[_]'], $val); // Escape divokých znaků T-SQL LIKE
			if ($op === 'starts') { // Začíná na
				return "{$col_expr} LIKE " . charliteral($escaped_like . '%'); // LIKE 'vzorek%'
			}
			if ($op === 'ends') { // Končí na
				return "{$col_expr} LIKE " . charliteral('%' . $escaped_like); // LIKE '%vzorek'
			}
			return "{$col_expr} LIKE " . charliteral('%' . $escaped_like . '%'); // LIKE '%vzorek%'
		}

		if (in_array($op, ['=', '<>', '>', '<', '>=', '<=', 'between'], true)) { // Číselná podmínka
			if ($op === 'between') { // Interval min..max
				$min_s = (string) (float) $rule['min']; // Dolní mez
				$max_s = (string) (float) $rule['max']; // Horní mez
				return "({$col_expr} >= {$min_s} AND {$col_expr} <= {$max_s})"; // BETWEEN podmínka
			}
			$sql_op = ($op === '<>') ? '=' : $op; // Negaci <> řeší nadřazené NOT (...)
			$val_s = (string) (float) ($rule['val'] ?? 0); // Číselný literál
			return "{$col_expr} {$sql_op} {$val_s}"; // Porovnání čísla
		}

		if (str_starts_with($op, 'date_')) { // Datumová podmínka
			if ($op === 'date_between') { // Datumový interval
				$d1 = charliteral((string) $rule['min'], 10); // Datum od
				$d2 = charliteral((string) $rule['max'], 10); // Datum do
				return "(CAST({$col_expr} AS date) >= {$d1} AND CAST({$col_expr} AS date) <= {$d2})"; // Interval dnů
			}
			$sub_op = substr($op, 5); // Operátor za 'date_'
			$sql_op = ($sub_op === '<>') ? '=' : $sub_op; // Negaci řeší NOT (...)
			$d_lit = charliteral((string) ($rule['val'] ?? ''), 10); // SQL literál data
			return "CAST({$col_expr} AS date) {$sql_op} {$d_lit}"; // Porovnání data
		}

		return ''; // Neznámý operátor
	}

	/**
	 * Sestaví lidsky čitelný textový popis aktivního filtru ve formátu `Label: výraz`.
	 */
	public function build_info_text(string $separator = "\n"): string { // Sestavení popisu filtru (Label: výraz)
		$lines = []; // Pole řádků popisu filtru

		foreach ($this->values as $col => $raw_val) { // Průchod zadanými hodnotami
			if (! isset($this->parsed[$col])) { // Přeskočení neplatného nebo prázdného pole
				continue; // Další pole
			}
			$def = $this->fields[$col] ?? []; // Definice pole
			$label = (string) ($def['label'] ?? $col); // Popisek pole (Label)
			$ftype = (string) ($def['filter_type'] ?? 'text'); // Typ filtru
			$disp_val = $raw_val; // Výchozí zobrazená hodnota = přesně jak ji uživatel zadal

			if ($ftype === 'checkbox') { // U checkboxu vypíšeme Ano / Ne
				$disp_val = ($raw_val === '1')
					? $this->phrase('val_yes', 'Ano (1)')
					: $this->phrase('val_no', 'Ne (0)'); // Čitelná hodnota checkboxu
			} elseif ($ftype === 'select' OR $ftype === 'record_state') { // U roletky vypíšeme text vybrané volby
				if ($raw_val === '=' OR $raw_val === '__NULL__') { // Nezadaná hodnota
					$disp_val = '='; // Znak nezadané hodnoty
				} elseif ($raw_val === '*' OR $raw_val === '__NOT_NULL__') { // Zadaná hodnota
					$disp_val = '*'; // Znak zadané hodnoty
				} elseif (isset($def['options'][$raw_val])) { // Nalezen popisek v roletce
					$disp_val = (string) $def['options'][$raw_val]; // Popisek volby z roletky
				}
			}

			$lines[] = "{$label}: {$disp_val}"; // Formát "Label: výraz"
		}

		if ($this->quick_filter_term !== '') { // Připojení případného rychlého filtru
			$lbl_q = $this->phrase('lbl_quick_filter', 'Rychlý filtr'); // Popisek rychlého filtru
			$lines[] = "{$lbl_q}: {$this->quick_filter_term}"; // Řádek rychlého filtru
		}

		return implode($separator, $lines); // Spojení řádků zvoleným oddělovačem
	}

	/**
	 * Alias pro build_info_text() (voláno z abstract_page_master_detail.php).
	 */
	public function get_info_summary(string $separator = "\n"): string { // Souhrn aktivního filtru
		return $this->build_info_text($separator); // Delegování na build_info_text
	}

	/**
	 * Vykreslí HTML vstupní prvek pro jedno filtrační pole (se jménem `adv_filter[sloupec]`).
	 */
	public function render_field_input(string $name, string $input_prefix = 'bcm_flt_'): string { // Vykreslení jednoho pole filtru
		if (! isset($this->fields[$name])) { // Kontrola existence pole
			return ''; // Neznámé pole
		}

		$def = $this->fields[$name]; // Definice pole
		$ftype = (string) $def['filter_type']; // Typ filtru
		$cur_val = (string) ($this->values[$name] ?? ''); // Aktuálně zadaná hodnota
		$safe_val = htmlspecialchars($cur_val); // Ošetřená hodnota pro HTML atribut
		$safe_col = htmlspecialchars($name); // Ošetřený název sloupce
		$inp_id = htmlspecialchars($input_prefix . $name); // HTML ID vstupního prvku
		$inp_name = 'adv_filter[' . $safe_col . ']'; // Jméno prvku pro odeslání formulářem
		$inp_style = 'width: 100%; padding: 5px 8px; box-sizing: border-box; border: 1px solid #cbd5e1; border-radius: 3px; font-size: 13px;'; // Styl

		if ($ftype === 'checkbox') { // Třístavová roletka pro checkbox
			$opt_all = htmlspecialchars($this->phrase('opt_all', '--- Vše ---')); // Vše
			$opt_yes = htmlspecialchars($this->phrase('val_yes', 'Ano (1)')); // Ano
			$opt_no  = htmlspecialchars($this->phrase('val_no', 'Ne (0)')); // Ne
			$sel_1 = ($cur_val === '1') ? 'selected' : ''; // Vybráno Ano
			$sel_0 = ($cur_val === '0') ? 'selected' : ''; // Vybráno Ne
			return "<select id=\"{$inp_id}\" name=\"{$inp_name}\" data-filter-col=\"{$safe_col}\" oninput=\"isFormDirty = false;\" style=\"{$inp_style}\">"
				. "<option value=\"\">{$opt_all}</option>"
				. "<option value=\"1\" {$sel_1}>{$opt_yes}</option>"
				. "<option value=\"0\" {$sel_0}>{$opt_no}</option>"
				. "</select>"; // HTML roletka checkboxu
		}

		if ($ftype === 'select' OR $ftype === 'record_state') { // Roletka pro číselník, relaci nebo stav záznamu
			$opt_all = htmlspecialchars($this->phrase('opt_all', '--- Vše ---')); // Výchozí volba Vše
			$opts_html = "<option value=\"\">{$opt_all}</option>"; // První položka roletky

			if ($ftype === 'select') { // U relací a číselníků nabídneme i '=' (NULL) a '*' (NOT NULL)
				$lbl_null = htmlspecialchars($this->phrase('opt_is_null', '= (Nezadaná hodnota / NULL)')); // Nezadaná hodnota
				$lbl_nnull = htmlspecialchars($this->phrase('opt_not_null', '* (Zadaná hodnota / NOT NULL)')); // Zadaná hodnota
				$sel_null = ($cur_val === '=' OR $cur_val === '__NULL__') ? 'selected' : ''; // Vybráno NULL
				$sel_nnull = ($cur_val === '*' OR $cur_val === '__NOT_NULL__') ? 'selected' : ''; // Vybráno NOT NULL
				$opts_html .= "<option value=\"=\" {$sel_null}>{$lbl_null}</option>";
				$opts_html .= "<option value=\"*\" {$sel_nnull}>{$lbl_nnull}</option>";
			}

			foreach ($def['options'] as $opt_k => $opt_v) { // Položky číselníku nebo relace
				$k_str = (string) $opt_k; // Klíč volby
				$sel = (strcasecmp($k_str, $cur_val) === 0) ? 'selected' : ''; // Označení vybrané položky
				$opts_html .= '<option value="' . htmlspecialchars($k_str) . '" ' . $sel . '>' . htmlspecialchars((string) $opt_v) . '</option>'; // Volba
			}

			return "<select id=\"{$inp_id}\" name=\"{$inp_name}\" data-filter-col=\"{$safe_col}\" oninput=\"isFormDirty = false;\" style=\"{$inp_style}\">{$opts_html}</select>"; // HTML select
		}

		if ($ftype === 'number') { // Jednořádkové pole pro číselný výraz
			$ph = htmlspecialchars($this->phrase('ph_number_expr', 'např. 10..50, >=25, <>0, 1;2;5 nebo = (prázdné)')); // Placeholder čísla
			return "<input type=\"text\" id=\"{$inp_id}\" name=\"{$inp_name}\" data-filter-col=\"{$safe_col}\" value=\"{$safe_val}\" placeholder=\"{$ph}\" oninput=\"isFormDirty = false;\" style=\"{$inp_style}\">"; // Input
		}

		if ($ftype === 'date') { // Jednořádkové pole pro datumový výraz
			$ph = htmlspecialchars($this->phrase('ph_date_expr', 'např. 1.1.2026..31.12.2026, >=2026-01-01 nebo = (prázdné)')); // Placeholder data
			return "<input type=\"text\" id=\"{$inp_id}\" name=\"{$inp_name}\" data-filter-col=\"{$safe_col}\" value=\"{$safe_val}\" placeholder=\"{$ph}\" oninput=\"isFormDirty = false;\" style=\"{$inp_style}\">"; // Input
		}

		$ph = htmlspecialchars($this->phrase('ph_text_expr', 'slovo (obsahuje), slovo*, *slovo, =přesně, !není, = (prázdné)')); // Placeholder textu
		return "<input type=\"text\" id=\"{$inp_id}\" name=\"{$inp_name}\" data-filter-col=\"{$safe_col}\" value=\"{$safe_val}\" placeholder=\"{$ph}\" oninput=\"isFormDirty = false;\" style=\"{$inp_style}\">"; // Input
	}

	/**
	 * Jednorázově vloží do stránky CSS styly a JS obsluhu modálního okna rozšířeného filtru.
	 */
	private function render_assets_once(string $default_modal_id): string { // CSS a JS pro modální filtr
		if (self::$assets_rendered) { // Pokud již byly styly a skripty vloženy
			return ''; // Nevypisujeme duplicitně
		}
		self::$assets_rendered = true; // Označení vložených zdrojů
		$js_def_id = addslashes($default_modal_id); // Výchozí ID modálu pro JS

		return <<<HTML
		<style>
			.bcm-flt-modal-overlay {
				position: fixed;
				inset: 0;
				background-color: rgba(15, 23, 42, 0.55);
				z-index: 99995;
				display: none;
				align-items: center;
				justify-content: center;
				padding: 20px;
				box-sizing: border-box;
			}
			.bcm-flt-modal-overlay.active { display: flex; }
			.bcm-flt-modal-dialog {
				background-color: #ffffff;
				width: min(760px, 95vw);
				max-height: 88vh;
				border-radius: 6px;
				box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
				display: flex;
				flex-direction: column;
				overflow: hidden;
				border: 1px solid #94a3b8;
			}
			.bcm-flt-modal-header {
				display: flex;
				justify-content: space-between;
				align-items: center;
				padding: 10px 16px;
				background-color: #f1f5f9;
				border-bottom: 1px solid #cbd5e1;
			}
			.bcm-flt-modal-body {
				flex: 1 1 auto;
				overflow-y: auto;
				padding: 14px 16px;
			}
			.bcm-flt-modal-footer {
				display: flex;
				justify-content: space-between;
				align-items: center;
				gap: 10px;
				padding: 10px 16px;
				background-color: #f8fafc;
				border-top: 1px solid #cbd5e1;
				flex-wrap: wrap;
			}
		</style>
		<script>
			(function() {
				window.bcmOpenFilterModal = function(modalId) {
					const id = modalId ? modalId : '{$js_def_id}';
					const el = document.getElementById(id);
					if (!el) return;
					el.classList.add('active');
					el.style.display = 'flex';
					const firstInp = el.querySelector('input[type="text"], select');
					if (firstInp) {
						setTimeout(function() { firstInp.focus(); }, 30);
					}
				};

				window.bcmCloseFilterModal = function(modalId) {
					const id = modalId ? modalId : '{$js_def_id}';
					const el = document.getElementById(id);
					if (!el) return;
					el.classList.remove('active');
					el.style.display = 'none';
				};

				window.bcmToggleFilterExtraRows = function(modalId) {
					const id = modalId ? modalId : '{$js_def_id}';
					const tbody = document.getElementById(id + '-extra-tbody');
					const btn = document.getElementById(id + '-toggle-extra');
					if (!tbody ? true : !btn) return;
					const isHidden = (tbody.style.display === 'none');
					const lblLess = btn.getAttribute('data-lbl-less');
					const lblMore = btn.getAttribute('data-lbl-more');
					tbody.style.display = isHidden ? 'table-row-group' : 'none';
					btn.textContent = isHidden ? (lblLess ? lblLess : '') : (lblMore ? lblMore : '');
				};

				window.bcmResetModalFilter = function(modalId) {
					const id = modalId ? modalId : '{$js_def_id}';
					const el = document.getElementById(id);
					if (!el) return;
					el.querySelectorAll('input[data-filter-col], select[data-filter-col]').forEach(function(inp) {
						inp.value = '';
					});
					window.bcmSubmitModalFilter(id);
				};

				window.bcmSubmitModalFilter = function(modalId) {
					const id = modalId ? modalId : '{$js_def_id}';
					const form = document.getElementById(id + '-form');
					if (typeof isFormDirty !== 'undefined') {
						isFormDirty = false;
					}
					if (form) {
						form.submit();
					}
				};

				document.addEventListener('keydown', function(ev) {
					if (ev.key === 'Escape') {
						const el = document.getElementById('{$js_def_id}');
						if (el && (el.classList.contains('active') ? true : el.style.display === 'flex')) {
							window.bcmCloseFilterModal('{$js_def_id}');
						}
					}
				});
			})();
		</script>
HTML;
	}

	/**
	 * Vykreslí kompletní HTML modálního okna pro vícepoložkové filtrování
	 * s progresivním rozbalením „Zobrazit vše“.
	 */
	public function render_modal(string $form_action = '', string $modal_id = 'bcm-flt-modal-overlay'): string { // Vykreslení modálního okna
		$assets_html = $this->render_assets_once($modal_id); // Jednorázové vložení CSS a JS
		$safe_modal_id = htmlspecialchars($modal_id); // Ošetřené ID modálního kontejneru
		$safe_action = htmlspecialchars($form_action); // Ošetřená URL akce formuláře
		$title_txt = htmlspecialchars($this->phrase('hdr_modal_filter', 'Rozšířené filtrování záznamů')); // Titulek modálu
		$help_str  = htmlspecialchars($this->phrase('help_syntax_string', 'Texty: slovo (obsahuje), slovo* (začíná), *slovo (končí), =text (přesně), !text (neobsahuje), = (nezadáno), * (zadáno).')); // Nápověda textů
		$help_num  = htmlspecialchars($this->phrase('help_syntax_number', 'Čísla a data: 10..50 (interval), 10.., ..50, >=10, <=50, <>0, seznam oddělený ; a samotné = (nezadáno / NULL).')); // Nápověda čísel

		$basic_rows_html = ''; // Řádky základních položek
		$extra_rows_html = ''; // Řádky ostatních položek (pod „Zobrazit vše“)
		$extra_count = 0; // Počet schovaných rozšiřujících položek
		$has_active_extra = false; // Zda je vyplněna některá rozšiřující položka

		foreach ($this->fields as $name => $def) { // Průchod všemi filtrovatelnými poli
			$lbl = htmlspecialchars((string) $def['label']); // Popisek pole
			$inp_html = $this->render_field_input($name); // HTML vstupního prvku
			$err_txt = isset($this->errors[$name])
				? '<div style="color:#b91c1c; font-size:11px; margin-top:3px; font-weight:bold;">' . htmlspecialchars($this->errors[$name]) . '</div>'
				: ''; // Případná validační chyba pole

			$tr_html = "<tr>"
				. "<td style=\"width: 36%; font-weight: bold; background-color: #f8fafc; vertical-align: middle;\">{$lbl}</td>"
				. "<td>{$inp_html}{$err_txt}</td>"
				. "</tr>\n"; // HTML řádku v tabulce filtru

			if (! empty($def['is_basic'])) { // Základní položka (viditelná ihned)
				$basic_rows_html .= $tr_html; // Přidání do základní tabulky
			} else {
				$extra_rows_html .= $tr_html; // Přidání do rozbalovací tabulky
				$extra_count++; // Zvýšení počtu rozšiřujících položek
				if (isset($this->values[$name]) AND $this->values[$name] !== '') { // Pokud má rozšiřující položka hodnotu
					$has_active_extra = true; // Rozšiřující sekci rovnou rozbalíme
				}
			}
		}

		$extra_disp = $has_active_extra ? 'table-row-group' : 'none'; // Výchozí viditelnost rozšiřující sekce
		$btn_show_all_lbl = htmlspecialchars($this->phrase('btn_show_all_fields', 'Zobrazit vše (+{' . chr(36) . 'count} dalších položek)', ['count' => $extra_count])); // Tlačítko Zobrazit vše
		$btn_hide_extra_lbl = htmlspecialchars($this->phrase('btn_hide_extra_fields', 'Skrýt rozšiřující položky')); // Tlačítko Skrýt
		$init_toggle_lbl = $has_active_extra ? $btn_hide_extra_lbl : $btn_show_all_lbl; // Počáteční popisek přepínače

		$btn_apply_lbl  = htmlspecialchars($this->phrase('btn_apply_filter', 'Použít filtr')); // Tlačítko Použít
		$btn_clear_lbl  = htmlspecialchars($this->phrase('btn_clear_filter', 'Vymazat vše')); // Tlačítko Vymazat
		$btn_cancel_lbl = htmlspecialchars($this->phrase('btn_cancel_modal', 'Zavřít')); // Tlačítko Zavřít

		$toggle_btn_html = ''; // HTML tlačítka Zobrazit vše
		if ($extra_count > 0) { // Pokud existují rozšiřující sloupce
			$toggle_btn_html = "<button type=\"button\" id=\"{$safe_modal_id}-toggle-extra\" class=\"tree-ctrl-link\" style=\"padding: 5px 10px; font-weight: bold; border: 1px solid #cbd5e1; border-radius: 3px; background: #fff; color: #004488; cursor: pointer;\" data-lbl-more=\"{$btn_show_all_lbl}\" data-lbl-less=\"{$btn_hide_extra_lbl}\" onclick=\"window.bcmToggleFilterExtraRows('{$safe_modal_id}');\">{$init_toggle_lbl}</button>";
		}

		$global_err = $this->get_error_message(); // Souhrnná chybová zpráva při neplatném výrazu
		$err_banner = ($global_err !== '')
			? '<div class="msg-err" style="margin-bottom: 10px; padding: 8px 10px; font-size: 12px;">' . htmlspecialchars($global_err) . '</div>'
			: ''; // Červený pruh chyby v modálu

		return <<<HTML
		{$assets_html}
		<div id="{$safe_modal_id}" class="bcm-flt-modal-overlay" onclick="if(event.target===this) window.bcmCloseFilterModal('{$safe_modal_id}');">
			<form id="{$safe_modal_id}-form" method="post" action="{$safe_action}" onsubmit="if(typeof isFormDirty!=='undefined')isFormDirty=false;" class="bcm-flt-modal-dialog" onclick="event.stopPropagation();">
				<input type="hidden" name="adv_filter_submit" value="1">
				<div class="bcm-flt-modal-header">
					<h3 style="margin: 0; font-size: 15px; color: #004488;">{$title_txt}</h3>
					<button type="button" onclick="window.bcmCloseFilterModal('{$safe_modal_id}');" style="font-weight: bold; padding: 2px 8px; border: 1px solid #cbd5e1; border-radius: 3px; background: #fff; cursor: pointer;">✕</button>
				</div>
				<div class="bcm-flt-modal-body">
					{$err_banner}
					<div style="background-color: #f0f9ff; border-left: 3px solid #0284c7; padding: 6px 10px; font-size: 11px; color: #0369a1; line-height: 1.4; margin-bottom: 10px;">
						<div><strong>•</strong> {$help_str}</div>
						<div><strong>•</strong> {$help_num}</div>
					</div>
					<table class="md-table" style="margin-bottom: 8px;">
						<tbody id="{$safe_modal_id}-basic-tbody">
							{$basic_rows_html}
						</tbody>
						<tbody id="{$safe_modal_id}-extra-tbody" style="display: {$extra_disp}; border-top: 2px dashed #94a3b8;">
							{$extra_rows_html}
						</tbody>
					</table>
				</div>
				<div class="bcm-flt-modal-footer">
					<div>{$toggle_btn_html}</div>
					<div style="display: flex; gap: 8px; align-items: center;">
						<button type="button" class="btn btn-secondary" style="padding: 7px 12px;" onclick="window.bcmResetModalFilter('{$safe_modal_id}');">{$btn_clear_lbl}</button>
						<button type="button" class="btn btn-secondary" style="padding: 7px 12px;" onclick="window.bcmCloseFilterModal('{$safe_modal_id}');">{$btn_cancel_lbl}</button>
						<button type="submit" class="btn btn-success" style="padding: 7px 16px;">{$btn_apply_lbl}</button>
					</div>
				</div>
			</form>
		</div>
HTML;
	}

	/**
	 * Zpětně kompatibilní aliasy pro render_modal().
	 */
	public function render_filter_modal(string $form_action = '', string $modal_id = 'bcm-flt-modal-overlay'): string { // Alias pro render_modal
		return $this->render_modal($form_action, $modal_id); // Delegování na render_modal
	}

	public function render_modal_html(string $modal_id = 'bcm-flt-modal-overlay'): string { // Alias pro render_modal
		return $this->render_modal('', $modal_id); // Delegování na render_modal
	}
}