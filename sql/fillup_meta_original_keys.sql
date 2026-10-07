/* =============================================================================
 * Soubor: fillup_meta_original_keys.sql
 * Účel: Hromadné znovunaplnění definic pro generování sloupce "original".
 * Vazby: Slouží jako podklad pro proceduru generate_trgo, která dynamicky 
 *        skládá a zakládá triggery nad všemi definovanými tabulkami.
 * Změny:
 * - Opravena definice pro meta_column (parent_object -> parent_class).
 * - Doplněno vysvětlení pro tabulku link.
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
	('meta_column', 'parent_class', 'column_name'),     -- OPRAVA: Vazba na logickou třídu
	('meta_class', 'class_name', NULL),                 -- Třída je unikátní svým názvem
	('meta_link_def', 'link_code', NULL),               -- Definice vazby je unikátní kódem
	('meta_codetable', 'codetable_name', 'value_code')  -- Číselník je unikátní názvem a hodnotou

-- VYSVĚTLENÍ VÝJIMKY PRO TABULKU LINK:
-- Tabulka link vyžaduje pro výpočet originálu 3 složky (link_def, from_object, to_object).
-- Tento generátor aktuálně podporuje max. 2 složky. Originál pro tabulku link
-- se proto počítá vlastním dedikovaným triggerem "trgo_link", definovaným na konci generate_trgo.sql.
-- INSERT INTO meta_original_keys ('link', 'link_def', 'from_object') -- ZAKOMENTOVÁNO ZÁMĚRNĚ
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
	AND object_type = 'U';                              -- Omezí tvorbu triggerů pouze na fyzické tabulky
GO