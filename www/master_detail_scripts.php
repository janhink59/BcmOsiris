<?php
/**
 * =============================================================================
 * Verze: 2026-11-16 16:15
 * Soubor: master_detail_scripts.php
 * Třída: master_detail_scripts
 *
 * 1. Role souboru v celém systému:
 *    Zapouzdřuje stabilní klientské CSS styly a JavaScriptovou obsluhu
 *    dvoupanelového layoutu Master-Detail (asynchronní načítání detailu
 *    loadDetailPanel, obnova levého panelu refreshMasterPanel, klientský filtr
 *    v sessionStorage, převod názvu na snake_case window.bcmToSnakeCase
 *    a přenos filtru do CSV exportu openSimpleClassCsv).
 *    Vyčleněno z abstract_page_master_detail.php pro udržení velikosti souborů
 *    hluboko pod limitem 50 KB.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Načítána automaticky přes spl_autoload_register v config.php.
 *    - Volána z metody abstract_page_master_detail::render_body()
 *      (abstract_page_master_detail.php).
 *    - Spolupracuje s klientskými funkcemi stromové šablony v tree_scripts.php
 *      (window.applyTreeMasterFilter, window.applyMenuTreeVisibility).
 *
 * 3. Očekávaná kontextová data:
 *    - Přijímá asociativní pole lokalizovaných textů z volající stránky;
 *      nevyžaduje přímý přístup k $_SESSION ani databázi.
 * =============================================================================
 */

declare(strict_types=1);

class master_detail_scripts {

