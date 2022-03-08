USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'Noti.HourlyMarginAlert'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	Noti.HourlyMarginAlert
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
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


	Version:	1.0.0
	Revision:
		- [1.0.0]	20220308@Billy		Release Noti.HourlyMarginAlert
		- [0.0.1]	20220303@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@ReportHour		DATETIME
		,	@ReportDate		DATETIME
		,	@isTest			BIT
		;

	BEGIN TRY SELECT @ReportHour = CONVERT(DATETIME, @Var1) END TRY BEGIN CATCH SELECT @ReportHour = NULL END CATCH;
	BEGIN TRY SELECT @isTest     = CONVERT(BIT     , @Var2) END TRY BEGIN CATCH SELECT @isTest     = NULL END CATCH;

	SELECT	@ReportHour		= ISNULL(@ReportHour, DATEADD(HOUR, -1, GETUTCDATE()))
		,	@ReportHour		= DATEADD(HOUR, DATEDIFF(HOUR, 0, @ReportHour), 0)
		,	@ReportDate		= CAST(@ReportHour AS DATE)
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
	SELECT	DATEADD(HOUR, tally.n, @ReportDate)
	FROM	(
		SELECT	ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) - 1
		FROM		(VALUES	(0), (0), (0), (0), (0), (0), (0), (0), (0), (0)) AS x10(n)
		CROSS APPLY	(VALUES	(0), (0), (0), (0), (0), (0), (0), (0), (0), (0)) AS x100(n)
	) AS tally(n)
	WHERE	tally.n <= DATEPART(HOUR, @ReportHour);

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

		TRUNCATE TABLE	#HourlySummary;

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
		INSERT INTO	@Report (L, reportTime, gameType, betCount, turnOver, winLoss, margin)
		SELECT	[L]				= s.L
			,	[reportTime]	= s.reportTime
			,	[gameType]		= s.gameType
			,	[betCount]		= SUM(s.betCount)
			,	[turnOver]		= SUM(s.stake)
			,	[winLoss]		= SUM(s.stake) - SUM(s.payOut)
			,	[margin]		= (SUM(s.stake) - SUM(s.payOut)) / SUM(s.stake)
		FROM	#HourlySummary AS s
		WHERE	s.L = @L
			AND	s.currency <> 'UUS'
		GROUP BY	s.L, s.reportTime, s.gameType;

		SELECT	@Message = @Icon + N'  NEGATIVE MARGIN ALERT @' + CONVERT(NVARCHAR(MAX), @ReportHour, 127) + N'
' + msg.str
		FROM	(
			SELECT	N'
---

「' + r.gameType + N'」  ' + ds.str + N'  
Last Hour:  `' + REPLACE(CONVERT(NVARCHAR(MAX), CAST(lh.winLoss AS MONEY), 1), '.00', '') + N'` / `' + REPLACE(CONVERT(NVARCHAR(MAX), CAST(lh.turnOver AS MONEY), 1), '.00', '') + N'`  
Today:  `' + REPLACE(CONVERT(NVARCHAR(MAX), CAST(r.winLoss AS MONEY), 1), '.00', '') + N'` / `' + REPLACE(CONVERT(NVARCHAR(MAX), CAST(r.turnOver AS MONEY), 1), '.00', '') + N'`  
  '
			FROM	(
				SELECT	[gameType]	= _r.gameType
					,	[turnOver]	= SUM(_r.turnOver)
					,	[winloss]	= SUM(_r.winLoss)
				FROM	@Report AS _r
				WHERE	_r.L = @L
				GROUP BY _r.gameType
			) AS r
			CROSS APPLY	(
				SELECT	TOP(1)
						[turnOver] = ISNULL(_r.turnOver, 0)
					,	[winLoss] = ISNULL(_r.winLoss, 0)
				FROM		@Hours AS _h
				LEFT JOIN	@Report AS _r
						ON	_r.L = @L
						AND	_r.gameType = r.gameType
						AND	_r.reportTime = _h.h
				ORDER BY _h.h DESC
			) AS lh
			CROSS APPLY	(
				SELECT	_d.d
				FROM	(
					SELECT	TOP(5)
							[h] = _h.h
						,	[d] = CASE  WHEN _sub.margin < 0 THEN N'🔴'
										WHEN _sub.margin > 0 THEN N'🟢'
										WHEN _sub.margin = 0 THEN N'🟡'
										ELSE N'⚫️' END
					FROM		@Hours AS _h
					LEFT JOIN	@Report AS _sub
							ON	_sub.L = @L
							AND	_sub.gameType = r.gameType
							AND	_sub.reportTime = _h.h
					ORDER BY _h.h DESC
				) AS _d
				ORDER BY _d.h
				FOR XML PATH ('')
				,	TYPE
			) AS dx(xml)
			CROSS APPLY	(
				SELECT	dx.xml.value('.', 'NVARCHAR(MAX)')
			) AS ds(str)
			CROSS APPLY	(
				SELECT	COUNT(1)
				FROM	(
					SELECT	TOP(3)
							_r.winLoss
					FROM		@Hours AS _h
					LEFT JOIN	@Report AS _r
							ON	_r.L = @L
							AND	_r.gameType = r.gameType
							AND	_r.reportTime = _h.h
					ORDER BY _h.h DESC
				) AS _t
				WHERE	_t.winLoss < 0
			) AS nm(n)
			CROSS APPLY	(
				SELECT	COUNT(1)
				FROM	(
					SELECT	TOP(3)
							_r.winLoss
					FROM		@Hours AS _h
					LEFT JOIN	@Report AS _r
							ON	_r.L = @L
							AND	_r.gameType = r.gameType
							AND	_r.reportTime = _h.h
					ORDER BY _h.h DESC
				) AS _t
				WHERE	_t.winLoss IS NULL
			) AS nu(n)
			WHERE	(r.winloss < 0 AND nu.n < 3)
				OR	nm.n = 3
			ORDER BY r.winloss ASC
			FOR XML PATH ('')
			,	TYPE
		) AS xmsg(xml)
		CROSS APPLY	(
			SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
		) AS msg(str);
		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;

	Finish:
	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	Noti.HourlyMarginAlert ;
GO
