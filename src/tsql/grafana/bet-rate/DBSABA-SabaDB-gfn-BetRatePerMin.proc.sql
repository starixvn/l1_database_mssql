USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'gfn.BetRatePerMin'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	gfn.BetRatePerMin
					@Var1				SQL_VARIANT		= NULL
				,	@Var2				SQL_VARIANT		= NULL
				,	@Var3				SQL_VARIANT		= NULL
				,	@Var4				SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210726@Billy
	Location:		DBSABA.SabaDB
	Description:	View Bet Rate on Grafana

	Parameters:
		@Var1				[optional]		- Report data from this time
				<DEFAULT>	NULL			- Start of yesterday

		@Var2				[optional]		- Report data to this time
				<DEFAULT>	NULL			- Start of today

		@Var3				[optional]		- The id of Luminet system that will be selected..
				<DEFAULT>	NULL			- No data

		@Var4				[optional]		- The game name that to be queried..
				<DEFAULT>	NULL			- All games

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210531@Billy		Release gfn.BetRatePerMin
		- [0.0.1]	20210531@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@FromDate			DATETIME		= NULL
		,	@ToDate				DATETIME		= NULL
		,	@L					TINYINT			= NULL
		,	@GameName			NVARCHAR(128)	= NULL
		;

	EXECUTE	base.WaitForRandom 1;

	BEGIN TRY; SELECT @FromDate = CONVERT(DATETIME     , @Var1) END TRY BEGIN CATCH; SELECT @FromDate = NULL; END CATCH;
	BEGIN TRY; SELECT @ToDate   = CONVERT(DATETIME     , @Var2) END TRY BEGIN CATCH; SELECT @ToDate   = NULL; END CATCH;
	BEGIN TRY; SELECT @L        = CONVERT(TINYINT      , @Var3) END TRY BEGIN CATCH; SELECT @L        = NULL; END CATCH;
	BEGIN TRY; SELECT @GameName = CONVERT(NVARCHAR(128), @Var4) END TRY BEGIN CATCH; SELECT @GameName = NULL; END CATCH;

	SELECT	@FromDate	= ISNULL(@FromDate, CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE))
		,	@ToDate		= ISNULL(@ToDate, CAST(GETUTCDATE() AS DATE))
		;

	DECLARE	@Query		NVARCHAR(MAX)
		,	@Archive	TINYINT
		,	@LogTbl		NVARCHAR(128)
		,	@CfgTbl		NVARCHAR(128)
		,	@ErrMsg		NVARCHAR(MAX)
		;

	DECLARE	@Games AS TABLE (
				gameId		INT
			,	nameEN		NVARCHAR(128)
			);

	DECLARE	@Return AS TABLE (
				time		DATETIME
			,	metric		NVARCHAR(128)
			,	value		DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (metric, time)
			);

	SELECT	@Archive = CASE WHEN @FromDate >= DATEADD(DAY, -7, GETUTCDATE()) THEN 0 ELSE 1 END
		,	@LogTbl = CASE WHEN @FromDate >= DATEADD(DAY, -7, GETUTCDATE()) THEN N'log.bets' ELSE N'log_arc.bets_bk' END
		,	@CfgTbl = CASE WHEN @FromDate >= DATEADD(DAY, -7, GETUTCDATE()) THEN N'summary.game_summary_config' ELSE N'summary_arc.game_summary_config' END
		;

	/* Get list of games */
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	gameId, nameEN
FROM	' + @CfgTbl + N';
';
		INSERT INTO	@Games (gameId, nameEN)
		EXECUTE	base.ExecuteSabaQuery @Query, @L, @Archive, 1;

		DELETE	@Games
		WHERE	nameEN <> @GameName;
	END;

	/* Get data */
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	FROM_UNIXTIME(FLOOR(UNIX_TIMESTAMP(b.requestTS)/60)*60) AS time
	,	b.gameTypeId AS metric
	,	COUNT(1) AS value
FROM	' + @LogTbl + N' AS b
WHERE	b.requestTS >= "' + CONVERT(NVARCHAR(MAX), @FromDate, 127) + N'"
	AND	b.requestTS < "' + CONVERT(NVARCHAR(MAX), @ToDate, 127) + N'"
	AND	b.gameTypeId IN (0' + gs.str + N')
GROUP BY FLOOR(UNIX_TIMESTAMP(b.requestTS)/60), b.gameTypeId
;
'
		FROM	(
			SELECT	N', ' + CAST(gameId AS NVARCHAR(MAX))
			FROM	@Games
			FOR XML PATH ('')
			,	TYPE
		) AS g(xml)
		CROSS APPLY	(
			SELECT	g.xml.value('.', 'NVARCHAR(MAX)')
		) AS gs(str);

		RAISERROR(@Query, 0, 0) WITH NOWAIT;

 		BEGIN TRY;
			INSERT INTO	@Return (time, metric, value)
			EXECUTE	base.ExecuteSabaQuery @Query, @L, @Archive, 1;
		END TRY
		BEGIN CATCH
			SELECT	@ErrMsg = N'\
Query from L' + CONVERT(NVARCHAR(MAX), @L) + N'_ARCSABABI
	- ' + ERROR_MESSAGE()
			RAISERROR(@ErrMsg, 0, 0) WITH NOWAIT;
		END CATCH;
	END;

	ReturnData:
	SELECT	[time]		= r.time
		,	[metric]	= g.nameEN
		,	[value]		= r.value
	FROM		@Return AS r
	INNER JOIN	@Games AS g
			ON	r.metric = g.gameId
	ORDER BY r.time, r.metric;
END;
GO
