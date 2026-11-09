/* =============================================================================
 * Verze: 2026-11-09 14:15
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