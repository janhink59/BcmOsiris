execute dropni 'request_message' -- Tabulku není třeba uchovávat mezi updaty databáze, protože se jedná o dočasné zprávy pro uživatele
GO
-- Tabulka request_message slouží k uchování zpráv, které se mají zobrazit uživateli při zpracování requestu. 
-- Zprávy se ukládají do tabulky request_message a při ukončení requestu se vyčistí. 
-- Zprávy mohou být unikátní podle parametru "code", opakované volání s tímto parametrem pak slouží k nasčítání hodnoty "intvalue".
create table request_message(
	spid int default @@spid not null references dbsession on delete cascade,
	counter int identity not null,
	primary key(spid,counter),
	code varchar(20) default '' not null,
	severity tinyint default 0 not null, -- 0=zpráva, 1=OK, 2=Warn, 3=Err, jiné = není určeno k zobrazení
	color varchar(20) default '' not null, -- Není-li zadána, nastaví se podle severity: black, green, blue, red
	icon varchar(40) default '' not null, -- pro budoucí použití
	msgtext varchar(6000) default '' not null, -- Hlavní text zprávy
	obj_type varchar(200) default '' not null,
	obj_name varchar(250) default '' not null,
	indent tinyint default 0 not null, -- úroveň odsazení
	style varchar(255) default '' not null, -- Styl platící pro celý řádek
	intvalue bigint null, -- počet zpracovaných řádků nebo jiná hodnota určená k zobrazení
	charvalue varchar(8000) default '' not null
)
execute sp_create_index 'request_message','i_request_message_code','spid,code'
GO
create table request_variable(
	spid int default @@spid not null references dbsession on delete cascade,
	varname varchar(250) not null,
	primary key(spid,varname),
	charvalue varchar(255) default '' not null,
	intvalue bigint default 0 not null,
	uuidvalue uniqueidentifier default 0x0 not null
)
GO
/*

	Procedura pro vložení zprávy o requestu.
	Je-li zadán neprázdný parametr @code, pak se jedná o unikátní zprávu, opakované volání s tímto parametrem pak slouží k nasčítání hodnoty "intvalue".
	18.02.2016 - Ochrana proti chybě při volání bez www session
*/
create procedure insert_request_message
	@msgtext varchar(6000)='',
	@severity tinyint=0,
	@intvalue bigint=null,
	@style varchar(255)='',
	@indent int=0,
	@color varchar(20)='',
	@icon varchar(40)='',
	@charvalue varchar(8000)='',
	@code varchar(20)='',
	@obj_type varchar(200)='',
	@obj_name varchar(250)=''
as
declare @l varchar(2)
select @l=language from dbsession
set @charvalue=isnull(@charvalue,'')
if @code<>'' and exists(select * from request_message where spid=@@spid and code=@code) begin
	if @intvalue>0
		update request_message set intvalue=intvalue+@intvalue
		where spid=@@spid and code=@code
	return
end

if not exists(select * from dbsession where spid=@@spid) return

if @code<>'' and @msgtext='' set @msgtext=dbo.f_php_phrase(@code,@l)
insert into request_message(spid,code,severity,color,icon,msgtext,indent,style,intvalue,charvalue,obj_type,obj_name)
values(@@spid,@code,@severity,@color,@icon,@msgtext,@indent,@style,@intvalue,@charvalue,@obj_type,@obj_name)
GO
create procedure select_request_message
as
select counter,
	severity,
	msgtext, 
	style,
	indent,
	case when color<>'' then color else case severity when 1 then 'green' when 2 then 'blue' when 3 then 'red' else 'black' end end color,
	icon,
	intvalue,
	charvalue,
	obj_type,
	obj_name
--into #r
from request_message where spid=@@spid
--select * from #r
order by code, counter
GO
/*
debuglogin 'hink'
execute init_wwwsession 'debug', @noresult='1'
execute insert_request_message 'X',2,@obj_name='NN'
execute insert_request_message 'Y',1,3
execute select_request_message
*/
GO
create function f_session_variable(@name varchar(250))
returns varchar(6000)
begin
	declare @v varchar(6000)
	select @v=charvalue from dbsession s, session_variable v where s.spid=@@spid and v.wwwsession=s.wwwsession and v.name=@name
	return @v
end
GO
create procedure p_session_variable @name varchar(250), @value varchar(6000)=null, @text varchar(max)=null
as
delete from session_variable from dbsession s, session_variable v where s.spid=@@spid and v.wwwsession=s.wwwsession and v.name=@name
if @value is not null insert into session_variable(wwwsession,name,charvalue,textvalue) select s.wwwsession, @name, @value, @text from dbsession s where s.spid=@@spid
GO
--debuglogin 'hink'
--execute p_session_variable 'A','1'
--execute p_session_variable 'B',2
--execute p_session_variable 'B',3
--select * from session_variable
--select dbo.f_session_variable('A'),dbo.f_session_variable('B'),dbo.f_session_variable('C')
GO
