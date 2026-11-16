<?php
/**
 * =============================================================================
 * Verze: 2026-11-16 16:15
 * Soubor: tree_scripts.php
 * Třída: tree_scripts
 *
 * 1. Role souboru v celém systému:
 *    Zapouzdřuje stabilní klientské CSS styly a JavaScriptový engine pro
 *    všechny stromové stránky dědící z abstract_page_tree (rozbalování a
 *    sbalování větví v sessionStorage, stromový filtr zachovávající nadřízené
 *    uzly a kompletní Drag & Drop engine přepočítávající parent_uuid a
 *    sort_code).
 *    Vyčleněno z abstract_page_tree.php pro snížení velikosti souboru pod 20 KB
 *    a zamezení opakovanému přenosu 18 KB skriptu při AJAX obnově stromu.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Načítána automaticky přes spl_autoload_register v config.php.
 *    - Volána z metody abstract_page_tree::render_master()
 *      (abstract_page_tree.php).
 *    - Spolupracuje s funkcemi loadDetailPanel() a refreshMasterPanel()
 *      definovanými v master_detail_scripts.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Přijímá konfigurační pole stromu ($cfg) z volající stránky; při AJAX
 *      volání (?ajax_panel=master) již nevypisuje duplicitně CSS ani JS engine,
 *      ale pouze zavolá window.bcmInitTreeMaster(cfg).
 * =============================================================================
 */

declare(strict_types=1);

class tree_scripts {

	private static bool $assets_rendered = false;                            // Příznak jednorázového vložení CSS a JS enginu v requestu

