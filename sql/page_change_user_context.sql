EXECUTE dropni 'page_change_user_context', 'P'
GO

/* =============================================================================
 * Verze: 2026-10-29 16:00
 * Soubor: page_change_user_context.sql
 * Účel: Datová a akční procedura pro stránku změny kontextu uživatele
 *       a obousměrné schvalování přístupu mezi organizacemi (žádosti a pozvánky).
 * Vazby:
 * - Volána z PHP třídy page_change_user_context (page_change_user_context.php).
 * - Čte kontext přihlášeného uživatele z tabulky dbsession pro aktuální @@SPID.
 * - Čte a modifikuje záznamy v tabulce user_organization_access (včetně konceptů 'D')
 *   a čte tabulky organization, organization_licence, user_account a pohled
 *   v_user_organization_access.
 * Změny:
 * - 2026-10-29 16:00: Ve větvi 'available_orgs' nahrazena kontrola o.login_disabled = 0
 *   kontrolou v tabulce organization_licence (kam byl sloupec login_disabled přesunut).
 * ============================================================================= */

CREATE PROCEDURE page_change_user_context
	@subpage varchar(30),
	@target_org uniqueidentifier = NULL,
	@note varchar(max) = ''
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @user_account uniqueidentifier;
	DECLARE @login_session_uuid uniqueidentifier;
	DECLARE @sess_lang varchar(2) = 'cs';
	
	-- Získání aktuálně přihlášeného uživatele (originálu) a relace z dbsession
	SELECT	@user_account = user_account,
		@login_session_uuid = login_session_uuid,
		@sess_lang = [language]
	FROM	dbsession 
	WHERE	spid = @@SPID;

	IF @user_account IS NULL
	BEGIN
		RAISERROR('Přístup odepřen: Nelze identifikovat aktivní relaci (dbsession).', 16, 1);
		RETURN;
	END

	-- Zjištění, zda má přihlášený uživatel právo orgadmina v alespoň jedné své organizaci
	DECLARE @is_any_orgadmin bit = 0;
	IF EXISTS (
		SELECT 1 FROM user_organization_access
		WHERE user_account_uuid = @user_account
		  AND is_orgadmin = 1
		  AND record_type = 'A'
		  AND removed = 0
		  AND inactive = 0
	)
	BEGIN
		SET @is_any_orgadmin = 1;
	END

	-- 1. Seznam aktivních schválených klientských organizací uživatele
	IF @subpage = 'main'
	BEGIN
		SELECT	organization, 
			organization_name, 
			current_organization,
			is_orgadmin
		FROM	v_user_organization_access
		WHERE	user_account_uuid = @user_account
			AND organization <> 0x00
		ORDER BY organization_name;
	END

	-- 2. Globální systémové role uživatele
	ELSE IF @subpage = 'system_roles'
	BEGIN
		SELECT	is_system_admin,
			is_developer
		FROM	user_account
		WHERE	original = @user_account AND record_type = 'A' AND removed = 0;
	END

	-- 3. Seznam dalších aktivních organizací v systému, do kterých uživatel může požádat o přístup
	--    (Systémová organizace 0x00 se nabízí pouze uživatelům, kteří jsou orgadminem ve vlastní organizaci)
	ELSE IF @subpage = 'available_orgs'
	BEGIN
		SELECT	o.original AS organization_uuid,
			o.caption AS organization_name,
			o.shortname
		FROM	organization o
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
		WHERE	(o.original <> 0x00 OR @is_any_orgadmin = 1)
			AND o.record_type = 'A'
			AND o.removed = 0
			AND o.inactive = 0
			AND (o.original = 0x00 OR ISNULL(lic.login_disabled, 0) = 0)
			AND NOT EXISTS (
				SELECT 1 FROM user_organization_access a
				WHERE a.user_account_uuid = @user_account
				  AND a.organization_uuid = o.original
				  AND a.removed = 0
				  AND a.record_type IN ('A', 'D')
			)
			AND NOT (
				o.original = 0x00
				AND EXISTS (
					SELECT 1 FROM user_account u
					WHERE u.original = @user_account
					  AND u.record_type = 'A'
					  AND (u.is_system_admin = 1 OR u.is_developer = 1)
				)
			)
		ORDER BY CASE WHEN o.original = 0x00 THEN 0 ELSE 1 END, o.caption;
	END

	-- 4. Seznam otevřených žádostí uživatele a pozvánek od orgadminů (record_type = 'D')
	ELSE IF @subpage = 'pending_requests'
	BEGIN
		SELECT	a.uuid,
			a.original,
			a.organization_uuid,
			o.caption AS organization_name,
			o.shortname,
			a.approval_status,
			a.draft_author,
			a.approval_note,
			a.is_orgadmin,
			a.right_translate,
			a.date_modified,
			dbo.f_get_user_info(a.who_modified) AS who_modified_info,
			CASE WHEN a.draft_author <> @user_account AND a.draft_author <> 0x00 THEN 1 ELSE 0 END AS is_invitation
		FROM	user_organization_access a
		JOIN	organization o ON o.original = a.organization_uuid AND o.record_type = 'A' AND o.removed = 0
		WHERE	a.user_account_uuid = @user_account
			AND a.record_type = 'D'
			AND a.removed = 0
		ORDER BY a.date_modified DESC;
	END

	-- 5. Podání žádosti o přístup samotným uživatelem (vytvoření konceptu 'D' se stavem 'F')
	ELSE IF @subpage = 'request_access'
	BEGIN
		IF @target_org IS NULL RETURN;

		IF @target_org = 0x00 AND @is_any_orgadmin = 0 RETURN;

		IF NOT EXISTS (SELECT 1 FROM organization WHERE original = @target_org AND record_type = 'A' AND removed = 0 AND inactive = 0)
			RETURN;

		IF EXISTS (SELECT 1 FROM user_organization_access WHERE user_account_uuid = @user_account AND organization_uuid = @target_org AND record_type = 'A' AND removed = 0)
			RETURN;

		DECLARE @calc_orig uuid = dbo.f_generate_original('user_organization_access', @target_org, CAST(@user_account AS varchar(36)), CAST(@target_org AS varchar(36)));
		DECLARE @clean_note varchar(max) = LTRIM(RTRIM(ISNULL(@note, '')));

		BEGIN TRAN;

		IF EXISTS (SELECT 1 FROM user_organization_access WHERE user_account_uuid = @user_account AND organization_uuid = @target_org AND record_type = 'D' AND removed = 0)
		BEGIN
			UPDATE	user_organization_access
			SET	approval_status = 'F',
				draft_author = @user_account,
				approval_note = @clean_note,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE	user_account_uuid = @user_account
				AND organization_uuid = @target_org
				AND record_type = 'D'
				AND removed = 0;
		END
		ELSE
		BEGIN
			INSERT INTO user_organization_access (
				uuid, object_owner, original, record_type, approval_status,
				draft_author, approval_note, [language],
				user_account_uuid, organization_uuid, is_orgadmin, last_role, right_translate,
				who_created, who_modified
			) VALUES (
				NEWID(), @target_org, @calc_orig, 'D', 'F',
				@user_account, @clean_note, @sess_lang,
				@user_account, @target_org, CASE WHEN @target_org = 0x00 THEN 1 ELSE 0 END, CASE WHEN @target_org = 0x00 THEN 'S' ELSE 'U' END, 0,
				@login_session_uuid, @login_session_uuid
			);
		END

		COMMIT;
	END

	-- 6. Přijetí pozvánky od orgadmina / sysadmina cílové organizace samotným uživatelem
	ELSE IF @subpage = 'accept_invitation'
	BEGIN
		IF @target_org IS NULL RETURN;

		DECLARE @inv_uuid uuid;
		DECLARE @inv_orgadmin bit = 0;
		DECLARE @inv_translate bit = 0;
		DECLARE @inv_dept varchar(150) = '';
		DECLARE @inv_job varchar(150) = '';
		DECLARE @inv_mgr uuid = NULL;
		DECLARE @inv_note varchar(max) = '';
		DECLARE @inv_wdate date = NULL;
		DECLARE @inv_eval varchar(40) = '';

		SELECT TOP 1
			@inv_uuid = uuid,
			@inv_orgadmin = is_orgadmin,
			@inv_translate = right_translate,
			@inv_dept = department_name,
			@inv_job = job_title,
			@inv_mgr = manager_uuid,
			@inv_note = note,
			@inv_wdate = working_date,
			@inv_eval = evaluation_method
		FROM	user_organization_access
		WHERE	user_account_uuid = @user_account
			AND organization_uuid = @target_org
			AND record_type = 'D'
			AND approval_status = 'F'
			AND draft_author <> @user_account
			AND draft_author <> 0x00
			AND removed = 0;

		IF @inv_uuid IS NULL RETURN;

		BEGIN TRAN;

		IF @target_org = 0x00
		BEGIN
			UPDATE	user_account
			SET	is_system_admin = CASE WHEN is_system_admin = 0 AND is_developer = 0 THEN 1 ELSE is_system_admin END,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE	original = @user_account AND record_type = 'A';
		END

		IF EXISTS (SELECT 1 FROM user_organization_access WHERE user_account_uuid = @user_account AND organization_uuid = @target_org AND record_type = 'A')
		BEGIN
			UPDATE	user_organization_access
			SET	removed = 0,
				inactive = 0,
				approval_status = 'A',
				draft_author = 0x00,
				approval_note = '',
				is_orgadmin = CASE WHEN @target_org = 0x00 THEN 1 ELSE @inv_orgadmin END,
				right_translate = CASE WHEN @target_org = 0x00 THEN 1 ELSE @inv_translate END,
				last_role = CASE WHEN @target_org = 0x00 THEN 'S' WHEN @inv_orgadmin = 1 THEN 'A' ELSE 'U' END,
				department_name = CASE WHEN @inv_dept <> '' THEN @inv_dept ELSE department_name END,
				job_title = CASE WHEN @inv_job <> '' THEN @inv_job ELSE job_title END,
				manager_uuid = COALESCE(@inv_mgr, manager_uuid),
				note = CASE WHEN @inv_note <> '' THEN @inv_note ELSE note END,
				working_date = COALESCE(@inv_wdate, working_date),
				evaluation_method = CASE WHEN @inv_eval <> '' THEN @inv_eval ELSE evaluation_method END,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE	user_account_uuid = @user_account
				AND organization_uuid = @target_org
				AND record_type = 'A';

			DELETE FROM user_organization_access WHERE uuid = @inv_uuid;
		END
		ELSE
		BEGIN
			UPDATE	user_organization_access
			SET	record_type = 'A',
				approval_status = 'A',
				draft_author = 0x00,
				approval_note = '',
				is_orgadmin = CASE WHEN @target_org = 0x00 THEN 1 ELSE @inv_orgadmin END,
				right_translate = CASE WHEN @target_org = 0x00 THEN 1 ELSE @inv_translate END,
				last_role = CASE WHEN @target_org = 0x00 THEN 'S' WHEN @inv_orgadmin = 1 THEN 'A' ELSE 'U' END,
				date_modified = GETDATE(),
				who_modified = @login_session_uuid
			WHERE	uuid = @inv_uuid;
		END

		UPDATE wwwsession SET change_context_allowed = 1 WHERE user_account = @user_account;
		UPDATE dbsession SET change_context_allowed = 1 WHERE user_account = @user_account;

		COMMIT;
	END

	-- 7. Odmítnutí pozvánky od orgadmina samotným uživatelem (přepne do stavu 'R' s důvodem)
	ELSE IF @subpage = 'reject_invitation'
	BEGIN
		IF @target_org IS NULL RETURN;

		DECLARE @rej_note varchar(max) = LTRIM(RTRIM(ISNULL(@note, '')));
		IF @rej_note = '' SET @rej_note = 'Uživatel pozvánku do organizace odmítl.';

		UPDATE	user_organization_access
		SET	approval_status = 'R',
			approval_note = @rej_note,
			date_modified = GETDATE(),
			who_modified = @login_session_uuid
		WHERE	user_account_uuid = @user_account
			AND organization_uuid = @target_org
			AND record_type = 'D'
			AND draft_author <> @user_account
			AND removed = 0;
	END

	-- 8. Stažení / smazání vlastní žádosti uživatele (nebo zamítnutého záznamu)
	ELSE IF @subpage = 'cancel_request'
	BEGIN
		IF @target_org IS NULL RETURN;

		DELETE FROM user_organization_access
		WHERE	user_account_uuid = @user_account
			AND organization_uuid = @target_org
			AND record_type = 'D'
			AND (draft_author = @user_account OR approval_status = 'R');
	END
END
GO