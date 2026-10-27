<?php
/**
 * =============================================================================
 * Verze: 2026-10-27 14:10
 * Soubor: rich_text.php
 * Třída: rich_text
 * Účel: Centrální služba pro detekci formátu (Markdown vs. HTML), obousměrnou
 *       konverzi, bezpečnostní sanitizaci HTML, vykreslování Preview náhledu
 *       v detailu a modálního editoru na popředí (Toast UI Editor) pro sloupce
 *       s příznakem meta_column.is_html = 1.
 *
 * ARCHITEKTONICKÉ VAZBY:
 * - Automaticky načítána přes spl_autoload_register v config.php.
 * - Využívá Composer knihovny:
 *   1. league/commonmark (převod Markdown -> HTML včetně GitHub Flavored Markdown tabulek),
 *   2. league/html-to-markdown (převod HTML -> Markdown včetně tabulek),
 *   3. symfony/html-sanitizer (bezpečnostní sanitizace HTML proti XSS).
 * - Na klientské straně (Vanilla JS) využívá Toast UI Editor
 *   (js/toastui-editor-all.min.js a css/toastui-editor.min.css s CDN fallbackem).
 * - V detailním formuláři (render_editor) zobrazuje čistý Preview režim se štítkem
 *   formátu a tlačítkem „Upravit“, které otevře prostorný modální panel na popředí.
 * - Volána z entity_manager::render_dynamic_input(), entity_manager_write::extract_post_data()
 *   a ze schvalovací obrazovky page_approval::render_detail().
 * - Využívá globální $phrase_manager pro plnou lokalizaci ovládacích prvků editoru.
 *
 * Změny:
 * 2026-10-27 14:10 - Přepracování render_editor() na Preview box v detailu s tlačítkem
 *                    „Upravit“, které otevře modální editor na popředí (mimo .md-table).
 *                  - Oprava spojených řádků ($clean v sanitize_html a $raw_html v to_html)
 *                    a doplnění mezer před znakem $ dle Anti-LaTeX pravidla.
 *                  - Doplněna CSS pojistka pro .toastui-editor-tooltip a ikony lišty
 *                    proti uskakování tlačítka More a podpora AJAX načtení detailu.
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
	private static function phrase(string $builtin_code, string $default_caption, array $vars = []): string { // Překlad fráze
		global $phrase_manager;                                              // Globální instance správce frází
		if (!isset($phrase_manager) OR !($phrase_manager instanceof phrase_manager)) { // Kontrola existence správce
			$phrase_manager = new phrase_manager('rich_text');               // Nouzová inicializace správce frází
			$GLOBALS['phrase_manager'] = $phrase_manager;                    // Uložení do globálního kontextu
		}
		return $phrase_manager->get($builtin_code, $vars, $default_caption, 'rich_text'); // Vrácení přeložené fráze
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
		foreach ($html_tags as $tag) {                                       // Průchod sledovanými HTML značkami
			if (str_contains($lower, $tag)) {                                // Nalezena HTML značka v textu
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
	public static function sanitize_html(string $raw_html): string {         // Sanitizace HTML proti XSS
		$clean = preg_replace('/^<!--(html|md)-->\s*/', '', $raw_html) ?? $raw_html; // Odstranění případné interní značky
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
		return strip_tags($clean, $allowed);                                 // Základní oříznutí nepovolených značek
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
			$converter = new MarkdownConverter($environment);                // Inicializace konvertoru
			$raw_html = (string)$converter->convert($clean)->getContent();   // Převod Markdownu do HTML
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
	public static function normalize_for_storage(string $raw_val, string $target_format = 'auto'): string { // Příprava pro DB
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
	 * Jednorázově vloží do stránky CSS/JS zdroje pro Toast UI Editor a obsluhu modálního editoru na popředí.
	 * Pokud by stránka načetla první rich_text prvek až přes AJAX, JavaScript sám zajistí načtení CSS/JS.
	 */
	private static function render_assets_once(): string {
		if (self::$assets_rendered) {                                        // Pokud již byly skripty v tomto requestu vypsány
			return '';                                                       // Nic dalšího nevypisujeme
		}
		self::$assets_rendered = true;                                       // Označení, že skripty jsou již vloženy

		$local_css = 'css/toastui-editor.min.css';                           // Standardní cesta k lokálnímu CSS souboru
		$alt_css   = 'js/toastui-editor.min.css';                            // Alternativní umístění CSS souboru
		$local_js  = 'js/toastui-editor-all.min.js';                         // Cesta k lokálnímu JS souboru

		if (is_file(__DIR__ . '/' . $local_css) AND filesize(__DIR__ . '/' . $local_css) > 1000) { // Ověření platného CSS v css/
			$css_url = $local_css;                                           // Použijeme lokální CSS v adresáři css/
		} elseif (is_file(__DIR__ . '/' . $alt_css) AND filesize(__DIR__ . '/' . $alt_css) > 1000) { // Ověření v js/
			$css_url = $alt_css;                                             // Použijeme lokální CSS v adresáři js/
		} else {
			$css_url = 'https://cdn.jsdelivr.net/npm/@toast-ui/editor@3.2.2/dist/toastui-editor.min.css'; // Spolehlivý CDN fallback
		}

		$js_url = (is_file(__DIR__ . '/' . $local_js) AND filesize(__DIR__ . '/' . $local_js) > 1000)
			? $local_js
			: 'https://cdn.jsdelivr.net/npm/@toast-ui/editor@3.2.2/dist/toastui-editor-all.min.js'; // Lokální JS nebo CDN fallback

		$safe_css_url = htmlspecialchars($css_url);                          // Ošetřená URL adresa CSS
		$safe_js_url  = htmlspecialchars($js_url);                           // Ošetřená URL adresa JS

		$lbl_modal_title = addslashes(self::phrase('lbl_modal_edit_title', 'Editace formátovaného textu:')); // Titulek modálu
		$lbl_fmt         = addslashes(self::phrase('lbl_storage_format', 'Formát uložení:')); // Popisek roletky formátu
		$opt_md          = addslashes(self::phrase('opt_format_markdown', 'Markdown (preferováno)')); // Volba Markdown
		$opt_htm         = addslashes(self::phrase('opt_format_html', 'HTML (WYSIWYG)')); // Volba HTML
		$btn_conv        = addslashes(self::phrase('btn_convert_format', 'Přepnout a zkonvertovat (MD ⇄ HTML)')); // Tlačítko konverze
		$tip_conv        = addslashes(self::phrase('tip_convert_format', 'Převede stávající text mezi formáty Markdown a HTML a přepne režim editoru')); // Tooltip konverze
		$btn_apply       = addslashes(self::phrase('btn_apply_modal', 'Použít v detailu')); // Tlačítko potvrzení modálu
		$btn_cancel      = addslashes(self::phrase('btn_cancel_modal', 'Zrušit')); // Tlačítko zrušení modálu
		$msg_modal_hint  = addslashes(self::phrase('msg_modal_footer_hint', 'Po kliknutí na „Použít v detailu“ se upravený text propíše do náhledu. Pro trvalý zápis do databáze pak uložte záznam.')); // Nápověda v patičce
		$txt_empty_prev  = addslashes(self::phrase('txt_empty_preview', '(Prázdné – klikněte na Upravit)')); // Text prázdného náhledu

		return <<<HTML
<link rel="stylesheet" href="{$safe_css_url}" id="bcm-toastui-css">
<script src="{$safe_js_url}" id="bcm-toastui-js"></script>
<style>
	/* Preview karta přímo v tabulce detailu */
	.bcm-rt-preview-card { border: 1px solid #cbd5e1; border-radius: 4px; background-color: #ffffff; overflow: hidden; }
	.bcm-rt-preview-bar { display: flex; justify-content: space-between; align-items: center; padding: 4px 10px; background-color: #f8fafc; border-bottom: 1px solid #e2e8f0; gap: 8px; }
	.bcm-rt-badge { display: inline-block; font-size: 10px; font-weight: bold; padding: 1px 6px; border-radius: 3px; }
	.bcm-rt-badge-md { background-color: #f0fdf4; color: #15803d; border: 1px solid #86efac; }
	.bcm-rt-badge-html { background-color: #fff7ed; color: #c2410c; border: 1px solid #fdba74; }
	.bcm-rt-edit-btn { display: inline-flex; align-items: center; gap: 5px; padding: 3px 10px; font-size: 12px; font-weight: bold; color: #004488; background-color: #e9f2fa; border: 1px solid #93c5fd; border-radius: 3px; cursor: pointer; transition: background 0.15s; }
	.bcm-rt-edit-btn:hover { background-color: #dbeafe; color: #003366; }
	.bcm-rt-edit-btn svg { width: 13px; height: 13px; fill: currentColor; }
	.bcm-rt-preview-body { padding: 8px 12px; min-height: 36px; max-height: 220px; overflow-y: auto; font-size: 13px; line-height: 1.5; color: #1e293b; background-color: #ffffff; }
	.bcm-rt-empty-placeholder { color: #94a3b8; font-style: italic; font-size: 12px; }

	/* Sdílené formátování vykresleného obsahu v náhledu */
	.bcm-richtext-view p, .bcm-rt-preview-body p { margin: 0 0 8px 0; }
	.bcm-richtext-view p:last-child, .bcm-rt-preview-body p:last-child { margin-bottom: 0; }
	.bcm-richtext-view table, .bcm-rt-preview-body table { border-collapse: collapse; margin: 6px 0; width: auto; }
	.bcm-richtext-view th, .bcm-richtext-view td, .bcm-rt-preview-body th, .bcm-rt-preview-body td { border: 1px solid #cbd5e1; padding: 4px 8px; }
	.bcm-richtext-view ul, .bcm-richtext-view ol, .bcm-rt-preview-body ul, .bcm-rt-preview-body ol { margin: 4px 0 8px 20px; padding: 0; }
	.bcm-richtext-view pre, .bcm-rt-preview-body pre { background: #f1f5f9; padding: 8px; border-radius: 4px; overflow-x: auto; }
	.bcm-richtext-view code, .bcm-rt-preview-body code { font-family: monospace; background: #f1f5f9; padding: 1px 4px; border-radius: 3px; }

	/* Modální panel editoru na popředí (mimo .md-table) */
	.bcm-rt-modal-overlay { position: fixed; inset: 0; background-color: rgba(15, 23, 42, 0.55); z-index: 99990; display: none; align-items: center; justify-content: center; padding: 20px; box-sizing: border-box; }
	.bcm-rt-modal-overlay.active { display: flex; }
	.bcm-rt-modal-dialog { background-color: #ffffff; width: min(1120px, 94vw); height: min(760px, 88vh); border-radius: 6px; box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3); display: flex; flex-direction: column; overflow: hidden; border: 1px solid #94a3b8; }
	.bcm-rt-modal-header { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 10px 16px; background-color: #f1f5f9; border-bottom: 1px solid #cbd5e1; flex-wrap: wrap; }
	.bcm-rt-modal-title { font-size: 15px; font-weight: bold; color: #004488; margin: 0; }
	.bcm-rt-modal-controls { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; font-size: 12px; }
	.bcm-rt-convert-btn { padding: 4px 10px; font-size: 12px; font-weight: bold; color: #004488; background-color: #e9f2fa; border: 1px solid #93c5fd; border-radius: 3px; cursor: pointer; }
	.bcm-rt-convert-btn:hover { background-color: #dbeafe; }
	.bcm-rt-modal-body { flex: 1 1 auto; display: flex; flex-direction: column; overflow: hidden; padding: 0; position: relative; background-color: #fff; }
	.bcm-rt-modal-mount { flex: 1 1 auto; overflow: hidden; }
	.bcm-rt-modal-fallback-ta { width: 100%; height: 100%; border: none; padding: 12px; box-sizing: border-box; font-family: monospace; font-size: 13px; resize: none; display: none; }
	.bcm-rt-modal-footer { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 10px 16px; background-color: #f8fafc; border-top: 1px solid #cbd5e1; flex-wrap: wrap; }
	.bcm-rt-modal-hint { font-size: 12px; color: #64748b; }
	.bcm-rt-modal-actions { display: flex; align-items: center; gap: 10px; }

	/* Ochranné pojistky pro Toast UI Editor proti poskakování tooltipu More a kolizi stylů */
	.toastui-editor-tooltip { position: absolute !important; z-index: 100020 !important; pointer-events: none !important; background-color: #1e293b !important; color: #fff !important; padding: 4px 8px !important; border-radius: 3px !important; font-size: 11px !important; white-space: nowrap !important; }
	.toastui-editor-defaultUI-toolbar { display: flex !important; align-items: center !important; flex-wrap: wrap !important; padding: 0 8px !important; background-color: #f8fafc !important; border-bottom: 1px solid #e2e8f0 !important; }
	.toastui-editor-toolbar-group { display: flex !important; align-items: center !important; border: none !important; margin: 2px 4px !important; }
	.toastui-editor-dropdown-toolbar { position: absolute !important; z-index: 100010 !important; background-color: #fff !important; border: 1px solid #cbd5e1 !important; box-shadow: 0 4px 12px rgba(0,0,0,0.15) !important; display: flex !important; align-items: center !important; padding: 4px !important; border-radius: 4px !important; }
	.toastui-editor-defaultUI .ProseMirror { font-family: Arial, sans-serif; font-size: 13px; line-height: 1.5; }
</style>
<script>
	(function() {
		let modalOverlay = null;
		let modalEditorInstance = null;
		let activeFieldCfg = null;

		// Ověří, zda je v dokumentu skutečně aplikováno CSS pro Toast UI Editor; pokud ne, připojí CDN záložní styl
		function ensureToastUiCssLoaded() {
			const testEl = document.createElement('div');
			testEl.className = 'toastui-editor-defaultUI';
			testEl.style.display = 'none';
			document.body.appendChild(testEl);
			const pos = window.getComputedStyle(testEl).position;
			document.body.removeChild(testEl);

			if (pos !== 'relative' && !document.getElementById('bcm-toastui-css-cdn-fallback')) {
				const link = document.createElement('link');
				link.id = 'bcm-toastui-css-cdn-fallback';
				link.rel = 'stylesheet';
				link.href = 'https://cdn.jsdelivr.net/npm/@toast-ui/editor@3.2.2/dist/toastui-editor.min.css';
				document.head.appendChild(link);
			}
		}

		// Pokud by selhalo načtení sprite ikon z CSS, doplní tlačítkům čitelné popisky
		function ensureToolbarButtonsReadable(rootEl) {
			if (!rootEl) return;
			const fallbackLabels = {
				'heading': 'H',
				'bold': 'B',
				'italic': 'I',
				'strike': 'S',
				'hr': '―',
				'quote': '❝',
				'ul': '•',
				'ol': '1.',
				'task': '☑',
				'table': '⊞',
				'link': '🔗',
				'code': '<>',
				'codeblock': '{ }',
				'more': '⋯'
			};
			rootEl.querySelectorAll('.toastui-editor-toolbar-icons').forEach(function(btn) {
				const bg = window.getComputedStyle(btn).backgroundImage;
				if (!bg || bg === 'none') {
					btn.style.width = 'auto';
					btn.style.minWidth = '28px';
					btn.style.height = '26px';
					btn.style.padding = '0 6px';
					btn.style.margin = '2px';
					btn.style.border = '1px solid #cbd5e1';
					btn.style.borderRadius = '3px';
					btn.style.background = '#ffffff';
					btn.style.fontWeight = 'bold';
					btn.style.fontSize = '12px';
					btn.style.color = '#1e293b';
					btn.style.cursor = 'pointer';
					Object.keys(fallbackLabels).forEach(function(cls) {
						if (btn.classList.contains(cls) && btn.textContent.trim() === '') {
							btn.textContent = fallbackLabels[cls];
						}
					});
				}
			});
		}

		// Jednorázově vytvoří DOM modálního okna v document.body
		function getOrCreateModal() {
			if (modalOverlay && document.body.contains(modalOverlay)) {
				return modalOverlay;
			}

			ensureToastUiCssLoaded();

			modalOverlay = document.createElement('div');
			modalOverlay.id = 'bcm-rt-modal-overlay';
			modalOverlay.className = 'bcm-rt-modal-overlay';
			modalOverlay.innerHTML = ''
				+ '<div class="bcm-rt-modal-dialog" onclick="event.stopPropagation();">'
				+ '	<div class="bcm-rt-modal-header">'
				+ '		<h3 class="bcm-rt-modal-title" id="bcm-rt-modal-title"></h3>'
				+ '		<div class="bcm-rt-modal-controls">'
				+ '			<label for="bcm-rt-modal-fmt" style="font-weight: bold; color: #334155;">{$lbl_fmt}</label>'
				+ '			<select id="bcm-rt-modal-fmt" style="padding: 4px 8px; font-size: 12px; border: 1px solid #cbd5e1; border-radius: 3px;">'
				+ '				<option value="markdown">{$opt_md}</option>'
				+ '				<option value="html">{$opt_htm}</option>'
				+ '			</select>'
				+ '			<button type="button" id="bcm-rt-modal-conv" class="bcm-rt-convert-btn" title="{$tip_conv}">{$btn_conv}</button>'
				+ '		</div>'
				+ '	</div>'
				+ '	<div class="bcm-rt-modal-body">'
				+ '		<textarea id="bcm-rt-modal-fallback-ta" class="bcm-rt-modal-fallback-ta"></textarea>'
				+ '		<div id="bcm-rt-modal-mount" class="bcm-rt-modal-mount"></div>'
				+ '	</div>'
				+ '	<div class="bcm-rt-modal-footer">'
				+ '		<div class="bcm-rt-modal-hint">{$msg_modal_hint}</div>'
				+ '		<div class="bcm-rt-modal-actions">'
				+ '			<button type="button" id="bcm-rt-modal-cancel" class="btn btn-secondary" style="padding: 8px 14px;">{$btn_cancel}</button>'
				+ '			<button type="button" id="bcm-rt-modal-apply" class="btn btn-success" style="padding: 8px 16px;">{$btn_apply}</button>'
				+ '		</div>'
				+ '	</div>'
				+ '</div>';

			document.body.appendChild(modalOverlay);

			const fmtSelect = document.getElementById('bcm-rt-modal-fmt');
			const convBtn   = document.getElementById('bcm-rt-modal-conv');
			const cancelBtn = document.getElementById('bcm-rt-modal-cancel');
			const applyBtn  = document.getElementById('bcm-rt-modal-apply');

			fmtSelect.addEventListener('change', function() {
				if (!modalEditorInstance) return;
				if (this.value === 'html') {
					modalEditorInstance.changeMode('wysiwyg', true);
				} else {
					modalEditorInstance.changeMode('markdown', true);
				}
				setTimeout(function() { ensureToolbarButtonsReadable(modalOverlay); }, 50);
			});

			convBtn.addEventListener('click', function() {
				if (!modalEditorInstance) return;
				if (fmtSelect.value === 'markdown') {
					fmtSelect.value = 'html';
					modalEditorInstance.changeMode('wysiwyg', true);
				} else {
					fmtSelect.value = 'markdown';
					modalEditorInstance.changeMode('markdown', true);
				}
				setTimeout(function() { ensureToolbarButtonsReadable(modalOverlay); }, 50);
			});

			cancelBtn.addEventListener('click', closeRichTextModal);
			applyBtn.addEventListener('click', applyRichTextModal);

			document.addEventListener('keydown', function(ev) {
				if (ev.key === 'Escape' && modalOverlay && modalOverlay.classList.contains('active')) {
					closeRichTextModal();
				}
			});

			return modalOverlay;
		}

		function closeRichTextModal() {
			if (!modalOverlay) return;
			modalOverlay.classList.remove('active');
			if (modalEditorInstance && typeof modalEditorInstance.destroy === 'function') {
				try { modalEditorInstance.destroy(); } catch (e) {}
			}
			modalEditorInstance = null;
			activeFieldCfg = null;
		}

		function applyRichTextModal() {
			if (!activeFieldCfg) return;
			const taEl      = document.getElementById(activeFieldCfg.textareaId);
			const fmtEl     = document.getElementById(activeFieldCfg.formatInputId);
			const prevBody  = document.getElementById(activeFieldCfg.previewBodyId);
			const badgeEl   = document.getElementById(activeFieldCfg.badgeId);
			const modalFmt  = document.getElementById('bcm-rt-modal-fmt');
			const fallbackTa = document.getElementById('bcm-rt-modal-fallback-ta');

			const chosenFormat = modalFmt ? modalFmt.value : 'markdown';
			let newRawValue = '';
			let newPreviewHtml = '';

			if (modalEditorInstance) {
				if (chosenFormat === 'html') {
					newRawValue = modalEditorInstance.getHTML();
				} else {
					newRawValue = modalEditorInstance.getMarkdown();
				}
				newPreviewHtml = modalEditorInstance.getHTML();
			} else if (fallbackTa) {
				newRawValue = fallbackTa.value;
				newPreviewHtml = '<pre style="margin:0; white-space:pre-wrap; font-family:inherit;">'
					+ newRawValue.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
					+ '</pre>';
			}

			if (taEl) {
				taEl.value = newRawValue;
			}
			if (fmtEl) {
				fmtEl.value = chosenFormat;
			}
			if (badgeEl) {
				badgeEl.textContent = (chosenFormat === 'html') ? 'HTML' : 'Markdown';
				badgeEl.className = 'bcm-rt-badge ' + (chosenFormat === 'html' ? 'bcm-rt-badge-html' : 'bcm-rt-badge-md');
			}
			if (prevBody) {
				if (newRawValue.trim() === '') {
					prevBody.innerHTML = '<span class="bcm-rt-empty-placeholder">{$txt_empty_prev}</span>';
				} else {
					prevBody.innerHTML = newPreviewHtml;
				}
			}

			if (typeof isFormDirty !== 'undefined') {
				isFormDirty = true;
			}

			closeRichTextModal();
		}

		// Otevře modální editor na popředí pro vybrané pole detailu
		window.bcmOpenRichTextModal = function(cfg) {
			const overlay    = getOrCreateModal();
			const titleEl    = document.getElementById('bcm-rt-modal-title');
			const fmtSelect  = document.getElementById('bcm-rt-modal-fmt');
			const convBtn    = document.getElementById('bcm-rt-modal-conv');
			const mountEl    = document.getElementById('bcm-rt-modal-mount');
			const fallbackTa = document.getElementById('bcm-rt-modal-fallback-ta');

			const taEl  = document.getElementById(cfg.textareaId);
			const fmtEl = document.getElementById(cfg.formatInputId);
			if (!taEl || !fmtEl) return;

			activeFieldCfg = cfg;
			const currentVal = taEl.value || '';
			const currentFmt = (fmtEl.value === 'html') ? 'html' : 'markdown';

			if (titleEl) {
				titleEl.textContent = '{$lbl_modal_title} ' + (cfg.fieldLabel || cfg.columnName || '');
			}
			if (fmtSelect) {
				fmtSelect.value = currentFmt;
			}

			if (modalEditorInstance && typeof modalEditorInstance.destroy === 'function') {
				try { modalEditorInstance.destroy(); } catch (e) {}
				modalEditorInstance = null;
			}
			mountEl.innerHTML = '';

			overlay.classList.add('active');

			if (typeof toastui === 'undefined' || !toastui.Editor) {
				mountEl.style.display = 'none';
				fallbackTa.style.display = 'block';
				fallbackTa.value = currentVal;
				if (convBtn) convBtn.style.display = 'none';
				fallbackTa.focus();
				return;
			}

			fallbackTa.style.display = 'none';
			mountEl.style.display = 'block';
			if (convBtn) convBtn.style.display = 'inline-block';

			const isHtmlInit = (currentFmt === 'html');
			const previewMode = (window.innerWidth >= 900) ? 'vertical' : 'tab';

			modalEditorInstance = new toastui.Editor({
				el: mountEl,
				height: '100%',
				initialEditType: isHtmlInit ? 'wysiwyg' : 'markdown',
				previewStyle: previewMode,
				usageStatistics: false,
				initialValue: isHtmlInit ? '' : currentVal,
				toolbarItems: [
					['heading', 'bold', 'italic', 'strike'],
					['hr', 'quote'],
					['ul', 'ol', 'task'],
					['table', 'link'],
					['code', 'codeblock']
				]
			});

			if (isHtmlInit && currentVal.trim() !== '') {
				modalEditorInstance.setHTML(currentVal);
			}

			setTimeout(function() {
				ensureToolbarButtonsReadable(overlay);
				if (modalEditorInstance && typeof modalEditorInstance.focus === 'function') {
					modalEditorInstance.focus();
				}
			}, 60);
		};
	})();
</script>
HTML;
	}

	/**
	 * Vykreslí v buňce detailu přehledný Preview box se štítkem formátu (Markdown / HTML),
	 * skrytým polem pro formulář a tlačítkem „Upravit“, které otevře modální editor na popředí.
	 *
	 * @param string               $column_name Název sloupce v databázi
	 * @param string               $value       Aktuální hodnota pole
	 * @param array<string, mixed> $meta        Metadata sloupce z entity_manageru
	 * @return string HTML kód Preview karty s tlačítkem pro otevření modálního editoru
	 */
	public static function render_editor(string $column_name, string $value, array $meta = []): string { // Vykreslení Preview + modálu
		self::$editor_counter++;                                             // Zvýšení unikátního počitadla prvku
		$idx = self::$editor_counter;                                        // Číslo aktuální instance prvku

		$assets_html = self::render_assets_once();                           // Jednorázové načtení JS/CSS zdrojů
		$detected_format = self::detect_format($value);                      // Detekce 'markdown' vs. 'html'

		$safe_name  = htmlspecialchars($column_name);                        // Ošetřený název vstupního pole
		$safe_val   = htmlspecialchars($value);                              // Ošetřená hodnota pro skryté <textarea>
		$field_lbl  = (string)($meta['label'] ?: $meta['caption'] ?: $column_name); // Lidsky čitelný název pole

		$ta_id      = "bcm_rt_ta_{$idx}";                                    // ID skrytého prvku <textarea>
		$fmt_id     = "bcm_rt_fmt_{$idx}";                                   // ID skrytého pole cílového formátu
		$prev_id    = "bcm_rt_prev_{$idx}";                                  // ID kontejneru vykresleného náhledu
		$badge_id   = "bcm_rt_badge_{$idx}";                                 // ID štítku formátu

		$badge_txt  = ($detected_format === 'html') ? 'HTML' : 'Markdown';   // Text štítku formátu
		$badge_cls  = ($detected_format === 'html') ? 'bcm-rt-badge-html' : 'bcm-rt-badge-md'; // CSS třída štítku

		$btn_edit_lbl = htmlspecialchars(self::phrase('btn_open_editor', 'Upravit')); // Text tlačítka Upravit
		$tip_edit_btn = htmlspecialchars(self::phrase('tip_open_editor', 'Otevřít editor formátovaného textu na popředí')); // Tooltip tlačítka
		$empty_txt    = htmlspecialchars(self::phrase('txt_empty_preview', '(Prázdné – klikněte na Upravit)')); // Text pro prázdnou hodnotu

		$rendered_preview = (trim($value) !== '')
			? self::to_html($value)
			: "<span class=\"bcm-rt-empty-placeholder\">{$empty_txt}</span>"; // Vyrenderovaný HTML náhled nebo placeholder

		$js_cfg = json_encode([                                              // Konfigurace předávaná do modálního editoru
			'textareaId'    => $ta_id,
			'formatInputId' => $fmt_id,
			'previewBodyId' => $prev_id,
			'badgeId'       => $badge_id,
			'columnName'    => $column_name,
			'fieldLabel'    => $field_lbl
		]);                                                                  // Konec JSON konfigurace
		$safe_onclick_cfg = htmlspecialchars((string)$js_cfg, ENT_QUOTES, 'UTF-8'); // Ošetřený JSON pro atribut onclick

		$pencil_svg = '<svg viewBox="0 0 24 24"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34a.9959.9959 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>'; // Ikona tužky

		return <<<HTML
{$assets_html}
<div class="bcm-rt-preview-card">
	<div class="bcm-rt-preview-bar">
		<span id="{$badge_id}" class="bcm-rt-badge {$badge_cls}">{$badge_txt}</span>
		<button type="button" class="bcm-rt-edit-btn" title="{$tip_edit_btn}" onclick="window.bcmOpenRichTextModal({$safe_onclick_cfg});">
			{$pencil_svg}
			<span>{$btn_edit_lbl}</span>
		</button>
	</div>
	<div id="{$prev_id}" class="bcm-rt-preview-body" ondblclick="window.bcmOpenRichTextModal({$safe_onclick_cfg});" title="{$tip_edit_btn}" style="cursor: pointer;">{$rendered_preview}</div>
	<textarea id="{$ta_id}" name="{$safe_name}" style="display: none;">{$safe_val}</textarea>
	<input type="hidden" id="{$fmt_id}" name="{$safe_name}__target_format" value="{$detected_format}">
</div>
HTML;
	}
}