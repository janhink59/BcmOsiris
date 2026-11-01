/* =============================================================================
 * Verze: 2026-11-01 17:15
 * Soubor: p_fix_meta_column.sql
 * Procedury: dbo.p_sync_hierarchy_to_meta_class, dbo.p_fix_meta_column
 * Účel: 1. dbo.p_sync_hierarchy_to_meta_class zajišťuje kompletní synchronizaci
 *          koncových hierarchií (is_leaf = 1) z tabulky hierarchy do meta_class
 *          (STI nad hierarchy_item) včetně symetrických 'L' záznamů. Volána jak
 *          z triggeru trg_hierarchy_sync_meta_class, tak při buildu v p_fix_meta_column.
 *       2. dbo.p_fix_meta_column provádí automatizovanou synchronizaci a provazování
 *          dědičnosti metadat (meta_object, meta_class, meta_column) a sjednocení
 *          RAC/SSC sloupců a unikátních filtrovaných indexů.
 *
 * Vazby na okolí:
 * - Volána na konci sestavovací dávky databáze (final_scripts.sql) a z triggeru
 *   trg_hierarchy_sync_meta_class (table_hierarchy.sql).
 * - Čte systémový pohled v_syscolumns (z HinkMSSQLLibrary.sql) a synchronizuje
 *   záznamy v tabulkách meta_object, meta_class a meta_column.
 * - Využívá deterministickou hashovací funkci dbo.f_generate_original.
 *
 * Změny:
 * - 2026-11-01 17:15: Opraven první parametr při výpočtu @cls_meta_column
 *   na 'meta_class' (místo 'meta_column') a odstraněn zdvojený UPDATE pro is_leaf
 *   u třídy hierarchy.
 * - 2026-11-01 11:45: Vyčleněna sdílená procedura dbo.p_sync_hierarchy_to_meta_class.
 *   Opraveno vynucení is_html = 1 pro 5 popisných sloupců v sys_global_columns.
 * ============================================================================= */

EXECUTE dropni 'p_fix_meta_column', 'P';
EXECUTE dropni 'p_sync_hierarchy_to_meta_class', 'P';
GO

/* =============================================================================
 * Procedura: dbo.p_sync_hierarchy_to_meta_class
 * Účel: Promítne koncové hierarchie (is_leaf = 1) z tabulky hierarchy do tabulky
 *       meta_class (jako STI třídy nad úložnou tabulkou hierarchy_item) včetně
 *       symetrických jazykových 'L' záznamů. Složky (is_leaf = 0) a smazané
 *       hierarchie v meta_class zneplatní (removed = 1).
 * ============================================================================= */
CREATE PROCEDURE dbo.p_sync_hierarchy_to_meta_class
	@fix_childless_folders bit = 0                                             -- 1 = Při buildu opraví bezdětné hierarchie s is_leaf = 0 na 1
