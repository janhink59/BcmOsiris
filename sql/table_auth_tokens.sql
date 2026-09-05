/*
=========================================================================================
KONTEXT PRO AI: Implementace permanentního pøihlášení (Remember Me) pro PHP 8.3
=========================================================================================
Tento skript (MSSQL 2019) definuje strukturu pro bezpeèné uložení dlouhodobých 
pøihlašovacích tokenù, které umožòují pøihlášení uživatele i po vypršení standardního SID.

Architektonická a bezpeènostní rozhodnutí:
1. Bezpeènostní vzor "Selector & Validator":
	- Cookie v prohlížeèi má formát "selector:validator".
	- Tabulka ukládá `selector` v èistém textu pro rychlé vyhledání.
	- Validator je uložen POUZE jako hash (SHA-256). Pøi úniku databáze tak útoèník 
	  nezíská použitelné tokeny. Pøi ovìøování se porovnává pøes hash_equals v PHP.
2. Optimalizace primárního klíèe:
	- Zámìrnì bylo vynecháno umìlé èíselné ID. Primárním klíèem je samotný `selector`, 
	  což vytváøí clustered index a zaruèuje okamžité ètení bez ohledu na poèet záznamù.
3. Identifikátor uživatele:
	- Místo user_id používáme pøímo `user_login` (VARCHAR).
4. Podpora pro selektivní odhlášení (Device Management):
	- Sloupce `ip_address`, `user_agent` a `last_used` slouží jako metadata.
	- Umožòují v UI zobrazit uživateli seznam aktivních sezení a selektivnì 
	  invalidovat konkrétní zaøízení (napø. pøi ztrátì mobilu) smazáním konkrétního selectoru.
5. Samoèisticí mechanismus:
	- Odstraòování expirovaných tokenù nevyžaduje SQL Agent job. Je øešeno pomocí 
	  AFTER INSERT triggeru, který pøi každém novém zápisu promaže staré záznamy.
=========================================================================================
*/

-- 1. Vytvoøení tabulky pro tokeny
CREATE TABLE auth_tokens (
	selector VARCHAR(64) PRIMARY KEY,
	user_login VARCHAR(100) NOT NULL,
	hashed_validator VARCHAR(255) NOT NULL,
	expires DATETIME2 NOT NULL,
	
	-- Metadata pro identifikaci zaøízení a selektivní logout
	ip_address VARCHAR(45) NOT NULL,
	user_agent NVARCHAR(500) NOT NULL,
	last_used DATETIME2 NOT NULL
);
GO

-- 2. Trigger pro automatický úklid expirovaných tokenù
CREATE TRIGGER trg_cleanup_expired_tokens
ON auth_tokens
AFTER INSERT
AS
BEGIN
	-- Vypnutí poèitadla dotèených øádkù pro snížení overheadu sítì a prevenci chyb v PDO
	SET NOCOUNT ON;
	
	-- Smazání všech záznamù, jejichž platnost již vypršela
	DELETE FROM auth_tokens 
	WHERE expires < SYSDATETIME();
END;
GO