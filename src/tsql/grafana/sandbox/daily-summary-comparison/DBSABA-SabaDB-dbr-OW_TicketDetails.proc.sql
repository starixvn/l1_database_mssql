USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.OW_TicketDetails'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.OW_TicketDetails
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210923@Billy
	Location:		DBSABA.SabaDB
	Description:	Get ticket details from OW database

	Parameters:
		@Var1				[optional]		- The type id of game that will be selected
				<DEFAULT>	NULL			- No data

		@Var2				[optional]		- The date of data that will be selected. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday 00:00:00 AM

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210923@Billy		Release dbr.OW_TicketDetails
		- [0.0.1]	20210923@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@ReportDate		DATETIME
		,	@GameTypeId		INT
		,	@VendorId		INT
		;

	BEGIN TRY; SELECT @GameTypeId = CONVERT(INT     , @Var1); END TRY BEGIN CATCH; SELECT @GameTypeId = NULL; END CATCH;
	BEGIN TRY; SELECT @ReportDate = CONVERT(DATETIME, @Var2); END TRY BEGIN CATCH; SELECT @ReportDate = NULL; END CATCH;

	SELECT	@ReportDate	= CONVERT(DATE, ISNULL(@ReportDate, DATEADD(DAY, -1, GETUTCDATE())))
		;

	SELECT	@VendorId	= m.vendorId
	FROM	dbr.tf_GameTypeMapping(NULL, NULL, @GameTypeId) AS m;


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
	,	[gameType]		= g.typenamee
	,	[currency]		= b.CurrencyName
	,	[phienId]		= b.GameId3rd
	,	[memberId]		= b.custId
	,	[stake]			= b.stake
	,	[winLost]		= b.winlost - b.stake
	,	[transdate]		= b.transDate3rd
	,	[status]		= b.status
	,	[statusId]		= b.statusId
	,	[cnt]			= COUNT(1) OVER(PARTITION BY b.gameId, b.GameId3rd, b.custId)
	,	[freeBet]		= CASE b.productID WHEN 200 THEN 0 WHEN 150 THEN 1 ELSE 0 END
FROM		dbo.bettransRnG AS b WITH (NOLOCK)
INNER JOIN	dbo.bettype AS g WITH (NOLOCK)
		ON	b.gameId = g.typeid
WHERE	b.vendorID = @VendorId
	AND	b.Transdate3rd >= @ReportDate
	AND	b.Transdate3rd < DATEADD(DAY, 1, @ReportDate)
	AND	b.gameId = @GameTypeId
OPTION (RECOMPILE);
'
		,	@Param = N'@VendorId INT, @ReportDate DATETIME, @GameTypeId INT'
		;

	EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param, @VendorId, @ReportDate, @GameTypeId;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.OW_TicketDetails 1612;
EXECUTE	dbr.OW_TicketDetails 3802;
