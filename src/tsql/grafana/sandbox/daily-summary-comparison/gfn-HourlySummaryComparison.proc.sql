USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'gfn.HourlySummaryComparison'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	gfn.HourlySummaryComparison
					@reportTime		DATETIME		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20240123@Billy
	Location:		DBSABA.SabaDB
	Description:	Compare Hourly Summary related result between OW and SB then show result on Grafana

	Parameters:
		@Var1				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterhour

	Version:	1.0.0
	Revision:
		- [1.0.0]	20240123@Billy		Release gfn.HourlySummaryComparison
		- [0.0.1]	20240123@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@errorMessage	NVARCHAR(MAX)
		,	@vendorId		SMALLINT
		,	@L				TINYINT
		;

	SELECT	@reportTime		= ISNULL(@reportTime, DATEADD(HOUR, -1, GETUTCDATE()));
	SELECT	@reportTime		= DATEADD(HOUR, DATEDIFF(HOUR, 0, @reportTime), 0);

	IF	NOT (DATEDIFF(HOUR, @reportTime, GETUTCDATE()) BETWEEN 1 AND 7 * 24)
	AND	NOT EXISTS ( SELECT 1 FROM dbo.superusers WHERE systemId = SUSER_SID() )
	BEGIN;
		SELECT	@errorMessage	= N'@reportTime is out of range';
		EXECUTE	logger.Error N'Assert', @errorMessage;
		THROW 50000, @errorMessage, 1;
		RETURN;
	END;

	DECLARE	@Vendors AS TABLE (
		vendorId	SMALLINT
	,	L			TINYINT
	,	isDone		BIT			DEFAULT (0)
	);

	INSERT INTO	@Vendors (vendorId, L)
	VALUES	(42, 1)
		,	(66, 2)
		;


	DECLARE	@OW_Summary	dbr.OW_HourlySummary;
	DECLARE	@L_Summary	dbr.L_HourlySummary;

	DECLARE	@OW_HourlySummary	dbr.OW_HourlySummary;
	DECLARE	@L_HourlySummary	dbr.L_HourlySummary;


	WHILE	0 = 0
	BEGIN;
		UPDATE	TOP(1)
				@Vendors
		SET		@vendorId	= vendorId
			,	@L			= L
			,	isDone		= 1
		WHERE	isDone		= 0;

		IF	@@ROWCOUNT = 0
			BREAK;

		DELETE	@OW_Summary;
		INSERT INTO	@OW_Summary
		EXECUTE	dbr.OW_HourlySummary @vendorId, @reportTime;

		DELETE	@L_Summary;
		INSERT INTO	@L_Summary
		EXECUTE	dbr.L_HourlySummary @L, @reportTime;

		INSERT INTO	@OW_HourlySummary (site, time, gameTypeId, gameName, currency, betcount, turnOver, payOut)
		SELECT	[site]			= m.operatorId
			,	[time]			= ow.time
			,	[gameTypeId]	= ow.gameTypeId
			,	[gameName]		= ow.gameName
			,	[currency]		= ow.currency
			,	[betCount]		= SUM(ow.betCount)
			,	[turnOver]		= SUM(ow.turnOver)
			,	[payOut]		= SUM(ow.payOut)
		FROM	@OW_Summary AS ow
		CROSS APPLY	(VALUES (NULLIF(ow.site, N'-'))) AS n(site)
		OUTER APPLY	dbr.tf_OW_OperatorMapping(@vendorId, n.site) AS m
		WHERE	ow.currency <> 'UUS'
		GROUP BY m.operatorId, ow.time, ow.gameTypeId, ow.gameName, ow.currency;

		INSERT INTO	@L_HourlySummary (operatorId, time, gameTypeId, gameId, gameName, currency, betCount, turnOver, payOut)
		SELECT	[operatorId]	= l.operatorId
			,	[time]			= l.time
			,	[gameTypeId]	= l.gameTypeId
			,	[gameId]		= l.gameId
			,	[gameName]		= l.gameName
			,	[currency]		= l.currency
			,	[betCount]		= SUM(l.betCount)
			,	[turnOver]		= SUM(l.turnOver)
			,	[payOut]		= SUM(l.payOut)
		FROM	@L_Summary AS l
		WHERE	l.currency <> 'UUS'
		GROUP BY l.operatorId, l.time, l.gameTypeId, l.gameId, l.gameName, l.currency;
	END;


	SELECT	[BC]			= IIF(diff.betCount = 0, N'✅', N'❌')
		,	[TO]			= IIF(diff.turnOver = 0, N'✅', N'❌')
		,	[PO]			= IIF(diff.payOut = 0, N'✅', N'❌')
		,	[site]			= diff.site
		,	[game]			= diff.gameName
		,	[id]			= diff.gameTypeId
		,	[¤]				= diff.currency

		,	[betCount «]	= ow.betCount
		,	[turnOver «]	= ow.turnOver
		,	[payOut «]		= ow.payOut
		,	[± BC «]		= IIF(diff.betCount > 0, ABS(diff.betCount), 0)
		,	[± TO «]		= IIF(diff.turnOver > 0, ABS(diff.turnOver), 0)
		,	[± PO «]		= IIF(diff.payOut > 0, ABS(diff.payOut), 0)
		,	[OW | SB]		= ''
		,	[» PO ±]		= IIF(diff.payOut < 0, ABS(diff.payOut), 0)
		,	[» TO ±]		= IIF(diff.turnOver < 0, ABS(diff.turnOver), 0)
		,	[» BC ±]		= IIF(diff.betCount < 0, ABS(diff.betCount), 0)
		,	[» betCount]	= l.betCount
		,	[» turnOver]	= l.turnOver
		,	[» payOut]		= l.payOut
	FROM			@OW_HourlySummary AS ow
	FULL OUTER JOIN	@L_HourlySummary AS l
				ON	ow.site = l.operatorId
				AND	ow.currency = l.currency
				AND	ow.gameTypeId = l.gameTypeId
				AND	ow.time = l.time
	CROSS APPLY	(VALUES (
		COALESCE(ow.site, l.operatorId, N'-')
	,	COALESCE(ow.currency, l.currency, N'¤')
	,	COALESCE(ow.gameTypeId, l.gameTypeId, 0)
	,	COALESCE(ow.gameName, l.gameName, '-')
	,	ISNULL(ow.betCount, 0) - ISNULL(l.betcount, 0)
	,	ISNULL(ow.turnOver, 0) - ISNULL(l.turnOver, 0)
	,	ISNULL(ow.payOut, 0) - ISNULL(l.payOut, 0)
	)) AS diff(site, currency, gameTypeId, gameName, betCount, turnOver, payOut)
	WHERE	diff.currency <> 'UUS'
		AND	ISNULL(ow.gameTypeId, l.gameTypeId) NOT IN (SELECT gameTypeId FROM dbr.tf_JackpotBettype())
	ORDER BY	IIF(diff.betCount = 0 AND diff.turnOver = 0 AND diff.payOut = 0, 1, 0)
			,	IIF(diff.currency = 'UUS', 1, 0)
			,	ow.site, l.operatorId
			,	ow.gameTypeId, l.gameTypeId
			,	ow.currency, l.currency
			;
END;
GO

EXECUTE	gfn.HourlySummaryComparison;
