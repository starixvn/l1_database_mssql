USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'vGaming.DailySummaryReport'
	,	@Version	SYSNAME		= N'2.2.2'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
DECLARE	@Procedure	SYSNAME		= N'vGaming.DailySummaryReport_Wrapper'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	vGaming.DailySummaryReport
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210529@Billy
	Location:		DBSABA.SabaDB
	Description:	Compare Daily Summary for vGaming
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing


	Version:	2.2.2
	Revision:
		- [2.2.2]	20230428@Billy		Treat vG as one platfrom
		- [2.2.1]	20230413@Billy		Reformat due to Skynex changes
		- [2.2.0]	20220624@Billy		Using SQL Server 2019 syntax
		- [2.1.2]	20220621@Billy		Reformat messages
		- [2.1.1]	20211020@Billy		Group by currency code
		- [2.1.0]	20210806@Billy		Migrate SC2 to vG2
		- [2.0.1]	20210722@Billy		Base SP updated for SIT environment support
		- [2.0.0]	20210531@Billy		Split into SabaClub & vGaming report
		- [1.0.2]	20210423@Billy		Update message format - [Gitlab: #060]
		- [1.0.1]	20210218@Billy		Report by currency for SC3 - [Gitlab: #058]
		- [1.0.0]	20201008@Billy		Release Noti.DailySummaryReport - [Gitlab: #058]
		- [0.0.1]	20201008@Billy		Initital - [Gitlab: #058]
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@ReportDate		DATETIME
		,	@isTest			BIT
		;

	BEGIN TRY SELECT @ReportDate = CONVERT(DATETIME, @Var1); END TRY BEGIN CATCH SELECT @ReportDate = NULL; END CATCH;
	BEGIN TRY SELECT @isTest     = CONVERT(BIT     , @Var2); END TRY BEGIN CATCH SELECT @isTest     = NULL; END CATCH;

	SELECT	@ReportDate		= ISNULL(@ReportDate, CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE))
		,	@isTest			= ISNULL(@isTest, 1)
		;

	DECLARE	@VendorId		INT 			= 66
		,	@Status			NVARCHAR(128)	= N'OK'
		,	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)
		;

	IF	NOT (DATEDIFF(DAY, @ReportDate, GETUTCDATE()) BETWEEN 1 AND 7)
	BEGIN;
		RAISERROR(N'\
[ERR]   @ReportDate is out of range', 0, 0) WITH NOWAIT;
		RETURN;
	END;

	DECLARE	@L				INT
		,	@isCash			TINYINT
		,	@GameId			INT
		,	@GameType		NVARCHAR(128)
		,	@GameTypeId		INT
		,	@Message		NVARCHAR(MAX)
		,	@Title			NVARCHAR(512)
		;

	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	isExpanded		BIT
			,	isCash			TINYINT
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (L)
			);

	DECLARE	@Tmp_DailySummary AS TABLE (
				L				TINYINT
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
			,	PRIMARY KEY CLUSTERED (L, gameTypeId, currency, isCash)
			);

	DECLARE	@Exchanges AS TABLE (
				currency		NVARCHAR(50)
			,	code			VARCHAR(3)
			,	PRIMARY KEY CLUSTERED (currency)
			)

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
						L				TINYINT
					,	gameId			INT
					,	gameTypeId		INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	isCash			TINYINT
					,	betCount		INT
					,	stake			DECIMAL(19,4)
					,	payOut			DECIMAL(19,4)
					,	PRIMARY KEY CLUSTERED (L, gameTypeId, currency, isCash)
					);

	-- List of Ls --
	INSERT INTO	@Ls
			(L, isExpanded, isCash, isDone)
	VALUES	(2,          1,      1,      0)
		,	(3,          1,   NULL,      0)
		;

	-- List of currencies --
	INSERT INTO	@Exchanges (currency, code)
	EXECUTE	dbr.OW_Exchanges;

	BEGIN;	-- OW --
		INSERT INTO	#OW_DailySummary (gameTypeId, gameType, currency, isCash, phienCount, betCount, stake, payOut)
		EXECUTE	dbr.OW_DailySummary @VendorId, @ReportDate;
		RAISERROR(N'\
[INFO]  Executed on OW - V%d.', 0, 0, @VendorId) WITH NOWAIT;
	END;	-- OW --

	BEGIN;	-- SB --
		UPDATE	@Ls
		SET		isDone = 0;

		WHILE	EXISTS (SELECT 1 FROM @Ls WHERE isDone = 0)
		BEGIN;
			UPDATE	TOP(1)
					@Ls
			SET		@L		= L
				,	@isCash	= isCash
				,	isDone	= 1
			WHERE	isDone = 0;

			DELETE	@Tmp_DailySummary;
			INSERT INTO	@Tmp_DailySummary (L, gameTypeId, gameId, gameType, currency, isCash, betCount, stake, payOut)
			EXECUTE	dbr.SB_DailySummary @L, 1, @ReportDate;

			MERGE INTO	#DS_DailySummary AS ds
			USING		@Tmp_DailySummary AS tmp
					ON	ds.L = 0
					AND	COALESCE(NULLIF(ds.isCash, 2), @isCash, 2) = COALESCE(NULLIF(tmp.isCash, 2), @isCash, 2)
					AND	ds.gameTypeId = tmp.gameTypeId
					AND	ds.currency = tmp.currency
			WHEN MATCHED THEN
				UPDATE
				SET	ds.betCount += tmp.betCount
				,	ds.stake += tmp.stake
				,	ds.payOut += tmp.payOut
			WHEN NOT MATCHED THEN
				INSERT	( L,     gameTypeId,     gameId,     gameType,     currency,                     isCash                 ,     betCount,     stake,     payOut)
				VALUES	( 0, tmp.gameTypeId, tmp.gameId, tmp.gameType, tmp.currency, COALESCE(NULLIF(tmp.isCash, 2), @isCash, 2), tmp.betCount, tmp.stake, tmp.payOut)
			;
			RAISERROR(N'\
[INFO]  Executed on L%d.', 0, 0, @L) WITH NOWAIT;
		END;
	END;	-- SB --

	-- Reuse @Tmp_DailySummary for checking mismatch --
	DELETE	@Tmp_DailySummary;
	INSERT INTO	@Tmp_DailySummary (L, gameTypeId, gameId, gameType, currency, isCash, betCount, stake, winLost)
	SELECT	[L]				= ISNULL(sb.L, 0)
		,	[gameTypeId]	= ISNULL(ow.gameTypeId, sb.gameTypeId)
		,	[gameId]		= ISNULL(sb.gameId, 0)
		,	[gameType]		= ISNULL(ow.gameType, sb.gameType)
		,	[currency]		= ISNULL(ow.currency, sb.currency)
		,	[isCash]		= ISNULL(ow.isCash, sb.isCash)
		,	[betCount]		= ISNULL(ow.betCount, 0) - ISNULL(sb.betCount, 0)
		,	[stake]			= ISNULL(ow.stake, 0) -ISNULL(sb.stake, 0)
		,	[winLost]		= ISNULL(ow.stake - ow.payOut, 0) - ISNULL(sb.stake - sb.payOut, 0)
	FROM			#OW_DailySummary AS ow
	FULL OUTER JOIN	#DS_DailySummary AS sb
				ON	ow.gameTypeId = sb.gameTypeId
				AND	ow.currency = sb.currency
				AND	ow.isCash = sb.isCash
	WHERE	COALESCE(ow.currency, sb.currency, N'') <> 'UUS'
		AND	ISNULL(ow.gameTypeId, sb.gameTypeId) NOT IN (3898)
		AND	(	ISNULL(ow.betCount, 0) <> ISNULL(sb.betCount, 0)
			OR	ISNULL(ow.stake, 0) <> ISNULL(sb.stake, 0)
			OR	ISNULL(ow.payOut, 0) <> ISNULL(sb.payOut, 0)
			);

	IF	EXISTS (SELECT 1 FROM @Tmp_DailySummary)
	BEGIN;	-- TRUE - Has mismatch --
		SELECT	@Status = N'MISMATCH';

		WHILE	EXISTS (SELECT 1 FROM @Tmp_DailySummary)
		BEGIN;
			SELECT	TOP(1)
					@L			= L
				,	@GameId		= gameId
				,	@GameType	= gameType
				,	@GameTypeId	= gameTypeId
			FROM	@Tmp_DailySummary
			ORDER BY L, gameId;

			SELECT	@Title		= @Status + N'] [vGaming Summary ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23)
				,	@Message	= CONCAT_WS(@NL
								,	CONCAT(N'[vG', @L, N' (', @gameTypeId, N'.', @gameId, N')] ', @GameType, N': (BC|TO|WL)')
								,	STRING_AGG(
										CONCAT(
											N'[', currency, N' (', CASE isCash WHEN 0 THEN N'CRE' WHEN 1 THEN N'DEP' WHEN 2 THEN N'null' ELSE N'invalid' END, N')] '
										,	CONCAT_WS(N'|'
											,	FORMAT(CAST(betCount AS MONEY), N'#,##0.##')
											,	FORMAT(CAST(stake AS MONEY), N'#,##0.##')
											,	FORMAT(CAST(winLost AS MONEY), N'#,##0.##')
											)
										)
									,	@NL
									) WITHIN GROUP (ORDER BY currency)
								)
			FROM	@Tmp_DailySummary
			WHERE	L = @L
				AND	gameId = @GameId;
			EXECUTE	Letstalk.SendNotification @Message, @Title, @isTest;

			SELECT	@Message	= CONCAT_WS(@NL
								,	CONCAT(N'[', @Status, N'] [vGaming Summary ', CONVERT(NVARCHAR(MAX), @ReportDate, 23), N']  ')
								,	CONCAT(N'[vG', @L, N' (', @gameTypeId, N'.', @gameId, N')] ', @GameType, N': (BC|TO|WL)  ')
								,	STRING_AGG(
										CONCAT(
											N'[', currency, N' (', CASE isCash WHEN 0 THEN N'CRE' WHEN 1 THEN N'DEP' WHEN 2 THEN N'null' ELSE N'invalid' END, N')] '
										,	CONCAT_WS(N'|'
											,	FORMAT(CAST(betCount AS MONEY), N'#,##0.##')
											,	FORMAT(CAST(stake AS MONEY), N'#,##0.##')
											,	FORMAT(CAST(winLost AS MONEY), N'#,##0.##')
											)
										)
									,	@NL
								)
								)
			FROM	@Tmp_DailySummary
			WHERE	L = @L
				AND	gameId = @GameId;
			EXECUTE	Noti.SendNotification @Message, @isTest;

			DELETE	@Tmp_DailySummary
			WHERE	L = @L
				AND	gameId = @GameId;
		END;
	END;	-- TRUE - Has mismatch --

	BEGIN;	-- Summary --
		SELECT	@Title		= @Status + N'] [vGaming Summary ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23)
			,	@Message	= STRING_AGG(
								g.str
							,	@NL
							)
		FROM	(
			SELECT	[str]	= CONCAT_WS(@NL
							,	N'vG:  '
							,	STRING_AGG(c.str, @NL) WITHIN GROUP (ORDER BY c.grp)
							)
			FROM		(
				SELECT	[grp]	= grp.CurGrp
					,	[str]	= CONCAT_WS(@NL
								,	CONCAT(N'  ', grp.CurGrp)
								,	CONCAT(N'    - BC: ', FORMAT(SUM(CAST(sb.betCount AS MONEY)), N'#,##0.##'))
								,	CONCAT(N'    - TO: ', FORMAT(SUM(CAST(sb.stake AS MONEY)), N'#,##0.##'))
								,	CONCAT(N'    - WL: ', FORMAT(SUM(CAST(sb.stake - sb.payOut AS MONEY)), N'#,##0.##'))
								)
				FROM		#DS_DailySummary AS sb
				LEFT JOIN	@Exchanges AS e
						ON	sb.currency = e.currency
				CROSS APPLY	(
					SELECT	[currency]	= ISNULL(e.code, sb.currency)
				) AS ex
				CROSS APPLY	(
					SELECT	[CurGrp]	= N'(' + CASE sb.isCash WHEN 0 THEN N'Cre' WHEN 1 THEN N'Dep' WHEN 2 THEN N'nul' ELSE N'***' END + N') ' +  UPPER(ex.currency)
				) AS grp
				WHERE	ex.currency <> 'UUS'
				GROUP BY grp.CurGrp
			) AS c
		) AS g;
		EXECUTE	Letstalk.SendNotification @Message, @Title, @isTest;

		SELECT	@Message	= CONCAT_WS(@NL
							,	CONCAT(N'[', @Status, N'] [vGaming Summary ', CONVERT(NVARCHAR(MAX), @ReportDate, 23), N']')
							,	STRING_AGG(
									g.str
								,	@NL
								)
							)
		FROM	(
			SELECT	[str]	= CONCAT_WS(@NL
							,	N'vG:  '
							,	STRING_AGG(c.str, @NL) WITHIN GROUP (ORDER BY c.grp)
							)
			FROM		(
				SELECT	[grp]	= grp.CurGrp
					,	[str]	= CONCAT_WS(@NL
								,	CONCAT(N'  `', grp.CurGrp, N'`')
								,	CONCAT(N'    - BC:  `', FORMAT(SUM(CAST(sb.betCount AS MONEY)), N'#,##0.##'), N'`')
								,	CONCAT(N'    - TO:  `', FORMAT(SUM(CAST(sb.stake AS MONEY)), N'#,##0.##'), N'`')
								,	CONCAT(N'    - WL:  `', FORMAT(SUM(CAST(sb.stake - sb.payOut AS MONEY)), N'#,##0.##'), N'`')
								)
				FROM		#DS_DailySummary AS sb
				LEFT JOIN	@Exchanges AS e
						ON	sb.currency = e.currency
				CROSS APPLY	(
					SELECT	[currency]	= ISNULL(e.code, sb.currency)
				) AS ex
				CROSS APPLY	(
					SELECT	[CurGrp]	= N'(' + CASE sb.isCash WHEN 0 THEN N'Cre' WHEN 1 THEN N'Dep' WHEN 2 THEN N'nul' ELSE N'***' END + N') ' +  UPPER(ex.currency)
				) AS grp
				WHERE	ex.currency <> 'UUS'
				GROUP BY grp.CurGrp
			) AS c
		) AS g;
		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;	-- Summary --
