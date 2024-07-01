USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'Noti.JackpotContributionReport'
	,	@Version	SYSNAME		= N'2.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
DECLARE	@Object		SYSNAME		= N'Noti.JackpotContributionReport_Wrapper'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	Noti.JackpotContributionReport
					@reportDate		DATE
				,	@isTest			BIT			= 1
WITH ENCRYPTION
AS
/*
	Creator:		20210324@Billy
	Location:		DBSABA.SabaDB
	Description:	Jackpot Contribution Report
					Compare Jackpot related result between OW and SB then send result via Notification Channel

	Parameters:
		@reportDate			[REQUIRED]		- The date of data that will be compared. The time is in UTC timezone.

		@isTest:			[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing

	Version:	2.0.2
	Revision:
		- [2.0.2]	20240424@Billy		Check for multiple games
		- [2.0.1]	20240115@Billy		Temporary hard code "ONEworksVGCash" operator
		- [2.0.0]	20230515@Billy		Sum by operator & convert to base currency
		- [1.3.2]	20230413@Billy		Reformat due to Skynex changes
		- [1.3.1]	20230328@Billy		Add current jackpot value
		- [1.3.0]	20220624@Billy		Using SQL Server 2019 syntax
		- [1.2.2]	20220621@Billy		Reformat message
		- [1.2.1]	20211015@Billy		Configure jackpot contribution rate value
		- [1.2.0]	20210806@Billy		Migrate SC2 to vG2
		- [1.1.0]	20210617@Billy		Update query to match with new BI schema
		- [1.0.0]	20210324@Billy		Release Noti.JackpotContributionReport
		- [0.0.1]	20210324@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	SELECT	@ReportDate		= ISNULL(@reportDate, DATEADD(DAY, -1, GETUTCDATE()))
		,	@isTest			= ISNULL(@isTest, 1)
		;

	DECLARE	@L				TINYINT			= 2
		,	@vendorId		SMALLINT		= 66
		,	@Env			TINYINT			= 1
		,	@Bettype		INT				= 3898
		,	@Status			NVARCHAR(128)	= N'OK'
		,	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)
		;

	IF	NOT (DATEDIFF(DAY, @ReportDate, GETUTCDATE()) BETWEEN 1 AND 7)
		RETURN;

	DECLARE	@Query		NVARCHAR(MAX)
		,	@Param		NVARCHAR(MAX)
		;

	DECLARE	@GameId			INT
		,	@GameType		NVARCHAR(128)
		,	@GameTypeId		INT
		,	@Message		NVARCHAR(MAX)
		;

	DECLARE	@Currencies	dbr.Currencies;
	DECLARE	@Exchanges	dbr.ExchangeRates;

	DECLARE	@OW_Jackpot			dbr.OW_DailySummary;
	DECLARE	@L_Jackpot			dbr.L_DailySummary;

	DECLARE	@OW_JackpotSummary	dbr.OW_DailySummary;
	DECLARE	@L_JackpotSummary	dbr.L_DailySummary;

	DECLARE	@Mismatches			dbr.L_DailySummary;

	DECLARE	@Tmp_JPContribution AS TABLE (
				L				TINYINT
			,	gameTypeId		INT
			,	gameId			INT
			,	gameType		NVARCHAR(128)
			,	currency		VARCHAR(10)
			,	JPCont			DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (L, gameTypeId, gameId, currency)
			);

	DECLARE	@CurrentJackpots AS TABLE (
				gameId			INT
			,	gameName		NVARCHAR(128)
			,	pool			DECIMAL(19,4)
			,	amount			DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (gameId, pool)
			)


	INSERT INTO	@Currencies
	EXECUTE	dbr.L_Currencies @L, @Env;

	INSERT INTO @Exchanges
	EXECUTE	dbr.L_LastExchangeRate @L, @Env;


	SELECT	@Query = N'';
	SELECT	@Query = CONCAT(@Query, N'\
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT	[site]			= ISNULL(s.site, ''-'')
	,	[time]			= t.time
	,	[gameTypeId]	= b.gameId
	,	[gameName]		= ISNULL(g.typenamee, N''-'')
	,	[currency]		= b.CurrencyName
	,	[betCount]		= COUNT(1)
	,	[turnOver]		= SUM(-b.awinlost)
	,	[payOut]		= 0
FROM		dbo.bettransRnG AS b WITH (NOLOCK)
CROSS APPLY	(VALUES (DATEADD(DAY, DATEDIFF(DAY, 0, b.Transdate3rd), 0))) AS t(time)
INNER JOIN	dbo.bettype AS g WITH (NOLOCK)
		ON	b.gameId = g.typeid
LEFT JOIN	dbo.Dep_CustSuper AS s WITH (NOLOCK)
		ON	b.srecommend = s.custid
WHERE	b.vendorId = @vendorId
	AND	b.gameID = @Bettype
	AND	b.Transdate3rd >= @ReportDate
	AND	b.Transdate3rd < DATEADD(DAY, 1, @ReportDate)
	AND	b.statusID NOT IN (101, 102, 0) -- Reject, Void, running
	AND	b.custid <> 0 -- Merged Tickets
GROUP BY s.site, t.time, b.gameId, g.typenamee, b.CurrencyName
OPTION (RECOMPILE);
');

	SELECT	@Param = N'';
	SELECT	@Param += N'@vendorId INT, @Bettype INT, @ReportDate DATETIME';

	INSERT INTO	@OW_Jackpot
	EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param, @vendorId, @Bettype, @ReportDate;

	RAISERROR('', 0, 0) WITH NOWAIT;


	SELECT	@Query = N'';
	SELECT	@Query = CONCAT(@Query, N'\
SELECT	ds.operatorId AS operatorId
	,	ds.time AS time
	,	', @Bettype, N' AS gameTypeId
	,	0 AS gameId
	,	"Jackpot Contribution" AS gameName
	,	IFNULL(ds.currency, "null") AS currency
	,	SUM(ds.tickets) AS betCount
	,	SUM(ds.stake * IFNULL(cfg.jpCont, 0)) AS turnOver
	,	0 AS payOut
FROM		summary.daily_summaries AS ds
INNER JOIN	summary.game_summary_config AS cfg
		ON	ds.gameId = cfg.gameId
WHERE	cfg.groupName = "Slots"
	AND	ds.operatorId = "ONEworksVGCash"
	AND	ds.time >= "', FORMAT(@ReportDate, 'yyyy-MM-dd'), N'"
	AND	ds.time < "' , FORMAT(DATEADD(DAY, 1, @ReportDate), 'yyyy-MM-dd'), N'"
GROUP BY ds.operatorId, ds.time, ds.currency
');

	INSERT INTO @L_Jackpot
	EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, 1;


	SELECT	@Query = N'';
	SELECT	@Query = CONCAT(@Query, N'\
SELECT	jp.gameId AS gameId
	,	cfg.nameEN AS gameName
	,	jp.pool AS poll
	,	SUM(jp.amount * 1000) AS amount
FROM		minigame.jackpots AS jp
INNER JOIN	summary.game_summary_config AS cfg
		ON	jp.gameId = cfg.gameId
WHERE	jp.hitAt IS NULL
GROUP BY jp.gameId, jp.pool
');

	INSERT INTO	@CurrentJackpots (gameId, gameName, pool, amount)
	EXECUTE	base.Query @Query, @L, 0, 1;

	IF	@isTest = 1
	BEGIN;
		SELECT * FROM @OW_Jackpot;
		SELECT * FROM @L_Jackpot;
		SELECT * FROM @CurrentJackpots;
	END;

	INSERT INTO	@OW_JackpotSummary (site, time, gameTypeId, gameName, currency, betcount, turnOver, payOut)
	SELECT	[site]			= m.operatorId
		,	[time]			= ow.time
		,	[gameTypeId]	= ow.gameTypeId
		,	[gameName]		= ow.gameName
		,	[currency]		= c.code
		,	[betCount]		= SUM(ow.betCount)
		,	[turnOver]		= SUM(ow.turnOver * r.rate)
		,	[payOut]		= SUM(ow.payOut * r.rate)
	FROM	@OW_Jackpot AS ow
	CROSS APPLY	(VALUES (NULLIF(ow.site, N'-'))) AS n(site)
	OUTER APPLY	dbr.tf_OW_OperatorMapping(@vendorId, n.site) AS m
	LEFT JOIN	@Currencies AS c
			ON	m.operatorId = c.operatorId
			AND	ow.currency = c.name
	LEFT JOIN	@Exchanges AS e
			ON	c.code = e.code
	CROSS APPLY	(VALUES (ISNULL(c.multiplier, 1) * ISNULL(e.rate, 1))) AS r(rate)
	WHERE	ow.currency <> 'UUS'
	GROUP BY m.operatorId, ow.time, ow.gameTypeId, ow.gameName, c.code;


	INSERT INTO	@L_JackpotSummary (operatorId, time, gameTypeId, gameId, gameName, currency, betCount, turnOver, payOut)
	SELECT	[operatorId]	= l.operatorId
		,	[time]			= l.time
		,	[gameTypeId]	= l.gameTypeId
		,	[gameId]		= l.gameId
		,	[gameName]		= l.gameName
		,	[currency]		= c.code
		,	[betCount]		= SUM(l.betCount)
		,	[turnOver]		= SUM(l.turnOver * r.rate)
		,	[payOut]		= SUM(l.payOut * r.rate)
	FROM	@L_Jackpot AS l
	LEFT JOIN	@Currencies AS c
			ON	l.operatorId = c.operatorId
			AND	l.currency = c.name
	LEFT JOIN	@Exchanges AS e
			ON	c.code = e.code
	CROSS APPLY	(VALUES (ISNULL(c.multiplier, 1) * ISNULL(e.rate, 1))) AS r(rate)
	WHERE	l.currency <> 'UUS'
	GROUP BY l.operatorId, l.time, l.gameTypeId, l.gameId, l.gameName, c.code

	IF	@isTest = 1
	BEGIN;
		SELECT * FROM @OW_JackpotSummary;
		SELECT * FROM @L_JackpotSummary;
	END;

	INSERT INTO	@Mismatches (operatorId, time, gameTypeId, gameId, gameName, currency, betCount, turnOver, payOut)
	SELECT	[operatorId]	= ISNULL(ow.site, l.operatorId)
		,	[time]			= ISNULL(ow.time, l.time)
		,	[gameTypeId]	= ISNULL(ow.gameTypeId, l.gameTypeId)
		,	[gameId]		= ISNULL(l.gameId, 0)
		,	[gameName]		= ISNULL(ow.gameName, l.gameName)
		,	[currency]		= ISNULL(ow.currency, l.currency)
		,	[betCount]		= 0
		,	[turnOver]		= diff.turnOver
		,	[payOut]		= 0
	FROM			@OW_JackpotSummary AS ow
	FULL OUTER JOIN	@L_JackpotSummary AS l
				ON	ow.site = l.operatorId
				AND	ow.time = l.time
				AND	ow.gameTypeId = l.gameTypeId
				AND	ow.currency = l.currency
	CROSS APPLY	(VALUES	(ISNULL(ow.turnOver, 0) - ISNULL(l.turnOver, 0))) AS diff(turnOver)
	WHERE	diff.turnOver <> 0


	IF	EXISTS (SELECT 1 FROM @Mismatches)
	BEGIN;
		SELECT	@Status		= N'MISMATCH';

		SELECT	@Message	= CONCAT_WS(@NL
				,	CONCAT(N'[', @Status, N'] [Jackpot Contribution `', FORMAT(@reportDate, 'yyyy-MM-dd'), N'`]')
				,	STRING_AGG(CONCAT(N'`', m.operatorId, N'`  -  `💸`:  `', FORMAT(m.turnOver, '#,##0.##'), N'`'), @NL)
				)
		FROM	@Mismatches AS m;

		IF	@isTest = 1
		BEGIN;
			SELECT * FROM @Mismatches;
		END;

		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;


	SELECT	@Message	= CONCAT_WS(@NL,
				CONCAT(N'[', @Status, N'] [Jackpot Contribution `', FORMAT(@reportDate, 'yyyy-MM-dd') , N'`]')
			,	MIN(jp.str)
			,	STRING_AGG(CONCAT(@NL, g.str), @NL) WITHIN GROUP (ORDER BY g.operatorId)
			)
	FROM	(
		SELECT	[operatorId]	= s.operatorId
			,	[jpCont]		= SUM(s.turnOver)
			,	[str]			= CONCAT(N'`', s.operatorId, N'`  - JP:  `', FORMAT(SUM(s.turnOver), '#,##0.##'), N'`  ')
		FROM	@L_JackpotSummary AS s
		GROUP BY s.operatorId
	) AS g
	CROSS APPLY	(
		SELECT	[str] = CONCAT_WS(@NL
				,	N'  `🍯`:'
				,	STRING_AGG(CONCAT(N'    - `', RIGHT(cjp.baseStr, cjp.baseMaxLen) ,N'` : `', cjp.amountStr, N'`'), @NL) WITHIN GROUP (ORDER BY cjp.baseStr)
				)
		FROM	(
			SELECT	[baseStr]		= FORMAT(_cjp.pool, N'     #0.#')
				,	[baseMaxLen]	= MAX(LEN(FORMAT(_cjp.pool, N'#0.#'))) OVER()
				,	[amountStr]		= FORMAT(SUM(_cjp.amount), N'#,##0.##')
			FROM	@CurrentJackpots AS _cjp
			GROUP BY _cjp.pool
		) AS cjp
	) AS jp
	WHERE	g.jpCont > 0;

	EXECUTE	Noti.SendNotification @Message, @isTest;
END;
GO
ALTER PROCEDURE	Noti.JackpotContributionReport_Wrapper
					@reportDate		DATETIME		= NULL
				,	@isTest			BIT				= 1

				,	@errorName		NVARCHAR(128)	= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220624@Billy
	Location:		DBSABA.SabaDB
	Description:	Jackpot Contribution Report Wrapper - No error execution
					Compare Jackpot related result between OW and SB then send result via Notification Channel

	Parameters:
		@reportDate			[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday
		@isTest:			[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var3:				[optional]		- The title for error message
				<DEFAULT>	NULL			- Default title

	Version:	2.0.0
	Revision:
		- [2.0.0]	20230515@Billy		Rename parameters
		- [1.0.0]	20220624@Billy		Release Noti.JackpotContributionReport_Wrapper
		- [0.0.1]	20220624@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	Noti.JackpotContributionReport @reportDate, @isTest;
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
EXECUTE	Noti.JackpotContributionReport_Wrapper NULL, 1, N'Adhoc Test';
GO
