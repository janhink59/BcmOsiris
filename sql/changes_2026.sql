/* =============================================================================
 * Verze: 2026-10-29 22:00
 * Soubor: changes_2026.sql
 * Účel:   Jednorázové změny struktury a dat databáze v kalendářním roce 2026.
 *         Spouští se samostatně PŘED hlavním slepeným skriptem BcmOsirisDb.sql.
 *
 * Pravidla pro údržbu a přidávání změn:
 * - Verze databáze (system_constant.database_version) má formát 'RR.MM.DD.N'
 *   (např. '26.10.20.0', kde poslední číslice N je intradenní pořadí změny).
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
 * - 2026-10-29 22:00 (26.10.29.0): Odstraněn statický INSERT do organization_licence
 *   způsobující chybu kompilace nad starší verzí tabulky bez sloupce login_disabled
 *   (vložení systémové licence přesunuto do fillup_organization_licence.sql).
 * - 2026-10-29 15:30 (26.10.29.0): Narovnání sloupců mezi organization_licence
 *   a organization (přesun licence_level a login_disabled do licence, doplnění
 *   nastavení organizace a CRMM limitů do organization, zrušení tabulky
 *   organization_settings) a přesun organizačně závislých sloupců z user_account
 *   do user_organization_access.
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

	-- 1. Zajištění existence tabulky service_logbook pro evidenci běhu skriptů a importů
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

	-- 2. Výměna DEFAULT constraintu na sloupci database_version v tabulce system_constant
	EXEC sp_drop_default 'system_constant', 'database_version';

	ALTER TABLE system_constant
		ADD CONSTRAINT df_system_constant_db_version DEFAULT '26.10.20.0' FOR database_version;

	-- 3. Posunutí verze databáze na výchozí bod 26.10.20.0
	UPDATE system_constant
	SET database_version = '26.10.20.0',
		date_modified = GETDATE();

	-- 4. Zápis o provedeném upgradu do provozního deníku service_logbook
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

	-- 1. Doplnění nových sloupců do organization_licence a migrace z organization
	EXEC p_create_missing_column 'organization_licence', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
	EXEC p_create_missing_column 'organization_licence', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
	EXEC p_create_missing_column 'organization_licence', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
	EXEC p_create_missing_column 'organization_licence', 'import_origin', 'varchar(255) NULL';
	EXEC p_create_missing_column 'organization_licence', 'login_disabled', 'bit NOT NULL DEFAULT 0';

	-- Pokud byl v organization_licence příznak is_developer = 1, povýšíme licence_level na 255 (Developer)
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

	-- Přenos login_disabled z tabulky organization do organization_licence
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

	-- Odstranění licence_level a login_disabled z tabulky organization
	EXEC sp_drop_column 'organization', 'licence_level';
	EXEC sp_drop_column 'organization', 'login_disabled';

	-- 2. Doplnění regionálních a CRMM výpočtových parametrů přímo do tabulky organization
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

	-- Odstranění opuštěné tabulky organization_settings
	EXEC dropni 'organization_settings';

	-- 3. Přesun organizačně závislých atributů z user_account do user_organization_access
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

	-- 4. Aktualizace výchozí verze databáze v system_constant a zápis do service_logbook
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

DECLARE @expected_version varchar(20) = '26.10.29.0';                          -- Požadovaná cílová verze tohoto skriptu
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