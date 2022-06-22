USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'gfn.DailySummaryComparisonDetails'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	gfn.DailySummaryComparisonDetails
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210923@Billy
	Location:		DBSABA.SabaDB
	Description:	Compare Daily Summary details result between OW and SB then show result on Grafana

	Parameters:
		@Var1				[optional]		- The type id of game that will be queried.
				<DEFAULT>	NULL			- No data

		@Var2				[optional]		- The date of data that will be compared. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210923@Billy		Release gfn.DailySummaryComparisonDetails
		- [0.0.1]	20210923@Billy		Initital
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@ReportDate		DATETIME
		,	@GameTypeId		INT
		;

	BEGIN TRY; SELECT @GameTypeId = CONVERT(INT     , @Var1); END TRY BEGIN CATCH; SELECT @GameTypeId = NULL; END CATCH;
	BEGIN TRY; SELECT @ReportDate = CONVERT(DATETIME, @Var2); END TRY BEGIN CATCH; SELECT @ReportDate = NULL; END CATCH;

	SELECT	@ReportDate		= ISNULL(@ReportDate, ISNULL(@ReportDate, CAST(DATEADD(DAY, -1, GETUTCDATE()) AS DATE)))
		,	@GameTypeId		= ISNULL(@GameTypeId, 0)
		;

	IF	NOT (DATEDIFF(DAY, @ReportDate, GETUTCDATE()) BETWEEN 1 AND 7)
	BEGIN;
		RAISERROR(N'\
[ERR]   @ReportDate is out of range', 0, 0) WITH NOWAIT;
		RETURN;
	END;

	DECLARE	@VendorId		INT
		,	@Name			NVARCHAR(128)
		,	@L				TINYINT
		;

	SELECT	@VendorId	= m.vendorId
		,	@Name		= m.baseName
	FROM	dbr.tf_GameTypeMapping(NULL, NULL, @GameTypeId) AS m;

	IF	@Name IS NULL
	BEGIN;
		RAISERROR(N'\
[ERR]   Invalid @GameTypeId', 0, 0) WITH NOWAIT;
		RETURN;
	END;

	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	vendorId		INT
			,	isDone			BIT
			,	PRIMARY KEY CLUSTERED (L)
			);

	CREATE TABLE	#OW_TicketDetails (
						gameTypeId		INT
					,	gameType		NVARCHAR(128)
					,	currency		VARCHAR(10)
					,	phienId			INT
					,	memberId		INT
					,	stake			DECIMAL(19,4)
					,	winLost			DECIMAL(19,4)
					,	transdate		DATETIME
					,	status			VARCHAR(10)
					,	statusId		SMALLINT
					,	cnt				SMALLINT
					,	freeBet			BIT
					,	PRIMARY KEY CLUSTERED (gameTypeId, phienId, memberId, transdate, currency, freeBet)
					);

	CREATE TABLE	#SB_TicketDetails (
						L				TINYINT			DEFAULT(0)
					,	gameTypeId		INT
					,	currency		VARCHAR(10)
					,	phienId			INT
					,	memberId		INT
					,	stake			DECIMAL(19,4)
					,	winLost			DECIMAL(19,4)
					,	transdate		DATETIME
					,	endgame			DATETIME
					,	thanhtoan		BIT
					,	freeBet			BIT
					,	PRIMARY KEY CLUSTERED (L, gameTypeId, phienId, memberId, freeBet)
					);

	-- List of Ls --
	INSERT INTO	@Ls
			(L, vendorId, isDone)
	VALUES	(1,       42,      0)
		,	(2,       66,      0)
		,	(3,       66,      0)
		;

	BEGIN;	-- OW --
		INSERT INTO	#OW_TicketDetails (gameTypeId, gameType, currency, phienId, memberId, stake, winLost, transdate, status, statusId, cnt, freeBet)
		EXECUTE	dbr.OW_TicketDetails @GameTypeId;
		RAISERROR('Executed on OW - #%d.', 0, 0, @GameTypeId) WITH NOWAIT;
	END;	-- OW --

	BEGIN;	-- SB --
		UPDATE	@Ls
		SET		isDone = 0;

		WHILE	EXISTS (SELECT 1 FROM @Ls WHERE isDone = 0 AND vendorId = @VendorId)
		BEGIN;
			UPDATE	TOP(1)
					@Ls
			SET		@L		= L
				,	isDone	= 1
			WHERE	isDone = 0
				AND	vendorId = @VendorId;

			INSERT INTO	#SB_TicketDetails (gameTypeId, currency, phienId, memberId, stake, winLost, transdate, endgame, thanhtoan, freeBet)
			EXECUTE	dbr.SB_TicketDetails @L, 1, @GameTypeId;

			UPDATE	#SB_TicketDetails
			SET		L = @L
			WHERE	L = 0;

			RAISERROR('Executed on L%d.', 0, 0, @L) WITH NOWAIT;
		END;
	END;	-- SB --

	SELECT	[sᴛᴀᴋᴇ?]			= CASE WHEN ow.stake = sb.stake THEN 1 ELSE 0 END
		,	[ᴡɪɴʟᴏsᴛ?]			= CASE WHEN ow.winLost = sb.winLost THEN 1 ELSE 0 END
		,	[ɢᴀᴍᴇᴛʏᴘᴇ]			= ISNULL(ow.gameTypeId, sb.gameTypeId)
		,	[ᴘʜɪᴇɴ]				= ISNULL(ow.phienId, sb.phienId)
		,	[ᴍᴇᴍʙᴇʀ]			= ISNULL(ow.memberId, sb.memberId)
		,	[¤]					= ISNULL(ow.currency, sb.currency)

		,	[sᴛᴀᴋᴇ «]			= ow.stake
		,	[ᴡɪɴʟᴏsᴛ «]			= ow.winLost
		,	[ᴛʀᴀɴsᴅᴀᴛᴇ «]		= CONVERT(NVARCHAR(MAX), ow.transdate, 127)
		,	[sᴛᴀᴛᴜs «]			= ow.status
		,	[sᴛᴀᴛᴜsɪᴅ «]		= ow.statusId
		,	[ᴄɴᴛ «]				= ow.cnt
		,	[± sᴛᴀᴋᴇ «]			= CASE WHEN ow.stake > sb.stake THEN ow.stake - sb.stake ELSE 0 END
		,	[± ᴡɪɴʟᴏsᴛ «]		= CASE WHEN ow.winLost > sb.winLost THEN ow.winLost - sb.winLost ELSE 0 END
		,	[OW | SB]			= ''
		,	[» ᴡɪɴʟᴏsᴛ ±]		= CASE WHEN sb.winLost > ow.winLost THEN sb.winLost - ow.winLost ELSE 0 END
		,	[» sᴛᴀᴋᴇ ±]			= CASE WHEN sb.stake > ow.stake THEN sb.stake - ow.stake ELSE 0 END
		,	[» sᴛᴀᴋᴇ]			= sb.stake
		,	[» ᴡɪɴʟᴏsᴛ]			= sb.winLost
		,	[» ᴛʀᴀɴsᴅᴀᴛᴇ]		= CONVERT(NVARCHAR(MAX), sb.transdate, 127)
		,	[» ᴇɴᴅɢᴀᴍᴇ]			= CONVERT(NVARCHAR(MAX), sb.endgame, 127)
		,	[» ᴛʜᴀɴʜᴛᴏᴀɴ]		= sb.thanhtoan
	FROM			#OW_TicketDetails AS ow
	FULL OUTER JOIN	#SB_TicketDetails AS sb
				ON	ow.gameTypeId = sb.gameTypeId
				AND	ow.phienId = sb.phienId
				AND	ow.memberId = sb.memberId
				AND	ow.currency = sb.currency
				AND	ow.freeBet = sb.freeBet
	WHERE	(	COALESCE(ow.currency, sb.currency, '') <> 'UUS'
			AND	CASE WHEN ow.stake = sb.stake AND ow.winLost = sb.winLost AND thanhtoan = 1 THEN 1 ELSE 0 END = 0
			)
		OR	ow.cnt > 1
	ORDER BY	CASE WHEN ISNULL(ow.currency, sb.currency) = 'UUS' THEN 1 ELSE 0 END
			,	ow.gameTypeId, sb.gameTypeId
			,	ow.phienId, sb.phienId
			,	ow.memberId, sb.memberId
			,	ow.currency, sb.currency
			,	ow.statusId
			;
END;
GO

EXECUTE	gfn.DailySummaryComparisonDetails 1612;
EXECUTE	gfn.DailySummaryComparisonDetails 3802;
