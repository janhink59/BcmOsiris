/* =============================================================================
 * Verze: 2026-11-13 18:10
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
 * Změny:
 * - 2026-11-13 18:10: Doplněna registrace třídy a sloupců do sysinit_class
 *   a sysinit_column.
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

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'scenario_assessment';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('scenario_assessment','cs','T','scenario_assessment','Hodnocení rizikového scénáře','Hodnocení rizikových scénářů','Vyhodnocení velikosti hrozby, zranitelnosti, dopadu a míry rizika scénářů nad aktivy organizace.','Obsahuje vstupní ohodnocení scénáře pro konkrétní aktivum i automaticky vypočtené inherentní a zbytkové riziko.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('scenario_assessment','en','Risk Scenario Assessment','Risk Scenario Assessments','Evaluation of threat level, vulnerability, impact, and resulting risk of scenarios across organization assets.','Contains input scenario scores for a specific asset as well as automatically calculated inherent and residual risk.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'scenario_assessment';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		is_mandatory, is_computed, referenced_class_code
	) VALUES
	('scenario_assessment','assessment_date','cs','Datum hodnocení (assessment_date)','Datum provedení hodnocení','Datum hodnocení','Datum posledního vyhodnocení nebo přezkoumání rizikového scénáře.',0,0,''),
	('scenario_assessment','assessor_user_uuid','cs','Hodnotitel scénáře (assessor_user_uuid)','Hodnotil (odpovědná osoba)','Hodnotitel','Odkaz na uživatelský účet osoby, která provedla nebo schválila hodnocení scénáře.',0,0,'user_account'),
	('scenario_assessment','asset_uuid','cs','Hodnocené / chráněné aktivum (asset_uuid)','Aktivum / prostor','Aktivum','Odkaz na hodnocené nebo chráněné aktivum či prostor v tabulce asset.',1,0,'asset'),
	('scenario_assessment','impact_score','cs','Skóre dopadu scénáře v % (impact_score)','Velikost dopadu scénáře (0–100 %)','Dopad (%)','Hodnocené skóre velikosti dopadu scénáře na dané aktivum v procentech (0 až 100 %).',0,0,''),
	('scenario_assessment','inherent_risk_score','cs','Inherentní riziko v % (inherent_risk_score)','Inherentní riziko před opatřeními (0–100 %)','Inh. riziko (%)','Vypočtené skóre inherentního (výchozího) rizika před započtením protiopatření v procentech (0 až 100 %).',0,1,''),
	('scenario_assessment','min_risk_floor_score','cs','Spodní práh rizika v % (min_risk_floor_score)','Minimální práh zbytkového rizika (0–100 %)','Min. práh (%)','Vypočtená spodní mez, pod kterou nesmí klesnout zbytkové riziko scénáře (z definice scénáře a neimplementovaných opatření).',0,1,''),
	('scenario_assessment','reduction_score','cs','Redukce rizika opatřeními v % (reduction_score)','Redukce rizika zavedenými opatřeními (0–100 %)','Redukce opatř. (%)','Vypočtené procentuální snížení inherentního rizika díky protiopatřením zavedeným na aktivu (0 až 100 %).',0,1,''),
	('scenario_assessment','residual_risk_score','cs','Zbytkové riziko v % (residual_risk_score)','Zbytkové / reziduální riziko (0–100 %)','Rez. riziko (%)','Vypočtené výsledné zbytkové (reziduální) riziko po zohlednění protiopatření a spodního prahu v procentech (0 až 100 %).',0,1,''),
	('scenario_assessment','scenario_uuid','cs','Hodnocený rizikový scénář (scenario_uuid)','Rizikový scénář z katalogu','Scénář','Odkaz na vyhodnocovaný rizikový scénář (událost) v tabulce scenario.',1,0,'scenario'),
	('scenario_assessment','threat_score','cs','Skóre hrozby scénáře v % (threat_score)','Velikost hrozby / pravděpodobnost (0–100 %)','Hrozba (%)','Hodnocené skóre velikosti hrozby (pravděpodobnosti scénáře) v procentech (0 až 100 %).',0,0,''),
	('scenario_assessment','vulnerability_score','cs','Skóre zranitelnosti v % (vulnerability_score)','Míra zranitelnosti aktiva (0–100 %)','Zranitelnost (%)','Hodnocené skóre zranitelnosti aktiva vůči danému scénáři v procentech (0 až 100 %).',0,0,'');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('scenario_assessment','assessment_date','en','Assessment Date (assessment_date)','Assessment Execution Date','Assessment Date','Date when the risk scenario was last assessed or reviewed.'),
	('scenario_assessment','assessor_user_uuid','en','Scenario Assessor (assessor_user_uuid)','Assessed By (Responsible Person)','Assessor','Reference to the user account of the person who performed or approved the scenario assessment.'),
	('scenario_assessment','asset_uuid','en','Assessed / Protected Asset (asset_uuid)','Asset / Space','Asset','Reference to the assessed or protected asset or space in the asset table.'),
	('scenario_assessment','impact_score','en','Scenario Impact Score in % (impact_score)','Scenario Impact Severity (0–100%)','Impact (%)','Assessed impact severity score of the scenario on the given asset in percent (0 to 100%).'),
	('scenario_assessment','inherent_risk_score','en','Inherent Risk in % (inherent_risk_score)','Inherent Risk Before Controls (0–100%)','Inh. Risk (%)','Calculated inherent (initial) risk score prior to applying countermeasures in percent (0 to 100%).'),
	('scenario_assessment','min_risk_floor_score','en','Minimum Risk Floor in % (min_risk_floor_score)','Minimum Residual Risk Threshold (0–100%)','Min. Floor (%)','Calculated lower bound below which scenario residual risk cannot drop (from scenario definition and unimplemented controls).'),
	('scenario_assessment','reduction_score','en','Control Risk Reduction in % (reduction_score)','Risk Reduction by Implemented Controls (0–100%)','Control Red. (%)','Calculated percentage reduction of inherent risk achieved by countermeasures implemented on the asset (0 to 100%).'),
	('scenario_assessment','residual_risk_score','en','Residual Risk in % (residual_risk_score)','Residual Risk After Controls (0–100%)','Res. Risk (%)','Calculated resulting residual risk score after accounting for countermeasures and minimum risk floor in percent (0 to 100%).'),
	('scenario_assessment','scenario_uuid','en','Assessed Risk Scenario (scenario_uuid)','Catalog Risk Scenario','Scenario','Reference to the evaluated risk scenario (event) in the scenario table.'),
	('scenario_assessment','threat_score','en','Scenario Threat Score in % (threat_score)','Threat Level / Likelihood (0–100%)','Threat (%)','Assessed threat level (scenario likelihood) score in percent (0 to 100%).'),
	('scenario_assessment','vulnerability_score','en','Vulnerability Score in % (vulnerability_score)','Asset Vulnerability Level (0–100%)','Vulnerability (%)','Assessed vulnerability score of the asset to the given scenario in percent (0 to 100%).');
END
GO