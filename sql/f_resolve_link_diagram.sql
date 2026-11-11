/* ===================================================================================================
 * Verze: 2026-11-11 21:30
 * Soubor: f_resolve_link_diagram.sql
 * Objekt: dbo.f_resolve_link_diagram
 * Typ:    Multi-statement Table-Valued Function (TVF)
 * Určení: MSSQL 2019
 *
 * Účel:   Vyřešení vztahů nadřízenosti a podřízenosti (orientovaného grafu / sítě)
 *         předaných v parametru @input. Transformuje seznam uzlů a hran do
 *         acyklického stromu cest s detekcí zacyklení (bad = 1, circular = 1)
 *         a určením vrcholových uzlů (level = 0 AND hidden_root = 0).
 *
 * Změny:
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
	unique(level, sort_order)
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

	-- 3. Hromadný update počtu přímých potomků (Set-Based)
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
	UPDATE @result 
	SET hidden_root = 1
	WHERE root_id IN (
		SELECT DISTINCT node_id FROM @result WHERE level = 1
	);

	-- 4b. Ochrana pro izolované cykly (kde každý uzel cyklu má předka a není dosažitelný z žádného uzlu s hidden_root = 0):
	--     Pro každou takovou osiřelou komponentu odhalíme (hidden_root = 0) právě jeden uzel s nejnižším sort_order.
	WHILE EXISTS (
		SELECT 1
		FROM @result r0
		WHERE r0.level = 0
		  AND r0.hidden_root = 1
		  AND NOT EXISTS (
			SELECT 1
			FROM @result vis
			WHERE vis.hidden_root = 0
			  AND vis.node_id = r0.node_id
		  )
	)
	BEGIN
		DECLARE @unhide_root varchar(40) = NULL;

		SELECT TOP 1 @unhide_root = r0.root_id
		FROM @result r0
		WHERE r0.level = 0
		  AND r0.hidden_root = 1
		  AND NOT EXISTS (
			SELECT 1
			FROM @result vis
			WHERE vis.hidden_root = 0
			  AND vis.node_id = r0.node_id
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

/*
-- TESTOVACÍ DATA Z PŮVODNÍHO SKRIPTU
declare @t table(nadr varchar(10), podr varchar(10))
insert into @t values
	('A0','A1')
	,('A0','A2')
	,('A0','A3')
	,('A0','B0')
		,('B0','C0')
			,('C0','D0')
	,('A0','C0')
	,('B0','E0')
	,('B2','C0')
	,('A2','B2')
	,('B1','U0')
	-- Následující dvě podřízenosti způsobují zacyklení
	,('B0','B0')
	,('D0','B0')

declare @input tt_resolve_link_diagram
insert into @input(node_id,sort_order)
select distinct nadr,nadr from @t
union
select distinct podr,podr from @t

insert into @input(node_id, from_id, sort_order)
select podr,nadr,podr from @t
select * from @input

select * from f_resolve_link_diagram(@input) order by sort_order
*/
GO
	--debuglogin 'o2_service'
	--declare @ti tt_resolve_link_diagram

	---- Tabulka s platnými skupinami

	--declare @uzly table(info2_claim_group uuid not null unique
	--	,sort_code varchar(20)
	--	,full_name varchar(400)
	--	,inactive smallint
	--)

	--insert into @uzly
	--select v.info2_claim_group
	--	,v.sort_code
	--	,v.full_name
	--	,v.inactive
	--from v_info2_claim_group v
	--where v.removed=0 and v.inactive=0 and v.abbreviation<>''

	--insert into @ti(node_id,sort_order)
	--select v.info2_claim_group, v.full_name
	--from @uzly v

	--insert into @ti(node_id,from_id,sort_order)
	--select s.subgroup,s.info2_claim_group, g1.full_name
	--from info2_claim_subgroup s
	--	join @uzly g1 on g1.info2_claim_group=s.info2_claim_group
	--	join @uzly g2 on g2.info2_claim_group=s.subgroup
	--where s.removed=0

	--select * from f_resolve_link_diagram(@ti)
	--order by sort_order
GO
