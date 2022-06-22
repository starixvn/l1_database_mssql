USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'gfn.DailySummaryComparison'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	gfn.DailySummaryComparison
					@Var1			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20201008@Billy
	Location:		DBSABA.SabaDB
	Description:	Compare Daily Summary related result between OW and SB then show result on Grafana

	Parameters:
		@Var1				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

	Version:	1.0.0
	Revision:
		- [1.0.0]	20201008@Billy		Release gfn.DailySummaryComparison
		- [0.0.1]	20201008@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@ReportDate		DATETIME
		;

	BEGIN TRY; SELECT @ReportDate = CONVERT(DATETIME, @Var1); END TRY BEGIN CATCH; SELECT @ReportDate = NULL; END CATCH;

	SELECT	@ReportDate		= ISNULL(@ReportDate, ISNULL(@ReportDate, CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE)))
		;

	IF	NOT (DATEDIFF(DAY, @ReportDate, GETUTCDATE()) BETWEEN 1 AND 7)
	BEGIN;
		RAISERROR(N'\
[ERR]   @ReportDate is out of range', 0, 0) WITH NOWAIT;
		RETURN;
	END;

	DECLARE	@SC				INT
		,	@isCash			TINYINT
		,	@GameId			INT
		,	@GameType		NVARCHAR(128)
		,	@GameTypeId		INT
		,	@Message		NVARCHAR(MAX)
		,	@Title			NVARCHAR(512)
		;

	DECLARE	@SCs AS TABLE (
				SC				TINYINT
			,	isExpanded		BIT
			,	isCash			TINYINT
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (SC)
			);

	DECLARE	@Tmp_DailySummary AS TABLE (
				SC				TINYINT
			,	gameTypeId		INT
			,	gameId			INT
			,	gameType		NVARCHAR(128)
			,	currency		VARCHAR(10)
			,	isCash			TINYINT
			,	phienCount		INT
			,	betCount		INT
			,	stake			DECIMAL(19,4)
			,	winLost			DECIMAL(19,4)
			,	payOut			DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (SC, gameTypeId, currency, isCash)
			);

	CREATE TABLE	#OW_DailySummary (
						gameTypeId		INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	isCash			TINYINT
					,	phienCount		INT
					,	betCount		INT
					,	stake			DECIMAL(19,4)
					,	payOut			DECIMAL(19,4)
					,	PRIMARY KEY CLUSTERED (gameTypeId, currency, isCash)
					);

	CREATE TABLE	#DS_DailySummary (
						SC				TINYINT
					,	gameId			INT
					,	gameTypeId		INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	isCash			TINYINT
					,	betCount		INT
					,	stake			DECIMAL(19,4)
					,	payOut			DECIMAL(19,4)
					,	PRIMARY KEY CLUSTERED (SC, gameTypeId, currency, isCash)
					);

	-- List of SCs --
	INSERT INTO	@SCs
			(SC, isExpanded, isCash, isDone)
	VALUES	( 1,          0,      0,      0)
		,	( 2,          0,      1,      0)
		,	( 3,          0,   NULL,      0)
		;

	BEGIN;	-- OW --
		INSERT INTO	#OW_DailySummary (gameTypeId, gameType, currency, isCash, phienCount, betCount, stake, payOut)
		EXECUTE	dbr.OW_DailySummary 42, @ReportDate;
		RAISERROR('Executed on OW - #%d.', 0, 0, 42) WITH NOWAIT;

		INSERT INTO	#OW_DailySummary (gameTypeId, gameType, currency, isCash, phienCount, betCount, stake, payOut)
		EXECUTE	dbr.OW_DailySummary 66, @ReportDate;
		RAISERROR('Executed on OW - #%d.', 0, 0, 66) WITH NOWAIT;

		DELETE	#OW_DailySummary
		WHERE	gameTypeId IN (1698, 3898);
	END;	-- OW --

	BEGIN;	-- SB --
		UPDATE	@SCs
		SET		isDone = 0;

		WHILE	EXISTS (SELECT 1 FROM @SCs WHERE isDone = 0)
		BEGIN;
			UPDATE	TOP(1)
					@SCs
			SET		@SC		= SC
				,	@isCash	= isCash
				,	isDone	= 1
			WHERE	isDone = 0;

			DELETE	@Tmp_DailySummary;
			INSERT INTO	@Tmp_DailySummary (SC, gameTypeId, gameId, gameType, currency, isCash, betCount, stake, payOut)
			EXECUTE	dbr.SB_DailySummary @SC, 1, @ReportDate;

			MERGE INTO	#DS_DailySummary AS ds
			USING		@Tmp_DailySummary AS tmp
					ON	ds.SC = @SC
					AND	COALESCE(NULLIF(ds.isCash, 2), @isCash, 2) = COALESCE(NULLIF(tmp.isCash, 2), @isCash, 2)
					AND	ds.gameTypeId = tmp.gameTypeId
					AND	ds.currency = tmp.currency
			WHEN MATCHED THEN
				UPDATE
				SET	ds.betCount += tmp.betCount
				,	ds.stake += tmp.stake
				,	ds.payOut += tmp.payOut
			WHEN NOT MATCHED THEN
				INSERT	( SC,     gameTypeId,     gameId,     gameType,     currency,                     isCash                 ,     betCount,     stake,     payOut)
				VALUES	(@SC, tmp.gameTypeId, tmp.gameId, tmp.gameType, tmp.currency, COALESCE(NULLIF(tmp.isCash, 2), @isCash, 2), tmp.betCount, tmp.stake, tmp.payOut)
			;
			RAISERROR('Executed on SC%d.', 0, 0, @SC) WITH NOWAIT;
		END;
	END;	-- SB --

	SELECT	[Id]			= ow.gameTypeId
		,	[Game]			= ow.gameType
		,	[¤]				= ow.currency
		,	[ ]				= CASE ow.isCash WHEN 0 THEN 'Credit' WHEN 1 THEN 'Deposit' ELSE '-- invalid --' END
		,	[Round Cnt.]	= ow.phienCount
		,	[T_OW]			= CASE	WHEN ow.betCount > sc.betCount THEN ow.betCount - sc.betCount
									ELSE 0 END
		,	[Ticket]		= CASE	WHEN ow.betCount > sc.betCount THEN -1
									WHEN ow.betCount < sc.betCount THEN 1
									ELSE 0 END
		,	[T_SC]			= CASE	WHEN ow.betCount < sc.betCount THEN sc.betCount - ow.betCount
									ELSE 0 END
		,	[S_OW]			= CASE	WHEN ow.stake > sc.stake THEN ow.stake - sc.stake
									ELSE 0 END
		,	[Stake]			= CASE	WHEN ow.stake > sc.stake THEN -1
									WHEN ow.stake < sc.stake THEN 1
									ELSE 0 END
		,	[S_SC]			= CASE	WHEN ow.stake < sc.stake THEN sc.stake - ow.stake
									ELSE 0 END
		,	[P_OW]			= CASE	WHEN ow.payOut > sc.payOut THEN ow.payOut - sc.payOut
									ELSE 0 END
		,	[PayOut]		= CASE	WHEN ow.payOut > sc.payOut THEN -1
									WHEN ow.payOut < sc.payOut THEN 1
									ELSE 0 END
		,	[P_SC]			= CASE	WHEN ow.payOut < sc.payOut THEN sc.payOut - ow.payOut
									ELSE 0 END
		,	[Ticket Status]	= CASE	WHEN ow.betCount = sc.betCount THEN 1
									ELSE 0 END
		,	[Stake Status]	= CASE	WHEN ow.stake = sc.stake THEN 1
									ELSE 0 END
		,	[Payout Status]	= CASE	WHEN ow.payOut = sc.payOut THEN 1
									ELSE 0 END
	FROM			#OW_DailySummary AS ow
	FULL OUTER JOIN	#DS_DailySummary AS sc
				ON	ow.gameTypeId = sc.gameTypeId
				AND	ow.currency = sc.currency
				AND	ow.isCash = sc.isCash
	WHERE	ISNULL(ow.currency, sc.currency) <> 'UUS'
	ORDER BY CASE WHEN ISNULL(ow.currency, sc.currency) = 'UUS' THEN 1 ELSE 0 END, ow.gameTypeId, sc.gameTypeId, ow.currency, sc.currency, ow.isCash, sc.isCash;

END;
GO

EXECUTE	gfn.DailySummaryComparison;
