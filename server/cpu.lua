-- =============================================================================
--  CPU OPPONENT MODULE - Bot spawning with mirror logic
-- =============================================================================

RegisterNetEvent('rts:server:cpuSpawnPlatoon', function(matchId, platoonIndex)
    local src = source
    local match = Matches[matchId]
    if not match or not match.isCpuMatch then return end

    local cpuData = match.players["CPU"]
    local humanData = match.players[src]
    if not cpuData or not humanData then return end

    local humanPlatoon = nil
    if humanData.platoons then
        humanPlatoon = humanData.platoons[tostring(platoonIndex)] or humanData.platoons[tonumber(platoonIndex)]
    end
    if not humanPlatoon then return end

    -- Filter NO-AI units
    local validUnits = {}
    local actualAiCost = 0
    local actualAiPop = 0

    for _, uData in ipairs(humanPlatoon.units or {}) do
        local uConf = Config.Units[uData.type]
        if uConf and not uConf.noai then
            table.insert(validUnits, uData)
            actualAiCost = actualAiCost + (uConf.cost * (uData.count or 1))
            actualAiPop = actualAiPop + (uData.count or 1)
        end
    end

    if #validUnits == 0 then return end

    -- Population cap
    local maxPop = Config.MatchSettings.MaxUnits or 20
    local currentPop = 0
    for _, u in pairs(match.units) do
        if u.owner == "CPU" then currentPop = currentPop + 1 end
    end
    if currentPop + actualAiPop > maxPop then return end

    if cpuData.commandPoints < actualAiCost then return end
    cpuData.commandPoints = cpuData.commandPoints - actualAiCost

    local mapConfig = Config.Maps[match.map]
    local centerPos = vector3(mapConfig.spawns.team2.x, mapConfig.spawns.team2.y, mapConfig.spawns.team2.z)

    for _, unitData in ipairs(validUnits) do
        local unitConfig = Config.Units[unitData.type]
        if unitConfig then
            for _ = 1, (unitData.count or 1) do
                local unitId = #match.units + 1
                local angle = math.random() * math.pi * 2
                local distance = math.random() * 15.0
                local spawnPos = vector3(
                    centerPos.x + math.cos(angle) * distance,
                    centerPos.y + math.sin(angle) * distance,
                    centerPos.z + 1.0
                )

                match.units[unitId] = {
                    id = unitId, type = unitData.type, owner = "CPU", team = 2,
                    position = spawnPos, health = unitConfig.health, maxHealth = unitConfig.health,
                    category = unitConfig.category, model = unitConfig.model, weapons = unitConfig.weapons
                }

                TriggerClientEvent('rts:client:cpuDoSpawn', src, {
                    unitId = unitId, team = 2, type = unitData.type, health = unitConfig.health, position = spawnPos
                })
            end
        end
    end
end)

function CreateCPUMatch(playerId)
    local keys = {}
    for k in pairs(Config.Maps) do table.insert(keys, k) end
    local mapName = keys[math.random(#keys)] or "grapeseed"
    local code = GenerateLobbyCode()
    local bot = Config.Bots[math.random(#Config.Bots)]

    Lobbies[code] = {
        code = code, host = playerId, hostName = GetPlayerName(playerId),
        players = { playerId, bot.id }, readyPlayers = { playerId, bot.id },
        platoons = {}, map = mapName, createdAt = os.time(), status = "waiting", maxPlayers = 2
    }

    PlayerStates[playerId] = {
        lobbyId = code, ready = true, platoons = {}, isHost = true, playerName = GetPlayerName(playerId)
    }
    PlayerStates[bot.id] = {
        lobbyId = code, ready = true, platoons = {}, isHost = false, playerName = bot.name
    }

    local lobbyData = {
        code = code, map = mapName, players = Lobbies[code].players,
        playerNames = { GetPlayerName(playerId), bot.name }, status = "waiting"
    }

    TriggerClientEvent('rts:forceJoinLobby', playerId, {
        code = code, hostName = GetPlayerName(playerId), lobbyData = lobbyData, isHost = true
    })

    SetTimeout(2000, function() StartMatchFromLobby(code) end)
end
