/* =============================================================================
 * Verze: 2026-11-01 18:00
 * Soubor: changes_2026.sql
 * Účel:   Jednorázové změny struktury a dat databáze v kalendářním roce 2026.
 *         Spouští se samostatně PŘED hlavním slepeným skriptem BcmOsirisDb.sql.
 *
 * Pravidla pro údržbu a přidávání změn:
 * - Verze databáze (system_constant.database_version) má formát 'RR.MM.DD.N'
 *   (např. '26.11.01.0', kde poslední číslice N je intradenní pořadí změny).
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
 * - 2026-11-01 18:00 (26.11.01.0): Oprava vazby referenced_class u sloupce
 *   ancestor v sys_global_columns, zrušení globální povinnosti is_mandatory = 1
 *   u sloupce builtin_code pro běžné věcné tabulky a doplnění sloupců
 *   builtin_code, svg_icon, is_final, is_protected do tabulky asset_class.
 * - 2026-10-29 22:00 (26.10.29.0): Reorganizace sloupců mezi organization_licence
 *   a organization a přesun organizačně závislých sloupců z user_account do
 *   user_organization_access.
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
-- Verze 26.11.01.0: Oprava referenced_class u sloupce ancestor, úprava povinnosti
--                   builtin_code a rozšíření asset_class pro Krok C CRMM
-- -----------------------------------------------------------------------------
IF EXISTS (
	SELECT 1
	FROM system_constant
	WHERE database_version < '26.11.01.0'
)
BEGIN
	PRINT '01.11.2026 (26.11.01.0): Oprava referenced_class u ancestor, odemčení builtin_code pro věcné tabulky a rozšíření asset_class';

	-- 1. Doplnění chybějících sloupců do tabulky asset_class
	IF OBJECT_ID('asset_class', 'U') IS NOT NULL
	BEGIN
		EXEC p_create_missing_column 'asset_class', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'asset_class', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
		EXEC p_create_missing_column 'asset_class', 'is_final', 'bit NOT NULL DEFAULT 0';
		EXEC p_create_missing_column 'asset_class', 'is_protected', 'bit NOT NULL DEFAULT 0';
		EXEC('UPDATE asset_class SET builtin_code = ''ROOT'' WHERE uuid = 0x00 AND builtin_code = ''''');
	END

	-- 2. Oprava nesprávného hashe referenced_class u sloupce ancestor a úprava povinnosti builtin_code v meta_column
	IF OBJECT_ID('meta_column', 'U') IS NOT NULL AND OBJECT_ID('meta_class', 'U') IS NOT NULL AND OBJECT_ID('f_generate_original', 'FN') IS NOT NULL
	BEGIN
		DECLARE @sys_own uniqueidentifier = CAST(0x00 AS uniqueidentifier);
		DECLARE @cls_glob uuid = dbo.f_generate_original('meta_class', CAST(@sys_own AS varchar(36)), 'sys_global_columns', '');
		DECLARE @cls_mcol uuid = dbo.f_generate_original('meta_class', CAST(@sys_own AS varchar(36)), 'meta_column', '');

		-- Oprava referenced_class u sloupce ancestor v globálním slovníku
		UPDATE meta_column
		SET referenced_class = @cls_mcol
		WHERE parent_class = @cls_glob
		  AND object_owner = 0x00
		  AND record_type = 'A'
		  AND column_name = 'ancestor'
		  AND ISNULL(referenced_class, 0x00) <> @cls_mcol;

		-- V globálním slovníku není builtin_code bezpodmínečně povinný (povinnost se řídí kontextem 0x00 / šablony / metadat)
		UPDATE meta_column
		SET is_mandatory = 0
		WHERE parent_class = @cls_glob
		  AND object_owner = 0x00
		  AND column_name = 'builtin_code'
		  AND who_modified = 0x00
		  AND is_mandatory = 1;

		-- U lokálních sloupců builtin_code mimo metadatové tabulky a mimo tabulku hierarchy vrátíme is_mandatory na NULL (dědí z globálního slovníku)
		UPDATE mc
		SET mc.is_mandatory = NULL
		FROM meta_column mc
		JOIN meta_class mcl ON mcl.original = mc.parent_class AND mcl.object_owner = 0x00 AND mcl.record_type = 'A'
		WHERE mc.parent_class <> @cls_glob
		  AND mc.object_owner = 0x00
		  AND mc.column_name = 'builtin_code'
		  AND mc.who_modified = 0x00
		  AND mc.is_mandatory = 1
		  AND mcl.class_name NOT LIKE 'meta_%'
		  AND mcl.class_name <> 'hierarchy';
	END

	-- 3. Povýšení verze databáze v system_constant a zápis do service_logbook
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
		'Oprava referenced_class u sloupce ancestor, úprava podmíněné povinnosti builtin_code a doplnění sloupců do asset_class'
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

DECLARE @expected_version varchar(20) = '26.11.01.0';                          -- Požadovaná cílová verze tohoto skriptu
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