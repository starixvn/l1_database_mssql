USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.OW_CheckExchangeDate'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.OW_CheckExchangeDate
					@Var1			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211109@Billy
	Location:		DBSABA.SabaDB
	Description:	Check Exchange date in OW database

	Parameters:

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211109@Billy		Release dbr.OW_CheckExchangeDate
		- [0.0.1]	20211109@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@Date		DATETIME
		;

	BEGIN TRY; SELECT @Date = CONVERT(DATETIME, @Var1); END TRY BEGIN CATCH; SELECT @Date = NULL; END CATCH;

	SELECT	@Date	= CONVERT(DATE, ISNULL(@Date, GETUTCDATE()))
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

SELECT	[latest]	= l.ExchangeDate
	,	[query]		= q.ExchangeDate
FROM	(
	SELECT	TOP(1)
			_o.ExchangeDate
	FROM	dbo.ExchangeDailyOanda AS _o
	ORDER BY _o.ExchangeDate DESC
) AS l
OUTER APPLY (
	SELECT	TOP(1)
			_o.ExchangeDate
	FROM	dbo.ExchangeDailyOanda AS _o
	WHERE	_o.ExchangeDate = @Date
) AS q
OPTION (RECOMPILE);
'
		,	@Param = N'@Date DATETIME'
		;
	EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param, @Date;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.OW_CheckExchangeDate;
