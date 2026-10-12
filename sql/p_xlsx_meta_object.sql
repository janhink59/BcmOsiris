/* =============================================================================
 * PROCEDURA: p_xlsx_meta_object
 * Účel: Zajišťuje import dat ze staging tabulek (vygenerovaných z Excelu) 
 *       do fyzických tabulek systému. Řeší unpivot překladů do 'L' vrstev.
 * ============================================================================= */

IF OBJECT_ID('p_xlsx_meta_object', 'P') IS NOT NULL DROP PROCEDURE p_xlsx_meta_object;
GO

CREATE PROCEDURE p_xlsx_meta_object
	@import_mode varchar(1) = '1'
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Získání auditního kontextu z aktuální relace
	DECLARE @user_session uniqueidentifier;
	SELECT @user_session = login_session_uuid FROM dbsession WHERE spid = @@SPID;
	IF @user_session IS NULL SET @user_session = 0x00;

	-- =========================================================================
	-- 1. Zpracování záložky: meta_object
	-- =========================================================================
	IF OBJECT_ID('XLSX_meta_object') IS NOT NULL
	BEGIN
		-- A) Zpracování Master záznamů ('A')
		
		-- Update existujících 'A' záznamů
		UPDATE t
		SET 
			t.system_role = ISNULL(s.system_role, 'S'),
			t.module = ISNULL(s.module, ''),
			t.date_modified = GETDATE(),
			t.who_modified = @user_session
		FROM meta_object t
		JOIN XLSX_meta_object s 
			ON dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code) = t.original
		WHERE t.object_owner = 0x00 AND t.record_type = 'A';

		-- Insert nových 'A' záznamů
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status,
			object_type, builtin_code, system_role, module,
			date_created, who_created, date_modified, who_modified
		)
		SELECT 
			dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code),
			0x00,
			dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code),
			'A', 'A',
			s.object_type, s.builtin_code, ISNULL(s.system_role, 'S'), ISNULL(s.module, ''),
			GETDATE(), @user_session, GETDATE(), @user_session
		FROM XLSX_meta_object s
		WHERE NOT EXISTS (
			SELECT 1 FROM meta_object t 
			WHERE t.original = dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code)
			  AND t.object_owner = 0x00 AND t.record_type = 'A'
		);

		-- B) Zpracování překladů ('L') - Čeština (CS)
		-- Kontrola, zda uživatel v Excelu sloupec vůbec nechal
		IF COL_LENGTH('XLSX_meta_object', 'caption_cs') IS NOT NULL
		BEGIN
			-- Update existujících CS překladů
			UPDATE t
			SET 
				t.caption = s.caption_cs,
				t.description = ISNULL(s.description_cs, ''),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN XLSX_meta_object s 
				ON dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code) = t.original
			WHERE t.object_owner = 0x00 AND t.record_type = 'L' AND t.language = 'cs';

			-- Insert chybějících CS překladů
			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, language,
				object_type, builtin_code, system_role, module,
				caption, description,
				date_created, who_created, date_modified, who_modified
			)
			SELECT 
				NEWID(), 0x00, dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code), 'L', 'A', 'cs',
				s.object_type, s.builtin_code, ISNULL(s.system_role, 'S'), ISNULL(s.module, ''),
				s.caption_cs, ISNULL(s.description_cs, ''),
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM XLSX_meta_object s
			WHERE s.caption_cs IS NOT NULL AND s.caption_cs <> '' AND NOT EXISTS (
				SELECT 1 FROM meta_object t 
				WHERE t.original = dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code)
				  AND t.object_owner = 0x00 AND t.record_type = 'L' AND t.language = 'cs'
			);
		END

		-- C) Zpracování překladů ('L') - Angličtina (EN)
		IF COL_LENGTH('XLSX_meta_object', 'caption_en') IS NOT NULL
		BEGIN
			-- Update existujících EN překladů
			UPDATE t
			SET 
				t.caption = s.caption_en,
				t.description = ISNULL(s.description_en, ''),
				t.date_modified = GETDATE(),
				t.who_modified = @user_session
			FROM meta_object t
			JOIN XLSX_meta_object s 
				ON dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code) = t.original
			WHERE t.object_owner = 0x00 AND t.record_type = 'L' AND t.language = 'en';

			-- Insert chybějících EN překladů
			INSERT INTO meta_object (
				uuid, object_owner, original, record_type, approval_status, language,
				object_type, builtin_code, system_role, module,
				caption, description,
				date_created, who_created, date_modified, who_modified
			)
			SELECT 
				NEWID(), 0x00, dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code), 'L', 'A', 'en',
				s.object_type, s.builtin_code, ISNULL(s.system_role, 'S'), ISNULL(s.module, ''),
				s.caption_en, ISNULL(s.description_en, ''),
				GETDATE(), @user_session, GETDATE(), @user_session
			FROM XLSX_meta_object s
			WHERE s.caption_en IS NOT NULL AND s.caption_en <> '' AND NOT EXISTS (
				SELECT 1 FROM meta_object t 
				WHERE t.original = dbo.f_generate_original('meta_object', 0x00, s.object_type, s.builtin_code)
				  AND t.object_owner = 0x00 AND t.record_type = 'L' AND t.language = 'en'
			);
		END

		EXEC insert_request_message 'Záložka meta_object byla úspěšně zpracována', 1;
	END
	ELSE
	BEGIN
		EXEC insert_request_message 'Záložka meta_object v souboru chybí, import objektů přeskočen', 2;
	END

	-- =========================================================================
	-- 2. Prostor pro další budoucí záložky (např. global_phrases)
	-- =========================================================================

END
GO