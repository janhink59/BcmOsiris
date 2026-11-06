<?php
/**
 * =============================================================================
 * Verze: 2026-11-06 00:35
 * Soubor: svg_icon_editor.php
 * Třída: svg_icon_editor
 * Účel: Komponenta pro vykreslení náhledové karty, klientskou validaci přes
 *       DOMParser (image/svg+xml), modální editaci na dvojklik / tlačítko
 *       a serverovou sanitizaci vektorových ikon ve sloupci svg_icon.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Registrována v meta_object (object_type = 'P', builtin_code = 'svg_icon_editor').
 * - Volána z entity_manager_ui.php (render_editor, render_readonly) a z
 *   entity_manager_write.php (validate_svg) při ukládání záznamu.
 * - Modální kontejner #bcm-svg-modal-overlay v document.body je řízen přes
 *   globální singleton window.bcmSvgState (neduplikuje se při AJAX loadDetailPanel).
 *
 * Změny:
 * 2026-11-06 00:35 - Do render_editor() doplněn volitelný 4. parametr $is_readonly = false
 *                    (při true deleguje na render_readonly), opraven překlep 'audio'
 *                    ve validate_svg() a odstraněny znaky svislítka a přímé https:// URL
 *                    dle Anti-LaTeX pravidla.
 * =============================================================================
 */

declare(strict_types=1);

class svg_icon_editor {

	private static bool $assets_rendered = false; // Příznak jednorázového vložení CSS/JS do stránky
	private static int $editor_counter = 0; // Počitadlo instancí SVG editoru na stránce

