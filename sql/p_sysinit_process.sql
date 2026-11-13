/* =============================================================================
 * Verze: 2026-11-13 18:30
 * Soubor: p_sysinit_process.sql
 * Procedura: dbo.p_sysinit_process
 * Účel:   Závěrečný procesor inicializačních tabulek sysinit_* (sysinit_object,
 *         sysinit_class, sysinit_column, sysinit_codetable, sysinit_menu,
 *         sysinit_phrase, sysinit_link_def).
 *         1. Idempotentně promítne nashromážděná systémová metadata a překlady
 *            (pro primární jazyk 'cs' jako záznamy 'A' + symetrické 'L', pro
 *            ostatní jazyky jako záznamy 'L') do cílových tabulek meta_*
 *            (object_owner = 0x00) při plném respektování ručních úprav v UI
 *            (who_modified <> 0x00) a s Delta kontrolou změn přes EXCEPT.
 *         2. V závěru automaticky promítne nativní 1:N cizí klíče (referenced_class)
 *            a stromové sloupce parent_uuid (parent_to_child 'P' / child_to_parent 'R')
 *            do tabulky meta_link_def jako odvozené vztahy (is_derived = 1).
 * Vazby:  - Volána ze závěrečné dávky final_scripts.sql (po p_fix_meta_column),
 *           případně samostatně v SSMS po spuštění dílčího skriptu *#phrase.sql
 *           nebo table_*.sql.
 * Změny:
 * - 2026-11-13 18:30: Do sekce 3b doplněno generování a aktualizace jazykových
 *   'L' záznamů pro lokální odchylky sloupců konkrétních tříd a přidána sekce 8
 *   pro automatickou projekci nativních 1:N vztahů do meta_link_def.
 * ============================================================================= */

EXECUTE dropni 'p_sysinit_process', 'P';
GO

