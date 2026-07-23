-- =============================================================================
--  MATCH MODULE - Match lifecycle, unit spawning, death tracking
-- =============================================================================

Matches = {}
local GameBuckets = {}

function GetAvailableBucket()
    return math.random(100, 9000)
end

function ReleaseBucket(bucket)
    GameBuckets[bucket] = nil
end

function GetPlayerMatch(playerId)
    for matchId, match in pairs(Matches) do
        if match.players[playerId] then
            return matchId, match
        end
    end
    return nil, nil
end

function GetEnemyPlayer(playerId, match)
    for id, _ in pairs(match.players) do
        if id ~= playerId then return id end
    end
    return nil
end

-- =============================================================================
--  MATCH START
-- =============================================================================

function StartMatchFromLobby(lobbyCode)
    local lobby = Lobbies[lobbyCode]
    if not lobby then return end
    if lobby.status ~= "starting" and not lobby.forceStart then return end
    if #lobby.players ~= Config.MatchSettings.MaxPlayers and not lobby.forceStart then return end

    local matchId = GenerateLobbyCode()
    local gameBucket = GetAvailableBucket()
    local map = Config.Maps[lobby.map]
    if not map then DebugPrint("Invalid map: " .. lobby.map) return end

    -- Detect bot
    local hasBot = false
    local botId = nil
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then hasBot = true; botId = pid end
    end

    Matches[matchId] = {
        id = matchId,
        lobbyCode = lobbyCode,
        players = {},
        units = {},
        objectives = {},
        startTime = os.time(),
        active = true,
        bucket = gameBucket,
        map = lobby.map,
        matchData = { totalUnits = 0, totalDamage = 0, events = {} },
        isCpuMatch = hasBot
    }

    -- Initialize objectives
    if map.objectives then
        for _, objective in ipairs(map.objectives) do
            Matches[matchId].objectives[objective.name] = {
                name = objective.name,
                type = objective.type,
                position = vector3(objective.x, objective.y, objective.z),
                radius = objective.radius or 15.0,
                captureRate = objective.captureRate or 5.0,
                bonus = objective.bonus or 0.0,
                capturingTeam = 0,
                progress = 0,
                controllingTeam = 0,
                captureStartTime = 0
            }
        end
    end

    -- Swap bot to team 2 if needed
    if #lobby.players == 2 then
        local p1_isBot = (type(lobby.players[1]) == "string" and string.sub(lobby.players[1], 1, 4) == "bot_")
        if p1_isBot then
            local temp = lobby.players[1]
            lobby.players[1] = lobby.players[2]
            lobby.players[2] = temp
        end
    end

    for i, playerId in ipairs(lobby.players) do
        local team = i
        local playerState = PlayerStates[playerId]
        local isBot = (type(playerId) == "string" and string.sub(playerId, 1, 4) == "bot_")

        if isBot then
            Matches[matchId].players["CPU"] = {
                source = "CPU",
                team = 2,
                platoons = playerState and playerState.platoons or {},
                commandPoints = Config.MatchSettings.CommandPointsStart,
                units = {},
                capturedObjectives = {},
                kills = 0,
                unitsLost = 0,
                damageDealt = 0,
                playerName = "A.I. COMMANDER [AI]",
                identifier = "bot_cpu"
            }
        else
            local license = GetPlayerIdentifier(playerId)
            Matches[matchId].players[playerId] = {
                source = playerId,
                team = team,
                platoons = playerState and playerState.platoons or {},
                commandPoints = Config.MatchSettings.CommandPointsStart,
                units = {},
                capturedObjectives = {},
                kills = 0,
                unitsLost = 0,
                damageDealt = 0,
                playerName = playerState and playerState.playerName or GetPlayerName(playerId),
                identifier = license,
                lastCameraPos = vector3(0, 0, 0)
            }

            SetPlayerRoutingBucket(playerId, gameBucket)

            local spawnPos = team == 1 and map.spawns.team1 or map.spawns.team2
            TriggerClientEvent('rts:startMatch', playerId, {
                matchId = matchId,
                team = team,
                map = lobby.map,
                spawnPos = vector3(spawnPos.x, spawnPos.y, spawnPos.z),
                mapData = map,
                platoons = PlayerStates[playerId].platoons,
                isCpuMatch = hasBot
            })
            TriggerClientEvent('rts:updateObjectives', playerId, Matches[matchId].objectives)
        end
    end

    -- Cleanup lobby
    Lobbies[lobbyCode] = nil
    for _, playerId in ipairs(lobby.players) do
        PlayerStates[playerId] = nil
    end

    StartMatchTick(matchId)
    StartObjectiveTick(matchId)

    -- Fire event for third-party scripts
    TriggerEvent('rts:matchStarted', {
        matchId = matchId,
        map = lobby.map,
        isCpuMatch = hasBot,
        players = Matches[matchId].players,
    })

    DebugPrint("Match started: " .. matchId)
