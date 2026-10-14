/* =============================================================================
 * Verze: 2026-10-14 13:32
 * Soubor: p_export_to_sql.sql
 * Procedura: p_export_to_sql
 * Popis:   Generuje SQL skript (CREATE TABLE + dávkové INSERT příkazy po 1000
 *          řádcích) z obsahu zadané zdrojové tabulky.
 * Vazby:   - Volána z PHP modulu page_excel_reader.php (metoda process_distribution)
 *            s parametrem @output_as_sqlresult = 1 při generování distribuční dávky.
 *          - Využívá funkci dbo.f_syscolumns a proceduru dropni z HinkMSSQLLibrary.
 *          - Využívá funkci dbo.f_varbinaryliteral pro export binárních sloupců.
 *          - Využívá proceduru p_print_longvarchar pro výpis dlouhých skriptů.
 * Změny:   - 2026-10-14: Výpis @create_table přes p_print_longvarchar podmíněn
 *            parametrem @output_as_sqlresult = 0, aby nerušil result-set v PHP.
 *          - 2026-10-14: Nahrazena funkce sys.fn_replreplacesinglequote za
 *            standardní REPLACE(..., '''', '''''') pro plnou podporu varchar(max).
 * ============================================================================= */

execute dropni 'p_export_to_sql'
GO
/*
	Procedura exportuje do SQL obsah tabulky předané v parametru
	
	15.11.2012 - První verze
	28.02.2013 - Přidána možnost exportu jako result set
	06.06.2013 - Rozšíření položky pro syntaxi "order by"
	02.04.2014 - Podpora "not null" atributu v definici tabulky
	01.03.2015 - Oprava kvůli importu delších textů
	13.03.2015 - Oprava kvůli názvům sloupců s mezerami
	07.10.2015 - Doplnění informací do výstupu
	02.03.2016 - Chybějící apostrof v jednom komentáři (opis příkazu)
	17.07.2025 - Podpora binárních datových typů
	30.01.2026 - Podpora vynechaného parametru u tabulek XLSX_%$
	14.10.2026 - Podmíněný print při @output_as_sqlresult=0 a bezpečný REPLACE apostrofů
*/
create or alter procedure p_export_to_sql
	@import_table varchar(200),                -- Cílová tabulka, která se před importem dropne a vytvoří znovu
	@data_table varchar(200)='',               -- Tabulka, ze které se data načtou, je-li prázdná použije se cílová
	@order_by varchar(2000)='',                -- Přídavná syntaxe
	@output_as_sqlresult bit=0,                -- Výsledek se neprintí, ale uloží do result-setu
	@truncate bit=0,                           -- Místo DROP & CREATE se použije TRUNCATE
	@debug bit=0                               -- Provést ladící printy
	,@computed bit=1                           -- Příznak, zda exportovat i computed a výhledově IMAGE objekty
as

if isnull(@data_table,'')='' begin
	if (left(@import_table,1)='#') 
		set @data_table=substring(@import_table,2,40)
	else if (right(@import_table,1)='$' and left(@import_table,5)!='XLSX_')
		set @data_table=substring(@import_table,1,len(@import_table)-1)
	else
		set @data_table=@import_table
end

declare
	@s nvarchar(max)='',
	@into nvarchar(max)='',
	@clist nvarchar(max)='',
	@create_table nvarchar(max)='',
	@body nvarchar(max)='',
	@insert_command nvarchar(max)='',
	@printgo varchar(50)='print ''GO''',
	@printbody varchar(100)='execute p_print_longvarchar @body',
	@printend varchar(200)='print ''-- END OF DATA '+@import_table+ '''
print ''GO'''
	
select
	@s = @s + '
declare @'+convert(varchar,colid) + ' ' + 
		case
			when typename='text' then 'varchar(max)'
			when typename='ntext' then 'nvarchar(max)'
			when typename='image' then 'varbinary(max)'
		else typename + case when prec_syntax='(max)' then '(max)' else prec_syntax end end
			+ ' -- ['+colname + '] ' ,

	@create_table = @create_table + ',
	['+colname + '] ' + typename + case when prec_syntax='(max)' then '(max)' else prec_syntax end + ' ' 
		+ nulls ,

	@into = @into + ',
	@'+convert(varchar,colid),
	
	@clist = @clist + ',
	['+colname+']',
	
	@body = @body + '+'',
