EXECUTE dropni 'page_xlsx_export_meta', 'P';
GO

/* =============================================================================
 * Verze: 2026-11-16 15:40
 * Soubor: page_xlsx_export_meta.sql
 * Procedura: dbo.page_xlsx_export_meta
 *
 * 1. Role souboru v celém systému:
 *    Databázová podpora pro zpětný export systémových metadat (object_owner = 0x00)
 *    do sešitu meta_object.xlsx na stránce page_xlsx_export_meta.php:
 *    - @subpage = 'languages': Vrátí seznam podporovaných jazyků z [language].
 *    - @subpage = 'page':      Vrátí stránky a UI třídy (meta_object typu 'P').
 *    - @subpage = 'menu':      Vrátí položky navigace (meta_menu).
 *    - @subpage = 'phrase':    Vrátí lokalizační fráze (meta_phrase).
 *    - @subpage = 'class':     Vrátí logické třídy (meta_class) včetně předků.
 *    - @subpage = 'column':    Vrátí sloupce metadat (meta_column) včetně
 *                              zděděných hodnot z globálního slovníku.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Volána z PHP třídy page_xlsx_export_meta (page_xlsx_export_meta.php).
 *    - Automaticky zařazena do buildu databáze maskou page_*.sql v BuildListDb.txt.
 *    - Čte tabulky language, meta_object, meta_menu, meta_phrase, meta_class
 *      a meta_column.
 *
 * 3. Očekávaná kontextová data:
 *    - Přijímá primární jazyk exportu (@lang) a volitelný druhý jazyk (@sec_lang);
 *      čte výhradně systémové záznamy (object_owner = 0x00).
 * ============================================================================= */
CREATE PROCEDURE dbo.page_xlsx_export_meta
	@subpage varchar(30),
	@lang varchar(2) = 'cs',
	@sec_lang varchar(2) = ''
