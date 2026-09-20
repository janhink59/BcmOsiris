/* =============================================================================
 * METADATA: meta_original_keys
 * Účel: Registr sloupců, které definují deterministický "original" (UUID) záznamu.
 * Změna: Zploštěná struktura pro max. 2 klíče (jeden řádek = jedna tabulka).
 * ============================================================================= */
IF OBJECT_ID('meta_original_keys') IS NOT NULL
	DROP TABLE meta_original_keys;
GO

CREATE TABLE meta_original_keys (
	table_name varchar(128) NOT NULL,
	key1_column varchar(128) NOT NULL,
	key2_column varchar(128) NULL, -- Druhý klíč je volitelný
	
	CONSTRAINT pk_meta_original_keys PRIMARY KEY (table_name)
);
GO

truncate table meta_original_keys
GO

-- Inicializační naplnění pro user_organization_access
INSERT INTO meta_original_keys (table_name, key1_column, key2_column) 
VALUES ('user_organization_access', 'user_account_uuid', 'organization_uuid');
GO