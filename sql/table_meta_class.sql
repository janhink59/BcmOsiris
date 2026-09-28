/* =============================================================================
 * Soubor: table_meta_class.sql
 * Tabulka: meta_class
 * Popis:   Logické třídy (entity) systému. Slouží jako nadstavba nad 
 *          fyzickými objekty (meta_object). Definuje konkrétní třídy 
 *          v rámci vzoru Single Table Inheritance (STI) a jejich chování,
 *          přístupová práva a prezentační vlastnosti.
 * Vazby:   - parent_object (UUID) ukazuje na meta_object (fyzická tabulka).
 *          - ancestor_class (UUID) ukazuje na jinou meta_class (dědičnost logiky).
 * ============================================================================= */

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
	class_name varchar(80) NOT NULL,                   -- Interní identifikátor třídy (např. 'server', 'employee')
	parent_object uuid NOT NULL,                       -- Vazba na fyzickou tabulku z meta_object
	ancestor_class uuid NULL,                          -- Vazba na předka pro dědičnost vlastností (meta_class.original)
	
	-- Prezentační texty (přeložitelné v overridu typu 'L')
	caption varchar(200) NOT NULL DEFAULT '',
	caption_plural varchar(200) NOT NULL DEFAULT '',
	description varchar(max) NOT NULL DEFAULT '',
	helptext varchar(max) NOT NULL DEFAULT '',
	
	-- Uživatelské rozhraní
	iconname varchar(250) NOT NULL DEFAULT '',         -- Název ikony pro navigaci/seznamy
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