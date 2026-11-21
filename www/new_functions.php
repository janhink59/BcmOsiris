<?php
/**
 * =============================================================================
 * Verze: 2026-11-21 11:30
 * Soubor: new_functions.php
 *
 * 1. Role souboru v celém systému:
 *    Nové a sjednocené globální procedurální pomocné funkce pro BCM Osiris.
 *    Vyčleněno do samostatného souboru mimo OsirisLib.php kvůli udržení
 *    velikosti souborů pod limitem 50 KB (samostatné třídy mají vlastní soubory).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Načítán z config.php bezprostředně po OsirisLib.php.
 *    - Poskytuje funkce pro kontrolu systémového kontextu (is_zero_guid,
 *      is_sys_org, has_role_access, get_session_org, get_session_lang,
 *      get_session_role), funkci generate_builtin_code(), univerzální
 *      překladovou funkci translate_phrase(), kešovanou kontrolu existence
 *      DB objektu db_object_exists() a kešované vyhodnocení stupňů hodnotících
 *      škál resolve_scale_level_badge().
 *
 * 3. Očekávaná kontextová data:
 *    - Čte globální pole $dbsession (naplněné procedurou p_init_wwwsession
 *      z tabulky dbsession pro aktuální @@SPID) a $GLOBALS['phrase_manager'].
 *
 * Změny:
 * 2026-11-21 11:30 - V resolve_scale_level_badge() vyloučeny oblastní škály
 *                    vodítek (is_area_guideline = 1) z výběru globální primární
 *                    škály a pro scale_type = 'IMPACT' upřednostněna výchozí
 *                    škála organizace (organization.default_impact_scale_uuid).
 * 2026-11-16 15:25 - Doplněny funkce db_object_exists() (se statickou keší
 *                    v requestu) a resolve_scale_level_badge() (se statickou
 *                    keší stupňů škál v paměti pro eliminaci opakovaných dotazů).
 * 2026-11-05 10:15 - Doplněna funkce generate_builtin_code() pro převod českého
 *                    názvu/zkratky na platný identifikátor builtin_code (snake_case).
 * 2026-11-04 10:30 - Union typy se svislítkem u translate_phrase() nahrazeny
 *                    typem mixed dle Anti-LaTeX pravidla.
 * =============================================================================
 */

declare(strict_types=1);

/**
 * Ověří, zda předaný identifikátor představuje systémovou nulu (0x00 nebo nulové UUID).
 */
function is_zero_guid(mixed $guid): bool {                                   // Kontrola nulového systémového identifikátoru
	$clean = strtolower(trim((string) ($guid ?? '')));                       // Normalizace řetězce na malá písmena bez mezer
	return ($clean === '' OR $clean === '0x00' OR$clean === '00000000-0000-0000-0000-000000000000'); // Vyhodnocení nulového UUID
}

/**
 * Vrátí surové UUID aktivní organizace z globálního pole $dbsession (výchozí '0x00').
 */
function get_session_org(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$org = trim((string) ($dbsession['organization'] ?? '0x00'));            // Načtení organizace z relace
	return ($org !== '') ?$org : '0x00';                                    // Vrácení organizace nebo 0x00
}

/**
 * Vrátí dvoupísmenný kód aktivního jazyka z $dbsession (výchozí 'cs').
 */
function get_session_lang(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$lang = trim((string) ($dbsession['language'] ?? 'cs'));                 // Načtení kódu jazyka z relace
	return ($lang !== '') ?$lang : 'cs';                                    // Vrácení jazyka nebo 'cs'
}

/**
 * Vrátí kód efektivní aplikační role uživatele z $dbsession ('U', 'A', 'S', 'D').
 */
function get_session_role(): string {
	global $dbsession;                                                       // Globální pole databázové relace
	$role = strtoupper(trim((string) ($dbsession['active_role'] ?? 'U')));   // Načtení aktivní role z relace
	return in_array($role, ['U', 'A', 'S', 'D'], true) ?$role : 'U';        // Validace proti povoleným rolím
}

/**
 * Určí, zda zadaná organizace (nebo aktuální organizace v $dbsession) je systémová master organizace (0x00).
 */
function is_sys_org(?string $org_uuid = null): bool {                        // Kontrola systémové organizace 0x00
	$target_org = ($org_uuid !== null) ?$org_uuid : get_session_org();      // Použití předané nebo relací dané organizace
	return is_zero_guid($target_org);                                        // Vyhodnocení přes is_zero_guid
}

/**
 * Ověří, zda aktuální role uživatele (nebo explicitně předaná $active_role)
 * splňuje požadovanou minimální úroveň oprávnění ($required_role: 'U' < 'A' < 'S' < 'D').
 */
