USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.L_TicketDetail'
	,	@Version	SYSNAME		= N'2.0.2'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.L_TicketDetail
					@fromTime		DATETIME
				,	@toTime			DATETIME
				,	@gameTypeId		INT
WITH ENCRYPTION
AS
/*
	Creator:		20230515@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Ticket Detail data from L database

	Parameters:
		@fromTime			[REQUIRED]		- The start time of data that will be selected. The time is in UTC timezone.

		@toTime				[REQUIRED]		- The end time of data that will be selected. The time is in UTC timezone.

		@gameTypeId			[REQUIRED]		- The type id of game that will be selected

	Version:	2.0.2
	Revision:
		- [2.0.2]	20240304@Billy		Update playerId filter
		- [2.0.1]	20230712@Billy		Special rule for blackjack game
		- [2.0.0]	20230529@Billy		Rename parameters
		- [1.0.0]	20210923@Billy		Release dbr.SB_TicketDetails
		- [0.0.1]	20210923@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		,	@L				TINYINT
		,	@VendorId		INT
		,	@Name			NVARCHAR(128)
		;

	SELECT	TOP(1)
			@L			= m.L
		,	@VendorId	= m.vendorId
		,	@Name		= m.baseName
	FROM	dbr.tf_GameTypeMapping(NULL, NULL, NULL, @gameTypeId) AS m;

	DECLARE	@Query		NVARCHAR(MAX);

	DECLARE	@roundField	NVARCHAR(128)	= IIF(@gameTypeId IN (1634, 3820, 1684, 3876), 'id', IIF(@gameTypeId IN (10801, 10802, 10803, 10804, 10806), 'drawId','roundId'));

	SELECT	@Query = N'';
	SELECT	@Query = CONCAT(@Query, N'\
SELECT	', @gameTypeId, N' AS gameTypeId
	,	b.currency AS currency
	,	b.', @roundField, ' AS roundId
	,	b.playerId AS playerId
	,	b.stake AS turnOver
	,	b.payout - b.stake AS winLost
	,	b.time AS transDate
	,	g.time AS endDate
	,	b.paid AS paid
	,	0 AS freeBet
FROM		minigame.', @Name, N'_rounds AS g
INNER JOIN	minigame.', @Name, N'_bets AS b
		ON	g.id = b.roundId
WHERE	g.time >= "', FORMAT(@fromTime, 'yyyy-MM-ddTHH:mm:ssZ'), N'"
	AND	g.time < "', FORMAT(@toTime, 'yyyy-MM-ddTHH:mm:ssZ'), N'"
	AND	b.playerId IS NOT NULL
')
		;

	EXECUTE	base.Query @Query, @L, 0, 1;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.L_TicketDetail') IS NOT NULL
		DROP TYPE dbr.L_TicketDetail;

	CREATE TYPE	dbr.L_TicketDetail AS TABLE (
		gameTypeId		INT
	,	currency		VARCHAR(16)
	,	roundId			INT
	,	playerId		INT
	,	turnOver		DECIMAL(19,4)
	,	winLost			DECIMAL(19,4)
	,	transDate		DATETIME
	,	endDate			DATETIME
	,	paid			BIT
	,	freeBet			BIT
	,	PRIMARY KEY NONCLUSTERED (gameTypeId, roundId, playerId, transDate)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
DECLARE	@Yesterday 	DATE = DATEADD(DAY, -1, GETUTCDATE())
	,	@Today		DATE = GETUTCDATE();
EXECUTE	dbr.L_TicketDetail @Yesterday, @Today, 1612;
EXECUTE	dbr.L_TicketDetail @Yesterday, @Today, 3802;