END;
GO
ALTER PROCEDURE	vGaming.DailySummaryReport_Wrapper
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220624@Billy
	Location:		DBSABA.SabaDB
	Description:	Daily Summary Report Wrapper - No error execution
					Compare Daily Summary for vGaming then send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday
		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var3:				[optional]		- The title for error message
				<DEFAULT>	NULL			- Default title

	Version:	1.0.0
	Revision:
		- [1.0.0]	20220624@Billy		Release vGaming.DailySummaryReport_Wrapper
		- [0.0.1]	20220624@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	vGaming.DailySummaryReport @Var1, @Var2;
	END TRY BEGIN CATCH;
		DECLARE	@Title			NVARCHAR(128)	= CONVERT(NVARCHAR(128), @Var3)
			,	@ErrNumber		INT				= ERROR_NUMBER()
			,	@ErrSeverity	INT				= ERROR_SEVERITY()
			,	@ErrState		INT				= ERROR_STATE()
			,	@ErrProcedure	NVARCHAR(128)	= ERROR_PROCEDURE()
			,	@ErrLine		INT				= ERROR_LINE()
			,	@ErrMessage		NVARCHAR(MAX)	= ERROR_MESSAGE()
			,	@Server			NVARCHAR(128)	= PUBLISHINGSERVERNAME()
			,	@Database		NVARCHAR(128)	= DB_NAME()
			,	@isTest			BIT				= CONVERT(BIT, @Var2)
			;
		EXECUTE	SysHealth.SendError
					@Title			= @Title
				,	@ErrorNumber	= @ErrNumber
				,	@ErrorSeverity	= @ErrSeverity
				,	@ErrorState		= @ErrState
				,	@ErrorProcedure	= @ErrProcedure
				,	@ErrorLine		= @ErrLine
				,	@ErrorMessage	= @ErrMessage
				,	@Server			= @Server
				,	@Database		= @Database
				,	@isTest			= @isTest
				;
	END CATCH;
END;
GO
EXECUTE	vGaming.DailySummaryReport_Wrapper NULL, NULL, N'Adhoc Test';
GO
