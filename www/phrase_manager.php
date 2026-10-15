<?php
/**
 * =============================================================================
 * Verze: 2026-10-15 22:18
 * Soubor: phrase_manager.php
 * Třída: phrase_manager
 * Účel: Centralizovaný správce pro dávkové načítání, kešování, lokalizaci
 *       a interpolaci textových frází (globálních i specifických pro třídy/stránky).
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Instancován v `abstract_page` (a uložen v `$GLOBALS['phrase_manager']`).
 * - Využívá `language_manager` (`language_manager.php`) pro získání fallback řetězce jazyků.
 * - Využívá globální pole `$dbsession` (inicializované v `OsirisLib.php`).
 * - Čte a při auto-discovery zapisuje do tabulky `meta_phrase` (`table_meta_phrase.sql`)
 *   a zajišťuje registraci zdrojového objektu typu 'P' v `meta_object`.
 * - Poskytuje kompletní metadata frází (včetně `svg_icon`, `css_class` a `helptext`)
 *   pro vykreslování tlačítek ve třídě `abstract_button`.
 *
 * Změny:
 * 2026-10-15 - První verze třídy s podporou reflexe dědičnosti, dávkového SQL dotazu,
 *              interpolace proměnných {$var} a automatického zápisu chybějících frází.
 * 2026-10-15 - Oprava mezer kolem proměnných a doplnění automatické registrace
 *              chybějícího source_code do meta_object (object_type = 'P').
 * =============================================================================
 */

declare(strict_types=1);

class phrase_manager {

	/** @var array<string, array<string, array<string, string>>> Načtené fráze: [source_code][builtin_code] => data */
	private array $phrases = [];                                             // Interní keš načtených frází

	/** @var array<string, bool> Seznam již načtených source_code v rámci requestu */
	private array $loaded_sources = [];                                      // Evidence načtených zdrojových tříd

	/** @var array<int, string> Pořadí prohledávání tříd od nejspecifičtější po globální ('') */
	private array $lookup_chain = [''];                                      // Řetězec tříd pro dědění frází

	private language_manager $lang_manager;                                  // Instance správce jazyků
	private bool $table_exists = false;                                      // Příznak existence tabulky meta_phrase

	/**
	 * Konstruktor správce frází.
	 *
	 * @param object|string|null $context_object Instance stránky nebo název třídy pro reflexi závislostí
	 * @param array<int, string> $extra_sources  Další komponenty k načtení v jedné dávce (např. 'abstract_button')
	 */
	public function __construct(object|string|null $context_object = null, array $extra_sources = ['abstract_button', 'user_context', 'menu_manager']) {
		$this->lang_manager = new language_manager();                        // Inicializace správce jazyků
		$this->check_table_exists();                                         // Ověření existence tabulky v DB

		$sources_to_load = [''];                                             // Vždy načítáme globální fráze ('')

		if ($context_object !== null) {
			$hierarchy = $this->resolve_class_dependencies($context_object); // Zjištění hierarchie dědičnosti třídy
			$this->lookup_chain = array_merge($hierarchy, ['']);             // Pořadí hledání: potomek -> předek -> globální
			$sources_to_load = array_merge($sources_to_load, $hierarchy);    // Přidání hierarchie do dávky
		}

		if (!empty($extra_sources)) {
			$sources_to_load = array_merge($sources_to_load, $extra_sources); // Přidání doplňkových komponent
		}

		$this->load_sources($sources_to_load);                               // Jednorázové dávkové načtení z DB
	}

	/**
	 * Ověří, zda v databázi již existuje tabulka meta_phrase (pojistka pro postupné nasazení).
	 */
	private function check_table_exists(): void {
		$q = sqlrun("SELECT OBJECT_ID('meta_phrase') AS obj_id");            // Dotaz na existenci tabulky
		if ($row = fetch($q)) {
			$this->table_exists = !empty($row['obj_id']);                    // Nastavení příznaku existence
		}
		free_result($q);                                                     // Uvolnění výsledku dotazu
	}

