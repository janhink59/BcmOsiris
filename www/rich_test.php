<?php
/**
 * =============================================================================
 * Verze: 2026-10-26 13:50
 * Soubor: rich_text.php
 * Třída: rich_text
 * Účel: Centrální služba pro detekci formátu (Markdown vs. HTML), obousměrnou
 *       konverzi, bezpečnostní sanitizaci HTML a vykreslování interaktivního
 *       editoru (Toast UI Editor) i pouze-čtecích náhledů pro sloupce s příznakem
 *       meta_column.is_html = 1.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Automaticky načítána přes spl_autoload_register v config.php.
 * - Využívá Composer knihovny:
 *   1. league/commonmark (převod Markdown -> HTML včetně GitHub Flavored Markdown tabulek),
 *   2. league/html-to-markdown (převod HTML -> Markdown včetně tabulek),
 *   3. symfony/html-sanitizer (bezpečnostní sanitizace HTML proti XSS).
 * - Na klientské straně (Vanilla JS) využívá Toast UI Editor
 *   (js/toastui-editor-all.min.js a css/toastui-editor.min.css s CDN fallbackem).
 * - Volána z entity_manager::render_dynamic_input(), entity_manager_write::extract_post_data()
 *   a ze schvalovací obrazovky page_approval::render_detail().
 * - Využívá globální $phrase_manager pro plnou lokalizaci ovládacích prvků editoru.
 *
 * Změny:
 * 2026-10-26 13:50 - Vytvoření centrální třídy pro podporu Markdownu a HTML.
 * =============================================================================
 */

declare(strict_types=1);

use League\CommonMark\Environment\Environment;
use League\CommonMark\Extension\CommonMark\CommonMarkCoreExtension;
use League\CommonMark\Extension\GithubFlavoredMarkdownExtension;
use League\CommonMark\MarkdownConverter;
use League\HTMLToMarkdown\HtmlConverter;
use League\HTMLToMarkdown\Converter\TableConverter;
use Symfony\Component\HtmlSanitizer\HtmlSanitizer;
use Symfony\Component\HtmlSanitizer\HtmlSanitizerConfig;

class rich_text {

	private static bool $assets_rendered = false;                            // Příznak jednorázového vložení CSS/JS do stránky
	private static int $editor_counter = 0;                                  // Počitadlo instancí editoru na stránce

