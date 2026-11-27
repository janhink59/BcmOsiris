/* =============================================================================
 * Verze: 2026-11-27 15:40
 * Soubor: page_link_diagram#phrase.sql
 *
 * 1. Role souboru v celém systému:
 *    Registrace stránky page_link_diagram do sysinit_object, položky menu
 *    link_diagram do sysinit_menu a kompletní sady českých i anglických frází
 *    do sysinit_phrase (včetně integrovaného editoru hran schématu).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Odpovídá voláním $this->phrase() a new abstract_button() v page_link_diagram.php.
 *    - Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 *
 * 3. Očekávaná kontextová data:
 *    - Běží jako součást sestavovací dávky databáze (maska *#phrase.sql) nad
 *      staging tabulkami sysinit_* bez závislosti na relaci v dbsession.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_link_diagram';
DELETE FROM sysinit_menu WHERE builtin_code = 'link_diagram';
DELETE FROM sysinit_phrase WHERE source_code = 'page_link_diagram';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_link_diagram','cs','U','Schémata sítí vztahů (Diagramy CRMM)','Správa orientovaných schémat heterogenních sítí vztahů a projekce nepřímých vazeb pro přenos rizik'),
('P','page_link_diagram','en','U','Network Relationship Diagrams (CRMM)','Management of directed heterogeneous network schemas and projection of indirect links for risk propagation');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('link_diagram','cs','crmm_folder','120','page_link_diagram','','U','<svg viewBox="0 0 24 24" fill="#4F46E5"><path d="M14 4l2.29 2.29-2.88 2.88 1.42 1.42 2.88-2.88L20 10V4h-6zm-4 0H4v6l2.29-2.29 4.71 4.7V20h2v-8.41l-5.29-5.3L10 4z"/></svg>','Schémata sítí vztahů (Diagramy)','Správa orientovaných schémat heterogenních sítí vztahů a projekce nepřímých vazeb pro výpočet cest přenosu rizik','Správa orientovaných schémat heterogenních sítí vztahů a projekce nepřímých vazeb pro výpočet cest přenosu rizik');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('link_diagram','en','Network Diagrams (Schemas)','Management of directed heterogeneous network schemas and projection of indirect links for risk propagation path calculation','Management of directed heterogeneous network schemas and projection of indirect links for risk propagation path calculation');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_link_diagram','badge_cycle_error','cs','Zacyklení tříd!','',''),
('page_link_diagram','badge_self_loop','cs','Vnitrotřídní průchod (self-referencing)','',''),
('page_link_diagram','badge_top_class','cs','Vrcholová třída','',''),
('page_link_diagram','btn_add_edge','cs','+ Přidat vztah','Zařadí zvolený orientovaný vztah z katalogu jako hranu tohoto schématu sítě',''),
('page_link_diagram','btn_diagram_derived_defs','cs','Odvozené vztahy ({$count}) →','Přejde na přehled nepřímých vztahů tříd vygenerovaných z tohoto diagramu','btn-secondary'),
('page_link_diagram','btn_new_diagram','cs','+ Nové schéma sítě (diagram)','Založí nové schéma heterogenní sítě vztahů',''),
('page_link_diagram','btn_rebuild_diagram','cs','↻ Přepočítat a promítnout síť','Vyhodnotí topologii diagramu a vygeneruje odvozené nepřímé vztahy do meta_link_def a vazby do link',''),
('page_link_diagram','btn_remove_edge','cs','Odebrat','Odebere tento vztah ze schématu sítě','btn-danger'),
('page_link_diagram','err_diagram_cycle_rebuild_blocked','cs','Schéma sítě obsahuje zacyklení mezi logickými třídami! Odstraňte prosím kolidující vztah a poté spusťte přepočet znovu.','',''),
('page_link_diagram','grp_identification','cs','Identifikace, řazení, vzhled a platnost','',''),
('page_link_diagram','grp_presentation','cs','Prezentační texty a popis schématu sítě','',''),
('page_link_diagram','hdr_diagram_class_topology','cs','Topologie tříd v heterogenní síti (vrcholové třídy → podřízené třídy):','',''),
('page_link_diagram','hdr_diagram_edges','cs','Vztahy (hrany) zařazené do schématu ({$count})','',''),
('page_link_diagram','header_edit_diagram','cs','Schéma sítě','',''),
('page_link_diagram','header_new_diagram','cs','Nové schéma sítě vztahů','',''),
('page_link_diagram','lbl_add_edge_select','cs','Přidat orientovaný vztah z katalogu (Definice typů vazeb):','',''),
('page_link_diagram','lbl_show_fk_defs','cs','Zobrazit i technické 1:N FK vztahy','',''),
('page_link_diagram','lbl_via_edges','cs','přes','',''),
('page_link_diagram','msg_diagram_cycle_banner','cs','Pozor: Zvolená sada vztahů vytváří cyklus mezi logickými třídami. Acyklický graf nelze s cyklem promítnout – odeberte některou hranu tvořící smyčku.','',''),
('page_link_diagram','msg_diagram_no_edges','cs','V tomto schématu sítě zatím nejsou zařazeny žádné vztahy. Vyberte orientované vztahy v seznamu níže a klikněte na „+ Přidat vztah“.','',''),
('page_link_diagram','msg_new_diagram_hint','cs','Tip: Nejprve uložte název a kód nového schématu sítě. Ihned po uložení se zde otevře výběr orientovaných vztahů (hran grafu) z katalogu Definice typů vazeb.','',''),
('page_link_diagram','opt_select_edge','cs','--- Vyberte orientovaný vztah k přidání ---','',''),
('page_link_diagram','page_title','cs','Schémata sítí vztahů (Diagramy CRMM)','',''),
('page_link_diagram','ph_filter_edges','cs','Filtrovat dostupné vztahy (název třídy nebo kód)...','',''),
('page_link_diagram','th_builtin_code','cs','Kód','',''),
('page_link_diagram','th_diagram_caption','cs','Název schématu sítě','',''),
('page_link_diagram','th_edge_action','cs','Akce','',''),
('page_link_diagram','th_edge_classes','cs','Zdrojová třída → Cílová třída','',''),
('page_link_diagram','th_edge_dir','cs','Směr','',''),
('page_link_diagram','th_edge_link','cs','Vztah (název a kód)','',''),
('page_link_diagram','th_sort_code','cs','Pořadí','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_link_diagram','badge_cycle_error','en','Class Cycle Detected!',''),
('page_link_diagram','badge_self_loop','en','Intra-Class Traversal (Self-Referencing)',''),
('page_link_diagram','badge_top_class','en','Top-Level Class',''),
('page_link_diagram','btn_add_edge','en','+ Add Relationship','Include the selected directed relationship from the catalog as an edge of this diagram'),
('page_link_diagram','btn_diagram_derived_defs','en','Derived Relationships ({$count}) →','View indirect class relationships generated from this diagram'),
('page_link_diagram','btn_new_diagram','en','+ New Network Diagram (Schema)','Create a new heterogeneous network relationship diagram'),
('page_link_diagram','btn_rebuild_diagram','en','↻ Recalculate & Project Network','Evaluate diagram topology and project indirect relationships and links'),
('page_link_diagram','btn_remove_edge','en','Remove','Remove this relationship from the network diagram'),
('page_link_diagram','err_diagram_cycle_rebuild_blocked','en','The network schema contains a cycle between logical classes! Please remove the conflicting relationship and recalculate again.',''),
('page_link_diagram','grp_identification','en','Identification, Ordering, Appearance & Validity',''),
('page_link_diagram','grp_presentation','en','Presentation Texts & Network Schema Description',''),
('page_link_diagram','hdr_diagram_class_topology','en','Class Topology in Heterogeneous Network (Top-Level Classes → Subordinate Classes):',''),
('page_link_diagram','hdr_diagram_edges','en','Relationships (Edges) Included in Schema ({$count})',''),
('page_link_diagram','header_edit_diagram','en','Network Schema',''),
('page_link_diagram','header_new_diagram','en','New Network Relationship Diagram',''),
('page_link_diagram','lbl_add_edge_select','en','Add directed relationship from catalog (Link Type Definitions):',''),
('page_link_diagram','lbl_show_fk_defs','en','Include technical 1:N FK relationships',''),
('page_link_diagram','lbl_via_edges','en','via',''),
('page_link_diagram','msg_diagram_cycle_banner','en','Warning: The selected relationships form a cycle between logical classes. An acyclic graph cannot be projected with a cycle – please remove one of the edges forming the loop.',''),
('page_link_diagram','msg_diagram_no_edges','en','No relationships are assigned to this network schema yet. Choose directed relationships from the list below and click "+ Add Relationship".',''),
('page_link_diagram','msg_new_diagram_hint','en','Tip: Save the name and code of the new network schema first. Immediately after saving, the selector for directed relationships (graph edges) from Link Type Definitions will appear here.',''),
('page_link_diagram','opt_select_edge','en','--- Select a directed relationship to add ---',''),
('page_link_diagram','page_title','en','Network Relationship Diagrams (CRMM)',''),
('page_link_diagram','ph_filter_edges','en','Filter available relationships (class name or code)...',''),
('page_link_diagram','th_builtin_code','en','Code',''),
('page_link_diagram','th_diagram_caption','en','Network Schema Name',''),
('page_link_diagram','th_edge_action','en','Action',''),
('page_link_diagram','th_edge_classes','en','Source Class → Target Class',''),
('page_link_diagram','th_edge_dir','en','Dir.',''),
('page_link_diagram','th_edge_link','en','Relationship (Caption & Code)',''),
('page_link_diagram','th_sort_code','en','Order','');
GO