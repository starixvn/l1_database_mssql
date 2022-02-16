USE	SabaDB;
DECLARE	@Procedure	SYSNAME		= N'Noti.BetLogSummaryReport'
	,	@Version	SYSNAME		= N'1.1.1'
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

	Version:	1.1.1
	Revision:
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

	BEGIN TRY;
		SELECT	@ReportDate		= CONVERT(DATETIME, @Var1);
	END TRY BEGIN CATCH;
		SELECT	@ReportDate		= NULL;
	END CATCH;

	BEGIN TRY;
		SELECT	@isTest			= CONVERT(BIT, @Var2);
	END TRY BEGIN CATCH;
		SELECT	@isTest			= NULL;
	END CATCH;

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
	VALUES	( 1, N'ᴄᴏᴄᴏs')
		,	( 2, N'ᴍᴏʙɪ')
		,	( 3, N'ɪɴsᴛᴀɴᴛ')
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
			,	@Message	= msg.str
		FROM	(
			SELECT	N'

' + dsb.name + CONVERT(NVARCHAR(MAX), dsb.L) + N':' + c.str
			FROM	(
				SELECT	L, name, isExpanded
				FROM	@Ls
			) AS dsb
			CROSS APPLY	(
				SELECT	N'
    ' + grp.CurGrp + N'
      - RC: ' + REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.requestCount AS MONEY)), 1), '.00', '') + N'
      - BC: ' + REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.betCount AS MONEY)), 1), '.00', '') + N'
      - TO: ' + CONVERT(NVARCHAR(MAX), SUM(CAST(sb.turnOver AS MONEY)), 1)
				FROM		#DS_DailySummary AS sb
				LEFT JOIN	@Exchanges AS e
						ON	sb.currency = e.currency
				CROSS APPLY	(
					SELECT	[currency]	= ISNULL(e.code, sb.currency)
				) AS ex
				CROSS APPLY	(
					SELECT	TOP(1)
							[CurGrp]	= CASE dsb.isExpanded
											WHEN 1 THEN N'(' + _sys.name + N') ' +  UPPER(ex.currency)
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
					AND	sb.L = dsb.L
				GROUP BY grp.CurGrp
				ORDER BY grp.CurGrp
				FOR XML PATH ('')
				,	TYPE
			) AS xc(xml)
			CROSS APPLY	(
				SELECT	xc.xml.value('.', 'NVARCHAR(MAX)')
			) AS c(str)
			ORDER BY dsb.L
			FOR XML PATH ('')
			,	TYPE
		) AS xmsg(xml)
		CROSS APPLY	(
			SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
		) AS msg(str);
		EXECUTE	Letstalk.SendNotification @Message, @Title, @isTest;

		SELECT	@Message	= N'\\\[BetLog Summary ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23) + N'\]' + msg.str
		FROM	(
			SELECT	N'  

---
' + dsb.name + CONVERT(NVARCHAR(MAX), dsb.L) + N':' + c.str
			FROM	(
				SELECT	L, name, isExpanded
				FROM	@Ls
			) AS dsb
			CROSS APPLY	(
				SELECT	N'  
    `' + grp.CurGrp + N'`  
      \- RC: ' + REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.requestCount AS MONEY)), 1), '.00', '') + N'  
      \- BC: ' + REPLACE(CONVERT(NVARCHAR(MAX), SUM(CAST(sb.betCount AS MONEY)), 1), '.00', '') + N'  
      \- TO: ' + CONVERT(NVARCHAR(MAX), SUM(CAST(sb.turnOver AS MONEY)), 1)
				FROM		#DS_DailySummary AS sb
				LEFT JOIN	@Exchanges AS e
						ON	sb.currency = e.currency
				CROSS APPLY	(
					SELECT	[currency]	= ISNULL(e.code, sb.currency)
				) AS ex
				CROSS APPLY	(
					SELECT	TOP(1)
							[CurGrp]	= CASE dsb.isExpanded
											WHEN 1 THEN N'(' + _sys.name + N') ' +  UPPER(ex.currency)
											ELSE N'(' + _sys.name + N') Total'
										  END
					FROM	(
						SELECT	id, name
						FROM	@Systems
						WHERE	id = sb.sys
						UNION ALL
						SELECT	NULL, N'***'
					) AS _sys
					ORDER BY id DESC
				) AS grp
				WHERE	ex.currency <> 'UUS'
					AND	sb.L = dsb.L
				GROUP BY grp.CurGrp
				ORDER BY grp.CurGrp
				FOR XML PATH ('')
				,	TYPE
			) AS xc(xml)
			CROSS APPLY	(
				SELECT	xc.xml.value('.', 'NVARCHAR(MAX)')
			) AS c(str)
			ORDER BY dsb.L
			FOR XML PATH ('')
			,	TYPE
		) AS xmsg(xml)
		CROSS APPLY	(
			SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
		) AS msg(str);
		EXECUTE	Noti.SendNotification @Message, @isTest;
	END;	-- Summary --
END;
GO
EXECUTE	Noti.BetLogSummaryReport;
GO
