/* =============================================================================
 * Verze: 2026-10-22 17:45
 * Soubor: f_language_list.sql
 * Funkce: dbo.f_language_list
 * Účel:   Vrátí seznam podporovaných jazyků ze statického číselníku [language]
 *         doplněný o vypočtené pořadí v řetězci dědičnosti (fallback_order)
 *         pro aktuální jazyk relace (nebo explicitně předaný @requested_lang).
 *         Hodnota fallback_order = 1 označuje aktivní jazyk, 2, 3... jeho
 *         postupné fallback jazyky a 1000 jazyky mimo aktuální fallback řetězec.
 * Vazby:  - Volána z třídy language_manager (language_manager.php).
 *         - Využívána v dotazech tříd entity_manager (entity_manager.php)
 *           a phrase_manager (phrase_manager.php) s podmínkou fallback_order < 1000.
 * Změny:  - 2026-10-22 17:45: Přidán volitelný parametr @requested_lang varchar(2) = NULL
 *           a fallback na výchozí jazyk (is_default = 1), pokud ještě neexistuje
 *           záznam v dbsession (např. na přihlašovací obrazovce).
 *         - Sjednocen název sloupce translator_org podle tabulky [language].
 * ============================================================================= */

execute dropni 'f_language_list'
GO
/*
	Funkce vrátí seznam jazyků, které jsou podporovány v systému.
	Kvůli snadnému třídění dle aktuálního jazyka a fallback jazyků
	je přidán sloupec fallback_order, kde hodnota 1000 znamená, že není v řetězci pro aktuální jazyk.
	Obecně použitelný sort order je fallback_order, sort_code
*/
create function dbo.f_language_list(
	@requested_lang varchar(2) = null
)
/* Definice procedury pro ladění */
--create procedure f_language_list as declare

-- Společná část kódu
returns @r table
(
	[language] varchar(2),
	caption varchar(200),
	fallback_language varchar(2),
	sort_code varchar(20) not null,
	is_default bit,
	translator_org uuid,
	svg_icon varchar(max),
	fallback_order int not null,
	primary key(fallback_order, sort_code, [language])
)
begin
	declare @l varchar(2) = nullif(ltrim(rtrim(@requested_lang)), ''), @fallback_order int = 1

	-- 1. Pokud nebyl jazyk explicitně předán, načteme jej z aktivní databázové relace
	if @l is null
	begin
		select @l = db.[language]
		from dbsession db
		where db.spid = @@spid
	end

	-- 2. Pokud relace ještě neexistuje (např. před přihlášením) nebo jazyk v číselníku není, vezmeme výchozí
	if @l is null or not exists (select 1 from [language] where [language] = @l)
	begin
		select top 1 @l = [language]
		from [language]
		where is_default = 1
		order by sort_code
	end

	insert into @r
	select
		l1.[language],
		l1.caption,
		l1.fallback_language,
		l1.sort_code,
		l1.is_default,
		l1.translator_org,
		l1.svg_icon,
		case when l1.[language] = @l then 1 else 1000 end
	from [language] l1

	-- 3. Iterativní výpočet pořadí navazujících fallback jazyků (ochrana proti zacyklení přes fallback_order = 1000)
	declare @rowcount int = 1
	while @rowcount > 0
	begin
		update @r
		set fallback_order = @fallback_order + 1
		from @r a, @r
		where a.fallback_order = @fallback_order
			and [@r].fallback_order = 1000
			and [@r].[language] = a.fallback_language

		set @rowcount = @@rowcount
		set @fallback_order = @fallback_order + 1
	end

	return
end
GO
--execute p_debuglogin 'honza.hink@gmail.com','sk'
----execute f_language_list
--select * from f_language_list() order by fallback_order, sort_code
GO
