/* =============================================================================
 * Verze: 2026-11-11 21:30
 * Soubor: changes_2026.sql
 * Účel:   Jednorázové změny struktury a dat databáze v kalendářním roce 2026.
 *         Spouští se samostatně PŘED hlavním slepeným skriptem BcmOsirisDb.sql.
 *
 * Pravidla pro údržbu a přidávání změn:
 * - Verze databáze (system_constant.database_version) má formát 'RR.MM.DD.N'
 *   (např. '26.11.11.0', kde poslední číslice N je intradenní pořadí změny).
 * - Všechny změnové bloky běží v transakci zahájené příkazem BEGIN TRAN.
 * - Příkaz COMMIT musí být uveden VÝHRADNĚ na konci posledního odladěného bloku
 *   (předchozí příkazy COMMIT při přidání nového bloku odstraň).
 * - Při testování nového bloku nanečisto zakomentuj poslední COMMIT – pojistka
 *   IF @@TRANCOUNT > 0 ROLLBACK na konci souboru změny vrátí a závěrečná
 *   kontrola ohlásí červenou chybu (severity 16), že verze nebyla povýšena.
 * - V blocích, které přidávají sloupce do již existujících tabulek přes
 *   p_create_missing_column, nikdy nepoužívej statické DML dotazy (INSERT/UPDATE)
 *   odkazující na nové sloupce (SQL Server by je nezkopiloval); pro případný
 *   přenos dat vždy použij dynamické EXEC('...'). Prvotní plnění výchozích
 *   záznamů patří výhradně do skriptů fillup_*.sql v BcmOsirisDb.sql.
 * - Opakované spuštění skriptu nebo spuštění staršího skriptu nad novější
 *   databází neprovede žádné změny a nezpůsobí žádnou škodu.
 *
 * Změny:
 * - 2026-11-11 21:30 (26.11.11.0): Rozšíření meta_link_def (reverse_link_def,
 *   direction_type, is_exclusive_parent, is_derived, diagram_uuid) a link
 *   (reverse_link_weight, diagram_uuid), vytvoření tabulky link_diagram,
 *   odstranění redundantních 1:N sloupců z tabulky asset (building_uuid,
 *   room_uuid, host_uuid, software_uuid, supplier_uuid) a oprava uq_%_language.
 * - 2026-11-09 18:30 (26.11.09.0): Sjednocení builtin_code a link_code na
 *   striktní snake_case a odstranění starých záznamů porušujících snake_case.
 * - 2026-11-04 15:15 (26.11.04.1): Doplnění sloupce is_default do hierarchy_item,
 *   sjednocení povinnosti builtin_code (s automatickým odvozením z názvu v UI)
 *   a zpřístupnění sloupce svg_icon pro modální editor ikon.
 * - 2026-11-04 10:30 (26.11.04.0): Odstranění umělého kořenového záznamu 0x00 (ROOT)
 *   z tabulky asset_class.
 * - 2026-11-01 18:00 (26.11.01.0): Oprava vazby referenced_class u sloupce
 *   ancestor v sys_global_columns a doplnění sloupců do asset_class.
 * ============================================================================= */

SET XACT_ABORT ON;
SET ANSI_WARNINGS ON;
SET NOCOUNT OFF;
GO

-- =============================================================================
-- Začátek transakce změnových bloků pro rok 2026
-- =============================================================================
BEGIN TRAN;
GO

