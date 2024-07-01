USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.L_HourlySummary'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.L_HourlySummary
					@L				TINYINT
				,	@reportHour		DATETIME
WITH ENCRYPTION
AS
/*
	Creator:		20240123@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Hourly Summary data from SB database

	Parameters:
		@L					[REQUIRED]		- The id of Luminet system that will be selected

		@reportDate			[REQUIRED]		- The date of data that will be selected. The time is in UTC timezone.

	Version:	1.0.0
	Revision:
		- [1.0.0]	20240123@Billy		Release dbr.L_HourlySummary
		- [0.0.1]	20240123@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME();

	DECLARE	@Query		NVARCHAR(MAX);

	SELECT	@Query = N'';
	SELECT	@Query += N'\
SELECT	ds.operatorId AS operatorId
	,	ds.time AS time
	,	cfg.gameTypeId AS gameTypeId
	,	cfg.gameId AS gameId
	,	cfg.nameEN AS gameName
	,	IFNULL(ds.currency, "null") AS currency
	,	ds.tickets AS betCount
	,	ds.stake AS stake
	,	ds.payOut AS payOut
FROM		summary.hourly_summaries AS ds
INNER JOIN	summary.game_summary_config AS cfg
		ON	ds.gameId = cfg.gameId
WHERE	ds.time >= "' + FORMAT(@reportHour, 'yyyy-MM-dd HH:00:00') + N'"
	AND	ds.time < "' + FORMAT(DATEADD(HOUR, 1, @reportHour), 'yyyy-MM-dd HH:00:00') + N'"
GROUP BY ds.operatorId, ds.time, ds.gameId, ds.currency
'
		;

	EXECUTE	base.Query @Query, @L, 0, 1;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.L_HourlySummary') IS NOT NULL
		DROP TYPE dbr.L_HourlySummary;

	CREATE TYPE	dbr.L_HourlySummary AS TABLE (
		operatorId		NVARCHAR(128)
	,	time			DATETIME
	,	gameTypeId		INT
	,	gameId			INT
	,	gameName		NVARCHAR(128)
	,	currency		VARCHAR(16)
	,	betCount		BIGINT
	,	turnOver		DECIMAL(19,4)
	,	payOut			DECIMAL(19,4)
	,	PRIMARY KEY NONCLUSTERED (operatorId, currency, gameTypeId, time)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
DECLARE	@LastHour DATETIME = DATEADD(HOUR, DATEDIFF(HOUR, 0, GETUTCDATE()) - 1, 0);
EXECUTE	dbr.L_HourlySummary 1, @LastHour;
EXECUTE	dbr.L_HourlySummary 2, @LastHour;
