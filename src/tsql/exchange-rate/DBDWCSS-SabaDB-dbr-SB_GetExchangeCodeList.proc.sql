USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_GetExchangeCodeList'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_GetExchangeCodeList
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211122@Billy
	Location:		DBDWCSS.SabaDB
	Description:	Exchange code list in SB database

	Parameters:

	Version:	1.0.1
	Revision:
		- [1.0.1]	20211214@Billy		Fetch [base] currency
		- [1.0.0]	20211122@Billy		Release dbr.SB_GetExchangeCodeList
		- [0.0.1]	20211122@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@L			TINYINT
		,	@Env		TINYINT
		;

	BEGIN TRY; SELECT @L   = CONVERT(TINYINT , @Var1); END TRY BEGIN CATCH; SELECT @L   = NULL; END CATCH;
	BEGIN TRY; SELECT @Env = CONVERT(TINYINT , @Var2); END TRY BEGIN CATCH; SELECT @Env = NULL; END CATCH;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	base, name
FROM	minigame.exchange_codes
'
		;
	EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_GetExchangeCodeList 1, 1;
EXECUTE	dbr.SB_GetExchangeCodeList 2, 1;
EXECUTE	dbr.SB_GetExchangeCodeList 3, 1;
