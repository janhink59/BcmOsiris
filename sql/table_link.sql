/* =============================================================================
 * Verze: 2026-10-30 23:35
 * Soubor: table_link.sql
 * Tabulka: link
 * Popis:   Univerzální transakční tabulka pro uživatelské i zděděné vazby mezi
 *          záznamy. Konkrétní smysl a typ vazby (např. 1:N, M:N, leaf_only)
 *          diktuje definiční tabulka "meta_link_def".
 * Vazby:   - link_def (UUID) ukazuje na definici vazby (meta_link_def.original).
 *          - from_object a to_object (UUID) ukazují na originály cílových záznamů.
 *          - ancestor_link (UUID) ukazuje na link.original nadřízené vazby,
 *            ze které tato vazba vznikla děděním po hierarchii (0x00 = přímá vazba).
 * Změny:   - 2026-10-30 23:35: Přidán sloupec ancestor_link uuid NOT NULL DEFAULT 0x00,
 *            zařazen do unikátního indexu uq_link_active_definition a vytvořen
 *            index ix_link_ancestor_link pro rychlé přepočty děděných vazeb.
 *          - 2026-10-23 11:00: Doplněny SSC sloupce draft_author, approval_note,
 *            import_origin a unikátní index uq_link_draft.
 * ============================================================================= */

IF OBJECT_ID('link') IS NULL
CREATE TABLE link(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu vazby (organizace)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor vazby
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, D, H)
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení (A, D, F, R)
	draft_author uuid NOT NULL DEFAULT 0x00,           -- Autor konceptu (user_account.original)
	approval_note varchar(max) NOT NULL DEFAULT '',    -- Poznámka schvalovatele / důvod vrácení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',         -- Ponecháno pro kompatibilitu s RAC
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
	-- Datové atributy vazby
	-- -------------------------------------------------------------------------
	link_def uuid NOT NULL,                            -- Odkaz na definici vazby (meta_link_def.original)
	from_object uuid NOT NULL,                         -- UUID originálu zdrojového objektu
	to_object uuid NOT NULL,                           -- UUID originálu cílového objektu
	ancestor_link uuid NOT NULL DEFAULT 0x00,          -- UUID zdrojové vazby v link při dědění (0x00 = ručně zadaná vazba)
	
	-- Metriky a vlastnosti uplatněné přímo na konkrétní instanci vazby
	link_weight decimal(16,4) NULL,                    -- Kvantitativní hodnota (např. váha rizika nebo priorita vazby)
	note varchar(max) NOT NULL DEFAULT '',             -- Umožňuje tenantovi okomentovat si důvod propojení
	
	-- -------------------------------------------------------------------------
	-- Systémová příznaková data
	-- -------------------------------------------------------------------------
	is_derived bit NOT NULL DEFAULT 0,                 -- 1 = Vazba vznikla děděním (ancestor_link <> 0x00), 0 = přímá vazba

	CONSTRAINT pk_link PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'link', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'link', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'link', 'ancestor_link', 'uuid NOT NULL DEFAULT 0x00';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------

-- Pokud existuje stará 4sloupcová verze indexu uq_link_active_definition (bez ancestor_link), nahradíme ji
IF EXISTS (
	SELECT 1 FROM sys.indexes WHERE name = 'uq_link_active_definition' AND object_id = OBJECT_ID('link')
) AND NOT EXISTS (
	SELECT 1 FROM v_sysindexcolumns WHERE table_name = 'link' AND index_name = 'uq_link_active_definition' AND column_name = 'ancestor_link'
)
BEGIN
	EXEC sp_drop_index 'link', 'uq_link_active_definition';
END
GO

-- Zajištění unikátnosti vazby (Active) včetně ancestor_link (umožňuje souběh dědění více cestami)
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_active_definition', 
	@colnames = 'object_owner, link_def, from_object, to_object, ancestor_link', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění původního logického omezení pro originál
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_active_original', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti konceptu (Draft)
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Zásadní indexy pro klientské dotazy a správu odvozených vazeb
-- -----------------------------------------------------------------------------

EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'ix_link_from_object', 
	@colnames = 'from_object, object_owner, link_def', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'ix_link_to_object', 
	@colnames = 'to_object, object_owner, link_def', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'ix_link_ancestor_link', 
	@colnames = 'ancestor_link, object_owner', 
	@uni = '', 
	@options = 'WHERE ancestor_link <> 0x00';
GO