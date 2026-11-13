/* =============================================================================
 * Verze: 2026-11-13 16:00
 * Soubor: sysinit_reset.sql
 * Účel:   1. Idempotentní založení tabulky sysinit_constant a procedury
 *            dbo.p_update_database_version (volané ze změnových dávek changes_*.sql
 *            a čtené v system_constant.sql).
 *         2. Založení a vyčištění inicializačních tabulek sysinit_object,
 *            sysinit_class, sysinit_column, sysinit_codetable, sysinit_menu,
 *            sysinit_phrase a sysinit_link_def pro modulární plnění systémových
 *            metadat z jednotlivých DDL skriptů (table_*.sql) a frázových dávek
 *            (*#phrase.sql).
 *         3. Naplnění sysinit_column společnými RAC/SSC, auditními a systémovými
 *            sloupci (table_name = ''), aby se nemusely opakovat v každém
 *            souboru table_*.sql.
 * Vazby:  - V BuildListDb.txt zařazen těsně před changes_*.sql.
 *         - Data ze sysinit_* tabulek následně zpracovává procedura
 *           dbo.p_sysinit_process (volaná v final_scripts.sql).
 * ============================================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- =============================================================================
-- 1. Tabulka sysinit_constant a procedura dbo.p_update_database_version
-- =============================================================================
IF OBJECT_ID('sysinit_constant', 'U') IS NULL
BEGIN
	CREATE TABLE sysinit_constant (
		database_version varchar(20) NOT NULL                                   -- Poslední známá verze schématu databáze
	);
END
GO

IF NOT EXISTS (SELECT 1 FROM sysinit_constant)
BEGIN
	DECLARE @init_ver varchar(20) = '26.11.12.0';                               -- Fallback verze pro zcela novou databázi
	IF OBJECT_ID('system_constant', 'U') IS NOT NULL
	BEGIN
		SELECT TOP 1 @init_ver = ISNULL(NULLIF(database_version, ''), @init_ver)
		FROM system_constant;
	END
	INSERT INTO sysinit_constant (database_version) VALUES (@init_ver);
END
GO

EXECUTE dropni 'p_update_database_version', 'P';
GO

/* =============================================================================
 * Procedura: dbo.p_update_database_version
 * Účel:      Zapíše novou verzi databáze po úspěšném provedení změnového bloku
 *            v changes_YYMM.sql do sysinit_constant, system_constant (včetně
 *            aktualizace DEFAULT constraintu) a do provozního deníku service_logbook.
 * ============================================================================= */
