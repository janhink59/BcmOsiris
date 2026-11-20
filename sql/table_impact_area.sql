/* =============================================================================
 * Verze: 2026-11-20 17:00
 * Soubor: table_impact_area.sql
 * Tabulka: impact_area (Katalog oblastí dopadů CRMM)
 *
 * 1. Role souboru v celém systému:
 *    Hierarchický katalog měřitelných oblastí, ve kterých se projevuje velikost
 *    dopadu (sloupce matice BIA), rozčleněný do 3 perspektiv:
 *    - Dopady na organizaci (finanční ztráta, obchodní zájmy, důvěryhodnost,
 *      povinnosti ze zákona, trestní jednání, osobní bezpečnost, řízení a provoz),
 *    - Dopady na stát / veřejný zájem (veřejný pořádek, mezinárodní vztahy,
 *      veřejná správa, obrana, bezpečnostní a zpravodajské zájmy),
 *    - Dopady na subjekt údajů / obyvatelstvo (fyzická, hmotná a nehmotná újma).
 *    Organizace si může libovolnou oblast nebo celou větev deaktivovat (inactive = 1).
 *    Sloupec scale_uuid umožňuje přiřadit konkrétní oblasti vlastní hodnotící
 *    škálu s vodítky (přebíjí organization.default_impact_scale_uuid); všechny
 *    škály promítají hodnocení do společné logaritmické osy 0..100 %.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - parent_uuid ukazuje na nadřízenou skupinu oblastí (impact_area.original).
 *    - scale_uuid ukazuje na individuální hodnotící škálu s vodítky (scale.original).
 *    - Spravována stromovou stránkou page_impact_area.php; prvotní data plní
 *      fillup_impact_area.sql a fillup_impact_area_en.sql.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) bez
 *      závislosti na uživatelské relaci v dbsession.
 * ============================================================================= */

IF OBJECT_ID('impact_area') IS NULL
BEGIN
	CREATE TABLE impact_area (
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
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód oblasti dopadu v snake_case (deterministický originál)
		caption varchar(200) NOT NULL DEFAULT '',          -- Název oblasti dopadu (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',         -- Zkratka oblasti do záhlaví matice BIA
		external_code varchar(200) NOT NULL DEFAULT '',    -- Kód dle externí metodiky / normy
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Stromová struktura a vazba na hodnotící škálu vodítek
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená perspektiva / skupina oblastí (impact_area.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Hodnotitelná oblast dopadu, 0 = Perspektiva / skupina oblastí
		scale_uuid uuid NULL,                              -- Volitelná individuální škála vodítek oblasti (scale.original; NULL = výchozí škála organizace)
		editor_role_uuid uuid NULL,                        -- Role pro editaci (dědí se do podřízených)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_impact_area PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka impact_area byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'impact_area', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'impact_area', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_area', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'impact_area', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_area', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_area', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'impact_area', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_area', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'impact_area', 'scale_uuid', 'uuid NULL';
EXEC p_create_missing_column 'impact_area', 'editor_role_uuid', 'uuid NULL';
EXEC p_create_missing_column 'impact_area', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'impact_area', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index
	@tname = 'impact_area',
	@iname = 'uq_impact_area_active',
	@colnames = 'original, object_owner',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'impact_area',
	@iname = 'uq_impact_area_language',
	@colnames = 'original, object_owner, language',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'impact_area',
	@iname = 'uq_impact_area_draft',
	@colnames = 'original, object_owner, language, draft_author',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'impact_area',
	@iname = 'ix_impact_area_parent_sort',
	@colnames = 'parent_uuid, sort_code, builtin_code',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'impact_area';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('impact_area','cs','T','impact_area','Oblast dopadu','Oblasti dopadů','Hierarchický katalog měřitelných oblastí dopadů na organizaci, stát a subjekt údajů (obyvatelstvo) s vazbou na hodnotící škály a vodítka.','Tvoří sloupce matice hodnocení dopadů (BIA); nevyužívané oblasti lze na úrovni organizace deaktivovat.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('impact_area','en','Impact Area','Impact Areas','Hierarchical catalog of measurable impact areas affecting the organization, state, and data subjects (citizens) linked to assessment scales and guidelines.','Forms the columns of the impact assessment (BIA) matrix; unused areas can be deactivated per organization.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'impact_area';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		referenced_class_code
	) VALUES
	('impact_area','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','impact_area'),
	('impact_area','scale_uuid','cs','Hodnotící škála a vodítka oblasti (scale_uuid)','Individuální škála vodítek (prázdné = výchozí škála organizace)','Škála vodítek','Volitelný odkaz na hodnotící škálu v tabulce scale obsahující stupně a texty vodítek specifické pro tuto oblast dopadu.','scale');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('impact_area','scale_uuid','en','Area Assessment Scale & Guidelines (scale_uuid)','Area-Specific Guideline Scale (Empty = Organization Default)','Guideline Scale','Optional reference to an assessment scale in the scale table holding levels and guideline descriptions tailored to this impact area.');
END
GO