	/**
	 * Pomocí PHP reflexe zjistí celý řetězec dědičnosti třídy (extends)
	 * i případné typované vlastnosti objektu, aby se všechny fráze načetly jedním dotazem.
	 *
	 * @param object|string $target Objekt stránky nebo název třídy
	 * @return array<int, string> Seznam názvů tříd od potomka po nejvyššího předka
	 */
	private function resolve_class_dependencies(object|string $target): array {
		$class_name = is_object($target) ? get_class($target) : $target;     // Zjištění názvu hlavní třídy
		if (!class_exists($class_name)) {
			return [$class_name];                                            // Fallback pokud třída neexistuje
		}

		$chain = [$class_name];                                              // Začínáme samotnou třídou potomka
		$parents = class_parents($class_name);                               // Zjištění všech předků přes reflexi
		if (is_array($parents)) {
			foreach ($parents as $parent_class) {
				$chain[] = $parent_class;                                    // Přidání předka do řetězce
			}
		}

		// Reflexe vlastností třídy: pokud má třída typované vlastnosti odkazující na jiné komponenty,
		// zařadíme jejich třídy rovněž do dávkového načtení.
		$ref = new ReflectionClass($class_name);                             // Reflexe cílové třídy
		foreach ($ref->getProperties() as $prop) {
			$type = $prop->getType();                                        // Získání datového typu vlastnosti
			if ($type instanceof ReflectionNamedType && !$type->isBuiltin()) {
				$prop_class = $type->getName();                              // Název třídy typované vlastnosti
				if (!in_array($prop_class, $chain, true)) {
					$chain[] = $prop_class;                                  // Přidání komponenty do seznamu
				}
			}
		}

		return $chain;                                                       // Vrácení kompletního seznamu tříd
	}

