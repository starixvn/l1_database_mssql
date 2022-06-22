USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'gfn.StatsSeDie'
	,	@Version	SYSNAME		= N'0.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	gfn.StatsSeDie
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
				,	@Var4			SQL_VARIANT		= NULL
				,	@Var5			SQL_VARIANT		= NULL
				,	@Var6			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211124@Billy
	Location:		DBSABA.SabaDB
	Description:	

	Parameters:

	Version:	0.0.1
	Revision:
		- [1.0.0]	20211124@Billy		Release dbr.StatsSeDie
		- [0.0.1]	20211124@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	EXECUTE	base.WaitForRandom;
	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@Game		NVARCHAR(256)
		,	@Coll		NVARCHAR(128)
		,	@From		DATETIME
		,	@To			DATETIME
		,	@Days		SMALLINT
		,	@L			TINYINT
		,	@Env		TINYINT
		,	@Type		NVARCHAR(128)
		;

	BEGIN TRY; SELECT @Game = CONVERT(NVARCHAR(256), @Var1); END TRY BEGIN CATCH; SELECT @Game = NULL; END CATCH;
	BEGIN TRY; SELECT @From = CONVERT(DATETIME     , @Var2); END TRY BEGIN CATCH; SELECT @From = NULL; END CATCH;
	BEGIN TRY; SELECT @Days = CONVERT(SMALLINT     , @Var3); END TRY BEGIN CATCH; SELECT @Days = NULL; END CATCH;
	BEGIN TRY; SELECT @L    = CONVERT(TINYINT      , @Var4); END TRY BEGIN CATCH; SELECT @L    = NULL; END CATCH;
	BEGIN TRY; SELECT @Env  = CONVERT(TINYINT      , @Var5); END TRY BEGIN CATCH; SELECT @Env  = NULL; END CATCH;
	BEGIN TRY; SELECT @Type = CONVERT(NVARCHAR(128), @Var6); END TRY BEGIN CATCH; SELECT @Type = NULL; END CATCH;

	SELECT	@Coll	= g.coll
	FROM	(
		VALUES	(N'Se Die'        , N'xocxoc')
			,	(N'Mini Se Die'   , N'minisedie')
			,	(N'VIP Se Die'    , N'vipsedie')
			,	(N'Special Se Die', N'specialsedie')
	) AS g(name, coll)
	WHERE	g.name = @Game;

	IF	@Coll IS NULL OR @L IS NULL
		GOTO Finish;

	SELECT	@From	= ISNULL(@From, CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE))
		,	@To		= CAST(DATEADD(DAY, ISNULL(@Days, 1), @From) AS DATE)
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
	IF	@Type = 'OddEven'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	SUM(odd)  AS "odd"
	,	SUM(even) AS "even"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 126) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'OddEvenDelta'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	(SUM(odd)  - SUM(1) * 1/2) / SUM(1) AS "odd"
	,	(SUM(even) - SUM(1) * 1/2) / SUM(1) AS "even"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 126) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'RedCount'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	SUM(r0) AS "0 reds"
	,	SUM(r1) AS "1 reds"
	,	SUM(r2) AS "2 reds"
	,	SUM(r3) AS "3 reds"
	,	SUM(r4) AS "4 reds"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 126) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'RedCountDelta'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	(SUM(r0) - SUM(1) * 1/16) / SUM(1) AS "0 reds"
	,	(SUM(r1) - SUM(1) * 4/16) / SUM(1) AS "1 reds"
	,	(SUM(r2) - SUM(1) * 6/16) / SUM(1) AS "2 reds"
	,	(SUM(r3) - SUM(1) * 4/16) / SUM(1) AS "3 reds"
	,	(SUM(r4) - SUM(1) * 1/16) / SUM(1) AS "4 reds"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 126) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'RedWhite'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	SUM(red1 + red2 + red3 + red4) AS "red"
	,	SUM(4) - SUM(red1 + red2 + red3 + red4) AS "white"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 126) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'RedWhiteDelta'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	"" AS "metric"
	,	(SUM(red1 + red2 + red3 + red4) - SUM(4) * 1/2) / SUM(4) AS "red"
	,	(SUM(4) - SUM(red1 + red2 + red3 + red4) - SUM(4) * 1/2) / SUM(4) AS "white"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 126) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;
	IF	@Type = 'Stats'
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	SUM(1) AS "RoundCnt"
FROM	minigame.' + @Coll + N'_rounds
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time <  "' + CONVERT(NVARCHAR(MAX), @To  , 126) + N'"
;'
			;
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;
	END;

	Finish:
	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	gfn.StatsSeDie 'Se Die', NULL, NULL, 1, 1, 'RedWhiteDelta'
