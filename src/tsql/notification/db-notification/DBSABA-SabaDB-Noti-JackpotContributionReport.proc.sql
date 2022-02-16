USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'Noti.JackpotContributionReport'
	,	@Version	SYSNAME		= N'1.2.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	Noti.JackpotContributionReport
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210324@Billy
	Location:		DBSABA.SabaDB
	Description:	Compare Jackpot related result between OW and SB then send result via Notification Channel

	Parameters:
		@Var1				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

		@Var2:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing

	Version:	1.2.1
	Revision:
		- [1.2.1]	20211015@Billy		Configure jackpot contribution rate value
		- [1.2.0]	20210806@Billy		Migrate SC2 to vG2
		- [1.1.0]	20210617@Billy		Update query to match with new BI schema
		- [1.0.0]	20210324@Billy		Release Noti.JackpotContributionReport
		- [0.0.1]	20210324@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
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

	DECLARE	@VendorId		INT 			= 66
		,	@Bettype		INT				= 3898
		,	@Status			NVARCHAR(128)	= N'OK'
		;

	IF	NOT (DATEDIFF(DAY, @ReportDate, GETUTCDATE()) BETWEEN 1 AND 7)
		RETURN;

	DECLARE	@OW_Query		NVARCHAR(MAX)
		,	@OW_Param		NVARCHAR(MAX)
		,	@DS_Query		NVARCHAR(MAX)
		;

	DECLARE	@L				INT
		,	@GameId			INT
		,	@GameType		NVARCHAR(128)
		,	@GameTypeId		INT
		,	@Message		NVARCHAR(MAX)
		,	@Title			NVARCHAR(512)
		;

	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	isExpanded		BIT
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (L)
			);

	DECLARE	@Tmp_JPContribution AS TABLE (
				L				TINYINT
			,	gameTypeId		INT
			,	gameId			INT
			,	gameType		NVARCHAR(128)
			,	currency		VARCHAR(10)
			,	JPCont			DECIMAL(19,4)
			,	PRIMARY KEY CLUSTERED (L, gameTypeId, gameId, currency)
			);

	CREATE TABLE	#OW_JPContribution (
						gameTypeId		INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	custCount		INT
					,	JPCont			DECIMAL(19,4)
					,	PRIMARY KEY CLUSTERED (gameTypeId, currency)
					);

	CREATE TABLE	#DS_JPContribution (
						L				TINYINT
					,	gameId			INT
					,	gameTypeId		INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	JPCont			DECIMAL(19,4)
					,	PRIMARY KEY CLUSTERED (L, gameTypeId, gameId, currency)
					);

	-- List of Ls --
	INSERT INTO	@Ls
			(L, isExpanded, isDone)
	VALUES	( 2,          0,      0)
		;

	-- OW Query --
	BEGIN;
		SELECT	@OW_Query = N'';
		SELECT	@OW_Query += N'\
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT	[gameTypeId]	= b.gameId
	,	[gameType]		= g.typenamee
	,	[currency]		= b.CurrencyName
	,	[JPCont]		= SUM(-b.awinlost)
FROM		dbo.bettransRnG AS b WITH (NOLOCK)
INNER JOIN	dbo.bettype AS g WITH (NOLOCK)
		ON	b.gameId = g.typeid
WHERE	b.vendorID = @VendorId
	AND	b.gameID = @Bettype
	AND	b.Transdate3rd >= @ReportDate
	AND	b.Transdate3rd < DATEADD(DAY, 1, @ReportDate)
	AND	b.statusID NOT IN (101, 102, 0) -- Reject, Void, running
	AND	b.custid <> 0 -- Merged Tickets
