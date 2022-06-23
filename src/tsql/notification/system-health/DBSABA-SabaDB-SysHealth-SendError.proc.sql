USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'SysHealth.SendError'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	SysHealth.SendError
					@Title			NVARCHAR(128)			= NULL
				,	@ErrorNumber	INT						= NULL
				,	@ErrorSeverity	INT						= NULL
				,	@ErrorState		INT						= NULL
				,	@ErrorProcedure	NVARCHAR(256)			= NULL
				,	@ErrorLine		INT						= NULL
				,	@ErrorMessage	NVARCHAR(MAX)			= NULL
				,	@Server			NVARCHAR(128)			= NULL
				,	@Database		NVARCHAR(128)			= NULL
				,	@isTest			BIT						= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220623@Billy
	Location:		DBSABA.SabaDB
	Description:	Send Error
					Receive error data then send them via SysHealth Channel

	Parameters:
		@Title				[optional]		- Title of error message
		@ErrorNumber		[REQUIRED]		- 
		@ErrorSeverity		[REQUIRED]		- 
		@ErrorState			[REQUIRED]		- 
		@ErrorProcedure		[REQUIRED]		- 
		@ErrorLine			[REQUIRED]		- 
		@ErrorMessage		[REQUIRED]		- 
		@DB					[optional]		- Database where error is happening
		@isTest				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing

	Version:	1.0.0
	Revision:
		- [1.0.0]	20220623@Billy		Release SysHealth.SendError
		- [0.0.1]	20220623@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Message		NVARCHAR(MAX)
		,	@NL				NVARCHAR(10)	= N'  
'
		;

	SELECT	@Message	= CONCAT_WS(@NL
						,	CONCAT(N'`', CONVERT(NVARCHAR(128), SYSUTCDATETIME(), 127), N'`')
						,	CONCAT(
								N'\\\[', ISNULL(@Title, N'SQL Server Error'), N'\]  `'
							,	CONCAT_WS(N'.', ISNULL(@Server, PUBLISHINGSERVERNAME()), ISNULL(@Database, DB_NAME()))
							, 	N'`'
							)
						,	CONCAT(
								N'`Msg ', @ErrorNumber, N'`, '
							,	N'`Level ', @ErrorSeverity, N'`, '
							,	N'`State ', @ErrorState, N'`, '
							,	ISNULL(N'`Procedure ' + @ErrorProcedure + N'`, ', N'Adhoc script, ')
							,	N'`Line ', @ErrorLine, N'`'
							)
						,	CONCAT(N'`', @ErrorMessage, N'`')
						);
	EXECUTE	SysHealth.SendNotification @Message, @isTest;
END;
GO
