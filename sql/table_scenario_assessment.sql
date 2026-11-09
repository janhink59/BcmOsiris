/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: table_scenario_assessment.sql
 * Tabulka: scenario_assessment (Hodnocení rizikových scénářů nad aktivy)
 * Popis:   Uchovává vyhodnocení velikosti hrozby, zranitelnosti, dopadu
 *          a vypočteného inherentního i reziduálního rizika konkrétního
 *          scénáře (scenario) na konkrétním aktivu (asset).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - asset_uuid ukazuje na asset.original.
 *          - scenario_uuid ukazuje na scenario.original.
 *          - assessor_user_uuid ukazuje na user_account.original.
 *          - Deterministický klíč original se počítá ze dvojice
 *            (asset_uuid, scenario_uuid) přes meta_original_keys.
 * ============================================================================= */

IF OBJECT_ID('scenario_assessment') IS NULL
BEGIN
	CREATE TABLE scenario_assessment (
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
		-- Klíčové vazby hodnocení a prezentační údaje
		-- ---------------------------------------------------------------------
		asset_uuid uuid NOT NULL,                                            -- Hodnocené aktivum (asset.original)
		scenario_uuid uuid NOT NULL,                                         -- Hodnocený rizikový scénář (scenario.original)
		builtin_code varchar(80) NOT NULL DEFAULT '',                        -- Doplňkový technický kód záznamu
		external_code varchar(40) NOT NULL DEFAULT '',                       -- Kód pro párování s externími systémy
		caption varchar(200) NOT NULL DEFAULT '',                            -- Zobrazovaný popis hodnocení (lokalizovatelný)
		description_text varchar(max) NOT NULL DEFAULT '',                   -- Zdůvodnění hodnocení (is_html = 1)
		note varchar(max) NOT NULL DEFAULT '',                               -- Interní poznámka (is_html = 1)

		-- ---------------------------------------------------------------------
		-- Vstupní a výsledné výpočtové hodnoty v intervalu 0.0000 až 100.0000 %
		-- ---------------------------------------------------------------------
		threat_score decimal(9,4) NOT NULL DEFAULT 0.0000,                   -- Skóre velikosti hrozby / pravděpodobnosti (0 až 100 %)
		vulnerability_score decimal(9,4) NOT NULL DEFAULT 0.0000,            -- Skóre zranitelnosti aktiva vůči scénáři (0 až 100 %)
		impact_score decimal(9,4) NOT NULL DEFAULT 0.0000,                   -- Skóre celkového dopadu scénáře (0 až 100 %)
		inherent_risk_score decimal(9,4) NOT NULL DEFAULT 0.0000,            -- Vypočtené inherentní riziko před opatřeními (0 až 100 %)
		reduction_score decimal(9,4) NOT NULL DEFAULT 0.0000,                -- Souhrnná redukce rizika z aplikovaných opatření (0 až 100 %)
		min_risk_floor_score decimal(9,4) NOT NULL DEFAULT 0.0000,           -- Spodní práh rizika z neimplementovaných opatření a scénáře (0 až 100 %)
		residual_risk_score decimal(9,4) NOT NULL DEFAULT 0.0000,            -- Výsledné zbytkové (reziduální) riziko (0 až 100 %)

		-- ---------------------------------------------------------------------
		-- Odpovědnost a termín hodnocení
		-- ---------------------------------------------------------------------
		assessor_user_uuid uuid NULL,                                        -- Osoba, která provedla hodnocení (user_account.original)
		assessment_date date NULL,                                           -- Datum provedení / revize hodnocení

		CONSTRAINT pk_scenario_assessment PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka scenario_assessment byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'scenario_assessment', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'scenario_assessment', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario_assessment', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'scenario_assessment', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario_assessment', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario_assessment', 'note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scenario_assessment', 'threat_score', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scenario_assessment', 'vulnerability_score', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scenario_assessment', 'impact_score', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scenario_assessment', 'inherent_risk_score', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scenario_assessment', 'reduction_score', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scenario_assessment', 'min_risk_floor_score', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scenario_assessment', 'residual_risk_score', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'scenario_assessment', 'assessor_user_uuid', 'uuid NULL';
EXEC p_create_missing_column 'scenario_assessment', 'assessment_date', 'date NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a rychlých přepočtů rizik
-- -----------------------------------------------------------------------------
EXEC sp_create_index
	@tname = 'scenario_assessment',
	@iname = 'uq_scenario_assessment_active',
	@colnames = 'original, object_owner',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'scenario_assessment',
	@iname = 'uq_scenario_assessment_language',
	@colnames = 'original, object_owner, language',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'scenario_assessment',
	@iname = 'uq_scenario_assessment_draft',
	@colnames = 'original, object_owner, language, draft_author',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'scenario_assessment',
	@iname = 'ix_scenario_assessment_asset',
	@colnames = 'object_owner, asset_uuid, scenario_uuid',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'scenario_assessment',
	@iname = 'ix_scenario_assessment_scenario',
	@colnames = 'object_owner, scenario_uuid, asset_uuid',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO