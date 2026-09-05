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