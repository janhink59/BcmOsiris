/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_organization#phrase.sql
 * Účel:   Registrace stránky page_organization do sysinit_object, položky menu
 *         organization do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_organization';
DELETE FROM sysinit_menu WHERE builtin_code = 'organization';
DELETE FROM sysinit_phrase WHERE source_code = 'page_organization';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_organization','cs','A','Správa a nastavení organizace','Nastavení organizace, fakturačních údajů a parametrů výpočtů CRMM'),
('P','page_organization','en','A','Organization Management & Settings','Organization settings, billing details, and CRMM calculation parameters');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('organization','cs','admin_folder','020','page_organization','','A','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>','Správa a nastavení organizace','Přehled, nastavení organizace a výpočtových parametrů CRMM','Přehled, nastavení organizace a výpočtových parametrů CRMM');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('organization','en','Organization Management & Settings','Overview, organization settings, and CRMM calculation parameters','Overview, organization settings, and CRMM calculation parameters');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_organization','btn_delete_logo','cs','Odstranit logo','Vymaže uložené grafické logo organizace','btn-danger'),
('page_organization','grp_address_contact','cs','Adresa sídla, identifikace a fakturace','',''),
('page_organization','grp_crmm_limits','cs','Metodické parametry a horní limity skóre CRMM','',''),
('page_organization','grp_general','cs','Název, zkratka, SSO doména a popis organizace','',''),
('page_organization','grp_logo','cs','Grafické logo organizace','',''),
('page_organization','grp_regional_formats','cs','Regionální formáty, měna a oddělovače','',''),
('page_organization','header_edit_org','cs','Nastavení organizace','',''),
('page_organization','lbl_current_logo','cs','Aktuální logo:','',''),
('page_organization','lbl_upload_logo','cs','Nahrát nové logo (PNG, SVG, JPG, max. 512 KB):','',''),
('page_organization','msg_logo_deleted','cs','Logo organizace bylo odstraněno.','',''),
('page_organization','msg_logo_too_large','cs','Soubor loga překračuje povolenou velikost 512 KB.','',''),
('page_organization','msg_logo_uploaded','cs','Logo organizace bylo úspěšně aktualizováno.','',''),
('page_organization','page_title','cs','Správa a nastavení organizace - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_organization','btn_delete_logo','en','Delete Logo','Remove the stored organization logo image'),
('page_organization','grp_address_contact','en','Headquarters Address, Identification & Billing',''),
('page_organization','grp_crmm_limits','en','CRMM Methodology Parameters & Score Limits',''),
('page_organization','grp_general','en','Name, Short Name, SSO Domain & Description',''),
('page_organization','grp_logo','en','Organization Graphic Logo',''),
('page_organization','grp_regional_formats','en','Regional Formats, Currency & Separators',''),
('page_organization','header_edit_org','en','Organization Settings',''),
('page_organization','lbl_current_logo','en','Current Logo:',''),
('page_organization','lbl_upload_logo','en','Upload New Logo (PNG, SVG, JPG, max. 512 KB):',''),
('page_organization','msg_logo_deleted','en','Organization logo has been removed.',''),
('page_organization','msg_logo_too_large','en','Logo file exceeds the maximum allowed size of 512 KB.',''),
('page_organization','msg_logo_uploaded','en','Organization logo has been updated successfully.',''),
('page_organization','page_title','en','Organization Management & Settings - BCM Osiris','');
GO