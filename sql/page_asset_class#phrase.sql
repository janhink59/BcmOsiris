/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: page_asset_class#phrase.sql
 * Účel:   Registrace stránky page_asset_class do sysinit_object, položky menu
 *         asset_class do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_asset_class';
DELETE FROM sysinit_menu WHERE builtin_code = 'asset_class';
DELETE FROM sysinit_phrase WHERE source_code = 'page_asset_class';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_asset_class','cs','U','Třídy aktiv (Katalog CRMM)','Správa hierarchického katalogu tříd aktiv v modulu CRMM'),
('P','page_asset_class','en','U','Asset Classes (CRMM Catalog)','Management of the hierarchical catalog of asset classes in CRMM');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('asset_class','cs','crmm_folder','010','page_asset_class','','U','<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9H9V9h10v2zm-4 4H9v-2h6v2zm4-8H9V5h10v2z"/></svg>','Třídy aktiv','Správa hierarchického katalogu tříd aktiv, koncových uzlů a rolí editorů','Správa hierarchického katalogu tříd aktiv, koncových uzlů a rolí editorů');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('asset_class','en','Asset Classes','Management of the hierarchical catalog of asset classes, leaf nodes, and editor roles','Management of the hierarchical catalog of asset classes, leaf nodes, and editor roles');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_asset_class','btn_new_asset_class','cs','+ Nová třída aktiv','Založí novou složku nebo koncovou třídu aktiv v katalogu',''),
('page_asset_class','grp_identification','cs','Kód a zařazení ve stromu','',''),
('page_asset_class','grp_permissions_protection','cs','Oprávnění, platnost a ochrana záznamu','',''),
('page_asset_class','grp_presentation','cs','Prezentační texty a popis','',''),
('page_asset_class','header_edit_class','cs','Třída aktiv','',''),
('page_asset_class','header_new_class','cs','Nová třída aktiv','',''),
('page_asset_class','master_heading','cs','Strom tříd aktiv','',''),
('page_asset_class','page_title','cs','Třídy aktiv (Katalog CRMM)','',''),
('page_asset_class','th_class_caption','cs','Třída aktiv','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_asset_class','btn_new_asset_class','en','+ New Asset Class','Create a new folder or leaf asset class in the catalog'),
('page_asset_class','grp_identification','en','Code & Tree Placement',''),
('page_asset_class','grp_permissions_protection','en','Permissions, Validity & Record Protection',''),
('page_asset_class','grp_presentation','en','Presentation Texts & Description',''),
('page_asset_class','header_edit_class','en','Asset Class',''),
('page_asset_class','header_new_class','en','New Asset Class',''),
('page_asset_class','master_heading','en','Asset Class Tree',''),
('page_asset_class','page_title','en','Asset Classes (CRMM Catalog)',''),
('page_asset_class','th_class_caption','en','Asset Class','');
GO