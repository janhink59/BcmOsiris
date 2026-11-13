/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: page_asset#phrase.sql
 * Účel:   Registrace stránky page_asset do sysinit_object, položek menu
 *         asset_locations a asset do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_asset';
DELETE FROM sysinit_menu WHERE builtin_code IN ('asset_locations', 'asset');
DELETE FROM sysinit_phrase WHERE source_code = 'page_asset';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_asset','cs','U','Evidence aktiv a prostorů (CRMM)','Správa prostorů (okres, město, lokalita, budova, místnost) a všech archetypů aktiv organizace'),
('P','page_asset','en','U','Asset & Space Inventory (CRMM)','Management of spaces (district, city, site, building, room) and all organization asset archetypes');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('asset','cs','crmm_analysis_folder','020','page_asset','','U','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M20 13H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1v-6c0-.55-.45-1-1-1zM7 19c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zM20 3H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1V4c0-.55-.45-1-1-1zM7 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"/></svg>','Evidence aktiv','Evidence fyzických aktiv, hostitelských počítačů, kabeláže, dokumentů, médií, dat, softwaru, aplikací, služeb, rozhraní, personálu a dodavatelů','Evidence fyzických aktiv, hostitelských počítačů, kabeláže, dokumentů, médií, dat, softwaru, aplikací, služeb, rozhraní, personálu a dodavatelů'),
('asset_locations','cs','crmm_analysis_folder','010','page_asset','&group=SPACE','U','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10z"/></svg>','Prostory a lokality','Hierarchická evidence prostorů (Okres -> Město -> Lokalita -> Budova -> Místnost) pro umístění aktiv','Hierarchická evidence prostorů (Okres -> Město -> Lokalita -> Budova -> Místnost) pro umístění aktiv');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('asset','en','Asset Inventory','Inventory of physical assets, host computers, cabling, documents, media, data, software, applications, services, interfaces, personnel, and suppliers','Inventory of physical assets, host computers, cabling, documents, media, data, software, applications, services, interfaces, personnel, and suppliers'),
('asset_locations','en','Spaces & Locations','Hierarchical inventory of spaces (District -> City -> Site -> Building -> Room) for asset placement','Hierarchical inventory of spaces (District -> City -> Site -> Building -> Room) for asset placement');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_asset','btn_asset_cms','cs','Opatření ({$count}) →','Přejde na přehled implementace protiopatření pro toto aktivum','btn-secondary'),
('page_asset','btn_asset_links','cs','Vazby ({$count}) →','Přejde na přehled provozních a prostorových vazeb tohoto aktiva','btn-secondary'),
('page_asset','btn_asset_scenarios','cs','Scénáře ({$count}) →','Přejde na hodnocení rizikových scénářů tohoto aktiva','btn-secondary'),
('page_asset','btn_new_asset','cs','+ Nové aktivum','Založí nové aktivum v evidenci aktiv',''),
('page_asset','btn_new_space','cs','+ Nový prostor / lokalita','Založí nový prostor, budovu nebo místnost',''),
('page_asset','grp_bia_risk_scores','cs','Parametry dostupnosti (BIA) a agregované skóre rizik (0 až 100 %)','',''),
('page_asset','grp_identification','cs','Klasifikace, archetyp a identifikace','',''),
('page_asset','grp_placement_relations','cs','Zařazení ve stromu (parent_uuid)','',''),
('page_asset','grp_presentation','cs','Prezentační texty, popis a poznámky','',''),
('page_asset','grp_validity_protection','cs','Platnost, ikona a ochrana záznamu','',''),
('page_asset','header_edit_asset','cs','Aktivum','',''),
('page_asset','header_edit_space','cs','Prostor','',''),
('page_asset','header_new_asset','cs','Nové aktivum','',''),
('page_asset','header_new_space','cs','Nový prostor / lokalita','',''),
('page_asset','lbl_filter_archetype','cs','Filtrovat podle archetypu:','',''),
('page_asset','master_heading','cs','Strom a seznam aktiv','',''),
('page_asset','master_heading_space','cs','Strom prostorů a lokalit','',''),
('page_asset','msg_no_building_warning','cs','Upozornění: V organizaci zatím není definována žádná Budova (archetyp BUILDING). Založte prosím nejprve alespoň jednu budovu (i kdyby byla fiktivní), protože do budov se povinně umisťují místnosti a kabeláž a do místností fyzická aktiva, hostitelské počítače, dokumenty a média.','',''),
('page_asset','opt_all_assets','cs','--- Všechny archetypy aktiv (mimo prostory) ---','',''),
('page_asset','opt_all_spaces','cs','--- Všechny prostory a lokality ---','',''),
('page_asset','page_title','cs','Evidence aktiv (CRMM)','',''),
('page_asset','page_title_space','cs','Prostory a lokality (CRMM)','',''),
('page_asset','th_archetype','cs','Archetyp','',''),
('page_asset','th_asset_caption','cs','Aktivum / Služba','',''),
('page_asset','th_res_risk','cs','Rez. riz.','',''),
('page_asset','th_space_caption','cs','Prostor / Lokalita','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_asset','btn_asset_cms','en','Controls ({$count}) →','Open countermeasure implementations for this asset'),
('page_asset','btn_asset_links','en','Links ({$count}) →','Open operational and spatial links for this asset'),
('page_asset','btn_asset_scenarios','en','Scenarios ({$count}) →','Open risk scenario assessments for this asset'),
('page_asset','btn_new_asset','en','+ New Asset','Create a new asset in the asset inventory'),
('page_asset','btn_new_space','en','+ New Space / Location','Create a new space, building, or room'),
('page_asset','grp_bia_risk_scores','en','Availability Parameters (BIA) & Aggregated Risk Scores (0 to 100%)',''),
('page_asset','grp_identification','en','Classification, Archetype & Identification',''),
('page_asset','grp_placement_relations','en','Tree Placement (parent_uuid)',''),
('page_asset','grp_presentation','en','Presentation Texts, Description & Notes',''),
('page_asset','grp_validity_protection','en','Validity, Icon & Record Protection',''),
('page_asset','header_edit_asset','en','Asset',''),
('page_asset','header_edit_space','en','Space',''),
('page_asset','header_new_asset','en','New Asset',''),
('page_asset','header_new_space','en','New Space / Location',''),
('page_asset','lbl_filter_archetype','en','Filter by Archetype:',''),
('page_asset','master_heading','en','Asset Tree & Inventory',''),
('page_asset','master_heading_space','en','Spaces & Locations Tree',''),
('page_asset','msg_no_building_warning','en','Warning: No Building (archetype BUILDING) is defined in the organization yet. Please create at least one building (even fictitious), as rooms and cabling must be placed in buildings, and physical assets, hosts, documents, and media must be placed in rooms.',''),
('page_asset','opt_all_assets','en','--- All Asset Archetypes (Excl. Spaces) ---',''),
('page_asset','opt_all_spaces','en','--- All Spaces & Locations ---',''),
('page_asset','page_title','en','Asset Inventory (CRMM)',''),
('page_asset','page_title_space','en','Spaces & Locations (CRMM)',''),
('page_asset','th_archetype','en','Archetype',''),
('page_asset','th_asset_caption','en','Asset / Service',''),
('page_asset','th_res_risk','en','Res. Risk',''),
('page_asset','th_space_caption','en','Space / Location','');
GO