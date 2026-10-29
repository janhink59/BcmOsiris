/* =============================================================================
 * Verze: 2026-10-29 15:30
 * Soubor: table_organization.sql
 * Tabulka: organization (Organizace a její nastavení)
 * Popis:	Základní kámen multi-tenantní architektury CRMM. Definuje jednotlivé 
 *			klienty (tenanty) v systému. Vlastníkem (object_owner) systémového 
 *			záznamu je 0x00, ostatní záznamy organizací vlastní samy sebe
 *			(object_owner = original) a jsou plně pod kontrolou administrátora
 *			dané organizace (OrgAdmin 'A').
 *			Licenční omezení (licence_level, login_disabled) jsou vyčleněna
 *			výhradně v tabulce organization_licence.
 *			Tabulka přímo obsahuje i regionální, formátovací a CRMM výpočtové
 *			parametry organizace (nahrazuje dřívější tabulku organization_settings).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Změny:
 * - 2026-10-29 15:30: Vyčleněny sloupce licence_level a login_disabled do
 *   tabulky organization_licence. Doplněny regionální, formátovací a CRMM
 *   výpočtové parametry organizace a unikátní index uq_organization_draft.
 * - 2026-10-22 17:45: Doplněno idempotentní dotvoření chybějících symetrických
 *   'L' záznamů pro všechny existující organizace (včetně 0x00).
 * ============================================================================= */

-- Podmíněné odstranění tabulky, pokud v ní nejsou poslední změny
IF NOT EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization' AND colname='shortname')
	EXECUTE dropni 'organization';
GO

IF OBJECT_ID('organization') IS NULL
CREATE TABLE organization (
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,
	original uuid NOT NULL DEFAULT 0x00,
	record_type varchar(1) NOT NULL DEFAULT 'A',
	approval_status varchar(1) NOT NULL DEFAULT 'A',
	draft_author uuid NOT NULL DEFAULT 0x00,
	approval_note varchar(max) NOT NULL DEFAULT '',
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,
	
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
	-- Specifické identifikační, fakturační a adresní sloupce organizace
	-- -------------------------------------------------------------------------
	note varchar(max) NOT NULL DEFAULT '',
	
	-- Detekce domovského SSO tenanta v multi-tenantním prostředí (pro IdP)
	login_domain varchar(200) NOT NULL DEFAULT '',		
	
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

	-- -------------------------------------------------------------------------
	-- Regionální a formátovací nastavení organizace
	-- -------------------------------------------------------------------------
	preferred_language varchar(2) NOT NULL DEFAULT 'cs',
	currency_unit varchar(40) NOT NULL DEFAULT 'tis. Kč',
	currency_digits tinyint NOT NULL DEFAULT 2,
	currency_before bit NOT NULL DEFAULT 0,
	format_date varchar(20) NOT NULL DEFAULT 'dd.MM.yyyy',
	format_time varchar(20) NOT NULL DEFAULT 'HH:mm:ss',
	time_zone varchar(100) NOT NULL DEFAULT 'Europe/Prague',
	thousand_separator varchar(1) NOT NULL DEFAULT ' ',
	decimal_separator varchar(1) NOT NULL DEFAULT ',',
	export_delimiter varchar(1) NOT NULL DEFAULT ';',

	-- -------------------------------------------------------------------------
	-- Metodické a výpočtové parametry CRMM (limity škál a finanční prahy)
	-- -------------------------------------------------------------------------
	max_threat_score decimal(9,4) NOT NULL DEFAULT 13.0000,
	max_vulnerability_score decimal(9,4) NOT NULL DEFAULT 6.5000,
	max_impact_score decimal(9,4) NOT NULL DEFAULT 25.5000,
	max_risk_score decimal(9,4) NOT NULL DEFAULT 40.7500,
	max_impact_financial decimal(18,2) NULL,
	residual_risk_min_financial decimal(18,2) NULL,
	evaluation_method varchar(40) NOT NULL DEFAULT '',

	-- Média a logotyp
	logo_data varbinary(max) NULL,
	logo_filename varchar(255) NOT NULL DEFAULT '',
	logo_mime_type varchar(100) NOT NULL DEFAULT '',

	CONSTRAINT pk_organization PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců a odstranění vyčleněných licenčních sloupců
-- -----------------------------------------------------------------------------
EXEC sp_drop_column 'organization', 'licence_level';
EXEC sp_drop_column 'organization', 'login_disabled';
GO

EXEC p_create_missing_column 'organization', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'organization', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'organization', 'preferred_language', 'varchar(2) NOT NULL DEFAULT ''cs''';
EXEC p_create_missing_column 'organization', 'currency_unit', 'varchar(40) NOT NULL DEFAULT ''tis. Kč''';
EXEC p_create_missing_column 'organization', 'currency_digits', 'tinyint NOT NULL DEFAULT 2';
EXEC p_create_missing_column 'organization', 'currency_before', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'organization', 'format_date', 'varchar(20) NOT NULL DEFAULT ''dd.MM.yyyy''';
EXEC p_create_missing_column 'organization', 'format_time', 'varchar(20) NOT NULL DEFAULT ''HH:mm:ss''';
EXEC p_create_missing_column 'organization', 'time_zone', 'varchar(100) NOT NULL DEFAULT ''Europe/Prague''';
EXEC p_create_missing_column 'organization', 'thousand_separator', 'varchar(1) NOT NULL DEFAULT '' ''';
EXEC p_create_missing_column 'organization', 'decimal_separator', 'varchar(1) NOT NULL DEFAULT '',''';
EXEC p_create_missing_column 'organization', 'export_delimiter', 'varchar(1) NOT NULL DEFAULT '';''';
EXEC p_create_missing_column 'organization', 'max_threat_score', 'decimal(9,4) NOT NULL DEFAULT 13.0000';
EXEC p_create_missing_column 'organization', 'max_vulnerability_score', 'decimal(9,4) NOT NULL DEFAULT 6.5000';
EXEC p_create_missing_column 'organization', 'max_impact_score', 'decimal(9,4) NOT NULL DEFAULT 25.5000';
EXEC p_create_missing_column 'organization', 'max_risk_score', 'decimal(9,4) NOT NULL DEFAULT 40.7500';
EXEC p_create_missing_column 'organization', 'max_impact_financial', 'decimal(18,2) NULL';
EXEC p_create_missing_column 'organization', 'residual_risk_min_financial', 'decimal(18,2) NULL';
EXEC p_create_missing_column 'organization', 'evaluation_method', 'varchar(40) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'organization', 
	@iname = 'uq_organization_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization', 
	@iname = 'uq_organization_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization', 
	@iname = 'uq_organization_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Inicializační systémový záznam (0x00)
-- -----------------------------------------------------------------------------
IF NOT EXISTS(SELECT * FROM organization WHERE uuid = 0x00)
BEGIN
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
END
GO

-- Idempotentní doplnění chybějících symetrických 'L' záznamů pro všechny existující organizace
INSERT INTO organization (
	uuid, object_owner, original, record_type, approval_status, [language],
	caption, shortname, description_text, help_text, note,
	login_domain, who_created, who_modified
)
SELECT
	NEWID(), a.object_owner, a.original, 'L', 'A', a.[language],
	a.caption, a.shortname, a.description_text, a.help_text, a.note,
	a.login_domain, a.who_created, a.who_modified
FROM organization a
WHERE a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM organization l
	WHERE l.original = a.original
	  AND l.object_owner = a.object_owner
	  AND l.record_type = 'L'
	  AND l.[language] = a.[language]
	  AND l.removed = 0
  );
GO