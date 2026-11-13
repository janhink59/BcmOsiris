/* =============================================================================
 * METADATA: meta_original_keys
 * Účel: Registr sloupců, které definují deterministický "original" (UUID) záznamu.
 * Změna: Zploštěná struktura pro max. 2 klíče (jeden řádek = jedna tabulka).
 * ============================================================================= */

IF OBJECT_ID('meta_original_keys') IS NULL
BEGIN
	CREATE TABLE meta_original_keys (
		table_name varchar(128) NOT NULL,
		key1_column varchar(128) NOT NULL,
		key2_column varchar(128) NULL, -- Druhý klíč je volitelný
		
		CONSTRAINT pk_meta_original_keys PRIMARY KEY (table_name)
	);
	PRINT 'Tabulka meta_original_keys byla vytvorena.';
END
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'meta_original_keys';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('meta_original_keys','cs','T','meta_original_keys','Klíč deterministického originálu','Klíče deterministických originálů','Registr klíčových sloupců tabulek, ze kterých se počítá deterministický identifikátor original.','Technická tabulka určující složky MD5 hashe pro výpočet identifikátoru original v triggerech trgo_.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('meta_original_keys','en','Deterministic Original Key','Deterministic Original Keys','Registry of key columns used to compute the deterministic original UUID of records.','Technical table defining MD5 hash key components for trgo_ triggers.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'meta_original_keys';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('meta_original_keys','key1_column','cs','První klíčový sloupec (key1_column)','1. klíčový sloupec originálu','1. klíč','Název prvního sloupce vstupujícího do výpočtu deterministického identifikátoru original.'),
	('meta_original_keys','key2_column','cs','Druhý klíčový sloupec (key2_column)','2. klíčový sloupec originálu','2. klíč','Název volitelného druhého sloupce vstupujícího do výpočtu deterministického identifikátoru original.'),
	('meta_original_keys','table_name','cs','Název tabulky (table_name)','Fyzický název tabulky','Tabulka','Název databázové tabulky v schématu dbo.'),
	('meta_original_keys','key1_column','en','First Key Column (key1_column)','1st Original Key Column','1st Key','Name of the first column used to calculate the deterministic original identifier.'),
	('meta_original_keys','key2_column','en','Second Key Column (key2_column)','2nd Original Key Column','2nd Key','Name of the optional second column used to calculate the deterministic original identifier.'),
	('meta_original_keys','table_name','en','Table Name (table_name)','Physical Table Name','Table','Name of the database table in the dbo schema.');
END
GO