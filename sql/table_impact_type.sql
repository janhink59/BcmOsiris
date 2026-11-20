/* =============================================================================
 * Verze: 2026-11-20 17:00
 * Soubor: table_impact_type.sql
 * Tabulka: impact_type (Katalog druhů dopadů / následků CRMM)
 *
 * 1. Role souboru v celém systému:
 *    Hierarchický katalog druhů dopadů (následků), které tvoří řádky matice
 *    hodnocení dopadů (BIA / kritičnosti):
 *    - Ohrožení důvěrnosti informací (prozrazení identifikovatelným osobám,
 *      smluvním poskytovatelům, cizím osobám),
 *    - Ohrožení integrity informací (chyby menšího/většího rozsahu, úmyslná modifikace),
 *    - Ohrožení dostupnosti informací (časové intervaly výpadku 15 min až 2+ měsíce),
 *    - Ztráta dat a fyzické zničení (od poslední zálohy, úplná ztráta, fyzické zničení),
 *    - Ohrožení integrity komunikace (vložení zprávy, popření původu/přijetí, atd.).
 *    Odděleno od oblastí dopadů (impact_area), ve kterých se měřitelná velikost
 *    dopadu vyhodnocuje (sloupce matice).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - parent_uuid ukazuje na nadřízenou kategorii druhů dopadů (impact_type.original).
 *    - Vazby M:N na scénáře (scenario), datová aktiva (asset_data) a služby
 *      (asset_service) se ukládají v tabulce link dle meta_link_def.
 *    - Sloupec cia_category je napojen na číselník meta_codetable ('cia_category')
 *      a sloupec duration_minutes udává délku výpadku u položek dostupnosti (pro
 *      kontrolu monotonie a mapování na asset.rto_hours).
 *    - Spravována stromovou stránkou page_impact_type.php; prvotní data plní
 *      fillup_impact_type.sql a fillup_impact_type_en.sql.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) bez
 *      závislosti na uživatelské relaci v dbsession.
 * ============================================================================= */

IF OBJECT_ID('impact_type') IS NULL
BEGIN
	CREATE TABLE impact_type (
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
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód druhu dopadu v snake_case (deterministický originál)
		caption varchar(200) NOT NULL DEFAULT '',          -- Název druhu dopadu / následku (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',         -- Zkratka následku (např. 15M, 1D, DP, DT, DM)
		external_code varchar(200) NOT NULL DEFAULT '',    -- Kód dle metodiky CRAMM / externího katalogu
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Stromová struktura a klasifikace druhu dopadu
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená kategorie druhů dopadů (impact_type.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncový druh dopadu, 0 = Skupina / kategorie
		cia_category varchar(20) NOT NULL DEFAULT '',      -- Kategorie CIA: CONFIDENTIALITY, INTEGRITY, AVAILABILITY, DESTRUCTION, COMMUNICATION
		duration_minutes int NULL,                         -- Délka výpadku v minutách (pouze pro druhy dopadů dostupnosti)
		editor_role_uuid uuid NULL,                        -- Role pro editaci (dědí se do podřízených)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_impact_type PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka impact_type byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'impact_type', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'impact_type', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_type', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'impact_type', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_type', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_type', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'impact_type', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_type', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'impact_type', 'cia_category', 'varchar(20) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'impact_type', 'duration_minutes', 'int NULL';
EXEC p_create_missing_column 'impact_type', 'editor_role_uuid', 'uuid NULL';
EXEC p_create_missing_column 'impact_type', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'impact_type', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index
	@tname = 'impact_type',
	@iname = 'uq_impact_type_active',
	@colnames = 'original, object_owner',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'impact_type',
	@iname = 'uq_impact_type_language',
	@colnames = 'original, object_owner, language',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'impact_type',
	@iname = 'uq_impact_type_draft',
	@colnames = 'original, object_owner, language, draft_author',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'impact_type',
	@iname = 'ix_impact_type_parent_sort',
	@colnames = 'parent_uuid, sort_code, builtin_code',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy, číselníku cia_category a sloupců do sysinit_*
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'impact_type';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('impact_type','cs','T','impact_type','Druh dopadu (následek)','Druhy dopadů (následky)','Hierarchický katalog druhů dopadů a následků (prozrazení, chyby integrity, nedostupnost podle délky výpadku, ztráta dat, narušení komunikace).','Tvoří řádky matice hodnocení dopadů (BIA) a spojuje rizikové scénáře s konkrétní povahou poškození aktiv.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('impact_type','en','Impact Type (Consequence)','Impact Types (Consequences)','Hierarchical catalog of impact types and consequences (disclosure, integrity errors, outage durations, data destruction, communication tampering).','Forms the rows of the impact assessment (BIA) matrix and links risk scenarios to the nature of asset harm.');
END

IF OBJECT_ID('sysinit_codetable', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_codetable WHERE codetable_name = 'cia_category';

	INSERT INTO sysinit_codetable (codetable_name, value_code, [language], sort_code, caption) VALUES
	('cia_category','AVAILABILITY','cs','030','Dostupnost (výpadky)'),
	('cia_category','COMMUNICATION','cs','050','Integrita a důvěrnost komunikace'),
	('cia_category','CONFIDENTIALITY','cs','010','Důvěrnost (prozrazení)'),
	('cia_category','DESTRUCTION','cs','040','Ztráta dat a fyzické zničení'),
	('cia_category','INTEGRITY','cs','020','Integrita informací (chyby / modifikace)'),
	('cia_category','AVAILABILITY','en','030','Availability (Outages)'),
	('cia_category','COMMUNICATION','en','050','Communication Integrity & Confidentiality'),
	('cia_category','CONFIDENTIALITY','en','010','Confidentiality (Disclosure)'),
	('cia_category','DESTRUCTION','en','040','Data Loss & Physical Destruction'),
	('cia_category','INTEGRITY','en','020','Information Integrity (Errors / Modification)');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'impact_type';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		referenced_codetable, referenced_class_code
	) VALUES
	('impact_type','cia_category','cs','Kategorie CIA (cia_category)','Kategorie narušení bezpečnosti (CIA)','Kategorie CIA','Zařazení druhu dopadu do hlavní bezpečnostní dimenze (Důvěrnost, Integrita, Dostupnost, Ztráta/Zničení, Komunikace).','cia_category',''),
	('impact_type','duration_minutes','cs','Délka výpadku v minutách (duration_minutes)','Délka výpadku (minuty)','Výpadek (min)','Časová délka nedostupnosti v minutách pro druhy dopadů typu Dostupnost (slouží ke kontrole monotonie a vazbě na RTO).','',''),
	('impact_type','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','','impact_type');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('impact_type','cia_category','en','CIA Category (cia_category)','Security Breach Category (CIA)','CIA Category','Classification of the impact type into a primary security dimension (Confidentiality, Integrity, Availability, Destruction, Communication).'),
	('impact_type','duration_minutes','en','Outage Duration in Minutes (duration_minutes)','Outage Duration (Minutes)','Outage (min)','Duration of unavailability in minutes for Availability impact types (used for monotonicity checks and RTO mapping).');
END
GO