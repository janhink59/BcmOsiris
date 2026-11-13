/* =============================================================================
 * Verze: 2026-11-13 16:00
 * Soubor: final_scripts.sql
 * Účel:   Závěrečné automatické operace spouštěné na konci hlavní sestavovací
 *         dávky databáze (BcmOsirisDb.sql).
 *         1. p_fix_meta_column       - synchronizuje tabulky, třídy a sloupce
 *                                      v meta_object, meta_class a meta_column
 *         2. p_sysinit_process       - promítne nashromážděná systémová data
 *                                      a překlady ze sysinit_* do meta_*
 *         3. p_empty_trash           - fyzicky vyčistí záznamy v koši (removed = 1)
 *                                      starší než days_in_trash dnů dle meta_class
 * ============================================================================= */

--EXECUTE p_create_standard_views;
EXECUTE p_fix_meta_column;
EXECUTE p_sysinit_process;
EXECUTE p_empty_trash;
GO