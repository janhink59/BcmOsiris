-- =============================================================================
-- Tabulka: asset_class (Třídy aktiv)
-- Popis:	Hierarchický číselník pro klasifikaci aktiv v modulu CRMM.
--			Určuje strukturu (např. Umístění -> Budova -> Místnost), 
--			definuje koncové uzly a umožňuje dědění rolí editorů.
-- Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
-- =============================================================================

-- Upozornění: Příkaz DROP TABLE IF EXISTS vyžaduje SQL Server 2016 a novější.
-- Zpětná kompatibilita DB CL110 se zde nevyžaduje.
DROP TABLE IF EXISTS asset_class;
GO

CREATE TABLE asset_class (
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce (dle domluvených konvencí)
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
	-- Společné textové vlastnosti (podpora UTF-8)
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
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické sloupce pro asset_class (Třídy aktiv CRMM a Stromová struktura)
	-- -------------------------------------------------------------------------
	
	-- Hierarchický odkaz na nadřízenou třídu. Slouží k primárnímu udržování sémantické 
	-- struktury stromu a přesunům větví bez vyvolání lavinových updatů v konceptech.
	parent_uuid uuid NULL,
	
	-- Textový klíč pro rychlé třídění a čtení struktury stromu na frontendu.
	sort_code varchar(200) NOT NULL DEFAULT '',
	
	-- Příznak koncového uzlu. Dle striktních pravidel mohou být aktiva vázána pouze na 
	-- uzly, které mají is_leaf = 1. Pokud klient pod tento uzel přidá vlastní větev, 
	-- je nutné toto dynamicky ošetřit ve View nebo provést aplikační migraci.
	is_leaf bit NOT NULL DEFAULT 0,
	
	-- Odkaz na roli. Definuje, která role je oprávněná k editaci aktiv v této třídě. 
	-- Tato vlastnost se může dědit do podřízených tříd (uzlů).
	editor_role_uuid uuid NULL,

	CONSTRAINT pk_asset_class PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka a originál.
CREATE UNIQUE INDEX uq_asset_class_active 
	ON asset_class(original, object_owner) 
	WHERE record_type = 'A' AND removed = 0;
GO

-- Zajištění unikátnosti jazykových verzí (Language) pro daného vlastníka a originál.
CREATE UNIQUE INDEX uq_asset_class_language 
	ON asset_class(original, object_owner, language) 
	WHERE record_type = 'L' AND removed = 0;
GO

-- -----------------------------------------------------------------------------
-- Inicializační systémový záznam (0x00)
-- Nutný pro bezproblémové fungování cross joinů a skládání systémových dat.
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
	is_leaf,
	sort_code
) VALUES (
	0x00, 
	0x00, 
	0x00, 
	'A', 
	'A', 
	'Kořenová třída aktiv', 
	'ROOT', 
	'Výchozí systémový uzel pro hierarchii tříd aktiv.',
	0,
	'000'
);
GO