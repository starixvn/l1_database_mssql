USE	SabaBK2DB;
DECLARE	@Object		SYSNAME		= N'dbo.GetFileSize_Byte'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	dbo.GetFileSize_Byte
					@Var1			SQL_VARIANT		= NULL
				,	@Size			BIGINT			OUTPUT
WITH ENCRYPTION
AS
/*
	Creator:		20210428@Billy
	Location:		DBBACKUP2.SabaBK2DB
	Description:	Get File Size in Byte

	Parameters:
		@Var1:				[Required]		- File path

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210428@Billy		Release dbo.GetFileSize_Byte
		- [0.0.1]	20210428@Billy		Initial
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@FilePath	NVARCHAR(1024)
		,	@Query		NVARCHAR(MAX)
		,	@Param		NVARCHAR(MAX)
		;

	BEGIN TRY SELECT @FilePath = CAST(@Var1 AS NVARCHAR(1024)); END TRY BEGIN CATCH GOTO FileInvalid; END CATCH;

	IF	@FilePath IS NULL
		GOTO FileInvalid;

	DECLARE	@FileExist AS TABLE (
				doesExist			BIT
			,	isDir				BIT
			,	doesParentDirExist	BIT
			);

	INSERT INTO	@FileExist (doesExist, isDir, doesParentDirExist)
	EXECUTE	sys.xp_fileexist @FilePath;

	IF	EXISTS (SELECT 1 FROM @FileExist WHERE doesExist = 0)
		GOTO FileInvalid;

	SELECT	@Query = N''
		,	@Param = N''
		;
	SELECT	@Query += N'\
SELECT	@Size = DATALENGTH(fl.BulkColumn)
FROM	OPENROWSET(BULK N''' + REPLACE(REPLACE(@FilePath, CHAR(39), CHAR(39) + CHAR(39)), CHAR(39), CHAR(39) + CHAR(39)) + N''', SINGLE_BLOB) AS fl
OPTION (RECOMPILE);
'
		,	@Param += N'@Size BIGINT OUTPUT'
		;

	EXECUTE	sys.sp_executesql @Query, @Param, @Size OUTPUT;
	RETURN;

	FileInvalid:
	SELECT	@Size = -1;
	RETURN;
END;
GO

DECLARE	@Size BIGINT
	,	@Time	DATETIME2 = SYSUTCDATETIME()
EXECUTE	dbo.GetFileSize_Byte N'G:\SCDBBackup\MongoDB\SC3\MainDB\minigame-20210429-000000.zip.bak', @Size OUTPUT;
SELECT	@Size, DATEDIFF(MICROSECOND, @Time, SYSUTCDATETIME());
