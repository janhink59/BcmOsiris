/* =============================================================================
 * Verze: 2026-11-01 18:00
 * Soubor: table_scenario.sql
 * Tabulka: scenario (Katalog rizikových scénářů / událostí CRMM)
 * Popis:   Hierarchický katalog rizikových scénářů (událostí).
 *          Každý scénář může odkazovat na hrozbu (threat_uuid), která událost
 *          způsobuje, na třídu aktiv (asset_class_uuid), u níž se hodnotí dopad,
 *          a definuje minimální skóre reziduálního rizika (residual_risk_min_score),
 *          pod které nemůže zbytkové riziko klesnout ani po zavedení opatření.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - parent_uuid ukazuje na nadřízený scénář/složku (scenario.original).
 *          - threat_uuid ukazuje na threat.original.
 *          - asset_class_uuid ukazuje na asset_class.original.
 *          - Vazby M:N na způsobené dopady (impact) a protiopatření (countermeasure)
 *            se ukládají do tabulky link.
 *          - Spravována stromovou stránkou page_scenario.php.
 * ============================================================================= */

IF OBJECT_ID('scenario') IS NULL
BEGIN
	CREATE TABLE scenario (
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
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód pro deterministický originál (povinný v 0x00 a šablonách)
		caption varchar(200) NOT NULL DEFAULT '',          -- Název scénáře (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		external_code varchar(200) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Stromová struktura a specifické sloupce pro rizikové scénáře
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená položka v hierarchii scénářů (scenario.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncový scénář, 0 = Složka (skupina scénářů)
		threat_uuid uuid NULL,                             -- Hrozba způsobující tuto událost (threat.original)
		asset_class_uuid uuid NULL,                        -- Třída aktiv, u které se hodnotí dopad (asset_class.original)
		residual_risk_min_score decimal(9,4) NULL,         -- Mez reziduálního rizika (skóre, pod které zbytkové riziko neklesne)
		editor_role_uuid uuid NULL,                        -- Role pro editaci (dědí se do podřízených)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_scenario PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka scenario byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'scenario', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'scenario', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'scenario', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'scenario', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'scenario', 'threat_uuid', 'uuid NULL';
EXEC p_create_missing_column 'scenario', 'asset_class_uuid', 'uuid NULL';
EXEC p_create_missing_column 'scenario', 'residual_risk_min_score', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'scenario', 'editor_role_uuid', 'uuid NULL';
EXEC p_create_missing_column 'scenario', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'scenario', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'scenario', 
	@iname = 'uq_scenario_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scenario', 
	@iname = 'uq_scenario_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scenario', 
	@iname = 'uq_scenario_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scenario', 
	@iname = 'ix_scenario_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO