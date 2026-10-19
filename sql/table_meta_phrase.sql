/* =============================================================================
 * Verze: 2026-10-19 23:40
 * Soubor: table_meta_phrase.sql
 * Tabulka: meta_phrase
 * Popis:   Uchovává textové fráze, popisky tlačítek, chybová hlášení a šablony
 *          zpráv s podporou proměnných {$var}, tooltipů a SVG ikon.
 *          Každá fráze je jednoznačně vázána na svou zdrojovou PHP třídu/modul
 *          (source_code) a svůj lokální identifikátor (builtin_code).
 *
 * Vazby na okolí:
 * - Deterministický klíč original se počítá přes meta_original_keys ze složek
 *   (source_code, builtin_code) pomocí triggeru trgo_meta_phrase.
 * - Sloupec source_code odpovídá názvu PHP třídy / souboru bez přípony .php
 *   (např. 'abstract_page', 'abstract_button', 'user_context', 'page_org_users').
 * - Plněno vývojářským importem z Excelu (p_xlsx_meta_object) a případně
 *   automatickým záchytem chybějících frází za běhu aplikace.
 * - Pro editaci v administraci využívá standardní entity_manager('meta_phrase').
 *
 * Změny:
 * - 2026-10-19 23:40: Doplněny sloupce draft_author a approval_note přímo do
 *   CREATE TABLE, změnových příkazů p_create_missing_column a index uq_meta_phrase_draft.
 * ============================================================================= */

-- Idempotentní odstranění staré verze tabulky (pokud ještě neobsahuje sloupec svg_icon)
IF OBJECT_ID('meta_phrase') IS NOT NULL
	AND NOT EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_phrase' AND colname = 'svg_icon')
BEGIN
	EXECUTE dropni 'meta_phrase';
END
GO

IF OBJECT_ID('meta_phrase') IS NULL
BEGIN
	CREATE TABLE meta_phrase(
		-- ---------------------------------------------------------------------
		-- Standardní RAC a SSC sloupce
		-- ---------------------------------------------------------------------
		uuid uuid NOT NULL,                                                -- Primární klíč záznamu
		object_owner uuid NOT NULL DEFAULT 0x00,                           -- Vlastník záznamu (0x00 = systémová fráze)
		original uuid NOT NULL DEFAULT 0x00,                               -- Deterministický logický identifikátor fráze
		record_type varchar(1) NOT NULL DEFAULT 'A',                       -- Typ záznamu ('A' = aktivní, 'L' = překlad, 'D' = koncept, 'H' = historie)
		approval_status varchar(1) NOT NULL DEFAULT 'A',                   -- Stav schválení v rámci SSC ('A', 'D', 'F', 'R')
		draft_author uuid NOT NULL DEFAULT 0x00,                           -- Autor konceptu (user_account.original)
		approval_note varchar(max) NOT NULL DEFAULT '',                    -- Poznámka schvalovatele / důvod vrácení
		inactive bit NOT NULL DEFAULT 0,                                   -- Příznak deaktivace záznamu
		removed bit NOT NULL DEFAULT 0,                                    -- Příznak smazání záznamu
		language varchar(2) NOT NULL DEFAULT 'cs',                         -- Jazyk záznamu (pro 'A' výchozí, pro 'L' a 'D' cílový)
		valid_from date NOT NULL DEFAULT '1970-01-01',                     -- Datum počátku platnosti
		valid_to date NULL,                                                -- Datum konce platnosti
		is_template bit NOT NULL DEFAULT 0,                                -- Příznak šablony
		template uuid NULL,                                                -- Odkaz na šablonu
		import_origin varchar(255) NULL,                                   -- Původ záznamu z importu (měkký audit)

		-- ---------------------------------------------------------------------
		-- Auditní stopy (vázané na audit_login_session přes dbsession)
		-- ---------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT getdate(),                  -- Datum a čas vytvoření
		who_created uuid NOT NULL DEFAULT 0x00,                            -- Identifikátor relace tvůrce
		date_modified datetime NOT NULL DEFAULT getdate(),                 -- Datum a čas poslední úpravy
		who_modified uuid NOT NULL DEFAULT 0x00,                           -- Identifikátor relace posledního editora

		-- ---------------------------------------------------------------------
		-- Identifikace a zařazení fráze
		-- ---------------------------------------------------------------------
		source_code varchar(80) NOT NULL DEFAULT '',                       -- Název vlastnící PHP třídy / souboru (např. 'abstract_page')
		builtin_code varchar(80) NOT NULL,                                 -- Kód fráze v rámci třídy (např. 'btn_save', 'confirm_delete')
		module varchar(80) NOT NULL DEFAULT '',                            -- Volitelné zařazení do licenčního modulu

		-- ---------------------------------------------------------------------
		-- Prezentační texty a kontext pro překlad
		-- ---------------------------------------------------------------------
		caption varchar(max) NOT NULL DEFAULT '',                          -- Hlavní text fráze (překládaný, podporuje {$promenne})
		helptext varchar(max) NOT NULL DEFAULT '',                         -- Text nápovědy / tooltipu (překládaný, např. title tlačítka)
		editor_note varchar(max) NOT NULL DEFAULT '',                      -- Sémantický kontext pro překladatele a AI (nepřekládá se)

		-- ---------------------------------------------------------------------
		-- Vizuální atributy (pro tlačítka a UI komponenty)
		-- ---------------------------------------------------------------------
		svg_icon varchar(max) NOT NULL DEFAULT '',                         -- Vektorová ikona SVG (nepřekládá se)
		css_class varchar(200) NOT NULL DEFAULT '',                        -- Doplňková CSS třída (např. 'btn-success', 'btn-danger')

		-- ---------------------------------------------------------------------
		-- Ochrana systémových struktur (limity klientského overridu)
		-- ---------------------------------------------------------------------
		is_final bit NOT NULL DEFAULT 0,                                   -- 1 = Zakazuje tenantovi měnit 'A' záznam (povolí jen 'L')
		is_protected bit NOT NULL DEFAULT 0,                               -- 1 = Chráněná technická konfigurace

		CONSTRAINT pk_meta_phrase PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka meta_phrase byla vytvořena.';
END
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_phrase', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_phrase', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'meta_phrase', 'import_origin', 'varchar(255) NULL';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a rychlého načítání frází podle třídy
-- -----------------------------------------------------------------------------

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka a originál
EXEC sp_create_index 
	@tname = 'meta_phrase', 
	@iname = 'uq_meta_phrase_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Zajištění unikátnosti jazykových verzí (Language) pro daného vlastníka a originál
EXEC sp_create_index 
	@tname = 'meta_phrase', 
	@iname = 'uq_meta_phrase_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- Zajištění unikátnosti konceptu (Draft) pro kombinaci originál, vlastník, jazyk a autor konceptu
EXEC sp_create_index 
	@tname = 'meta_phrase', 
	@iname = 'uq_meta_phrase_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

-- Optimalizační index pro okamžité načtení všech frází konkrétní PHP třídy (source_code)
EXEC sp_create_index 
	@tname = 'meta_phrase', 
	@iname = 'ix_meta_phrase_source_lookup', 
	@colnames = 'source_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0 AND inactive = 0';
GO