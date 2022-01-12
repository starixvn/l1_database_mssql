USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'base.tf_DecodeURL'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	base.tf_DecodeURL (
					@string		NVARCHAR(MAX)
				)
RETURNS TABLE
WITH ENCRYPTION
AS
/*
	Creator:		20210416@Billy
	Location:		DBDWCSS.SabaDB
	Description:	URL Decode Function - Inline Table-valued Version

	Parameters:
		@string:			[REQUIRED]		- Input string that need to be decoded.

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210416@Billy		Release base.tf_DecodeURL
		- [0.0.1]	20210416@Billy		Initial - [Gitlab: #058]
*/
RETURN (
	WITH cte AS (
		SELECT	sp.id, s.code, s.str, butf.lbyte, butf.ucode
		FROM		base.f_SplitString(@string, '%', NULL) AS sp
		CROSS APPLY	(
			SELECT	[code]		= CASE sp.id WHEN 1 THEN NULL ELSE SUBSTRING(sp.val, 1, 2) END
				,	[str]		= NULLIF(CASE sp.id WHEN 1 THEN val ELSE SUBSTRING(sp.val, 3, 2147483647) END, '')
		) AS s
		CROSS APPLY	(
			SELECT	[hex]		= CONVERT(BINARY(1), s.code, 2)
				,	[byte]		= CONVERT(INT, CONVERT(BINARY(1), s.code, 2))
		) AS b
		CROSS APPLY	(
			SELECT	[lbyte]		= CASE
									WHEN b.byte < 128 THEN 1
									WHEN b.byte < 192 THEN NULL
									WHEN b.byte < 224 THEN 2
									WHEN b.byte < 240 THEN 3
									WHEN b.byte >= 240 THEN 4
									ELSE NULL
								  END
				,	[ucode]		= CASE
									WHEN b.byte < 128 THEN b.byte & 127
									WHEN b.byte < 192 THEN b.byte & 63
									WHEN b.byte < 224 THEN (b.byte & 31) * 64
									WHEN b.byte < 240 THEN (b.byte & 15) * 4096
									WHEN b.byte >= 240 THEN (b.byte & 7) * 262144
									ELSE NULL
								  END
		) AS butf
	)
	SELECT	cc.str
	FROM	(
		SELECT	ISNULL(b4.calC, '') + COALESCE(cte.str, s.str, '')
		FROM	cte
		OUTER APPLY	(
			SELECT	[str] = MAX(_.str)
				,	[sumcode] = cte.ucode + SUM(_.ucode * POWER(2, _p.pos * 6))
			FROM		cte AS _
			CROSS APPLY	(
				SELECT	[pos] = cte.lbyte + cte.id - _.id - 1
			) AS _p
			WHERE	_.id > cte.id
				AND	_.id < cte.id + cte.lbyte
				AND	_.lbyte IS NULL
		) AS s
		OUTER APPLY	(
			SELECT	[scode] = cte.ucode + ISNULL(s.sumcode, 0)
		) AS sc
		CROSS APPLY	(
			SELECT	[sH] = (((sc.scode - 65536) & 1047552) / 1024) + 55296
				,	[sL] = ((sc.scode - 65536) & 1023) + 56320
		) AS surrogate
		CROSS APPLY	(
			SELECT	[calC] = ISNULL(CAST(NCHAR(NULLIF(sc.scode, 0)) AS NVARCHAR(MAX)), NCHAR(surrogate.sH) + NCHAR(surrogate.sL)) --https://docs.microsoft.com/en-us/sql/t-sql/functions/nchar-transact-sql?view=sql-server-ver15
		) AS b4
		WHERE	cte.id = 1
			OR	cte.lbyte > 0
		FOR XML PATH ('')
		,	TYPE
	) AS ccx(xml)
	CROSS APPLY	(
		SELECT	REPLACE(ccx.xml.value('.', 'NVARCHAR(MAX)'), '+', ' ')
	) AS cc(str)
);
GO

SELECT	*
FROM	base.tf_DecodeURL('%C3%A1%C3%A0%C3%B4ano%5D%20%28id%F0%A9%A3%91%F0%A3%85%BFINT%29%3B%20DROP%20DATA%E8%8B%B1%E7%89%B9%E5%B0%94%C2%AE+%E9%85%B7%E7%9D%BF%E2%84%A2+M+%E5%A4%84%E7%90%86%E5%99%A8BASE%20SabaDB%3B%22%2C%20%22other%F0%22%3A%20%22===%F0----')
