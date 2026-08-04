RegisterNetEvent('rts:joinMatchmaking', function()
    local src = source
    
    if PlayerStates[src] and PlayerStates[src].lobbyId then
        TriggerClientEvent('rts:nuiNotify', src, { message = "Cannot queue while in a lobby", type = "error" })
        return
    end

    for i, p in ipairs(MatchmakingQueue) do
        if p.src == src then return end 
    end
    
    local Player = RTS.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid

    MySQL.scalar('SELECT score FROM rts_player_stats WHERE citizenid = ?', {cid}, function(score)
        local currentScore = score or 0
        local lvlInfo = CalculateLevel(currentScore)

        table.insert(MatchmakingQueue, {
            src = src,
            level = lvlInfo.level,
            joinTime = os.time()
        })
        
        DebugPrint("Player " .. GetPlayerName(src) .. " (Lvl " .. lvlInfo.level .. ") joined matchmaking. Queue size: " .. #MatchmakingQueue)
    end)
end)

RegisterNetEvent('rts:leaveMatchmaking', function()
    local src = source
    for i, p in ipairs(MatchmakingQueue) do
        if p.src == src then
            table.remove(MatchmakingQueue, i)
            DebugPrint("Player " .. GetPlayerName(src) .. " left matchmaking.")
            break
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for i, p in ipairs(MatchmakingQueue) do
        if p.src == src then
            table.remove(MatchmakingQueue, i)
            break
        end
    end
end)

function GetEstimatedWaitTime()
    local online = GetNumPlayerIndices()
    local inQueue = #MatchmakingQueue
    
    local activeMatches = 0
    for _ in pairs(Matches) do activeMatches = activeMatches + 1 end
    
    local playersInMatch = activeMatches * 2
    local availablePlayers = online - playersInMatch - inQueue

    if inQueue >= 1 then
        
        return "5 - 15 SEC"
    elseif availablePlayers >= 4 then
        
        return "30 - 60 SEC"
    elseif availablePlayers >= 2 then
        
        return "1 - 2 MIN"
    elseif online > 1 then
        
        return "2 - 5 MIN"
    else
        
        return "WAITING FOR OPPONENTS"
    end
end

CreateThread(function()
    while true do
        Wait(2000) 

        if #MatchmakingQueue >= 2 then
            
            local matchedIndices = {} 
            
            table.sort(MatchmakingQueue, function(a, b) return a.joinTime < b.joinTime end)
            
            for i = 1, #MatchmakingQueue do
                if not matchedIndices[i] then
                    local p1 = MatchmakingQueue[i]
                    
                    if os.time() - p1.joinTime >= 5 then
                        
                        local bestMatchIndex = nil
                        local smallestLevelDifference = 99999 
                        
                        for j = i + 1, #MatchmakingQueue do
                            if not matchedIndices[j] then
                                local p2 = MatchmakingQueue[j]
                                
                                if os.time() - p2.joinTime >= 5 then
                                    
                                    local levelDiff = math.abs(p1.level - p2.level)
                                    
                                    if levelDiff < smallestLevelDifference then
                                        smallestLevelDifference = levelDiff
                                        bestMatchIndex = j
                                    end
                                end
                            end
                        end
                        
                        if bestMatchIndex then
                            matchedIndices[i] = true
                            matchedIndices[bestMatchIndex] = true
                            
                            local player1_src = p1.src
                            local player2_src = MatchmakingQueue[bestMatchIndex].src
                            
                            DebugPrint("SBMM MATCH FOUND: " .. GetPlayerName(player1_src) .. " (Lvl "..p1.level..") vs " .. GetPlayerName(player2_src) .. " (Lvl "..MatchmakingQueue[bestMatchIndex].level..")")
                            
                            CreateAutoMatch(player1_src, player2_src)
                        end
                    end
                end
            end
            
            for i = #MatchmakingQueue, 1, -1 do
                if matchedIndices[i] then
                    table.remove(MatchmakingQueue, i)
                end
            end
        end
    end
end)

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
        lobbyId = code,
        ready = false,
        platoons = {},
        isHost = true,
        playerName = GetPlayerName(hostId)
    }

    PlayerStates[joinerId] = {
        lobbyId = code,
        ready = false,
        platoons = {},
        isHost = false,
        playerName = GetPlayerName(joinerId)
    }

    local playerNames = { GetPlayerName(hostId), GetPlayerName(joinerId) }
    
    local lobbyData = {
        code = code,
        hostName = GetPlayerName(hostId),
        lobbyData = {
            code = code,
            map = mapName,
            players = Lobbies[code].players,
            playerNames = playerNames,
            status = "waiting"
        }
    }

    lobbyData.isHost = true
    TriggerClientEvent('rts:forceJoinLobby', hostId, lobbyData)

    lobbyData.isHost = false
    TriggerClientEvent('rts:forceJoinLobby', joinerId, lobbyData)

    DebugPrint("Auto-Match created on map: " .. mapName .. " (" .. code .. ")")
