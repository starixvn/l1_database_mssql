USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.SB_TicketDetails'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.SB_TicketDetails
					@Var1			SQL_VARIANT		= NULL
				,	@Var2			SQL_VARIANT		= NULL
				,	@Var3			SQL_VARIANT		= NULL
				,	@Var4			SQL_VARIANT		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210923@Billy
	Location:		DBSABA.SabaDB
	Description:	Get ticket details from SB database

	Parameters:
		@Var1				[optional]		- The id of Luminet system that will be selected
				<DEFAULT>	NULL			- No data

		@Var2				[optional]		- The id of environment that will be selected
				<DEFAULT>	NULL			- No data

		@Var3				[optional]		- The type id of game that will be selected
				<DEFAULT>	NULL			- No data

		@Var4				[optional]		- The date of data that will be selected. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday 00:00:00 AM

	Version:	1.0.0
	Revision:
		- [1.0.0]	20210923@Billy		Release dbr.SB_TicketDetails
		- [0.0.1]	20210923@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer			DATETIME2		= SYSUTCDATETIME()
		;

	DECLARE	@L				INT
		,	@Env			INT
		,	@GameTypeId		INT
		,	@ReportDate		DATETIME
		,	@VendorId		INT
		,	@Name			NVARCHAR(128)
		;

	BEGIN TRY SELECT @L          = CONVERT(INT     , @Var1); END TRY BEGIN CATCH SELECT @L          = NULL; END CATCH;
	BEGIN TRY SELECT @Env        = CONVERT(INT     , @Var2); END TRY BEGIN CATCH SELECT @Env        = NULL; END CATCH;
	BEGIN TRY SELECT @GameTypeId = CONVERT(INT     , @Var3); END TRY BEGIN CATCH SELECT @GameTypeId = NULL; END CATCH;
	BEGIN TRY SELECT @ReportDate = CONVERT(DATETIME, @Var4); END TRY BEGIN CATCH SELECT @ReportDate = NULL; END CATCH;

	SELECT	@ReportDate	= CONVERT(DATE, ISNULL(@ReportDate, DATEADD(DAY, -1, GETUTCDATE())))
		;

	SELECT	@VendorId	= m.vendorId
		,	@Name		= m.baseName
	FROM	dbr.tf_GameTypeMapping(NULL, NULL, @GameTypeId) AS m;

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	' + CAST(@gameTypeId AS NVARCHAR(MAX)) + ' AS gameTypeId
	,	b.currency AS currency
	,	b.roundId AS phienId
	,	b.memberId AS memberId
	,	b.stake AS stake
	,	b.payout - b.stake AS winLost
	,	b.time AS transdate
	,	g.time AS endgame
	,	b.settled AS thanhtoan
	,	0 AS freeBet
FROM		minigame.' + @Name + N'_rounds AS g
INNER JOIN	minigame.' + @Name + N'_tickets AS b
		ON	g.id = b.roundId
WHERE	g.time >= ''' + CONVERT(NVARCHAR(MAX), @ReportDate, 127) + N'''
	AND	g.time < ''' + CONVERT(NVARCHAR(MAX), DATEADD(DAY, 1, @ReportDate), 127) + N'''
	AND	b.memberId > 0
'
		;

	EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, @Env;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.SB_TicketDetails 1, 1, 1612;
EXECUTE	dbr.SB_TicketDetails 2, 1, 3802;
EXECUTE	dbr.SB_TicketDetails 3, 1, 3802;
EXECUTE	dbr.SB_TicketDetails;