GROUP BY b.gameId, g.typenamee, b.CurrencyName
OPTION (RECOMPILE);
';

		SELECT	@OW_Param = N'';
		SELECT	@OW_Param += N'@VendorId INT, @Bettype INT, @ReportDate DATETIME';

		INSERT INTO	#OW_JPContribution (gameTypeId, gameType, currency, JPCont)
		EXECUTE	DB061KBT.bodb02.sys.sp_executesql @OW_Query, @OW_Param, @VendorId, @Bettype, @ReportDate;

		RAISERROR('', 0, 0) WITH NOWAIT;
	END;

	SELECT	@DS_Query = N'';
	SELECT	@DS_Query += N'\
SELECT	0 AS L
	,	' + CAST(@Bettype AS NVARCHAR(MAX)) + N' AS gameTypeId
	,	cfg.gameId AS gameId
	,	cfg.nameEN AS gameType
	,	IFNULL(ds.currency, "null") AS currency
	,	ds.stake * IFNULL(cfg.jpCont, 0) AS JPCont
FROM		summary.daily_summaries AS ds
INNER JOIN	summary.game_summary_config AS cfg
		ON	ds.gameId = cfg.gameId
WHERE	cfg.groupName = "Slots"
	AND	ds.time >= "' + CONVERT(NVARCHAR(MAX), @ReportDate, 127) + N'"
	AND	ds.time < "' + CONVERT(NVARCHAR(MAX), DATEADD(DAY, 1, @ReportDate), 127) + N'"
';

	BEGIN;
		UPDATE	@Ls
		SET		isDone = 0;

		WHILE	EXISTS (SELECT 1 FROM @Ls WHERE isDone = 0)
		BEGIN;
			UPDATE	TOP(1)
					@Ls
			SET		@L = L
				,	isDone = 1
			WHERE	isDone = 0;

			DELETE	@Tmp_JPContribution;
			INSERT INTO	@Tmp_JPContribution (L, gameTypeId, gameId, gameType, currency, JPCont)
			EXECUTE	base.ExecuteSabaQuery @DS_Query, @L, 0, 1;

			MERGE INTO	#DS_JPContribution AS ds
			USING		@Tmp_JPContribution AS tmp
					ON	ds.L = @L
					AND	ds.gameTypeId = tmp.gameTypeId
					AND	ds.currency = tmp.currency
			WHEN MATCHED THEN
				UPDATE
				SET	ds.JPCont += tmp.JPCont
			WHEN NOT MATCHED THEN
				INSERT	( L,     gameTypeId,     gameId,     gameType,     currency,     JPCont)
				VALUES	(@L, tmp.gameTypeId, tmp.gameId, tmp.gameType, tmp.currency, tmp.JPCont)
			;
			RAISERROR('Executed on L%d.', 0, 0, @L) WITH NOWAIT;
		END;
	END;

	-- Reuse @Tmp_JPContribution for checking mismatch --
	DELETE	@Tmp_JPContribution;
	INSERT INTO	@Tmp_JPContribution (L, gameTypeId, gameId, gameType, currency, JPCont)
	SELECT	[L]				= ISNULL(sb.L, 0)
		,	[gameTypeId]	= ISNULL(ow.gameTypeId, sb.gameTypeId)
		,	[gameId]		= 0
		,	[gameType]		= ow.gameType
		,	[currency]		= ISNULL(ow.currency, sb.currency)
		,	[JPCont]		= ISNULL(ow.JPCont, 0) - ISNULL(sb.JPCont, 0)
	FROM			#OW_JPContribution AS ow
	FULL OUTER JOIN	(
		SELECT	ds.L, ds.gameTypeId, ds.currency, [JPCont] = SUM(ds.JPCont)
		FROM	#DS_JPContribution AS ds
		GROUP BY ds.L, ds.gameTypeId, ds.currency
	) AS sb
				ON	ow.gameTypeId = sb.gameTypeId
				AND	ow.currency = sb.currency
	WHERE	COALESCE(ow.currency, sb.currency) <> 'UUS'
		AND	(	ISNULL(ow.JPCont, 0) <> ISNULL(sb.JPCont, 0)
			);

	IF	EXISTS (SELECT 1 FROM @Tmp_JPContribution)
	-- TRUE - Has mismatch --
	BEGIN;
		SELECT	@Status = N'MISMATCH';

		WHILE	EXISTS (SELECT 1 FROM @Tmp_JPContribution)
		BEGIN;
			SELECT	TOP(1)
					@L			= L
				,	@GameId		= gameId
				,	@GameType	= gameType
				,	@GameTypeId	= gameTypeId
			FROM	@Tmp_JPContribution
			ORDER BY L, gameId;

			SELECT	@Title		= @Status + N'] [Jackpot Contribution ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23)
				,	@Message	= N'[L' + CONVERT(NVARCHAR(MAX), @L) + N' (' + CONVERT(NVARCHAR(MAX), @gameTypeId) + N'.' + CONVERT(NVARCHAR(MAX), @gameId) + N')] ' + @GameType + N': (JC)' + msg.str
			FROM	(
				SELECT	N'
[' + currency + N']'
+ N' ' + REPLACE(CONVERT(NVARCHAR(MAX), CAST(JPCont AS MONEY), 2), '.0000', '')
				FROM	@Tmp_JPContribution
				WHERE	L = @L
					AND	gameId = @GameId
				ORDER BY currency
				FOR XML PATH ('')
				,	TYPE
			) AS xmsg(xml)
			CROSS APPLY	(
				SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
			) AS msg(str);
			EXECUTE	Letstalk.SendNotification @Message, @Title, @isTest;

			SELECT	@Message = N'\\\[' + @Status + N'\] \\\[Jackpot Contribution ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23) + N'\]  
