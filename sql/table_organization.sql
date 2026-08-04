-- =============================================================================
-- Tabulka: organization (Organizace)
-- Popis:	Základní kámen multi-tenantní architektury CRMM. Definuje jednotlivé 
--			klienty (tenanty) v systému. Vlastníkem (object_owner) systémového 
--			záznamu je 0x00, ostatní záznamy organizací vlastní samy sebe.
-- Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
-- =============================================================================

DROP TABLE IF EXISTS organization;
GO

CREATE TABLE organization (
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
	-- Společné textové vlastnosti (vždy varchar s plnou podporou UTF-8)
	-- -------------------------------------------------------------------------
	caption varchar(200) NOT NULL DEFAULT '',
	shortname varchar(40) NOT NULL DEFAULT '',
	external_code varchar(200) NOT NULL DEFAULT '',
	instance_class_name varchar(80) NOT NULL DEFAULT '',
	description_text varchar(max) NOT NULL DEFAULT '',
	help_text varchar(max) NOT NULL DEFAULT '',
	
	-- -------------------------------------------------------------------------
	-- Auditní stopy (výhradně uuid odkazy bez denormalizovaných jmen)
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické byznys sloupce organizace
	-- -------------------------------------------------------------------------
	note varchar(max) NOT NULL DEFAULT '',
	login_disabled bit NOT NULL DEFAULT 0,
	
	-- Detekce domovského SSO tenanta v multi-tenantním prostředí (pro IdP)
	login_domain varchar(200) NOT NULL DEFAULT '',		
	
	licence_level tinyint NOT NULL DEFAULT 0,
	register_id bigint NULL DEFAULT 0,
	tax_id varchar(40) NOT NULL DEFAULT '',
	invoice_info varchar(max) NOT NULL DEFAULT '',
	
	-- Adresní údaje
	address_name varchar(100) NOT NULL DEFAULT '',
	address_street varchar(100) NOT NULL DEFAULT '',
	address_city varchar(100) NOT NULL DEFAULT '',
	address_zip varchar(10) NOT NULL DEFAULT '',
	address_state varchar(40) NOT NULL DEFAULT '',
	www_address varchar(200) NOT NULL DEFAULT '',

	-- Média a logotyp
	logo_data varbinary(max) NULL,
	logo_filename varchar(255) NOT NULL DEFAULT '',
	logo_mime_type varchar(100) NOT NULL DEFAULT '',

	CONSTRAINT pk_organization PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka a originál
CREATE UNIQUE INDEX uq_organization_active 
	ON organization(original, object_owner) 
	WHERE record_type = 'A' AND removed = 0;
GO

-- Zajištění unikátnosti jazykových verzí (Language) pro daného vlastníka a originál
CREATE UNIQUE INDEX uq_organization_language 
	ON organization(original, object_owner, language) 
	WHERE record_type = 'L' AND removed = 0;
GO

-- -----------------------------------------------------------------------------
-- Inicializační systémový záznam (0x00)
-- -----------------------------------------------------------------------------
INSERT INTO organization (
	uuid,
	object_owner,
	original,
	record_type,
	approval_status,
	caption,
	shortname,
	description_text
) VALUES (
	0x00,
	0x00,
	0x00,
	'A',
	'A',
	'System',
	'SYS',
	'Systémová master organizace.'
);
GO