/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: fillup_meta_original_keys.sql
 * Účel: Hromadné znovunaplnění definic pro generování sloupce "original".
 * Vazby: Slouží jako podklad pro proceduru generate_trgo, která dynamicky 
 *        skládá a zakládá triggery nad všemi definovanými tabulkami.
 *        Čte systémový pohled v_syscolumns a zapisuje do tabulky meta_original_keys.
 * Změny:
 * - 2026-11-09 14:15: Přidány složené klíče (asset_uuid, scenario_uuid) pro
 *   tabulku scenario_assessment a (asset_uuid, countermeasure_uuid) pro
 *   tabulku countermeasure_implementation (tabulka asset se zařadí automaticky
 *   přes sloupec builtin_code).
 * - 2026-11-04 15:15: Přidána definice složeného klíče (scale, builtin_code)
 *   pro tabulku scale_value.
 * - 2026-10-30 23:35: Přidána definice klíčů pro tabulky hierarchy (builtin_code)
 *   a hierarchy_item (hierarchy, builtin_code).
 * ============================================================================= */
SET NOCOUNT ON;
GO

TRUNCATE TABLE meta_original_keys;
GO

-- 1. Explicitní definice známých složených a katalogových klíčů
INSERT INTO meta_original_keys (table_name, key1_column, key2_column) 
VALUES 
	('user_organization_access', 'user_account_uuid', 'organization_uuid'),
	('meta_object', 'object_type', 'builtin_code'),
	('meta_column', 'parent_class', 'column_name'),                         -- Vazba na logickou třídu
	('meta_class', 'class_name', NULL),                                     -- Třída je unikátní svým názvem
	('meta_link_def', 'link_code', NULL),                                   -- Definice vazby je unikátní kódem
	('meta_codetable', 'codetable_name', 'value_code'),                     -- Číselník je unikátní názvem a hodnotou
	('meta_phrase', 'source_code', 'builtin_code'),                         -- Fráze je unikátní zdrojovou třídou a kódem
	('hierarchy', 'builtin_code', NULL),                                    -- Hierarchie je unikátní svým kódem
	('hierarchy_item', 'hierarchy', 'builtin_code'),                        -- Uzel hierarchie je unikátní v rámci dané hierarchie
	('scale_value', 'scale', 'builtin_code'),                               -- Stupeň škály je unikátní v rámci dané škály
	('scenario_assessment', 'asset_uuid', 'scenario_uuid'),                 -- Hodnocení scénáře je unikátní pro aktivum a scénář
	('countermeasure_implementation', 'asset_uuid', 'countermeasure_uuid'); -- Implementace opatření je unikátní pro aktivum a opatření

-- VYSVĚTLENÍ VÝJIMKY PRO TABULKU LINK:
-- Tabulka link vyžaduje pro výpočet originálu 4 složky (link_def, from_object, to_object, ancestor_link).
-- Tento generátor podporuje max. 2 složky. Originál pro tabulku link se proto počítá
-- vlastním dedikovaným triggerem "trgo_link", definovaným na konci generate_trgo.sql.
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
	AND tabname NOT IN (SELECT table_name FROM meta_original_keys)
	AND tabname NOT LIKE '%$'                                               -- Vyloučení dočasných staging tabulek z Excelu (XLSX_*$)
	AND object_type = 'U';                                                  -- Omezí tvorbu triggerů pouze na fyzické tabulky
GO