-- -----------------------------------------------------------------------------
-- Verze 26.10.20.0: Zavedení systému upgradů, sjednocení verze a service_logbook
-- -----------------------------------------------------------------------------
IF EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.10.20.0'
)
BEGIN
	PRINT '20.10.2026 (26.10.20.0): Inicializace systému upgradů databáze a tabulky service_logbook';

	IF OBJECT_ID('service_logbook') IS NULL
	BEGIN
		CREATE TABLE service_logbook (
			id int IDENTITY PRIMARY KEY,
			servername varchar(250) NOT NULL DEFAULT @@servername,
			original_login varchar(200) NOT NULL DEFAULT original_login(),
			[date] smalldatetime NOT NULL DEFAULT getdate(),
			[name] varchar(250) NOT NULL,
			[version] varchar(200) NOT NULL,
			content varchar(max) NULL
		);
	END

	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.10.20.0' FOR database_version;

	UPDATE system_constant
	SET database_version = '26.10.20.0',
		date_modified = GETDATE();

	INSERT INTO service_logbook ([name], [version], content)
	VALUES (
		'changes_2026.sql',
		'26.10.20.0',
		'Inicializace systému upgradů databáze a nastavení výchozí verze 26.10.20.0'
	);
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.10.29.0: Reorganizace organization / organization_licence
--                   a user_account / user_organization_access
-- -----------------------------------------------------------------------------
IF EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.10.29.0'
)
BEGIN
	PRINT '29.10.2026 (26.10.29.0): Narovnání sloupců v organization_licence, organization, user_account a user_organization_access';

	EXEC p_create_missing_column 'organization_licence', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
	EXEC p_create_missing_column 'organization_licence', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
	EXEC p_create_missing_column 'organization_licence', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
	EXEC p_create_missing_column 'organization_licence', 'import_origin', 'varchar(255) NULL';
	EXEC p_create_missing_column 'organization_licence', 'login_disabled', 'bit NOT NULL DEFAULT 0';

	IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'organization_licence' AND colname = 'is_developer')
	BEGIN
		EXEC('UPDATE organization_licence SET licence_level = 255 WHERE is_developer = 1 AND licence_level < 255');
		EXEC sp_drop_column 'organization_licence', 'is_developer';
	END

	IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'organization_licence' AND colname = 'organization_name')
	BEGIN
		EXEC('UPDATE organization_licence SET caption = organization_name WHERE caption = '''' AND organization_name <> ''''');
		EXEC sp_drop_column 'organization_licence', 'organization_name';
	END

	IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'organization' AND colname = 'login_disabled')
	BEGIN
		EXEC('
			UPDATE ol
			SET ol.login_disabled = o.login_disabled
			FROM organization_licence ol
			JOIN organization o ON o.original = ol.organization_uuid AND o.record_type = ''A''
			WHERE ol.record_type = ''A''
		');
	END

	EXEC sp_drop_column 'organization', 'licence_level';
	EXEC sp_drop_column 'organization', 'login_disabled';

	EXEC p_create_missing_column 'organization', 'preferred_language', 'varchar(2) NOT NULL DEFAULT ''cs''';
	EXEC p_create_missing_column 'organization', 'currency_unit', 'varchar(40) NOT NULL DEFAULT ''tis. Kč''';
	EXEC p_create_missing_column 'organization', 'currency_digits', 'tinyint NOT NULL DEFAULT 2';
	EXEC p_create_missing_column 'organization', 'currency_before', 'bit NOT NULL DEFAULT 0';
	EXEC p_create_missing_column 'organization', 'format_date', 'varchar(20) NOT NULL DEFAULT ''dd.MM.yyyy''';
	EXEC p_create_missing_column 'organization', 'format_time', 'varchar(20) NOT NULL DEFAULT ''HH:mm:ss''';
	EXEC p_create_missing_column 'organization', 'time_zone', 'varchar(100) NOT NULL DEFAULT ''Europe/Prague''';
	EXEC p_create_missing_column 'organization', 'thousand_separator', 'varchar(1) NOT NULL DEFAULT '' ''';
	EXEC p_create_missing_column 'organization', 'decimal_separator', 'varchar(1) NOT NULL DEFAULT '',''';
	EXEC p_create_missing_column 'organization', 'export_delimiter', 'varchar(1) NOT NULL DEFAULT '';''';
	EXEC p_create_missing_column 'organization', 'max_threat_score', 'decimal(9,4) NOT NULL DEFAULT 13.0000';
	EXEC p_create_missing_column 'organization', 'max_vulnerability_score', 'decimal(9,4) NOT NULL DEFAULT 6.5000';
	EXEC p_create_missing_column 'organization', 'max_impact_score', 'decimal(9,4) NOT NULL DEFAULT 25.5000';
	EXEC p_create_missing_column 'organization', 'max_risk_score', 'decimal(9,4) NOT NULL DEFAULT 40.7500';
	EXEC p_create_missing_column 'organization', 'max_impact_financial', 'decimal(18,2) NULL';
	EXEC p_create_missing_column 'organization', 'residual_risk_min_financial', 'decimal(18,2) NULL';
	EXEC p_create_missing_column 'organization', 'evaluation_method', 'varchar(40) NOT NULL DEFAULT ''''';

	EXEC dropni 'organization_settings';

	EXEC p_create_missing_column 'user_organization_access', 'department_name', 'varchar(150) NOT NULL DEFAULT ''''';
	EXEC p_create_missing_column 'user_organization_access', 'job_title', 'varchar(150) NOT NULL DEFAULT ''''';
	EXEC p_create_missing_column 'user_organization_access', 'manager_uuid', 'uuid NULL';
	EXEC p_create_missing_column 'user_organization_access', 'note', 'varchar(max) NOT NULL DEFAULT ''''';
	EXEC p_create_missing_column 'user_organization_access', 'working_date', 'date NULL';
	EXEC p_create_missing_column 'user_organization_access', 'evaluation_method', 'varchar(40) NOT NULL DEFAULT ''''';

	IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'user_account' AND colname = 'department_name')
	BEGIN
		EXEC('
			UPDATE uoa
			SET uoa.department_name = CASE WHEN uoa.department_name = '''' THEN u.department_name ELSE uoa.department_name END,
				uoa.job_title = CASE WHEN uoa.job_title = '''' THEN u.job_title ELSE uoa.job_title END,
				uoa.manager_uuid = COALESCE(uoa.manager_uuid, u.manager_uuid),
				uoa.note = CASE WHEN uoa.note = '''' THEN u.note ELSE uoa.note END
			FROM user_organization_access uoa
			JOIN user_account u ON u.original = uoa.user_account_uuid AND u.record_type = ''A''
		');
		EXEC sp_drop_column 'user_account', 'department_name';
		EXEC sp_drop_column 'user_account', 'job_title';
		EXEC sp_drop_column 'user_account', 'manager_uuid';
		EXEC sp_drop_column 'user_account', 'note';
	END

	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.10.29.0' FOR database_version;

	UPDATE system_constant
	SET database_version = '26.10.29.0',
		date_modified = GETDATE();

	INSERT INTO service_logbook ([name], [version], content)
	VALUES (
		'changes_2026.sql',
		'26.10.29.0',
		'Reorganizace sloupců mezi organization_licence / organization a user_account / user_organization_access, zrušení organization_settings'
	);
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.01.0: Oprava referenced_class u sloupce ancestor a rozšíření asset_class
-- -----------------------------------------------------------------------------
IF EXISTS (
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

	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.11.01.0' FOR database_version;

	UPDATE system_constant
	SET database_version = '26.11.01.0',
		date_modified = GETDATE();

	INSERT INTO service_logbook ([name], [version], content)
	VALUES (
		'changes_2026.sql',
		'26.11.01.0',
		'Oprava referenced_class u sloupce ancestor a doplnění sloupců do asset_class'
	);
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.04.0: Odstranění umělého kořenového záznamu 0x00 (ROOT) z tabulky asset_class
-- -----------------------------------------------------------------------------
IF EXISTS (
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

	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.11.04.0' FOR database_version;

	UPDATE system_constant
	SET database_version = '26.11.04.0',
		date_modified = GETDATE();

	INSERT INTO service_logbook ([name], [version], content)
	VALUES (
		'changes_2026.sql',
		'26.11.04.0',
		'Odstranění umělého kořenového záznamu 0x00 (ROOT) z tabulky asset_class'
	);
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.04.1: Doplnění is_default do hierarchy_item, sjednocení povinnosti
--                   builtin_code a odemčení svg_icon pro modální editor ikon
-- -----------------------------------------------------------------------------
IF EXISTS (
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

	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.11.04.1' FOR database_version;

	UPDATE system_constant
	SET database_version = '26.11.04.1',
		date_modified = GETDATE();

	INSERT INTO service_logbook ([name], [version], content)
	VALUES (
		'changes_2026.sql',
		'26.11.04.1',
		'Doplnění sloupce is_default do hierarchy_item, sjednocení povinnosti builtin_code a zpřístupnění svg_icon pro modální editor'
	);
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.09.0: Sjednocení builtin_code a link_code na snake_case a
--                   odstranění starých dat porušujících snake_case
-- -----------------------------------------------------------------------------
IF EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.09.0'
)
BEGIN
	PRINT '09.11.2026 (26.11.09.0): Sjednocení builtin_code a link_code na snake_case a vyčištění starých dat';

	-- 1. Oprava builtin_code v organization_licence ('SYS' -> 'sys' a převod na snake_case)
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

	-- 2. Oprava link_code v meta_link_def (např. 'asset_Additional_class' -> 'asset_additional_class')
	IF OBJECT_ID('meta_link_def', 'U') IS NOT NULL
	BEGIN
		UPDATE meta_link_def
		SET link_code = LOWER(link_code)
		WHERE link_code <> LOWER(link_code) COLLATE Latin1_General_BIN;

		DELETE FROM meta_link_def
		WHERE link_code = ''
		   OR link_code LIKE '%[^a-z0-9_]%' COLLATE Latin1_General_BIN;
	END

	-- 3. Odstranění starých a testovacích dat v katalogových a CRMM tabulkách,
	--    jejichž builtin_code nedodržuje pravidlo snake_case ([a-z0-9_])
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

	-- 4. Vyčištění případných osiřelých záznamů v navazujících tabulkách CRMM
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

	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.11.09.0' FOR database_version;

	UPDATE system_constant
	SET database_version = '26.11.09.0',
		date_modified = GETDATE();

	INSERT INTO service_logbook ([name], [version], content)
	VALUES (
		'changes_2026.sql',
		'26.11.09.0',
		'Sjednocení builtin_code a link_code na snake_case a odstranění starých nekonformních dat'
	);
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.11.11.0: Obousměrné vztahy v meta_link_def, vyčištění 1:N sloupců
--                   z asset, tabulka link_diagram a projekce nepřímých vazeb
-- -----------------------------------------------------------------------------
IF EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.11.0'
)
BEGIN
	PRINT '11.11.2026 (26.11.11.0): Rozšíření meta_link_def a link, tabulka link_diagram a odstranění 1:N sloupců z asset';

	-- 1. Odstranění redundantních vazebních sloupců z tabulky asset (ponechává se pouze přímý parent_uuid)
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

	-- 2. Rozšíření tabulky meta_link_def pro zpětné vztahy, exkluzivní parent_uuid a odvozené vztahy z diagramů
	IF OBJECT_ID('meta_link_def', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'meta_link_def', 'reverse_link_def', 'uuid NULL';
		EXEC p_create_missing_column 'meta_link_def', 'direction_type', 'varchar(1) NOT NULL DEFAULT ''P''';
		EXEC p_create_missing_column 'meta_link_def', 'is_exclusive_parent', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'meta_link_def', 'is_derived', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'meta_link_def', 'diagram_uuid', 'uuid NULL';
	END

	-- 3. Rozšíření tabulky link o zpětnou váhu a identifikátor diagramu pro materializované nepřímé vazby
	IF OBJECT_ID('link', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'link', 'reverse_link_weight', 'decimal(16,4) NULL';
		EXEC p_create_missing_column 'link', 'diagram_uuid', 'uuid NULL';
	END

	-- 4. Založení tabulky link_diagram (pokud ještě neexistuje)
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

	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.11.11.0' FOR database_version;

	UPDATE system_constant
	SET database_version = '26.11.11.0',
		date_modified = GETDATE();

	INSERT INTO service_logbook ([name], [version], content)
	VALUES (
		'changes_2026.sql',
		'26.11.11.0',
		'Rozšíření meta_link_def a link pro zpětné vztahy, exkluzivní parent_uuid a projekci diagramů, vytvoření link_diagram a vyčištění asset'
	);

	-- !!! Při ladění nanečisto zakomentuj následující COMMIT; při přidání dalšího bloku jej přesuň na konec nového bloku !!!
	COMMIT;
END
GO

-- =============================================================================
-- Bezpečnostní pojistka: Odrolování neukončené transakce (při testu nanečisto
-- nebo pokud byla databáze již ve stejné či vyšší verzi a žádný blok neproběhl)
-- =============================================================================
IF @@TRANCOUNT > 0 ROLLBACK;
SET NOCOUNT ON;
GO

-- =============================================================================
-- Závěrečná kontrola, zda byla databáze převedena do očekávané verze
-- =============================================================================
IF @@TRANCOUNT > 0 ROLLBACK;

DECLARE @expected_version varchar(20) = '26.11.11.0';                          -- Požadovaná cílová verze tohoto skriptu
DECLARE @current_version varchar(20) = '';                                     -- Skutečná verze zjištěná v system_constant
DECLARE @msg varchar(800) = '';                                                -- Text výsledné zprávy pro operátora
DECLARE @severity int = 16;                                                    -- Závažnost (1 = OK/Info, 16 = Červená chyba)

SELECT TOP 1
	@current_version = ISNULL(database_version, '')
FROM system_constant;

IF @current_version = @expected_version
BEGIN
	SET @severity = 1;
	SET @msg = 'Databáze je v požadované verzi ' + @expected_version + '.' + CHAR(13) + CHAR(10)
		+ 'Pokud nebyla hlášena chyba zprávou označenou červeně,' + CHAR(13) + CHAR(10)
		+ 'otevřete a spusťte hlavní dávku pro aktualizaci objektů "BcmOsirisDb.sql".';
END
ELSE IF @current_version > @expected_version
BEGIN
	SET @severity = 1;
	SET @msg = 'Databáze je již v novější verzi (' + @current_version + ') než tento změnový skript (' + @expected_version + ').' + CHAR(13) + CHAR(10)
		+ 'Žádné změny nebyly provedeny.';
END
ELSE
BEGIN
	SET @severity = 16;
	SET @msg = 'Databázi se nepodařilo převést do verze ' + @expected_version + '!' + CHAR(13) + CHAR(10)
		+ 'Zjištěná verze v system_constant je: ' + @current_version + '.' + CHAR(13) + CHAR(10)
		+ 'Zkontrolujte předchozí chybové zprávy nebo zda nebyl v posledním bloku zakomentován příkaz COMMIT.';
END

RAISERROR(@msg, @severity, 1);
GO