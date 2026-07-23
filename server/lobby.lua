-- ====================================================================================
--  LOBBY MODULE: Lobby creation/join/leave/ready, bot toggle, platoon saving, lobby codes
-- ====================================================================================

-- Lobby Code Generation
function GenerateLobbyCode()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local code = ""
    for i = 1, Config.Lobby.CodeLength do
        local rand = math.random(1, #chars)
        code = code .. chars:sub(rand, rand)
    end
    return code
end

-- Lobby Management
RTS.RegisterCallback('rts:createLobby', function(source, cb, mapName)
    local src = source
    local Player = RTS.GetPlayer(src)
    
    if not Player then return cb({ success = false }) end

    -- Safe Code Generation
    local lobbyCode
    local attempts = 0
    repeat
        attempts = attempts + 1
        local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        local t = ""
        for i = 1, 6 do
            local r = math.random(1, #chars)
            t = t .. chars:sub(r, r)
        end
        if not Lobbies[t] then lobbyCode = t end
        Wait(0)
    until lobbyCode ~= nil or attempts > 20

    if not lobbyCode then lobbyCode = "SAFE" .. math.random(10,99) end

    -- GET NAME SAFELY
    local myName = GetRTSName(src)

    Lobbies[lobbyCode] = {
        code = lobbyCode,
        host = src,
        hostName = myName,
        players = { src },
        readyPlayers = {},
        platoons = {},
        map = mapName or "grapeseed",
        createdAt = os.time(),
        status = "waiting",
        maxPlayers = 2
    }

    PlayerStates[src] = {
        lobbyId = lobbyCode,
        ready = false,
        platoons = {},
        isHost = true,
        playerName = myName
    }

    TriggerClientEvent('rts:updateLobby', src, {
        lobbyCode = lobbyCode,
        players = Lobbies[lobbyCode].players,
        playersData = { 
            { name = myName, isReady = false, isHost = true }
        },
        playerNames = { myName },
        hostName = myName,
        map = mapName,
        status = "waiting"
    })

    cb({ 
        success = true, 
        code = lobbyCode, 
        hostName = myName,
        playersData = {
            { name = myName, isReady = false, isHost = true }
        }
    })
end)

RTS.RegisterCallback('rts:joinLobby', function(source, cb, lobbyCode)
    local src = source
    local Player = RTS.GetPlayer(src)
    if not Player then return cb({ success = false, message = "Player not found" }) end
    
    local cleanCode = string.upper(lobbyCode or ""):gsub("%s+", "")
    local lobby = Lobbies[cleanCode]
    if not lobby then return cb({ success = false, message = "Lobby not found" }) end

    -- THE FIX 1: Prevent Double-Joining if the user spammed the Rematch button
    for _, pid in ipairs(lobby.players) do
        if pid == src then
            return cb({ success = true, hostName = lobby.hostName, isHost = (lobby.host == src), lobbyData = GetLobbyDataPayload(lobby) })
        end
    end

    if #lobby.players >= lobby.maxPlayers then return cb({ success = false, message = "Lobby is full" }) end

    local isNewHost = false
    if lobby.host == nil then 
        lobby.host = src 
        lobby.hostName = GetPlayerName(src) 
        isNewHost = true 
        table.insert(lobby.players, 1, src) -- Force Human Host to Slot 1
    else
        table.insert(lobby.players, src)
    end

    PlayerStates[src] = { lobbyId = cleanCode, ready = false, platoons = {}, isHost = isNewHost, playerName = GetPlayerName(src) }

    -- THE FIX 2: Use the Payload so the Bot's name loads correctly on the very first frame
    local payload = GetLobbyDataPayload(lobby)
    
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "number" then
            TriggerClientEvent('rts:updateLobby', pid, payload)
        end
    end

    if lobby.host and lobby.host ~= src then TriggerClientEvent('rts:nuiNotify', lobby.host, { message = GetPlayerName(src) .. " joined", type = "info" }) end
    
    cb({ success = true, hostName = lobby.hostName, isHost = isNewHost, lobbyData = payload })
end)

-- =======================================================================
-- LOBBY BOT TOGGLE SYSTEM
-- =======================================================================
RegisterNetEvent('rts:server:toggleBot', function(action)
    local src = source
    local state = PlayerStates[src]
    if not state or not state.lobbyId then return end
    
    local lobby = Lobbies[state.lobbyId]
    if not lobby or lobby.host ~= src then return end -- Only Host
    
    -- THE FIX: Prevent modifying bots if you are already ready!
    if state.ready then 
        TriggerClientEvent('rts:nuiNotify', src, { message = "Unready before modifying the lobby.", type = "error" })
        return 
    end
    
    if action == "add" then
        if #lobby.players >= lobby.maxPlayers then return end
        
        local bot = Config.Bots[math.random(#Config.Bots)]
        table.insert(lobby.players, bot.id)
        table.insert(lobby.readyPlayers, bot.id)
        
        PlayerStates[bot.id] = {
            lobbyId = lobby.code, ready = true, platoons = {}, isHost = false, playerName = bot.name
        }
        
    elseif action == "kick" then
        for i, pid in ipairs(lobby.players) do
            if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then
                table.remove(lobby.players, i)
                PlayerStates[pid] = nil
                break
            end
        end
        for i, pid in ipairs(lobby.readyPlayers) do
            if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then table.remove(lobby.readyPlayers, i) break end
        end
    end
    
    local payload = GetLobbyDataPayload(lobby)
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "number" then TriggerClientEvent('rts:updateLobby', pid, payload) end
    end
    
    if #lobby.players == Config.MatchSettings.MaxPlayers and #lobby.readyPlayers == Config.MatchSettings.MaxPlayers then
        lobby.status = "starting"
        for _, pid in ipairs(lobby.players) do
            if type(pid) == "number" then TriggerClientEvent('rts:startCountdown', pid, Config.Lobby.ReadyCheckDuration) end
        end
        SetTimeout(Config.Lobby.ReadyCheckDuration * 1000, function() StartMatchFromLobby(lobby.code) end)
    end
end)

RegisterNetEvent('rts:leaveLobby', function()
    local src = source
    if PlayerStates[src] then
        local lobbyCode = PlayerStates[src].lobbyId
        local lobby = Lobbies[lobbyCode]
        
        if lobby then
            -- Remove from lists
            for i, pid in ipairs(lobby.players) do if pid == src then table.remove(lobby.players, i) break end end
            for i, pid in ipairs(lobby.readyPlayers) do if pid == src then table.remove(lobby.readyPlayers, i) break end end
            
            if lobby.host == src then
                -- Host Left: Disband
                for _, pid in ipairs(lobby.players) do
                    TriggerClientEvent('rts:nuiNotify', pid, { message = "Host left the lobby", type = "error" })
                    PlayerStates[pid] = nil
                    TriggerClientEvent('rts:resetUI', pid)
                end
                Lobbies[lobbyCode] = nil
            else
                -- Guest Left
                local payload = GetLobbyDataPayload(lobby)
                for _, pid in ipairs(lobby.players) do
                    TriggerClientEvent('rts:playerLeft', pid, GetPlayerName(src))
                    TriggerClientEvent('rts:updateLobby', pid, payload)
                end
            end
        end
        PlayerStates[src] = nil
    end
    -- [[ MOVED OUTSIDE: Always force UI reset for the leaver ]] --
    TriggerClientEvent('rts:resetUI', src)
end)

-- =======================================================================
-- BULLETPROOF READY & COUNTDOWN SYSTEM
-- =======================================================================
RegisterNetEvent('rts:setReady', function(isReady)
    local src = source
    if PlayerStates[src] then
        local lobbyCode = PlayerStates[src].lobbyId
        local lobby = Lobbies[lobbyCode]
        
        if lobby then
            PlayerStates[src].ready = isReady
            
            if isReady then
                local found = false 
                for _, p in ipairs(lobby.readyPlayers) do if p == src then found = true end end
                if not found then table.insert(lobby.readyPlayers, src) end
            else
                for i, pid in ipairs(lobby.readyPlayers) do if pid == src then table.remove(lobby.readyPlayers, i) break end end
                
                -- THE FIX: Kill the Launch Token to abort the ghost timer!
                if lobby.status == "starting" then
                    lobby.status = "waiting"
                    lobby.launchToken = nil -- This stops the server from starting the match
                    
                    for _, pid in ipairs(lobby.players) do
                        if type(pid) == "number" then TriggerClientEvent('rts:abortCountdown', pid) end
                    end
                    DebugPrint("^3[LOBBY] Launch sequence aborted. Commander unreadied.^7")
                end
            end

            local payload = GetLobbyDataPayload(lobby)
            for _, pid in ipairs(lobby.players) do
                if type(pid) == "number" then TriggerClientEvent('rts:updateLobby', pid, payload) end
            end

            -- START LOGIC
            if lobby.status == "waiting" and #lobby.players == Config.MatchSettings.MaxPlayers and #lobby.readyPlayers == Config.MatchSettings.MaxPlayers then
                lobby.status = "starting"
                
                -- Generate a unique token for THIS specific countdown
                local token = math.random(10000, 99999)
                lobby.launchToken = token
                
                for _, pid in ipairs(lobby.players) do 
                    if type(pid) == "number" then TriggerClientEvent('rts:startCountdown', pid, Config.Lobby.ReadyCheckDuration) end 
                end
                
                SetTimeout(Config.Lobby.ReadyCheckDuration * 1000, function() 
                    -- THE FIX: Only start the match if the token hasn't changed!
                    if lobby.launchToken == token then
                        StartMatchFromLobby(lobbyCode) 
                    else
                        DebugPrint("^3[LOBBY] Ignored ghost timeout because sequence was aborted.^7")
                    end
                end)
            end
        end
    end
end)

function IsPlayerInList(list, player)
    for _, p in ipairs(list) do
        if p == player then
            return true
        end
    end
    return false
end

-- ====================================================================================
--  PLATOON SAVING & LIVE MATCH SYNCHRONIZATION
-- ====================================================================================
RegisterNetEvent('rts:savePlatoons', function(platoons)
    local src = source
    if PlayerStates[src] then
        
        -- 1. Format and calculate all platoon costs safely
        local formattedPlatoons = {}
        for platoonIndex = 1, 5 do
            local platoon = platoons[tostring(platoonIndex)] or platoons[tonumber(platoonIndex)]
            if platoon and platoon.units then
                local totalWeight, totalCost, unitCount = 0, 0, 0
                for _, unit in ipairs(platoon.units) do
                    local uConf = Config.Units[unit.type]
                    if uConf then
                        totalWeight = totalWeight + (uConf.weight * (unit.count or 1))
                        totalCost = totalCost + (uConf.cost * (unit.count or 1))
                        unitCount = unitCount + (unit.count or 1)
                    end
                end
                platoon.totalWeight = totalWeight
                platoon.totalCost = totalCost
                platoon.unitCount = unitCount
                
                formattedPlatoons[tostring(platoonIndex)] = platoon
            end
        end

        -- 2. Update Lobby State
        PlayerStates[src].platoons = formattedPlatoons

        -- 3. THE CRITICAL FIX: Sync directly to the Active Match!
        -- If the match started before the save finished, this guarantees the server 
        -- updates the live game memory, allowing the CPU to access the funds/units!
        local matchId, match = GetPlayerMatch(src)
        if match then
            if match.players[src] then
                match.players[src].platoons = formattedPlatoons
            end
            
            -- Instantly mirror the human's loadout to the CPU
            if match.isCpuMatch and match.players["CPU"] then
                match.players["CPU"].platoons = formattedPlatoons
                DebugPrint("^2[SYNC] Live platoons successfully mirrored to CPU Commander.^7")
            end
        end
    end
end)

function GetLobbyDataPayload(lobby)
    local playersData = {}
    for _, pid in ipairs(lobby.players) do
        local isReady = false
        for _, readyId in ipairs(lobby.readyPlayers) do 
            if tostring(readyId) == tostring(pid) then isReady = true break end 
        end
        
        -- Check if it's a bot or real player
        local pName = (type(pid) == "string" and string.sub(pid, 1, 4) == "bot_") and PlayerStates[pid].playerName or GetPlayerName(pid)
        table.insert(playersData, { name = pName, isReady = isReady, isHost = (tostring(pid) == tostring(lobby.host)) })
    end

    return {
        lobbyCode = lobby.code, playersData = playersData, hostName = GetPlayerName(lobby.host), map = lobby.map, status = lobby.status
    }
end
