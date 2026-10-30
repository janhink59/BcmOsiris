IF OBJECT_ID('p_fix_meta_column', 'P') IS NOT NULL DROP PROCEDURE p_fix_meta_column;
GO

/* =============================================================================
 * Procedura: p_fix_meta_column
 * Verze: 2026-10-30 23:35
 * Soubor: p_fix_meta_column.sql
 * Účel: Plně automatizovaná synchronizace a provazování dědičnosti metadat.
 *       Plně respektuje STI architekturu – sloupce se vážou výhradně
 *       na logické třídy (meta_class), včetně odvozených tříd z tabulky hierarchy.
 *
 * Vazby na okolí:
 * - Volána na konci sestavovací dávky databáze (final_scripts.sql).
 * - Čte systémový pohled v_syscolumns (z HinkMSSQLLibrary.sql) a synchronizuje
 *   systémové záznamy (object_owner = 0x00) v tabulkách meta_object,
 *   meta_class a meta_column.
 * - Využívá deterministickou hashovací funkci dbo.f_generate_original.
 * - Zakládá a udržuje kořenový kontejner dědičnosti vlastností sloupců
 *   'sys_global_columns' (object_type = 'C'), ze kterého čerpá entity_manager.php.
 *
 * Změny:
 * - 2026-10-30 23:35: Doplněna synchronizace registrovaných hierarchií (tabulka
 *   hierarchy) do meta_class, podpora sloupců pro odvozené STI třídy v sekcích
 *   4a/4b/4c, skrytí technických sloupců ancestor_link a is_derived v globálním
 *   slovníku a napojení sloupce hierarchy_item.hierarchy na třídu hierarchy.
 * - 2026-10-29 16:00: V sekci 5b doplněno napojení sloupce preferred_language
 *   na třídu language.
 * - 2026-10-26 13:55: V sekci 5 doplněno výchozí nastavení příznaku is_html = 1
 *   v globálním slovníku (sys_global_columns) pro dlouhé popisné sloupce.
 * ============================================================================= */
