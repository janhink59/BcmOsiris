/* =============================================================================
 * Verze: 2026-10-04
 * Soubor: table_language.sql
 * Tabulka: language
 * Popis:   Statický číselník podporovaných jazyků aplikace (bez plné RAC/SSC zátěže).
 * Vazby:   - Slouží pro UI a určuje fallback (dědičnost) překladů v entity_manageru.
 *          - Obsahuje 'translator_org' pro delegování práv na globální
 *            překlad systémových objektů (0x00) konkrétnímu tenantovi.
 * ============================================================================= */

-- Drop staré verze tabulky
IF NOT EXISTS (SELECT 1 FROM v_syscolumns WHERE tabname = 'language' AND colname = 'translator_org')
BEGIN
	execute dropni 'language'
END
GO

IF OBJECT_ID('language') IS NULL
BEGIN
	CREATE TABLE [language] (
		[language] varchar(2) NOT NULL,                                      -- Primární klíč, kód jazyka (např. 'cs', 'en', 'it')
		caption varchar(200) NOT NULL DEFAULT '',                            -- Zobrazovaný název
		fallback_language varchar(2) not null default 'en',                                   -- Odkaz na nadřízený jazyk (např. 'sk' -> 'cs')
		sort_code varchar(20) NOT NULL DEFAULT '',                           -- Pořadí v menu
		is_default bit NOT NULL DEFAULT 0,                                   -- Výchozí systémový jazyk
		
		-- [ ARCHITEKTURA PŘEKLADŮ ]
		-- Oprávnění pro globální systémové překlady (object_owner = 0x00).
		-- Pokud je zde uvedeno UUID konkrétní organizace, její uživatelé s
		-- oprávněním 'right_translate' zapisují překlady rovnou pro celý systém.
		-- Ostatní uživatelé si tvoří jen vlastní lokální mutace.
		translator_org uuid not null default 0x00,                                            
		
		svg_icon varchar(max) NOT NULL DEFAULT '',                           -- Zdrojový kód SVG vlaječky pro UI
		
		CONSTRAINT pk_language PRIMARY KEY ([language])
	);
	PRINT 'Tabulka language byla vytvorena.';

	-- Vložení výchozích jazyků se sémantikou dědičnosti a integrovanou grafikou
	INSERT INTO [language] ([language], caption, fallback_language, sort_code, is_default, svg_icon)
	VALUES 
		('cs', 'Čeština', 'en', '01', 1, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-cs"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-cs)"><rect width="512" height="256" fill="#eceff1"/><rect y="256" width="512" height="256" fill="#d32f2f"/><polygon points="0,0 256,256 0,512" fill="#1976d2"/></g></svg>'),
		('en', 'English', 'cs', '02', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-en"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-en)"><rect width="512" height="512" fill="#012169"/><path d="M0,0 L512,512 M512,0 L0,512" stroke="#fff" stroke-width="100"/><path d="M0,0 L512,512 M512,0 L0,512" stroke="#C8102E" stroke-width="60"/><path d="M256,0 L256,512 M0,256 L512,256" stroke="#fff" stroke-width="140"/><path d="M256,0 L256,512 M0,256 L512,256" stroke="#C8102E" stroke-width="80"/></g></svg>'),
		('sk', 'Slovenčina', 'cs', '03', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-sk"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-sk)"><rect width="512" height="170" fill="#fff"/><rect y="170" width="512" height="172" fill="#0b4ea2"/><rect y="342" width="512" height="170" fill="#ee1c25"/><path d="M130,120 h100 v120 a50,50 0 0,1 -100,0 z" fill="#ee1c25" stroke="#fff" stroke-width="10"/><path d="M165,220 v-50 h30 v50 m-15,-50 v-30" stroke="#fff" stroke-width="12" fill="none"/></g></svg>'),
		('de', 'Deutsch', 'en', '04', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-de"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-de)"><rect width="512" height="170" fill="#000"/><rect y="170" width="512" height="172" fill="#d00"/><rect y="342" width="512" height="170" fill="#ffce00"/></g></svg>'),
		('it', 'Italiano', 'en', '05', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-it"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-it)"><rect width="170" height="512" fill="#009246"/><rect x="170" width="172" height="512" fill="#fff"/><rect x="342" width="170" height="512" fill="#ce2b37"/></g></svg>'),
		('pl', 'Polski', 'cs', '06', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-pl"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-pl)"><rect width="512" height="256" fill="#fff"/><rect y="256" width="512" height="256" fill="#dc143c"/></g></svg>'),
		('hu', 'Magyar', 'en', '07', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-hu"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-hu)"><rect width="512" height="170" fill="#ce2939"/><rect y="170" width="512" height="172" fill="#fff"/><rect y="342" width="512" height="170" fill="#477050"/></g></svg>'),
		('lt', 'Lietuvių', 'en', '08', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-lt"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-lt)"><rect width="512" height="170" fill="#fdb913"/><rect y="170" width="512" height="172" fill="#006a44"/><rect y="342" width="512" height="170" fill="#c1272d"/></g></svg>'),
		('ro', 'Română', 'en', '09', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-ro"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-ro)"><rect width="170" height="512" fill="#002b7f"/><rect x="170" width="172" height="512" fill="#fcd116"/><rect x="342" width="170" height="512" fill="#ce1126"/></g></svg>'),
		('es', 'Español', 'en', '10', 0, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><mask id="mask-es"><circle cx="256" cy="256" r="256" fill="#fff"/></mask><g mask="url(#mask-es)"><rect width="512" height="128" fill="#aa151b"/><rect y="128" width="512" height="256" fill="#f1bf00"/><rect y="384" width="512" height="128" fill="#aa151b"/></g></svg>');
END
GO