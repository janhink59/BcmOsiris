/* =============================================================================
 * Verze: 2026-11-13 16:45
 * Soubor: page_meta_phrase#phrase.sql
 * Účel:   Registrace stránky page_meta_phrase do sysinit_object, položky menu
 *         meta_phrase do sysinit_menu a frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'page_meta_phrase';
DELETE FROM sysinit_menu WHERE builtin_code = 'meta_phrase';
DELETE FROM sysinit_phrase WHERE source_code = 'page_meta_phrase';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','page_meta_phrase','cs','U','Textové fráze a překlady','Správa textových frází, tlačítek a jazykových mutací'),
('P','page_meta_phrase','en','U','Text Phrases & Translations','Management of text phrases, buttons, and language mutations');

INSERT INTO sysinit_menu (builtin_code, [language], parent_code, sort_code, target_page, url_parameters, system_role, svg_icon, caption, description, helptext) VALUES
('meta_phrase','cs','metadata_folder','030','page_meta_phrase','','U','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94 2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v1.99h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.3 9.19 6.69 8h-2c.73 1.63 1.73 3.17 2.98 4.56l-5.09 5.02L4 19l5-5 3.11 3.11.76-2.04zM18.5 10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z"/></svg>','Textové fráze a překlady','Správa textových frází, tlačítek a jazykových mutací','Správa textových frází, tlačítek a jazykových mutací');

INSERT INTO sysinit_menu (builtin_code, [language], caption, description, helptext) VALUES
('meta_phrase','en','Text Phrases & Translations','Management of text phrases, buttons, and language mutations','Management of text phrases, buttons, and language mutations');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('page_meta_phrase','btn_new_phrase','cs','+ Nová textová fráze','Založí novou lokalizovatelnou textovou frázi nebo tlačítko',''),
('page_meta_phrase','grp_ai_protection','cs','Kontext pro překlad (AI) a ochrana','',''),
('page_meta_phrase','grp_identification','cs','Zdrojová třída a unikátní kód fráze','',''),
('page_meta_phrase','grp_presentation','cs','Text fráze, tooltip a vzhled tlačítka','',''),
('page_meta_phrase','header_edit_phrase','cs','Textová fráze','',''),
('page_meta_phrase','header_new_phrase','cs','Nová textová fráze','',''),
('page_meta_phrase','lbl_filter_source','cs','Filtrovat podle zdroje (source_code):','',''),
('page_meta_phrase','opt_all_sources','cs','--- Všechny zdroje (stránky a třídy) ---','',''),
('page_meta_phrase','page_title','cs','Textové fráze a překlady - BCM Osiris','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('page_meta_phrase','btn_new_phrase','en','+ New Text Phrase','Create a new localizable text phrase or button label'),
('page_meta_phrase','grp_ai_protection','en','Translation Context (AI) & Protection',''),
('page_meta_phrase','grp_identification','en','Source Class & Unique Phrase Code',''),
('page_meta_phrase','grp_presentation','en','Phrase Text, Tooltip & Button Styling',''),
('page_meta_phrase','header_edit_phrase','en','Text Phrase',''),
('page_meta_phrase','header_new_phrase','en','New Text Phrase',''),
('page_meta_phrase','lbl_filter_source','en','Filter by Source (source_code):',''),
('page_meta_phrase','opt_all_sources','en','--- All Sources (Pages & Classes) ---',''),
('page_meta_phrase','page_title','en','Text Phrases & Translations - BCM Osiris','');
GO