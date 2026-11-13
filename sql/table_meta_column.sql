/* =============================================================================
 * Soubor: table_meta_column.sql
 * Verze: 2026-11-13 17:15
 * Tabulka: meta_column
 * Popis:   Uchovává metadata sloupců/proměnných v databázi a aplikacích.
 * Vazby:   Podklad pro entity_manager. Definuje vlastnosti formulářů a 
 *          rozšíření základních definic globálního slovníku (meta_class.original).
 *          Odkazuje na meta_codetable a meta_class pro datové <select> prvky.
 *          Plněno automaticky procedurou p_fix_meta_column, p_sysinit_process a importem p_xlsx_meta_object.
 * Změny:   - 2026-11-13 17:15: Doplněna registrace třídy a sloupců do sysinit_class
 *            a sysinit_column.
 *          - 2026-10-18 17:15: Přidán sloupec editor_note pro kontext AI překladů,
 *            sloupce draft_author a approval_note pro SSC a unikátní indexy
 *            uq_meta_column_active a uq_meta_column_language.
 * ============================================================================= */

-- Idempotentní odstranění tabulky, pokud obsahuje starou vazbu na fyzický objekt
IF EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'meta_column' AND colname = 'parent_object')
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
	object_owner uuid NOT NULL DEFAULT 0x00,
	original uuid NOT NULL DEFAULT 0x00,
	record_type varchar(1) NOT NULL DEFAULT 'A',
	approval_status varchar(1) NOT NULL DEFAULT 'A',
	draft_author uuid NOT NULL DEFAULT 0x00,                               -- Autor konceptu (user_account.original)
	approval_note varchar(max) NOT NULL DEFAULT '',                        -- Poznámka schvalovatele / důvod vrácení
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,                                       -- Původní textový autor/systém z importu (Měkký audit)

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
	parent_class uuid NOT NULL,                                            -- STRUKTURÁLNÍ VAZBA: Ukazuje na meta_class.original. Definuje, ke které logické třídě (entitě) tento sloupec fyzicky patří.
	parent_order int NOT NULL DEFAULT 0,
	sort_code varchar(20) NULL,
	column_name varchar(80) NOT NULL,
	
	-- Nastavení pro Master panel (Seznam záznamů)
	list_order int NULL,                                                   -- Pokud je vyplněno, sloupec se zobrazí v levém panelu v tomto pořadí
	
	caption varchar(200) NULL,
	caption_plural varchar(200) NULL,
	description varchar(max) NULL,
	label varchar(200) NULL,
	header varchar(200) NULL,
	helptext varchar(max) NULL,
	placeholder varchar(200) NULL,
	editor_note varchar(max) NULL,                                         -- Sémantický kontext pro překladatele a AI (nepřekládá se)
	input_type varchar(20) NULL,
	input_width varchar(50) NULL,
	input_rows int NULL,
	max_length int NULL,
	css_class varchar(200) NULL,
	translate bit NULL,
	history bit NULL,
	is_html bit NULL,
	is_mandatory bit NULL,
	is_url bit NULL,
	is_computed bit NULL,
	show_empty bit NULL,
	hidden bit NULL,
	customizable bit NULL,
	
	ancestor uuid NULL,                                                    -- METADATOVÁ DĚDIČNOST: Ukazuje na meta_column.original (obvykle v sys_global_columns). Pokud je zde hodnota NULL, převezme se z tohoto předka.
	
	-- Odkazy pro dynamické <select> prvky v entity_manager
	referenced_codetable varchar(80) NOT NULL DEFAULT '',                  -- DATOVÁ VAZBA: Název číselníku z meta_codetable, odkud se mají načítat hodnoty pro rozevírací seznamy.
	referenced_class uuid NULL,                                            -- DATOVÁ VAZBA: Ukazuje na meta_class.original. Používá se pro relační vazby cizích klíčů na jiné entity.

	-- -------------------------------------------------------------------------
	-- Ochrana systémových struktur
	-- -------------------------------------------------------------------------
	is_final bit NOT NULL DEFAULT 0,
	is_protected bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_meta_columns PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'meta_column', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'meta_column', 'editor_note', 'varchar(max) NULL';
