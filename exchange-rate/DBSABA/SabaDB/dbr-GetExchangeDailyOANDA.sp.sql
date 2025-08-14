USE SabaDB;
GO
CREATE OR ALTER PROCEDURE	dbr.GetExchangeDailyOANDA
	@Date	DATETIME		= NULL
,	@L		TINYINT			= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211018@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Exchange OANDA data from OW database

	Parameters:
		@Date				[optional]		- The date of data that will be selected. The time is in UTC-4 timezone.
				<DEFAULT>	NULL			- Newest date from OW OANDA

	Version:	2.1.2
	Revision:
		- [2.1.2]	20250813@Billy		Migrate to KL IDC
		- [2.1.1]	20250324@Billy		Remove support for multiple L system
		- [2.1.0]	20230713@Billy		Remove call to L3
		- [2.0.1]	20220715@Billy		Round to 10 decimal number
		- [2.0.0]	20211214@Billy		Support multiple L system
		- [1.0.0]	20211018@Billy		Release dbr.GetExchangeDailyOANDA
		- [0.0.1]	20211018@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@ExchangeDate	DATETIME
		,	@Query			NVARCHAR(MAX)
		,	@Param			NVARCHAR(MAX)
		;

	CREATE TABLE #ExchangeOANDA (
		ExchangeDate	DATE
	,	Code			NVARCHAR(128)
	,	BaseCode		NVARCHAR(128)
	,	BaseRate		DECIMAL(28,20)
	,	PRIMARY KEY CLUSTERED (Code)
	);

	DECLARE	@CheckDate AS TABLE (
				latest			DATETIME
			,	query			DATETIME
			);
	DECLARE	@Codes AS TABLE (
				base			NVARCHAR(128)
			,	code			NVARCHAR(128)
			);

	/** Get the date to be selected */
	INSERT INTO	@CheckDate (latest, query)
	EXECUTE	dbr.OW_CheckExchangeDate @Date;

	SELECT	@ExchangeDate = ISNULL(query, latest)
	FROM	@CheckDate;

	/** Get list of currency codes to be selected */
	DELETE	@Codes;
	IF	@L = 1
		INSERT INTO	@Codes (base, code)
		SELECT	base, code
		FROM	l1.ExchangeCodes;
	ELSE IF @L = 2
		INSERT INTO	@Codes (base, code)
		SELECT	base, code
		FROM	l2.ExchangeCodes;
	ELSE IF @L = 4
		INSERT INTO	@Codes (base, code)
		SELECT	base, code
		FROM	l4.ExchangeCodes;
	ELSE IF @L = 5
		INSERT INTO	@Codes (base, code)
		SELECT	base, code
		FROM	l5.ExchangeCodes;

	/** Get OANDA data */
	SELECT	@Query = N''
		,	@Param = N''
		;
	SELECT	@Query = @Query + N'\
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT	[ExchangeDate]	= o.ExchangeDate
	,	[Code]			= e.code
	,	[BaseCode]		= N''' + b.base + N'''
	,	[BaseRate]		= CAST(o.rate / eid.MultipliedBy AS DECIMAL(19,10))
FROM	(
	SELECT	DISTINCT code
	FROM	dbo.exchange AS _e
	WHERE	_e.code IN (' + sc.str + N')
) AS e
CROSS APPLY	(
	SELECT	TOP(1)
			[exchangeid]	= _e.exchangeid
		,	[MultipliedBy]	= _e.MultipliedBy
	FROM	dbo.exchange AS _e
	WHERE	_e.code = e.code
	ORDER BY IIF(_e.code = _e.currency, 0, 1)
) AS eid
CROSS APPLY	(
	SELECT	TOP(1)
			[rate]			= _o.' + b.base + N'
		,	[ExchangeDate]	= _o.ExchangeDate
	FROM	dbo.ExchangeDailyOanda AS _o
	WHERE	_o.ExchangeDate = @Date
		AND	_o.exchangeid = eid.exchangeid
) AS o
ORDER BY e.code ASC
OPTION (RECOMPILE);
'
		,	@Param = @Param + N'@Date DATETIME'
	FROM	(
		SELECT	STRING_AGG(CONCAT(NCHAR(39), code, NCHAR(39)), N', ')
		FROM	@Codes
	) AS sc(str)
	CROSS APPLY	(
		SELECT	TOP(1)
				base
		FROM	@Codes
		WHERE	base IS NOT NULL
	) AS b(base);
	INSERT INTO	#ExchangeOANDA (ExchangeDate, Code, BaseCode, BaseRate)
	EXECUTE	DB061.bodb02.sys.sp_executesql @Query, @Param, @ExchangeDate;


	SELECT	ExchangeDate, Code, BaseCode, BaseRate
	FROM	#ExchangeOANDA;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.Exchanges') IS NOT NULL
		DROP TYPE dbr.Exchanges;

	CREATE TYPE	dbr.Exchanges AS TABLE (
		L				TINYINT
	,	exchangeDate	DATE
	,	code			VARCHAR(16)
	,	baseCode		VARCHAR(16)
	,	baseRate		DECIMAL(19,10)
	,	PRIMARY KEY NONCLUSTERED (L, code, baseCode, exchangeDate)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
EXECUTE	dbr.GetExchangeDailyOANDA NULL, 1;
