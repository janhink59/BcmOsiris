/* =============================================================================
 * Verze: 2026-10-31 11:00
 * Soubor: table_hierarchy.sql
 * Tabulka: hierarchy (Registr sekundárních hierarchií a stromových štítků / tagů)
 * Popis:   Uchovává definice dalších hierarchických struktur a štítků (tagů),
 *          které poskytují alternativní pohledy, klasifikaci a filtrování
 *          nad záznamy v databázi.
 *          Samotná tabulka je rovněž hierarchického typu (parent_uuid, sort_code,
 *          is_leaf). Její jednotlivé položky (uzly) jsou uloženy v tabulce
 *          hierarchy_item.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - Každá koncová hierarchie (is_leaf = 1) se přes doménový trigger
 *            trg_hierarchy_sync_meta_class (a při buildu v p_fix_meta_column)
 *            automaticky promítá jako logická třída do tabulky meta_class
 *            (s úložným objektem hierarchy_item), včetně symetrických 'L' záznamů.
 *          - Povolené vazby na systémové třídy se evidují v meta_link_def a
 *            aplikovatelnost na uživatelské třídy aktiv (asset_class) v tabulce link.
 * Změny:   - 2026-10-31 11:00: Trigger trg_hierarchy_sync_meta_class upraven tak,
 *            aby do meta_class promítal pouze koncové hierarchie (is_leaf = 1),
 *            složky (is_leaf = 0) v meta_class zneplatnil (removed = 1) a plně
 *            synchronizoval i jazykové 'L' záznamy.
 * ============================================================================= */

