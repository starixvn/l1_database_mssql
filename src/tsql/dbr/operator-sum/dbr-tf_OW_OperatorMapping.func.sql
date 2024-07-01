USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'dbr.tf_OW_OperatorMapping'
	,	@Version	SYSNAME		= N'1.0.1'
	;
EXECUTE	dbo.sp_MSR_InitInlineTableFunction @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER FUNCTION	dbr.tf_OW_OperatorMapping (
					@vendorId	SMALLINT
				,	@site		VARCHAR(128)
				)
RETURNS TABLE
WITH ENCRYPTION
AS
/*
	Creator:		20210503@Billy
	Location:		DBSABA.SabaDB
	Description:	Map Site to relevant

	Parameters:
		@input:				[REQUIRED]		- Input value to be formatted as byte.

	Version:	1.0.1
	Revision:
		- [1.0.1]	20240614@Billy		Add xD system
		- [1.0.0]	20230512@Billy		Release dbr.tf_OW_OperatorMapping
		- [0.0.1]	20230512@Billy		Initial
*/
RETURN (
	SELECT	TOP(1)
			[operatorId] = meta.operatorId
	FROM	(
		VALUES	(42, NULL, N'ONEworks1')
			,	(66, NULL, N'ONEworks_VG')
			,	(66, N'', N'ONEworksVGCash')
			,	(66, N'SEAL888', N'ONEworksSeal888')
			,	(86, NULL, N'ONEworksCredit')
			,	(86, N'', N'ONEworksCash')
			,	(86, N'SEAL888', N'ONEworksSeal888')
	) AS meta(vendorId, site, operatorId)
	WHERE	@vendorId = meta.vendorId
		AND	(
			(@site IS NULL AND meta.site IS NULL)
		OR	(@site IS NOT NULL AND meta.site IS NOT NULL)
		)
	ORDER BY IIF(@site = meta.site, 1, 0) DESC, meta.site ASC
);
GO
SELECT	*
FROM	(
	VALUES	(42, NULL)
		,	(42, 'Credit')
		,	(42, 'Deposit')
		,	(66, NULL)
		,	(66, 'Credit')
		,	(66, 'Deposit')
		,	(66, 'SEAL888')
		,	(86, NULL)
		,	(86, 'Credit')
		,	(86, 'Deposit')
		,	(86, 'SEAL888')
) AS input(vendorId, site)
OUTER APPLY	dbr.tf_OW_OperatorMapping(input.vendorId, input.site);
