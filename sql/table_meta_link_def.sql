/* =============================================================================
 * Verze: 2026-11-13 17:15
 * Soubor: table_meta_link_def.sql
 * Tabulka: meta_link_def
 * Popis:   Definiční tabulka pro vztahy mezi logickými třídami (meta_class).
 *          Podporuje samostatné záznamy pro zpětné vztahy (reverse_link_def),
 *          rozlišení směru (direction_type: 'P' = primární řídící, 'R' = zpětný,
 *          'S' = symetrický neorientovaný), registraci exkluzivních stromových
 *          vztahů parent_uuid (is_exclusive_parent = 1) a projekci nepřímých
 *          vztahů vygenerovaných z diagramů heterogenních sítí (is_derived = 1,
 *          diagram_uuid).
 * Vazby:   - from_class a to_class (UUID) ukazují na meta_class.original.
 *          - reverse_link_def (UUID) ukazuje na opačný vztah v meta_link_def.original.
 *          - diagram_uuid (UUID) ukazuje na link_diagram.original.
 * Změny:   - 2026-11-13 17:15: Doplněna registrace třídy, číselníku direction_type
 *            a sloupců do sysinit_class, sysinit_codetable a sysinit_column.
 *          - 2026-11-12 18:30: Doplněn unikátní filtrovaný index uq_meta_link_def_key
 *            nad složeným klíčem (object_owner, from_class, link_code).
 *          - 2026-11-11 21:30: Doplněny sloupce reverse_link_def, direction_type,
 *            is_exclusive_parent, is_derived a diagram_uuid.
 *          - 2026-10-23 11:00: Doplněny SSC sloupce draft_author, approval_note,
 *            import_origin a unikátní index uq_meta_link_def_draft.
 * ============================================================================= */

