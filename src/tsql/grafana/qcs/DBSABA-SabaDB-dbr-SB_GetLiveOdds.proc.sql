USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_GetLiveOdds'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_GetLiveOdds
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211123@Billy
	Location:		DBSABA.SabaDB
	Description:	Exchange code list in SB database

	Parameters:

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211123@Billy		Release dbr.SB_GetLiveOdds
		- [0.0.1]	20211123@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	EXECUTE	base.WaitForRandom;
	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@Type		NVARCHAR(128)
		,	@TypeId		NVARCHAR(128)
		,	@L			TINYINT
		,	@Env		TINYINT
		;

	BEGIN TRY; SELECT @Type = CONVERT(NVARCHAR(128), @Var1); END TRY BEGIN CATCH; SELECT @Type = NULL; END CATCH;
	BEGIN TRY; SELECT @L    = CONVERT(TINYINT      , @Var2); END TRY BEGIN CATCH; SELECT @L    = NULL; END CATCH;
	BEGIN TRY; SELECT @Env  = CONVERT(TINYINT      , @Var3); END TRY BEGIN CATCH; SELECT @Env  = NULL; END CATCH;

	SELECT	@TypeId = m.id
	FROM	(
		VALUES	(N'bluered'  , N'Blue Red'  )
			,	(N'overunder', N'Over Under')
	) AS m (id, name)
	WHERE	m.name = @Type;

	IF	@TypeId IS NULL
		GOTO Finish;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	' + CAST(@L AS NVARCHAR(MAX)) + N' AS "L"
	,	*
FROM	minigame.kenomatch_liveodds_' + @TypeId + N'
ORDER BY val ASC
'
		;
	EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;

	Finish:
	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_GetLiveOdds 'Blue Red', 1, 1;
