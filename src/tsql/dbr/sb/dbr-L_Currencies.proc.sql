USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.L_Currencies'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.L_Currencies
					@L				TINYINT
				,	@Env			TINYINT
WITH ENCRYPTION
AS
/*
	Creator:		20230515@Billy
	Location:		DBSABA.SabaDB
	Description:	Get currencies settings

	Parameters:
		@L				[REQUIRED]		- The id of Luminet system that will be selected
		@Env			[REQUIRED]		- The id of environment that will be selected

	Version:	1.0.1
	Revision:
		- [1.0.1]	20240614@Billy		Using latest term of operatorId
		- [1.0.0]	20230515@Billy		Release dbr.L_Currencies
		- [0.0.1]	20230515@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME();

	DECLARE	@Query		NVARCHAR(MAX);

	SELECT	@Query = N'';
	SELECT	@Query += N'\
SELECT	operatorId AS operatorId
	,	name AS name
	,	code AS code
	,	multiplier AS multiplier
FROM	minigame.currencies
WHERE	isTest = 0
	AND	enabled = 1;
';

	EXECUTE	base.Query @Query, @L, 0, @Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.Currencies') IS NOT NULL
		DROP TYPE dbr.Currencies;

	CREATE TYPE	dbr.Currencies AS TABLE (
		operatorId		NVARCHAR(128)
	,	name			VARCHAR(16)
	,	code			VARCHAR(16)
	,	multiplier		DECIMAL(19,9)
	,	PRIMARY KEY NONCLUSTERED (operatorId, name)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
EXECUTE	dbr.L_Currencies 1, 1;
EXECUTE	dbr.L_Currencies 2, 1;
