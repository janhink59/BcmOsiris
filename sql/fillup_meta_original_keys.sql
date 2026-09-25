/* =============================================================================
 * NAPLNĚNÍ METADAT: meta_original_keys
 * Účel: Hromadné znovunaplnění definic pro generování sloupce "original".
 * ============================================================================= */
SET NOCOUNT ON;
GO

TRUNCATE TABLE meta_original_keys;
GO

-- 1. Explicitní definice známých složených klíčů
INSERT INTO meta_original_keys (table_name, key1_column, key2_column) 
VALUES 
	('user_organization_access', 'user_account_uuid', 'organization_uuid'),
	('meta_object', 'object_type', 'builtin_code'),
	('meta_column', 'parent_object', 'column_name');
GO

-- 2. Dynamické doplnění všech ostatních tabulek, které obsahují sloupec builtin_code
--    (Pokud tabulka ještě není v číselníku definována, použije se builtin_code jako jediný klíč)
INSERT INTO meta_original_keys (table_name, key1_column, key2_column)
SELECT 
	tabname, 
	'builtin_code', 
	NULL
FROM v_syscolumns
WHERE colname = 'builtin_code' 
	AND tabname NOT IN (SELECT table_name FROM meta_original_keys);
GO