end

-- =============================================================================
--  MATCH TICK (Economy)
-- =============================================================================

function StartMatchTick(matchId)
    CreateThread(function()
        local match = Matches[matchId]
        if not match then return end

        while match.active do
            Wait(1000)

            local elapsed = os.time() - match.startTime
            local timeLeft = Config.MatchSettings.MatchDuration - elapsed

            for playerId, playerData in pairs(match.players) do
                if playerData.commandPoints < 10000 then
                    local basePerSecond = Config.MatchSettings.CommandPointsPerMinute / 60
                    local bonusMultiplier = 0.0

                    for _, objective in pairs(match.objectives) do
                        if objective.controllingTeam == playerData.team and (objective.bonus or 0) > 0 then
                            bonusMultiplier = bonusMultiplier + objective.bonus
                        end
                    end

                    local totalPerSecond = basePerSecond * (1.0 + bonusMultiplier)
                    playerData.commandPoints = playerData.commandPoints + totalPerSecond

                    local realIncomeRate = math.floor(totalPerSecond * 60)

                    TriggerClientEvent('rts:updateResources', playerId, {
                        commandPoints = math.floor(playerData.commandPoints),
                        incomeRate = realIncomeRate
                    })
                end
            end

            -- Update timer
            for playerId in pairs(match.players) do
                TriggerClientEvent('rts:updateMatchTimer', playerId, timeLeft)
            end

            if timeLeft <= 0 then
                EndMatch(matchId, { type = "timeout", winner = 0 })
                break
            end
        end
    end)
end

-- =============================================================================
--  UNIT SPAWNING
-- =============================================================================

