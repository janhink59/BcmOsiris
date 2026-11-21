/* =============================================================================
 * Verze: 2026-11-21 11:20
 * Soubor: page_impact_area#phrase.sql
 *
 * 1. Role souboru v celém systému:
 *    Registrace stránky page_impact_area do sysinit_object, položky menu
 *    impact_area do sysinit_menu a českých i anglických frází do sysinit_phrase.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Odpovídá voláním $this->phrase() v page_impact_area.php.
 *    - Automaticky zařazen do buildu databáze maskou *#phrase.sql v BuildListDb.txt.
 *    - Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      staging tabulkami sysinit_* bez závislosti na relaci v dbsession.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_impact_area';
DELETE FROM sysinit_menu WHERE builtin_code = 'impact_area';
DELETE FROM sysinit_phrase WHERE source_code = 'page_impact_area';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_impact_area','cs','U','Oblasti dopadů (Katalog CRMM)','Správa hierarchického katalogu měřitelných oblastí dopadů na organizaci, stát a subjekt údajů s vazbou na hodnotící škály vodítek'),
('P','page_impact_area','en','U','Impact Areas (CRMM Catalog)','Management of the hierarchical catalog of measurable impact areas affecting the organization, state, and data subjects linked to guideline scales');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('impact_area','cs','crmm_folder','035','page_impact_area','','U','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm0-14c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6-2.69-6-6-6zm0 10c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm0-6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>','Oblasti dopadů','Správa hierarchického katalogu měřitelných oblastí dopadů (sloupce matice BIA: organizace, stát, subjekt údajů) a jejich škál vodítek','Správa hierarchického katalogu měřitelných oblastí dopadů (sloupce matice BIA: organizace, stát, subjekt údajů) a jejich škál vodítek');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('impact_area','en','Impact Areas','Management of the hierarchical catalog of measurable impact areas (BIA matrix columns: organization, state, data subjects) and their guideline scales','Management of the hierarchical catalog of measurable impact areas (BIA matrix columns: organization, state, data subjects) and their guideline scales');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_impact_area','btn_new_impact_area','cs','+ Nová oblast dopadu','Založí novou perspektivu nebo měřitelnou oblast dopadu v katalogu',''),
('page_impact_area','grp_hierarchy_scale','cs','Zařazení ve stromu a škála vodítek','',''),
('page_impact_area','grp_presentation','cs','Prezentační texty a nápověda','',''),
('page_impact_area','grp_validity_protection','cs','Platnost, vzhled a ochrana','',''),
('page_impact_area','header_edit_impact_area','cs','Oblast dopadu','',''),
('page_impact_area','header_new_impact_area','cs','Nová oblast dopadu','',''),
('page_impact_area','master_heading','cs','Strom oblastí dopadů','',''),
('page_impact_area','msg_impact_area_scale_hint','cs','Tip: Pokud ponecháte pole „Individuální škála vodítek (scale_uuid)“ prázdné, použije se výchozí škála dopadů organizace (organization.default_impact_scale_uuid). Oblasti nebo celé perspektivy, které vaše organizace nevyhodnocuje, lze skrýt zaškrtnutím příznaku Neaktivní (inactive).','',''),
('page_impact_area','page_title','cs','Oblasti dopadů (Katalog CRMM)','',''),
('page_impact_area','th_impact_area_caption','cs','Oblast dopadu / Perspektiva','',''),
('page_impact_area','th_shortname','cs','Zkratka','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_impact_area','btn_new_impact_area','en','+ New Impact Area','Create a new perspective or measurable impact area in the catalog'),
('page_impact_area','grp_hierarchy_scale','en','Tree Placement & Guideline Scale',''),
('page_impact_area','grp_presentation','en','Presentation Texts & Help',''),
('page_impact_area','grp_validity_protection','en','Validity, Appearance & Protection',''),
('page_impact_area','header_edit_impact_area','en','Impact Area',''),
('page_impact_area','header_new_impact_area','en','New Impact Area',''),
('page_impact_area','master_heading','en','Impact Areas Tree',''),
('page_impact_area','msg_impact_area_scale_hint','en','Tip: Leaving "Area-Specific Guideline Scale (scale_uuid)" empty defaults to the organization impact scale (organization.default_impact_scale_uuid). Areas or entire perspectives not evaluated by your organization can be hidden by checking Inactive (inactive).',''),
('page_impact_area','page_title','en','Impact Areas (CRMM Catalog)',''),
('page_impact_area','th_impact_area_caption','en','Impact Area / Perspective',''),
('page_impact_area','th_shortname','en','Short Name','');
GO