/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: abstract_page_tree#phrase.sql
 * Účel:   Registrace stromové šablony abstract_page_tree do sysinit_object
 *         a naplnění jejích českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'abstract_page_tree';
DELETE FROM sysinit_phrase WHERE source_code = 'abstract_page_tree';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','abstract_page_tree','cs','U','Stromová šablona Master-Detail','Abstraktní dvoupanelová šablona pro správu hierarchických stromových struktur s podporou Drag & Drop'),
('P','abstract_page_tree','en','U','Tree Master-Detail Template','Abstract two-panel template for managing hierarchical tree structures with Drag & Drop support');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('abstract_page_tree','badge_draft','cs','Koncept','',''),
('abstract_page_tree','badge_forwarded','cs','Ke schválení','',''),
('abstract_page_tree','badge_rejected','cs','Vráceno','',''),
('abstract_page_tree','badge_removed','cs','Zrušeno','',''),
('abstract_page_tree','btn_collapse_all','cs','Sbalit vše','Sbalí všechny rozbalené větve stromu v levém panelu',''),
('abstract_page_tree','btn_expand_all','cs','Rozbalit vše','Rozbalí všechny složky stromu v levém panelu',''),
('abstract_page_tree','btn_new_tree_item','cs','+ Nová položka','Založí novou položku ve stromové struktuře',''),
('abstract_page_tree','btn_split_node_oth','cs','Rozčlenit na podtřídy (+ _oth)','Vytvoří pod tímto uzlem koncovou položku „Ostatní (*_oth)“, převede na ni navázané záznamy a uvolní tento uzel jako složku','btn-secondary'),
('abstract_page_tree','confirm_split_node_oth','cs','Opravdu chcete tento koncový uzel změnit na složku a převést jeho přímé vazby a záznamy na novou podřízenou položku „Ostatní ({$code}_oth)“?','',''),
('abstract_page_tree','default_tree_heading','cs','Strom záznamů','',''),
('abstract_page_tree','lbl_show_removed','cs','Zobrazit i zrušené','',''),
('abstract_page_tree','msg_auto_split_parent_info','cs','Nadřízený koncový uzel byl automaticky změněn na složku a jeho původní přímé záznamy byly převedeny na novou položku „{$code}“.','',''),
('abstract_page_tree','msg_dnd_unsaved_notice','cs','Nadřízená položka (parent_uuid) a pořadí (sort_code) byly upraveny přetažením. Zkontrolujte údaje a potvrďte je tlačítkem Uložit změny (příp. Uložit koncept / Předat ke schválení).','',''),
('abstract_page_tree','msg_node_locked_notice','cs','🔒 Tento uzel (nebo jeho podřízený uzel) má již navázané platné záznamy. Změna nadřízeného uzlu (přepodřízení) a smazání jsou uzamčeny; pokud potřebujete tento koncový uzel dále členit na podtřídy, použijte tlačítko „Rozčlenit na podtřídy (+ _oth)“ v záhlaví detailu (nebo pod něj rovnou přidejte novou položku).','',''),
('abstract_page_tree','placeholder_search','cs','Hledat ve stromu...','',''),
('abstract_page_tree','th_builtin_code','cs','Kód','',''),
('abstract_page_tree','th_sort_code','cs','Pořadí','',''),
('abstract_page_tree','th_tree_caption','cs','Název položky (Strom)','',''),
('abstract_page_tree','tip_drag_handle','cs','Přetažením myší (Drag & Drop) upravíte pořadí nebo nadřízenou složku v detailu','',''),
('abstract_page_tree','tip_folder_node','cs','Vnitřní složka hierarchie (is_leaf = 0)','',''),
('abstract_page_tree','tip_locked_node','cs','Uzel má navázané záznamy – změna nadřízené složky je uzamčena (lze měnit pouze pořadí mezi sourozenci)','',''),
('abstract_page_tree','tip_toggle_branch','cs','Sbalit / rozbalit podřízené položky','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('abstract_page_tree','badge_draft','en','Draft',''),
('abstract_page_tree','badge_forwarded','en','Pending Approval',''),
('abstract_page_tree','badge_rejected','en','Returned',''),
('abstract_page_tree','badge_removed','en','Removed',''),
('abstract_page_tree','btn_collapse_all','en','Collapse All','Collapse all expanded tree branches in the left panel'),
('abstract_page_tree','btn_expand_all','en','Expand All','Expand all tree folders in the left panel'),
('abstract_page_tree','btn_new_tree_item','en','+ New Item','Create a new item in the tree hierarchy'),
('abstract_page_tree','btn_split_node_oth','en','Split into Subclasses (+ _oth)','Creates a terminal "Other (*_oth)" item under this node, moves linked records to it, and converts this node into a folder'),
('abstract_page_tree','confirm_split_node_oth','en','Are you sure you want to convert this leaf node into a folder and move its direct links and records to a new child item "Other ({$code}_oth)"?',''),
('abstract_page_tree','default_tree_heading','en','Record Tree',''),
('abstract_page_tree','lbl_show_removed','en','Show removed',''),
('abstract_page_tree','msg_auto_split_parent_info','en','The parent leaf node was automatically converted into a folder and its original direct records were moved to the new item "{$code}".',''),
('abstract_page_tree','msg_dnd_unsaved_notice','en','Parent item (parent_uuid) and sort order (sort_code) were adjusted via Drag & Drop. Review the details and confirm by clicking Save Changes (or Save Draft / Submit for Approval).',''),
('abstract_page_tree','msg_node_locked_notice','en','🔒 This node (or its child node) already has active linked records. Changing its parent node (reparenting) and deletion are locked; if you need to subdivide this leaf node into subclasses, use the "Split into Subclasses (+ _oth)" button in the detail header (or add a new child item directly under it).',''),
('abstract_page_tree','placeholder_search','en','Search tree...',''),
('abstract_page_tree','th_builtin_code','en','Code',''),
('abstract_page_tree','th_sort_code','en','Order',''),
('abstract_page_tree','th_tree_caption','en','Item Name (Tree)',''),
('abstract_page_tree','tip_drag_handle','en','Drag & Drop to adjust sort order or parent folder in the detail panel',''),
('abstract_page_tree','tip_folder_node','en','Internal hierarchy folder (is_leaf = 0)',''),
('abstract_page_tree','tip_locked_node','en','Node has linked records – changing parent folder is locked (only sibling order can be changed)',''),
('abstract_page_tree','tip_toggle_branch','en','Collapse / expand child items','');
GO