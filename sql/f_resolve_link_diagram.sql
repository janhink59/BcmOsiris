/* ===================================================================================================
 * Verze: 2026-11-16 14:40
 * Soubor: f_resolve_link_diagram.sql
 * Objekt: dbo.f_resolve_link_diagram
 * Typ:    Multi-statement Table-Valued Function (TVF)
 * Určení: MSSQL 2019
 *
 * 1. Role souboru v celém systému:
 *    Vyřešení vztahů nadřízenosti a podřízenosti (orientovaného grafu / sítě)
 *    předaných v parametru @input. Transformuje seznam uzlů a hran do
 *    acyklického stromu cest s detekcí zacyklení (bad = 1, circular = 1)
 *    a určením vrcholových uzlů (level = 0 AND hidden_root = 0).
 *
 * 2. Návaznosti na další soubory, DB tabulky, views nebo procedury:
 *    - Využívá proceduru dropni (HinkMSSQLLibrary.sql).
 *    - Definuje tabulkový typ tt_resolve_link_diagram.
 *    - Volána z procedury dbo.p_rebuild_link_diagram (p_rebuild_link_diagram.sql)
 *      a ze stránky page_link_diagram.php.
 *
 * 3. Očekávaná kontextová data:
 *    - Funkce je čistě deterministická a bezstavová; volající procedura předává
 *      již vyfiltrovanou sadu uzlů a orientovaných hran v parametru @input.
 *
 * Změny:
 * - 2026-11-16 14:40:
 *   1. Do návratové tabulky @result doplněny inline indexy ix_result_node,
 *      ix_result_root a ix_result_parent pro přímé Index Seeky ve všech krocích.
 *   2. Klauzule WHERE root_id IN (SELECT ...) v kroku 4 nahrazena indexovanou
 *      tabulkovou proměnnou @lvl1_nodes s PRIMARY KEY (node_id).
 *   3. Dvojitý poddotaz WHILE EXISTS (...) + SELECT TOP 1 v kroku 4b sloučen
 *      do jediného průchodu využívajícího index ix_result_node.
 * - 2026-11-11 21:30:
 *   1. Opraveno číslování větví v ROW_NUMBER() z PARTITION BY r.node_id na
 *      PARTITION BY r.sort_order (zabraňuje kolizi v diamantovém DAGu).
 *   2. Sloupce current_path a parent_path rozšířeny na varchar(8000) (až ~200
 *      úrovní UUID bez LOB režie varchar(max)), PK změněn na sort_order varchar(800).
 *   3. Opraveno vyhodnocení hidden_root při výskytu zacyklení: uzly na level = 1
 *      dostanou hidden_root = 1; pokud má izolovaná cyklická komponenta všechny
 *      uzly s předkem, zůstane hidden_root = 0 právě jednomu reprezentantovi.
 * =================================================================================================== */

execute dropni 'f_resolve_link_diagram'
execute dropni 'tt_resolve_link_diagram'
GO

create type tt_resolve_link_diagram as table(
	node_id varchar(40) not null -- ID uzlu (číslo, string stejné délky nebo UUID)
	,from_id varchar(40) default '' not null -- Nadřízený (prázdný pro základní seznam)
	,primary key(node_id,from_id)
	,sort_order varchar(800) -- Pořadí v rámci nadřízeného (nejčastěji název uzlu)
)
GO