RegisterNetEvent('rts:spawnPlatoon', function(platoonIndex, position)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    if not match then return end

    local playerData = match.players[src]
    local mapConfig = Config.Maps[match.map]
    local teamSpawn = (playerData.team == 1) and mapConfig.spawns.team1 or mapConfig.spawns.team2
    local centerPos = vector3(teamSpawn.x, teamSpawn.y, teamSpawn.z)

    local pIndex = tostring(platoonIndex)
    local platoon = playerData.platoons[pIndex]
    if not platoon or not platoon.units or #platoon.units == 0 then return end

    -- Cooldown check
    if playerData.platoonCooldowns and playerData.platoonCooldowns[platoonIndex] and playerData.platoonCooldowns[platoonIndex] > 0 then
        NotifyPlayer(src, "Platoon on cooldown", "error")
        return
    end

    if playerData.commandPoints < platoon.totalCost then
        NotifyPlayer(src, "Not enough command points", "error")
        return
    end

    -- Population cap
    local maxPop = Config.MatchSettings.MaxUnits or 20
    local currentPop = 0
    for _, u in pairs(match.units) do
        if u.owner == src then currentPop = currentPop + 1 end
    end
    if currentPop + (platoon.unitCount or 1) > maxPop then
        NotifyPlayer(src, "Unit population cap reached! (Max " .. maxPop .. ")", "error")
        return
    end

    playerData.commandPoints = playerData.commandPoints - platoon.totalCost
    TriggerClientEvent('rts:updateResources', src, {
        commandPoints = math.floor(playerData.commandPoints),
        incomeRate = math.floor(Config.MatchSettings.CommandPointsPerMinute)
    })

    local spawnedUnitIDs = {}
    local primaryCategory = nil

    for _, unitData in ipairs(platoon.units) do
        local unitConfig = Config.Units[unitData.type]
        if unitConfig then
            primaryCategory = unitConfig.category
            for _ = 1, (unitData.count or 1) do
                Wait(10)
                local unitId = #match.units + 1
                local angle = math.random() * math.pi * 2
                local distance = math.random() * 17.0
                local spawnPos = vector3(
                    centerPos.x + math.cos(angle) * distance,
                    centerPos.y + math.sin(angle) * distance,
                    centerPos.z + 1.0
                )

                match.units[unitId] = {
                    id = unitId,
                    type = unitData.type,
                    owner = src,
                    team = playerData.team,
                    position = spawnPos,
                    health = unitConfig.health,
                    maxHealth = unitConfig.health,
                    category = unitConfig.category,
                    model = unitConfig.model,
                    weapons = unitConfig.weapons
                }

                match.matchData.totalUnits = match.matchData.totalUnits + 1
                table.insert(playerData.units, unitId)
                table.insert(spawnedUnitIDs, unitId)

                TriggerClientEvent('rts:spawnUnit', src, {
                    unitId = unitId,
                    unitType = unitData.type,
                    position = spawnPos,
                    team = playerData.team,
                    matchId = matchId,
                })

                local enemyPlayer = GetEnemyPlayer(src, match)
                if enemyPlayer then
                    TriggerClientEvent('rts:spawnEnemyUnit', enemyPlayer, {
                        unitId = unitId,
                        team = playerData.team,
                        type = unitData.type,
                        health = unitConfig.health,
                        position = spawnPos
                    })
                end
            end
        end
    end

    TriggerClientEvent('rts:platoonDeployed', src, {
        name = "SQUAD " .. Config.Platoon.PlatoonSlots[tonumber(platoonIndex)].name,
        icon = Config.Platoon.PlatoonSlots[tonumber(platoonIndex)].icon,
        color = Config.Platoon.PlatoonSlots[tonumber(platoonIndex)].color,
        units = spawnedUnitIDs,
        type = platoonIndex,
        category = primaryCategory
    })

    -- Set cooldown
    if not playerData.platoonCooldowns then playerData.platoonCooldowns = {} end
    playerData.platoonCooldowns[platoonIndex] = Config.MatchSettings.RespawnCooldown

    CreateThread(function()
        local cooldown = Config.MatchSettings.RespawnCooldown
        while cooldown > 0 and match.active do
            Wait(1000)
            cooldown = cooldown - 1
            playerData.platoonCooldowns[platoonIndex] = cooldown
            TriggerClientEvent('rts:updatePlatoonCooldown', src, platoonIndex, cooldown)
        end
    end)
end)

-- =============================================================================
--  UNIT ENTITY REGISTRATION
-- =============================================================================

RegisterNetEvent('rts:registerUnitEntity', function(matchId, unitId, netId)
    local src = source
    local match = Matches[matchId]
    if match and match.units[unitId] then
        match.units[unitId].netId = netId
        local enemyPlayer = GetEnemyPlayer(src, match)
        if enemyPlayer then
            TriggerClientEvent('rts:spawnEnemyUnit', enemyPlayer, {
                unitId = unitId,
                netId = netId,
                team = match.units[unitId].team,
                type = match.units[unitId].type,
                health = Config.Units[match.units[unitId].type].health,
                position = match.units[unitId].position
            })
        end
    end
end)

