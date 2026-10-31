/* =============================================================================
 * Verze: 2026-11-01 11:15
 * Soubor: p_phrases.sql
 * Procedury: dbo.p_get_phrases, dbo.p_auto_register_phrase
 * Účel:   1. dbo.p_get_phrases načte dávkově 'A' a 'L' záznamy frází (s filtrem
 *            fallback_order < 1000 z dbo.f_language_list) pro seznam zdrojových
 *            tříd (@sources_csv oddělených čárkou) pomocí indexovaných tabulkových
 *            proměnných (@src, @fl, @sy, @my, @mix) a přímého Index Seeku.
 *         2. dbo.p_auto_register_phrase idempotentně zaregistruje dosud
 *            neexistující frázi do meta_phrase ('A' + symetrické 'L') a zajistí
 *            existenci zdrojového objektu typu 'P' v meta_object.
 * Vazby:  - Voláno z PHP třídy phrase_manager (phrase_manager.php).
 *         - Využívá funkce dbo.f_string_list, dbo.f_language_list,
 *           dbo.f_generate_original a kontext relace z tabulky dbsession.
 * ============================================================================= */

EXECUTE dropni 'p_get_phrases', 'P';
EXECUTE dropni 'p_auto_register_phrase', 'P';
GO

CREATE PROCEDURE dbo.p_get_phrases
	@sources_csv varchar(max),                                                 -- Seznam source_code oddělených čárkou
	@requested_lang varchar(2) = NULL                                          -- Volitelný explicitní kód jazyka
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @org_uuid uniqueidentifier = 0x00;
	DECLARE @sess_lang varchar(2) = NULLIF(LTRIM(RTRIM(@requested_lang)), '');

	SELECT TOP 1
		@org_uuid = ISNULL(organization, 0x00),
		@sess_lang = COALESCE(@sess_lang, NULLIF(LTRIM(RTRIM([language])), ''))
	FROM dbsession
	WHERE spid = @@SPID;

	-- 1. Rozparsování seznamu požadovaných source_code do indexované tabulkové proměnné
	DECLARE @src TABLE (
		source_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY
	);
	INSERT INTO @src (source_code)
	SELECT DISTINCT LEFT(s, 80)
	FROM dbo.f_string_list(@sources_csv)
	WHERE s IS NOT NULL AND s <> '';

	IF NOT EXISTS (SELECT 1 FROM @src)
		RETURN;

	-- 2. Načtení fallback řetězce jazyků (< 1000)
	DECLARE @fl TABLE (
		[language] varchar(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
		fallback_order int NOT NULL
	);
	INSERT INTO @fl ([language], fallback_order)
	SELECT [language], fallback_order
	FROM dbo.f_language_list(@sess_lang)
	WHERE fallback_order < 1000;

	-- 3. Systémové 'A' záznamy frází
	DECLARE @sy TABLE (
		original uniqueidentifier NOT NULL PRIMARY KEY,
		sys_uuid uniqueidentifier NOT NULL
	);
	INSERT INTO @sy (original, sys_uuid)
	SELECT rc.original, rc.uuid
	FROM meta_phrase rc
	JOIN @src s ON s.source_code = rc.source_code
	WHERE rc.object_owner = 0x00
	  AND rc.record_type = 'A'
	  AND rc.removed = 0
	  AND rc.inactive = 0;

	-- 4. Klientské 'A' overridy frází (pokud uživatel nepracuje v 0x00)
	DECLARE @my TABLE (
		original uniqueidentifier NOT NULL PRIMARY KEY,
		my_uuid uniqueidentifier NOT NULL
	);
	IF @org_uuid <> 0x00
	BEGIN
		INSERT INTO @my (original, my_uuid)
		SELECT rc.original, rc.uuid
		FROM meta_phrase rc
		JOIN @src s ON s.source_code = rc.source_code
		WHERE rc.object_owner = @org_uuid
		  AND rc.record_type = 'A'
		  AND rc.removed = 0
		  AND rc.inactive = 0;
	END

	-- 5. Složení vítězných 'A' záznamů
	DECLARE @mix TABLE (
		original uniqueidentifier NOT NULL PRIMARY KEY,
		win_uuid uniqueidentifier NOT NULL,
		sys_uuid uniqueidentifier NULL
	);
	INSERT INTO @mix (original, win_uuid, sys_uuid)
	SELECT my.original, my.my_uuid, sy.sys_uuid
	FROM @my my
	LEFT JOIN @sy sy ON sy.original = my.original
	UNION ALL
	SELECT sy.original, sy.sys_uuid, sy.sys_uuid
	FROM @sy sy
	LEFT JOIN @my my ON my.original = sy.original
	WHERE my.original IS NULL;

	-- 6. Výsledný result-set ('A' záznamy + podřízené 'L' záznamy ve fallback řetězci)
	SELECT
		'A' AS row_kind,
		m.original,
		m.source_code,
		m.builtin_code,
		m.[language],
		CASE WHEN m.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant,
		ISNULL(fl.fallback_order, 1000) AS fallback_order,
		COALESCE(NULLIF(CAST(m.caption AS NVARCHAR(MAX)), ''), CAST(o.caption AS NVARCHAR(MAX)), '') AS caption,
		COALESCE(NULLIF(CAST(m.helptext AS NVARCHAR(MAX)), ''), CAST(o.helptext AS NVARCHAR(MAX)), '') AS helptext,
		COALESCE(NULLIF(CAST(m.svg_icon AS NVARCHAR(MAX)), ''), CAST(o.svg_icon AS NVARCHAR(MAX)), '') AS svg_icon,
		COALESCE(NULLIF(m.css_class, ''), o.css_class, '') AS css_class
	FROM @mix mk
	JOIN meta_phrase m ON m.uuid = mk.win_uuid
	LEFT JOIN meta_phrase o ON o.uuid = mk.sys_uuid
	LEFT JOIN @fl fl ON fl.[language] = m.[language]

	UNION ALL

	SELECT
		'L' AS row_kind,
		l.original,
		m.source_code,
		m.builtin_code,
		l.[language],
		CASE WHEN l.object_owner <> 0x00 THEN 1 ELSE 0 END AS is_tenant,
		fl.fallback_order,
		CAST(l.caption AS NVARCHAR(MAX)) AS caption,
		CAST(l.helptext AS NVARCHAR(MAX)) AS helptext,
		'' AS svg_icon,
		'' AS css_class
	FROM @mix mk
	JOIN meta_phrase m ON m.uuid = mk.win_uuid
	JOIN meta_phrase l
		ON l.original = mk.original
		AND l.record_type = 'L'
		AND l.removed = 0
		AND (l.object_owner = 0x00 OR l.object_owner = @org_uuid)
	JOIN @fl fl ON fl.[language] = l.[language]
	ORDER BY row_kind ASC, fallback_order ASC, is_tenant DESC;
END
GO

CREATE PROCEDURE dbo.p_auto_register_phrase
	@source_code varchar(80),                                                  -- Zdrojová PHP třída nebo stránka
	@builtin_code varchar(80),                                                 -- Kód fráze v rámci třídy
	@caption varchar(max),                                                     -- Výchozí český text fráze
	@svg_icon varchar(max) = '',                                               -- Volitelná vektorová ikona SVG
	@css_class varchar(200) = ''                                               -- Volitelná CSS třída tlačítka
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	SET @source_code = ISNULL(NULLIF(LTRIM(RTRIM(@source_code)), ''), 'global_phrase');
	SET @builtin_code = LTRIM(RTRIM(ISNULL(@builtin_code, '')));

	IF @builtin_code = ''
		RETURN;

	DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
	DECLARE @user_session uniqueidentifier = @sys_owner;

	SELECT TOP 1 @user_session = ISNULL(login_session_uuid, @sys_owner)
	FROM dbsession
	WHERE spid = @@SPID;

	DECLARE @obj_orig uuid = dbo.f_generate_original('meta_object', @sys_owner, 'P', @source_code);
	DECLARE @orig uuid = dbo.f_generate_original('meta_phrase', @sys_owner, @source_code, @builtin_code);

	IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @obj_orig AND object_owner = @sys_owner AND record_type = 'A' AND removed = 0)
	BEGIN
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin, object_type, builtin_code, system_role, caption,
			who_created, who_modified
		) VALUES (
			@obj_orig, @sys_owner, @obj_orig, 'A', 'A', 'cs',
			'AUTO_DISCOVERED', 'P', @source_code, 'U', @source_code,
			@user_session, @user_session
		);
	END

	IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @obj_orig AND object_owner = @sys_owner AND record_type = 'L' AND [language] = 'cs' AND removed = 0)
	BEGIN
		INSERT INTO meta_object (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin, object_type, builtin_code, system_role, caption,
			who_created, who_modified
		) VALUES (
			NEWID(), @sys_owner, @obj_orig, 'L', 'A', 'cs',
			'AUTO_DISCOVERED', 'P', @source_code, 'U', @source_code,
			@user_session, @user_session
		);
	END

	IF NOT EXISTS (SELECT 1 FROM meta_phrase WHERE original = @orig AND object_owner = @sys_owner AND record_type = 'A' AND removed = 0)
	BEGIN
		INSERT INTO meta_phrase (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin, source_code, builtin_code, caption, svg_icon, css_class,
			who_created, who_modified
		) VALUES (
			@orig, @sys_owner, @orig, 'A', 'A', 'cs',
			'AUTO_DISCOVERED', @source_code, @builtin_code, ISNULL(@caption, ''), ISNULL(@svg_icon, ''), ISNULL(@css_class, ''),
			@user_session, @user_session
		);

		INSERT INTO meta_phrase (
			uuid, object_owner, original, record_type, approval_status, [language],
			import_origin, source_code, builtin_code, caption, svg_icon, css_class,
			who_created, who_modified
		) VALUES (
			NEWID(), @sys_owner, @orig, 'L', 'A', 'cs',
			'AUTO_DISCOVERED', @source_code, @builtin_code, ISNULL(@caption, ''), ISNULL(@svg_icon, ''), ISNULL(@css_class, ''),
			@user_session, @user_session
		);
	END
END
GO