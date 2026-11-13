/* =============================================================================
 * Verze: 2026-11-13 18:10
 * Soubor: table_session_import.sql
 * Tabulky: session_import_parameter, session_import_table,
 *          session_import_column, session_import_data
 * Procedura: p_csv_clear_session_import
 * Popis:   Pracovní staging tabulky vázané na relaci uživatele (wwwsession)
 *          pro Fázi 1 dvoufázového importu víceblokových CSV/TSV balíčků.
 *          Neobsahují trvalá uživatelská data, proto se při sestavení databáze
 *          vždy přegenerují a využívají plnou kaskádovou referenční integritu
 *          (ON DELETE CASCADE).
 * Vazby:   - wwwsession -> session_import_parameter
 *          - wwwsession -> session_import_table -> session_import_column -> session_import_data
 *          - Plněno z PHP třídy abstract_csv_package a čteno procedurami p_csv_import_*.
 * Změny:
 * - 2026-11-13 18:10: Doplněna registrace tříd a sloupců do sysinit_class
 *   a sysinit_column.
 * ============================================================================= */

EXECUTE dropni 'p_csv_clear_session_import', 'P';
EXECUTE dropni 'session_import_data'
EXECUTE dropni 'session_import_column'
EXECUTE dropni 'session_import_table'
EXECUTE dropni 'session_import_parameter'
GO

-- 1. Hlavičkové a filtrační parametry načteného CSV/TSV balíčku
CREATE TABLE session_import_parameter (
	wwwsession varchar(50) NOT NULL,                                           -- Identifikátor relace prohlížeče
	param_order int NOT NULL DEFAULT 0,                                        -- Pořadí parametru v souboru
	parameter_code varchar(80) NOT NULL,                                       -- Kód parametru (např. package_code, verify_data, signature)
	parameter_value varchar(max) NOT NULL DEFAULT '',                          -- Hodnota parametru

	CONSTRAINT pk_session_import_parameter PRIMARY KEY (wwwsession, parameter_code),
	CONSTRAINT fk_session_import_param_sess FOREIGN KEY (wwwsession)
		REFERENCES wwwsession (wwwsession) ON DELETE CASCADE
);
GO

-- 2. Seznam tabulek (bloků dat) nalezených v CSV/TSV souboru
CREATE TABLE session_import_table (
	wwwsession varchar(50) NOT NULL,                                           -- Identifikátor relace prohlížeče
	table_id int NOT NULL,                                                     -- Pořadové číslo bloku tabulky v importu (1, 2, ...)
	table_name varchar(128) NOT NULL,                                          -- Název tabulky z řádku před hlavičkou sloupců
	row_count int NOT NULL DEFAULT 0,                                          -- Počet načtených datových řádků v bloku

	CONSTRAINT pk_session_import_table PRIMARY KEY (wwwsession, table_id),
	CONSTRAINT uq_session_import_table_name UNIQUE (wwwsession, table_name),
	CONSTRAINT fk_session_import_table_sess FOREIGN KEY (wwwsession)
		REFERENCES wwwsession (wwwsession) ON DELETE CASCADE
);
GO

-- 3. Seznam sloupců jednotlivých tabulek načtených z CSV/TSV souboru
CREATE TABLE session_import_column (
	wwwsession varchar(50) NOT NULL,                                           -- Identifikátor relace prohlížeče
	column_id int NOT NULL,                                                    -- Globální pořadí sloupce v importu (zvyšuje se o 1)
	table_id int NOT NULL,                                                     -- Vazba na session_import_table.table_id
	column_name varchar(128) NOT NULL,                                         -- Technický název sloupce z CSV hlavičky

	CONSTRAINT pk_session_import_column PRIMARY KEY (wwwsession, column_id),
	CONSTRAINT uq_session_import_column_name UNIQUE (wwwsession, table_id, column_name),
	CONSTRAINT fk_session_import_col_table FOREIGN KEY (wwwsession, table_id)
		REFERENCES session_import_table (wwwsession, table_id) ON DELETE CASCADE
);
GO

-- 4. Hodnoty neprázdných buněk načtených z CSV/TSV souboru
CREATE TABLE session_import_data (
	wwwsession varchar(50) NOT NULL,                                           -- Identifikátor relace prohlížeče
	row_id int NOT NULL,                                                       -- Pořadové číslo datového řádku v rámci importu
	column_id int NOT NULL,                                                    -- Vazba na session_import_column.column_id
	cell_value varchar(max) NOT NULL DEFAULT '',                               -- Textová hodnota buňky (bez znaků CR)

	CONSTRAINT pk_session_import_data PRIMARY KEY (wwwsession, row_id, column_id),
	CONSTRAINT fk_session_import_data_col FOREIGN KEY (wwwsession, column_id)
		REFERENCES session_import_column (wwwsession, column_id) ON DELETE CASCADE
);
GO

-- Pomocný index pro rychlé skládání dat podle sloupce a řádku v SQL procedurách
EXEC sp_create_index
	@tname = 'session_import_data',
	@iname = 'ix_session_import_data_col_row',
	@colnames = 'wwwsession, column_id, row_id',
	@uni = '';
GO

/* =============================================================================
 * Procedura: p_csv_clear_session_import
 * Účel: Vymaže všechna rozpracovaná data CSV/TSV importu pro aktuální relaci
 *       (podle @@SPID v dbsession). Díky ON DELETE CASCADE na cizích klíčích
 *       odstraní smazání ze session_import_table automaticky i sloupce a buňky.
 * ============================================================================= */