function has_role_access(string $required_role, ?string $active_role = null): bool { // Kontrola hierarchie oprávnění role
	$act = ($active_role !== null) ? strtoupper(trim($active_role)) : get_session_role(); // Efektivní role uživatele
	$req = strtoupper(trim($required_role));                                 // Požadovaná minimální role

	if ($act === 'D') {                                                      // Developer má přístup ke všem úrovním (U, A, S, D)
		return true;
	}
	if ($act === 'S') {                                                      // Sysadmin má přístup k úrovním U, A, S
		return in_array($req, ['U', 'A', 'S'], true);                        // Kontrola pro Sysadmina
	}
	if ($act === 'A') {                                                      // OrgAdmin má přístup k úrovním U, A
		return in_array($req, ['U', 'A'], true);                             // Kontrola pro OrgAdmina
	}
	return ($req === 'U');                                                   // Běžný uživatel má přístup pouze k úrovni U
}

/**
 * Odvodí platný technický identifikátor (builtin_code v snake_case) ze zadaného názvu nebo zkratky.
 * Spolehlivě odstraní českou a evropskou diakritiku nezávisle na nastavení OS locale.
 */
function generate_builtin_code(string $text, int$max_len = 40): string {    // Odvození builtin_code z názvu nebo zkratky
	$raw = trim(strip_tags($text));                                          // Odstranění případných HTML značek a okrajových mezer
	if ($raw === '') {                                                       // Prázdný vstup vrací prázdný řetězec
		return '';
	}

	$map = [                                                                 // Převodní tabulka české a slovenské diakritiky
		'á' => 'a', 'č' => 'c', 'ď' => 'd', 'é' => 'e', 'ě' => 'e', 'í' => 'i', 'ľ' => 'l', 'ĺ' => 'l',
		'ň' => 'n', 'ó' => 'o', 'ô' => 'o', 'ř' => 'r', 'ŕ' => 'r', 'š' => 's', 'ť' => 't', 'ú' => 'u',
		'ů' => 'u', 'ý' => 'y', 'ž' => 'z', 'ä' => 'a', 'ö' => 'o', 'ü' => 'u', 'ß' => 'ss',
		'Á' => 'a', 'Č' => 'c', 'Ď' => 'd', 'É' => 'e', 'Ě' => 'e', 'Í' => 'i', 'Ľ' => 'l', 'Ĺ' => 'l',
		'Ň' => 'n', 'Ó' => 'o', 'Ô' => 'o', 'Ř' => 'r', 'Ŕ' => 'r', 'Š' => 's', 'Ť' => 't', 'Ú' => 'u',
		'Ů' => 'u', 'Ý' => 'y', 'Ž' => 'z', 'Ä' => 'a', 'Ö' => 'o', 'Ü' => 'u'
	];                                                                       // Konec převodní tabulky
	$ascii = strtr($raw,$map);                                              // Nahrazení českých a evropských znaků
	$trans = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE',$ascii);             // Doplňková transliterace zbylých znaků
	if (is_string($trans) AND$trans !== '') {                               // Pokud iconv vrátil platný řetězec
		$ascii =$trans;                                                     // Použijeme výsledek iconv
	}

	$lower = strtolower($ascii);                                             // Převod na malá písmena
	$snake = (string) preg_replace('/[^a-z0-9]+/', '_',$lower);             // Nahrazení mezer a symbolů podtržítkem
	$clean = trim($snake, '_');                                              // Odstranění okrajových podtržítek
	if ($max_len > 0 AND strlen($clean) >$max_len) {                        // Omezení na požadovanou maximální délku
		$clean = rtrim(substr($clean, 0,$max_len), '_');                    // Oříznutí bez koncového podtržítka
	}
	return $clean;                                                           // Vrácení čistého identifikátoru
}

/**
 * Sjednocený globální helper pro překlad a interpolaci frází přes $GLOBALS['phrase_manager'].
 * Podporuje obě konvence volání: (kód, výchozí text, proměnné) i (kód, proměnné, výchozí text).
 *
 * @param string $builtin_code    Kód fráze v meta_phrase
 * @param mixed  $default_caption Výchozí český text (nebo pole proměnných)
 * @param mixed  $vars            Proměnné pro interpolaci (nebo výchozí text)
 * @param string $source_code     Zdrojová třída (prázdné = prohledá lookup_chain)
 * @return string Přeložený a interpolovaný text fráze
 */
