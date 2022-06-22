USE	SabaDB;
SET NOCOUNT ON;
GO
IF	OBJECT_ID('gfn.TicketInformation_BetLog') IS NULL
BEGIN;
	EXECUTE	sys.sp_executesql N'CREATE PROCEDURE gfn.TicketInformation_BetLog AS';
END;
GO
ALTER PROCEDURE	gfn.TicketInformation_BetLog
					@obTransId			BIGINT			= NULL
				,	@gameType			NVARCHAR(128)	= NULL
				,	@gameRoundId		INT				= NULL
				,	@username			NVARCHAR(128)	= NULL
				,	@obCustId			INT				= NULL
WITH ENCRYPTION
AS
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@Query			NVARCHAR(MAX)
		,	@gameTypeId		INT
		;

	DECLARE	@Games AS TABLE (
				gameTypeId		SMALLINT
			,	owGameTypeId	INT
			,	nameEN			NVARCHAR(128)
			,	nameVI			NVARCHAR(128)
			,	PRIMARY KEY CLUSTERED (gameTypeId)
			);

	DECLARE	@Users AS TABLE (
				obCustId		INT
			,	username		NVARCHAR(128)
			,	PRIMARY KEY CLUSTERED (obCustId)
			);

	DECLARE	@BetCall AS TABLE (
				callAPI				NVARCHAR(128)
			,	amount				MONEY
			,	choiceId			SMALLINT
			,	currency			VARCHAR(5)
			,	gameRoundId			INT
			,	gameTypeId			SMALLINT
			,	ip					VARCHAR(128)
			,	obCustId			INT
			,	requestTS	DATETIME2
			,	balance				MONEY
			,	errCode				SMALLINT
			,	errDesc				NVARCHAR(MAX)
			,	errMsg				NVARCHAR(MAX)
			,	obTransId			BIGINT
			);

	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	gameId
	,	gameTypeId
	,	nameEN
	,	nameVI
FROM	summary.game_summary_config;
';

		INSERT INTO	@Games (gameTypeId, owGameTypeId, nameEN, nameVI)
		EXECUTE	(@Query) AT L1_SABABI;
	END;

	IF	ISNULL(@obTransId, 0) <> 0
	BEGIN;
		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	callType
	,	amount
	,	choiceId
	,	currency
	,	gameRoundId
	,	gameTypeId
	,	ip
	,	obCustId
	,	requestTS
	,	balance
	,	0
	,	""
	,	""
	,	obTransId
FROM	log.bets
WHERE	obTransId = ' + CAST(@obTransId AS NVARCHAR(MAX)) + N'
';

		INSERT INTO	@BetCall (callAPI, amount, choiceId, currency, gameRoundId, gameTypeId, ip, obCustId, requestTS, balance, errCode, errDesc, errMsg, obTransId)
		EXECUTE	base.ExecuteSabaQuery @Query, 1, 0, 1;

		INSERT INTO	@BetCall (callAPI, amount, choiceId, currency, gameRoundId, gameTypeId, ip, obCustId, requestTS, balance, errCode, errDesc, errMsg, obTransId)
		EXECUTE	base.ExecuteSabaQuery @Query, 2, 0, 1;

		INSERT INTO	@BetCall (callAPI, amount, choiceId, currency, gameRoundId, gameTypeId, ip, obCustId, requestTS, balance, errCode, errDesc, errMsg, obTransId)
		EXECUTE	base.ExecuteSabaQuery @Query, 3, 0, 1;

		SELECT	[API]			= bc.callAPI
			,	[GameId]		= LTRIM(g.owGameTypeId) + N'.' + LTRIM(bc.gameTypeId)
			,	[Game]			= g.nameEN
			,	[Round]			= bc.gameRoundId
			,	[CustId]		= bc.obCustId
			,	[$]				= bc.currency
			,	[TransId]		= bc.obTransId
			,	[RequestTime]	= bc.requestTS
			,	[IP]			= bc.ip
			,	[ChoiceId]		= bc.choiceId
			,	[Amount]		= bc.amount
			,	[Balance]		= bc.balance
			,	[ErrCode]		= bc.errCode
			,	[ErrDesc]		= bc.errDesc
			,	[ErrMsg]		= bc.errMsg
		FROM		@BetCall AS bc
		LEFT JOIN	@Games AS g
				ON	bc.gameTypeId = g.gameTypeId
		ORDER BY	bc.requestTS ASC;
	END;
	ELSE IF	ISNULL(@gameType, N'') <> N''
		AND	ISNULL(@gameRoundId, 0) <> 0
	BEGIN;
		SELECT	@gameTypeId	= gameTypeId
		FROM	@Games
		WHERE	nameEN = @gameType;

		IF	ISNULL(@obCustId, 0) = 0 AND ISNULL(@username, N'') <> N''
		BEGIN;
			SELECT	@Query = N'';
			SELECT	@Query += N'\
SELECT	memberId
	,	memberName
