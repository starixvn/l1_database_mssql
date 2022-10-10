USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'gfn.SummaryByDate'
	,	@Version	SYSNAME		= N'1.2.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	gfn.SummaryByDate
					@ReportDate			DATETIME		= NULL
				,	@L					TINYINT			= NULL
				,	@Field				NVARCHAR(128)	= NULL
				,	@GroupBy			NVARCHAR(128)	= NULL
				,	@Currency			NVARCHAR(128)	= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20201014@Billy
	Location:		DBSABA.SabaDB
	Description:	View Daily Summary on Grafana

	Parameters:
		@ReportDate			[optional]		- The date of data that will be reported. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

		@L					[optional]		- The id of Luminet system that will be selected
				<DEFAULT>	NULL			- No data

		@Field				[optional]		- The data field which will be selected and filterred.
				<DEFAULT>	NULL			- No data

		@GroupBy			[optional]		- The data field which will be grouped by for aggregation calculation.
				<DEFAULT>	NULL			- All in one

		@Currency			[optional]		- The currency that will be reported.
				<DEFAULT>	NULL			- All currencies

	Version:	1.2.0
	Revisions:
		- [1.2.0]	20221010@Billy		Rearrange game category
		- [1.1.1]	20210419@Billy		Change input encoding to percentage code - [Gitlab: #060]
		- [1.1.0]	20210322@Billy		Update coding convention - Using base functions - [Gitlab: #059]
		- [1.0.2]	20210208@Billy		View summary by currency - [Gitlab: #058]
		- [1.0.1]	20201207@Billy		Support grouping by Game Group - [Gitlab: #053]
		- [1.0.0]	20201020@Billy		Release gfn.SummaryByDate
		- [0.0.2]	20201020@Billy		Separate WinLoss to Win and Loss - [Gitlab: #045]
		- [0.0.1]	20201014@Billy		Initial - [Gitlab: #034]
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@_ReportDate		DATETIME	= CAST(ISNULL(@ReportDate, DATEADD(DAY, -1, GETUTCDATE())) AS DATE)
		;

	DECLARE	@Query		NVARCHAR(MAX)
		,	@WaitFor	VARCHAR(16)		= '00:00:0'
										+ CAST((CAST(RAND() * 10 AS INT)) % 3 AS CHAR(1))
										+ '.'
										+ CAST(CAST(RAND() * 1000 AS INT) AS CHAR(3))
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

	WAITFOR DELAY @WaitFor;

	SELECT	@Value	=	CASE f.str
							WHEN N'Stake' THEN N'ds.stake'
							WHEN N'WinLost' THEN N'ds.stake - ds.payout'
							WHEN N'Win' THEN N'ds.stake - ds.payout'
							WHEN N'Lose' THEN N'ds.payout - ds.stake'
							WHEN N'Ticket' THEN N'ds.tickets'
							ELSE NULL
						END
		,	@Group	=	CASE gb.str
							WHEN N'Game Type' THEN N'cfg.nameEN'
							WHEN N'Game' THEN N'cfg.gameName'
							WHEN N'Game Group' THEN N'cfg.groupName'
							WHEN N'Currency' THEN N'ds.currency'
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
	BEGIN;
		SELECT	r.time, r.metric, r.value
		FROM	@Return AS r;

		RETURN;
	END;

	IF	@_ReportDate = CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE)
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	time, metric, value
FROM	(
	SELECT	ds.time AS time
		,	' + @Group + N' AS metric
		,	SUM(' + @Value + N') AS value
	FROM		summary.game_summary_config AS cfg
	INNER JOIN	summary.daily_summaries AS ds
			ON	ds.gameId = cfg.gameId
	WHERE	ds.currency <> "UUS"
		AND	ds.time = "' + CONVERT(NVARCHAR(MAX), @_ReportDate, 121) + N'"' + ISNULL(N'
		AND	ds.currency = "' + @Currency + N'"', N'') + N'
	GROUP BY ds.time' + ISNULL(', ' + @Group, N'') + N'
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
Query from L' + CONVERT(NVARCHAR(MAX), @L) + N'_SABABI
	- ' + ERROR_MESSAGE()
			RAISERROR(@ErrMsg, 0, 0) WITH NOWAIT;
		END CATCH;
	END;
	ELSE
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	time, metric, value
FROM	(
	SELECT	ds.time AS time
		,	' + @Group + N' AS metric
		,	SUM(' + @Value + N') AS value
	FROM		summary_arc.game_summary_config AS cfg
	INNER JOIN	summary_arc.daily_summaries AS ds
			ON	ds.gameId = cfg.gameId
	WHERE	ds.currency <> "UUS"
		AND	ds.time = "' + CONVERT(NVARCHAR(MAX), @_ReportDate, 121) + N'"' + ISNULL(N'
		AND	ds.currency = "' + @Currency + N'"', N'') + N'
	GROUP BY ds.time' + ISNULL(', ' + @Group, N'') + N'
) AS q
' + @Filter + N'
ORDER BY q.time, q.value DESC;
	';

		BEGIN TRY;
			DELETE	@Temporary;
			INSERT INTO	@Temporary (time, metric, value)
			EXECUTE	base.ExecuteSabaQuery @Query, @L, 1, 1;
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
Query from L' + CONVERT(NVARCHAR(MAX), @L) + N'_SABAARCBI
	- ' + ERROR_MESSAGE()
			RAISERROR(@ErrMsg, 0, 0) WITH NOWAIT;
		END CATCH;
	END;

	SELECT	r.time, r.metric, r.value
	FROM	@Return AS r
	ORDER BY r.value DESC;
END;
GO
