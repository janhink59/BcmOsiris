execute dropni 'p_init_wwwsession'
GO
/*

	Check active session, additional parameter allows to change current language

*/
create procedure [dbo].[p_init_wwwsession]
	@wwwsession varchar(40),
	@language varchar(2)=null,
	@working_date date=null,
	@no_result bit=0
as

set nocount on

-- Deleting expired sessions

delete from wwwsession
from wwwsession u, system_constant c
where dateadd(mi,c.session_timeout,u.request_date)<getdate()

-- Updating SPID (and LANGUAGE if needed)

update wwwsession set
	spid=@@spid,
	language=isnull(@language,language),
	working_date=isnull(@working_date,working_date),
	request_date=getdate()
where wwwsession=@wwwsession

-- Copy to DBSESSION (delete then insert method)
delete from dbsession where spid=@@spid
insert into dbsession select * from wwwsession where wwwsession=@wwwsession

-- Updating last request time in the log

if @no_result=0 select * from dbsession where spid=@@spid
GO

