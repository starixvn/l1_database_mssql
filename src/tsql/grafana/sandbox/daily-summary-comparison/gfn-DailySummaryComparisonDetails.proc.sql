USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'gfn.DailySummaryComparisonDetails'
	,	@Version	SYSNAME		= N'2.0.2'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	gfn.DailySummaryComparisonDetails
					@gameTypeId		INT
				,	@reportDate		DATETIME		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210923@Billy
	Location:		DBSABA.SabaDB
	Description:	Compare Daily Summary details result between OW and l then show result on Grafana

	Parameters:
		@Var1				[optional]		- The type id of game that will be queried.
				<DEFAULT>	NULL			- No data

		@Var2				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

	Version:	2.0.2
	Revision:
		- [2.0.2]	20240122@Billy		Support super users
		- [2.0.1]	20230710@Billy		Correct winLost value if ticket is not paid
		- [2.0.0]	20230529@Billy		Rename parameters
		- [1.0.1]	20220908@Billy		Fix missed passing date into data query
		- [1.0.0]	20210923@Billy		Release gfn.DailySummaryComparisonDetails
		- [0.0.1]	20210923@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@errorMessage	NVARCHAR(MAX)
		,	@gameName		NVARCHAR(128)
		,	@fromTime		DATETIME
		,	@toTime			DATETIME
		;

	SELECT	@reportDate		= CAST(ISNULL(@reportDate, DATEADD(DAY, -1, GETUTCDATE())) AS DATE);

	IF	NOT (DATEDIFF(DAY, @reportDate, GETUTCDATE()) BETWEEN 1 AND 7)
	AND	NOT EXISTS ( SELECT 1 FROM dbo.superusers WHERE systemId = SUSER_SID() )
	BEGIN;
		SELECT	@errorMessage	= N'@reportDate is out of range';
		EXECUTE	logger.Error N'Assert', @errorMessage;
		THROW 50000, @errorMessage, 1;
		RETURN;
	END;

	SELECT	TOP(1)
			@gameName = m.gameName
	FROM	dbr.tf_GameTypeMapping(NULL, NULL, NULL, @GameTypeId) AS m;

	IF	@gameName IS NULL
	BEGIN;
		SELECT	@errorMessage	= N'Invalid @gameTypeId';
		EXECUTE	logger.Error N'Assert', @errorMessage;
		THROW 50000, @errorMessage, 2;
		RETURN;
	END;


	DECLARE	@OW_TicketDetail	dbr.OW_TicketDetail;
	DECLARE	@L_TicketDetail		dbr.L_TicketDetail;


	SELECT	@fromTime	= DATEADD(HOUR, -1, @reportDate)
		,	@toTime		= DATEADD(HOUR, 25, @reportDate)
		;

	INSERT INTO	@OW_TicketDetail
	EXECUTE	dbr.OW_TicketDetail @fromTime, @toTime, @gameTypeId;

	INSERT INTO	@L_TicketDetail
	EXECUTE	dbr.L_TicketDetail @fromTime, @toTime, @gameTypeId;


	SELECT	@fromTime	= @reportDate
		,	@toTime		= DATEADD(HOUR, 24, @reportDate)
		;

	SELECT	[TO]			= IIF(diff.turnOver = 0, N'✅', N'❌')
		,	[WL]			= IIF((ow.statusId = 101 OR ow.statusId = 102) AND l.paid = 0, N'⚠️', IIF(diff.winLost = 0, N'✅', N'❌'))
		,	[🗓]			= IIF(diff.transDate = 0, N'✅', N'❌')
		,	[#]				= @gameTypeId
		,	[game]			= @gameName
		,	[round]			= ISNULL(ow.roundId, l.roundId)
		,	[player]		= ISNULL(ow.playerId, l.playerId)
		,	[¤]				= ISNULL(ow.currency, l.currency)

		,	[turnOver «]	= ow.turnOver
		,	[winLost «]		= ow.winLost
		,	[transDate «]	= FORMAT(ow.transDate, 'yyyy-MM-ddTHH:mm:ssZ')
		,	[status «]		= CONCAT('[', ow.statusId, '] ', ow.status)
		,	[count «]		= ow.recordCount
		,	[± TO «]		= IIF(diff.turnOver > 0, ABS(diff.turnOver), 0)
		,	[± WL «]		= IIF(diff.winLost > 0, ABS(diff.winLost), 0)
		,	[OW | SB]		= ''
		,	[» WL ±]		= IIF(diff.winLost < 0, ABS(diff.winLost), 0)
		,	[» TO ±]		= IIF(diff.turnOver < 0, ABS(diff.turnOver), 0)
		,	[» turnOver]	= l.turnOver
		,	[» winLost]		= l.winLost
		,	[» transDate]	=  FORMAT(l.transDate, 'yyyy-MM-ddTHH:mm:ssZ')
		,	[» endDate]		=  FORMAT(l.endDate, 'yyyy-MM-ddTHH:mm:ssZ')
		,	[» paid]		=  l.paid
	FROM			@OW_TicketDetail AS ow
	FULL OUTER JOIN	@L_TicketDetail AS l
				ON	ow.gameTypeId = l.gameTypeId
				AND	ow.roundId = l.roundId
				AND	ow.playerId = l.playerId
				AND	ow.currency = l.currency
				AND	ow.freeBet = l.freeBet
	CROSS APPLY	(VALUES (
		COALESCE(ow.currency, l.currency, N'¤')
	,	ISNULL(ow.turnOver, 0) - ISNULL(l.turnOver, 0)
	,	ISNULL(ow.winLost, 0) - ISNULL(l.winlost * l.paid, 0)
	,	DATEDIFF(DAY, CAST(ow.transDate AS DATE), CAST(l.endDate AS DATE))
	)) AS diff(currency, turnOver, winLost, transDate)
	WHERE	(	(	diff.currency <> N'UUS'
				AND	IIF(diff.turnOver = 0 AND diff.winLost = 0 AND diff.transDate = 0 AND l.paid = 1, 1, 0) = 0
				)
			OR	ow.recordCount > 1
			)
		-- AND	(	ow.transDate BETWEEN @fromTime AND @toTime
		-- 	OR	l.transDate BETWEEN @fromTime AND @toTime
		-- 	)
	ORDER BY	IIF(diff.currency = 'UUS', 1, 0)
			,	IIF((ow.statusId = 101 OR ow.statusId = 102) AND l.paid = 0, 1, 0)
			,	ow.recordCount
			,	ow.gameTypeId, l.gameTypeId
			,	ow.roundId, l.roundId
			,	ow.playerId, l.playerId
			,	ow.currency, l.currency
			,	ow.statusId
			;
END;
GO

EXECUTE	gfn.DailySummaryComparisonDetails 1612;
EXECUTE	gfn.DailySummaryComparisonDetails 3824;
