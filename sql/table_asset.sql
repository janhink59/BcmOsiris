/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: table_asset.sql
 * Tabulka: asset (Evidence aktiv organizace – STI úložiště všech archetypů)
 * Popis:   Společná fyzická tabulka pro evidenci všech tříd a archetypů aktiv
 *          v modulu CRMM (Prostory: okres, město, lokalita, budova, místnost;
 *          Fyzická aktiva, Hostitelské počítače, Kabeláž, Dokumenty, Média,
 *          Datová aktiva, Software, Instalované aplikace, Služby, Služby typu
 *          Interface, Personál a Dodavatelé).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus) + STI
 * Vazby:   - primary_asset_class ukazuje na koncový uzel asset_class.original.
 *          - parent_uuid umožňuje stromovou hierarchii (zejména pro Prostory:
 *            Okres -> Město -> Lokalita -> Budova -> Místnost, příp. podsystémy).
 *          - building_uuid ukazuje na asset.original (archetyp BUILDING).
 *          - room_uuid ukazuje na asset.original (archetyp ROOM).
 *          - host_uuid ukazuje na asset.original (archetyp HOST).
 *          - software_uuid ukazuje na asset.original (archetyp SOFTWARE).
 *          - supplier_uuid ukazuje na asset.original (archetyp SUPPLIER).
 *          - owner_user_uuid ukazuje na user_account.original (vlastník/garant).
 *          - Vícenásobné vazby M:N (aplikace -> data, služba -> aplikace,
 *            aplikace -> personál atd.) jsou uloženy v tabulce link podle
 *            definic v meta_link_def.
 * ============================================================================= */

IF OBJECT_ID('asset') IS NULL
BEGIN
	CREATE TABLE asset (
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
		-- Společné identifikační a prezentační vlastnosti
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',                        -- Unikátní kód aktiva (automaticky odvozený z názvu)
		external_code varchar(40) NOT NULL DEFAULT '',                       -- Externí kód / spárování s CMDB či majetkovou evidencí
		inventory_number varchar(80) NOT NULL DEFAULT '',                    -- Inventární nebo sériové číslo (pro HW, média, dokumenty)
		caption varchar(200) NOT NULL DEFAULT '',                            -- Zobrazovaný název aktiva (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',                           -- Zkratka aktiva
		description_text varchar(max) NOT NULL DEFAULT '',                   -- Podrobný popis aktiva (is_html = 1)
		help_text varchar(max) NOT NULL DEFAULT '',                          -- Metodická nápověda / pokyny (is_html = 1)
		note varchar(max) NOT NULL DEFAULT '',                               -- Interní poznámka (is_html = 1)
		svg_icon varchar(max) NOT NULL DEFAULT '',                           -- Vektorová ikona SVG

		-- ---------------------------------------------------------------------
		-- Klasifikace STI archetypu, primární třída a stromová struktura
		-- ---------------------------------------------------------------------
		asset_archetype varchar(30) NOT NULL DEFAULT 'PHYSICAL',             -- Archetyp STI (DISTRICT, CITY, SITE, BUILDING, ROOM, PHYSICAL, HOST, CABLING, DOCUMENT, MEDIA, DATA, SOFTWARE, APPLICATION, SERVICE, INTERFACE, PERSONNEL, SUPPLIER)
		primary_asset_class uuid NULL,                                       -- Primární koncová třída aktiv (asset_class.original s is_leaf = 1)
		parent_uuid uuid NULL,                                               -- Nadřízené aktivum / prostor ve stromu (asset.original)
		sort_code varchar(200) NOT NULL DEFAULT '',                          -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                                      -- 1 = Koncová položka, 0 = Složka / souhrnný uzel

		-- ---------------------------------------------------------------------
		-- Přímé relační vazby 1:N podle archetypu (vynucované přes meta_column)
		-- ---------------------------------------------------------------------
		building_uuid uuid NULL,                                             -- Umístění v budově (asset.original typu BUILDING – povinné pro Místnost a Kabeláž)
		room_uuid uuid NULL,                                                 -- Umístění v místnosti (asset.original typu ROOM – povinné pro Fyzická aktiva, Hosty, Dokumenty a Média)
		host_uuid uuid NULL,                                                 -- Primární hostitelský počítač (asset.original typu HOST)
		software_uuid uuid NULL,                                             -- Zdrojový SW balík (asset.original typu SOFTWARE – pro instalované aplikace)
		supplier_uuid uuid NULL,                                             -- Dodavatel / provozovatel (asset.original typu SUPPLIER – pro Interface, HW a SW)
		owner_user_uuid uuid NULL,                                           -- Vlastník / garant aktiva (user_account.original)

		-- ---------------------------------------------------------------------
		-- Parametry dostupnosti (BIA) a agregované skóre hodnocení rizik (0..100 %)
		-- ---------------------------------------------------------------------
		rto_hours decimal(9,2) NULL,                                         -- Recovery Time Objective – max. přijatelná doba výpadku v hodinách
		rpo_hours decimal(9,2) NULL,                                         -- Recovery Point Objective – max. přijatelná ztráta dat od poslední zálohy v hodinách
		confidentiality_score decimal(9,4) NULL,                             -- Skóre požadavku na důvěrnost (dopad prozrazení dat, 0 až 100 %)
		integrity_score decimal(9,4) NULL,                                   -- Skóre požadavku na integritu (dopad chyby/nekonzistence/likvidace dat, 0 až 100 %)
		availability_score decimal(9,4) NULL,                                -- Skóre požadavku na dostupnost (dopad výpadku služby/dat, 0 až 100 %)
		inherent_risk_score decimal(9,4) NULL,                               -- Vypočtené agregované inherentní riziko aktiva (0 až 100 %)
		residual_risk_score decimal(9,4) NULL,                               -- Vypočtené agregované zbytkové (reziduální) riziko aktiva (0 až 100 %)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových a šablonových záznamů
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_asset PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka asset byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'asset', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'asset', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'asset', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'inventory_number', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'asset_archetype', 'varchar(30) NOT NULL DEFAULT ''PHYSICAL''';
EXEC p_create_missing_column 'asset', 'primary_asset_class', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'asset', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'asset', 'building_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'room_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'host_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'software_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'supplier_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'owner_user_uuid', 'uuid NULL';
EXEC p_create_missing_column 'asset', 'rto_hours', 'decimal(9,2) NULL';
EXEC p_create_missing_column 'asset', 'rpo_hours', 'decimal(9,2) NULL';
EXEC p_create_missing_column 'asset', 'confidentiality_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'integrity_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'availability_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'inherent_risk_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'residual_risk_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'asset', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'asset', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury, stromu prostorů a filtrování STI
-- -----------------------------------------------------------------------------
EXEC sp_create_index
	@tname = 'asset',
	@iname = 'uq_asset_active',
	@colnames = 'original, object_owner',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'uq_asset_language',
	@colnames = 'original, object_owner, language',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'uq_asset_draft',
	@colnames = 'original, object_owner, language, draft_author',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'ix_asset_parent_sort',
	@colnames = 'object_owner, parent_uuid, sort_code, builtin_code',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'ix_asset_archetype_class',
	@colnames = 'object_owner, asset_archetype, primary_asset_class',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'asset',
	@iname = 'ix_asset_locations',
	@colnames = 'object_owner, building_uuid, room_uuid',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO