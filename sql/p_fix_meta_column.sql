EXECUTE dropni 'p_fix_meta_column', 'P'
GO

/* =============================================================================
 * Procedura: p_fix_meta_column
 * Verze: 2026-09-25 17:15
 * Účel: Plně automatizovaná synchronizace a provazování dědičnosti metadat.
 *       1. Vypočítá nejčastější hodnoty metadat (módus) z DB včetně chytré šířky.
 *       2. Založí a naplní globální slovník sloupců (typ 'C').
 *       3. Synchronizuje fyzické objekty (T, V, F).
 *       4. Synchronizuje fyzické sloupce a zanese odchylky od globálu.
 * Poznámka: Pracuje striktně se systémovými záznamy (object_owner = 0x00).
 * OPRAVA: Využití nativního výpočtu f_generate_original pro prevenci duplicit.
 *         Odstranění @ parametrů a omezení na dbo aplikační objekty.
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
		FROM meta_object
		WHERE object_owner = 0x00 AND record_type = 'A'
	)
	DELETE FROM meta_object WHERE uuid IN (SELECT uuid FROM cte WHERE rn > 1);

	-- 3. Odstranění duplicit sloupců
	WITH cte AS (
		SELECT uuid, ROW_NUMBER() OVER(PARTITION BY parent_object, column_name, object_owner, record_type ORDER BY date_created ASC) as rn
		FROM meta_column
		WHERE object_owner = 0x00 AND record_type = 'A'
	)
	DELETE FROM meta_column WHERE uuid IN (SELECT uuid FROM cte WHERE rn > 1);

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
	-- 1. PŘÍPRAVA GLOBÁLNÍHO SLOVNÍKU (Typ C)
	-- -------------------------------------------------------------------------
	
	-- ELEGANTNÍ VÝPOČET: Konstantní UUID slovníku známe z kombinace key1='C' a key2='sys_global_columns'
	DECLARE @c_object uniqueidentifier = dbo.f_generate_original('meta_object', @sys_owner, 'C', 'sys_global_columns');

	IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @c_object AND object_owner = 0x00 AND record_type = 'A')
	BEGIN
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status,
			object_type, builtin_code, caption, caption_plural, description, helptext,
			module, is_final, is_protected
		) VALUES (
			@c_object, 0x00, @c_object, 'A', 'A',
			'C', 'sys_global_columns', 'Globální definice sloupců', 'Globální definice sloupců', 'Systémový slovník pro výchozí vlastnosti databázových sloupců', 'Kontejner',
			'', 1, 1
		);
	END

	-- Plnění unikátních názvů sloupců do globálního slovníku
	INSERT INTO meta_column (
		uuid, object_owner, original, record_type, approval_status,
		parent_object, parent_order, sort_code, column_name, 
		caption, caption_plural, description, label, header, helptext, placeholder,
		input_type, input_width, input_rows, max_length, css_class,
		translate, history, is_html, is_mandatory, is_url, is_computed, 
		show_empty, hidden, customizable,
		is_final, is_protected, ancestor
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',                                -- uuid se plní vypočítaným hashem, trigger to potvrdí
		@c_object, 
		ROW_NUMBER() OVER(ORDER BY ga.colname), 
		'C' + RIGHT('000' + CAST(ROW_NUMBER() OVER(ORDER BY ga.colname) * 10 AS varchar), 3),
		ga.colname,
		ga.colname, ga.colname, 'Globální definice pro ' + ga.colname, ga.colname, ga.colname, 
		'Nápověda pro ' + ga.colname, 'Zadejte ' + ga.colname,
		ga.calc_input_type, ga.calc_input_width, 0, ga.calc_max_length, '',
		0, 0, 0, 0, 0, ga.calc_is_computed, 1, 0, 1,
		1, 0, NULL
	FROM #global_attr ga
	CROSS APPLY (SELECT dbo.f_generate_original('meta_column', @sys_owner, CAST(@c_object AS varchar(36)), ga.colname) AS orig_uuid) x
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_column mc 
		WHERE mc.original = x.orig_uuid 
		  AND mc.record_type = 'A'
		  AND mc.object_owner = 0x00
	);

	-- -------------------------------------------------------------------------
	-- 2. SYNCHRONIZACE OBJEKTŮ (T, V, F)
	-- -------------------------------------------------------------------------
	INSERT INTO meta_object (
		uuid, object_owner, original, record_type, approval_status,
		object_type, builtin_code, caption, caption_plural, description, helptext,
		module, is_final, is_protected
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		x.obj_type, 
		o.name, o.name, o.name, 'Popis pro ' + o.name, 
		CASE WHEN o.type = 'U' THEN 'Nápověda pro tabulku ' + o.name WHEN o.type = 'V' THEN 'Nápověda pro view ' + o.name ELSE 'Nápověda pro ' + o.name END,
		'', 1, 0
	FROM sys.objects o
	CROSS APPLY (SELECT CASE WHEN o.type = 'U' THEN 'T' WHEN o.type = 'V' THEN 'V' ELSE 'F' END AS obj_type) ot
	CROSS APPLY (SELECT dbo.f_generate_original('meta_object', @sys_owner, ot.obj_type, o.name) AS orig_uuid) x
	WHERE o.type IN ('U', 'V', 'FN', 'IF', 'TF')
	  AND o.is_ms_shipped = 0
	  AND o.schema_id = SCHEMA_ID('dbo')
	  AND NOT EXISTS (
		SELECT 1 FROM meta_object mo
		WHERE mo.original = x.orig_uuid
		  AND mo.record_type = 'A'
		  AND mo.object_owner = 0x00
	  );

	-- -------------------------------------------------------------------------
	-- 3. SYNCHRONIZACE LOKÁLNÍCH SLOUPCŮ (Uložení NULL tam, kde je shoda s C)
	-- -------------------------------------------------------------------------
	INSERT INTO meta_column (
		uuid, object_owner, original, record_type, approval_status,
		parent_object, parent_order, column_name, 
		caption, caption_plural, description, label, header, helptext, placeholder,
		input_type, input_width, input_rows, max_length, css_class,
		translate, history, is_html, is_mandatory, is_url, is_computed, 
		show_empty, hidden, customizable,
		is_final, is_protected, ancestor
	)
	SELECT 
		x.orig_uuid, 0x00, x.orig_uuid, 'A', 'A',
		mo.original, c.colid, c.colname,
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
	JOIN meta_column gc
		ON gc.parent_object = @c_object
		AND gc.column_name = c.colname COLLATE DATABASE_DEFAULT
		AND gc.record_type = 'A'
		AND gc.object_owner = 0x00
	JOIN #global_attr ga
		ON ga.colname = gc.column_name COLLATE DATABASE_DEFAULT
	CROSS APPLY (SELECT dbo.f_generate_original('meta_column', @sys_owner, CAST(mo.original AS varchar(36)), c.colname) AS orig_uuid) x
	WHERE c.colname NOT LIKE '@%'
	  AND NOT EXISTS (
		SELECT 1 FROM meta_column mc 
		WHERE mc.original = x.orig_uuid
		  AND mc.record_type = 'A'
		  AND mc.object_owner = 0x00
	);

	-- -------------------------------------------------------------------------
	-- 4. KOREKCE EXISTUJÍCÍCH SLOUPCŮ BEZ PŘEDKA (Napojení na 'C' a zachování odchylek)
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
	JOIN meta_object mo 
		ON mo.original = mc.parent_object 
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
		ON gc.parent_object = @c_object 
		AND gc.column_name = mc.column_name 
		AND gc.record_type = 'A' 
		AND gc.object_owner = 0x00
	JOIN #global_attr ga
		ON ga.colname = gc.column_name COLLATE DATABASE_DEFAULT
	WHERE mc.record_type = 'A' 
	  AND mc.object_owner = 0x00 
	  AND mc.ancestor IS NULL
	  AND mc.column_name NOT LIKE '@%';

END
GO