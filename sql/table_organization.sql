/* =============================================================================
 * Verze: 2026-11-13 17:30
 * Soubor: table_organization.sql
 * Tabulka: organization (Organizace a její nastavení)
 * Popis:	Základní kámen multi-tenantní architektury CRMM. Definuje jednotlivé 
 *			klienty (tenanty) v systému. Vlastníkem (object_owner) systémového 
 *			záznamu je 0x00, ostatní záznamy organizací vlastní samy sebe
 *			(object_owner = original) a jsou plně pod kontrolou administrátora
 *			dané organizace (OrgAdmin 'A').
 *			Licenční omezení (licence_level, login_disabled) jsou vyčleněna
 *			výhradně v tabulce organization_licence.
 *			Tabulka přímo obsahuje i regionální, formátovací a CRMM výpočtové
 *			parametry organizace (nahrazuje dřívější tabulku organization_settings).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Změny:
 * - 2026-11-13 17:30: Doplněna registrace třídy a sloupců do sysinit_class
 *   a sysinit_column.
 * - 2026-10-29 15:30: Vyčleněny sloupce licence_level a login_disabled do
 *   tabulky organization_licence. Doplněny regionální, formátovací a CRMM
 *   výpočtové parametry organizace a unikátní index uq_organization_draft.
 * - 2026-10-22 17:45: Doplněno idempotentní dotvoření chybějících symetrických
 *   'L' záznamů pro všechny existující organizace (včetně 0x00).
 * ============================================================================= */

-- Podmíněné odstranění tabulky, pokud v ní nejsou poslední změny
IF NOT EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization' AND colname='shortname')
	EXECUTE dropni 'organization';
GO

