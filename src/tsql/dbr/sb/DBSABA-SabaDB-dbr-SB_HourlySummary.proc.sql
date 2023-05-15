USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_HourlySummary'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_HourlySummary
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
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

		@Var3				[optional]		- The date of data that will be selected. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday 00:00:00 AM

	Version:	1.0.1
	Revision:
		- [1.0.1]	20230511@Billy		Add GROUP BY due to multiple operatorId
		- [1.0.0]	20220217@Billy		Release dbr.SB_HourlySummary
		- [0.0.2]	20220225@Billy		Add time field
		- [0.0.1]	20220217@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@_L				INT
		,	@_Env			INT
		,	@_ReportHour	DATETIME
		;


	BEGIN TRY SELECT @_L          = CONVERT(INT     , @Var1); END TRY BEGIN CATCH SELECT @_L          = NULL; END CATCH;
	BEGIN TRY SELECT @_Env        = CONVERT(INT     , @Var2); END TRY BEGIN CATCH SELECT @_Env        = NULL; END CATCH;
	BEGIN TRY SELECT @_ReportHour = CONVERT(DATETIME, @Var3); END TRY BEGIN CATCH SELECT @_ReportHour = NULL; END CATCH;

	SELECT	@_ReportHour	= ISNULL(@_ReportHour, DATEADD(HOUR, -1, GETUTCDATE()))
		,	@_ReportHour	= DATEADD(HOUR, DATEDIFF(HOUR, 0, @_ReportHour), 0)
		;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	' + CAST(@_L AS NVARCHAR(MAX)) + ' AS SC
	,	s.time AS time
	,	cfg.gameTypeId AS gameTypeId
	,	cfg.gameId AS gameId
	,	cfg.nameEN AS gameType
	,	IFNULL(s.currency, "null") AS currency
	,	IFNULL(s.isCash, 2) AS isCash
	,	s.tickets AS betCount
	,	s.stake AS stake
	,	s.payOut AS payOut
FROM		summary.hourly_summaries AS s
INNER JOIN	summary.game_summary_config AS cfg
		ON	s.gameId = cfg.gameId
WHERE	s.time >= "' + CONVERT(NVARCHAR(MAX), @_ReportHour, 127) + N'"
	AND	s.time < "' + CONVERT(NVARCHAR(MAX), DATEADD(HOUR, 1, @_ReportHour), 127) + N'"
GROUP BY s.time, s.gameId, s.currency, s.isCash
'
		;

	EXECUTE	base.ExecuteSabaQuery @Query, @_L, 0, @_Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_HourlySummary 1, 1;
EXECUTE	dbr.SB_HourlySummary 2, 1;
EXECUTE	dbr.SB_HourlySummary 3, 1;
EXECUTE	dbr.SB_HourlySummary;
