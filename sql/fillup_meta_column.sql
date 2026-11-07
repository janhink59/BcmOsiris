/* =============================================================================
 * Verze: 2026-11-07 13:15
 * Soubor: fillup_meta_column.sql
 * Účel:   Hromadné idempotentní nastavení výchozích českých názvů sloupců (jazyk 'cs')
 *         pro globální slovník sys_global_columns (a specifické lokální overridy)
 *         v tabulce meta_column (object_owner = 0x00) jedním příkazem z tabulkové
 *         proměnné se sloupci (column_name, caption, label, header, helptext).
 *         Přepisuje záznamy s who_modified = 0x00 nebo date_modified < '2026-11-01'
 *         a synchronizuje symetrické 'L' záznamy pro jazyk 'cs'.
 * Vazby:  - Vyžaduje tabulku meta_column, meta_class a funkci dbo.f_generate_original.
 *         - V BuildListDb.txt se spouští za final_scripts.sql (po p_fix_meta_column).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
DECLARE @c_class uniqueidentifier = dbo.f_generate_original('meta_class', @sys_owner, 'sys_global_columns', '');
DECLARE @cls_hierarchy uniqueidentifier = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'hierarchy', '');

DECLARE @col_cs TABLE (
	column_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption varchar(200) NOT NULL,
	label varchar(200) NOT NULL,
	header varchar(200) NOT NULL,
	helptext varchar(max) NOT NULL
);

INSERT INTO @col_cs (column_name, caption, label, header, helptext) VALUES
-- 1. Standardní RAC, SSC, časové a auditní sloupce
('uuid',                        'Primární klíč řádku (uuid)',                      'UUID řádku',                             'UUID',                   'Fyzický primární klíč konkrétního řádku v databázové tabulce.'),
('object_owner',                'Vlastník objektu (object_owner)',                 'Vlastník (organizace)',                  'Vlastník',               'Identifikátor vlastnící organizace (tenanta); hodnota 0x00 označuje systémový záznam.'),
('original',                    'Logický identifikátor záznamu (original)',        'Originál (UUID objektu)',                'Originál',               'Společný logický identifikátor záznamu napříč jazykovými verzemi, koncepty a overridy.'),
('record_type',                 'Typ záznamu (record_type)',                       'Typ záznamu (A/L/D/H)',                  'Typ záz.',               'Určuje druh záznamu: A = schválený aktivní, L = jazyková mutace, D = koncept/návrh, H = historie.'),
('approval_status',             'Stav schválení (approval_status)',                'Stav schválení (A/D/F/R)',               'Schválení',              'Stav v rámci schvalovacího cyklu: A = schváleno, D = rozpracovaný koncept, F = předáno ke schválení, R = vráceno.'),
('draft_author',                'Autor návrhu (draft_author)',                     'Autor návrhu',                           'Autor návrhu',           'Identifikátor uživatelského účtu autora rozpracovaného konceptu nebo návrhu změny.'),
('approval_note',               'Poznámka schvalování (approval_note)',            'Poznámka schvalovatele / důvod',         'Pozn. schválení',        'Průvodní poznámka k návrhu nebo zdůvodnění schvalovatele při vrácení návrhu k přepracování.'),
('inactive',                    'Neaktivní záznam (inactive)',                     'Neaktivní (deaktivováno)',               'Neaktivní',              'Příznak dočasného nebo trvalého znepřístupnění záznamu pro běžný výběr bez jeho smazání.'),
('removed',                     'Zrušený záznam v koši (removed)',                 'Zrušený záznam (v koši)',                'Zrušeno',                'Příznak přesunutí záznamu do koše; po uplynutí doby days_in_trash je záznam automaticky odstraněn.'),
('language',                    'Jazyk záznamu (language)',                        'Jazyk',                                  'Jazyk',                  'Dvoupísmenný ISO kód jazyka záznamu nebo jazykové mutace (např. cs, en, sk, de).'),
('valid_from',                  'Platnost od (valid_from)',                        'Platnost od',                            'Platí od',               'Datum počátku platnosti záznamu.'),
('valid_to',                    'Platnost do (valid_to)',                          'Platnost do',                            'Platí do',               'Datum ukončení platnosti záznamu (prázdné pole znamená časově neomezenou platnost).'),
('valid_today',                 'Platné k pracovnímu datu (valid_today)',          'Platné dnes',                            'Platné',                 'Příznak udávající, zda je záznam platný k aktuálně nastavenému pracovnímu datu.'),
('is_template',                 'Příznak šablony (is_template)',                   'Slouží jako šablona',                    'Je šablona',             'Určuje, zda tento záznam slouží jako vzorová šablona pro vytváření dalších záznamů.'),
('template',                    'Zdrojová šablona (template)',                     'Vytvořeno ze šablony',                   'Šablona',                'Odkaz na vzorovou šablonu, ze které byl tento záznam naklonován.'),
('import_origin',               'Původ importu (import_origin)',                   'Původ záznamu z importu',                'Původ importu',          'Označení externího zdroje, balíčku nebo autora při hromadném importu dat (měkký audit).'),
('date_created',                'Datum vytvoření (date_created)',                  'Datum a čas vytvoření',                  'Vytvořeno',              'Přesné datum a čas prvotního založení záznamu.'),
('who_created',                 'Vytvořil uživatel (who_created)',                 'Vytvořil (relace)',                      'Vytvořil',               'Odkaz na přihlašovací relaci uživatele, který záznam původně vytvořil.'),
('date_modified',               'Datum poslední změny (date_modified)',            'Datum a čas poslední změny',             'Změněno',                'Přesné datum a čas poslední úpravy záznamu nebo jeho jazykové mutace.'),
('who_modified',                'Naposledy změnil (who_modified)',                 'Naposledy změnil (relace)',              'Změnil',                 'Odkaz na přihlašovací relaci uživatele, který provedl poslední úpravu záznamu.'),

-- 2. Společné identifikační, prezentační a stromové sloupce
('builtin_code',                'Unikátní kód (builtin_code)',                     'Kód záznamu (builtin_code)',             'Kód',                    'Unikátní technický identifikátor záznamu pro deterministický výpočet originálu (u nových záznamů se předvyplní z názvu).'),
('external_code',               'Externí kód (external_code)',                     'Externí kód (pro párování)',             'Ext. kód',               'Volitelný identifikátor pro párování záznamu s externími systémy, normami nebo katalogy.'),
('caption',                     'Zobrazovaný název (caption)',                     'Název',                                  'Název',                  'Hlavní zobrazovaný název položky (podporuje překlad do dalších jazyků).'),
('caption_plural',              'Název v množném čísle (caption_plural)',          'Název v množném čísle (nadpis seznamu)', 'Název (mn. č.)',         'Tvar názvu v množném čísle zobrazovaný jako nadpis přehledového seznamu v levém panelu.'),
('shortname',                   'Zkratka (shortname)',                             'Zkratka',                                'Zkratka',                'Zkrácené označení položky pro kompaktní výpisy, matice a štítky.'),
('title',                       'Titulek (title)',                                 'Titulek',                                'Titulek',                'Zobrazovaný titulek nebo nadpis záznamu.'),
('name',                        'Název / Jméno (name)',                            'Název / Jméno',                          'Název',                  'Technický nebo zobrazovaný název položky.'),
('description',                 'Popis (description)',                             'Podrobný popis',                         'Popis',                  'Podrobný popis významu a účelu položky (podporuje formátování Markdown / HTML).'),
('description_text',            'Popis (description_text)',                        'Podrobný popis',                         'Popis',                  'Podrobný metodický nebo věcný popis položky (podporuje formátování Markdown / HTML).'),
('helptext',                    'Text nápovědy (helptext)',                        'Nápověda (tooltip / pokyny)',            'Nápověda',               'Metodická nápověda nebo pokyny pro uživatele zobrazované u položky.'),
('help_text',                   'Text nápovědy (help_text)',                       'Nápověda (tooltip / pokyny)',            'Nápověda',               'Metodická nápověda nebo pokyny pro uživatele zobrazované u položky.'),
('note',                        'Poznámka (note)',                                 'Poznámka',                               'Poznámka',               'Doplňující interní komentář nebo poznámka k záznamu (podporuje formátování Markdown / HTML).'),
('editor_note',                 'Kontextová poznámka pro AI (editor_note)',        'Poznámka pro překladatele a AI',         'AI kontext',             'Sémantické upřesnění významu záznamu pro správný automatický i lidský překlad (nepřekládá se).'),
('svg_icon',                    'Vektorová ikona (svg_icon)',                      'Vektorová ikona (SVG)',                  'Ikona',                  'Vektorová ikona ve formátu SVG. Dvojklikem nebo tlačítkem Upravit ikonu otevřete modální editor s kontrolou syntaxe.'),
('color_code',                  'Kód barvy / semaforu (color_code)',               'Barva (HEX / CSS kód)',                  'Barva',                  'Kód barvy (např. #16A34A) pro vizuální zvýraznění položky nebo stupně škály.'),
('css_class',                   'CSS třída (css_class)',                           'Doplňková CSS třída',                    'CSS třída',              'Volitelná CSS třída pro vizuální stylování prvku nebo tlačítka v uživatelském rozhraní.'),
('parent_uuid',                 'Nadřízená položka ve stromu (parent_uuid)',       'Nadřízená složka / položka',             'Nadřízený uzel',         'Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).'),
('sort_code',                   'Řadicí kód (sort_code)',                          'Pořadí řazení (sort_code)',              'Pořadí',                 'Kód určující pořadí položky v seznamech a mezi sourozenci ve stromu (doporučeno číslovat po desítkách: 010, 020...).'),
('is_leaf',                     'Koncový uzel / list (is_leaf)',                   'Koncový uzel (list)',                    'List',                   'Zaškrtněte u koncové položky (listu). Odškrtněte u vnitřního uzlu (složky), pod který se budou vkládat podřízené položky.'),
('is_default',                  'Výchozí položka (is_default)',                    'Výchozí hodnota (předvybraná)',          'Výchozí',                'Zaškrtněte u položky, která má být automaticky předvybrána při zakládání nového záznamu.'),
('is_final',                    'Finální záznam bez overridu (is_final)',          'Zakázat přepis v organizaci (is_final)', 'Finální',                'Pokud je zaškrtnuto (1), klientské organizace nemohou měnit věcné nastavení záznamu (mohou pouze překládat texty).'),
('is_protected',                'Chráněná technická logika (is_protected)',        'Chráněný systémový prvek (is_protected)','Chráněno',               'Omezuje klientské úpravy čistě technických a architektonických vlastností záznamu.'),
('builtin',                     'Vestavěný záznam (builtin)',                      'Vestavěný systémový záznam',             'Vestavěný',              'Příznak standardního vestavěného záznamu dodávaného se systémem.'),
('instance_class_name',         'Název třídy instance (instance_class_name)',      'Třída instance objektu',                 'Třída instance',         'Specifické určení aplikační třídy pro instance dané kategorie.'),
('editor_role_uuid',            'Role editora (editor_role_uuid)',                 'Role oprávněná k editaci',               'Role editora',           'Odkaz na roli oprávněnou upravovat záznamy v této větvi hierarchie (dědí se do podřízených uzlů).'),

-- 3. Sloupce metadat (meta_object, meta_class, meta_column, meta_menu, meta_phrase, meta_codetable, meta_link_def)
('object_type',                 'Druh systémového objektu (object_type)',          'Druh objektu (T/V/F/P/C/M)',             'Druh obj.',              'Kategorie objektu: T = tabulka, V = pohled, F = funkce, P = PHP stránka/třída, C = globální slovník sloupců, M = modul.'),
('module',                      'Aplikační modul (module)',                        'Licenční modul',                         'Modul',                  'Kód aplikačního nebo licenčního modulu, ke kterému objekt nebo fráze přísluší.'),
('system_role',                 'Minimální systémová role (system_role)',          'Minimální požadovaná role (U/A/S/D)',    'Min. role',              'Minimální efektivní role nutná pro přístup: U = User, A = Admin organizace, S = Sysadmin, D = Developer.'),
('class_name',                  'Technický název třídy (class_name)',              'Kód logické třídy (class_name)',         'Kód třídy',              'Unikátní systémový identifikátor logické třídy v architektuře STI.'),
('storage_object',              'Fyzické úložiště (storage_object)',               'Fyzická úložná tabulka / pohled',        'Úložiště',               'Odkaz na fyzickou databázovou tabulku nebo pohled v meta_object, kde jsou uložena data této třídy.'),
('ancestor_class',              'Předek třídy pro dědičnost (ancestor_class)',     'Nadřazená třída (dědičnost STI)',        'Předek třídy',           'Odkaz na nadřazenou logickou třídu, ze které tato třída dědí definici sloupců a výchozí chování.'),
('days_in_trash',               'Dny uchování v koši (days_in_trash)',             'Dny v koši před smazáním',               'Dny v koši',             'Počet dnů uchování zrušených záznamů (removed = 1) v koši před automatickým fyzickým smazáním (0 = nikdy nemazat).'),
('role_editor',                 'Role editora třídy (role_editor)',                'Role oprávněná k editaci třídy',         'Role editora',           'Odkaz na roli oprávněnou k úpravám dat této logické třídy.'),
('parent_class',                'Patří ke třídě (parent_class)',                   'Nadřízená logická třída',                'Třída',                  'Strukturální vazba určující, ke které logické třídě tento sloupec patří.'),
('parent_order',                'Pořadí sloupce v tabulce (parent_order)',         'Pořadí sloupce ve třídě',                'Poř. sloupce',           'Číselné pořadí sloupce převzaté z fyzické struktury databázové tabulky.'),
('column_name',                 'Technický název sloupce (column_name)',           'Technický název sloupce',                'Sloupec',                'Přesný databázový identifikátor sloupce v úložné tabulce nebo pohledu.'),
('list_order',                  'Pořadí v levém seznamu (list_order)',             'Pořadí sloupce v seznamu (Master)',      'Poř. v seznamu',         'Pokud je vyplněno kladné číslo, sloupec se zobrazuje v přehledové tabulce levého panelu v tomto pořadí.'),
('label',                       'Popisek pole ve formuláři (label)',               'Popisek pole v detailu (label)',         'Popisek (Label)',        'Text návěstí zobrazovaný vlevo u vstupního pole v detailním editačním formuláři.'),
('header',                      'Záhlaví sloupce v tabulce (header)',              'Záhlaví sloupce v seznamu (header)',     'Záhlaví (Header)',       'Krátký nadpis sloupce používaný v záhlaví přehledových tabulek a seznamů.'),
('placeholder',                 'Zástupný text pole (placeholder)',                'Zástupný text v prázdném poli',          'Placeholder',            'Nápovědný text zobrazený šedě přímo uvnitř nevyplněného vstupního pole (překládá se).'),
('input_type',                  'Typ vstupního prvku (input_type)',                'Typ formulářového prvku',                'Typ prvku',              'Druh HTML prvku v detailu (text, textarea, number, date, checkbox).'),
('input_width',                 'Šířka vstupního pole (input_width)',              'Šířka vstupního pole (CSS)',             'Šířka pole',             'CSS šířka formulářového prvku v detailu (např. 100%, 180px, auto).'),
('input_rows',                  'Počet řádků textového pole (input_rows)',         'Počet řádků (pro textarea)',             'Řádků pole',             'Výška víceřádkového textového pole (textarea) udaná počtem viditelných řádků.'),
('max_length',                  'Maximální délka textu (max_length)',              'Maximální počet znaků',                  'Max. délka',             'Maximální povolený počet znaků v textovém poli odpovídající definici v databázi.'),
('translate',                   'Podporuje překlad (translate)',                   'Překládaný sloupec (jazykové verze L)',  'Překlad',                'Určuje, zda hodnota sloupce podléhá překladu do dalších jazyků přes záznamy typu L.'),
('history',                     'Sledovat historii (history)',                     'Ukládat historické verze (H)',           'Historie',               'Určuje, zda se při změně hodnoty sloupce má vytvářet historický snímek typu H.'),
('is_html',                     'Formátovaný text Markdown/HTML (is_html)',        'Formátovaný text (Markdown / HTML)',     'Rich-text',              'Zapíná podporu formátovaného textu s náhledem a modálním Toast UI Editorem (Markdown / HTML).'),
('is_mandatory',                'Povinná položka (is_mandatory)',                  'Povinné pole (vyžadováno)',              'Povinné',                'Označuje pole, které musí být před uložením formuláře vždy vyplněno.'),
('is_url',                      'Obsahuje URL adresu (is_url)',                    'Pole obsahuje URL odkaz',                'Je URL',                 'Validuje a formátuje vstupní pole jako webovou URL adresu.'),
('is_computed',                 'Vypočítávaný sloupec (is_computed)',              'Vypočítávaný sloupec (jen pro čtení)',   'Počítaný',               'Sloupec je počítán databází nebo aplikací a ve formuláři je vždy uzamčen pouze pro čtení.'),
('show_empty',                  'Zobrazovat i prázdné (show_empty)',               'Zobrazit pole i když je prázdné',        'Zobr. prázdné',          'Určuje, zda se má pole zobrazovat v přehledech i v případě nevyplněné hodnoty.'),
('hidden',                      'Skrytý sloupec (hidden)',                         'Skrýt pole v běžném formuláři',          'Skryté',                 'Technický sloupec, který se běžně nezobrazuje v editačních formulářích detailu.'),
('customizable',                'Povolit přizpůsobení (customizable)',             'Povolit klientské přizpůsobení',         'Upravitelné',            'Určuje, zda si může organizace (tenant) upravit vlastnosti tohoto sloupce.'),
('ancestor',                    'Předek sloupce (ancestor)',                       'Předek v globálním slovníku sloupců',    'Předek sloupce',         'Odkaz na výchozí definici sloupce ve třídě sys_global_columns, ze které sloupec dědí nevyplněné vlastnosti.'),
('referenced_codetable',        'Odkazovaný číselník (referenced_codetable)',      'Navázaný systémový číselník',            'Číselník',               'Kód číselníku v tabulce meta_codetable, ze kterého se plní rozevírací seznam (<select>) tohoto pole.'),
('referenced_class',            'Odkazovaná třída (referenced_class)',             'Navázaná logická třída (cizí klíč)',     'Odkazovaná třída',       'Odkaz na cílovou logickou třídu v meta_class pro výběr souvisejícího záznamu z rozevíracího seznamu.'),
('target_object',               'Cílová stránka (target_object)',                  'Cílová stránka aplikace (meta_object)',  'Cílová stránka',         'Odkaz na registrovanou PHP stránku (object_type = P), kterou otevře kliknutí na koncovou položku menu.'),
('url_parameters',              'Parametry URL (url_parameters)',                  'Dodatečné GET parametry URL',            'Parametry URL',          'Volitelné parametry připojované za URL cílové stránky (např. &hierarchy=...).'),
('target_url',                  'Externí URL odkaz (target_url)',                  'Externí nebo pevná URL adresa',          'Externí URL',            'Přímá URL adresa pro položky menu směřující mimo standardní aplikační stránky.'),
('target_window',               'Cílové okno odkazu (target_window)',              'Cílové okno prohlížeče (např. _blank)',  'Cílové okno',            'Určuje způsob otevření odkazu (prázdné = totéž okno, _blank = nová záložka prohlížeče).'),
('permanent',                   'Trvale viditelná položka (permanent)',            'Trvale zobrazit i prázdnou složku',      'Trvalé',                 'Ponechá složku menu viditelnou (jako neaktivní) i tehdy, když uživatel nemá přístup k žádné její podpoložce.'),
('source_code',                 'Zdrojová třída / stránka (source_code)',          'Zdrojová PHP třída / stránka',           'Zdroj (Třída)',          'Název PHP třídy nebo stránky, ke které textová fráze patří (global_phrase pro celosystémové fráze).'),
('codetable_name',              'Název číselníku (codetable_name)',                'Kód číselníku (codetable_name)',         'Kód číselníku',          'Technický identifikátor skupiny položek v tabulce meta_codetable.'),
('value_code',                  'Kód hodnoty číselníku (value_code)',              'Ukládaná hodnota (value_code)',          'Hodnota',                'Interní kód položky číselníku ukládaný do databáze při výběru v roletce.'),
('link_code',                   'Kód typu vazby (link_code)',                      'Technický kód typu vazby',               'Kód vazby',              'Unikátní systémový identifikátor definice vazby v meta_link_def.'),
('from_class',                  'Výchozí třída vazby (from_class)',                'Zdrojová třída vazby (odkud)',           'Zdrojová třída',         'Odkaz na logickou třídu v meta_class tvořící výchozí stranu vazby.'),
('to_class',                    'Cílová třída vazby (to_class)',                   'Cílová třída vazby (kam)',               'Cílová třída',           'Odkaz na logickou třídu v meta_class tvořící cílovou stranu vazby.'),
('caption_forward',             'Název vazby tam (caption_forward)',               'Název vazby ze zdroje na cíl',           'Vazba (tam)',            'Slovní popis vazby z pohledu zdrojového objektu (např. „Působí na“ nebo „Obsahuje“).'),
('caption_backward',            'Název vazby zpět (caption_backward)',             'Název vazby z cíle na zdroj',            'Vazba (zpět)',           'Slovní popis vazby z pohledu cílového objektu (např. „Je ohrožováno“ nebo „Patří do“).'),
('is_multiple',                 'Vícenásobná vazba (is_multiple)',                 'Povolit navázání více objektů (M:N)',    'Vícenásobná',            'Určuje, zda lze k jednomu zdrojovému záznamu připojit více cílových záznamů tohoto typu.'),
('transfer_roles',              'Přenos oprávnění (transfer_roles)',               'Přenášet editační oprávnění po vazbě',   'Přenos rolí',            'Určuje, zda vazba přenáší oprávnění k editaci ze zdrojového objektu na cílový.'),
('link_weight_enabled',         'Váha vazby povolena (link_weight_enabled)',       'Evidovat číselnou váhu na vazbě',        'Váha povolena',          'Povoluje zadávání kvantitativní váhy nebo priority přímo na instanci vazby v tabulce link.'),
('table_name',                  'Název tabulky (table_name)',                      'Fyzický název tabulky',                  'Tabulka',                'Název databázové tabulky v schématu dbo.'),
('key1_column',                 'První klíčový sloupec (key1_column)',             '1. klíčový sloupec originálu',           '1. klíč',                'Název prvního sloupce vstupujícího do výpočtu deterministického identifikátoru original.'),
('key2_column',                 'Druhý klíčový sloupec (key2_column)',             '2. klíčový sloupec originálu',           '2. klíč',                'Název volitelného druhého sloupce vstupujícího do výpočtu deterministického identifikátoru original.'),

-- 4. Sloupce modulu CRMM (hierarchie, škály, scénáře, protiopatření, vazby)
('multiple',                    'Vícenásobné přiřazení (multiple)',                'Povolit přiřazení více položek',         'Více položek',           'Určuje, zda cílový záznam může mít navázáno více položek z této hierarchie současně.'),
('leaf_only',                   'Pouze koncové uzly (leaf_only)',                  'Vazby pouze na koncové uzly (listy)',    'Jen listy',              'Určuje, zda lze cílové záznamy navazovat výhradně na koncové uzly (is_leaf = 1) této hierarchie.'),
('hierarchy',                   'Nadřazená hierarchie (hierarchy)',                'Sekundární hierarchie / sada štítků',    'Hierarchie',             'Odkaz na definici sekundární hierarchie nebo sady štítků (tagů) v tabulce hierarchy.'),
('scale',                       'Hodnotící škála (scale)',                         'Hodnotící škála',                        'Škála',                  'Odkaz na definici hodnotící škály v tabulce scale.'),
('scale_type',                  'Druh škály (scale_type)',                         'Druh měřené veličiny',                   'Druh škály',             'Určuje veličinu hodnocenou touto škálou (Hrozba, Zranitelnost, Dopad, Výsledné riziko).'),
('priority',                    'Priorita škály (priority)',                       'Priorita škály (0 = primární)',          'Priorita',               '0 = primární škála pro zadávání a výchozí zobrazení; > 0 = sekundární škála pro zpětný přepočet v reportech.'),
('initial_levels',              'Počet stupňů při založení (initial_levels)',      'Počet stupňů (pro vygenerování)',        'Počet stupňů',           'Počet rovnoměrných stupňů (2 až 20), které se automaticky vygenerují v intervalu 0 až 100 % při prvním uložení nové škály.'),
('threshold_value',             'Dolní práh intervalu v % (threshold_value)',      'Dolní práh intervalu (0–100 %)',         'Práh (%)',               'Dolní mez intervalu stupně v procentech (0 až 100 %). Určuje pořadí stupňů ve škále (nejnižší stupeň začíná na 0).'),
('score_value',                 'Hodnota skóre v % (score_value)',                 'Hodnota skóre (0–100 %)',                'Skóre (%)',              'Výpočtové skóre stupně v procentech (0 až 100 %). Musí ležet uvnitř intervalu daného stupně a tvořit rostoucí řadu.'),
('reduction_factor',            'Redukční faktor v % (reduction_factor)',          'Redukční faktor (0–100 %)',              'Redukce (%)',            'Udává míru snížení zbytkového rizika scénáře při aplikaci opatření (resp. váhu stavu opatření).'),
('risk_factor',                 'Rizikový faktor / práh v % (risk_factor)',        'Rizikový faktor / práh (0–100 %)',       'Rizikový práh (%)',      'Udává výsledné skóre rizika, pod které nesmí riziko scénáře klesnout, pokud opatření není implementováno.'),
('default_threat_score',        'Výchozí skóre hrozby (default_threat_score)',     'Výchozí velikost hrozby (skóre)',        'Výchozí skóre',          'Výchozí číselné ohodnocení velikosti hrozby předvyplňované při analýze scénářů.'),
('threat_uuid',                 'Působící hrozba (threat_uuid)',                   'Hrozba vyvolávající scénář',             'Hrozba',                 'Odkaz na hrozbu z katalogu hrozeb, která tuto rizikovou událost (scénář) způsobuje.'),
('asset_class_uuid',            'Cílová třída aktiv (asset_class_uuid)',           'Třída aktiv pro hodnocení dopadu',       'Třída aktiv',            'Odkaz na třídu aktiv v katalogu asset_class, u níž se hodnotí dopad tohoto scénáře.'),
('primary_asset_class',         'Primární třída aktiva (primary_asset_class)',     'Primární koncová třída aktiva',          'Třída aktiva',           'Odkaz na hlavní koncovou třídu aktiv (is_leaf = 1), podle které se aktivum třídí a zařazuje.'),
('residual_risk_min_score',     'Minimální reziduální riziko (residual_risk_min_score)', 'Minimální skóre zbytkového rizika', 'Min. rez. riziko',       'Spodní mez skóre reziduálního rizika scénáře, pod kterou zbytkové riziko neklesne ani po zavedení opatření.'),
('link_def',                    'Definice vazby (link_def)',                       'Typ vazby (meta_link_def)',              'Typ vazby',              'Odkaz na definici typu vazby v tabulce meta_link_def.'),
('from_object',                 'Zdrojový objekt vazby (from_object)',             'Zdrojový záznam vazby (odkud)',          'Zdroj vazby',            'Identifikátor (original) výchozího záznamu propojovaného vazbou.'),
('to_object',                   'Cílový objekt vazby (to_object)',                 'Cílový záznam vazby (kam)',              'Cíl vazby',              'Identifikátor (original) cílového záznamu propojovaného vazbou.'),
('ancestor_link',               'Zdrojová nadřazená vazba (ancestor_link)',        'Zdrojová vazba při dědění',              'Zdroj dědění',           'Identifikátor nadřízené vazby v tabulce link, ze které tato vazba vznikla děděním po hierarchii (0x00 = přímá vazba).'),
('link_weight',                 'Číselná váha vazby (link_weight)',                'Kvantitativní váha / priorita vazby',    'Váha vazby',             'Číselná hodnota vyjadřující váhu přenosu rizika nebo prioritu konkrétní vazby.'),
('is_derived',                  'Zděděná vazba (is_derived)',                      'Vazba odvozená děděním',                 'Zděděno',                'Příznak udávající, že vazba vznikla automatickou materializací dědění z nadřízeného uzlu hierarchie.'),

-- 5. Organizace, licence, nastavení CRMM a uživatelé
('login_domain',                'Přihlašovací SSO doména (login_domain)',          'Doména pro SSO přihlášení',              'SSO doména',             'Internetová doména organizace pro automatické rozpoznání domovského tenanta při SSO autentizaci.'),
('register_id',                 'Identifikační číslo (register_id)',               'IČO organizace',                         'IČO',                    'Oficiální identifikační číslo organizace v obchodním nebo živnostenském rejstříku.'),
('tax_id',                      'Daňové identifikační číslo (tax_id)',             'DIČ organizace',                         'DIČ',                    'Daňové identifikační číslo organizace pro účely fakturace a DPH.'),
('invoice_info',                'Fakturační údaje (invoice_info)',                 'Fakturační a bankovní údaje',            'Fakturace',              'Doplňující fakturační údaje, bankovní spojení nebo poznámka na fakturu.'),
('address_name',                'Název v adrese (address_name)',                   'Oficiální název v adrese sídla',         'Název (adresa)',         'Obchodní jméno nebo doplněk názvu uváděný v poštovní adrese sídla.'),
('address_street',              'Ulice a číslo (address_street)',                  'Ulice a číslo popisné / orientační',     'Ulice',                  'Ulice a číslo domu sídla organizace.'),
('address_city',                'Město / obec (address_city)',                     'Město / Obec',                           'Město',                  'Město nebo obec sídla organizace.'),
('address_zip',                 'PSČ (address_zip)',                               'Poštovní směrovací číslo (PSČ)',         'PSČ',                    'Poštovní směrovací číslo adresy sídla.'),
('address_state',               'Stát (address_state)',                            'Stát / Země',                            'Stát',                   'Stát, ve kterém se nachází sídlo organizace.'),
('www_address',                 'Webová stránka (www_address)',                    'Webová adresa (URL)',                    'Web (WWW)',              'Oficiální webová prezentace organizace.'),
('preferred_language',          'Výchozí jazyk organizace (preferred_language)',   'Preferovaný výchozí jazyk',              'Výchozí jazyk',          'Výchozí jazyk prostředí a dat pro nově zakládané uživatele a záznamy organizace.'),
('currency_unit',               'Měnová jednotka (currency_unit)',                 'Používaná měnová jednotka',              'Měna',                   'Označení měnové jednotky pro finanční hodnocení dopadů a rizik (např. tis. Kč, EUR).'),
('currency_digits',             'Desetinná místa měny (currency_digits)',          'Počet desetinných míst měny',            'Des. místa měny',        'Počet zobrazovaných desetinných míst u finančních částek.'),
('currency_before',             'Měna před částkou (currency_before)',             'Zobrazovat symbol měny před číslem',     'Měna před',              'Pokud je zaškrtnuto, symbol měny se vypisuje před číselnou částkou (např. € 100).'),
('format_date',                 'Formát data (format_date)',                       'Formát zobrazení data',                  'Formát data',            'Maska pro formátování kalendářního data v uživatelském rozhraní (např. dd.MM.yyyy).'),
('format_time',                 'Formát času (format_time)',                       'Formát zobrazení času',                  'Formát času',            'Maska pro formátování času v uživatelském rozhraní (např. HH:mm:ss).'),
('time_zone',                   'Časové pásmo (time_zone)',                        'Časové pásmo organizace',                'Časové pásmo',           'Identifikátor časového pásma organizace (např. Europe/Prague).'),
('thousand_separator',          'Oddělovač tisíců (thousand_separator)',           'Znak oddělovače tisíců',                 'Odd. tisíců',            'Znak používaný pro oddělení tisíců při výpisu čísel (např. mezera).'),
('decimal_separator',           'Desetinný oddělovač (decimal_separator)',         'Znak desetinného oddělovače',            'Des. oddělovač',         'Znak oddělující celou a desetinnou část čísla (čárka nebo tečka).'),
('export_delimiter',            'Oddělovač polí v CSV (export_delimiter)',         'Výchozí oddělovač pro CSV export',       'CSV oddělovač',          'Znak oddělující sloupce v exportovaných CSV souborech (standardně středník ;).'),
('max_threat_score',            'Maximální skóre hrozby (max_threat_score)',       'Horní limit skóre velikosti hrozby',     'Max. hrozba',            'Nejvyšší povolená hodnota skóre při hodnocení velikosti hrozby v organizaci.'),
('max_vulnerability_score',     'Maximální skóre zranitelnosti (max_vulnerability_score)', 'Horní limit skóre zranitelnosti', 'Max. zranitelnost',      'Nejvyšší povolená hodnota skóre při hodnocení zranitelnosti v organizaci.'),
('max_impact_score',            'Maximální skóre dopadu (max_impact_score)',       'Horní limit skóre velikosti dopadu',     'Max. dopad',             'Nejvyšší povolená hodnota skóre při hodnocení velikosti dopadu v organizaci.'),
('max_risk_score',              'Maximální skóre rizika (max_risk_score)',         'Horní limit skóre výsledného rizika',    'Max. riziko',            'Nejvyšší hodnota skóre výsledného rizika v metodice organizace.'),
('max_impact_financial',        'Finanční hodnota max. dopadu (max_impact_financial)', 'Finanční vyjádření nejvyššího dopadu','Max. dopad (fin.)',      'Finanční částka v měnové jednotce organizace odpovídající nejvyššímu stupni dopadu.'),
('residual_risk_min_financial', 'Finanční práh zbytkového rizika (residual_risk_min_financial)', 'Zanedbatelná roční ztráta (skóre 1)', 'Min. rez. (fin.)', 'Finanční hodnota ročních ztrát v měně organizace považovaná za zanedbatelné zbytkové riziko.'),
('evaluation_method',           'Metoda hodnocení rizik (evaluation_method)',      'Zvolená metodika hodnocení CRMM',        'Metoda hodnocení',       'Kód metodiky nebo výpočtového modelu používaného pro vyhodnocení rizik.'),
('logo_data',                   'Binární data loga (logo_data)',                   'Soubor loga organizace',                 'Logo (data)',            'Binární obsah grafického souboru s logotypem organizace.'),
('logo_filename',               'Název souboru loga (logo_filename)',              'Původní název souboru loga',             'Soubor loga',            'Název nahraného grafického souboru s logotypem organizace.'),
('logo_mime_type',              'MIME typ loga (logo_mime_type)',                  'Formát obrázku loga (MIME)',             'MIME typ loga',          'Internetový typ média nahraného loga (např. image/png, image/svg+xml).'),
('licence_state',               'Stav licence (licence_state)',                    'Stav licenčního záznamu',                'Stav licence',           'Životní cyklus licence: DRAFT = koncept, APPROVED = schváleno k aktivaci, PROCESSED = aktivní, REJECTED = zamítnuto.'),
('licence_level',               'Úroveň licence (licence_level)',                  'Úroveň licence organizace',              'Úroveň licence',         'Rozsah oprávnění organizace: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
('login_disabled',              'Zablokovat přihlášení (login_disabled)',          'Zablokovat přihlašování organizaci',     'Přihlášení blok.',       'Pokud je zaškrtnuto, žádný uživatel se nemůže přihlásit do kontextu této organizace.'),
('organization_uuid',           'Cílová organizace (organization_uuid)',           'Organizace (UUID)',                      'Organizace',             'Odkaz na originální identifikátor organizace v tabulce organization.'),
('organization',                'Aktivní organizace (organization)',               'Organizace',                             'Organizace',             'Identifikátor aktivní organizace v relaci nebo pohledu.'),
('organization_name',           'Název organizace (organization_name)',            'Název organizace',                       'Název organizace',       'Zobrazovaný název organizace.'),
('organization_note',           'Poznámka k licenci (organization_note)',          'Interní poznámka k licenci organizace',  'Pozn. k licenci',        'Doplňující poznámka vydavatele licence k licencované organizaci.'),
('server_licence',              'Licence serveru (server_licence)',                'Identifikátor serverové licence',        'Licence serveru',        'Kód nebo klíč serverové licence.'),
('authorization_code',          'Autorizační kód (authorization_code)',            'Autorizační kód aktivace',               'Autorizační kód',        'Unikátní identifikátor pro autorizaci licenčního požadavku.'),
('activation_date',             'Datum aktivace (activation_date)',                'Datum aktivace licence',                 'Aktivováno dne',         'Datum, kdy byla licence zpracována a organizace aktivována.'),
('admin_login',                 'Login správce organizace (admin_login)',          'Login prvního administrátora',           'Login admina',           'Přihlašovací jméno výchozího administrátora zakládané organizace.'),
('admin_first_name',            'Jméno správce (admin_first_name)',                'Křestní jméno administrátora',           'Jméno admina',           'Křestní jméno výchozího administrátora organizace.'),
('admin_last_name',             'Příjmení správce (admin_last_name)',              'Příjmení administrátora',                'Příjmení admina',        'Příjmení výchozího administrátora organizace.'),
('admin_email',                 'E-mail správce (admin_email)',                    'E-mail administrátora organizace',       'E-mail admina',          'Kontaktní e-mailová adresa administrátora organizace.'),
('digital_signature',           'Digitální podpis (digital_signature)',            'Kontrolní digitální podpis',             'Podpis',                 'Binární kontrolní součet nebo podpis záznamu.'),
('login_name',                  'Přihlašovací jméno (login_name)',                 'Přihlašovací jméno (login)',             'Login',                  'Unikátní přihlašovací jméno uživatele v systému.'),
('email',                       'E-mailová adresa (email)',                        'E-mailová adresa',                       'E-mail',                 'Kontaktní a autentizační e-mailová adresa uživatele.'),
('password_hash',               'Hash hesla (password_hash)',                      'Kryptografický hash hesla',              'Hash hesla',             'Bezpečně uložený bcrypt/argon2 otisk hesla uživatele.'),
('allow_local_login',           'Povolit lokální přihlášení (allow_local_login)',  'Povolit přihlášení jménem a heslem',     'Lokální login',          'Určuje, zda se uživatel smí přihlásit lokálním heslem (při vypnutí je vyžadováno SSO).'),
('is_system_admin',             'Systémový administrátor (is_system_admin)',       'Globální role Sysadmin (S)',             'Sysadmin',               'Opravňuje uživatele ke vstupu do systémové organizace (0x00) a správě celého serveru.'),
('is_developer',                'Vývojář systému (is_developer)',                  'Globální role Developer (D)',            'Developer',              'Opravňuje uživatele k úpravám systémových metadat, struktur a vývojářských balíčků.'),
('require_password_change',     'Vyžadovat změnu hesla (require_password_change)', 'Vynutit změnu hesla při přihlášení',     'Změna hesla',            'Při příštím přihlášení vyzve uživatele k nastavení nového hesla.'),
('failed_login_attempts',       'Neúspěšné pokusy (failed_login_attempts)',        'Počet neúspěšných pokusů o přihlášení',  'Chybné pokusy',          'Počítadlo po sobě jdoucích chybných zadání hesla (při dosažení limitu se účet dočasně uzamkne).'),
('locked_until',                'Uzamčeno do (locked_until)',                      'Účet dočasně uzamčen do',                'Uzamčeno do',            'Datum a čas, do kdy je přihlášení k účtu zablokováno po opakovaném chybném zadání hesla.'),
('last_login_date',             'Poslední přihlášení (last_login_date)',           'Datum a čas posledního přihlášení',      'Posl. přihlášení',       'Časová značka posledního úspěšného přihlášení uživatele do systému.'),
('last_password_change',        'Poslední změna hesla (last_password_change)',     'Datum a čas poslední změny hesla',       'Změna hesla dne',        'Časová značka poslední změny hesla uživatelského účtu.'),
('mfa_enabled',                 'Dvoufaktorové ověření (mfa_enabled)',             'Vyžadovat vícefaktorové ověření (MFA)',  'MFA zapnuto',            'Příznak aktivace dvoufaktorové autentizace u účtu uživatele.'),
('mfa_secret',                  'Tajný klíč MFA (mfa_secret)',                     'Kryptografický klíč pro MFA',            'MFA klíč',               'Interní tajný klíč pro generování jednorázových TOTP kódů.'),
('last_login_organization',     'Poslední organizace (last_login_organization)',   'Naposledy navštívená organizace',        'Posl. organizace',       'Odkaz na organizaci, ve které uživatel pracoval při svém posledním přihlášení.'),
('user_title_before',           'Titul před jménem (user_title_before)',           'Titul před jménem',                      'Titul před',             'Akademický nebo profesní titul uváděný před jménem (např. Ing., Mgr.).'),
('first_name',                  'Křestní jméno (first_name)',                      'Křestní jméno',                          'Jméno',                  'Křestní jméno osoby.'),
('last_name',                   'Příjmení (last_name)',                            'Příjmení',                               'Příjmení',               'Příjmení osoby.'),
('user_title_after',            'Titul za jménem (user_title_after)',              'Titul za jménem',                        'Titul za',               'Akademický titul uváděný za příjmením (např. Ph.D., CSc.).'),
('phone',                       'Telefon (phone)',                                 'Telefonní číslo (pevná linka)',          'Telefon',                'Kontaktní telefonní číslo uživatele.'),
('mobile',                      'Mobilní telefon (mobile)',                        'Mobilní telefon',                        'Mobil',                  'Číslo mobilního telefonu uživatele.'),
('user_account_uuid',           'Uživatelský účet (user_account_uuid)',            'Uživatel (UUID účtu)',                   'Uživatel (UUID)',        'Odkaz na globální účet uživatele v tabulce user_account.'),
('user_account',                'Uživatelský účet (user_account)',                 'Uživatelský účet',                       'Uživatel',               'Odkaz na účet uživatele.'),
('is_orgadmin',                 'Administrátor organizace (is_orgadmin)',          'Administrátor této organizace (role A)', 'Admin org.',             'Opravňuje uživatele spravovat uživatele, přístupy a nastavení v rámci dané organizace.'),
('last_role',                   'Poslední zvolená role (last_role)',               'Naposledy použitá role (U/A/S/D)',       'Posl. role',             'Naposledy zvolená efektivní role uživatele v dané organizaci.'),
('right_translate',             'Právo překládat (right_translate)',               'Oprávnění pořizovat překlady',           'Právo překladu',         'Opravňuje uživatele ukládat jazykové překlady (v garantující organizaci i globálně pro systém).'),
('department_name',             'Oddělení / útvar (department_name)',              'Oddělení / organizační útvar',           'Oddělení',               'Název oddělení nebo útvaru, do kterého je uživatel v organizaci zařazen.'),
('job_title',                   'Pracovní pozice (job_title)',                     'Pracovní pozice / funkce',               'Pozice',                 'Název pracovní pozice nebo funkce uživatele v organizaci.'),
('manager_uuid',                'Nadřízený pracovník (manager_uuid)',              'Přímý nadřízený (manažer)',              'Nadřízený',              'Odkaz na uživatelský účet přímého nadřízeného v organizaci.'),
('working_date',                'Pracovní datum (working_date)',                   'Osobní pracovní datum (prázdné = dnes)', 'Pracovní datum',         'Datum, ke kterému se vyhodnocuje časová platnost záznamů v relaci uživatele.'),

-- 6. Relace, audit přihlášení, tokeny, systémové konstanty, provozní deník a systémové pohledy
('fallback_language',           'Záložní jazyk (fallback_language)',               'Nadřazený záložní jazyk (fallback)',     'Fallback jazyk',         'Kód náhradního jazyka, který se použije, pokud text není do daného jazyka přeložen.'),
('translator_org',              'Garant překladu (translator_org)',                'Organizace garantující globální překlad','Garant překladu',        'Organizace, jejíž překladatelé mají právo zapisovat překlady tohoto jazyka přímo do systémových záznamů (0x00).'),
('fallback_order',              'Pořadí v řetězci dědičnosti (fallback_order)',    'Pořadí jazykového fallbacku',            'Poř. fallbacku',         'Vypočtené pořadí jazyka v řetězci dědičnosti pro aktuální relaci (1 = aktivní jazyk, < 1000 = v řetězci).'),
('assumed_role',                'Zvolená role v relaci (assumed_role)',            'Efektivní role v relaci (U/A/S/D)',      'Role v relaci',          'Role, pod kterou uživatel v dané přihlašovací relaci pracoval.'),
('active_role',                 'Aktivní role (active_role)',                      'Aktivní role sezení (U/A/S/D)',          'Aktivní role',           'Efektivní aplikační role v běžícím sezení.'),
('login_time',                  'Čas přihlášení (login_time)',                     'Datum a čas přihlášení',                 'Přihlášení',             'Okamžik zahájení přihlašovací relace uživatele.'),
('last_request_time',           'Poslední aktivita (last_request_time)',           'Čas posledního požadavku v relaci',      'Posl. aktivita',         'Časová značka posledního HTTP požadavku zaznamenaného v dané relaci.'),
('logout_time',                 'Čas odhlášení / expirace (logout_time)',          'Datum a čas odhlášení nebo expirace',    'Odhlášení',              'Okamžik řádného odhlášení uživatele nebo automatického vypršení neaktivní relace.'),
('ip_address',                  'IP adresa (ip_address)',                          'Klientská IP adresa',                    'IP adresa',              'Síťová IP adresa klienta (včetně případné cesty X-Forwarded-For).'),
('client_ip',                   'IP adresa klienta (client_ip)',                   'IP adresa klienta',                      'IP klienta',             'Síťová IP adresa klientského prohlížeče.'),
('request_ip',                  'IP adresa žádosti (request_ip)',                  'IP adresa žadatele o token',             'IP žádosti',             'IP adresa, ze které bylo vyžádáno vygenerování bezpečnostního tokenu.'),
('selector',                    'Veřejný selektor tokenu (selector)',              'Identifikátor tokenu (selector)',        'Selektor',               'Veřejná část trvalého přihlašovacího tokenu sloužící k rychlému vyhledání v databázi.'),
('hashed_validator',            'Hash validátoru (hashed_validator)',              'SHA-256 hash tajného validátoru',        'Hash validátoru',        'Kryptografický otisk tajné části trvalého přihlašovacího tokenu.'),
('expires',                     'Expirace tokenu (expires)',                       'Platnost tokenu do',                     'Expiruje',               'Datum a čas vypršení platnosti trvalého přihlašovacího tokenu.'),
('expires_at',                  'Vyprší dne (expires_at)',                         'Okamžik vypršení platnosti tokenu',      'Expiruje v',             'Přesný čas, kdy jednorázový bezpečnostní token přestává platit.'),
('user_agent',                  'Identifikace prohlížeče (user_agent)',            'Prohlížeč a operační systém (User-Agent)','Prohlížeč',             'Textový řetězec identifikující prohlížeč a zařízení uživatele.'),
('last_used',                   'Naposledy použito (last_used)',                   'Čas posledního uplatnění tokenu',        'Naposledy použito',      'Datum a čas posledního automatického přihlášení pomocí tohoto tokenu.'),
('token_hash',                  'Hash tokenu (token_hash)',                        'Kryptografický otisk tokenu',            'Hash tokenu',            'SHA-256 hash jednorázového bezpečnostního tokenu.'),
('token_purpose',               'Účel tokenu (token_purpose)',                     'Účel bezpečnostního tokenu',             'Účel tokenu',            'Určuje kontext použití tokenu (PASSWORD_RESET, ACTIVATION, MFA).'),
('is_used',                     'Token již použit (is_used)',                      'Token byl již uplatněn',                 'Použito',                'Příznak zabraňující opakovanému použití jednorázového tokenu.'),
('spid',                        'ID procesu SQL Serveru (spid)',                   'Číslo procesu SQL Serveru (@@SPID)',     'SPID',                   'Identifikátor serverového procesu databázového spojení (@@SPID).'),
('wwwsession',                  'ID webové relace (wwwsession)',                   'Identifikátor relace prohlížeče (SID)',  'Web Session',            'Unikátní identifikátor relace prohlížeče (PHP session_id).'),
('login_session_uuid',          'ID auditní relace (login_session_uuid)',          'Odkaz do audit_login_session',           'ID relace',              'Unikátní identifikátor přihlášení v tabulce audit_login_session pro auditní stopu.'),
('user_name',                   'Uživatelské jméno v relaci (user_name)',          'Přihlašovací jméno uživatele',           'Login',                  'Přihlašovací jméno uživatele v aktivní relaci.'),
('display_name',                'Zobrazované jméno (display_name)',                'Celé jméno přihlášeného uživatele',      'Jméno uživatele',        'Zobrazované celé jméno uživatele v horní liště aplikace.'),
('login_date',                  'Čas přihlášení relace (login_date)',              'Čas vzniku relace',                      'Přihlášeno',             'Datum a čas vytvoření webové relace.'),
('request_date',                'Čas posledního požadavku (request_date)',         'Čas posledního HTTP požadavku',          'Posl. požadavek',        'Čas poslední aktivity webové relace pro hlídání timeoutu.'),
('session_log',                 'Kód logování relace (session_log)',               'Příznak logování relace',                'Log relace',             'Interní příznak úrovně logování relace.'),
('debug',                       'Ladicí režim (debug)',                            'Zapnout ladicí výpisy (debug)',          'Debug',                  'Příznak aktivace vývojářského ladicího režimu v relaci.'),
('servername',                  'Název serveru (servername)',                      'Název serveru',                          'Server',                 'Síťový název databázového nebo aplikačního serveru.'),
('application',                 'Název aplikace (application)',                    'Identifikátor klientské aplikace',       'Aplikace',               'Název aplikace přistupující k databázi.'),
('change_context_allowed',      'Povolena změna kontextu (change_context_allowed)','Povolit přepínání organizace / role',    'Změna kontextu',         'Určuje, zda má uživatel v horní liště k dispozici odkaz pro přepnutí organizace nebo role.'),
('database_version',            'Verze databáze (database_version)',               'Aktuální verze schématu databáze',       'Verze DB',               'Označení verze databázového schématu ve formátu RR.MM.DD.N řízené skriptem changes_YYYY.sql.'),
('app_version',                 'Verze aplikace (app_version)',                    'Verze aplikačního kódu',                 'Verze aplikace',         'Označení verze nasazených PHP skriptů aplikace.'),
('database_state',              'Stav databáze (database_state)',                  'Provozní stav databáze',                 'Stav DB',                'Jednoznakový indikátor provozního stavu databáze.'),
('sysadmin_email',              'E-mail systémového správce (sysadmin_email)',     'E-mail hlavního správce systému',        'E-mail sysadmina',       'E-mailová adresa pro nouzovou obnovu hesla účtu admin a systémová upozornění.'),
('system_admin_pwd',            'Hash nouzového hesla (system_admin_pwd)',         'Hash hesla nouzového účtu admin',        'Nouzové heslo',          'Bcrypt/argon2 hash hesla pro offline/break-glass přihlášení systémového administrátora.'),
('login_with_token',            'Vyžadovat token při přihlášení (login_with_token)','Globálně vyžadovat autentizační token', 'Login s tokenem',        'Globální přepínač vynucující přihlašování s bezpečnostním tokenem.'),
('ldap_root',                   'Kořenová cesta LDAP (ldap_root)',                 'Kořenová cesta Active Directory / LDAP', 'LDAP kořen',             'Konfigurační cesta pro integraci s adresářovou službou Active Directory / LDAP.'),
('application_info_file',       'Soubor informací o aplikaci (application_info_file)', 'Cesta k souboru s informacemi o verzi', 'Info soubor',         'Cesta k souboru se zprávou pro uživatele (MOTD / release notes).'),
('smtp_server',                 'SMTP server (smtp_server)',                       'Adresa odchozího poštovního serveru',    'SMTP server',            'Doménový název nebo IP adresa SMTP serveru pro odesílání systémových e-mailů.'),
('smtp_port',                   'SMTP port (smtp_port)',                           'Číslo portu SMTP serveru',               'SMTP port',              'Číslo síťového portu SMTP serveru (např. 25, 465, 587, 2525).'),
('email_sender_name',           'Jméno odesílatele e-mailů (email_sender_name)',   'Zobrazované jméno odesílatele e-mailů',  'Jméno odesílatele',      'Jméno uváděné v hlavičce From u systémových e-mailů.'),
('email_sender_address',        'Adresa odesílatele (email_sender_address)',       'E-mailová adresa odesílatele',           'E-mail odesílatele',     'E-mailová adresa uváděná jako odesílatel systémových zpráv.'),
('sysmsg_recipients',           'Příjemci systémových zpráv (sysmsg_recipients)',  'Seznam příjemců servisních hlášení',     'Příjemci hlášení',       'Seznam e-mailových adres pro doručování automatických provozních a chybových zpráv.'),
('backup_path',                 'Cesta pro zálohy (backup_path)',                  'Adresář pro ukládání záloh databáze',    'Cesta záloh',            'Fyzická cesta na disku serveru určená pro soubory záloh databáze.'),
('backup_full_date',            'Datum plné zálohy (backup_full_date)',            'Čas poslední plné zálohy databáze',      'Plná záloha dne',        'Datum a čas posledního provedení úplné (FULL) zálohy databáze.'),
('backup_full_days',            'Perioda plné zálohy (backup_full_days)',          'Interval plné zálohy ve dnech',          'Perioda plné zál.',      'Počet dnů mezi automatickými úplnými zálohami databáze.'),
('backup_diff_count',           'Počet rozdílových záloh (backup_diff_count)',     'Počet rozdílových záloh v cyklu',        'Počet diff záloh',       'Nastavený počet diferenciálních záloh mezi plnými zálohami.'),
('backup_diff_counter',         'Počítadlo rozdílových záloh (backup_diff_counter)','Aktuální pořadí rozdílové zálohy',      'Čítač diff záloh',       'Interní počítadlo provedených diferenciálních záloh.'),
('backup_log_date',             'Datum zálohy logu (backup_log_date)',             'Čas poslední zálohy transakčního logu',  'Záloha logu dne',        'Datum a čas poslední zálohy transakčního logu.'),
('backup_log_hours',            'Perioda zálohy logu (backup_log_hours)',          'Interval zálohy logu v hodinách',        'Perioda logu (h)',       'Počet hodin mezi zálohami transakčního logu.'),
('copyonly_backup_switch',      'Režim COPY_ONLY zálohy (copyonly_backup_switch)', 'Používat při zálohování příznak COPY_ONLY','COPY_ONLY záloha',     'Zabraňuje narušení sekvence LSN řetězce při souběžném externím zálohování.'),
('session_timeout',             'Timeout relace v minutách (session_timeout)',     'Doba neaktivity před odhlášením (min)',  'Timeout (min)',          'Počet minut neaktivity uživatele, po jejichž uplynutí webová relace automaticky expiruje.'),
('current_year',                'Aktuální rok (current_year)',                     'Aktuální kalendářní rok',                'Aktuální rok',           'Výchozí kalendářní rok v systémovém nastavení.'),
('machine_guid',                'Identifikátor stroje (machine_guid)',             'Unikátní identifikátor serveru',         'ID stroje',              'Hardwarový nebo systémový identifikátor serveru.'),
('right_profadmin_enabled',     'Režim profesního admina (right_profadmin_enabled)','Povolit globální správu metodiky',      'Profadmin povolen',      'Systémový přepínač režimu správy metodiky.'),
('id',                          'Pořadové ID (id)',                                'Číselný identifikátor záznamu (ID)',     'ID',                     'Automaticky generované pořadové číslo záznamu (IDENTITY).'),
('original_login',              'Přihlašovací účet SQL (original_login)',          'Původní přihlašovací účet SQL Serveru',  'SQL Login',              'Systémové jméno účtu SQL Serveru (original_login()), pod kterým byl skript spuštěn.'),
('date',                        'Datum a čas (date)',                              'Datum a čas záznamu',                    'Datum a čas',            'Datum a čas pořízení záznamu v provozním deníku.'),
('version',                     'Verze (version)',                                 'Označení verze',                         'Verze',                  'Číslo nebo časové označení verze databáze, skriptu či datového balíčku.'),
('content',                     'Obsah / poznámka (content)',                      'Obsah záznamu / popis provedené změny',  'Obsah / Poznámka',       'Textový popis provedené operace, upgradu nebo importovaného balíčku.'),
('counter',                     'Pořadí zprávy (counter)',                         'Pořadové číslo zprávy',                  'Pořadí',                 'Automatické pořadové číslo zprávy v tabulce request_message.'),
('code',                        'Kód (code)',                                      'Kód položky / zprávy',                   'Kód',                    'Technický kód zprávy nebo položky.'),
('severity',                    'Závažnost zprávy (severity)',                     'Úroveň závažnosti (0=Info,1=OK,2=Var,3=Chyba)', 'Závažnost',       'Číselná závažnost zprávy: 0 = informace, 1 = potvrzení OK, 2 = varování, 3 = kritická chyba.'),
('color',                       'Barva textu (color)',                             'Barva zobrazení zprávy',                 'Barva',                  'Explicitní barva pro výpis řádku zprávy.'),
('icon',                        'Ikona zprávy (icon)',                             'Ikona zprávy',                           'Ikona',                  'Označení ikony u zprávy požadavku.'),
('msgtext',                     'Text zprávy (msgtext)',                           'Hlavní text zprávy',                     'Zpráva',                 'Text stavového nebo chybového hlášení zobrazeného uživateli.'),
('obj_type',                    'Typ dotčeného objektu (obj_type)',                'Typ objektu',                            'Typ objektu',            'Druh objektu nebo tabulky, ke které se zpráva vztahuje.'),
('obj_name',                    'Název dotčeného objektu (obj_name)',              'Označení konkrétního objektu / položky', 'Název objektu',          'Konkrétní identifikátor nebo název záznamu, kterého se zpráva týká.'),
('indent',                      'Úroveň odsazení (indent)',                        'Odsazení řádku zprávy',                  'Odsazení',               'Číselná úroveň grafického odsazení zprávy zleva.'),
('style',                       'CSS styl řádku (style)',                          'Inline CSS styl výpisu',                 'CSS styl',               'Doplňkový CSS styl pro vykreslení řádku zprávy.'),
('intvalue',                    'Číselná hodnota (intvalue)',                      'Číselná hodnota / počet řádků',          'Čís. hodnota',           'Celočíselná hodnota spojená se zprávou nebo proměnnou (např. počet zpracovaných záznamů).'),
('charvalue',                   'Textová hodnota (charvalue)',                     'Textový detail / hodnota proměnné',      'Text. hodnota',          'Textový detail zprávy nebo hodnota proměnné požadavku.'),
('varname',                     'Název proměnné (varname)',                        'Název proměnné požadavku',               'Proměnná',               'Jméno proměnné uložené v tabulce request_variable.'),
('uuidvalue',                   'UUID hodnota (uuidvalue)',                        'Hodnota typu UUID',                      'UUID hodnota',           'Identifikátor UUID uložený v proměnné požadavku.'),
('param_order',                 'Pořadí parametru (param_order)',                  'Pořadí parametru v souboru',             'Poř. param.',            'Pořadové číslo hlavičkového parametru v importovaném CSV souboru.'),
('parameter_code',              'Kód parametru (parameter_code)',                  'Technický název parametru balíčku',      'Kód parametru',          'Identifikátor parametru v hlavičce CSV importu (např. package_name, verify_data, signature).'),
('parameter_value',             'Hodnota parametru (parameter_value)',             'Hodnota parametru balíčku',              'Hodnota param.',         'Textová hodnota parametru načtená z hlavičky CSV souboru.'),
('table_id',                    'ID tabulky v importu (table_id)',                 'Pořadové číslo tabulky v CSV',           'ID tabulky',             'Pořadové číslo bloku tabulky v rámci probíhajícího CSV importu.'),
('row_count',                   'Počet řádků (row_count)',                         'Počet datových řádků v bloku',           'Počet řádků',            'Celkový počet načtených datových řádků dané tabulky v CSV importu.'),
('column_id',                   'ID sloupce v importu (column_id)',                'Globální pořadové číslo sloupce v CSV',  'ID sloupce',             'Unikátní pořadové číslo sloupce v rámci staging tabulek CSV importu.'),
('row_id',                      'Číslo řádku v importu (row_id)',                  'Pořadové číslo datového řádku',          'Č. řádku',               'Pořadové číslo datového řádku v rámci importované tabulky.'),
('cell_value',                  'Hodnota buňky (cell_value)',                      'Textová hodnota buňky z CSV',            'Hodnota buňky',          'Obsah neprázdné buňky načtený z importovaného CSV souboru.'),
('row_num',                     'Číslo řádku (row_num)',                           'Pořadové číslo řádku (0..1024)',         'Č. řádku',               'Sekvenční číslo v pomocné systémové tabulce rowgenerator.'),
('access_uuid',                 'ID přístupu (access_uuid)',                       'Originál záznamu přístupu',              'ID přístupu',            'Logický identifikátor záznamu v user_organization_access.'),
('last_login_org',              'Poslední organizace (last_login_org)',            'Naposledy přihlášená organizace',        'Posl. org.',             'Organizace, do které se uživatel naposledy přihlásil.'),
('current_organization',        'Aktuální organizace relace (current_organization)','Právě zvolená organizace v relaci',     'Aktuální org.',          'Organizace aktivní v právě běžící relaci @@SPID.'),
('tabname',                     'Název tabulky (tabname)',                         'Název tabulky / pohledu',                'Tabulka',                'Systémový název tabulky nebo pohledu v databázovém katalogu.'),
('colid',                       'ID sloupce (colid)',                              'Pořadové číslo sloupce v tabulce',       'ID sloupce',             'Interní pořadové číslo sloupce v systémovém katalogu syscolumns.'),
('colname',                     'Název sloupce (colname)',                         'Systémový název sloupce',                'Sloupec',                'Název sloupce v systémovém katalogu databáze.'),
('typename',                    'Datový typ (typename)',                           'Název datového typu SQL Serveru',        'Datový typ',             'Fyzický datový typ sloupce v databázi (např. varchar, int, uuid, bit).'),
('prec',                        'Přesnost / délka (prec)',                         'Maximální délka nebo přesnost typu',     'Délka / Přesnost',       'Číselná délka nebo přesnost datového typu v systémovém katalogu.'),
('prec_syntax',                 'Syntaxe délky typu (prec_syntax)',                'Zápis délky/přesnosti pro DDL',          'Syntaxe délky',          'Zformátovaný zápis délky nebo přesnosti typu v závorkách, např. (200) nebo (9,4).'),
('iscomputed',                  'Vypočítávaný sloupec (iscomputed)',               'Příznak počítaného sloupce v DB',        'Počítaný (DB)',          'Příznak v systémovém katalogu udávající, zda jde o computed column.'),
('collation_name',              'Řazení znakové sady (collation_name)',            'Název databázové kolace sloupce',        'Collation',              'Název collation použité u textového sloupce v SQL Serveru.'),
('keyno',                       'Pořadí v primárním klíči (keyno)',                'Pořadí sloupce v primárním klíči',       'Poř. v PK',              'Pořadové číslo sloupce v rámci složeného primárního klíče tabulky.'),
('nulls',                       'Povolení NULL (nulls)',                           'Povolení hodnoty NULL (null / not null)','NULL / NOT NULL',        'Určuje, zda sloupec v databázi povoluje hodnotu NULL.'),
('default_syntax',              'Syntaxe výchozí hodnoty (default_syntax)',        'Definice DEFAULT constraintu',           'Default výraz',          'SQL výraz výchozí hodnoty sloupce v systémovém katalogu.'),
('default_constraint_name',     'Název DEFAULT constraintu (default_constraint_name)','Systémový název DEFAULT omezení',     'Název defaultu',         'Jméno databázového constraintu zajišťujícího výchozí hodnotu sloupce.'),
('is_identity',                 'Automatické číslování (is_identity)',             'Příznak sloupce IDENTITY',               'Je IDENTITY',            'Určuje, zda má sloupec v databázi zapnuté automatické číslování IDENTITY.'),
('computed_syntax',             'Výraz počítaného sloupce (computed_syntax)',      'SQL vzorec počítaného sloupce',          'Vzorec sloupce',         'SQL definice výrazu pro vypočítávaný (computed) sloupec.'),
('table_type',                  'Typ tabulkového objektu (table_type)',            'Typ objektu v sys.objects',              'Typ tabulky',            'Kód typu objektu v systémovém katalogu (U = tabulka, V = pohled).'),
('index_name',                  'Název indexu (index_name)',                       'Systémový název indexu',                 'Index',                  'Název databázového indexu v sys.indexes.'),
('is_unique',                   'Unikátní index (is_unique)',                      'Příznak unikátního indexu',              'Unikátní',               'Určuje, zda index vynucuje jedinečnost klíčových hodnot.'),
('is_primary_key',              'Primární klíč (is_primary_key)',                  'Index tvoří primární klíč tabulky',      'Primární klíč',          'Určuje, zda je daný index primárním klíčem tabulky.'),
('key_ordinal',                 'Pořadí klíče v indexu (key_ordinal)',             'Pořadové číslo sloupce v klíči indexu',  'Poř. v indexu',          'Pořadí sloupce v klíči databázového indexu (0 = inkludovaný sloupec).'),
('is_descending_key',           'Sestupné řazení v indexu (is_descending_key)',    'Sloupec v indexu řazen sestupně (DESC)', 'Sestupně (DESC)',        'Určuje, zda je sloupec v indexu uložen v sestupném pořadí.'),
('is_included_column',          'Inkludovaný sloupec (is_included_column)',        'Neklíčový sloupec přidaný přes INCLUDE', 'INCLUDE sloupec',        'Určuje, zda je sloupec připojen k indexu v klauzuli INCLUDE.'),
('keyvalue',                    'Hodnota klíče uzlu (keyvalue)',                   'Identifikátor uzlu ve stromu',           'Klíč uzlu',              'Identifikátor položky při výpočtu stromové hierarchie.'),
('parent',                      'Nadřízený uzel (parent)',                         'Identifikátor rodiče ve stromu',         'Rodič',                  'Odkaz na nadřízený prvek ve funkci f_resolve_hierarchy.'),
('num',                         'Pořadové číslo pod rodičem (num)',                'Pořadí uzlu mezi sourozenci',            'Pořadí (num)',           'Vypočtené pořadové číslo uzlu v rámci stejného nadřízeného prvku.'),
('hierarchy_sort',              'Stromový třídicí klíč (hierarchy_sort)',          'Znakový klíč průchodu stromem',          'Stromový klíč',          'Zřetězený zero-padded třídicí kód určující přesné pořadí v celém stromu.'),
('level',                       'Úroveň zanoření (level)',                         'Hloubka zanoření uzlu ve stromu',        'Úroveň',                 'Číselná úroveň zanoření položky ve stromové hierarchii (0 = kořen).'),
('ordr',                        'Pořadí položky v seznamu (ordr)',                 'Pořadové číslo prvku z parsovaného seznamu', 'Pořadí',             'Pořadí položky vrácené parsovacími funkcemi f_string_list, f_integer_list a f_uuid_list.'),
('i',                           'Celé číslo (i)',                                  'Parsovaná celočíselná hodnota',          'Číslo (i)',              'Celočíselná hodnota vrácená funkcí f_integer_list.'),
('s',                           'Textová položka (s)',                             'Parsovaný textový řetězec',              'Text (s)',               'Textová položka vrácená funkcí f_string_list.');

-- 1. Jediný hromadný UPDATE hlavních záznamů (record_type = 'A', language = 'cs') v sys_global_columns
UPDATE mc
SET mc.caption = s.caption,
	mc.caption_plural = s.caption,
	mc.label = s.label,
	mc.header = s.header,
	mc.helptext = s.helptext,
	mc.[language] = 'cs',
	mc.who_modified = @sys_owner,
	mc.date_modified = GETDATE()
FROM meta_column mc
JOIN @col_cs s ON s.column_name = mc.column_name
WHERE mc.parent_class = @c_class
  AND mc.object_owner = @sys_owner
  AND mc.record_type = 'A'
  AND (mc.who_modified = @sys_owner OR mc.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT mc.caption, mc.caption_plural, mc.label, mc.header, mc.helptext, mc.[language]
	EXCEPT
	SELECT s.caption, s.caption, s.label, s.header, s.helptext, 'cs'
  );

-- 2. Hromadný UPDATE existujících symetrických 'L' záznamů pro češtinu (language = 'cs') v sys_global_columns
UPDATE l
SET l.caption = s.caption,
	l.caption_plural = s.caption,
	l.label = s.label,
	l.header = s.header,
	l.helptext = s.helptext,
	l.who_modified = @sys_owner,
	l.date_modified = GETDATE()
FROM meta_column l
JOIN meta_column a
	ON a.original = l.original
	AND a.object_owner = @sys_owner
	AND a.record_type = 'A'
	AND a.parent_class = @c_class
JOIN @col_cs s ON s.column_name = a.column_name
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'cs'
  AND (l.who_modified = @sys_owner OR l.date_modified < '2026-11-01')
  AND EXISTS (
	SELECT l.caption, l.caption_plural, l.label, l.header, l.helptext
	EXCEPT
	SELECT s.caption, s.caption, s.label, s.header, s.helptext
  );

-- 3. Hromadné doplnění chybějících symetrických 'L' záznamů pro češtinu (language = 'cs') v sys_global_columns
INSERT INTO meta_column (
	uuid, object_owner, original, record_type, approval_status, [language],
	parent_class, parent_order, sort_code, column_name, list_order,
	caption, caption_plural, description, label, header, helptext, placeholder,
	input_type, input_width, input_rows, max_length, css_class,
	translate, history, is_html, is_mandatory, is_url, is_computed,
	show_empty, hidden, customizable, ancestor, referenced_codetable, referenced_class,
	is_final, is_protected,
	date_created, who_created, date_modified, who_modified
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
	a.parent_class, a.parent_order, a.sort_code, a.column_name, a.list_order,
	s.caption, s.caption, a.description, s.label, s.header, s.helptext, a.placeholder,
	a.input_type, a.input_width, a.input_rows, a.max_length, a.css_class,
	a.translate, a.history, a.is_html, a.is_mandatory, a.is_url, a.is_computed,
	a.show_empty, a.hidden, a.customizable, a.ancestor, a.referenced_codetable, a.referenced_class,
	a.is_final, a.is_protected,
	GETDATE(), @sys_owner, GETDATE(), @sys_owner
FROM meta_column a
JOIN @col_cs s ON s.column_name = a.column_name
WHERE a.parent_class = @c_class
  AND a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_column l
	WHERE l.original = a.original
	  AND l.object_owner = @sys_owner
	  AND l.record_type = 'L'
	  AND l.[language] = 'cs'
  );

-- 4. Specifický kontextový popisek sloupce is_leaf přímo na třídě hierarchy (odlišení složky registru od koncové hierarchie)
UPDATE meta_column
SET caption = 'Samostatná hierarchie / sada štítků (is_leaf)',
	label = 'Samostatná hierarchie (is_leaf)',
	header = 'Hierarchie',
	helptext = 'Zaškrtněte (1) u koncové definice hierarchie nebo sady štítků, do které budete vkládat položky. Odškrtněte (0) pouze u nadřazené organizační složky v tomto registru.'
WHERE parent_class = @cls_hierarchy
  AND object_owner = @sys_owner
  AND record_type IN ('A', 'L')
  AND [language] = 'cs'
  AND column_name = 'is_leaf'
  AND (who_modified = @sys_owner OR date_modified < '2026-11-01');
GO