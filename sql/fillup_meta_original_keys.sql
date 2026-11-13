/* =============================================================================
 * Verze: 2026-11-13 18:30
 * Soubor: fillup_meta_original_keys.sql
 * Účel: Hromadné znovunaplnění definic pro generování sloupce "original".
 * Vazby: Slouží jako podklad pro proceduru generate_trgo, která dynamicky 
 *        skládá a zakládá triggery nad všemi definovanými tabulkami.
 *        Čte systémový pohled v_syscolumns a zapisuje do tabulky meta_original_keys.
 * Změny:
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
--    a současně disponují všemi 6 povinnými RAC sloupci pro trigger trgo_
INSERT INTO meta_original_keys (table_name, key1_column, key2_column)
SELECT
	c.tabname,
	'builtin_code',
	NULL
FROM v_syscolumns c
WHERE c.colname = 'builtin_code'
	AND c.object_type = 'U'
	AND c.tabname NOT IN (SELECT table_name FROM meta_original_keys)
	AND c.tabname NOT LIKE '%$'
	AND (
		SELECT COUNT(DISTINCT r.colname)
		FROM v_syscolumns r
		WHERE r.tabname = c.tabname
			AND r.object_type = 'U'
			AND r.colname IN ('uuid', 'object_owner', 'original', 'record_type', 'removed', 'template')
	) = 6;
GO