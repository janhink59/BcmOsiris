/* =============================================================================
 * Verze: 2026-11-12 18:30
 * Soubor: table_meta_link_def.sql
 * Tabulka: meta_link_def
 * Popis:   Definiční tabulka pro vztahy mezi logickými třídami (meta_class).
 *          Podporuje samostatné záznamy pro zpětné vztahy (reverse_link_def),
 *          rozlišení směru (direction_type: 'P' = primární řídící, 'R' = zpětný,
 *          'S' = symetrický neorientovaný), registraci exkluzivních stromových
 *          vztahů parent_uuid (is_exclusive_parent = 1) a projekci nepřímých
 *          vztahů vygenerovaných z diagramů heterogenních sítí (is_derived = 1,
 *          diagram_uuid).
 * Vazby:   - from_class a to_class (UUID) ukazují na meta_class.original.
 *          - reverse_link_def (UUID) ukazuje na opačný vztah v meta_link_def.original.
 *          - diagram_uuid (UUID) ukazuje na link_diagram.original.
 * Změny:   - 2026-11-12 18:30: Doplněn unikátní filtrovaný index uq_meta_link_def_key
 *            nad složeným klíčem (object_owner, from_class, link_code).
 *          - 2026-11-11 21:30: Doplněny sloupce reverse_link_def, direction_type,
 *            is_exclusive_parent, is_derived a diagram_uuid.
 *          - 2026-10-23 11:00: Doplněny SSC sloupce draft_author, approval_note,
 *            import_origin a unikátní index uq_meta_link_def_draft.
 * ============================================================================= */

IF OBJECT_ID('meta_link_def') IS NULL
CREATE TABLE meta_link_def(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu (0x00 pro systémové definice vztahů)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor definice vztahu napříč overridy
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, L, D, H)
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení (A, D, F, R)
	draft_author uuid NOT NULL DEFAULT 0x00,           -- Autor konceptu (user_account.original)
	approval_note varchar(max) NOT NULL DEFAULT '',    -- Poznámka schvalovatele / důvod vrácení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,                   -- Původ záznamu z importu (Měkký audit)

	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické atributy definice vztahu
	-- -------------------------------------------------------------------------
	link_code varchar(80) NOT NULL,                    -- Unikátní technický kód vztahu v snake_case
	from_class uuid NOT NULL,                          -- UUID zdrojové třídy (z meta_class.original)
	to_class uuid NOT NULL,                            -- UUID cílové třídy (z meta_class.original)
	reverse_link_def uuid NULL,                        -- Odkaz na opačný (zpětný) vztah v meta_link_def.original
	direction_type varchar(1) NOT NULL DEFAULT 'P',    -- 'P' = Primární (řídící), 'R' = Zpětný (reverzní), 'S' = Symetrický (neorientovaný)
	
	-- Prezentační texty (přeložitelné)
	caption_forward varchar(200) NOT NULL DEFAULT '',  -- Název vztahu z pohledu from_class (např. "Podporuje")
	caption_backward varchar(200) NOT NULL DEFAULT '', -- Název opačného směru z pohledu to_class (např. "Je podporováno")
	description varchar(max) NOT NULL DEFAULT '',
	helptext varchar(max) NOT NULL DEFAULT '',
	
	-- Pravidla a omezení pro UI, stromovou hierarchii a projekci diagramů
	is_multiple bit NOT NULL DEFAULT 1,                -- 1 = K jednomu from_object lze navázat více to_object
	is_mandatory bit NOT NULL DEFAULT 0,               -- 1 = Třída from_class musí mít tento vztah vyplněný
	leaf_only bit NOT NULL DEFAULT 0,                  -- 1 = Povoluje vazbu pouze na koncové uzly (is_leaf = 1 v cílové třídě)
	is_exclusive_parent bit NOT NULL DEFAULT 0,        -- 1 = Vztah odpovídá exkluzivnímu sloupci parent_uuid na záznamu
	transfer_roles bit NOT NULL DEFAULT 0,             -- 1 = Přenáší editační oprávnění z primární třídy na cílovou
	link_weight_enabled bit NOT NULL DEFAULT 0,        -- 1 = Na samotné vazbě se udržuje číselná váha / metrika
	is_derived bit NOT NULL DEFAULT 0,                 -- 1 = Nepřímý vztah vygenerovaný z diagramu sítě (diagram_uuid)
	diagram_uuid uuid NULL,                            -- Odkaz na link_diagram.original u odvozeného vztahu

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur (limity klientského overridu)
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,
	is_protected bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_meta_link_def PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_link_def', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_link_def', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'meta_link_def', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'meta_link_def', 'reverse_link_def', 'uuid NULL';
EXEC p_create_missing_column 'meta_link_def', 'direction_type', 'varchar(1) NOT NULL DEFAULT ''P''';
EXEC p_create_missing_column 'meta_link_def', 'is_exclusive_parent', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'meta_link_def', 'is_derived', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'meta_link_def', 'diagram_uuid', 'uuid NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a rychlého hledání definic
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti složeného klíče (from_class, link_code) pro daného vlastníka
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_key', 
	@colnames = 'object_owner, from_class, link_code', 
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

-- Zajištění unikátnosti konceptu (Draft)
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

-- Optimalizace pro vyhledávání dostupných vztahů pro konkrétní třídu
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'ix_meta_link_def_classes', 
	@colnames = 'from_class, to_class', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

-- Optimalizace pro vyhledávání a přepočet odvozených vztahů podle diagramu
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'ix_meta_link_def_diagram', 
	@colnames = 'diagram_uuid, object_owner', 
	@uni = '', 
	@options = 'WHERE diagram_uuid IS NOT NULL';
GO