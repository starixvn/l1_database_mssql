USE SabaDB;
GO
CREATE OR ALTER PROCEDURE	dbr.OW_CheckExchangeDate
		@Date	DATETIME		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211109@Billy
	Location:		DBSABA.SabaDB
	Description:	Check Exchange date in OW database

	Parameters:

	Version:	1.0.1
	Revision:
		- [1.0.1]	20250813@Billy		Migrate to KL IDC
		- [1.0.0]	20211109@Billy		Release dbr.OW_CheckExchangeDate
		- [0.0.1]	20211109@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

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
	EXECUTE	DB061.bodb02.sys.sp_executesql @Query, @Param, @Date;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.OW_CheckExchangeDate;