EXEC p_create_missing_column 'meta_column', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'meta_column', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'meta_column', 
	@iname = 'uq_meta_column_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'meta_column', 
	@iname = 'uq_meta_column_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'meta_column';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('meta_column','cs','T','meta_column','Sloupec metadat','Sloupce metadat','Definice vlastností, popisků, formulářových prvků a vazeb jednotlivých sloupců logických tříd.','Umožňuje přizpůsobit popisky polí ve formulářích, záhlaví seznamů, nápovědu a pořadí zobrazení.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('meta_column','en','Metadata Column','Metadata Columns','Definition of properties, labels, form controls, and relations for columns of logical classes.','Allows customizing form field labels, list headers, tooltips, and display order.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'meta_column';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		list_order, translate, is_mandatory, referenced_class_code
	) VALUES
	('meta_column','ancestor','cs','Předek sloupce (ancestor)','Předek v globálním slovníku sloupců','Předek sloupce','Odkaz na výchozí definici sloupce ve třídě sys_global_columns, ze které sloupec dědí nevyplněné vlastnosti.',NULL,0,0,'meta_column'),
	('meta_column','column_name','cs','Technický název sloupce (column_name)','Technický název sloupce','Sloupec','Přesný databázový identifikátor sloupce v úložné tabulce nebo pohledu.',4,0,1,''),
	('meta_column','customizable','cs','Povolit přizpůsobení (customizable)','Povolit klientské přizpůsobení','Upravitelné','Určuje, zda si může organizace (tenant) upravit vlastnosti tohoto sloupce.',NULL,0,0,''),
	('meta_column','header','cs','Záhlaví sloupce v tabulce (header)','Záhlaví sloupce v seznamu (header)','Záhlaví (Header)','Krátký nadpis sloupce používaný v záhlaví přehledových tabulek a seznamů.',NULL,1,0,''),
	('meta_column','hidden','cs','Skrytý sloupec (hidden)','Skrýt pole v běžném formuláři','Skryté','Technický sloupec, který se běžně nezobrazuje v editačních formulářích detailu.',NULL,0,0,''),
	('meta_column','history','cs','Sledovat historii (history)','Ukládat historické verze (H)','Historie','Určuje, zda se při změně hodnoty sloupce má vytvářet historický snímek typu H.',NULL,0,0,''),
	('meta_column','input_rows','cs','Počet řádků textového pole (input_rows)','Počet řádků (pro textarea)','Řádků pole','Výška víceřádkového textového pole (textarea) udaná počtem viditelných řádků.',NULL,0,0,''),
	('meta_column','input_type','cs','Typ vstupního prvku (input_type)','Typ formulářového prvku','Typ prvku','Druh HTML prvku v detailu (text, textarea, number, date, checkbox).',NULL,0,0,''),
	('meta_column','input_width','cs','Šířka vstupního pole (input_width)','Šířka vstupního pole (CSS)','Šířka pole','CSS šířka formulářového prvku v detailu (např. 100%, 180px, auto).',NULL,0,0,''),
	('meta_column','is_computed','cs','Vypočítávaný sloupec (is_computed)','Vypočítávaný sloupec (jen pro čtení)','Počítaný','Sloupec je počítán databází nebo aplikací a ve formuláři je vždy uzamčen pouze pro čtení.',NULL,0,0,''),
	('meta_column','is_html','cs','Formátovaný text Markdown/HTML (is_html)','Formátovaný text (Markdown / HTML)','Rich-text','Zapíná podporu formátovaného textu s náhledem a modálním Toast UI Editorem (Markdown / HTML).',NULL,0,0,''),
	('meta_column','is_mandatory','cs','Povinná položka (is_mandatory)','Povinné pole (vyžadováno)','Povinné','Označuje pole, které musí být před uložením formuláře vždy vyplněno.',NULL,0,0,''),
	('meta_column','is_url','cs','Obsahuje URL adresu (is_url)','Pole obsahuje URL odkaz','Je URL','Validuje a formátuje vstupní pole jako webovou URL adresu.',NULL,0,0,''),
	('meta_column','label','cs','Popisek pole ve formuláři (label)','Popisek pole v detailu (label)','Popisek (Label)','Text návěstí zobrazovaný vlevo u vstupního pole v detailním editačním formuláři.',NULL,1,0,''),
	('meta_column','list_order','cs','Pořadí v levém seznamu (list_order)','Pořadí sloupce v seznamu (Master)','Poř. v seznamu','Pokud je vyplněno kladné číslo, sloupec se zobrazuje v přehledové tabulce levého panelu v tomto pořadí.',NULL,0,0,''),
	('meta_column','max_length','cs','Maximální délka textu (max_length)','Maximální počet znaků','Max. délka','Maximální povolený počet znaků v textovém poli odpovídající definici v databázi.',NULL,0,0,''),
	('meta_column','parent_class','cs','Patří ke třídě (parent_class)','Nadřízená logická třída','Třída','Strukturální vazba určující, ke které logické třídě tento sloupec patří.',NULL,0,1,'meta_class'),
	('meta_column','parent_order','cs','Pořadí sloupce v tabulce (parent_order)','Pořadí sloupce ve třídě','Poř. sloupce','Číselné pořadí sloupce převzaté z fyzické struktury databázové tabulky.',NULL,0,0,''),
	('meta_column','placeholder','cs','Zástupný text pole (placeholder)','Zástupný text v prázdném poli','Placeholder','Nápovědný text zobrazený šedě přímo uvnitř nevyplněného vstupního pole (překládá se).',NULL,1,0,''),
	('meta_column','referenced_class','cs','Odkazovaná třída (referenced_class)','Navázaná logická třída (cizí klíč)','Odkazovaná třída','Odkaz na cílovou logickou třídu v meta_class pro výběr souvisejícího záznamu z rozevíracího seznamu.',NULL,0,0,'meta_class'),
	('meta_column','referenced_codetable','cs','Odkazovaný číselník (referenced_codetable)','Navázaný systémový číselník','Číselník','Kód číselníku v tabulce meta_codetable, odkud se plní rozevírací seznam (<select>) tohoto pole.',NULL,0,0,''),
	('meta_column','show_empty','cs','Zobrazovat i prázdné (show_empty)','Zobrazit pole i když je prázdné','Zobr. prázdné','Určuje, zda se má pole zobrazovat v přehledech i v případě nevyplněné hodnoty.',NULL,0,0,''),
	('meta_column','translate','cs','Podporuje překlad (translate)','Překládaný sloupec (jazykové verze L)','Překlad','Určuje, zda hodnota sloupce podléhá překladu do dalších jazyků přes záznamy typu L.',NULL,0,0,'');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('meta_column','ancestor','en','Column Ancestor (ancestor)','Ancestor in Global Column Dictionary','Ancestor Column','Reference to the base column definition in sys_global_columns from which unspecified properties are inherited.'),
	('meta_column','column_name','en','Technical Column Name (column_name)','Technical Column Name','Column','Exact database identifier of the column in the storage table or view.'),
	('meta_column','customizable','en','Allow Customization (customizable)','Allow Tenant Customization','Customizable','Indicates whether a client organization (tenant) may customize properties of this column.'),
	('meta_column','header','en','Table Column Header (header)','List Column Header (header)','Header','Short column heading used in summary tables and master lists.'),
	('meta_column','hidden','en','Hidden Column (hidden)','Hide Field in Standard Form','Hidden','Technical column hidden from standard detail edit forms.'),
	('meta_column','history','en','Track History (history)','Store Historical Versions (H)','History','Indicates whether changing the column value creates a historical snapshot record (type H).'),
	('meta_column','input_rows','en','Textarea Rows (input_rows)','Number of Rows (for textarea)','Rows','Height of a multi-line text field (textarea) in visible rows.'),
	('meta_column','input_type','en','Input Control Type (input_type)','Form Input Type','Input Type','HTML control type in the detail form (text, textarea, number, date, checkbox).'),
	('meta_column','input_width','en','Input Width (input_width)','Input Field Width (CSS)','Input Width','CSS width of the form control in the detail panel (e.g., 100%, 180px, auto).'),
	('meta_column','is_computed','en','Computed Column (is_computed)','Computed Column (Read-Only)','Computed','The column is calculated by the database or application and is locked as read-only in forms.'),
	('meta_column','is_html','en','Formatted Text Markdown/HTML (is_html)','Formatted Rich Text (Markdown / HTML)','Rich Text','Enables formatted rich text support with preview and modal Toast UI Editor (Markdown / HTML).'),
	('meta_column','is_mandatory','en','Mandatory Field (is_mandatory)','Mandatory Field (Required)','Mandatory','Marks a field that must be filled in before saving the form.'),
	('meta_column','is_url','en','Contains URL Address (is_url)','Field Contains URL Link','Is URL','Validates and formats the input field as a web URL address.'),
	('meta_column','label','en','Form Field Label (label)','Detail Field Label (label)','Label','Label text displayed to the left of the input control in the detail edit form.'),
	('meta_column','list_order','en','Master List Order (list_order)','Column Order in Master List','List Order','If set to a positive integer, the column is displayed in the left master list table in this order.'),
	('meta_column','max_length','en','Maximum Text Length (max_length)','Maximum Character Count','Max. Length','Maximum allowed number of characters in a text input matching the database definition.'),
	('meta_column','parent_class','en','Belongs to Class (parent_class)','Parent Logical Class','Class','Structural link defining which logical class this column belongs to.'),
	('meta_column','parent_order','en','Column Table Order (parent_order)','Column Order in Class','Col. Order','Numeric column order derived from the physical structure of the database table.'),
	('meta_column','placeholder','en','Input Placeholder (placeholder)','Empty Input Placeholder Text','Placeholder','Hint text displayed inside an empty input field (translatable).'),
	('meta_column','referenced_class','en','Referenced Class (referenced_class)','Linked Logical Class (Foreign Key)','Referenced Class','Reference to the target logical class in meta_class for selecting related records from a dropdown list.'),
	('meta_column','referenced_codetable','en','Referenced Codetable (referenced_codetable)','Linked System Codetable','Codetable','Codetable name in meta_codetable used to populate the dropdown select for this field.'),
	('meta_column','show_empty','en','Show When Empty (show_empty)','Display Field Even When Empty','Show Empty','Indicates whether the field should be displayed in views even when its value is empty.'),
	('meta_column','translate','en','Supports Translation (translate)','Translatable Column (L records)','Translate','Indicates whether the column value can be translated into other languages via L records.');
END
GO