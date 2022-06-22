USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'gfn.BetLogSummary'
	,	@Version	SYSNAME		= N'1.1.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	gfn.BetLogSummary
					@Var1				SQL_VARIANT
				,	@Var2				SQL_VARIANT
				,	@Var3				SQL_VARIANT		= NULL
				,	@Var4				SQL_VARIANT		= NULL
				,	@Var5				SQL_VARIANT		= NULL
				,	@Var6				SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210531@Billy
	Location:		DBDWCSS.SabaDB
	Description:	View BetLog Summary on Grafana

	Parameters:
		@Var1				[REQUIRED]		- The start time of data that will be compared. The time is in UTC timezone.

		@Var2				[REQUIRED]		- The end time of data that will be compared. The time is in UTC timezone.

		@Var3				[optional]		- The id of Luminet system that will be selected.
				<DEFAULT>	NULL			- No data

		@Var4				[optional]		- The field to be selected.
				<DEFAULT>	NULL			- No data

		@Var5				[optional]		- The field to be grouped.
				<DEFAULT>	NULL			- No data

		@Var6				[optional]		- The currency to be selected.
				<DEFAULT>	NULL			- All currencies

	Version:	1.1.0
	Revision:
		- [1.1.0]	20210816@Billy		Add ɪɴsᴛᴀɴᴛ value
		- [1.1.0]	20210617@Billy		Update query to match with new BI schema
		- [1.0.0]	20210531@Billy		Release gfn.BetLogSummaryByDate
		- [0.0.1]	20210531@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@DateFrom			DATETIME
		,	@DateTo				DATETIME
		,	@L					TINYINT			= NULL
		,	@Field				NVARCHAR(128)	= NULL
		,	@GroupBy			NVARCHAR(128)	= NULL
		,	@Currency			NVARCHAR(128)	= NULL
		;

	EXECUTE	base.WaitForRandom 1;

	BEGIN TRY; SELECT @DateFrom = CONVERT(DATETIME     , @Var1) END TRY BEGIN CATCH; SELECT @DateFrom = NULL; END CATCH;
	BEGIN TRY; SELECT @DateTo   = CONVERT(DATETIME     , @Var2) END TRY BEGIN CATCH; SELECT @DateTo   = NULL; END CATCH;
	BEGIN TRY; SELECT @L        = CONVERT(TINYINT      , @Var3) END TRY BEGIN CATCH; SELECT @L        = NULL; END CATCH;
	BEGIN TRY; SELECT @Field    = CONVERT(NVARCHAR(128), @Var4) END TRY BEGIN CATCH; SELECT @Field    = NULL; END CATCH;
	BEGIN TRY; SELECT @GroupBy  = CONVERT(NVARCHAR(128), @Var5) END TRY BEGIN CATCH; SELECT @GroupBy  = NULL; END CATCH;
	BEGIN TRY; SELECT @Currency = CONVERT(NVARCHAR(128), @Var6) END TRY BEGIN CATCH; SELECT @Currency = NULL; END CATCH;

	DECLARE	@Query		NVARCHAR(MAX)
		,	@Value		NVARCHAR(256)
		,	@Group		NVARCHAR(256)
		,	@Filter		NVARCHAR(256)
		,	@ErrMsg		NVARCHAR(MAX)
		;

	DECLARE	@Return AS TABLE (
				time		DATETIME
			,	metric		NVARCHAR(128)
			,	value		DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (metric, time)
			);

	DECLARE	@Temporary AS TABLE (
				time		DATETIME
			,	metric		NVARCHAR(128)
			,	value		DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (metric, time)
			);

	SELECT	@Value	=	CASE f.str
							WHEN N'Request' THEN N'bs.requestCount'
							WHEN N'Bet' THEN N'bs.betCount'
							WHEN N'TurnOver' THEN N'bs.totalAmount'
							ELSE NULL
						END
		,	@Group	=	CASE gb.str
							WHEN N'Game' THEN N'cfg.nameEN'
							WHEN N'Game Group' THEN N'cfg.groupName'
							WHEN N'Currency' THEN N'bs.currency'
							WHEN N'Summary' THEN N'"Summary"'
							ELSE NULL
						END
		,	@Filter	=	CASE f.str
							WHEN N'Win' THEN N'WHERE	q.value >= 0'
							WHEN N'Lose' THEN N'WHERE	q.value < 0'
							ELSE N''
						END
	FROM		base.tf_DecodeURL(@Field) AS f
	CROSS APPLY	base.tf_DecodeURL(@GroupBy) AS gb
		;

	IF	@Value IS NULL OR @Group IS NULL
		GOTO ReturnData;

	SELECT	@Query = N'';
	SELECT	@Query += N'\
SELECT	time, metric, value
FROM	(
	SELECT	DATE(bs.time) AS time
		,	CONCAT(CASE bs.system WHEN 1 THEN "ᴄᴏᴄᴏs " WHEN 2 THEN "ᴍᴏʙɪ " WHEN 3 THEN "ɪɴsᴛᴀɴᴛ " ELSE "" END, ' + @Group + N') AS metric
		,	SUM(' + @Value + N') AS value
	FROM		summary.game_summary_config AS cfg
	INNER JOIN	summary.betlog_summaries AS bs
			ON	bs.gameId = cfg.gameId
	WHERE	bs.currency <> "UUS"
		AND	bs.time >= "' + CONVERT(NVARCHAR(MAX), @DateFrom, 121) + N'"
		AND	bs.time <= "' + CONVERT(NVARCHAR(MAX), @DateTo, 121) + N'"' + ISNULL(N'
		AND	bs.currency = "' + @Currency + N'"', N'') + N'
	GROUP BY DATE_FORMAT(bs.`time`, "%Y-%m-%d"), CONCAT(bs.system, ' + @Group + N')
) AS q
' + @Filter + N'
ORDER BY q.time, q.value DESC;
';

	BEGIN TRY;
		DELETE	@Temporary;
		INSERT INTO	@Temporary (time, metric, value)
		EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, 1;
		MERGE INTO	@Return AS r
		USING	@Temporary AS t
			ON	r.time = t.time
			AND	r.metric = t.metric
		WHEN MATCHED THEN
			UPDATE SET	r.value = r.value + ISNULL(t.value, 0)
		WHEN NOT MATCHED THEN
			INSERT	(time, metric, value)
			VALUES	(t.time, t.metric, ISNULL(t.value, 0))
		;
	END TRY
	BEGIN CATCH
		SELECT	@ErrMsg = N'\
Query from L' + @L + N'_SABAARCBI
	- ' + ERROR_MESSAGE()
		RAISERROR(@ErrMsg, 0, 0) WITH NOWAIT;
	END CATCH;

	ReturnData:
	SELECT	r.time, r.metric, r.value
	FROM	@Return AS r
	ORDER BY r.time, r.metric;
END;
GO
