USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'base.tf_ByteFormat'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	base.tf_ByteFormat (
					@input		BIGINT
				)
RETURNS TABLE
WITH ENCRYPTION
AS
/*
	Creator:		20210503@Billy
	Location:		DBSABA.SabaDB
	Description:	Byte Value Format Function - Inline Table Value Version

	Parameters:
		@input:				[REQUIRED]		- Input value to be formatted as byte.

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210503@Billy		Release base.tf_ByteFormat
		- [0.0.1]	20210503@Billy		Initial
*/
RETURN (
	SELECT	TOP(1)
			[str] = RIGHT(N'   ' + CONVERT(NVARCHAR(MAX), CONVERT(MONEY, d.val, 1)), 8) + pf.value
	FROM	(
		VALUES	(0, ' B' )
			,	(1, ' kB')
			,	(2, ' MB')
			,	(3, ' GB')
			,	(4, ' TB')
			,	(5, ' PB')
			,	(6, ' EB')
			,	(7, ' ZB')
			,	(8, ' YB')
	) AS pf(level, value)
	CROSS APPLY	(
		SELECT	[val] = @input / POWER(1024.0, pf.level)
	) AS d
	WHERE	d.val >= 1
	ORDER BY pf.level DESC
);
GO
