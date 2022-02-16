USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'Letstalk.SendNotification'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	Letstalk.SendNotification
					@Var1			NVARCHAR(MAX)	= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210531@Billy
	Location:		DBSABA.SabaDB
	Description:	Send message to letstalk channel

	Parameters:
		@Var1:				[optional]		- Message that will be sent
				<DEFAULT>	NULL			- Message will NOT be sent

		@Var2:				[optional]		- Title of message that will be sent
				<DEFAULT>	NULL			- Default title

		@Var3:				[optional]		- Is this testing message?
				<DEFAULT>	NULL			- Treat as if testing message

	Version:	1.0.1
	Revision:
		- [1.0.1]	20211221@Billy	Print message to stdout for native debugging
		- [1.0.0]	20210531@Billy	Release Letstalk.SendNotification
		- [0.0.1]	20210531@Billy	Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Message		NVARCHAR(MAX)	= @Var1
		,	@Title			NVARCHAR(128)
		,	@isTest			BIT
		;

	BEGIN TRY SELECT @Title  = CONVERT(NVARCHAR(128), @Var2) END TRY BEGIN CATCH SELECT @Title  = NULL END CATCH;
	BEGIN TRY SELECT @isTest = CONVERT(BIT          , @Var3) END TRY BEGIN CATCH SELECT @isTest = NULL END CATCH;

	SELECT	@isTest = ISNULL(@isTest, 1);

	DECLARE	@Letstalk		NVARCHAR(128)	= N'DBNotification'
		;

	IF	@Message IS NOT NULL AND @isTest = 0
	BEGIN TRY;
		EXECUTE	DBNOTI.NotificationDB.dbo.Letstalk_SendMessage
					@To			= @Letstalk
				,	@Title		= @Title
				,	@Msg		= @Message
				;
		RAISERROR(N'Message''s sent to [%s]', 0, 0, @Letstalk) WITH NOWAIT;
	END TRY BEGIN CATCH;
		RAISERROR(N'\
[ERR]   There is a problem at sending message, printing instead.', 0, 0) WITH NOWAIT;
		GOTO stdout;
	END CATCH;
	ELSE IF	@Message IS NULL
	BEGIN;
		RAISERROR(N'\
[WARN]  NULL message will NOT be sent.', 0, 0) WITH NOWAIT;
	END;

	IF	@isTest = 1
		GOTO stdout;

	RETURN;

	stdout:
	RAISERROR(N'\
[DEBUG] Send message to letstalk
------------------ [%s] ------------------
[%s]
%s
------------------ [%s] ------------------', 0, 0, @Letstalk, @Title, @Message, @Letstalk) WITH NOWAIT;
END;
GO
GRANT EXECUTE ON Letstalk.SendNotification TO sqlLink AS dbo;
