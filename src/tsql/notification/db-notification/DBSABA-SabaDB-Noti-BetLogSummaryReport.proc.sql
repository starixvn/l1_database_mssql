USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'Noti.BetLogSummaryReport'
	,	@Version	SYSNAME		= N'1.2.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
DECLARE	@Procedure	SYSNAME		= N'Noti.BetLogSummaryReport_Wrapper'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	Noti.BetLogSummaryReport
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210601@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Betlog Summary
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The date of data that will be fetched. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing

	Version:	1.2.1
	Revision:
		- [1.2.1]	20230322@Billy		Add metadata for megakeno
		- [1.2.0]	20220623@Billy		Using SQL Server 2019 syntax
		- [1.1.2]	20220621@Billy		Reformat messages
		- [1.1.1]	20211018@Billy		Group by currency code
		- [1.1.0]	20210812@Billy		Support instant system
		- [1.0.1]	20210722@Billy		Base SP updated for SIT environment support
		- [1.0.0]	20210601@Billy		Release Noti.BetLogSummaryReport - [Gitlab: #058]
		- [0.0.1]	20210601@Billy		Initital - [Gitlab: #058]
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@ReportDate		DATETIME
		,	@isTest			BIT
		;

	BEGIN TRY SELECT @ReportDate = CONVERT(DATETIME, @Var1); END TRY BEGIN CATCH SELECT	@ReportDate = NULL; END CATCH;
	BEGIN TRY SELECT @isTest     = CONVERT(BIT     , @Var2); END TRY BEGIN CATCH SELECT	@isTest     = NULL; END CATCH;

	SELECT	@ReportDate		= ISNULL(@ReportDate, ISNULL(@ReportDate, CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE)))
		,	@isTest			= ISNULL(@isTest, 1)
		;

	IF	NOT (DATEDIFF(DAY, @ReportDate, GETUTCDATE()) BETWEEN 1 AND 7)
	BEGIN;
		RAISERROR(N'\
[ERR]   @ReportDate is out of range', 0, 0) WITH NOWAIT;
		RETURN;
	END;

	DECLARE	@L				INT
		,	@GameId			INT
		,	@GameType		NVARCHAR(128)
		,	@Message		NVARCHAR(MAX)
		,	@Title			NVARCHAR(512)
		;

	DECLARE	@NL				NVARCHAR(10)	= NCHAR(13) + NCHAR(10)

	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	name			NVARCHAR(128)
			,	isExpanded		BIT
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (L)
			);

	DECLARE	@Systems AS TABLE (
				id				TINYINT
			,	name			NVARCHAR(128)
			,	PRIMARY KEY CLUSTERED (id)
			);

	DECLARE	@Exchanges AS TABLE (
				currency		NVARCHAR(50)
			,	code			VARCHAR(3)
			,	PRIMARY KEY CLUSTERED (currency)
			)

	CREATE TABLE	#DS_DailySummary (
						L				TINYINT
					,	gameId			INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	sys				TINYINT
					,	requestCount	INT
					,	betCount		INT
					,	turnOver		DECIMAL(19,4)
					,	PRIMARY KEY CLUSTERED (L, gameId, currency, sys)
					);

	-- List of Ls --
	INSERT INTO	@Ls
			(L,  name, isExpanded, isDone)
	VALUES	(1, N'SC',          0,      0)
		,	(2, N'vG',          0,      0)
		,	(3, N'vG',          1,      0)
		;

	-- List of systems --
	INSERT INTO	@Systems
			(id, name)
	VALUES	( 1, N'`SC`')
		,	( 2, N'`SM`')
		,	( 3, N'`SI`')
		,	( 4, N'`MK`' )
		;

	-- List of currencies --
	INSERT INTO	@Exchanges (currency, code)
	EXECUTE	dbr.OW_Exchanges;

	BEGIN;	-- SB --
		UPDATE	@Ls
		SET		isDone = 0;

		WHILE	EXISTS (SELECT 1 FROM @Ls WHERE isDone = 0)
		BEGIN;
			UPDATE	TOP(1)
					@Ls
			SET		@L		= L
				,	isDone	= 1
			WHERE	isDone	= 0;

			INSERT INTO	#DS_DailySummary (L, gameId, gameType, currency, sys, requestCount, betCount, turnOver)
			EXECUTE	dbr.SB_BetLogSummary @L, 1, @ReportDate;
			RAISERROR('Executed on L%d.', 0, 0, @L) WITH NOWAIT;
		END;
	END;	-- SB --

	BEGIN;	-- Summary --
		SELECT	@Title		= N'BetLog Summary ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23)
			,	@Message	= CONCAT_WS(@NL
							,	N'  (system) currency : RC | BC | TO  '
							,	STRING_AGG(msg.msg, @NL) WITHIN GROUP (ORDER BY msg.l)
							)
		FROM	(
			SELECT	[l]		= l.L
				,	[msg]	= CONCAT(N'---  ', @NL, l.name, l.L, N':  ', @NL, STRING_AGG(lmsg.msg, @NL) WITHIN GROUP (ORDER BY lmsg.grp))
			FROM	@Ls AS l
			CROSS APPLY	(
				SELECT	[grp]	= sb.sys
					,	[msg]	= CONCAT(N'  ',  grp.CurGrp,  N' :  '
								,	CONCAT_WS(N'  |  '
									,	REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.requestCount AS MONEY)), 1), '.00', '')
									,	REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.betCount AS MONEY)), 1), '.00', '')
									,	CONVERT(NVARCHAR(MAX), SUM(CAST(sb.turnOver AS MONEY)), 1)
									)
								,	N'  '
								)
				FROM		#DS_DailySummary AS sb
				LEFT JOIN	@Exchanges AS e
						ON	sb.currency = e.currency
				CROSS APPLY	(
					SELECT	[currency]	= ISNULL(e.code, sb.currency)
				) AS ex
				CROSS APPLY	(
					SELECT	TOP(1)
							[CurGrp]	= CASE l.isExpanded
											WHEN 1 THEN N'(' + _sys.name + N') ' + UPPER(ex.currency)
											ELSE N'(' + _sys.name + N') Total'
											END
					FROM	(
						SELECT	id, name
						FROM	@Systems
						WHERE	id = sb.sys
						UNION
						SELECT	NULL, N'***'
					) AS _sys
					ORDER BY id DESC
				) AS grp
				WHERE	ex.currency <> 'UUS'
					AND	sb.L = l.L
				GROUP BY grp.CurGrp, sb.sys
			) AS lmsg
			GROUP BY l.L, l.name
		) AS msg;
		EXECUTE	Letstalk.SendNotification @Message, @Title, @isTest;

		SELECT	@Message	= CONCAT_WS(@NL
							,	N'\\\[BetLog Summary ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23) + N'\]  '
							,	N'  `(system) currency : RC | BC | TO`  '
							,	STRING_AGG(msg.msg, @NL) WITHIN GROUP (ORDER BY msg.l)
							)
		FROM	(
			SELECT	[l]		= l.L
				,	[msg]	= CONCAT(N'---  ', @NL, l.name, l.L, N':  ', @NL, STRING_AGG(lmsg.msg, @NL) WITHIN GROUP (ORDER BY lmsg.grp))
			FROM	@Ls AS l
			CROSS APPLY	(
				SELECT	[grp]	= grp.CurGrp
					,	[msg]	= CONCAT(N'  ',  grp.CurGrp,  N' :  '
								,	CONCAT_WS(N'  |  '
									,	REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.requestCount AS MONEY)), 1), '.00', '')
									,	REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.betCount AS MONEY)), 1), '.00', '')
									,	CONVERT(NVARCHAR(MAX), SUM(CAST(sb.turnOver AS MONEY)), 1)
									)
								,	N'  '
								)
				FROM		#DS_DailySummary AS sb
				LEFT JOIN	@Exchanges AS e
						ON	sb.currency = e.currency
				CROSS APPLY	(
					SELECT	[currency]	= ISNULL(e.code, sb.currency)
				) AS ex
				CROSS APPLY	(
					SELECT	TOP(1)
							[CurGrp]	= CASE l.isExpanded
											WHEN 1 THEN N'(' + _sys.name + N') ' + UPPER(ex.currency)
											ELSE N'(' + _sys.name + N') Total'
											END
					FROM	(
						SELECT	id, name
						FROM	@Systems
						WHERE	id = sb.sys
						UNION
						SELECT	NULL, N'***'
					) AS _sys
					ORDER BY id DESC
				) AS grp
				WHERE	ex.currency <> 'UUS'
					AND	sb.L = l.L
				GROUP BY grp.CurGrp
			) AS lmsg
			GROUP BY l.L, l.name
		) AS msg;
		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;	-- Summary --
END;
GO
ALTER PROCEDURE	Noti.BetLogSummaryReport_Wrapper
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220623@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Betlog Summary Wrapper - No error execution
					Send result via Noti telegram channel

	Parameters:
		@Var1				[optional]		- The date of data that will be fetched. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday
		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing
		@Var3:				[optional]		- The title for error message
				<DEFAULT>	NULL			- Default title

	Version:	1.0.0
	Revision:
		- [1.0.0]	20220623@Billy		Release Noti.BetLogSummaryReport_Wrapper
		- [0.0.1]	20220623@Billy		Initital
*/
BEGIN;
	BEGIN TRY;
		EXECUTE	Noti.BetLogSummaryReport @Var1, @Var2;
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
EXECUTE	Noti.BetLogSummaryReport_Wrapper NULL, NULL, 'Adhoc Test';
GO
