execute dropni 'p_fix_meta_column', 'P'
GO

/* =============================================================================
 * Procedura: p_fix_meta_column
 * Účel: Automatická synchronizace fyzické struktury databáze do metadatových 
 *       tabulek meta_object a meta_column. 
 *       Krok 1: Mapování objektů (T, V, F).
 *       Krok 2: Mapování sloupců.
 *       Krok 3: Pokročilá detekce předků u Views přes závislosti.
 * ============================================================================= */
CREATE PROCEDURE p_fix_meta_column
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- -------------------------------------------------------------------------
	-- 1. SYNCHRONIZACE OBJEKTŮ DO meta_object
	-- -------------------------------------------------------------------------
	INSERT INTO meta_object (
		uuid, object_owner, original, record_type, approval_status,
		object_type, builtin_code, caption, caption_plural, helptext,
		module, generic_column_list, is_final, is_protected
	)
	SELECT 
		NEWID(), 0x00, NEWID(), 'A', 'A',
		CASE 
			WHEN o.type = 'U' THEN 'T'
			WHEN o.type = 'V' THEN 'V'
			WHEN o.type IN ('FN', 'IF', 'TF') THEN 'F'
		END, 
		o.name, o.name, o.name, 'Vygenerováno automaticky', 
		'', 
		CASE 
			WHEN o.name = 'meta_object' THEN 'object_type,builtin_code'
			WHEN o.name = 'meta_column' THEN 'parent_object,column_name'
			ELSE 'uuid'
		END,
		1, 0
	FROM sys.objects o
	WHERE o.type IN ('U', 'V', 'FN', 'IF', 'TF')
	  AND o.name COLLATE DATABASE_DEFAULT NOT IN (
	  	SELECT builtin_code FROM meta_object WHERE object_type IN ('T', 'V', 'F') AND record_type = 'A'
	  );

	UPDATE meta_object SET original = uuid WHERE original <> uuid AND record_type = 'A';

	UPDATE meta_object SET generic_column_list = 'object_type,builtin_code'
	WHERE builtin_code = 'meta_object' AND object_type = 'T' AND generic_column_list <> 'object_type,builtin_code';

	UPDATE meta_object SET generic_column_list = 'parent_object,column_name'
	WHERE builtin_code = 'meta_column' AND object_type = 'T' AND generic_column_list <> 'parent_object,column_name';

	-- -------------------------------------------------------------------------
	-- 2. SYNCHRONIZACE SLOUPCŮ DO meta_column
	-- -------------------------------------------------------------------------
	INSERT INTO meta_column (
		uuid, object_owner, original, record_type, approval_status,
		parent_object, parent_order, sort_code, column_name, 
		caption, caption_plural, label, header, helptext, placeholder,
		input_type, input_width, input_rows, input_cols,
		translate, history, is_html, is_mandatory, is_url, is_computed, 
		show_empty, hidden, customizable,
		is_final, is_protected, ancestor
	)
	SELECT 
		NEWID(), 0x00, NEWID(), 'A', 'A',
		mo.original, 
		c.colid, 
		'C' + RIGHT('000' + CAST(c.colid * 10 AS varchar), 3),
		c.colname,
		c.colname, c.colname, c.colname, c.colname, 
		'Nápověda pro ' + c.colname, 'Zadejte ' + c.colname,
		CASE 
			WHEN c.typename IN ('bit') THEN 'checkbox'
			WHEN c.typename IN ('date', 'datetime', 'datetime2') THEN 'date'
			WHEN c.typename IN ('int', 'smallint', 'tinyint', 'decimal', 'numeric') THEN 'number'
			WHEN c.typename IN ('varchar', 'nvarchar') AND c.prec = -1 THEN 'textarea'
			ELSE 'text'
		END,
		'100%', 0, 0,
		0, 0, 0, 
		CASE WHEN c.nulls = 'not null' THEN 1 ELSE 0 END,
		0, ISNULL(c.iscomputed, 0), 1, 0, 1,
		1, 0, NULL
	FROM v_syscolumns c
	JOIN meta_object mo ON mo.builtin_code = c.tabname COLLATE DATABASE_DEFAULT AND mo.object_type IN ('T', 'V', 'F') AND mo.record_type = 'A'
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_column mc 
		WHERE mc.parent_object = mo.original 
		  AND mc.column_name = c.colname COLLATE DATABASE_DEFAULT 
		  AND mc.record_type = 'A'
	);

	UPDATE meta_column SET original = uuid WHERE original <> uuid AND record_type = 'A';

	-- -------------------------------------------------------------------------
	-- 3. PROPOJENÍ PŘEDKŮ (ANCESTOR) U VIEWS (Pokročilá heuristika)
	-- -------------------------------------------------------------------------
	UPDATE mc_view
	SET ancestor = best_match.ancestor_column
	FROM meta_column mc_view
	JOIN meta_object mo_view 
		ON mo_view.original = mc_view.parent_object 
		AND mo_view.record_type = 'A' 
		AND mo_view.object_type = 'V'
	CROSS APPLY (
		SELECT TOP 1 mc_table.original AS ancestor_column
		FROM sys.sql_expression_dependencies sed
		JOIN meta_object mo_table 
			ON mo_table.builtin_code = sed.referenced_entity_name COLLATE DATABASE_DEFAULT
			AND mo_table.object_type = 'T' 
			AND mo_table.record_type = 'A'
		JOIN meta_column mc_table 
			ON mc_table.parent_object = mo_table.original 
			-- Porovnání s ořezáním speciálních přípon z vrepo_ view
			AND mc_table.column_name = 
				CASE 
					WHEN RIGHT(mc_view.column_name, 7) = '_system' THEN LEFT(mc_view.column_name, LEN(mc_view.column_name) - 7)
					WHEN RIGHT(mc_view.column_name, 11) = '_translated' THEN LEFT(mc_view.column_name, LEN(mc_view.column_name) - 11)
					WHEN RIGHT(mc_view.column_name, 9) = '_original' THEN LEFT(mc_view.column_name, LEN(mc_view.column_name) - 9)
					ELSE mc_view.column_name 
				END COLLATE DATABASE_DEFAULT
			AND mc_table.record_type = 'A'
		WHERE sed.referencing_id = OBJECT_ID(mo_view.builtin_code)
		ORDER BY 
			-- Priorita 1: Název view obsahuje název tabulky (např. vrepo_organization -> organization)
			CASE WHEN mo_view.builtin_code LIKE '%' + mo_table.builtin_code + '%' THEN 0 ELSE 1 END ASC,
			-- Priorita 2: V případě více shodných závislostí vezme delší název (specifičtější tabulka)
			LEN(mo_table.builtin_code) DESC
	) AS best_match
	WHERE mc_view.record_type = 'A'
	  AND mc_view.ancestor IS NULL;

END
GO