CREATE PROCEDURE p_fix_meta_column
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Explicitní definice vlastníka a jednotného času spuštění dávky
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @batch_time datetime = GETDATE();

	-- -------------------------------------------------------------------------
	-- PŘÍPRAVA RAC/SSC STRUKTUR: Zajištění sloupců a indexů pro koncepty ('D')
	-- -------------------------------------------------------------------------
	DECLARE @rac_tab VARCHAR(128);
	DECLARE @idx_name VARCHAR(200);

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

		SET @idx_name = 'uq_' + @rac_tab + '_draft';
		EXEC sp_create_index
			@tname = @rac_tab,
			@iname = @idx_name,
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
	
	-- 1. Odstranění parametrů funkcí (začínajících zavináčem)
	DELETE FROM meta_column WHERE column_name LIKE '@%';

	-- 1b. Odstranění dočasných staging tabulek z Excelu (končících znakem $), pokud v metadatech uvízly
	DELETE mc
	FROM meta_column mc
	JOIN meta_class mcl ON mcl.original = mc.parent_class AND mcl.object_owner = 0x00
	WHERE mc.object_owner = 0x00 AND mcl.class_name LIKE '%$';

	DELETE FROM meta_class WHERE object_owner = 0x00 AND class_name LIKE '%$';
	DELETE FROM meta_object WHERE object_owner = 0x00 AND builtin_code LIKE '%$';

	-- 1c. Odstranění zastaralých názvů sloupců vektorových ikon (sjednoceno na svg_icon)
	DELETE FROM meta_column WHERE object_owner = 0x00 AND column_name IN ('iconname', 'svg_code', 'svg_name');
	
	-- 2. Odstranění duplicit objektů (ponecháme vždy ten nejstarší platný)
	WITH cte AS (
		SELECT ROW_NUMBER() OVER(PARTITION BY builtin_code, object_type, object_owner, record_type ORDER BY removed ASC, date_created ASC) as rn
		FROM meta_object WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM cte WHERE rn > 1;

	-- Odstranění duplicit tříd
	WITH cte AS (
		SELECT ROW_NUMBER() OVER(PARTITION BY class_name, object_owner, record_type ORDER BY removed ASC, date_created ASC) as rn
		FROM meta_class WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM cte WHERE rn > 1;

	-- Odstranění duplicit sloupců
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
	  AND tabname NOT LIKE '%$';                    -- Vyloučení dočasných staging tabulek z Excelu

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
	-- 1a. Obnova dříve zrušených fyzických objektů (removed: 1 -> 0), pokud se v DB znovu objevily
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

	-- 1b. Označení osiřelých fyzických objektů (removed: 0 -> 1), které již v DB neexistují
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

	-- 1c. Vložení zcela nových fyzických objektů (T, V, F)
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
	-- 2. INTEGRACE p_generate_primitive_classes: Synchronizace logických tříd
	-- -------------------------------------------------------------------------
	-- 2a. Obnova dříve zrušených primitivních tříd (removed: 1 -> 0), jejichž fyzický objekt je opět platný
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

	-- 2b. Vložení chybějících primitivních logických tříd pro platné fyzické objekty
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

	-- 2d. Promítnutí registrovaných hierarchií z tabulky hierarchy do meta_class (STI nad hierarchy_item)
	IF OBJECT_ID('hierarchy') IS NOT NULL
	BEGIN
		DECLARE @stg_hier_item uuid = dbo.f_generate_original('meta_object', @sys_owner, 'T', 'hierarchy_item');
		DECLARE @cls_hier_item uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'hierarchy_item', '');

		INSERT INTO meta_class (
			uuid, object_owner, original, record_type, approval_status, [language],
			inactive, removed, class_name, storage_object, ancestor_class, sort_code,
			caption, caption_plural, description, helptext,
			is_final, is_protected,
			date_created, who_created, date_modified, who_modified
		)
		SELECT
			x.cls_orig, h.object_owner, x.cls_orig, 'A', 'A', h.[language],
			h.inactive, h.removed, h.builtin_code, @stg_hier_item, @cls_hier_item, LEFT(h.sort_code, 20),
			NULLIF(h.caption, ''), NULLIF(h.caption, ''), NULLIF(h.description_text, ''), NULLIF(h.help_text, ''),
			h.is_final, h.is_protected,
			h.date_created, h.who_created, h.date_modified, h.who_modified
		FROM hierarchy h
		CROSS APPLY (
			SELECT dbo.f_generate_original('meta_class', CAST(h.object_owner AS varchar(36)), h.builtin_code, '') AS cls_orig
		) x
		WHERE h.record_type = 'A'
		  AND h.builtin_code <> ''
		  AND NOT EXISTS (
			SELECT 1 FROM meta_class mc
			WHERE mc.class_name = h.builtin_code
			  AND mc.object_owner IN (0x00, h.object_owner)
			  AND mc.record_type = 'A'
		  );
	END

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

	-- 2c. Označení osiřelých systémových tříd (removed: 0 -> 1), jejichž úložný objekt neexistuje nebo je zrušený
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

	-- 3b. Obnova dříve zrušených sloupců v globálním slovníku (removed: 1 -> 0), pokud se v DB znovu objevily
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

	-- 3c. Označení osiřelých sloupců v globálním slovníku (removed: 0 -> 1), které se již nevyskytují v žádné tabulce/view/funkci
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

	-- 3d. Plnění unikátních názvů sloupců do globálního slovníku (navázáno na @c_class)
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
	-- 4. SYNCHRONIZACE LOKÁLNÍCH SLOUPCŮ (Vazba na logickou třídu vč. STI potomků)
	-- -------------------------------------------------------------------------
	-- 4a. Obnova dříve zrušených lokálních sloupců (removed: 1 -> 0), pokud jsou třída i fyzický sloupec opět platné
	UPDATE mc
	SET mc.removed = 0,
		mc.date_modified = @batch_time
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
		AND mo.object_type IN ('T', 'V', 'F')
	JOIN #syscol_attr la
		ON la.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND la.colname = mc.column_name COLLATE DATABASE_DEFAULT
	WHERE mc.object_owner = 0x00
	  AND mc.parent_class <> @c_class
	  AND mc.removed = 1;

	-- 4b. Označení osiřelých lokálních sloupců (removed: 0 -> 1), pokud je neplatná jejich třída nebo fyzický sloupec zmizel
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

	-- 4c. Vložení nových lokálních sloupců pro všechny platné logické třídy (primitivní i STI)
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
	-- 5. KOREKCE EXISTUJÍCÍCH SLOUPCŮ BEZ PŘEDKA (Napojení na 'C' a zachování odchylek)
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

	-- Výchozí nastavení hodnoty list_order pro sloupce zobrazované v levém Master panelu
	create table #list_order(column_name varchar(80) collate database_default, list_order int identity primary key)
	insert into #list_order(column_name)
	values('source_code'), ('builtin_code'), ('column_name'), ('class_name'), ('caption'), ('shortname'), ('title')

	update meta_column
		set list_order=lc.list_order
	from meta_column
		left outer join #list_order lc on lc.column_name=meta_column.column_name
	where parent_class=@c_class

	-- Nastavení položky "translate" pro vyjmenované sloupce
	update meta_column
		set translate=1
	where parent_class=@c_class
		and column_name in(
			'title', 'caption', 'caption_plural', 'label', 'header', 
			'shortname', 'description', 'description_text', 'helptext', 'help_text',
			'caption_forward', 'caption_backward', 'note'
		)

	-- Výchozí zapnutí podpory formátovaného textu (Markdown / HTML: is_html = 1)
	-- pro víceřádkové popisné sloupce v globálním slovníku (pokud nebyly ručně změněny)
	UPDATE meta_column
	SET is_html = 1
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND who_modified = 0x00
	  AND column_name IN ('description', 'description_text', 'helptext', 'help_text', 'note');

	-- Výchozí česká lokalizace pro sloupec days_in_trash v globálním slovníku
	UPDATE meta_column
	SET caption = 'Dny v koši (days_in_trash)',
		label = 'Dny v koši',
		header = 'Dny v koši',
		helptext = 'Počet dnů uchování zrušených záznamů (removed = 1) v koši před automatickým smazáním (0 = nikdy).'
	WHERE parent_class = @c_class
	  AND object_owner = 0x00
	  AND column_name = 'days_in_trash'
	  AND (who_modified = 0x00 OR caption = 'days_in_trash');

	-- Skrytí čistě technických RAC/SSC, odvozených a binárních sloupců z automaticky generovaných formulářů
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

	-- Sloupec vektorových ikon (svg_icon) necháme ve formuláři viditelný (hidden = 0) a chráněný (is_protected = 1)
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

	-- Rekurzivní stromová vazba parent_uuid vždy odkazuje na vlastní logickou třídu (např. meta_menu, asset_class, hierarchy)
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