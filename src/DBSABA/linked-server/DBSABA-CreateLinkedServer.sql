USE	master;
SET NOCOUNT ON;

DECLARE	@PROReadOnlyPwd	SYSNAME		= N''
	,	@UATReadOnlyPwd	SYSNAME		= N''
	,	@SITReadOnlyPwd	SYSNAME		= N''
	;

DECLARE	@Servers AS TABLE (
			name	SYSNAME		PRIMARY KEY CLUSTERED
		,	pwd		SYSNAME
		,	isDone	BIT			DEFAULT (0)
		);

INSERT INTO	@Servers (name, pwd)
VALUES	(N'L1_SabaBI'   , @PROReadOnlyPwd)
	,	(N'L2_SabaBI'   , @PROReadOnlyPwd)
	,	(N'L1_SabaArcBI', @PROReadOnlyPwd)
	,	(N'L2_SabaArcBI', @PROReadOnlyPwd)
	,	(N'L1_SabaUATBI', @UATReadOnlyPwd)
	,	(N'L2_SabaUATBI', @UATReadOnlyPwd)
	,	(N'L1_SabaSITBI', @SITReadOnlyPwd)
	,	(N'L2_SabaSITBI', @SITReadOnlyPwd)
	;

DECLARE	@Svr	SYSNAME
	,	@Pwd	SYSNAME
	;

WHILE	0 = 0
BEGIN;
	UPDATE	TOP(1) @Servers
	SET		@Svr = name
		,	@Pwd = pwd
		,	isDone = 1
	WHERE	isDone = 0;

	IF	@@ROWCOUNT = 0
		BREAK;

	BEGIN TRY;
		RAISERROR(N'\
[INFO]	Creating linked server [%s]', 0, 0, @Svr) WITH NOWAIT;
		EXECUTE	master.dbo.sp_addlinkedserver @server = @Svr, @srvproduct = N'MongoBI', @provider = N'MSDASQL', @datasrc = @Svr;
		RAISERROR(N'\
[DONE]	Creating linked server [%s]', 0, 0, @Svr) WITH NOWAIT;
	END TRY BEGIN CATCH
		RAISERROR(N'\
[ERR]	Failed to create linked server [%s] - %d', 0, 0, @Svr, @@ERROR) WITH NOWAIT;
	END CATCH;

	IF	NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @Svr)
	BEGIN;
		RAISERROR(N'\
[ERR]	Linked server [%s] does NOT exist - Abort remaining scripts...', 0, 0, @Svr) WITH NOWAIT;
		BREAK;
	END;

	RAISERROR(N'\
[INFO]	Creating linked server''s login @[%s]', 0, 0, @Svr) WITH NOWAIT;
	EXECUTE	master.dbo.sp_addlinkedsrvlogin @rmtsrvname = @Svr, @useself = N'False', @locallogin = NULL          , @rmtuser = N'';
	EXECUTE	master.dbo.sp_addlinkedsrvlogin @rmtsrvname = @Svr, @useself = N'False', @locallogin = N'DBDWCSS\SQL', @rmtuser = N'lmn_readonly', @rmtpassword = @Pwd;
	EXECUTE	master.dbo.sp_addlinkedsrvlogin @rmtsrvname = @Svr, @useself = N'False', @locallogin = N'lmnBackend' , @rmtuser = N'lmn_readonly', @rmtpassword = @Pwd;
	EXECUTE	master.dbo.sp_addlinkedsrvlogin @rmtsrvname = @Svr, @useself = N'False', @locallogin = N'lmnGrafana' , @rmtuser = N'lmn_readonly', @rmtpassword = @Pwd;
	EXECUTE	master.dbo.sp_addlinkedsrvlogin @rmtsrvname = @Svr, @useself = N'False', @locallogin = N'vnBilly'    , @rmtuser = N'lmn_readonly', @rmtpassword = @Pwd;
	RAISERROR(N'\
[DONE]	Creating linked server''s login @[%s]', 0, 0, @Svr) WITH NOWAIT;

	RAISERROR(N'\
[INFO]	Configuring linked server [%s]', 0, 0, @Svr) WITH NOWAIT;
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'data access'                      , @optvalue = N'true';
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'rpc'                              , @optvalue = N'true';
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'rpc out'                          , @optvalue = N'true';

	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'dist'                             , @optvalue = N'false';
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'pub'                              , @optvalue = N'false';
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'sub'                              , @optvalue = N'false';

	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'collation compatible'             , @optvalue = N'false';
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'collation name'                   , @optvalue = NULL;
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'use remote collation'             , @optvalue = N'true';

	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'connect timeout'                  , @optvalue = N'0';
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'query timeout'                    , @optvalue = N'0';

	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'lazy schema validation'           , @optvalue = N'false';
	EXECUTE	master.dbo.sp_serveroption @server = @Svr, @optname = N'remote proc transaction promotion', @optvalue = N'false';
	RAISERROR(N'\
[DONE]	Configuring linked server [%s]', 0, 0, @Svr) WITH NOWAIT;

	RAISERROR(N'', 0, 0) WITH NOWAIT;
END;

SELECT	tmp.isDone, svr.*
FROM		@Servers AS tmp
INNER JOIN	sys.servers AS svr
		ON	tmp.name = svr.name;
GO