	/**
	 * Pomocná metoda pro překlad textů komponenty svg_icon_editor přes phrase_manager.
	 */
	private static function phrase(string $builtin_code, string $default_caption, array $vars = []): string { // Překlad fráze
		if (function_exists('translate_phrase')) { // Pokud je dostupný globální helper z new_functions.php
			return translate_phrase($builtin_code, $default_caption, $vars, 'svg_icon_editor'); // Překlad přes helper
		}
		global $phrase_manager; // Globální instance správce frází
		if (! isset($phrase_manager) OR ! ($phrase_manager instanceof phrase_manager)) { // Kontrola existence správce
			$phrase_manager = new phrase_manager('svg_icon_editor'); // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] = $phrase_manager; // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, $vars, $default_caption, 'svg_icon_editor'); // Vrácení přeložené fráze
	}

	/**
	 * Serverová validace a bezpečnostní sanitizace SVG kódu pomocí DOMDocument.
	 * Odstraní nebezpečné elementy (<script>, <foreignObject>, <iframe>) a události on*.
	 * Při syntaktické chybě XML nastaví chybovou zprávu do $error_msg a vrátí prázdný řetězec.
	 */
	public static function validate_svg(string $raw_svg, ?string &$error_msg = null): string { // Serverová validace SVG
		$error_msg = null; // Vynulování chybové zprávy
		$trimmed = trim($raw_svg); // Oříznutí bílých znaků
		if ($trimmed === '') { // Prázdná ikona je platný stav
			return '';
		}

		if (! class_exists('DOMDocument')) { // Pojistka pokud by chyběla extenze dom
			if (! str_starts_with(strtolower($trimmed), '<svg') OR ! str_ends_with(strtolower($trimmed), '</svg>')) { // Základní kontrola
				$error_msg = self::phrase('err_svg_not_root', 'Kód ikony musí začínat značkou <svg> a končit </svg>.'); // Chyba
				return '';
			}
			return $trimmed; // Vrácení oříznutého řetězce
		}

		$prev_use_errors = libxml_use_internal_errors(true); // Zapnutí interního zachytávání XML chyb
		libxml_clear_errors(); // Vyčištění fronty XML chyb

		$dom = new DOMDocument(); // Inicializace XML DOM parseru
		$xml_flags = LIBXML_NONET + LIBXML_NOERROR + LIBXML_NOWARNING; // Bezpečné příznaky bez svislítka (Anti-LaTeX)
		$loaded = $dom->loadXML($trimmed, $xml_flags); // Načtení a rozparsování XML struktury
		$xml_err = libxml_get_last_error(); // Zjištění případné syntaktické chyby XML
		libxml_clear_errors(); // Vyčištění chyb
		libxml_use_internal_errors($prev_use_errors); // Obnovení původního režimu libxml

		if (! $loaded OR $dom->documentElement === null) { // Pokud XML syntaxe není platná
			$detail = ($xml_err !== false) ? trim($xml_err->message) : 'Neplatná XML struktura'; // Detail chyby z parseru
			$error_msg = self::phrase('err_svg_xml_syntax', 'Chyba syntaxe SVG ikony: {' . chr(36) . 'detail}', ['detail' => $detail]); // Hláška
			return '';
		}

		$root = $dom->documentElement; // Kořenový element dokumentu
		if (strtolower($root->localName ?? $root->nodeName) !== 'svg') { // Kořenovým elementem musí být <svg>
			$error_msg = self::phrase('err_svg_not_root', 'Kořenovým elementem ikony musí být značka <svg>.'); // Chybová hláška
			return '';
		}

		// Odstranění nebezpečných elementů (XSS ochrana)
		$forbidden_tags = ['script', 'foreignobject', 'iframe', 'object', 'embed', 'audio', 'video']; // Zakázané značky
		$all_elements = $dom->getElementsByTagName('*'); // Všechny elementy v dokumentu
		$nodes_to_remove = []; // Seznam uzlů k odstranění
		foreach ($all_elements as $el) { // Průchod všemi elementy
			$tag_low = strtolower($el->localName ?? $el->nodeName); // Název značky malými písmeny
			if (in_array($tag_low, $forbidden_tags, true)) { // Pokud jde o zakázanou značku
				$nodes_to_remove[] = $el; // Zařazení uzlu ke smazání
				continue;
			}
			if ($el->hasAttributes()) { // Kontrola atributů elementu
				$attrs_to_remove = []; // Seznam nebezpečných atributů
				foreach ($el->attributes as $attr) { // Průchod atributy elementu
					$a_name = strtolower($attr->nodeName); // Název atributu malými písmeny
					$a_val = strtolower(trim($attr->nodeValue ?? '')); // Hodnota atributu malými písmeny
					if (str_starts_with($a_name, 'on') OR str_starts_with($a_val, 'javascript:') OR str_starts_with($a_val, 'data:text/html')) { // XSS
						$attrs_to_remove[] = $attr->nodeName; // Zařazení atributu ke smazání
					}
				}
				foreach ($attrs_to_remove as $rem_a) { // Odstranění nebezpečných atributů
					$el->removeAttribute($rem_a); // Smazání atributu z elementu
				}
			}
		}

		foreach ($nodes_to_remove as $rem_node) { // Fyzické odstranění zakázaných elementů
			if ($rem_node->parentNode !== null) { // Pokud má uzel rodiče
				$rem_node->parentNode->removeChild($rem_node); // Odpojení uzlu z DOMu
			}
		}

		if (! $root->hasAttribute('xmlns')) { // Doplnění standardního jmenného prostoru SVG
			$root->setAttribute('xmlns', 'http://www.w3.org/2000/svg'); // Nastavení atributu xmlns
		}
		if (! $root->hasAttribute('viewBox') AND ! $root->hasAttribute('viewbox')) { // Pojistka atributu viewBox
			$w = (int) $root->getAttribute('width') ?: 24; // Šířka z atributu nebo výchozích 24
			$h = (int) $root->getAttribute('height') ?: 24; // Výška z atributu nebo výchozích 24
			$root->setAttribute('viewBox', "0 0 {$w} {$h}"); // Automatické doplnění viewBoxu
		}

		$clean_xml = $dom->saveXML($root); // Serializace samotného kořenového prvku <svg>
		return is_string($clean_xml) ? trim($clean_xml) : ''; // Vrácení čistého jednořádkového SVG kódu
	}

	/**
	 * Vykreslí kompaktní náhled SVG ikony v režimu pouze pro čtení ($is_readonly).
	 */
	public static function render_readonly(string $value): string { // Vykreslení náhledu v readonly režimu
		$assets_html = self::render_assets_once(); // Zajištění CSS pravidel pro SVG náhled
		$trimmed = trim($value); // Očištěný SVG řetězec
		$safe_val = htmlspecialchars($trimmed); // Ošetřená hodnota pro skrytý input
		if ($trimmed !== '' AND str_starts_with(strtolower($trimmed), '<svg')) { // Pokud obsahuje platnou SVG značku
			return $assets_html
				. "<input type=\"hidden\" name=\"svg_icon\" value=\"{$safe_val}\">"
				. "<div class=\"bcm-svg-card\">"
				. "<span class=\"bcm-svg-preview-box\" style=\"cursor: default; border-style: solid;\">{$trimmed}</span>"
				. "</div>"; // Neredigovatelný náhled ikony se shodným CSS
		}
		$lbl_none = htmlspecialchars(self::phrase('lbl_no_svg_icon', 'Ikona není nastavena')); // Popisek prázdné ikony
		return $assets_html
			. "<input type=\"hidden\" name=\"svg_icon\" value=\"\">"
			. "<div style=\"padding: 6px 10px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 4px; font-size: 12px; color: #94a3b8; font-style: italic;\">{$lbl_none}</div>"; // Prázdný stav
	}

	/**
	 * Jednorázově vloží do stránky CSS styly a JavaScript obsluhu modálního editoru SVG ikon.
	 */
	private static function render_assets_once(): string {
		if (self::$assets_rendered) { // Pokud již byly skripty v tomto requestu vloženy
			return '';
		}
		self::$assets_rendered = true; // Označení, že skripty jsou již vypsány

		$lbl_title    = addslashes(self::phrase('lbl_modal_title', 'Editor vektorové ikony (SVG):')); // Titulek modálu
		$lbl_code     = addslashes(self::phrase('lbl_svg_code_input', 'Zdrojový kód SVG ikony (vložte <svg ...>...</svg>):')); // Popisek pole
		$lbl_sources  = addslashes(self::phrase('lbl_svg_sources', 'Získat SVG kód ikony:')); // Popisek lišty s odkazy
		$tip_source   = addslashes(self::phrase('tip_svg_ext_source', 'Otevře katalog ikon v nové záložce (zkopírujte SVG kód ikony a vložte jej sem)')); // Tooltip odkazu
		$lbl_preview  = addslashes(self::phrase('lbl_live_preview', 'Živý náhled a kontrola syntaxe:')); // Nadpis náhledu
		$btn_validate = addslashes(self::phrase('btn_validate_svg', 'Zkontrolovat syntaxi a vyčistit')); // Tlačítko kontroly
		$btn_apply    = addslashes(self::phrase('btn_apply_svg', 'Použít v detailu')); // Tlačítko potvrzení
		$btn_cancel   = addslashes(self::phrase('btn_cancel_svg', 'Zrušit')); // Tlačítko zrušení
		$msg_hint     = addslashes(self::phrase('msg_modal_hint', 'Tip: Ikony s fill="currentColor" nebo bez atributu fill automaticky přebírají barvu textu v menu a tlačítkách. Vlastní barvy (např. fill="#...") zůstávají všude zachovány.')); // Nápověda
		$msg_ok       = addslashes(self::phrase('msg_syntax_ok', '✓ Syntaxe SVG je platná.')); // Zpráva o platné syntaxi
		$msg_empty    = addslashes(self::phrase('msg_svg_empty_ok', 'Ikona je prázdná (po potvrzení bude odstraněna).')); // Prázdná ikona
		$err_xml      = addslashes(self::phrase('err_js_xml_invalid', 'Neplatná XML syntaxe: ')); // Prefix chyby XML
		$err_root     = addslashes(self::phrase('err_js_not_svg_root', 'Kód musí obsahovat kořenový element <svg>...</svg>.')); // Chyba kořene
		$txt_no_icon  = addslashes(self::phrase('lbl_no_svg_icon', 'Ikona není nastavena (dvojklikem upravíte)')); // Placeholder

		$url_boot   = 'https://' . 'icons.getbootstrap.com/'; // Rozdělená URL Bootstrap Icons proti Markdown auto-linkování
		$url_remix  = 'https://' . 'remixicon.com/'; // Rozdělená URL Remix Icon
		$url_tabler = 'https://' . 'tabler.io/icons'; // Rozdělená URL Tabler Icons

		return '<style>
	.bcm-svg-card { display: inline-flex; align-items: center; gap: 10px; padding: 5px 10px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; min-height: 34px; }
	.bcm-svg-preview-box { display: inline-flex; align-items: center; justify-content: center; min-width: 28px; min-height: 28px; padding: 2px 6px; background-color: #ffffff; border: 1px dashed #cbd5e1; border-radius: 3px; cursor: pointer; color: #004488; }
	.bcm-svg-preview-box:hover { border-color: #2563eb; background-color: #eff6ff; }
	.bcm-svg-preview-box svg { width: 24px; height: 24px; display: block; flex-shrink: 0; }
	.bcm-svg-preview-box svg:not([fill]) { fill: currentColor; }
	.bcm-svg-modal-overlay { position: fixed; inset: 0; background-color: rgba(15, 23, 42, 0.55); z-index: 99992; display: none; align-items: center; justify-content: center; padding: 20px; box-sizing: border-box; }
	.bcm-svg-modal-overlay.active { display: flex; }
	.bcm-svg-modal-dialog { background-color: #ffffff; width: min(760px, 94vw); border-radius: 6px; box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3); display: flex; flex-direction: column; overflow: hidden; border: 1px solid #94a3b8; }
	.bcm-svg-modal-header { display: flex; justify-content: space-between; align-items: center; padding: 12px 16px; background-color: #f1f5f9; border-bottom: 1px solid #cbd5e1; }
	.bcm-svg-modal-body { padding: 16px; display: flex; flex-direction: column; gap: 12px; }
	.bcm-svg-label-row { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px; }
	.bcm-svg-ext-links { display: inline-flex; align-items: center; gap: 6px; font-size: 11px; color: #475569; flex-wrap: wrap; }
	.bcm-svg-ext-link { display: inline-flex; align-items: center; gap: 3px; padding: 2px 8px; background-color: #eff6ff; color: #1d4ed8; border: 1px solid #bfdbfe; border-radius: 3px; text-decoration: none; font-weight: bold; }
	.bcm-svg-ext-link:hover { background-color: #dbeafe; border-color: #93c5fd; color: #1e40af; }
	.bcm-svg-modal-ta { width: 100%; height: 150px; font-family: monospace; font-size: 12px; padding: 8px; border: 1px solid #cbd5e1; border-radius: 4px; box-sizing: border-box; resize: vertical; }
	.bcm-svg-preview-strip { display: flex; align-items: center; gap: 20px; padding: 12px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 4px; flex-wrap: wrap; }
	.bcm-svg-sample { display: inline-flex; align-items: center; gap: 8px; padding: 6px 12px; border-radius: 4px; font-size: 12px; font-weight: bold; }
	.bcm-svg-sample svg { width: 100%; height: 100%; display: block; flex-shrink: 0; }
	.bcm-svg-sample svg:not([fill]) { fill: currentColor; }
	.bcm-svg-sample-light { background-color: #ffffff; color: #004488; border: 1px solid #cbd5e1; }
	.bcm-svg-sample-dark { background-color: #004488; color: #ffffff; }
	.bcm-svg-status-ok { color: #15803d; font-size: 12px; font-weight: bold; }
	.bcm-svg-status-err { color: #b91c1c; font-size: 12px; font-weight: bold; background-color: #fef2f2; padding: 6px 10px; border-left: 3px solid #b91c1c; }
</style>
<script>
	(function() {
		if (!window.bcmSvgState) {
			window.bcmSvgState = {
				activeCfg: null,
				lastValidSvg: ""
			};
		}

		function parseAndCleanSvgClient(rawText) {
			const trimmed = (rawText ? rawText : "").trim();
			if (trimmed === "") {
				return { valid: true, empty: true, svg: "", message: "' . $msg_empty . '" };
			}
			const parser = new DOMParser();
			const doc = parser.parseFromString(trimmed, "image/svg+xml");
			const pErr = doc.querySelector("parsererror");
			if (pErr) {
				return { valid: false, empty: false, svg: "", message: "' . $err_xml . '" + pErr.textContent.replace(/\\s+/g, " ").trim() };
			}
			const root = doc.documentElement;
			if (!root ? true : root.nodeName.toLowerCase() !== "svg") {
				return { valid: false, empty: false, svg: "", message: "' . $err_root . '" };
			}

			["script", "foreignObject", "iframe", "object", "embed", "audio", "video"].forEach(function(tag) {
				root.querySelectorAll(tag).forEach(function(el) { el.remove(); });
			});
			root.querySelectorAll("*").forEach(function(el) {
				Array.from(el.attributes).forEach(function(attr) {
					const an = attr.name.toLowerCase();
					const av = (attr.value ? attr.value : "").trim().toLowerCase();
					if (an.indexOf("on") === 0 ? true : av.indexOf("javascript:") === 0) {
						el.removeAttribute(attr.name);
					}
				});
			});

			if (!root.hasAttribute("xmlns")) {
				root.setAttribute("xmlns", "http://www.w3.org/2000/svg");
			}
			if (!root.hasAttribute("viewBox")) {
				const wAttr = root.getAttribute("width");
				const hAttr = root.getAttribute("height");
				const w = parseInt(wAttr ? wAttr : "24", 10);
				const h = parseInt(hAttr ? hAttr : "24", 10);
				root.setAttribute("viewBox", "0 0 " + (w ? w : 24) + " " + (h ? h : 24));
			}

			const serialized = new XMLSerializer().serializeToString(root);
			return { valid: true, empty: false, svg: serialized, message: "' . $msg_ok . '" };
		}

		function getOrCreateSvgModal() {
			let overlay = document.getElementById("bcm-svg-modal-overlay");
			if (overlay) return overlay;

			overlay = document.createElement("div");
			overlay.id = "bcm-svg-modal-overlay";
			overlay.className = "bcm-svg-modal-overlay";
			overlay.innerHTML = ""
				+ "<div class=\"bcm-svg-modal-dialog\" onclick=\"event.stopPropagation();\">"
				+ "	<div class=\"bcm-svg-modal-header\">"
				+ "		<h3 style=\"margin:0; font-size:15px; color:#004488;\" id=\"bcm-svg-modal-title\"></h3>"
				+ "		<button type=\"button\" class=\"bcm-rt-edit-btn\" id=\"bcm-svg-btn-validate\">' . $btn_validate . '</button>"
				+ "	</div>"
				+ "	<div class=\"bcm-svg-modal-body\">"
				+ "		<div class=\"bcm-svg-label-row\">"
				+ "			<label for=\"bcm-svg-modal-ta\" style=\"font-size:12px; font-weight:bold; color:#334155;\">' . $lbl_code . '</label>"
				+ "			<div class=\"bcm-svg-ext-links\">"
				+ "				<span>' . $lbl_sources . '</span>"
				+ "				<a href=\"' . $url_boot . '\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"bcm-svg-ext-link\" title=\"' . $tip_source . '\">Bootstrap Icons ↗</a>"
				+ "				<a href=\"' . $url_remix . '\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"bcm-svg-ext-link\" title=\"' . $tip_source . '\">Remix Icon ↗</a>"
				+ "				<a href=\"' . $url_tabler . '\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"bcm-svg-ext-link\" title=\"' . $tip_source . '\">Tabler Icons ↗</a>"
				+ "			</div>"
				+ "		</div>"
				+ "		<textarea id=\"bcm-svg-modal-ta\" class=\"bcm-svg-modal-ta\" placeholder=\"<svg viewBox=&quot;0 0 24 24&quot; fill=&quot;currentColor&quot;>...</svg>\"></textarea>"
				+ "		<div style=\"font-size:12px; font-weight:bold; color:#334155;\">' . $lbl_preview . '</div>"
				+ "		<div id=\"bcm-svg-modal-status\" class=\"bcm-svg-status-ok\"></div>"
				+ "		<div class=\"bcm-svg-preview-strip\" id=\"bcm-svg-modal-samples\"></div>"
				+ "		<div style=\"font-size:11px; color:#64748b;\">' . $msg_hint . '</div>"
				+ "	</div>"
				+ "	<div class=\"bcm-rt-modal-footer\">"
				+ "		<div></div>"
				+ "		<div class=\"bcm-rt-modal-actions\">"
				+ "			<button type=\"button\" id=\"bcm-svg-btn-cancel\" class=\"btn btn-secondary\" style=\"padding:8px 14px;\">' . $btn_cancel . '</button>"
				+ "			<button type=\"button\" id=\"bcm-svg-btn-apply\" class=\"btn btn-success\" style=\"padding:8px 16px;\">' . $btn_apply . '</button>"
				+ "		</div>"
				+ "	</div>"
				+ "</div>";

			document.body.appendChild(overlay);

			const taEl = document.getElementById("bcm-svg-modal-ta");
			const valBtn = document.getElementById("bcm-svg-btn-validate");
			const cancelBtn = document.getElementById("bcm-svg-btn-cancel");
			const applyBtn = document.getElementById("bcm-svg-btn-apply");

			function refreshModalPreview(formatTextarea) {
				const res = parseAndCleanSvgClient(taEl.value);
				const statusEl = document.getElementById("bcm-svg-modal-status");
				const samplesEl = document.getElementById("bcm-svg-modal-samples");
				applyBtn.disabled = !res.valid;

				if (!res.valid) {
					statusEl.className = "bcm-svg-status-err";
					statusEl.textContent = res.message;
					samplesEl.innerHTML = "";
					return res;
				}

				statusEl.className = "bcm-svg-status-ok";
				statusEl.textContent = res.message;
				window.bcmSvgState.lastValidSvg = res.svg;

				if (formatTextarea && !res.empty) {
					taEl.value = res.svg;
				}

				if (res.empty) {
					samplesEl.innerHTML = "<span style=\"color:#94a3b8; font-style:italic; font-size:12px;\">' . $txt_no_icon . '</span>";
				} else {
					samplesEl.innerHTML = ""
						+ "<div class=\"bcm-svg-sample bcm-svg-sample-light\"><span style=\"display:inline-flex; width:16px; height:16px;\">" + res.svg + "</span><span>16px</span></div>"
						+ "<div class=\"bcm-svg-sample bcm-svg-sample-light\"><span style=\"display:inline-flex; width:24px; height:24px;\">" + res.svg + "</span><span>24px</span></div>"
						+ "<div class=\"bcm-svg-sample bcm-svg-sample-dark\"><span style=\"display:inline-flex; width:24px; height:24px;\">" + res.svg + "</span><span>Menu / Tlačítko</span></div>"
						+ "<div class=\"bcm-svg-sample bcm-svg-sample-light\"><span style=\"display:inline-flex; width:48px; height:48px;\">" + res.svg + "</span><span>48px</span></div>";
				}
				return res;
			}

			taEl.addEventListener("input", function() { refreshModalPreview(false); });
			valBtn.addEventListener("click", function() { refreshModalPreview(true); });
			cancelBtn.addEventListener("click", function() { overlay.classList.remove("active"); });

			applyBtn.addEventListener("click", function() {
				const res = refreshModalPreview(true);
				if (!res.valid ? true : !window.bcmSvgState.activeCfg) return;
				const cfg = window.bcmSvgState.activeCfg;
				const inpEl = document.getElementById(cfg.inputId);
				const prevEl = document.getElementById(cfg.previewId);
				const clrBtn = document.getElementById(cfg.clearBtnId);

				if (inpEl) inpEl.value = res.svg;
				if (prevEl) {
					if (res.empty) {
						prevEl.innerHTML = "<span style=\"color:#94a3b8; font-style:italic; font-size:12px;\">' . $txt_no_icon . '</span>";
					} else {
						prevEl.innerHTML = res.svg;
					}
				}
				if (clrBtn) {
					clrBtn.style.display = res.empty ? "none" : "inline-flex";
				}
				if (typeof isFormDirty !== "undefined") {
					isFormDirty = true;
				}
				overlay.classList.remove("active");
			});

			overlay._refreshPreview = refreshModalPreview;
			return overlay;
		}

		window.bcmOpenSvgIconModal = function(cfg) {
			const overlay = getOrCreateSvgModal();
			const inpEl = document.getElementById(cfg.inputId);
			const titleEl = document.getElementById("bcm-svg-modal-title");
			const taEl = document.getElementById("bcm-svg-modal-ta");
			if (!inpEl ? true : !taEl) return;

			window.bcmSvgState.activeCfg = cfg;
			if (titleEl) {
				const lbl = cfg.fieldLabel ? cfg.fieldLabel : (cfg.columnName ? cfg.columnName : "svg_icon");
				titleEl.textContent = "' . $lbl_title . ' " + lbl;
			}
			taEl.value = inpEl.value ? inpEl.value : "";
			overlay.classList.add("active");
			if (typeof overlay._refreshPreview === "function") {
				overlay._refreshPreview(false);
			}
			setTimeout(function() { taEl.focus(); }, 40);
		};

		window.bcmClearSvgIcon = function(cfg) {
			const inpEl = document.getElementById(cfg.inputId);
			const prevEl = document.getElementById(cfg.previewId);
			const clrBtn = document.getElementById(cfg.clearBtnId);
			if (inpEl) inpEl.value = "";
			if (prevEl) {
				prevEl.innerHTML = "<span style=\"color:#94a3b8; font-style:italic; font-size:12px;\">' . $txt_no_icon . '</span>";
			}
			if (clrBtn) clrBtn.style.display = "none";
			if (typeof isFormDirty !== "undefined") {
				isFormDirty = true;
			}
		};
	})();
</script>' . "\n"; // Konec CSS/JS bloku modálního SVG editoru
	}

	/**
	 * Vykreslí náhledovou kartu SVG ikony s podporou dvojkliku a tlačítka pro otevření modálního editoru.
	 * Pokud je předán parametr $is_readonly = true, vykreslí uzamčený náhled přes render_readonly().
	 */
	public static function render_editor(string $column_name, string $value, array $meta = [], bool $is_readonly = false): string { // Vykreslení editoru ikony
		if ($is_readonly) { // V režimu pouze pro čtení vykreslíme neredigovatelnou kartu
			return self::render_readonly($value); // Delegování na readonly náhled
		}

		self::$editor_counter++; // Inkrementace unikátního počitadla prvku
		$idx = self::$editor_counter; // Pořadové číslo prvku na stránce

		$assets_html = self::render_assets_once(); // Jednorázové načtení JS/CSS modálu
		$trimmed = trim($value); // Očištěný SVG řetězec
		$safe_name = htmlspecialchars($column_name); // Ošetřený název sloupce
		$safe_val = htmlspecialchars($trimmed); // Ošetřená hodnota pro skrytý input
		$field_lbl = (string) ($meta['label'] ?: $meta['caption'] ?: $column_name); // Lidsky čitelný popisek pole

		$inp_id = "bcm_svg_inp_{$idx}"; // ID skrytého pole formuláře
		$prev_id = "bcm_svg_prev_{$idx}"; // ID kontejneru živého náhledu
		$clr_id = "bcm_svg_clr_{$idx}"; // ID tlačítka pro vymazání ikony

		$btn_edit_lbl = htmlspecialchars(self::phrase('btn_edit_svg', 'Upravit ikonu')); // Popisek tlačítka úpravy
		$btn_clr_lbl  = htmlspecialchars(self::phrase('btn_clear_svg', 'Smazat')); // Popisek tlačítka smazání
		$tip_dblclick = htmlspecialchars(self::phrase('tip_open_svg_editor', 'Dvojklikem nebo tlačítkem otevřete editor vektorové ikony SVG')); // Tooltip
		$txt_no_icon  = htmlspecialchars(self::phrase('lbl_no_svg_icon', 'Ikona není nastavena (dvojklikem upravíte)')); // Text bez ikony

		$has_icon = ($trimmed !== '' AND str_starts_with(strtolower($trimmed), '<svg')); // Zda je ikona vyplněna
		$preview_inner = $has_icon
			? $trimmed
			: "<span style=\"color:#94a3b8; font-style:italic; font-size:12px;\">{$txt_no_icon}</span>"; // Obsah náhledu
		$clr_disp = $has_icon ? 'inline-flex' : 'none'; // Viditelnost tlačítka Smazat

		$js_cfg = json_encode([ // Konfigurace předávaná do JS handleru
			'inputId'    => $inp_id,
			'previewId'  => $prev_id,
			'clearBtnId' => $clr_id,
			'columnName' => $column_name,
			'fieldLabel' => $field_lbl
		]); // Konec JSON konfigurace
		$safe_cfg = htmlspecialchars((string) $js_cfg, ENT_QUOTES, 'UTF-8'); // Ošetřený JSON pro onclick/ondblclick

		return $assets_html
			. "<div class=\"bcm-svg-card\">\n"
			. "\t<input type=\"hidden\" id=\"{$inp_id}\" name=\"{$safe_name}\" value=\"{$safe_val}\">\n"
			. "\t<div id=\"{$prev_id}\" class=\"bcm-svg-preview-box\" title=\"{$tip_dblclick}\" ondblclick=\"window.bcmOpenSvgIconModal({$safe_cfg});\">{$preview_inner}</div>\n"
			. "\t<button type=\"button\" class=\"bcm-rt-edit-btn\" title=\"{$tip_dblclick}\" onclick=\"window.bcmOpenSvgIconModal({$safe_cfg});\">{$btn_edit_lbl}</button>\n"
			. "\t<button type=\"button\" id=\"{$clr_id}\" class=\"bcm-rt-edit-btn\" style=\"display:{$clr_disp}; color:#b91c1c; border-color:#fca5a5; background-color:#fef2f2;\" onclick=\"window.bcmClearSvgIcon({$safe_cfg});\">{$btn_clr_lbl}</button>\n"
			. "</div>"; // Výsledný HTML kód karty SVG ikony
	}

	/**
	 * Zpětně kompatibilní alias pro render_editor().
	 */
	public static function render_input(string $column_name, string $value, array $meta = [], bool $is_readonly = false): string { // Alias pro render_editor
		return self::render_editor($column_name, $value, $meta, $is_readonly); // Delegování na render_editor
	}
}