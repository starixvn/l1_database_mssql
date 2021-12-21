USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'base.tf_SplitString'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	base.tf_SplitString (
					@string		NVARCHAR(MAX)
				,	@splitter	NVARCHAR(MAX)
				,	@id			INT				= NULL
				)
RETURNS TABLE
WITH ENCRYPTION
AS
/*
	Creator:		20190125@Billy
	Location:		DBDWCSS.SabaDB
	Description:	Split String Function - Inline Table Value Version

	Parameters:
		@string:			[REQUIRED]		- Input string that need to be splitted.
		@splitter:			[REQUIRED]		- Input string that used to separate the string.
		@id:				[REQUIRED]		- The position of item to retrieve after splitting.
				<DEFAULT>	NULL			- Get all items

	Version:	1.0.1
	Revision:
		- [1.0.1]	20210413@Billy		Using DATALENGTH instead of LEN because of data trimming
		- [1.0.0]	20190125@Billy		Release base.tf_SplitString
		- [0.0.1]	20190125@Billy		Initial
*/
RETURN (
	WITH cte AS (
				SELECT	[start]		= CAST(1 AS INT)
					,	[finish]	= CASE WHEN CHARINDEX(@splitter, @string, 1) = 0 THEN DATALENGTH(@string) / 2 + 1 ELSE CHARINDEX(@splitter, @string, 1) END
					,	[id]		= 1
				UNION ALL
				SELECT	[start]		= CAST(cte.finish + LEN(@splitter) AS INT)
					,	[finish]	= CASE WHEN CHARINDEX(@splitter, @string, cte.finish + DATALENGTH(@splitter) / 2) = 0 THEN DATALENGTH(@string) / 2 + 1 ELSE CHARINDEX(@splitter, @string, cte.finish + DATALENGTH(@splitter) / 2) END
					,	[id]		= cte.id + 1
				FROM	cte
				WHERE	cte.finish < DATALENGTH(@string) / 2
			)
	SELECT	[id]	= cte.id
		,	[val]	= SUBSTRING(@string, cte.start, cte.finish - cte.start)
	FROM	cte
	WHERE	cte.id = ISNULL(@id, cte.id)
);
GO
