USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.GetExchangeDailyOANDA'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.GetExchangeDailyOANDA
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211018@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Exchange OANDA data from OW database

	Parameters:
		@Var1				[optional]		- The date of data that will be selected. The time is in UTC-4 timezone.
				<DEFAULT>	NULL			- Newest date from OW OANDA

	Version:	2.0.0
	Revision:
		- [2.0.0]	20211214@Billy		Support multiple L system
		- [1.0.0]	20211018@Billy		Release dbr.GetExchangeDailyOANDA
		- [0.0.1]	20211018@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@Date			DATETIME
		,	@L				TINYINT
		,	@Env			TINYINT
		,	@ExchangeDate	DATETIME
		,	@Query			NVARCHAR(MAX)
		,	@Param			NVARCHAR(MAX)
		;

	BEGIN TRY SELECT @Date = CONVERT(DATETIME, @Var1); END TRY BEGIN CATCH SELECT @Date = NULL; END CATCH;
	BEGIN TRY SELECT @Env  = CONVERT(TINYINT , @Var2); END TRY BEGIN CATCH SELECT @Env  = NULL; END CATCH;

	CREATE TABLE #ExchangeOANDA (
		L				TINYINT
	,	ExchangeDate	DATE
	,	Code			NVARCHAR(128)
	,	BaseCode		NVARCHAR(128)
	,	BaseRate		DECIMAL(28,20)
	,	PRIMARY KEY CLUSTERED (L, Code)
	);

	/** Hardcode list of L systems */
	DECLARE	@Ls AS TABLE (
				L				TINYINT
			,	isDone			BIT
			);
	INSERT INTO	@Ls (L)
	VALUES	(1), (2), (3);

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

	/** Loop through all L systems */
	UPDATE	@Ls
	SET		isDone = 0;

	WHILE	0 = 0
	BEGIN;
		UPDATE	TOP(1)
				@Ls
		SET		@L = L
			,	isDone = 1
		WHERE	isDone = 0;

		IF	@@ROWCOUNT = 0
			BREAK;

		/** Get list of currency codes to be selected */
		DELETE	@Codes;
		INSERT INTO	@Codes (base, code)
		EXECUTE	dbr.SB_GetExchangeCodeList @L, @Env;

		/** Get OANDA data */
		SELECT	@Query = N''
			,	@Param = N''
			;
		SELECT	@Query = @Query + N'\
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT	DISTINCT
		[L]				= @L
	,	[ExchangeDate]	= o.ExchangeDate
	,	[Code]			= e.code
	,	[BaseCode]		= N''' + b.base + N'''
	,	[BaseRate]		= CAST(o.' + b.base + N' / e.MultipliedBy AS DECIMAL(28,20))
FROM		dbo.exchange AS e
INNER JOIN	dbo.ExchangeDailyOanda AS o
		ON	e.exchangeid = o.ExchangeId
WHERE	e.IsActive = 1
	AND	o.ExchangeDate = @Date
	AND	e.code IN (' + SUBSTRING(sc.str, 0, LEN(sc.str)) + N')
ORDER BY e.code ASC
OPTION (RECOMPILE);
'
			,	@Param = @Param + N'@Date DATETIME, @L TINYINT'
		FROM	(
			SELECT	N'''' + code + N''', '
			FROM	@Codes
			FOR XML PATH ('')
			,	TYPE
		) AS xc(xml)
		CROSS APPLY	(
			SELECT	xc.xml.value('.', 'NVARCHAR(MAX)')
		) AS sc(str)
		CROSS APPLY	(
			SELECT	TOP(1)
					base
			FROM	@Codes
			WHERE	base IS NOT NULL
		) AS b(base)
		;
		INSERT INTO	#ExchangeOANDA (L, ExchangeDate, Code, BaseCode, BaseRate)
		EXECUTE	DB061KBT.bodb02.sys.sp_executesql @Query, @Param, @ExchangeDate, @L;
	END;

	SELECT	L, ExchangeDate, Code, BaseCode, BaseRate
	FROM	#ExchangeOANDA;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.GetExchangeDailyOANDA NULL, 1;