function translate_phrase(string $builtin_code, mixed$default_caption = '', mixed $vars = [], string$source_code = ''): string { // Překlad fráze
	if (is_array($default_caption)) {                                        // Pokud bylo voláno s konvencí (kód, proměnné, výchozí text)
		$actual_vars =$default_caption;                                     // Pole proměnných z 2. parametru
		$actual_default = is_string($vars) ?$vars : '';                     // Výchozí text ze 3. parametru
	} else {
		$actual_default = (string)$default_caption;                         // Výchozí text z 2. parametru
		$actual_vars = is_array($vars) ?$vars : [];                         // Pole proměnných ze 3. parametru
	}
	global $phrase_manager;                                                  // Globální instance správce frází
	if (! isset($phrase_manager) OR ! ($phrase_manager instanceof phrase_manager)) { // Kontrola inicializace správce
		$init_src = ($source_code !== '') ?$source_code : 'global_phrase';  // Výchozí kontext při nouzové inicializaci
		$phrase_manager = new phrase_manager($init_src);                     // Vytvoření instance phrase_manager
		$GLOBALS['phrase_manager'] =$phrase_manager;                        // Uložení do globálního kontextu
	}
	return $phrase_manager->get($builtin_code,$actual_vars, $actual_default,$source_code); // Vrácení přeloženého textu
}

/**
 * Kešovaná kontrola existence databázového objektu (tabulky, procedury, funkce nebo pohledu)
 * v rámci jednoho HTTP požadavku. Zabraňuje opakovaným SQL dotazům SELECT OBJECT_ID(...).
 */
function db_object_exists(string $object_name, string$object_type = ''): bool { // Kontrola existence DB objektu s keší
	static $cache = [];                                                      // Statická keš pro aktuální HTTP request
	$key = strtolower(trim($object_name)) . ':' . strtoupper(trim($object_type)); // Unikátní klíč v keši
	if (array_key_exists($key,$cache)) {                                    // Pokud již byl objekt v tomto requestu ověřen
		return $cache[$key];                                                 // Vrácení výsledku z paměti
	}

	$safe_name = charliteral(trim($object_name), 250);                       // SQL literál názvu objektu
	if (trim($object_type) !== '') {                                         // Pokud je specifikován typ objektu ('U', 'P', 'FN'...)
		$safe_type = charliteral(trim($object_type), 10);                    // SQL literál typu objektu
		$row = sqlfirstrow("SELECT OBJECT_ID({$safe_name}, {$safe_type}) AS obj_id"); // Dotaz s typem objektu
	} else {
		$row = sqlfirstrow("SELECT OBJECT_ID({$safe_name}) AS obj_id");      // Obecný dotaz na OBJECT_ID
	}

	$exists = (! empty($row) AND ! empty($row['obj_id']));                   // Vyhodnocení existence objektu
	$cache[$key] =$exists;                                                  // Uložení výsledku do statické keše
	return $exists;                                                          // Vrácení příznaku existence
}

/**
 * Zařadí procentuální skóre (0..100 %) do stupně primární hodnotící škály daného typu (`scale_type`).
 * Při prvním volání v requestu načte všechny stupně aktivních primárních škál (mimo oblastní
 * vodítka `is_area_guideline = 1`, s předností `organization.default_impact_scale_uuid` pro `IMPACT`)
 * jedním dotazem do paměti.
 *
 * @return array{caption: string, shortname: string, color_code: string}
 */
