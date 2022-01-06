USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'SysHealth.SummaryCrossCheck'
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
	Location:		DBDWCSS.SabaDB
	Description:	Summary Cross Check
					Summary data between daily and hourly then send result via SysHealth Channel

	Parameters:
		@Var1:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var2:				[optional]		- The system environment id
				<DEFAULT>	NULL			- Invalid

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211201@Billy		Release SysHealth.SummaryCrossCheck
		- [0.0.3]	20211203@Billy		Include partnerId & environment
		- [0.0.2]	20211202@Billy		Include refund data
		- [0.0.1]	20211201@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Status			NVARCHAR(128)	= N'OK'
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
		SELECT	@LQuery += N'\
SELECT	' + CAST(@L AS NVARCHAR(MAX)) + N' AS L, time, gameId, currency, isCash, partnerId, stake, refund, payout, tickets
FROM	summary.daily_summaries;
';
		INSERT INTO	@Daily (L, time, gameId, currency, isCash, partnerId, stake, refund, payout, tickets)
		EXECUTE	base.ExecuteSabaQuery @LQuery, @L, 0, @Env;

		-- Hourly Summary --
		SELECT	@LQuery = N'';
		SELECT	@LQuery += N'\
SELECT	' + CAST(@L AS NVARCHAR(MAX)) + N' AS L
	,	DATE(DATE_FORMAT(time, "%Y-%m-%d")) AS time
	,	gameId, currency, isCash, partnerId
	,	SUM(stake) AS stake
	,	SUM(refund) AS refund
	,	SUM(payout) AS payout
	,	SUM(tickets) AS tickets
FROM	summary.hourly_summaries
WHERE	time >= DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL -7 DAY))
GROUP BY DATE_FORMAT(time, "%Y-%m-%d"), gameId, currency, isCash, partnerId;
';
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

		SELECT	@Message	= N'\\\[' + @Status + N'\] \\\[Summary Cross Check\] ('
							+ CASE @Env WHEN 1 THEN N'PRO' WHEN 2 THEN N'UAT' WHEN 3 THEN N'SIT' ELSE N'???' END
							+ N') @`' + CONVERT(NVARCHAR(MAX), GETUTCDATE(), 23) + N'`' + r.str
		FROM		(
			SELECT	N'  

---
`L' + CONVERT(NVARCHAR(MAX), rd.L) + N'|'
   + CONVERT(NVARCHAR(MAX), rd.time, 23) + N'|'
   + CONVERT(NVARCHAR(MAX), rd.gameId) + N'|'
   + rd.currency + N'|'
   + CASE rd.isCash WHEN 0 THEN N'Cre' WHEN 1 THEN N'Dep' ELSE N'???' END + N'|'
   + rd.partnerId + N'`' + d.str
			FROM		(
				SELECT	DISTINCT
						L, time, gameId, currency, isCash, partnerId
				FROM	@Diff
			) AS rd
			CROSS APPLY	(
				SELECT	CASE WHEN df.stake <> 0 THEN N'  
    \- stake: ' + CONVERT(NVARCHAR(MAX), df.stake) ELSE N'' END +
						CASE WHEN df.refund <> 0 THEN N'  
    \- refund: ' + CONVERT(NVARCHAR(MAX), df.refund) ELSE N'' END +
						CASE WHEN df.payout <> 0 THEN N'  
    \- payout: ' + CONVERT(NVARCHAR(MAX), df.payout) ELSE N'' END +
						CASE WHEN df.tickets <> 0 THEN N'  
    \- tickets: ' + CONVERT(NVARCHAR(MAX), df.tickets) ELSE N'' END
				FROM	@Diff AS df
				WHERE	df.L			= rd.L
					AND	df.time			= rd.time
					AND	df.gameId		= rd.gameId
					AND	df.currency		= rd.currency
					AND	df.isCash		= rd.isCash
					AND	df.partnerId	= rd.partnerId
				FOR XML PATH ('')
				,	TYPE
			) AS xd(xml)
			CROSS APPLY	(
				SELECT	xd.xml.value('.', 'NVARCHAR(MAX)')
			) AS d(str)
			FOR XML PATH ('')
			,	TYPE
		) AS xr(xml)
		CROSS APPLY	(
			SELECT	xr.xml.value('.', 'NVARCHAR(MAX)')
		) AS r(str);

		EXECUTE	SysHealth.SendNotification @Message, @isTest;
	END;
	ELSE
	BEGIN;
		SELECT	@Message	= N'\\\[' + @Status + N'\] \\\[Summary Cross Check\] ('
							+ CASE @Env WHEN 1 THEN N'PRO' WHEN 2 THEN N'UAT' WHEN 3 THEN N'SIT' ELSE N'???' END
							+ N') @`' + CONVERT(NVARCHAR(MAX), GETUTCDATE(), 23) + N'`'
		EXECUTE	SysHealth.SendNotification @Message, @isTest;
	END;
END;
GO
EXECUTE	SysHealth.SummaryCrossCheck 1, 1;
EXECUTE	SysHealth.SummaryCrossCheck 1, 2;
EXECUTE	SysHealth.SummaryCrossCheck 1, 3;
GO
