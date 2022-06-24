USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'SysHealth.SummaryCrossCheck'
	,	@Version	SYSNAME		= N'1.1.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
DECLARE	@Procedure	SYSNAME		= N'SysHealth.SummaryCrossCheck_Wrapper'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	SysHealth.SummaryCrossCheck
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211201@Billy
	Location:		DBSABA.SabaDB
	Description:	Summary Cross Check
					Summary data between daily and hourly then send result via SysHealth Channel

	Parameters:
		@Var1:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var2:				[optional]		- The system environment id
				<DEFAULT>	NULL			- Invalid

	Version:	1.1.0
	Revision:
		- [1.1.0]	20220624@Billy		Using SQL Server 2019 syntax
		- [1.0.2]	20220622@Billy		Filter out today to avoid NULL data
		- [1.0.1]	20220114@Billy		Truncate overflow message
		- [1.0.0]	20211201@Billy		Release SysHealth.SummaryCrossCheck
		- [0.0.3]	20211203@Billy		Include partnerId & environment
		- [0.0.2]	20211202@Billy		Include refund data
		- [0.0.1]	20211201@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Status			NVARCHAR(128)	= N'OK'
		,	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)
		;

	DECLARE	@isTest			BIT
		,	@Env			TINYINT
		;

	BEGIN TRY; SELECT @isTest = CONVERT(BIT    , @Var1); END TRY BEGIN CATCH; SELECT @isTest = 1    END CATCH;
	BEGIN TRY; SELECT @Env    = CONVERT(TINYINT, @Var2); END TRY BEGIN CATCH; SELECT @Env    = NULL END CATCH;

	IF	@Env IS NULL
		RETURN;

	DECLARE	@LQuery			NVARCHAR(MAX)
		,	@L				TINYINT
		,	@Message		NVARCHAR(MAX)
		;

	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	isDone			BIT
			);
	INSERT INTO	@Ls (L)
	VALUES	(1), (2), (3);

	DECLARE	@Daily AS TABLE (
				L				TINYINT
			,	time			DATE
			,	gameId			SMALLINT
			,	currency		NVARCHAR(128)
			,	isCash			BIT
			,	partnerId		NVARCHAR(128)
			,	stake			MONEY
			,	refund			MONEY
			,	payout			MONEY
			,	tickets			INT
			,	PRIMARY KEY CLUSTERED (L, time, gameId, currency, isCash, partnerId)
			);

	DECLARE	@Hourly AS TABLE (
				L				TINYINT
			,	time			DATE
			,	gameId			SMALLINT
			,	currency		NVARCHAR(128)
			,	isCash			BIT
			,	partnerId		NVARCHAR(128)
			,	stake			MONEY
			,	refund			MONEY
			,	payout			MONEY
			,	tickets			INT
			,	PRIMARY KEY CLUSTERED (L, time, gameId, currency, isCash, partnerId)
			);

	DECLARE	@Diff AS TABLE (
				L				TINYINT
			,	time			DATE
			,	gameId			SMALLINT
			,	currency		NVARCHAR(128)
			,	isCash			BIT
			,	partnerId		NVARCHAR(128)
			,	stake			MONEY
			,	refund			MONEY
			,	payout			MONEY
			,	tickets			INT
			,	PRIMARY KEY CLUSTERED (L, time, gameId, currency, isCash, partnerId)
			);


	UPDATE	@Ls SET isDone = 0;
	WHILE	EXISTS (SELECT 1 FROM @Ls WHERE isDone = 0)
	BEGIN;
		UPDATE	TOP(1)
				@Ls
		SET		@L = L
			,	isDone = 1
		WHERE	isDone = 0;

		IF	@@ROWCOUNT = 0
			BREAK;

		-- Daily Summary --
		SELECT	@LQuery = N'';
		SELECT	@LQuery = CONCAT(@LQuery, N'\
SELECT	', @L, N' AS L, time, gameId, currency, isCash, partnerId, stake, refund, payout, tickets
FROM	summary.daily_summaries
WHERE	time < DATE(UTC_TIMESTAMP());
');
		INSERT INTO	@Daily (L, time, gameId, currency, isCash, partnerId, stake, refund, payout, tickets)
		EXECUTE	base.ExecuteSabaQuery @LQuery, @L, 0, @Env;

		-- Hourly Summary --
		SELECT	@LQuery = N'';
		SELECT	@LQuery = CONCAT(@LQuery, N'\
SELECT	', @L, N' AS L
	,	DATE(DATE_FORMAT(time, "%Y-%m-%d")) AS time
	,	gameId, currency, isCash, partnerId
	,	SUM(stake) AS stake
	,	SUM(refund) AS refund
	,	SUM(payout) AS payout
	,	SUM(tickets) AS tickets
FROM	summary.hourly_summaries
WHERE	time >= DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL -7 DAY))
	AND	time <  DATE(UTC_TIMESTAMP())
