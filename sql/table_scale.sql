/* =============================================================================
 * Verze: 2026-11-20 17:00
 * Soubor: table_scale.sql
 * Tabulka: scale (Definice hodnotících škál a oblastních vodítek CRMM)
 *
 * 1. Role souboru v celém systému:
 *    Uchovává definice hodnotících škál pro jednotlivé veličiny CRMM
 *    (scale_type: THREAT, VULNERABILITY, IMPACT, RISK) i individuální škály
 *    vodítek pro konkrétní oblasti dopadů (is_area_guideline = 1).
 *    - Škály slouží výhradně k prezentaci skóre (0..100 %) při zadávání nebo
 *      reportování (hodnocení pořízené v jemnější 10stupňové škále lze zpětně
 *      reportovat v libovolné hrubší škále, např. 4- nebo 5stupňové).
 *    - Veškeré výpočty rizik pracují výhradně s logaritmicky chápaným skóre
 *      (scale_value.score_value, výchozí nastavení uprostřed intervalu); prahy
 *      (scale_value.threshold_value, první stupeň vždy od 0 %) slouží pouze ke
 *      zpětnému dohledání stupně škály pro zobrazení.
 *    - Při prvním uložení nové škály se podle initial_levels (2..20) automaticky
 *      vygeneruje odpovídající počet rovnoměrných stupňů v scale_value.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Jednotlivé stupně a texty vodítek jsou v tabulce scale_value
 *      (scale_value.scale -> scale.original).
 *    - Odkazována z organization.default_impact_scale_uuid a impact_area.scale_uuid.
 *    - Spravována stránkou page_scale.php; prvotní data plní fillup_scale*.sql.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) bez
 *      závislosti na uživatelské relaci v dbsession.
 *
 * Změny:
 * - 2026-11-20 17:00: Přidán sloupec is_area_guideline bit NOT NULL DEFAULT 0
 *   pro odlišení individuálních škál vodítek konkrétních oblastí dopadů.
 * ============================================================================= */

IF OBJECT_ID('scale') IS NULL
BEGIN
	CREATE TABLE scale (
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
		-- Identifikace a prezentační vlastnosti škály
		-- ---------------------------------------------------------------------
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Unikátní kód škály (automaticky odvozený z názvu)
		external_code varchar(40) NOT NULL DEFAULT '',     -- Kód pro párování s externími systémy
		caption varchar(200) NOT NULL DEFAULT '',          -- Zobrazovaný název škály (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Metodické a řídicí vlastnosti škály
		-- ---------------------------------------------------------------------
		scale_type varchar(20) NOT NULL DEFAULT 'IMPACT',  -- Veličina: THREAT, VULNERABILITY, IMPACT, RISK
		is_area_guideline bit NOT NULL DEFAULT 0,          -- 1 = Škála vodítek specifická pro konkrétní oblast dopadu (impact_area)
		priority smallint NOT NULL DEFAULT 0,              -- 0 = Primární škála pro zadávání, > 0 = Přepočtová škála pro reporty
		initial_levels tinyint NOT NULL DEFAULT 4,         -- Výchozí počet automaticky generovaných stupňů při založení (2..20)
		is_default bit NOT NULL DEFAULT 0,                 -- 1 = Výchozí škála pro daný scale_type
		sort_code varchar(20) NOT NULL DEFAULT '',         -- Pořadí škály v seznamech

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_scale PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka scale byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'scale', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'scale', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'scale', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'scale', 'scale_type', 'varchar(20) NOT NULL DEFAULT ''IMPACT''';
EXEC p_create_missing_column 'scale', 'is_area_guideline', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'scale', 'priority', 'smallint NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'scale', 'initial_levels', 'tinyint NOT NULL DEFAULT 4';
EXEC p_create_missing_column 'scale', 'is_default', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'scale', 'sort_code', 'varchar(20) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'uq_scale_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'uq_scale_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'uq_scale_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'scale', 
	@iname = 'ix_scale_type_priority', 
	@colnames = 'scale_type, priority, sort_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy, číselníku scale_type a sloupců do sysinit_*
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'scale';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('scale','cs','T','scale','Hodnotící škála','Hodnotící škály','Definice hodnotících škál pro hrozby, zranitelnosti, dopady a výsledná rizika v modulu CRMM (včetně oblastních vodítek dopadů).','Umožňuje definovat primární škály pro zadávání (priorita 0), převodní škály pro reportování i individuální škály vodítek pro oblasti dopadů.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('scale','en','Assessment Scale','Assessment Scales','Definitions of assessment scales for threats, vulnerabilities, impacts, and resulting risks in CRMM (including area-specific impact guidelines).','Allows defining primary input scales (priority 0), secondary reporting scales, and area-specific guideline scales.');
END

IF OBJECT_ID('sysinit_codetable', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_codetable WHERE codetable_name = 'scale_type';

	INSERT INTO sysinit_codetable (codetable_name, value_code, [language], sort_code, caption) VALUES
	('scale_type','IMPACT','cs','030','Dopad / Kritičnost aktiv'),
	('scale_type','RISK','cs','040','Výsledné riziko / Míra ohrožení'),
	('scale_type','THREAT','cs','010','Hrozba / Pravděpodobnost'),
	('scale_type','VULNERABILITY','cs','020','Zranitelnost'),
	('scale_type','IMPACT','en','030','Impact / Asset Criticality'),
	('scale_type','RISK','en','040','Resulting Risk / Threat Level'),
	('scale_type','THREAT','en','010','Threat / Probability'),
	('scale_type','VULNERABILITY','en','020','Vulnerability');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'scale';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		referenced_codetable
	) VALUES
	('scale','initial_levels','cs','Počet stupňů při založení (initial_levels)','Počet stupňů (pro vygenerování)','Počet stupňů','Počet rovnoměrných stupňů (2 až 20), které se automaticky vygenerují v intervalu 0 až 100 % při prvním uložení nové škály.',''),
	('scale','is_area_guideline','cs','Škála vodítek oblasti dopadu (is_area_guideline)','Oblastní vodítko dopadu (impact_area)','Vodítko obl.','Zaškrtněte u škály obsahující specifická vodítka pro konkrétní oblast dopadu (odkazované z impact_area.scale_uuid).',''),
	('scale','priority','cs','Priorita škály (priority)','Priorita škály (0 = primární)','Priorita','0 = primární škála pro zadávání a výchozí zobrazení; > 0 = sekundární škála pro zpětný přepočet v reportech.',''),
	('scale','scale_type','cs','Druh škály (scale_type)','Druh měřené veličiny','Druh škály','Určuje veličinu hodnocenou touto škálou (Hrozba, Zranitelnost, Dopad, Výsledné riziko).','scale_type');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('scale','initial_levels','en','Initial Level Count (initial_levels)','Number of Levels (to Generate)','Level Count','Number of even levels (2 to 20) automatically generated in the 0 to 100% range when first saving a new scale.'),
	('scale','is_area_guideline','en','Impact Area Guideline Scale (is_area_guideline)','Area-Specific Impact Guideline (impact_area)','Area Guide','Check for a scale containing specific guideline descriptions tailored to a particular impact area (referenced by impact_area.scale_uuid).'),
	('scale','priority','en','Scale Priority (priority)','Scale Priority (0 = Primary)','Priority','0 = primary scale for data entry and default display; > 0 = secondary conversion scale for reporting.'),
	('scale','scale_type','en','Scale Type (scale_type)','Measured Quantity Type','Scale Type','Determines the quantity evaluated by this scale (Threat, Vulnerability, Impact, Resulting Risk).');
END
GO