/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_organization_licence#phrase.sql
 * Účel:   Registrace stránky page_organization_licence do sysinit_object,
 *         položky menu organization_licence do sysinit_menu a frází
 *         do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_organization_licence';
DELETE FROM sysinit_menu WHERE builtin_code = 'organization_licence';
DELETE FROM sysinit_phrase WHERE source_code = 'page_organization_licence';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_organization_licence','cs','A','Správa licencí organizací','Evidence a aktivace licencí pro jednotlivé tenanty'),
('P','page_organization_licence','en','A','Organization Licence Management','Registry and activation of licences for individual tenants');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('organization_licence','cs','admin_folder','030','page_organization_licence','','A','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M20 2H4c-1.11 0-2 .89-2 2v11c0 1.11.89 2 2 2h4v5l4-2 4 2v-5h4c1.11 0 2-.89 2-2V4c0-1.11-.89-2-2-2zm0 13H4v-2h16v2zm0-5H4V4h16v6z"/></svg>','Správa licencí organizací','Evidence žádostí o licenci a aktivace nových organizací','Evidence žádostí o licenci a aktivace nových organizací');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('organization_licence','en','Organization Licence Management','Registry of licence requests and activation of new organizations','Registry of licence requests and activation of new organizations');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_organization_licence','btn_new_licence','cs','+ Nová licence organizace','Založí nový licenční záznam pro vytvoření a aktivaci organizace',''),
('page_organization_licence','grp_admin_account','cs','Výchozí administrátor zakládané organizace','',''),
('page_organization_licence','grp_licence_params','cs','Parametry licence, úroveň a stav aktivace','',''),
('page_organization_licence','grp_notes_validity','cs','Poznámky a časová platnost licence','',''),
('page_organization_licence','header_edit_licence','cs','Licence organizace','',''),
('page_organization_licence','header_new_licence','cs','Nová licence organizace','',''),
('page_organization_licence','msg_activation_hint','cs','Při uložení se stavem APPROVED (Schváleno k aktivaci) systém automaticky založí cílovou organizaci, výchozího administrátora a odešle aktivační e-mail.','',''),
('page_organization_licence','page_title','cs','Správa licencí organizací - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_organization_licence','btn_new_licence','en','+ New Organization Licence','Create a new licence record to set up and activate an organization'),
('page_organization_licence','grp_admin_account','en','Initial Administrator of the Organization',''),
('page_organization_licence','grp_licence_params','en','Licence Parameters, Tier & Activation State',''),
('page_organization_licence','grp_notes_validity','en','Notes & Licence Temporal Validity',''),
('page_organization_licence','header_edit_licence','en','Organization Licence',''),
('page_organization_licence','header_new_licence','en','New Organization Licence',''),
('page_organization_licence','msg_activation_hint','en','When saved with state APPROVED, the system automatically creates the target organization, sets up the initial administrator, and sends an activation email.',''),
('page_organization_licence','page_title','en','Organization Licence Management - BCM Osiris','');
GO