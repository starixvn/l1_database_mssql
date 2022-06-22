USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_GameSummaryConfig'
	,	@Version	SYSNAME		= N'0.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_GameSummaryConfig
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20220217@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Hourly Summary data from SB database

	Parameters:
		@Var1				[optional]		- The id of Luminet system that will be selected
				<DEFAULT>	NULL			- No data

		@Var2				[optional]		- The id of environment that will be selected
				<DEFAULT>	NULL			- No data

	Version:	0.0.1
	Revision:
		- [1.0.0]	20210529@Billy		Release dbr.SB_GameSummaryConfig
		- [0.0.1]	20220217@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@_L				INT
		,	@_Env			INT
		;

	BEGIN TRY SELECT @_L   = CONVERT(INT, @Var1); END TRY BEGIN CATCH SELECT @_L   = NULL; END CATCH;
	BEGIN TRY SELECT @_Env = CONVERT(INT, @Var2); END TRY BEGIN CATCH SELECT @_Env = NULL; END CATCH;

	DECLARE	@Query		NVARCHAR(MAX)
		,	@vendorId	
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
FROM		summary.hourly_summaries AS ds
INNER JOIN	summary.game_summary_config AS cfg
		ON	ds.gameId = cfg.gameId
WHERE	ds.time >= "' + CONVERT(NVARCHAR(MAX), @_ReportHour, 127) + N'"
	AND	ds.time < "' + CONVERT(NVARCHAR(MAX), DATEADD(DAY, 1, @_ReportHour), 127) + N'"
'
		;

	EXECUTE	base.ExecuteSabaQuery @Query, @_L, 0, @_Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_GameSummaryConfig 1, 1;
EXECUTE	dbr.SB_GameSummaryConfig 2, 1;
EXECUTE	dbr.SB_GameSummaryConfig 3, 1;
EXECUTE	dbr.SB_GameSummaryConfig;
