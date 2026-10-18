EXECUTE dropni 'form_org_users', 'P'
GO

/* =============================================================================
 * Verze: 2026-10-18 17:15
 * Soubor: form_org_users.sql
 * Procedura: form_org_users
 * Účel: Bezpečné uložení, úprava, pozvání nebo schválení přístupu uživatele
 *       v rámci tenanta s oddělením osobních dat (user_account) od oprávnění
 *       v organizaci (user_organization_access).
 * 
 * Architektura a bezpečnost:
 * - Oboustranný souhlas (SSC):
 *   1. Pokud orgadmin přidává nového uživatele a zadaný @login_name již v tabulce
 *      user_account existuje (z jiné organizace), procedura NEZASAHUJE do jeho
 *      osobních dat v user_account, ale založí v user_organization_access koncept
 *      pozvánky (record_type = 'D', approval_status = 'F', draft_author = @current_user_account),
 *      který musí uživatel sám přijmout na stránce page_change_user_context.
 *   2. Pokud uživatel požádal o přístup do této organizace (record_type = 'D',
 *      draft_author = @resolved_user_uuid), orgadmin může žádost schválit (@action = 'APPROVE')
 *      nebo odmítnout (@action = 'REJECT').
 *   3. Při schválení přístupu do systémové organizace (0x00) se uživateli v user_account
 *      automaticky nastaví is_system_admin = 1 (pokud nebyl zvolen Developer) a volitelně
 *      is_developer = @is_developer, protože v 0x00 uživatel pracuje přirozeně jako Sysadmin / Developer.
 *   4. Jakmile je přístup uživatele v organizaci schválen (record_type = 'A' AND removed = 0),
 *      mají orgadmini této organizace právo upravovat i jeho osobní údaje v user_account,
 *      zatímco oprávnění (is_orgadmin, right_translate, remove_access) řídí vždy jen pro svou organizaci.
 * - Ochrana proti eskalaci privilegií: Běžný admin (A) nemůže přidělovat 
 *   ani odebírat globální role (S, D). Tyto parametry jsou pro něj ignorovány.
 * - Ochrana před sebevražedným zásahem: Uživatel nemůže sám sebe deaktivovat, 
 *   zbavit se org. administrátora ani globálních rolí.
 * - Audit: who_created/who_modified přebírá UUID z login_session_uuid.
 * ============================================================================= */
