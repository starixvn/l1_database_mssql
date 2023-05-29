USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.OW_TicketDetail'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.OW_TicketDetail
					@fromTime		DATETIME
				,	@toTime			DATETIME
				,	@gameTypeId		INT
WITH ENCRYPTION
AS
/*
	Creator:		20210923@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Ticket Detail data from OW database

	Parameters:
		@fromTime			[REQUIRED]		- The start time of data that will be selected. The time is in UTC timezone.

		@toTime				[REQUIRED]		- The end time of data that will be selected. The time is in UTC timezone.

		@gameTypeId			[REQUIRED]		- The type id of game that will be selected

	Version:	2.0.0
	Revision:
		- [2.0.0]	20230529@Billy		Rename parameters
		- [1.0.0]	20210923@Billy		Release dbr.OW_TicketDetails
		- [0.0.1]	20210923@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		,	@VendorId		INT
		;

	SELECT	TOP(1)
			@vendorId	= m.vendorId
	FROM	dbr.tf_GameTypeMapping(NULL, NULL, NULL, @GameTypeId) AS m;

	DECLARE	@Query		NVARCHAR(MAX)
		,	@Param		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		,	@Param = N''
		;

	SELECT	@Query += N'\
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT	[gameTypeId]	= b.gameId
	,	[gameName]		= g.typenamee
	,	[currency]		= b.CurrencyName
	,	[roundId]		= b.GameId3rd
	,	[playerId]		= b.custId
	,	[turnOver]		= b.stake
	,	[winLost]		= b.winlost - b.stake
	,	[transDate]		= b.transDate3rd
	,	[status]		= b.status
	,	[statusId]		= b.statusId
	,	[recordCount]	= COUNT(1) OVER(PARTITION BY b.gameId, b.GameId3rd, b.custId)
	,	[freeBet]		= CASE b.productID WHEN 200 THEN 0 WHEN 150 THEN 1 ELSE 0 END
FROM		dbo.bettransRnG AS b WITH (NOLOCK)
INNER JOIN	dbo.bettype AS g WITH (NOLOCK)
		ON	b.gameId = g.typeid
WHERE	b.vendorID = @VendorId
	AND	b.Transdate3rd >= @fromTIme
	AND	b.Transdate3rd < @toTime
	AND	b.gameId = @GameTypeId
OPTION (RECOMPILE);
'
		,	@Param = N'@vendorId SMALLINT, @fromTime DATETIME, @toTime DATETIME, @gameTypeId INT'
		;

	EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param, @vendorId, @fromTime, @toTime, @gameTypeId;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.OW_TicketDetail') IS NOT NULL
		DROP TYPE dbr.OW_TicketDetail;

	CREATE TYPE	dbr.OW_TicketDetail AS TABLE (
		gameTypeId		INT
	,	gameName		NVARCHAR(128)
	,	currency		VARCHAR(16)
	,	roundId			INT
	,	playerId		INT
	,	turnOver		DECIMAL(19,4)
	,	winLost			DECIMAL(19,4)
	,	transDate		DATETIME
	,	status			VARCHAR(16)
	,	statusId		SMALLINT
	,	recordCount		INT
	,	freeBet			BIT
	,	PRIMARY KEY NONCLUSTERED (gameTypeId, roundId, playerId, transDate)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
DECLARE	@Yesterday 	DATE = DATEADD(DAY, -1, GETUTCDATE())
	,	@Today		DATE = GETUTCDATE();
EXECUTE	dbr.OW_TicketDetail @Yesterday, @Today, 1612;
EXECUTE	dbr.OW_TicketDetail @Yesterday, @Today, 3802;
