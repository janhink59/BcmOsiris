<?php
/**
 * =============================================================================
 * Verze: 2026-11-09 16:30
 * Soubor: entity_manager_ssc.php
 * Trait: entity_manager_ssc
 * Účel: Schvalovací cyklus (SSC: approve_draft, reject_draft, delete_draft),
 *       doménová validace monotonie hodnotících škál (validate_scale_value_monotonicity)
 *       a návazné operace po uložení záznamu (run_post_save_hooks).
 *       Vyčleněno z entity_manager_write.php pro modulární strukturu a menší
 *       velikost jednotlivých zdrojových souborů.
 *
 * VAZBY NA OKOLÍ:
 * - Inkludován a používán výhradně uvnitř třídy `entity_manager` (`entity_manager.php`).
 * - Spolupracuje s traitem `entity_manager_write` (`clone_with_map`, `unquote_sql_literal`).
 * - Volán z `entity_manager_write::save_post_data()`, `abstract_page_master_detail::process_save()`
 *   a `page_approval::process_save()`.
 * - V `run_post_save_hooks()` volá `dbo.p_crmm_recalculate` při uložení entit CRMM.
 * =============================================================================
 */

declare(strict_types=1);

trait entity_manager_ssc {

	/**
	 * Validuje prahové hodnoty (`threshold_value`) a skóre (`score_value`) v tabulce `scale_value`:
	 * 1. Interval `0 <= threshold_value <= score_value <= 100`.
	 * 2. Nejnižší stupeň škály musí mít `threshold_value = 0`.
	 * 3. Přísná monotonie prahů i skóre napříč všemi platnými stupni dané škály.
	 */
	private function validate_scale_value_monotonicity(string $orig_guid_sql, string $rec_owner_sql, array $src_data): bool { // Kontrola monotonie scale_value
		$scale_lit = (string) ($src_data['scale'] ?? 'NULL'); // SQL literál nadřazené škály
		if ($scale_lit === 'NULL' OR $scale_lit === '0x00') { // Kontrola vyplnění škály
			$this->set_last_save_error($this->phrase('err_scale_missing', 'Musí být zvolena nadřazená hodnotící škála (scale).')); // Chyba
			return false; // Neplatná škála
		}

		$thr_val = (float) ($src_data['threshold_value'] ?? 0.0); // Zadaná dolní prahová hodnota v %
		$scr_val = (float) ($src_data['score_value'] ?? 0.0); // Zadaná hodnota skóre v %

		if ($thr_val < 0.0 OR $thr_val > 100.0 OR $scr_val < 0.0 OR $scr_val > 100.0) { // Kontrola intervalu 0..100 %
			$this->set_last_save_error($this->phrase('err_scale_val_range', 'Prahová hodnota (threshold_value) i skóre (score_value) musí ležet v procentuálním intervalu 0 až 100 %.')); // Chyba rozsahu
			return false; // Mimo rozsah 0..100
		}

		if ($scr_val < $thr_val) { // Skóre nesmí být menší než dolní práh téhož stupně
			$this->set_last_save_error($this->phrase('err_scale_score_below_threshold', 'Hodnota skóre (score_value) nesmí být menší než dolní prahová hodnota (threshold_value) daného stupně.')); // Chyba
			return false; // Porušení intervalu stupně
		}

		$excl_self = ($orig_guid_sql !== '' AND $orig_guid_sql !== 'NULL') ? "AND a.original <> {$orig_guid_sql}" : ""; // Vyloučení právě upravovaného stupně
		$existing_levels = sqlarray_simple("
			SELECT original, builtin_code, caption, threshold_value, score_value
			FROM (
				SELECT a.original, a.builtin_code, a.caption, a.threshold_value, a.score_value,
					ROW_NUMBER() OVER (PARTITION BY a.original ORDER BY CASE WHEN a.object_owner = {$rec_owner_sql} THEN 0 ELSE 1 END) AS rn
				FROM scale_value a
				WHERE a.scale = {$scale_lit}
				  AND a.object_owner IN (0x00, {$rec_owner_sql})
				  AND a.record_type = 'A'
				  AND a.removed = 0
				  {$excl_self}
			) x
			WHERE x.rn = 1
			ORDER BY threshold_value ASC
		"); // Načtení ostatních platných stupňů škály

		$all_levels = []; // Pole všech stupňů včetně ukládaného záznamu
		if (is_array($existing_levels)) { // Přidání existujících stupňů
			foreach ($existing_levels as $el) { // Průchod existujícími stupni
				$el_thr = (float) $el['threshold_value']; // Práh existujícího stupně
				if (abs($el_thr - $thr_val) < 0.00005) { // Kontrola duplicitního prahu ve škále
					$dup_lbl = (string) ($el['caption'] ?: $el['builtin_code']); // Označení kolidujícího stupně
					$this->set_last_save_error($this->phrase(
						'err_scale_duplicate_threshold',
						'Stupeň se shodnou prahovou hodnotou ({' . chr(36) . 'thr} %) již v této škále existuje ({' . chr(36) . 'name}). Prahové hodnoty musí tvořit rostoucí řadu.',
						['thr' => number_format($thr_val, 2, '.', ''), 'name' => $dup_lbl]
					)); // Chybová hláška duplicitního prahu
					return false; // Zastavení zápisu
				}
				$all_levels[] = [ // Zařazení existujícího stupně do kontroly
					'thr'  => $el_thr,
					'scr'  => (float) $el['score_value'],
					'name' => (string) ($el['caption'] ?: $el['builtin_code'])
				];
			}
		}

		$cur_name = $this->unquote_sql_literal((string) ($src_data['caption'] ?? $src_data['builtin_code'] ?? '')); // Název ukládaného stupně
		$all_levels[] = [ // Přidání právě ukládaného stupně
			'thr'  => $thr_val,
			'scr'  => $scr_val,
			'name' => ($cur_name !== '' ? $cur_name : 'Nový stupeň')
		];

		usort($all_levels, function (array $a, array $b): int { // Seřazení všech stupňů vzestupně podle prahu
			return ($a['thr'] <=> $b['thr']); // Porovnání prahových hodnot
		});

		if ($all_levels[0]['thr'] > 0.00005) { // Nejnižší stupeň škály musí začínat na 0 %
			$this->set_last_save_error($this->phrase('err_scale_first_threshold_zero', 'Nejnižší stupeň hodnotící škály musí mít dolní prahovou hodnotu (threshold_value) rovnu 0 %.')); // Chyba
			return false; // Chybí nulový počátek škály
		}

		$cnt = count($all_levels); // Celkový počet stupňů škály
		for ($i = 0; $i < $cnt; $i++) { // Kontrola monotonie a intervalů všech stupňů
			$curr = $all_levels[$i]; // Aktuálně kontrolovaný stupeň
			$next_thr = ($i + 1 < $cnt) ? $all_levels[$i + 1]['thr'] : 100.0; // Horní mez intervalu

			if ($curr['scr'] > $next_thr + 0.00005) { // Skóre přesahuje práh následujícího stupně
				$this->set_last_save_error($this->phrase(
					'err_scale_score_exceeds_next_threshold',
					'Hodnota skóre ({' . chr(36) . 'scr} %) u stupně „{' . chr(36) . 'name}“ přesahuje prahovou hodnotu následujícího stupně ({' . chr(36) . 'next} %).',
					['scr' => number_format($curr['scr'], 2, '.', ''), 'name' => $curr['name'], 'next' => number_format($next_thr, 2, '.', '')]
				)); // Chybová hláška překročení intervalu
				return false; // Zastavení zápisu
			}

			if ($i > 0 AND $curr['scr'] <= $all_levels[$i - 1]['scr'] + 0.00005) { // Skóre není ostře větší než u předchozího stupně
				$prev = $all_levels[$i - 1]; // Předchozí stupeň
				$this->set_last_save_error($this->phrase(
					'err_scale_score_not_monotonic',
					'Hodnoty skóre musí tvořit rostoucí řadu: stupeň „{' . chr(36) . 'name}“ ({' . chr(36) . 'scr} %) musí mít vyšší skóre než předchozí stupeň „{' . chr(36) . 'prev_name}“ ({' . chr(36) . 'prev_scr} %).',
					['name' => $curr['name'], 'scr' => number_format($curr['scr'], 2, '.', ''), 'prev_name' => $prev['name'], 'prev_scr' => number_format($prev['scr'], 2, '.', '')]
				)); // Chybová hláška porušení monotonie skóre
				return false; // Zastavení zápisu
			}
		}

		return true; // Všechny kontroly monotonie prošly
	}

	/**
	 * Spustí post-processing operace po uložení schváleného záznamu ('A'):
	 * 1. U tabulky `link` zmaterializuje odvozené vazby (`dbo.p_sync_derived_links`).
	 * 2. U číselníků a škál se zaškrtnutým `is_default = 1` vynuluje `is_default` na ostatních sourozencích.
	 * 3. U nově založené hodnotící škály (`scale`) vygeneruje $n$ výchozích stupňů v `scale_value` (`0..100 %`).
	 * 4. U tabulek modulu CRMM spustí přepočet rizik a faktorů (`dbo.p_crmm_recalculate`).
	 */
	private function run_post_save_hooks(string $orig_guid_sql, string $rec_owner_sql = '0x00', string $lang_sql = "'cs'", string $user_uuid_sql = '0x00'): void { // Návazné operace
		if ($orig_guid_sql === '' OR $orig_guid_sql === 'NULL') { // Kontrola platného SQL literálu originálu
			return; // Ukončení bez volání procedur
		}

		$table = $this->storage_table; // Fyzická tabulka entity

		if ($table === 'link') { // Materializace zděděných vazeb v tabulce link
			$p_row = sqlfirstrow("SELECT OBJECT_ID('p_sync_derived_links', 'P') AS pid"); // Ověření existence procedury
			if (! empty($p_row['pid'])) { // Pokud procedura v DB existuje
				sqlrun("EXEC dbo.p_sync_derived_links @root_link_original = {$orig_guid_sql}"); // Přepočet odvozených vazeb
			}
		}

		if (in_array('is_default', $this->physical_cols, true)) { // Zajištění jednoznačnosti výchozí položky (is_default = 1)
			$saved_rec = sqlfirstrow("SELECT TOP 1 * FROM [{$table}] WHERE original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type = 'A' AND removed = 0"); // Načtení uloženého A záznamu
			if (! empty($saved_rec) AND ! empty($saved_rec['is_default'])) { // Pokud má záznam nastaveno is_default = 1
				if ($table === 'countermeasure_state') { // Plochý číselník stavů protiopatření
					sqlrun("UPDATE countermeasure_state SET is_default = 0 WHERE object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních
				} elseif ($table === 'scale_value') { // Stupně v rámci jedné hodnotící škály
					$sc_sql = guidliteral((string) $saved_rec['scale']); // SQL literál nadřazené škály
					sqlrun("UPDATE scale_value SET is_default = 0 WHERE scale = {$sc_sql} AND object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních ve škále
				} elseif ($table === 'scale') { // Hodnotící škála v rámci téhož scale_type
					$st_sql = charliteral((string) $saved_rec['scale_type'], 20); // SQL literál druhu škály
					sqlrun("UPDATE scale SET is_default = 0 WHERE scale_type = {$st_sql} AND object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních téhož druhu
				} elseif ($table === 'hierarchy_item') { // Položka sekundární hierarchie (u jednohodnotových s multiple = 0)
					$h_sql = guidliteral((string) $saved_rec['hierarchy']); // SQL literál nadřazené hierarchie
					$h_row = sqlfirstrow("SELECT TOP 1 multiple FROM hierarchy WHERE original = {$h_sql} AND record_type = 'A' AND removed = 0 ORDER BY CASE WHEN object_owner = {$rec_owner_sql} THEN 0 ELSE 1 END"); // Zjištění příznaku multiple
					if (! empty($h_row) AND empty($h_row['multiple'])) { // Jednohodnotový číselník (multiple = 0)
						sqlrun("UPDATE hierarchy_item SET is_default = 0 WHERE hierarchy = {$h_sql} AND object_owner = {$rec_owner_sql} AND original <> {$orig_guid_sql} AND is_default = 1"); // Vynulování ostatních
					}
				}
			}
		}

		if ($table === 'scale' AND in_array('initial_levels', $this->physical_cols, true)) { // Automatické vygenerování stupňů v scale_value
			$sc_row = sqlfirstrow("SELECT TOP 1 initial_levels, [language] FROM scale WHERE original = {$orig_guid_sql} AND object_owner = {$rec_owner_sql} AND record_type = 'A' AND removed = 0"); // Načtení škály
			$cnt_ex = sqlfirstrow("SELECT COUNT(1) AS cnt FROM scale_value WHERE scale = {$orig_guid_sql} AND record_type = 'A' AND removed = 0"); // Počet existujících stupňů
			$existing_cnt = (int) ($cnt_ex['cnt'] ?? 0); // Zjištěný počet stupňů

			if (! empty($sc_row) AND $existing_cnt === 0) { // Škála zatím nemá žádné stupně -> vygenerujeme je
				$n = (int) ($sc_row['initial_levels'] ?? 4); // Požadovaný počet stupňů
				$n = max(2, min(20, $n)); // Omezení na rozsah 2..20 stupňů
				$sc_lang = (string) ($sc_row['language'] ?? 'cs'); // Jazyk škály
				$sc_lang_sql = charliteral($sc_lang, 2); // SQL literál jazyka škály
				$lbl_prefix = ($sc_lang === 'en') ? 'Level ' : 'Stupeň '; // Výchozí pojmenování stupně podle jazyka
				$step_w = 100.0 / $n; // Šířka jednoho intervalu v procentech

				for ($i = 1; $i <= $n; $i++) { // Generování stupňů 1..n
					$thr = round(($i - 1) * $step_w, 4); // Dolní práh intervalu: (i - 1) * (100 / n)
					$scr = round(($i - 0.5) * $step_w, 4); // Střed intervalu (skóre): (i - 0.5) * (100 / n)
					$safe_bc = charliteral('l' . $i, 80); // SQL literál builtin_code
					$safe_sn = charliteral('L' . $i, 40); // SQL literál shortname
					$safe_cp = charliteral($lbl_prefix . $i, 200); // SQL literál caption
					$thr_sql = number_format($thr, 4, '.', ''); // SQL literál threshold_value
					$scr_sql = number_format($scr, 4, '.', ''); // SQL literál score_value
					$is_def = ($i === 1) ? 1 : 0; // První stupeň nastavíme jako výchozí

					$sv_orig_row = sqlfirstrow("SELECT dbo.f_generate_original('scale_value', {$rec_owner_sql}, CAST({$orig_guid_sql} AS varchar(36)), {$safe_bc}) AS orig"); // Deterministický originál stupně
					$sv_orig_sql = guidliteral((string) ($sv_orig_row['orig'] ?? generateUUID())); // SQL literál originálu stupně

					sqlrun("
						INSERT INTO scale_value (
							uuid, object_owner, original, record_type, approval_status, [language],
							scale, builtin_code, caption, shortname, threshold_value, score_value, is_default,
							date_created, who_created, date_modified, who_modified
						) VALUES (
							{$sv_orig_sql}, {$rec_owner_sql}, {$sv_orig_sql}, 'A', 'A', {$sc_lang_sql},
							{$orig_guid_sql}, {$safe_bc}, {$safe_cp}, {$safe_sn}, {$thr_sql}, {$scr_sql}, {$is_def},
							GETDATE(), {$user_uuid_sql}, GETDATE(), {$user_uuid_sql}
						);
						INSERT INTO scale_value (
							uuid, object_owner, original, record_type, approval_status, [language],
							scale, builtin_code, caption, shortname, threshold_value, score_value, is_default,
							date_created, who_created, date_modified, who_modified
						) VALUES (
							NEWID(), {$rec_owner_sql}, {$sv_orig_sql}, 'L', 'A', {$sc_lang_sql},
							{$orig_guid_sql}, {$safe_bc}, {$safe_cp}, {$safe_sn}, {$thr_sql}, {$scr_sql}, {$is_def},
							GETDATE(), {$user_uuid_sql}, GETDATE(), {$user_uuid_sql}
						);
					"); // Vložení 'A' i symetrického 'L' záznamu stupně škály
				}
			}
		}

		if (in_array($table, ['asset', 'link', 'countermeasure_implementation', 'scenario_assessment', 'countermeasure', 'countermeasure_state', 'scenario', 'threat'], true)) { // Přepočet CRMM
			$crmm_proc = sqlfirstrow("SELECT OBJECT_ID('p_crmm_recalculate', 'P') AS pid"); // Kontrola existence výpočetní procedury
			if (! empty($crmm_proc['pid'])) { // Pokud procedura v DB existuje
				sqlrun("EXEC dbo.p_crmm_recalculate @org_uuid = {$rec_owner_sql}"); // Automatický přepočet faktorů a rizik organizace
			}
		}
	}

	/**
	 * Odstraní rozpracovaný nebo vrácený koncept ('D') přihlášeného uživatele bez náhrady.
	 */
	public function delete_draft(string $original_guid): void { // Smazání konceptu uživatele podle original
		if (! $this->is_initialized OR trim($original_guid) === '') { // Kontrola platného vstupu
			return; // Ukončení při prázdném identifikátoru
		}

		global $dbsession; // Globální kontext relace
		$org_raw = (string) ($dbsession['organization'] ?? '0x00'); // Surové UUID organizace v relaci
		$table = $this->storage_table; // Fyzická tabulka entity
		$rec_owner_sql = ($table === 'organization') ? guidliteral($original_guid) : guidliteral($org_raw); // Vlastník záznamu
		$user_acc_sql = guidliteral((string) ($dbsession['user_account'] ?? '0x00')); // SQL literál účtu uživatele
		$lang_sql = charliteral((string) ($dbsession['language'] ?? 'cs')); // SQL literál jazyka relace
		$orig_sql = guidliteral($original_guid); // SQL literál mazaného originálu

		sqlrun("
			DELETE FROM {$table}
			WHERE original = {$orig_sql}
			  AND object_owner = {$rec_owner_sql}
			  AND record_type = 'D'
			  AND [language] = {$lang_sql}
			  AND (draft_author = {$user_acc_sql} OR draft_author = 0x00)
		"); // Fyzické odstranění konceptu z DB
	}

	/**
	 * Schválí vybraný návrh (`record_type = 'D'`) identifikovaný svým primárním klíčem `uuid`.
	 */
	public function approve_draft(string $draft_uuid): void { // Schválení vybraného návrhu
		if (! $this->is_initialized OR trim($draft_uuid) === '') { // Kontrola inicializace a platného UUID
			return; // Ukončení při chybějícím UUID návrhu
		}

		global $dbsession; // Globální kontext relace schvalovatele
		$sess_org_raw = (string) ($dbsession['organization'] ?? '0x00'); // Surové UUID organizace schvalovatele
		$sess_org_sql = guidliteral($sess_org_raw); // SQL literál organizace schvalovatele
		$sess_lang_sql = charliteral((string) ($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka schvalovatele
		$is_sys_org_flag = is_sys_org($sess_org_raw); // Zda je schvalovatel v systémové organizaci 0x00

		$approver_session_sql = guidliteral((string) ($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$right_translate = ! empty($dbsession['right_translate']); // Oprávnění ke globálnímu překladu
		$table = $this->storage_table; // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid); // SQL literál primárního klíče návrhu

		$owner_cond = ($table === 'organization' AND $is_sys_org_flag)
			? "(object_owner = {$sess_org_sql} OR object_owner = original)"
			: "object_owner = {$sess_org_sql}"; // Izolace schvalovaného návrhu podle tenanta

		$draft_row = sqlfirstrow("
			SELECT * FROM {$table}
			WHERE uuid = {$draft_uuid_sql}
			  AND record_type = 'D'
			  AND approval_status = 'F'
			  AND {$owner_cond}
			  AND [language] = {$sess_lang_sql}
		"); // Dotaz na návrh (vč. removed = 1)

		if (empty($draft_row)) { // Pokud návrh nebyl nalezen nebo nepatří tenantovi
			return; // Ukončení zpracování
		}

		$orig_raw = (string) $draft_row['original']; // Surové UUID originálu
		$orig_sql = guidliteral($orig_raw); // SQL literál originálu
		$owner_raw = (string) $draft_row['object_owner']; // Surové UUID vlastníka návrhu
		$owner_sql = guidliteral($owner_raw); // SQL literál vlastníka návrhu
		$draft_lang_raw = (string) $draft_row['language']; // Jazyk schvalovaného návrhu
		$draft_lang_sql = charliteral($draft_lang_raw, 2); // SQL literál jazyka návrhu
		$author_session_sql = guidliteral((string) $draft_row['who_modified']); // Relace autora v době postoupení návrhu
		$author_date_sql = charliteral((string) $draft_row['date_modified']); // Datum postoupení návrhu autorem

		$is_sys_owner = is_zero_guid($owner_raw); // Zda jde o systémového vlastníka 0x00
		$is_final_class = (! $is_sys_owner AND $table !== 'organization' AND ! empty($this->class_meta['is_final'])); // Zda třída zakazuje A override

		$existing_a = sqlfirstrow("SELECT TOP 1 * FROM {$table} WHERE original = {$orig_sql} AND record_type = 'A' AND object_owner IN ({$owner_sql}, 0x00) ORDER BY object_owner DESC, removed ASC, date_modified DESC"); // Hledání A záznamu

		$own_a_exists = (! empty($existing_a) AND ((string) $existing_a['object_owner'] === $owner_raw OR $is_sys_owner)); // Zda má vlastník vlastní A záznam
		$a_lang_raw = ! empty($existing_a) ? (string) $existing_a['language'] : $draft_lang_raw; // Mateřský jazyk A záznamu
		$is_native_lang = ($a_lang_raw === $draft_lang_raw); // Zda je návrh v mateřském jazyce záznamu

		$skip_data_cols = array_merge([ // Technické a klíčové sloupce, které se při UPDATE nemění
			'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
			'draft_author', 'approval_note', 'language',
			'date_created', 'who_created', 'date_modified', 'who_modified'
		], $this->get_original_key_columns()); // Ochrana klíčových sloupců i při schválení UPDATE

		if (! empty($existing_a) AND $this->is_hierarchy_node_locked($orig_raw)) { // Ochrana uzamčené větve při schválení návrhu
			$skip_data_cols[] = 'parent_uuid'; // Zákaz přepodřízení uzamčené větve
			if (! empty($existing_a['is_leaf'])) { // Pokud byl uzel koncovým listem
				$skip_data_cols[] = 'is_leaf'; // Zákaz zrušení koncového uzlu
			}
		}

		$ap_audit_map = ['date_created' => $author_date_sql, 'who_created' => $author_session_sql, 'date_modified' => 'GETDATE()', 'who_modified' => $approver_session_sql]; // Audit autora a schvalovatele

		sqlrun("BEGIN TRAN"); // Zahájení transakce schválení

		if (! $is_final_class) { // Zápis do schváleného 'A' záznamu
			if ($own_a_exists) { // UPDATE existujícího 'A' záznamu
				$a_uuid_sql = guidliteral((string) $existing_a['uuid']); // Primární klíč existujícího A záznamu
				$set_a = []; // Pole změn pro UPDATE A záznamu
				foreach ($this->physical_cols as $col) { // Průchod fyzickými sloupci tabulky
					if (in_array($col, $skip_data_cols, true)) { // Přeskočení technických a klíčových sloupců
						continue; // Pokračování na další sloupec
					}
					if ($col === 'removed' AND ! $is_native_lang) { // V sekundárním jazyce ruší removed pouze překlad L
						continue; // Hlavní záznam A v primárním jazyce nerušíme
					}
					$is_trans = ! empty($this->columns_meta[$col]['translate']); // Zda je sloupec překládaný
					if ($is_trans AND ! $is_native_lang) { // Ochrana mateřského jazyka v A záznamu
						continue; // Cizojazyčný překlad patří pouze do L záznamu
					}
					$set_a[] = "[$col] = d.[$col]"; // Převzetí hodnoty ze schvalovaného návrhu d
				}
				$set_a[] = "approval_status = 'A'"; // Nastavení schváleného stavu
				$set_a[] = "draft_author = 0x00"; // Vynulování autora konceptu
				$set_a[] = "approval_note = ''"; // Vyčištění poznámky schvalování
				$set_a[] = "date_modified = GETDATE()"; // Datum schválení
				$set_a[] = "who_modified = {$approver_session_sql}"; // Schvalovatel
				sqlrun("UPDATE a SET " . implode(', ', $set_a) . " FROM {$table} a JOIN {$table} d ON d.uuid = {$draft_uuid_sql} WHERE a.uuid = {$a_uuid_sql}"); // SQL UPDATE A
			} else {
				$ap_a_pk = (! empty($existing_a) ? 'NEWID()' : 'original'); // Primární klíč nového A záznamu
				$ap_a_hdr = ['uuid' => $ap_a_pk, 'object_owner' => $owner_sql, 'original' => 'original', 'record_type' => "'A'", 'approval_status' => "'A'", 'draft_author' => '0x00', 'approval_note' => "''"]; // Hlavička A
				$this->clone_with_map($ap_a_hdr + $ap_audit_map, "uuid = {$draft_uuid_sql}"); // Založení schváleného A záznamu
			}
		}

		if ($table !== 'link') { // Zápis do symetrického 'L' záznamu pro jazyk návrhu (mimo tabulku link)
			$l_owner_sql = $owner_sql; // Vlastník jazykové mutace
			if (! empty($existing_a) AND is_zero_guid($existing_a['object_owner']) AND $right_translate) { // Systémový A záznam
				$l_owner_sql = '0x00'; // Globální systémový překlad
			}
			$existing_l = sqlfirstrow("SELECT TOP 1 uuid FROM {$table} WHERE original = {$orig_sql} AND object_owner = {$l_owner_sql} AND record_type = 'L' AND [language] = {$draft_lang_sql} ORDER BY removed ASC, date_modified DESC"); // Kontrola existence L

			if (! empty($existing_l)) { // UPDATE existujícího 'L' záznamu
				$l_uuid_sql = guidliteral((string) $existing_l['uuid']); // Primární klíč L záznamu
				$set_l = []; // Pole změn pro UPDATE L záznamu
				foreach ($this->physical_cols as $col) { // Průchod fyzickými sloupci
					if (in_array($col, $skip_data_cols, true)) { // Přeskočení technických a klíčových sloupců
						continue; // Pokračování na další sloupec
					}
					$set_l[] = "[$col] = d.[$col]"; // Převzetí hodnoty z návrhu d
				}
				$set_l[] = "approval_status = 'A'"; // Schválený stav L záznamu
				$set_l[] = "draft_author = 0x00"; // Vynulování autora konceptu
				$set_l[] = "approval_note = ''"; // Vyčištění poznámky
				$set_l[] = "date_modified = GETDATE()"; // Datum schválení překladu
				$set_l[] = "who_modified = {$approver_session_sql}"; // Relace schvalovatele
				sqlrun("UPDATE l SET " . implode(', ', $set_l) . " FROM {$table} l JOIN {$table} d ON d.uuid = {$draft_uuid_sql} WHERE l.uuid = {$l_uuid_sql}"); // SQL UPDATE L
			} else {
				$ap_l_hdr = ['uuid' => 'NEWID()', 'object_owner' => $l_owner_sql, 'original' => 'original', 'record_type' => "'L'", 'approval_status' => "'A'", 'draft_author' => '0x00', 'approval_note' => "''", 'language' => $draft_lang_sql]; // Hlavička L
				$this->clone_with_map($ap_l_hdr + $ap_audit_map, "uuid = {$draft_uuid_sql}"); // Založení schváleného L záznamu
			}

			if (($is_final_class OR ! $is_native_lang) AND ! empty($existing_a)) { // Jednotná auditní stopa na 'A' záznamu
				$a_uuid_sql = guidliteral((string) $existing_a['uuid']); // UUID hlavního A záznamu
				sqlrun("UPDATE {$table} SET date_modified = GETDATE(), who_modified = {$approver_session_sql} WHERE uuid = {$a_uuid_sql}"); // Aktualizace auditu na A
			}
		}

		sqlrun("DELETE FROM {$table} WHERE uuid = {$draft_uuid_sql}"); // Fyzické odstranění právě schváleného návrhu ('D')

		$safe_auto_rej = charliteral($this->phrase('msg_auto_rejected_other_approved', 'Byl schválen záznam jiného uživatele.')); // Text automatického odmítnutí
		sqlrun("UPDATE {$table} SET approval_status = 'R', approval_note = {$safe_auto_rej}, date_modified = GETDATE(), who_modified = {$approver_session_sql} WHERE original = {$orig_sql} AND object_owner = {$owner_sql} AND record_type = 'D' AND [language] = {$draft_lang_sql}"); // Automatické odmítnutí souběžných návrhů

		$this->run_post_save_hooks($orig_sql, $owner_sql, $draft_lang_sql, $approver_session_sql); // Návazné operace po schválení

		sqlrun("COMMIT"); // Potvrzení transakce schválení
	}

	/**
	 * Odmítne / vrátí k přepracování vybraný návrh (`record_type = 'D'`) a uloží poznámku (`approval_note`).
	 */
	public function reject_draft(string $draft_uuid, string $approval_note = ''): void { // Odmítnutí návrhu schvalovatelem
		if (! $this->is_initialized OR trim($draft_uuid) === '') { // Kontrola platného vstupu
			return; // Ukončení při chybějícím UUID
		}

		global $dbsession; // Globální kontext relace schvalovatele
		$sess_org_raw = (string) ($dbsession['organization'] ?? '0x00'); // Surové UUID organizace schvalovatele
		$sess_org_sql = guidliteral($sess_org_raw); // SQL literál organizace schvalovatele
		$sess_lang_sql = charliteral((string) ($dbsession['language'] ?? 'cs'), 2); // SQL literál jazyka schvalovatele
		$is_sys_org_flag = is_sys_org($sess_org_raw); // Zda je schvalovatel v systémové organizaci 0x00

		$approver_session_sql = guidliteral((string) ($dbsession['login_session_uuid'] ?? '0x00')); // Relace schvalovatele
		$table = $this->storage_table; // Fyzická tabulka entity
		$draft_uuid_sql = guidliteral($draft_uuid); // SQL literál UUID návrhu

		$owner_cond = ($table === 'organization' AND $is_sys_org_flag)
			? "(object_owner = {$sess_org_sql} OR object_owner = original)"
			: "object_owner = {$sess_org_sql}"; // Izolace odmítaného návrhu podle tenanta

		$note_text = trim($approval_note); // Očištěný text poznámky
		if ($note_text === '') { // Výchozí text pokud schvalovatel nevyplnil poznámku
			$note_text = $this->phrase('msg_rejected_by_approver', 'Vráceno schvalovatelem k přepracování.'); // Výchozí důvod vrácení
		}
		$safe_note = charliteral($note_text); // SQL literál poznámky

		sqlrun("
			UPDATE {$table}
			SET approval_status = 'R',
				approval_note = {$safe_note},
				date_modified = GETDATE(),
				who_modified = {$approver_session_sql}
			WHERE uuid = {$draft_uuid_sql}
			  AND record_type = 'D'
			  AND {$owner_cond}
			  AND [language] = {$sess_lang_sql}
		"); // Přepnutí návrhu do stavu 'R' (Vráceno)
	}
}