CREATE PROCEDURE form_org_users
	@organization_uuid uniqueidentifier,
	@user_original uniqueidentifier = NULL,
	@action varchar(20) = 'SAVE',
	@login_name varchar(100) = '',
	@email varchar(200) = '',
	@first_name varchar(100) = '',
	@last_name varchar(100) = '',
	@user_title_before varchar(40) = '',
	@user_title_after varchar(40) = '',
	@phone varchar(50) = '',
	@mobile varchar(50) = '',
	@department_name varchar(150) = '',
	@job_title varchar(150) = '',
	@note varchar(max) = '',
	@is_orgadmin bit = 0,
	@right_translate bit = 0,
	@is_system_admin bit = 0,
	@is_developer bit = 0,
	@allow_local_login bit = 1,
	@remove_access bit = 0,
	@deactivate_global bit = 0,
	@approval_note varchar(max) = ''
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	
	DECLARE @resolved_user_uuid uniqueidentifier = NULLIF(@user_original, 0x00);
	DECLARE @is_new_selection bit = CASE WHEN @resolved_user_uuid IS NULL THEN 1 ELSE 0 END;
	
	-- Získání kontextu přístupu a identity přihlášeného správce PŘÍMO ze session
	DECLARE @login_session_uuid uniqueidentifier;
	DECLARE @current_user_account uniqueidentifier;
	DECLARE @active_role varchar(1);
	DECLARE @sess_lang varchar(2) = 'cs';
	
	SELECT	@login_session_uuid = login_session_uuid,
		@current_user_account = user_account,
		@active_role = active_role,
		@sess_lang = [language]
	FROM	dbsession 
	WHERE	spid = @@SPID;
	
	IF @login_session_uuid IS NULL
	BEGIN
		RAISERROR('Bezpečnostní chyba: Nelze ověřit identitu relace (dbsession chybí).', 16, 1);
		RETURN;
	END

	SET @login_name = LTRIM(RTRIM(ISNULL(@login_name, '')));
	SET @first_name = LTRIM(RTRIM(ISNULL(@first_name, '')));
	SET @last_name = LTRIM(RTRIM(ISNULL(@last_name, '')));
	SET @email = LTRIM(RTRIM(ISNULL(@email, '')));
	SET @approval_note = LTRIM(RTRIM(ISNULL(@approval_note, '')));

	-- Pokud jde o zadání v režimu "+ Nový uživatel", pokusíme se najít existující účet podle unikátního login_name
	IF @resolved_user_uuid IS NULL AND @login_name <> ''
	BEGIN
		SELECT @resolved_user_uuid = original 
		FROM user_account 
		WHERE login_name = @login_name AND record_type = 'A' AND removed = 0;
	END

	-- V systémové organizaci (0x00) pracuje přijatý uživatel přirozeně jako Sysadmin (příp. Developer)
	IF @organization_uuid = 0x00 AND @active_role IN ('S', 'D') AND @remove_access = 0
	BEGIN
		IF @is_system_admin = 0 AND @is_developer = 0
			SET @is_system_admin = 1;
		SET @is_orgadmin = 1;
		SET @right_translate = 1;
	END

	-- =========================================================================
	-- VĚTEV 1: ZRUŠENÍ POZVÁNKY NEBO ODMÍTNUTÍ ŽÁDOSTI (@action = 'CANCEL_INVITE' / 'REJECT')
	-- =========================================================================
	IF @action = 'CANCEL_INVITE' AND @resolved_user_uuid IS NOT NULL
	BEGIN
		DELETE FROM user_organization_access
		WHERE user_account_uuid = @resolved_user_uuid
		  AND organization_uuid = @organization_uuid
		  AND record_type = 'D';
		RETURN;
	END

	IF @action = 'REJECT' AND @resolved_user_uuid IS NOT NULL
	BEGIN
		IF @approval_note = '' SET @approval_note = 'Žádost o přístup byla zamítnuta administrátorem organizace.';

		UPDATE user_organization_access
		SET approval_status = 'R',
			approval_note = @approval_note,
			date_modified = GETDATE(),
			who_modified = @login_session_uuid
		WHERE user_account_uuid = @resolved_user_uuid
		  AND organization_uuid = @organization_uuid
		  AND record_type = 'D'
		  AND removed = 0;
		RETURN;
	END

	-- =========================================================================
	-- VĚTEV 2: SCHVÁLENÍ ŽÁDOSTI UŽIVATELE O PŘÍSTUP (@action = 'APPROVE')
	-- =========================================================================
	IF @action = 'APPROVE' AND @resolved_user_uuid IS NOT NULL
	BEGIN
		DECLARE @req_uuid uuid;

		-- Orgadmin / Sysadmin smí schválit žádost, kterou podal sám uživatel (draft_author = @resolved_user_uuid)
		SELECT TOP 1 @req_uuid = uuid
		FROM user_organization_access
		WHERE user_account_uuid = @resolved_user_uuid
		  AND organization_uuid = @organization_uuid
		  AND record_type = 'D'
		  AND draft_author = @resolved_user_uuid
		  AND removed = 0;

		IF @req_uuid IS NULL RETURN;

		DECLARE @approved_role varchar(1) = CASE
			WHEN @organization_uuid = 0x00 THEN (CASE WHEN @is_developer = 1 AND @is_system_admin = 0 THEN 'D' ELSE 'S' END)
			WHEN @is_orgadmin = 1 THEN 'A'
			ELSE 'U'
		END;

		BEGIN TRAN;

		-- Pokud schvaluje Sysadmin/Developer (zejména v 0x00), uložíme rovnou i globální příznaky účtu
		IF @active_role IN ('S', 'D')
		BEGIN
			UPDATE user_account
			SET is_system_admin = @is_system_admin,
				is_developer = @is_developer,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE original = @resolved_user_uuid AND record_type = 'A';
		END

		IF EXISTS (SELECT 1 FROM user_organization_access WHERE user_account_uuid = @resolved_user_uuid AND organization_uuid = @organization_uuid AND record_type = 'A')
		BEGIN
			UPDATE user_organization_access
			SET removed = 0,
				inactive = 0,
				approval_status = 'A',
				draft_author = 0x00,
				approval_note = '',
				is_orgadmin = @is_orgadmin,
				right_translate = @right_translate,
				last_role = @approved_role,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE user_account_uuid = @resolved_user_uuid
			  AND organization_uuid = @organization_uuid
			  AND record_type = 'A';

			DELETE FROM user_organization_access WHERE uuid = @req_uuid;
		END
		ELSE
		BEGIN
			UPDATE user_organization_access
			SET record_type = 'A',
				approval_status = 'A',
				draft_author = 0x00,
				approval_note = '',
				is_orgadmin = @is_orgadmin,
				right_translate = @right_translate,
				last_role = @approved_role,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE uuid = @req_uuid;
		END

		UPDATE wwwsession SET change_context_allowed = 1 WHERE user_account = @resolved_user_uuid;
		UPDATE dbsession SET change_context_allowed = 1 WHERE user_account = @resolved_user_uuid;

		COMMIT;
		RETURN;
	END

	-- =========================================================================
	-- VĚTEV 3: STANDARDNÍ ZÁPIS / POZVÁNKA (@action = 'SAVE')
	-- =========================================================================
	-- Načtení stávajících globálních rolí a stavu členství v aktuální organizaci
	DECLARE @current_sysadmin bit = 0;
	DECLARE @current_developer bit = 0;
	DECLARE @current_allow_local bit = 1;
	DECLARE @has_active_membership bit = 0;

	IF @resolved_user_uuid IS NOT NULL
	BEGIN
		SELECT	@current_sysadmin = is_system_admin,
			@current_developer = is_developer,
			@current_allow_local = allow_local_login
		FROM	user_account
		WHERE	original = @resolved_user_uuid AND record_type = 'A';

		IF EXISTS (
			SELECT 1 FROM user_organization_access
			WHERE user_account_uuid = @resolved_user_uuid
			  AND organization_uuid = @organization_uuid
			  AND record_type = 'A'
			  AND removed = 0
		)
		BEGIN
			SET @has_active_membership = 1;
		END
	END

	-- BEZPEČNOSTNÍ POJISTKA 1: Ochrana před eskalací privilegií z úrovně lokálního tenanta
	IF @active_role NOT IN ('S', 'D')
	BEGIN
		SET @is_system_admin = @current_sysadmin;
		SET @is_developer = @current_developer;
		IF @resolved_user_uuid IS NOT NULL SET @allow_local_login = @current_allow_local;
	END

	-- BEZPEČNOSTNÍ POJISTKA 2: Ochrana před ztrátou kontroly nad vlastním účtem
	IF @resolved_user_uuid = @current_user_account
	BEGIN
		SET @remove_access = 0;
		SET @deactivate_global = 0;
		SET @is_orgadmin = 1;
		SET @is_system_admin = @current_sysadmin;
		SET @is_developer = @current_developer;
	END

	-- Pokud Sysadmin odebírá uživateli přístup ze systémové organizace (0x00), odebereme mu i globální příznaky S/D
	IF @organization_uuid = 0x00 AND @remove_access = 1 AND @resolved_user_uuid <> @current_user_account
	BEGIN
		SET @is_system_admin = 0;
		SET @is_developer = 0;
	END

	DECLARE @default_role varchar(1) = CASE
		WHEN @organization_uuid = 0x00 THEN (CASE WHEN @is_developer = 1 AND @is_system_admin = 0 THEN 'D' ELSE 'S' END)
		WHEN @is_orgadmin = 1 THEN 'A'
		ELSE 'U'
	END;

	DECLARE @full_caption varchar(200) = LTRIM(RTRIM(
		CASE WHEN @user_title_before <> '' THEN @user_title_before + ' ' ELSE '' END +
		@first_name + ' ' + @last_name +
		CASE WHEN @user_title_after <> '' THEN ' ' + @user_title_after ELSE '' END
	));
	IF @full_caption = '' SET @full_caption = @login_name;

	BEGIN TRAN;

	-- A. ZCELA NOVÝ ÚČET V SYSTÉMU (login_name dosud v user_account neexistuje) -> založíme účet 'A' i přístup 'A'
	IF @resolved_user_uuid IS NULL
	BEGIN
		IF @login_name = ''
		BEGIN
			ROLLBACK;
			RAISERROR('Přihlašovací jméno (login_name) musí být vyplněno.', 16, 1);
			RETURN;
		END

		SET @resolved_user_uuid = NEWID();
		
		INSERT INTO user_account (
			uuid, object_owner, original, record_type, approval_status,
			caption, login_name, email,
			user_title_before, first_name, last_name, user_title_after,
			phone, mobile, department_name, job_title, note,
			allow_local_login, is_system_admin, is_developer, inactive,
			last_login_organization, who_created, who_modified
		) VALUES (
			@resolved_user_uuid, 0x00, @resolved_user_uuid, 'A', 'A',
			@full_caption, @login_name, @email,
			@user_title_before, @first_name, @last_name, @user_title_after,
			@phone, @mobile, @department_name, @job_title, @note,
			@allow_local_login, @is_system_admin, @is_developer, @deactivate_global,
			@organization_uuid, @login_session_uuid, @login_session_uuid
		);

		DECLARE @new_acc_orig uuid = dbo.f_generate_original('user_organization_access', @organization_uuid, CAST(@resolved_user_uuid AS varchar(36)), CAST(@organization_uuid AS varchar(36)));

		INSERT INTO user_organization_access (
			uuid, object_owner, original, record_type, approval_status,
			user_account_uuid, organization_uuid, is_orgadmin, right_translate,
			last_role, removed, who_created, who_modified
		) VALUES (
			@new_acc_orig, @organization_uuid, @new_acc_orig, 'A', 'A',
			@resolved_user_uuid, @organization_uuid, @is_orgadmin, @right_translate,
			@default_role, 0,
			@login_session_uuid, @login_session_uuid
		);

		COMMIT;
		RETURN;
	END

	-- B. ÚČET JIŽ V USER_ACCOUNT EXISTUJE, ALE DOSUD NEMÁ SCHVÁLENÝ PŘÍSTUP V TÉTO ORGANIZACI
	--    Orgadmin nesmí přepsat jeho osobní údaje bez souhlasu uživatele -> vytvoří/aktualizuje pozvánku 'D'!
	IF @has_active_membership = 0 AND NOT EXISTS (
		SELECT 1 FROM user_organization_access
		WHERE user_account_uuid = @resolved_user_uuid
		  AND organization_uuid = @organization_uuid
		  AND record_type = 'A'
		  AND removed = 1
		  AND @is_new_selection = 0
	)
	BEGIN
		-- Pokud uživatel sám mezitím podal žádost o přístup (draft_author = @resolved_user_uuid), rovnou ji schválíme
		IF EXISTS (
			SELECT 1 FROM user_organization_access
			WHERE user_account_uuid = @resolved_user_uuid
			  AND organization_uuid = @organization_uuid
			  AND record_type = 'D'
			  AND draft_author = @resolved_user_uuid
			  AND removed = 0
		)
		BEGIN
			IF @active_role IN ('S', 'D')
			BEGIN
				UPDATE user_account
				SET is_system_admin = @is_system_admin,
					is_developer = @is_developer,
					date_modified = GETDATE(),
					who_modified = @login_session_uuid
				WHERE original = @resolved_user_uuid AND record_type = 'A';
			END

			UPDATE user_organization_access
			SET record_type = 'A',
				approval_status = 'A',
				draft_author = 0x00,
				approval_note = '',
				is_orgadmin = @is_orgadmin,
				right_translate = @right_translate,
				last_role = @default_role,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE user_account_uuid = @resolved_user_uuid
			  AND organization_uuid = @organization_uuid
			  AND record_type = 'D'
			  AND draft_author = @resolved_user_uuid
			  AND removed = 0;
		END
		ELSE IF EXISTS (
			SELECT 1 FROM user_organization_access
			WHERE user_account_uuid = @resolved_user_uuid
			  AND organization_uuid = @organization_uuid
			  AND record_type = 'D'
			  AND removed = 0
		)
		BEGIN
			-- Aktualizace existující pozvánky vystavené orgadminem
			UPDATE user_organization_access
			SET approval_status = 'F',
				draft_author = @current_user_account,
				approval_note = @approval_note,
				is_orgadmin = @is_orgadmin,
				right_translate = @right_translate,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE user_account_uuid = @resolved_user_uuid
			  AND organization_uuid = @organization_uuid
			  AND record_type = 'D'
			  AND removed = 0;
		END
		ELSE
		BEGIN
			-- Založení nové pozvánky ('D', 'F') čekající na přijetí uživatelem v page_change_user_context
			DECLARE @inv_orig uuid = dbo.f_generate_original('user_organization_access', @organization_uuid, CAST(@resolved_user_uuid AS varchar(36)), CAST(@organization_uuid AS varchar(36)));

			INSERT INTO user_organization_access (
				uuid, object_owner, original, record_type, approval_status,
				draft_author, approval_note, [language],
				user_account_uuid, organization_uuid, is_orgadmin, right_translate,
				last_role, removed, who_created, who_modified
			) VALUES (
				NEWID(), @organization_uuid, @inv_orig, 'D', 'F',
				@current_user_account, @approval_note, @sess_lang,
				@resolved_user_uuid, @organization_uuid, @is_orgadmin, @right_translate,
				@default_role, 0,
				@login_session_uuid, @login_session_uuid
			);
		END

		-- Aby uživatel pozvánku viděl na stránce Změna kontextu, zapneme mu change_context_allowed v běžící relaci
		UPDATE wwwsession SET change_context_allowed = 1 WHERE user_account = @resolved_user_uuid;
		UPDATE dbsession SET change_context_allowed = 1 WHERE user_account = @resolved_user_uuid;

		COMMIT;
		RETURN;
	END

	-- C. UŽIVATEL JE SCHVÁLENÝM ČLENEM TÉTO ORGANIZACE (record_type = 'A')
	--    Orgadmin této organizace smí upravovat jeho osobní údaje v user_account i lokální práva v organizaci.
	UPDATE user_account
	SET caption = @full_caption,
		email = @email,
		user_title_before = @user_title_before,
		first_name = @first_name,
		last_name = @last_name,
		user_title_after = @user_title_after,
		phone = @phone,
		mobile = @mobile,
		department_name = @department_name,
		job_title = @job_title,
		note = @note,
		allow_local_login = @allow_local_login,
		is_system_admin = @is_system_admin,
		is_developer = @is_developer,
		inactive = CASE WHEN @active_role IN ('S', 'D') THEN @deactivate_global ELSE inactive END,
		date_modified = GETDATE(),
		who_modified = @login_session_uuid
	WHERE original = @resolved_user_uuid AND record_type = 'A';

	UPDATE user_organization_access
	SET is_orgadmin = @is_orgadmin,
		right_translate = @right_translate,
		last_role = @default_role,
		removed = @remove_access,
		date_modified = GETDATE(),
		who_modified = @login_session_uuid
	WHERE user_account_uuid = @resolved_user_uuid
	  AND organization_uuid = @organization_uuid
	  AND record_type = 'A';

	-- Aktualizace příznaku přepínání kontextu v aktivních relacích upravovaného uživatele
	UPDATE wwwsession SET change_context_allowed = 1 WHERE user_account = @resolved_user_uuid;
	UPDATE dbsession SET change_context_allowed = 1 WHERE user_account = @resolved_user_uuid;

	COMMIT;
END
GO