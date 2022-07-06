USE	SabaBK2DB;
DECLARE	@Object		SYSNAME		= N'dbo.CheckBackupStatus'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	dbo.CheckBackupStatus
					@Var1			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210428@Billy
	Location:		DBBACKUP2.SabaBK2DB
	Description:	Check database backup copy job's status then send result via Notification Channel

	Parameters:
		@Var1:				[optional]		- Is this testing execution?
				<DEFAULT>	NULL			- Treat as if testing execution

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210428@Billy		Release dbo.CheckBackupStatus
		- [0.0.1]	20210428@Billy		Initial
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@L				TINYINT
		,	@isTest			BIT
		,	@Path			NVARCHAR(1024)
		,	@File			NVARCHAR(1024)
		,	@Size			BIGINT
		,	@Today			DATE
		,	@Message		NVARCHAR(MAX)
		;

	BEGIN TRY SELECT @isTest = CONVERT(BIT, @Var1); END TRY BEGIN CATCH SELECT isTest = 1; END CATCH;

	DECLARE	@Files AS TABLE (
				L			TINYINT			DEFAULT (0)
			,	foldername	NVARCHAR(1000)
			,	filename	NVARCHAR(449)
			,	depth		SMALLINT
			,	isFile		BIT
			,	size		BIGINT
			,	PRIMARY KEY CLUSTERED (L, filename)
			);

	DECLARE	@Ls AS TABLE (
				L			TINYINT
			,	isDone		BIT
			,	PRIMARY KEY CLUSTERED (L)
			);

	INSERT INTO	@Ls (L)
	VALUES	(1), (2), (3);

	SELECT	@Today = GETUTCDATE()
		;

	UPDATE	@Ls
	SET		isDone = 0;

	WHILE	0 = 0
	BEGIN;
		UPDATE	TOP(1)
				@Ls
		SET		@L = L
			,	isDone = 1
		WHERE	isDone = 0;

		IF	@@ROWCOUNT = 0
			BREAK;

		SELECT	@Path = N'G:\SCDBBackup\MongoDB\SC' + CAST(@L AS NVARCHAR(10)) + N'\MainDB'

		INSERT INTO	@Files (filename, depth, isFile)
		EXECUTE	sys.xp_dirtree @Path, 0, 1;

		UPDATE	@Files
		SET		L = @L
			,	foldername = @Path
		WHERE	L = 0;

		RAISERROR('sys.xp_dirtree - L%d', 0, 0, @L) WITH NOWAIT;
	END;

	DELETE	@Files
	WHERE	isFile <> 1;

	WHILE	0 = 0
	BEGIN;
		SELECT	TOP(1)
				@L = L
			,	@Path = foldername + N'\' + filename
			,	@File = filename
		FROM	@Files
		WHERE	isFile = 1
			AND	filename LIKE N'%-' + CONVERT(NVARCHAR(MAX), @Today, 112) + N'-%'
			AND	size IS NULL;

		IF	@@ROWCOUNT = 0
			BREAK;

		EXECUTE	dbo.GetFileSize_Byte @Path, @Size OUTPUT;

		UPDATE	@Files
		SET		size = @Size
		WHERE	L = @L
			AND	filename = @File;

		RAISERROR('dbo.GetFileSize_Byte - L%d', 0, 0, @L) WITH NOWAIT;
	END;

	SELECT	@Message = msg.str
	FROM	(
		SELECT	N'\

---  
\\\[Backup ' + CONVERT(NVARCHAR(MAX), @Today, 23) + N'\] L' + CONVERT(NVARCHAR(MAX), l.L) + N'  
' + f.str
		FROM	@Ls AS l
		CROSS APPLY	(
			SELECT	N'    `' + _f.filename + N'` - ' + bf.str + N'  
'
			FROM		@Files AS _f
			CROSS APPLY	base.tf_ByteFormat(_f.size) AS bf
			WHERE	_f.L = l.L
				AND	_f.size IS NOT NULL
			ORDER BY _f.filename
			FOR XML PATH ('')
			,	TYPE
		) AS xf(xml)
		CROSS APPLY	(
			SELECT	xf.xml.value('.', 'NVARCHAR(MAX)')
		) AS f(str)
		FOR XML PATH ('')
		,	TYPE
	) AS xmsg(xml)
	CROSS APPLY	(
		SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
	) AS msg(str);
	EXECUTE	DBSABA.SabaDB.SysHealth.SendNotification @Message, @isTest;

	SELECT	@Message = msg.str
	FROM	(
		SELECT	N'\

---  
\\\[Backup Summary\] L' + CONVERT(NVARCHAR(MAX), l.L) + N'  
' + f.str
		FROM	@Ls AS l
		CROSS APPLY	(
			SELECT	N'    `' + _db.val + N'` - ' + CONVERT(NVARCHAR(MAX), COUNT(1)) + N' files \(' + MIN(_date.val) + N' ⇒ ' + MAX(_date.val) + N'\)  
'
			FROM		@Files AS _f
			CROSS APPLY	base.tf_SplitString(_f.filename, N'-', 2) AS _db
			CROSS APPLY	base.tf_SplitString(_f.filename, N'-', 3) AS _date
			WHERE	_f.L = l.L
			GROUP BY _db.val
			ORDER BY _db.val
			FOR XML PATH ('')
			,	TYPE
		) AS xf(xml)
		CROSS APPLY	(
			SELECT	xf.xml.value('.', 'NVARCHAR(MAX)')
		) AS f(str)
		FOR XML PATH ('')
		,	TYPE
	) AS xmsg(xml)
	CROSS APPLY	(
		SELECT	xmsg.xml.value('.', 'NVARCHAR(MAX)')
	) AS msg(str);
	EXECUTE	DBSABA.SabaDB.SysHealth.SendNotification @Message, @isTest;

	IF	ISNULL(@isTest, 1) = 1
	BEGIN;
		SELECT	*
		FROM	@Files AS f
		OUTER APPLY	base.tf_ByteFormat(f.size) AS bf
		OUTER APPLY	base.tf_SplitString(f.filename, N'-', 2) AS _db
		OUTER APPLY	base.tf_SplitString(f.filename, N'-', 3) AS _date
	END;
END;
GO
