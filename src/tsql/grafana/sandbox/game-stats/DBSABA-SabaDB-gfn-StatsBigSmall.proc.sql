USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'gfn.StatsBigSmall'
	,	@Version	SYSNAME		= N'0.0.3'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	gfn.StatsBigSmall
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
				,	@Var4			SQL_VARIANT		= NULL
				,	@Var5			SQL_VARIANT		= NULL
				,	@Var6			SQL_VARIANT		= NULL
				,	@Var7			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211201@Billy
	Location:		DBSABA.SabaDB
	Description:	

	Parameters:

	Version:	0.0.3
	Revision:
		- [1.0.0]	20211201@Billy		Release dbr.StatsBigSmall
		- [0.0.3]	20211202@Billy		Using refund data from summary
		- [0.0.2]	20211201@Billy		Combine Stake|Refund & Stake|Payout
		- [0.0.1]	20211201@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	EXECUTE	base.WaitForRandom;
	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@Game		NVARCHAR(256)
		,	@Coll		NVARCHAR(128)
		,	@GameId		SMALLINT
		,	@From		DATETIME
		,	@To			DATETIME
		,	@Days		SMALLINT
		,	@L			TINYINT
		,	@Env		TINYINT
		,	@Type		NVARCHAR(128)
		,	@Interval	NVARCHAR(128)
		;

	BEGIN TRY; SELECT @Game     = CONVERT(NVARCHAR(256), @Var1); END TRY BEGIN CATCH; SELECT @Game     = NULL; END CATCH;
	BEGIN TRY; SELECT @From     = CONVERT(DATETIME     , @Var2); END TRY BEGIN CATCH; SELECT @From     = NULL; END CATCH;
	BEGIN TRY; SELECT @Days     = CONVERT(SMALLINT     , @Var3); END TRY BEGIN CATCH; SELECT @Days     = NULL; END CATCH;
	BEGIN TRY; SELECT @L        = CONVERT(TINYINT      , @Var4); END TRY BEGIN CATCH; SELECT @L        = NULL; END CATCH;
	BEGIN TRY; SELECT @Env      = CONVERT(TINYINT      , @Var5); END TRY BEGIN CATCH; SELECT @Env      = NULL; END CATCH;
	BEGIN TRY; SELECT @Type     = CONVERT(NVARCHAR(128), @Var6); END TRY BEGIN CATCH; SELECT @Type     = NULL; END CATCH;
	BEGIN TRY; SELECT @Interval = CONVERT(NVARCHAR(128), @Var7); END TRY BEGIN CATCH; SELECT @Interval = NULL; END CATCH;

	SELECT	@Coll	= g.coll
	FROM	(
		VALUES	(N'Big Small', N'taixiu')
			,	(N'Turbo Big Small', N'txturbo')
	) AS g(name, coll)
	WHERE	g.name = @Game;

	SELECT	@GameId	= gm.gameId
	FROM	dbr.tf_GameTypeMapping(NULL, NULL, NULL) AS gm
	WHERE	gm.baseName = @Coll;

	IF	@Coll IS NULL OR @L IS NULL
		GOTO Finish;

	SELECT	@From	= ISNULL(@From, CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE))
		,	@To		= DATEADD(DAY, ISNULL(@Days, 1), @From)
		;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	IF	@Type = 'LastRound'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	id, time
FROM	minigame.' + @Coll + N'_rounds
ORDER BY id DESC
LIMIT 1
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'LastActiveRound'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	roundId AS id
FROM	minigame.' + @Coll + N'_tickets
ORDER BY roundId DESC
LIMIT 1
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'BigSmall'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	SUM(big)   AS "big"
	,	SUM(small) AS "small"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 127) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 127) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'BigSmallDelta'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	(SUM(big)   - SUM(1) * 1/2) / SUM(1) AS "big"
	,	(SUM(small) - SUM(1) * 1/2) / SUM(1) AS "small"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 127) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 127) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'StakeRefund'
	BEGIN;
		SELECT	@Coll = NULL;
		SELECT	@Coll = m.coll
		FROM	(
			VALUES	(N'hour', N'hourly_summaries')
				,	(N'day' , N'daily_summaries')
		) AS m(interval, coll)
		WHERE	m.interval = @Interval;

		IF	@Coll IS NULL
			GOTO Finish;

		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	time AS time
	,	SUM(refund) AS refund
	,	SUM(stake - refund) AS valid
	,	SUM(payout) AS payout
FROM	summary.' + @Coll + N'
WHERE	currency <> "UUS"
	AND	gameId = ' + CONVERT(NVARCHAR(MAX), @GameId) + N'
	AND	time >= "' + CONVERT(NVARCHAR(MAX), @From, 127) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 127) + N'"
GROUP BY time
ORDER BY time
;';
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'StakeRefundPercent'
	BEGIN;
		SELECT	@Coll = NULL;
		SELECT	@Coll = m.coll
		FROM	(
			VALUES	(N'hour', N'hourly_summaries')
				,	(N'day' , N'daily_summaries')
		) AS m(interval, coll)
		WHERE	m.interval = @Interval;

		IF	@Coll IS NULL
			GOTO Finish;

		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	time AS time
	,	SUM(refund) / SUM(stake) AS refund
	,	SUM(stake - refund) / SUM(stake) AS valid
FROM	summary.' + @Coll + N'
WHERE	currency <> "UUS"
	AND	gameId = ' + CONVERT(NVARCHAR(MAX), @GameId) + N'
	AND	time >= "' + CONVERT(NVARCHAR(MAX), @From, 127) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 127) + N'"
GROUP BY time
ORDER BY time
;';
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;

	Finish:
	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	gfn.StatsBigSmall 'Big Small', NULL, NULL, 1, 1, 'BigSmall'
EXECUTE	gfn.StatsBigSmall 'Big Small', '2021-11-30T08:00:00Z', 1, 1, 1, 'StakeRefund', 'hour'
