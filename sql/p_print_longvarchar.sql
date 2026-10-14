/* =============================================================================
 * Verze: 2026-10-14 12:33
 * Soubor: p_print_longvarchar.sql
 * Procedura: p_print_longvarchar
 * Popis:   Pomocná systémová procedura pro výpis dlouhých řetězců varchar(max)
 *          po jednotlivých řádcích do výstupu PRINT nebo do result-setu.
 * Vazby:   - Volána z procedury p_drop_excel_tables (výpis mazaných tabulek).
 *          - Volána z procedury p_export_to_sql (výpis generovaného DDL/DML).
 *          - Využívá proceduru dropni z knihovny HinkMSSQLLibrary.
 * Změny:   - 2026-10-14: Sjednocení konců řádků (CRLF/CR -> LF) na začátku
 *            procedury a oprava posunu v SUBSTRING z @i+2 na @i+1 při hledání
 *            CHAR(10), aby nedocházelo k ořezávání prvního znaku řádku.
 * ============================================================================= */

execute dropni 'p_print_longvarchar'
GO
/*

	Procedura vyprintí předanou proměnnou.
	Účelem je to, že výstup příkazu print je klientovi omezen,
	já ho však používám v případě syntaxe generovaných procedur, kterou potřebuji vidět celou.
	Obsah proměnné proto rozkládám na řádky, které tisknu jeden po druhém.

	Omezení: Proměnná se musí skládat z oddělených řádků, které jsou dostatečně krátké pro samostatné printy

	29.12.2010 - Přidán parametr @output_into_resultset, kterým lze nastavit výstup do resultu místo printu
	16.05.2011 - Podpora odlišné collation v TEMPDB
	01.02.2026 - Rozšířen limit na výstup 20MB
	14.10.2026 - Normalizace CRLF/LF na CHAR(10) a oprava posunu řádku (@i+1)
*/
create procedure p_print_longvarchar @p varchar(max), @output_into_resultset bit=0
as
set nocount on
declare @i int set @i=1
declare @row int set @row=1
declare @r varchar(8000)

-- Normalizace konců řádků (CRLF i CR převedeme na jednotný znak LF = CHAR(10))
set @p = replace(replace(@p, char(13) + char(10), char(10)), char(13), char(10))

if @output_into_resultset=1 create table #plv(id int identity not null, s varchar(8000) collate database_default null)
l:
if @p<>'' begin
	set @i=charindex(char(10),@p)
	if @i=0 begin
		if @output_into_resultset=1 begin
			insert into #plv values(@p)
			select s from #plv order by id
		end else
			print @p
		return
	end
	set @r=substring(@p,1,@i-1)
	if @output_into_resultset=1 begin
		insert into #plv values(@r)
	end else
		print @r
	set @p=substring(@p,@i+1,20000000)
	goto l
end
if @output_into_resultset=1 select s from #plv order by id
GO
--declare @v varchar(max) set @v='
--První řádek
--Druhý řádek
--Třetí řádek'
--execute p_print_longvarchar @v,1
GO