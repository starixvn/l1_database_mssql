USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_DailySummary'
	,	@Version	SYSNAME		= N'1.1.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_DailySummary
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210529@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Daily Summary data from SB database

	Parameters:
		@Var1				[optional]		- The id of Luminet system that will be selected
				<DEFAULT>	NULL			- No data

		@Var2				[optional]		- The id of environment that will be selected
				<DEFAULT>	NULL			- No data

		@Var3				[optional]		- The date of data that will be selected. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday 00:00:00 AM

	Version:	1.1.1
	Revision:
		- [1.1.1]	20210722@Billy		Add option to query SIT environment
		- [1.1.0]	20210617@Billy		Update query to match with new BI schema
		- [1.0.0]	20210529@Billy		Release dbr.SB_DailySummary
		- [0.0.1]	20210529@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@_L				INT
		,	@_Env			INT
		,	@_ReportDate	DATETIME
		;


	BEGIN TRY SELECT @_L          = CONVERT(INT     , @Var1); END TRY BEGIN CATCH SELECT @_L          = NULL; END CATCH;
	BEGIN TRY SELECT @_Env        = CONVERT(INT     , @Var2); END TRY BEGIN CATCH SELECT @_Env        = NULL; END CATCH;
	BEGIN TRY SELECT @_ReportDate = CONVERT(DATETIME, @Var3); END TRY BEGIN CATCH SELECT @_ReportDate = NULL; END CATCH;

	SELECT	@_ReportDate	= CONVERT(DATE, ISNULL(@_ReportDate, DATEADD(DAY, -1, GETUTCDATE())))
		;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	' + CAST(@_L AS NVARCHAR(MAX)) + ' AS SC
	,	cfg.gameTypeId AS gameTypeId
	,	cfg.gameId AS gameId
	,	cfg.nameEN AS gameType
	,	IFNULL(ds.currency, "null") AS currency
	,	IFNULL(ds.isCash, 2) AS isCash
	,	ds.tickets AS betCount
	,	ds.stake AS stake
	,	ds.payOut AS payOut
FROM		summary.daily_summaries AS ds
INNER JOIN	summary.game_summary_config AS cfg
		ON	ds.gameId = cfg.gameId
WHERE	ds.time >= "' + CONVERT(NVARCHAR(MAX), @_ReportDate, 127) + N'"
	AND	ds.time < "' + CONVERT(NVARCHAR(MAX), DATEADD(DAY, 1, @_ReportDate), 127) + N'"
'
		;

	EXECUTE	base.ExecuteSabaQuery @Query, @_L, 0, @_Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_DailySummary 1, 1;
EXECUTE	dbr.SB_DailySummary 2, 1;
EXECUTE	dbr.SB_DailySummary 3, 1;
EXECUTE	dbr.SB_DailySummary;
