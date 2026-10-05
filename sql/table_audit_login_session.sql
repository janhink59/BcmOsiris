/* =============================================================================
 * Verze: 2026-10-05
 * Soubor: table_audit_login_session.sql
 * Tabulka: audit_login_session
 * Popis:   Forenzní log přihlášení uživatelů. Nahrazuje původní ukládání identity
 *          do user_organization_access. Poskytuje nezměnitelný historický
 *          kontext pro auditní stopy (who_created, who_modified).
 * Vazby:   user_account_uuid -> user_account.original
 *          organization_uuid -> organization.original
 * ============================================================================= */

IF OBJECT_ID('audit_login_session') IS NULL
BEGIN
	CREATE TABLE audit_login_session (
		uuid uuid NOT NULL,
		
		user_account_uuid uuid NOT NULL,           -- Identita přihlášeného uživatele (originál z user_account)
		organization_uuid uuid NOT NULL,           -- Tenant, do kterého uživatel vstoupil (originál z organization)
		
		assumed_role varchar(1) NOT NULL,          -- Zvolená efektivní role (U=User, A=Admin, S=Sysadmin, D=Developer)
		
		login_time datetime NOT NULL DEFAULT getdate(),
		last_request_time datetime NOT NULL DEFAULT getdate(), -- Sledování aktivity pro určení délky relace
		logout_time datetime NULL,                 -- Čas explicitního odhlášení nebo expirace
		
		ip_address varchar(200) NOT NULL DEFAULT '', -- IP adresa včetně forwarded hlaviček
		
		CONSTRAINT pk_audit_login_session PRIMARY KEY (uuid)
	);
	PRINT 'Tabulka audit_login_session byla vytvorena.';
END
GO

-- Idempotentní vytvoření indexů pro rychlé dohledávání historie konkrétního uživatele nebo tenanta
EXEC sp_create_index 
	@tname = 'audit_login_session', 
	@iname = 'ix_audit_login_session_user', 
	@colnames = 'user_account_uuid, login_time', 
	@uni = '', 
	@options = '';
GO

EXEC sp_create_index 
	@tname = 'audit_login_session', 
	@iname = 'ix_audit_login_session_org', 
	@colnames = 'organization_uuid, login_time', 
	@uni = '', 
	@options = '';
GO