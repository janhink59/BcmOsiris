<?php
/**
 * =============================================================================
 * Verze: 2026-11-01 11:45
 * Soubor: entity_manager_read.php
 * Trait: entity_manager_read
 * Účel: Čtecí a překladová vrstva třídy entity_manager.
 *       Zajišťuje dvoupolové vyhodnocení překladů v PHP (resolve_field_from_arrays)
 *       a načítání záznamů přes indexované tabulkové proměnné (fetch_rows, fetch_row).
 *
 * VAZBY NA OKOLÍ:
 * - Inkludován a používán výhradně uvnitř třídy `entity_manager` (`entity_manager.php`).
 * - Využívá databázovou funkci `dbo.f_language_list` (`fallback_order < 1000`)
 *   a funkci `dbo.f_get_user_info`.
 * =============================================================================
 */

declare(strict_types=1);

trait entity_manager_read {

	/**
	 * Pomocná metoda: Vyhodnotí přeloženou textovou hodnotu sloupce pro daný 'original'
	 * z hlavního pole 'A' (a_rows) a podřízeného 2D pole 'L' (l_rows) seřazeného dle fallback_order.
	 */
	private function resolve_field_from_arrays(
		string $orig,                                                        // UUID záznamu
		string $col,                                                         // Název sloupce
		array &$a_rows,                                                      // Pole hlavních 'A'/'D' záznamů
		array &$anc_a_rows,                                                  // Pole předků 'A'
		array &$l_rows,                                                      // Podřízené 2D pole 'L' záznamů
		string $curr_lang,                                                   // Aktuální jazyk relace
		array $lang_chain,                                                   // Řetězec jazyků dle fallback_order
		string $anc_key = 'ancestor'                                         // Sloupec vazby na předka
	): string {
		$row = $a_rows[$orig] ?? $anc_a_rows[$orig] ?? null;                 // Nalezení hlavního záznamu 'A'/'D'
		if ($row === null) {                                                 // Pokud záznam neexistuje
			return '';                                                       // Vrátíme prázdný řetězec
		}

		// 0. Pokud je aktivní řádek rozpracovaným konceptem ('D') a má vyplněnou hodnotu, má přednost
		if (($row['record_type'] ?? 'A') === 'D' AND (string)($row[$col] ?? '') !== '') { // Hodnota z konceptu
			return (string)$row[$col];                                       // Vrácení hodnoty konceptu
		}

		$a_lang = (string)($row['native_language'] ?? $row['language'] ?? 'cs'); // Mateřský jazyk hlavního 'A' záznamu
		$a_val = (string)($row[$col] ?? '');                                 // Hodnota v hlavním 'A' záznamu
		$has_tenant_l_curr = (! empty($l_rows[$orig][$curr_lang]['is_tenant_l']) AND (string)($l_rows[$orig][$curr_lang][$col] ?? '') !== ''); // Zda má tenant vlastní L

		// 1. Je-li jazyk 'A' shodný s aktuálním jazykem (a tenant nemá vlastní L override), bereme rovnou 'A'
		if ($a_lang === $curr_lang AND $a_val !== '' AND ! $has_tenant_l_curr) { // Shoda jazyka 'A' s aktuálním jazykem
			return $a_val;                                                   // Není třeba hledat v podřízeném poli
		}

		// 2. Průchod podřízeným polem 'L' seřazeným podle fallback_order (< 1000)
		foreach ($lang_chain as $fl_lang) {                                  // Průchod jazyky dle fallback_order
			if (isset($l_rows[$orig][$fl_lang])) {                           // Pokud existuje 'L' záznam pro daný jazyk
				$l_val = (string)($l_rows[$orig][$fl_lang][$col] ?? '');     // Hodnota v 'L' záznamu
				$l_rem = ! empty($l_rows[$orig][$fl_lang]['removed']);       // Zda je 'L' záznam zrušený
				if (! $l_rem AND $l_val !== '') {                            // Nalezena platná neprázdná hodnota v 'L'
					return $l_val;                                           // Vrácení nalezeného překladu
				}
			}
			if ($a_lang === $fl_lang AND $a_val !== '') {                    // Pokud je samotný 'A' záznam v tomto fallback jazyce
				return $a_val;                                               // Vrácení hodnoty z 'A' na příslušné úrovni fallbacku
			}
		}

		// 3. Pokud se v podřízeném poli nic nenašlo, vezmeme hodnotu ze záznamu 'A' (i v neznámém jazyce)
		if ($a_val !== '') {                                                 // Pokud má 'A' záznam neprázdnou hodnotu
			return $a_val;                                                   // Vrácení hodnoty z 'A'
		}

		// 4. Dědičnost z předka (ancestor / ancestor_class), pokud je vazba vyplněna
		$anc_orig = (string)($row[$anc_key] ?? '');                          // UUID předka
		if ($anc_orig !== '' AND $anc_orig !== $orig) {                      // Ochrana proti zacyklení
			return $this->resolve_field_from_arrays($anc_orig, $col, $a_rows, $anc_a_rows, $l_rows, $curr_lang, $lang_chain, $anc_key); // Rekurze na předka
		}

		return '';                                                           // Nikde nebyla nalezena neprázdná hodnota
	}

