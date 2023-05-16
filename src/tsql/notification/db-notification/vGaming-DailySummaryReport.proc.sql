USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'vGaming.DailySummaryReport'
	,	@Version	SYSNAME		= N'3.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
DECLARE	@Procedure	SYSNAME		= N'vGaming.DailySummaryReport_Wrapper'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	vGaming.DailySummaryReport
					@reportDate		DATE
				,	@isTest			BIT				= 1
WITH ENCRYPTION
AS
/*
	Creator:		20210529@Billy
	Location:		DBSABA.SabaDB
	Description:	Compare Daily Summary for vGaming
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing


	Version:	3.0.0
	Revision:
		- [3.0.0]	20230515@Billy		Sum by operator & convert to base currency
		- [2.2.2]	20230428@Billy		Treat vG as one platfrom
		- [2.2.1]	20230413@Billy		Reformat due to Skynex changes
		- [2.2.0]	20220624@Billy		Using SQL Server 2019 syntax
		- [2.1.2]	20220621@Billy		Reformat messages
		- [2.1.1]	20211020@Billy		Group by currency code
		- [2.1.0]	20210806@Billy		Migrate SC2 to vG2
		- [2.0.1]	20210722@Billy		Base SP updated for SIT environment support
		- [2.0.0]	20210531@Billy		Split into SabaClub & vGaming report
		- [1.0.2]	20210423@Billy		Update message format - [Gitlab: #060]
		- [1.0.1]	20210218@Billy		Report by currency for SC3 - [Gitlab: #058]
		- [1.0.0]	20201008@Billy		Release Noti.DailySummaryReport - [Gitlab: #058]
		- [0.0.1]	20201008@Billy		Initital - [Gitlab: #058]
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@vendorId		INT 			= 66
		,	@L				TINYINT			= 2
		,	@Env			TINYINT			= 1
		,	@Status			NVARCHAR(128)	= N'OK'
		,	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)
		;

	SELECT	@ReportDate		= ISNULL(@reportDate, DATEADD(DAY, -1, GETUTCDATE()))
		,	@isTest			= ISNULL(@isTest, 1)
		;

	IF	NOT (DATEDIFF(DAY, @reportDate, GETUTCDATE()) BETWEEN 1 AND 7)
	BEGIN;
		RAISERROR(N'\
[ERR]   @reportDate is out of range', 0, 0) WITH NOWAIT;
		RETURN;
	END;

	DECLARE	@isCash			TINYINT
		,	@gameId			SMALLINT
		,	@gameTypeId		SMALLINT
		,	@gameName		NVARCHAR(128)
		,	@Message		NVARCHAR(MAX)
		;

	DECLARE	@Currencies	dbr.Currencies;
	DECLARE	@Exchanges	dbr.ExchangeRates;

	DECLARE	@OW_Summary	dbr.OW_DailySummary;
	DECLARE	@L_Summary	dbr.L_DailySummary;

	DECLARE	@OW_DailySummary	dbr.OW_DailySummary;
	DECLARE	@L_DailySummary		dbr.L_DailySummary;

	DECLARE	@Mismatches			dbr.L_DailySummary;


	INSERT INTO	@Currencies
	EXECUTE	dbr.L_Currencies @L, @Env;

	INSERT INTO @Exchanges
	EXECUTE	dbr.L_LastExchangeRate @L, @Env;

	INSERT INTO	@OW_Summary
	EXECUTE	dbr.OW_DailySummary @vendorId, @reportDate;

	INSERT INTO	@L_Summary
	EXECUTE	dbr.L_DailySummary @L, @reportDate;


	INSERT INTO	@OW_DailySummary (site, time, gameTypeId, gameName, currency, betcount, turnOver, payOut)
	SELECT	[site]			= m.operatorId
		,	[time]			= ow.time
		,	[gameTypeId]	= ow.gameTypeId
		,	[gameName]		= ow.gameName
		,	[currency]		= nc.currency
		,	[betCount]		= SUM(ow.betCount)
		,	[turnOver]		= SUM(ow.turnOver * r.rate)
		,	[payOut]		= SUM(ow.payOut * r.rate)
	FROM	@OW_Summary AS ow
	CROSS APPLY	(VALUES (NULLIF(ow.site, N'-'))) AS n(site)
	OUTER APPLY	dbr.tf_OW_OperatorMapping(@vendorId, n.site) AS m
	LEFT JOIN	@Currencies AS c
			ON	m.operatorId = c.operatorId
			AND	ow.currency = c.name
	CROSS APPLY	(VALUES (ISNULL(c.code, ow.currency))) nc(currency)
	LEFT JOIN	@Exchanges AS e
			ON	nc.currency = e.code
	CROSS APPLY	(VALUES (ISNULL(c.multiplier, 1) * ISNULL(e.rate, 1))) AS r(rate)
	WHERE	ow.currency <> 'UUS'
	GROUP BY m.operatorId, ow.time, ow.gameTypeId, ow.gameName, nc.currency;


	INSERT INTO	@L_DailySummary (operatorId, time, gameTypeId, gameId, gameName, currency, betCount, turnOver, payOut)
	SELECT	[operatorId]	= l.operatorId
		,	[time]			= l.time
		,	[gameTypeId]	= l.gameTypeId
		,	[gameId]		= l.gameId
		,	[gameName]		= l.gameName
		,	[currency]		= nc.currency
		,	[betCount]		= SUM(l.betCount)
		,	[turnOver]		= SUM(l.turnOver * r.rate)
		,	[payOut]		= SUM(l.payOut * r.rate)
	FROM	@L_Summary AS l
	LEFT JOIN	@Currencies AS c
			ON	l.operatorId = c.operatorId
			AND	l.currency = c.name
	CROSS APPLY	(VALUES (ISNULL(c.code, l.currency))) nc(currency)
	LEFT JOIN	@Exchanges AS e
			ON	nc.currency = e.code
	CROSS APPLY	(VALUES (ISNULL(c.multiplier, 1) * ISNULL(e.rate, 1))) AS r(rate)
	WHERE	l.currency <> 'UUS'
	GROUP BY l.operatorId, l.time, l.gameTypeId, l.gameId, l.gameName, nc.currency


	INSERT INTO	@Mismatches (operatorId, time, gameTypeId, gameId, gameName, currency, betCount, turnOver, payOut)
	SELECT	[operatorId]	= ISNULL(ow.site, l.operatorId)
		,	[time]			= ISNULL(ow.time, l.time)
		,	[gameTypeId]	= ISNULL(ow.gameTypeId, l.gameTypeId)
		,	[gameId]		= ISNULL(l.gameId, 0)
		,	[gameName]		= ISNULL(ow.gameName, l.gameName)
		,	[currency]		= ISNULL(ow.currency, l.currency)
		,	[betCount]		= diff.betCount
		,	[turnOver]		= diff.turnOver
		,	[payOut]		= diff.payOut
	FROM			@OW_DailySummary AS ow
	FULL OUTER JOIN	@L_DailySummary AS l
				ON	ow.site = l.operatorId
				AND	ow.time = l.time
				AND	ow.gameTypeId = l.gameTypeId
				AND	ow.currency = l.currency
	CROSS APPLY	(VALUES	(
		ISNULL(ow.betCount, 0) - ISNULL(l.betCount, 0)
	,	ISNULL(ow.turnOver, 0) - ISNULL(l.turnOver, 0)
	,	ISNULL(ow.payOut, 0) - ISNULL(l.payOut, 0)
	)) AS diff(betCount, turnOver, payOut)
	WHERE	ISNULL(ow.gameTypeId, l.gameTypeId) NOT IN (SELECT gameTypeId FROM dbr.tf_JackpotBettype())
		AND	diff.betCount + diff.turnOver + diff.payOut <> 0


	WHILE	EXISTS (SELECT 1 FROM @Mismatches)
	BEGIN;
		SELECT	TOP(1)
				@gameTypeId	= gameTypeId
			,	@gameId		= gameId
			,	@gameName	= gameName
			,	@Status		= N'MISMATCH'
		FROM	@Mismatches
		ORDER BY gameTypeId;

		SELECT	@Message = CONCAT_WS(@NL
				,	CONCAT(N'[', @Status, N'] [VG] @`', FORMAT(@reportDate, 'yyyy-MM-dd'), N'`')
				,	CONCAT(N'[', @gameTypeId, N'.', @gameId, N'] ', @gameName, N': (`BC`|`TO`|`PO`)')
				,	STRING_AGG(CONCAT(
						N'  `', m.operatorId, N'`: '
					,	CONCAT_WS(N'|',
								FORMAT(m.betCount, '#,##0.##')
							,	FORMAT(m.turnOver, '#,##0.##')
							,	FORMAT(m.payOut, '#,##0.##')
						)
					), @NL)
				)
		FROM	@Mismatches AS m
		WHERE	m.gameTypeId = @gameTypeId;

		EXECUTE	Noti.SendNotification @Message, @isTest;

		DELETE	@Mismatches
		WHERE	gameTypeId = @gameTypeId;
	END;


	SELECT	@Message	= CONCAT_WS(@NL,
				CONCAT(N'[', @Status, N'] [vGaming Summary `', FORMAT(@reportDate, 'yyyy-MM-dd') , N'`]')
			,	STRING_AGG(CONCAT(@NL, g.str), @NL) WITHIN GROUP (ORDER BY g.operatorId)
			)
	FROM	(
		SELECT	[operatorId]	= s.operatorId
			,	[str]			= CONCAT_WS(@NL
				,	CONCAT(N'`', s.operatorId, N'`  -  `💸`:  ')
				,	CONCAT(N'  - BC:  `', FORMAT(SUM(s.betCount), '#,##0.##'), N'`  ')
				,	CONCAT(N'  - TO:  `', FORMAT(SUM(s.turnOver), '#,##0.##'), N'`  ')
				,	CONCAT(N'  - WL:  `', FORMAT(SUM(s.turnOver - s.payOut), '#,##0.##'), N'`  ')
				)
		FROM	@L_DailySummary AS s
		GROUP BY s.operatorId
	) AS g;

	EXECUTE	Noti.SendNotification @Message, @isTest;
END;
GO
ALTER PROCEDURE	vGaming.DailySummaryReport_Wrapper
					@reportDate		DATE			= NULL
				,	@isTest			BIT				= 1

				,	@errorName		NVARCHAR(128)	= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220624@Billy
	Location:		DBSABA.SabaDB
	Description:	Daily Summary Report Wrapper - No error execution
					Compare Daily Summary for vGaming then send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday
		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var3:				[optional]		- The title for error message
				<DEFAULT>	NULL			- Default title

	Version:	2.0.0
	Revision:
		- [2.0.0]	20230515@Billy		Rename parameters
		- [1.0.0]	20220624@Billy		Release vGaming.DailySummaryReport_Wrapper
		- [0.0.1]	20220624@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	vGaming.DailySummaryReport @reportDate, @isTest;
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
EXECUTE	vGaming.DailySummaryReport_Wrapper NULL, NULL, N'Adhoc Test';
GO