CREATE PROCEDURE p_csv_clear_session_import
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @sess varchar(50);
	SELECT @sess = wwwsession FROM dbsession WHERE spid = @@SPID;

	IF @sess IS NOT NULL
	BEGIN
		DELETE FROM session_import_parameter WHERE wwwsession = @sess;
		DELETE FROM session_import_table WHERE wwwsession = @sess;
	END
END
GO

-- -----------------------------------------------------------------------------
-- Registrace tříd a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name IN (
		'session_import_column', 'session_import_data',
		'session_import_parameter', 'session_import_table'
	);

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('session_import_column','cs','T','session_import_column','Sloupec CSV importu','Sloupce CSV importu','Dočasná evidence hlaviček sloupců načtených v 1. fázi importu CSV balíčku.','Technická staging tabulka vázaná na webovou relaci.'),
	('session_import_data','cs','T','session_import_data','Buňka dat CSV importu','Data CSV importu','Dočasné úložiště hodnot jednotlivých buněk načtených v 1. fázi importu CSV balíčku.','Technická staging tabulka vázaná na webovou relaci.'),
	('session_import_parameter','cs','T','session_import_parameter','Parametr CSV importu','Parametry CSV importu','Dočasné úložiště řídicích a podpisových parametrů načteného CSV balíčku.','Technická staging tabulka vázaná na webovou relaci.'),
	('session_import_table','cs','T','session_import_table','Tabulka CSV importu','Tabulky CSV importu','Dočasný seznam tabulkových bloků načtených v 1. fázi importu CSV balíčku.','Technická staging tabulka vázaná na webovou relaci.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('session_import_column','en','CSV Import Column','CSV Import Columns','Temporary registry of column headers loaded during Phase 1 of CSV package import.','Technical staging table bound to the web session.'),
	('session_import_data','en','CSV Import Data Cell','CSV Import Data','Temporary storage of cell values loaded during Phase 1 of CSV package import.','Technical staging table bound to the web session.'),
	('session_import_parameter','en','CSV Import Parameter','CSV Import Parameters','Temporary storage of control and signature parameters of a loaded CSV package.','Technical staging table bound to the web session.'),
	('session_import_table','en','CSV Import Table','CSV Import Tables','Temporary list of table blocks loaded during Phase 1 of CSV package import.','Technical staging table bound to the web session.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name IN (
		'session_import_column', 'session_import_data',
		'session_import_parameter', 'session_import_table'
	);

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('session_import_column','column_id','cs','Pořadí sloupce v CSV (column_id)','Pořadové číslo sloupce v bloku','ID sloupce','Pořadové číslo sloupce v načtené tabulce CSV balíčku.'),
	('session_import_data','cell_value','cs','Hodnota buňky (cell_value)','Načtená hodnota buňky z CSV','Hodnota buňky','Textová hodnota buňky načtená v 1. fázi importu CSV balíčku.'),
	('session_import_data','row_id','cs','Číslo řádku v CSV (row_id)','Pořadové číslo datového řádku','Č. řádku','Pořadové číslo řádku v rámci tabulkového bloku CSV balíčku.'),
	('session_import_parameter','param_order','cs','Pořadí parametru (param_order)','Pořadové číslo parametru','Poř. param.','Pořadové číslo řídicího parametru při načtení CSV balíčku.'),
	('session_import_parameter','parameter_code','cs','Kód parametru balíčku (parameter_code)','Název parametru CSV balíčku','Parametr','Identifikátor řídicího parametru v hlavičce CSV balíčku.'),
	('session_import_parameter','parameter_value','cs','Hodnota parametru balíčku (parameter_value)','Hodnota parametru CSV balíčku','Hodnota param.','Textová hodnota řídicího parametru v hlavičce CSV balíčku.'),
	('session_import_table','row_count','cs','Počet řádků (row_count)','Počet načtených datových řádků','Počet řádků','Celkový počet datových řádků načtených v daném bloku tabulky.'),
	('session_import_table','table_id','cs','Pořadové ID tabulky v CSV (table_id)','Pořadové číslo tabulky v balíčku','ID tabulky','Interní pořadové číslo tabulkového bloku v rámci relace CSV importu.'),
	('session_import_column','column_id','en','CSV Column ID (column_id)','Column Sequential Number in Block','Column ID','Sequential column number in the loaded CSV package table.'),
	('session_import_data','cell_value','en','Cell Value (cell_value)','Loaded CSV Cell Value','Cell Value','String value of a cell loaded during Phase 1 of CSV package import.'),
	('session_import_data','row_id','en','CSV Row ID (row_id)','Sequential Data Row Number','Row ID','Sequential row number within a table block of the CSV package.'),
	('session_import_parameter','param_order','en','Parameter Order (param_order)','Parameter Sequential Number','Param. Order','Sequential number of a control parameter when loading a CSV package.'),
	('session_import_parameter','parameter_code','en','Package Parameter Code (parameter_code)','CSV Package Parameter Name','Parameter','Identifier of a control parameter in the CSV package header.'),
	('session_import_parameter','parameter_value','en','Package Parameter Value (parameter_value)','CSV Package Parameter Value','Param. Value','Value of a control parameter in the CSV package header.'),
	('session_import_table','row_count','en','Row Count (row_count)','Loaded Data Row Count','Row Count','Total number of data rows loaded in the given table block.'),
	('session_import_table','table_id','en','CSV Table ID (table_id)','Table Sequential Number in Package','Table ID','Internal sequential number of a table block within a CSV import session.');
END
GO