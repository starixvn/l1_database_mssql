USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.L_LastExchangeRate'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.L_LastExchangeRate
					@L				TINYINT
				,	@Env			TINYINT
WITH ENCRYPTION
AS
/*
	Creator:		20230515@Billy
	Location:		DBSABA.SabaDB
	Description:	Get last exchange rates

	Parameters:
		@L				[REQUIRED]		- The id of Luminet system that will be selected

		@Env			[REQUIRED]		- The id of environment that will be selected

	Version:	1.0.0
	Revision:
		- [1.0.0]	20230515@Billy		Release dbr.L_LastExchangeRate
		- [0.0.1]	20230515@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME();

	DECLARE	@Query		NVARCHAR(MAX);

	SELECT	@Query = N'';
	SELECT	@Query += N'\
SELECT	er.exDate, er.code, er.rate
FROM	(
	SELECT	exId
	FROM	minigame.exchange_rates
	ORDER BY exId DESC
	LIMIT 1
) AS lastDate
INNER JOIN	minigame.exchange_rates AS er
		ON	er.exId = lastDate.exId
';

	EXECUTE	base.Query @Query, @L, 0, @Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.ExchangeRates') IS NOT NULL
		DROP TYPE dbr.ExchangeRates;

	CREATE TYPE	dbr.ExchangeRates AS TABLE (
		exDate			DATE
	,	code			VARCHAR(16)
	,	rate			DECIMAL(19,9)
	,	PRIMARY KEY NONCLUSTERED (code, exDate)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
EXECUTE	dbr.L_LastExchangeRate 1, 1;
EXECUTE	dbr.L_LastExchangeRate 2, 1;