function resolve_scale_level_badge(string $scale_type, float$score): array { // Vyhodnocení stupně škály v paměti
	static $scales_cache = null;                                             // Statická keš stupňů škál pro aktuální request
	static $cache_context = '';                                              // Kontext organizace a jazyka pro keš

	$org_raw = get_session_org();                                            // Surové UUID aktivní organizace
	$lang_raw = get_session_lang();                                          // Kód aktivního jazyka relace
	$curr_ctx = strtolower($org_raw) . ':' . strtolower($lang_raw);          // Klíč kontextu relace

	if ($scales_cache === null OR $cache_context !==$curr_ctx) {            // Jednorázové načtení všech stupňů škál v requestu
		$scales_cache = [];                                                  // Inicializace pole keše
		$cache_context =$curr_ctx;                                          // Uložení kontextu keše

		if (db_object_exists('scale', 'U') AND db_object_exists('scale_value', 'U')) { // Kontrola existence tabulek
			$org_sql = guidliteral($org_raw);                                // SQL literál aktivní organizace
			$lang_sql = charliteral($lang_raw, 2);                           // SQL literál jazyka relace

			$rows = sqlarray_simple("
				SET NOCOUNT ON;
				DECLARE @fl TABLE ([language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY, fallback_order int NOT NULL);
				INSERT INTO @fl ([language], fallback_order) SELECT [language], fallback_order FROM dbo.f_language_list({$lang_sql}) WHERE fallback_order < 1000; -- Jazykový řetězec relace

				DECLARE @org_def_imp_scale uniqueidentifier = NULL;
				SELECT TOP 1 @org_def_imp_scale = default_impact_scale_uuid
				FROM organization
				WHERE original = {$org_sql} -- Výchozí škála dopadů nastavená na organizaci
				  AND record_type = 'A'
				  AND removed = 0;

				DECLARE @win_scale TABLE (
					scale_type varchar(20) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
					scale_orig uniqueidentifier NOT NULL
				);

				INSERT INTO @win_scale (scale_type, scale_orig)
				SELECT scale_type, original
				FROM (
					SELECT UPPER(scale_type) AS scale_type, original,
						ROW_NUMBER() OVER (
							PARTITION BY UPPER(scale_type)
							ORDER BY
								CASE WHEN UPPER(scale_type) = 'IMPACT' AND @org_def_imp_scale IS NOT NULL AND original = @org_def_imp_scale THEN 0 ELSE 1 END ASC,
								CASE WHEN is_default = 1 THEN 0 ELSE 1 END ASC,
								priority ASC,
								CASE WHEN object_owner = {$org_sql} THEN 0 ELSE 1 END ASC, -- Přednost škály tenanta
								sort_code ASC
						) AS rn
					FROM scale
					WHERE object_owner IN ({$org_sql}, 0x00) -- Výběr škály tenanta nebo systému
					  AND record_type = 'A'
					  AND removed = 0
					  AND inactive = 0
					  AND (is_area_guideline = 0 OR (UPPER(scale_type) = 'IMPACT' AND @org_def_imp_scale IS NOT NULL AND original = @org_def_imp_scale))
				) s
				WHERE s.rn = 1;

				SELECT
					ws.scale_type,
					sv.threshold_value,
					COALESCE(tr.caption, NULLIF(sv.caption, ''), sv.builtin_code) AS caption,
					COALESCE(tr.shortname, NULLIF(sv.shortname, ''), '') AS shortname,
					sv.color_code
				FROM @win_scale ws
				JOIN (
					SELECT scale, original, builtin_code, caption, shortname, threshold_value, color_code,
						ROW_NUMBER() OVER (PARTITION BY scale, original ORDER BY CASE WHEN object_owner = {$org_sql} THEN 0 ELSE 1 END) AS rn -- Přednost stupně tenanta
					FROM scale_value
					WHERE object_owner IN ({$org_sql}, 0x00) -- Stupně škály tenanta nebo systému
					  AND record_type = 'A'
					  AND removed = 0
					  AND inactive = 0
				) sv ON sv.scale = ws.scale_orig AND sv.rn = 1
				OUTER APPLY (
					SELECT TOP 1
						NULLIF(CAST(l.caption AS VARCHAR(200)), '') AS caption,
						NULLIF(CAST(l.shortname AS VARCHAR(40)), '') AS shortname
					FROM scale_value l
					JOIN @fl fl ON fl.[language] = l.[language]
					WHERE l.original = sv.original
					  AND l.record_type = 'L'
					  AND l.removed = 0
					  AND l.object_owner IN ({$org_sql}, 0x00) -- Jazykové mutace stupně škály
					  AND (NULLIF(CAST(l.caption AS VARCHAR(200)), '') IS NOT NULL OR NULLIF(CAST(l.shortname AS VARCHAR(40)), '') IS NOT NULL)
					ORDER BY fl.fallback_order ASC, CASE WHEN l.object_owner = {$org_sql} THEN 0 ELSE 1 END ASC -- Pořadí překladu
				) tr
				ORDER BY ws.scale_type ASC, sv.threshold_value DESC;
			");                                                              // Načtení všech stupňů vítězných primárních škál

			if (is_array($rows)) {                                           // Uložení stupňů do paměťové keše (seřazeno sestupně dle prahu)
				foreach ($rows as$r) {                                      // Průchod stupni
					$st_key = strtoupper((string)$r['scale_type']);         // Klíč druhu škály
					$scales_cache[$st_key][] = [                             // Zařazení stupně do keše
						'threshold'  => (float) $r['threshold_value'],
						'caption'    => (string) ($r['caption'] ?? ''),
						'shortname'  => (string) ($r['shortname'] ?? ''),
						'color_code' => (string) ($r['color_code'] ?? '')
					];
				}
			}
		}
	}

	$type_key = strtoupper(trim($scale_type));                               // Hledaný druh škály
	$clamped = max(0.0, min(100.0,$score));                                 // Omezení skóre na interval 0..100 %
	if (! empty($scales_cache[$type_key])) {                                 // Vyhledání prvního stupně s threshold_value <= $clamped
		foreach ($scales_cache[$type_key] as$lvl) {                         // Průchod sestupně od nejvyššího prahu
			if ($clamped + 0.00005 >=$lvl['threshold']) {                   // Nalezen odpovídající stupeň škály
				return [                                                     // Vrácení dat stupně z paměti
					'caption'    => $lvl['caption'],
					'shortname'  => $lvl['shortname'],
					'color_code' => $lvl['color_code']
				];
			}
		}
	}

	return ['caption' => '', 'shortname' => '', 'color_code' => ''];         // Žádná škála pro daný typ nebyla nalezena
}