-- =============================================================================
-- Tabulka: user_external_identity (Externí identity uživatelů)
-- Popis:	Vazební tabulka pro integraci Single Sign-On (SSO). Propojuje 
--			externí identifikační údaje od Identity Providerů (např. Microsoft 
--			Entra ID, Google Workspace) s lokálními uživatelskými účty.
-- Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
-- =============================================================================

IF OBJECT_ID('user_external_identity') IS NULL
BEGIN
	CREATE TABLE user_external_identity (
		-- Standardní RAC a SSC sloupce
		uuid uuid NOT NULL,
		object_owner uuid NOT NULL DEFAULT 0x00,
		original uuid NOT NULL DEFAULT 0x00,
		record_type varchar(1) NOT NULL DEFAULT 'A',
		approval_status varchar(1) NOT NULL DEFAULT 'A',
		inactive bit NOT NULL DEFAULT 0,
		removed bit NOT NULL DEFAULT 0,
		language varchar(2) NOT NULL DEFAULT 'cs',
		valid_from date NOT NULL DEFAULT '1970-01-01',
		valid_to date NULL,
		
		-- Auditní stopy
		date_created datetime NOT NULL DEFAULT getdate(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT getdate(),
		who_modified uuid NOT NULL DEFAULT 0x00,
		
		-- Specifické byznys sloupce (Autentizace přes IdP)
		provider_name varchar(50) NOT NULL DEFAULT '',
		provider_user_id varchar(255) NOT NULL DEFAULT '',
		
		-- Odkaz na klíč original z tabulky user_account
		user_account uuid NOT NULL DEFAULT 0x00,
		
		CONSTRAINT pk_user_external_identity PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka user_external_identity byla vytvořena.';
END
GO

-- =============================================================================
-- Aktualizace struktury (přidání chybějících sloupců při opakovaném spuštění)
-- =============================================================================
-- Pokud v budoucnu přidáš nový sloupec do CREATE TABLE bloku výše, 
-- přidej sem i jeho založení přes p_create_missing_column, aby se aplikoval 
-- na již existující databáze.
-- 
-- Příklad:
-- EXEC p_create_missing_column 'user_external_identity', 'novy_sloupec', 'varchar(100) NOT NULL DEFAULT ''''';
-- GO

-- =============================================================================
-- Indexy (řešené idempotentně přes dodanou proceduru sp_create_index)
-- =============================================================================

-- Zajištění unikátnosti aktivního záznamu (Active) pro daného vlastníka a originál.
EXEC sp_create_index 
	@tname = 'user_external_identity', 
	@iname = 'uq_user_external_identity_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- Index pro rychlé vyhledání uživatele během procesu přihlášení (SSO callback).
EXEC sp_create_index 
	@tname = 'user_external_identity', 
	@iname = 'ix_user_external_identity_provider', 
	@colnames = 'provider_name, provider_user_id, record_type', 
	@uni = '', 
	@options = 'WHERE removed = 0';
GO

-- Index pro rychlé dohledání všech navázaných identit konkrétního lokálního účtu.
EXEC sp_create_index 
	@tname = 'user_external_identity', 
	@iname = 'ix_user_external_identity_account', 
	@colnames = 'user_account, record_type', 
	@uni = '', 
	@options = 'WHERE removed = 0';
GO