GROUP BY DATE_FORMAT(time, "%Y-%m-%d"), gameId, currency, isCash, partnerId;
');
		INSERT INTO	@Hourly (L, time, gameId, currency, isCash, partnerId, stake, refund, payout, tickets)
		EXECUTE	base.ExecuteSabaQuery @LQuery, @L, 0, @Env;
	END;

	INSERT INTO	@Diff (L, time, gameId, currency, isCash, partnerId, stake, refund, payout, tickets)
	SELECT	[L]			= ISNULL(d.L, h.L)
		,	[time]		= ISNULL(d.time, h.time)
		,	[gameId]	= ISNULL(d.gameId, h.gameId)
		,	[currency]	= ISNULL(d.currency, h.currency)
		,	[isCash]	= ISNULL(d.isCash, h.isCash)
		,	[partnerId]	= ISNULL(d.partnerId, h.partnerId)
		,	[stake]		= ISNULL(d.stake, 0) - ISNULL(h.stake, 0)
		,	[refund]	= ISNULL(d.refund, 0) - ISNULL(h.refund, 0)
		,	[payout]	= ISNULL(d.payout, 0) - ISNULL(h.payout, 0)
		,	[tickets]	= ISNULL(d.tickets, 0) - ISNULL(h.tickets, 0)
	FROM			@Daily AS d
	FULL OUTER JOIN	@Hourly AS h
				ON	d.L			= h.L
				AND	d.time		= h.time
				AND	d.gameId	= h.gameId
				AND	d.currency	= h.currency
				AND	d.isCash	= h.isCash
				AND	d.partnerId	= h.partnerId
	WHERE	ISNULL(d.time, h.time) < CAST(GETUTCDATE() AS DATE)
		AND	(	ISNULL(d.stake, -1) <> ISNULL(h.stake, -2)
			OR	ISNULL(d.refund, -1) <> ISNULL(h.refund, -2)
			OR	ISNULL(d.payout, -1) <> ISNULL(h.payout, -2)
			OR	ISNULL(d.tickets, -1) <> ISNULL(h.tickets, -2)
			)

	IF	EXISTS (SELECT 1 FROM @Diff)
	BEGIN;
		SELECT	@Status = N'NG';

		SELECT	@Message	= CONCAT(
								N'\\\[', @Status, N'\] \\\[Summary Cross Check\] ('
							,	CASE @Env WHEN 1 THEN N'PRO' WHEN 2 THEN N'UAT' WHEN 3 THEN N'SIT' ELSE N'???' END
							,	N') @`', CONVERT(NVARCHAR(MAX), GETUTCDATE(), 23), N'`'
							,	STRING_AGG(r.msg, @NL) WITHIN GROUP (ORDER BY r.L, r.time, r.gameId, r.currency, r.isCash, r.partnerId)
							)
		FROM		(
			SELECT	rd.*
				,	[msg]	= CONCAT_WS(@NL
							,	N''
							,	N'---'
							,	N'`' + CONCAT_WS(N'|'
								,	CONCAT(N'L', rd.L)
								,	CONVERT(NVARCHAR(MAX), rd.time, 23)
								,	rd.gameId
								,	rd.currency
								,	CASE rd.isCash WHEN 0 THEN N'Cre' WHEN 1 THEN N'Dep' ELSE N'???' END
								,	rd.partnerId
								) + N'`'
							,	d.str
							)
			FROM		(
				SELECT	DISTINCT
						L, time, gameId, currency, isCash, partnerId
				FROM	@Diff
			) AS rd
			CROSS APPLY	(
				SELECT	[str] = CONCAT_WS(@NL
						,	CASE WHEN df.stake   <> 0 THEN CONCAT(N'  \- stake: ', df.stake) ELSE NULL END
						,	CASE WHEN df.refund  <> 0 THEN CONCAT(N'  \- refund: ', df.refund) ELSE NULL END
						,	CASE WHEN df.payout  <> 0 THEN CONCAT(N'  \- payout: ', df.payout) ELSE NULL END
						,	CASE WHEN df.tickets <> 0 THEN CONCAT(N'  \- tickets: ', df.tickets) ELSE NULL END
						)
				FROM	@Diff AS df
				WHERE	df.L			= rd.L
					AND	df.time			= rd.time
					AND	df.gameId		= rd.gameId
					AND	df.currency		= rd.currency
					AND	df.isCash		= rd.isCash
					AND	df.partnerId	= rd.partnerId
			) AS d
		) AS r

		SELECT	@Message = CASE WHEN DATALENGTH(@Message) > 8000 THEN LEFT(@Message, 3997) + N'...' ELSE @Message END
		EXECUTE	SysHealth.SendNotification @Message, @isTest;
	END;
	ELSE
	BEGIN;
		SELECT	@Message	= CONCAT(
								N'\\\[' + @Status + N'\] \\\[Summary Cross Check\] ('
							,	CASE @Env WHEN 1 THEN N'PRO' WHEN 2 THEN N'UAT' WHEN 3 THEN N'SIT' ELSE N'???' END
							,	N') @`', CONVERT(NVARCHAR(MAX), GETUTCDATE(), 23), N'`'
							);
		EXECUTE	SysHealth.SendNotification @Message, @isTest;
	END;
END;
GO
ALTER PROCEDURE	SysHealth.SummaryCrossCheck_Wrapper
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220623@Billy
	Location:		DBSABA.SabaDB
	Description:	Summary Cross Check Wrapper - No error execution
					Summary data between daily and hourly then send result via SysHealth Channel

	Parameters:
		@Var1:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var2:				[optional]		- The system environment id
				<DEFAULT>	NULL			- Invalid
		@Var3:				[optional]		- The title for error message
				<DEFAULT>	NULL			- Default title

	Version:	1.0.0
	Revision:
		- [1.0.0]	20220623@Billy		Release SysHealth.SummaryCrossCheck_Wrapper
		- [0.0.1]	20220623@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	SysHealth.SummaryCrossCheck @Var1, @Var2;
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
			,	@isTest			BIT				= CONVERT(BIT, @Var1)
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
EXECUTE	SysHealth.SummaryCrossCheck_Wrapper 1, 1, N'Adhoc Test';
EXECUTE	SysHealth.SummaryCrossCheck_Wrapper 1, 2, N'Adhoc Test';
EXECUTE	SysHealth.SummaryCrossCheck_Wrapper 1, 3, N'Adhoc Test';
GO
