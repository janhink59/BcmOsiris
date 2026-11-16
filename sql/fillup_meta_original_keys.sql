/* =============================================================================
 * Verze: 2026-11-16 14:40
 * Soubor: fillup_meta_original_keys.sql
 *
 * 1. Role souboru v celém systému:
 *    Hromadné znovunaplnění definic klíčových sloupců v tabulce meta_original_keys
 *    pro deterministický výpočet identifikátoru "original".
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Čte systémový pohled v_syscolumns (HinkMSSQLLibrary.sql) a zapisuje do
 *      tabulky meta_original_keys (table_meta_original_keys.sql).
 *    - Slouží jako podklad pro skript generate_trgo.sql, procedury
 *      p_fix_meta_column, p_csv_import_simple_class a třídu entity_manager.
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) bez
 *      závislosti na uživatelské relaci.
 *
 * Změny:
 * - 2026-11-16 14:40: Odstraněna klauzule NOT IN (SELECT ...) a korelovaný
 *   poddotaz (SELECT COUNT(DISTINCT r.colname) ...) nad pohledem v_syscolumns;
 *   nahrazeno jedním agregačním průchodem do indexované tabulkové proměnné
 *   @valid_rac_tables s PRIMARY KEY (tabname).
 * - 2026-11-13 18:30: Dynamické doplňování tabulek se sloupcem builtin_code
 *   omezeno strukturální kontrolou na tabulky, které obsahují všech 6 povinných
 *   RAC sloupců vyžadovaných triggery trgo_ (uuid, object_owner, original,
 *   record_type, removed, template).
 * - 2026-11-12 16:45: Klíč tabulky meta_link_def rozšířen na složený klíč
 *   (from_class, link_code), aby šlo používat jednotné kódy parent_to_child
 *   a child_to_parent napříč různými třídami.
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
	('meta_link_def', 'from_class', 'link_code'),                           -- Definice vztahu je unikátní zdrojovou třídou a kódem
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

-- 2. Dynamické doplnění všech ostatních RAC tabulek, které obsahují sloupec builtin_code
--    a současně disponují všemi 6 povinnými RAC sloupci pro trigger trgo_ (celkem 7 sloupců)
DECLARE @valid_rac_tables TABLE (
	tabname varchar(128) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
);

INSERT INTO @valid_rac_tables (tabname)
SELECT r.tabname
FROM v_syscolumns r
WHERE r.object_type = 'U'
  AND r.tabname NOT LIKE '%$'
  AND r.tabname NOT LIKE 'sysinit[_]%'
  AND r.colname IN ('uuid', 'object_owner', 'original', 'record_type', 'removed', 'template', 'builtin_code')
GROUP BY r.tabname
HAVING COUNT(DISTINCT r.colname) = 7;

INSERT INTO meta_original_keys (table_name, key1_column, key2_column)
SELECT
	v.tabname,
	'builtin_code',
	NULL
FROM @valid_rac_tables v
LEFT JOIN meta_original_keys ex ON ex.table_name = v.tabname
WHERE ex.table_name IS NULL;
GO