	/**
	 * Načte jedním SQL dotazem všechny fráze pro zadané zdrojové třídy (source_code)
	 * včetně vyhodnocení kaskádového COALESCE pro jazyky a tenant overrides.
	 *
	 * @param array<int, string> $sources Seznam identifikátorů source_code
	 */
	public function load_sources(array $sources): void {
		if (!$this->table_exists) {
			return;
		}

		$new_sources = [];                                                   // Seznam dosud nenačtených tříd
		foreach (array_unique($sources) as $src) {
			$src_key = (string)$src;                                         // Převod na řetězec
			if (!isset($this->loaded_sources[$src_key])) {
				$new_sources[] = charliteral($src_key);                      // SQL literál názvu třídy
				$this->loaded_sources[$src_key] = true;                      // Označení třídy jako načtené
				if (!isset($this->phrases[$src_key])) {
					$this->phrases[$src_key] = [];                           // Inicializace pole pro třídu
				}
			}
		}

		if (empty($new_sources)) {
			return;
		}

		$in_clause = implode(', ', $new_sources);                            // Složení klauzule IN (...)
		$lang_chain = $this->lang_manager->get_fallback_chain();             // Fallback řetězec jazyků

		$coal_caption = [];                                                  // Kaskáda pro sloupec caption
		$coal_helptext = [];                                                 // Kaskáda pro sloupec helptext
		$joins = "";                                                         // Dynamické LEFT JOINy pro jazyky

		foreach ($lang_chain as $lang) {
			$coal_caption[] = "NULLIF(CAST(v_{$lang}.caption AS NVARCHAR(MAX)), '')";
			$coal_caption[] = "NULLIF(CAST(l_{$lang}.caption AS NVARCHAR(MAX)), '')";

			$coal_helptext[] = "NULLIF(CAST(v_{$lang}.helptext AS NVARCHAR(MAX)), '')";
			$coal_helptext[] = "NULLIF(CAST(l_{$lang}.helptext AS NVARCHAR(MAX)), '')";

			$joins .= "\n\t\tLEFT JOIN meta_phrase l_{$lang} ON l_{$lang}.original = m.original AND l_{$lang}.object_owner = 0x00 AND l_{$lang}.language = '{$lang}' AND l_{$lang}.record_type = 'L' AND l_{$lang}.removed = 0";
			$joins .= "\n\t\tLEFT JOIN meta_phrase v_{$lang} ON v_{$lang}.original = m.original AND v_{$lang}.object_owner = s.organization_uuid AND v_{$lang}.language = '{$lang}' AND v_{$lang}.record_type = 'L' AND v_{$lang}.removed = 0";
		}

		$coal_caption[] = "NULLIF(CAST(m.caption AS NVARCHAR(MAX)), '')";
		$coal_caption[] = "NULLIF(CAST(o.caption AS NVARCHAR(MAX)), '')";
		$coal_caption[] = "''";                                              // Nouzový prázdný řetězec pro caption

		$coal_helptext[] = "NULLIF(CAST(m.helptext AS NVARCHAR(MAX)), '')";
		$coal_helptext[] = "NULLIF(CAST(o.helptext AS NVARCHAR(MAX)), '')";
		$coal_helptext[] = "''";                                             // Nouzový prázdný řetězec pro helptext

		$caption_expr = "COALESCE(" . implode(', ', $coal_caption) . ")";    // Výsledný SQL výraz pro caption
		$helptext_expr = "COALESCE(" . implode(', ', $coal_helptext) . ")";  // Výsledný SQL výraz pro helptext

		$sql = "
		WITH s AS (
			SELECT organization AS organization_uuid FROM dbsession WHERE spid = @@SPID
		),
		sy AS (
			SELECT rc.*
			FROM s JOIN meta_phrase rc ON rc.object_owner = 0x00 AND rc.record_type = 'A'
			WHERE rc.removed = 0 AND rc.inactive = 0 AND rc.source_code IN ({$in_clause})
		),
		my AS (
			SELECT rc.*
			FROM s JOIN meta_phrase rc ON rc.object_owner = s.organization_uuid AND rc.record_type = 'A'
			WHERE rc.removed = 0 AND rc.inactive = 0 AND rc.source_code IN ({$in_clause})
		),
		mix AS (
			SELECT sy.* FROM sy LEFT JOIN my ON my.original = sy.original WHERE my.original IS NULL
			UNION ALL
			SELECT * FROM my
		)
		SELECT
			m.source_code,
			m.builtin_code,
			{$caption_expr} AS caption,
			{$helptext_expr} AS helptext,
			COALESCE(NULLIF(CAST(m.svg_icon AS NVARCHAR(MAX)), ''), CAST(o.svg_icon AS NVARCHAR(MAX)), '') AS svg_icon,
			COALESCE(NULLIF(m.css_class, ''), o.css_class, '') AS css_class
		FROM s
		CROSS JOIN mix m
		LEFT JOIN meta_phrase o ON o.original = m.original AND o.object_owner = 0x00 AND o.record_type = 'A'
		{$joins}
		";

		$q = sqlrun($sql);                                                   // Spuštění dávkového dotazu frází
		while ($row = fetch($q)) {
			$src = (string)$row['source_code'];                              // Zdrojová třída fráze
			$code = (string)$row['builtin_code'];                            // Kód konkrétní fráze
			$this->phrases[$src][$code] = [                                  // Uložení atributů fráze do keše
				'caption'   => (string)$row['caption'],                      // Přeložený text fráze
				'helptext'  => (string)$row['helptext'],                     // Přeložená nápověda / tooltip
				'svg_icon'  => (string)$row['svg_icon'],                     // Kód vektorové ikony SVG
				'css_class' => (string)$row['css_class']                     // Doplňková CSS třída
			];
		}
		free_result($q);                                                     // Uvolnění výsledku dávkového dotazu
	}

