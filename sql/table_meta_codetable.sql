/* =============================================================================
 * Soubor: table_meta_codetable.sql
 * Tabulka: meta_codetable
 * Popis:   Univerzální tabulka pro definici uživatelských a systémových číselníků.
 *          Tato data primárně krmí <select> prvky v uživatelském rozhraní, 
 *          pokud se k danému výčtu nehodí vytvářet samostatnou fyzickou entitu.
 *          Nahrazuje původní tabulky repo_codetable a částečně repo_object.
 * ============================================================================= */

IF OBJECT_ID('meta_codetable') IS NULL
CREATE TABLE meta_codetable(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu (0x00 = systémový výčet)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor konkrétní hodnoty
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- 'A' = aktuálně schválený, 'L' = jazyková verze
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stavy schvalování (SSC)
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
	-- Specifické atributy číselníku
	-- -------------------------------------------------------------------------
	codetable_name varchar(80) NOT NULL,               -- Identifikátor číselníku (vazba z meta_column např. 'cm_category')
	value_code varchar(80) NOT NULL,                   -- Interní ukládaná hodnota (atribut value="" v option tagu)
	
	-- Prezentační texty (přeložitelné přes 'L' overridy)
	caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný text v roletce (text uvnitř option tagu)
	description varchar(max) NOT NULL DEFAULT '',      -- Podrobnější popis položky
	helptext varchar(max) NOT NULL DEFAULT '',         -- Nápověda (např. pro zobrazení do title/tooltipu nad volbou)
	
	-- Uživatelské rozhraní
	sort_code varchar(20) NOT NULL DEFAULT '',         -- Pořadí položek ve výpisu
	iconname varchar(250) NOT NULL DEFAULT '',         -- Volitelná ikonka pro UI
	color_code varchar(20) NOT NULL DEFAULT '',        -- Barva nebo CSS třída pro zvýraznění záznamu v tabulkách

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur (limity klientského overridu)
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,                   -- 1 = Zcela zakazuje tenantům vytvořit vlastní override hodnoty
	is_protected bit NOT NULL DEFAULT 0,               -- 1 = Omezuje možnosti tenantů upravovat byznys logiku volby

	CONSTRAINT pk_meta_codetable PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury a rychlého čtení číselníků
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka a originál
EXEC sp_create_index 
	@tname = 'meta_codetable', 
	@iname = 'uq_meta_codetable_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti jazykových verzí (Language)
EXEC sp_create_index 
	@tname = 'meta_codetable', 
	@iname = 'uq_meta_codetable_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- Index optimalizovaný přímo pro načítání obsahu <select> prvků na frontendu
EXEC sp_create_index 
	@tname = 'meta_codetable', 
	@iname = 'ix_meta_codetable_name', 
	@colnames = 'codetable_name, sort_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO