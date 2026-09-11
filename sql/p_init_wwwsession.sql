EXECUTE dropni 'p_init_wwwsession', 'P'
GO

CREATE PROCEDURE [dbo].[p_init_wwwsession]
	@wwwsession varchar(40),
	@language varchar(2)=null,
	@working_date date=null,
	@no_result bit=0
AS
BEGIN
	SET NOCOUNT ON;

	DELETE FROM wwwsession
	FROM wwwsession u, system_constant c
	WHERE DATEADD(mi, c.session_timeout, u.request_date) < GETDATE();

	UPDATE wwwsession SET
		spid=@@spid,
		language=ISNULL(@language,language),
		working_date=ISNULL(@working_date,working_date),
		request_date=GETDATE()
	WHERE wwwsession=@wwwsession;

	DELETE FROM dbsession WHERE spid=@@spid;
	INSERT INTO dbsession SELECT * FROM wwwsession WHERE wwwsession=@wwwsession;

	IF @no_result=0 
	BEGIN
		SELECT * FROM dbsession WHERE spid=@@spid;
	END
END
GO