	/**
	 * Načte záznamy entity pomocí indexovaných tabulkových proměnných (@fl, @sy, @my, @dr, @mix, @target_origs)
	 * a dvoupolového vyhodnocení překladů v PHP (zcela bez vícenásobně vyhodnocovaných ;WITH CTE).
	 */
	public function fetch_rows(string $where = '', string $order_by = '', bool $ignore_drafts = false, bool $show_removed = false): array { // Načtení záznamů přes @table
		if (! $this->is_initialized) {                                       // Kontrola inicializace správce
			$err_title = $this->phrase('err_em_title', 'Entity manager');    // Lokalizovaný titulek chyby
			$err_msg = $this->phrase('err_meta_not_found', 'Metadata pro logickou třídu {' . chr(36) . 'class} nebyla nalezena.', ['class' => $this->class_name]); // Text chyby
			fatal_error($err_title, $err_msg);                               // Vyvolání fatální chyby
		}

		$table = $this->storage_table;                                       // Fyzická tabulka entity
		$is_meta_tab = $this->is_metadata_entity();                          // Zda jde o metadatovou tabulku (meta_*)
		$is_self_owned = ($table === 'organization');                        // V tabulce organization vlastní záznamy samy sebe
		$curr_lang = $this->lang_manager->get_current_language();            // Aktuální jazyk relace
		$safe_lang = charliteral($curr_lang, 2);                             // SQL literál aktuálního jazyka
		$lang_chain = $this->lang_manager->get_fallback_chain();             // Řetězec jazyků s fallback_order < 1000

		$anc_col_name = '';                                                  // Název sloupce předka (pokud v tabulce existuje)
		if (isset($this->columns_meta['ancestor'])) {                        // Tabulka meta_column
			$anc_col_name = 'ancestor';                                      // Vazba na předka sloupce
		} elseif (isset($this->columns_meta['ancestor_class'])) {            // Tabulka meta_class
			$anc_col_name = 'ancestor_class';                                // Vazba na předka třídy
		}

		$meta_columns_list = [                                               // Technické sloupce RAC a SSC
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note',
			'language', 'inactive', 'removed', 'valid_from', 'valid_to',
			'is_template', 'template', 'date_created', 'who_created',
			'date_modified', 'who_modified', 'import_origin'
		];                                                                   // Konec seznamu technických sloupců

		$trans_cols = [];                                                    // Seznam překládaných sloupců třídy
		$select_a_cols = [];                                                 // Sloupce pro SELECT v části 'A'
		$select_anc_cols = [];                                               // Sloupce pro SELECT v části 'ANC_A'
		$select_l_cols = [];                                                 // Sloupce pro SELECT v části 'L'

		foreach ($this->columns_meta as $colname => $meta) {                 // Sestavení projekce sloupců
			$select_anc_cols[] = "anc.[{$colname}]";                         // V 'ANC_A' bereme přímo z tabulky anc
			$select_l_cols[] = "l.[{$colname}]";                             // V 'L' bereme přímo z tabulky l

			if (in_array($colname, $meta_columns_list, true)) {              // Technický sloupec
				$select_a_cols[] = "m.[{$colname}]";                         // V 'A' bereme přímo z m
				continue;                                                    // Další sloupec
			}

			$is_trans = ! empty($meta['translate']);                         // Zda je sloupec překládaný
			$is_prot = ! empty($meta['is_protected']);                       // Zda je sloupec chráněný
			if ($is_trans) {                                                 // Evidujeme překládaný sloupec
				$trans_cols[] = $colname;                                    // Přidání do seznamu překládaných sloupců
			}

			if ($is_prot) {                                                  // Chráněný sloupec (vynucení systémového originálu o)
				$expr_a = "CASE WHEN m.record_type = 'D' THEN COALESCE(m.[{$colname}], o.[{$colname}]) ELSE COALESCE(o.[{$colname}], m.[{$colname}]) END AS [{$colname}]"; // Výraz
			} elseif ($is_meta_tab) {                                        // U metadat znamená NULL v overridu dědění ze systémového záznamu o
				$expr_a = "COALESCE(m.[{$colname}], o.[{$colname}]) AS [{$colname}]"; // Fallback na systémový originál při NULL v meta_*
			} else {
				$expr_a = "m.[{$colname}] AS [{$colname}]";                  // U věcných tabulek má m.[col] (vč. NULL u parent_uuid) přímou platnost
			}
			$select_a_cols[] = $expr_a;                                      // Přidání do SELECTu 'A'
		}

		foreach (['uuid', 'original', 'record_type', 'approval_status', 'draft_author', 'approval_note', 'language', 'removed', 'date_created', 'who_created', 'date_modified', 'who_modified'] as $req_c) { // Povinné sloupce
			if (! isset($this->columns_meta[$req_c]) AND in_array($req_c, $this->physical_cols, true)) { // Pokud chybí v columns_meta
				$select_a_cols[] = "m.[{$req_c}]";                           // Přidání z m
				$select_anc_cols[] = "anc.[{$req_c}]";                       // Přidání z anc
				$select_l_cols[] = "l.[{$req_c}]";                           // Přidání z l
			}
		}

		$sel_a_str = implode(",\n\t\t\t", $select_a_cols);                   // Řetězec sloupců pro 'A'
		$sel_anc_str = implode(",\n\t\t\t", $select_anc_cols);               // Řetězec sloupců pro 'ANC_A'
		$sel_l_str = implode(",\n\t\t\t", $select_l_cols);                   // Řetězec sloupců pro 'L'

		$has_draft_author_col = in_array('draft_author', $this->physical_cols, true); // Zda tabulka podporuje koncepty
		$rem_and_filter = $show_removed ? "" : "AND rc.removed = 0";         // Podmínka platných záznamů
		$sy_rem_where = $show_removed ? "" : "AND sy.removed = 0";           // Filtr platných systémových záznamů

		$my_owner_cond = $is_self_owned
			? "(rc.object_owner = @org_uuid OR (@org_uuid = 0x00 AND rc.object_owner = rc.original))"
			: "rc.object_owner = @org_uuid AND rc.object_owner <> 0x00";     // Podmínka vlastníka pro @my

		$dr_owner_cond = $is_self_owned
			? "(rc.object_owner = @org_uuid OR (@org_uuid = 0x00 AND rc.object_owner = rc.original))"
			: "rc.object_owner = @org_uuid";                                 // Podmínka vlastníka pro koncepty @dr

		// Protlačení filtrů na klíčové NOT NULL sloupce přímo do @sy, @my, @dr pro okamžitý Index Seek (bez přímého svislítka v kódu)
		$pushdown_rc_filter = '';                                            // Výchozí prázdný pushdown filtr
		$trimmed_where = trim($where);                                       // Oříznutá vstupní podmínka WHERE
		$m_push = [];                                                        // Pole zachycených skupin regulárního výrazu
		$pipe = chr(124);                                                    // Znak svislítka pro sestavení regulárního výrazu
		$push_regex = '/^m\.(original' . $pipe . 'parent_class' . $pipe . 'source_code' . $pipe . 'hierarchy)\s*=\s*(\'[0-9a-zA-Z_\-]+\'' . $pipe . '0x00)$/i'; // Vzorek klíčového filtru
		if ($trimmed_where !== '' AND preg_match($push_regex, $trimmed_where, $m_push)) { // Detekce klíčového filtru
			$push_col = $m_push[1];                                          // Filtrovaný klíčový sloupec
			$push_val = $m_push[2];                                          // Hodnota filtru
			$pushdown_rc_filter = "AND rc.[{$push_col}] = {$push_val}";      // Přímé omezení pro Index Seek v primární tabulce
		}

		$where_clause = ($trimmed_where !== '') ? "WHERE {$trimmed_where}" : ""; // Obecná podmínka WHERE nad vítězným záznamem m
		$anc_expr_sql = ($anc_col_name !== '')
			? "COALESCE(m.[{$anc_col_name}], o.[{$anc_col_name}])"
			: "NULL";                                                        // Výraz pro zjištění UUID předka do @mix

		if (! $ignore_drafts AND $has_draft_author_col) {                    // Sestavení plnění @mix se zahrnutím konceptů @dr
			$dr_sql_block = "
		DECLARE @dr TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			dr_uuid uniqueidentifier NOT NULL,
			native_language varchar(2) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT INTO @dr (original, dr_uuid, native_language)
		SELECT original, uuid, native_language
		FROM (
			SELECT rc.original, rc.uuid,
				ROW_NUMBER() OVER (PARTITION BY rc.original ORDER BY rc.date_modified DESC) AS rn_rec,
				ISNULL((
					SELECT TOP 1 a_nat.[language]
					FROM {$table} a_nat
					WHERE a_nat.original = rc.original AND a_nat.record_type = 'A'
					ORDER BY CASE WHEN a_nat.object_owner = rc.object_owner THEN 0 ELSE 1 END, a_nat.removed ASC
				), rc.[language]) AS native_language
			FROM {$table} rc
			WHERE {$dr_owner_cond}
			  AND rc.record_type = 'D'
			  AND rc.[language] = @sess_lang
			  AND (rc.draft_author = @user_account OR (rc.draft_author = 0x00 AND rc.approval_status = 'R'))
			  {$pushdown_rc_filter}
		) x
		WHERE x.rn_rec = 1;

		DECLARE @cand TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			win_uuid uniqueidentifier NOT NULL,
			sys_uuid uniqueidentifier NULL,
			object_is_mine bit NOT NULL,
			native_language varchar(2) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT INTO @cand (original, win_uuid, sys_uuid, object_is_mine, native_language)
		SELECT dr.original, dr.dr_uuid, sy.sys_uuid, 1, dr.native_language
		FROM @dr dr
		LEFT JOIN @sy sy ON sy.original = dr.original
		UNION ALL
		SELECT my.original, my.my_uuid, sy.sys_uuid, 1, my.native_language
		FROM @my my
		LEFT JOIN @sy sy ON sy.original = my.original
		LEFT JOIN @dr dr ON dr.original = my.original
		WHERE dr.original IS NULL
		UNION ALL
		SELECT sy.original, sy.sys_uuid, sy.sys_uuid, 0, sy.native_language
		FROM @sy sy
		LEFT JOIN @my my ON my.original = sy.original
		LEFT JOIN @dr dr ON dr.original = sy.original
		WHERE my.original IS NULL AND dr.original IS NULL {$sy_rem_where};"; // Kandidáti s koncepty
		} else {
			$dr_sql_block = "
		DECLARE @cand TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			win_uuid uniqueidentifier NOT NULL,
			sys_uuid uniqueidentifier NULL,
			object_is_mine bit NOT NULL,
			native_language varchar(2) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT INTO @cand (original, win_uuid, sys_uuid, object_is_mine, native_language)
		SELECT my.original, my.my_uuid, sy.sys_uuid, 1, my.native_language
		FROM @my my
		LEFT JOIN @sy sy ON sy.original = my.original
		UNION ALL
		SELECT sy.original, sy.sys_uuid, sy.sys_uuid, 0, sy.native_language
		FROM @sy sy
		LEFT JOIN @my my ON my.original = sy.original
		WHERE my.original IS NULL {$sy_rem_where};";                        // Kandidáti bez konceptů
		}

		$anc_union_sql = "";                                                 // SQL větev pro načtení předků
		$target_anc_insert = "";                                             // Doplnění předků do @target_origs pro překlady 'L'
		if ($anc_col_name !== '') {                                          // Pokud tabulka podporuje dědičnost z předka
			$anc_union_sql = "
		UNION ALL

		SELECT
			2 AS kind_order,
			'ANC_A' AS row_kind,
			0 AS is_tenant_l,
			0 AS fallback_order,
			CAST(0 AS BIT) AS object_is_mine,
			anc.[language] AS native_language,
			'' AS who_created_info,
			'' AS who_modified_info,
			{$sel_anc_str}
		FROM (SELECT DISTINCT anc_uuid FROM @mix WHERE anc_uuid IS NOT NULL) a
		JOIN {$table} anc
			ON anc.original = a.anc_uuid
			AND anc.object_owner = 0x00
			AND anc.record_type = 'A'
			AND anc.removed = 0";                                            // Načtení předků přes Index Seek na anc.original
			$target_anc_insert = "
		INSERT INTO @target_origs (original)
		SELECT DISTINCT anc_uuid
		FROM @mix m
		WHERE m.anc_uuid IS NOT NULL
		  AND NOT EXISTS (SELECT 1 FROM @target_origs t WHERE t.original = m.anc_uuid);"; // Zařazení předků do @target_origs
		}

		$l_prep_sql = "";                                                    // Příprava tabulky @target_origs pro 'L'
		$l_union_sql = "";                                                   // SQL větev pro načtení 'L' záznamů
		if (! empty($trans_cols)) {                                          // Pouze pokud má třída překládané sloupce
			$l_owner_cond = $is_self_owned
				? "(l.object_owner = 0x00 OR l.object_owner = l.original OR l.object_owner = @org_uuid)"
				: "(l.object_owner = 0x00 OR l.object_owner = @org_uuid)";   // Vlastník L záznamu
			$l_rem_cond = $show_removed ? "" : "AND l.removed = 0";          // Filtr zrušených L záznamů

			$l_prep_sql = "
		DECLARE @target_origs TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY
		);

		INSERT INTO @target_origs (original)
		SELECT original FROM @mix;
		{$target_anc_insert}";                                               // Naplnění unikátních klíčů original pro 'L' dotaz

			$l_union_sql = "
		UNION ALL

		SELECT
			3 AS kind_order,
			'L' AS row_kind,
			CASE WHEN l.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant_l,
			fl.fallback_order,
			CAST(0 AS BIT) AS object_is_mine,
			l.[language] AS native_language,
			'' AS who_created_info,
			dbo.f_get_user_info(l.who_modified) AS who_modified_info,
			{$sel_l_str}
		FROM @target_origs to_orig
		JOIN {$table} l ON l.original = to_orig.original
		JOIN @fl fl ON fl.[language] = l.[language]
		WHERE l.record_type = 'L'
		  {$l_rem_cond}
		  AND {$l_owner_cond}";                                              // Přímý Index Seek přes uq_<table>_language
		}

