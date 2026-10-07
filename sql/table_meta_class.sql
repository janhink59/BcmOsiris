/* =============================================================================
 * Soubor: table_meta_class.sql
 * Verze: 2026-10-07 11:18
 * Tabulka: meta_class
 * Popis:   Logické třídy (entity) systému. Slouží jako nadstavba nad 
 *          fyzickými objekty (meta_object). Definuje konkrétní třídy 
 *          v rámci vzoru Single Table Inheritance (STI) a jejich chování.
 * Vazby:   - storage_object (UUID) ukazuje na meta_object (fyzická tabulka).
 *          - ancestor_class (UUID) ukazuje na jinou meta_class (dědičnost logiky i sloupců).
 * Změny:   - Přejmenováno parent_object na storage_object.
 *          - Textové vlastnosti změněny na NULLable pro podporu dědičnosti.
 *          - Přidán sloupec import_origin pro evidenci původu záznamu z importu (Měkký audit).
 * ============================================================================= */

if not exists (select * from v_syscolumns where tabname='meta_class' and colname='storage_object')
	execute dropni 'meta_class';

IF OBJECT_ID('meta_class') IS NULL
CREATE TABLE meta_class(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu (0x00 pro systémové třídy)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor třídy napříč overridy
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, L, H)
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,                   -- Původní textový autor/systém z importu (Měkký audit)

	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické atributy logické třídy
	-- -------------------------------------------------------------------------
	class_name varchar(80) NOT NULL,                   -- Interní identifikátor třídy (např. 'asset_class', 'employee')
	storage_object uuid NOT NULL,                      -- Vazba na fyzickou tabulku z meta_object
	ancestor_class uuid NULL,                          -- Vazba na předka pro dědičnost (meta_class.original). Plně nahrazuje původní column_ancestor z meta_object.
	
	-- Prezentační texty (přeložitelné v overridu typu 'L', NULL = dědí se)
	caption varchar(200) NULL,
	caption_plural varchar(200) NULL,
	description varchar(max) NULL,
	helptext varchar(max) NULL,
	
	-- Uživatelské rozhraní
	iconname varchar(250) NULL,                        -- Název ikony pro navigaci/seznamy
	sort_code varchar(20) NOT NULL DEFAULT '',         -- Výchozí třídění v hierarchii
	
	-- Oprávnění (Vazba na role v rámci tenanta)
	role_editor uuid NULL,                             -- Odkaz (UUID) na roli oprávněnou k editaci dat této třídy

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur (limity klientského overridu)
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,                   -- 1 = Zcela zakazuje tenantům vytvořit 'A' override třídy
	is_protected bit NOT NULL DEFAULT 0,               -- 1 = Tenant nesmí měnit technickou logiku (povolena jen vizuální úprava)

	CONSTRAINT pk_meta_class PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze (změnový příkaz)
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_class', 'import_origin', 'varchar(255) NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka
EXEC sp_create_index 
	@tname = 'meta_class', 
	@iname = 'uq_meta_class_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti jazykových verzí (Language)
EXEC sp_create_index 
	@tname = 'meta_class', 
	@iname = 'uq_meta_class_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO