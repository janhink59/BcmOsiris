/* =============================================================================
 * Soubor: table_meta_link_def.sql
 * Tabulka: meta_link_def
 * Popis:   Definiční tabulka pro vazby mezi logickými třídami (meta_class).
 *          Nahrazuje původní hardcodované sloupce v repo_class a umožňuje 
 *          dynamicky řídit, jaké entity lze mezi sebou propojovat.
 * Vazby:   - from_class a to_class (UUID) ukazují na meta_class.original.
 * ============================================================================= */

IF OBJECT_ID('meta_link_def') IS NULL
CREATE TABLE meta_link_def(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu (0x00 pro systémové definice vazeb)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor definice vazby napříč overridy
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
	-- Specifické atributy definice vazby
	-- -------------------------------------------------------------------------
	link_code varchar(80) NOT NULL,                    -- Unikátní technický kód vazby (např. 'depends_on', 'located_in')
	from_class uuid NOT NULL,                          -- UUID zdrojové třídy (z meta_class.original)
	to_class uuid NOT NULL,                            -- UUID cílové třídy (z meta_class.original)
	
	-- Prezentační texty (přeložitelné)
	caption_forward varchar(200) NOT NULL DEFAULT '',  -- Název vazby z pohledu zdroje (např. "Podporuje")
	caption_backward varchar(200) NOT NULL DEFAULT '', -- Název vazby z pohledu cíle (např. "Je podporováno")
	description varchar(max) NOT NULL DEFAULT '',
	helptext varchar(max) NOT NULL DEFAULT '',
	
	-- Pravidla a omezení pro UI a aplikační logiku
	is_multiple bit NOT NULL DEFAULT 1,                -- 1 = Lze navázat více cílových objektů (1:N nebo M:N)
	is_mandatory bit NOT NULL DEFAULT 0,               -- 1 = Třída A musí mít tuto vazbu na třídu B vyplněnou
	leaf_only bit NOT NULL DEFAULT 0,                  -- 1 = Povoluje vazbu pouze na koncové uzly (is_leaf = 1 v cílové třídě)
	transfer_roles bit NOT NULL DEFAULT 0,             -- 1 = Přenáší editační oprávnění ze zdrojové třídy na cílovou
	link_weight_enabled bit NOT NULL DEFAULT 0,        -- 1 = Na samotné vazbě se bude udržovat metrika (např. zbytkové riziko nebo finanční váha)

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur (limity klientského overridu)
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,
	is_protected bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_meta_link_def PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury a rychlého hledání definic
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti jazykových verzí (Language)
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- Optimalizace pro vyhledávání dostupných vazeb pro konkrétní třídu
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'ix_meta_link_def_classes', 
	@colnames = 'from_class, to_class', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO