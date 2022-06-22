USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.OW_DailySummary'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.OW_DailySummary
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210529@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Daily Summary data from OW database

	Parameters:
		@Var1				[optional]		- The id of vendor that will be selected
				<DEFAULT>	NULL			- No data

		@Var2				[optional]		- The date of data that will be selected. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday 00:00:00 AM

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210529@Billy		Release dbr.OW_DailySummary
		- [0.0.1]	20210529@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@ReportDate		DATETIME
		,	@VendorId		INT
		;

	BEGIN TRY; SELECT @VendorId   = CONVERT(INT     , @Var1); END TRY BEGIN CATCH; SELECT @VendorId   = NULL; END CATCH;
	BEGIN TRY; SELECT @ReportDate = CONVERT(DATETIME, @Var2); END TRY BEGIN CATCH; SELECT @ReportDate = NULL; END CATCH;

	SELECT	@ReportDate	= CONVERT(DATE, ISNULL(@ReportDate, DATEADD(DAY, -1, GETUTCDATE())))
		;

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
	,	[isCash]		= ISNULL(s.custid / s.custid, 0)
	,	[phienCount]	= COUNT(DISTINCT b.GameId3rd)
	,	[betCount]		= COUNT(1)
	,	[stake]			= SUM(b.stake)
	,	[payOut]		= SUM(b.winlost)
FROM		dbo.bettransRnG AS b WITH (NOLOCK)
INNER JOIN	dbo.bettype AS g WITH (NOLOCK)
		ON	b.gameId = g.typeid
LEFT JOIN	dbo.Dep_CustSuper AS s WITH (NOLOCK)
		ON	b.srecommend = s.custid
WHERE	b.vendorID = @VendorId
	AND	b.Transdate3rd >= @ReportDate
	AND	b.Transdate3rd < DATEADD(DAY, 1, @ReportDate)
	AND	b.statusID NOT IN (101, 102, 0) -- Reject, Void, running
	AND	b.custid <> 0 -- Merged Tickets
GROUP BY b.gameId, g.typenamee, b.CurrencyName, s.custid / s.custid
OPTION (RECOMPILE);
'
		,	@Param = N'@VendorId INT, @ReportDate DATETIME'
		;

	EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param, @VendorId, @ReportDate;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.OW_DailySummary 42;
EXECUTE	dbr.OW_DailySummary 66;
EXECUTE	dbr.OW_DailySummary;
