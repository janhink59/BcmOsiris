/* =============================================================================
 * Verze: 2026-11-13 16:00
 * Soubor: changes_2610.sql
 * Účel:   Jednorázové změny struktury a dat databáze za období 10/2026
 *         (do verze '26.10.29.0').
 *         Spouští se v abecedním pořadí v rámci masky changes_*.sql.
 * Vazby:  - Využívá proceduru dbo.p_update_database_version (ze sysinit_reset.sql).
 *         - Při selhání přechodu na cílovou verzi vyvolá fatální chybu
 *           RAISERROR(..., 20, 1) WITH LOG, která odpojí relaci a zastaví
 *           provádění všech navazujících dávek v SSMS.
 * ============================================================================= */

SET XACT_ABORT ON;
SET ANSI_WARNINGS ON;
SET NOCOUNT OFF;
GO

-- =============================================================================
-- Začátek transakce změnových bloků pro říjen 2026 (2610)
-- =============================================================================
BEGIN TRAN;
GO

-- -----------------------------------------------------------------------------
-- Verze 26.10.20.0: Zavedení systému upgradů, sjednocení verze a service_logbook
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
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

	EXEC dbo.p_update_database_version
		@version = '26.10.20.0',
		@script_name = 'changes_2610.sql',
		@content = 'Inicializace systému upgradů databáze a nastavení výchozí verze 26.10.20.0';
END
GO

-- -----------------------------------------------------------------------------
-- Verze 26.10.29.0: Reorganizace organization / organization_licence
--                   a user_account / user_organization_access
-- -----------------------------------------------------------------------------
IF OBJECT_ID('system_constant', 'U') IS NOT NULL AND EXISTS (
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

	EXEC dbo.p_update_database_version
		@version = '26.10.29.0',
		@script_name = 'changes_2610.sql',
		@content = 'Reorganizace sloupců mezi organization_licence / organization a user_account / user_organization_access, zrušení organization_settings';

	COMMIT;
END
GO

-- =============================================================================
-- Bezpečnostní pojistka a kontrola provedení dávky changes_2610.sql
-- =============================================================================
IF @@TRANCOUNT > 0 ROLLBACK;
SET NOCOUNT ON;
GO

IF OBJECT_ID('system_constant', 'U') IS NOT NULL
BEGIN
	DECLARE @expected_version varchar(20) = '26.10.29.0';                      -- Cílová verze skriptu changes_2610.sql
	DECLARE @current_version varchar(20) = '';                                 -- Skutečná verze zjištěná v system_constant

	SELECT TOP 1 @current_version = ISNULL(database_version, '')
	FROM system_constant;

	IF @current_version = @expected_version
	BEGIN
		PRINT 'Dávka changes_2610.sql převedla databázi do verze ' + @expected_version + '.';
	END
	ELSE IF @current_version > @expected_version
	BEGIN
		PRINT 'Dávka changes_2610.sql neprovedla žádnou změnu.';
	END
	ELSE
	BEGIN
		DECLARE @err_msg varchar(800) = 'Dávka changes_2610.sql selhala! Očekávaná verze: '
			+ @expected_version + ', zjištěná verze: ' + @current_version + '. Provádění skriptu bylo přerušeno.';
		RAISERROR(@err_msg, 20, 1) WITH LOG;
	END
END
GO