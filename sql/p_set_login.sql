EXECUTE dropni 'p_set_login', 'P'
GO

/* =============================================================================
 * Verze: 2026-10-29 16:00
 * Soubor: p_set_login.sql
 * Procedura: p_set_login
 * Účel: Založení uživatelské relace a inicializace kontextu (tenant, práva,
 *       úroveň licence licence_level a pracovní datum working_date).
 *
 * Vazby:
 * - Voláno primárně při úspěšné autentizaci, nebo pro explicitní změnu kontextu z UI.
 * - Čte oprávnění a licence_level z pohledu v_user_organization_access
 *   (který kontroluje i login_disabled = 0 v organization_licence).
 * - Ukládá instanci přihlášení do audit_login_session a předává login_session_uuid 
 *   do aplikační relace (wwwsession -> dbsession).
 *
 * Změny:
 * - 2026-10-29 16:00: Doplněno načítání a ukládání licence_level (pro 0x00 vždy 255)
 *   a osobního pracovního data working_date z v_user_organization_access do wwwsession.
 *   Opravena kontrola dostupných organizací pro @change_context_allowed (kontrola
 *   login_disabled přesunuta z organization do organization_licence).
 * ============================================================================= */
CREATE PROCEDURE p_set_login
	@user_uuid uniqueidentifier,
	@wwwsession varchar(50),
	@client_ip varchar(200),
	@requested_org uniqueidentifier = NULL,
	@requested_role varchar(1) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @user_name varchar(80) = 'admin';
	DECLARE @display_name varchar(200) = 'System Administrator';
	DECLARE @is_sysadmin bit = 1;
	DECLARE @is_developer bit = 0;
	DECLARE @user_language varchar(2) = 'cs';
	
	DECLARE @organization uniqueidentifier = NULL;
	DECLARE @organization_name nvarchar(200) = '';
	DECLARE @licence_level tinyint = 0;
	DECLARE @working_date date = CAST(GETDATE() AS date);
	DECLARE @active_role varchar(1) = 'U';
	DECLARE @static_right_translate bit = 0;
	DECLARE @change_context_allowed bit = 0;
	
	-- Unikátní identifikátor relace pro forenzní log
	DECLARE @login_session_uuid uniqueidentifier = NEWID();

	BEGIN TRAN;

	-- Vyčištění případné staré neukončené webové relace se stejným session_id
	DELETE FROM wwwsession WHERE wwwsession = @wwwsession;

	IF @user_uuid <> 0x00 AND @user_uuid <> '00000000-0000-0000-0000-000000000000'
	BEGIN
		-- 1. Načtení základní identity a globálních oprávnění
		SELECT	@user_name = login_name,
			@display_name = LTRIM(RTRIM(ISNULL(first_name, '') + ' ' + ISNULL(last_name, ''))),
			@is_sysadmin = is_system_admin,
			@is_developer = is_developer,
			@user_language = [language]
		FROM	user_account
		WHERE	original = @user_uuid AND record_type = 'A' AND removed = 0 AND inactive = 0;

		IF @display_name = '' SET @display_name = @user_name;

		-- 2. Vyhodnocení požadovaného kontextu (Systém 0x00 vs. Běžný Tenant)
		IF @requested_org = 0x00 OR @requested_role IN ('S', 'D')
		BEGIN
			-- A. Bezpečnostní validace pro přístup do systémového jádra
			IF @requested_role = 'S' AND @is_sysadmin = 0 
				RAISERROR('Přístup odepřen: Nemáte globální roli Sysadmin.', 16, 1);
			
			IF @requested_role = 'D' AND @is_developer = 0 
				RAISERROR('Přístup odepřen: Nemáte globální roli Developer.', 16, 1);
			
			-- Zajištění platné role, pokud přišel požadavek jen přes organizaci (0x00) bez role
			IF @requested_role NOT IN ('S', 'D')
			BEGIN
				IF @is_developer = 1 SET @requested_role = 'D';
				ELSE IF @is_sysadmin = 1 SET @requested_role = 'S';
				ELSE RAISERROR('Do systémové organizace se lze přihlásit pouze s rolí Sysadmin nebo Developer.', 16, 1);
			END

			SET @organization = 0x00;
			SET @organization_name = 'Systémová organizace';
			SET @licence_level = 255;
			SET @active_role = @requested_role;
			SET @static_right_translate = 1;

			SELECT TOP 1 @working_date = ISNULL(working_date, CAST(GETDATE() AS date))
			FROM user_organization_access
			WHERE user_account_uuid = @user_uuid AND organization_uuid = 0x00 AND record_type = 'A' AND removed = 0;

			-- Paměť poslední použité role pro systémovou vrstvu
			UPDATE	user_organization_access
			SET	last_role = @active_role
			WHERE	user_account_uuid = @user_uuid AND organization_uuid = 0x00 AND record_type = 'A';
		END
		ELSE
		BEGIN
			-- B. Standardní proces pro přihlášení do klientského tenanta
			DECLARE @is_orgadmin bit = 0;
			DECLARE @last_role varchar(1) = 'U';

			SELECT TOP 1 
				@organization = v.organization,
				@organization_name = v.organization_name,
				@is_orgadmin = v.is_orgadmin,
				@last_role = v.last_role,
				@static_right_translate = v.right_translate,
				@licence_level = v.licence_level,
				@working_date = ISNULL(v.working_date, CAST(GETDATE() AS date))
			FROM	v_user_organization_access v
			WHERE	v.user_account_uuid = @user_uuid
			  AND	v.organization <> 0x00 -- Izolace jádra od standardního přihlašování
			ORDER BY 
				CASE 
					WHEN v.organization = @requested_org THEN 0
					WHEN v.organization = v.last_login_org THEN 1
					ELSE 2 
				END,
				v.date_created DESC;
			
			IF @organization IS NULL
			BEGIN
				-- Fallback pro vývojáře/sysadminy, kteří nemají přístup do žádné klientské firmy
				IF @is_sysadmin = 1 OR @is_developer = 1
				BEGIN
					SET @organization = 0x00;
					SET @organization_name = 'Systémová organizace';
					SET @licence_level = 255;
					SET @active_role = CASE WHEN @is_developer = 1 THEN 'D' ELSE 'S' END;
					SET @static_right_translate = 1;
				END
				ELSE
				BEGIN
					ROLLBACK;
					RAISERROR ('Uživateli nebyl přidělen přístup do žádné aktivní organizace.', 16, 1);
					RETURN;
				END
			END
			ELSE
			BEGIN
				-- Validace a přiřazení rolí v tenantu
				IF @requested_role IS NOT NULL
				BEGIN
					IF @requested_role = 'A' AND @is_orgadmin = 0 
						RAISERROR('Přístup odepřen: Nemáte administrátorská práva v této organizaci.', 16, 1);
					
					SET @active_role = CASE WHEN @requested_role = 'A' THEN 'A' ELSE 'U' END;

					UPDATE	user_organization_access
					SET	last_role = @active_role
					WHERE	user_account_uuid = @user_uuid AND organization_uuid = @organization AND record_type = 'A';
				END
				ELSE
				BEGIN
					-- Převzetí poslední platné role, snížení v případě odebrání práv
					SET @active_role = @last_role;
					IF @active_role = 'A' AND @is_orgadmin = 0 SET @active_role = 'U';
				END
			END
		END

		-- 3. Vyhodnocení, zda se uživateli zobrazí v UI přepínač kontextu
		DECLARE @org_count int;
		SELECT @org_count = COUNT(1) FROM v_user_organization_access WHERE user_account_uuid = @user_uuid;

		IF @is_sysadmin = 1 OR @is_developer = 1
		BEGIN
			IF @org_count > 0 OR (@is_sysadmin = 1 AND @is_developer = 1) SET @change_context_allowed = 1;
		END
		ELSE
		BEGIN
			-- Běžní uživatelé mohou na stránku změny kontextu, pokud:
			-- a) jsou ve více firmách nebo mají roli Admin,
			-- b) mají rozpracovanou / čekající žádost či pozvánku v user_organization_access (record_type = 'D'),
			-- c) v systému existuje jiná aktivní klientská organizace (bez login_disabled v organization_licence), do které mohou požádat o přístup.
			IF @org_count > 1 
				OR EXISTS (SELECT 1 FROM v_user_organization_access WHERE user_account_uuid = @user_uuid AND is_orgadmin = 1)
				OR EXISTS (SELECT 1 FROM user_organization_access WHERE user_account_uuid = @user_uuid AND record_type = 'D' AND removed = 0)
				OR EXISTS (
					SELECT 1
					FROM organization o
					OUTER APPLY (
						SELECT TOP 1 ol.login_disabled
						FROM organization_licence ol
						WHERE ol.organization_uuid = o.original
						  AND ol.record_type = 'A'
						  AND ol.removed = 0
						  AND ol.inactive = 0
						  AND ol.licence_state = 'PROCESSED'
						ORDER BY ol.date_modified DESC
					) lic
					WHERE o.original <> 0x00
					  AND o.original <> @organization
					  AND o.record_type = 'A'
					  AND o.removed = 0
					  AND o.inactive = 0
					  AND ISNULL(lic.login_disabled, 0) = 0
				)
			BEGIN
				SET @change_context_allowed = 1;
			END
		END

		-- 4. Aktualizace statistik účtu
		UPDATE	user_account 
		SET	failed_login_attempts = 0, 
			last_login_date = GETDATE(),
			last_login_organization = @organization
		WHERE	original = @user_uuid AND record_type = 'A';
	END
	ELSE 
	BEGIN
		-- C. Fallback master účtu (0x00) volaný z vnitřních skriptů bez reálné identity
		SET @organization = 0x00;
		SET @organization_name = 'Systémová organizace';
		SET @licence_level = 255;
		SET @active_role = 'S';
		SET @static_right_translate = 1;
		SET @change_context_allowed = 1;
	END

	-- [ ARCHITEKTURA PŘEKLADŮ ]
	DECLARE @effective_translate bit = 0;
	IF @active_role IN ('S', 'D')
	BEGIN
		SET @effective_translate = 1;
	END 
	ELSE IF @static_right_translate = 1 AND EXISTS (SELECT 1 FROM [language] WHERE [language] = @user_language AND translator_org = @organization)
	BEGIN
		SET @effective_translate = 1;
	END

	-- 5. Uložení forenzní stopy (Auditní log)
	INSERT INTO audit_login_session (
		uuid, user_account_uuid, organization_uuid, assumed_role, ip_address, login_time, last_request_time
	) VALUES (
		@login_session_uuid, @user_uuid, @organization, @active_role, @client_ip, GETDATE(), GETDATE()
	);

	-- 6. Zápis do sdílené paměti aplikační relace (včetně licence_level a working_date)
	INSERT INTO wwwsession (
		spid, wwwsession, user_account, login_session_uuid, user_name, organization, organization_name, display_name, 
		licence_level, [language], working_date, session_log, client_ip, login_date, request_date,
		active_role, right_translate, change_context_allowed
	) VALUES (
		@@SPID, @wwwsession, @user_uuid, @login_session_uuid, @user_name, @organization, @organization_name, @display_name, 
		@licence_level, @user_language, @working_date, 0, @client_ip, GETDATE(), GETDATE(),
		@active_role, @effective_translate, @change_context_allowed
	);

	COMMIT;
END
GO