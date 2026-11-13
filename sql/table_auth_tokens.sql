/*
=========================================================================================
KONTEXT PRO AI: Implementace permanentního přihlášení (Remember Me) pro PHP 8.3
=========================================================================================
Tento skript (MSSQL 2019) definuje strukturu pro bezpečné uložení dlouhodobých 
přihlašovacích tokenů, které umožňují přihlášení uživatele i po vypršení standardního SID.

Architektonická a bezpečnostní rozhodnutí:
1. Bezpečnostní vzor "Selector & Validator":
	- Cookie v prohlížeči má formát "selector:validator".
	- Tabulka ukládá `selector` v čistém textu pro rychlé vyhledání.
	- Validator je uložen POUZE jako hash (SHA-256). Při úniku databáze tak útočník 
	  nezíská použitelné tokeny. Při ověřování se porovnává přes hash_equals v PHP.
2. Optimalizace primárního klíče:
	- Záměrně bylo vynecháno umělé číselné ID. Primárním klíčem je samotný `selector`, 
	  což vytváří clustered index a zaručuje okamžité čtení bez ohledu na počet záznamů.
3. Identifikátor uživatele (ZMĚNA 09/2026):
	- Vazba je definována sloupcem `user_account_uuid` (uuid) místo textového loginu.
	  Tím odpadá nutnost doplňkového čtení tabulky user_account před voláním 
	  procedury p_set_login.
4. Podpora pro selektivní odhlášení (Device Management):
	- Sloupce `ip_address`, `user_agent` a `last_used` slouží jako metadata.
	- Umožňují v UI zobrazit uživateli seznam aktivních sezení a selektivně 
	  invalidovat konkrétní zařízení (např. při ztrátě mobilu) smazáním konkrétního selectoru.
5. Samočisticí mechanismus:
	- Odstraňování expirovaných tokenů nevyžaduje SQL Agent job. Je řešeno pomocí 
	  AFTER INSERT triggeru, který při každém novém zápisu promaže staré záznamy.
=========================================================================================
*/

-- Idempotentní odstranění staré verze tabulky (pokud obsahuje textový user_login)
IF EXISTS (
	SELECT 1 
	FROM sys.columns 
	WHERE object_id = OBJECT_ID('auth_tokens') 
	  AND name = 'user_login'
)
BEGIN
	DROP TABLE auth_tokens;
	PRINT 'Stará tabulka auth_tokens (s user_login) byla odstraněna.';
END
GO

-- 1. Vytvoření tabulky pro tokeny
IF OBJECT_ID('auth_tokens') IS NULL
BEGIN
	CREATE TABLE auth_tokens (
		selector VARCHAR(64) PRIMARY KEY,
		
		-- Vazba přímo na originální UUID uživatele z user_account
		user_account_uuid uuid NOT NULL,
		
		hashed_validator VARCHAR(255) NOT NULL,
		expires DATETIME2 NOT NULL,
		
		-- Metadata pro identifikaci zařízení a selektivní logout
		ip_address VARCHAR(45) NOT NULL,
		user_agent NVARCHAR(500) NOT NULL,
		last_used DATETIME2 NOT NULL
	);
	PRINT 'Tabulka auth_tokens byla vytvořena.';
END
GO

-- 2. Trigger pro automatický úklid expirovaných tokenů
IF OBJECT_ID('trg_cleanup_expired_tokens', 'TR') IS NOT NULL
	DROP TRIGGER trg_cleanup_expired_tokens;
GO

CREATE TRIGGER trg_cleanup_expired_tokens
ON auth_tokens
AFTER INSERT
AS
BEGIN
	-- Vypnutí počitadla dotčených řádků pro snížení overheadu sítě a prevenci chyb v PDO
	SET NOCOUNT ON;
	
	-- Smazání všech záznamů, jejichž platnost již vypršela
	DELETE FROM auth_tokens 
	WHERE expires < SYSDATETIME();
END;
GO

-- 3. Registrace třídy a sloupců do sysinit_class a sysinit_column
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'auth_tokens';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('auth_tokens','cs','T','auth_tokens','Token trvalého přihlášení','Tokeny trvalého přihlášení','Bezpečné úložiště dlouhodobých autentizačních tokenů (Remember Me) podle vzoru Selector & Validator.','Technická tabulka spravující aktivní trvalá přihlášení prohlížečů.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('auth_tokens','en','Persistent Login Token','Persistent Login Tokens','Secure storage of long-lived authentication tokens (Remember Me) using the Selector & Validator pattern.','Technical table managing active persistent browser sessions.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'auth_tokens';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('auth_tokens','expires','cs','Expirace tokenu (expires)','Platnost tokenu do','Expiruje','Datum a čas vypršení platnosti trvalého přihlašovacího tokenu.'),
	('auth_tokens','hashed_validator','cs','Hash validátoru (hashed_validator)','SHA-256 hash tajného validátoru','Hash validátoru','Kryptografický otisk tajné části trvalého přihlašovacího tokenu.'),
	('auth_tokens','ip_address','cs','IP adresa (ip_address)','Klientská IP adresa','IP adresa','Síťová IP adresa klienta (včetně případné cesty X-Forwarded-For).'),
	('auth_tokens','last_used','cs','Naposledy použito (last_used)','Čas posledního uplatnění tokenu','Naposledy použito','Datum a čas posledního automatického přihlášení pomocí tohoto tokenu.'),
	('auth_tokens','selector','cs','Veřejný selektor tokenu (selector)','Identifikátor tokenu (selector)','Selektor','Veřejná část trvalého přihlašovacího tokenu sloužící k rychlému vyhledání v databázi.'),
	('auth_tokens','user_account_uuid','cs','Uživatelský účet (user_account_uuid)','Uživatel (UUID účtu)','Uživatel (UUID)','Odkaz na globální účet uživatele v tabulce user_account.'),
	('auth_tokens','user_agent','cs','Identifikace prohlížeče (user_agent)','Prohlížeč a operační systém (User-Agent)','Prohlížeč','Textový řetězec identifikující prohlížeč a zařízení uživatele.'),
	('auth_tokens','expires','en','Token Expiration (expires)','Token Valid Until','Expires','Expiration date and time of the persistent login token.'),
	('auth_tokens','hashed_validator','en','Validator Hash (hashed_validator)','SHA-256 Hash of Secret Validator','Validator Hash','Cryptographic hash of the secret validator part of the persistent login token.'),
	('auth_tokens','ip_address','en','IP Address (ip_address)','Client IP Address','IP Address','Network IP address of the client (including X-Forwarded-For path).'),
	('auth_tokens','last_used','en','Last Used (last_used)','Token Last Used Timestamp','Last Used','Date and time when this persistent token was last used for auto-login.'),
	('auth_tokens','selector','en','Token Public Selector (selector)','Token Identifier (selector)','Selector','Public part of the persistent login token used for fast database lookup.'),
	('auth_tokens','user_account_uuid','en','User Account (user_account_uuid)','User (Account UUID)','User (UUID)','Reference to the global user account in the user_account table.'),
	('auth_tokens','user_agent','en','Browser User-Agent (user_agent)','Browser & OS Identification (User-Agent)','User-Agent','User-Agent string identifying the user browser and operating system.');
END
GO