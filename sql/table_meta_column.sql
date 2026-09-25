/* =============================================================================
 * Tabulka: meta_column
 * Popis:   Uchovává metadata sloupců/proměnných v databázi a aplikacích.
 * ============================================================================= */

-- Idempotentní drop: Pokud chybí nový sloupec max_length, tabulku nekompromisně odstraníme
IF NOT EXISTS(SELECT * FROM v_syscolumns WHERE tabname='meta_column' AND colname='max_length')
BEGIN
	EXECUTE dropni 'meta_column';
END
GO

IF OBJECT_ID('meta_column') IS NULL
CREATE TABLE meta_column(
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,           -- Sem se bude zapisovat UUID organizace
	original uuid NOT NULL DEFAULT 0x00,               -- Logický identifikátor záznamu napříč verzemi a tenant overridy.
	record_type varchar(1) NOT NULL DEFAULT 'A',       -- 'A' = aktuálně schválený, 'L' = jazyková verze, 'H' = historie.
	approval_status varchar(1) NOT NULL DEFAULT 'A',   -- Stavy schvalování v rámci SSC.
	inactive bit NOT NULL DEFAULT 0,                   -- Příznak deaktivace (logické smazání).
	removed bit NOT NULL DEFAULT 0,                    -- Příznak odstranění.
	language varchar(2) NOT NULL DEFAULT 'cs',         -- Jazyková mutace (využito pro record_type = 'L').
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,

	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické atributy záznamu (Prezentační a aplikační logika)
	-- -------------------------------------------------------------------------
	parent_object uuid NOT NULL,                       -- UUID objektu, ke kterému sloupec patří (odkaz na original v meta_object)
	parent_order int NOT NULL DEFAULT 0,               -- Pořadí sloupce v objektu (číselné)
	sort_code varchar(20) NULL,                        -- Alfanumerické řazení v UI (např. 'C0018'), přebíjí fyzické pořadí
	column_name varchar(80) NOT NULL,                  -- Název položky v DB nebo formuláři
	caption varchar(200) NULL,                         -- Zobrazovaný název
	caption_plural varchar(200) NULL,                  -- Množné číslo
	description varchar(max) NULL,                     -- Rozšířený popis pro administrátory
	label varchar(200) NULL,                           -- Štítek zobrazený nad polem formuláře
	header varchar(200) NULL,                          -- Název sloupce v seznamech a grid tabulkách
	helptext varchar(max) NULL,                        -- Text nápovědy k poli
	placeholder varchar(200) NULL,                     -- Šedý text na pozadí prázdného pole
	input_type varchar(20) NULL,                       -- Typ vstupu (text, checkbox, radio, select...)
	input_width varchar(50) NULL,                      -- Šířka pole (např. '100%', '250px', 'auto')
	input_rows int NULL,                               -- Počet řádků pro textarea
	max_length int NULL,                               -- Maximální délka vstupu ve znacích pro UI validaci (HTML maxlength)
	css_class varchar(200) NULL,                       -- Třída pro formátování (např. text-right, is-warning)
	translate bit NULL,                                -- Překládat hodnoty sloupce (1/0)
	history bit NULL,                                  -- Uchovávat historii hodnot (1/0)
	
	-- UI a behaviorální příznaky
	is_html bit NULL,                                  -- Zda hodnota obsahuje RAW HTML kód (vypíná htmlspecialchars)
	is_mandatory bit NULL,                             -- Zda je pole pro odeslání formuláře povinné
	is_url bit NULL,                                   -- Zda se má hodnota v read-only režimu formátovat jako odkaz
	is_computed bit NULL,                              -- Zda jde o aplikačně kalkulovaný sloupec (neukládá se zpět do DB)
	show_empty bit NULL,                               -- Zda v detailu zobrazovat label, i když je hodnota prázdná
	hidden bit NULL,                                   -- Zda je pole v UI skryté (např. technická ID)
	customizable bit NULL,                             -- Zda si může uživatel sloupec přidat/skrýt v osobním pohledu
	
	ancestor uuid NULL,                                -- UUID předka sloupce pro dědičnost

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur (Neúčastní se dědičnosti, platí lokálně)
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,                   -- 1 = Zákaz tenant overridu ('A' záznamu)
	is_protected bit NOT NULL DEFAULT 0,               -- 1 = Povoluje tenant override jen u prezentačních vlastností

	CONSTRAINT pk_meta_columns PRIMARY KEY (uuid),

	-- -------------------------------------------------------------------------
	-- Kontrola integrity logiky předků a potomků
	-- Varianta A: Pokud je ancestor vyplněn, nesmí odkazovat sám na sebe.
	-- Varianta B: Pokud ancestor vyplněn není, MUSÍ být vlastnosti definovány.
	-- -------------------------------------------------------------------------
	CONSTRAINT chk_meta_columns_ancestor CHECK (
		(
			ancestor IS NOT NULL 
			AND ancestor <> uuid
		)
		OR 
		(
			ancestor IS NULL 
			AND ISNULL(sort_code, '') <> ''
			AND ISNULL(caption, '') <> ''
			AND ISNULL(caption_plural, '') <> ''
			AND description IS NOT NULL
			AND ISNULL(label, '') <> ''
			AND ISNULL(header, '') <> ''
			AND ISNULL(helptext, '') <> ''
			AND ISNULL(placeholder, '') <> ''
			AND ISNULL(input_type, '') <> ''
			AND ISNULL(input_width, '') <> ''
			AND input_rows IS NOT NULL
			AND max_length IS NOT NULL
			AND css_class IS NOT NULL
			AND translate IS NOT NULL
			AND history IS NOT NULL
			AND is_html IS NOT NULL
			AND is_mandatory IS NOT NULL
			AND is_url IS NOT NULL
			AND is_computed IS NOT NULL
			AND show_empty IS NOT NULL
			AND hidden IS NOT NULL
			AND customizable IS NOT NULL
		)
	)
);
GO