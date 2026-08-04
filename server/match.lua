local bucketCounter = 100

function GetAvailableBucket()
    local id = bucketCounter
    bucketCounter = bucketCounter + 1
    if bucketCounter > 9000 then bucketCounter = 100 end
    return id
end

function ReleaseBucket(bucket)
    GameBuckets[bucket] = nil
end

function StartMatchFromLobby(lobbyCode)
    local lobby = Lobbies[lobbyCode]
    
    if not lobby then return end
    if lobby.status ~= "starting" and not lobby.forceStart then return end 
    if #lobby.players ~= 2 and not lobby.forceStart then return end

    if not lobby or (#lobby.players ~= 2 and not lobby.forceStart) then
        DebugPrint("Cannot start match: Invalid lobby or not enough players")
        return
    end
    
    local matchId = GenerateLobbyCode()
    local gameBucket = GetAvailableBucket()
    local map = Config.Maps[lobby.map]
    
    if not map then DebugPrint("Invalid map: " .. lobby.map) return end
    
    local hasBot = false
    local botId = nil
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then hasBot = true; botId = pid end
    end

    Matches[matchId] = { 
        id = matchId, lobbyCode = lobbyCode, players = {}, units = {}, objectives = {}, 
        startTime = os.time(), active = true, bucket = gameBucket, map = lobby.map, 
        matchData = { totalUnits = 0, totalDamage = 0, events = {} },
        isCpuMatch = hasBot
    }
    
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
    
    local logPlayersData, sqlLicenses = {}, {}
    local hasBot = false
    
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then hasBot = true end
    end

    if #lobby.players == 2 then
        local p1_isBot = (type(lobby.players[1]) == "string" and string.sub(lobby.players[1], 1, 4) == "bot_")
        if p1_isBot then
            local temp = lobby.players[1]
            lobby.players[1] = lobby.players[2]
            lobby.players[2] = temp
            DebugPrint("Swapped Bot from Team 1 to Team 2 to prevent team-killing.")
        end
    end

    for i, playerId in ipairs(lobby.players) do
        local team = i
        
        local playerState = PlayerStates[playerId]
        local isBot = (type(playerId) == "string" and string.sub(playerId, 1, 4) == "bot_")
        
        if isBot then
            
            local botName = "A.I. COMMANDER [AI]"
            if Config.Bots then
                for _, b in ipairs(Config.Bots) do
                    if b.id == playerId then botName = b.name break end
                end
            end
            Matches[matchId].players["CPU"] = {
                source = "CPU", team = 2, platoons = playerState.platoons or {}, 
                commandPoints = Config.MatchSettings.CommandPointsStart,
                units = {}, capturedObjectives = {}, kills = 0, unitsLost = 0, damageDealt = 0, 
                playerName = botName, 
                identifier = "bot_cpu" 
            }
        else
            local license = GetPlayerIdentifierByType(playerId, 'license') or "license:unknown"
            table.insert(sqlLicenses, license)
            logPlayersData[license] = { src = playerId, name = playerState.playerName or GetPlayerName(playerId), team = team, platoons = playerState.platoons or {} }

            Matches[matchId].players[playerId] = { 
                source = playerId, team = team, platoons = playerState.platoons or {}, 
                commandPoints = Config.MatchSettings.CommandPointsStart, units = {}, capturedObjectives = {}, 
                kills = 0, unitsLost = 0, damageDealt = 0, playerName = playerState.playerName, 
                identifier = license, lastCameraPos = vector3(0,0,0) 
            }
            SetPlayerRoutingBucket(playerId, gameBucket)
            
            local spawnPos = team == 1 and map.spawns.team1 or map.spawns.team2
            
            local pLevel = 1
            if not isBot then
                local pScore = MySQL.scalar.await('SELECT score FROM rts_player_stats WHERE citizenid = ?', {license}) or 0
                pLevel = CalculateLevel(pScore).level
            end
            
            TriggerClientEvent('rts:startMatch', playerId, { 
                matchId = matchId, team = team, map = lobby.map, spawnPos = vector3(spawnPos.x, spawnPos.y, spawnPos.z), 
                mapData = map, platoons = playerState.platoons, isCpuMatch = hasBot,
                botId = botId,
                playerLevel = pLevel
            })
            TriggerClientEvent('rts:updateObjectives', playerId, Matches[matchId].objectives)
        end
    end
    
    Lobbies[lobbyCode] = nil
    for _, playerId in ipairs(lobby.players) do
        PlayerStates[playerId] = nil
    end
    
    StartMatchTick(matchId)
    StartObjectiveTick(matchId)
    
    DebugPrint("Match started: " .. matchId)

    if MySQL and MySQL.query then
        
        MySQL.query("SELECT * FROM rts_player_stats WHERE citizenid IN (?)", { sqlLicenses }, function(dbResults)
            local statsMap = {}
            if dbResults then
                for _, row in ipairs(dbResults) do
                    statsMap[row.citizenid] = row
                end
            end

            local logMsg = string.format("**Match ID:** `#%s`\n**Arena Zone:** `%s`\n**Routing Bucket:** `%s`\n", matchId, lobby.map:upper(), gameBucket)
            logMsg = logMsg .. "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n**COMBATANT OPERATION DOSSIER:**\n"

            for licenseKey, pLog in pairs(logPlayersData) do
                local stats = statsMap[licenseKey] or { wins = 0, losses = 0, kills = 0, score = 0 }
                
                local platoonStr = "None Selected"
                if pLog.platoons and #pLog.platoons > 0 then
                    platoonStr = table.concat(pLog.platoons, ", ")
                elseif type(pLog.platoons) == "table" then
                    
                    local temp = {}
                    for k, v in pairs(pLog.platoons) do table.insert(temp, tostring(v)) end
                    if #temp > 0 then platoonStr = table.concat(temp, ", ") end
                end

                logMsg = logMsg .. string.format(
                    "\n**%s** (ID: `%s` | Team %s)\n" ..
                    "» **License Hash:** `%s`\n" ..
                    "» **Rank Baseline:** `%s pts` (%sW / %sL | %s Kills)\n" ..
                    "» **Deployed Platoons:** *%s*\n",
                    pLog.name, pLog.src, pLog.team, licenseKey, stats.score, stats.wins, stats.losses, stats.kills, platoonStr
                )
            end
            
            logMsg = logMsg .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            SendDiscordLog(Webhooks.Matches, "Match Started Operations", logMsg, 3447003)
        end)
    else
        
        SendDiscordLog(Webhooks.Matches, "Match Started (Basic Fallback)", "**Match ID:** " .. matchId .. "\n**Map:** " .. lobby.map, 3447003)
    end
end

function StartMatchTick(matchId)
    CreateThread(function()
        local match = Matches[matchId]
        if not match then return end
        
        while match.active do
            Wait(1000) 
            
            local currentTime = os.time()
            local elapsed = currentTime - match.startTime
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

function StartObjectiveTick(matchId)
    CreateThread(function()
        local match = Matches[matchId]
        if not match then return end
        
        while match.active do
            Wait(1000) 
            
            UpdateObjectives(matchId)
            
            local victoryResult = CheckVictoryConditions(matchId)
            if victoryResult then
                EndMatch(matchId, victoryResult)
                break
            end
        end
    end)
end

function UpdateObjectives(matchId)
    local match = Matches[matchId]
    if not match then return end
    
    local dirty = false 
    
    for objName, obj in pairs(match.objectives) do
        
        local counts = { [1] = 0, [2] = 0 }
        
        for _, unit in pairs(match.units) do
            if unit.health > 0 then
                
                local dist = #(vector2(unit.position.x, unit.position.y) - vector2(obj.position.x, obj.position.y))
                
                if dist < obj.radius then
                    counts[unit.team] = counts[unit.team] + 1
                end
            end
        end
        
        local dominantTeam = 0
        if counts[1] > counts[2] then dominantTeam = 1
        elseif counts[2] > counts[1] then dominantTeam = 2
        end
        
        local capRate = obj.captureRate or 5.0
        local oldProgress = obj.progress
        local oldOwner = obj.controllingTeam
        local oldCapper = obj.capturingTeam

        if dominantTeam > 0 then
            if obj.controllingTeam == 0 then
                
                if obj.capturingTeam == 0 or obj.capturingTeam == dominantTeam then
                    obj.capturingTeam = dominantTeam
                    obj.progress = math.min(100, obj.progress + capRate)
                else
                    
                    obj.progress = math.max(0, obj.progress - capRate)
                    if obj.progress == 0 then obj.capturingTeam = 0 end
                end
                
                if obj.progress >= 100 and obj.capturingTeam == dominantTeam then
                    obj.controllingTeam = dominantTeam
                    TriggerClientEvent('rts:objectiveCaptured', -1, { name = objName, team = dominantTeam, type = obj.type })
                end
            elseif obj.controllingTeam == dominantTeam then
                
                obj.progress = math.min(100, obj.progress + capRate)
            else
                
                obj.progress = math.max(0, obj.progress - capRate)
                if obj.progress <= 0 then
                    obj.controllingTeam = 0
                    obj.capturingTeam = 0
                end
            end
        else
            
            if obj.controllingTeam == 0 and obj.progress > 0 then
                obj.progress = math.max(0, obj.progress - (capRate * 0.5))
                if obj.progress == 0 then obj.capturingTeam = 0 end
            end
        end
        
        if math.floor(oldProgress) ~= math.floor(obj.progress) or 
           oldOwner ~= obj.controllingTeam or 
           oldCapper ~= obj.capturingTeam then
            dirty = true
        end
    end
    
    if dirty then
        for playerId, _ in pairs(match.players) do
            TriggerClientEvent('rts:updateObjectives', playerId, match.objectives)
        end
    end
end

function CheckVictoryConditions(matchId)
    local match = Matches[matchId]
    if not match then return nil end
    
    if (os.time() - match.startTime) < 60 then return nil end
    
    for _, obj in pairs(match.objectives) do
        if obj.type == "victory" and obj.progress >= 100 then
            return { 
                type = "capture", 
                winner = obj.controllingTeam 
            }
        end
    end
    if Config.MatchSettings.WinOnEliminations then
        
        local units = {[1]=0, [2]=0}
        for _, u in pairs(match.units) do 
            if u.health > 0 then 
                units[u.team] = units[u.team] + 1 
            end 
        end
        
        if units[1] == 0 and units[2] > 0 then return { type = "elimination", winner = 2 } end
        if units[2] == 0 and units[1] > 0 then return { type = "elimination", winner = 1 } end
    end
    return nil
end

function CalculateRewards(playerData, isWinner, matchDuration, resultType)
    local baseRewards = isWinner and Config.Rewards.Victory or Config.Rewards.Defeat
    
    local cash = math.random(baseRewards.cash.min, baseRewards.cash.max)
    local xp = baseRewards.xp
    
    local minutes = matchDuration / 60
    local timeBonus = math.floor(minutes * 500)
    cash = cash + timeBonus
    
    local performanceBonus = math.floor((playerData.kills * 200) - (playerData.unitsLost * 100))
    cash = cash + math.max(0, performanceBonus)
    
    if isWinner and resultType == "elimination" then
        cash = cash + 2000
    elseif isWinner and resultType == "capture" then
        cash = cash + 1500
    end
    
    return {
        cash = cash,
        xp = xp,
        timeBonus = timeBonus,
        performanceBonus = performanceBonus,
        total = cash
    }
end

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
    
    if not platoon or not platoon.units or #platoon.units == 0 then
        DebugPrint("Invalid platoon spawn attempted for index: " .. tostring(platoonIndex))
        TriggerClientEvent('rts:nuiNotify', src, { message = "Invalid platoon", type = "error" })
        return
    end

    if playerData.platoonCooldowns and playerData.platoonCooldowns[platoonIndex] and playerData.platoonCooldowns[platoonIndex] > 0 then
        TriggerClientEvent('rts:nuiNotify', src, { message = "Platoon on cooldown", type = "error" })
        return
    end

    if playerData.commandPoints < platoon.totalCost then 
        TriggerClientEvent('rts:nuiNotify', src, { message = "Not enough command points", type = "error" }) 
        return 
    end

    local maxPop = Config.MatchSettings.MaxUnits or 20
    local currentPop = 0
    for _, u in pairs(match.units) do
        if u.owner == src then currentPop = currentPop + 1 end
    end

    if currentPop + (platoon.unitCount or 1) > maxPop then
        TriggerClientEvent('rts:nuiNotify', src, { message = "Unit population cap reached! (Max " .. maxPop .. ")", type = "error" })
        return
    end

    playerData.commandPoints = playerData.commandPoints - platoon.totalCost
    TriggerClientEvent('rts:updateResources', src, {
        commandPoints = math.floor(playerData.commandPoints),
        incomeRate = math.floor(Config.MatchSettings.CommandPointsPerMinute)
    })

    local spawnedUnitIDs = {} 
    
    for _, unitData in ipairs(platoon.units) do
        local unitConfig = Config.Units[unitData.type]
        if unitConfig then
            for i = 1, (unitData.count or 1) do
                Wait(10)
                local unitId = #match.units + 1
                primaryCategory = unitConfig.category 
                
                local angle = math.random() * math.pi * 2
                local distance = math.random() * 17.0 
                local offsetX = math.cos(angle) * distance
                local offsetY = math.sin(angle) * distance
                local spawnPos = vector3(centerPos.x + offsetX, centerPos.y + offsetY, centerPos.z + 1.0)

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

function GetPlayerMatch(playerId)
    for matchId, match in pairs(Matches) do
        if match.players[playerId] then
            return matchId, match
        end
    end
    return nil, nil
end

function GetEnemyPlayer(playerId, match)
    for id, playerData in pairs(match.players) do
        if id ~= playerId then
            return id
        end
    end
    return nil
end

RegisterNetEvent('rts:updateCameraPosition', function(position)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    
    if match and match.players[src] then
        match.players[src].lastCameraPos = position
    end
end)

RegisterNetEvent('rts:registerUnitEntity', function(matchId, unitId, netId)
    local src = source
    local match = Matches[matchId]
    
    if match and match.units[unitId] then
        
        match.units[unitId].netId = netId
        local unitConfig = Config.Units[match.units[unitId].type]
        
        local enemyPlayer = GetEnemyPlayer(src, match)
        if enemyPlayer then
            TriggerClientEvent('rts:spawnEnemyUnit', enemyPlayer, {
                unitId = unitId,
                netId = netId, 
                team = match.units[unitId].team,
                type = match.units[unitId].type,
                health = unitConfig.health,
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

RegisterNetEvent('rts:reportUnitDeath', function(unitId)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    
    if not match then return end
    
    local uid = tonumber(unitId)
    local unit = match.units[uid]
    
    if not unit then return end 

    local ownerId = unit.owner
    if match.players[ownerId] then
        match.players[ownerId].unitsLost = (match.players[ownerId].unitsLost or 0) + 1
    end

    local enemyId = nil
    
    for pid, pData in pairs(match.players) do
        if pData.team ~= unit.team then
            pData.kills = (pData.kills or 0) + 1
            pData.score = (pData.score or 0) + 100
            enemyId = pid
            
            DebugPrint("^2[RTS KILL] Unit (Team " .. unit.team .. ") Died. Kill awarded to " .. pData.playerName .. " (Team " .. pData.team .. "). Total: " .. pData.kills .. "^7")
        end
    end

    match.units[uid] = nil
    
    TriggerClientEvent('rts:unitDestroyed', ownerId, uid)
    if enemyId then 
        TriggerClientEvent('rts:enemyUnitDestroyed', enemyId, uid) 
    end
end)

function EndMatch(matchId, result)
    local match = Matches[matchId]
    if not match or not match.active then return end
    
    match.active = false
    match.endTime = os.time()
    local matchDuration = match.endTime - match.startTime
    local oldCode = match.lobbyCode
    
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
        status = "waiting", maxPlayers = 2 
    }
    
    local discordLogMsg = string.format("**Match ID:** `#%s`\n**Arena Zone:** `%s`\n**Duration:** `%d seconds`\n**Resolution:** `%s`\n", 
        matchId, string.upper(match.map), matchDuration, string.upper(result.type or "Completed"))
    discordLogMsg = discordLogMsg .. "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📋 **AFTER-ACTION REPORT:**\n"
    
    for pid, pData in pairs(match.players) do
        pcall(function()
            local isBot = (pid == "CPU")
            local isWinner = (result.winner == pData.team)
            local matchScore = (pData.score or 0) + (isWinner and 2000 or 0)
            for _, obj in pairs(match.objectives) do if obj.controllingTeam == pData.team then matchScore = matchScore + 500 end end

            local cid = pData.identifier
            
            local enemyName = "Unknown Force"
            local enemyId = GetEnemyPlayer(pid, match)
            if enemyId and match.players[enemyId] then enemyName = match.players[enemyId].playerName end

            CreateThread(function()
                local currentTotal = MySQL.scalar.await('SELECT score FROM rts_player_stats WHERE citizenid = ?', {cid}) or 0
                local newTotalScore = currentTotal + matchScore
                local lvlInfo = CalculateLevel(newTotalScore)

                MySQL.query([[
                    INSERT INTO rts_player_stats (citizenid, name, wins, losses, kills, units_destroyed, matches, score)
                    VALUES (?, ?, ?, ?, ?, ?, 1, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), wins = wins + VALUES(wins), losses = losses + VALUES(losses), kills = kills + VALUES(kills), matches = matches + 1, score = ? 
                ]], { cid, pData.playerName, isWinner and 1 or 0, isWinner and 0 or 1, pData.kills or 0, pData.kills or 0, matchScore, newTotalScore })

                MySQL.insert([[ INSERT INTO rts_match_history (match_uuid, citizenid, map_name, result, opponent_name, kills, score) VALUES (?, ?, ?, ?, ?, ?, ?) ]], { matchId, cid, match.map, isWinner and 'WIN' or 'LOSS', enemyName, pData.kills or 0, matchScore })

                if not isBot then
                    TriggerClientEvent('rts:endMatch', pid, { victory = isWinner, reason = result.type, levelData = lvlInfo, score = matchScore, showCash = Config.Rewards.ShowCash, cashAmount = 0, stats = { kills = pData.kills or 0, unitsLost = pData.unitsLost or 0, matchTime = matchDuration }, matchData = { nextLobby = oldCode } })
                    Wait(1000) if GetPlayerName(pid) then SetPlayerRoutingBucket(pid, 0) end
                end
            end)
            discordLogMsg = discordLogMsg .. string.format("\n**%s** (Team %s) — %s\n» **Kills:** `%d` | **Units Lost:** `%d`\n» **Score Earned:** `+%d pts`\n", pData.playerName or "Unknown", pData.team, isWinner and "**VICTORY**" or "**DEFEAT**", pData.kills or 0, pData.unitsLost or 0, matchScore)
        end)
    end
    
    discordLogMsg = discordLogMsg .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    SendDiscordLog(Webhooks.Matches, "Match Concluded", discordLogMsg, 16753920) 
    
    SetTimeout(2000, function()
        ReleaseBucket(match.bucket)
        Matches[matchId] = nil
        DebugPrint("Match Ended. Lobby " .. oldCode .. " reset for rematch.")
    end)
end

RegisterNetEvent('rts:surrenderMatch', function()
    local src = source
    local matchId, match = GetPlayerMatch(src)

    if match and match.active then
        
        local winnerId = GetEnemyPlayer(src, match)
        
        local winningTeam = 0
        if winnerId and match.players[winnerId] then
            winningTeam = match.players[winnerId].team
        end

        DebugPrint("Player " .. GetPlayerName(src) .. " surrendered match " .. matchId)

        EndMatch(matchId, {
            type = "surrender",
            winner = winningTeam
        })
    end
end)

RegisterNetEvent('rts:server:cpuSpawnPlatoon', function(matchId, platoonIndex)
    local src = source
    local match = Matches[matchId]
    
    if not match or not match.isCpuMatch then return end

    local cpuData = match.players["CPU"]
    local humanData = match.players[src] 
    
    local humanPlatoon = nil
    if humanData and humanData.platoons then
        humanPlatoon = humanData.platoons[tostring(platoonIndex)] or humanData.platoons[tonumber(platoonIndex)]
    end
    
    if not humanPlatoon then return end

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

    local maxPop = Config.MatchSettings.MaxUnits or 20
    local currentPop = 0
    for _, u in pairs(match.units) do
        if u.owner == "CPU" then currentPop = currentPop + 1 end
    end

    if currentPop + actualAiPop > maxPop then
        DebugPrint("^1[CPU SERVER] Blocked Bot spawn - Population Cap Reached!^7")
        return
    end

    if cpuData.commandPoints < actualAiCost then return end
    cpuData.commandPoints = cpuData.commandPoints - actualAiCost

    local mapConfig = Config.Maps[match.map]
    local centerPos = vector3(mapConfig.spawns.team2.x, mapConfig.spawns.team2.y, mapConfig.spawns.team2.z)

    for _, unitData in ipairs(validUnits) do
        local unitConfig = Config.Units[unitData.type]
        if unitConfig then
            for i = 1, (unitData.count or 1) do
                local unitId = #match.units + 1
                local angle = math.random() * math.pi * 2
                local distance = math.random() * 15.0
                local spawnPos = vector3(centerPos.x + math.cos(angle)*distance, centerPos.y + math.sin(angle)*distance, centerPos.z + 1.0)

                match.units[unitId] = {
                    id = unitId, type = unitData.type, owner = "CPU", team = 2, position = spawnPos,
                    health = unitConfig.health, maxHealth = unitConfig.health, category = unitConfig.category,
                    model = unitConfig.model, weapons = unitConfig.weapons
                }
                
                TriggerClientEvent('rts:client:cpuDoSpawn', src, {
                    unitId = unitId, team = 2, type = unitData.type, health = unitConfig.health, position = spawnPos
                })
            end
        end
    end
end)

RegisterNetEvent('rts:server:botChatMessage', function(matchId, botName, message)
    if not Matches then
        print("^1[RTS ERROR] Matches table is nil!^7")
        return
    end

    local match = Matches[matchId]

    if match and match.active then
        print("^3[RTS CHAT] Bot " .. botName .. " sent: " .. message .. " to match " .. matchId .. "^7")

        for pid, _ in pairs(match.players) do
            if type(pid) == "number" then
                TriggerClientEvent('rts:client:receiveChatMessage', pid, botName, message, "match")
            end
        end

        if Webhooks and Webhooks.Chat then
            local logMsg = string.format("🎮 **[MATCH #%s]**\n🤖 **%s**:\n💬 %s", matchId, botName, message)
            SendDiscordLog(Webhooks.Chat, "RTS Match Chat (A.I.)", logMsg, 15158332)
        end
    else
        print("^1[RTS CHAT] Warning: Attempted to send bot chat, but match " .. tostring(matchId) .. " is invalid or inactive.^7")
    end
end)