	/**
	 * Vrátí kompletní sadu atributů fráze (caption, helptext, svg_icon, css_class).
	 * Pokud fráze v databázi neexistuje a je zadán $default_caption, automaticky ji založí.
	 *
	 * @param string $builtin_code    Identifikátor fráze (např. 'btn_save', 'confirm_delete')
	 * @param string $default_caption Výchozí text pro případ, že fráze v DB dosud neexistuje
	 * @param string $source_code     Explicitní určení třídy (pokud prázdné, prohledá se lookup_chain)
	 * @param string $default_svg     Výchozí SVG ikona při automatickém založení
	 * @param string $default_css     Výchozí CSS třída při automatickém založení
	 * @return array{caption: string, helptext: string, svg_icon: string, css_class: string}
	 */
	public function get_meta(
		string $builtin_code,
		string $default_caption = '',
		string $source_code = '',
		string $default_svg = '',
		string $default_css = ''
	): array {
		// 1. Pokud je zadán konkrétní source_code, ujistíme se, že je načten, a hledáme nejprve v něm
		if ($source_code !== '') {
			if (!isset($this->loaded_sources[$source_code])) {
				$this->load_sources([$source_code]);                         // Doffetchnutí chybějící třídy
			}
			if (isset($this->phrases[$source_code][$builtin_code])) {
				return $this->phrases[$source_code][$builtin_code];          // Nalezeno přímo v požadované třídě
			}
			// Fallback na globální frázi ('')
			if (isset($this->phrases[''][$builtin_code])) {
				return $this->phrases[''][$builtin_code];                    // Nalezeno v globálních frázích
			}
		} else {
			// 2. Prohledání celého řetězce dědičnosti (potomek -> předek -> globální '')
			foreach ($this->lookup_chain as $src) {
				if (isset($this->phrases[$src][$builtin_code])) {
					return $this->phrases[$src][$builtin_code];              // Nalezeno v hierarchii stránky
				}
			}
		}

		// 3. Fallback a Auto-discovery: Fráze nebyla v DB nalezena
		$target_source = ($source_code !== '') ? $source_code : ($this->lookup_chain[0] ?? '');
		$fallback_text = ($default_caption !== '') ? $default_caption : "[{$builtin_code}]";

		$meta = [                                                            // Výchozí struktura metadat fráze
			'caption'   => $fallback_text,                                   // Použití výchozího textu
			'helptext'  => '',                                               // Výchozí prázdný helptext
			'svg_icon'  => $default_svg,                                     // Výchozí SVG ikona
			'css_class' => $default_css                                      // Výchozí CSS třída
		];

		// Uložíme do paměti pro tento request, abychom neprováděli opakované INSERTy
		$this->phrases[$target_source][$builtin_code] = $meta;               // Zápis do lokální keše

		// Pokud máme smysluplný výchozí text a tabulka existuje, zapíšeme chybějící frázi do DB
		if ($this->table_exists && $default_caption !== '') {
			$this->auto_register_phrase($target_source, $builtin_code, $default_caption, $default_svg, $default_css);
		}

		return $meta;                                                        // Vrácení metadat fráze
	}

	/**
	 * Vrátí výsledný text fráze s bezpečně dosazenými proměnnými {$var}.
	 *
	 * @param string               $builtin_code    Identifikátor fráze
	 * @param array<string, mixed> $vars            Asociativní pole proměnných pro nahrazení {$klic}
	 * @param string               $default_caption Výchozí text při neexistenci v DB
	 * @param string               $source_code     Volitelný explicitní název zdrojové třídy
	 * @return string Výsledný přeložený text s dosazenými proměnnými
	 */
	public function get(
		string $builtin_code,
		array $vars = [],
		string $default_caption = '',
		string $source_code = ''
	): string {
		$meta = $this->get_meta($builtin_code, $default_caption, $source_code); // Načtení metadat fráze
		return $this->interpolate($meta['caption'], $vars);                  // Vrácení textu po dosazení proměnných
	}

