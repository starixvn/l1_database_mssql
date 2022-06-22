USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_GetExchangeRates'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_GetExchangeRates
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
				,	@Var4			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211123@Billy
	Location:		DBSABA.SabaDB
	Description:	Exchange code list in SB database

	Parameters:

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211123@Billy		Release dbr.SB_GetExchangeRates
		- [0.0.1]	20211123@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@From		DATETIME
		,	@To			DATETIME
		,	@L			TINYINT
		,	@Env		TINYINT
		;

	BEGIN TRY; SELECT @From = CONVERT(DATETIME, @Var1); END TRY BEGIN CATCH; SELECT @From = NULL; END CATCH;
	BEGIN TRY; SELECT @To   = CONVERT(DATETIME, @Var2); END TRY BEGIN CATCH; SELECT @To   = NULL; END CATCH;
	BEGIN TRY; SELECT @L    = CONVERT(TINYINT , @Var3); END TRY BEGIN CATCH; SELECT @L    = NULL; END CATCH;
	BEGIN TRY; SELECT @Env  = CONVERT(TINYINT , @Var4); END TRY BEGIN CATCH; SELECT @Env  = NULL; END CATCH;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	source, time, code, rate, exId, exDate
FROM	minigame.exchange_rates
WHERE	time >= "' + CONVERT(NVARCHAR(MAX), @From, 126) + N'"
	AND	time < "' + CONVERT(NVARCHAR(MAX), @To, 126) + N'"
ORDER BY time DESC, code ASC
'
		;
	EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_GetExchangeRates '2021-11-22', '2021-11-23', 1, 2;
