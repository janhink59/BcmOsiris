execute dropni 'meta_object'
GO

/*
    Tabulka meta_object slouží k uchování metadat objektů v databázi a aplikaci.
    Obsahuje informace o názvu a dalších atributech objektu určených pro lokalizaci, stejně jako informace o modulu, ke kterému objekt patří.
*/
if object_id('meta_object') is null
create table meta_object(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Sem se bude zapisovat UUID organizace
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
	-- Specifické atributy objektu
	-- -------------------------------------------------------------------------
	object_type varchar(1) NOT NULL,                   -- T=Table,V=view,F=funkce,P=PHP Page,G=Global Phrase, M=Module
	builtin_code varchar(80) NOT NULL,
	caption varchar(200) NOT NULL,
	caption_plural varchar(200) NOT NULL,
	helptext varchar(max) NOT NULL,
	
	module varchar(80) NOT NULL DEFAULT '',            -- Modul, ke kterému objekt patří (odkaz na builtin_code v tabulce object_type=M)
	generic_column_list varchar(200) NOT NULL DEFAULT 'builtin_code', -- Seznam sloupců, které slouží ke generování originálního UUID

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,                   -- 1 = Tenant nesmí vytvořit override záznamu (typ 'A'), povoleny jen překlady ('L')
	is_protected bit NOT NULL DEFAULT 0,               -- 1 = Tenant smí vytvořit override, ale lze měnit jen vizuální vlastnosti (caption, helptext)

	CONSTRAINT pk_meta_object PRIMARY KEY (uuid),
	CONSTRAINT chk_meta_object_type CHECK (object_type IN ('T', 'V', 'F', 'P', 'G', 'M'))
);
GO