AS
BEGIN
	SET NOCOUNT ON;

	SET @lang = ISNULL(NULLIF(LTRIM(RTRIM(@lang)), ''), 'cs');
	SET @sec_lang = ISNULL(LTRIM(RTRIM(@sec_lang)), '');
	IF @sec_lang = @lang
		SET @sec_lang = '';

	-- 1. Seznam podporovaných jazyků pro formulář exportu
	IF @subpage = 'languages'
	BEGIN
		SELECT [language], caption
		FROM [language]
		ORDER BY sort_code;
		RETURN;
	END

	-- 2. Záložka page (meta_object, object_type = 'P')
	IF @subpage = 'page'
	BEGIN
		SELECT
			a.builtin_code,
			a.system_role,
			a.module,
			a.inactive,
			CASE
				WHEN a.removed = 1 THEN 1
				WHEN @sec_lang <> '' AND l2.uuid IS NOT NULL THEN l2.removed
				ELSE 0
			END AS removed,
			ISNULL(a.editor_note, '') AS editor_note,
			COALESCE(NULLIF(l1.caption, ''), a.caption, '') AS caption,
			COALESCE(NULLIF(l1.description, ''), a.description, '') AS description,
			COALESCE(NULLIF(l1.helptext, ''), a.helptext, '') AS helptext,
			l2.caption AS own_caption_l,
			l2.description AS own_description_l,
			l2.helptext AS own_helptext_l
		FROM meta_object a
		LEFT JOIN meta_object l1
			ON l1.original = a.original
			AND l1.object_owner = 0x00
			AND l1.record_type = 'L'
			AND l1.[language] = @lang
			AND l1.removed = 0
		LEFT JOIN meta_object l2
			ON l2.original = a.original
			AND l2.object_owner = 0x00
			AND l2.record_type = 'L'
			AND l2.[language] = @sec_lang
			AND @sec_lang <> ''
		WHERE a.object_owner = 0x00
		  AND a.object_type = 'P'
		  AND a.builtin_code <> ''
		  AND a.record_type = 'A'
		ORDER BY
			CASE WHEN a.builtin_code = 'global_phrase' THEN 0 WHEN a.builtin_code LIKE 'page_%' THEN 2 ELSE 1 END,
			a.builtin_code;
		RETURN;
	END

	-- 3. Záložka menu (meta_menu – bez sloupce svg_icon)
	IF @subpage = 'menu'
	BEGIN
		SELECT
			m.builtin_code,
			ISNULL(pm.builtin_code, '') AS parent_code,
			m.sort_code,
			ISNULL(mo.builtin_code, '') AS target_page,
			m.url_parameters,
			m.target_url,
			m.target_window,
			m.system_role,
			m.permanent,
			CASE
				WHEN m.removed = 1 THEN 1
				WHEN m.parent_uuid IS NOT NULL AND (pm.original IS NULL OR pm.removed = 1) THEN 1
				WHEN m.target_object IS NOT NULL AND (mo.original IS NULL OR mo.removed = 1) THEN 1
				WHEN @sec_lang <> '' AND l2.uuid IS NOT NULL THEN l2.removed
				ELSE 0
			END AS removed,
			m.css_class,
			ISNULL(m.editor_note, '') AS editor_note,
			COALESCE(NULLIF(l1.caption, ''), m.caption, '') AS caption,
			COALESCE(NULLIF(l1.description, ''), m.description, '') AS description,
			COALESCE(NULLIF(l1.helptext, ''), m.helptext, '') AS helptext,
			l2.caption AS own_caption_l,
			l2.description AS own_description_l,
			l2.helptext AS own_helptext_l
		FROM meta_menu m
		LEFT JOIN meta_menu pm
			ON pm.original = m.parent_uuid
			AND pm.object_owner = 0x00
			AND pm.record_type = 'A'
		LEFT JOIN meta_object mo
			ON mo.original = m.target_object
			AND mo.object_owner = 0x00
			AND mo.record_type = 'A'
		LEFT JOIN meta_menu l1
			ON l1.original = m.original
			AND l1.object_owner = 0x00
			AND l1.record_type = 'L'
			AND l1.[language] = @lang
			AND l1.removed = 0
		LEFT JOIN meta_menu l2
			ON l2.original = m.original
			AND l2.object_owner = 0x00
			AND l2.record_type = 'L'
			AND l2.[language] = @sec_lang
			AND @sec_lang <> ''
		WHERE m.object_owner = 0x00
		  AND m.record_type = 'A'
		ORDER BY
			CASE WHEN m.parent_uuid IS NULL THEN 0 ELSE 1 END,
			m.sort_code,
			m.builtin_code;
		RETURN;
	END

	-- 4. Záložka phrase (meta_phrase – bez sloupce svg_icon)
	IF @subpage = 'phrase'
	BEGIN
		SELECT
			CASE WHEN ISNULL(LTRIM(RTRIM(a.source_code)), '') = '' THEN 'global_phrase' ELSE a.source_code END AS source_code,
			a.builtin_code,
			a.module,
			a.css_class,
			a.inactive,
			CASE
				WHEN a.removed = 1 THEN 1
				WHEN mo.original IS NULL OR mo.removed = 1 THEN 1
				WHEN @sec_lang <> '' AND l2.uuid IS NOT NULL THEN l2.removed
				ELSE 0
			END AS removed,
			ISNULL(a.editor_note, '') AS editor_note,
			COALESCE(NULLIF(CAST(l1.caption AS NVARCHAR(MAX)), ''), CAST(a.caption AS NVARCHAR(MAX)), '') AS caption,
			COALESCE(NULLIF(CAST(l1.helptext AS NVARCHAR(MAX)), ''), CAST(a.helptext AS NVARCHAR(MAX)), '') AS helptext,
			CAST(l2.caption AS NVARCHAR(MAX)) AS own_caption_l,
			CAST(l2.helptext AS NVARCHAR(MAX)) AS own_helptext_l
		FROM meta_phrase a
		LEFT JOIN meta_object mo
			ON mo.object_type = 'P'
			AND mo.builtin_code = CASE WHEN ISNULL(LTRIM(RTRIM(a.source_code)), '') = '' THEN 'global_phrase' ELSE LTRIM(RTRIM(a.source_code)) END
			AND mo.object_owner = 0x00
			AND mo.record_type = 'A'
		LEFT JOIN meta_phrase l1
			ON l1.original = a.original
			AND l1.object_owner = 0x00
			AND l1.record_type = 'L'
			AND l1.[language] = @lang
			AND l1.removed = 0
		LEFT JOIN meta_phrase l2
			ON l2.original = a.original
			AND l2.object_owner = 0x00
			AND l2.record_type = 'L'
			AND l2.[language] = @sec_lang
			AND @sec_lang <> ''
		WHERE a.object_owner = 0x00
		  AND a.record_type = 'A'
		ORDER BY
			CASE WHEN ISNULL(LTRIM(RTRIM(a.source_code)), '') IN ('', 'global_phrase') THEN 0 ELSE 1 END,
			a.source_code,
			a.builtin_code;
		RETURN;
	END

	-- 5. Záložka class (meta_class – včetně days_in_trash, bez svg_icon)
	IF @subpage = 'class'
	BEGIN
		SELECT
			c.class_name,
			ISNULL(mo.object_type, CASE WHEN c.class_name LIKE 'v[_]%' OR c.class_name LIKE 'vrepo[_]%' THEN 'V' ELSE 'T' END) AS storage_type,
			ISNULL(mo.builtin_code, c.class_name) AS storage_code,
			ISNULL(anc.class_name, '') AS ancestor_code,
			c.sort_code,
			ISNULL(c.days_in_trash, 365) AS days_in_trash,
			c.is_final,
			c.is_protected,
			c.inactive,
			CASE
				WHEN c.removed = 1 THEN 1
				WHEN mo.original IS NULL OR mo.removed = 1 THEN 1
				WHEN c.ancestor_class IS NOT NULL AND (anc.original IS NULL OR anc.removed = 1) THEN 1
				WHEN @sec_lang <> '' AND l2.uuid IS NOT NULL THEN l2.removed
				ELSE 0
			END AS removed,
			ISNULL(c.editor_note, '') AS editor_note,
			COALESCE(NULLIF(l1.caption, ''), c.caption) AS own_caption,
			COALESCE(NULLIF(anc_l1.caption, ''), anc.caption) AS anc_caption,
			l2.caption AS own_caption_l,
			COALESCE(NULLIF(anc_l2.caption, ''), NULLIF(l1.caption, ''), NULLIF(c.caption, ''), NULLIF(anc_l1.caption, ''), anc.caption) AS inh_caption_l,
			COALESCE(NULLIF(l1.caption_plural, ''), c.caption_plural) AS own_caption_plural,
			COALESCE(NULLIF(anc_l1.caption_plural, ''), anc.caption_plural) AS anc_caption_plural,
			l2.caption_plural AS own_caption_plural_l,
			COALESCE(NULLIF(anc_l2.caption_plural, ''), NULLIF(l1.caption_plural, ''), NULLIF(c.caption_plural, ''), NULLIF(anc_l1.caption_plural, ''), anc.caption_plural) AS inh_caption_plural_l,
			COALESCE(NULLIF(l1.description, ''), c.description) AS own_description,
			COALESCE(NULLIF(anc_l1.description, ''), anc.description) AS anc_description,
			l2.description AS own_description_l,
			COALESCE(NULLIF(anc_l2.description, ''), NULLIF(l1.description, ''), NULLIF(c.description, ''), NULLIF(anc_l1.description, ''), anc.description) AS inh_description_l,
			COALESCE(NULLIF(l1.helptext, ''), c.helptext) AS own_helptext,
			COALESCE(NULLIF(anc_l1.helptext, ''), anc.helptext) AS anc_helptext,
			l2.helptext AS own_helptext_l,
			COALESCE(NULLIF(anc_l2.helptext, ''), NULLIF(l1.helptext, ''), NULLIF(c.helptext, ''), NULLIF(anc_l1.helptext, ''), anc.helptext) AS inh_helptext_l
		FROM meta_class c
		LEFT JOIN meta_object mo ON mo.original = c.storage_object AND mo.object_owner = 0x00 AND mo.record_type = 'A'
		LEFT JOIN meta_class anc ON anc.original = c.ancestor_class AND anc.object_owner = 0x00 AND anc.record_type = 'A'
		LEFT JOIN meta_class l1 ON l1.original = c.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = @lang AND l1.removed = 0
		LEFT JOIN meta_class anc_l1 ON anc_l1.original = anc.original AND anc_l1.object_owner = 0x00 AND anc_l1.record_type = 'L' AND anc_l1.[language] = @lang AND anc_l1.removed = 0
		LEFT JOIN meta_class l2 ON l2.original = c.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = @sec_lang AND @sec_lang <> ''
		LEFT JOIN meta_class anc_l2 ON anc_l2.original = anc.original AND anc_l2.object_owner = 0x00 AND anc_l2.record_type = 'L' AND anc_l2.[language] = @sec_lang AND anc_l2.removed = 0 AND @sec_lang <> ''
		WHERE c.object_owner = 0x00
		  AND c.record_type = 'A'
		ORDER BY
			CASE WHEN c.class_name = 'sys_global_columns' THEN 0 ELSE 1 END,
			c.class_name;
		RETURN;
	END

	-- 6. Záložka column (meta_column)
	IF @subpage = 'column'
	BEGIN
		SELECT
			mcl.class_name,
			c.column_name,
			c.parent_order,
			c.sort_code AS own_sort_code, gc.sort_code AS anc_sort_code,
			c.list_order AS own_list_order, gc.list_order AS anc_list_order,
			c.input_type AS own_input_type, gc.input_type AS anc_input_type,
			c.input_width AS own_input_width, gc.input_width AS anc_input_width,
			c.input_rows AS own_input_rows, gc.input_rows AS anc_input_rows,
			c.max_length AS own_max_length, gc.max_length AS anc_max_length,
			c.css_class AS own_css_class, gc.css_class AS anc_css_class,
			c.translate AS own_translate, gc.translate AS anc_translate,
			c.history AS own_history, gc.history AS anc_history,
			c.is_html AS own_is_html, gc.is_html AS anc_is_html,
			c.is_mandatory AS own_is_mandatory, gc.is_mandatory AS anc_is_mandatory,
			c.is_url AS own_is_url, gc.is_url AS anc_is_url,
			c.is_computed AS own_is_computed, gc.is_computed AS anc_is_computed,
			c.show_empty AS own_show_empty, gc.show_empty AS anc_show_empty,
			c.hidden AS own_hidden, gc.hidden AS anc_hidden,
			c.customizable AS own_customizable, gc.customizable AS anc_customizable,
			ISNULL(gc.column_name, '') AS ancestor_column,
			c.referenced_codetable AS own_ref_codetable, gc.referenced_codetable AS anc_ref_codetable,
			rc_own.class_name AS own_ref_class_code, rc_anc.class_name AS anc_ref_class_code,
			c.is_final,
			c.is_protected,
			c.inactive,
			CASE
				WHEN c.removed = 1 THEN 1
				WHEN mcl.removed = 1 OR mo.original IS NULL OR mo.removed = 1 THEN 1
				WHEN @sec_lang <> '' AND l2.uuid IS NOT NULL THEN l2.removed
				ELSE 0
			END AS removed,
			ISNULL(c.editor_note, '') AS editor_note,
			COALESCE(NULLIF(l1.caption, ''), c.caption) AS own_caption,
			COALESCE(NULLIF(gc_l1.caption, ''), gc.caption) AS anc_caption,
			l2.caption AS own_caption_l,
			COALESCE(NULLIF(gc_l2.caption, ''), NULLIF(l1.caption, ''), NULLIF(c.caption, ''), NULLIF(gc_l1.caption, ''), gc.caption) AS inh_caption_l,
			COALESCE(NULLIF(l1.caption_plural, ''), c.caption_plural) AS own_caption_plural,
			COALESCE(NULLIF(gc_l1.caption_plural, ''), gc.caption_plural) AS anc_caption_plural,
			l2.caption_plural AS own_caption_plural_l,
			COALESCE(NULLIF(gc_l2.caption_plural, ''), NULLIF(l1.caption_plural, ''), NULLIF(c.caption_plural, ''), NULLIF(gc_l1.caption_plural, ''), gc.caption_plural) AS inh_caption_plural_l,
			COALESCE(NULLIF(l1.description, ''), c.description) AS own_description,
			COALESCE(NULLIF(gc_l1.description, ''), gc.description) AS anc_description,
			l2.description AS own_description_l,
			COALESCE(NULLIF(gc_l2.description, ''), NULLIF(l1.description, ''), NULLIF(c.description, ''), NULLIF(gc_l1.description, ''), gc.description) AS inh_description_l,
			COALESCE(NULLIF(l1.label, ''), c.label) AS own_label,
			COALESCE(NULLIF(gc_l1.label, ''), gc.label) AS anc_label,
			l2.label AS own_label_l,
			COALESCE(NULLIF(gc_l2.label, ''), NULLIF(l1.label, ''), NULLIF(c.label, ''), NULLIF(gc_l1.label, ''), gc.label) AS inh_label_l,
			COALESCE(NULLIF(l1.header, ''), c.header) AS own_header,
			COALESCE(NULLIF(gc_l1.header, ''), gc.header) AS anc_header,
			l2.header AS own_header_l,
			COALESCE(NULLIF(gc_l2.header, ''), NULLIF(l1.header, ''), NULLIF(c.header, ''), NULLIF(gc_l1.header, ''), gc.header) AS inh_header_l,
			COALESCE(NULLIF(l1.helptext, ''), c.helptext) AS own_helptext,
			COALESCE(NULLIF(gc_l1.helptext, ''), gc.helptext) AS anc_helptext,
			l2.helptext AS own_helptext_l,
			COALESCE(NULLIF(gc_l2.helptext, ''), NULLIF(l1.helptext, ''), NULLIF(c.helptext, ''), NULLIF(gc_l1.helptext, ''), gc.helptext) AS inh_helptext_l,
			COALESCE(NULLIF(l1.placeholder, ''), c.placeholder) AS own_placeholder,
			COALESCE(NULLIF(gc_l1.placeholder, ''), gc.placeholder) AS anc_placeholder,
			l2.placeholder AS own_placeholder_l,
			COALESCE(NULLIF(gc_l2.placeholder, ''), NULLIF(l1.placeholder, ''), NULLIF(c.placeholder, ''), NULLIF(gc_l1.placeholder, ''), gc.placeholder) AS inh_placeholder_l
		FROM meta_column c
		JOIN meta_class mcl ON mcl.original = c.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A'
		LEFT JOIN meta_object mo ON mo.original = mcl.storage_object AND mo.object_owner = 0x00 AND mo.record_type = 'A'
		LEFT JOIN meta_column gc ON gc.original = c.ancestor AND gc.object_owner = 0x00 AND gc.record_type = 'A' AND gc.removed = 0
		LEFT JOIN meta_class rc_own ON rc_own.original = c.referenced_class AND rc_own.object_owner = 0x00 AND rc_own.record_type = 'A' AND rc_own.removed = 0
		LEFT JOIN meta_class rc_anc ON rc_anc.original = gc.referenced_class AND rc_anc.object_owner = 0x00 AND rc_anc.record_type = 'A' AND rc_anc.removed = 0
		LEFT JOIN meta_column l1 ON l1.original = c.original AND l1.object_owner = 0x00 AND l1.record_type = 'L' AND l1.[language] = @lang AND l1.removed = 0
		LEFT JOIN meta_column gc_l1 ON gc_l1.original = gc.original AND gc_l1.object_owner = 0x00 AND gc_l1.record_type = 'L' AND gc_l1.[language] = @lang AND gc_l1.removed = 0
		LEFT JOIN meta_column l2 ON l2.original = c.original AND l2.object_owner = 0x00 AND l2.record_type = 'L' AND l2.[language] = @sec_lang AND @sec_lang <> ''
		LEFT JOIN meta_column gc_l2 ON gc_l2.original = gc.original AND gc_l2.object_owner = 0x00 AND gc_l2.record_type = 'L' AND gc_l2.[language] = @sec_lang AND gc_l2.removed = 0 AND @sec_lang <> ''
		WHERE c.object_owner = 0x00
		  AND c.record_type = 'A'
		ORDER BY
			CASE WHEN mcl.class_name = 'sys_global_columns' THEN 0 ELSE 1 END,
			mcl.class_name,
			c.parent_order,
			c.column_name;
		RETURN;
	END
END
GO