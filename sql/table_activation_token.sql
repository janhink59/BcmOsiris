-- =============================================================================
-- Tabulka: activation_token
-- Úèel: Univerzální tabulka pro jednorázové tokeny (aktivace, reset hesla, MFA, magic links).
-- Architektura: Transakèní tabulka. Zámìrnì vyjmuta z RAC a SSC komplexity (bez verzování).
-- =============================================================================

IF OBJECT_ID('activation_token') IS NULL
BEGIN
	CREATE TABLE activation_token (
		-- -------------------------------------------------------------------------
		-- Primární klíè s využitím uživatelského typu uuid
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		
		-- -------------------------------------------------------------------------
		-- Byznys sloupce pro token
		-- -------------------------------------------------------------------------
		-- Ukládáme pouze hash (napø. bcrypt/argon2), nikdy plaintext token!
		token_hash varchar(255) NOT NULL,
		
		-- Urèuje kontext použití tokenu (ACTIVATION, PASSWORD_RESET, MAGIC_LINK, MFA)
		token_purpose varchar(50) NOT NULL,
		
		-- Reference na úèet, na který se token váže (bez FOREIGN KEY)
		user_account uuid NOT NULL DEFAULT 0x00,
		
		-- Pøesný èas, kdy token pøestává platit
		expires_at datetime NOT NULL,
		
		-- Pøíznak, zda již byl token uplatnìn (zamezení znovupoužití - replay attack)
		is_used bit NOT NULL DEFAULT 0,
		
		-- IP adresa, ze které byl token vyžádán (bezpeènostní a auditní dùvod)
		request_ip varchar(45) NOT NULL DEFAULT '',

		-- -------------------------------------------------------------------------
		-- Základní auditní stopy (uuid odkazy místo textu)
		-- -------------------------------------------------------------------------
		date_created datetime NOT NULL DEFAULT GETDATE(),
		who_created uuid NOT NULL DEFAULT 0x00,
		date_modified datetime NOT NULL DEFAULT GETDATE(),
		who_modified uuid NOT NULL DEFAULT 0x00,
		removed bit NOT NULL DEFAULT 0,

		CONSTRAINT pk_activation_token PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka activation_token byla vytvoøena.';
END
GO

-- =============================================================================
-- Aktualizace struktury a indexy
-- =============================================================================

-- Idempotentní založení indexu pro rychlé vyhledávání platných tokenù dle úèelu
EXEC sp_create_index 
	@tname = 'activation_token', 
	@iname = 'ix_activation_token_lookup', 
	@colnames = 'token_purpose, is_used', 
	@uni = '', 
	@options = 'WHERE removed = 0 AND is_used = 0';
GO
