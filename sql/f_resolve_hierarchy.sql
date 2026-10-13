/*
	=============================================================================
	Role souboru v celém systému:
	Skript zajišťuje výpočet čistých hierarchických struktur (stromů s jedním rodičem). 
	Poskytuje bezpečné lexikografické třídění pomocí doplňování nulami (zero-padding 
	na 5 znaků), které pojme až 99 999 podřízených uzlů v jedné větvi a je 
	ideální pro přenos přes HTTP/HTMX.
	
	Návaznosti na další soubory, DB tabulky, views nebo procedury:
	- Využívá proceduru `dropni` k bezpečnému smazání předchozích verzí objektů.
	- Definuje tabulkový typ `tt_resolve_hierarchy` jako kontrakt pro vstupní data.
	- Funkci `f_resolve_hierarchy` budou využívat views a procedury modulu CRMM
	  (např. pro Třídy aktiv, Hrozby, Scénáře).
	
	Očekávaná kontextová data:
	- Funkce je čistě deterministická a bezstavová.
	- Očekává se, že aplikace v PHP nastaví spojení přes SESSION_CONTEXT() 
	  (např. ID organizace, jazyk) a nadřazená procedura vyfiltruje data ještě 
	  předtím, než je vloží do proměnné typu `tt_resolve_hierarchy`.
	=============================================================================
*/

execute dropni 'f_resolve_hierarchy'
execute dropni 'tt_resolve_hierarchy'
GO

-- Definice vstupního typu pro hierarchická data
create type tt_resolve_hierarchy as table(
	keyvalue varchar(40) primary key,	-- Identifikátor řádku
	parent varchar(40) null,			-- Identifikátor nadřízeného
	parent_order varchar(200) null,		-- Pořadí v rámci nadřízeného
	top_level bit not null				-- Řádky označené jako vrchol (nejméně jeden musí být 1)
)
GO

/*
	Funkce vrátí platnou hierarchii záznamů v předané tabulce.
	Vstupní tabulka je definována typem tt_resolve_hierarchy.
	Výstup vrací pro každý řádek ověřené hierarchie úroveň a třídící kód. 
	Třídící kód je generován doplňováním nul (zero-padding na 5 znaků), 
	což umožňuje až 99 999 sourozenců pod jedním uzlem a max. hloubku stromu 80.
*/
create function f_resolve_hierarchy(@input tt_resolve_hierarchy readonly)
returns @output table(
	keyvalue varchar(40) not null primary key,	-- Identifikátor řádku (pouze z platné hierarhie)
	parent varchar(40) null,					-- Nadřízený uzel
	num int,									-- Pořadí pod nadřízeným
	hierarchy_sort varchar(400),				-- Znakový třídící kód (např. 000010000500002)
	level tinyint,								-- Úroveň zanoření ve stromu
	unique(parent,num),							-- Index pro třídění od nadřízeného
	unique(hierarchy_sort,keyvalue)				-- Index pro třídění celého stromu
)
begin

-- Pracovní tabulka pro přípravu a indexaci vstupních dat
declare @data table(
	keyvalue varchar(40),
	parent varchar(40),
	num int,
	hierarchy_sort varchar(400),
	level tinyint null,
	unique(hierarchy_sort,keyvalue),
	unique(level,parent,num)
)

-- 1. Fáze: Příprava dat a výpočet formátovaného pořadí (Zero-padded na 5 znaků)
insert into @data
select keyvalue
	,parent
	,row_number() over(partition by parent order by parent_order) as num
	,right('00000' + cast(row_number() over(partition by parent order by parent_order) as varchar(10)), 5) as hierarchy_sort
	,case when top_level=1 then 0 else null end as level
from @input

-- 2. Fáze: Vybudování stromu od kořenů k listům (Recursive CTE)
;with m as(
	-- Vyhledání vrcholových uzlů (kořenů)
	select keyvalue
		,parent
		,num
		,hierarchy_sort
		,level
	from @data 
	where level=0
	
	UNION ALL
	
	-- Rekurzivní napojení potomků s nabalováním formátované cesty (vždy 5 znaků per úroveň)
	select d.keyvalue
		,d.parent
		,d.num
		,cast(m.hierarchy_sort + right('00000' + cast(d.num as varchar(10)), 5) as varchar(400))
		,cast(m.level+1 as tinyint)
	from m
	inner join @data d on d.parent=m.keyvalue and d.level is null
)
insert into @output
select keyvalue, parent, num, hierarchy_sort, level
from m

-- 3. Fáze: Záchrana sirotků (uzlů bez vazby na top_level kořeny)
insert into @output
select d.keyvalue, d.parent, d.num, '', 0
from @data d
	left outer join @output o on o.keyvalue=d.keyvalue
where o.level is null

return
end
GO

--declare @input tt_resolve_hierarchy
--insert into @input
--select php_menuitem, parent_menuitem, parent_ordr, case when name like 'mainmenu%' then 1 else 0 end
--from php_menuitem
--where removed=0

--select * from f_resolve_hierarchy(@input) h
--join php_menuitem m on m.php_menuitem=h.keyvalue
--order by hierarchy_sort
GO