CREATE PROCEDURE dbo.p_sysinit_process
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @c_class uniqueidentifier = dbo.f_generate_original('meta_class', @sys_owner, 'sys_global_columns', '');

	-- =========================================================================
	-- 1. ZPRACOVÁNÍ sysinit_object -> meta_object
	-- =========================================================================
	IF OBJECT_ID('sysinit_object', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM sysinit_object)
	BEGIN
		-- 1a. UPDATE a INSERT hlavních 'A' záznamů z primárního jazyka ('cs')
		UPDATE t
		SET t.system_role = s.system_role,
			t.module = CASE WHEN s.module <> '' THEN s.module ELSE t.module END,
			t.caption = CASE WHEN s.caption <> '' THEN s.caption ELSE t.caption END,
			t.caption_plural = CASE WHEN s.caption_plural <> '' THEN s.caption_plural ELSE t.caption_plural END,
			t.description = CASE WHEN s.description <> '' THEN s.description ELSE t.description END,
			t.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE t.helptext END,
			t.editor_note = CASE WHEN s.editor_note <> '' THEN s.editor_note ELSE t.editor_note END,
			t.[language] = 'cs',
			t.date_modified = GETDATE()
		FROM meta_object t
		JOIN sysinit_object s
			ON s.object_type = t.object_type
			AND s.builtin_code = t.builtin_code
			AND s.[language] = 'cs'
		WHERE t.object_owner = @sys_owner
		  AND t.record_type = 'A'
		  AND (t.who_modified = @sys_owner OR t.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT t.system_role, t.caption, t.description, t.helptext
			EXCEPT
			SELECT s.system_role,
				CASE WHEN s.caption <> '' THEN s.caption ELSE t.caption END,
				CASE WHEN s.description <> '' THEN s.description ELSE t.description END,
				CASE WHEN s.helptext <> '' THEN s.helptext ELSE t.helptext END
		  );

		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			object_type, builtin_code, system_role, module,
			caption, caption_plural, description, helptext, editor_note
		)
		SELECT
			x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
			s.object_type, s.builtin_code, s.system_role, s.module,
			NULLIF(s.caption, ''), NULLIF(s.caption_plural, ''), NULLIF(s.description, ''), NULLIF(s.helptext, ''), NULLIF(s.editor_note, '')
		FROM sysinit_object s
		CROSS APPLY (SELECT dbo.f_generate_original('meta_object', @sys_owner, s.object_type, s.builtin_code) AS orig) x
		WHERE s.[language] = 'cs'
		  AND NOT EXISTS (
			SELECT 1 FROM meta_object t
			WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
		  );

		-- 1b. UPDATE a INSERT jazykových 'L' záznamů pro všechny jazyky v sysinit_object
		UPDATE l
		SET l.system_role = a.system_role,
			l.module = a.module,
			l.caption = CASE WHEN s.caption <> '' THEN s.caption ELSE l.caption END,
			l.caption_plural = CASE WHEN s.caption_plural <> '' THEN s.caption_plural ELSE l.caption_plural END,
			l.description = CASE WHEN s.description <> '' THEN s.description ELSE l.description END,
			l.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END,
			l.date_modified = GETDATE()
		FROM meta_object l
		JOIN meta_object a
			ON a.original = l.original
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
		JOIN sysinit_object s
			ON s.object_type = a.object_type
			AND s.builtin_code = a.builtin_code
			AND s.[language] = l.[language]
		WHERE l.object_owner = @sys_owner
		  AND l.record_type = 'L'
		  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT l.system_role, l.caption, l.description, l.helptext
			EXCEPT
			SELECT a.system_role,
				CASE WHEN s.caption <> '' THEN s.caption ELSE l.caption END,
				CASE WHEN s.description <> '' THEN s.description ELSE l.description END,
				CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END
		  );

		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			object_type, builtin_code, system_role, module,
			caption, caption_plural, description, helptext
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', s.[language],
			a.object_type, a.builtin_code, a.system_role, a.module,
			NULLIF(s.caption, ''), NULLIF(s.caption_plural, ''), NULLIF(s.description, ''), NULLIF(s.helptext, '')
		FROM sysinit_object s
		JOIN meta_object a
			ON a.object_type = s.object_type
			AND a.builtin_code = s.builtin_code
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = s.[language]
		);
	END

	-- =========================================================================
	-- 2. ZPRACOVÁNÍ sysinit_class -> meta_class
	-- =========================================================================
	IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM sysinit_class)
	BEGIN
		-- 2a. UPDATE a INSERT hlavních 'A' záznamů z primárního jazyka ('cs')
		UPDATE mc
		SET mc.storage_object = COALESCE(stg.orig, mc.storage_object),
			mc.ancestor_class = CASE WHEN s.ancestor_code <> '' THEN anc.orig ELSE mc.ancestor_class END,
			mc.sort_code = CASE WHEN s.sort_code <> '' THEN s.sort_code ELSE mc.sort_code END,
			mc.days_in_trash = s.days_in_trash,
			mc.is_final = s.is_final,
			mc.is_protected = s.is_protected,
			mc.svg_icon = CASE WHEN ISNULL(mc.svg_icon, '') = '' AND s.svg_icon <> '' THEN s.svg_icon ELSE mc.svg_icon END,
			mc.caption = CASE WHEN s.caption <> '' THEN s.caption ELSE mc.caption END,
			mc.caption_plural = CASE WHEN s.caption_plural <> '' THEN s.caption_plural WHEN s.caption <> '' THEN s.caption ELSE mc.caption_plural END,
			mc.description = CASE WHEN s.description <> '' THEN s.description ELSE mc.description END,
			mc.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE mc.helptext END,
			mc.editor_note = CASE WHEN s.editor_note <> '' THEN s.editor_note ELSE mc.editor_note END,
			mc.[language] = 'cs',
			mc.date_modified = GETDATE()
		FROM meta_class mc
		JOIN sysinit_class s
			ON s.class_name = mc.class_name
			AND s.[language] = 'cs'
		OUTER APPLY (
			SELECT dbo.f_generate_original('meta_object', @sys_owner, ISNULL(NULLIF(s.storage_type, ''), 'T'), ISNULL(NULLIF(s.storage_code, ''), s.class_name)) AS orig
		) stg
		OUTER APPLY (
			SELECT CASE WHEN s.ancestor_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.ancestor_code, '') ELSE NULL END AS orig
		) anc
		WHERE mc.object_owner = @sys_owner
		  AND mc.record_type = 'A'
		  AND (mc.who_modified = @sys_owner OR mc.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT mc.caption, mc.caption_plural, mc.description, mc.helptext, mc.days_in_trash
			EXCEPT
			SELECT
				CASE WHEN s.caption <> '' THEN s.caption ELSE mc.caption END,
				CASE WHEN s.caption_plural <> '' THEN s.caption_plural WHEN s.caption <> '' THEN s.caption ELSE mc.caption_plural END,
				CASE WHEN s.description <> '' THEN s.description ELSE mc.description END,
				CASE WHEN s.helptext <> '' THEN s.helptext ELSE mc.helptext END,
				s.days_in_trash
		  );

		INSERT INTO meta_class (
			uuid, object_owner, original, record_type, approval_status, [language],
			class_name, storage_object, ancestor_class, sort_code, days_in_trash,
			svg_icon, is_final, is_protected,
			caption, caption_plural, description, helptext, editor_note
		)
		SELECT
			x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
			s.class_name, stg.orig, anc.orig, s.sort_code, s.days_in_trash,
			NULLIF(s.svg_icon, ''), s.is_final, s.is_protected,
			NULLIF(s.caption, ''), COALESCE(NULLIF(s.caption_plural, ''), NULLIF(s.caption, '')),
			NULLIF(s.description, ''), NULLIF(s.helptext, ''), NULLIF(s.editor_note, '')
		FROM sysinit_class s
		CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.class_name, '') AS orig) x
		CROSS APPLY (SELECT dbo.f_generate_original('meta_object', @sys_owner, ISNULL(NULLIF(s.storage_type, ''), 'T'), ISNULL(NULLIF(s.storage_code, ''), s.class_name)) AS orig) stg
		OUTER APPLY (SELECT CASE WHEN s.ancestor_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.ancestor_code, '') ELSE NULL END AS orig) anc
		WHERE s.[language] = 'cs'
		  AND NOT EXISTS (
			SELECT 1 FROM meta_class mc
			WHERE mc.original = x.orig AND mc.object_owner = @sys_owner AND mc.record_type = 'A'
		  );

		-- 2b. UPDATE a INSERT jazykových 'L' záznamů pro všechny jazyky v sysinit_class
		UPDATE l
		SET l.caption = CASE WHEN s.caption <> '' THEN s.caption ELSE l.caption END,
			l.caption_plural = CASE WHEN s.caption_plural <> '' THEN s.caption_plural WHEN s.caption <> '' THEN s.caption ELSE l.caption_plural END,
			l.description = CASE WHEN s.description <> '' THEN s.description ELSE l.description END,
			l.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END,
			l.date_modified = GETDATE()
		FROM meta_class l
		JOIN meta_class a
			ON a.original = l.original
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
		JOIN sysinit_class s
			ON s.class_name = a.class_name
			AND s.[language] = l.[language]
		WHERE l.object_owner = @sys_owner
		  AND l.record_type = 'L'
		  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT l.caption, l.caption_plural, l.description, l.helptext
			EXCEPT
			SELECT
				CASE WHEN s.caption <> '' THEN s.caption ELSE l.caption END,
				CASE WHEN s.caption_plural <> '' THEN s.caption_plural WHEN s.caption <> '' THEN s.caption ELSE l.caption_plural END,
				CASE WHEN s.description <> '' THEN s.description ELSE l.description END,
				CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END
		  );

		INSERT INTO meta_class (
			uuid, object_owner, original, record_type, approval_status, [language],
			class_name, storage_object, ancestor_class, sort_code, days_in_trash,
			svg_icon, is_final, is_protected,
			caption, caption_plural, description, helptext
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', s.[language],
			a.class_name, a.storage_object, a.ancestor_class, a.sort_code, a.days_in_trash,
			a.svg_icon, a.is_final, a.is_protected,
			NULLIF(s.caption, ''), COALESCE(NULLIF(s.caption_plural, ''), NULLIF(s.caption, '')),
			NULLIF(s.description, ''), NULLIF(s.helptext, '')
		FROM sysinit_class s
		JOIN meta_class a
			ON a.class_name = s.class_name
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_class l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = s.[language]
		);
	END

	-- =========================================================================
	-- 3. ZPRACOVÁNÍ sysinit_column -> meta_column (sys_global_columns + třídy)
	-- =========================================================================
	IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM sysinit_column)
	BEGIN
		-- 3a. Agregace (módus / prioritní '' záznam) pro každý (column_name, language) do #glob_col
		IF OBJECT_ID('tempdb..#glob_col') IS NOT NULL DROP TABLE #glob_col;

		;WITH ranked_glob AS (
			SELECT
				s.*,
				ROW_NUMBER() OVER (
					PARTITION BY s.column_name, s.[language]
					ORDER BY CASE WHEN s.table_name IN ('', 'sys_global_columns') THEN 0 ELSE 1 END ASC,
						LEN(s.caption) DESC,
						s.table_name ASC
				) AS rn
			FROM sysinit_column s
		)
		SELECT *
		INTO #glob_col
		FROM ranked_glob
		WHERE rn = 1;

		-- Aktualizace 'A' záznamů v sys_global_columns z #glob_col ('cs')
		UPDATE mc
		SET mc.caption = CASE WHEN g.caption <> '' THEN g.caption ELSE mc.caption END,
			mc.caption_plural = CASE WHEN g.caption_plural <> '' THEN g.caption_plural WHEN g.caption <> '' THEN g.caption ELSE mc.caption_plural END,
			mc.label = CASE WHEN g.label <> '' THEN g.label ELSE mc.label END,
			mc.header = CASE WHEN g.header <> '' THEN g.header ELSE mc.header END,
			mc.helptext = CASE WHEN g.helptext <> '' THEN g.helptext ELSE mc.helptext END,
			mc.placeholder = CASE WHEN g.placeholder <> '' THEN g.placeholder ELSE mc.placeholder END,
			mc.description = CASE WHEN g.description <> '' THEN g.description ELSE mc.description END,
			mc.editor_note = CASE WHEN g.editor_note <> '' THEN g.editor_note ELSE mc.editor_note END,
			mc.list_order = COALESCE(g.list_order, mc.list_order),
			mc.input_type = COALESCE(NULLIF(g.input_type, ''), mc.input_type),
			mc.input_width = COALESCE(NULLIF(g.input_width, ''), mc.input_width),
			mc.input_rows = COALESCE(g.input_rows, mc.input_rows),
			mc.translate = COALESCE(g.translate, mc.translate),
			mc.is_html = COALESCE(g.is_html, mc.is_html),
			mc.is_mandatory = COALESCE(g.is_mandatory, mc.is_mandatory),
			mc.hidden = COALESCE(g.hidden, mc.hidden),
			mc.is_protected = COALESCE(g.is_protected, mc.is_protected),
			mc.referenced_codetable = CASE WHEN g.referenced_codetable <> '' THEN g.referenced_codetable ELSE mc.referenced_codetable END,
			mc.referenced_class = COALESCE(rc.orig, mc.referenced_class),
			mc.[language] = 'cs',
			mc.date_modified = GETDATE()
		FROM meta_column mc
		JOIN #glob_col g
			ON g.column_name = mc.column_name
			AND g.[language] = 'cs'
		OUTER APPLY (
			SELECT CASE WHEN g.referenced_class_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), g.referenced_class_code, '') ELSE NULL END AS orig
		) rc
		WHERE mc.parent_class = @c_class
		  AND mc.object_owner = @sys_owner
		  AND mc.record_type = 'A'
		  AND (mc.who_modified = @sys_owner OR mc.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT mc.caption, mc.label, mc.header, mc.helptext, mc.referenced_codetable, mc.referenced_class
			EXCEPT
			SELECT
				CASE WHEN g.caption <> '' THEN g.caption ELSE mc.caption END,
				CASE WHEN g.label <> '' THEN g.label ELSE mc.label END,
				CASE WHEN g.header <> '' THEN g.header ELSE mc.header END,
				CASE WHEN g.helptext <> '' THEN g.helptext ELSE mc.helptext END,
				CASE WHEN g.referenced_codetable <> '' THEN g.referenced_codetable ELSE mc.referenced_codetable END,
				COALESCE(rc.orig, mc.referenced_class)
		  );

		-- Aktualizace a vložení 'L' záznamů v sys_global_columns pro všechny jazyky v #glob_col
		UPDATE l
		SET l.caption = CASE WHEN g.caption <> '' THEN g.caption ELSE l.caption END,
			l.caption_plural = CASE WHEN g.caption_plural <> '' THEN g.caption_plural WHEN g.caption <> '' THEN g.caption ELSE l.caption_plural END,
			l.label = CASE WHEN g.label <> '' THEN g.label ELSE l.label END,
			l.header = CASE WHEN g.header <> '' THEN g.header ELSE l.header END,
			l.helptext = CASE WHEN g.helptext <> '' THEN g.helptext ELSE l.helptext END,
			l.placeholder = CASE WHEN g.placeholder <> '' THEN g.placeholder ELSE l.placeholder END,
			l.description = CASE WHEN g.description <> '' THEN g.description ELSE l.description END,
			l.date_modified = GETDATE()
		FROM meta_column l
		JOIN meta_column a
			ON a.original = l.original
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.parent_class = @c_class
		JOIN #glob_col g
			ON g.column_name = a.column_name
			AND g.[language] = l.[language]
		WHERE l.object_owner = @sys_owner
		  AND l.record_type = 'L'
		  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT l.caption, l.label, l.header, l.helptext
			EXCEPT
			SELECT
				CASE WHEN g.caption <> '' THEN g.caption ELSE l.caption END,
				CASE WHEN g.label <> '' THEN g.label ELSE l.label END,
				CASE WHEN g.header <> '' THEN g.header ELSE l.header END,
				CASE WHEN g.helptext <> '' THEN g.helptext ELSE l.helptext END
		  );

		INSERT INTO meta_column (
			uuid, object_owner, original, record_type, approval_status, [language],
			parent_class, parent_order, sort_code, column_name, list_order,
			caption, caption_plural, description, label, header, helptext, placeholder,
			input_type, input_width, input_rows, max_length, css_class,
			translate, history, is_html, is_mandatory, is_url, is_computed,
			show_empty, hidden, customizable, ancestor, referenced_codetable, referenced_class,
			is_final, is_protected
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', g.[language],
			a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
			NULLIF(g.caption, ''), COALESCE(NULLIF(g.caption_plural, ''), NULLIF(g.caption, '')),
			NULLIF(g.description, ''), NULLIF(g.label, ''), NULLIF(g.header, ''), NULLIF(g.helptext, ''), NULLIF(g.placeholder, ''),
			a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
			a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
			a.show_empty, a.hidden, a.customizable, a.ancestor, a.referenced_codetable, a.referenced_class,
			a.is_final, a.is_protected
		FROM #glob_col g
		JOIN meta_column a
			ON a.parent_class = @c_class
			AND a.column_name = g.column_name
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_column l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = g.[language]
		);

		-- 3b. Specifické lokální odchylky sloupců konkrétních tříd (table_name <> '' a liší se od #glob_col)
		UPDATE mc
		SET mc.caption = CASE WHEN s.caption <> '' AND s.caption <> ISNULL(g.caption, '') THEN s.caption ELSE mc.caption END,
			mc.label = CASE WHEN s.label <> '' AND s.label <> ISNULL(g.label, '') THEN s.label ELSE mc.label END,
			mc.header = CASE WHEN s.header <> '' AND s.header <> ISNULL(g.header, '') THEN s.header ELSE mc.header END,
			mc.helptext = CASE WHEN s.helptext <> '' AND s.helptext <> ISNULL(g.helptext, '') THEN s.helptext ELSE mc.helptext END,
			mc.list_order = COALESCE(s.list_order, mc.list_order),
			mc.referenced_codetable = CASE WHEN s.referenced_codetable <> '' THEN s.referenced_codetable ELSE mc.referenced_codetable END,
			mc.referenced_class = COALESCE(rc.orig, mc.referenced_class),
			mc.date_modified = GETDATE()
		FROM sysinit_column s
		JOIN meta_class mcl
			ON mcl.class_name = s.table_name
			AND mcl.object_owner = @sys_owner
			AND mcl.record_type = 'A'
		JOIN meta_column mc
			ON mc.parent_class = mcl.original
			AND mc.column_name = s.column_name
			AND mc.object_owner = @sys_owner
			AND mc.record_type = 'A'
		LEFT JOIN #glob_col g
			ON g.column_name = s.column_name
			AND g.[language] = 'cs'
		OUTER APPLY (
			SELECT CASE WHEN s.referenced_class_code <> '' THEN dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.referenced_class_code, '') ELSE NULL END AS orig
		) rc
		WHERE s.table_name NOT IN ('', 'sys_global_columns')
		  AND s.[language] = 'cs'
		  AND (mc.who_modified = @sys_owner OR mc.date_modified < '2026-11-01')
		  AND (
			(s.caption <> '' AND s.caption <> ISNULL(g.caption, ''))
			OR (s.label <> '' AND s.label <> ISNULL(g.label, ''))
			OR (s.header <> '' AND s.header <> ISNULL(g.header, ''))
			OR (s.helptext <> '' AND s.helptext <> ISNULL(g.helptext, ''))
			OR s.list_order IS NOT NULL
			OR s.referenced_codetable <> ''
			OR rc.orig IS NOT NULL
		  );

		-- Aktualizace a vložení 'L' záznamů pro lokální odchylky sloupců konkrétních tříd
		UPDATE l
		SET l.caption = CASE WHEN s.caption <> '' THEN s.caption ELSE l.caption END,
			l.label = CASE WHEN s.label <> '' THEN s.label ELSE l.label END,
			l.header = CASE WHEN s.header <> '' THEN s.header ELSE l.header END,
			l.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END,
			l.date_modified = GETDATE()
		FROM sysinit_column s
		JOIN meta_class mcl
			ON mcl.class_name = s.table_name
			AND mcl.object_owner = @sys_owner
			AND mcl.record_type = 'A'
		JOIN meta_column a
			ON a.parent_class = mcl.original
			AND a.column_name = s.column_name
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
		JOIN meta_column l
			ON l.original = a.original
			AND l.object_owner = @sys_owner
			AND l.record_type = 'L'
			AND l.[language] = s.[language]
		LEFT JOIN #glob_col g
			ON g.column_name = s.column_name
			AND g.[language] = s.[language]
		WHERE s.table_name NOT IN ('', 'sys_global_columns')
		  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
		  AND (
			(s.caption <> '' AND s.caption <> ISNULL(g.caption, ''))
			OR (s.label <> '' AND s.label <> ISNULL(g.label, ''))
			OR (s.header <> '' AND s.header <> ISNULL(g.header, ''))
			OR (s.helptext <> '' AND s.helptext <> ISNULL(g.helptext, ''))
		  );

		INSERT INTO meta_column (
			uuid, object_owner, original, record_type, approval_status, [language],
			parent_class, parent_order, sort_code, column_name, list_order,
			caption, caption_plural, description, label, header, helptext, placeholder,
			input_type, input_width, input_rows, max_length, css_class,
			translate, history, is_html, is_mandatory, is_url, is_computed,
			show_empty, hidden, customizable, ancestor, referenced_codetable, referenced_class,
			is_final, is_protected
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', s.[language],
			a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
			NULLIF(s.caption, ''), COALESCE(NULLIF(s.caption_plural, ''), NULLIF(s.caption, '')),
			NULLIF(s.description, ''), NULLIF(s.label, ''), NULLIF(s.header, ''), NULLIF(s.helptext, ''), NULLIF(s.placeholder, ''),
			a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
			a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
			a.show_empty, a.hidden, a.customizable, a.ancestor, a.referenced_codetable, a.referenced_class,
			a.is_final, a.is_protected
		FROM sysinit_column s
		JOIN meta_class mcl
			ON mcl.class_name = s.table_name
			AND mcl.object_owner = @sys_owner
			AND mcl.record_type = 'A'
		JOIN meta_column a
			ON a.parent_class = mcl.original
			AND a.column_name = s.column_name
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		LEFT JOIN #glob_col g
			ON g.column_name = s.column_name
			AND g.[language] = s.[language]
		WHERE s.table_name NOT IN ('', 'sys_global_columns')
		  AND (
			(s.caption <> '' AND s.caption <> ISNULL(g.caption, ''))
			OR (s.label <> '' AND s.label <> ISNULL(g.label, ''))
			OR (s.header <> '' AND s.header <> ISNULL(g.header, ''))
			OR (s.helptext <> '' AND s.helptext <> ISNULL(g.helptext, ''))
		  )
		  AND NOT EXISTS (
			SELECT 1 FROM meta_column l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = s.[language]
		  );

		DROP TABLE #glob_col;
	END

	-- =========================================================================
	-- 4. ZPRACOVÁNÍ sysinit_codetable -> meta_codetable
	-- =========================================================================
	IF OBJECT_ID('sysinit_codetable', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM sysinit_codetable)
	BEGIN
		UPDATE mc
		SET mc.sort_code = CASE WHEN s.sort_code <> '' THEN s.sort_code ELSE mc.sort_code END,
			mc.caption = s.caption,
			mc.description = s.description,
			mc.helptext = s.helptext,
			mc.svg_icon = CASE WHEN ISNULL(mc.svg_icon, '') = '' AND s.svg_icon <> '' THEN s.svg_icon ELSE mc.svg_icon END,
			mc.color_code = CASE WHEN s.color_code <> '' THEN s.color_code ELSE mc.color_code END,
			mc.is_final = s.is_final,
			mc.is_protected = s.is_protected,
			mc.[language] = 'cs',
			mc.date_modified = GETDATE()
		FROM meta_codetable mc
		JOIN sysinit_codetable s
			ON s.codetable_name = mc.codetable_name
			AND s.value_code = mc.value_code
			AND s.[language] = 'cs'
		WHERE mc.object_owner = @sys_owner
		  AND mc.record_type = 'A'
		  AND (mc.who_modified = @sys_owner OR mc.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT mc.sort_code, mc.caption, mc.description, mc.helptext
			EXCEPT
			SELECT CASE WHEN s.sort_code <> '' THEN s.sort_code ELSE mc.sort_code END, s.caption, s.description, s.helptext
		  );

		INSERT INTO meta_codetable (
			uuid, object_owner, original, record_type, approval_status, [language],
			codetable_name, value_code, sort_code, caption, description, helptext,
			svg_icon, color_code, is_final, is_protected
		)
		SELECT
			x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
			s.codetable_name, s.value_code, s.sort_code, s.caption, s.description, s.helptext,
			s.svg_icon, s.color_code, s.is_final, s.is_protected
		FROM sysinit_codetable s
		CROSS APPLY (SELECT dbo.f_generate_original('meta_codetable', @sys_owner, s.codetable_name, s.value_code) AS orig) x
		WHERE s.[language] = 'cs'
		  AND NOT EXISTS (
			SELECT 1 FROM meta_codetable mc
			WHERE mc.original = x.orig AND mc.object_owner = @sys_owner AND mc.record_type = 'A'
		  );

		UPDATE l
		SET l.caption = s.caption,
			l.description = s.description,
			l.helptext = s.helptext,
			l.sort_code = a.sort_code,
			l.date_modified = GETDATE()
		FROM meta_codetable l
		JOIN meta_codetable a
			ON a.original = l.original
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
		JOIN sysinit_codetable s
			ON s.codetable_name = a.codetable_name
			AND s.value_code = a.value_code
			AND s.[language] = l.[language]
		WHERE l.object_owner = @sys_owner
		  AND l.record_type = 'L'
		  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT l.caption, l.description, l.helptext
			EXCEPT
			SELECT s.caption, s.description, s.helptext
		  );

		INSERT INTO meta_codetable (
			uuid, object_owner, original, record_type, approval_status, [language],
			codetable_name, value_code, sort_code, caption, description, helptext,
			svg_icon, color_code, is_final, is_protected
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', s.[language],
			a.codetable_name, a.value_code, a.sort_code, s.caption, s.description, s.helptext,
			a.svg_icon, a.color_code, a.is_final, a.is_protected
		FROM sysinit_codetable s
		JOIN meta_codetable a
			ON a.codetable_name = s.codetable_name
			AND a.value_code = s.value_code
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_codetable l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = s.[language]
		);
	END

	-- =========================================================================
	-- 5. ZPRACOVÁNÍ sysinit_menu -> meta_menu
	-- =========================================================================
	IF OBJECT_ID('sysinit_menu', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM sysinit_menu)
	BEGIN
		UPDATE m
		SET m.parent_uuid = p.parent_orig,
			m.sort_code = s.sort_code,
			m.target_object = t.target_orig,
			m.url_parameters = s.url_parameters,
			m.target_url = s.target_url,
			m.target_window = s.target_window,
			m.system_role = s.system_role,
			m.permanent = s.permanent,
			m.svg_icon = CASE WHEN ISNULL(m.svg_icon, '') = '' OR m.svg_icon LIKE '%fill="currentColor"%' THEN s.svg_icon ELSE m.svg_icon END,
			m.css_class = CASE WHEN s.css_class <> '' THEN s.css_class ELSE m.css_class END,
			m.caption = s.caption,
			m.description = s.description,
			m.helptext = s.helptext,
			m.editor_note = CASE WHEN s.editor_note <> '' THEN s.editor_note ELSE m.editor_note END,
			m.[language] = 'cs',
			m.date_modified = GETDATE()
		FROM meta_menu m
		JOIN sysinit_menu s
			ON s.builtin_code = m.builtin_code
			AND s.[language] = 'cs'
		OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('meta_menu', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
		OUTER APPLY (SELECT CASE WHEN s.target_page <> '' THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', s.target_page) ELSE NULL END AS target_orig) t
		WHERE m.object_owner = @sys_owner
		  AND m.record_type = 'A'
		  AND (m.who_modified = @sys_owner OR m.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT m.parent_uuid, m.sort_code, m.target_object, m.url_parameters, m.system_role, m.caption, m.helptext
			EXCEPT
			SELECT p.parent_orig, s.sort_code, t.target_orig, s.url_parameters, s.system_role, s.caption, s.helptext
		  );

		INSERT INTO meta_menu (
			uuid, object_owner, original, record_type, approval_status, [language],
			builtin_code, parent_uuid, sort_code, target_object, url_parameters, target_url, target_window,
			system_role, permanent, svg_icon, css_class, caption, description, helptext, editor_note,
			is_final, is_protected
		)
		SELECT
			x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
			s.builtin_code, p.parent_orig, s.sort_code, t.target_orig, s.url_parameters, s.target_url, s.target_window,
			s.system_role, s.permanent, s.svg_icon, s.css_class, s.caption, s.description, s.helptext, s.editor_note,
			1, 1
		FROM sysinit_menu s
		CROSS APPLY (SELECT dbo.f_generate_original('meta_menu', @sys_owner, s.builtin_code, '') AS orig) x
		OUTER APPLY (SELECT CASE WHEN s.parent_code <> '' THEN dbo.f_generate_original('meta_menu', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig) p
		OUTER APPLY (SELECT CASE WHEN s.target_page <> '' THEN dbo.f_generate_original('meta_object', @sys_owner, 'P', s.target_page) ELSE NULL END AS target_orig) t
		WHERE s.[language] = 'cs'
		  AND NOT EXISTS (
			SELECT 1 FROM meta_menu m
			WHERE m.original = x.orig AND m.object_owner = @sys_owner AND m.record_type = 'A'
		  );

		UPDATE l
		SET l.parent_uuid = a.parent_uuid,
			l.sort_code = a.sort_code,
			l.target_object = a.target_object,
			l.url_parameters = a.url_parameters,
			l.system_role = a.system_role,
			l.svg_icon = a.svg_icon,
			l.caption = s.caption,
			l.description = CASE WHEN s.description <> '' THEN s.description ELSE l.description END,
			l.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END,
			l.date_modified = GETDATE()
		FROM meta_menu l
		JOIN meta_menu a
			ON a.original = l.original
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
		JOIN sysinit_menu s
			ON s.builtin_code = a.builtin_code
			AND s.[language] = l.[language]
		WHERE l.object_owner = @sys_owner
		  AND l.record_type = 'L'
		  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
		  AND EXISTS (
			SELECT l.parent_uuid, l.sort_code, l.target_object, l.url_parameters, l.system_role, l.caption, l.helptext
			EXCEPT
			SELECT a.parent_uuid, a.sort_code, a.target_object, a.url_parameters, a.system_role, s.caption, CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END
		  );

		INSERT INTO meta_menu (
			uuid, object_owner, original, record_type, approval_status, [language],
			builtin_code, parent_uuid, sort_code, target_object, url_parameters, target_url, target_window,
			system_role, permanent, svg_icon, css_class, caption, description, helptext,
			is_final, is_protected
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', s.[language],
			a.builtin_code, a.parent_uuid, a.sort_code, a.target_object, a.url_parameters, a.target_url, a.target_window,
			a.system_role, a.permanent, a.svg_icon, a.css_class, s.caption, s.description, s.helptext,
			a.is_final, a.is_protected
		FROM sysinit_menu s
		JOIN meta_menu a
			ON a.builtin_code = s.builtin_code
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_menu l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = s.[language]
		);
	END

	-- =========================================================================
	-- 6. ZPRACOVÁNÍ sysinit_phrase -> meta_phrase (včetně auto-registrace 'P' v meta_object)
	-- =========================================================================
	IF OBJECT_ID('sysinit_phrase', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM sysinit_phrase)
	BEGIN
		-- 6a. Zajištění existence všech odkazovaných source_code jako objektů typu 'P' v meta_object
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			object_type, builtin_code, system_role, caption
		)
		SELECT
			x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
			'P', src.source_code, 'U', src.source_code
		FROM (SELECT DISTINCT source_code FROM sysinit_phrase WHERE source_code <> '') src
		CROSS APPLY (SELECT dbo.f_generate_original('meta_object', @sys_owner, 'P', src.source_code) AS orig) x
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object mo
			WHERE mo.original = x.orig AND mo.object_owner = @sys_owner AND mo.record_type = 'A'
		);

		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			object_type, builtin_code, system_role, caption
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
			'P', a.builtin_code, a.system_role, a.caption
		FROM meta_object a
		JOIN (SELECT DISTINCT source_code FROM sysinit_phrase WHERE source_code <> '') src ON src.source_code = a.builtin_code
		WHERE a.object_owner = @sys_owner
		  AND a.object_type = 'P'
		  AND a.record_type = 'A'
		  AND NOT EXISTS (
			SELECT 1 FROM meta_object l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
		  );

		-- 6b. UPDATE a INSERT hlavních 'A' záznamů frází z primárního jazyka ('cs')
		UPDATE mp
		SET mp.caption = s.caption,
			mp.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE mp.helptext END,
			mp.editor_note = CASE WHEN s.editor_note <> '' THEN s.editor_note ELSE mp.editor_note END,
			mp.css_class = CASE WHEN s.css_class <> '' THEN s.css_class ELSE mp.css_class END,
			mp.svg_icon = CASE WHEN ISNULL(mp.svg_icon, '') = '' AND s.svg_icon <> '' THEN s.svg_icon ELSE mp.svg_icon END,
			mp.module = CASE WHEN s.module <> '' THEN s.module ELSE mp.module END,
			mp.[language] = 'cs',
			mp.import_origin = CASE WHEN mp.import_origin = 'AUTO_DISCOVERED' THEN NULL ELSE mp.import_origin END,
			mp.who_modified = @sys_owner,
			mp.date_modified = GETDATE()
		FROM meta_phrase mp
		JOIN sysinit_phrase s
			ON s.source_code = mp.source_code
			AND s.builtin_code = mp.builtin_code
			AND s.[language] = 'cs'
		WHERE mp.object_owner = @sys_owner
		  AND mp.record_type = 'A'
		  AND (
			mp.who_modified = @sys_owner
			OR mp.date_modified < '2026-11-01'
			OR mp.import_origin = 'AUTO_DISCOVERED'
		  )
		  AND EXISTS (
			SELECT mp.caption, mp.helptext, mp.css_class, mp.[language]
			EXCEPT
			SELECT s.caption, CASE WHEN s.helptext <> '' THEN s.helptext ELSE mp.helptext END, CASE WHEN s.css_class <> '' THEN s.css_class ELSE mp.css_class END, 'cs'
		  );

		INSERT INTO meta_phrase (
			uuid, object_owner, original, record_type, approval_status, [language],
			source_code, builtin_code, module, caption, helptext, editor_note,
			svg_icon, css_class, is_final, is_protected
		)
		SELECT
			x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
			s.source_code, s.builtin_code, s.module, s.caption, s.helptext, s.editor_note,
			s.svg_icon, s.css_class, 1, 1
		FROM sysinit_phrase s
		CROSS APPLY (SELECT dbo.f_generate_original('meta_phrase', @sys_owner, s.source_code, s.builtin_code) AS orig) x
		WHERE s.[language] = 'cs'
		  AND NOT EXISTS (
			SELECT 1 FROM meta_phrase mp
			WHERE mp.original = x.orig AND mp.object_owner = @sys_owner AND mp.record_type = 'A'
		  );

		-- 6c. UPDATE a INSERT jazykových 'L' záznamů frází pro všechny jazyky v sysinit_phrase
		UPDATE l
		SET l.caption = s.caption,
			l.helptext = CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END,
			l.css_class = a.css_class,
			l.svg_icon = a.svg_icon,
			l.import_origin = CASE WHEN l.import_origin = 'AUTO_DISCOVERED' THEN NULL ELSE l.import_origin END,
			l.who_modified = @sys_owner,
			l.date_modified = GETDATE()
		FROM meta_phrase l
		JOIN meta_phrase a
			ON a.original = l.original
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
		JOIN sysinit_phrase s
			ON s.source_code = a.source_code
			AND s.builtin_code = a.builtin_code
			AND s.[language] = l.[language]
		WHERE l.object_owner = @sys_owner
		  AND l.record_type = 'L'
		  AND (
			l.who_modified = @sys_owner
			OR l.date_modified < '2026-11-01'
			OR l.import_origin = 'AUTO_DISCOVERED'
		  )
		  AND EXISTS (
			SELECT l.caption, l.helptext, l.css_class
			EXCEPT
			SELECT s.caption, CASE WHEN s.helptext <> '' THEN s.helptext ELSE l.helptext END, a.css_class
		  );

		INSERT INTO meta_phrase (
			uuid, object_owner, original, record_type, approval_status, [language],
			source_code, builtin_code, module, caption, helptext,
			svg_icon, css_class, is_final, is_protected
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', s.[language],
			a.source_code, a.builtin_code, a.module,
			s.caption, CASE WHEN s.helptext <> '' THEN s.helptext ELSE a.helptext END,
			a.svg_icon, a.css_class, a.is_final, a.is_protected
		FROM sysinit_phrase s
		JOIN meta_phrase a
			ON a.source_code = s.source_code
			AND a.builtin_code = s.builtin_code
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_phrase l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = s.[language]
		);
	END

	-- =========================================================================
	-- 7. ZPRACOVÁNÍ sysinit_link_def -> meta_link_def
	-- =========================================================================
	IF OBJECT_ID('sysinit_link_def', 'U') IS NOT NULL AND EXISTS (SELECT 1 FROM sysinit_link_def)
	BEGIN
		UPDATE t
		SET t.to_class = tc.orig,
			t.reverse_link_def = rc.rev_orig,
			t.direction_type = s.direction_type,
			t.is_exclusive_parent = s.is_exclusive_parent,
			t.is_derived = s.is_derived,
			t.is_multiple = s.is_multiple,
			t.is_mandatory = s.is_mandatory,
			t.leaf_only = s.leaf_only,
			t.transfer_roles = s.transfer_roles,
			t.link_weight_enabled = s.link_weight_enabled,
			t.caption_forward = s.caption_forward,
			t.caption_backward = s.caption_backward,
			t.description = s.description,
			t.helptext = s.helptext,
			t.[language] = 'cs',
			t.date_modified = GETDATE()
		FROM meta_link_def t
		JOIN sysinit_link_def s
			ON s.link_code = t.link_code
			AND s.[language] = 'cs'
		CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.from_class_code, '') AS orig) fc
		CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.to_class_code, '') AS orig) tc
		CROSS APPLY (SELECT CASE WHEN s.reverse_code <> '' THEN dbo.f_generate_original('meta_link_def', @sys_owner, CAST(tc.orig AS varchar(36)), s.reverse_code) ELSE NULL END AS rev_orig) rc
		WHERE t.object_owner = @sys_owner
		  AND t.from_class = fc.orig
		  AND t.record_type = 'A'
		  AND t.who_modified = @sys_owner
		  AND EXISTS (
			SELECT t.to_class, t.reverse_link_def, t.direction_type, t.is_exclusive_parent, t.is_derived, t.is_multiple, t.is_mandatory, t.leaf_only, t.link_weight_enabled, t.caption_forward, t.caption_backward, t.description, t.helptext
			EXCEPT
			SELECT tc.orig, rc.rev_orig, s.direction_type, s.is_exclusive_parent, s.is_derived, s.is_multiple, s.is_mandatory, s.leaf_only, s.link_weight_enabled, s.caption_forward, s.caption_backward, s.description, s.helptext
		  );

		INSERT INTO meta_link_def (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_code, from_class, to_class, reverse_link_def, direction_type,
			is_exclusive_parent, is_derived, caption_forward, caption_backward, description, helptext,
			is_multiple, is_mandatory, leaf_only, transfer_roles, link_weight_enabled,
			is_final, is_protected
		)
		SELECT
			x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
			s.link_code, fc.orig, tc.orig, rc.rev_orig, s.direction_type,
			s.is_exclusive_parent, s.is_derived, s.caption_forward, s.caption_backward, s.description, s.helptext,
			s.is_multiple, s.is_mandatory, s.leaf_only, s.transfer_roles, s.link_weight_enabled,
			1, 1
		FROM sysinit_link_def s
		CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.from_class_code, '') AS orig) fc
		CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.to_class_code, '') AS orig) tc
		CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, CAST(fc.orig AS varchar(36)), s.link_code) AS orig) x
		CROSS APPLY (SELECT CASE WHEN s.reverse_code <> '' THEN dbo.f_generate_original('meta_link_def', @sys_owner, CAST(tc.orig AS varchar(36)), s.reverse_code) ELSE NULL END AS rev_orig) rc
		WHERE s.[language] = 'cs'
		  AND NOT EXISTS (
			SELECT 1 FROM meta_link_def t
			WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
		  );

		UPDATE l
		SET l.from_class = a.from_class,
			l.to_class = a.to_class,
			l.reverse_link_def = a.reverse_link_def,
			l.direction_type = a.direction_type,
			l.is_exclusive_parent = a.is_exclusive_parent,
			l.is_derived = a.is_derived,
			l.caption_forward = s.caption_forward,
			l.caption_backward = s.caption_backward,
			l.description = s.description,
			l.helptext = s.helptext,
			l.date_modified = GETDATE()
		FROM meta_link_def l
		JOIN meta_link_def a
			ON a.original = l.original
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
		JOIN meta_class mc
			ON mc.original = a.from_class
			AND mc.object_owner = @sys_owner
			AND mc.record_type = 'A'
		JOIN sysinit_link_def s
			ON s.from_class_code = mc.class_name
			AND s.link_code = a.link_code
			AND s.[language] = l.[language]
		WHERE l.object_owner = @sys_owner
		  AND l.record_type = 'L'
		  AND l.who_modified = @sys_owner
		  AND EXISTS (
			SELECT l.reverse_link_def, l.direction_type, l.is_exclusive_parent, l.is_derived, l.caption_forward, l.caption_backward, l.description, l.helptext
			EXCEPT
			SELECT a.reverse_link_def, a.direction_type, a.is_exclusive_parent, a.is_derived, s.caption_forward, s.caption_backward, s.description, s.helptext
		  );

		INSERT INTO meta_link_def (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_code, from_class, to_class, reverse_link_def, direction_type,
			is_exclusive_parent, is_derived, caption_forward, caption_backward, description, helptext,
			is_multiple, is_mandatory, leaf_only, transfer_roles, link_weight_enabled,
			is_final, is_protected
		)
		SELECT
			NEWID(), @sys_owner, a.original, 'L', 'A', s.[language],
			a.link_code, a.from_class, a.to_class, a.reverse_link_def, a.direction_type,
			a.is_exclusive_parent, a.is_derived, s.caption_forward, s.caption_backward, s.description, s.helptext,
			a.is_multiple, a.is_mandatory, a.leaf_only, a.transfer_roles, a.link_weight_enabled,
			a.is_final, a.is_protected
		FROM sysinit_link_def s
		JOIN meta_class mc
			ON mc.class_name = s.from_class_code
			AND mc.object_owner = @sys_owner
			AND mc.record_type = 'A'
		JOIN meta_link_def a
			ON a.from_class = mc.original
			AND a.link_code = s.link_code
			AND a.object_owner = @sys_owner
			AND a.record_type = 'A'
			AND a.removed = 0
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_link_def l
			WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = s.[language]
		);
	END

	-- =========================================================================
	-- 8. AUTOMATICKÁ PROJEKCE NATIVNÍCH 1:N VAZEB (parent_uuid i cizích klíčů
	--    referenced_class) DO meta_link_def JAKO ODVOZENÝCH (is_derived = 1)
	-- =========================================================================
	IF OBJECT_ID('meta_link_def', 'U') IS NOT NULL AND COL_LENGTH('meta_link_def', 'direction_type') IS NOT NULL
	BEGIN
		DECLARE @batch_time datetime = GETDATE();
		DECLARE @native_links TABLE (
			from_class uuid NOT NULL,
			link_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
			to_class uuid NOT NULL,
			rev_from_class uuid NOT NULL,
			rev_link_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
			direction_type varchar(1) NOT NULL,
			is_exclusive_parent bit NOT NULL,
			is_multiple bit NOT NULL,
			is_mandatory bit NOT NULL,
			caption_cs varchar(200) NOT NULL,
			caption_rev_cs varchar(200) NOT NULL,
			caption_en varchar(200) NOT NULL,
			caption_rev_en varchar(200) NOT NULL,
			PRIMARY KEY (from_class, link_code)
		);

		-- 8a. Stromové vztahy parent_uuid na všech třídách (parent_to_child = 'P', child_to_parent = 'R')
		INSERT INTO @native_links (
			from_class, link_code, to_class, rev_from_class, rev_link_code,
			direction_type, is_exclusive_parent, is_multiple, is_mandatory,
			caption_cs, caption_rev_cs, caption_en, caption_rev_en
		)
		SELECT
			mcl.original, 'parent_to_child', mcl.original, mcl.original, 'child_to_parent',
			'P', 1, 1, 0,
			'Je nadřízenou položkou pro (parent_uuid)', 'Má nadřízenou položku (parent_uuid)',
			'Is parent item for (parent_uuid)', 'Has parent item (parent_uuid)'
		FROM meta_column mc
		JOIN meta_class mcl ON mcl.original = mc.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A' AND mcl.removed = 0
		WHERE mc.object_owner = 0x00
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
		  AND mc.column_name = 'parent_uuid'
		  AND mcl.class_name <> 'sys_global_columns'
		UNION ALL
		SELECT
			mcl.original, 'child_to_parent', mcl.original, mcl.original, 'parent_to_child',
			'R', 1, 0, 0,
			'Má nadřízenou položku (parent_uuid)', 'Je nadřízenou položkou pro (parent_uuid)',
			'Has parent item (parent_uuid)', 'Is parent item for (parent_uuid)'
		FROM meta_column mc
		JOIN meta_class mcl ON mcl.original = mc.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A' AND mcl.removed = 0
		WHERE mc.object_owner = 0x00
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
		  AND mc.column_name = 'parent_uuid'
		  AND mcl.class_name <> 'sys_global_columns';

		-- 8b. Ostatní nativní 1:N cizí klíče (referenced_class IS NOT NULL, mimo systémové tabulky meta_* a sloupce v tabulce link)
		INSERT INTO @native_links (
			from_class, link_code, to_class, rev_from_class, rev_link_code,
			direction_type, is_exclusive_parent, is_multiple, is_mandatory,
			caption_cs, caption_rev_cs, caption_en, caption_rev_en
		)
		SELECT
			ref_cls.original,
			LEFT('ref_by_' + mcl.class_name + '_' + mc.column_name, 80),
			mcl.original,
			mcl.original,
			LEFT('fk_' + mc.column_name, 80),
			'P', 0, 1, 0,
			LEFT('Je odkazováno z ' + COALESCE(NULLIF(mcl.caption, ''), mcl.class_name) + ' (' + mc.column_name + ')', 200),
			LEFT('Odkazuje na ' + COALESCE(NULLIF(ref_cls.caption, ''), ref_cls.class_name) + ' (' + mc.column_name + ')', 200),
			LEFT('Is referenced by ' + mcl.class_name + ' (' + mc.column_name + ')', 200),
			LEFT('References ' + ref_cls.class_name + ' (' + mc.column_name + ')', 200)
		FROM meta_column mc
		JOIN meta_class mcl ON mcl.original = mc.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A' AND mcl.removed = 0
		LEFT JOIN meta_column gc ON gc.original = mc.ancestor AND gc.object_owner = 0x00 AND gc.record_type = 'A'
		JOIN meta_class ref_cls ON ref_cls.original = COALESCE(mc.referenced_class, gc.referenced_class) AND ref_cls.object_owner = 0x00 AND ref_cls.record_type = 'A' AND ref_cls.removed = 0
		WHERE mc.object_owner = 0x00
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
		  AND mc.column_name <> 'parent_uuid'
		  AND mcl.class_name NOT IN ('sys_global_columns', 'link')
		  AND mcl.class_name NOT LIKE 'meta_%'
		UNION ALL
		SELECT
			mcl.original,
			LEFT('fk_' + mc.column_name, 80),
			ref_cls.original,
			ref_cls.original,
			LEFT('ref_by_' + mcl.class_name + '_' + mc.column_name, 80),
			'R', 0, 0, COALESCE(mc.is_mandatory, gc.is_mandatory, 0),
			LEFT('Odkazuje na ' + COALESCE(NULLIF(ref_cls.caption, ''), ref_cls.class_name) + ' (' + mc.column_name + ')', 200),
			LEFT('Je odkazováno z ' + COALESCE(NULLIF(mcl.caption, ''), mcl.class_name) + ' (' + mc.column_name + ')', 200),
			LEFT('References ' + ref_cls.class_name + ' (' + mc.column_name + ')', 200),
			LEFT('Is referenced by ' + mcl.class_name + ' (' + mc.column_name + ')', 200)
		FROM meta_column mc
		JOIN meta_class mcl ON mcl.original = mc.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A' AND mcl.removed = 0
		LEFT JOIN meta_column gc ON gc.original = mc.ancestor AND gc.object_owner = 0x00 AND gc.record_type = 'A'
		JOIN meta_class ref_cls ON ref_cls.original = COALESCE(mc.referenced_class, gc.referenced_class) AND ref_cls.object_owner = 0x00 AND ref_cls.record_type = 'A' AND ref_cls.removed = 0
		WHERE mc.object_owner = 0x00
		  AND mc.record_type = 'A'
		  AND mc.removed = 0
		  AND mc.column_name <> 'parent_uuid'
		  AND mcl.class_name NOT IN ('sys_global_columns', 'link')
		  AND mcl.class_name NOT LIKE 'meta_%';

		INSERT INTO meta_link_def (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_code, from_class, to_class, reverse_link_def, direction_type,
			is_exclusive_parent, is_derived,
			caption_forward, caption_backward,
			is_multiple, is_mandatory, leaf_only, link_weight_enabled,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.orig, 0x00, x.orig, 'A', 'A', 'cs',
			nl.link_code, nl.from_class, nl.to_class, r.rev_orig, nl.direction_type,
			nl.is_exclusive_parent, 1,
			nl.caption_cs, nl.caption_rev_cs,
			nl.is_multiple, nl.is_mandatory, 0, 0,
			1, 1,
			@batch_time, @sys_owner, @batch_time, @sys_owner
		FROM @native_links nl
		CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, CAST(nl.from_class AS varchar(36)), nl.link_code) AS orig) x
		CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, CAST(nl.rev_from_class AS varchar(36)), nl.rev_link_code) AS rev_orig) r
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_link_def mld
			WHERE mld.original = x.orig AND mld.object_owner = 0x00 AND mld.record_type = 'A'
		);

		INSERT INTO meta_link_def (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_code, from_class, to_class, reverse_link_def, direction_type,
			is_exclusive_parent, is_derived,
			caption_forward, caption_backward,
			is_multiple, is_mandatory, leaf_only, link_weight_enabled,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), 0x00, x.orig, 'L', 'A', 'cs',
			nl.link_code, nl.from_class, nl.to_class, r.rev_orig, nl.direction_type,
			nl.is_exclusive_parent, 1,
			nl.caption_cs, nl.caption_rev_cs,
			nl.is_multiple, nl.is_mandatory, 0, 0,
			1, 1,
			@batch_time, @sys_owner, @batch_time, @sys_owner
		FROM @native_links nl
		CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, CAST(nl.from_class AS varchar(36)), nl.link_code) AS orig) x
		CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, CAST(nl.rev_from_class AS varchar(36)), nl.rev_link_code) AS rev_orig) r
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_link_def mld
			WHERE mld.original = x.orig AND mld.object_owner = 0x00 AND mld.record_type = 'L' AND mld.[language] = 'cs'
		);

		INSERT INTO meta_link_def (
			uuid, object_owner, original, record_type, approval_status, [language],
			link_code, from_class, to_class, reverse_link_def, direction_type,
			is_exclusive_parent, is_derived,
			caption_forward, caption_backward,
			is_multiple, is_mandatory, leaf_only, link_weight_enabled,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			NEWID(), 0x00, x.orig, 'L', 'A', 'en',
			nl.link_code, nl.from_class, nl.to_class, r.rev_orig, nl.direction_type,
			nl.is_exclusive_parent, 1,
			nl.caption_en, nl.caption_rev_en,
			nl.is_multiple, nl.is_mandatory, 0, 0,
			1, 1,
			@batch_time, @sys_owner, @batch_time, @sys_owner
		FROM @native_links nl
		CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, CAST(nl.from_class AS varchar(36)), nl.link_code) AS orig) x
		CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, CAST(nl.rev_from_class AS varchar(36)), nl.rev_link_code) AS rev_orig) r
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_link_def mld
			WHERE mld.original = x.orig AND mld.object_owner = 0x00 AND mld.record_type = 'L' AND mld.[language] = 'en'
		);
	END
END
GO