	/**
	 * Bezpečně nahradí zástupné symboly {$var} v textu hodnotami z pole $vars nebo$GLOBALS.
	 * Nepoužívá nebezpečný eval().
	 *
	 * @param string               $text Text šablony obsahující {$promenne}
	 * @param array<string, mixed> $vars Explicitně předané proměnné
	 * @return string Text s nahrazenými hodnotami
	 */
	public function interpolate(string $text, array $vars = []): string {
		if (!str_contains($text, '{' . chr(36))) {
			return $text;                                                    // Rychlý návrat pokud text nemá proměnné
		}

		$pattern = '/\{\$([a-zA-Z0-9_]+)\}/';                                // Regulární výraz pro {$identifikator}
		return (string)preg_replace_callback($pattern, function(array $matches) use ($vars): string {
			$var_name = $matches[1];                                         // Název nalezené proměnné bez {$}
			if (array_key_exists($var_name, $vars)) {
				return (string)$vars[$var_name];                             // Přednost má explicitně předaná proměnná
			}
			if (array_key_exists($var_name, $GLOBALS) && is_scalar($GLOBALS[$var_name])) {
				return (string)$GLOBALS[$var_name];                          // Fallback na skalární globální proměnnou
			}
			return $matches[0];                                              // Ponechání původního zástupce při nenalezení
		}, $text);
	}

	/**
	 * Automaticky zaregistruje dosud neexistující frázi do tabulky meta_phrase (A + symetrické L)
	 * a zajistí existenci zdrojové třídy v meta_object (typ 'P'),
	 * aby se následně objevila ve vygenerovaném souboru meta_object.xlsx.
	 */
	private function auto_register_phrase(
		string $source_code,
		string $builtin_code,
		string $caption,
		string $svg_icon = '',
		string $css_class = ''
	): void {
		global $dbsession;                                                   // Globální kontext relace
		$user_session = guidliteral((string)($dbsession['login_session_uuid'] ?? '0x00'));

		$safe_src = charliteral($source_code, 80);                           // SQL literál source_code
		$safe_code = charliteral($builtin_code, 80);                         // SQL literál builtin_code
		$safe_cap = charliteral($caption);                                   // SQL literál výchozího textu
		$safe_svg = charliteral($svg_icon);                                  // SQL literál SVG ikony
		$safe_css = charliteral($css_class, 200);                            // SQL literál CSS třídy

		$sql = "
		DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
		DECLARE @obj_orig uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', {$safe_src});
		DECLARE @orig uuid = dbo.f_generate_original('meta_phrase', @sys_owner, {$safe_src}, {$safe_code});

		IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @obj_orig AND object_owner = @sys_owner AND record_type = 'A')
		BEGIN
			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, [language],
				import_origin, object_type, builtin_code, system_role, caption,
				who_created, who_modified
			) VALUES (
				@obj_orig, @sys_owner, @obj_orig, 'A', 'A', 'cs',
				'AUTO_DISCOVERED', 'P', {$safe_src}, 'U', {$safe_src},
				{$user_session}, {$user_session}
			);
		END

		IF NOT EXISTS (SELECT 1 FROM meta_phrase WHERE original = @orig AND object_owner = @sys_owner AND record_type = 'A')
		BEGIN
			INSERT INTO meta_phrase (
				uuid, object_owner, original, record_type, approval_status, [language],
				import_origin, source_code, builtin_code, caption, svg_icon, css_class,
				who_created, who_modified
			) VALUES (
				@orig, @sys_owner, @orig, 'A', 'A', 'cs',
				'AUTO_DISCOVERED', {$safe_src}, {$safe_code}, {$safe_cap}, {$safe_svg}, {$safe_css},
				{$user_session}, {$user_session}
			);

			INSERT INTO meta_phrase (
				uuid, object_owner, original, record_type, approval_status, [language],
				import_origin, source_code, builtin_code, caption, svg_icon, css_class,
				who_created, who_modified
			) VALUES (
				NEWID(), @sys_owner, @orig, 'L', 'A', 'cs',
				'AUTO_DISCOVERED', {$safe_src}, {$safe_code}, {$safe_cap}, {$safe_svg}, {$safe_css},
				{$user_session}, {$user_session}
			);
		END
		";

		sqlrun($sql);                                                        // Zápis nově objevené fráze do DB
	}
}