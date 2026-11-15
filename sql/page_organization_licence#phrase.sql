/* =============================================================================
 * Verze: 2026-11-15 20:05
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
('page_organization_licence','btn_new_licence','cs','+ Nová licence','Založí nový licenční záznam pro vytvoření a aktivaci organizace',''),
('page_organization_licence','detail_heading','cs','Detail organizace a licencování','',''),
('page_organization_licence','lbl_admin_email','cs','E-mail admina','',''),
('page_organization_licence','lbl_admin_first_name','cs','Jméno admina','',''),
('page_organization_licence','lbl_admin_last_name','cs','Příjmení admina','',''),
('page_organization_licence','lbl_admin_login','cs','Login admina','',''),
('page_organization_licence','lbl_builtin_code','cs','Kód licence (zkratka)','',''),
('page_organization_licence','lbl_caption','cs','Název organizace','',''),
('page_organization_licence','lbl_licence_level','cs','Úroveň licence','',''),
('page_organization_licence','lbl_licence_state','cs','Stav licence','',''),
('page_organization_licence','lbl_login_disabled','cs','Zablokovat přihlašování organizaci (login_disabled)','',''),
('page_organization_licence','lbl_login_domain','cs','Login doména','',''),
('page_organization_licence','lbl_preferred_language','cs','Výchozí jazyk organizace','',''),
('page_organization_licence','master_heading','cs','Evidence organizací a licencí','',''),
('page_organization_licence','msg_licence_not_found','cs','Licence nebyla nalezena.','',''),
('page_organization_licence','msg_select_or_create_licence','cs','Vyberte licenci ze seznamu vlevo nebo vytvořte novou.','',''),
('page_organization_licence','page_title','cs','Správa licencí organizací','',''),
('page_organization_licence','placeholder_search','cs','Hledat...','',''),
('page_organization_licence','state_approved','cs','Schváleno (spustí aktivaci)','',''),
('page_organization_licence','state_draft','cs','Koncept','',''),
('page_organization_licence','state_processed','cs','Zpracováno (Aktivní)','',''),
('page_organization_licence','state_rejected','cs','Zamítnuto','',''),
('page_organization_licence','th_admin_login','cs','Admin (Login)','',''),
('page_organization_licence','th_licence_level','cs','Úroveň','',''),
('page_organization_licence','th_licence_state','cs','Stav licence','',''),
('page_organization_licence','th_organization','cs','Organizace','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_organization_licence','btn_new_licence','en','+ New Licence','Create a new licence record to set up and activate an organization'),
('page_organization_licence','detail_heading','en','Organization & Licensing Detail',''),
('page_organization_licence','lbl_admin_email','en','Admin Email',''),
('page_organization_licence','lbl_admin_first_name','en','Admin First Name',''),
('page_organization_licence','lbl_admin_last_name','en','Admin Last Name',''),
('page_organization_licence','lbl_admin_login','en','Admin Login',''),
('page_organization_licence','lbl_builtin_code','en','Licence Code (Short Name)',''),
('page_organization_licence','lbl_caption','en','Organization Name',''),
('page_organization_licence','lbl_licence_level','en','Licence Level',''),
('page_organization_licence','lbl_licence_state','en','Licence State',''),
('page_organization_licence','lbl_login_disabled','en','Disable login for this organization (login_disabled)',''),
('page_organization_licence','lbl_login_domain','en','Login Domain',''),
('page_organization_licence','lbl_preferred_language','en','Default Organization Language',''),
('page_organization_licence','master_heading','en','Organizations & Licences Registry',''),
('page_organization_licence','msg_licence_not_found','en','Licence was not found.',''),
('page_organization_licence','msg_select_or_create_licence','en','Select a licence from the list on the left or create a new one.',''),
('page_organization_licence','page_title','en','Organization Licence Management',''),
('page_organization_licence','placeholder_search','en','Search...',''),
('page_organization_licence','state_approved','en','Approved (Triggers Activation)',''),
('page_organization_licence','state_draft','en','Draft',''),
('page_organization_licence','state_processed','en','Processed (Active)',''),
('page_organization_licence','state_rejected','en','Rejected',''),
('page_organization_licence','th_admin_login','en','Admin (Login)',''),
('page_organization_licence','th_licence_level','en','Level',''),
('page_organization_licence','th_licence_state','en','Licence State',''),
('page_organization_licence','th_organization','en','Organization','');
GO