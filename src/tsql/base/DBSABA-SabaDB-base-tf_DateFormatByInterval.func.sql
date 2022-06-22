USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'base.tf_DateFormatByInterval'
	,	@Version	SYSNAME		= N'2.0.0'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	base.tf_DateFormatByInterval (
					@Interval		NVARCHAR(128)
				)
RETURNS TABLE
WITH ENCRYPTION
AS
/*
	Creator:		20210416@Billy
	Location:		DBSABA.SabaDB
	Description:	Date Formatter by Interval - Inline Table-valued Version

	Parameters:
		@gameId				[REQUIRED]		- The id of game that will be selected
							NULL			- All games

		@vendorId			[REQUIRED]		- The id of vendor that will be selected
							NULL			- All vendors

		@gameTypeId			[REQUIRED]		- The id of game type that will be selected
							NULL			- All games

	Version:	2.0.0
	Revision:
		- [2.0.0]	20220217@Billy		Move to base schema
		- [1.0.0]	20210416@Billy		Release dbr.tf_GameTypeMapping
		- [0.0.1]	20210416@Billy		Initital - [Gitlab: #058]
*/
RETURN (
	SELECT	tbl.fmtStr
	FROM	(
		VALUES	( N'year'  , N'%Y-01-01T00:00:00Z' )
			,	( N'month' , N'%Y-%m-01T00:00:00Z' )
			,	( N'day'   , N'%Y-%m-%dT00:00:00Z' )
			,	( N'hour'  , N'%Y-%m-%dT%H:00:00Z' )
			,	( N'minute', N'%Y-%m-%dT%H:%i:00Z' )
			,	( N'second', N'%Y-%m-%dT%H:%i:%sZ' )
	) AS tbl (interval, fmtStr)
	WHERE	tbl.interval = @Interval
);
GO
