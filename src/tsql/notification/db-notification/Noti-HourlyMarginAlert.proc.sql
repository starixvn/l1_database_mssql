USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'Noti.HourlyMarginAlert'
	,	@Version	SYSNAME		= N'2.1.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
DECLARE	@Procedure	SYSNAME		= N'Noti.HourlyMarginAlert_Wrapper'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	Noti.HourlyMarginAlert
					@reportHour			DATETIME		= NULL
				,	@isTest				BIT				= 1

				/** Configs */
				,	@historyDots		TINYINT			= 5
				,	@negCountToAlert	TINYINT			= 3
				,	@nullIgnore			TINYINT			= 1
				,	@totalThreshold		MONEY			= 0.01
WITH ENCRYPTION
AS
/*
	Creator:		20220303@Billy
	Location:		DBSABA.SabaDB
	Description:	Hourly Margin Alert for Noti
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The hour of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterhour

		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing

	Version:	2.1.0
	Revision:
		- [2.1.0]	20240617@Billy		Add xD product
		- [2.0.0]	20230515@Billy		Sum by operator & convert to base currency
		- [1.2.2]	20230413@Billy		Reformat due to Skynex changes
		- [1.2.1]	20220727@Billy		Add threshold to limit result
		- [1.2.0]	20220623@Billy		Using SQL Server 2019 syntax
		- [1.1.0]	20220309@Billy		Can config some alert variables now
		- [1.0.0]	20220308@Billy		Release Noti.HourlyMarginAlert
		- [0.0.1]	20220303@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		,	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)
		,	@reportDate		DATETIME
		;

	SELECT	@reportHour		= ISNULL(@reportHour, DATEADD(HOUR, -1, GETUTCDATE()))
		,	@reportHour		= DATEADD(HOUR, DATEDIFF(HOUR, 0, @reportHour), 0)
		,	@reportDate		= CAST(@reportHour AS DATE)
		;

	IF	NOT (DATEDIFF(HOUR, @reportHour, GETUTCDATE()) BETWEEN 1 AND 7 * 24)
	BEGIN;
		RAISERROR(N'\
[ERR]   @reportHour is out of range', 0, 0) WITH NOWAIT;
		GOTO Finish;
	END;

	DECLARE	@L				INT
		,	@fromHour		DATETIME
		,	@toHour			DATETIME
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

	DECLARE	@Hours				base.Hours;
	DECLARE	@Exchanges			dbr.ExchangeRates;
	DECLARE	@HourlySummary		dbr.L_SiteHourSummary;
	DECLARE	@GameTypeMapping	dbr.GameTypeMappingL;

	DECLARE	@Report AS TABLE (
				reportTime		DATETIME
			,	gameType		NVARCHAR(128)
			,	betCount		INT
			,	turnOver		DECIMAL(19,4)
			,	winLoss			DECIMAL(19,4)
			,	margin			DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (gameType, reportTime)
			);


	-- List of Ls --
	INSERT INTO	@Ls
			(L, icon , isDone)
	VALUES	(1, N'1️⃣',      0)
		,	(2, N'2️⃣',      0)
		,	(4, N'4️⃣',      0)
		;

	-- List of hours - From beginning of @reportDate --
	INSERT INTO @Hours (h)
	SELECT	DATEADD(HOUR, tally.n, @reportDate)
	FROM	(
		SELECT	ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) - 1
		FROM		(VALUES	(0), (0), (0), (0), (0), (0), (0), (0), (0), (0)) AS x10(n)
		CROSS APPLY	(VALUES	(0), (0), (0), (0), (0), (0), (0), (0), (0), (0)) AS x100(n)
	) AS tally(n)
	WHERE	tally.n <= DATEPART(HOUR, @reportHour);

	SELECT	@fromHour	= MIN(h)
		,	@toHour		= DATEADD(MINUTE, 1, MAX(h))
	FROM	@Hours;

	WHILE	0 = 0
	BEGIN;
		UPDATE	TOP(1)
				@Ls
		SET		@L		= L
			,	@Icon	= icon
			,	isDone	= 1
		WHERE	isDone	= 0;;

		IF	@@ROWCOUNT = 0
			BREAK;


		DELETE	@GameTypeMapping;
		INSERT INTO @GameTypeMapping (L, gameId, gameName)
		SELECT	L, gameId, gameName
		FROM	dbr.tf_GameTypeMapping(@L, NULL, NULL, NULL);


		DELETE @Exchanges;
		INSERT INTO	@Exchanges (exDate, code, rate)
		EXECUTE	dbr.L_LastExchangeRate @L, 1;


		DELETE	@HourlySummary;
		INSERT INTO	@HourlySummary (operatorId, time, gameTypeId, gameId, currency, betCount, turnOver, payOut)
		EXECUTE	dbr.L_SiteHourSummary @L, @fromHour, @toHour;

		DELETE	@Report;
		INSERT INTO	@Report (reportTime, gameType, betCount, turnOver, winLoss, margin)
		SELECT	[reportTime]	= s.time
			,	[gameType]		= m.gameName
			,	[betCount]		= SUM(s.betCount)
			,	[turnOver]		= SUM(s.turnOver * r.rate)
			,	[winLoss]		= (SUM(s.turnOver * r.rate) - SUM(s.payOut * r.rate))
			,	[margin]		= (SUM(s.turnOver * r.rate) - SUM(s.payOut * r.rate)) / ISNULL(NULLIF(SUM(s.turnOver * r.rate), 0), 1)
		FROM		@HourlySummary AS s
		LEFT JOIN	@GameTypeMapping AS m
				ON	m.L = @L
				AND	s.gameId = m.gameId
		LEFT JOIN	@Exchanges AS e
				ON	s.currency = e.code
		OUTER APPLY	(VALUES (ISNULL(e.rate, 1))) AS r(rate)
		WHERE	s.currency <> 'UUS'
		GROUP BY	s.time, m.gameName;

		IF	@isTest = 1
		BEGIN
			SELECT [@L] = @L, [@from] = @fromHour, [@to] = @toHour;
			SELECT * FROM @Hours;
			SELECT * FROM @HourlySummary;
			SELECT * FROM @Report;
		END;

		SELECT	@Message	= CONCAT(@Icon, N'  NEGATIVE MARGIN ALERT @`' + FORMAT(@reportHour, 'yyyy-MM-dd HH'), N'h`', @NL
							,	STRING_AGG(msg.msg, @NL) WITHIN GROUP (ORDER BY msg.wl)
							)
		FROM	(
			SELECT	[wl]	= r.winloss
				,	[msg]	= CONCAT_WS(@NL
							,	N''
							,	N'「' + r.gameType + N'」  ' + ds.str + N'  '
							,	CONCAT(N'Last Hour:  `', FORMAT(lh.winLoss, '#,##0'), N'` / `',	FORMAT(lh.turnOver, '#,##0'), N'`')
							,	CONCAT(N'Today:  `', FORMAT(r.winLoss, '#,##0'), N'` / `',	FORMAT(r.turnOver, '#,##0'), N'`')
							)
			FROM	(
				SELECT	[gameType]	= _r.gameType
					,	[turnOver]	= SUM(_r.turnOver)
					,	[winloss]	= SUM(_r.winLoss)
				FROM	@Report AS _r
				GROUP BY _r.gameType
			) AS r
			CROSS APPLY	(
				SELECT	TOP(1)
						[turnOver] = ISNULL(_r.turnOver, 0)
					,	[winLoss] = ISNULL(_r.winLoss, 0)
				FROM		@Hours AS _h
				LEFT JOIN	@Report AS _r
						ON	_r.gameType = r.gameType
						AND	_r.reportTime = _h.h
				ORDER BY _h.h DESC
			) AS lh
			CROSS APPLY	(
				SELECT	STRING_AGG(_d.d, N'') WITHIN GROUP (ORDER BY _d.h)
				FROM	(
					SELECT	TOP(@historyDots)
							[h] = _h.h
						,	[d] = CASE  WHEN _sub.margin < 0 THEN N'🔴'
										WHEN _sub.margin > 0 THEN N'🟢'
										WHEN _sub.margin = 0 THEN N'🟡'
										ELSE N'⚫️' END
					FROM		@Hours AS _h
					LEFT JOIN	@Report AS _sub
							ON	_sub.gameType = r.gameType
							AND	_sub.reportTime = _h.h
					ORDER BY _h.h DESC
				) AS _d
			) AS ds(str)
			CROSS APPLY	(
				SELECT	COUNT(1)
				FROM	(
					SELECT	TOP(@negCountToAlert)
							_r.winLoss
					FROM		@Hours AS _h
					LEFT JOIN	@Report AS _r
							ON	_r.gameType = r.gameType
							AND	_r.reportTime = _h.h
					ORDER BY _h.h DESC
				) AS _t
				WHERE	_t.winLoss < 0
			) AS nm(n)
			CROSS APPLY	(
				SELECT	COUNT(1)
				FROM	(
					SELECT	TOP(@nullIgnore)
							_r.winLoss
					FROM		@Hours AS _h
					LEFT JOIN	@Report AS _r
							ON	_r.gameType = r.gameType
							AND	_r.reportTime = _h.h
					ORDER BY _h.h DESC
				) AS _t
				WHERE	_t.winLoss IS NULL
			) AS nu(n)
			CROSS APPLY	(
				SELECT	SUM(_r.turnOver) * @totalThreshold
				FROM	@Report AS _r
			) AS turnover(threshold)
			CROSS APPLY	(
				SELECT	SUM(_r.winLoss) * @totalThreshold
				FROM	@Report AS _r
				WHERE	_r.winLoss < 0
			) AS loss(threshold)
			WHERE	(r.turnOver >= turnover.threshold OR r.winLoss <= loss.threshold)
				AND	(	(r.winloss < 0 AND nu.n < @nullIgnore)
					OR	nm.n = @negCountToAlert
					)
		) AS msg
		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;

	Finish:
	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
ALTER PROCEDURE	Noti.HourlyMarginAlert_Wrapper
					@reportHour			DATETIME		= NULL
				,	@isTest				BIT				= 1

				/** Configs */
				,	@historyDots		TINYINT			= 5
				,	@negCountToAlert	TINYINT			= 3
				,	@nullIgnore			TINYINT			= 1
				,	@totalThreshold		MONEY			= 0.01

				,	@errorName			NVARCHAR(128)	= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220623@Billy
	Location:		DBSABA.SabaDB
	Description:	Hourly Margin Alert for Noti Wrapper - No error execution
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The hour of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterhour
		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var3:				[optional]		- The title for error message
				<DEFAULT>	NULL			- Default title

	Version:	2.0.0
	Revision:
		- [2.0.0]	20230515@Billy		Rename parameters
		- [1.0.0]	20220623@Billy		Release Noti.HourlyMarginAlert_Wrapper
		- [0.0.1]	20220623@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	Noti.HourlyMarginAlert @reportHour, @isTest, @historyDots, @negCountToAlert, @nullIgnore, @totalThreshold;
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
EXECUTE	Noti.HourlyMarginAlert_Wrapper @errorName = N'Adhoc Test';
GO