RegisterNetEvent('rts:registerUnitEntityDriver', function(matchId, unitId, netId)
    local src = source
    local match = Matches[matchId]
    if match and match.units[unitId] then
        match.units[unitId].netId = netId
        local enemyPlayer = GetEnemyPlayer(src, match)
        if enemyPlayer then
            TriggerClientEvent('rts:spawnEnemyUnitDriver', enemyPlayer, {
                unitId = unitId,
                netId = netId,
                team = match.units[unitId].team,
                type = match.units[unitId].type,
                position = match.units[unitId].position,
                driver = true
            })
        end
    end
end)

RegisterNetEvent('rts:syncUnitPositions', function(updates)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    if match then
        for unitId, newPos in pairs(updates) do
            local uid = tonumber(unitId)
            local unit = match.units[uid]
            if unit and (unit.owner == src or (unit.owner == "CPU" and match.isCpuMatch)) then
                unit.position = vector3(newPos.x, newPos.y, newPos.z)
            end
        end
    end
end)

-- =============================================================================
--  DEATH REPORTING
-- =============================================================================

RegisterNetEvent('rts:reportUnitDeath', function(unitId)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    if not match then return end

    local uid = tonumber(unitId)
    local unit = match.units[uid]
    if not unit then return end

    -- Count loss for owner
    local ownerId = unit.owner
    if match.players[ownerId] then
        match.players[ownerId].unitsLost = (match.players[ownerId].unitsLost or 0) + 1
    end

    -- Count kill for enemy
    local enemyId = nil
    for pid, pData in pairs(match.players) do
        if pData.team ~= unit.team then
            pData.kills = (pData.kills or 0) + 1
            pData.score = (pData.score or 0) + 100
            enemyId = pid
        end
    end

    match.units[uid] = nil

    TriggerClientEvent('rts:unitDestroyed', ownerId, uid)
    if enemyId then
        TriggerClientEvent('rts:enemyUnitDestroyed', enemyId, uid)
    end
end)

-- =============================================================================
--  END MATCH
-- =============================================================================

function EndMatch(matchId, result)
    local match = Matches[matchId]
    if not match or not match.active then return end

    match.active = false
    match.endTime = os.time()
    local matchDuration = match.endTime - match.startTime
    local oldCode = match.lobbyCode

    -- Reset lobby for rematch
    local remPlayers = {}
    local remReady = {}
    for pid, pData in pairs(match.players) do
        if pid == "CPU" then
            local safeId = pData.identifier or "bot_cpu"
            local safeName = pData.playerName or "A.I. COMMANDER [AI]"
            if not string.find(safeName, "%[AI%]") then safeName = safeName .. " [AI]" end
            table.insert(remPlayers, safeId)
            table.insert(remReady, safeId)
            PlayerStates[safeId] = {
                lobbyId = oldCode, ready = true, platoons = {}, isHost = false, playerName = safeName
            }
        end
    end

    Lobbies[oldCode] = {
        code = oldCode, host = nil, hostName = "Waiting for Commander...",
        players = remPlayers, readyPlayers = remReady,
        platoons = {}, map = match.map, createdAt = os.time(),
        status = "waiting", maxPlayers = Config.MatchSettings.MaxPlayers
    }

    -- Calculate rewards
    for pid, pData in pairs(match.players) do
        pcall(function()
            local isBot = (pid == "CPU")
            local isWinner = (result.winner == pData.team)
            local matchScore = (pData.score or 0) + (isWinner and 2000 or 0)

            for _, obj in pairs(match.objectives) do
                if obj.controllingTeam == pData.team then matchScore = matchScore + 500 end
            end

            local cid = pData.identifier

            if not isBot then
                local enemyName = "Unknown Force"
                local enemyId = GetEnemyPlayer(pid, match)
                if enemyId and match.players[enemyId] then
                    enemyName = match.players[enemyId].playerName
                end

                CreateThread(function()
                    local currentTotal = MySQL.scalar.await('SELECT score FROM rts_player_stats WHERE citizenid = ?', { cid }) or 0
                    local newTotalScore = currentTotal + matchScore
                    local lvlInfo = CalculateLevel(newTotalScore)

                    MySQL.query([[
                        INSERT INTO rts_player_stats (citizenid, name, wins, losses, kills, units_destroyed, matches, score)
                        VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                        ON DUPLICATE KEY UPDATE
                            name = VALUES(name),
                            wins = wins + VALUES(wins),
                            losses = losses + VALUES(losses),
                            kills = kills + VALUES(kills),
                            matches = matches + 1,
                            score = ?
                    ]], { cid, pData.playerName, isWinner and 1 or 0, isWinner and 0 or 1, pData.kills or 0, pData.kills or 0, matchScore, newTotalScore })

                    MySQL.insert([[
                        INSERT INTO rts_match_history (match_uuid, citizenid, map_name, result, opponent_name, kills, score)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    ]], { matchId, cid, match.map, isWinner and 'WIN' or 'LOSS', enemyName, pData.kills or 0, matchScore })

                    TriggerClientEvent('rts:endMatch', pid, {
                        victory = isWinner,
                        reason = result.type,
                        levelData = lvlInfo,
                        score = matchScore,
                        stats = {
                            kills = pData.kills or 0,
                            unitsLost = pData.unitsLost or 0,
                            matchTime = matchDuration
                        },
                        matchData = { nextLobby = oldCode }
                    })

                    Wait(1000)
                    if GetPlayerName(pid) then SetPlayerRoutingBucket(pid, 0) end
                end)
            end
        end)
    end

    SetTimeout(2000, function()
        ReleaseBucket(match.bucket)

        -- Fire event for third-party scripts
        TriggerEvent('rts:matchEnded', {
            matchId = matchId,
            map = match.map,
            duration = matchDuration,
            reason = result.type,
            winner = result.winner,
        })

        Matches[matchId] = nil
        DebugPrint("Match Ended. Lobby " .. oldCode .. " reset for rematch.")
    end)
