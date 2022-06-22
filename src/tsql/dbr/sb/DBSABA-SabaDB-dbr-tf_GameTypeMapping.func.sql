USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'dbr.tf_GameTypeMapping'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	dbr.tf_GameTypeMapping (
					@gameId		INT
				,	@vendorId	INT
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

	Version:	2.0.0
	Revision:
		- [2.0.0]	20220217@Billy		Using configs from SB
		- [1.0.0]	20210416@Billy		Release dbr.tf_GameTypeMapping
		- [0.0.1]	20210416@Billy		Initital - [Gitlab: #058]
*/
RETURN (
	SELECT	tbl.gameId, tbl.vendorId, tbl.gameTypeId, tbl.baseName
	FROM	(
		SELECT	gameId, vendorId, gameTypeId, baseName
		FROM	OPENQUERY(L1_SABABI, N'\
SELECT	gameId, 42 AS vendorId, gameTypeId, coll AS baseName
FROM	summary.game_summary_config
')
		UNION
		SELECT	gameId, vendorId, gameTypeId, baseName
		FROM	OPENQUERY(L2_SABABI, N'\
SELECT	gameId, 66 AS vendorId, gameTypeId, coll AS baseName
FROM	summary.game_summary_config
')
		UNION
		SELECT	gameId, vendorId, gameTypeId, baseName
		FROM	OPENQUERY(L3_SABABI, N'\
SELECT	gameId, 66 AS vendorId, gameTypeId, coll AS baseName
FROM	summary.game_summary_config
')
	) AS tbl (gameId, vendorId, gameTypeId, baseName)
	WHERE	tbl.gameId		= ISNULL(@gameId, tbl.gameId)
		AND	tbl.vendorId	= ISNULL(@vendorId, tbl.vendorId)
		AND	tbl.gameTypeId	= ISNULL(@gameTypeId, tbl.gameTypeId)
);
GO
SELECT	*
FROM	dbr.tf_GameTypeMapping(NULL, NULL, NULL)