USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'Noti.SendNotification'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	Noti.SendNotification
					@Var1			NVARCHAR(MAX)	= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210529@Billy
	Location:		DBSABA.SabaDB
	Description:	Send message to telegram channel - [Skynex.SC] DB Notification

	Parameters:
		@Var1:				[optional]		- Message that will be sent
				<DEFAULT>	NULL			- Message will NOT be sent

		@Var2:				[optional]		- Is this testing message?
				<DEFAULT>	NULL			- Treat as if testing message

	Version:	1.0.1
	Revision:
		- [1.0.1]	20211221@Billy	Print message to stdout for native debugging
									Handle error when sending message
		- [1.0.0]	20210529@Billy	Release Noti.SendNotification
		- [0.0.1]	20210529@Billy	Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Message		NVARCHAR(MAX)	= @Var1
		,	@isTest			BIT
		;

	BEGIN TRY SELECT @isTest = CONVERT(BIT, @Var2) END TRY BEGIN CATCH SELECT @isTest = 1 END CATCH;

	SELECT	@isTest = ISNULL(@isTest, 1);

	DECLARE	@Telegram		NVARCHAR(128)	= CASE @isTest WHEN 0 THEN N'T-SCNOTI' ELSE N'T-BILLY' END
		;

	IF	@Message IS NOT NULL
	BEGIN TRY;
		EXECUTE	DBNOTI.NotificationDB.dbo.Skype_SendMessage
					@To			= @Telegram
				,	@Msg		= @Message
				;
		RAISERROR(N'\
[INFO]  Message''s sent to [%s]', 0, 0, @Telegram) WITH NOWAIT;
	END TRY BEGIN CATCH;
		RAISERROR(N'\
[ERR]   There is a problem at sending message, printing instead.', 0, 0) WITH NOWAIT;
		GOTO stdout;
	END CATCH;
	ELSE
	BEGIN;
		RAISERROR(N'\
[WARN]  NULL message will NOT be sent.', 0, 0) WITH NOWAIT;
	END;

	IF	@isTest = 1
		GOTO stdout;

	RETURN;

	stdout:
	RAISERROR(N'\
[DEBUG] Send message to telegram
------------------ [%s] ------------------
%s
------------------ [%s] ------------------', 0, 0, @Telegram, @Message, @Telegram) WITH NOWAIT;
END;
GO
GRANT EXECUTE ON Noti.SendNotification TO sqlLink AS dbo;