end

-- =============================================================================
--  SURRENDER
-- =============================================================================

RegisterNetEvent('rts:surrenderMatch', function()
    local src = source
    local matchId, match = GetPlayerMatch(src)
    if match and match.active then
        local winnerId = GetEnemyPlayer(src, match)
        local winningTeam = 0
        if winnerId and match.players[winnerId] then
            winningTeam = match.players[winnerId].team
        end
        EndMatch(matchId, { type = "surrender", winner = winningTeam })
    end
end)

-- =============================================================================
--  FORCE JOIN (for quick match)
-- =============================================================================

function CreateAutoMatch(hostId, joinerId)
    local keys = {}
    for k in pairs(Config.Maps) do table.insert(keys, k) end
    local mapName = keys[math.random(#keys)] or "grapeseed"

    local code = GenerateLobbyCode()

    Lobbies[code] = {
        code = code,
        host = hostId,
        hostName = GetPlayerName(hostId),
        players = { hostId, joinerId },
        readyPlayers = {},
        platoons = {},
        map = mapName,
        createdAt = os.time(),
        status = "waiting",
        maxPlayers = 2
    }

    PlayerStates[hostId] = {
        lobbyId = code, ready = false, platoons = {}, isHost = true, playerName = GetPlayerName(hostId)
    }
    PlayerStates[joinerId] = {
        lobbyId = code, ready = false, platoons = {}, isHost = false, playerName = GetPlayerName(joinerId)
    }

    local lobbyData = {
        code = code,
        map = mapName,
        players = Lobbies[code].players,
        playerNames = { GetPlayerName(hostId), GetPlayerName(joinerId) },
        status = "waiting"
    }

    TriggerClientEvent('rts:forceJoinLobby', hostId, { code = code, hostName = GetPlayerName(hostId), lobbyData = lobbyData, isHost = true })
    TriggerClientEvent('rts:forceJoinLobby', joinerId, { code = code, hostName = GetPlayerName(hostId), lobbyData = lobbyData, isHost = false })

    DebugPrint("Auto-Match created on map: " .. mapName .. " (" .. code .. ")")
end
