EXECUTE dropni 'f_check_asset_class_compatible', 'FN';
GO

/* =============================================================================
 * Verze: 2026-11-19 15:40
 * Soubor: f_check_asset_class_compatible.sql
 * Funkce: dbo.f_check_asset_class_compatible
 *
 * 1. Role souboru v celém systému:
 *    Vyhodnotí slučitelnost dvou tříd aktiv (asset_class.original) na jednom
 *    aktivu na základě hierarchického příznaku asset_class.multi_class:
 *    Dvě různé třídy C1 a C2 jsou na jednom aktivu slučitelné právě tehdy,
 *    když oba přímé poduzly B1 a B2 pod jejich nejbližším společným předkem
 *    (LCA, příp. oba kořenové uzly při absenci společného předka) mají
 *    nastaveno multi_class = 1.
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Čte tabulku asset_class (table_asset_class.sql).
 *    - Volána z PHP traitu entity_manager_write (entity_manager_write.php)
 *      při ukládání vazby asset_additional_class / asset_class_has_asset
 *      a při změně primary_asset_class v tabulce asset.
 *    - Zařazena do sestavení databáze automaticky maskou f_*.sql v BuildListDb.txt.
 *
 * 3. Očekávaná kontextová data:
 *    - Přijímá @org_uuid (aktivní organizaci z relace pro zohlednění případného
 *      tenant overridu v asset_class); je bezstavová a bez CTE (;WITH).
 * ============================================================================= */
CREATE FUNCTION dbo.f_check_asset_class_compatible(
	@class1_orig uniqueidentifier,                                              -- Originál první třídy aktiv (asset_class.original)
	@class2_orig uniqueidentifier,                                              -- Originál druhé třídy aktiv (asset_class.original)
	@org_uuid uniqueidentifier = 0x00                                           -- Aktivní organizace pro zohlednění tenant overridů
)
RETURNS bit
AS
BEGIN
	IF @class1_orig IS NULL OR @class2_orig IS NULL
		RETURN 1;

	IF @class1_orig = @class2_orig
		RETURN 1;

	SET @org_uuid = ISNULL(@org_uuid, 0x00);

	DECLARE @p1 TABLE (
		step int NOT NULL PRIMARY KEY,
		node_uuid uniqueidentifier NOT NULL,
		parent_uuid uniqueidentifier NULL,
		multi_class bit NOT NULL,
		INDEX ix_p1_node (node_uuid),
		INDEX ix_p1_parent (parent_uuid)
	);

	DECLARE @p2 TABLE (
		step int NOT NULL PRIMARY KEY,
		node_uuid uniqueidentifier NOT NULL,
		parent_uuid uniqueidentifier NULL,
		multi_class bit NOT NULL,
		INDEX ix_p2_node (node_uuid),
		INDEX ix_p2_parent (parent_uuid)
	);

	-- 1. Sběr cesty od @class1_orig směrem ke kořeni stromu
	DECLARE @curr uniqueidentifier = @class1_orig;
	DECLARE @par uniqueidentifier = NULL;
	DECLARE @mc bit = 0;
	DECLARE @step int = 0;

	WHILE @curr IS NOT NULL AND @step < 30
	BEGIN
		SET @par = NULL;
		SET @mc = 0;

		SELECT TOP 1
			@par = parent_uuid,
			@mc = multi_class
		FROM asset_class
		WHERE original = @curr
		  AND object_owner IN (@org_uuid, 0x00)
		  AND record_type = 'A'
		  AND removed = 0
		ORDER BY CASE WHEN object_owner = @org_uuid THEN 0 ELSE 1 END;

		IF @@ROWCOUNT = 0
			BREAK;

		INSERT INTO @p1 (step, node_uuid, parent_uuid, multi_class)
		VALUES (@step, @curr, @par, @mc);

		IF @par = @curr OR EXISTS (SELECT 1 FROM @p1 WHERE node_uuid = @par)
			BREAK;

		SET @curr = @par;
		SET @step = @step + 1;
	END

	-- 2. Sběr cesty od @class2_orig směrem ke kořeni stromu
	SET @curr = @class2_orig;
	SET @step = 0;

	WHILE @curr IS NOT NULL AND @step < 30
	BEGIN
		SET @par = NULL;
		SET @mc = 0;

		SELECT TOP 1
			@par = parent_uuid,
			@mc = multi_class
		FROM asset_class
		WHERE original = @curr
		  AND object_owner IN (@org_uuid, 0x00)
		  AND record_type = 'A'
		  AND removed = 0
		ORDER BY CASE WHEN object_owner = @org_uuid THEN 0 ELSE 1 END;

		IF @@ROWCOUNT = 0
			BREAK;

		INSERT INTO @p2 (step, node_uuid, parent_uuid, multi_class)
		VALUES (@step, @curr, @par, @mc);

		IF @par = @curr OR EXISTS (SELECT 1 FROM @p2 WHERE node_uuid = @par)
			BREAK;

		SET @curr = @par;
		SET @step = @step + 1;
	END

	IF NOT EXISTS (SELECT 1 FROM @p1) OR NOT EXISTS (SELECT 1 FROM @p2)
		RETURN 0;

	-- Nelze kombinovat nadřazený uzel s jeho vlastním podřízeným uzlem
	IF EXISTS (SELECT 1 FROM @p1 WHERE node_uuid = @class2_orig)
	   OR EXISTS (SELECT 1 FROM @p2 WHERE node_uuid = @class1_orig)
		RETURN 0;

	-- 3. Nalezení nejbližšího společného předka (LCA = nejmenší step v @p1 společný s @p2)
	DECLARE @lca uniqueidentifier = NULL;

	SELECT TOP 1 @lca = p1.node_uuid
	FROM @p1 p1
	JOIN @p2 p2 ON p2.node_uuid = p1.node_uuid
	ORDER BY p1.step ASC;

	DECLARE @mc1 bit = 0;
	DECLARE @mc2 bit = 0;

	IF @lca IS NOT NULL
	BEGIN
		SELECT TOP 1 @mc1 = multi_class FROM @p1 WHERE parent_uuid = @lca;
		SELECT TOP 1 @mc2 = multi_class FROM @p2 WHERE parent_uuid = @lca;
	END
	ELSE
	BEGIN
		SELECT TOP 1 @mc1 = multi_class FROM @p1 WHERE parent_uuid IS NULL;
		SELECT TOP 1 @mc2 = multi_class FROM @p2 WHERE parent_uuid IS NULL;
	END

	RETURN CASE WHEN @mc1 = 1 AND @mc2 = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END;
END
GO