/* =============================================================================
 * Verze: 2026-10-25 08:45
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
 * - Opakované spuštění skriptu nebo spuštění staršího skriptu nad novější
 *   databází neprovede žádné změny a nezpůsobí žádnou škodu.
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

DECLARE @expected_version varchar(20) = '26.10.20.0';                          -- Požadovaná cílová verze tohoto skriptu
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