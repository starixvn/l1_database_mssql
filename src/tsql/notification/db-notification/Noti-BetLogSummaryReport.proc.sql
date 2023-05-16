USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'Noti.BetLogSummaryReport'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
DECLARE	@Procedure	SYSNAME		= N'Noti.BetLogSummaryReport_Wrapper'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	Noti.BetLogSummaryReport
					@reportDate		DATE
				,	@isTest			BIT				= 1
WITH ENCRYPTION
AS
/*
	Creator:		20210601@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Betlog Summary
					Send result via Noti telegram channel

	Parameters:
		@reportDate			[REQUIRED]		- The date of data that will be fetched. The time is in UTC timezone.

		@isTest:			[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing

	Version:	2.0.0
	Revision:
		- [2.0.0]	20230515@Billy		Sum by operator & convert to base currency
		- [1.2.2]	20230413@Billy		Reformat due to Skynex changes
		- [1.2.1]	20230322@Billy		Add metadata for megakeno
		- [1.2.0]	20220623@Billy		Using SQL Server 2019 syntax
		- [1.1.2]	20220621@Billy		Reformat messages
		- [1.1.1]	20211018@Billy		Group by currency code
		- [1.1.0]	20210812@Billy		Support instant system
		- [1.0.1]	20210722@Billy		Base SP updated for SIT environment support
		- [1.0.0]	20210601@Billy		Release Noti.BetLogSummaryReport - [Gitlab: #058]
		- [0.0.1]	20210601@Billy		Initital - [Gitlab: #058]
*/
BEGIN;
	SET NOCOUNT ON;

	SELECT	@ReportDate		= ISNULL(@reportDate, DATEADD(DAY, -1, GETUTCDATE()))
		,	@isTest			= ISNULL(@isTest, 1)
		;

	IF	NOT (DATEDIFF(DAY, @ReportDate, GETUTCDATE()) BETWEEN 1 AND 7)
	BEGIN;
		RAISERROR(N'\
[ERR]   @ReportDate is out of range', 0, 0) WITH NOWAIT;
		RETURN;
	END;

	DECLARE	@L				INT
		,	@Name			NVARCHAR(128)
		,	@Message		NVARCHAR(MAX)
		;

	DECLARE	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)
		,	@Env			TINYINT			= 1
		;

	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	name			NVARCHAR(128)
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (L)
			);

	DECLARE	@Systems AS TABLE (
				L				TINYINT
			,	id				TINYINT
			,	name			NVARCHAR(128)
			,	maxNameLen		TINYINT
			,	PRIMARY KEY CLUSTERED (L, id)
			);

	DECLARE	@Currencies	dbr.Currencies;
	DECLARE	@Exchanges	dbr.ExchangeRates;

	DECLARE	@BetLog AS TABLE (
				L				TINYINT
			,	gameId			INT
			,	gameType		NVARCHAR(128)
			,	currency		VARCHAR(10)
			,	sys				TINYINT
			,	requestCount	INT
			,	betCount		INT
			,	turnOver		DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (L, gameId, currency, sys)
			);

	DECLARE	@BetLogSummary AS TABLE (
				sys				TINYINT
			,	requestCount	INT
			,	betCount		INT
			,	turnOver		DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (sys)
			)

	-- List of Ls --
	INSERT INTO	@Ls
			(L,  name, isDone)
	VALUES	(1, N'SC', 0)
		,	(2, N'VG', 0)
		;

	-- List of systems --
	INSERT INTO	@Systems
			(L, id, name)
	VALUES	(1,  1, N'SC')
		,	(1,  2, N'SM')
		,	(1,  3, N'SI')
		,	(1,  4, N'MK')
		,	(2,  1, N'VG')
		,	(2,  2, N'VGM')
		,	(2,  3, N'VGI')
		,	(2,  4, N'VMK')
		;

	UPDATE	s
	SET		maxNameLen = s.maxNameLenCalc
	FROM	(
		SELECT	*, maxNameLenCalc = MAX(LEN(name)) OVER()
		FROM	@Systems
	) AS s;


	UPDATE	@Ls
	SET		isDone = 0;

	WHILE	EXISTS (SELECT 1 FROM @Ls WHERE isDone = 0)
	BEGIN;
		UPDATE	TOP(1)
				@Ls
		SET		@L		= L
			,	@Name	= name
			,	isDone	= 1
		WHERE	isDone	= 0;


		DELETE	@BetLog;
		INSERT INTO	@BetLog (L, gameId, gameType, currency, sys, requestCount, betCount, turnOver)
		EXECUTE	dbr.SB_BetLogSummary @L, 1, @ReportDate;
		RAISERROR('Executed on L%d.', 0, 0, @L) WITH NOWAIT;

		DELETE	@Currencies;
		INSERT INTO	@Currencies
		EXECUTE	dbr.L_Currencies @L, @Env;

		DELETE	@Exchanges;
		INSERT INTO @Exchanges
		EXECUTE	dbr.L_LastExchangeRate @L, @Env;


		DELETE	@BetLogSummary;
		INSERT INTO	@BetLogSummary (sys, requestCount, betCount, turnOver)
		SELECT	[sys]			= s.sys
			,	[requestCount]	= SUM(s.requestCount)
			,	[betCount]		= SUM(s.betCount)
			,	[turnOver]		= SUM(s.turnOver * ISNULL(cur.rate, 1))
		FROM	@BetLog AS s
		OUTER APPLY (
			SELECT	TOP(1)
					[rate]	= r.rate
			FROM		@Currencies AS c
			CROSS APPLY	(VALUES (ISNULL(c.code, s.currency))) nc(currency)
			LEFT JOIN	@Exchanges AS e
					ON	nc.currency = e.code
			CROSS APPLY	(VALUES (ISNULL(c.multiplier, 1) * ISNULL(e.rate, 1))) AS r(rate)
			WHERE	s.currency = c.name
			ORDER BY r.rate DESC
		) AS cur
		WHERE	s.currency <> 'UUS'
		GROUP BY s.sys


		SELECT	@Message	= CONCAT_WS(@NL
				,	CONCAT(N'[`', @Name ,N'`  BetLog Summary `', FORMAT(@reportDate, 'yyyy-MM-dd'), N'`]')
				,	N'  (system:  RC | BC | TO)'
				,	STRING_AGG(CONCAT(
						N'  `', ISNULL(RIGHT(CONCAT(N'   ', sys.name), sys.maxNameLen), N'***'), N'` :  '
					,	CONCAT_WS(N' | '
						,	FORMAT(s.requestCount, N'#,##0.##')
						,	FORMAT(s.betCount, N'#,##0.##')
						,	FORMAT(s.turnOver, N'#,##0.##')
						)
					), @NL)
				)
		FROM		@BetLogSummary AS s
		LEFT JOIN	@Systems AS sys
				ON	sys.L = @L
				AND	sys.id = s.sys

		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;
