-- =============================================================================
--  ECONOMY MODULE - Live stats & leaderboard callbacks
-- =============================================================================

-- =============================================================================
--  LIVE STATS (No DB queries used during gameplay)
-- =============================================================================

RegisterServerCallback('rts:getLiveMenuStats', function(source, cb)
    local activeBattles = 0
    for _ in pairs(Matches) do activeBattles = activeBattles + 1 end

    cb({
        onlineCount = GetNumPlayerIndices(),
        activeBattles = activeBattles,
        ping = GetPlayerPing(source),
        estimatedWait = GetEstimatedWaitTime()
    })
end)

RegisterServerCallback('rts:getGlobalStats', function(source, cb)
    local defaultStats = {
        wins = 0, losses = 0, kills = 0, matches = 0, score = 0,
        name = GetPlayerName(source) or "Commander",
        levelData = { level = 1, currentXP = 0, requiredXP = 3000, percent = 0 }
    }

    local citId = GetPlayerIdentifier(source)

    local success, dbStats = pcall(function()
        return MySQL.single.await('SELECT * FROM rts_player_stats WHERE citizenid = ?', { citId })
    end)

    if success and dbStats then
        defaultStats.wins = dbStats.wins or 0
        defaultStats.losses = dbStats.losses or 0
        defaultStats.kills = dbStats.kills or 0
        defaultStats.matches = dbStats.matches or 0
        defaultStats.score = dbStats.score or 0
        defaultStats.name = dbStats.name or GetPlayerName(source)
    end

    local lvlInfo = CalculateLevel(defaultStats.score)
    defaultStats.levelData = lvlInfo

    cb({
        onlineCount = GetNumPlayerIndices(),
        activeBattles = 0,
        myStats = defaultStats,
        ping = GetPlayerPing(source)
    })
end)

RegisterServerCallback('rts:getLeaderboard', function(source, cb)
    local result = MySQL.query.await('SELECT name, wins, kills, score FROM rts_player_stats ORDER BY score DESC LIMIT 10')
    for _, row in ipairs(result) do
        local lvl = CalculateLevel(row.score)
        row.level = lvl.level
    end
    cb(result)
end)

RegisterServerCallback('rts:getMatchHistory', function(source, cb)
    local cid = GetPlayerIdentifier(source)
    local history = MySQL.query.await([[
        SELECT map_name, result, opponent_name, kills, score, date_played
        FROM rts_match_history
        WHERE citizenid = ?
        ORDER BY date_played DESC
        LIMIT 20
    ]], { cid })
    cb(history)
end)

RegisterServerCallback('rts:getServerPlayerCount', function(source, cb)
    cb(#GetPlayers())
end)