AS
BEGIN
	SET NOCOUNT ON;

	IF OBJECT_ID('hierarchy', 'U') IS NULL OR OBJECT_ID('meta_class', 'U') IS NULL OR OBJECT_ID('meta_object', 'U') IS NULL OR OBJECT_ID('f_generate_original', 'FN') IS NULL
		RETURN;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @stg_hier_item uuid = dbo.f_generate_original('meta_object', @sys_owner, 'T', 'hierarchy_item');
	DECLARE @cls_hier_item uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'hierarchy_item', '');

	IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @stg_hier_item AND object_owner = 0x00 AND record_type = 'A')
		RETURN;

	-- 1. Při buildu opravíme dříve založené bezdětné hierarchie, které měly is_leaf = 0 kvůli nezaškrtnutému checkboxu
	IF @fix_childless_folders = 1
	BEGIN
		UPDATE h
		SET h.is_leaf = 1,
			h.multiple = CASE WHEN h.multiple = 0 AND h.leaf_only = 0 THEN 1 ELSE h.multiple END,
			h.leaf_only = CASE WHEN h.multiple = 0 AND h.leaf_only = 0 THEN 1 ELSE h.leaf_only END
		FROM hierarchy h
		WHERE h.is_leaf = 0
		  AND h.removed = 0
		  AND h.builtin_code <> ''
		  AND NOT EXISTS (
			SELECT 1 FROM hierarchy ch
			WHERE ch.parent_uuid = h.original
			  AND ch.record_type = 'A'
			  AND ch.removed = 0
		  );
	END

	-- 2. Označení tříd v meta_class jako removed = 1, pokud byla hierarchie změněna na složku (is_leaf = 0) nebo smazána
	UPDATE mc
	SET mc.removed = 1,
		mc.date_modified = GETDATE()
	FROM meta_class mc
	LEFT JOIN hierarchy h
		ON h.builtin_code = mc.class_name
		AND h.object_owner = mc.object_owner
		AND h.record_type = 'A'
	WHERE mc.storage_object = @stg_hier_item
	  AND mc.class_name <> 'hierarchy_item'
	  AND mc.removed = 0
	  AND (h.uuid IS NULL OR h.removed = 1 OR h.is_leaf = 0);

	-- 3. Aktualizace a případná obnova existujících 'A' záznamů v meta_class podle koncových hierarchií (is_leaf = 1)
	UPDATE mc
	SET mc.caption = NULLIF(h.caption, ''),
		mc.caption_plural = NULLIF(h.caption, ''),
		mc.description = NULLIF(h.description_text, ''),
		mc.helptext = NULLIF(h.help_text, ''),
		mc.sort_code = LEFT(h.sort_code, 20),
		mc.svg_icon = NULLIF(h.svg_icon, ''),
		mc.inactive = h.inactive,
		mc.removed = h.removed,
		mc.date_modified = h.date_modified,
		mc.who_modified = h.who_modified
	FROM meta_class mc
	JOIN hierarchy h
		ON h.builtin_code = mc.class_name
		AND h.object_owner = mc.object_owner
		AND h.record_type = 'A'
		AND h.is_leaf = 1
	WHERE mc.storage_object = @stg_hier_item
	  AND mc.class_name <> 'hierarchy_item'
	  AND mc.record_type = 'A'
	  AND EXISTS (
		SELECT mc.caption, mc.caption_plural, mc.description, mc.helptext, mc.sort_code, mc.svg_icon, mc.inactive, mc.removed
		EXCEPT
		SELECT NULLIF(h.caption, ''), NULLIF(h.caption, ''), NULLIF(h.description_text, ''), NULLIF(h.help_text, ''), LEFT(h.sort_code, 20), NULLIF(h.svg_icon, ''), h.inactive, h.removed
	  );

	-- 4. Vložení chybějících 'A' záznamů do meta_class pouze pro koncové hierarchie (is_leaf = 1)
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		inactive, removed, class_name, storage_object, ancestor_class, sort_code,
		caption, caption_plural, description, helptext, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.cls_orig, h.object_owner, x.cls_orig, 'A', 'A', h.[language],
		h.inactive, h.removed, h.builtin_code, @stg_hier_item, @cls_hier_item, LEFT(h.sort_code, 20),
		NULLIF(h.caption, ''), NULLIF(h.caption, ''), NULLIF(h.description_text, ''), NULLIF(h.help_text, ''), NULLIF(h.svg_icon, ''),
		h.is_final, h.is_protected,
		h.date_created, h.who_created, h.date_modified, h.who_modified
	FROM hierarchy h
	CROSS APPLY (
		SELECT dbo.f_generate_original('meta_class', CAST(h.object_owner AS varchar(36)), h.builtin_code, '') AS cls_orig
	) x
	WHERE h.record_type = 'A'
	  AND h.is_leaf = 1
	  AND h.removed = 0
	  AND h.builtin_code <> ''
	  AND NOT EXISTS (
		SELECT 1 FROM meta_class mc
		WHERE mc.class_name = h.builtin_code
		  AND mc.object_owner IN (0x00, h.object_owner)
		  AND mc.record_type = 'A'
	  );

	-- 5. Synchronizace existujících jazykových 'L' záznamů v meta_class
	UPDATE mcl
	SET mcl.caption = NULLIF(hl.caption, ''),
		mcl.caption_plural = NULLIF(hl.caption, ''),
		mcl.description = NULLIF(hl.description_text, ''),
		mcl.helptext = NULLIF(hl.help_text, ''),
		mcl.removed = CASE WHEN ha.is_leaf = 1 AND ha.removed = 0 THEN hl.removed ELSE 1 END,
		mcl.date_modified = hl.date_modified,
		mcl.who_modified = hl.who_modified
	FROM meta_class mcl
	JOIN meta_class mca
		ON mca.original = mcl.original
		AND mca.object_owner = mcl.object_owner
		AND mca.record_type = 'A'
		AND mca.storage_object = @stg_hier_item
	JOIN hierarchy ha
		ON ha.builtin_code = mca.class_name
		AND ha.object_owner = mca.object_owner
		AND ha.record_type = 'A'
	JOIN hierarchy hl
		ON hl.original = ha.original
		AND hl.object_owner = mcl.object_owner
		AND hl.record_type = 'L'
		AND hl.[language] = mcl.[language]
	WHERE mcl.record_type = 'L'
	  AND EXISTS (
		SELECT mcl.caption, mcl.caption_plural, mcl.description, mcl.helptext, mcl.removed
		EXCEPT
		SELECT NULLIF(hl.caption, ''), NULLIF(hl.caption, ''), NULLIF(hl.description_text, ''), NULLIF(hl.help_text, ''), CASE WHEN ha.is_leaf = 1 AND ha.removed = 0 THEN hl.removed ELSE CAST(1 AS bit) END
	  );

	-- 6. Vložení chybějících symetrických 'L' záznamů do meta_class pro koncové hierarchie
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		inactive, removed, class_name, storage_object, ancestor_class, sort_code,
		caption, caption_plural, description, helptext, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), hl.object_owner, mca.original, 'L', 'A', hl.[language],
		mca.inactive, hl.removed, mca.class_name, @stg_hier_item, @cls_hier_item, mca.sort_code,
		NULLIF(hl.caption, ''), NULLIF(hl.caption, ''), NULLIF(hl.description_text, ''), NULLIF(hl.help_text, ''), mca.svg_icon,
		mca.is_final, mca.is_protected,
		hl.date_created, hl.who_created, hl.date_modified, hl.who_modified
	FROM hierarchy hl
	JOIN hierarchy ha
		ON ha.original = hl.original
		AND ha.object_owner = hl.object_owner
		AND ha.record_type = 'A'
		AND ha.is_leaf = 1
		AND ha.removed = 0
	JOIN meta_class mca
		ON mca.class_name = ha.builtin_code
		AND mca.object_owner = ha.object_owner
		AND mca.record_type = 'A'
		AND mca.storage_object = @stg_hier_item
		AND mca.removed = 0
	WHERE hl.record_type = 'L'
	  AND hl.removed = 0
	  AND NOT EXISTS (
		SELECT 1 FROM meta_class ex
		WHERE ex.original = mca.original
		  AND ex.object_owner = hl.object_owner
		  AND ex.record_type = 'L'
		  AND ex.[language] = hl.[language]
	  );