	/**
	 * Vykreslí CSS styly pro stromový Master panel (při AJAX obnově se nevypisují duplicitně).
	 */
	public static function render_styles(): string {
		if (isset($_GET['ajax_panel'])) {                                    // Při AJAX obnově jsou již styly v dokumentu přítomny
			return '';                                                       // Prázdný výstup při AJAXu
		}

		return <<<HTML
		<style>
			.tree-toggle-btn {
				display: inline-flex;
				align-items: center;
				justify-content: center;
				width: 18px;
				height: 18px;
				margin-right: 4px;
				border: 1px solid #cbd5e1;
				border-radius: 3px;
				background-color: #f8fafc;
				color: #334155;
				font-size: 10px;
				line-height: 1;
				cursor: pointer;
				user-select: none;
				padding: 0;
				vertical-align: middle;
			}
			.tree-toggle-btn:hover { background-color: #e2e8f0; color: #004488; }
			.tree-toggle-spacer { display: inline-block; width: 18px; margin-right: 4px; }
			.tree-ctrl-link {
				font-size: 11px;
				color: #004488;
				background: none;
				border: 1px solid #cbd5e1;
				border-radius: 3px;
				padding: 2px 6px;
				cursor: pointer;
				background-color: #fff;
			}
			.tree-ctrl-link:hover { background-color: #e9f2fa; }
			.dnd-grip, .tree-node-icon {
				display: inline-flex;
				align-items: center;
				justify-content: center;
				min-width: 16px;
				height: 16px;
				margin-right: 5px;
				font-size: 13px;
				line-height: 1;
				user-select: none;
				vertical-align: middle;
			}
			.dnd-grip {
				color: #94a3b8;
				cursor: grab;
			}
			.dnd-grip:hover { color: #004488; }
			.dnd-grip:active { cursor: grabbing; }
			.dnd-grip.dnd-grip-icon, .tree-node-icon { color: #004488; }
			.dnd-grip svg, .tree-node-icon svg {
				width: 16px;
				height: 16px;
				display: block;
				flex-shrink: 0;
				pointer-events: none;
			}
			.dnd-grip svg:not([fill]), .tree-node-icon svg:not([fill]) {
				fill: currentColor;
			}
			.tree-folder-icon { font-size: 12px; margin-right: 4px; vertical-align: middle; }
			.tree-lock-icon { font-size: 11px; margin-left: 5px; vertical-align: middle; cursor: help; }
			tr.tree-ancestor-context td { opacity: 0.72; background-color: #f8fafc; }
			tr.dnd-dragging { opacity: 0.45; }
			tr.dnd-drop-before td { border-top: 2px solid #2563eb !important; }
			tr.dnd-drop-after td { border-bottom: 2px solid #2563eb !important; }
			tr.dnd-drop-inside td { background-color: #dbeafe !important; outline: 1px dashed #2563eb; }
		</style>
HTML;
	}

	/**
	 * Jednorázově vygeneruje hlavní JavaScriptový engine `window.bcmInitTreeMaster`.
	 */
	private static function render_engine_once(): string {
		if (self::$assets_rendered OR isset($_GET['ajax_panel'])) {          // Engine vkládáme pouze při prvotním načtení stránky
			return '';                                                       // Při AJAX obnově již v okně existuje
		}
		self::$assets_rendered = true;                                       // Označení vloženého enginu

		return <<<'HTML'
		<script>
			window.bcmInitTreeMaster = function(cfg) {
				const STORAGE_KEY     = cfg.storageKey ? cfg.storageKey : 'bcm_tree_collapsed';
				const initialOpenOrig = cfg.initialOpenOrig ? cfg.initialOpenOrig : '';
				const canDragDrop     = Boolean(cfg.canDragDrop);
				const basePageUrl     = cfg.basePageUrl ? cfg.basePageUrl : '';
				const parentColName   = cfg.parentColName ? cfg.parentColName : 'parent_uuid';
				const sortColName     = cfg.sortColName ? cfg.sortColName : 'sort_code';
				const hasServerFilter = Boolean(cfg.hasServerFilter);

				// Dynamicky zjistí právě otevřenou položku v detailu (odolné vůči AJAX přepínání detailu)
				function getCurrentOpenOrig() {
					const inp = document.querySelector('.md-detail form input[name="update_guid"]');
					if (inp && inp.value && inp.value !== 'NEW') {
						return inp.value.toLowerCase();
					}
					const actRow = document.getElementById('active-row');
					if (actRow && actRow.dataset.orig) {
						return actRow.dataset.orig.toLowerCase();
					}
					return initialOpenOrig;
				}

				// Načtení sbalených větví ze sessionStorage prohlížeče
				function getCollapsedSet() {
					try {
						const raw = sessionStorage.getItem(STORAGE_KEY);
						const arr = raw ? JSON.parse(raw) : [];
						return new Set(Array.isArray(arr) ? arr : []);
					} catch (e) {
						return new Set();
					}
				}

				function saveCollapsedSet(setObj) {
					try {
						sessionStorage.setItem(STORAGE_KEY, JSON.stringify(Array.from(setObj)));
					} catch (e) {}
				}

				// Zajistí, že předci právě vybraného řádku (#active-row) nebudou sbalení
				function ensureActiveRowVisible(collapsedSet) {
					const openOrig = getCurrentOpenOrig();
					if (!openOrig) return;
					const rowsMap = {};
					document.querySelectorAll('#master-list tr[data-orig]').forEach(function(r) {
						rowsMap[r.dataset.orig] = r.dataset.parent ? r.dataset.parent : '';
					});
					let p = rowsMap[openOrig] ? rowsMap[openOrig] : '';
					let guard = 0;
					while (p !== '' && guard < 50) {
						collapsedSet.delete(p);
						p = rowsMap[p] ? rowsMap[p] : '';
						guard++;
					}
				}

				// Stromový filtr se zachováním všech nadřízených uzlů až ke kořeni stromu
				window.applyTreeMasterFilter = function(term) {
					const cleanTerm = (term ? term : '').trim().toLowerCase();
					const allRows = document.querySelectorAll('#master-list tr[data-orig]');
					if (cleanTerm === '') {
						allRows.forEach(function(r) {
							const isAnc = (r.dataset.srvAncestor !== '1' ? true : r.classList.contains('md-row-active'));
							if (isAnc) {
								r.classList.remove('tree-ancestor-context');
							} else {
								r.classList.add('tree-ancestor-context');
							}
						});
						window.applyMenuTreeVisibility();
						return;
					}

					const parentLookup = {};
					const matchedSet = new Set();
					const visibleSet = new Set();

					allRows.forEach(function(r) {
						const orig = r.dataset.orig;
						parentLookup[orig] = r.dataset.parent ? r.dataset.parent : '';
						if (r.textContent.toLowerCase().indexOf(cleanTerm) !== -1) {
							matchedSet.add(orig);
							visibleSet.add(orig);
						}
					});

					// Doplnění všech nadřízených uzlů pro každý vyhovující řádek až ke kořeni
					matchedSet.forEach(function(orig) {
						let p = parentLookup[orig] ? parentLookup[orig] : '';
						let guard = 0;
						while (p !== '' && guard < 50) {
							visibleSet.add(p);
							p = parentLookup[p] ? parentLookup[p] : '';
							guard++;
						}
					});

					allRows.forEach(function(r) {
						const orig = r.dataset.orig;
						if (visibleSet.has(orig)) {
							r.style.display = '';
							const isDirectMatch = matchedSet.has(orig);
							if (!isDirectMatch && !r.classList.contains('md-row-active')) {
								r.classList.add('tree-ancestor-context');
							} else {
								r.classList.remove('tree-ancestor-context');
							}
							const btn = r.querySelector('.tree-toggle-btn');
							if (btn) {
								btn.textContent = '▼';
							}
						} else {
							r.style.display = 'none';
						}
					});
				};

				// Překreslí viditelnost řádků a ikony ▼/▶ podle stavu sbalení
				window.applyMenuTreeVisibility = function() {
					const filterInput = document.getElementById('master-filter');
					if (filterInput && filterInput.value.trim() !== '') {
						window.applyTreeMasterFilter(filterInput.value);
						return;
					}
					const collapsedSet = hasServerFilter ? new Set() : getCollapsedSet();
					const parentLookup = {};
					const allRows = document.querySelectorAll('#master-list tr[data-orig]');

					allRows.forEach(function(r) {
						parentLookup[r.dataset.orig] = r.dataset.parent ? r.dataset.parent : '';
						const btn = r.querySelector('.tree-toggle-btn');
						if (btn) {
							btn.textContent = collapsedSet.has(r.dataset.orig) ? '▶' : '▼';
						}
					});

					allRows.forEach(function(r) {
						let p = r.dataset.parent ? r.dataset.parent : '';
						let hiddenByAncestor = false;
						let guard = 0;
						while (p !== '' && guard < 50) {
							if (collapsedSet.has(p)) {
								hiddenByAncestor = true;
								break;
							}
							p = parentLookup[p] ? parentLookup[p] : '';
							guard++;
						}
						r.style.display = hiddenByAncestor ? 'none' : '';
					});
				};

				window.toggleMenuBranch = function(ev, orig) {
					ev.stopPropagation();
					ev.preventDefault();
					const filterInput = document.getElementById('master-filter');
					if (filterInput && filterInput.value.trim() !== '') {
						return;
					}
					const collapsedSet = getCollapsedSet();
					if (collapsedSet.has(orig)) {
						collapsedSet.delete(orig);
					} else {
						collapsedSet.add(orig);
					}
					saveCollapsedSet(collapsedSet);
					window.applyMenuTreeVisibility();
				};

				window.expandAllMenuBranches = function() {
					saveCollapsedSet(new Set());
					window.applyMenuTreeVisibility();
				};

				window.collapseAllMenuBranches = function() {
					const collapsedSet = new Set();
					document.querySelectorAll('#master-list .tree-toggle-btn').forEach(function(btn) {
						const orig = btn.getAttribute('data-toggle-orig');
						if (orig) {
							const row = btn.closest('tr');
							if (!row ? true : row.dataset.protRoot !== '1') {
								collapsedSet.add(orig);
							}
						}
					});
					saveCollapsedSet(collapsedSet);
					window.applyMenuTreeVisibility();
				};

				const initSet = getCollapsedSet();
				ensureActiveRowVisible(initSet);
				saveCollapsedSet(initSet);
				window.applyMenuTreeVisibility();

				const fInp = document.getElementById('master-filter');
				if (fInp && fInp.value.trim() !== '') {
					window.applyTreeMasterFilter(fInp.value);
				}

				// =============================================================
				// DRAG & DROP (Varianta 1: Úprava parent_uuid a sort_code v detailu)
				// =============================================================
				if (!canDragDrop) return;

				const tbody = document.getElementById('master-list');
				if (!tbody ? true : tbody.dataset.dndBound === '1') return;
				tbody.dataset.dndBound = '1';

				let draggedRow = null;
				let draggedDescendants = new Set();

				function collectSubtreeOrigs(rootOrig) {
					const set = new Set([rootOrig]);
					let added = true;
					while (added) {
						added = false;
						tbody.querySelectorAll('tr[data-orig]').forEach(function(r) {
							const o = r.dataset.orig;
							const p = r.dataset.parent ? r.dataset.parent : '';
							if (p !== '' && set.has(p) && !set.has(o)) {
								set.add(o);
								added = true;
							}
						});
					}
					return set;
				}

				function clearDropIndicators() {
					tbody.querySelectorAll('tr').forEach(function(r) {
						r.classList.remove('dnd-drop-before', 'dnd-drop-after', 'dnd-drop-inside');
					});
				}

				function computeBetweenSortCode(prevCode, nextCode) {
					const cleanPrev = (prevCode ? prevCode : '').replace(/[^0-9]/g, '');
					const cleanNext = (nextCode ? nextCode : '').replace(/[^0-9]/g, '');

					if (cleanPrev === '' && cleanNext === '') {
						return '010';
					}

					if (cleanNext === '') {
						const padLen = Math.max(cleanPrev.length, 3);
						const paddedPrev = cleanPrev.padEnd(padLen, '0');
						const prevNum = parseInt(paddedPrev, 10) ? parseInt(paddedPrev, 10) : 0;
						const nextTen = (Math.floor(prevNum / 10) + 1) * 10;
						return String(nextTen).padStart(padLen, '0');
					}

					let len = Math.max(cleanPrev.length, cleanNext.length, 3);
					while (len <= 18) {
						const pStr = cleanPrev === '' ? ''.padEnd(len, '0') : cleanPrev.padEnd(len, '0');
						const nStr = cleanNext.padEnd(len, '0');
						const pNum = parseInt(pStr, 10) ? parseInt(pStr, 10) : 0;
						const nNum = parseInt(nStr, 10) ? parseInt(nStr, 10) : 0;

						if (nNum - pNum > 1) {
							const mid = Math.floor((pNum + nNum) / 2);
							let res = String(mid).padStart(len, '0');
							if (res.length > 3) {
								res = res.replace(/0+$/, '');
								if (res.length < 3) res = res.padEnd(3, '0');
							}
							if ((cleanPrev === '' ? true : res > prevCode) && res < nextCode) {
								return res;
							}
						}
						len++;
					}

					return (prevCode ? prevCode : '000') + '5';
				}

				function resolveDropMode(targetRow, clientY) {
					const rect = targetRow.getBoundingClientRect();
					const relY = clientY - rect.top;
					const height = rect.height ? rect.height : 30;
					const isFolder = (targetRow.dataset.isFolder === '1');
					const isProtRoot = (targetRow.dataset.protRoot === '1');
					const isDraggedLocked = (draggedRow && draggedRow.dataset.locked === '1');
					const dragParent = (draggedRow && draggedRow.dataset.parent) ? draggedRow.dataset.parent : '';
					const targetParent = targetRow.dataset.parent ? targetRow.dataset.parent : '';

					if (isDraggedLocked) {
						if (isFolder && targetRow.dataset.orig === dragParent) {
							return 'inside';
						}
						if (targetParent !== dragParent ? true : isProtRoot) {
							return null;
						}
						return (relY < height * 0.5) ? 'before' : 'after';
					}

					if (isProtRoot) {
						return isFolder ? 'inside' : 'after';
					}
					if (isFolder) {
						if (relY < height * 0.25) return 'before';
						if (relY > height * 0.75) return 'after';
						return 'inside';
					}
					return (relY < height * 0.5) ? 'before' : 'after';
				}

				function reorderTreeDom(movedRow, newParentOrig, newParentUuid, newSortCode) {
					movedRow.dataset.parent = newParentOrig;
					movedRow.dataset.parentUuid = newParentUuid;
					movedRow.dataset.sort = newSortCode;
					const sortCell = movedRow.querySelector('.cell-tree-sort');
					if (sortCell) {
						sortCell.textContent = newSortCode;
					}

					if (newParentOrig !== '') {
						const cSet = getCollapsedSet();
						if (cSet.has(newParentOrig)) {
							cSet.delete(newParentOrig);
							saveCollapsedSet(cSet);
						}
					}

					const allRows = Array.from(tbody.querySelectorAll('tr[data-orig]'));
					const byParent = {};
					allRows.forEach(function(r) {
						const p = r.dataset.parent ? r.dataset.parent : '';
						if (!byParent[p]) byParent[p] = [];
						byParent[p].push(r);
					});

					Object.keys(byParent).forEach(function(p) {
						byParent[p].sort(function(a, b) {
							const sa = a.dataset.sort ? a.dataset.sort : '';
							const sb = b.dataset.sort ? b.dataset.sort : '';
							if (sa !== sb) return sa.localeCompare(sb, undefined, { numeric: true, sensitivity: 'base' });
							return (a.dataset.code ? a.dataset.code : '').localeCompare(b.dataset.code ? b.dataset.code : '');
						});
					});

					const orderedRows = [];
					const visitedSet = new Set();
					function walkDomTree(pKey, lvl) {
						const list = byParent[pKey] ? byParent[pKey] : [];
						list.forEach(function(r) {
							const o = r.dataset.orig;
							if (visitedSet.has(o)) return;
							visitedSet.add(o);
							r.dataset.level = String(lvl);
							const capCell = r.querySelector('.cell-tree-caption');
							if (capCell) {
								capCell.style.paddingLeft = 'calc(6px + ' + (lvl * 18) + 'px)';
							}
							orderedRows.push(r);
							walkDomTree(o, lvl + 1);
						});
					}
					walkDomTree('', 0);
					orderedRows.forEach(function(r) {
						tbody.appendChild(r);
					});

					window.isTreeDomDirty = true;
					window.applyMenuTreeVisibility();
				}

				tbody.addEventListener('dragstart', function(e) {
					const tr = e.target.closest('tr[data-orig]');
					if (!tr ? true : tr.dataset.protRoot === '1') {
						e.preventDefault();
						return;
					}
					draggedRow = tr;
					draggedDescendants = collectSubtreeOrigs(tr.dataset.orig);
					tr.classList.add('dnd-dragging');
					if (e.dataTransfer) {
						e.dataTransfer.effectAllowed = 'move';
						e.dataTransfer.setData('text/plain', tr.dataset.uuid);
					}
				});

				tbody.addEventListener('dragend', function() {
					if (draggedRow) {
						draggedRow.classList.remove('dnd-dragging');
					}
					draggedRow = null;
					draggedDescendants.clear();
					clearDropIndicators();
				});

				tbody.addEventListener('dragover', function(e) {
					if (!draggedRow) return;
					const targetRow = e.target.closest('tr[data-orig]');
					if (!targetRow ? true : draggedDescendants.has(targetRow.dataset.orig)) {
						clearDropIndicators();
						return;
					}
					const mode = resolveDropMode(targetRow, e.clientY);
					if (!mode) {
						clearDropIndicators();
						return;
					}
					e.preventDefault();
					if (e.dataTransfer) {
						e.dataTransfer.dropEffect = 'move';
					}
					clearDropIndicators();
					targetRow.classList.add('dnd-drop-' + mode);
				});

				tbody.addEventListener('dragleave', function(e) {
					const targetRow = e.target.closest('tr[data-orig]');
					if (targetRow) {
						targetRow.classList.remove('dnd-drop-before', 'dnd-drop-after', 'dnd-drop-inside');
					}
				});

				tbody.addEventListener('drop', function(e) {
					if (!draggedRow) return;
					const targetRow = e.target.closest('tr[data-orig]');
					clearDropIndicators();
					if (!targetRow ? true : draggedDescendants.has(targetRow.dataset.orig)) {
						return;
					}
					const mode = resolveDropMode(targetRow, e.clientY);
					if (!mode) {
						return;
					}
					e.preventDefault();
					e.stopPropagation();

					const dragOrig = draggedRow.dataset.orig;
					const dragUuid = draggedRow.dataset.uuid;

					let newParentOrig = '';
					let newParentUuid = '';
					let prevSort = '';
					let nextSort = '';

					if (mode === 'inside') {
						newParentOrig = targetRow.dataset.orig;
						newParentUuid = targetRow.dataset.uuid;
						const existingChildren = Array.from(tbody.querySelectorAll('tr[data-orig]')).filter(function(r) {
							return (r.dataset.parent ? r.dataset.parent : '') === newParentOrig && r.dataset.orig !== dragOrig;
						});
						if (existingChildren.length > 0) {
							const lastChild = existingChildren[existingChildren.length - 1];
							prevSort = lastChild.dataset.sort ? lastChild.dataset.sort : '';
						}
					} else {
						newParentOrig = targetRow.dataset.parent ? targetRow.dataset.parent : '';
						newParentUuid = targetRow.dataset.parentUuid ? targetRow.dataset.parentUuid : '';
						const siblings = Array.from(tbody.querySelectorAll('tr[data-orig]')).filter(function(r) {
							return (r.dataset.parent ? r.dataset.parent : '') === newParentOrig && r.dataset.orig !== dragOrig;
						});
						const tIdx = siblings.indexOf(targetRow);
						if (mode === 'before') {
							prevSort = (tIdx > 0 && siblings[tIdx - 1].dataset.sort) ? siblings[tIdx - 1].dataset.sort : '';
							nextSort = targetRow.dataset.sort ? targetRow.dataset.sort : '';
						} else {
							prevSort = targetRow.dataset.sort ? targetRow.dataset.sort : '';
							nextSort = (tIdx >= 0 && tIdx + 1 < siblings.length && siblings[tIdx + 1].dataset.sort) ? siblings[tIdx + 1].dataset.sort : '';
						}
					}

					const newSortCode = computeBetweenSortCode(prevSort, nextSort);
					const activeOrig = getCurrentOpenOrig();

					reorderTreeDom(draggedRow, newParentOrig, newParentUuid, newSortCode);

					if (dragOrig !== activeOrig) {
						const targetUrl = basePageUrl
							+ '&update_guid=' + encodeURIComponent(dragUuid)
							+ '&dnd_parent=' + encodeURIComponent(newParentUuid)
							+ '&dnd_sort=' + encodeURIComponent(newSortCode);
						if (window.loadDetailPanel) {
							window.loadDetailPanel(targetUrl, draggedRow);
						} else {
							window.location.href = targetUrl;
						}
						return;
					}

					const parentSelect = document.querySelector('.md-detail form [name="' + parentColName + '"]');
					const sortInput = document.querySelector('.md-detail form [name="' + sortColName + '"]');

					if (parentSelect && !parentSelect.disabled && !parentSelect.readOnly) {
						let matchedVal = newParentUuid;
						if (parentSelect.options) {
							Array.from(parentSelect.options).forEach(function(opt) {
								if (opt.value.toLowerCase() === newParentUuid.toLowerCase()) {
									matchedVal = opt.value;
								}
							});
						}
						parentSelect.value = matchedVal;
						parentSelect.style.backgroundColor = '#dcfce7';
						parentSelect.style.borderColor = '#16a34a';
					}

					if (sortInput && !sortInput.disabled && !sortInput.readOnly) {
						sortInput.value = newSortCode;
						sortInput.style.backgroundColor = '#dcfce7';
						sortInput.style.borderColor = '#16a34a';
					}

					const banner = document.getElementById('tree-dnd-banner');
					if (banner) {
						banner.style.display = 'block';
					}

					isFormDirty = true;
				});
			};
		</script>
HTML;
	}

	/**
	 * Vykreslí inicializační skript stromu (při prvním načtení včetně samotného JS enginu).
	 *
	 * @param array<string, mixed> $cfg Konfigurace aktuálního stromu
	 */
	public static function render_script(array $cfg): string {               // Vykreslení inicializace stromu
		$engine_html = self::render_engine_once();                           // Jednorázové vložení JS enginu
		$json_cfg = json_encode($cfg);                                       // JSON konfigurace stromu

		return $engine_html . "\n\t\t<script>if (window.bcmInitTreeMaster) { window.bcmInitTreeMaster({$json_cfg}); }</script>\n"; // Zavolání inicializace
	}
}