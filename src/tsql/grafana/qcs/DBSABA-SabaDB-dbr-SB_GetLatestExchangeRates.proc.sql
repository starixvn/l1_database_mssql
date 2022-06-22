USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_GetLatestExchangeRates'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_GetLatestExchangeRates
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211123@Billy
	Location:		DBSABA.SabaDB
	Description:	Exchange code list in SB database

	Parameters:

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211123@Billy		Release dbr.SB_GetLatestExchangeRates
		- [0.0.1]	20211123@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@L			TINYINT
		,	@Env		TINYINT
		;

	BEGIN TRY; SELECT @L    = CONVERT(TINYINT , @Var1); END TRY BEGIN CATCH; SELECT @L    = NULL; END CATCH;
	BEGIN TRY; SELECT @Env  = CONVERT(TINYINT , @Var2); END TRY BEGIN CATCH; SELECT @Env  = NULL; END CATCH;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	source, time, code, rate, exId, exDate
FROM	minigame.exchange_rates
WHERE	time = (
	SELECT	time
	FROM	minigame.exchange_rates
	ORDER BY time DESC
	LIMIT 1
)
ORDER BY time DESC, code ASC
'
		;
	EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_GetLatestExchangeRates 1, 2;
