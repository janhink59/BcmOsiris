/* =============================================================================
 * Soubor: table_meta_column.sql
 * Verze: 2026-10-08
 * Tabulka: meta_column
 * Popis:   Uchovává metadata sloupců/proměnných v databázi a aplikacích.
 * Vazby:   Podklad pro entity_manager. Definuje vlastnosti formulářů a 
 *          rozšíření základních definic globálního slovníku (meta_class.original).
 *          Odkazuje na meta_codetable a meta_class pro datové <select> prvky.
 * Změny:   - Přesnější okomentování sémantiky vazeb (parent_class, ancestor, referenced_class).
 *          - Přejmenováno parent_object na parent_class (vazba na logickou třídu).
 *          - Přidán import_origin pro evidenci importů (Měkký audit).
 * ============================================================================= */

-- Idempotentní odstranění tabulky, pokud obsahuje starou vazbu na fyzický objekt
IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_column' AND colname = 'parent_object')
BEGIN
	EXECUTE dropni 'meta_column';
END
GO

IF OBJECT_ID('meta_column') IS NULL
CREATE TABLE meta_column(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,
	original uuid NOT NULL DEFAULT 0x00,
	record_type varchar(1) NOT NULL DEFAULT 'A',
	approval_status varchar(1) NOT NULL DEFAULT 'A',
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,                                       -- Původní textový autor/systém z importu (Měkký audit)

	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické atributy záznamu (Prezentační a aplikační logika)
	-- -------------------------------------------------------------------------
	parent_class uuid NOT NULL,                                            -- STRUKTURÁLNÍ VAZBA: Ukazuje na meta_class.original. Definuje, ke které logické třídě (entitě) tento sloupec fyzicky patří.
	parent_order int NOT NULL DEFAULT 0,
	sort_code varchar(20) NULL,
	column_name varchar(80) NOT NULL,
	
	-- Nastavení pro Master panel (Seznam záznamů)
	list_order int NULL,                                                   -- Pokud je vyplněno, sloupec se zobrazí v levém panelu v tomto pořadí
	
	caption varchar(200) NULL,
	caption_plural varchar(200) NULL,
	description varchar(max) NULL,
	label varchar(200) NULL,
	header varchar(200) NULL,
	helptext varchar(max) NULL,
	placeholder varchar(200) NULL,
	input_type varchar(20) NULL,
	input_width varchar(50) NULL,
	input_rows int NULL,
	max_length int NULL,
	css_class varchar(200) NULL,
	translate bit NULL,
	history bit NULL,
	is_html bit NULL,
	is_mandatory bit NULL,
	is_url bit NULL,
	is_computed bit NULL,
	show_empty bit NULL,
	hidden bit NULL,
	customizable bit NULL,
	
	ancestor uuid NULL,                                                    -- METADATOVÁ DĚDIČNOST: Ukazuje na meta_column.original (obvykle v sys_global_columns). Pokud je zdení hodnota NULL, převezme se z tohoto předka.
	
	-- Odkazy pro dynamické <select> prvky v entity_manager
	referenced_codetable varchar(80) NOT NULL DEFAULT '',                  -- DATOVÁ VAZBA: Název číselníku z meta_codetable, odkud se mají načítat hodnoty pro rozevírací seznamy.
	referenced_class uuid NULL,                                            -- DATOVÁ VAZBA: Ukazuje na meta_class.original. Používá se pro relační vazby cizích klíčů na jiné entity.

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,
	is_protected bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_meta_columns PRIMARY KEY (uuid)
);
GO