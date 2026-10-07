IF OBJECT_ID('p_fix_meta_column', 'P') IS NOT NULL DROP PROCEDURE p_fix_meta_column;
GO

/* =============================================================================
 * Procedura: p_fix_meta_column
 * Verze: 2026-10-07 14:30
 * Účel: Plně automatizovaná synchronizace a provazování dědičnosti metadat.
 *       Nyní plně respektuje STI architekturu – sloupce se vážou výhradně
 *       na logické třídy (meta_class). Obsahuje i integrovanou logiku
 *       z původní procedury p_generate_primitive_classes.
 * ============================================================================= */
CREATE PROCEDURE p_fix_meta_column
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Explicitní definice vlastníka pro zajištění stejného datového typu jako má T-SQL hash
	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

	-- -------------------------------------------------------------------------
	-- CLEANUP: Odstranění vadných dat z předchozích běhů
	-- -------------------------------------------------------------------------
	
	-- 1. Odstranění parametrů funkcí (začínajících zavináčem)
	DELETE FROM meta_column WHERE column_name LIKE '@%';
	
	-- 2. Odstranění duplicit objektů (ponecháme vždy ten nejstarší platný)
	WITH cte AS (
		SELECT uuid, ROW_NUMBER() OVER(PARTITION BY builtin_code, object_type, object_owner, record_type ORDER BY date_created ASC) as rn
		FROM meta_object WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM meta_object WHERE uuid IN (SELECT uuid FROM cte WHERE rn > 1);

	-- Odstranění duplicit tříd
	WITH cte AS (
		SELECT uuid, ROW_NUMBER() OVER(PARTITION BY class_name, object_owner, record_type ORDER BY date_created ASC) as rn
		FROM meta_class WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM meta_class WHERE uuid IN (SELECT uuid FROM cte WHERE rn > 1);

	-- Odstranění duplicit sloupců
	WITH cte AS (
		SELECT uuid, ROW_NUMBER() OVER(PARTITION BY parent_class, column_name, object_owner, record_type ORDER BY date_created ASC) as rn
		FROM meta_column WHERE object_owner = 0x00 AND record_type = 'A'
	) DELETE FROM meta_column WHERE uuid IN (SELECT uuid FROM cte WHERE rn > 1);

	-- -------------------------------------------------------------------------
	-- 0. VÝPOČET NEJČASTĚJŠÍCH VLASTNOSTÍ (MÓDUS) PRO GLOBÁLNÍ SLOVNÍK
	-- -------------------------------------------------------------------------
	IF OBJECT_ID('tempdb..#global_attr') IS NOT NULL DROP TABLE #global_attr;
	
	WITH column_attributes AS (
		SELECT 
			colname,
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
				WHEN typename IN ('int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money') THEN '100px'
				ELSE '100%'
			END AS calc_input_width
		FROM v_syscolumns
		WHERE colname NOT LIKE '@%'
	),
	ranked_attributes AS (
		SELECT 
			colname, calc_input_type, calc_max_length, calc_is_computed, calc_input_width,
			ROW_NUMBER() OVER(PARTITION BY colname ORDER BY COUNT(*) DESC) AS rn
		FROM column_attributes
		GROUP BY colname, calc_input_type, calc_max_length, calc_is_computed, calc_input_width
	)
	SELECT colname, calc_input_type, calc_max_length, calc_is_computed, calc_input_width
	INTO #global_attr
	FROM ranked_attributes 
	WHERE rn = 1;

	-- -------------------------------------------------------------------------
	-- 1. SYNCHRONIZACE FYZICKÝCH OBJEKTŮ (T, V, F)
	-- -------------------------------------------------------------------------
	INSERT INTO meta_object (
		uuid, object_owner, original, record_type, approval_status,
		object_type, builtin_code, module
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		obj.obj_type, obj.tabname, ''
	FROM (
		SELECT DISTINCT 
			tabname,
			CASE WHEN object_type = 'U' THEN 'T' WHEN object_type = 'V' THEN 'V' ELSE 'F' END AS obj_type
		FROM v_syscolumns
		WHERE colname NOT LIKE '@%'
	) obj
	CROSS APPLY (SELECT dbo.f_generate_original('meta_object', @sys_owner, obj.obj_type, obj.tabname) AS orig_uuid) x
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_object mo
		WHERE mo.original = x.orig_uuid
		  AND mo.record_type = 'A'
		  AND mo.object_owner = 0x00
	);

	-- -------------------------------------------------------------------------
	-- 2. INTEGRACE p_generate_primitive_classes: Vytvoření logických tříd
	-- -------------------------------------------------------------------------
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status,
		class_name, storage_object, ancestor_class,
		is_final, is_protected,
		who_created, who_modified
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		mo.builtin_code, mo.original, NULL,
		1, 0,
		@sys_owner, @sys_owner
	FROM meta_object mo
	CROSS APPLY (
		SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), mo.builtin_code, '') AS orig_uuid
	) x
	WHERE mo.object_owner = 0x00 
		AND mo.record_type = 'A' 
		AND mo.removed = 0
		AND mo.object_type IN ('T', 'V', 'F')                               -- Záměrně uvolněno pro všechny objekty se sloupci (i TVF)
		AND NOT EXISTS (
			SELECT 1 FROM meta_class mc 
			WHERE mc.original = x.orig_uuid
				AND mc.object_owner = 0x00 
				AND mc.record_type = 'A'
		);

	-- -------------------------------------------------------------------------
	-- 3. PŘÍPRAVA GLOBÁLNÍHO SLOVNÍKU (Objekt typu C a globální třída)
	-- -------------------------------------------------------------------------
	DECLARE @c_object uniqueidentifier = dbo.f_generate_original('meta_object', @sys_owner, 'C', 'sys_global_columns');
	DECLARE @c_class uniqueidentifier = dbo.f_generate_original('meta_class', @sys_owner, 'sys_global_columns', '');

	IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @c_object AND object_owner = 0x00 AND record_type = 'A')
	BEGIN
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status,
			object_type, builtin_code, module
		) VALUES (
			@c_object, 0x00, @c_object, 'A', 'A', 'C', 'sys_global_columns', ''
		);
	END

	IF NOT EXISTS (SELECT 1 FROM meta_class WHERE original = @c_class AND object_owner = 0x00 AND record_type = 'A')
	BEGIN
		INSERT INTO meta_class (
			uuid, object_owner, original, record_type, approval_status,
			class_name, storage_object, is_final, is_protected, caption
		) VALUES (
			@c_class, 0x00, @c_class, 'A', 'A',
			'sys_global_columns', @c_object, 1, 1, 'Globální definice sloupců'
		);
	END

	-- Plnění unikátních názvů sloupců do globálního slovníku (navázáno na @c_class)
	INSERT INTO meta_column (
		uuid, object_owner, original, record_type, approval_status,
		parent_class, parent_order, sort_code, column_name, 
		caption, caption_plural, description, label, header, helptext, placeholder,
		input_type, input_width, input_rows, max_length, css_class,
		translate, history, is_html, is_mandatory, is_url, is_computed, 
		show_empty, hidden, customizable,
		is_final, is_protected, ancestor
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
		1, 0, NULL
	FROM #global_attr ga
	CROSS APPLY (SELECT dbo.f_generate_original('meta_column', @sys_owner, CAST(@c_class AS varchar(36)), ga.colname) AS orig_uuid) x
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_column mc 
		WHERE mc.original = x.orig_uuid 
		  AND mc.record_type = 'A'
		  AND mc.object_owner = 0x00
	);

	-- -------------------------------------------------------------------------
	-- 4. SYNCHRONIZACE LOKÁLNÍCH SLOUPCŮ (Vazba na primitivní logickou třídu)
	-- -------------------------------------------------------------------------
	INSERT INTO meta_column (
		uuid, object_owner, original, record_type, approval_status,
		parent_class, parent_order, column_name, 
		caption, caption_plural, description, label, header, helptext, placeholder,
		input_type, input_width, input_rows, max_length, css_class,
		translate, history, is_html, is_mandatory, is_url, is_computed, 
		show_empty, hidden, customizable,
		is_final, is_protected, ancestor
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		mcl.original, c.colid, c.colname,
		NULL, NULL, NULL, NULL, NULL, NULL, NULL,
		
		CASE WHEN la.calc_input_type = ga.calc_input_type THEN NULL ELSE la.calc_input_type END,
		CASE WHEN la.calc_input_width = ga.calc_input_width THEN NULL ELSE la.calc_input_width END, 
		NULL, 
		CASE WHEN la.calc_max_length = ga.calc_max_length THEN NULL ELSE la.calc_max_length END,
		NULL,
		NULL, NULL, NULL, NULL, NULL, 
		CASE WHEN la.calc_is_computed = ga.calc_is_computed THEN NULL ELSE la.calc_is_computed END, 
		NULL, NULL, NULL,
		1, 0, gc.original
	FROM v_syscolumns c
	CROSS APPLY (
		SELECT 
			CASE 
				WHEN c.typename IN ('bit') THEN 'checkbox'
				WHEN c.typename IN ('date', 'datetime', 'datetime2', 'smalldatetime') THEN 'date'
				WHEN c.typename IN ('int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money') THEN 'number'
				WHEN c.typename IN ('varchar', 'nvarchar', 'text', 'ntext') AND c.prec = -1 THEN 'textarea'
				ELSE 'text'
			END AS calc_input_type,
			CASE 
				WHEN c.typename IN ('varchar', 'nvarchar', 'char', 'nchar') AND c.prec > 0 THEN c.prec
				ELSE 0 
			END AS calc_max_length,
			ISNULL(c.iscomputed, 0) AS calc_is_computed,
			CASE 
				WHEN c.typename = 'bit' THEN 'auto'
				WHEN c.typename = 'date' THEN '120px'
				WHEN c.typename = 'smalldatetime' THEN '150px'
				WHEN c.typename IN ('datetime', 'datetime2') THEN '180px'
				WHEN c.typename IN ('int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money') THEN '100px'
				ELSE '100%'
			END AS calc_input_width
	) la
	JOIN meta_object mo 
		ON mo.builtin_code = c.tabname COLLATE DATABASE_DEFAULT 
		AND mo.object_type IN ('T', 'V', 'F') 
		AND mo.record_type = 'A'
		AND mo.object_owner = 0x00
	JOIN meta_class mcl 
		ON mcl.storage_object = mo.original
		AND mcl.class_name = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND mcl.record_type = 'A'
		AND mcl.object_owner = 0x00
	JOIN meta_column gc
		ON gc.parent_class = @c_class
		AND gc.column_name = c.colname COLLATE DATABASE_DEFAULT
		AND gc.record_type = 'A'
		AND gc.object_owner = 0x00
	JOIN #global_attr ga
		ON ga.colname = gc.column_name COLLATE DATABASE_DEFAULT
	CROSS APPLY (SELECT dbo.f_generate_original('meta_column', @sys_owner, CAST(mcl.original AS varchar(36)), c.colname) AS orig_uuid) x
	WHERE c.colname NOT LIKE '@%'
	  AND NOT EXISTS (
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
	JOIN meta_object mo 
		ON mo.original = mcl.storage_object 
		AND mo.object_type IN ('T', 'V', 'F') 
		AND mo.record_type = 'A' 
		AND mo.object_owner = 0x00
	JOIN v_syscolumns c
		ON c.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND c.colname = mc.column_name COLLATE DATABASE_DEFAULT
	CROSS APPLY (
		SELECT 
			CASE 
				WHEN c.typename IN ('bit') THEN 'checkbox'
				WHEN c.typename IN ('date', 'datetime', 'datetime2', 'smalldatetime') THEN 'date'
				WHEN c.typename IN ('int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money') THEN 'number'
				WHEN c.typename IN ('varchar', 'nvarchar', 'text', 'ntext') AND c.prec = -1 THEN 'textarea'
				ELSE 'text'
			END AS calc_input_type,
			CASE 
				WHEN c.typename IN ('varchar', 'nvarchar', 'char', 'nchar') AND c.prec > 0 THEN c.prec
				ELSE 0 
			END AS calc_max_length,
			ISNULL(c.iscomputed, 0) AS calc_is_computed,
			CASE 
				WHEN c.typename = 'bit' THEN 'auto'
				WHEN c.typename = 'date' THEN '120px'
				WHEN c.typename = 'smalldatetime' THEN '150px'
				WHEN c.typename IN ('datetime', 'datetime2') THEN '180px'
				WHEN c.typename IN ('int', 'smallint', 'tinyint', 'bigint', 'decimal', 'numeric', 'float', 'real', 'money') THEN '100px'
				ELSE '100%'
			END AS calc_input_width
	) la
	JOIN meta_column gc 
		ON gc.parent_class = @c_class 
		AND gc.column_name = mc.column_name 
		AND gc.record_type = 'A' 
		AND gc.object_owner = 0x00
	JOIN #global_attr ga
		ON ga.colname = gc.column_name COLLATE DATABASE_DEFAULT
	WHERE mc.record_type = 'A' 
	  AND mc.object_owner = 0x00 
	  AND mc.ancestor IS NULL
	  AND mc.column_name NOT LIKE '@%';

	-- Výchozí nastavení hodnoty translate pro některé názvy sloupců
	create table #list_order(column_name varchar(80) collate database_default, list_order int identity primary key)
	insert into #list_order(column_name)
	values('builtin_code'), ('column_name'), ('caption'), ('title')

	-- Nastavení položky "list_order" dle výše uvedeného seznamu
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
			'shortname', 'description', 'helptext', 'note'
		)
END
GO