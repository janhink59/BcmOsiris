/* =============================================================================
 * Verze: 2026-11-13 17:15
 * Soubor: table_link.sql
 * Tabulka: link
 * Popis:   Univerzální transakční tabulka pro uživatelské, stromové (parent_uuid)
 *          i hierarchicky či diagramově odvozené vazby mezi záznamy.
 *          Konkrétní smysl a typ vztahu (např. 1:N, M:N, leaf_only, direction_type)
 *          diktuje definiční tabulka "meta_link_def".
 * Vazby:   - link_def (UUID) ukazuje na definici vztahu (meta_link_def.original).
 *          - from_object a to_object (UUID) ukazují na originály cílových záznamů.
 *          - ancestor_link (UUID) ukazuje na link.original nadřízené vazby,
 *            ze které tato vazba vznikla děděním po hierarchii (0x00 = přímá vazba).
 *          - diagram_uuid (UUID) ukazuje na link_diagram.original u nepřímých
 *            vazeb materializovaných ze schématu heterogenní sítě.
 * Změny:   - 2026-11-13 17:15: Doplněna registrace třídy a sloupců do sysinit_class
 *            a sysinit_column.
 *          - 2026-11-11 21:30: Přidány sloupce reverse_link_weight a diagram_uuid
 *            a index ix_link_diagram.
 *          - 2026-10-30 23:35: Přidán sloupec ancestor_link uuid NOT NULL DEFAULT 0x00,
 *            zařazen do unikátního indexu uq_link_active_definition a vytvořen
 *            index ix_link_ancestor_link pro rychlé přepočty děděných vazeb.
 *          - 2026-10-23 11:00: Doplněny SSC sloupce draft_author, approval_note,
 *            import_origin a unikátní index uq_link_draft.
 * ============================================================================= */

IF OBJECT_ID('link') IS NULL
CREATE TABLE link(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu vazby (organizace)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor vazby
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, D, H)
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení (A, D, F, R)
	draft_author uuid NOT NULL DEFAULT 0x00,           -- Autor konceptu (user_account.original)
	approval_note varchar(max) NOT NULL DEFAULT '',    -- Poznámka schvalovatele / důvod vrácení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',         -- Ponecháno pro kompatibilitu s RAC
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,                   -- Původ záznamu z importu (Měkký audit)

	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Datové atributy vazby
	-- -------------------------------------------------------------------------
	link_def uuid NOT NULL,                            -- Odkaz na definici vztahu (meta_link_def.original)
	from_object uuid NOT NULL,                         -- UUID originálu zdrojového objektu
	to_object uuid NOT NULL,                           -- UUID originálu cílového objektu
	ancestor_link uuid NOT NULL DEFAULT 0x00,          -- UUID zdrojové vazby při dědění / projekci (0x00 = ručně zadaná vazba)
	diagram_uuid uuid NULL,                            -- Odkaz na link_diagram.original u vazby vygenerované z diagramu sítě
	
	-- Metriky a vlastnosti uplatněné přímo na konkrétní instanci vazby
	link_weight decimal(16,4) NULL,                    -- Kvantitativní hodnota v přímém směru (váha přenosu rizika / priorita)
	reverse_link_weight decimal(16,4) NULL,            -- Volitelná kvantitativní hodnota v opačném směru
	note varchar(max) NOT NULL DEFAULT '',             -- Umožňuje tenantovi okomentovat si důvod propojení
	
	-- -------------------------------------------------------------------------
	-- Systémová příznaková data
	-- -------------------------------------------------------------------------
	is_derived bit NOT NULL DEFAULT 0,                 -- 1 = Vazba vznikla děděním, ze sloupce parent_uuid nebo z diagramu sítě

	CONSTRAINT pk_link PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'link', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'link', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'link', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'link', 'ancestor_link', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'link', 'diagram_uuid', 'uuid NULL';
EXEC p_create_missing_column 'link', 'reverse_link_weight', 'decimal(16,4) NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------

-- Pokud existuje stará 4sloupcová verze indexu uq_link_active_definition (bez ancestor_link), nahradíme ji
IF EXISTS (
	SELECT 1 FROM sys.indexes WHERE name = 'uq_link_active_definition' AND object_id = OBJECT_ID('link')
) AND NOT EXISTS (
	SELECT 1 FROM v_sysindexcolumns WHERE table_name = 'link' AND index_name = 'uq_link_active_definition' AND column_name = 'ancestor_link'
)
BEGIN
	EXEC sp_drop_index 'link', 'uq_link_active_definition';
END
GO

-- Zajištění unikátnosti vazby (Active) včetně ancestor_link (umožňuje souběh dědění více cestami)
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_active_definition', 
	@colnames = 'object_owner, link_def, from_object, to_object, ancestor_link', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění původního logického omezení pro originál
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_active_original', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti konceptu (Draft)
EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'uq_link_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Zásadní indexy pro klientské dotazy a správu odvozených vazeb
-- -----------------------------------------------------------------------------

EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'ix_link_from_object', 
	@colnames = 'from_object, object_owner, link_def', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'ix_link_to_object', 
	@colnames = 'to_object, object_owner, link_def', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'ix_link_ancestor_link', 
	@colnames = 'ancestor_link, object_owner', 
	@uni = '', 
	@options = 'WHERE ancestor_link <> 0x00';
GO

EXEC sp_create_index 
	@tname = 'link', 
	@iname = 'ix_link_diagram', 
	@colnames = 'diagram_uuid, object_owner', 
	@uni = '', 
	@options = 'WHERE diagram_uuid IS NOT NULL';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'link';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('link','cs','T','link','Vazba mezi objekty','Vazby a závislosti objektů','Univerzální tabulka uživatelských, stromových (parent_uuid) i hierarchicky a diagramově odvozených vazeb M:N mezi záznamy entit.','Uchovává přímé vazby i vazby automaticky zmaterializované děděním po stromu nebo ze schémat sítí.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('link','en','Object Link','Object Links & Dependencies','Universal table of user-defined, tree (parent_uuid), and hierarchically or diagram-derived M:N links between entity records.','Stores direct links as well as links automatically materialized down the hierarchy tree or from network schemas.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'link';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		is_mandatory, hidden, referenced_class_code
	) VALUES
	('link','ancestor_link','cs','Zdrojová nadřazená vazba (ancestor_link)','Zdrojová vazba při dědění','Zdroj dědění','Identifikátor nadřízené vazby v tabulce link, ze které tato vazba vznikla děděním po hierarchii (0x00 = přímá vazba).',0,1,''),
	('link','diagram_uuid','cs','Zdrojové schéma sítě (diagram_uuid)','Schéma sítě / diagram (link_diagram)','Schéma sítě','Odkaz na schéma heterogenní sítě (link_diagram), ze kterého byl tento nepřímý vztah nebo vazba vygenerována.',0,0,'link_diagram'),
	('link','from_object','cs','Zdrojový objekt vazby (from_object)','Zdrojový záznam vazby (odkud)','Zdroj vazby','Identifikátor (original) výchozího záznamu propojovaného vazbou.',1,0,'asset'),
	('link','is_derived','cs','Zděděná vazba (is_derived)','Vazba odvozená děděním','Zděděno','Příznak udávající, že vazba vznikla automatickou materializací dědění z nadřízeného uzlu hierarchie.',0,1,''),
	('link','link_def','cs','Definice vazby (link_def)','Typ vazby (meta_link_def)','Typ vazby','Odkaz na definici typu vazby v tabulce meta_link_def.',1,0,'meta_link_def'),
	('link','link_weight','cs','Číselná váha vazby (link_weight)','Kvantitativní váha / priorita vazby','Váha vazby','Číselná hodnota vyjadřující váhu přenosu rizika nebo prioritu konkrétní vazby.',0,0,''),
	('link','reverse_link_weight','cs','Váha vazby v opačném směru (reverse_link_weight)','Kvantitativní váha zpětného směru vazby','Zpětná váha','Volitelná číselná váha přenosu rizika nebo priority v opačném směru vazby.',0,0,''),
	('link','to_object','cs','Cílový objekt vazby (to_object)','Cílový záznam vazby (kam)','Cíl vazby','Identifikátor (original) cílového záznamu propojovaného vazbou.',1,0,'asset');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('link','ancestor_link','en','Ancestor Source Link (ancestor_link)','Source Link for Hierarchy Inheritance','Ancestor Link','Identifier of the parent link in the link table from which this link was derived by hierarchy inheritance (0x00 = direct link).'),
	('link','diagram_uuid','en','Source Network Diagram (diagram_uuid)','Network Diagram / Schema (link_diagram)','Network Diagram','Reference to the heterogeneous network schema (link_diagram) from which this indirect relationship or link was projected.'),
	('link','from_object','en','Source Link Object (from_object)','Source Linked Record (From)','From Object','Original UUID of the source record connected by the link.'),
	('link','is_derived','en','Derived Link (is_derived)','Link Materialized by Inheritance','Derived','Flag indicating that the link was automatically materialized by inheritance from a parent hierarchy node.'),
	('link','link_def','en','Link Definition (link_def)','Link Type (meta_link_def)','Link Type','Reference to the link type definition in meta_link_def.'),
	('link','link_weight','en','Link Numeric Weight (link_weight)','Quantitative Link Weight / Priority','Link Weight','Numeric value expressing risk transfer weight or priority of the specific link instance.'),
	('link','reverse_link_weight','en','Reverse Link Weight (reverse_link_weight)','Quantitative Weight of Reverse Direction','Reverse Weight','Optional numeric risk transfer weight or priority in the opposite direction of the link.'),
	('link','to_object','en','Target Link Object (to_object)','Target Linked Record (To)','To Object','Original UUID of the target record connected by the link.');
END
GO