\\\[L' + CONVERT(NVARCHAR(MAX), @L) + N' \(' + CONVERT(NVARCHAR(MAX), @gameTypeId) + N'.' + CONVERT(NVARCHAR(MAX), @gameId) + N'\)\] ' + @GameType + N': \(JC\)'
							 + msg.str
			FROM	(
				SELECT	N'  
\\\[' + currency + N'\]'
+ N' ' + REPLACE(CONVERT(NVARCHAR(MAX), CAST(JPCont AS MONEY), 2), '.0000', '')
				FROM	@Tmp_JPContribution
				WHERE	L = @L
					AND	gameId = @GameId
				ORDER BY currency
				FOR XML PATH ('')
				,	TYPE
			) AS xmsg(xml)
			CROSS APPLY	(
				SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
			) AS msg(str);
			EXECUTE	Noti.SendNotification @Message, @isTest;

			DELETE	@Tmp_JPContribution
			WHERE	L = @L
				AND	gameId = @GameId;
		END;
	END;


	BEGIN;
		SELECT	@Title		= @Status + N'] [Jackpot Contribution ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23)
			,	@Message	= msg.str
		FROM	(
			SELECT	N'

L' + CONVERT(NVARCHAR(MAX), dsb.L) + N':' + c.str
			FROM	(
				SELECT	L, isExpanded
				FROM	@Ls
			) AS dsb
			CROSS APPLY	(
				SELECT	N'
    ' + grp.CurGrp + N'
      - JC: ' + CONVERT(NVARCHAR(MAX), SUM(CAST(sb.JPCont AS MONEY)), 2)
				FROM		#DS_JPContribution AS sb
				CROSS APPLY	(
					SELECT	[CurGrp]	= CASE dsb.isExpanded WHEN 1 THEN UPPER(sb.currency) ELSE N'Total' END
				) AS grp
				WHERE	sb.currency <> 'UUS'
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

		SELECT	@Message	= N'\\\[' + @Status + N'\] \\\[Jackpot Contribution ' + CONVERT(NVARCHAR(MAX), @ReportDate, 23) + N'\]' + msg.str
		FROM	(
			SELECT	N'  

---
L' + CONVERT(NVARCHAR(MAX), dsb.L) + N':' + c.str
			FROM	(
				SELECT	L, isExpanded
				FROM	@Ls
			) AS dsb
			CROSS APPLY	(
				SELECT	N'  
    `' + grp.CurGrp + N'`  
      \- JC: ' + CONVERT(NVARCHAR(MAX), SUM(CAST(sb.JPCont AS MONEY)), 2)
				FROM		#DS_JPContribution AS sb
				CROSS APPLY	(
					SELECT	[CurGrp]	= CASE dsb.isExpanded WHEN 1 THEN UPPER(sb.currency) ELSE N'Total' END
				) AS grp
				WHERE	sb.currency <> 'UUS'
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
	END;
END;
GO
EXECUTE	Noti.JackpotContributionReport;
GO
