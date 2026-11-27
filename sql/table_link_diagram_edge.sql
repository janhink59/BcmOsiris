/* =============================================================================
 * Verze: 2026-11-27 15:40
 * Soubor: table_link_diagram_edge.sql
 * Tabulka: link_diagram_edge (Hrany / orientované vztahy zařazené do schématu sítě)
 *
 * 1. Role souboru v celém systému:
 *    Samostatná vazební tabulka definující, které orientované vztahy z katalogu
 *    meta_link_def (diagram_uuid IS NULL) tvoří spojnice konkrétního schématu
 *    heterogenní sítě (link_diagram). Zcela odděluje metodickou definici grafu
 *    (Nastavení a katalogy CRMM) od provozní tabulky link (Analýza rizik).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - diagram_uuid odkazuje na link_diagram.original (table_link_diagram.sql).
 *    - link_def_uuid odkazuje na meta_link_def.original (table_meta_link_def.sql).
 *    - Deterministický klíč original se počítá ze složené dvojice
 *      (diagram_uuid, link_def_uuid) přes meta_original_keys a trigger
 *      trgo_link_diagram_edge (fillup_meta_original_keys.sql, generate_trgo.sql).
 *    - Čtena a modifikována uloženou procedurou dbo.page_link_diagram
 *      (page_link_diagram.sql) a procedurou dbo.p_rebuild_link_diagram
 *      (p_rebuild_link_diagram.sql) pro stránku page_link_diagram.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) bez
 *      závislosti na uživatelské relaci v dbsession.
 * ============================================================================= */

IF OBJECT_ID('link_diagram_edge', 'U') IS NULL
BEGIN
	CREATE TABLE link_diagram_edge (
		-- ---------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- ---------------------------------------------------------------------
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,                            -- Vlastník definice hrany (0x00 nebo tenant)
		original uuid NOT NULL DEFAULT 0x00,                                -- Deterministický identifikátor (diagram_uuid, link_def_uuid)
		record_type varchar(1) NOT NULL DEFAULT 'A',                        -- Stav verze (A, L, D, H)
		approval_status varchar(1) NOT NULL DEFAULT 'A',                    -- Stav schválení (A, D, F, R)
		draft_author uuid NOT NULL DEFAULT 0x00,                            -- Autor konceptu (user_account.original)
		approval_note varchar(max) NOT NULL DEFAULT '',                     -- Poznámka schvalovatele / důvod vrácení
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		is_template bit NOT NULL DEFAULT 0,
		template uuid NULL,
		import_origin varchar(255) NULL,

		-- ---------------------------------------------------------------------
		-- Auditní stopy
		-- ---------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- ---------------------------------------------------------------------
		-- Datové atributy hrany schématu sítě
		-- ---------------------------------------------------------------------
		diagram_uuid uuid NOT NULL,                                         -- Schéma sítě (link_diagram.original)
		link_def_uuid uuid NOT NULL,                                        -- Zařazený orientovaný vztah (meta_link_def.original)
		sort_code varchar(20) NOT NULL DEFAULT '',                          -- Volitelné pořadí hrany v seznamu diagramu
		edge_weight decimal(16,4) NULL,                                     -- Volitelná výchozí váha přenosu přes tuto hranu
		note varchar(max) NOT NULL DEFAULT '',                              -- Interní poznámka k zařazení vztahu do diagramu

		CONSTRAINT pk_link_diagram_edge PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka link_diagram_edge byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'link_diagram_edge', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'link_diagram_edge', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link_diagram_edge', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'link_diagram_edge', 'sort_code', 'varchar(20) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link_diagram_edge', 'edge_weight', 'decimal(16,4) NULL';
EXEC p_create_missing_column 'link_diagram_edge', 'note', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC/SSC architektury a rychlého načítání hran diagramu
-- -----------------------------------------------------------------------------
EXEC sp_create_index
	@tname = 'link_diagram_edge',
	@iname = 'uq_link_diagram_edge_active',
	@colnames = 'original, object_owner',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'link_diagram_edge',
	@iname = 'uq_link_diagram_edge_pair',
	@colnames = 'object_owner, diagram_uuid, link_def_uuid',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'link_diagram_edge',
	@iname = 'uq_link_diagram_edge_language',
	@colnames = 'original, object_owner, language',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'link_diagram_edge',
	@iname = 'uq_link_diagram_edge_draft',
	@colnames = 'original, object_owner, language, draft_author',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'link_diagram_edge',
	@iname = 'ix_link_diagram_edge_diagram',
	@colnames = 'diagram_uuid, object_owner, sort_code',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'link_diagram_edge';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, sort_code, is_final, is_protected, caption, caption_plural, description, helptext) VALUES
	('link_diagram_edge','cs','T','link_diagram_edge','185',0,1,'Hrana schématu sítě','Hrany schémat sítí','Seznam orientovaných vztahů (meta_link_def) zařazených jako spojnice do konkrétního schématu heterogenní sítě (link_diagram).','Uchovává definici hran acyklického grafu tříd pro výpočet cest přenosu hrozeb, dopadů a závislostí.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('link_diagram_edge','en','Network Diagram Edge','Network Diagram Edges','List of directed relationships (meta_link_def) included as edges in a heterogeneous network diagram (link_diagram).','Stores the directed edge definitions of an acyclic class graph used to evaluate threat, impact, and dependency propagation paths.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'link_diagram_edge';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		is_mandatory, referenced_class_code
	) VALUES
	('link_diagram_edge','diagram_uuid','cs','Schéma sítě (diagram_uuid)','Schéma sítě (link_diagram)','Schéma sítě','Odkaz na schéma heterogenní sítě v tabulce link_diagram, do kterého tato hrana patří.',1,'link_diagram'),
	('link_diagram_edge','edge_weight','cs','Výchozí váha hrany (edge_weight)','Výchozí váha přenosu přes hranu','Váha hrany','Volitelná výchozí kvantitativní váha přenosu rizika nebo závislosti přes tuto hranu schématu.',0,''),
	('link_diagram_edge','link_def_uuid','cs','Zařazený vztah (link_def_uuid)','Orientovaný vztah (meta_link_def)','Vztah','Odkaz na orientovanou definici vztahu v tabulce meta_link_def tvořící hranu grafu.',1,'meta_link_def');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('link_diagram_edge','diagram_uuid','en','Network Diagram (diagram_uuid)','Network Diagram (link_diagram)','Network Diagram','Reference to the heterogeneous network diagram in link_diagram to which this edge belongs.'),
	('link_diagram_edge','edge_weight','en','Default Edge Weight (edge_weight)','Default Propagation Weight on Edge','Edge Weight','Optional default quantitative risk or dependency propagation weight along this diagram edge.'),
	('link_diagram_edge','link_def_uuid','en','Included Relationship (link_def_uuid)','Directed Relationship (meta_link_def)','Relationship','Reference to the directed relationship definition in meta_link_def forming an edge of the graph.');
END
GO