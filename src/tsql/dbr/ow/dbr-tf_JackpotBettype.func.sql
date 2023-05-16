USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'dbr.tf_JackpotBettype'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	dbr.tf_JackpotBettype ()
RETURNS TABLE
WITH ENCRYPTION
AS
/*
	Creator:		20230516@Billy
	Location:		DBSABA.SabaDB
	Description:	Jackpot Bettypes - Inline Table-valued Version

	Parameters:
		@gameId				[REQUIRED]		- The id of game that will be selected
							NULL			- All games

		@vendorId			[REQUIRED]		- The id of vendor that will be selected
							NULL			- All vendors

		@gameTypeId			[REQUIRED]		- The id of game type that will be selected
							NULL			- All games

	Version:	1.0.0
	Revision:
		- [1.0.0]	20230516@Billy		Release dbr.tf_JackpotBettype
		- [0.0.1]	20230516@Billy		Initital - [Gitlab: #058]
*/
RETURN (
	SELECT	tbl.gameTypeId
	FROM	(VALUES	(1698), (3898)) AS tbl(gameTypeId)
);
GO
SELECT	*
FROM	dbr.tf_JackpotBettype()
