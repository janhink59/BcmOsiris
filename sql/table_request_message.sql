/* =============================================================================
 * Verze: 2026-11-13 17:30
 * Soubor: table_request_message.sql
 * Popis:   Dočasné zprávy a proměnné requestu vázané na @@SPID v dbsession.
 * Vazby:   - Využívá tabulku dbsession (cizí klíč spid), tabulku meta_phrase
 *            a funkci dbo.f_language_list pro překlad kódových zpráv.
 *          - Voláno z procedury printt, p_xlsx_meta_object, p_empty_trash
 *            a dalších SQL procedur.
 * Změny:   - 2026-11-13 17:30: Doplněna registrace tříd request_message a
 *            request_variable do sysinit_class a sloupců do sysinit_column.
 *          - 2026-10-29 15:30: Funkce dbo.f_php_phrase napojena na fallback
 *            řetězec z dbo.f_language_list(@lang) s podmínkou fallback_order < 1000.
 *          - 2026-10-20 11:25: Výchozí a fallbackový source_code ve funkci
 *            dbo.f_php_phrase změněn z prázdného '' na 'global_phrase'.
 * ============================================================================= */

execute dropni 'request_message'
execute dropni 'request_variable'
execute dropni 'insert_request_message'
execute dropni 'select_request_message'
execute dropni 'f_php_phrase'
execute dropni 'p_session_variable'
execute dropni 'f_session_variable'
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
-- Tabulka request_variable slouží k zápisu různých proměnných procedurami,
-- typicky návratových hodnot, které může nadřízená procedura nebo klient pod stejným @@SPID získat
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
	Funkce vrátí přeložený text fráze podle zadaného kódu z tabulky meta_phrase
	s využitím jazykového fallback řetězce dbo.f_language_list(@lang) (fallback_order < 1000).
	Jazyk a aktivní organizaci načítá autonomně z tabulky dbsession pro aktuální @@SPID.
	Pro globální fráze používá sjednocený source_code = 'global_phrase'.
*/
create function dbo.f_php_phrase(
	@code varchar(80),
	@source_code varchar(80) = 'global_phrase'
)
returns varchar(6000)
as
begin
	declare @lang varchar(2) = 'cs', @org uuid = 0x00, @result varchar(6000) = null;

	if isnull(@source_code, '') = ''
		set @source_code = 'global_phrase';

	select @lang = [language], @org = organization
	from dbsession
	where spid = @@spid;

	if object_id('meta_phrase') is not null
	begin
		select top 1
			@result = coalesce(
				tr.caption,
				nullif(cast(mv.caption as varchar(6000)), ''),
				nullif(cast(ms.caption as varchar(6000)), '')
			)
		from meta_phrase ms
		left join meta_phrase mv
			on mv.original = ms.original
			and mv.object_owner = @org
			and mv.record_type = 'A'
			and mv.removed = 0
		outer apply (
			select top 1 cast(l.caption as varchar(6000)) as caption
			from meta_phrase l
			join dbo.f_language_list(@lang) fl
				on fl.[language] = l.[language]
				and fl.fallback_order < 1000
			where l.original = ms.original
			  and l.record_type = 'L'
			  and l.removed = 0
			  and l.object_owner in (@org, 0x00)
			  and nullif(cast(l.caption as varchar(6000)), '') is not null
			order by fl.fallback_order asc, case when l.object_owner = @org then 0 else 1 end asc
		) tr
		where ms.object_owner = 0x00
		  and ms.record_type = 'A'
		  and ms.removed = 0
		  and ms.builtin_code = @code
		  and (ms.source_code = @source_code or ms.source_code = 'global_phrase')
		order by case when ms.source_code = @source_code then 0 else 1 end;
	end

	return isnull(@result, @code);
end
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
set @charvalue=isnull(@charvalue,'')
if @code<>'' and exists(select * from request_message where spid=@@spid and code=@code) begin
	if @intvalue>0
		update request_message set intvalue=intvalue+@intvalue
		where spid=@@spid and code=@code
	return
end

if not exists(select * from dbsession where spid=@@spid) return

if @code<>'' and @msgtext='' set @msgtext=dbo.f_php_phrase(@code, default)
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
from request_message where spid=@@spid
order by code, counter
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

-- -----------------------------------------------------------------------------
-- Registrace tříd a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name IN ('request_message', 'request_variable');

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('request_message','cs','T','request_message','Zpráva zpracování požadavku','Zprávy zpracování požadavku','Dočasná fronta stavových, varovných a chybových zpráv vygenerovaných během běhu SQL procedur.','Zprávy vázané na @@SPID pro zobrazení výsledku operace uživateli.'),
	('request_variable','cs','T','request_variable','Proměnná požadavku','Proměnné požadavku','Dočasné úložiště návratových proměnných mezi uloženými procedurami v rámci jednoho @@SPID.','Technická tabulka pro předávání hodnot uvnitř databázové relace.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('request_message','en','Request Processing Message','Request Processing Messages','Temporary queue of status, warning, and error messages generated during SQL procedure execution.','Messages bound to @@SPID for displaying operation results to the user.'),
	('request_variable','en','Request Variable','Request Variables','Temporary storage of return variables shared between stored procedures within the same @@SPID.','Technical table for passing values inside a database session.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name IN ('request_message', 'request_variable');

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('request_message','charvalue','cs','Textová hodnota (charvalue)','Textový detail / hodnota proměnné','Text. hodnota','Textový detail zprávy nebo hodnota proměnné požadavku.'),
	('request_message','code','cs','Kód (code)','Kód položky / zprávy','Kód','Technický kód zprávy nebo položky.'),
	('request_message','color','cs','Barva textu (color)','Barva zobrazení zprávy','Barva','Explicitní barva pro výpis řádku zprávy.'),
	('request_message','counter','cs','Pořadí zprávy (counter)','Pořadové číslo zprávy','Pořadí','Automatické pořadové číslo zprávy v tabulce request_message.'),
	('request_message','icon','cs','Ikona zprávy (icon)','Ikona zprávy','Ikona','Označení ikony u zprávy požadavku.'),
	('request_message','indent','cs','Úroveň odsazení (indent)','Odsazení řádku zprávy','Odsazení','Číselná úroveň grafického odsazení zprávy zleva.'),
	('request_message','intvalue','cs','Číselná hodnota (intvalue)','Číselná hodnota / počet řádků','Čís. hodnota','Celočíselná hodnota spojená se zprávou nebo proměnnou (např. počet zpracovaných záznamů).'),
	('request_message','msgtext','cs','Text zprávy (msgtext)','Hlavní text zprávy','Zpráva','Text stavového nebo chybového hlášení zobrazeného uživateli.'),
	('request_message','obj_name','cs','Název dotčeného objektu (obj_name)','Označení konkrétního objektu / položky','Název objektu','Konkrétní identifikátor nebo název záznamu, kterého se zpráva týká.'),
	('request_message','obj_type','cs','Typ dotčeného objektu (obj_type)','Typ objektu','Typ objektu','Druh objektu nebo tabulky, ke které se zpráva vztahuje.'),
	('request_message','severity','cs','Závažnost zprávy (severity)','Úroveň závažnosti (0=Info,1=OK,2=Var,3=Chyba)','Závažnost','Číselná závažnost zprávy: 0 = informace, 1 = potvrzení OK, 2 = varování, 3 = kritická chyba.'),
	('request_message','style','cs','CSS styl řádku (style)','Inline CSS styl výpisu','CSS styl','Doplňkový CSS styl pro vykreslení řádku zprávy.'),
	('request_variable','uuidvalue','cs','UUID hodnota (uuidvalue)','Hodnota typu UUID','UUID hodnota','Identifikátor UUID uložený v proměnné požadavku.'),
	('request_variable','varname','cs','Název proměnné (varname)','Název proměnné požadavku','Proměnná','Jméno proměnné uložené v tabulce request_variable.'),
	('request_message','charvalue','en','Character Value (charvalue)','Text Detail / Variable Value','Char. Value','Text detail of the message or value of the request variable.'),
	('request_message','code','en','Code (code)','Item / Message Code','Code','Technical code of the message or item.'),
	('request_message','color','en','Text Color (color)','Message Display Color','Color','Explicit text color for rendering the message row.'),
	('request_message','counter','en','Message Counter (counter)','Sequential Message Number','Counter','Automatic sequential number of the message in request_message.'),
	('request_message','icon','en','Message Icon (icon)','Message Icon','Icon','Icon identifier for a request message.'),
	('request_message','indent','en','Indentation Level (indent)','Message Row Indentation','Indent','Numeric visual indentation level of the message from the left.'),
	('request_message','intvalue','en','Integer Value (intvalue)','Numeric Value / Row Count','Int. Value','Integer value associated with the message or variable (e.g., processed row count).'),
	('request_message','msgtext','en','Message Text (msgtext)','Main Message Text','Message','Status or error message text displayed to the user.'),
	('request_message','obj_name','en','Affected Object Name (obj_name)','Specific Object / Item Identifier','Object Name','Specific identifier or name of the record to which the message relates.'),
	('request_message','obj_type','en','Affected Object Type (obj_type)','Object Type','Object Type','Type of object or table to which the message relates.'),
	('request_message','severity','en','Message Severity (severity)','Severity Level (0=Info,1=OK,2=Warn,3=Err)','Severity','Numeric severity level: 0 = info, 1 = OK confirmation, 2 = warning, 3 = critical error.'),
	('request_message','style','en','Row CSS Style (style)','Inline CSS Display Style','CSS Style','Additional inline CSS style for rendering the message row.'),
	('request_variable','uuidvalue','en','UUID Value (uuidvalue)','UUID Variable Value','UUID Value','UUID identifier stored in a request variable.'),
	('request_variable','varname','en','Variable Name (varname)','Request Variable Name','Variable','Name of the variable stored in request_variable.');
END
GO