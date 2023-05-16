USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.OW_DailySummary'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.OW_DailySummary
					@vendorId		SMALLINT
				,	@reportDate		DATE
WITH ENCRYPTION
AS
/*
	Creator:		20210529@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Daily Summary data from OW database

	Parameters:
		@vendorId			[REQUIRED]		- The id of vendor that will be selected

		@reportDate			[REQUIRED]		- The date of data that will be selected. The time is in UTC timezone.

	Version:	1.0.0
	Revision:
		- [2.0.0]	20230515@Billy		Summary by site
		- [1.0.0]	20210529@Billy		Release dbr.OW_DailySummary
		- [0.0.1]	20210529@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME();

	DECLARE	@Query		NVARCHAR(MAX)
		,	@Param		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		,	@Param = N''
		;

	SELECT	@Query += N'\
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT	[site]			= ISNULL(s.site, ''-'')
	,	[time]			= t.time
	,	[gameTypeId]	= b.gameId
	,	[gameName]		= ISNULL(g.typenamee, N''-'')
	,	[currency]		= b.CurrencyName
	,	[betCount]		= COUNT(1)
	,	[turnOver]		= SUM(b.stake)
	,	[payOut]		= SUM(b.winlost)
FROM		dbo.bettransRnG AS b WITH (NOLOCK)
CROSS APPLY	(VALUES (DATEADD(DAY, DATEDIFF(DAY, 0, b.Transdate3rd), 0))) AS t(time)
LEFT JOIN	dbo.bettype AS g WITH (NOLOCK)
		ON	b.gameId = g.typeid
LEFT JOIN	dbo.Dep_CustSuper AS s WITH (NOLOCK)
		ON	b.srecommend = s.custid
WHERE	b.vendorID = @vendorId
	AND	b.Transdate3rd >= @reportDate
	AND	b.Transdate3rd < DATEADD(DAY, 1, @reportDate)
	AND	b.statusID NOT IN (101, 102, 0) -- Reject, Void, running
	AND	b.custid <> 0 -- Merged Tickets
GROUP BY s.site, t.time, b.gameId, g.typenamee, b.CurrencyName
OPTION (RECOMPILE);
'
		,	@Param = N'@vendorId SMALLINT, @reportDate DATETIME'
		;

	EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param, @vendorId, @reportDate;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.OW_DailySummary') IS NOT NULL
		DROP TYPE dbr.OW_DailySummary;

	CREATE TYPE	dbr.OW_DailySummary AS TABLE (
		site			NVARCHAR(128)
	,	time			DATETIME
	,	gameTypeId		INT
	,	gameName		NVARCHAR(128)
	,	currency		VARCHAR(16)
	,	betCount		BIGINT
	,	turnOver		DECIMAL(19,4)
	,	payOut			DECIMAL(19,4)
	,	PRIMARY KEY NONCLUSTERED (site, currency, gameTypeId, time)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
DECLARE	@Yesterday DATE = DATEADD(DAY, -1, GETUTCDATE());
EXECUTE	dbr.OW_DailySummary 42, @Yesterday;
EXECUTE	dbr.OW_DailySummary 66, @Yesterday;