IF OBJECT_ID('hierarchy') IS NULL
BEGIN
	CREATE TABLE hierarchy (
		-- ---------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- ---------------------------------------------------------------------
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

		-- ---------------------------------------------------------------------
		-- Auditní stopy
		-- ---------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,

		-- ---------------------------------------------------------------------
		-- Společné prezentační a identifikační vlastnosti
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Unikátní kód hierarchie (promítá se jako class_name do meta_class)
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název hierarchie (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Hierarchické uspořádání samotných hierarchií
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená položka v registru hierarchií (hierarchy.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncová hierarchie, 0 = Složka hierarchií

		-- ---------------------------------------------------------------------
		-- Výchozí pravidla pro navazování položek této hierarchie (meta_link_def)
		-- ---------------------------------------------------------------------
		multiple bit NOT NULL DEFAULT 1,                   -- 1 = Cílový záznam může mít vazbu na více položek této hierarchie
		leaf_only bit NOT NULL DEFAULT 1,                  -- 1 = Cílový záznam smí být vázán pouze na koncový uzel (is_leaf = 1)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_hierarchy PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka hierarchy byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'hierarchy', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'hierarchy', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'hierarchy', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'hierarchy', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'hierarchy', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'hierarchy', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'hierarchy', 'multiple', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'hierarchy', 'leaf_only', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'hierarchy', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'uq_hierarchy_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'uq_hierarchy_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'uq_hierarchy_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'hierarchy', 
	@iname = 'ix_hierarchy_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Doménový trigger: Automatické promítnutí koncové hierarchie (is_leaf = 1)
--                   do tabulky meta_class (včetně symetrických 'L' záznamů)
-- Poznámka: Prefix trg_ (nikoliv trgo_) chrání trigger před smazáním v generate_trgo.sql
-- -----------------------------------------------------------------------------
IF OBJECT_ID('trg_hierarchy_sync_meta_class', 'TR') IS NOT NULL
	DROP TRIGGER trg_hierarchy_sync_meta_class;
GO

CREATE TRIGGER trg_hierarchy_sync_meta_class
ON hierarchy
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	IF OBJECT_ID('meta_class') IS NULL OR OBJECT_ID('meta_object') IS NULL OR OBJECT_ID('f_generate_original', 'FN') IS NULL
		RETURN;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @stg_obj uuid = dbo.f_generate_original('meta_object', @sys_owner, 'T', 'hierarchy_item');
	DECLARE @anc_cls uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'hierarchy_item', '');

	IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @stg_obj AND object_owner = 0x00 AND record_type = 'A')
		RETURN;

	-- 1. Aktualizace existujících 'A' záznamů v meta_class podle změněných 'A' záznamů v hierarchy
	--    Pokud se z hierarchie stala složka (is_leaf = 0), označí se v meta_class jako removed = 1
	UPDATE mc
	SET mc.caption = NULLIF(h.caption, ''),
		mc.caption_plural = NULLIF(h.caption, ''),
		mc.description = NULLIF(h.description_text, ''),
		mc.helptext = NULLIF(h.help_text, ''),
		mc.sort_code = LEFT(h.sort_code, 20),
		mc.svg_icon = NULLIF(h.svg_icon, ''),
		mc.inactive = h.inactive,
		mc.removed = CASE WHEN h.is_leaf = 1 THEN h.removed ELSE 1 END,
		mc.date_modified = h.date_modified,
		mc.who_modified = h.who_modified
	FROM meta_class mc
	JOIN inserted i ON i.record_type = 'A' AND i.builtin_code <> ''
	JOIN hierarchy h ON h.uuid = i.uuid
	CROSS APPLY (
		SELECT dbo.f_generate_original('meta_class', CAST(h.object_owner AS varchar(36)), h.builtin_code, '') AS cls_orig
	) x
	WHERE mc.original = x.cls_orig
	  AND mc.object_owner = h.object_owner
	  AND mc.record_type = 'A'
	  AND mc.storage_object = @stg_obj
	  AND mc.class_name <> 'hierarchy_item';

	-- 2. Vložení nových 'A' záznamů do meta_class pouze pro koncové hierarchie (is_leaf = 1)
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		inactive, removed, class_name, storage_object, ancestor_class, sort_code,
		caption, caption_plural, description, helptext, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		x.cls_orig, h.object_owner, x.cls_orig, 'A', 'A', h.[language],
		h.inactive, h.removed, h.builtin_code, @stg_obj, @anc_cls, LEFT(h.sort_code, 20),
		NULLIF(h.caption, ''), NULLIF(h.caption, ''), NULLIF(h.description_text, ''), NULLIF(h.help_text, ''), NULLIF(h.svg_icon, ''),
		h.is_final, h.is_protected,
		h.date_created, h.who_created, h.date_modified, h.who_modified
	FROM inserted i
	JOIN hierarchy h ON h.uuid = i.uuid
	CROSS APPLY (
		SELECT dbo.f_generate_original('meta_class', CAST(h.object_owner AS varchar(36)), h.builtin_code, '') AS cls_orig
	) x
	WHERE h.record_type = 'A'
	  AND h.is_leaf = 1
	  AND h.removed = 0
	  AND h.builtin_code <> ''
	  AND NOT EXISTS (
		SELECT 1 FROM meta_class mc
		WHERE mc.class_name = h.builtin_code
		  AND mc.object_owner IN (0x00, h.object_owner)
		  AND mc.record_type = 'A'
	  );

	-- 3. Synchronizace jazykových 'L' záznamů v meta_class (při změně 'L' nebo 'A' v hierarchy)
	UPDATE mcl
	SET mcl.caption = NULLIF(hl.caption, ''),
		mcl.caption_plural = NULLIF(hl.caption, ''),
		mcl.description = NULLIF(hl.description_text, ''),
		mcl.helptext = NULLIF(hl.help_text, ''),
		mcl.removed = CASE WHEN ha.is_leaf = 1 AND ha.removed = 0 THEN hl.removed ELSE 1 END,
		mcl.date_modified = hl.date_modified,
		mcl.who_modified = hl.who_modified
	FROM meta_class mcl
	JOIN meta_class mca
		ON mca.original = mcl.original
		AND mca.object_owner = mcl.object_owner
		AND mca.record_type = 'A'
		AND mca.storage_object = @stg_obj
	JOIN hierarchy ha
		ON ha.builtin_code = mca.class_name
		AND ha.object_owner = mca.object_owner
		AND ha.record_type = 'A'
	JOIN hierarchy hl
		ON hl.original = ha.original
		AND hl.object_owner = mcl.object_owner
		AND hl.record_type = 'L'
		AND hl.[language] = mcl.[language]
	WHERE EXISTS (
		SELECT 1 FROM inserted i
		WHERE i.original = ha.original
	);

	-- 4. Vložení chybějících symetrických 'L' záznamů do meta_class
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		inactive, removed, class_name, storage_object, ancestor_class, sort_code,
		caption, caption_plural, description, helptext, svg_icon,
		is_final, is_protected,
		date_created, who_created, date_modified, who_modified
	)
	SELECT
		NEWID(), hl.object_owner, mca.original, 'L', 'A', hl.[language],
		mca.inactive, hl.removed, mca.class_name, @stg_obj, @anc_cls, mca.sort_code,
		NULLIF(hl.caption, ''), NULLIF(hl.caption, ''), NULLIF(hl.description_text, ''), NULLIF(hl.help_text, ''), mca.svg_icon,
		mca.is_final, mca.is_protected,
		hl.date_created, hl.who_created, hl.date_modified, hl.who_modified
	FROM inserted i
	JOIN hierarchy hl ON hl.uuid = i.uuid AND hl.record_type = 'L' AND hl.removed = 0
	JOIN hierarchy ha ON ha.original = hl.original AND ha.object_owner = hl.object_owner AND ha.record_type = 'A' AND ha.is_leaf = 1 AND ha.removed = 0
	JOIN meta_class mca ON mca.class_name = ha.builtin_code AND mca.object_owner = ha.object_owner AND mca.record_type = 'A' AND mca.storage_object = @stg_obj
	WHERE NOT EXISTS (
		SELECT 1 FROM meta_class ex
		WHERE ex.original = mca.original
		  AND ex.object_owner = hl.object_owner
		  AND ex.record_type = 'L'
		  AND ex.[language] = hl.[language]
	);
END;
GO