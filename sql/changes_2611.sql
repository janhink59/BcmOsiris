/* =============================================================================
 * Verze: 2026-11-13 16:00
 * Soubor: changes_2611.sql
 * Účel:   Jednorázové změny struktury a dat databáze za období 11/2026
 *         (aktuální cílová verze '26.11.12.0').
 *         Spouští se v abecedním pořadí v rámci masky changes_*.sql.
 *
 * Pravidla pro údržbu a přidávání změn:
 * - Všechny změnové bloky běží v transakci zahájené příkazem BEGIN TRAN.
 * - Příkaz COMMIT musí být uveden VÝHRADNĚ na konci posledního odladěného bloku
 *   (předchozí příkazy COMMIT při přidání nového bloku odstraň).
 * - Povýšení verze na konci bloku prováděj voláním EXEC dbo.p_update_database_version.
 * - Při selhání přechodu na cílovou verzi vyvolá závěrečná kontrola fatální chybu
 *   RAISERROR(..., 20, 1) WITH LOG, která odpojí spojení a zastaví celou dávku.
 * ============================================================================= */

SET XACT_ABORT ON;
SET ANSI_WARNINGS ON;
SET NOCOUNT OFF;
GO

-- =============================================================================
-- Začátek transakce změnových bloků pro listopad 2026 (2611)
-- =============================================================================
BEGIN TRAN;
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.01.0: Oprava referenced_class u sloupce ancestor a rozšíření asset_class
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.01.0'
)
BEGIN
	PRINT '01.11.2026 (26.11.01.0): Oprava referenced_class u ancestor a rozšíření asset_class';

	IF OBJECT_ID('asset_class', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'asset_class', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'asset_class', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'asset_class', 'is_final', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'asset_class', 'is_protected', 'bit NOT NULL DEFAULT 0';
	END

	IF OBJECT_ID('meta_column', 'U') IS NOT NULL AND OBJECT_ID('meta_class', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
	BEGIN
		DECLARE @sys_own uniqueidentifier = CAST(0x00 AS uniqueidentifier);
		DECLARE @cls_glob uuid = dbo.f_generate_original('meta_class', CAST(@sys_own AS varchar(36)), 'sys_global_columns', '');
		DECLARE @cls_mcol uuid = dbo.f_generate_original('meta_class', CAST(@sys_own AS varchar(36)), 'meta_column', '');

		UPDATE meta_column
		SET referenced_class = @cls_mcol
		WHERE parent_class = @cls_glob
		  AND object_owner = 0x00
		  AND record_type = 'A'
		  AND column_name = 'ancestor'
		  AND ISNULL(referenced_class, 0x00) <> @cls_mcol;
	END

	EXEC dbo.p_update_database_version
		@version = '26.11.01.0',
		@script_name = 'changes_2611.sql',
		@content = 'Oprava referenced_class u sloupce ancestor a doplnění sloupců do asset_class';
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.04.0: Odstranění umělého kořenového záznamu 0x00 (ROOT) z tabulky asset_class
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.04.0'
)
BEGIN
	PRINT '04.11.2026 (26.11.04.0): Odstranění umělého kořenového záznamu 0x00 (ROOT) z tabulky asset_class';

	IF OBJECT_ID('asset_class', 'U') IS NOT NULL
	BEGIN
		UPDATE asset_class
		SET parent_uuid = NULL
		WHERE parent_uuid = 0x00;

		DELETE FROM asset_class
		WHERE uuid = 0x00 OR original = 0x00;
	END

	EXEC dbo.p_update_database_version
		@version = '26.11.04.0',
		@script_name = 'changes_2611.sql',
		@content = 'Odstranění umělého kořenového záznamu 0x00 (ROOT) z tabulky asset_class';
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.04.1: Doplnění is_default do hierarchy_item, sjednocení povinnosti
--                   builtin_code a odemčení svg_icon pro modální editor ikon
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.04.1'
)
BEGIN
	PRINT '04.11.2026 (26.11.04.1): Doplnění is_default do hierarchy_item, sjednocení povinnosti builtin_code a zpřístupnění svg_icon';

	IF OBJECT_ID('hierarchy_item', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'hierarchy_item', 'is_default', 'bit NOT NULL DEFAULT 0';
	END

	IF OBJECT_ID('meta_column', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
	BEGIN
		DECLARE @sys_own2 uniqueidentifier = CAST(0x00 AS uniqueidentifier);
		DECLARE @cls_glob2 uuid = dbo.f_generate_original('meta_class', CAST(@sys_own2 AS varchar(36)), 'sys_global_columns', '');

		UPDATE meta_column
		SET is_mandatory = 1
		WHERE parent_class = @cls_glob2
		  AND object_owner = 0x00
		  AND column_name = 'builtin_code'
		  AND who_modified = 0x00;

		UPDATE meta_column
		SET is_protected = 0
		WHERE parent_class = @cls_glob2
		  AND object_owner = 0x00
		  AND column_name = 'svg_icon'
		  AND who_modified = 0x00;
	END

	EXEC dbo.p_update_database_version
		@version = '26.11.04.1',
		@script_name = 'changes_2611.sql',
		@content = 'Doplnění sloupce is_default do hierarchy_item, sjednocení povinnosti builtin_code a zpřístupnění svg_icon pro modální editor';
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.09.0: Sjednocení builtin_code a link_code na snake_case a
--                   odstranění starých dat porušujících snake_case
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.09.0'
)
BEGIN
	PRINT '09.11.2026 (26.11.09.0): Sjednocení builtin_code a link_code na snake_case a vyčištění starých dat';

	IF OBJECT_ID('organization_licence', 'U') IS NOT NULL
	BEGIN
		UPDATE organization_licence
		SET builtin_code = 'sys'
		WHERE organization_uuid = 0x00
		  AND builtin_code <> 'sys' COLLATE Latin1_General_BIN;

		UPDATE organization_licence
		SET builtin_code = LOWER(REPLACE(REPLACE(LTRIM(RTRIM(builtin_code)), ' ', '_'), '-', '_'))
		WHERE builtin_code LIKE '%[^a-z0-9_]%' COLLATE Latin1_General_BIN;
	END

	IF OBJECT_ID('meta_link_def', 'U') IS NOT NULL
	BEGIN
		UPDATE meta_link_def
		SET link_code = LOWER(link_code)
		WHERE link_code <> LOWER(link_code) COLLATE Latin1_General_BIN;

		DELETE FROM meta_link_def
		WHERE link_code = ''
		   OR link_code LIKE '%[^a-z0-9_]%' COLLATE Latin1_General_BIN;
	END

	DECLARE @clean_tabs TABLE (tabname varchar(128) NOT NULL PRIMARY KEY);
	INSERT INTO @clean_tabs (tabname) VALUES
		('asset'),
		('asset_class'),
		('threat'),
		('impact'),
		('scenario'),
		('countermeasure'),
		('countermeasure_state'),
		('scale'),
		('scale_value'),
		('hierarchy'),
		('hierarchy_item'),
		('meta_menu'),
		('meta_phrase');

	DECLARE @t_clean varchar(128);
	DECLARE cur_clean CURSOR LOCAL FAST_FORWARD FOR
		SELECT tabname FROM @clean_tabs;

	OPEN cur_clean;
	FETCH NEXT FROM cur_clean INTO @t_clean;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF OBJECT_ID(@t_clean, 'U') IS NOT NULL AND COL_LENGTH(@t_clean, 'builtin_code') IS NOT NULL
		BEGIN
			DECLARE @sql_del nvarchar(max) = N'
			DECLARE @bad_origs TABLE (original uniqueidentifier NOT NULL PRIMARY KEY);

			INSERT INTO @bad_origs (original)
			SELECT DISTINCT original
			FROM [' + @t_clean + N']
			WHERE LTRIM(RTRIM(ISNULL(builtin_code, ''''))) = ''''
			   OR builtin_code LIKE ''%[^a-z0-9_]%'' COLLATE Latin1_General_BIN
			   OR LEFT(builtin_code, 1) = ''_''
			   OR RIGHT(builtin_code, 1) = ''_'';

			DELETE t
			FROM [' + @t_clean + N'] t
			JOIN @bad_origs b ON b.original = t.original;

			DELETE FROM [' + @t_clean + N']
			WHERE LTRIM(RTRIM(ISNULL(builtin_code, ''''))) = ''''
			   OR builtin_code LIKE ''%[^a-z0-9_]%'' COLLATE Latin1_General_BIN;';

			EXEC sp_executesql @sql_del;
		END

		FETCH NEXT FROM cur_clean INTO @t_clean;
	END

	CLOSE cur_clean;
	DEALLOCATE cur_clean;

	IF OBJECT_ID('scenario_assessment', 'U') IS NOT NULL AND OBJECT_ID('asset', 'U') IS NOT NULL
	BEGIN
		DELETE sa
		FROM scenario_assessment sa
		WHERE NOT EXISTS (SELECT 1 FROM asset a WHERE a.original = sa.asset_uuid)
		   OR (OBJECT_ID('scenario', 'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM scenario s WHERE s.original = sa.scenario_uuid));

		UPDATE scenario_assessment
		SET builtin_code = LOWER(REPLACE(REPLACE(LTRIM(RTRIM(builtin_code)), ' ', '_'), '-', '_'))
		WHERE builtin_code <> ''
		  AND builtin_code LIKE '%[^a-z0-9_]%' COLLATE Latin1_General_BIN;
	END

	IF OBJECT_ID('countermeasure_implementation', 'U') IS NOT NULL AND OBJECT_ID('asset', 'U') IS NOT NULL
	BEGIN
		DELETE ci
		FROM countermeasure_implementation ci
		WHERE NOT EXISTS (SELECT 1 FROM asset a WHERE a.original = ci.asset_uuid)
		   OR (OBJECT_ID('countermeasure', 'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM countermeasure c WHERE c.original = ci.countermeasure_uuid));

		UPDATE countermeasure_implementation
		SET builtin_code = LOWER(REPLACE(REPLACE(LTRIM(RTRIM(builtin_code)), ' ', '_'), '-', '_'))
		WHERE builtin_code <> ''
		  AND builtin_code LIKE '%[^a-z0-9_]%' COLLATE Latin1_General_BIN;
	END

	IF OBJECT_ID('dbo.p_sync_hierarchy_to_meta_class', 'P') IS NOT NULL
	BEGIN
		EXEC dbo.p_sync_hierarchy_to_meta_class @fix_childless_folders = 1;
	END

	EXEC dbo.p_update_database_version
		@version = '26.11.09.0',
		@script_name = 'changes_2611.sql',
		@content = 'Sjednocení builtin_code a link_code na snake_case a odstranění starých nekonformních dat';
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.11.0: Obousměrné vztahy v meta_link_def se složeným klíčem
--                   (from_class, link_code), vyčištění 1:N sloupců z asset,
--                   tabulka link_diagram a projekce nepřímých a 1:N vazeb
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.11.0'
)
BEGIN
	PRINT '11.11.2026 (26.11.11.0): Rozšíření meta_link_def a link, tabulka link_diagram a odstranění 1:N sloupců z asset';

	IF OBJECT_ID('asset', 'U') IS NOT NULL
	BEGIN
		EXEC sp_drop_index 'asset', 'ix_asset_locations';

		IF COL_LENGTH('asset', 'building_uuid') IS NOT NULL
		BEGIN
			EXEC('UPDATE asset SET parent_uuid = building_uuid WHERE parent_uuid IS NULL AND building_uuid IS NOT NULL');
			EXEC sp_drop_column 'asset', 'building_uuid';
		END

		IF COL_LENGTH('asset', 'room_uuid') IS NOT NULL
		BEGIN
			EXEC('UPDATE asset SET parent_uuid = room_uuid WHERE parent_uuid IS NULL AND room_uuid IS NOT NULL');
			EXEC sp_drop_column 'asset', 'room_uuid';
		END

		EXEC sp_drop_column 'asset', 'host_uuid';
		EXEC sp_drop_column 'asset', 'software_uuid';
		EXEC sp_drop_column 'asset', 'supplier_uuid';
	END

	IF OBJECT_ID('meta_link_def', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'meta_link_def', 'reverse_link_def', 'uuid NULL';
		EXEC p_create_missing_column 'meta_link_def', 'direction_type', 'varchar(1) NOT NULL DEFAULT ''P''';
		EXEC p_create_missing_column 'meta_link_def', 'is_exclusive_parent', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'meta_link_def', 'is_derived', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'meta_link_def', 'diagram_uuid', 'uuid NULL';

		IF OBJECT_ID('meta_original_keys', 'U') IS NOT NULL
		BEGIN
			UPDATE meta_original_keys
			SET key1_column = 'from_class',
				key2_column = 'link_code'
			WHERE table_name = 'meta_link_def';
		END

		DELETE FROM meta_link_def WHERE object_owner = 0x00;
	END

	IF OBJECT_ID('link', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'link', 'reverse_link_weight', 'decimal(16,4) NULL';
		EXEC p_create_missing_column 'link', 'diagram_uuid', 'uuid NULL';
		DELETE FROM link WHERE is_derived = 1;
	END

	IF OBJECT_ID('link_diagram', 'U') IS NULL
	BEGIN
		CREATE TABLE link_diagram (
			uuid uuid NOT NULL,
			object_owner uuid NOT NULL DEFAULT 0x00,
			original uuid NOT NULL DEFAULT 0x00,
			record_type varchar(1) NOT NULL DEFAULT 'A',
			approval_status varchar(1) NOT NULL DEFAULT 'A',
			draft_author uuid NOT NULL DEFAULT 0x00,
			approval_note varchar(max) NOT NULL DEFAULT '',
			inactive bit NOT NULL DEFAULT 0,
			removed bit NOT NULL DEFAULT 0,
			language varchar(2) NOT NULL DEFAULT 'cs',
			valid_from date NOT NULL DEFAULT '1970-01-01',
			valid_to date NULL,
			is_template bit NOT NULL DEFAULT 0,
			template uuid NULL,
			import_origin varchar(255) NULL,
			date_created datetime NOT NULL DEFAULT getdate(),
			who_created uuid NOT NULL DEFAULT 0x00,
			date_modified datetime NOT NULL DEFAULT getdate(),
			who_modified uuid NOT NULL DEFAULT 0x00,
			builtin_code varchar(80) NOT NULL DEFAULT '',
			external_code varchar(40) NOT NULL DEFAULT '',
			caption varchar(200) NOT NULL DEFAULT '',
			shortname varchar(40) NOT NULL DEFAULT '',
			description_text varchar(max) NOT NULL DEFAULT '',
			help_text varchar(max) NOT NULL DEFAULT '',
			svg_icon varchar(max) NOT NULL DEFAULT '',
			sort_code varchar(20) NOT NULL DEFAULT '',
			is_final bit NOT NULL DEFAULT 0,
			is_protected bit NOT NULL DEFAULT 0,
			CONSTRAINT pk_link_diagram PRIMARY KEY (uuid)
		);
	END

	EXEC dbo.p_update_database_version
		@version = '26.11.11.0',
		@script_name = 'changes_2611.sql',
		@content = 'Rozšíření meta_link_def a link se složeným klíčem (from_class, link_code), projekce 1:N vazeb, vytvoření link_diagram a vyčištění asset';
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.12.0: Kompletní vymazání tabulek link a meta_link_def kvůli
--                   přechodu na nový výpočet original (from_class, link_code)
--                   a rozšíření tabulky organization_unit o stromové sloupce
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.12.0'
)
BEGIN
	PRINT '12.11.2026 (26.11.12.0): Vymazání obsahu tabulek link a meta_link_def a rozšíření organization_unit';

	IF OBJECT_ID('asset', 'U') IS NOT NULL
	BEGIN
		EXEC sp_drop_index 'asset', 'ix_asset_locations';

		IF COL_LENGTH('asset', 'building_uuid') IS NOT NULL
		BEGIN
			EXEC('UPDATE asset SET parent_uuid = building_uuid WHERE parent_uuid IS NULL AND building_uuid IS NOT NULL');
			EXEC sp_drop_column 'asset', 'building_uuid';
		END

		IF COL_LENGTH('asset', 'room_uuid') IS NOT NULL
		BEGIN
			EXEC('UPDATE asset SET parent_uuid = room_uuid WHERE parent_uuid IS NULL AND room_uuid IS NOT NULL');
			EXEC sp_drop_column 'asset', 'room_uuid';
		END

		EXEC sp_drop_column 'asset', 'host_uuid';
		EXEC sp_drop_column 'asset', 'software_uuid';
		EXEC sp_drop_column 'asset', 'supplier_uuid';
	END

	IF OBJECT_ID('meta_link_def', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'meta_link_def', 'reverse_link_def', 'uuid NULL';
		EXEC p_create_missing_column 'meta_link_def', 'direction_type', 'varchar(1) NOT NULL DEFAULT ''P''';
		EXEC p_create_missing_column 'meta_link_def', 'is_exclusive_parent', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'meta_link_def', 'is_derived', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'meta_link_def', 'diagram_uuid', 'uuid NULL';
	END

	IF OBJECT_ID('link', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'link', 'reverse_link_weight', 'decimal(16,4) NULL';
		EXEC p_create_missing_column 'link', 'diagram_uuid', 'uuid NULL';
	END

	IF OBJECT_ID('organization_unit', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'organization_unit', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
		EXEC p_create_missing_column 'organization_unit', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'organization_unit', 'import_origin', 'varchar(255) NULL';
		EXEC p_create_missing_column 'organization_unit', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'organization_unit', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'organization_unit', 'parent_uuid', 'uuid NULL';
		EXEC p_create_missing_column 'organization_unit', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'organization_unit', 'is_leaf', 'bit NOT NULL DEFAULT 1';
		EXEC p_create_missing_column 'organization_unit', 'is_final', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'organization_unit', 'is_protected', 'bit NOT NULL DEFAULT 0';
	END

	IF OBJECT_ID('meta_original_keys', 'U') IS NOT NULL
	BEGIN
		UPDATE meta_original_keys
		SET key1_column = 'from_class',
			key2_column = 'link_code'
		WHERE table_name = 'meta_link_def';
	END

	IF OBJECT_ID('link', 'U') IS NOT NULL
	BEGIN
		DELETE FROM link;
	END

	IF OBJECT_ID('meta_link_def', 'U') IS NOT NULL
	BEGIN
		DELETE FROM meta_link_def;
	END

	EXEC dbo.p_update_database_version
		@version = '26.11.12.0',
		@script_name = 'changes_2611.sql',
		@content = 'Kompletní vyčištění tabulek link a meta_link_def pro přechod na složený klíč (from_class, link_code) a rozšíření organization_unit';

	-- !!! Při ladění nanečisto zakomentuj následující COMMIT; při přidání dalšího bloku jej přesuň na konec nového bloku !!!
	COMMIT;
END
GO

-- =============================================================================
-- Bezpečnostní pojistka a závěrečná kontrola provedení dávky changes_2611.sql
-- =============================================================================
IF @@TRANCOUNT > 0 ROLLBACK;
SET NOCOUNT ON;
GO

IF OBJECT_ID('system_constant', 'U') IS NOT NULL
BEGIN
	DECLARE @expected_version varchar(20) = '26.11.12.0';                      -- Požadovaná cílová verze tohoto skriptu
	DECLARE @current_version varchar(20) = '';                                 -- Skutečná verze zjištěná v system_constant

	SELECT TOP 1 @current_version = ISNULL(database_version, '')
	FROM system_constant;

	IF @current_version = @expected_version
	BEGIN
		DECLARE @ok_msg varchar(800) = 'Databáze je v požadované verzi ' + @expected_version + '.' + CHAR(13) + CHAR(10)
			+ 'Pokud nebyla hlášena chyba zprávou označenou červeně,' + CHAR(13) + CHAR(10)
			+ 'otevřete a spusťte hlavní dávku pro aktualizaci objektů "BcmOsirisDb.sql".';
		RAISERROR(@ok_msg, 1, 1);
	END
	ELSE IF @current_version > @expected_version
	BEGIN
		PRINT 'Dávka changes_2611.sql neprovedla žádnou změnu.';
	END
	ELSE
	BEGIN
		DECLARE @err_msg varchar(800) = 'Databázi se v dávce changes_2611.sql nepodařilo převést do verze ' + @expected_version + '!' + CHAR(13) + CHAR(10)
			+ 'Zjištěná verze v system_constant je: ' + @current_version + '.' + CHAR(13) + CHAR(10)
			+ 'Zkontrolujte předchozí chybové zprávy nebo zda nebyl v posledním bloku zakomentován příkaz COMMIT.';
		RAISERROR(@err_msg, 20, 1) WITH LOG;
	END
END
GO