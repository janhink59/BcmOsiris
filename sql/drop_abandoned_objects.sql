/* =============================================================================
 * Verze: 2026-10-29 16:00
 * Soubor: drop_abandoned_objects.sql
 * Účel:   Idempotentní odstranění opuštěných tabulek a procedur.
 * Změny:  - 2026-10-29 16:00: Přidáno odstranění opuštěné tabulky
 *           organization_settings (její sloupce byly přesunuty do organization).
 * ============================================================================= */

EXECUTE dropni 'p_generate_primitive_classes', 'P'
EXECUTE dropni 'password_reset_request'
EXECUTE dropni 'organization_settings'
GO