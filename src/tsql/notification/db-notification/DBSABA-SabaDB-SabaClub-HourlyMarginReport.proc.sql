USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'SabaClub.HourlyMarginReport'
	,	@Version	SYSNAME		= N'0.0.3'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	SabaClub.HourlyMarginReport
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220216@Billy
	Location:		DBSABA.SabaDB
	Description:	Hourly Margin Report for SabaClub
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The hour of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing


	Version:	0.0.3
	Revision:
		- [1.0.0]	20220216@Billy		Release SabaClub.HourlyMarginReport
		- [0.0.2]	20220225@Billy		Limit positive margin to 3 items
										Add margin history status
										Add margin over total turnover
		- [0.0.1]	20220216@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@ReportHour		DATETIME
		,	@isTest			BIT
		;

	BEGIN TRY SELECT @ReportHour = CONVERT(DATETIME, @Var1) END TRY BEGIN CATCH SELECT @ReportHour = NULL END CATCH;
	BEGIN TRY SELECT @isTest     = CONVERT(BIT     , @Var2) END TRY BEGIN CATCH SELECT @isTest     = NULL END CATCH;

	SELECT	@ReportHour		= ISNULL(@ReportHour, DATEADD(HOUR, -1, GETUTCDATE()))
		,	@ReportHour		= DATEADD(HOUR, DATEDIFF(HOUR, 0, @ReportHour), 0)
		,	@isTest			= ISNULL(@isTest, 1)
		;

	IF	NOT (DATEDIFF(HOUR, @ReportHour, GETUTCDATE()) BETWEEN 1 AND 7 * 24)
	BEGIN;
		RAISERROR(N'\
[ERR]   @ReportHour is out of range', 0, 0) WITH NOWAIT;
		GOTO Finish;
	END;

	DECLARE	@L				INT
		,	@Hour			DATETIME
		,	@Icon			NVARCHAR(10)
		,	@Message		NVARCHAR(MAX)
		;

	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	icon			NVARCHAR(10)
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (L)
			);
	
	DECLARE	@Hours AS TABLE (
				h				DATETIME
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (h)
			)

	DECLARE	@Report AS TABLE (
				L				TINYINT
			,	reportTime		DATETIME
			,	gameType		NVARCHAR(128)
			,	betCount		INT
			,	turnOver		DECIMAL(19,4)
			,	winLoss			DECIMAL(19,4)
			,	margin			DECIMAL(19,4)
			,	marginL			DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (L, gameType, reportTime)
			);

	CREATE TABLE	#HourlySummary (
						L				TINYINT
					,	reportTime		DATETIME
					,	gameId			INT
					,	gameTypeId		INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	isCash			TINYINT
					,	betCount		INT
					,	stake			DECIMAL(19,4)
					,	payOut			DECIMAL(19,4)
					,	PRIMARY KEY CLUSTERED (L, reportTime, gameTypeId, currency, isCash)
					);

	-- List of Ls --
	INSERT INTO	@Ls
			(L, icon , isDone)
	VALUES	(1, N'1️⃣',      0)
		,	(2, N'2️⃣',      0)
		;

	-- List of hours --
	INSERT INTO @Hours (h)
	SELECT	DATEADD(HOUR, - tally.n, @ReportHour)
	FROM	(
		SELECT	ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) - 1
		FROM	(VALUES	(0), (0), (0), (0), (0), (0), (0), (0), (0), (0)) AS x10(n)
	) AS tally(n)
	WHERE	tally.n < 5;

	WHILE	0 = 0
	BEGIN;
		UPDATE	TOP(1)
				@Ls
		SET		@L		= L
			,	@Icon	= icon
			,	isDone	= 1
		WHERE	isDone	= 0;

		IF	@@ROWCOUNT = 0
			BREAK;

		UPDATE	@Hours
		SET		isDone = 0;

		WHILE	0 = 0
		BEGIN;
			UPDATE	TOP(1)
					@Hours
			SET		@Hour = h
				,	isDone = 1
			WHERE	isDone = 0;

			IF	@@ROWCOUNT = 0
				BREAK;

			INSERT INTO	#HourlySummary (L, reportTime, gameId, gameTypeId, gameType, currency, isCash, betCount, stake, payOut)
			EXECUTE	dbr.SB_HourlySummary @L, 1, @Hour;
		END;

		DELETE	@Report;
		INSERT INTO	@Report (L, reportTime, gameType, betCount, turnOver, winLoss, margin, marginL)
		SELECT	[L]				= s.L
			,	[reportTime]	= s.reportTime
			,	[gameType]		= s.gameType
			,	[betCount]		= SUM(s.betCount)
			,	[turnOver]		= SUM(s.stake)
			,	[winLoss]		= SUM(s.stake) - SUM(s.payOut)
			,	[margin]		= (SUM(s.stake) - SUM(s.payOut)) / SUM(s.stake)
			,	[marginL]		= (SUM(s.stake) - SUM(s.payOut)) / SUM(SUM(s.stake)) OVER(PARTITION BY s.L, s.reportTime)
		FROM	#HourlySummary AS s
		WHERE	s.L = @L
			AND	s.currency <> 'UUS'
		GROUP BY	s.L, s.reportTime, s.gameType;

		SELECT	@Message = @Icon + N'  NEGATIVE MARGIN @' + CONVERT(NVARCHAR(MAX), @ReportHour, 127) + N'
' + msg.str
		FROM	(
			SELECT	N'
---

\\\[' + r.gameType + N'\] ' + s.str + N'  
\`BC\`: ' + REPLACE(CONVERT(NVARCHAR(MAX), CAST(r.betCount AS MONEY), 1), '.00', '') + N'  
\`TO\`: ' + CONVERT(NVARCHAR(MAX), CAST(r.turnOver AS MONEY), 1) + N'  
\`WL\`: ' + CONVERT(NVARCHAR(MAX), CAST(r.winLoss AS MONEY), 1) + N'  
\`MG\`: ' + CONVERT(NVARCHAR(MAX), CAST(r.margin * 100 AS MONEY), 1) + N'%  \(' + CONVERT(NVARCHAR(MAX), CAST(r.marginL * 100 AS MONEY), 1) + N'%\)  

'
			FROM	@Report AS r
			CROSS APPLY	(
				SELECT	CASE WHEN _sub.margin < 0 THEN N'🔴' WHEN _sub.margin > 0 THEN N'🟢' WHEN _sub.margin = 0 THEN N'🟡' ELSE N'⚫️' END
				FROM		@Hours AS _h
				LEFT JOIN	@Report AS _sub
						ON	_sub.L = r.L
						AND	_sub.gameType = r.gameType
						AND	_sub.reportTime = _h.h
				ORDER BY _h.h
				FOR XML PATH ('')
				,	TYPE
			) AS sx(xml)
			CROSS APPLY	(
				SELECT	sx.xml.value('.', 'NVARCHAR(MAX)')
			) AS s(str)
			WHERE	r.reportTime = @ReportHour
				AND	r.margin < 0
			ORDER BY r.winLoss ASC
			FOR XML PATH ('')
			,	TYPE
		) AS xmsg(xml)
		CROSS APPLY	(
			SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
		) AS msg(str);
		EXECUTE	dbo.SendNotification @Message, @isTest;
	END;

	Finish:
	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	SabaClub.HourlyMarginReport ;
GO
