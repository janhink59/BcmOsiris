/* =============================================================================
 * Verze: 2026-11-21 11:20
 * Soubor: page_impact_type#phrase.sql
 *
 * 1. Role souboru v celém systému:
 *    Registrace stránky page_impact_type do sysinit_object, položky menu
 *    impact_type do sysinit_menu a českých i anglických frází do sysinit_phrase.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Odpovídá voláním $this->phrase() v page_impact_type.php.
 *    - Automaticky zařazen do buildu databáze maskou *#phrase.sql v BuildListDb.txt.
 *    - Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (BcmOsirisDb.sql) nad
 *      staging tabulkami sysinit_* bez závislosti na relaci v dbsession.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_impact_type';
DELETE FROM sysinit_menu WHERE builtin_code = 'impact_type';
DELETE FROM sysinit_phrase WHERE source_code = 'page_impact_type';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_impact_type','cs','U','Druhy dopadů (Katalog CRMM)','Správa hierarchického katalogu druhů dopadů a následků (důvěrnost, integrita, délky výpadku dostupnosti, ztráta dat, komunikace)'),
('P','page_impact_type','en','U','Impact Types (CRMM Catalog)','Management of the hierarchical catalog of impact types and consequences (confidentiality, integrity, availability outages, data loss, communication)');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('impact_type','cs','crmm_folder','030','page_impact_type','','U','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z"/></svg>','Druhy dopadů (následky)','Správa hierarchického katalogu druhů dopadů a následků (řádky matice BIA: prozrazení, chyby, výpadky, ztráta dat, komunikace)','Správa hierarchického katalogu druhů dopadů a následků (řádky matice BIA: prozrazení, chyby, výpadky, ztráta dat, komunikace)');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('impact_type','en','Impact Types (Consequences)','Management of the hierarchical catalog of impact types and consequences (BIA matrix rows: disclosure, errors, outages, data loss, communication)','Management of the hierarchical catalog of impact types and consequences (BIA matrix rows: disclosure, errors, outages, data loss, communication)');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_impact_type','btn_new_impact_type','cs','+ Nový druh dopadu','Založí novou kategorii nebo koncový druh dopadu (následek) v katalogu',''),
('page_impact_type','grp_hierarchy_classification','cs','Zařazení ve stromu, kategorie CIA a délka výpadku','',''),
('page_impact_type','grp_presentation','cs','Prezentační texty a nápověda','',''),
('page_impact_type','grp_validity_protection','cs','Platnost, vzhled a ochrana','',''),
('page_impact_type','header_edit_impact_type','cs','Druh dopadu','',''),
('page_impact_type','header_new_impact_type','cs','Nový druh dopadu (následek)','',''),
('page_impact_type','master_heading','cs','Strom druhů dopadů (následků)','',''),
('page_impact_type','page_title','cs','Druhy dopadů (Katalog CRMM)','',''),
('page_impact_type','th_cia_category','cs','CIA','',''),
('page_impact_type','th_duration_minutes','cs','Min.','',''),
('page_impact_type','th_impact_type_caption','cs','Druh dopadu / Kategorie','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_impact_type','btn_new_impact_type','en','+ New Impact Type','Create a new category or leaf impact type (consequence) in the catalog'),
('page_impact_type','grp_hierarchy_classification','en','Tree Placement, CIA Category & Outage Duration',''),
('page_impact_type','grp_presentation','en','Presentation Texts & Help',''),
('page_impact_type','grp_validity_protection','en','Validity, Appearance & Protection',''),
('page_impact_type','header_edit_impact_type','en','Impact Type',''),
('page_impact_type','header_new_impact_type','en','New Impact Type (Consequence)',''),
('page_impact_type','master_heading','en','Impact Types Tree (Consequences)',''),
('page_impact_type','page_title','en','Impact Types (CRMM Catalog)',''),
('page_impact_type','th_cia_category','en','CIA',''),
('page_impact_type','th_duration_minutes','en','Min.',''),
('page_impact_type','th_impact_type_caption','en','Impact Type / Category','');
GO