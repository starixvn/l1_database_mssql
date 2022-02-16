USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'uat.GetExchangeDailyOANDA'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	uat.GetExchangeDailyOANDA
					@Var1			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20211018@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Exchange OANDA data from OW database

	Parameters:
		@Var1				[optional]		- The date of data that will be selected. The time is in UTC-4 timezone.
				<DEFAULT>	NULL			- Newest date from OW OANDA

	Version:	1.0.0
	Revision:
		- [1.0.0]	20211018@Billy		Release uat.GetExchangeDailyOANDA
		- [0.0.1]	20211018@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	EXECUTE	dbr.GetExchangeDailyOANDA @Var1, 2;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
GRANT EXECUTE ON uat.GetExchangeDailyOANDA TO lmnBackend AS dbo;
GO
EXECUTE	uat.GetExchangeDailyOANDA;
