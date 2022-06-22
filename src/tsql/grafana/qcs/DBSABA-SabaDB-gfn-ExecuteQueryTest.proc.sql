USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'gfn.ExecuteQueryTest'
	,	@Version	SYSNAME		= N'0.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	gfn.ExecuteQueryTest
					@Query			NVARCHAR(MAX)	= NULL
				,	@Var1			SQL_VARIANT		= NULL		-- L
				,	@Var2			SQL_VARIANT		= NULL		-- Type
				,	@Var3			SQL_VARIANT		= NULL		-- Env
WITH ENCRYPTION
AS
/*
	Creator:		20220601@Billy
	Location:		DBSABA.SabaDB
	Description:	Execute test query on Luminet system (SIT/UAT only)

	Parameters:
		@Query:				[optional]		- The query to be executed.
				<DEFAULT>	NULL			- Do nothing

		@Var1:				[optional]		- The Luminet system to be executed on.
				<DEFAULT>	NULL			- Do nothing

		@Var2:				[optional]		- Is the system active?
				<DEFAULT>	NULL			- Active
							1				- Archive

		@Var3:				[optional]		- The environment of system.
				<DEFAULT>	NULL			- Do nothing
							1				- Production - Not allowed
							2				- UAT
							3				- SIT

	Version:	0.0.1
	Revision:
		- [1.0.0]	20220601@Billy		Release gfn.ExecuteQueryTest
		- [0.0.1]	20220601@Billy		Initial
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	IF	CONVERT(SMALLINT, @Var3) = 1
		RETURN;

	EXECUTE	base.ExecuteSabaQuery @Query, @Var1, @Var2, @Var3;
END;
GO
