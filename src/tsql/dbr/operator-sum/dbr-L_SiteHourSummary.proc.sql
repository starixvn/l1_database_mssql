USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.L_SiteHourSummary'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.L_SiteHourSummary
					@L				TINYINT
				,	@fromHour		DATETIME
				,	@toHour			DATETIME
WITH ENCRYPTION
AS
/*
	Creator:		20230512@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Daily Summary data from SB database

	Parameters:
		@L					[optional]		- The id of Luminet system that will be selected
				<DEFAULT>	NULL			- No data

	Version:	1.0.0
	Revision:
		- [1.0.0]	20231214@Billy		Exclude test currency UUS
		- [1.0.0]	20230512@Billy		Release dbr.L_SiteHourSummary
		- [0.0.1]	20230512@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME();

	DECLARE	@Query		NVARCHAR(MAX);

	SELECT	@Query = N'';
	SELECT	@Query += N'\
SELECT	ds.operatorId
	,	ds.time
	,	cfg.gameTypeId
	,	cfg.gameId
	,	IFNULL(c.code, ds.currency) AS currency
	,	ds.tickets AS betCount
	,	ds.stake * IFNULL(c.multiplier, 1) AS turnOver
	,	ds.payout * IFNULL(c.multiplier, 1)  AS payOut
FROM		summary.hourly_summaries AS ds
INNER JOIN	summary.game_summary_config AS cfg
		ON	ds.gameId = cfg.gameId
LEFT JOIN	minigame.currencies AS c
		ON	ds.operatorId = c.partnerId
		AND	ds.currency = c.name
WHERE	ds.time >= "' + FORMAT(@fromHour, 'yyyy-MM-ddTHH:mm:ssZ') + N'"
	AND	ds.time < "' + FORMAT(@toHour, 'yyyy-MM-ddTHH:mm:ssZ') + N'"
	AND c.isTest = 0
GROUP BY ds.operatorId, ds.time, ds.gameId, IFNULL(c.code, ds.currency)
';

	EXECUTE	base.Query @Query, @L, 0, 1;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.L_SiteHourSummary') IS NOT NULL
		DROP TYPE dbr.L_SiteHourSummary;

	CREATE TYPE	dbr.L_SiteHourSummary AS TABLE (
		operatorId		VARCHAR(128)
	,	time			DATETIME
	,	gameTypeId		SMALLINT
	,	gameId			SMALLINT
	,	currency		VARCHAR(10)
	,	betCount		INT
	,	turnOver		MONEY
	,	payOut			MONEY
	,	PRIMARY KEY NONCLUSTERED (operatorId, time, gameId, currency)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
DECLARE	@from	DATETIME	= DATEADD(MINUTE, DATEDIFF(MINUTE, 0, GETUTCDATE()) - 120, 0)
	,	@to		DATETIME	= DATEADD(MINUTE, DATEDIFF(MINUTE, 0, GETUTCDATE()) - 61, 0)
	;
SELECT	[@from] = @from, [@to] = @to;
EXECUTE	dbr.L_SiteHourSummary 1, @from, @to;
EXECUTE	dbr.L_SiteHourSummary 2, @from, @to;
GO
