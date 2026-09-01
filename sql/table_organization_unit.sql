-- =============================================================================
-- Tabulka: organization_unit
-- Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
-- =============================================================================

-- Kontrola a odstranění tabulky, pokud pochází ze starého systému (obsahuje guid)
IF EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_unit' AND colname='guid')
	EXECUTE dropni 'organization_unit';
GO

IF OBJECT_ID('organization_unit') IS NULL
CREATE TABLE organization_unit (
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
	builtin bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_organization_unit PRIMARY KEY (uuid)
);
GO

-- Indexy pro zajištění RAC architektury
EXEC sp_create_index 
	@tname = 'organization_unit', 
	@iname = 'uq_organization_unit_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_unit', 
	@iname = 'uq_organization_unit_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO
