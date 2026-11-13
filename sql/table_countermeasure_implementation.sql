/* =============================================================================
 * Verze: 2026-11-13 17:00
 * Soubor: table_countermeasure_implementation.sql
 * Tabulka: countermeasure_implementation (Implementace protiopatření na aktivech)
 * Popis:   Eviduje skutečný stav zavedení bezpečnostního, technického nebo
 *          organizačního protiopatření (countermeasure) na konkrétním aktivu
 *          nebo prostoru (asset) a jeho efektivní redukční a rizikový faktor.
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - asset_uuid ukazuje na asset.original.
 *          - countermeasure_uuid ukazuje na countermeasure.original.
 *          - state_uuid ukazuje na countermeasure_state.original.
 *          - responsible_user_uuid ukazuje na user_account.original.
 *          - Deterministický klíč original se počítá ze dvojice
 *            (asset_uuid, countermeasure_uuid) přes meta_original_keys.
 * ============================================================================= */

IF OBJECT_ID('countermeasure_implementation') IS NULL
BEGIN
	CREATE TABLE countermeasure_implementation (
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
		-- Klíčové vazby implementace opatření a prezentační údaje
		-- ---------------------------------------------------------------------
		asset_uuid uuid NOT NULL,                                            -- Chráněné aktivum / prostor (asset.original)
		countermeasure_uuid uuid NOT NULL,                                   -- Aplikované protiopatření (countermeasure.original)
		state_uuid uuid NULL,                                                -- Aktuální stav zavedení opatření (countermeasure_state.original)
		builtin_code varchar(80) NOT NULL DEFAULT '',                        -- Doplňkový technický kód záznamu
		external_code varchar(40) NOT NULL DEFAULT '',                       -- Kód pro párování s externími systémy / auditem
		caption varchar(200) NOT NULL DEFAULT '',                            -- Zobrazovaný popis implementace (lokalizovatelný)
		description_text varchar(max) NOT NULL DEFAULT '',                   -- Popis způsobu realizace opatření (is_html = 1)
		note varchar(max) NOT NULL DEFAULT '',                               -- Interní poznámka / zjištění z kontroly (is_html = 1)

		-- ---------------------------------------------------------------------
		-- Odpovědnost, termíny a efektivní výpočtové faktory (0 až 100 %)
		-- ---------------------------------------------------------------------
		responsible_user_uuid uuid NULL,                                     -- Osoba odpovědná za zavedení / provoz opatření (user_account.original)
		target_date date NULL,                                               -- Plánovaný termín zavedení opatření
		completion_date date NULL,                                           -- Skutečné datum dokončení / ověření opatření
		effective_reduction_factor decimal(9,4) NOT NULL DEFAULT 0.0000,     -- Efektivní redukční faktor (součin opatření × stav, 0 až 100 %)
		effective_risk_factor decimal(9,4) NOT NULL DEFAULT 0.0000,          -- Efektivní prahový rizikový faktor při neimplementaci (0 až 100 %)

		CONSTRAINT pk_countermeasure_implementation PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka countermeasure_implementation byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'countermeasure_implementation', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'countermeasure_implementation', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_implementation', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'countermeasure_implementation', 'state_uuid', 'uuid NULL';
EXEC p_create_missing_column 'countermeasure_implementation', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_implementation', 'external_code', 'varchar(40) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_implementation', 'note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'countermeasure_implementation', 'responsible_user_uuid', 'uuid NULL';
EXEC p_create_missing_column 'countermeasure_implementation', 'target_date', 'date NULL';
EXEC p_create_missing_column 'countermeasure_implementation', 'completion_date', 'date NULL';
EXEC p_create_missing_column 'countermeasure_implementation', 'effective_reduction_factor', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
EXEC p_create_missing_column 'countermeasure_implementation', 'effective_risk_factor', 'decimal(9,4) NOT NULL DEFAULT 0.0000';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a rychlých přepočtů rizik
-- -----------------------------------------------------------------------------
EXEC sp_create_index
	@tname = 'countermeasure_implementation',
	@iname = 'uq_countermeasure_implementation_active',
	@colnames = 'original, object_owner',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'countermeasure_implementation',
	@iname = 'uq_countermeasure_implementation_language',
	@colnames = 'original, object_owner, language',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'countermeasure_implementation',
	@iname = 'uq_countermeasure_implementation_draft',
	@colnames = 'original, object_owner, language, draft_author',
	@uni = 'UNIQUE',
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'countermeasure_implementation',
	@iname = 'ix_cm_impl_asset',
	@colnames = 'object_owner, asset_uuid, countermeasure_uuid',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index
	@tname = 'countermeasure_implementation',
	@iname = 'ix_cm_impl_cm',
	@colnames = 'object_owner, countermeasure_uuid, asset_uuid',
	@uni = '',
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'countermeasure_implementation';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('countermeasure_implementation','cs','T','countermeasure_implementation','Implementace protiopatření','Implementace protiopatření','Evidence stavu zavedení jednotlivých bezpečnostních protiopatření u konkrétních aktiv a prostorů.','Sleduje skutečný stav implementace opatření na aktivech a jeho vliv na snížení zbytkového rizika.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('countermeasure_implementation','en','Countermeasure Implementation','Countermeasure Implementations','Registry of the implementation state of security countermeasures on specific assets and spaces.','Tracks actual implementation status of controls on assets and its effect on residual risk reduction.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'countermeasure_implementation';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		is_mandatory, is_computed, referenced_class_code
	) VALUES
	('countermeasure_implementation','asset_uuid','cs','Hodnocené / chráněné aktivum (asset_uuid)','Aktivum / prostor','Aktivum','Odkaz na hodnocené nebo chráněné aktivum či prostor v tabulce asset.',1,0,'asset'),
	('countermeasure_implementation','completion_date','cs','Datum dokončení (completion_date)','Skutečné datum dokončení / ověření','Dokončeno dne','Skutečné datum zavedení a ověření funkčnosti protiopatření.',0,0,''),
	('countermeasure_implementation','countermeasure_uuid','cs','Aplikované protiopatření (countermeasure_uuid)','Protiopatření z katalogu','Protiopatření','Odkaz na bezpečnostní, technické nebo organizační opatření v tabulce countermeasure.',1,0,'countermeasure'),
	('countermeasure_implementation','effective_reduction_factor','cs','Efektivní redukční faktor v % (effective_reduction_factor)','Efektivní redukce rizika (0–100 %)','Ef. redukce (%)','Vypočtený součin redukčního faktoru opatření a váhy jeho stavu v procentech (0 až 100 %).',0,1,''),
	('countermeasure_implementation','effective_risk_factor','cs','Efektivní prahový rizikový faktor v % (effective_risk_factor)','Efektivní spodní práh rizika (0–100 %)','Ef. práh rizika (%)','Vypočtený součin rizikového faktoru opatření a váhy jeho stavu při neimplementaci (0 až 100 %).',0,1,''),
	('countermeasure_implementation','responsible_user_uuid','cs','Odpovědná osoba (responsible_user_uuid)','Osoba odpovědná za opatření','Odpovědná osoba','Odkaz na uživatelský účet osoby odpovědné za zavedení a provoz protiopatření.',0,0,'user_account'),
	('countermeasure_implementation','state_uuid','cs','Stav zavedení opatření (state_uuid)','Stav implementace protiopatření','Stav opatření','Odkaz na aktuální stav realizace opatření v číselníku countermeasure_state.',0,0,'countermeasure_state'),
	('countermeasure_implementation','target_date','cs','Cílový termín realizace (target_date)','Plánovaný termín zavedení','Termín (plán)','Plánované datum dokončení implementace protiopatření.',0,0,'');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('countermeasure_implementation','asset_uuid','en','Assessed / Protected Asset (asset_uuid)','Asset / Space','Asset','Reference to the assessed or protected asset or space in the asset table.'),
	('countermeasure_implementation','completion_date','en','Completion Date (completion_date)','Actual Completion / Verification Date','Completed On','Actual date when the countermeasure was implemented and verified.'),
	('countermeasure_implementation','countermeasure_uuid','en','Applied Countermeasure (countermeasure_uuid)','Catalog Countermeasure','Countermeasure','Reference to the security, technical, or organizational control in the countermeasure table.'),
	('countermeasure_implementation','effective_reduction_factor','en','Effective Reduction Factor in % (effective_reduction_factor)','Effective Risk Reduction (0–100%)','Eff. Reduction (%)','Calculated product of the countermeasure reduction factor and its state weight in percent (0 to 100%).'),
	('countermeasure_implementation','effective_risk_factor','en','Effective Risk Floor Factor in % (effective_risk_factor)','Effective Minimum Risk Floor (0–100%)','Eff. Risk Floor (%)','Calculated product of the countermeasure risk factor and its state weight when unimplemented (0 to 100%).'),
	('countermeasure_implementation','responsible_user_uuid','en','Responsible Person (responsible_user_uuid)','Person Responsible for Countermeasure','Responsible Person','Reference to the user account of the person responsible for implementing and operating the countermeasure.'),
	('countermeasure_implementation','state_uuid','en','Countermeasure Implementation State (state_uuid)','Countermeasure Implementation State','Control State','Reference to the current implementation state in the countermeasure_state codetable.'),
	('countermeasure_implementation','target_date','en','Target Implementation Date (target_date)','Planned Implementation Date','Target Date','Planned completion date for countermeasure implementation.');
END
GO