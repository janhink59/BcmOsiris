/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_threat#phrase.sql
 * Účel:   Registrace stránky page_threat do sysinit_object, položky menu
 *         threat do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_threat';
DELETE FROM sysinit_menu WHERE builtin_code = 'threat';
DELETE FROM sysinit_phrase WHERE source_code = 'page_threat';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_threat','cs','U','Katalog hrozeb (CRMM)','Správa hierarchického katalogu hrozeb a jejich výchozího hodnocení v modulu CRMM'),
('P','page_threat','en','U','Threat Catalog (CRMM)','Management of the hierarchical catalog of threats and their default evaluation in CRMM');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('threat','cs','crmm_folder','020','page_threat','','U','<svg viewBox="0 0 24 24" fill="#DC2626"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>','Katalog hrozeb','Správa hierarchického katalogu hrozeb a jejich výchozích hodnot skóre','Správa hierarchického katalogu hrozeb a jejich výchozích hodnot skóre');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('threat','en','Threat Catalog','Management of the hierarchical catalog of threats and their default score values','Management of the hierarchical catalog of threats and their default score values');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_threat','btn_new_threat','cs','+ Nová hrozba','Založí novou skupinu nebo koncovou hrozbu v katalogu',''),
('page_threat','grp_evaluation','cs','Výchozí hodnocení hrozby','',''),
('page_threat','grp_identification','cs','Kód, zařazení ve stromu a ikona','',''),
('page_threat','grp_permissions_protection','cs','Oprávnění, platnost a ochrana záznamu','',''),
('page_threat','grp_presentation','cs','Prezentační texty a popis hrozby','',''),
('page_threat','header_edit_threat','cs','Hrozba','',''),
('page_threat','header_new_threat','cs','Nová hrozba','',''),
('page_threat','master_heading','cs','Strom katalogu hrozeb','',''),
('page_threat','page_title','cs','Katalog hrozeb (CRMM)','',''),
('page_threat','th_default_score','cs','Výchozí skóre','',''),
('page_threat','th_threat_caption','cs','Hrozba','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_threat','btn_new_threat','en','+ New Threat','Create a new group or leaf threat in the catalog'),
('page_threat','grp_evaluation','en','Default Threat Evaluation',''),
('page_threat','grp_identification','en','Code, Tree Placement & Icon',''),
('page_threat','grp_permissions_protection','en','Permissions, Validity & Record Protection',''),
('page_threat','grp_presentation','en','Presentation Texts & Threat Description',''),
('page_threat','header_edit_threat','en','Threat',''),
('page_threat','header_new_threat','en','New Threat',''),
('page_threat','master_heading','en','Threat Catalog Tree',''),
('page_threat','page_title','en','Threat Catalog (CRMM)',''),
('page_threat','th_default_score','en','Default Score',''),
('page_threat','th_threat_caption','en','Threat','');
GO