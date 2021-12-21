USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'base.ExecuteSabaQuery'
	,	@Version	SYSNAME		= N'1.3.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	base.ExecuteSabaQuery
					@Query			NVARCHAR(MAX)	= NULL
				,	@Var1			SQL_VARIANT		= NULL		-- L
				,	@Var2			SQL_VARIANT		= NULL		-- Type
				,	@Var3			SQL_VARIANT		= NULL		-- Env
WITH ENCRYPTION
AS
/*
	Creator:		20210208@Billy
	Location:		DBDWCSS.SabaDB
	Description:	Execute query on Luminet system

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
							1				- Production
							2				- UAT
							3				- SIT

	Version:	1.3.0
	Revision:
		- [1.3.0]	20211221@Billy		Forward execution to bridge on Linux instance
										Support Local Environment
		- [1.2.0]	20211130@Billy		Support UAT Environment
		- [1.1.0]	20210722@Billy		Support SIT Environment
		- [1.0.2]	20210419@Billy		Do nothing if query is empty - [Gitlab: #060]
		- [1.0.1]	20210322@Billy		Apply code convention - [Gitlab: #059]
		- [1.0.0]	20210208@Billy		Release base.ExecuteSabaQuery - [Gitlab: #058]
		- [0.0.1]	20210208@Billy		Initial - [Gitlab: #058]
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	/** Forward execution to Windows SQL Server instance due to lack of external linked server
	    support on Linux SQL Server.
	*/
	DECLARE	@Win	NVARCHAR(256)
		;
	SELECT	@Win = windows_release
	FROM	sys.dm_os_windows_info;
	IF	@Win = N''
	BEGIN;
		EXECUTE	DBBRIDGE.SabaDB.base.ExecuteSabaQuery @Query, @Var1, @Var2, @Var3;
		RETURN
	END;

	DECLARE	@_L		INT
		,	@_Type	INT
		,	@_Env	INT
		;

	BEGIN TRY SELECT @_L    = ABS(ISNULL(CAST(@Var1 AS INT), 0)); END TRY BEGIN CATCH SELECT @_L    = 0; END CATCH;
	BEGIN TRY SELECT @_Type = ABS(ISNULL(CAST(@Var2 AS INT), 0)); END TRY BEGIN CATCH SELECT @_Type = 0; END CATCH;
	BEGIN TRY SELECT @_Env  = ABS(ISNULL(CAST(@Var3 AS INT), 0)); END TRY BEGIN CATCH SELECT @_Env  = 0; END CATCH;

	IF	NULLIF(@Query, N'') IS NULL
		RETURN;

	IF	@_L    = 1
	AND	@_Type = 0 -- Active
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABABI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L1BI;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type = 0 -- Active
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABABI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L2BI;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type = 0 -- Active
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABABI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L3aBI;
	END CATCH;

	IF	@_L    = 1
	AND	@_Type = 1 -- Archive
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABAARCBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L1BI;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type = 1 -- Archive
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABAARCBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L2BI;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type = 1 -- Archive
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABAARCBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L3aBI;
	END CATCH;

	IF	@_L    = 1
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 2 -- UAT
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABAUATBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L1pBI;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 2 -- UAT
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABAUATBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L2pBI;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 2 -- UAT
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABAUATBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L3bBI;
	END CATCH;

	IF	@_L    = 1
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 3 -- SIT
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABASITBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L1ppBI;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 3 -- SIT
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABASITBI;
	END TRY BEGIN CATCH;
		RETURN;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 3 -- SIT
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABASITBI;
	END TRY BEGIN CATCH;
		EXECUTE	(@Query) AT L3cBI;
	END CATCH;
END;
GO
