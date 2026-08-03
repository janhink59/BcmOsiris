-- =============================================================================
-- Tabulka: asset_class (Tøídy aktiv)
-- Popis:	Hierarchický èíselník pro klasifikaci aktiv v modulu CRMM.
--			Urèuje strukturu (napø. Umístìní -> Budova -> Místnost), 
--			definuje koncové uzly a umožòuje dìdìní rolí editorù.
-- Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
-- =============================================================================

DROP TABLE IF EXISTS asset_class;

CREATE TABLE asset_class (
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce (dle domluvených konvencí)
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT CAST(0x00 AS uuid),
	original uuid NOT NULL DEFAULT CAST(0x00 AS uuid),
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
	-- Spoleèné textové vlastnosti (podpora UTF-8)
	-- -------------------------------------------------------------------------
	caption varchar(200) NOT NULL DEFAULT '',
	shortname varchar(40) NOT NULL DEFAULT '',
	external_code varchar(200) NOT NULL DEFAULT '',
	instance_class_name varchar(80) NOT NULL DEFAULT '',
	description_text varchar(max) NOT NULL DEFAULT '',
	help_text varchar(max) NOT NULL DEFAULT '',
	
	-- -------------------------------------------------------------------------
	-- Auditní stopy (uuid vazby, bez denormalizovaných jmen)
	-- -------------------------------------------------------------------------
	date_created datetime2 NOT NULL DEFAULT sysutcdatetime(),
	who_created uuid NOT NULL DEFAULT CAST(0x00 AS uuid),
	date_modified datetime2 NOT NULL DEFAULT sysutcdatetime(),
	who_modified uuid NOT NULL DEFAULT CAST(0x00 AS uuid),

	-- -------------------------------------------------------------------------
	-- Specifické sloupce pro asset_class (Tøídy aktiv CRMM)
	-- -------------------------------------------------------------------------
	parent_uuid uuid NULL,				-- Hierarchický odkaz na nadøízenou tøídu (tvorba stromu)
	is_end_node bit NOT NULL DEFAULT 0,	-- Pøíznak koncového uzlu (pouze k tìmto lze vázat konkrétní aktiva)
	editor_role_uuid uuid NULL,			-- Odkaz na tabulku role: Role oprávnìná k editaci aktiv v této tøídì (dìdí se do podøízených)

	CONSTRAINT pk_asset_class PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištìní RAC architektury
-- -----------------------------------------------------------------------------
-- Unikátní aktivní záznam pro vlastníka a originál
CREATE UNIQUE INDEX uq_asset_class_active 
	ON asset_class(original, object_owner) 
	WHERE record_type = 'A' AND removed = 0;
GO

-- Unikátní jazyková verze pro vlastníka, originál a jazyk
CREATE UNIQUE INDEX uq_asset_class_language 
	ON asset_class(original, object_owner, language) 
	WHERE record_type = 'L' AND removed = 0;
GO

-- -----------------------------------------------------------------------------
-- Inicializaèní systémový záznam (0x00)
-- Nutný pro bezproblémové fungování cross joinù a skládání systémových dat
-- -----------------------------------------------------------------------------
INSERT INTO asset_class (
	uuid, 
	object_owner, 
	original, 
	record_type, 
	approval_status, 
	caption, 
	shortname, 
	description_text,
	is_end_node
) VALUES (
	CAST(0x00 AS uuid), 
	CAST(0x00 AS uuid), 
	CAST(0x00 AS uuid), 
	'A', 
	'A', 
	'Koøenová tøída aktiv', 
	'ROOT', 
	'Výchozí systémový uzel pro hierarchii tøíd aktiv.',
	0
);
GO