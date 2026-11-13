/* =============================================================================
 * Verze: 2026-11-13 16:30
 * Soubor: page_link_diagram#phrase.sql
 * Účel:   Registrace stránky page_link_diagram do sysinit_object, položky menu
 *         link_diagram do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
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
('page_link_diagram','btn_diagram_derived_defs','cs','Odvozené vztahy ({$count}) →','Přejde na přehled nepřímých vztahů vygenerovaných z tohoto diagramu','btn-secondary'),
('page_link_diagram','btn_diagram_edges','cs','Spojnice a vazby sítě ({$edges} / {$links}) →','Přejde na správu spojnic diagramu a přehled vygenerovaných nepřímých vazeb','btn-secondary'),
('page_link_diagram','btn_new_diagram','cs','+ Nové schéma sítě (diagram)','Založí nové schéma heterogenní sítě vztahů',''),
('page_link_diagram','btn_rebuild_diagram','cs','↻ Přepočítat a promítnout síť','Vyhodnotí topologii diagramu a vygeneruje odvozené nepřímé vztahy do meta_link_def a vazby do link',''),
('page_link_diagram','grp_identification','cs','Identifikace, řazení, vzhled a platnost','',''),
('page_link_diagram','grp_presentation','cs','Prezentační texty a popis schématu sítě','',''),
('page_link_diagram','hdr_diagram_class_topology','cs','Topologie tříd v heterogenní síti (vrcholové třídy → podřízené třídy):','',''),
('page_link_diagram','header_edit_diagram','cs','Schéma sítě','',''),
('page_link_diagram','header_new_diagram','cs','Nové schéma sítě vztahů','',''),
('page_link_diagram','msg_diagram_no_edges','cs','V tomto schématu sítě zatím nejsou zařazeny žádné orientované vztahy. Klikněte na „Spojnice a vazby sítě“ v záhlaví detailu a přidejte vztahy pomocí „diagram_includes_link_def“.','',''),
('page_link_diagram','msg_new_diagram_hint','cs','Tip: Po uložení schématu sítě k němu tlačítkem „Spojnice a vazby sítě“ přiřaďte orientované vztahy (vztah diagram_includes_link_def) a stiskněte „Přepočítat a promítnout síť“.','',''),
('page_link_diagram','page_title','cs','Schémata sítí vztahů (Diagramy CRMM)','',''),
('page_link_diagram','th_builtin_code','cs','Kód','',''),
('page_link_diagram','th_diagram_caption','cs','Název schématu sítě','',''),
('page_link_diagram','th_sort_code','cs','Pořadí','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_link_diagram','badge_cycle_error','en','Class Cycle Detected!',''),
('page_link_diagram','badge_self_loop','en','Intra-Class Traversal (Self-Referencing)',''),
('page_link_diagram','badge_top_class','en','Top-Level Class',''),
('page_link_diagram','btn_diagram_derived_defs','en','Derived Relationships ({$count}) →','View indirect relationships generated from this diagram'),
('page_link_diagram','btn_diagram_edges','en','Network Edges & Links ({$edges} / {$links}) →','Manage diagram edges and view projected indirect links'),
('page_link_diagram','btn_new_diagram','en','+ New Network Diagram (Schema)','Create a new heterogeneous network relationship diagram'),
('page_link_diagram','btn_rebuild_diagram','en','↻ Recalculate & Project Network','Evaluate diagram topology and project indirect relationships and links'),
('page_link_diagram','grp_identification','en','Identification, Ordering, Appearance & Validity',''),
('page_link_diagram','grp_presentation','en','Presentation Texts & Network Schema Description',''),
('page_link_diagram','hdr_diagram_class_topology','en','Class Topology in Heterogeneous Network (Top-Level Classes → Subordinate Classes):',''),
('page_link_diagram','header_edit_diagram','en','Network Schema',''),
('page_link_diagram','header_new_diagram','en','New Network Relationship Diagram',''),
('page_link_diagram','msg_diagram_no_edges','en','No directed relationships are assigned to this network schema yet. Click "Network Edges & Links" in the detail header and add relationships using "diagram_includes_link_def".',''),
('page_link_diagram','msg_new_diagram_hint','en','Tip: After saving the network schema, use the "Network Edges & Links" button to assign directed relationships (diagram_includes_link_def) and click "Recalculate & Project Network".',''),
('page_link_diagram','page_title','en','Network Relationship Diagrams (CRMM)',''),
('page_link_diagram','th_builtin_code','en','Code',''),
('page_link_diagram','th_diagram_caption','en','Network Schema Name',''),
('page_link_diagram','th_sort_code','en','Order','');
GO