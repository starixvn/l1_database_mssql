USE	SabaDB;
SET NOCOUNT ON;
GO
IF	OBJECT_ID('gfn.GetGameTypes') IS NULL
BEGIN;
	EXECUTE	sys.sp_executesql N'CREATE PROCEDURE gfn.GetGameTypes AS';
END;
GO
ALTER PROCEDURE	gfn.GetGameTypes
					@Type			SMALLINT
WITH ENCRYPTION
AS
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Query			NVARCHAR(MAX)
		;

	DECLARE	@Games AS TABLE (
				gameId			SMALLINT
			,	gameTypeId		INT
			,	nameEN			NVARCHAR(128)
			,	nameVI			NVARCHAR(128)
			,	PRIMARY KEY CLUSTERED (gameTypeId)
			);

	SELECT	@Query = N'';
	SELECT	@Query += N'\
SELECT	gameId
	,	gameTypeId
	,	nameEN
	,	nameVI
FROM	summary.game_summary_config
WHERE	gameTypeId IS NOT NULL;
';

	INSERT INTO	@Games (gameId, gameTypeId, nameEN, nameVI)
	EXECUTE	base.ExecuteSabaQuery @Query, 1, 0, 1;

	SELECT	[value]	=	CASE @Type
							WHEN 1 THEN LTRIM(gameId)
							WHEN 2 THEN LTRIM(gameTypeId)
							WHEN 3 THEN nameEN
							WHEN 4 THEN nameVI
							ELSE nameEN
						END
	FROM	@Games;
END;
GO
EXECUTE	gfn.GetGameTypes 3