IF OBJECT_ID('meta_link_def') IS NULL
CREATE TABLE meta_link_def(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Vlastník záznamu (0x00 pro systémové definice vztahů)
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor definice vztahu napříč overridy
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- Stav verze (A, L, D, H)
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stav schválení (A, D, F, R)
	draft_author uuid NOT NULL DEFAULT 0x00,           -- Autor konceptu (user_account.original)
	approval_note varchar(max) NOT NULL DEFAULT '',    -- Poznámka schvalovatele / důvod vrácení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
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
	-- Specifické atributy definice vztahu
	-- -------------------------------------------------------------------------
	link_code varchar(80) NOT NULL,                    -- Unikátní technický kód vztahu v snake_case
	from_class uuid NOT NULL,                          -- UUID zdrojové třídy (z meta_class.original)
	to_class uuid NOT NULL,                            -- UUID cílové třídy (z meta_class.original)
	reverse_link_def uuid NULL,                        -- Odkaz na opačný (zpětný) vztah v meta_link_def.original
	direction_type varchar(1) NOT NULL DEFAULT 'P',    -- 'P' = Primární (řídící), 'R' = Zpětný (reverzní), 'S' = Symetrický (neorientovaný)
	
	-- Prezentační texty (přeložitelné)
	caption_forward varchar(200) NOT NULL DEFAULT '',  -- Název vztahu z pohledu from_class (např. "Podporuje")
	caption_backward varchar(200) NOT NULL DEFAULT '', -- Název opačného směru z pohledu to_class (např. "Je podporováno")
	description varchar(max) NOT NULL DEFAULT '',
	helptext varchar(max) NOT NULL DEFAULT '',
	
	-- Pravidla a omezení pro UI, stromovou hierarchii a projekci diagramů
	is_multiple bit NOT NULL DEFAULT 1,                -- 1 = K jednomu from_object lze navázat více to_object
	is_mandatory bit NOT NULL DEFAULT 0,               -- 1 = Třída from_class musí mít tento vztah vyplněný
	leaf_only bit NOT NULL DEFAULT 0,                  -- 1 = Povoluje vazbu pouze na koncové uzly (is_leaf = 1 v cílové třídě)
	is_exclusive_parent bit NOT NULL DEFAULT 0,        -- 1 = Vztah odpovídá exkluzivnímu sloupci parent_uuid na záznamu
	transfer_roles bit NOT NULL DEFAULT 0,             -- 1 = Přenáší editační oprávnění z primární třídy na cílovou
	link_weight_enabled bit NOT NULL DEFAULT 0,        -- 1 = Na samotné vazbě se udržuje číselná váha / metrika
	is_derived bit NOT NULL DEFAULT 0,                 -- 1 = Nepřímý vztah vygenerovaný z diagramu sítě (diagram_uuid)
	diagram_uuid uuid NULL,                            -- Odkaz na link_diagram.original u odvozeného vztahu

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur (limity klientského overridu)
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,
	is_protected bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_meta_link_def PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_link_def', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_link_def', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'meta_link_def', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'meta_link_def', 'reverse_link_def', 'uuid NULL';
EXEC p_create_missing_column 'meta_link_def', 'direction_type', 'varchar(1) NOT NULL DEFAULT ''P''';
EXEC p_create_missing_column 'meta_link_def', 'is_exclusive_parent', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'meta_link_def', 'is_derived', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'meta_link_def', 'diagram_uuid', 'uuid NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a rychlého hledání definic
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti složeného klíče (from_class, link_code) pro daného vlastníka
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_key', 
	@colnames = 'object_owner, from_class, link_code', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti jazykových verzí (Language)
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- Zajištění unikátnosti konceptu (Draft)
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'uq_meta_link_def_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

-- Optimalizace pro vyhledávání dostupných vztahů pro konkrétní třídu
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'ix_meta_link_def_classes', 
	@colnames = 'from_class, to_class', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO

-- Optimalizace pro vyhledávání a přepočet odvozených vztahů podle diagramu
EXEC sp_create_index 
	@tname = 'meta_link_def', 
	@iname = 'ix_meta_link_def_diagram', 
	@colnames = 'diagram_uuid, object_owner', 
	@uni = '', 
	@options = 'WHERE diagram_uuid IS NOT NULL';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy, číselníku direction_type a sloupců do sysinit_*
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'meta_link_def';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('meta_link_def','cs','T','meta_link_def','Definice typu vazby','Definice typů vazeb','Katalog povolených typů relací a vztahů M:N mezi logickými třídami v tabulce link (včetně zpětných a odvozených vztahů).','Určuje, které třídy lze mezi sebou propojovat, jaký je směr vztahu (P/R/S), zda je vazba povinná, vícenásobná nebo exkluzivní.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('meta_link_def','en','Link Type Definition','Link Type Definitions','Catalog of allowed M:N relationship types between logical classes in the link table (including reverse and derived relationships).','Defines which classes can be linked, direction type (P/R/S), whether the relation is mandatory, multiple, or exclusive.');
END

IF OBJECT_ID('sysinit_codetable', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_codetable WHERE codetable_name = 'direction_type';

	INSERT INTO sysinit_codetable (codetable_name, value_code, [language], sort_code, caption) VALUES
	('direction_type','P','cs','010','Primární / řídící směr (P)'),
	('direction_type','R','cs','020','Zpětný / reverzní směr (R)'),
	('direction_type','S','cs','030','Symetrický / neorientovaný (S)'),
	('direction_type','P','en','010','Primary / Governing Direction (P)'),
	('direction_type','R','en','020','Reverse / Inverse Direction (R)'),
	('direction_type','S','en','030','Symmetric / Undirected (S)');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'meta_link_def';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		list_order, translate, is_mandatory, hidden, referenced_codetable, referenced_class_code
	) VALUES
	('meta_link_def','caption_backward','cs','Název vazby zpět (caption_backward)','Název vazby z cíle na zdroj','Vazba (zpět)','Slovní popis vazby z pohledu cílového objektu (např. „Je ohrožováno“ nebo „Patří do“).',NULL,1,0,0,'',''),
	('meta_link_def','caption_forward','cs','Název vazby tam (caption_forward)','Název vazby ze zdroje na cíl','Vazba (tam)','Slovní popis vazby z pohledu zdrojového objektu (např. „Působí na“ nebo „Obsahuje“).',7,1,0,0,'',''),
	('meta_link_def','diagram_uuid','cs','Zdrojové schéma sítě (diagram_uuid)','Schéma sítě / diagram (link_diagram)','Schéma sítě','Odkaz na schéma heterogenní sítě (link_diagram), ze kterého byl tento nepřímý vztah nebo vazba vygenerována.',NULL,0,0,0,'','link_diagram'),
	('meta_link_def','direction_type','cs','Směr vztahu (direction_type)','Druh směru vztahu (P/R/S)','Směr (P/R/S)','Určuje orientaci vztahu: P = primární (řídící směr), R = zpětný (reverzní směr), S = symetrický (neorientovaný).',NULL,0,0,0,'direction_type',''),
	('meta_link_def','from_class','cs','Výchozí třída vazby (from_class)','Zdrojová třída vazby (odkud)','Zdrojová třída','Odkaz na logickou třídu v meta_class tvořící výchozí stranu vazby.',NULL,0,1,0,'','meta_class'),
	('meta_link_def','is_derived','cs','Zděděná vazba (is_derived)','Vazba odvozená děděním','Zděděno','Příznak udávající, že vazba vznikla automatickou materializací dědění z nadřízeného uzlu hierarchie.',NULL,0,0,1,'',''),
	('meta_link_def','is_exclusive_parent','cs','Exkluzivní stromový rodič (is_exclusive_parent)','Vztah odpovídá sloupci parent_uuid','Exkl. rodič','Označuje, že tento vztah reprezentuje přímou stromovou nadřízenost ze sloupce parent_uuid (max. 1 rodič).',NULL,0,0,0,'',''),
	('meta_link_def','is_mandatory','cs','Povinná položka (is_mandatory)','Povinné pole (vyžadováno)','Povinné','Označuje pole, které musí být před uložením formuláře vždy vyplněno.',NULL,0,0,0,'',''),
	('meta_link_def','is_multiple','cs','Vícenásobná vazba (is_multiple)','Povolit navázání více objektů (M:N)','Vícenásobná','Určuje, zda lze k jednomu zdrojovému záznamu připojit více cílových záznamů tohoto typu.',NULL,0,0,0,'',''),
	('meta_link_def','leaf_only','cs','Pouze koncové uzly (leaf_only)','Vazby pouze na koncové uzly (listy)','Jen listy','Určuje, zda lze cílové záznamy navazovat výhradně na koncové uzly (is_leaf = 1) této hierarchie.',NULL,0,0,0,'',''),
	('meta_link_def','link_code','cs','Kód typu vazby (link_code)','Technický kód typu vazby','Kód vazby','Unikátní systémový identifikátor definice vazby v meta_link_def.',3,0,1,0,'',''),
	('meta_link_def','link_weight_enabled','cs','Váha vazby povolena (link_weight_enabled)','Evidovat číselnou váhu na vazbě','Váha povolena','Povoluje zadávání kvantitativní váhy nebo priority přímo na instanci vazby v tabulce link.',NULL,0,0,0,'',''),
	('meta_link_def','reverse_link_def','cs','Opačný / zpětný vztah (reverse_link_def)','Párový zpětný vztah (meta_link_def)','Zpětný vztah','Odkaz na párovou definici opačného směru téhož vztahu v tabulce meta_link_def.',NULL,0,0,0,'','meta_link_def'),
	('meta_link_def','to_class','cs','Cílová třída vazby (to_class)','Cílová třída vazby (kam)','Cílová třída','Odkaz na logickou třídu v meta_class tvořící cílovou stranu vazby.',NULL,0,1,0,'','meta_class'),
	('meta_link_def','transfer_roles','cs','Přenos oprávnění (transfer_roles)','Přenášet editační oprávnění po vazbě','Přenos rolí','Určuje, zda vazba přenáší oprávnění k editaci ze zdrojového objektu na cílový.',NULL,0,0,0,'','');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('meta_link_def','caption_backward','en','Backward Link Caption (caption_backward)','Link Caption from Target to Source','Backward Caption','Verbal description of the link from the target perspective (e.g., "Is Affected By" or "Belongs To").'),
	('meta_link_def','caption_forward','en','Forward Link Caption (caption_forward)','Link Caption from Source to Target','Forward Caption','Verbal description of the link from the source perspective (e.g., "Affects" or "Contains").'),
	('meta_link_def','diagram_uuid','en','Source Network Diagram (diagram_uuid)','Network Diagram / Schema (link_diagram)','Network Diagram','Reference to the heterogeneous network schema (link_diagram) from which this indirect relationship or link was projected.'),
	('meta_link_def','direction_type','en','Relationship Direction (direction_type)','Direction Type (P/R/S)','Direction (P/R/S)','Specifies relationship orientation: P = Primary (governing direction), R = Reverse (inverse direction), S = Symmetric (undirected).'),
	('meta_link_def','from_class','en','Source Link Class (from_class)','Source Class of Link (From)','From Class','Reference to the logical class in meta_class forming the origin side of the link.'),
	('meta_link_def','is_derived','en','Derived Link (is_derived)','Link Materialized by Inheritance','Derived','Flag indicating that the link was automatically materialized by inheritance from a parent hierarchy node.'),
	('meta_link_def','is_exclusive_parent','en','Exclusive Tree Parent (is_exclusive_parent)','Relationship Maps to parent_uuid Column','Excl. Parent','Indicates that this relationship represents direct exclusive tree parenthood from the parent_uuid column (at most 1 parent).'),
	('meta_link_def','is_mandatory','en','Mandatory Field (is_mandatory)','Mandatory Field (Required)','Mandatory','Marks a field that must be filled in before saving the form.'),
	('meta_link_def','is_multiple','en','Multiple Link (is_multiple)','Allow Linking Multiple Objects (M:N)','Multiple','Indicates whether multiple target records of this type can be linked to a single source record.'),
	('meta_link_def','leaf_only','en','Leaf Nodes Only (leaf_only)','Allow Links to Leaf Nodes Only','Leaves Only','Indicates whether target records may be linked exclusively to terminal leaf nodes (is_leaf = 1) of this hierarchy.'),
	('meta_link_def','link_code','en','Link Type Code (link_code)','Technical Link Type Code','Link Code','Unique system identifier of the link definition in meta_link_def.'),
	('meta_link_def','link_weight_enabled','en','Link Weight Enabled (link_weight_enabled)','Track Numeric Weight on Link','Weight Enabled','Enables entering a quantitative weight or priority directly on the link instance in the link table.'),
	('meta_link_def','reverse_link_def','en','Reverse Relationship (reverse_link_def)','Paired Reverse Relationship (meta_link_def)','Reverse Link','Reference to the paired definition of the opposite direction of the same relationship in meta_link_def.'),
	('meta_link_def','to_class','en','Target Link Class (to_class)','Target Class of Link (To)','To Class','Reference to the logical class in meta_class forming the destination side of the link.'),
	('meta_link_def','transfer_roles','en','Transfer Permissions (transfer_roles)','Transfer Edit Permissions Along Link','Transfer Roles','Indicates whether the link transfers edit permissions from the source object to the target object.');
END
GO