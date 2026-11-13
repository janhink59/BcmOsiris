/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: table_countermeasure.sql
 * Tabulka: countermeasure (Hierarchický katalog protiopatření CRMM)
 * Popis:   Hierarchický katalog bezpečnostních, technických a organizačních
 *          protiopatření. Obsahuje dva výpočtové faktory typu decimal(9,4):
 *          - reduction_factor: redukční faktor udávající snížení zbytkového
 *            rizika scénáře při aplikaci opatření,
 *          - risk_factor: prahové skóre rizika, pod které nesmí riziko scénáře
 *            klesnout, pokud toto opatření není implementováno.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - parent_uuid ukazuje na nadřízené opatření/skupinu (countermeasure.original).
 *          - Vazby M:N na rizikové scénáře (scenario) a hrozby (threat) se
 *            ukládají do tabulky link.
 *          - Spravována stromovou stránkou page_countermeasure.php.
 * ============================================================================= */

IF OBJECT_ID('countermeasure') IS NULL
BEGIN
	CREATE TABLE countermeasure (
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
		builtin_code varchar(80) NOT NULL DEFAULT '',      -- Kód pro deterministický originál (odvozený z názvu)
		external_code varchar(40) NOT NULL DEFAULT '',     -- Kód opatření dle normy / externího systému (např. ISO 27001)
		caption varchar(200) NOT NULL DEFAULT '',          -- Název protiopatření (lokalizovatelný)
		shortname varchar(40) NOT NULL DEFAULT '',
		description_text varchar(max) NOT NULL DEFAULT '',
		help_text varchar(max) NOT NULL DEFAULT '',
		svg_icon varchar(max) NOT NULL DEFAULT '',

		-- ---------------------------------------------------------------------
		-- Stromová struktura a výpočtové faktory protiopatření
		-- ---------------------------------------------------------------------
		parent_uuid uuid NULL,                             -- Nadřízená položka v hierarchii opatření (countermeasure.original)
		sort_code varchar(200) NOT NULL DEFAULT '',        -- Pořadí v rámci sourozenců
		is_leaf bit NOT NULL DEFAULT 1,                    -- 1 = Koncové opatření, 0 = Složka (skupina opatření)
		reduction_factor decimal(9,4) NULL,                -- Redukční faktor snížení zbytkového rizika při aplikaci (0 až 100 %)
		risk_factor decimal(9,4) NULL,                     -- Rizikový faktor (dolní mez rizika při neimplementaci, 0 až 100 %)
		editor_role_uuid uuid NULL,                        -- Role pro editaci (dědí se do podřízených)

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,
		is_protected bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_countermeasure PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka countermeasure byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'countermeasure', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'countermeasure', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'countermeasure', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'countermeasure', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'countermeasure', 'reduction_factor', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'countermeasure', 'risk_factor', 'decimal(9,4) NULL';
EXEC p_create_missing_column 'countermeasure', 'editor_role_uuid', 'uuid NULL';
EXEC p_create_missing_column 'countermeasure', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'countermeasure', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'countermeasure', 
	@iname = 'uq_countermeasure_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'countermeasure', 
	@iname = 'uq_countermeasure_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'countermeasure', 
	@iname = 'uq_countermeasure_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'countermeasure', 
	@iname = 'ix_countermeasure_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'countermeasure';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('countermeasure','cs','T','countermeasure','Protiopatření','Katalog protiopatření','Hierarchický katalog bezpečnostních, technických a organizačních opatření s redukčním a rizikovým faktorem.','Obsahuje opatření ke snížení rizika scénářů a prahový rizikový faktor při neimplementaci.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('countermeasure','en','Countermeasure','Countermeasure Catalog','Hierarchical catalog of security, technical, and organizational countermeasures with reduction and risk factors.','Contains controls that reduce scenario residual risk and define minimum risk thresholds when unimplemented.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'countermeasure';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext, referenced_class_code) VALUES
	('countermeasure','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','countermeasure'),
	('countermeasure','reduction_factor','cs','Redukční faktor v % (reduction_factor)','Redukční faktor (0–100 %)','Redukce (%)','Udává míru snížení zbytkového rizika scénáře při aplikaci opatření (resp. váhu stavu opatření).',''),
	('countermeasure','risk_factor','cs','Rizikový faktor / práh v % (risk_factor)','Rizikový faktor / práh (0–100 %)','Rizikový práh (%)','Udává výsledné skóre rizika, pod které nesmí riziko scénáře klesnout, pokud opatření není implementováno.','');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('countermeasure','reduction_factor','en','Reduction Factor in % (reduction_factor)','Risk Reduction Factor (0–100%)','Reduction (%)','Specifies the residual risk reduction of a scenario when the control is applied (or the state weight).'),
	('countermeasure','risk_factor','en','Risk Factor / Threshold in % (risk_factor)','Minimum Risk Factor / Threshold (0–100%)','Risk Threshold (%)','Specifies the resulting risk score below which scenario risk cannot drop if the control is not implemented.');
END
GO