	/**
	 * Vrátí CSS styly pro dvoupanelový Master-Detail layout.
	 */
	public static function render_styles(): string {
		return <<<HTML
		<style>
			.page-panel { max-width: 95% !important; padding: 0 !important; display: flex; flex-direction: row; height: calc(100vh - 120px); overflow: hidden; }
			.md-master { flex: 0 0 45%; min-width: 400px; border-right: 1px solid #ddd; background-color: #fafafa; padding: 20px; display: flex; flex-direction: column; overflow: hidden; }
			.md-detail { flex: 1; padding: 20px 30px; background-color: #ffffff; display: flex; flex-direction: column; overflow: hidden; transition: opacity 0.12s ease; }
			.md-detail.md-loading { opacity: 0.55; pointer-events: none; }
			.md-master-header, .md-sticky-header-master { flex: 0 0 auto; border-bottom: 2px solid #eee; margin-bottom: 10px; padding-bottom: 10px; }
			.md-master-content { flex: 1 1 auto; overflow-y: auto; padding-right: 5px; }
			.md-detail-header, .md-sticky-header-detail { flex: 0 0 auto; border-bottom: 2px solid #004488; display: flex; justify-content: space-between; align-items: center; padding-bottom: 10px; margin-bottom: 20px; gap: 10px; flex-wrap: wrap; }
			.md-detail-content { flex: 1 1 auto; overflow-y: auto; padding-right: 10px; }
			.md-master-header h2, .md-sticky-header-master h2, .md-detail-header h2, .md-sticky-header-detail h2 { color: #004488; }
			.md-table { width: 100%; border-collapse: collapse; margin-top: 0; }
			.md-table th { position: sticky; top: 0; background-color: #e9f2fa; padding: 6px 4px; border: 1px solid #ddd; text-align: left; z-index: 5; box-shadow: 0 1px 0 #ddd, 0 -1px 0 #ddd; }
			.md-table td { padding: 4px; border: 1px solid #ddd; }
			.md-table tr { background-color: #fff; color: #333; }
			.md-table tr:hover { background-color: #f1f1f1; }
			.md-row-active { background-color: #e6f7ff !important; color: #333 !important; }
			.md-row-inactive { background-color: #f9f9f9 !important; color: #999 !important; }
			.md-row-removed td { color: #991b1b !important; text-decoration: line-through; background-color: #fef2f2 !important; }
			.md-row-Active-removed td { color: #991b1b !important; text-decoration: line-through; background-color: #fde8e8 !important; }
			.ssc-badge { display: inline-block; font-size: 10px; font-weight: bold; padding: 1px 5px; border-radius: 3px; margin-left: 6px; vertical-align: middle; text-decoration: none !important; }
			.ssc-badge-d { background-color: #fef3c7; color: #92400e; border: 1px solid #f59e0b; }
			.ssc-badge-f { background-color: #dbeafe; color: #1e40af; border: 1px solid #3b82f6; }
			.ssc-badge-r { background-color: #fee2e2; color: #991b1b; border: 1px solid #ef4444; }
			.ssc-badge-rem { background-color: #991b1b; color: #ffffff; border: 1px solid #7f1d1d; }
		</style>
HTML;
	}

	/**
	 * Vrátí klientský JavaScript pro obsluhu Master-Detail obrazovky.
	 *
	 * @param array<string, string> $labels Lokalizované texty pro JS hlášení
	 */
	public static function render_script(array $labels): string {            // Generování JS skriptu pro Master-Detail
		$err_ajax_net    = addslashes((string) ($labels['err_ajax_net'] ?? 'Chyba sítě při AJAX volání'));          // Chyba sítě
		$err_ajax_ref    = addslashes((string) ($labels['err_ajax_ref'] ?? 'Chyba při obnově master panelu:'));     // Chyba obnovy
		$err_ajax_det    = addslashes((string) ($labels['err_ajax_det'] ?? 'Chyba při načítání detailu:'));         // Chyba detailu
		$unsaved_confirm = addslashes((string) ($labels['unsaved_confirm'] ?? 'Máte neuložené změny. Opravdu chcete stránku opustit?')); // Varování
		$lbl_quick_flt   = addslashes((string) ($labels['lbl_quick_flt'] ?? 'Rychlý filtr'));                       // Popisek rychlého filtru

		return <<<HTML
		<script>
			window.isTreeDomDirty = false;

			// Sestavení unikátního klíče v sessionStorage pro uchování filtru levého panelu
			function getMasterFilterStorageKey() {
				const u = new URL(window.location.href);
				const page = u.searchParams.get('page') ? u.searchParams.get('page') : 'default';
				const pCls = u.searchParams.get('parent_class') ? u.searchParams.get('parent_class') : '';
				const pObj = u.searchParams.get('parent_object') ? u.searchParams.get('parent_object') : '';
				const hier = u.searchParams.get('hierarchy') ? u.searchParams.get('hierarchy') : '';
				const scl  = u.searchParams.get('scale') ? u.searchParams.get('scale') : '';
				const fCls = u.searchParams.get('filter_class') ? u.searchParams.get('filter_class') : '';
				return 'bcm_mf_' + page + '_' + pCls + '_' + pObj + '_' + hier + '_' + scl + '_' + fCls;
			}

			// Aplikuje text filtru #master-filter na řádky v #master-list (na stromových stránkách zachová nadřízené uzly)
			function applyMasterFilter(term) {
				const list = document.getElementById('master-list');
				if (!list) return;
				const cleanTerm = (term ? term : '').trim().toLowerCase();
				if (typeof window.applyTreeMasterFilter === 'function') {
					window.applyTreeMasterFilter(cleanTerm);
					return;
				}
				if (cleanTerm === '' && typeof window.applyMenuTreeVisibility === 'function') {
					window.applyMenuTreeVisibility();
					return;
				}
				list.querySelectorAll('tr').forEach(function(row) {
					const matches = (cleanTerm === '' ? true : row.textContent.toLowerCase().includes(cleanTerm));
					row.style.display = matches ? '' : 'none';
				});
			}

			// Otevře stránku CSV exportu/importu (simple_class) s přenesením rychlého i rozšířeného filtru do parametru info
			window.openSimpleClassCsv = function(linkEl) {
				if (!linkEl) return true;
				const u = new URL(linkEl.href, window.location.href);
				const quickInp = document.getElementById('master-filter');
				const quickVal = (quickInp && quickInp.value) ? quickInp.value.trim() : '';
				if (quickVal !== '') {
					const existingInfo = u.searchParams.get('info') ? u.searchParams.get('info') : '';
					const quickLine = '{$lbl_quick_flt}: ' + quickVal; // Popisek rychlého filtru
					const lf = String.fromCharCode(10);
					u.searchParams.set('info', existingInfo !== '' ? (existingInfo + lf + quickLine) : quickLine);
					u.searchParams.set('quick_filter', quickVal);
				}
				window.location.href = u.toString();
				return false;
			};

			// Obnoví uložený filtr ze sessionStorage (např. po uložení záznamu a PRG redirectu)
			function restoreMasterFilterFromStorage() {
				const input = document.getElementById('master-filter');
				if (!input) return;
				try {
					const saved = sessionStorage.getItem(getMasterFilterStorageKey());
					if (saved !== null && saved !== '') {
						input.value = saved;
						applyMasterFilter(saved);
					}
				} catch (e) {}
			}

			// Pokud je levý panel dlouhý, automaticky odscrolluje na právě vybraný aktivní řádek
			function scrollToActiveRow() {
				const activeRow = document.getElementById("active-row");
				const scrollingContainer = document.querySelector(".md-master-content");
				
				if (activeRow && scrollingContainer && activeRow.style.display !== 'none') {
					const containerRect = scrollingContainer.getBoundingClientRect();
					const rowRect = activeRow.getBoundingClientRect();
					const isOut = (rowRect.top < containerRect.top ? true : rowRect.bottom > containerRect.bottom);
					if (isOut) {
						const offset = rowRect.top - containerRect.top;
						scrollingContainer.scrollTop += offset - (containerRect.height / 2) + (rowRect.height / 2);
					}
				}
			}

			// Přepnutí zobrazení zrušených záznamů (show_removed) v URL
			function toggleShowRemoved(checked) {
				const url = new URL(window.location.href);
				if (checked) {
					url.searchParams.set('show_removed', '1');
				} else {
					url.searchParams.delete('show_removed');
				}
				window.location.href = url.toString();
			}

			// Jednotný převod názvu/zkratky na platný snake_case identifikátor (builtin_code / link_code)
			window.bcmToSnakeCase = function(str) {
				const s = str ? String(str) : '';
				return s
					.normalize('NFD')
					.replace(/[\u0300-\u036f]/g, '')
					.toLowerCase()
					.replace(/[^a-z0-9]+/g, '_')
					.replace(/^_+/g, '')
					.replace(/_+$/g, '')
					.substring(0, 60);
			};

			// Centrální klientské filtrování #master-list a automatické odvozování builtin_code v detailu
			document.addEventListener('input', function(e) {
				if (e.target && e.target.id === 'master-filter') {
					const val = e.target.value;
					try {
						sessionStorage.setItem(getMasterFilterStorageKey(), val);
					} catch (err) {}
					applyMasterFilter(val);
					return;
				}

				const form = e.target ? e.target.closest('.md-detail form') : null;
				if (!form) return;
				const updInp = form.querySelector('input[name="update_guid"]');
				if (!updInp ? true : updInp.value !== 'NEW') return;

				const codeInp = form.querySelector('input[name="builtin_code"]:not([readonly])');
				if (!codeInp) return;

				if (e.target.name === 'builtin_code') {
					codeInp.dataset.manualEdit = (codeInp.value.trim() !== '') ? '1' : '0';
					return;
				}

				if (e.target.name === 'caption' ? true : e.target.name === 'shortname') {
					if (codeInp.dataset.manualEdit === '1') return;
					const shInp  = form.querySelector('input[name="shortname"]');
					const capInp = form.querySelector('input[name="caption"], textarea[name="caption"]');
					const rawSrc = (shInp && shInp.value.trim() !== '') ? shInp.value : (capInp ? capInp.value : '');
					codeInp.value = window.bcmToSnakeCase(rawSrc);
				}
			});

			// Normalizace ručně zadaného builtin_code / link_code na snake_case při opuštění pole
			document.addEventListener('change', function(e) {
				if (!e.target ? true : e.target.readOnly) return;
				if (e.target.name === 'builtin_code' ? true : e.target.name === 'link_code') {
					const form = e.target.closest('.md-detail form');
					if (form && e.target.value.trim() !== '') {
						e.target.value = window.bcmToSnakeCase(e.target.value);
					}
				}
			});

			// Aktualizace zvýraznění aktivního řádku v levém panelu podle cílové URL nebo kliknutého řádku
			function updateActiveMasterRow(targetUrlObj, clickedRow) {
				const list = document.getElementById('master-list');
				if (!list) return;
				const uGuid = targetUrlObj.searchParams.get('update_guid');
				const dGuid = targetUrlObj.searchParams.get('draft_uuid');
				const rawGuid = uGuid ? uGuid : (dGuid ? dGuid : '');
				const targetGuid = rawGuid.toLowerCase();

				list.querySelectorAll('tr').forEach(function(tr) {
					tr.classList.remove('md-row-active', 'md-row-Active-removed');
					if (tr.id === 'active-row') {
						tr.removeAttribute('id');
					}
				});

				let activeTr = clickedRow ? clickedRow : null;
				if (!activeTr && targetGuid !== '' && targetGuid !== 'new') {
					list.querySelectorAll('tr').forEach(function(tr) {
						const attrUuid = tr.getAttribute('data-uuid');
						const rowUuid = (attrUuid ? attrUuid : '').toLowerCase();
						if (rowUuid !== '' && rowUuid === targetGuid) {
							activeTr = tr;
						}
					});
				}

				if (activeTr) {
					activeTr.id = 'active-row';
					if (activeTr.classList.contains('md-row-removed')) {
						activeTr.classList.add('md-row-active', 'md-row-Active-removed');
					} else {
						activeTr.classList.add('md-row-active');
					}
				}
			}

			// Spustí vnořené <script> elementy uvnitř asynchronně načteného detailního panelu
			function executeDetailScripts(container) {
				if (!container) return;
				container.querySelectorAll('script').forEach(function(oldScript) {
					const newScript = document.createElement('script');
					Array.from(oldScript.attributes).forEach(function(attr) {
						newScript.setAttribute(attr.name, attr.value);
					});
					newScript.textContent = oldScript.textContent;
					oldScript.parentNode.replaceChild(newScript, oldScript);
				});
			}

			// Asynchronní načtení pouze pravého detailního panelu bez refreshe levého panelu
			window.loadDetailPanel = function(targetUrl, clickedRow, pushHistory) {
				if (typeof pushHistory === 'undefined') {
					pushHistory = true;
				}
				const cleanUrlObj = new URL(targetUrl, window.location.href);
				const hasDndParams = cleanUrlObj.searchParams.has('dnd_sort');

				if (typeof isFormDirty !== 'undefined' && isFormDirty) {
					if (!confirm('{$unsaved_confirm}')) { // Potvrzení opuštění neuložených změn
						return false;
					}
					isFormDirty = false;
				}

				if (window.isTreeDomDirty && !hasDndParams) {
					window.isTreeDomDirty = false;
					refreshMasterPanel();
				}

				const detailContainer = document.getElementById('md-detail-container');
				if (!detailContainer) {
					window.location.href = targetUrl;
					return false;
				}

				cleanUrlObj.searchParams.delete('ajax_panel');

				const fetchUrlObj = new URL(cleanUrlObj.toString());
				fetchUrlObj.searchParams.set('ajax_panel', 'detail');

				updateActiveMasterRow(cleanUrlObj, clickedRow ? clickedRow : null);
				detailContainer.classList.add('md-loading');

				fetch(fetchUrlObj.toString(), {
					headers: {
						'X-Requested-With': 'XMLHttpRequest'
					}
				})
				.then(function(response) {
					if (!response.ok) throw new Error("{$err_ajax_net}"); // Chyba sítě při načítání detailu
					return response.text();
				})
				.then(function(html) {
					detailContainer.innerHTML = html;
					detailContainer.classList.remove('md-loading');
					executeDetailScripts(detailContainer);
					if (typeof isFormDirty !== 'undefined' && !hasDndParams) {
						isFormDirty = false;
					}
					if (pushHistory) {
						const histUrlObj = new URL(cleanUrlObj.toString());
						histUrlObj.searchParams.delete('dnd_parent');
						histUrlObj.searchParams.delete('dnd_sort');
						window.history.pushState({ mdUrl: histUrlObj.toString() }, '', histUrlObj.toString());
					}
				})
				.catch(function(error) {
					detailContainer.classList.remove('md-loading');
					console.error('{$err_ajax_det}', error); // Výpis chyby načtení detailu do konzole
					window.location.href = cleanUrlObj.toString();
				});

				return false;
			};

			// Podpora tlačítek Zpět / Vpřed v prohlížeči při asynchronním přepínání záznamů
			window.addEventListener('popstate', function() {
				window.loadDetailPanel(window.location.href, null, false);
			});

			// Delegované zachycení tlačítek "+ Nový" v levém panelu a "Zahodit změny" v pravém panelu
			document.addEventListener('click', function(e) {
				const link = e.target.closest('a.btn');
				if (!link) return;
				const href = link.getAttribute('href');
				const hasTarget = Boolean(link.getAttribute('target'));
				if (!href ? true : (href === '#' ? true : hasTarget)) return;

				try {
					const targetUrl = new URL(href, window.location.href);
					const currUrl = new URL(window.location.href);
					if (targetUrl.pathname === currUrl.pathname && targetUrl.searchParams.get('page') === currUrl.searchParams.get('page')) {
						const inMaster = Boolean(link.closest('#md-master-container'));
						const inDetailDiscard = Boolean(link.closest('#md-detail-container') && link.classList.contains('btn-danger'));
						if (inMaster ? true : inDetailDiscard) {
							e.preventDefault();
							if (inDetailDiscard && window.isTreeDomDirty) {
								window.isTreeDomDirty = false;
								refreshMasterPanel();
							}
							window.loadDetailPanel(targetUrl.toString(), null, true);
						}
					}
				} catch (err) {}
			});

			// Asynchronní překreslení (refresh) levého panelu se zachováním filtru a skriptů
			function refreshMasterPanel() {
				const url = new URL(window.location.href);
				url.searchParams.set('ajax_panel', 'master');
				
				fetch(url.toString(), {
					headers: {
						'X-Requested-With': 'XMLHttpRequest'
					}
				})
				.then(function(response) {
					if (!response.ok) throw new Error("{$err_ajax_net}"); // Chyba sítě při obnově seznamu
					return response.text();
				})
				.then(function(html) {
					const masterPanel = document.getElementById("md-master-container");
					if (masterPanel) {
						masterPanel.innerHTML = html;
						executeDetailScripts(masterPanel);
						restoreMasterFilterFromStorage();
						scrollToActiveRow();
					}
				})
				.catch(function(error) {
					console.error('{$err_ajax_ref}', error); // Výpis chyby obnovy seznamu do konzole
				});
			}

			document.addEventListener("DOMContentLoaded", function() {
				restoreMasterFilterFromStorage();
				setTimeout(scrollToActiveRow, 50);
			});
		</script>
HTML;
	}
}