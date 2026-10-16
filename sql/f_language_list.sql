execute dropni 'f_language_list'
GO
/*
    Funkce vrátí seznam jazyků, které jsou podporovány v systému.
	Kvůli snadnému třídění dle aktuálního jazyka a fallback jazyků
	je přidán sloupec fallback_order, kde hodnota 1000 znamená, že není v řetězci pro aktuální jazyk.
	Obecně použitelný sort order je fallback_order, sort_code
*/


/* Definice funkce */
create function f_language_list() returns

/* Definice procedury pro ladění */
--create procedure f_language_list as declare

-- Společná část kódu
@r table
	(
		language varchar(2) --primary key
		,caption varchar(80)
		,fallback_language varchar(2)
        ,sort_code varchar(20) not null
        ,is_default bit
        ,translator_organization uuid
        ,svg_icon varchar(max)
        ,fallback_order int not null
		,primary key(fallback_order,sort_code,language)
	)
begin
	declare @l varchar(2), @fb varchar(2), @fallback_order int=1

	select @l=db.language
	from dbsession db
	where db.spid=@@spid

	--select @l, @fb
	insert into @r
    select *,case when l1.language=@l then 1 else 1000 end
	from language l1

	-- Zápis počítadla dalších fallback_jazyků
	
	declare @rowcount int=1
	while @rowcount>0 begin
		update @r set fallback_order=@fallback_order+1
		from @r a, @r 
		where a.fallback_order=@fallback_order
			and [@r].fallback_order=1000
			and [@r].language=a.fallback_language
		
		set @rowcount=@@ROWCOUNT
		set @fallback_order=@fallback_order+1

	end
	/* Pouze pro proceduru */
	--select * from @r
	return
end 
GO
--execute p_debuglogin 'honza.hink@gmail.com','sk'
----execute f_language_list
--select * from f_language_list() order by fallback_order, sort_code
GO
