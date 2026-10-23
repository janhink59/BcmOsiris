/* =============================================================================
 * Verze: 2026-10-23 15:15
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