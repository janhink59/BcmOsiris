/* =============================================================================
 * Verze: 2026-10-29 15:30
 * Soubor: p_empty_trash.sql
 * Procedura: dbo.p_empty_trash
 * Účel:   Automatické vysypávání koše (fyzické mazání záznamů s removed = 1
 *         starších než days_in_trash dnů podle nastavení v tabulce meta_class).
 *         Hodnota days_in_trash = 0 znamená, že se záznamy dané třídy z koše
 *         automaticky nemazají nikdy.
 *         Pokud je z koše fyzicky smazán hlavní záznam (record_type = 'A'),
 *         odstraní se s ním i osiřelé podřízené záznamy ('L', 'D', 'H')
 *         stejného (original, object_owner).
 * Vazby:  - Čte tabulky meta_class, meta_object a pohled v_syscolumns.
 *         - Volána v závěru sestavovací dávky (final_scripts.sql) nebo z údržby.
 *         - Při @log_to_service_logbook = 1 zapíše informaci o počtu smazaných
 *           záznamů do tabulky service_logbook (pokud bylo něco smazáno).
 * ============================================================================= */

EXECUTE dropni 'p_empty_trash', 'P';
GO

CREATE PROCEDURE dbo.p_empty_trash
	@log_to_service_logbook bit = 1,
	@debug bit = 0
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Pro každou fyzickou RAC tabulku vezmeme nejdelší dobu uchování days_in_trash
	-- ze všech aktivních logických tříd, které do ní ukládají data (0 = nikdy nemazat).
	DECLARE @targets TABLE (
		table_name varchar(128) NOT NULL PRIMARY KEY,
		days_in_trash int NOT NULL
	);

	INSERT INTO @targets (table_name, days_in_trash)
	SELECT
		mo.builtin_code,
		CASE WHEN MIN(CASE WHEN mc.days_in_trash <= 0 THEN 0 ELSE 1 END) = 0 THEN 0 ELSE MAX(CAST(mc.days_in_trash AS int)) END
	FROM meta_class mc
	JOIN meta_object mo
		ON mo.original = mc.storage_object
		AND mo.object_owner = 0x00
		AND mo.record_type = 'A'
		AND mo.removed = 0
		AND mo.object_type = 'T'
	JOIN v_syscolumns c_rem
		ON c_rem.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND c_rem.colname = 'removed'
	JOIN v_syscolumns c_mod
		ON c_mod.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND c_mod.colname = 'date_modified'
	JOIN v_syscolumns c_rt
		ON c_rt.tabname = mo.builtin_code COLLATE DATABASE_DEFAULT
		AND c_rt.colname = 'record_type'
	WHERE mc.object_owner = 0x00
	  AND mc.record_type = 'A'
	  AND mc.removed = 0
	  AND mo.builtin_code NOT LIKE '%$'
	GROUP BY mo.builtin_code;

	DECLARE @tab varchar(128), @days int;
	DECLARE @total_deleted int = 0;
	DECLARE @summary varchar(max) = '';

	DECLARE cur_trash CURSOR LOCAL FAST_FORWARD FOR
		SELECT table_name, days_in_trash
		FROM @targets
		WHERE days_in_trash > 0
		ORDER BY table_name;

	OPEN cur_trash;
	FETCH NEXT FROM cur_trash INTO @tab, @days;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		DECLARE @cutoff datetime = DATEADD(day, -@days, GETDATE());
		DECLARE @del_cnt int = 0;

		-- Chráněné systémové kořenové záznamy (0x00, global_phrase, sys_global_columns, home) mají removed = 0,
		-- přesto přidáme explicitní pojistku uuid <> 0x00 AND original <> 0x00.
		DECLARE @sql nvarchar(max) = N'
		DECLARE @c int = 0;

		-- 1. Smazání podřízených záznamů (L, D, H), jejichž hlavní A záznam je v koši déle než @p_cutoff
		DELETE sub
		FROM [' + @tab + N'] sub
		JOIN [' + @tab + N'] a
			ON a.original = sub.original
			AND a.object_owner = sub.object_owner
			AND a.record_type = ''A''
		WHERE sub.record_type <> ''A''
		  AND a.removed = 1
		  AND a.date_modified < @p_cutoff
		  AND a.original <> 0x00;

		SET @c = @c + @@ROWCOUNT;

		-- 2. Smazání všech záznamů (A, L, D, H), které mají samy removed = 1 déle než @p_cutoff
		DELETE FROM [' + @tab + N']
		WHERE removed = 1
		  AND date_modified < @p_cutoff
		  AND uuid <> 0x00
		  AND original <> 0x00;

		SET @c = @c + @@ROWCOUNT;
		SELECT @p_out = @c;';

		EXEC sp_executesql
			@stmt = @sql,
			@params = N'@p_cutoff datetime, @p_out int OUTPUT',
			@p_cutoff = @cutoff,
			@p_out = @del_cnt OUTPUT;

		IF @del_cnt > 0
		BEGIN
			SET @total_deleted = @total_deleted + @del_cnt;
			SET @summary = @summary + CASE WHEN @summary <> '' THEN ', ' ELSE '' END + @tab + ': ' + CAST(@del_cnt AS varchar(20));
			IF @debug = 1
				PRINT 'p_empty_trash: Z tabulky ' + @tab + ' smazáno záznamů: ' + CAST(@del_cnt AS varchar(20));
		END

		FETCH NEXT FROM cur_trash INTO @tab, @days;
	END

	CLOSE cur_trash;
	DEALLOCATE cur_trash;

	IF @total_deleted > 0 AND @log_to_service_logbook = 1 AND OBJECT_ID('service_logbook') IS NOT NULL
	BEGIN
		INSERT INTO service_logbook ([name], [version], content)
		VALUES (
			'p_empty_trash',
			CONVERT(varchar(20), GETDATE(), 120),
			'Automatické vysypání koše (celkem smazáno ' + CAST(@total_deleted AS varchar(20)) + ' záznamů): ' + @summary
		);
	END
END
GO