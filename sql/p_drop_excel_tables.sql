execute dropni 'p_drop_excel_tables'
GO
/*
	Procedura odstraní všechny tabulky vzniké importem z Excelu (konèí znakem $)
*/
create procedure p_drop_excel_tables @print_message bit=1
as
declare @s varchar(max)=''
select @s=@s+'drop table ['+x.TABLE_CATALOG+'].['+x.TABLE_SCHEMA+'].['+TABLE_NAME+']
' from INFORMATION_SCHEMA.TABLES x
where right(TABLE_NAME,1)='$'
	or charindex('$_xlnm#',TABLE_NAME)>1
execute(@s)
if @s<>'' and @print_message=1 begin
	print 'Dropping temporary excel tables:'
	execute p_print_longvarchar @s
end
GO
begin tran
execute p_drop_excel_tables @print_message=0
commit
GO
