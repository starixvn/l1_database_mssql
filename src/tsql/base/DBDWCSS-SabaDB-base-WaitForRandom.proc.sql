USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'base.WaitForRandom'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	base.WaitForRandom
					@Var1			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210208@Billy
	Location:		DBDWCSS.SabaDB
	Description:	Wait for random period of time before continue

	Parameters:
		@Var1:				[optional]		- The maximum number of seconds that we have to wait
				<DEFAULT>	NULL			- 3 seconds

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210208@Billy		Release base.WaitForRandom - [Gitlab: #058]
		- [0.0.1]	20210208@Billy		Initial - [Gitlab: #058]
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Sec		INT
		,	@WaitFor	VARCHAR(16)
		;

	BEGIN TRY SELECT @Sec = CAST(@Var1 AS INT) END TRY BEGIN CATCH SELECT @Sec = NULL END CATCH;

	SELECT	@Sec		= ISNULL(ABS(@Sec), 3);
	SELECT	@WaitFor	= '00:00:0'
						+ CAST(ABS(CHECKSUM(NEWID())) % @Sec AS CHAR(1))
						+ '.'
						+ CAST(ABS(CHECKSUM(NEWID())) % 1000 AS CHAR(3))
		;

	WAITFOR DELAY @WaitFor;
END;
GO