''		+case
	when @'+convert(varchar,colid)+' is null then ''NULL''
	else '''+
	case when f.typename in('varbinary','binary','image') then 
		'''+dbo.f_varbinaryliteral(@'+convert(varchar,colid)+')+'''''
	else 
		'''''''+replace(cast(@'+convert(varchar,colid)+' as nvarchar(max)),'''''''','''''''''''')+'''''''''
	end
	+'end'
from f_syscolumns(@data_table) f
where /*f.typename not in('image') and*/ (@computed=1 or iscomputed=0)
order by colid

set @insert_command='
INSERT INTO '+@import_table+'('+substring(@clist,2,200000)+')
VALUES'

DECLARE @unicode_marker nvarchar(1)=NCHAR(9733)

if @truncate=0
	set @create_table='/*	UTF-8 detection: ' + @unicode_marker + '
	execute P_EXPORT_TO_SQL '''+@import_table+''''
		+case when @data_table<>@import_table then ','''+@data_table+'''' else '' end
		+case when @order_by<>'' then ', @order_by='''+@order_by+'''' else '' end + ' 

	Date: '+convert(varchar,getdate(),104)+' '+convert(varchar,getdate(),8)+'
	Database: '+@@servername+'.'+db_name()+'
	Export table: "'+@data_table+'"'+case when @order_by<>'' then '
	Filter: "'+@order_by+'"' else '' end + '
*/

execute dropni '''+@import_table+'''
GO
CREATE TABLE '+@import_table+'('+substring(@create_table,2,200000)+')'

else -- @truncate<>0

	set @create_table='/*	UTF-8 detection: ' + @unicode_marker + '
	execute P_EXPORT_TO_SQL '''+@import_table+''''
		+case when @data_table<>@import_table then ','''+@data_table+'''' else '' end
		+case when @order_by<>'' then ', @order_by='''+@order_by+'''' else '' end + ', @truncate=1

	Date: '+convert(varchar,getdate(),104)+' '+convert(varchar,getdate(),8)+'
	Database: '+@@servername+'.'+db_name()+'
	Export table: "'+@data_table+'"'+case when @order_by<>'' then '
	Filter: "'+@order_by+'"' else '' end + '
*/

truncate table '+@import_table+'
GO
'

--set @create_table=@create_table + '
--print ''Import dat do tabulky "'+@import_table+'"''
--'

if @output_as_sqlresult=0
	execute p_print_longvarchar @create_table

declare @printinsert varchar(max)='print '''+@insert_command+''''
	
if @output_as_sqlresult=1 begin
	create table #output_sql(id int identity not null primary key, txt nvarchar(max) collate database_default default '' not null)
	insert into #output_sql(txt) values --('execute dropni '''+@import_table+''''),
		--('GO'),
		(@create_table)
	set @printgo='insert into #output_sql(txt) values(''GO'')'
	set @printbody='insert into #output_sql(txt) values (@body)'
	set @printinsert='insert into #output_sql(txt) values ('''+@insert_command+''')'
	set @printend='insert into #output_sql(txt) values (''-- END OF DATA '+@import_table+ '''),(''GO'')'
end


set @body = '	set @body = @body+'',
(''+'+substring(@body,10,20000000)+'+'')''
	'
set @into='
set nocount on
declare @s nvarchar(max), @body nvarchar(max)=''''
declare @c cursor, @i integer=0
set @c=cursor for
select '+substring(@clist,2,20000000)+'
from '+@data_table+'
'+@order_by+'
open @c
l:
fetch @c into
	'+substring(@into,5,20000000)+'
if @@fetch_status=0 begin
	'+@body+'
	if @i=0 begin
		set @body=substring(@body,2,20000000)
		'+@printinsert+'
	end
	'+@printbody+'--execute p_print_longvarchar @body
	set @i=@i+1
	if @i=1000 begin
		set @i=0
		'+@printgo+'
	end
	--print @i
	set @body=''''
	goto l
end
set @body = substring(@body,2,20000000)
'+@printend

set @s=@s+@into
if @debug=1 execute p_print_longvarchar @s
execute (@s)
if @output_as_sqlresult=1 select txt from #output_sql order by id
GO
--execute p_export_to_sql 't','organization'--,@order_by='where name like''Risk%'''
--	--,@debug=1

GO