		$sql = "
		SET NOCOUNT ON;

		DECLARE @org_uuid uniqueidentifier = 0x00;
		DECLARE @user_account uniqueidentifier = 0x00;
		DECLARE @sess_lang varchar(2) = {$safe_lang};

		SELECT TOP 1
			@org_uuid = ISNULL(organization, 0x00),
			@user_account = ISNULL(user_account, 0x00),
			@sess_lang = ISNULL([language], {$safe_lang})
		FROM dbsession
		WHERE spid = @@SPID;

		DECLARE @fl TABLE (
			[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
			fallback_order int NOT NULL
		);
		INSERT INTO @fl ([language], fallback_order)
		SELECT [language], fallback_order
		FROM dbo.f_language_list(@sess_lang)
		WHERE fallback_order < 1000;

		DECLARE @sy TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			sys_uuid uniqueidentifier NOT NULL,
			removed bit NOT NULL,
			native_language varchar(2) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT INTO @sy (original, sys_uuid, removed, native_language)
		SELECT original, uuid, removed, [language]
		FROM (
			SELECT rc.original, rc.uuid, rc.removed, rc.[language],
				ROW_NUMBER() OVER (PARTITION BY rc.original ORDER BY rc.removed ASC, rc.date_modified DESC) AS rn_rec
			FROM {$table} rc
			WHERE rc.object_owner = 0x00
			  AND rc.record_type = 'A'
			  {$rem_and_filter}
			  {$pushdown_rc_filter}
		) x
		WHERE x.rn_rec = 1;

		DECLARE @my TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			my_uuid uniqueidentifier NOT NULL,
			removed bit NOT NULL,
			native_language varchar(2) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT INTO @my (original, my_uuid, removed, native_language)
		SELECT original, uuid, removed, [language]
		FROM (
			SELECT rc.original, rc.uuid, rc.removed, rc.[language],
				ROW_NUMBER() OVER (PARTITION BY rc.original ORDER BY rc.removed ASC, rc.date_modified DESC) AS rn_rec
			FROM {$table} rc
			WHERE {$my_owner_cond}
			  AND rc.record_type = 'A'
			  {$rem_and_filter}
			  {$pushdown_rc_filter}
		) x
		WHERE x.rn_rec = 1;
		{$dr_sql_block}

		DECLARE @mix TABLE (
			original uniqueidentifier NOT NULL PRIMARY KEY,
			win_uuid uniqueidentifier NOT NULL,
			sys_uuid uniqueidentifier NULL,
			anc_uuid uniqueidentifier NULL,
			object_is_mine bit NOT NULL,
			native_language varchar(2) COLLATE DATABASE_DEFAULT NOT NULL
		);

		INSERT INTO @mix (original, win_uuid, sys_uuid, anc_uuid, object_is_mine, native_language)
		SELECT
			c.original,
			c.win_uuid,
			c.sys_uuid,
			{$anc_expr_sql},
			c.object_is_mine,
			c.native_language
		FROM @cand c
		JOIN {$table} m ON m.uuid = c.win_uuid
		LEFT JOIN {$table} o ON o.uuid = c.sys_uuid
		{$where_clause};
		{$l_prep_sql}

		SELECT
			1 AS kind_order,
			'A' AS row_kind,
			0 AS is_tenant_l,
			0 AS fallback_order,
			mk.object_is_mine,
			mk.native_language,
			dbo.f_get_user_info(m.who_created) AS who_created_info,
			dbo.f_get_user_info(m.who_modified) AS who_modified_info,
			{$sel_a_str}
		FROM @mix mk
		JOIN {$table} m ON m.uuid = mk.win_uuid
		LEFT JOIN {$table} o ON o.uuid = mk.sys_uuid
		{$anc_union_sql}
		{$l_union_sql}
		ORDER BY kind_order ASC, fallback_order ASC, is_tenant_l DESC, removed ASC;
		";                                                                   // Optimalizovaná dávka bez ;WITH CTE

		$raw_rows = sqlarray_simple($sql);                                   // Načtení všech dat jedním dotazem
		if (! is_array($raw_rows) OR empty($raw_rows)) {                     // Pokud dotaz nevrátil žádné záznamy
			return [];                                                       // Vrácení prázdného pole
		}

		// 1. Rozdělení načtených dat na dvě pole: a_rows (podle original) a l_rows ([original][language])
		$a_rows = [];                                                        // První pole s indexem 'original' (záznamy 'A'/'D')
		$anc_a_rows = [];                                                    // Pomocné pole předků 'A'
		$l_rows = [];                                                        // Druhé 2D pole podřízené originálu s indexem jazyka

		foreach ($raw_rows as $r) {                                          // Průchod načtenými řádky
			$orig = (string)$r['original'];                                  // UUID originálu
			$kind = (string)$r['row_kind'];                                  // Typ řádku ('A', 'ANC_A', 'L')
			if ($kind === 'A') {                                             // Hlavní záznam
				$r['l_removed'] = 0;                                         // Výchozí stav zrušení překladu
				$a_rows[$orig] = $r;                                         // Uložení do prvního pole pod klíčem original
			} elseif ($kind === 'ANC_A') {                                   // Záznam předka
				$anc_a_rows[$orig] = $r;                                     // Uložení předka
			} else {
				$lang = (string)$r['language'];                              // Kód jazyka 'L' záznamu
				if (! isset($l_rows[$orig][$lang])) {                        // První záznam pro daný jazyk
					$l_rows[$orig][$lang] = $r;                              // Uložení do 2D podřízeného pole
				} else {
					foreach ($trans_cols as $tc) {                           // Doplnění případných prázdných hodnot ze systémového 'L'
						if ((string)($l_rows[$orig][$lang][$tc] ?? '') === '' AND (string)($r[$tc] ?? '') !== '') { // Fallback
							$l_rows[$orig][$lang][$tc] = $r[$tc];            // Převzetí hodnoty ze systémového 'L'
						}
					}
				}
			}
		}

		// 2. Vyhodnocení překladů, dědičnosti z předka a nejnovějšího data úpravy pro každý 'original'
		foreach ($a_rows as $orig => &$a_row) {                              // Průchod hlavním polem záznamů
			if (isset($l_rows[$orig])) {                                     // Pokud k záznamu existují 'L' mutace
				if (isset($l_rows[$orig][$curr_lang])) {                     // Pokud existuje 'L' mutace pro aktuální jazyk
					$a_row['l_removed'] = ! empty($l_rows[$orig][$curr_lang]['removed']) ? 1 : 0; // Příznak zrušení L mutace
				}
				if (($a_row['record_type'] ?? 'A') !== 'D') {                // U schválených záznamů zohledníme i změny v 'L'
					foreach ($l_rows[$orig] as $l_item) {                    // Průchod podřízenými 'L' záznamy
						$l_mod = (string)($l_item['date_modified'] ?? '');   // Datum změny 'L' záznamu
						$a_mod = (string)($a_row['date_modified'] ?? '');    // Datum změny 'A' záznamu
						if ($l_mod !== '' AND $l_mod > $a_mod) {             // Pokud je 'L' záznam novější než 'A'
							$a_row['date_modified'] = $l_mod;                // Převzetí novějšího data úpravy
							$a_row['who_modified'] = $l_item['who_modified']; // Převzetí autora úpravy
							$a_row['who_modified_info'] = $l_item['who_modified_info']; // Převzetí jména autora
						}
					}
				}
			}

			if ($is_meta_tab AND $anc_col_name !== '') {                     // Pouze pokud jde o tabulku metadat s předkem
				$anc_id = (string)($a_row[$anc_col_name] ?? '');             // UUID předka
				$anc_rec = ($anc_id !== '') ? ($anc_a_rows[$anc_id] ?? $a_rows[$anc_id] ?? null) : null; // Záznam předka
				if ($anc_rec !== null) {                                     // Pokud byl předek nalezen
					foreach ($this->columns_meta as $cn => $cm) {            // Průchod sloupci
						if (empty($cm['translate']) AND ! in_array($cn, $meta_columns_list, true)) { // Nepřekládané sloupce
							if ($a_row[$cn] === null AND isset($anc_rec[$cn])) { // Dědění při NULL
								$a_row[$cn] = $anc_rec[$cn];                 // Převzetí hodnoty od předka
							}
						}
					}
				}
			}

			foreach ($trans_cols as $tc) {                                   // Průchod překládanými sloupci
				$a_row[$tc] = $this->resolve_field_from_arrays($orig, $tc, $a_rows, $anc_a_rows, $l_rows, $curr_lang, $lang_chain, $anc_col_name ?: 'ancestor'); // Překlad
			}
		}
		unset($a_row);                                                       // Uvolnění reference po smyčce

		$result = array_values($a_rows);                                     // Převod asociativního pole na indexované pole

		// 3. Seřazení výsledného pole podle order_by nebo podle sloupců Master panelu (list_columns)
		$sort_cols = [];                                                     // Pole sloupců pro řazení: [sloupec => 'ASC'|'DESC']
		if ($order_by !== '') {                                              // Pokud bylo zadáno explicitní řazení
			foreach (explode(',', $order_by) as $ob_part) {                  // Rozpad klauzule ORDER BY
				$ob_clean = trim(str_replace(['[', ']', 'm.'], '', $ob_part)); // Očištění názvu sloupce
				if ($ob_clean !== '') {                                      // Pokud část není prázdná
					$tokens = preg_split('/\s+/', $ob_clean);               // Rozdělení na název a směr
					$sc_name = (string)($tokens[0] ?? '');                   // Název sloupce
					$sc_dir = strtoupper((string)($tokens[1] ?? 'ASC'));     // Směr řazení
					if ($sc_name !== '') {                                   // Zařazení sloupce do řazení
						$sort_cols[$sc_name] = ($sc_dir === 'DESC') ? 'DESC' : 'ASC'; // Uložení směru
					}
				}
			}
		} else {
			foreach (array_keys($this->list_columns) as $lc_name) {          // Výchozí řazení podle sloupců seznamu
				$sort_cols[$lc_name] = 'ASC';                                // Vzestupné řazení
			}
		}

		if (! empty($sort_cols) AND count($result) > 1) {                    // Seřazení výsledků v PHP
			usort($result, function(array $x, array $y) use ($sort_cols): int { // Porovnávací funkce řazení
				foreach ($sort_cols as $sc => $dir) {                        // Průchod řadicími sloupci
					$vx = (string)($x[$sc] ?? '');                           // Hodnota prvního řádku
					$vy = (string)($y[$sc] ?? '');                           // Hodnota druhého řádku
					$cmp = strnatcasecmp($vx, $vy);                          // Přirozené porovnání řetězců
					if ($cmp !== 0) {                                        // Pokud se hodnoty liší
						return ($dir === 'DESC') ? -$cmp : $cmp;             // Vrácení výsledku dle směru ASC/DESC
					}
				}
				return 0;                                                    // Shoda ve všech řadicích sloupcích
			});
		}

		return $result;                                                      // Vrácení seřazeného pole záznamů
	}

	/**
	 * Zpětně kompatibilní alias pro metodu fetch_rows().
	 */
	public function fetch_records(string $where = '', string $order_by = '', bool $ignore_drafts = false, bool $show_removed = false): array { // Alias pro fetch_rows
		return $this->fetch_rows($where, $order_by, $ignore_drafts, $show_removed); // Delegování na fetch_rows
	}

	/**
	 * Načte jeden konkrétní záznam pomocí dvoupolového vyhodnocení v PHP.
	 */
	public function fetch_row(string $where = '', bool $ignore_drafts = false, bool $show_removed = false): array { // Načtení jednoho záznamu
		$rows = $this->fetch_rows($where, '', $ignore_drafts, $show_removed); // Načtení záznamů přes fetch_rows
		return $rows[0] ?? [];                                               // Vrácení prvního záznamu nebo prázdného pole
	}
}