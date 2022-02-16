USE	SabaDB;
DECLARE	@Object		SYSNAME		= N'Bot.SkynexQuery'
	,	@Version	SYSNAME		= N'0.0.1'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Object;
EXECUTE	dbo.sp_MSR_SetVersion @Object, @Version;
GO
ALTER PROCEDURE	Bot.SkynexQuery
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			NVARCHAR(MAX)	= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210411@Billy
	Location:		DBSABA.SabaDB
	Description:	Query Saba information via Skynex commands

	Parameters:
		@Var1:				[optional]		- The id that identified the channel that issuing the query.
				<DEFAULT>	NULL			- Invalid

		@Var2:				[optional]		- The query string.
				<DEFAULT>	NULL			- Invalid

	Version:	0.0.1
	Revision:
		- [0.0.1]	20210411@Billy		Initital - [Gitlab: #060]
*/
BEGIN;
	SET NOCOUNT ON;

	DECLARE	@ConversationId			VARCHAR(256)
		,	@Command				NVARCHAR(MAX)
		;

	BEGIN TRY;
		SELECT	@ConversationId		= CONVERT(VARCHAR(256), @Var1)
			,	@Command			= @Var2
			;

		IF	@ConversationId IS NULL
		OR	@Command IS NULL
		OR	LTRIM(RTRIM(@Command)) = N'saba'
		OR	@Command NOT LIKE N'saba %'
			GOTO InvalidResponse;

		TODO:
		DECLARE	@Commands AS TABLE (
					id			INT
				,	cmd			NVARCHAR(MAX)
				,	PRIMARY KEY CLUSTERED (id)
				);
		INSERT INTO	@Commands (id, cmd)
		SELECT	id, val
		FROM	base.f_SplitString(@Command, N' ', NULL)
		WHERE	id > 1;

		SELECT	[result] = @ConversationId + N' - ' + CAST(COUNT(1) AS NVARCHAR(MAX)) + N'_' + CAST(CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS NVARCHAR(MAX))
		FROM	@Commands;
		RETURN;
	END TRY BEGIN CATCH;
		GOTO InvalidResponse;
	END CATCH;

	InvalidResponse:
	BEGIN;
		SELECT	[result] = N'Please send **help** to get my commands'
		RETURN;
	END;
END;
GO
GRANT EXECUTE ON Bot.SkynexQuery TO sqlLink AS dbo;
GO
EXECUTE	Bot.SkynexQuery N'TEST', N'saba ';
