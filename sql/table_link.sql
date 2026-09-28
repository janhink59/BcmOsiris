/* =============================================================================
 * Soubor: table_link.sql
 * Tabulka: link
 * Popis:   Univerzální transakční tabulka pro uživatelské vazby mezi záznamy.
 *          Tato tabulka nahrazuje dřívější "repo_link". Konkrétní smysl a typ
 *          vazby (např. 1:N, M:N) diktuje definiční tabulka "meta_link_def".
 * Vazby:   - link_def (UUID) ukazuje na definici vazby (meta_link_def.original)
 *          - from_object a to_object (UUID) ukazují na originály cílových záznamů.
 * ============================================================================= */

IF OBJECT_ID('link') IS NULL
CREATE TABLE link(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu vazby (organizace)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor vazby
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, H) - 'L' (jazyková) zde nedává smysl
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',         -- Ponecháno pro kompatibilitu s RAC, ačkoliv se nepoužije k překladu
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
	-- Datové atributy vazby
	-- -------------------------------------------------------------------------
	link_def uuid NOT NULL,                            -- Odkaz na definici vazby (meta_link_def.original)
	from_object uuid NOT NULL,                         -- UUID originálu zdrojového objektu
	to_object uuid NOT NULL,                           -- UUID originálu cílového objektu
	
	-- Metriky a vlastnosti uplatněné přímo na konkrétní instanci vazby
	link_weight decimal(16,4) NULL,                    -- Kvantitativní hodnota (např. váha rizika nebo priorita vazby)
	note varchar(max) NOT NULL DEFAULT '',             -- Umožňuje tenantovi okomentovat si důvod propojení
	
	-- -------------------------------------------------------------------------
	-- Systémová příznaková data
	-- -------------------------------------------------------------------------
	is_derived bit NOT NULL DEFAULT 0,                 -- 1 = Vazba vznikla automatickým výpočtem či dědičností, 0 = vytvořil ji člověk

	CONSTRAINT pk_link PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti vazby (Active) pro daného vlastníka a konkrétní definici
-- U této tabulky garantujeme, že jeden tenant nemůže vytvořit dvě naprosto stejné vazby stejného typu
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_active_definition', 
	@colnames = 'object_owner, link_def, from_object, to_object', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění původního logického omezení pro originál (pro vrepo views)
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_active_original', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Zásadní indexy pro klientské dotazy (JOINy na from_object a to_object)
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