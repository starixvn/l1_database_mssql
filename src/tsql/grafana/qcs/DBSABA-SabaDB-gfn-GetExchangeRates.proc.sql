USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'gfn.GetExchangeRates'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	gfn.GetExchangeRates
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
				,	@Var4			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211123@Billy
	Location:		DBSABA.SabaDB
	Description:	Exchange rates in SB database

	Parameters:

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211123@Billy		Release gfn.GetExchangeRates
		- [0.0.1]	20211123@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	EXECUTE	base.WaitForRandom;
	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@EnvName	VARCHAR(128)
		,	@EnvId		TINYINT
		;

	BEGIN TRY; SELECT @EnvName = CONVERT(VARCHAR(128), @Var4); END TRY BEGIN CATCH; SELECT @EnvName = NULL; END CATCH;

	SELECT	@EnvId = m.id
	FROM	(
		VALUES	(1, 'PRO')
			,	(2, 'UAT')
			,	(3, 'SIT')
			,	(1, 'Local')
			,	(2, 'Local1')
			,	(3, 'Local2')
	) AS m (id, val)
	WHERE	m.val = @EnvName;

	EXECUTE	dbr.SB_GetExchangeRates @Var1, @Var2, @Var3, @EnvId;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	gfn.GetExchangeRates '2021-11-10', '2021-11-23', 1, 'SIT';