IF OBJECT_ID('organization') IS NULL
CREATE TABLE organization (
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,
	original uuid NOT NULL DEFAULT 0x00,
	record_type varchar(1) NOT NULL DEFAULT 'A',
	approval_status varchar(1) NOT NULL DEFAULT 'A',
	draft_author uuid NOT NULL DEFAULT 0x00,
	approval_note varchar(max) NOT NULL DEFAULT '',
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,
	
	-- -------------------------------------------------------------------------
	-- Společné textové vlastnosti (vždy varchar s plnou podporou UTF-8)
	-- -------------------------------------------------------------------------
	caption varchar(200) NOT NULL DEFAULT '',
	shortname varchar(40) NOT NULL DEFAULT '',
	external_code varchar(200) NOT NULL DEFAULT '',
	instance_class_name varchar(80) NOT NULL DEFAULT '',
	description_text varchar(max) NOT NULL DEFAULT '',
	help_text varchar(max) NOT NULL DEFAULT '',
	
	-- -------------------------------------------------------------------------
	-- Auditní stopy (výhradně uuid odkazy bez denormalizovaných jmen)
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Specifické identifikační, fakturační a adresní sloupce organizace
	-- -------------------------------------------------------------------------
	note varchar(max) NOT NULL DEFAULT '',
	
	-- Detekce domovského SSO tenanta v multi-tenantním prostředí (pro IdP)
	login_domain varchar(200) NOT NULL DEFAULT '',		
	
	register_id bigint NULL DEFAULT 0,
	tax_id varchar(40) NOT NULL DEFAULT '',
	invoice_info varchar(max) NOT NULL DEFAULT '',
	
	-- Adresní údaje
	address_name varchar(100) NOT NULL DEFAULT '',
	address_street varchar(100) NOT NULL DEFAULT '',
	address_city varchar(100) NOT NULL DEFAULT '',
	address_zip varchar(10) NOT NULL DEFAULT '',
	address_state varchar(40) NOT NULL DEFAULT '',
	www_address varchar(200) NOT NULL DEFAULT '',

	-- -------------------------------------------------------------------------
	-- Regionální a formátovací nastavení organizace
	-- -------------------------------------------------------------------------
	preferred_language varchar(2) NOT NULL DEFAULT 'cs',
	currency_unit varchar(40) NOT NULL DEFAULT 'tis. Kč',
	currency_digits tinyint NOT NULL DEFAULT 2,
	currency_before bit NOT NULL DEFAULT 0,
	format_date varchar(20) NOT NULL DEFAULT 'dd.MM.yyyy',
	format_time varchar(20) NOT NULL DEFAULT 'HH:mm:ss',
	time_zone varchar(100) NOT NULL DEFAULT 'Europe/Prague',
	thousand_separator varchar(1) NOT NULL DEFAULT ' ',
	decimal_separator varchar(1) NOT NULL DEFAULT ',',
	export_delimiter varchar(1) NOT NULL DEFAULT ';',

	-- -------------------------------------------------------------------------
	-- Metodické a výpočtové parametry CRMM (limity škál a finanční prahy)
	-- -------------------------------------------------------------------------
	max_threat_score decimal(9,4) NOT NULL DEFAULT 13.0000,
	max_vulnerability_score decimal(9,4) NOT NULL DEFAULT 6.5000,
	max_impact_score decimal(9,4) NOT NULL DEFAULT 25.5000,
	max_risk_score decimal(9,4) NOT NULL DEFAULT 40.7500,
	max_impact_financial decimal(18,2) NULL,
	residual_risk_min_financial decimal(18,2) NULL,
	evaluation_method varchar(40) NOT NULL DEFAULT '',

	-- Média a logotyp
	logo_data varbinary(max) NULL,
	logo_filename varchar(255) NOT NULL DEFAULT '',
	logo_mime_type varchar(100) NOT NULL DEFAULT '',

	CONSTRAINT pk_organization PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců a odstranění vyčleněných licenčních sloupců
-- -----------------------------------------------------------------------------
EXEC sp_drop_column 'organization', 'licence_level';
EXEC sp_drop_column 'organization', 'login_disabled';
GO

EXEC p_create_missing_column 'organization', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'organization', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'organization', 'preferred_language', 'varchar(2) NOT NULL DEFAULT ''cs''';
EXEC p_create_missing_column 'organization', 'currency_unit', 'varchar(40) NOT NULL DEFAULT ''tis. Kč''';
EXEC p_create_missing_column 'organization', 'currency_digits', 'tinyint NOT NULL DEFAULT 2';
EXEC p_create_missing_column 'organization', 'currency_before', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'organization', 'format_date', 'varchar(20) NOT NULL DEFAULT ''dd.MM.yyyy''';
EXEC p_create_missing_column 'organization', 'format_time', 'varchar(20) NOT NULL DEFAULT ''HH:mm:ss''';
EXEC p_create_missing_column 'organization', 'time_zone', 'varchar(100) NOT NULL DEFAULT ''Europe/Prague''';
EXEC p_create_missing_column 'organization', 'thousand_separator', 'varchar(1) NOT NULL DEFAULT '' ''';
EXEC p_create_missing_column 'organization', 'decimal_separator', 'varchar(1) NOT NULL DEFAULT '',''';
EXEC p_create_missing_column 'organization', 'export_delimiter', 'varchar(1) NOT NULL DEFAULT '';''';
EXEC p_create_missing_column 'organization', 'max_threat_score', 'decimal(9,4) NOT NULL DEFAULT 13.0000';
EXEC p_create_missing_column 'organization', 'max_vulnerability_score', 'decimal(9,4) NOT NULL DEFAULT 6.5000';
EXEC p_create_missing_column 'organization', 'max_impact_score', 'decimal(9,4) NOT NULL DEFAULT 25.5000';
EXEC p_create_missing_column 'organization', 'max_risk_score', 'decimal(9,4) NOT NULL DEFAULT 40.7500';
EXEC p_create_missing_column 'organization', 'max_impact_financial', 'decimal(18,2) NULL';
EXEC p_create_missing_column 'organization', 'residual_risk_min_financial', 'decimal(18,2) NULL';
EXEC p_create_missing_column 'organization', 'evaluation_method', 'varchar(40) NOT NULL DEFAULT ''''';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'organization', 
	@iname = 'uq_organization_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization', 
	@iname = 'uq_organization_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization', 
	@iname = 'uq_organization_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Inicializační systémový záznam (0x00)
-- -----------------------------------------------------------------------------
IF NOT EXISTS(SELECT * FROM organization WHERE uuid = 0x00)
BEGIN
	INSERT INTO organization (
		uuid,
		object_owner,
		original,
		record_type,
		approval_status,
		caption,
		shortname,
		description_text
	) VALUES (
		0x00,
		0x00,
		0x00,
		'A',
		'A',
		'System',
		'SYS',
		'Systémová master organizace.'
	);
END
GO

-- Idempotentní doplnění chybějících symetrických 'L' záznamů pro všechny existující organizace
INSERT INTO organization (
	uuid, object_owner, original, record_type, approval_status, [language],
	caption, shortname, description_text, help_text, note,
	login_domain, who_created, who_modified
)
SELECT
	NEWID(), a.object_owner, a.original, 'L', 'A', a.[language],
	a.caption, a.shortname, a.description_text, a.help_text, a.note,
	a.login_domain, a.who_created, a.who_modified
FROM organization a
WHERE a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM organization l
	WHERE l.original = a.original
	  AND l.object_owner = a.object_owner
	  AND l.record_type = 'L'
	  AND l.[language] = a.[language]
	  AND l.removed = 0
  );
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'organization';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('organization','cs','T','organization','Organizace','Organizace','Kmenová evidence organizací (tenantů) včetně fakturačních, regionálních a metodických parametrů CRMM.','Správa identifikačních údajů organizace, formátování měn a dat a výpočtových limitů hodnocení rizik.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('organization','en','Organization','Organizations','Master registry of organizations (tenants) including billing, regional, and CRMM calculation parameters.','Manage organization identification, currency/date formatting, and risk assessment score limits.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'organization';

	INSERT INTO sysinit_column (
		table_name, column_name, [language],
		caption, label, header, helptext,
		hidden
	) VALUES
	('organization','address_city','cs','Město / obec (address_city)','Město / Obec','Město','Město nebo obec sídla organizace.',0),
	('organization','address_name','cs','Název v adrese (address_name)','Oficiální název v adrese sídla','Název (adresa)','Obchodní jméno nebo doplněk názvu uváděný v poštovní adrese sídla.',0),
	('organization','address_state','cs','Stát (address_state)','Stát / Země','Stát','Stát, ve kterém se nachází sídlo organizace.',0),
	('organization','address_street','cs','Ulice a číslo (address_street)','Ulice a číslo popisné / orientační','Ulice','Ulice a číslo domu sídla organizace.',0),
	('organization','address_zip','cs','PSČ (address_zip)','Poštovní směrovací číslo (PSČ)','PSČ','Poštovní směrovací číslo adresy sídla.',0),
	('organization','currency_before','cs','Měna před částkou (currency_before)','Zobrazovat symbol měny před číslem','Měna před','Pokud je zaškrtnuto, symbol měny se vypisuje před číselnou částkou (např. € 100).',0),
	('organization','currency_digits','cs','Desetinná místa měny (currency_digits)','Počet desetinných míst měny','Des. místa měny','Počet zobrazovaných desetinných míst u finančních částek.',0),
	('organization','currency_unit','cs','Měnová jednotka (currency_unit)','Používaná měnová jednotka','Měna','Označení měnové jednotky pro finanční hodnocení dopadů a rizik (např. tis. Kč, EUR).',0),
	('organization','decimal_separator','cs','Desetinný oddělovač (decimal_separator)','Znak desetinného oddělovače','Des. oddělovač','Znak oddělující celou a desetinnou část čísla (čárka nebo tečka).',0),
	('organization','evaluation_method','cs','Metoda hodnocení rizik (evaluation_method)','Zvolená metodika hodnocení CRMM','Metoda hodnocení','Kód metodiky nebo výpočtového modelu používaného pro vyhodnocení rizik.',0),
	('organization','export_delimiter','cs','Oddělovač polí v CSV (export_delimiter)','Výchozí oddělovač pro CSV export','CSV oddělovač','Znak oddělující sloupce v exportovaných CSV souborech (standardně středník ;).',0),
	('organization','format_date','cs','Formát data (format_date)','Formát zobrazení data','Formát data','Maska pro formátování kalendářního data v uživatelském rozhraní (např. dd.MM.yyyy).',0),
	('organization','format_time','cs','Formát času (format_time)','Formát zobrazení času','Formát času','Maska pro formátování času v uživatelském rozhraní (např. HH:mm:ss).',0),
	('organization','invoice_info','cs','Fakturační údaje (invoice_info)','Fakturační a bankovní údaje','Fakturace','Doplňující fakturační údaje, bankovní spojení nebo poznámka na fakturu.',0),
	('organization','login_domain','cs','Přihlašovací SSO doména (login_domain)','Doména pro SSO přihlášení','SSO doména','Internetová doména organizace pro automatické rozpoznání domovského tenanta při SSO autentizaci.',0),
	('organization','logo_data','cs','Binární data loga (logo_data)','Soubor loga organizace','Logo (data)','Binární obsah grafického souboru s logotypem organizace.',1),
	('organization','logo_filename','cs','Název souboru loga (logo_filename)','Původní název souboru loga','Soubor loga','Název nahraného grafického souboru s logotypem organizace.',1),
	('organization','logo_mime_type','cs','MIME typ loga (logo_mime_type)','Formát obrázku loga (MIME)','MIME typ loga','Internetový typ média nahraného loga (např. image/png, image/svg+xml).',1),
	('organization','max_impact_financial','cs','Finanční hodnota max. dopadu (max_impact_financial)','Finanční vyjádření nejvyššího dopadu','Max. dopad (fin.)','Finanční částka v měnové jednotce organizace odpovídající nejvyššímu stupni dopadu.',0),
	('organization','max_impact_score','cs','Maximální skóre dopadu (max_impact_score)','Horní limit skóre velikosti dopadu','Max. dopad','Nejvyšší povolená hodnota skóre při hodnocení velikosti dopadu v organizaci.',0),
	('organization','max_risk_score','cs','Maximální skóre rizika (max_risk_score)','Horní limit skóre výsledného rizika','Max. riziko','Nejvyšší hodnota skóre výsledného rizika v metodice organizace.',0),
	('organization','max_threat_score','cs','Maximální skóre hrozby (max_threat_score)','Horní limit skóre velikosti hrozby','Max. hrozba','Nejvyšší povolená hodnota skóre při hodnocení velikosti hrozby v organizaci.',0),
	('organization','max_vulnerability_score','cs','Maximální skóre zranitelnosti (max_vulnerability_score)','Horní limit skóre zranitelnosti','Max. zranitelnost','Nejvyšší povolená hodnota skóre při hodnocení zranitelnosti v organizaci.',0),
	('organization','preferred_language','cs','Výchozí jazyk organizace (preferred_language)','Preferovaný výchozí jazyk','Výchozí jazyk','Výchozí jazyk prostředí a dat pro nově zakládané uživatele a záznamy organizace.',0),
	('organization','register_id','cs','Identifikační číslo (register_id)','IČO organizace','IČO','Oficiální identifikační číslo organizace v obchodním nebo živnostenském rejstříku.',0),
	('organization','residual_risk_min_financial','cs','Finanční práh zbytkového rizika (residual_risk_min_financial)','Zanedbatelná roční ztráta (skóre 1)','Min. rez. (fin.)','Finanční hodnota ročních ztrát v měně organizace považovaná za zanedbatelné zbytkové riziko.',0),
	('organization','tax_id','cs','Daňové identifikační číslo (tax_id)','DIČ organizace','DIČ','Daňové identifikační číslo organizace pro účely fakturace a DPH.',0),
	('organization','thousand_separator','cs','Oddělovač tisíců (thousand_separator)','Znak oddělovače tisíců','Odd. tisíců','Znak používaný pro oddělení tisíců při výpisu čísel (např. mezera).',0),
	('organization','time_zone','cs','Časové pásmo (time_zone)','Časové pásmo organizace','Časové pásmo','Identifikátor časového pásma organizace (např. Europe/Prague).',0),
	('organization','www_address','cs','Webová stránka (www_address)','Webová adresa (URL)','Web (WWW)','Oficiální webová prezentace organizace.',0);

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('organization','address_city','en','City / Town (address_city)','City / Municipality','City','City or municipality of the organization headquarters.'),
	('organization','address_name','en','Address Name (address_name)','Official Name in Registered Address','Address Name','Company name or supplement used in the postal address.'),
	('organization','address_state','en','Country / State (address_state)','Country / State','Country','Country where the organization headquarters is located.'),
	('organization','address_street','en','Street & Number (address_street)','Street and Building Number','Street','Street and building number of the organization headquarters.'),
	('organization','address_zip','en','Postal / ZIP Code (address_zip)','Postal / ZIP Code','ZIP Code','Postal code of the headquarters address.'),
	('organization','currency_before','en','Currency Before Amount (currency_before)','Display Currency Symbol Before Number','Currency Before','If checked, the currency symbol is placed before the numeric amount (e.g., € 100).'),
	('organization','currency_digits','en','Currency Decimal Places (currency_digits)','Number of Currency Decimal Places','Currency Decimals','Number of decimal places displayed for financial amounts.'),
	('organization','currency_unit','en','Currency Unit (currency_unit)','Currency Unit Used','Currency','Currency unit label used for financial impact and risk valuation (e.g., kCZK, EUR).'),
	('organization','decimal_separator','en','Decimal Separator (decimal_separator)','Decimal Separator Character','Decimal Sep.','Character separating integer and fractional parts of a number (comma or dot).'),
	('organization','evaluation_method','en','Risk Evaluation Method (evaluation_method)','Selected CRMM Evaluation Method','Evaluation Method','Code of the methodology or calculation model used for risk evaluation.'),
	('organization','export_delimiter','en','CSV Field Delimiter (export_delimiter)','Default Delimiter for CSV Export','CSV Delimiter','Character separating columns in exported CSV files (semicolon ; by default).'),
	('organization','format_date','en','Date Format (format_date)','Date Display Format','Date Format','Formatting mask for displaying calendar dates in the UI (e.g., dd.MM.yyyy or yyyy-MM-dd).'),
	('organization','format_time','en','Time Format (format_time)','Time Display Format','Time Format','Formatting mask for displaying time values in the UI (e.g., HH:mm:ss).'),
	('organization','invoice_info','en','Billing Information (invoice_info)','Billing & Bank Account Details','Billing Info','Additional billing details, bank account numbers, or invoice notes.'),
	('organization','login_domain','en','SSO Login Domain (login_domain)','Domain for SSO Login','SSO Domain','Internet domain of the organization used to automatically detect the home tenant during SSO authentication.'),
	('organization','logo_data','en','Logo Binary Data (logo_data)','Organization Logo File Data','Logo (Data)','Binary content of the organization logo image file.'),
	('organization','logo_filename','en','Logo Filename (logo_filename)','Original Logo Filename','Logo Filename','Filename of the uploaded organization logo image.'),
	('organization','logo_mime_type','en','Logo MIME Type (logo_mime_type)','Logo Image Format (MIME)','Logo MIME Type','Internet media type of the uploaded logo (e.g., image/png, image/svg+xml).'),
	('organization','max_impact_financial','en','Financial Value of Max Impact (max_impact_financial)','Financial Expression of Highest Impact','Max. Impact (Fin.)','Financial amount in the organization currency corresponding to the highest impact level.'),
	('organization','max_impact_score','en','Maximum Impact Score (max_impact_score)','Upper Limit of Impact Score','Max. Impact','Highest allowed score value when assessing impact severity in the organization.'),
	('organization','max_risk_score','en','Maximum Risk Score (max_risk_score)','Upper Limit of Resulting Risk Score','Max. Risk','Highest resulting risk score value in the organization methodology.'),
	('organization','max_threat_score','en','Maximum Threat Score (max_threat_score)','Upper Limit of Threat Score','Max. Threat','Highest allowed score value when assessing threat level in the organization.'),
	('organization','max_vulnerability_score','en','Maximum Vulnerability Score (max_vulnerability_score)','Upper Limit of Vulnerability Score','Max. Vulnerability','Highest allowed score value when assessing vulnerability in the organization.'),
	('organization','preferred_language','en','Default Organization Language (preferred_language)','Preferred Default Language','Default Language','Default UI and data language for newly created users and records in the organization.'),
	('organization','register_id','en','Company Registration ID (register_id)','Company Registration Number (ID)','Reg. ID','Official registration number of the organization in the commercial register.'),
	('organization','residual_risk_min_financial','en','Financial Residual Risk Threshold (residual_risk_min_financial)','Negligible Annual Loss (Score 1)','Min. Res. (Fin.)','Financial value of annual loss in the organization currency considered negligible residual risk.'),
	('organization','tax_id','en','Tax Identification Number (tax_id)','VAT / Tax ID of Organization','Tax ID','Tax identification number of the organization for billing and VAT purposes.'),
	('organization','thousand_separator','en','Thousands Separator (thousand_separator)','Thousands Separator Character','Thousands Sep.','Character used to separate thousands when formatting numbers (e.g., space or comma).'),
	('organization','time_zone','en','Time Zone (time_zone)','Organization Time Zone','Time Zone','Time zone identifier of the organization (e.g., Europe/Prague).'),
	('organization','www_address','en','Website (www_address)','Website Address (URL)','Website','Official website URL of the organization.');
END
GO