END
GO

/* =============================================================================
 * Procedura: dbo.p_fix_meta_column
 * ============================================================================= */
CREATE PROCEDURE dbo.p_fix_meta_column
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @batch_time datetime = GETDATE();

	-- -------------------------------------------------------------------------
	-- PŘÍPRAVA RAC/SSC STRUKTUR: Zajištění sloupců a standardních RAC/SSC indexů
	-- -------------------------------------------------------------------------
	DECLARE @rac_tab VARCHAR(128);
	DECLARE @idx_active VARCHAR(200), @idx_lang VARCHAR(200), @idx_draft VARCHAR(200);

	DECLARE cur_rac CURSOR LOCAL FAST_FORWARD FOR
		SELECT c_uuid.tabname
		FROM v_syscolumns c_uuid
		JOIN v_syscolumns c_owner ON c_owner.tabname = c_uuid.tabname AND c_owner.colname = 'object_owner'
		JOIN v_syscolumns c_orig ON c_orig.tabname = c_uuid.tabname AND c_orig.colname = 'original'
		JOIN v_syscolumns c_rectype ON c_rectype.tabname = c_uuid.tabname AND c_rectype.colname = 'record_type'
		JOIN v_syscolumns c_lang ON c_lang.tabname = c_uuid.tabname AND c_lang.colname = 'language'
		WHERE c_uuid.colname = 'uuid'
		  AND c_uuid.object_type = 'U'
		  AND c_uuid.tabname NOT LIKE '%$';

	OPEN cur_rac;
	FETCH NEXT FROM cur_rac INTO @rac_tab;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC p_create_missing_column @rac_tab, 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
		EXEC p_create_missing_column @rac_tab, 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column @rac_tab, 'import_origin', 'varchar(255) NULL';

		IF @rac_tab NOT IN ('link', 'user_organization_access')
		BEGIN
			SET @idx_active = 'uq_' + @rac_tab + '_active';
			EXEC sp_create_index
				@tname = @rac_tab,
				@iname = @idx_active,
				@colnames = 'original, object_owner',
				@uni = 'UNIQUE',
				@options = 'WHERE record_type = ''A'' AND removed = 0';

			SET @idx_lang = 'uq_' + @rac_tab + '_language';
			EXEC sp_create_index
				@tname = @rac_tab,
				@iname = @idx_lang,
				@colnames = 'original, object_owner, language',
				@uni = 'UNIQUE',
				@options = 'WHERE record_type = ''L'' AND removed = 0';
		END

		SET @idx_draft = 'uq_' + @rac_tab + '_draft';
		EXEC sp_create_index
			@tname = @rac_tab,
			@iname = @idx_draft,
			@colnames = 'original, object_owner, language, draft_author',
			@uni = 'UNIQUE',
			@options = 'WHERE record_type = ''D'' AND removed = 0';

		FETCH NEXT FROM cur_rac INTO @rac_tab;
	END

	CLOSE cur_rac;
	DEALLOCATE cur_rac;

	-- -------------------------------------------------------------------------
	-- CLEANUP: Odstranění vadných dat z předchozích běhů
	-- -------------------------------------------------------------------------
	DELETE FROM meta_column WHERE column_name LIKE '@%';

	DELETE mc
	FROM meta_column mc
	JOIN meta_class mcl ON mcl.original = mc.parent_class AND mcl.object_owner = 0x00
	WHERE mc.object_owner = 0x00 AND mcl.class_name LIKE '%$';

	DELETE FROM meta_class WHERE object_owner = 0x00 AND class_name LIKE '%$';
	DELETE FROM meta_object WHERE object_owner = 0x00 AND builtin_code LIKE '%$';
	DELETE FROM meta_column WHERE object_owner = 0x00 AND column_name IN ('iconname', 'svg_code', 'svg_name');

	WITH cte AS (
		SELECT ROW_NUMBER() OVER(PARTITION BY builtin_code, object_type, object_owner, record_type ORDER BY removed ASC, date_created ASC) as rn
		FROM meta_object WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM cte WHERE rn > 1;

	WITH cte AS (
		SELECT ROW_NUMBER() OVER(PARTITION BY class_name, object_owner, record_type ORDER BY removed ASC, date_created ASC) as rn
		FROM meta_class WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM cte WHERE rn > 1;

	WITH cte AS (
		SELECT ROW_NUMBER() OVER(PARTITION BY parent_class, column_name, object_owner, record_type ORDER BY removed ASC, date_created ASC) as rn
		FROM meta_column WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM cte WHERE rn > 1;

	-- -------------------------------------------------------------------------
	-- 0. VÝPOČET VLASTNOSTÍ SLOUPCŮ Z v_syscolumns A MÓDUSU PRO GLOBÁLNÍ SLOVNÍK
	-- -------------------------------------------------------------------------
	IF OBJECT_ID('tempdb..#syscol_attr') IS NOT NULL DROP TABLE #syscol_attr;
	IF OBJECT_ID('tempdb..#global_attr') IS NOT NULL DROP TABLE #global_attr;

	SELECT 
		tabname COLLATE DATABASE_DEFAULT AS tabname,
		object_type COLLATE DATABASE_DEFAULT AS object_type,
		CASE WHEN object_type = 'U' THEN 'T' WHEN object_type = 'V' THEN 'V' ELSE 'F' END AS meta_obj_type,
		colid,
		colname COLLATE DATABASE_DEFAULT AS colname,
		CASE 
			WHEN typename IN ('bit') THEN 'checkbox'
			WHEN typename IN ('date', 'datetime', 'datetime2', 'smalldatetime') THEN 'date'
			WHEN typename IN ('int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money') THEN 'number'
			WHEN typename IN ('varchar', 'nvarchar', 'text', 'ntext') AND prec = -1 THEN 'textarea'
			ELSE 'text'
		END AS calc_input_type,
		CASE 
			WHEN typename IN ('varchar', 'nvarchar', 'char', 'nchar') AND prec > 0 THEN prec
			ELSE 0 
		END AS calc_max_length,
		ISNULL(iscomputed, 0) AS calc_is_computed,
		CASE 
			WHEN typename = 'bit' THEN 'auto'
			WHEN typename = 'date' THEN '120px'
			WHEN typename = 'smalldatetime' THEN '150px'
			WHEN typename IN ('datetime', 'datetime2') THEN '180px'
			WHEN typename IN ('int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money') THEN '120px'
			ELSE '100%'
		END AS calc_input_width
	INTO #syscol_attr
	FROM v_syscolumns
	WHERE colname NOT LIKE '@%'
	  AND tabname NOT LIKE '%$';

	WITH ranked_attributes AS (
		SELECT 
			colname, calc_input_type, calc_max_length, calc_is_computed, calc_input_width,
			ROW_NUMBER() OVER(PARTITION BY colname ORDER BY COUNT(*) DESC) AS rn
		FROM #syscol_attr
		GROUP BY colname, calc_input_type, calc_max_length, calc_is_computed, calc_input_width
	)
	SELECT colname, calc_input_type, calc_max_length, calc_is_computed, calc_input_width
	INTO #global_attr
	FROM ranked_attributes 
	WHERE rn = 1;

	-- -------------------------------------------------------------------------
	-- 1. SYNCHRONIZACE FYZICKÝCH OBJEKTŮ (T, V, F) V TABULCE meta_object
	-- -------------------------------------------------------------------------
	UPDATE mo
	SET mo.removed = 0,
		mo.date_modified = @batch_time
	FROM meta_object mo
	WHERE mo.object_owner = 0x00
	  AND mo.object_type IN ('T', 'V', 'F')
	  AND mo.removed = 1
	  AND EXISTS (
		SELECT 1 FROM #syscol_attr s
		WHERE s.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		  AND s.meta_obj_type = mo.object_type COLLATE DATABASE_DEFAULT
	  );

	UPDATE mo
	SET mo.removed = 1,
		mo.date_modified = @batch_time
	FROM meta_object mo
	WHERE mo.object_owner = 0x00
	  AND mo.object_type IN ('T', 'V', 'F')
	  AND mo.removed = 0
	  AND NOT EXISTS (
		SELECT 1 FROM #syscol_attr s
		WHERE s.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		  AND s.meta_obj_type = mo.object_type COLLATE DATABASE_DEFAULT
	  );

	INSERT INTO meta_object (
		uuid, object_owner, original, record_type, approval_status,
		object_type, builtin_code, module, date_created, date_modified
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		obj.meta_obj_type, obj.tabname, '', @batch_time, @batch_time
	FROM (
		SELECT DISTINCT tabname, meta_obj_type
		FROM #syscol_attr
	) obj
	CROSS APPLY (SELECT dbo.f_generate_original('meta_object', @sys_owner, obj.meta_obj_type, obj.tabname) AS orig_uuid) x
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_object mo
		WHERE mo.original = x.orig_uuid
		  AND mo.record_type = 'A'
		  AND mo.object_owner = 0x00
	);

	-- -------------------------------------------------------------------------
	-- 2. SYNCHRONIZACE LOGICKÝCH TŘÍD V meta_class
	-- -------------------------------------------------------------------------
	UPDATE mc
	SET mc.removed = 0,
		mc.date_modified = @batch_time
	FROM meta_class mc
	JOIN meta_object mo
		ON mo.original = mc.storage_object
		AND mo.object_owner = 0x00
		AND mo.record_type = 'A'
		AND mo.removed = 0
		AND mo.object_type IN ('T', 'V', 'F')
	WHERE mc.object_owner = 0x00
	  AND mc.removed = 1
	  AND mc.class_name = mo.builtin_code;

	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status,
		class_name, storage_object, ancestor_class,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified,
		caption, caption_plural
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		mo.builtin_code, mo.original, NULL,
		1, 0,
		@batch_time, @sys_owner, @batch_time, @sys_owner,
		UPPER(SUBSTRING(mo.builtin_code, 1, 1)) + SUBSTRING(mo.builtin_code, 2, LEN(mo.builtin_code)),
		UPPER(SUBSTRING(mo.builtin_code, 1, 1)) + SUBSTRING(mo.builtin_code, 2, LEN(mo.builtin_code))
	FROM meta_object mo
	CROSS APPLY (
		SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), mo.builtin_code, '') AS orig_uuid
	) x
	WHERE mo.object_owner = 0x00 
		AND mo.record_type = 'A' 
		AND mo.removed = 0
		AND mo.object_type IN ('T', 'V', 'F')
		AND NOT EXISTS (
			SELECT 1 FROM meta_class mc 
			WHERE mc.original = x.orig_uuid
				AND mc.object_owner = 0x00 
				AND mc.record_type = 'A'
		);

	-- 2d. Promítnutí registrovaných koncových hierarchií (is_leaf = 1) z tabulky hierarchy do meta_class
	EXEC dbo.p_sync_hierarchy_to_meta_class @fix_childless_folders = 1;

	-- -------------------------------------------------------------------------
	-- 3. PŘÍPRAVA GLOBÁLNÍHO SLOVNÍKU (Objekt typu C a globální třída)
	-- -------------------------------------------------------------------------
	DECLARE @c_object uniqueidentifier = dbo.f_generate_original('meta_object', @sys_owner, 'C', 'sys_global_columns');
	DECLARE @c_class uniqueidentifier = dbo.f_generate_original('meta_class', @sys_owner, 'sys_global_columns', '');

	IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @c_object AND object_owner = 0x00 AND record_type = 'A')
	BEGIN
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status,
			object_type, builtin_code, module, date_created, date_modified
		) VALUES (
			@c_object, 0x00, @c_object, 'A', 'A', 'C', 'sys_global_columns', '', @batch_time, @batch_time
		);
	END
	ELSE
	BEGIN
		UPDATE meta_object
		SET removed = 0, date_modified = @batch_time
		WHERE original = @c_object AND object_owner = 0x00 AND removed = 1;
	END

	IF NOT EXISTS (SELECT 1 FROM meta_class WHERE original = @c_class AND object_owner = 0x00 AND record_type = 'A')
	BEGIN
		INSERT INTO meta_class (
			uuid, object_owner, original, record_type, approval_status,
			class_name, storage_object, is_final, is_protected, caption,
			date_created, date_modified
		) VALUES (
			@c_class, 0x00, @c_class, 'A', 'A',
			'sys_global_columns', @c_object, 1, 1, 'Globální definice sloupců',
			@batch_time, @batch_time
		);
	END
	ELSE
	BEGIN
		UPDATE meta_class
		SET removed = 0, date_modified = @batch_time
		WHERE original = @c_class AND object_owner = 0x00 AND removed = 1;
	END

	UPDATE mc
	SET mc.removed = 1,
		mc.date_modified = @batch_time
	FROM meta_class mc
	WHERE mc.object_owner = 0x00
	  AND mc.removed = 0
	  AND mc.original <> @c_class
	  AND NOT EXISTS (
		SELECT 1 FROM meta_object mo
		WHERE mo.original = mc.storage_object
		  AND mo.object_owner = 0x00
		  AND mo.record_type = 'A'
		  AND mo.removed = 0
	  );

	UPDATE mc
	SET mc.removed = 0,
		mc.date_modified = @batch_time
	FROM meta_column mc
	WHERE mc.object_owner = 0x00
	  AND mc.parent_class = @c_class
	  AND mc.removed = 1
	  AND EXISTS (
		SELECT 1 FROM #global_attr ga
		WHERE ga.colname = mc.column_name COLLATE DATABASE_DEFAULT
	  );

	UPDATE mc
	SET mc.removed = 1,
		mc.date_modified = @batch_time
	FROM meta_column mc
	WHERE mc.object_owner = 0x00
	  AND mc.parent_class = @c_class
	  AND mc.removed = 0
	  AND NOT EXISTS (
		SELECT 1 FROM #global_attr ga
		WHERE ga.colname = mc.column_name COLLATE DATABASE_DEFAULT
	  );

	INSERT INTO meta_column (
		uuid, object_owner, original, record_type, approval_status,
		parent_class, parent_order, sort_code, column_name, 
		caption, caption_plural, description, label, header, helptext, placeholder,
		input_type, input_width, input_rows, max_length, css_class,
		translate, history, is_html, is_mandatory, is_url, is_computed, 
		show_empty, hidden, customizable,
		is_final, is_protected, ancestor,
		date_created, date_modified
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		@c_class, 
		ROW_NUMBER() OVER(ORDER BY ga.colname), 
		'C' + RIGHT('000' + CAST(ROW_NUMBER() OVER(ORDER BY ga.colname) * 10 AS varchar), 3),
		ga.colname,
		ga.colname, ga.colname, 'Globální definice pro ' + ga.colname, ga.colname, ga.colname, 
		'Nápověda pro ' + ga.colname, 'Zadejte ' + ga.colname,
		ga.calc_input_type, ga.calc_input_width, 0, ga.calc_max_length, '',
		0, 0, 0, 0, 0, ga.calc_is_computed, 1, 0, 1,
		1, 0, NULL,
		@batch_time, @batch_time
	FROM #global_attr ga
	CROSS APPLY (SELECT dbo.f_generate_original('meta_column', @sys_owner, CAST(@c_class AS varchar(36)), ga.colname) AS orig_uuid) x
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_column mc 
		WHERE mc.original = x.orig_uuid 
		  AND mc.record_type = 'A'
		  AND mc.object_owner = 0x00
	);

	-- -------------------------------------------------------------------------
	-- 4. SYNCHRONIZACE LOKÁLNÍCH SLOUPCŮ (Pro bázové logické třídy ancestor_class IS NULL)
	-- -------------------------------------------------------------------------
	DELETE mc
	FROM meta_column mc
	JOIN meta_class mcl
		ON mcl.original = mc.parent_class
		AND mcl.object_owner = 0x00
	WHERE mc.object_owner = 0x00
	  AND mc.who_modified = 0x00
	  AND mcl.ancestor_class IS NOT NULL
	  AND mcl.class_name <> 'hierarchy_item';

	UPDATE mc
	SET mc.removed = 0,
		mc.date_modified = @batch_time
	FROM meta_column mc
	JOIN meta_class mcl
		ON mcl.original = mc.parent_class
		AND mcl.object_owner = 0x00
		AND mcl.record_type = 'A'
		AND mcl.removed = 0
		AND mcl.ancestor_class IS NULL
	JOIN meta_object mo
		ON mo.original = mcl.storage_object
		AND mo.object_owner = 0x00
		AND mo.record_type = 'A'
		AND mo.removed = 0
		AND mo.object_type IN ('T', 'V', 'F')
	JOIN #syscol_attr la
		ON la.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND la.colname = mc.column_name COLLATE DATABASE_DEFAULT
	WHERE mc.object_owner = 0x00
	  AND mc.parent_class <> @c_class
	  AND mc.removed = 1;

	UPDATE mc
	SET mc.removed = 1,
		mc.date_modified = @batch_time
	FROM meta_column mc
	LEFT JOIN meta_class mcl
		ON mcl.original = mc.parent_class
		AND mcl.object_owner = 0x00
		AND mcl.record_type = 'A'
		AND mcl.removed = 0
	LEFT JOIN meta_object mo
		ON mo.original = mcl.storage_object
		AND mo.object_owner = 0x00
		AND mo.record_type = 'A'
		AND mo.removed = 0
	WHERE mc.object_owner = 0x00
	  AND mc.parent_class <> @c_class
	  AND mc.removed = 0
	  AND (
		mcl.original IS NULL
		OR mo.original IS NULL
		OR (
			mo.object_type IN ('T', 'V', 'F')
			AND NOT EXISTS (
				SELECT 1 FROM #syscol_attr la
				WHERE la.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
				  AND la.colname = mc.column_name COLLATE DATABASE_DEFAULT
			)
		)
	  );

	INSERT INTO meta_column (
		uuid, object_owner, original, record_type, approval_status,
		parent_class, parent_order, column_name, 
		caption, caption_plural, description, label, header, helptext, placeholder,
		input_type, input_width, input_rows, max_length, css_class,
		translate, history, is_html, is_mandatory, is_url, is_computed, 
		show_empty, hidden, customizable,
		is_final, is_protected, ancestor,
		date_created, date_modified
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		mcl.original, la.colid, la.colname,
		NULL, NULL, NULL, NULL, NULL, NULL, NULL,
		CASE WHEN la.calc_input_type = ga.calc_input_type THEN NULL ELSE la.calc_input_type END,
		CASE WHEN la.calc_input_width = ga.calc_input_width THEN NULL ELSE la.calc_input_width END, 
		NULL, 
		CASE WHEN la.calc_max_length = ga.calc_max_length THEN NULL ELSE la.calc_max_length END,
		NULL,
		NULL, NULL, NULL, NULL, NULL, 
		CASE WHEN la.calc_is_computed = ga.calc_is_computed THEN NULL ELSE la.calc_is_computed END, 
		NULL, NULL, NULL,
		1, 0, gc.original,
		@batch_time, @batch_time
	FROM #syscol_attr la
	JOIN meta_object mo 
		ON mo.builtin_code = la.tabname
		AND mo.object_type = la.meta_obj_type
		AND mo.record_type = 'A'
		AND mo.object_owner = 0x00
		AND mo.removed = 0
	JOIN meta_class mcl 
		ON mcl.storage_object = mo.original
		AND mcl.record_type = 'A'
		AND mcl.object_owner = 0x00
		AND mcl.removed = 0
		AND mcl.ancestor_class IS NULL
	JOIN meta_column gc
		ON gc.parent_class = @c_class
		AND gc.column_name = la.colname
		AND gc.record_type = 'A'
		AND gc.object_owner = 0x00
		AND gc.removed = 0
	JOIN #global_attr ga
		ON ga.colname = gc.column_name COLLATE DATABASE_DEFAULT
	CROSS APPLY (SELECT dbo.f_generate_original('meta_column', @sys_owner, CAST(mcl.original AS varchar(36)), la.colname) AS orig_uuid) x
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_column mc 
		WHERE mc.original = x.orig_uuid 
		  AND mc.record_type = 'A'
		  AND mc.object_owner = 0x00
	);

	-- -------------------------------------------------------------------------
	-- 5. KOREKCE EXISTUJÍCÍCH SLOUPCŮ BEZ PŘEDKA A GLOBÁLNÍ NASTAVENÍ
	-- -------------------------------------------------------------------------
	UPDATE mc
	SET ancestor = gc.original,
		caption = NULL, caption_plural = NULL, description = NULL, label = NULL, 
		header = NULL, helptext = NULL, placeholder = NULL, 
		input_rows = NULL, css_class = NULL, translate = NULL, 
		history = NULL, is_html = NULL, is_mandatory = NULL, is_url = NULL, 
		show_empty = NULL, hidden = NULL, customizable = NULL,
		input_type = CASE WHEN la.calc_input_type = ga.calc_input_type THEN NULL ELSE la.calc_input_type END,
		input_width = CASE WHEN la.calc_input_width = ga.calc_input_width THEN NULL ELSE la.calc_input_width END,
		max_length = CASE WHEN la.calc_max_length = ga.calc_max_length THEN NULL ELSE la.calc_max_length END,
		is_computed = CASE WHEN la.calc_is_computed = ga.calc_is_computed THEN NULL ELSE la.calc_is_computed END
	FROM meta_column mc
	JOIN meta_class mcl 
		ON mcl.original = mc.parent_class 
		AND mcl.record_type = 'A' 
		AND mcl.object_owner = 0x00
		AND mcl.removed = 0
	JOIN meta_object mo 
		ON mo.original = mcl.storage_object 
		AND mo.object_type IN ('T', 'V', 'F') 
		AND mo.record_type = 'A' 
		AND mo.object_owner = 0x00
		AND mo.removed = 0
	JOIN #syscol_attr la
		ON la.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND la.colname = mc.column_name COLLATE DATABASE_DEFAULT
	JOIN meta_column gc 
		ON gc.parent_class = @c_class 
		AND gc.column_name = mc.column_name 
		AND gc.record_type = 'A' 
		AND gc.object_owner = 0x00
		AND gc.removed = 0
	JOIN #global_attr ga
		ON ga.colname = gc.column_name COLLATE DATABASE_DEFAULT
	WHERE mc.record_type = 'A' 
	  AND mc.object_owner = 0x00 
	  AND mc.removed = 0
	  AND mc.ancestor IS NULL;

	CREATE TABLE #list_order(column_name varchar(80) COLLATE DATABASE_DEFAULT, list_order int IDENTITY PRIMARY KEY);
	INSERT INTO #list_order(column_name)
	VALUES('source_code'), ('builtin_code'), ('column_name'), ('class_name'), ('caption'), ('shortname'), ('title');

	UPDATE meta_column
	SET list_order = lc.list_order
	FROM meta_column
	LEFT OUTER JOIN #list_order lc ON lc.column_name = meta_column.column_name
	WHERE parent_class = @c_class;

	UPDATE meta_column
	SET translate = 1
	WHERE parent_class = @c_class
	  AND column_name IN (
		'title', 'caption', 'caption_plural', 'label', 'header', 
		'shortname', 'description', 'description_text', 'helptext', 'help_text',
		'caption_forward', 'caption_backward', 'note'
	  );

	UPDATE meta_column
	SET is_mandatory = 1
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name IN (
		'builtin_code', 'class_name', 'column_name', 'source_code',
		'codetable_name', 'value_code', 'link_code', 'hierarchy',
		'caption', 'login_name', 'link_def', 'from_object', 'to_object'
	  )
	  AND ISNULL(is_mandatory, 0) = 0;

	IF OBJECT_ID('meta_original_keys') IS NOT NULL
	BEGIN
		UPDATE mc
		SET mc.is_mandatory = 1
		FROM meta_column mc
		JOIN meta_class mcl
			ON mcl.original = mc.parent_class
			AND mcl.object_owner = 0x00
			AND mcl.record_type = 'A'
			AND mcl.removed = 0
		JOIN meta_object mo
			ON mo.original = mcl.storage_object
			AND mo.object_owner = 0x00
			AND mo.record_type = 'A'
			AND mo.removed = 0
		JOIN meta_original_keys mok
			ON mok.table_name = mo.builtin_code
			AND (mok.key1_column = mc.column_name OR mok.key2_column = mc.column_name)
		WHERE mc.object_owner = 0x00
		  AND mc.record_type = 'A'
		  AND ISNULL(mc.is_mandatory, 0) = 0;
	END

	-- Vynucení podpory formátovaného textu (Markdown / HTML: is_html = 1)
	-- pro 5 víceřádkových popisných sloupců v globálním slovníku (i pokud byly přepsány starším importem na 0)
	UPDATE meta_column
	SET is_html = 1
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name IN ('description', 'description_text', 'helptext', 'help_text', 'note')
	  AND ISNULL(is_html, 0) = 0;

	-- U lokálních sloupců těchto 5 názvů vyčistíme is_html = 0 na NULL, aby dědily is_html = 1 z globálního slovníku
	UPDATE meta_column
	SET is_html = NULL
	WHERE parent_class <> @c_class
	  AND object_owner = 0x00
	  AND ancestor IS NOT NULL
	  AND column_name IN ('description', 'description_text', 'helptext', 'help_text', 'note')
	  AND is_html = 0;

	UPDATE meta_column
	SET caption = 'Dny v koši (days_in_trash)',
		label = 'Dny v koši',
		header = 'Dny v koši',
		helptext = 'Počet dnů uchování zrušených záznamů (removed = 1) v koši před automatickým smazáním (0 = nikdy).'
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name = 'days_in_trash'
	  AND (who_modified = 0x00 OR caption = 'days_in_trash');

	UPDATE meta_column
	SET caption = 'Koncový uzel (is_leaf)',
		label = 'Koncový uzel (list)',
		header = 'List',
		helptext = 'Zaškrtněte u koncové položky (listu). Odškrtněte u vnitřního uzlu (složky), pod který se budou vkládat podřízené položky.'
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name = 'is_leaf'
	  AND (who_modified = 0x00 OR caption = 'is_leaf');

	UPDATE meta_column
	SET caption = 'Vícenásobné přiřazení (multiple)',
		label = 'Povolit více položek (multiple)',
		header = 'Více položek',
		helptext = 'Určuje, zda cílový záznam může mít navázáno více položek z této hierarchie současně.'
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name = 'multiple'
	  AND (who_modified = 0x00 OR caption = 'multiple');

	UPDATE meta_column
	SET caption = 'Pouze koncové uzly (leaf_only)',
		label = 'Vazby jen na koncové uzly (leaf_only)',
		header = 'Jen listy',
		helptext = 'Určuje, zda lze cílové záznamy navazovat výhradně na koncové uzly (is_leaf = 1) této hierarchie.'
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name = 'leaf_only'
	  AND (who_modified = 0x00 OR caption = 'leaf_only');

	UPDATE meta_column
	SET caption = 'Hierarchie (hierarchy)',
		label = 'Nadřazená hierarchie',
		header = 'Hierarchie',
		helptext = 'Odkaz na definici sekundární hierarchie nebo stromu štítků (tagů) v tabulce hierarchy.'
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name = 'hierarchy'
	  AND (who_modified = 0x00 OR caption = 'hierarchy');

	UPDATE meta_column
	SET hidden = 1
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND record_type = 'A'
	  AND column_name IN (
		'uuid', 'object_owner', 'original', 'record_type', 'approval_status',
		'draft_author', 'approval_note', 'import_origin', 'removed',
		'date_created', 'who_created', 'date_modified', 'who_modified',
		'logo_data', 'logo_filename', 'logo_mime_type',
		'ancestor_link', 'is_derived'
	  );

	UPDATE meta_column
	SET hidden = 0,
		is_protected = 1
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND record_type = 'A'
	  AND column_name = 'svg_icon';

	-- -------------------------------------------------------------------------
	-- 5b. AUTOMATICKÉ NAPOJENÍ VAZEB referenced_class V GLOBÁLNÍM SLOVNÍKU A STROMECH
	-- -------------------------------------------------------------------------
	DECLARE @cls_meta_class uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'meta_class', '');
	DECLARE @cls_meta_object uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'meta_object', '');
	DECLARE @cls_meta_column uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'meta_column', '');
	DECLARE @cls_hierarchy uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'hierarchy', '');

	-- Specifický popisek sloupce is_leaf u třídy hierarchy (odlišení samostatné hierarchie od složky registru)
	UPDATE meta_column
	SET caption = 'Samostatná hierarchie / sada štítků (is_leaf)',
		label = 'Samostatná hierarchie (is_leaf)',
		header = 'Hierarchie',
		helptext = 'Zaškrtněte (1) u koncové definice hierarchie nebo sady štítků, do které budete vkládat položky. Odškrtněte (0) pouze u nadřazené organizační složky v tomto registru.'
	WHERE parent_class = @cls_hierarchy
	  AND object_owner = 0x00
	  AND column_name = 'is_leaf'
	  AND who_modified = 0x00;

	UPDATE meta_column
	SET referenced_class = @cls_meta_class
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND record_type = 'A'
	  AND column_name IN ('parent_class', 'ancestor_class', 'referenced_class', 'from_class', 'to_class')
	  AND referenced_class IS NULL;

	UPDATE meta_column
	SET referenced_class = @cls_meta_object
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND record_type = 'A'
	  AND column_name IN ('storage_object', 'target_object')
	  AND referenced_class IS NULL;

	UPDATE meta_column
	SET referenced_class = @cls_meta_column
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND record_type = 'A'
	  AND column_name = 'ancestor'
	  AND referenced_class IS NULL;

	IF EXISTS (SELECT 1 FROM meta_class WHERE original = @cls_hierarchy AND object_owner = 0x00 AND record_type = 'A' AND removed = 0)
	BEGIN
		UPDATE meta_column
		SET referenced_class = @cls_hierarchy
		WHERE parent_class = @c_class
		  AND object_owner = 0x00
		  AND record_type = 'A'
		  AND column_name = 'hierarchy'
		  AND referenced_class IS NULL;
	END

	UPDATE meta_column
	SET referenced_class = parent_class
	WHERE parent_class <> @c_class
	  AND object_owner = 0x00
	  AND record_type = 'A'
	  AND column_name = 'parent_uuid'
	  AND referenced_class IS NULL;

	-- -------------------------------------------------------------------------
	-- 6. OPRAVA HISTORICKÝCH DAT: Doplnění chybějícího caption u existujících tříd
	-- -------------------------------------------------------------------------
	UPDATE meta_class
	SET caption = UPPER(SUBSTRING(class_name, 1, 1)) + SUBSTRING(class_name, 2, LEN(class_name)),
		caption_plural = UPPER(SUBSTRING(class_name, 1, 1)) + SUBSTRING(class_name, 2, LEN(class_name))
	WHERE caption IS NULL 
	  AND record_type = 'A' 
	  AND object_owner = 0x00;
END
GO