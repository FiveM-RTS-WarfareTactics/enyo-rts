-- ====================================================================================
--  MATCH MODULE: Match start, unit spawning, death reporting, end match, surrender,
--                economy tick loop, objective system
-- ====================================================================================

function GetAvailableBucket()
    return math.random(100, 9000)
end

function ReleaseBucket(bucket)
    GameBuckets[bucket] = nil
end

-- Match Management
function StartMatchFromLobby(lobbyCode)
    local lobby = Lobbies[lobbyCode]
    
    -- Double-check that the lobby wasn't aborted during the timeout!
    if not lobby then return end
    if lobby.status ~= "starting" and not lobby.forceStart then return end 
    if #lobby.players ~= Config.MatchSettings.MaxPlayers and not lobby.forceStart then return end

    -- ALLOW THE OVERRIDE BYPASS HERE:
    if not lobby or (#lobby.players ~= Config.MatchSettings.MaxPlayers and not lobby.forceStart) then
        DebugPrint("Cannot start match: Invalid lobby or not enough players")
        return
    end
    
    local matchId = GenerateLobbyCode()
    local gameBucket = GetAvailableBucket()
    local map = Config.Maps[lobby.map]
    
    if not map then DebugPrint("Invalid map: " .. lobby.map) return end
    
    -- 1. Create Match Table
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
    -- 2. INITIALIZE OBJECTIVES
    if map.objectives then
        for _, objective in ipairs(map.objectives) do
            -- Use the objective name as the key
            Matches[matchId].objectives[objective.name] = {
                name = objective.name,
                type = objective.type, -- "victory" or "resource"
                position = vector3(objective.x, objective.y, objective.z),
                
                -- Set defaults if config is missing them
                radius = objective.radius or 15.0, 
                captureRate = objective.captureRate or 5.0,
                bonus = objective.bonus or 0.0, -- Ensure bonus is saved for resource calc
                
                capturingTeam = 0,
                progress = 0,
                controllingTeam = 0,
                captureStartTime = 0
            }
        end
    end
    
    -- Initialize our Discord trackers before the loop starts
    local logPlayersData, sqlLicenses = {}, {}
    local hasBot = false
    
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then hasBot = true end
    end

    -- If the Bot somehow got into Slot 1, swap it with the Human so Human is ALWAYS Team 1!
    if #lobby.players == 2 then
        local p1_isBot = (type(lobby.players[1]) == "string" and string.sub(lobby.players[1], 1, 4) == "bot_")
        if p1_isBot then
            local temp = lobby.players[1]
            lobby.players[1] = lobby.players[2]
            lobby.players[2] = temp
            DebugPrint("Swapped Bot from Team 1 to Team 2 to prevent team-killing.")
        end
    end

    -- Loop Players
    for i, playerId in ipairs(lobby.players) do
        local team = i
        -- ... [rest of the function continues normally] ...
        local playerState = PlayerStates[playerId]
        local isBot = (type(playerId) == "string" and string.sub(playerId, 1, 4) == "bot_")
        
        if isBot then
            -- CPU Player (Mirrors human's platoons for fairness)
            Matches[matchId].players["CPU"] = {
                source = "CPU", team = 2, platoons = playerState.platoons or {}, 
                commandPoints = Config.MatchSettings.CommandPointsStart,
                units = {}, capturedObjectives = {}, kills = 0, unitsLost = 0, damageDealt = 0, 

                -- Ensure the name explicitly contains [AI] and the ID starts with "bot_"
                playerName = "A.I. COMMANDER [AI]", 
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
            TriggerClientEvent('rts:startMatch', playerId, { 
                matchId = matchId, team = team, map = lobby.map, spawnPos = vector3(spawnPos.x, spawnPos.y, spawnPos.z), 
                mapData = map, platoons = playerState.platoons, isCpuMatch = hasBot 
            })
            TriggerClientEvent('rts:updateObjectives', playerId, Matches[matchId].objectives)
        end
    end
    
    -- Cleanup Lobby
    Lobbies[lobbyCode] = nil
    for _, playerId in ipairs(lobby.players) do
        PlayerStates[playerId] = nil
    end
    
    StartMatchTick(matchId)
    StartObjectiveTick(matchId)
    
    DebugPrint("Match started: " .. matchId)

    -- =======================================================================
    -- ENRICHED DISCORD METADATA LOGGER DECK
    -- =======================================================================
    if MySQL and MySQL.query then
        -- Query statistics directly for all players participating in this launch sequence
        MySQL.query("SELECT * FROM rts_player_stats WHERE citizenid IN (?)", { sqlLicenses }, function(dbResults)
            local statsMap = {}
            if dbResults then
                for _, row in ipairs(dbResults) do
                    statsMap[row.citizenid] = row
                end
            end

            -- Begin assembling the embed content block text strings
            local logMsg = string.format("**Match ID:** `#%s`\n**Arena Zone:** `%s`\n**Routing Bucket:** `%s`\n", matchId, lobby.map:upper(), gameBucket)
            logMsg = logMsg .. "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n**COMBATANT OPERATION DOSSIER:**\n"

            for licenseKey, pLog in pairs(logPlayersData) do
                local stats = statsMap[licenseKey] or { wins = 0, losses = 0, kills = 0, score = 0 }
                
                -- Neatly format their active platoon listings
                local platoonStr = "None Selected"
                if pLog.platoons and #pLog.platoons > 0 then
                    platoonStr = table.concat(pLog.platoons, ", ")
                elseif type(pLog.platoons) == "table" then
                    -- Fallback if platoons is key-value based
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
        -- Fallback if the database connector encounters an outage during load
        SendDiscordLog(Webhooks.Matches, "Match Started (Basic Fallback)", "**Match ID:** " .. matchId .. "\n**Map:** " .. lobby.map, 3447003)
    end
end

function StartMatchTick(matchId)
    CreateThread(function()
        local match = Matches[matchId]
        if not match then return end
        
        while match.active do
            Wait(1000) -- Tick every second
            
            local currentTime = os.time()
            local elapsed = currentTime - match.startTime
            local timeLeft = Config.MatchSettings.MatchDuration - elapsed
            
            -- Update command points for all players
            for playerId, playerData in pairs(match.players) do
                if playerData.commandPoints < 10000 then -- Cap at 10000
                    
                    -- 1. Calculate Base Income (Per Second)
                    local basePerSecond = Config.MatchSettings.CommandPointsPerMinute / 60
                    local bonusMultiplier = 0.0
                    
                    -- 2. Calculate Bonuses from Captured Objectives
                    for _, objective in pairs(match.objectives) do
                        -- Check if we own it AND it produces a bonus
                        if objective.controllingTeam == playerData.team and (objective.bonus or 0) > 0 then
                            bonusMultiplier = bonusMultiplier + objective.bonus
                        end
                    end
                    
                    -- 3. Apply Total Income
                    local totalPerSecond = basePerSecond * (1.0 + bonusMultiplier)
                    playerData.commandPoints = playerData.commandPoints + totalPerSecond
                    
                    -- 4. Send REAL Income Rate to Client (Per Minute)
                    -- We send the boosted rate so the UI shows green numbers going up!
                    local realIncomeRate = math.floor(totalPerSecond * 60)
                    
                    TriggerClientEvent('rts:updateResources', playerId, {
                        commandPoints = math.floor(playerData.commandPoints),
                        incomeRate = realIncomeRate 
                    })
                end
            end
            
            -- Update timers
            for playerId in pairs(match.players) do
                TriggerClientEvent('rts:updateMatchTimer', playerId, timeLeft)
            end
            
            -- Check time limit
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
            Wait(1000) -- Updates 2x per second
            
            UpdateObjectives(matchId)
            
            -- Check victory conditions
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
        -- 1. Count Units (Using 2D Distance)
        local counts = { [1] = 0, [2] = 0 }
        
        for _, unit in pairs(match.units) do
            if unit.health > 0 then
                -- Calculate Flat 2D Distance (Fixes hill/elevation bugs)
                local dist = #(vector2(unit.position.x, unit.position.y) - vector2(obj.position.x, obj.position.y))
                
                if dist < obj.radius then
                    counts[unit.team] = counts[unit.team] + 1
                end
            end
        end
        
        -- 2. Determine Dominant Team
        local dominantTeam = 0
        if counts[1] > counts[2] then dominantTeam = 1
        elseif counts[2] > counts[1] then dominantTeam = 2
        end
        
        -- 3. Capture Logic
        local capRate = obj.captureRate or 5.0
        local oldProgress = obj.progress
        local oldOwner = obj.controllingTeam
        local oldCapper = obj.capturingTeam

        if dominantTeam > 0 then
            if obj.controllingTeam == 0 then
                -- Neutral Zone
                if obj.capturingTeam == 0 or obj.capturingTeam == dominantTeam then
                    obj.capturingTeam = dominantTeam
                    obj.progress = math.min(100, obj.progress + capRate)
                else
                    -- Contested
                    obj.progress = math.max(0, obj.progress - capRate)
                    if obj.progress == 0 then obj.capturingTeam = 0 end
                end
                
                if obj.progress >= 100 and obj.capturingTeam == dominantTeam then
                    obj.controllingTeam = dominantTeam
                    TriggerClientEvent('rts:objectiveCaptured', -1, { name = objName, team = dominantTeam, type = obj.type })
                end
            elseif obj.controllingTeam == dominantTeam then
                -- Defending
                obj.progress = math.min(100, obj.progress + capRate)
            else
                -- Attacking Enemy Zone
                obj.progress = math.max(0, obj.progress - capRate)
                if obj.progress <= 0 then
                    obj.controllingTeam = 0
                    obj.capturingTeam = 0
                end
            end
        else
            -- Decay if neutral
            if obj.controllingTeam == 0 and obj.progress > 0 then
                obj.progress = math.max(0, obj.progress - (capRate * 0.5))
                if obj.progress == 0 then obj.capturingTeam = 0 end
            end
        end
        
        -- 4. Mark Dirty if ANY change occurred
        if math.floor(oldProgress) ~= math.floor(obj.progress) or 
           oldOwner ~= obj.controllingTeam or 
           oldCapper ~= obj.capturingTeam then
            dirty = true
        end
    end
    
    -- 5. Broadcast to Clients
    if dirty then
        for playerId, _ in pairs(match.players) do
            TriggerClientEvent('rts:updateObjectives', playerId, match.objectives)
        end
    end
end

function CheckVictoryConditions(matchId)
    local match = Matches[matchId]
    if not match then return nil end
    
    -- 1. Grace Period (e.g. 60 seconds)
    if (os.time() - match.startTime) < 60 then return nil end
    
    -- 2. Check Objectives (Capture Win)
    for _, obj in pairs(match.objectives) do
        if obj.type == "victory" and obj.progress >= 100 then
            return { 
                type = "capture", 
                winner = obj.controllingTeam 
            }
        end
    end
    if Config.MatchSettings.WinOnEliminations then
        -- 3. Check Elimination (Death Match Win)
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
    
    -- Time bonus (per minute)
    local minutes = matchDuration / 60
    local timeBonus = math.floor(minutes * 500)
    cash = cash + timeBonus
    
    -- Performance bonus
    local performanceBonus = math.floor((playerData.kills * 200) - (playerData.unitsLost * 100))
    cash = cash + math.max(0, performanceBonus)
    
    -- Victory bonus
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

-- Unit Management
RegisterNetEvent('rts:spawnPlatoon', function(platoonIndex, position)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    if not match then return end
    
    local playerData = match.players[src]
    
    -- === FIX: FORCE SPAWN AT BASE ===
    -- Get the map config
    local mapConfig = Config.Maps[match.map]
    -- Get the spawn point for THIS team (1 or 2)
    local teamSpawn = (playerData.team == 1) and mapConfig.spawns.team1 or mapConfig.spawns.team2
    
    -- Use this as the center position for the platoon
    local centerPos = vector3(teamSpawn.x, teamSpawn.y, teamSpawn.z)
    -- ================================

    -- 1. Validation Logic
    local pIndex = tostring(platoonIndex)
    local platoon = playerData.platoons[pIndex]
    
    if not platoon or not platoon.units or #platoon.units == 0 then
        DebugPrint("Invalid platoon spawn attempted for index: " .. tostring(platoonIndex))
        TriggerClientEvent('rts:nuiNotify', src, { message = "Invalid platoon", type = "error" })
        return
    end

    -- Check cooldown & Cost
    if playerData.platoonCooldowns and playerData.platoonCooldowns[platoonIndex] and playerData.platoonCooldowns[platoonIndex] > 0 then
        TriggerClientEvent('rts:nuiNotify', src, { message = "Platoon on cooldown", type = "error" })
        return
    end

    if playerData.commandPoints < platoon.totalCost then 
        TriggerClientEvent('rts:nuiNotify', src, { message = "Not enough command points", type = "error" }) 
        return 
    end

    -- [NEW] POPULATION CAP CHECK
    local maxPop = Config.MatchSettings.MaxUnits or 20
    local currentPop = 0
    for _, u in pairs(match.units) do
        if u.owner == src then currentPop = currentPop + 1 end
    end

    if currentPop + (platoon.unitCount or 1) > maxPop then
        TriggerClientEvent('rts:nuiNotify', src, { message = "Unit population cap reached! (Max " .. maxPop .. ")", type = "error" })
        return
    end

    -- Deduct Resources
    playerData.commandPoints = playerData.commandPoints - platoon.totalCost
    TriggerClientEvent('rts:updateResources', src, {
        commandPoints = math.floor(playerData.commandPoints),
        incomeRate = math.floor(Config.MatchSettings.CommandPointsPerMinute)
    })

    -- 2. Spawn Logic
    local spawnedUnitIDs = {} -- Collect ALL IDs here first
    
    for _, unitData in ipairs(platoon.units) do
        local unitConfig = Config.Units[unitData.type]
        if unitConfig then
            for i = 1, (unitData.count or 1) do
                Wait(10)
                local unitId = #match.units + 1
                primaryCategory = unitConfig.category -- Capture the category
                -- Calculate Position
                local angle = math.random() * math.pi * 2
                local distance = math.random() * 17.0 -- (Config.MatchSettings.UnitSpawnRadius or 10.0)
                local offsetX = math.cos(angle) * distance
                local offsetY = math.sin(angle) * distance
                local spawnPos = vector3(centerPos.x + offsetX, centerPos.y + offsetY, centerPos.z + 1.0)

                -- Create Unit Data
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
                table.insert(spawnedUnitIDs, unitId) -- Add to our collection list

                -- Trigger Spawn for Client
                TriggerClientEvent('rts:spawnUnit', src, {
                    unitId = unitId,
                    unitType = unitData.type,
                    position = spawnPos,
                    team = playerData.team,
                    matchId = matchId,
                    
                })
                
                -- Notify Enemy
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

    -- 3. Send Deployed Event (ONCE per click, containing ALL IDs)
    TriggerClientEvent('rts:platoonDeployed', src, {
        name = "SQUAD " .. Config.Platoon.PlatoonSlots[tonumber(platoonIndex)].name,
        icon = Config.Platoon.PlatoonSlots[tonumber(platoonIndex)].icon,
        color = Config.Platoon.PlatoonSlots[tonumber(platoonIndex)].color,
        units = spawnedUnitIDs, -- Sends {1, 2, 3} as one group
        type = platoonIndex,
        category = primaryCategory -- <--- Send this so client knows if it's aircraft
    })

    -- 4. Set Cooldown
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

-- Player Commands
RegisterNetEvent('rts:updateCameraPosition', function(position)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    
    if match and match.players[src] then
        match.players[src].lastCameraPos = position
    end
end)

-- NEW: Link Entity Network ID to RTS Unit ID
RegisterNetEvent('rts:registerUnitEntity', function(matchId, unitId, netId)
    local src = source
    local match = Matches[matchId]
    
    if match and match.units[unitId] then
        -- Update Server Data
        match.units[unitId].netId = netId
        local unitConfig = Config.Units[match.units[unitId].type]
        -- Notify Enemy Player
        local enemyPlayer = GetEnemyPlayer(src, match)
        if enemyPlayer then
            TriggerClientEvent('rts:spawnEnemyUnit', enemyPlayer, {
                unitId = unitId,
                netId = netId, -- Send NetID to enemy
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
        -- Update Server Data
        match.units[unitId].netId = netId
        
        -- Notify Enemy Player
        local enemyPlayer = GetEnemyPlayer(src, match)
        if enemyPlayer then
            TriggerClientEvent('rts:spawnEnemyUnitDriver', enemyPlayer, {
                unitId = unitId,
                netId = netId, -- Send NetID to enemy
                team = match.units[unitId].team,
                type = match.units[unitId].type,
                position = match.units[unitId].position,
                driver = true
            })
        end
    end
end)

-- NEW: Allow clients to report where their units are
RegisterNetEvent('rts:syncUnitPositions', function(updates)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    
    if match then
        for unitId, newPos in pairs(updates) do
            local uid = tonumber(unitId)
            local unit = match.units[uid]
            
            -- Allow update if the player owns it OR if it's a CPU unit in a bot match
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
    
    -- Force convert unitId to number to prevent nil lookups
    local uid = tonumber(unitId)
    local unit = match.units[uid]
    
    if not unit then return end 

    -- 1. Count LOSS for the Owner
    -- We use unit.owner to be safe, rather than 'src'
    local ownerId = unit.owner
    if match.players[ownerId] then
        match.players[ownerId].unitsLost = (match.players[ownerId].unitsLost or 0) + 1
    end

    -- 2. Count KILL for the Enemy (Team Logic)
    -- Loop through all players; if they are NOT on the dead unit's team, they get the kill.
    local enemyId = nil
    
    for pid, pData in pairs(match.players) do
        if pData.team ~= unit.team then
            pData.kills = (pData.kills or 0) + 1
            pData.score = (pData.score or 0) + 100
            enemyId = pid
            
            -- Debug: Check your server console to confirm this prints!
            DebugPrint("^2[RTS KILL] Unit (Team " .. unit.team .. ") Died. Kill awarded to " .. pData.playerName .. " (Team " .. pData.team .. "). Total: " .. pData.kills .. "^7")
        end
    end

    -- 3. Cleanup
    match.units[uid] = nil
    
    -- 4. Notify Clients to remove markers
    TriggerClientEvent('rts:unitDestroyed', ownerId, uid)
    if enemyId then 
        TriggerClientEvent('rts:enemyUnitDestroyed', enemyId, uid) 
    end
end)

-- End Match
function EndMatch(matchId, result)
    local match = Matches[matchId]
    if not match or not match.active then return end
    
    match.active = false
    match.endTime = os.time()
    local matchDuration = match.endTime - match.startTime
    local oldCode = match.lobbyCode
    
    -- Safely transfer the bot to the Rematch Lobby
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
    
    -- ==========================================
    -- DISCORD: SETUP AFTER-ACTION REPORT HEADER
    -- ==========================================
    local discordLogMsg = string.format("**Match ID:** `#%s`\n**Arena Zone:** `%s`\n**Duration:** `%d seconds`\n**Resolution:** `%s`\n", 
        matchId, string.upper(match.map), matchDuration, string.upper(result.type or "Completed"))
    discordLogMsg = discordLogMsg .. "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📋 **AFTER-ACTION REPORT:**\n"
    
    -- Loop players
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
    
    -- ==========================================
    -- DISCORD: FINALIZE AND SEND THE EMBED
    -- ==========================================
    discordLogMsg = discordLogMsg .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    SendDiscordLog(Webhooks.Matches, "Match Concluded", discordLogMsg, 16753920) -- Orange Hex Color
    
    -- Just delete the match and let the players ready up in the lobby themselves
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
        -- Find the winner (The person who didn't surrender)
        local winnerId = GetEnemyPlayer(src, match)
        
        -- Default to 0 (Draw) if something breaks, but usually winnerId exists
        local winningTeam = 0
        if winnerId and match.players[winnerId] then
            winningTeam = match.players[winnerId].team
        end

        DebugPrint("Player " .. GetPlayerName(src) .. " surrendered match " .. matchId)

        -- End the match
        EndMatch(matchId, {
            type = "surrender",
            winner = winningTeam
        })
    end
end)

-- =======================================================================
-- CPU SPAWNER (Bulletproof Mirror Logic & NO-AI Sanitizer)
-- =======================================================================
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

    -- Sanitize NO-AI units on the server
    local validUnits = {}
    local actualAiCost = 0
    local actualAiPop = 0

    for _, uData in ipairs(humanPlatoon.units or {}) do
        local uConf = Config.Units[uData.type]
        -- Filter out units with 'noai = true'
        if uConf and not uConf.noai then
            table.insert(validUnits, uData)
            actualAiCost = actualAiCost + (uConf.cost * (uData.count or 1))
            actualAiPop = actualAiPop + (uData.count or 1)
        end
    end

    -- Abort if the platoon only consisted of NO-AI units
    if #validUnits == 0 then return end

    -- [NEW] POPULATION CAP CHECK FOR BOT
    local maxPop = Config.MatchSettings.MaxUnits or 20
    local currentPop = 0
    for _, u in pairs(match.units) do
        if u.owner == "CPU" then currentPop = currentPop + 1 end
    end

    if currentPop + actualAiPop > maxPop then
        DebugPrint("^1[CPU SERVER] Blocked Bot spawn - Population Cap Reached!^7")
        return
    end

    -- Check bot economy against the SANITIZED cost
    if cpuData.commandPoints < actualAiCost then return end
    cpuData.commandPoints = cpuData.commandPoints - actualAiCost

    local mapConfig = Config.Maps[match.map]
    local centerPos = vector3(mapConfig.spawns.team2.x, mapConfig.spawns.team2.y, mapConfig.spawns.team2.z)

    -- Spawn only the valid units
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
