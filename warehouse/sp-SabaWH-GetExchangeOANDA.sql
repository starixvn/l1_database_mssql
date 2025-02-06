USE	SabaWH;
GO
ALTER PROCEDURE dbo.GetExchangeOANDA
	@Codes			t.CurrencyCodes	READONLY
,	@ExchangeDate	DATE			= NULL
AS
BEGIN TRY;
	SET NOCOUNT ON;

	SELECT	@ExchangeDate = ISNULL(@ExchangeDate, GETUTCDATE());

	SELECT	[time] = eo.ExchangeDate
		,	[code] = c.Code
		,	[USD] = eo.USD / e.MultipliedBy
		,	[VND] = eo.VND / e.MultipliedBy
	FROM	@Codes AS c
	CROSS APPLY	(
		SELECT	TOP (1)
				ec.exchangeid
			,	ec.MultipliedBy
		FROM	(
			SELECT	_e.exchangeid, _e.currency, _e.Code, _e.MultipliedBy
			FROM	dbo.exchange AS _e
			WHERE	_e.currency = c.Code
			AND		_e.IsActive = 1
			UNION ALL
			SELECT	TOP(1)
					_e.exchangeid, _e.currency, _e.Code, _e.MultipliedBy
			FROM	dbo.exchange AS _e
			WHERE	_e.Code = c.Code
			ORDER BY _e.exchangeid ASC, _e.IsActive DESC
		) AS ec
		ORDER BY IIF(ec.Code = ec.currency, 0, 1)
	) AS e
	CROSS APPLY	(
		SELECT	_e.ExchangeDate, _e.USD, _e.VND
		FROM	dbo.ExchangeDailyOanda AS _e WITH (NOLOCK)
		WHERE	_e.ExchangeDate = @ExchangeDate
		AND		_e.ExchangeId = e.exchangeid
	) AS eo;
END TRY
BEGIN CATCH
	EXECUTE logger.handleThrow @isTest = 0;
END CATCH;
GO
GRANT EXECUTE ON dbo.GetExchangeOANDA TO app_exchange;
GO
DECLARE @Codes t.CurrencyCodes;
INSERT INTO @Codes (Code)
VALUES	('AUD')
	,	('CAD')
	,	('CNY')
	,	('EUR')
	,	('GBP')
	,	('HKD')
	,	('IDR')
	,	('JPY')
	,	('KRW')
	,	('MYR')
	,	('PHP')
	,	('SGD')
	,	('THB')
	,	('TWD')
	,	('USD')
	,	('VND')
	,	('YNG')
	,	('ARS')
	,	('BDT')
	,	('BND')
	,	('BRL')
	,	('CHF')
	,	('CLP')
	,	('CZK')
	,	('DKK')
	,	('GHS')
	,	('INR')
	,	('KES')
	,	('KHR')
	,	('KZT')
	,	('LAK')
	,	('MMK')
	,	('MXN')
	,	('NOK')
	,	('NPR')
	,	('PEN')
	,	('PKR')
	,	('PLN')
	,	('RON')
	,	('RUB')
	,	('SEK')
	,	('TRY')
	,	('COP');
EXECUTE dbo.GetExchangeOANDA @Codes = @Codes;