	/**
	 * Pomocná metoda pro překlad textů komponenty rich_text přes phrase_manager.
	 *
	 * @param string               $builtin_code    Kód fráze v meta_phrase
	 * @param string               $default_caption Výchozí český text
	 * @param array<string, mixed> $vars            Proměnné pro interpolaci
	 * @return string Přeložený text
	 */
	private static function phrase(string $builtin_code, string $default_caption, array$vars = []): string { // Překlad fráze
		global $phrase_manager;                                              // Globální instance správce frází
		if (!isset($phrase_manager) OR !($phrase_manager instanceof phrase_manager)) { // Kontrola existence správce
			$phrase_manager = new phrase_manager('rich_text');               // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] =$phrase_manager;                    // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, $vars,$default_caption, 'rich_text'); // Vrácení přeložené fráze
	}

	/**
	 * Rozpozná, zda je předaný text ve formátu 'markdown' nebo 'html'.
	 * Prázdný text nebo běžný text bez HTML struktury je vždy vyhodnocen jako 'markdown'
	 * (v souladu s preferencí uživatelů).
	 *
	 * @param string $text Vstupní text z databáze nebo formuláře
	 * @return string 'markdown' nebo 'html'
	 */
	public static function detect_format(string $text): string {             // Detekce formátu uloženého textu
		$trimmed = trim($text);                                              // Oříznutí bílých znaků okolo textu
		if ($trimmed === '') {                                               // Prázdná hodnota preferuje Markdown
			return 'markdown';                                               // Výchozí formát je Markdown
		}

		if (str_starts_with($trimmed, '<!--html-->')) {                      // Explicitní značka pro HTML formát
			return 'html';                                                   // Jednoznačně HTML
		}
		if (str_starts_with($trimmed, '<!--md-->')) {                        // Explicitní značka pro Markdown formát
			return 'markdown';                                               // Jednoznačně Markdown
		}

		// Pokud text začíná typickou Markdown syntaxí (nadpis #, citace >, seznam -/*, kód ```), jde o Markdown
		if (preg_match('/^(#+\s|>\s|[-*+]\s|\d+\.\s|```)/m', $trimmed)) {    // Detekce blokové Markdown syntaxe
			if (!preg_match('/<\/(p|div|table|ul|ol)>/i', $trimmed)) {       // Pokud současně neobsahuje uzavírací HTML bloky
				return 'markdown';                                           // Vyhodnoceno jako Markdown
			}
		}

		// Detekce typických blokových a formátovacích HTML značek (bez použití znaku pipe v kódu)
		$html_tags = [                                                       // Seznam sledovaných HTML značek
			'<p>', '<p ', '</p>', '<div>', '<div ', '</div>',
			'<table', '</table>', '<ul>', '<ul ', '</ul>', '<ol>', '<ol ', '</ol>', '<li>', '</li>',
			'<h1>', '<h2>', '<h3>', '<h4>', '<h5>', '<h6>', '</h1>', '</h2>', '</h3>',
			'<blockquote', '</blockquote>', '<pre>', '</pre>',
			'<strong>', '</strong>', '<em>', '</em>', '<b>', '</b>', '<i>', '</i>', '<u>', '</u>',
			'<a href=', '<span ', '</span>', '<br>', '<br/>', '<br />', '<hr>', '<hr/>', '<hr />'
		];                                                                   // Konec seznamu HTML značek

		$lower = strtolower($trimmed);                                       // Převod na malá písmena pro rychlé hledání
		foreach ($html_tags as$tag) {                                       // Průchod sledovanými HTML značkami
			if (str_contains($lower,$tag)) {                                // Nalezena HTML značka v textu
				return 'html';                                               // Text je ve formátu HTML
			}
		}

		return 'markdown';                                                   // Výchozí vyhodnocení jako Markdown
	}

	/**
	 * Očistí HTML řetězec od nebezpečných značek a atributů (XSS ochrana)
	 * pomocí knihovny symfony/html-sanitizer.
	 *
	 * @param string $raw_html Surový HTML řetězec
	 * @return string Bezpečný sanitizovaný HTML řetězec
	 */
	public static function sanitize_html(string $raw_html): string {         // Sanitizace HTML proti XSS$clean = preg_replace('/^<!--(html|md)-->\s*/', '', $raw_html) ?? $raw_html; // Odstranění případné interní značky
		if (trim($clean) === '') {                                           // Prázdný řetězec není třeba čistit
			return '';                                                       // Vrácení prázdného řetězce
		}

		if (class_exists(HtmlSanitizer::class) AND class_exists(HtmlSanitizerConfig::class)) { // Kontrola Symfony knihovny
			$config = (new HtmlSanitizerConfig())                            // Vytvoření konfigurace sanitizeru
				->allowSafeElements()                                        // Povolení všech bezpečných HTML5 elementů
				->allowRelativeLinks()                                       // Povolení relativních odkazů v href
				->allowRelativeMedias()                                      // Povolení relativních zdrojů obrázků
				->withMaxInputLength(500000);                                // Limit délky vstupního HTML (500 KB)
			$sanitizer = new HtmlSanitizer($config);                         // Inicializace Symfony sanitizeru
			return $sanitizer->sanitize($clean);                             // Vrácení bezpečného HTML
		}

		// Nouzový fallback, pokud by knihovna nebyla načtena
		$allowed = '<p><br><div><span><strong><b><em><i><u><s><del><ins><h1><h2><h3><h4><h5><h6><ul><ol><li><table><thead><tbody><tfoot><tr><th><td><blockquote><pre><code><a><hr><sub><sup>'; // Povolené značky
		return strip_tags($clean,$allowed);                                 // Základní oříznutí nepovolených značek
	}

	/**
	 * Převede Markdown (nebo HTML) na bezpečný, sanitizovaný HTML kód
	 * pomocí knihovny league/commonmark (s podporou GFM tabulek a seznamů).
	 *
	 * @param string $text Vstupní text v Markdownu nebo HTML
	 * @return string Výsledný sanitizovaný HTML kód
	 */
	public static function to_html(string $text): string {                   // Převod Markdown/HTML na bezpečné HTML
		$clean = preg_replace('/^<!--(html|md)-->\s*/', '', $text) ?? $text; // Odstranění případného komentářového prefixu
		if (trim($clean) === '') {                                           // Kontrola prázdného vstupu
			return '';                                                       // Vrácení prázdného řetězce
		}

		if (self::detect_format($text) === 'html') {                         // Pokud je vstup již ve formátu HTML
			return self::sanitize_html($clean);                              // Pouze očistíme přes HtmlSanitizer
		}

		if (class_exists(MarkdownConverter::class) AND class_exists(Environment::class)) { // Kontrola league/commonmark
			$config = [                                                      // Konfigurace CommonMark konvertoru
				'html_input'         => 'allow',                             // Povolíme vložené HTML (následně projde sanitizerem)
				'allow_unsafe_links' => false                                // Zákaz javascript: a data: odkazů
			];                                                               // Konec konfigurace
			$environment = new Environment($config);                         // Vytvoření prostředí CommonMarku
			$environment->addExtension(new CommonMarkCoreExtension());       // Základní CommonMark syntaxe
			if (class_exists(GithubFlavoredMarkdownExtension::class)) {      // Kontrola GFM rozšíření (tabulky, přeškrtnutí)
				$environment->addExtension(new GithubFlavoredMarkdownExtension()); // Přidání GFM rozšíření
			}
			$converter = new MarkdownConverter($environment);                // Inicializace konvertoru$raw_html = $converter->convert($clean)->getContent();           // Převod Markdownu do HTML
			return self::sanitize_html($raw_html);                           // Finální sanitizace výsledného HTML
		}

		return nl2br(htmlspecialchars($clean));                              // Fallback při nedostupnosti knihovny
	}

	/**
	 * Převede HTML (nebo Markdown) na čistý Markdown pomocí knihovny league/html-to-markdown.
	 *
	 * @param string $text Vstupní HTML nebo Markdown řetězec
	 * @return string Výsledný text ve formátu Markdown
	 */
	public static function to_markdown(string $text): string {               // Převod HTML na Markdown
		$clean = preg_replace('/^<!--(html|md)-->\s*/', '', $text) ?? $text; // Odstranění případného komentářového prefixu
		$clean = str_replace("\r\n", "\n", $clean);                          // Sjednocení konců řádků na LF
		if (trim($clean) === '') {                                           // Kontrola prázdného vstupu
			return '';                                                       // Vrácení prázdného řetězce
		}

		if (self::detect_format($text) === 'markdown') {                     // Pokud je text již v Markdownu
			return trim($clean);                                             // Vrátíme očištěný Markdown
		}

		if (class_exists(HtmlConverter::class)) {                            // Kontrola přítomnosti league/html-to-markdown
			$converter = new HtmlConverter([                                 // Inicializace HTML->Markdown konvertoru
				'strip_tags'   => true,                                      // Odstranění neznámých HTML značek
				'hard_break'   => true,                                      // Zachování odřádkování <br>
				'header_style' => 'atx'                                      // Nadpisy pomocí znaků #
			]);                                                              // Konec nastavení konvertoru
			if (class_exists(TableConverter::class)) {                       // Podpora převodu HTML tabulek na Markdown
				$converter->getEnvironment()->addConverter(new TableConverter()); // Registrace konvertoru tabulek
			}
			$md = $converter->convert($clean);                               // Provedení konverze HTML -> Markdown
			return trim(str_replace("\r\n", "\n", $md));                     // Vrácení čistého Markdownu
		}

		return trim(strip_tags($clean));                                     // Nouzový fallback bez knihovny
	}

	/**
	 * Normalizuje a očistí odeslanou hodnotu z formuláře před zápisem do databáze.
	 * Zajišťuje serverovou konverzi mezi Markdownem a HTML a bezpečnostní sanitizaci.
	 *
	 * @param string $raw_val       Surová hodnota z $_POST
	 * @param string $target_format Požadovaný cílový formát ('markdown', 'html', 'auto')
	 * @return string Očištěný řetězec připravený pro uložení do DB
	 */
	public static function normalize_for_storage(string $raw_val, string$target_format = 'auto'): string { // Příprava pro DB
		$val = str_replace("\r\n", "\n", $raw_val);                          // Sjednocení konců řádků na LF
		if (trim($val) === '') {                                             // Prázdný text ukládáme jako ''
			return '';                                                       // Vrácení prázdného řetězce
		}

		if ($target_format === 'markdown') {                                 // Uživatel zvolil uložení jako Markdown
			return self::to_markdown($val);                                  // Převod případného HTML na čistý Markdown
		}

		if ($target_format === 'html') {                                     // Uživatel zvolil uložení jako HTML
			return self::to_html($val);                                      // Převod případného Markdownu a sanitizace HTML
		}

		// Režim 'auto': zachováme detekovaný formát, u HTML provedeme sanitizaci
		if (self::detect_format($val) === 'html') {                          // Pokud je hodnota v HTML
			return self::sanitize_html($val);                                // Očištění HTML přes Symfony HtmlSanitizer
		}
		return trim($val);                                                   // Markdown vrátíme očištěný od okrajových mezer
	}

	/**
	 * Vykreslí bezpečný zformátovaný HTML výstup pro režim pouze pro čtení ($is_readonly)
	 * nebo pro porovnávací tabulku schvalování (page_approval.php).
	 *
	 * @param string $value      Uložený Markdown nebo HTML text
	 * @param bool   $show_badge Zda zobrazit štítek detekovaného formátu ([Markdown] / [HTML])
	 * @return string HTML kód zformátovaného bloku
	 */
	public static function render_formatted(string $value, bool $show_badge = false): string { // Vykreslení formátovaného textu
		if (trim($value) === '') {                                           // Prázdná hodnota
			return '';                                                       // Vrácení prázdného řetězce
		}

		$format = self::detect_format($value);                               // Zjištění formátu ('markdown' nebo 'html')
		$html_out = self::to_html($value);                                   // Převod na sanitizované HTML

		$badge_html = '';                                                    // Volitelný štítek formátu
		if ($show_badge) {                                                   // Sestavení štítku pro schvalování a readonly
			$badge_label = ($format === 'html') ? 'HTML' : 'Markdown';       // Text štítku
			$badge_bg = ($format === 'html') ? '#fff7ed' : '#f0fdf4';        // Barva pozadí štítku
			$badge_col = ($format === 'html') ? '#c2410c' : '#15803d';       // Barva textu štítku
			$badge_brd = ($format === 'html') ? '#fdba74' : '#86efac';       // Barva rámečku štítku
			$badge_html = "<div style=\"margin-bottom: 4px;\"><span style=\"display: inline-block; font-size: 10px; font-weight: bold; padding: 1px 6px; border-radius: 3px; background-color: {$badge_bg}; color: {$badge_col}; border: 1px solid {$badge_brd};\">{$badge_label}</span></div>"; // HTML štítku
		}

		return $badge_html . "<div class=\"bcm-richtext-view\" style=\"line-height: 1.5; font-size: 13px;\">{$html_out}</div>"; // Výsledný blok
	}

	/**
	 * Jednorázově vloží do stránky CSS/JS zdroje pro Toast UI Editor a obslužný Vanilla JS skript.
	 * Automaticky upřednostní lokální soubory v js/ a css/, jinak použije CDN fallback.
	 */
	private static function render_assets_once(): string {
		if (self::$assets_rendered) {                                        // Pokud již byly skripty v tomto requestu vypsány
			return '';                                                       // Nic dalšího nevypisujeme
		}
		self::$assets_rendered = true;                                       // Označení, že skripty jsou již vloženy

		$local_css = 'css/toastui-editor.min.css';                           // Cesta k lokálnímu CSS souboru
		$local_js  = 'js/toastui-editor-all.min.js';                         // Cesta k lokálnímu JS souboru

		$css_url = is_file(__DIR__ . '/' . $local_css)
			? $local_css
			: 'https://uicdn.toast.com/editor/3.2.2/toastui-editor.min.css'; // Lokální CSS nebo CDN fallback

		$js_url = is_file(__DIR__ . '/' . $local_js)
			? $local_js
			: 'https://uicdn.toast.com/editor/3.2.2/toastui-editor-all.min.js'; // Lokální JS nebo CDN fallback

		$safe_css_url = htmlspecialchars($css_url);                          // Ošetřená URL adresa CSS
		$safe_js_url  = htmlspecialchars($js_url);                           // Ošetřená URL adresa JS

		return <<<HTML
<link rel="stylesheet" href="{$safe_css_url}">
<script src="{$safe_js_url}"></script>
<style>
	.bcm-rt-wrapper { border: 1px solid #cbd5e1; border-radius: 4px; background: #fff; overflow: hidden; }
	.bcm-rt-toolbar { display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 6px 10px; background-color: #f8fafc; border-bottom: 1px solid #cbd5e1; font-size: 12px; flex-wrap: wrap; }
	.bcm-rt-format-group { display: flex; align-items: center; gap: 8px; }
	.bcm-rt-convert-btn { padding: 3px 8px; font-size: 11px; font-weight: bold; color: #004488; background-color: #e9f2fa; border: 1px solid #93c5fd; border-radius: 3px; cursor: pointer; }
	.bcm-rt-convert-btn:hover { background-color: #dbeafe; }
	.bcm-richtext-view p { margin: 0 0 8px 0; }
	.bcm-richtext-view p:last-child { margin-bottom: 0; }
	.bcm-richtext-view table { border-collapse: collapse; margin: 6px 0; }
	.bcm-richtext-view th, .bcm-richtext-view td { border: 1px solid #cbd5e1; padding: 4px 8px; }
	.bcm-richtext-view ul, .bcm-richtext-view ol { margin: 4px 0 8px 20px; padding: 0; }
	.bcm-richtext-view pre { background: #f1f5f9; padding: 8px; border-radius: 4px; overflow-x: auto; }
	.bcm-richtext-view code { font-family: monospace; background: #f1f5f9; padding: 1px 4px; border-radius: 3px; }
</style>
<script>
	window.bcmInitRichTextEditor = function(cfg) {
		const textarea = document.getElementById(cfg.textareaId);
		const mountEl = document.getElementById(cfg.mountId);
		const formatSelect = document.getElementById(cfg.formatSelectId);
		const convertBtn = document.getElementById(cfg.convertBtnId);

		if (!textarea || !mountEl || !formatSelect) {
			return;
		}

		// Pokud není Toast UI Editor načten, ponecháme standardní <textarea> a serverovou konverzi
		if (typeof toastui === 'undefined' || !toastui.Editor) {
			textarea.style.display = 'block';
			mountEl.style.display = 'none';
			if (convertBtn) {
				convertBtn.style.display = 'none';
			}
			return;
		}

		textarea.style.display = 'none';
		const isHtmlInit = (cfg.initialFormat === 'html');

		const editor = new toastui.Editor({
			el: mountEl,
			height: cfg.height || '260px',
			initialEditType: isHtmlInit ? 'wysiwyg' : 'markdown',
			previewStyle: 'tab',
			usageStatistics: false,
			initialValue: isHtmlInit ? '' : textarea.value,
			toolbarItems: [
				['heading', 'bold', 'italic', 'strike'],
				['hr', 'quote'],
				['ul', 'ol', 'task'],
				['table', 'link'],
				['code', 'codeblock']
			]
		});

		if (isHtmlInit && textarea.value.trim() !== '') {
			editor.setHTML(textarea.value);
		}

		let isInitializing = true;
		setTimeout(function() { isInitializing = false; }, 150);

		function syncToTextarea() {
			const targetFmt = formatSelect.value;
			if (targetFmt === 'html') {
				textarea.value = editor.getHTML();
			} else {
				textarea.value = editor.getMarkdown();
			}
		}

		editor.on('change', function() {
			syncToTextarea();
			if (!isInitializing && typeof isFormDirty !== 'undefined') {
				isFormDirty = true;
			}
		});

		formatSelect.addEventListener('change', function() {
			if (this.value === 'html') {
				editor.changeMode('wysiwyg', true);
			} else {
				editor.changeMode('markdown', true);
			}
			syncToTextarea();
			if (typeof isFormDirty !== 'undefined') {
				isFormDirty = true;
			}
		});

		if (convertBtn) {
			convertBtn.addEventListener('click', function() {
				if (formatSelect.value === 'markdown') {
					formatSelect.value = 'html';
					editor.changeMode('wysiwyg', true);
				} else {
					formatSelect.value = 'markdown';
					editor.changeMode('markdown', true);
				}
				syncToTextarea();
				if (typeof isFormDirty !== 'undefined') {
					isFormDirty = true;
				}
			});
		}

		const parentForm = textarea.closest('form');
		if (parentForm) {
			parentForm.addEventListener('submit', function() {
				syncToTextarea();
			});
		}
	};
</script>
HTML;
	}

	/**
	 * Vykreslí kompletní interaktivní editor (Markdown + HTML WYSIWYG) pro formulářové pole.
	 *
	 * @param string               $column_name Název sloupce v databázi
	 * @param string               $value       Aktuální hodnota pole
	 * @param array<string, mixed> $meta        Metadata sloupce z entity_manageru
	 * @return string HTML kód editoru
	 */
	public static function render_editor(string $column_name, string $value, array $meta = []): string { // Vykreslení editoru
		self::$editor_counter++;                                             // Zvýšení unikátního počitadla editoru
		$idx = self::$editor_counter;                                        // Číslo aktuální instance editoru

		$assets_html = self::render_assets_once();                           // Jednorázové načtení JS/CSS zdrojů
		$detected_format = self::detect_format($value);                      // Detekce 'markdown' vs. 'html'

		$safe_name = htmlspecialchars($column_name);                         // Ošetřený název vstupního pole
		$safe_val  = htmlspecialchars($value);                               // Ošetřená hodnota pro výchozí <textarea>
		$rows_num  = !empty($meta['input_rows']) ? max(4, intval($meta['input_rows'])) : 6; // Počet řádků
		$height_px = max(220, $rows_num * 38) . 'px';                        // Výška Toast UI Editoru v pixelech

		$ta_id  = "bcm_rt_ta_{$idx}";                                        // ID skrytého prvku <textarea>
		$mnt_id = "bcm_rt_mnt_{$idx}";                                       // ID kontejneru pro Toast UI Editor
		$sel_id = "bcm_rt_fmt_{$idx}";                                       // ID přepínače cílového formátu
		$btn_id = "bcm_rt_btn_{$idx}";                                       // ID tlačítka rychlé konverze

		$sel_md   = ($detected_format === 'markdown') ? 'selected' : '';     // Označení volby Markdown
		$sel_html = ($detected_format === 'html') ? 'selected' : '';         // Označení volby HTML

		$lbl_fmt = htmlspecialchars(self::phrase('lbl_storage_format', 'Formát uložení:')); // Popisek roletky formátu
		$opt_md  = htmlspecialchars(self::phrase('opt_format_markdown', 'Markdown (preferováno)')); // Volba Markdown
		$opt_htm = htmlspecialchars(self::phrase('opt_format_html', 'HTML (WYSIWYG)')); // Volba HTML
		$btn_ txt = htmlspecialchars(self::phrase('btn_convert_format', 'Přepnout a zkonvertovat (MD ⇄ HTML)')); // Tlačítko konverze
		$tip_btn = htmlspecialchars(self::phrase('tip_convert_format', 'Převede stávající text mezi formáty Markdown a HTML a přepne režim editoru')); // Tooltip

		$req_attr = !empty($meta['is_mandatory']) ? 'required' : '';         // Případný atribut povinného pole
		$ph_attr  = !empty($meta['placeholder']) ? 'placeholder="' . htmlspecialchars((string)$meta['placeholder']) . '"' : ''; // Placeholder

		$js_cfg = json_encode([                                              // Konfigurační JSON pro inicializaci v JS
			'textareaId'    => $ta_id,
			'mountId'       => $mnt_id,
			'formatSelectId'=> $sel_id,
			'convertBtnId'  => $btn_id,
			'initialFormat' => $detected_format,
			'height'        => $height_px
		]);                                                                  // Konec JSON konfigurace

		return <<<HTML
{$assets_html}
<div class="bcm-rt-wrapper">
	<div class="bcm-rt-toolbar">
		<div class="bcm-rt-format-group">
			<label for="{$sel_id}" style="font-weight: bold; color: #334155;">{$lbl_fmt}</label>
			<select id="{$sel_id}" name="{$safe_name}__target_format" style="padding: 2px 6px; font-size: 12px; border: 1px solid #cbd5e1; border-radius: 3px;">
				<option value="markdown" {$sel_md}>{$opt_md}</option>
				<option value="html" {$sel_html}>{$opt_htm}</option>
			</select>
		</div>
		<button type="button" id="{$btn_id}" class="bcm-rt-convert-btn" title="{$tip_btn}">{$btn_txt}</button>
	</div>
	<textarea id="{$ta_id}" name="{$safe_name}" rows="{$rows_num}" {$ph_attr} {$req_attr} style="width: 100%; padding: 8px; box-sizing: border-box; border: none; font-family: monospace;">{$safe_val}</textarea>
	<div id="{$mnt_id}"></div>
</div>
<script>
	document.addEventListener('DOMContentLoaded', function() {
		if (window.bcmInitRichTextEditor) {
			window.bcmInitRichTextEditor({$js_cfg});
		}
	});
</script>
HTML;
	}
}