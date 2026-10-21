/* =============================================================================
 * Soubor: table_meta_class.sql
 * Verze: 2026-10-21 14:25
 * Tabulka: meta_class
 * Popis:   Logické třídy (entity) systému. Slouží jako nadstavba nad 
 *          fyzickými objekty (meta_object). Definuje konkrétní třídy 
 *          v rámci vzoru Single Table Inheritance (STI) a jejich chování.
 * Vazby:   - storage_object (UUID) ukazuje na meta_object (fyzická tabulka).
 *          - ancestor_class (UUID) ukazuje na jinou meta_class (dědičnost logiky i sloupců).
 *          - Plněno automaticky procedurou p_fix_meta_column a importem p_xlsx_meta_object.
 * Změny:   - Přejmenováno parent_object na storage_object.
 *          - Textové vlastnosti změněny na NULLable pro podporu dědičnosti.
 *          - Přidán sloupec import_origin pro evidenci původu záznamu z importu (Měkký audit).
 *          - 2026-10-18 17:15: Přidán sloupec editor_note pro sémantický kontext AI překladů
 *            a sloupce draft_author a approval_note pro schvalovací cyklus (SSC).
 *          - 2026-10-21 14:25: Sloupec iconname nahrazen sjednoceným sloupcem
 *            svg_icon varchar(max) NULL (včetně idempotentní migrace a odstranění iconname).
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
	editor_note varchar(max) NULL,                     -- Sémantický kontext pro překladatele a AI (nepřekládá se)
	
	-- Uživatelské rozhraní
	svg_icon varchar(max) NULL,                        -- Vektorová ikona SVG pro navigaci a seznamy (NULL = dědí se)
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
EXEC p_create_missing_column 'meta_class', 'editor_note', 'varchar(max) NULL';
EXEC p_create_missing_column 'meta_class', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_class', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'meta_class', 'svg_icon', 'varchar(max) NULL';
GO

-- Idempotentní migrace a odstranění zastaralého sloupce iconname
IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_class' AND colname = 'iconname')
BEGIN
	EXEC('UPDATE meta_class SET svg_icon = iconname WHERE svg_icon IS NULL AND iconname IS NOT NULL AND iconname <> ''''');
	EXEC sp_drop_column 'meta_class', 'iconname';
END
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