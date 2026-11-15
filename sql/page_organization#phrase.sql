/* =============================================================================
 * Verze: 2026-11-15 20:05
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
('page_organization','btn_goto_licences','cs','Správa licencí (založení organizace) →','Přejde do správy licencí pro vytvoření a aktivaci nové organizace','btn-secondary'),
('page_organization','grp_address_info','cs','Sídlo a kontaktní údaje','',''),
('page_organization','grp_basic_info','cs','Základní identifikace organizace','',''),
('page_organization','grp_billing_info','cs','Registrační, daňové a fakturační údaje','',''),
('page_organization','grp_crmm_parameters','cs','Metodické a výpočtové parametry CRMM','',''),
('page_organization','grp_regional_settings','cs','Regionální a formátovací nastavení','',''),
('page_organization','grp_texts_notes','cs','Popis, nápověda a interní poznámky','',''),
('page_organization','header_edit_org','cs','Organizace','',''),
('page_organization','msg_system_org_notice','cs','Toto je systémová master organizace (0x00). Slouží jako globální kontejner pro systémové administrátory a vývojáře.','',''),
('page_organization','page_title','cs','Správa a nastavení organizace','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_organization','btn_goto_licences','en','Licence Management (Create Organization) →','Open licence management to create and activate a new organization'),
('page_organization','grp_address_info','en','Headquarters & Contact Information',''),
('page_organization','grp_basic_info','en','Basic Organization Identification',''),
('page_organization','grp_billing_info','en','Registration, Tax & Billing Information',''),
('page_organization','grp_crmm_parameters','en','CRMM Methodological & Calculation Parameters',''),
('page_organization','grp_regional_settings','en','Regional & Formatting Settings',''),
('page_organization','grp_texts_notes','en','Description, Help & Internal Notes',''),
('page_organization','header_edit_org','en','Organization',''),
('page_organization','msg_system_org_notice','en','This is the system master organization (0x00). It serves as the global container for system administrators and developers.',''),
('page_organization','page_title','en','Organization Management & Settings','');
GO