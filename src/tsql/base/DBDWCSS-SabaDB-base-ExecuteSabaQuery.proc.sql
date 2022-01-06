USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'base.ExecuteSabaQuery'
	,	@Version	SYSNAME		= N'1.3.3'
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

	Version:	1.3.3
	Revision:
		- [1.3.3]	20220106@Billy		If there are 2 errors, raise error instead of printing only
		- [1.3.2]	20211228@Billy		Capture all errors in case both tries failed
		- [1.3.1]	20211222@Billy		Normal user cannot access DMV, fallback to @@VERSION to detect OS type
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
	DECLARE	@Win	BIT
		;
	SELECT	@Win = CASE WHEN val LIKE N'%Windows%' THEN 1 WHEN val LIKE N'%Linux%' THEN 0 ELSE NULL END
	FROM	base.tf_SplitString(@@VERSION, N' on ', 2);

	IF	@Win IS NULL
		RETURN;

	IF	@Win = 0
	BEGIN;
		EXECUTE	DBBRIDGE.SabaDB.base.ExecuteSabaQuery @Query, @Var1, @Var2, @Var3;
		RETURN;
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

	DECLARE	@Errors AS TABLE (
				ErrNumber		INT
			,	ErrSeverity		INT
			,	ErrState		INT
			,	ErrProcedure	NVARCHAR(128)
			,	ErrLine			INT
			,	ErrMessage		NVARCHAR(MAX)
			);
	DECLARE	@Message	NVARCHAR(MAX)
		;

	IF	@_L    = 1
	AND	@_Type = 0 -- Active
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABABI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L1BI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type = 0 -- Active
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABABI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L2BI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type = 0 -- Active
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABABI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L3aBI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 1
	AND	@_Type = 1 -- Archive
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABAARCBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L1BI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type = 1 -- Archive
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABAARCBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L2BI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type = 1 -- Archive
	AND	@_Env  = 1 -- PRO
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABAARCBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L3aBI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 1
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 2 -- UAT
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABAUATBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L1pBI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 2 -- UAT
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABAUATBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L2pBI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 2 -- UAT
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABAUATBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L3bBI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 1
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 3 -- SIT
	BEGIN TRY;
		EXECUTE	(@Query) AT L1_SABASITBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L1ppBI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 2
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 3 -- SIT
	BEGIN TRY;
		EXECUTE	(@Query) AT L2_SABASITBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;

	IF	@_L    = 3
	AND	@_Type IN (0, 1) -- Mixxed
	AND	@_Env  = 3 -- SIT
	BEGIN TRY;
		EXECUTE	(@Query) AT L3_SABASITBI;
	END TRY BEGIN CATCH
		INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
		VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		BEGIN TRY;
			EXECUTE	(@Query) AT L3cBI;
		END TRY BEGIN CATCH
			INSERT INTO	@Errors (ErrNumber, ErrSeverity, ErrState, ErrProcedure, ErrLine, ErrMessage)
			VALUES	(ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
		END CATCH;

		SELECT	@Message = errx.xml.value('.', 'NVARCHAR(MAX)')
		FROM	(
			SELECT	  N'Msg ' + CAST(ErrNumber AS NVARCHAR(MAX))
					+ N', Level ' + CAST(ErrSeverity AS NVARCHAR(MAX))
					+ N', State ' + CAST(ErrState AS NVARCHAR(MAX))
					+ ISNULL(N', Procedure ' + ErrProcedure, N'')
					+ N', Line ' + CAST(ErrLine AS NVARCHAR(MAX))
					+ N'
' + ErrMessage + N'

'
			FROM	@Errors
			FOR XML PATH ('')
			,	TYPE
		) AS errx(xml);

		IF	(SELECT COUNT(1) FROM @Errors) > 1
			RAISERROR(@Message, 16, 1) WITH NOWAIT;
		ELSE
			RAISERROR(@Message, 0, 0) WITH NOWAIT;
	END CATCH;
END;
GO
