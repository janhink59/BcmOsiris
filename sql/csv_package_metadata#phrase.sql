/* =============================================================================
 * Verze: 2026-11-15 19:15
 * Soubor: csv_package_metadata#phrase.sql
 * Účel:   Registrace třídy csv_package_metadata do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'csv_package_metadata';
DELETE FROM sysinit_phrase WHERE source_code = 'csv_package_metadata';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','csv_package_metadata','cs','U','CSV/TSV balíček systémových metadat','Definice pro přenos systémových metadat mezi instancemi'),
('P','csv_package_metadata','en','U','System Metadata CSV/TSV Package','Definition for transferring system metadata between instances');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('csv_package_metadata','pkg_desc','cs','Export a dvoufázový import kompletních systémových metadat (object_owner = 0x00) ve všech jazycích ve víceblokovém CSV formátu.','',''),
('csv_package_metadata','pkg_title','cs','Systémová metadata (třídy, sloupce, menu, fráze, číselníky)','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('csv_package_metadata','pkg_desc','en','Export and two-phase import of complete system metadata (object_owner = 0x00) across all languages in multi-block CSV format.',''),
('csv_package_metadata','pkg_title','en','System Metadata (Classes, Columns, Menus, Phrases, Codetables)','');
GO