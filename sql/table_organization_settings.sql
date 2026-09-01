-- =============================================================================
-- Tabulka: organization_settings
-- Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
-- =============================================================================

-- Kontrola a odstranění tabulky, pokud pochází ze starého systému (obsahuje guid)
IF EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_settings' AND colname='guid')
	EXECUTE dropni 'organization_settings';
GO

IF OBJECT_ID('organization_settings') IS NULL
CREATE TABLE organization_settings (
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
	-- Společné textové vlastnosti
	-- -------------------------------------------------------------------------
	caption varchar(200) NOT NULL DEFAULT '',
	shortname varchar(40) NOT NULL DEFAULT '',
	external_code varchar(200) NOT NULL DEFAULT '',
	instance_class_name varchar(80) NOT NULL DEFAULT '',
	description_text varchar(max) NOT NULL DEFAULT '',
	help_text varchar(max) NOT NULL DEFAULT '',
	
	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické sloupce
	-- -------------------------------------------------------------------------
	preferred_language varchar(2) NOT NULL DEFAULT 'cs',
	currency_unit varchar(40) NOT NULL DEFAULT '€',
	currency_digits int NOT NULL DEFAULT 2,
	currency_before bit NOT NULL DEFAULT 1,
	format_date varchar(100) NOT NULL DEFAULT 'dd.MM.yyyy',
	format_time varchar(100) NOT NULL DEFAULT 'HH:mm:ss',
	time_zone varchar(100) NOT NULL DEFAULT 'Europe/Prague',
	format_name varchar(200) NOT NULL DEFAULT 'first_name last_name',
	thousand_separator varchar(1) NOT NULL DEFAULT '.',
	decimal_separator varchar(1) NOT NULL DEFAULT ',',
	export_encoding varchar(10) NOT NULL DEFAULT 'UTF-8',
	export_delimiter varchar(1) NOT NULL DEFAULT ',',
	default_login_role varchar(200) NOT NULL DEFAULT 'user',
	default_list_size int NOT NULL DEFAULT 15,
	list_size_for_two_panels int NOT NULL DEFAULT 5,
	displayed_chars_in_list int NOT NULL DEFAULT 50,
	displayed_chars_in_detail int NOT NULL DEFAULT 50,

	CONSTRAINT pk_organization_settings PRIMARY KEY (uuid)
);
GO

-- Indexy pro zajištění RAC architektury
EXEC sp_create_index 
	@tname = 'organization_settings', 
	@iname = 'uq_organization_settings_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_settings', 
	@iname = 'uq_organization_settings_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO