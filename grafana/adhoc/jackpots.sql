SELECT  gameName AS Game
    ,   IFNULL(prize, CASE pool WHEN 1 THEN "minor" WHEN 5 THEN "major" WHEN 10 THEN "grand" ELSE NULL END) AS Prize
    ,   createdTime
    ,   initAmount * IF(gameId = 29, 1000, 1) / rate AS initAmount
    ,   amount * IF(gameId = 29, 1000, 1) / rate AS amount
    ,   byMembers / rate AS playerContributed
FROM    minigame.jackpots AS j
INNER JOIN  (
    SELECT  rate
    FROM    minigame.exchange_rates
    WHERE   code = "USD"
    ORDER BY exDate DESC
    LIMIT 1
) AS r
WHERE   hitAt IS NULL
ORDER BY gameId, CASE Prize WHEN "minor" THEN 1 WHEN "major" THEN 2 WHEN "grand" THEN 3 END
