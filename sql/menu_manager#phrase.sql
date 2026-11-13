/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: menu_manager#phrase.sql
 * Účel:   Registrace třídy menu_manager do sysinit_object a naplnění
 *         jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'menu_manager';
DELETE FROM sysinit_phrase WHERE source_code = 'menu_manager';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','menu_manager','cs','U','Správce navigace','Třída pro sestavení a vykreslení drobečkové navigace a menu'),
('P','menu_manager','en','U','Navigation Manager','Class for building and rendering breadcrumbs and navigation menus');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('menu_manager','breadcrumb_home','cs','Domů','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('menu_manager','breadcrumb_home','en','Home','');
GO