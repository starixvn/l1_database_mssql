USE SabaDB;
DECLARE	@Procedure	SYSNAME		= N'dbr.L_SiteHourSummary_tmp'
	,	@Version	SYSNAME		= N'1.0.0'
	;
EXECUTE	dbo.sp_MSR_InitProcedure @Procedure;
EXECUTE	dbo.sp_MSR_SetVersion @Procedure, @Version;
GO
ALTER PROCEDURE	dbr.L_SiteHourSummary_tmp
					@L				TINYINT
				,	@reportDate		DATETIME		= NULL
WITH ENCRYPTION
AS
/*
	Creator:		20210529@Billy
	Location:		DBSABA.SabaDB
	Description:	Get Daily Summary data from SB database

	Parameters:
		@L					[optional]		- The id of Luminet system that will be selected
				<DEFAULT>	NULL			- No data

		@reportDate			[optional]		- The date of data that will be selected. The time is in UTC timezone.
				<DEFAULT>	NULL			- Yesterday 00:00:00 AM

	Version:	1.0.0
	Revision:
		- [1.0.0]	20230512@Billy		Release dbr.OW_SiteHourSummary
		- [0.0.1]	20230512@Billy		Initital
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Timer		DATETIME2		= SYSUTCDATETIME();

	SELECT	@reportDate = CONVERT(DATE, ISNULL(@reportDate, DATEADD(DAY, -1, GETUTCDATE())));

	DECLARE	@Query		NVARCHAR(MAX)
		;

	SELECT	@Query = N''
		;

	SELECT	@Query += N'\
SELECT	CASE WHEN ds.operatorId = "ONEworks_VG" AND ds.isCash = 0 THEN "ONEworks_VG"
			 WHEN ds.operatorId = "ONEworks_VG" AND ds.isCash = 1 THEN "ONEworksVGCash"
			 ELSE ds.operatorId
		END AS operatorId
	,	ds.time
	,	cfg.gameTypeId
	,	cfg.gameId
	,	ds.currency
	,	ds.tickets AS betCount
	,	ds.stake AS turnOver
	,	ds.payout AS payOut
FROM		summary.hourly_summaries AS ds
INNER JOIN	summary.game_summary_config AS cfg
		ON	ds.gameId = cfg.gameId
WHERE	ds.time >= "' + FORMAT(@reportDate, 'yyyy-MM-dd') + N'"
	AND	ds.time < "' + FORMAT(DATEADD(DAY, 1, @reportDate), 'yyyy-MM-dd') + N'"
GROUP BY ds.operatorId, ds.isCash, ds.time, ds.gameId, ds.currency
'
		;

	EXECUTE	base.ExecuteSabaQuery @Query, @L, 0, 1;

	RETURN	DATEDIFF(MILLISECOND, @Timer, SYSUTCDATETIME());
END;
GO
EXECUTE	dbr.L_SiteHourSummary_tmp 3;
