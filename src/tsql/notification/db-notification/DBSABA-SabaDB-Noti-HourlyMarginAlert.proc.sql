USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'Noti.HourlyMarginAlert'
	,	@Version	SYSNAME		= N'1.2.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
DECLARE	@Procedure	SYSNAME		= N'Noti.HourlyMarginAlert_Wrapper'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	Noti.HourlyMarginAlert
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL

				/** Configs */
				,	@Config1		SQL_VARIANT		= NULL
				,	@Config2		SQL_VARIANT		= NULL
				,	@Config3		SQL_VARIANT		= NULL
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

	Version:	1.2.0
	Revision:
		- [1.2.0]	20220623@Billy		Using SQL Server 2019 syntax
		- [1.1.0]	20220309@Billy		Can config some alert variables now
		- [1.0.0]	20220308@Billy		Release Noti.HourlyMarginAlert
		- [0.0.1]	20220303@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		,	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)
		;

	DECLARE	@ReportHour		DATETIME
		,	@ReportDate		DATETIME
		,	@isTest			BIT

		/** Configs */
		,	@Histories		TINYINT
		,	@NegAlert		TINYINT
		,	@NullIgnore		TINYINT
		;

	BEGIN TRY SELECT @ReportHour = CONVERT(DATETIME, @Var1   ) END TRY BEGIN CATCH SELECT @ReportHour = NULL END CATCH;
	BEGIN TRY SELECT @isTest     = CONVERT(BIT     , @Var2   ) END TRY BEGIN CATCH SELECT @isTest     = NULL END CATCH;

	BEGIN TRY SELECT @Histories  = CONVERT(TINYINT , @Config1) END TRY BEGIN CATCH SELECT @Histories  = NULL END CATCH;
	BEGIN TRY SELECT @NegAlert   = CONVERT(TINYINT , @Config2) END TRY BEGIN CATCH SELECT @NegAlert   = NULL END CATCH;
	BEGIN TRY SELECT @NullIgnore = CONVERT(TINYINT , @Config3) END TRY BEGIN CATCH SELECT @NullIgnore = NULL END CATCH;

	SELECT	@ReportHour		= ISNULL(@ReportHour, DATEADD(HOUR, -1, GETUTCDATE()))
		,	@ReportHour		= DATEADD(HOUR, DATEDIFF(HOUR, 0, @ReportHour), 0)
		,	@ReportDate		= CAST(@ReportHour AS DATE)
		,	@isTest			= ISNULL(@isTest, 1)

		/** Configs */
		,	@Histories		= ISNULL(@Histories , 5)
		,	@NegAlert		= ISNULL(@NegAlert  , 3)
		,	@NullIgnore		= ISNULL(@NullIgnore, 1)
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
		WHERE	isDone	= 0;;

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

		SELECT	@Message	= CONCAT(@Icon, N'  NEGATIVE MARGIN ALERT @' + CONVERT(NVARCHAR(MAX), @ReportHour, 127), N'  ', @NL
							,	STRING_AGG(msg.msg, @NL) WITHIN GROUP (ORDER BY msg.wl)
							)
		FROM	(
			SELECT	[wl]	= r.winloss
				,	[msg]	= CONCAT_WS(@NL
							,	N'---  '
							,	N''
							,	N'「' + r.gameType + N'」  ' + ds.str + N'  '
							,	CONCAT(
									N'Last Hour:  `'
								,	REPLACE(CONVERT(NVARCHAR(MAX), CAST(lh.winLoss AS MONEY), 1), '.00', '')
								,	N'` / `'
								,	REPLACE(CONVERT(NVARCHAR(MAX), CAST(lh.turnOver AS MONEY), 1), '.00', '')
								,	N'`  '
								)
							,	CONCAT(
									N'Today:  `'
								,	REPLACE(CONVERT(NVARCHAR(MAX), CAST(r.winLoss AS MONEY), 1), '.00', '')
								,	N'` / `'
								,	REPLACE(CONVERT(NVARCHAR(MAX), CAST(r.turnOver AS MONEY), 1), '.00', '')
								,	N'`  '
								)
							)
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
				SELECT	STRING_AGG(_d.d, N'') WITHIN GROUP (ORDER BY _d.h)
				FROM	(
					SELECT	TOP(@Histories)
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
			) AS ds(str)
			CROSS APPLY	(
				SELECT	COUNT(1)
				FROM	(
					SELECT	TOP(@NegAlert)
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
					SELECT	TOP(@NullIgnore)
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
			WHERE	(r.winloss < 0 AND nu.n < @NullIgnore)
				OR	nm.n = @NegAlert
		) AS msg
		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;

	Finish:
	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
ALTER PROCEDURE	Noti.HourlyMarginAlert_Wrapper
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL

				/** Configs */
				,	@Config1		SQL_VARIANT		= NULL
				,	@Config2		SQL_VARIANT		= NULL
				,	@Config3		SQL_VARIANT		= NULL

				,	@Var3			SQL_VARIANT		= NULL
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

	Version:	1.0.0
	Revision:
		- [1.0.0]	20220623@Billy		Release Noti.HourlyMarginAlert_Wrapper
		- [0.0.1]	20220623@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	Noti.HourlyMarginAlert @Var1, @Var2, @Config1, @Config2, @Config3;
	END TRY BEGIN CATCH;
		DECLARE	@Title			NVARCHAR(128)	= CONVERT(NVARCHAR(128), @Var3)
			,	@ErrNumber		INT				= ERROR_NUMBER()
			,	@ErrSeverity	INT				= ERROR_SEVERITY()
			,	@ErrState		INT				= ERROR_STATE()
			,	@ErrProcedure	NVARCHAR(128)	= ERROR_PROCEDURE()
			,	@ErrLine		INT				= ERROR_LINE()
			,	@ErrMessage		NVARCHAR(MAX)	= ERROR_MESSAGE()
			,	@Server			NVARCHAR(128)	= PUBLISHINGSERVERNAME()
			,	@Database		NVARCHAR(128)	= DB_NAME()
			,	@isTest			BIT				= CONVERT(BIT, @Var2)
			;
		EXECUTE	SysHealth.SendError
					@Title			= @Title
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
EXECUTE	Noti.HourlyMarginAlert_Wrapper @Var3 = N'Adhoc Test';
GO