end

function CreateCPUMatch(playerId)
    local keys = {} for k in pairs(Config.Maps) do table.insert(keys, k) end
    local mapName = keys[math.random(#keys)] or "grapeseed"
    local code = GenerateLobbyCode()
    local bot = Config.Bots[math.random(#Config.Bots)]

    Lobbies[code] = { code = code, host = playerId, hostName = GetPlayerName(playerId), players = { playerId, bot.id }, readyPlayers = {playerId, bot.id}, platoons = {}, map = mapName, createdAt = os.time(), status = "waiting", maxPlayers = 2 }
    
    PlayerStates[playerId] = { lobbyId = code, ready = true, platoons = {}, isHost = true, playerName = GetPlayerName(playerId) }
    PlayerStates[bot.id] = { lobbyId = code, ready = true, platoons = {}, isHost = false, playerName = bot.name }

    local lobbyData = { code = code, map = mapName, players = Lobbies[code].players, playerNames = {GetPlayerName(playerId), bot.name}, status = "waiting" }
    TriggerClientEvent('rts:forceJoinLobby', playerId, { code = code, hostName = GetPlayerName(playerId), lobbyData = lobbyData, isHost = true })
    SetTimeout(2000, function() StartMatchFromLobby(code) end)
end

RegisterNetEvent('rts:startAiMatchFromQueue', function()
    local src = source
    
    for i, p in ipairs(MatchmakingQueue) do
        if p == src then 
            table.remove(MatchmakingQueue, i) 
            break 
        end
    end

    local mapKeys = {}
    for k, _ in pairs(Config.Maps) do table.insert(mapKeys, k) end
    local randomMap = mapKeys[math.random(1, #mapKeys)]

    local charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local code = ""
    for i = 1, 6 do
        local rand = math.random(1, #charset)
        code = code .. string.sub(charset, rand, rand)
    end

    Lobbies[code] = {
        code = code,
        host = src,
        hostName = GetPlayerName(src),
        players = {src}, 
        readyPlayers = {}, 
        platoons = {},
        map = randomMap,
        createdAt = os.time(),
        status = "waiting",
        maxPlayers = 2,
    }

    PlayerStates[src] = { lobbyId = code, ready = false, platoons = {}, isHost = true, playerName = GetPlayerName(src) }

    local payload = GetLobbyDataPayload(Lobbies[code])
    TriggerClientEvent('rts:forceJoinLobby', src, {
        isHost = true,
        code = code,
        hostName = GetPlayerName(src),
        lobbyData = payload
    })

    SetTimeout(1000, function()
        local lobby = Lobbies[code]
        if not lobby then return end
        
        local bot = Config.Bots[math.random(#Config.Bots)]
        
        table.insert(lobby.players, bot.id)
        PlayerStates[bot.id] = { 
            lobbyId = code, 
            ready = true, 
            platoons = {}, 
            isHost = false, 
            playerName = bot.name 
        }
        
        table.insert(lobby.readyPlayers, bot.id)
        
        lobby.status = "waiting"
        lobby.forceStart = false 

        local newPayload = GetLobbyDataPayload(lobby)
        TriggerClientEvent('rts:updateLobby', src, newPayload)
    end)
end)