FROM	minigame.users
WHERE	memberName = "' + @username + N'"
';

			INSERT INTO	@Users (obCustId, username)
			EXECUTE	base.ExecuteSabaQuery @Query, 1, 0, 1;

			INSERT INTO	@Users (obCustId, username)
			EXECUTE	base.ExecuteSabaQuery @Query, 2, 0, 1;

			INSERT INTO	@Users (obCustId, username)
			EXECUTE	base.ExecuteSabaQuery @Query, 3, 0, 1;

			SELECT	@obCustId = obCustId
			FROM	@Users;
		END;

		SELECT	@Query = N'';
		SELECT	@Query += N'\
SELECT	callType
	,	amount
	,	choiceId
	,	currency
	,	gameRoundId
	,	gameTypeId
	,	ip
	,	obCustId
	,	requestTS
	,	balance
	,	0
	,	""
	,	""
	,	obTransId
FROM	log.bets
WHERE	gameTypeId = ' + LTRIM(@gameTypeId) + N'
	AND	gameRoundId = ' + LTRIM(@gameRoundId) + ISNULL(N'
	AND	obCustId = ' + LTRIM(NULLIF(@obCustId, 0)), N'') + N'
UNION ALL
SELECT	callType
	,	amount
	,	choiceId
	,	currency
	,	gameRoundId
	,	gameTypeId
	,	ip
	,	obCustId
	,	requestTS
	,	0
	,	errorCode
	,	errorDesc
	,	errorMsg
	,	0
FROM	log.bets_failed
WHERE	gameTypeId = ' + LTRIM(@gameTypeId) + N'
	AND	gameRoundId = ' + LTRIM(@gameRoundId) + ISNULL(N'
	AND	obCustId = ' + LTRIM(NULLIF(@obCustId, 0)), N'') + N'
';

		INSERT INTO	@BetCall (callAPI, amount, choiceId, currency, gameRoundId, gameTypeId, ip, obCustId, requestTS, balance, errCode, errDesc, errMsg, obTransId)
		EXECUTE	base.ExecuteSabaQuery @Query, 1, 0, 1;

		INSERT INTO	@BetCall (callAPI, amount, choiceId, currency, gameRoundId, gameTypeId, ip, obCustId, requestTS, balance, errCode, errDesc, errMsg, obTransId)
		EXECUTE	base.ExecuteSabaQuery @Query, 2, 0, 1;

		INSERT INTO	@BetCall (callAPI, amount, choiceId, currency, gameRoundId, gameTypeId, ip, obCustId, requestTS, balance, errCode, errDesc, errMsg, obTransId)
		EXECUTE	base.ExecuteSabaQuery @Query, 3, 0, 1;

		SELECT	[API]			= bc.callAPI
			,	[GameId]		= LTRIM(g.owGameTypeId) + N'.' + LTRIM(bc.gameTypeId)
			,	[Game]			= g.nameEN
			,	[Round]			= bc.gameRoundId
			,	[CustId]		= bc.obCustId
			,	[$]				= bc.currency
			,	[TransId]		= bc.obTransId
			,	[RequestTime]	= bc.requestTS
			,	[IP]			= bc.ip
			,	[ChoiceId]		= bc.choiceId
			,	[Amount]		= bc.amount
			,	[Balance]		= bc.balance
			,	[ErrCode]		= bc.errCode
			,	[ErrDesc]		= bc.errDesc
			,	[ErrMsg]		= bc.errMsg
		FROM		@BetCall AS bc
		LEFT JOIN	@Games AS g
				ON	bc.gameTypeId = g.gameTypeId
		ORDER BY	bc.requestTS ASC;
	END;
	ELSE
	BEGIN;
		SELECT	[ErrMsg]		= N'Invalid Input'
			;
	END;

	
END;
GO
EXECUTE	gfn.TicketInformation_BetLog 102807581809
EXECUTE	gfn.TicketInformation_BetLog NULL, 'VIP Se Die', 262835
