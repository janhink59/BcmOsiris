/* =============================================================================
 * Soubor: table_meta_column.sql
 * Tabulka: meta_column
 * Popis:   Uchovává metadata sloupců/proměnných v databázi a aplikacích.
 * Změna:   Zcela odstraněny check-constrainty pro ancestor (kontrola zacyklení 
 *          proběhne spolehlivěji na aplikační vrstvě nebo přes trigger).
 * ============================================================================= */

-- 1. Idempotentní odstranění případného původního i dočasného constraintu
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'chk_meta_columns_ancestor')
BEGIN
	execute dropni 'meta_column'
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
	parent_object uuid NOT NULL,
	parent_order int NOT NULL DEFAULT 0,
	sort_code varchar(20) NULL,
	column_name varchar(80) NOT NULL,
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
	
	ancestor uuid NULL,

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,
	is_protected bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_meta_columns PRIMARY KEY (uuid)
);
GO