CREATE FUNCTION dbo.f_resolve_link_diagram(@input tt_resolve_link_diagram READONLY) 
RETURNS @result TABLE (
	node_id varchar(40) not null,
	from_id varchar(40) default '' not null,
	sort_order varchar(800) default '' not null primary key,
	parent_order varchar(800) default '' not null,
	current_path varchar(8000) default '' not null,
	parent_path varchar(8000) default '' not null,
	root_id varchar(40) default '' not null,
	level tinyint default 0,
	children int default 0,
	bad bit default 0,
	circular int default 0,
	hidden_root int default 0,
	unique(level, sort_order),
	index ix_result_node (node_id, level, hidden_root),
	index ix_result_root (root_id, bad, sort_order),
	index ix_result_parent (parent_order)
)
BEGIN
	DECLARE @lvl INT = 0;
	DECLARE @inserted_rows INT = 0;

	-- 1. Počáteční naplnění všemi kandidátními uzly na vrcholu (level = 0)
	INSERT INTO @result(node_id, from_id, sort_order, parent_order, current_path, parent_path, root_id, level, bad)
	SELECT 
		node_id                                                                    AS node_id, 
		''                                                                         AS from_id,
		REPLACE(STR(ROW_NUMBER() OVER(ORDER BY i.sort_order, i.node_id), 5), ' ', '0') AS sort_order, 
		''                                                                         AS parent_order, 
		node_id                                                                    AS current_path, 
		''                                                                         AS parent_path, 
		node_id                                                                    AS root_id, 
		@lvl                                                                       AS level, 
		0                                                                          AS bad
	FROM @input i
	WHERE i.from_id = '';

	SET @inserted_rows = @@ROWCOUNT;

	-- 2. Zpracování dalších úrovní po vrstvách BFS (čteme pouze předchozí vrstvu @lvl bez cyklu)
	WHILE @inserted_rows > 0 AND @lvl < 155
	BEGIN
		INSERT INTO @result (node_id, from_id, sort_order, parent_order, current_path, parent_path, root_id, level, bad)
		SELECT 
			i.node_id                                                                            AS node_id,
			r.node_id                                                                            AS from_id,
			r.sort_order + REPLACE(STR(ROW_NUMBER() OVER(PARTITION BY r.sort_order ORDER BY i.sort_order, i.node_id), 5), ' ', '0') AS sort_order,
			r.sort_order                                                                         AS parent_order,
			r.current_path + ' ' + i.node_id                                                     AS current_path,
			r.current_path                                                                       AS parent_path,
			r.root_id                                                                            AS root_id,
			@lvl + 1                                                                             AS level,
			CASE WHEN CHARINDEX(' ' + i.node_id + ' ', ' ' + r.current_path + ' ') > 0 THEN 1 ELSE 0 END AS bad
		FROM @result r
		INNER JOIN @input i ON i.from_id = r.node_id AND i.from_id <> ''
		WHERE r.level = @lvl
		  AND r.bad = 0;

		SET @inserted_rows = @@ROWCOUNT;
		SET @lvl = @lvl + 1;
	END

	-- 3. Hromadný update počtu přímých potomků (Set-Based přes ix_result_parent)
	UPDATE r
	SET children = c.cnt
	FROM @result r
	INNER JOIN (
		SELECT parent_order, COUNT(*) AS cnt 
		FROM @result 
		WHERE parent_order <> ''
		GROUP BY parent_order
	) c ON r.sort_order = c.parent_order;

	-- 4. Nastavení příznaku hidden_root = 1 pro stromy začínající v uzlech, které mají nadřízený uzel (level = 1)
	DECLARE @lvl1_nodes TABLE (
		node_id varchar(40) NOT NULL PRIMARY KEY
	);

	INSERT INTO @lvl1_nodes (node_id)
	SELECT DISTINCT node_id
	FROM @result
	WHERE level = 1;

	UPDATE r
	SET r.hidden_root = 1
	FROM @result r
	JOIN @lvl1_nodes l1 ON l1.node_id = r.root_id;

	-- 4b. Ochrana pro izolované cykly (kde každý uzel cyklu má předka a není dosažitelný z žádného uzlu s hidden_root = 0):
	--     Pro každou takovou osiřelou komponentu odhalíme (hidden_root = 0) právě jeden uzel s nejnižším sort_order.
	DECLARE @unhide_root varchar(40) = '';

	WHILE 1 = 1
	BEGIN
		SET @unhide_root = NULL;

		SELECT TOP 1 @unhide_root = r0.root_id
		FROM @result r0
		WHERE r0.level = 0
		  AND r0.hidden_root = 1
		  AND NOT EXISTS (
			SELECT 1
			FROM @result vis
			WHERE vis.node_id = r0.node_id
			  AND vis.hidden_root = 0
		  )
		ORDER BY r0.sort_order ASC;

		IF @unhide_root IS NULL
			BREAK;

		UPDATE @result
		SET hidden_root = 0
		WHERE root_id = @unhide_root;
	END

	-- 5. Nastavení příznaku circular = 1 na všech předcích vedoucích k zacyklenému uzlu (bad = 1)
	UPDATE r
	SET circular = 1
	FROM @result r
	WHERE EXISTS (
		SELECT 1
		FROM @result b
		WHERE b.root_id = r.root_id
		  AND b.bad = 1
		  AND b.sort_order LIKE r.sort_order + '%'
	);

	RETURN;
END;
GO