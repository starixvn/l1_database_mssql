USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'dbr.tf_GameTypeMapping'
	,	@Version	SYSNAME		= N'2.1.0'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	dbr.tf_GameTypeMapping (
					@L			INT
				,	@vendorId	INT
				,	@gameId		INT
				,	@gameTypeId	INT
				)
RETURNS TABLE
WITH ENCRYPTION
AS
/*
	Creator:		20210416@Billy
	Location:		DBSABA.SabaDB
	Description:	Game Type Mapping - Inline Table-valued Version

	Parameters:
		@gameId				[REQUIRED]		- The id of game that will be selected
							NULL			- All games

		@vendorId			[REQUIRED]		- The id of vendor that will be selected
							NULL			- All vendors

		@gameTypeId			[REQUIRED]		- The id of game type that will be selected
							NULL			- All games

	Version:	2.1.0
	Revision:
		- [2.1.0]	20230515@Billy		Remove VG3 system
		- [2.0.0]	20220217@Billy		Using configs from SB
		- [1.0.0]	20210416@Billy		Release dbr.tf_GameTypeMapping
		- [0.0.1]	20210416@Billy		Initital - [Gitlab: #058]
*/
RETURN (
	SELECT	tbl.L, tbl.vendorId, tbl.gameId, tbl.gameTypeId, tbl.baseName, tbl.gameName
	FROM	(
		SELECT	L, vendorId, gameId, gameTypeId, baseName, gameName
		FROM	OPENQUERY(L1_SABABI, N'\
SELECT	1 AS L, 42 AS vendorId, gameId, gameTypeId, coll AS baseName, nameEN as gameName
FROM	summary.game_summary_config
')
		UNION
		SELECT	L, vendorId, gameId, gameTypeId, baseName, gameName
		FROM	OPENQUERY(L2_SABABI, N'\
SELECT	2 AS L, 66 AS vendorId, gameId, gameTypeId, coll AS baseName, nameEN as gameName
FROM	summary.game_summary_config
')
	) AS tbl (L, vendorId, gameId, gameTypeId, baseName, gameName)
	WHERE	tbl.L			= ISNULL(@L, tbl.L)
		AND	tbl.vendorId	= ISNULL(@vendorId, tbl.vendorId)
		AND	tbl.gameId		= ISNULL(@gameId, tbl.gameId)
		AND	tbl.gameTypeId	= ISNULL(@gameTypeId, tbl.gameTypeId)
);
GO
BEGIN TRY;
	IF	TYPE_ID('dbr.GameTypeMappingL') IS NOT NULL
		DROP TYPE dbr.GameTypeMappingL;

	CREATE TYPE	dbr.GameTypeMappingL AS TABLE (
		L				TINYINT
	,	vendorId		SMALLINT
	,	gameId			SMALLINT
	,	gameTypeId		SMALLINT
	,	baseName		VARCHAR(128)
	,	gameName		NVARCHAR(128)
	,	PRIMARY KEY NONCLUSTERED (L, gameId)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
BEGIN TRY;
	IF	TYPE_ID('dbr.GameTypeMappingOW') IS NOT NULL
		DROP TYPE dbr.GameTypeMappingOW;

	CREATE TYPE	dbr.GameTypeMappingOW AS TABLE (
		L				TINYINT
	,	vendorId		SMALLINT
	,	gameId			SMALLINT
	,	gameTypeId		SMALLINT
	,	baseName		VARCHAR(128)
	,	gameName		NVARCHAR(128)
	,	PRIMARY KEY NONCLUSTERED (vendorId, gameTypeId)
	) WITH (MEMORY_OPTIMIZED = ON);
END TRY BEGIN CATCH;
	EXECUTE	logger.Error N'Type'
END CATCH;
GO
SELECT	*
FROM	dbr.tf_GameTypeMapping(NULL, NULL, NULL, NULL)
