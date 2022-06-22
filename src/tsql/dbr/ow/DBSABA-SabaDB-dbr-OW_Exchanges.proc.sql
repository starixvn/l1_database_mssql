USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.OW_Exchanges'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.OW_Exchanges
WITH ENCRYPTION
AS
/*
	Creator:		20211018@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Exchanges data from OW database

	Parameters:

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211018@Billy		Release dbr.OW_Exchanges
		- [0.0.1]	20211018@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
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

SELECT	DISTINCT
		[currency]	= e.currency
	,	[code]		= ISNULL(NULLIF(e.Code, N''''), e.currency)
FROM	dbo.exchange AS e
WHERE	e.IsActive = 1
OPTION (RECOMPILE);
'
		,	@Param = N''
		;

	EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.OW_Exchanges;
