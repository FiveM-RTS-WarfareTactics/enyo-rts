-- =============================================================================
--  EXPORTS MODULE - Public API for third-party resources
--  All exports are documented in API.md
-- =============================================================================

-- ---- Server State Queries ----

exports('GetServerOverview', function()
    local activeMatchCount, playersInMatches = 0, 0
    for _, match in pairs(Matches) do
        activeMatchCount = activeMatchCount + 1
        if match.players then
            for _ in pairs(match.players) do playersInMatches = playersInMatches + 1 end
        end
    end
    return {
        totalOnline   = GetNumPlayerIndices(),
        activeMatches = activeMatchCount,
        playersInQueue = (#MatchmakingQueue or 0),
        playersInGame  = playersInMatches,
    }
end)

exports('GetMatchCount', function()
    local c = 0
    for _ in pairs(Matches) do c = c + 1 end
    return c
end)

exports('GetQueueSize', function()
    return #MatchmakingQueue
end)

-- ---- Match Queries ----

exports('GetActiveMatches', function()
    local matchDetails = {}
    for matchId, match in pairs(Matches) do
        local playersList = {}
        if match.players then
            for src, pData in pairs(match.players) do
                local unitCount = 0
                if match.units then
                    for _, u in pairs(match.units) do
                        if u.owner == src then unitCount = unitCount + 1 end
                    end
                end
                table.insert(playersList, {
                    source = src,
                    name = pData.playerName or GetPlayerName(src) or "Unknown",
                    team = pData.team or 1,
                    spawnedUnits = unitCount,
                    commandPoints = math.floor(pData.commandPoints or 0),
                    kills = pData.kills or 0,
                    bucket = GetPlayerRoutingBucket(src),
                })
            end
        end
        table.insert(matchDetails, {
            matchId   = matchId,
            mapName   = match.map or "unknown",
            bucketId  = match.bucket or matchId,
            startTime = match.startTime,
            isActive  = match.active,
            playerCount = #playersList,
            players = playersList,
            objectives = match.objectives,
        })
    end
    return matchDetails
end)

exports('GetMatchDetails', function(matchId)
    local match = Matches[matchId]
    if not match then return nil end
    local playersList = {}
    if match.players then
        for src, pData in pairs(match.players) do
            table.insert(playersList, {
                source = src,
                name = pData.playerName or "Unknown",
                team = pData.team,
                identifier = pData.identifier,
                commandPoints = math.floor(pData.commandPoints or 0),
                kills = pData.kills or 0,
                unitsLost = pData.unitsLost or 0,
                damageDealt = pData.damageDealt or 0,
            })
        end
    end
    return {
        matchId    = matchId,
        mapName    = match.map,
        bucketId   = match.bucket,
        startTime  = match.startTime,
        isActive   = match.active,
        isCpuMatch = match.isCpuMatch,
        players    = playersList,
        objectives = match.objectives,
        unitCount  = match.matchData and match.matchData.totalUnits or 0,
    }
end)

exports('IsPlayerInMatch', function(source)
    for _, match in pairs(Matches) do
        if match.players and match.players[source] then return true end
    end
    return false
end)

exports('GetPlayerMatchId', function(source)
    for matchId, match in pairs(Matches) do
        if match.players and match.players[source] then return matchId end
    end
    return nil
end)

exports('GetMatchForPlayer', function(source)
    for matchId, match in pairs(Matches) do
        if match.players and match.players[source] then return match, matchId end
    end
    return nil, nil
end)

-- ---- Match Actions ----

exports('TerminateMatch', function(matchId)
    if Matches[matchId] then
        EndMatch(matchId, { type = "api_terminated", winner = 0 })
        return true
    end
    return false
end)

exports('ForcePlayerToMenu', function(source)
    local matchId, match = GetPlayerMatch(source)
    if match and match.active then
        local winner = GetEnemyPlayer(source, match)
        EndMatch(matchId, { type = "force", winner = winner })
    end
    PlayerStates[source] = nil
    TriggerClientEvent('rts:resetUI', source)
    SetPlayerRoutingBucket(source, 0)
end)

-- ---- Lobby Queries ----

exports('GetActiveLobbies', function()
    local lobbyList = {}
    for code, lobby in pairs(Lobbies) do
        table.insert(lobbyList, {
            code = code,
            hostName = lobby.hostName or "Unknown",
            playerCount = #(lobby.players or {}),
            maxPlayers = lobby.maxPlayers or 2,
            map = lobby.map,
            status = lobby.status,
        })
    end
    return lobbyList
end)

-- ---- Player Stats ----

exports('GetPlayerStats', function(source)
    local identifier = GetPlayerIdentifier(source)
    if not identifier then return nil end

    local success, dbStats = pcall(function()
        return MySQL.single.await('SELECT * FROM rts_player_stats WHERE citizenid = ?', { identifier })
    end)

    if not success or not dbStats then
        return { wins = 0, losses = 0, kills = 0, matches = 0, score = 0, name = GetPlayerName(source) or "Unknown" }
    end

    local lvlInfo = CalculateLevel(dbStats.score or 0)
    return {
        wins   = dbStats.wins or 0,
        losses = dbStats.losses or 0,
        kills  = dbStats.kills or 0,
        matches = dbStats.matches or 0,
        score  = dbStats.score or 0,
        name   = dbStats.name or GetPlayerName(source),
        level  = lvlInfo.level,
    }
end)

exports('GetLeaderboard', function(limit)
    limit = limit or 10
    local result = MySQL.query.await('SELECT name, wins, kills, score FROM rts_player_stats ORDER BY score DESC LIMIT ?', { limit })
    for _, row in ipairs(result) do
        row.level = CalculateLevel(row.score).level
    end
    return result
end)

exports('GetMatchHistory', function(source, limit)
    local cid = GetPlayerIdentifier(source)
    limit = limit or 20
    return MySQL.query.await([[
        SELECT map_name, result, opponent_name, kills, score, date_played
        FROM rts_match_history
        WHERE citizenid = ?
        ORDER BY date_played DESC
        LIMIT ?
    ]], { cid, limit })
end)
