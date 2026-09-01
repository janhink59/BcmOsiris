-- =============================================================================
-- Tabulka: organization_licence
-- Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
-- =============================================================================

-- Kontrola a odstranění tabulky, pokud obsahuje staré sloupce (admin_initial_password, admin_sex, guid)
-- nebo naopak neobsahuje nově přidané byznys sloupce (licence_state, licence_level)
IF EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='admin_initial_password')
	OR EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='admin_sex')
	OR EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='guid')
	OR NOT EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_licence' AND colname='licence_state')
	EXECUTE dropni 'organization_licence';
GO

IF OBJECT_ID('organization_licence') IS NULL
CREATE TABLE organization_licence (
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
	-- Identifikace stavu životního cyklu licence (DRAFT, APPROVED, PROCESSED, REJECTED)
	licence_state varchar(20) NOT NULL DEFAULT 'DRAFT',
	
	-- Úroveň licence, která bude následně přiřazena cílové organizaci
	licence_level tinyint NOT NULL DEFAULT 0,
	
	organization_uuid uuid NOT NULL DEFAULT 0x00,
	server_licence uuid NOT NULL DEFAULT 0x00,
	organization_name varchar(200) NOT NULL DEFAULT '',
	login_domain varchar(200) NOT NULL DEFAULT '',
	organization_note varchar(max) NOT NULL DEFAULT '',
	authorization_code uuid NOT NULL DEFAULT 0x00,
	activation_date date NULL,
	
	ip_address varchar(200) NOT NULL DEFAULT '',
	preferred_language varchar(2) NOT NULL DEFAULT 'cs',
	admin_login varchar(200) NOT NULL DEFAULT '',
	admin_first_name varchar(200) NOT NULL DEFAULT '',
	admin_last_name varchar(200) NOT NULL DEFAULT '',
	admin_email varchar(200) NOT NULL DEFAULT '',
	digital_signature varbinary(20) NULL,

	CONSTRAINT pk_organization_licence PRIMARY KEY (uuid)
);
GO

-- Indexy pro zajištění RAC architektury
EXEC sp_create_index 
	@tname = 'organization_licence', 
	@iname = 'uq_organization_licence_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_licence', 
	@iname = 'uq_organization_licence_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO
