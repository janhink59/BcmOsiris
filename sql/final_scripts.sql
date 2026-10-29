/* =============================================================================
 * Verze: 2026-10-29 16:40
 * Soubor: final_scripts.sql
 * Účel:   Závěrečné automatické operace spouštěné na konci hlavní sestavovací
 *         dávky databáze (BcmOsirisDb.sql).
 *         1. p_create_standard_views - odstraní případné staré pohledy vrepo_%
 *         2. p_fix_meta_column       - synchronizuje tabulky, třídy a sloupce
 *                                      v meta_object, meta_class a meta_column
 *         3. p_empty_trash           - fyzicky vyčistí záznamy v koši (removed = 1)
 *                                      starší než days_in_trash dnů dle meta_class
 * ============================================================================= */

EXECUTE p_create_standard_views;
EXECUTE p_fix_meta_column;
EXECUTE p_empty_trash;
GO