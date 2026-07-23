-- ====================================================================================
--  MATCHMAKING MODULE: Queue management, SBMM loop, AI match creation, wait time estimation
-- ====================================================================================

-- [[ MATCHMAKING SYSTEM ]] --
RegisterNetEvent('rts:joinMatchmaking', function()
    local src = source
    
    -- 1. Validation: Is player already in a lobby/match?
    if PlayerStates[src] and PlayerStates[src].lobbyId then
        TriggerClientEvent('rts:nuiNotify', src, { message = "Cannot queue while in a lobby", type = "error" })
        return
    end

    -- 2. Avoid duplicates
    for i, p in ipairs(MatchmakingQueue) do
        if p.src == src then return end 
    end
    
    local Player = RTS.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid

    -- 3. Fetch Player Level from DB asynchronously to base the matchmaking on
    MySQL.scalar('SELECT score FROM rts_player_stats WHERE citizenid = ?', {cid}, function(score)
        local currentScore = score or 0
        local lvlInfo = CalculateLevel(currentScore)

        -- Add to queue as an object containing their Level and Join Time
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

-- Cleanup Queue on Disconnect
AddEventHandler('playerDropped', function()
    local src = source
    for i, p in ipairs(MatchmakingQueue) do
        if p.src == src then
            table.remove(MatchmakingQueue, i)
            break
        end
    end
end)

-- [[ DYNAMIC WAIT TIME ESTIMATOR ]] --
function GetEstimatedWaitTime()
    local online = GetNumPlayerIndices()
    local inQueue = #MatchmakingQueue
    
    local activeMatches = 0
    for _ in pairs(Matches) do activeMatches = activeMatches + 1 end
    
    -- Calculate how many people are sitting in the menu doing nothing
    local playersInMatch = activeMatches * 2
    local availablePlayers = online - playersInMatch - inQueue

    -- Logic Tree
    if inQueue >= 1 then
        -- Someone is already waiting. You will match almost instantly (minimum 5s delay).
        return "5 - 15 SEC"
    elseif availablePlayers >= 4 then
        -- Lots of people idling in the menu. Someone will likely queue soon.
        return "30 - 60 SEC"
    elseif availablePlayers >= 2 then
        -- A couple of people idling.
        return "1 - 2 MIN"
    elseif online > 1 then
        -- Everyone else on the server is currently inside a match. You have to wait for them to finish.
        return "2 - 5 MIN"
    else
        -- You are literally the only person on the server.
        return "WAITING FOR OPPONENTS"
    end
end
-- [[ THE MATCHMAKING LOOP (SBMM + 5 Second Delay) ]] --
CreateThread(function()
    while true do
        Wait(2000) -- Check the queue every 2 seconds

        -- Only run if we have at least 2 people in the queue
        if #MatchmakingQueue >= 2 then
            
            local matchedIndices = {} -- Track who gets matched this tick
            
            -- Sort queue so whoever has waited the longest gets priority
            table.sort(MatchmakingQueue, function(a, b) return a.joinTime < b.joinTime end)
            
            for i = 1, #MatchmakingQueue do
                if not matchedIndices[i] then
                    local p1 = MatchmakingQueue[i]
                    
                    -- RULE 1: Player 1 MUST wait at least 5 seconds
                    if os.time() - p1.joinTime >= 5 then
                        
                        local bestMatchIndex = nil
                        local smallestLevelDifference = 99999 -- High starting number
                        
                        -- Look through everyone else in the queue for the closest level
                        for j = i + 1, #MatchmakingQueue do
                            if not matchedIndices[j] then
                                local p2 = MatchmakingQueue[j]
                                
                                -- RULE 2: Player 2 MUST ALSO wait at least 5 seconds
                                if os.time() - p2.joinTime >= 5 then
                                    
                                    -- RULE 3: Find the Closest Level
                                    local levelDiff = math.abs(p1.level - p2.level)
                                    
                                    if levelDiff < smallestLevelDifference then
                                        smallestLevelDifference = levelDiff
                                        bestMatchIndex = j
                                    end
                                end
                            end
                        end
                        
                        -- If we found the best possible match, pair them up!
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
            
            -- Remove matched players from the queue safely (backwards)
            for i = #MatchmakingQueue, 1, -1 do
                if matchedIndices[i] then
                    table.remove(MatchmakingQueue, i)
                end
            end
        end
    end
end)


function CreateAutoMatch(hostId, joinerId)
    -- 1. Random Map Selection
    local keys = {}
    for k in pairs(Config.Maps) do table.insert(keys, k) end
    local mapName = keys[math.random(#keys)] or "grapeseed"

    -- 2. Generate Lobby
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

    -- 3. Set Player States
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

    -- 4. Prepare Data for Clients
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

    -- 5. Force Clients into Lobby
    lobbyData.isHost = true
    TriggerClientEvent('rts:forceJoinLobby', hostId, lobbyData)

    lobbyData.isHost = false
    TriggerClientEvent('rts:forceJoinLobby', joinerId, lobbyData)

    DebugPrint("Auto-Match created on map: " .. mapName .. " (" .. code .. ")")
end

-- =======================================================================
-- CPU MATCHMAKER TIMEOUT & SPAWNER
-- =======================================================================
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

-- =======================================================================
-- INSTANT A.I. MATCH FROM QUEUE (Wait for Player Ready & Persona Names)
-- =======================================================================
RegisterNetEvent('rts:startAiMatchFromQueue', function()
    local src = source
    
    -- 1. Remove player from the queue
    for i, p in ipairs(MatchmakingQueue) do
        if p == src then 
            table.remove(MatchmakingQueue, i) 
            break 
        end
    end

    -- 2. Pick a random Map
    local mapKeys = {}
    for k, _ in pairs(Config.Maps) do table.insert(mapKeys, k) end
    local randomMap = mapKeys[math.random(1, #mapKeys)]

    -- 3. Generate a Lobby Code
    local charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local code = ""
    for i = 1, 6 do
        local rand = math.random(1, #charset)
        code = code .. string.sub(charset, rand, rand)
    end

    -- 4. Build Lobby with ONLY the human player
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

    -- 5. Force the player's UI into the empty lobby
    local payload = GetLobbyDataPayload(Lobbies[code])
    TriggerClientEvent('rts:forceJoinLobby', src, {
        isHost = true,
        code = code,
        hostName = GetPlayerName(src),
        lobbyData = payload
    })

    -- 6. The 1-Second Dramatic Pause
    SetTimeout(1000, function()
        local lobby = Lobbies[code]
        if not lobby then return end
        
        -- Pick a random bot
        local bot = Config.Bots[math.random(#Config.Bots)]
        
        -- Add the Bot to the room using the Bot's ID and Name from Config
        table.insert(lobby.players, bot.id)
        PlayerStates[bot.id] = { 
            lobbyId = code, 
            ready = true, 
            platoons = {}, 
            isHost = false, 
            playerName = bot.name 
        }
        
        -- Ready the bot automatically
        table.insert(lobby.readyPlayers, bot.id)
        
        -- We do NOT ready the human (playerStates[src].ready remains false)
        lobby.status = "waiting"
        lobby.forceStart = false 

        -- Update the UI
        local newPayload = GetLobbyDataPayload(lobby)
        TriggerClientEvent('rts:updateLobby', src, newPayload)
    end)
end)