END;
GO
ALTER PROCEDURE	Noti.BetLogSummaryReport_Wrapper
					@reportDate		DATE			= NULL
				,	@isTest			BIT				= 1

				,	@errorName		NVARCHAR(128)	= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220623@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Betlog Summary Wrapper - No error execution
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The date of data that will be fetched. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday
		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var3:				[optional]		- The title for error message
				<DEFAULT>	NULL			- Default title

	Version:	2.0.0
	Revision:
		- [2.0.0]	20230515@Billy		Rename parameters
		- [1.0.0]	20220623@Billy		Release Noti.BetLogSummaryReport_Wrapper
		- [0.0.1]	20220623@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	Noti.BetLogSummaryReport @reportDate, @isTest;
	END TRY BEGIN CATCH;
		DECLARE	@ErrNumber		INT				= ERROR_NUMBER()
			,	@ErrSeverity	INT				= ERROR_SEVERITY()
			,	@ErrState		INT				= ERROR_STATE()
			,	@ErrProcedure	NVARCHAR(128)	= ERROR_PROCEDURE()
			,	@ErrLine		INT				= ERROR_LINE()
			,	@ErrMessage		NVARCHAR(MAX)	= ERROR_MESSAGE()
			,	@Server			NVARCHAR(128)	= PUBLISHINGSERVERNAME()
			,	@Database		NVARCHAR(128)	= DB_NAME()
			;
		EXECUTE	SysHealth.SendError
					@Title			= @errorName
				,	@ErrorNumber	= @ErrNumber
				,	@ErrorSeverity	= @ErrSeverity
				,	@ErrorState		= @ErrState
				,	@ErrorProcedure	= @ErrProcedure
				,	@ErrorLine		= @ErrLine
				,	@ErrorMessage	= @ErrMessage
				,	@Server			= @Server
				,	@Database		= @Database
				,	@isTest			= @isTest
				;
	END CATCH;
END;
GO
EXECUTE	Noti.BetLogSummaryReport_Wrapper NULL, NULL, 'Adhoc Test';
GO