CREATE PROCEDURE dbo.p_update_database_version
	@version varchar(20),                                                       -- Nová verze databáze ve formátu 'RR.MM.DD.N'
	@script_name varchar(250),                                                  -- Název změnového skriptu (např. 'changes_2611.sql')
	@content varchar(max) = NULL                                                -- Popis provedené změny pro service_logbook
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- 1. Uložení verze do trvalé tabulky sysinit_constant
	DELETE FROM sysinit_constant;
	INSERT INTO sysinit_constant (database_version) VALUES (@version);

	-- 2. Aktualizace DEFAULT constraintu a hodnoty v system_constant
	IF OBJECT_ID('system_constant', 'U') IS NOT NULL
	BEGIN
		EXEC sp_drop_default 'system_constant', 'database_version';

		DECLARE @sql_df nvarchar(400) = N'ALTER TABLE system_constant ADD CONSTRAINT df_system_constant_db_version DEFAULT '''
			+ REPLACE(@version, '''', '''''') + N''' FOR database_version;';
		EXEC sp_executesql @sql_df;

		UPDATE system_constant
		SET database_version = @version,
			date_modified = GETDATE();
	END

	-- 3. Zápis do provozního deníku service_logbook
	IF OBJECT_ID('service_logbook', 'U') IS NOT NULL
	BEGIN
		INSERT INTO service_logbook ([name], [version], content)
		VALUES (@script_name, @version, @content);
	END
END
GO

-- =============================================================================
-- 2. Založení a vyčištění staging tabulek sysinit_* pro systémová metadata
-- =============================================================================
DROP TABLE IF EXISTS sysinit_object;
DROP TABLE IF EXISTS sysinit_class;
DROP TABLE IF EXISTS sysinit_column;
DROP TABLE IF EXISTS sysinit_codetable;
DROP TABLE IF EXISTS sysinit_menu;
DROP TABLE IF EXISTS sysinit_phrase;
DROP TABLE IF EXISTS sysinit_link_def;
GO

CREATE TABLE sysinit_object (
	object_type varchar(1) NOT NULL DEFAULT 'P',                                -- T=Table, V=View, F=Function, P=PHP Page/Class, C=Column Dict
	builtin_code varchar(80) NOT NULL,                                          -- Technický název objektu nebo PHP třídy/stránky
	[language] varchar(2) NOT NULL DEFAULT 'cs',                                -- Kód jazyka ('cs', 'en', ...)
	system_role varchar(1) NOT NULL DEFAULT 'U',                                -- Minimální vyžadovaná role ('U', 'A', 'S', 'D')
	module varchar(80) NOT NULL DEFAULT '',                                     -- Licenční modul
	caption varchar(200) NOT NULL DEFAULT '',                                   -- Zobrazovaný název
	caption_plural varchar(200) NOT NULL DEFAULT '',                            -- Množné číslo názvu
	description varchar(max) NOT NULL DEFAULT '',                               -- Podrobný popis objektu
	helptext varchar(max) NOT NULL DEFAULT '',                                  -- Metodická nápověda
	editor_note varchar(max) NOT NULL DEFAULT '',                               -- Kontext pro překladatele a AI
	CONSTRAINT pk_sysinit_object PRIMARY KEY (object_type, builtin_code, [language])
);

CREATE TABLE sysinit_class (
	class_name varchar(80) NOT NULL,                                            -- Unikátní kód logické třídy v meta_class
	[language] varchar(2) NOT NULL DEFAULT 'cs',                                -- Kód jazyka ('cs', 'en', ...)
	storage_type varchar(1) NOT NULL DEFAULT 'T',                               -- Druh úložného objektu ('T', 'V', 'F', 'C')
	storage_code varchar(80) NOT NULL DEFAULT '',                               -- Název fyzické tabulky (prázdné = shodné s class_name)
	ancestor_code varchar(80) NOT NULL DEFAULT '',                              -- Kód nadřazené třídy pro STI dědičnost
	sort_code varchar(20) NOT NULL DEFAULT '',                                  -- Pořadí třídy v seznamech
	days_in_trash smallint NOT NULL DEFAULT 365,                                -- Doba uchování záznamů v koši
	is_final bit NOT NULL DEFAULT 1,                                            -- 1 = Zákaz klientského 'A' overridu
	is_protected bit NOT NULL DEFAULT 0,                                        -- 1 = Chráněná technická logika
	svg_icon varchar(max) NOT NULL DEFAULT '',                                  -- Vektorová ikona třídy
	caption varchar(200) NOT NULL DEFAULT '',                                   -- Název třídy v jednotném čísle
	caption_plural varchar(200) NOT NULL DEFAULT '',                            -- Název třídy v množném čísle
	description varchar(max) NOT NULL DEFAULT '',                               -- Popis třídy
	helptext varchar(max) NOT NULL DEFAULT '',                                  -- Nápověda ke třídě
	editor_note varchar(max) NOT NULL DEFAULT '',                               -- Kontext pro AI překlady
	CONSTRAINT pk_sysinit_class PRIMARY KEY (class_name, [language])
);

CREATE TABLE sysinit_column (
	table_name varchar(80) NOT NULL DEFAULT '',                                 -- Název tabulky/třídy ('' = globální slovník sys_global_columns)
	column_name varchar(80) NOT NULL,                                           -- Technický název sloupce
	[language] varchar(2) NOT NULL DEFAULT 'cs',                                -- Kód jazyka ('cs', 'en', ...)
	caption varchar(200) NOT NULL DEFAULT '',                                   -- Zobrazovaný název sloupce
	caption_plural varchar(200) NOT NULL DEFAULT '',                            -- Množné číslo názvu
	label varchar(200) NOT NULL DEFAULT '',                                     -- Popisek pole v editačním formuláři
	header varchar(200) NOT NULL DEFAULT '',                                    -- Záhlaví sloupce v tabulce seznamu
	helptext varchar(max) NOT NULL DEFAULT '',                                  -- Nápověda / tooltip ke sloupci
	placeholder varchar(200) NOT NULL DEFAULT '',                               -- Zástupný text v prázdném poli
	description varchar(max) NOT NULL DEFAULT '',                               -- Podrobný popis sloupce
	editor_note varchar(max) NOT NULL DEFAULT '',                               -- Kontext pro AI překlady
	sort_code varchar(20) NULL,                                                 -- Řadicí kód sloupce
	list_order int NULL,                                                        -- Pořadí sloupce v levém Master seznamu
	input_type varchar(20) NULL,                                                -- Druh vstupního prvku (text, textarea, number, date, checkbox)
	input_width varchar(50) NULL,                                               -- CSS šířka vstupního pole
	input_rows int NULL,                                                        -- Počet řádků pro textarea
	max_length int NULL,                                                        -- Maximální délka textu
	css_class varchar(200) NULL,                                                -- Doplňková CSS třída
	translate bit NULL,                                                         -- 1 = Sloupec podporuje překlad přes 'L' záznamy
	history bit NULL,                                                           -- 1 = Sledovat historii změn
	is_html bit NULL,                                                           -- 1 = Formátovaný text Markdown / HTML (rich_text)
	is_mandatory bit NULL,                                                      -- 1 = Povinné pole ve formuláři
	is_url bit NULL,                                                            -- 1 = Pole obsahuje URL adresu
	is_computed bit NULL,                                                       -- 1 = Vypočítávané pole (readonly)
	show_empty bit NULL,                                                        -- 1 = Zobrazit i prázdné pole
	hidden bit NULL,                                                            -- 1 = Skryté technické pole
	customizable bit NULL,                                                      -- 1 = Povoleno klientské přizpůsobení
	is_final bit NULL,                                                          -- 1 = Zákaz klientského 'A' overridu
	is_protected bit NULL,                                                      -- 1 = Chráněné systémové pole
	referenced_codetable varchar(80) NOT NULL DEFAULT '',                       -- Odkazovaný číselník v meta_codetable
	referenced_class_code varchar(80) NOT NULL DEFAULT '',                      -- Odkazovaná logická třída v meta_class
	CONSTRAINT pk_sysinit_column PRIMARY KEY (table_name, column_name, [language])
);

CREATE TABLE sysinit_codetable (
	codetable_name varchar(80) NOT NULL,                                        -- Kód číselníku
	value_code varchar(80) NOT NULL,                                            -- Hodnota položky číselníku
	[language] varchar(2) NOT NULL DEFAULT 'cs',                                -- Kód jazyka ('cs', 'en', ...)
	sort_code varchar(20) NOT NULL DEFAULT '',                                  -- Pořadí položky v roletce
	caption varchar(200) NOT NULL DEFAULT '',                                   -- Zobrazovaný text položky
	description varchar(max) NOT NULL DEFAULT '',                               -- Podrobný popis položky
	helptext varchar(max) NOT NULL DEFAULT '',                                  -- Nápověda k položce
	svg_icon varchar(max) NOT NULL DEFAULT '',                                  -- Volitelná SVG ikona položky
	color_code varchar(20) NOT NULL DEFAULT '',                                 -- Volitelná barva položky
	is_final bit NOT NULL DEFAULT 1,                                            -- 1 = Finální systémová položka
	is_protected bit NOT NULL DEFAULT 1,                                        -- 1 = Chráněná položka
	CONSTRAINT pk_sysinit_codetable PRIMARY KEY (codetable_name, value_code, [language])
);

CREATE TABLE sysinit_menu (
	builtin_code varchar(80) NOT NULL,                                          -- Unikátní kód položky menu
	[language] varchar(2) NOT NULL DEFAULT 'cs',                                -- Kód jazyka ('cs', 'en', ...)
	parent_code varchar(80) NOT NULL DEFAULT '',                                -- Kód nadřízené položky menu ('' = kořen)
	sort_code varchar(20) NOT NULL DEFAULT '',                                  -- Pořadí mezi sourozenci
	target_page varchar(80) NOT NULL DEFAULT '',                                -- Cílová PHP stránka (meta_object typu 'P')
	url_parameters varchar(500) NOT NULL DEFAULT '',                            -- Dodatečné GET parametry URL
	target_url varchar(500) NOT NULL DEFAULT '',                                -- Externí URL adresa
	target_window varchar(20) NOT NULL DEFAULT '',                              -- Cílové okno prohlížeče
	system_role varchar(1) NOT NULL DEFAULT 'U',                                -- Minimální požadovaná role
	permanent bit NOT NULL DEFAULT 0,                                           -- 1 = Trvale viditelná složka
	svg_icon varchar(max) NOT NULL DEFAULT '',                                  -- Vektorová ikona položky menu
	css_class varchar(200) NOT NULL DEFAULT '',                                 -- Doplňková CSS třída
	caption varchar(200) NOT NULL DEFAULT '',                                   -- Název položky v menu
	description varchar(max) NOT NULL DEFAULT '',                               -- Popis položky menu
	helptext varchar(max) NOT NULL DEFAULT '',                                  -- Nápověda / podtitulek na dlaždici
	editor_note varchar(max) NOT NULL DEFAULT '',                               -- Kontext pro AI překlady
	CONSTRAINT pk_sysinit_menu PRIMARY KEY (builtin_code, [language])
);

CREATE TABLE sysinit_phrase (
	source_code varchar(80) NOT NULL,                                           -- Zdrojová PHP třída / stránka (nebo 'global_phrase')
	builtin_code varchar(80) NOT NULL,                                          -- Kód fráze v rámci třídy
	[language] varchar(2) NOT NULL DEFAULT 'cs',                                -- Kód jazyka ('cs', 'en', ...)
	caption varchar(max) NOT NULL DEFAULT '',                                   -- Text fráze (podporuje {$promenne})
	helptext varchar(max) NOT NULL DEFAULT '',                                  -- Tooltip / nápověda (např. u tlačítka)
	editor_note varchar(max) NOT NULL DEFAULT '',                               -- Kontext pro překladatele a AI
	css_class varchar(200) NOT NULL DEFAULT '',                                 -- Doplňková CSS třída tlačítka
	svg_icon varchar(max) NOT NULL DEFAULT '',                                  -- Vektorová ikona tlačítka
	module varchar(80) NOT NULL DEFAULT '',                                     -- Licenční modul
	CONSTRAINT pk_sysinit_phrase PRIMARY KEY (source_code, builtin_code, [language])
);

CREATE TABLE sysinit_link_def (
	from_class_code varchar(80) NOT NULL,                                       -- Kód zdrojové třídy v meta_class
	link_code varchar(80) NOT NULL,                                             -- Unikátní kód vztahu v rámci zdrojové třídy
	[language] varchar(2) NOT NULL DEFAULT 'cs',                                -- Kód jazyka ('cs', 'en', ...)
	to_class_code varchar(80) NOT NULL DEFAULT '',                              -- Kód cílové třídy v meta_class
	reverse_code varchar(80) NOT NULL DEFAULT '',                               -- Kód opačného (zpětného) vztahu
	direction_type varchar(1) NOT NULL DEFAULT 'P',                             -- 'P' = primární, 'R' = zpětný, 'S' = symetrický
	is_exclusive_parent bit NOT NULL DEFAULT 0,                                 -- 1 = Odpovídá exkluzivnímu sloupci parent_uuid
	is_derived bit NOT NULL DEFAULT 0,                                          -- 1 = Odvozený vztah
	is_multiple bit NOT NULL DEFAULT 1,                                         -- 1 = Povolena vazba M:N
	is_mandatory bit NOT NULL DEFAULT 0,                                        -- 1 = Povinný vztah
	leaf_only bit NOT NULL DEFAULT 0,                                           -- 1 = Vazba pouze na koncové uzly (is_leaf = 1)
	transfer_roles bit NOT NULL DEFAULT 0,                                      -- 1 = Přenos oprávnění
	link_weight_enabled bit NOT NULL DEFAULT 0,                                 -- 1 = Povolena číselná váha vazby
	caption_forward varchar(200) NOT NULL DEFAULT '',                           -- Název vazby ze zdroje na cíl
	caption_backward varchar(200) NOT NULL DEFAULT '',                          -- Název vazby z cíle na zdroj
	description varchar(max) NOT NULL DEFAULT '',                               -- Podrobný popis vztahu
	helptext varchar(max) NOT NULL DEFAULT '',                                  -- Nápověda ke vztahu
	CONSTRAINT pk_sysinit_link_def PRIMARY KEY (from_class_code, link_code, [language])
);
GO

-- =============================================================================
-- 3. Naplnění společných RAC/SSC, auditních a systémových sloupců (table_name = '')
-- =============================================================================
INSERT INTO sysinit_column (
	table_name, column_name, [language],
	caption, label, header, helptext,
	list_order, translate, is_html, is_mandatory, hidden, is_protected,
	referenced_codetable, referenced_class_code
) VALUES
-- 3a. Společné RAC, SSC, auditní a kmenové sloupce tabulek
('','approval_note','cs','Poznámka schvalování (approval_note)','Poznámka schvalovatele / důvod','Pozn. schválení','Průvodní poznámka k návrhu nebo zdůvodnění schvalovatele při vrácení návrhu k přepracování.',NULL,0,0,0,1,0,'',''),
('','approval_status','cs','Stav schválení (approval_status)','Stav schválení (A/D/F/R)','Schválení','Stav v rámci schvalovacího cyklu: A = schváleno, D = rozpracovaný koncept, F = předáno ke schválení, R = vráceno.',NULL,0,0,0,1,0,'',''),
('','builtin','cs','Vestavěný záznam (builtin)','Vestavěný systémový záznam','Vestavěný','Příznak standardního vestavěného záznamu dodávaného se systémem.',NULL,0,0,0,0,0,'',''),
('','builtin_code','cs','Unikátní kód (builtin_code)','Kód záznamu (builtin_code)','Kód','Unikátní technický identifikátor záznamu pro deterministický výpočet originálu (u nových záznamů se předvyplní z názvu).',2,0,0,1,0,0,'',''),
('','caption','cs','Zobrazovaný název (caption)','Název','Název','Hlavní zobrazovaný název položky (podporuje překlad do dalších jazyků).',6,1,0,1,0,0,'',''),
('','caption_plural','cs','Název v množném čísle (caption_plural)','Název v množném čísle (nadpis seznamu)','Název (mn. č.)','Tvar názvu v množném čísle zobrazovaný jako nadpis přehledového seznamu v levém panelu.',NULL,1,0,0,0,0,'',''),
('','color_code','cs','Kód barvy / semaforu (color_code)','Barva (HEX / CSS kód)','Barva','Kód barvy (např. #16A34A) pro vizuální zvýraznění položky nebo stupně škály.',NULL,0,0,0,0,0,'',''),
('','css_class','cs','CSS třída (css_class)','Doplňková CSS třída','CSS třída','Volitelná CSS třída pro vizuální stylování prvku v uživatelském rozhraní.',NULL,0,0,0,0,0,'',''),
('','date_created','cs','Datum vytvoření (date_created)','Datum a čas vytvoření','Vytvořeno','Přesné datum a čas prvotního založení záznamu.',NULL,0,0,0,1,0,'',''),
('','date_modified','cs','Datum poslední změny (date_modified)','Datum a čas poslední změny','Změněno','Přesné datum a čas poslední úpravy záznamu nebo jeho jazykové mutace.',NULL,0,0,0,1,0,'',''),
('','description','cs','Popis (description)','Podrobný popis','Popis','Podrobný popis významu a účelu položky (podporuje formátování Markdown / HTML).',NULL,1,1,0,0,0,'',''),
('','description_text','cs','Popis (description_text)','Podrobný popis','Popis','Podrobný metodický nebo věcný popis položky (podporuje formátování Markdown / HTML).',NULL,1,1,0,0,0,'',''),
('','draft_author','cs','Autor návrhu (draft_author)','Autor návrhu','Autor návrhu','Identifikátor uživatelského účtu autora rozpracovaného konceptu nebo návrhu změny.',NULL,0,0,0,1,0,'',''),
('','editor_note','cs','Kontextová poznámka pro AI (editor_note)','Poznámka pro překladatele a AI','AI kontext','Sémantické upřesnění významu záznamu pro správný automatický i lidský překlad (nepřekládá se).',NULL,0,0,0,0,0,'',''),
('','editor_role_uuid','cs','Role editora (editor_role_uuid)','Role oprávněná k editaci','Role editora','Odkaz na roli oprávněnou upravovat záznamy v této větvi hierarchie (dědí se do podřízených uzlů).',NULL,0,0,0,0,0,'',''),
('','external_code','cs','Externí kód (external_code)','Externí kód (pro párování)','Ext. kód','Volitelný identifikátor pro párování záznamu s externími systémy, normami nebo katalogy.',NULL,0,0,0,0,0,'',''),
('','help_text','cs','Text nápovědy (help_text)','Nápověda (tooltip / pokyny)','Nápověda','Metodická nápověda nebo pokyny pro uživatele zobrazované u položky.',NULL,1,1,0,0,0,'',''),
('','helptext','cs','Text nápovědy (helptext)','Nápověda (tooltip / pokyny)','Nápověda','Metodická nápověda nebo pokyny pro uživatele zobrazované u položky.',NULL,1,1,0,0,0,'',''),
('','import_origin','cs','Původ importu (import_origin)','Původ záznamu z importu','Původ importu','Označení externího zdroje, balíčku nebo autora při hromadném importu dat (měkký audit).',NULL,0,0,0,1,0,'',''),
('','inactive','cs','Neaktivní záznam (inactive)','Neaktivní (deaktivováno)','Neaktivní','Příznak dočasného nebo trvalého znepřístupnění záznamu pro běžný výběr bez jeho smazání.',NULL,0,0,0,0,0,'',''),
('','instance_class_name','cs','Název třídy instance (instance_class_name)','Třída instance objektu','Třída instance','Specifické určení aplikační třídy pro instance dané kategorie.',NULL,0,0,0,0,0,'',''),
('','is_default','cs','Výchozí položka (is_default)','Výchozí hodnota (předvybraná)','Výchozí','Zaškrtněte u položky, která má být automaticky předvybrána při zakládání nového záznamu.',NULL,0,0,0,0,0,'',''),
('','is_final','cs','Finální záznam bez overridu (is_final)','Zakázat přepis v organizaci (is_final)','Finální','Pokud je zaškrtnuto (1), klientské organizace nemohou měnit věcné nastavení záznamu (mohou pouze překládat texty).',NULL,0,0,0,0,0,'',''),
('','is_leaf','cs','Koncový uzel / list (is_leaf)','Koncový uzel (list)','List','Zaškrtněte u koncové položky (listu). Odškrtněte u vnitřního uzlu (složky), pod který se budou vkládat podřízené položky.',NULL,0,0,0,0,0,'',''),
('','is_protected','cs','Chráněná technická logika (is_protected)','Chráněný systémový prvek (is_protected)','Chráněno','Omezuje klientské úpravy čistě technických a architektonických vlastností záznamu.',NULL,0,0,0,0,0,'',''),
('','is_template','cs','Příznak šablony (is_template)','Slouží jako šablona','Je šablona','Určuje, zda tento záznam slouží jako vzorová šablona pro vytváření dalších záznamů.',NULL,0,0,0,0,0,'',''),
('','language','cs','Jazyk záznamu (language)','Jazyk','Jazyk','Dvoupísmenný ISO kód jazyka záznamu nebo jazykové mutace (např. cs, en, sk, de).',NULL,0,0,0,0,0,'',''),
('','module','cs','Aplikační modul (module)','Licenční modul','Modul','Kód aplikačního nebo licenčního modulu, ke kterému objekt nebo fráze přísluší.',NULL,0,0,0,0,0,'',''),
('','note','cs','Poznámka (note)','Poznámka','Poznámka','Doplňující interní komentář nebo poznámka k záznamu (podporuje formátování Markdown / HTML).',NULL,1,1,0,0,0,'',''),
('','object_owner','cs','Vlastník objektu (object_owner)','Vlastník (organizace)','Vlastník','Identifikátor vlastnící organizace (tenanta); hodnota 0x00 označuje systémový záznam.',NULL,0,0,0,1,0,'',''),
('','original','cs','Logický identifikátor záznamu (original)','Originál (UUID objektu)','Originál','Společný logický identifikátor záznamu napříč jazykovými verzemi, koncepty a overridy.',NULL,0,0,0,1,0,'',''),
('','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).',NULL,0,0,0,0,0,'',''),
('','record_type','cs','Typ záznamu (record_type)','Typ záznamu (A/L/D/H)','Typ záz.','Určuje druh záznamu: A = schválený aktivní, L = jazyková mutace, D = koncept/návrh, H = historie.',NULL,0,0,0,1,0,'',''),
('','removed','cs','Zrušený záznam v koši (removed)','Zrušený záznam (v koši)','Zrušeno','Příznak přesunutí záznamu do koše; po uplynutí doby days_in_trash je záznam automaticky odstraněn.',NULL,0,0,0,1,0,'',''),
('','shortname','cs','Zkratka (shortname)','Zkratka','Zkratka','Zkrácené označení položky pro kompaktní výpisy, matice a štítky.',8,1,0,0,0,0,'',''),
('','sort_code','cs','Řadicí kód (sort_code)','Pořadí řazení (sort_code)','Pořadí','Kód určující pořadí položky v seznamech a mezi sourozenci ve stromu (doporučeno číslovat po desítkách: 010, 020...).',NULL,0,0,0,0,0,'',''),
('','svg_icon','cs','Vektorová ikona (svg_icon)','Vektorová ikona (SVG)','Ikona','Vektorová ikona ve formátu SVG. Dvojklikem nebo tlačítkem Upravit ikonu otevřete modální editor s kontrolou syntaxe.',NULL,0,0,0,0,0,'',''),
('','template','cs','Zdrojová šablona (template)','Vytvořeno ze šablony','Šablona','Odkaz na vzorovou šablonu, ze které byl tento záznam naklonován.',NULL,0,0,0,0,0,'',''),
('','title','cs','Titulek (title)','Titulek','Titulek','Zobrazovaný titulek nebo nadpis záznamu.',9,1,0,0,0,0,'',''),
('','uuid','cs','Primární klíč řádku (uuid)','UUID řádku','UUID','Fyzický primární klíč konkrétního řádku v databázové tabulce.',NULL,0,0,0,1,0,'',''),
('','valid_from','cs','Platnost od (valid_from)','Platnost od','Platí od','Datum počátku platnosti záznamu.',NULL,0,0,0,0,0,'',''),
('','valid_to','cs','Platnost do (valid_to)','Platnost do','Platí do','Datum ukončení platnosti záznamu (prázdné pole znamená časově neomezenou platnost).',NULL,0,0,0,0,0,'',''),
('','valid_today','cs','Platné k pracovnímu datu (valid_today)','Platné dnes','Platné','Příznak udávající, zda je záznam platný k aktuálně nastavenému pracovnímu datu.',NULL,0,0,0,0,0,'',''),
('','who_created','cs','Vytvořil uživatel (who_created)','Vytvořil (relace)','Vytvořil','Odkaz na přihlašovací relaci uživatele, který záznam původně vytvořil.',NULL,0,0,0,1,0,'',''),
('','who_modified','cs','Naposledy změnil (who_modified)','Naposledy změnil (relace)','Změnil','Odkaz na přihlašovací relaci uživatele, který provedl poslední úpravu záznamu.',NULL,0,0,0,1,0,'',''),
-- 3b. Sloupce systémových pohledů a funkcí knihovny HinkMSSQLLibrary
('','bad','cs','Zacyklená hrana (bad)','Příznak uzlu způsobujícího zacyklení','Cyklus (bad)','Příznak (1) označující koncový uzel hrany, která se vrací do již navštíveného předka na cestě.',NULL,0,0,0,0,0,'',''),
('','children','cs','Počet přímých potomků (children)','Počet navazujících uzlů větve','Potomků','Celkový počet přímých následníků daného uzlu ve vyhodnoceném grafu.',NULL,0,0,0,0,0,'',''),
('','circular','cs','Větev obsahuje cyklus (circular)','Příznak větve vedoucí k zacyklení','Větev s cyklem','Příznak (1) na všech uzlech větve, pod níž došlo k zacyklení v orientovaném grafu.',NULL,0,0,0,0,0,'',''),
('','colid','cs','ID sloupce (colid)','Pořadové číslo sloupce v tabulce','ID sloupce','Interní pořadové číslo sloupce v systémovém katalogu syscolumns.',NULL,0,0,0,0,0,'',''),
('','collation_name','cs','Řazení znakové sady (collation_name)','Název databázové kolace sloupce','Collation','Název collation použité u textového sloupce v SQL Serveru.',NULL,0,0,0,0,0,'',''),
('','colname','cs','Název sloupce (colname)','Systémový název sloupce','Sloupec','Název sloupce v systémovém katalogu databáze.',NULL,0,0,0,0,0,'',''),
('','computed_syntax','cs','Výraz počítaného sloupce (computed_syntax)','SQL vzorec počítaného sloupce','Vzorec sloupce','SQL definice výrazu pro vypočítávaný (computed) sloupec.',NULL,0,0,0,0,0,'',''),
('','current_path','cs','Aktuální cesta průchodu (current_path)','Posloupnost uzlů na cestě od kořene','Cesta v grafu','Mezerami oddělený seznam navštívených uzlů od kořene pro detekci zacyklení v grafu.',NULL,0,0,0,0,0,'',''),
('','default_constraint_name','cs','Název DEFAULT constraintu (default_constraint_name)','Systémový název DEFAULT omezení','Název defaultu','Jméno databázového constraintu zajišťujícího výchozí hodnotu sloupce.',NULL,0,0,0,0,0,'',''),
('','default_syntax','cs','Syntaxe výchozí hodnoty (default_syntax)','Definice DEFAULT constraintu','Default výraz','SQL výraz výchozí hodnoty sloupce v systémovém katalogu.',NULL,0,0,0,0,0,'',''),
('','fallback_order','cs','Pořadí v řetězci dědičnosti (fallback_order)','Pořadí jazykového fallbacku','Poř. fallbacku','Vypočtené pořadí jazyka v řetězci dědičnosti pro aktuální relaci (1 = aktivní jazyk, < 1000 = v řetězci).',NULL,0,0,0,0,0,'',''),
('','from_id','cs','Výchozí uzel hrany (from_id)','Nadřízený / výchozí uzel v grafu','Z uzlu (from_id)','Identifikátor nadřízeného uzlu hrany ve funkci f_resolve_link_diagram.',NULL,0,0,0,0,0,'',''),
('','hidden_root','cs','Skrytý kořen s předkem (hidden_root)','Uzel není vrcholem grafu (má předka)','Skrytý kořen','Příznak (1) označující startovní uzly, do nichž vede platná hrana z jiného uzlu (nejsou na vrcholu sítě).',NULL,0,0,0,0,0,'',''),
('','hierarchy_sort','cs','Stromový třídicí klíč (hierarchy_sort)','Znakový klíč průchodu stromem','Stromový klíč','Zřetězený zero-padded třídicí kód určující přesné pořadí v celém stromu.',NULL,0,0,0,0,0,'',''),
('','i','cs','Celé číslo (i)','Parsovaná celočíselná hodnota','Číslo (i)','Celočíselná hodnota vrácená funkcí f_integer_list.',NULL,0,0,0,0,0,'',''),
('','index_name','cs','Název indexu (index_name)','Systémový název indexu','Index','Název databázového indexu v sys.indexes.',NULL,0,0,0,0,0,'',''),
('','is_descending_key','cs','Sestupné řazení v indexu (is_descending_key)','Sloupec v indexu řazen sestupně (DESC)','Sestupně (DESC)','Určuje, zda je sloupec v indexu uložen v sestupném pořadí.',NULL,0,0,0,0,0,'',''),
('','is_identity','cs','Automatické číslování (is_identity)','Příznak sloupce IDENTITY','Je IDENTITY','Určuje, zda má sloupec v databázi zapnuté automatické číslování IDENTITY.',NULL,0,0,0,0,0,'',''),
('','is_included_column','cs','Inkludovaný sloupec (is_included_column)','Neklíčový sloupec přidaný přes INCLUDE','INCLUDE sloupec','Určuje, zda je sloupec připojen k indexu v klauzuli INCLUDE.',NULL,0,0,0,0,0,'',''),
('','is_primary_key','cs','Primární klíč (is_primary_key)','Index tvoří primární klíč tabulky','Primární klíč','Určuje, zda je daný index primárním klíčem tabulky.',NULL,0,0,0,0,0,'',''),
('','is_unique','cs','Unikátní index (is_unique)','Příznak unikátního indexu','Unikátní','Určuje, zda index vynucuje jedinečnost klíčových hodnot.',NULL,0,0,0,0,0,'',''),
('','iscomputed','cs','Vypočítávaný sloupec (iscomputed)','Příznak počítaného sloupce v DB','Počítaný (DB)','Příznak v systémovém katalogu udávající, zda jde o computed column.',NULL,0,0,0,0,0,'',''),
('','key_ordinal','cs','Pořadí klíče v indexu (key_ordinal)','Pořadové číslo sloupce v klíči indexu','Poř. v indexu','Pořadí sloupce v klíči databázového indexu (0 = inkludovaný sloupec).',NULL,0,0,0,0,0,'',''),
('','keyno','cs','Pořadí v primárním klíči (keyno)','Pořadí sloupce v primárním klíči','Poř. v PK','Pořadové číslo sloupce v rámci složeného primárního klíče tabulky.',NULL,0,0,0,0,0,'',''),
('','keyvalue','cs','Hodnota klíče uzlu (keyvalue)','Identifikátor uzlu ve stromu','Klíč uzlu','Identifikátor položky při výpočtu stromové hierarchie.',NULL,0,0,0,0,0,'',''),
('','level','cs','Úroveň zanoření (level)','Hloubka zanoření uzlu ve stromu','Úroveň','Číselná úroveň zanoření položky ve stromové hierarchii (0 = kořen).',NULL,0,0,0,0,0,'',''),
('','node_id','cs','Identifikátor uzlu v grafu (node_id)','Identifikátor uzlu sítě','Uzel (node_id)','Textový identifikátor uzlu při průchodu orientovaným grafem ve funkci f_resolve_link_diagram.',NULL,0,0,0,0,0,'',''),
('','nulls','cs','Povolení NULL (nulls)','Povolení hodnoty NULL (null / not null)','NULL / NOT NULL','Určuje, zda sloupec v databázi povoluje hodnotu NULL.',NULL,0,0,0,0,0,'',''),
('','num','cs','Pořadové číslo pod rodičem (num)','Pořadí uzlu mezi sourozenci','Pořadí (num)','Vypočtené pořadové číslo uzlu v rámci stejného nadřízeného prvku.',NULL,0,0,0,0,0,'',''),
('','ordr','cs','Pořadí položky v seznamu (ordr)','Pořadové číslo prvku z parsovaného seznamu','Pořadí','Pořadí položky vrácené parsovacími funkcemi f_string_list, f_integer_list a f_uuid_list.',NULL,0,0,0,0,0,'',''),
('','parent','cs','Nadřízený uzel (parent)','Identifikátor rodiče ve stromu','Rodič','Odkaz na nadřízený prvek ve funkci f_resolve_hierarchy.',NULL,0,0,0,0,0,'',''),
('','parent_path','cs','Cesta předka (parent_path)','Posloupnost uzlů k nadřízenému uzlu','Cesta předka','Cesta od kořene k bezprostředně předchozímu uzlu v orientovaném grafu.',NULL,0,0,0,0,0,'',''),
('','prec','cs','Přesnost / délka (prec)','Maximální délka nebo přesnost typu','Délka / Přesnost','Číselná délka nebo přesnost datového typu v systémovém katalogu.',NULL,0,0,0,0,0,'',''),
('','prec_syntax','cs','Syntaxe délky typu (prec_syntax)','Zápis délky/přesnosti pro DDL','Syntaxe délky','Zformátovaný zápis délky nebo přesnosti typu v závorkách, např. (200) nebo (9,4).',NULL,0,0,0,0,0,'',''),
('','root_id','cs','Kořenový uzel cesty (root_id)','Výchozí kořenový uzel stromu v grafu','Kořen (root_id)','Identifikátor vrcholového uzlu (level = 0), ze kterého vyšla daná cesta v grafu.',NULL,0,0,0,0,0,'',''),
('','row_num','cs','Číslo řádku (row_num)','Pořadové číslo řádku (0..1024)','Č. řádku','Sekvenční číslo v pomocné systémové tabulce rowgenerator.',NULL,0,0,0,0,0,'',''),
('','s','cs','Textová položka (s)','Parsovaný textový řetězec','Text (s)','Textová položka vrácená funkcí f_string_list.',NULL,0,0,0,0,0,'',''),
('','sort_order','cs','Třídicí cesta v grafu (sort_order)','Znakový klíč průchodu grafem','Pořadí v grafu','Zřetězený pětiznakový klíč určující jednoznačné pořadí větve ve funkci f_resolve_link_diagram.',NULL,0,0,0,0,0,'',''),
('','table_type','cs','Typ tabulkového objektu (table_type)','Typ objektu v sys.objects','Typ tabulky','Kód typu objektu v systémovém katalogu (U = tabulka, V = pohled).',NULL,0,0,0,0,0,'',''),
('','tabname','cs','Název tabulky (tabname)','Název tabulky / pohledu','Tabulka','Systémový název tabulky nebo pohledu v databázovém katalogu.',NULL,0,0,0,0,0,'',''),
('','typename','cs','Datový typ (typename)','Název datového typu SQL Serveru','Datový typ','Fyzický datový typ sloupce v databázi (např. varchar, int, uuid, bit).',NULL,0,0,0,0,0,'','');

-- 3c. Anglické překlady společných sloupců (zkrácená syntaxe bez netextových atributů)
INSERT INTO sysinit_column (
	table_name, column_name, [language],
	caption, label, header, helptext
) VALUES
('','approval_note','en','Approval Note (approval_note)','Approver Note / Rejection Reason','Approval Note','Accompanying note for the proposal or the approver reason when returning a draft for revision.'),
('','approval_status','en','Approval Status (approval_status)','Approval Status (A/D/F/R)','Approval','SSC lifecycle status: A = approved, D = working draft, F = forwarded for approval, R = rejected/returned.'),
('','builtin','en','Built-in Record (builtin)','Built-in System Record','Built-in','Flag indicating a standard built-in record supplied with the system.'),
('','builtin_code','en','Unique Code (builtin_code)','Record Code (builtin_code)','Code','Unique technical identifier used for deterministic original calculation (auto-derived from name on new records).'),
('','caption','en','Display Caption (caption)','Name / Caption','Name','Primary display name of the item (supports translation into other languages).'),
('','caption_plural','en','Plural Caption (caption_plural)','Plural Name (List Heading)','Plural Name','Plural form of the name displayed as the master list heading in the left panel.'),
('','color_code','en','Color Code (color_code)','Color (HEX / CSS Code)','Color','Color code (e.g., #16A34A) for visual highlighting of the item or scale level.'),
('','css_class','en','CSS Class (css_class)','Additional CSS Class','CSS Class','Optional CSS class for visual styling of the element in the user interface.'),
('','date_created','en','Date Created (date_created)','Created Date & Time','Created','Exact date and time when the record was initially created.'),
('','date_modified','en','Date Modified (date_modified)','Last Modified Date & Time','Modified','Exact date and time of the last modification of the record or its language mutation.'),
('','description','en','Description (description)','Detailed Description','Description','Detailed description of the purpose and meaning of the item (supports Markdown / HTML).'),
('','description_text','en','Description (description_text)','Detailed Description','Description','Detailed methodological or domain description of the item (supports Markdown / HTML).'),
('','draft_author','en','Draft Author (draft_author)','Draft Author','Draft Author','User account identifier of the author of the working draft or proposed change.'),
('','editor_note','en','AI Context Note (editor_note)','Translator & AI Context Note','AI Context','Semantic clarification of the record meaning for accurate human and AI translation (not translated).'),
('','editor_role_uuid','en','Editor Role (editor_role_uuid)','Role Authorized to Edit','Editor Role','Reference to the role authorized to edit records in this hierarchy branch (inherited by child nodes).'),
('','external_code','en','External Code (external_code)','External Code (for mapping)','Ext. Code','Optional identifier for mapping the record with external systems, standards, or catalogs.'),
('','help_text','en','Help Text (help_text)','Help Text (Tooltip / Guidance)','Help Text','Methodological help or user instructions displayed for the item.'),
('','helptext','en','Help Text (helptext)','Help Text (Tooltip / Guidance)','Help Text','Methodological help or user instructions displayed for the item.'),
('','import_origin','en','Import Origin (import_origin)','Record Import Origin','Import Origin','Identification of the external source, package, or author during bulk data import (soft audit).'),
('','inactive','en','Inactive Record (inactive)','Inactive (Deactivated)','Inactive','Flag temporarily or permanently disabling the record from standard selection without deleting it.'),
('','instance_class_name','en','Instance Class Name (instance_class_name)','Object Instance Class','Instance Class','Specific application class designation for instances of this category.'),
('','is_default','en','Default Item (is_default)','Default Value (Preselected)','Default','Check for the item that should be automatically preselected when creating a new record.'),
('','is_final','en','Final Record without Override (is_final)','Disallow Tenant Override (is_final)','Final','If checked (1), client organizations cannot override functional attributes of the record (only translations are allowed).'),
('','is_leaf','en','Leaf Node (is_leaf)','Leaf Node (Terminal Item)','Leaf','Check for a terminal leaf item. Uncheck for an internal folder node that will contain child items.'),
('','is_protected','en','Protected Technical Logic (is_protected)','Protected System Element (is_protected)','Protected','Restricts client modifications of purely technical and architectural properties of the record.'),
('','is_template','en','Template Flag (is_template)','Acts as Template','Is Template','Indicates whether this record serves as a master template for cloning.'),
('','language','en','Record Language (language)','Language','Language','Two-letter ISO language code of the record or language mutation (e.g., cs, en, sk, de).'),
('','module','en','Application Module (module)','Licence Module','Module','Code of the application or licensing module to which the object or phrase belongs.'),
('','note','en','Note (note)','Note','Note','Additional internal comment or note on the record (supports Markdown / HTML).'),
('','object_owner','en','Object Owner (object_owner)','Owner (Organization)','Owner','Identifier of the owning organization (tenant); 0x00 denotes a system record.'),
('','original','en','Logical Record Identifier (original)','Original (Object UUID)','Original','Shared logical identifier of the record across language versions, drafts, and tenant overrides.'),
('','parent_uuid','en','Parent Tree Node (parent_uuid)','Parent Folder / Item','Parent Node','Reference to the parent node in the tree hierarchy (empty means a top-level root item).'),
('','record_type','en','Record Type (record_type)','Record Type (A/L/D/H)','Rec. Type','Determines record kind: A = active approved, L = language mutation, D = draft/proposal, H = history.'),
('','removed','en','Removed Record in Trash (removed)','Removed Record (In Trash)','Removed','Flag moving the record to the trash bin; automatically purged after days_in_trash days.'),
('','shortname','en','Short Name (shortname)','Short Name / Abbreviation','Short Name','Abbreviated label used in compact tables, matrices, and badges.'),
('','sort_code','en','Sort Code (sort_code)','Sort Order (sort_code)','Sort Order','Code determining item order in lists and among tree siblings (recommended numbering by tens: 010, 020...).'),
('','svg_icon','en','Vector Icon (svg_icon)','Vector Icon (SVG)','Icon','SVG vector icon. Double-click or click Edit Icon to open the modal editor with XML syntax validation.'),
('','template','en','Source Template (template)','Created from Template','Template','Reference to the template from which this record was cloned.'),
('','title','en','Title (title)','Title','Title','Display title or heading of the record.'),
('','uuid','en','Row Primary Key (uuid)','Row UUID','UUID','Physical primary key of the specific row in the database table.'),
('','valid_from','en','Valid From (valid_from)','Valid From','Valid From','Start date of record validity.'),
('','valid_to','en','Valid To (valid_to)','Valid To','Valid To','End date of record validity (leave empty for unlimited validity).'),
('','valid_today','en','Valid on Working Date (valid_today)','Valid Today','Valid','Flag indicating whether the record is valid as of the currently selected working date.'),
('','who_created','en','Created By (who_created)','Created By (Session)','Created By','Reference to the login session of the user who originally created the record.'),
('','who_modified','en','Last Modified By (who_modified)','Last Modified By (Session)','Modified By','Reference to the login session of the user who performed the last modification.'),
('','bad','en','Cyclic Edge (bad)','Flag of Node Causing a Cycle','Cycle (bad)','Flag (1) marking the terminal node of an edge that loops back to an already visited ancestor on the path.'),
('','children','en','Direct Child Count (children)','Number of Subsequent Branch Nodes','Children','Total number of direct successor nodes of the given node in the resolved graph.'),
('','circular','en','Branch Contains Cycle (circular)','Flag of Branch Leading to a Cycle','Cyclic Branch','Flag (1) on all nodes of a branch under which a cycle occurred in the directed graph.'),
('','colid','en','Column ID (colid)','Column Sequential Number in Table','Col. ID','Internal sequential column number in the system syscolumns catalog.'),
('','collation_name','en','Collation Name (collation_name)','Database Column Collation Name','Collation','Collation name applied to a character column in SQL Server.'),
('','colname','en','Column Name (colname)','System Column Name','Column','Column name in the database system catalog.'),
('','computed_syntax','en','Computed Column Formula (computed_syntax)','SQL Formula of Computed Column','Computed Formula','SQL expression defining a computed column.'),
('','current_path','en','Current Traversal Path (current_path)','Sequence of Nodes from Root','Graph Path','Space-separated list of visited nodes from the root used for cycle detection in the graph.'),
('','default_constraint_name','en','Default Constraint Name (default_constraint_name)','System DEFAULT Constraint Name','Default Name','Database constraint name enforcing the column default value.'),
('','default_syntax','en','Default Value Syntax (default_syntax)','DEFAULT Constraint Definition','Default Syntax','SQL expression of the column default value in the system catalog.'),
('','fallback_order','en','Fallback Chain Order (fallback_order)','Language Fallback Order','Fallback Order','Computed language order in the fallback chain for the current session (1 = active language, < 1000 = in chain).'),
('','from_id','en','Edge Source Node (from_id)','Parent / Source Node in Graph','From Node (from_id)','Identifier of the parent source node of an edge in f_resolve_link_diagram.'),
('','hidden_root','en','Hidden Root with Predecessor (hidden_root)','Node Is Not a Graph Root (Has Predecessor)','Hidden Root','Flag (1) marking starting nodes that have an incoming valid edge from another node (not top-level roots).'),
('','hierarchy_sort','en','Tree Sort Path (hierarchy_sort)','Zero-Padded Tree Traversal Sort Key','Tree Sort Key','Concatenated zero-padded sort string determining exact tree order.'),
('','i','en','Integer Value (i)','Parsed Integer Value','Integer (i)','Integer value returned by f_integer_list.'),
('','index_name','en','Index Name (index_name)','System Index Name','Index','Database index name in sys.indexes.'),
('','is_descending_key','en','Descending Index Key (is_descending_key)','Index Column Sorted Descending (DESC)','Descending (DESC)','Indicates whether the column is sorted descending in the index.'),
('','is_identity','en','Identity Column (is_identity)','IDENTITY Auto-Increment Flag','Is IDENTITY','Indicates whether the database column uses IDENTITY auto-incrementing.'),
('','is_included_column','en','Included Column (is_included_column)','Non-Key Column Added via INCLUDE','Included Col.','Indicates whether the column is attached to the index via the INCLUDE clause.'),
('','is_primary_key','en','Primary Key (is_primary_key)','Index Forms Table Primary Key','Primary Key','Indicates whether the index represents the primary key of the table.'),
('','is_unique','en','Unique Index (is_unique)','Unique Index Flag','Unique','Indicates whether the index enforces uniqueness of key values.'),
('','iscomputed','en','Computed Column (iscomputed)','Database Computed Column Flag','Computed (DB)','System catalog flag indicating whether the column is a computed column.'),
('','key_ordinal','en','Index Key Ordinal (key_ordinal)','Column Position in Index Key','Key Ordinal','Position of the column within the index key (0 = included non-key column).'),
('','keyno','en','Primary Key Ordinal (keyno)','Column Position in Primary Key','PK Ordinal','Sequential position of the column within a composite primary key.'),
('','keyvalue','en','Node Key Value (keyvalue)','Tree Node Identifier','Node Key','Item identifier used during tree hierarchy resolution.'),
('','level','en','Nesting Level (level)','Tree Node Nesting Depth','Level','Numeric nesting depth of the item in the tree hierarchy (0 = root).'),
('','node_id','en','Graph Node Identifier (node_id)','Network Node Identifier','Node (node_id)','String identifier of a node during directed graph traversal in f_resolve_link_diagram.'),
('','nulls','en','Nullability (nulls)','NULL Permission (null / not null)','NULL / NOT NULL','Indicates whether the database column allows NULL values.'),
('','num','en','Sibling Order Number (num)','Node Order Among Siblings','Order (num)','Computed sequential number of the node under the same parent.'),
('','ordr','en','List Item Order (ordr)','Sequential Number in Parsed List','Order','Item position returned by list-splitting functions f_string_list, f_integer_list, and f_uuid_list.'),
('','parent','en','Parent Node (parent)','Parent Identifier in Tree','Parent','Reference to the parent element in f_resolve_hierarchy.'),
('','parent_path','en','Parent Traversal Path (parent_path)','Sequence of Nodes to Parent Node','Parent Path','Path from the root to the immediate predecessor node in the directed graph.'),
('','prec','en','Precision / Length (prec)','Maximum Type Length or Precision','Length / Prec.','Numeric length or precision of the data type in the system catalog.'),
('','prec_syntax','en','Length Syntax (prec_syntax)','DDL Length / Precision Syntax','Length Syntax','Formatted length or precision in parentheses for DDL statements, e.g., (200) or (9,4).'),
('','root_id','en','Path Root Node (root_id)','Initial Root Node of Graph Tree','Root (root_id)','Identifier of the top-level node (level = 0) from which the graph path originated.'),
('','row_num','en','Row Number (row_num)','Sequential Row Number (0..1024)','Row Num.','Sequential number in the helper rowgenerator system table.'),
('','s','en','String Value (s)','Parsed String Item','String (s)','String item returned by f_string_list.'),
('','sort_order','en','Graph Sort Path (sort_order)','Zero-Padded Graph Traversal Key','Graph Order','Concatenated 5-digit key determining the unique branch order in f_resolve_link_diagram.'),
('','table_type','en','Table Object Type (table_type)','Object Type in sys.objects','Table Type','Object type code in the system catalog (U = User Table, V = View).'),
('','tabname','en','Table Name (tabname)','Table / View Name','Table','System name of the table or view in the database catalog.'),
('','typename','en','Data Type (typename)','SQL Server Data Type Name','Data Type','Physical SQL data type of the column (e.g., varchar, int, uuid, bit).');
GO