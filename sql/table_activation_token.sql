-- =============================================================================
-- Tabulka: activation_token
-- Účel: Univerzální tabulka pro jednorázové tokeny (aktivace, reset hesla, MFA, magic links).
-- Architektura: Transakční tabulka. Záměrně vyjmuta z RAC a SSC komplexity (bez verzování).
-- =============================================================================

IF OBJECT_ID('activation_token') IS NULL
BEGIN
	CREATE TABLE activation_token (
		-- -------------------------------------------------------------------------
		-- Primární klíč s využitím uživatelského typu uuid
		-- -------------------------------------------------------------------------
		uuid uuid NOT NULL,
		
		-- -------------------------------------------------------------------------
		-- Byznys sloupce pro token
		-- -------------------------------------------------------------------------
		-- Ukládáme pouze hash (např. bcrypt/argon2), nikdy plaintext token!
		token_hash varchar(255) NOT NULL,
		
		-- Určuje kontext použití tokenu (ACTIVATION, PASSWORD_RESET, MAGIC_LINK, MFA)
		token_purpose varchar(50) NOT NULL,
		
		-- Reference na účet, na který se token váže (bez FOREIGN KEY)
		user_account uuid NOT NULL DEFAULT 0x00,
		
		-- Přesný čas, kdy token přestává platit
		expires_at datetime NOT NULL,
		
		-- Příznak, zda již byl token uplatněn (zamezení znovupoužití - replay attack)
		is_used bit NOT NULL DEFAULT 0,
		
		-- IP adresa, ze které byl token vyžádán (bezpečnostní a auditní důvod)
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
	PRINT 'Tabulka activation_token byla vytvořena.';
END
GO

-- =============================================================================
-- Aktualizace struktury a indexy
-- =============================================================================

-- Idempotentní založení indexu pro rychlé vyhledávání platných tokenů dle účelu
EXEC sp_create_index 
	@tname = 'activation_token', 
	@iname = 'ix_activation_token_lookup', 
	@colnames = 'token_purpose, is_used', 
	@uni = '', 
	@options = 'WHERE removed = 0 AND is_used = 0';
GO

-- =============================================================================
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- =============================================================================
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'activation_token';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('activation_token','cs','T','activation_token','Jednorázový bezpečnostní token','Jednorázové bezpečnostní tokeny','Evidence jednorázových kryptografických tokenů pro obnovu hesla, aktivaci účtu a dvoufaktorové ověření.','Technická tabulka pro ověřování časově omezených bezpečnostních odkazů.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('activation_token','en','One-Time Security Token','One-Time Security Tokens','Registry of one-time cryptographic tokens for password reset, account activation, and MFA.','Technical table for verifying time-limited security links.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'activation_token';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('activation_token','expires_at','cs','Vyprší dne (expires_at)','Okamžik vypršení platnosti tokenu','Expiruje v','Přesný čas, kdy jednorázový bezpečnostní token přestává platit.'),
	('activation_token','is_used','cs','Token již použit (is_used)','Token byl již uplatněn','Použito','Příznak zabraňující opakovanému použití jednorázového tokenu.'),
	('activation_token','request_ip','cs','IP adresa žádosti (request_ip)','IP adresa žadatele o token','IP žádosti','IP adresa, ze které bylo vyžádáno vygenerování bezpečnostního tokenu.'),
	('activation_token','token_hash','cs','Hash tokenu (token_hash)','Kryptografický otisk tokenu','Hash tokenu','SHA-256 hash jednorázového bezpečnostního tokenu.'),
	('activation_token','token_purpose','cs','Účel tokenu (token_purpose)','Účel bezpečnostního tokenu','Účel tokenu','Určuje kontext použití tokenu (PASSWORD_RESET, ACTIVATION, MFA).'),
	('activation_token','user_account','cs','Uživatelský účet (user_account)','Uživatelský účet','Uživatel','Odkaz na účet uživatele.'),
	('activation_token','expires_at','en','Expires At (expires_at)','Token Expiration Timestamp','Expires At','Exact timestamp when the one-time security token expires.'),
	('activation_token','is_used','en','Token Already Used (is_used)','Token Has Been Used','Used','Flag preventing replay/reuse of a one-time security token.'),
	('activation_token','request_ip','en','Request IP Address (request_ip)','Token Requester IP Address','Request IP','IP address from which the security token was requested.'),
	('activation_token','token_hash','en','Token Hash (token_hash)','Cryptographic Token Hash','Token Hash','SHA-256 hash of the one-time security token.'),
	('activation_token','token_purpose','en','Token Purpose (token_purpose)','Security Token Purpose','Token Purpose','Specifies the token usage context (PASSWORD_RESET, ACTIVATION, MFA).'),
	('activation_token','user_account','en','User Account (user_account)','User Account','User','Reference to the user account.');
END
GO