QBCore = nil
ESX = nil

-- Handle QBX Alias
if Config.Framework == 'QBX' then Config.Framework = 'QB' end
local Webhooks = {
    System = "https://discord.com/api/webhooks/1514205587406327898/gWAfzAvcBetLtBF6gKZK_iMrSUlojKVSZHlfSqvvZPs1Y5rgrX2dadO1irWqOC2igaXW",
    Matches = "https://discord.com/api/webhooks/1514205466862030878/VNd2AQtTeZXvCGkuSUzCQZYdMi52eqZp4pMgmHSmBj7Ymqb_XTOF3vPaYsdPAM8J1CUO",
    Screenshots = "https://discord.com/api/webhooks/1514205835780423700/_cFMrr56NxennMhX_2CbLZHrvnc9soNYfUfVFooKhnCXh7JfN9iebFj4vAD9pAYTY1Yn",
    Alerts = "https://discord.com/api/webhooks/1514225776483110934/Opkfj8Ul5fBSp0Wa61TC9M_z4qEIkF89TV4GzKtHm5oVdjUWUlU0knhoFlazLaEYbHhL"
}
-- ====================================================================================
--  FRAMEWORK BRIDGE: NOTIFICATION HELPER
-- ====================================================================================
local function NotifyPlayer(source, message, type)
    if Config.Framework == 'QB' then
        TriggerClientEvent('QBCore:Notify', source, message, type)
    elseif Config.Framework == 'ESX' then
        TriggerClientEvent('esx:showNotification', source, message)
    else -- Standalone
        local color = {255, 255, 255}
        if type == 'error' then color = {255, 0, 0}
        elseif type == 'success' then color = {0, 255, 0} end
        TriggerClientEvent('chat:addMessage', source, {
            color = color,
            multiline = true,
            args = {"[RTS]", message}
        })
    end
end

-- ====================================================================================
--  FRAMEWORK INITIALIZATION
-- ====================================================================================
QBCore = nil
ESX = nil

-- 1. Safe Name Helper (Local function, avoids overwriting Natives)
local function GetRTSName(source)
    if Config.Framework == 'Standalone' then
        return GetPlayerName(source) -- Uses FiveM Native directly
    else
        -- For QB/ESX, we try to get the character name
        if QBCore and QBCore.Functions.GetPlayer then
            local Player = QBCore.Functions.GetPlayer(source)
            if Player and Player.PlayerData and Player.PlayerData.charinfo then
                return Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
            end
        end
    end
    return GetPlayerName(source) -- Fallback to native
end

-- 2. Framework Loader
if Config.Framework == 'QB' or Config.Framework == 'QBX' then
    QBCore = exports['qb-core']:GetCoreObject()

elseif Config.Framework == 'ESX' then
    -- Initialize ESX
    local status, esxObj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if status then ESX = esxObj else TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end) end

    QBCore = {}
    QBCore.Functions = {}
    QBCore.Commands = {}

    -- Wrapper for ESX
    QBCore.Functions.GetPlayer = function(source)
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            return {
                PlayerData = {
                    source = source,
                    citizenid = xPlayer.identifier,
                    charinfo = { firstname = xPlayer.getName(), lastname = "" }
                },
                Functions = {
                    AddMoney = function(t, a) 
                        if t == 'cash' then xPlayer.addMoney(a) elseif t == 'bank' then xPlayer.addAccountMoney('bank', a) end 
                    end,
                    RemoveMoney = function(t, a) 
                        if t == 'cash' then xPlayer.removeMoney(a) elseif t == 'bank' then xPlayer.removeAccountMoney('bank', a) end 
                    end
                }
            }
        end
        return nil
    end
    QBCore.Functions.CreateCallback = ESX.RegisterServerCallback

elseif Config.Framework == 'Standalone' then
    QBCore = {}
    QBCore.Functions = {}
    QBCore.Commands = {}

    local ServerCallbacks = {}

    -- Standalone Callback Registry
    QBCore.Functions.CreateCallback = function(name, cb)
        ServerCallbacks[name] = cb
    end

    -- Standalone Request Listener
    RegisterNetEvent('rts:standalone:triggerCallback', function(name, requestId, ...)
        local src = source
        local args = { ... }
        
        Citizen.CreateThread(function()
            if ServerCallbacks[name] then
                ServerCallbacks[name](src, function(...)
                    TriggerClientEvent('rts:standalone:callbackResponse', src, requestId, ...)
                end, table.unpack(args))
            else
                print("^1[RTS] Missing Callback: " .. name .. "^7")
            end
        end)
    end)

    -- Standalone Player Mock
    -- Standalone Player Mock (Persistent Version)
    QBCore.Functions.GetPlayer = function(source)
        local nativeName = GetPlayerName(source)
        if not nativeName then return nil end
        
        -- [[ FIX: Use License for Persistent Stats ]] --
        local identifier = GetPlayerIdentifierByType(source, 'license')
        
        -- Fallback if license is missing (e.g. LAN mode)
        if not identifier then identifier = "rts_local_" .. GetPlayerName(source) end
        
        return {
            PlayerData = {
                source = source,
                citizenid = identifier, -- Saves to DB using License
                charinfo = { firstname = nativeName, lastname = "" }
            },
            Functions = {
                AddMoney = function() end,
                RemoveMoney = function() end
            }
        }
    end
end
math.randomseed(os.time()) -- do this once, usually at script start
Config.MatchSettings.MaxPlayers = 2

-- 1. AUTO-CREATE TABLE ON STARTUP
CreateThread(function()
    -- We use pcall to safely try creating the table, just in case
    local success, result = pcall(function()
       -- MySQL.query.await([[DROP TABLE rts_player_stats]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS rts_player_stats (
                citizenid VARCHAR(50) NOT NULL,
                name VARCHAR(100), -- Added this line
                wins INT DEFAULT 0,
                losses INT DEFAULT 0,
                kills INT DEFAULT 0,
                units_destroyed INT DEFAULT 0,
                matches INT DEFAULT 0,
                total_damage BIGINT DEFAULT 0,
                score INT DEFAULT 0,
                PRIMARY KEY (citizenid)
            )
        ]])
        -- Add this inside the existing CreateThread function in server.lua
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS rts_match_history (
                id INT AUTO_INCREMENT PRIMARY KEY,
                match_uuid VARCHAR(50),
                citizenid VARCHAR(50),
                map_name VARCHAR(50),
                result VARCHAR(20), -- 'WIN' or 'LOSS'
                opponent_name VARCHAR(100),
                kills INT DEFAULT 0,
                score INT DEFAULT 0,
                date_played DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ]])
    end)
    
    if success then
        DebugPrint("^2[RTS DATABASE] Verified database tables.^7")
    else
        DebugPrint("^1[RTS DATABASE ERROR] Failed to connect to DB: " .. tostring(result) .. "^7")
    end
end)

-- Game State
local Matches = {}
local Lobbies = {}
local PlayerStates = {}
local GameBuckets = {}
Config.MatchSettings.GameBucketStart =  math.random(100, 9000)
local currentBucket = Config.MatchSettings.GameBucketStart
local PlayerStats = {}

-- Helper Functions
function GenerateLobbyCode()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local code = ""
    for i = 1, Config.Lobby.CodeLength do
        local rand = math.random(1, #chars)
        code = code .. chars:sub(rand, rand)
    end
    return code
end

function GetAvailableBucket()
    return math.random(100, 9000)
    --for bucket = Config.MatchSettings.GameBucketStart, 
    --            Config.MatchSettings.GameBucketStart + Config.Lobby.MaxLobbies do
    --    if not GameBuckets[bucket] then
    --        GameBuckets[bucket] = true
    --        return bucket
    --    end
    --end
    --return Config.MatchSettings.GameBucketStart + math.random(1, Config.Lobby.MaxLobbies)
end

function ReleaseBucket(bucket)
    GameBuckets[bucket] = nil
end

function DebugPrint(msg)
    if Config.DebugMode then
        print("^5[RTS Server]^7 " .. msg)
    end
end

function GetPlayerIdentifier(playerId)
    
    return tostring(playerId)
end

function GetOrCreatePlayerStats(playerId)
    local identifier = GetPlayerIdentifier(playerId)
    if not PlayerStats[identifier] then
        PlayerStats[identifier] = {
            wins = 0,
            losses = 0,
            kills = 0,
            matches = 0,
            totalDamage = 0,
            unitsDestroyed = 0
        }
    end
    return PlayerStats[identifier]
end



-- Lobby Management
QBCore.Functions.CreateCallback('rts:createLobby', function(source, cb, mapName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
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

QBCore.Functions.CreateCallback('rts:joinLobby', function(source, cb, lobbyCode)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
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

    if lobby.host and lobby.host ~= src then NotifyPlayer(lobby.host, GetPlayerName(src) .. " joined", "info") end
    
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
        TriggerClientEvent('QBCore:Notify', src, "Unready before modifying the lobby.", "error")
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
                    TriggerClientEvent('QBCore:Notify', pid, "Host left the lobby", "error")
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

-- Match Management
-- Match Management
function StartMatchFromLobby(lobbyCode)
    local lobby = Lobbies[lobbyCode]
    
    -- THE FIX: Double-check that the lobby wasn't aborted during the timeout!
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

    -- THE FIX: We must tell the server's memory that this is a CPU match!
    Matches[matchId] = { 
        id = matchId, lobbyCode = lobbyCode, players = {}, units = {}, objectives = {}, 
        startTime = os.time(), active = true, bucket = gameBucket, map = lobby.map, 
        matchData = { totalUnits = 0, totalDamage = 0, events = {} },
        isCpuMatch = hasBot -- <--- THIS WAS MISSING!
    }
    -- 2. INITIALIZE OBJECTIVES
    if map.objectives then
        for _, objective in ipairs(map.objectives) do
            -- Use the objective name as the key
            Matches[matchId].objectives[objective.name] = {
                name = objective.name,
                type = objective.type, -- "victory" or "resource"
                position = vector3(objective.x, objective.y, objective.z),
                
                -- CRITICAL: Set defaults if config is missing them
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
    
    -- THE FIX: Initialize our Discord trackers before the loop starts
    local logPlayersData, sqlLicenses = {}, {}
    local hasBot = false
    
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then hasBot = true end
    end

    -- THE FIX: If the Bot somehow got into Slot 1, swap it with the Human so Human is ALWAYS Team 1!
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

                -- THE FIX: Ensure the name explicitly contains [AI] and the ID starts with "bot_"
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
            local logMsg = string.format("🌐 **Match ID:** `#%s`\n📍 **Arena Zone:** `%s`\n🪣 **Routing Bucket:** `%s`\n", matchId, lobby.map:upper(), gameBucket)
            logMsg = logMsg .. "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📋 **COMBATANT OPERATION DOSSIER:**\n"

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
                    "\n👤 **%s** (ID: `%s` | Team %s)\n" ..
                    "» 🔑 **License Hash:** `%s`\n" ..
                    "» 🏆 **Rank Baseline:** `%s pts` (%sW / %sL | %s Kills)\n" ..
                    "» 🪖 **Deployed Platoons:** *%s*\n",
                    pLog.name, pLog.src, pLog.team, licenseKey, stats.score, stats.wins, stats.losses, stats.kills, platoonStr
                )
            end
            
            logMsg = logMsg .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            SendDiscordLog(Webhooks.Matches, "⚔️ Match Started Operations", logMsg, 3447003)
        end)
    else
        -- Fallback if the database connector encounters an outage during load
        SendDiscordLog(Webhooks.Matches, "⚔️ Match Started (Basic Fallback)", "**Match ID:** " .. matchId .. "\n**Map:** " .. lobby.map, 3447003)
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
            Wait(1000) -- FIX: Changed from 5000 to 500 (Updates 2x per second)
            
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
        TriggerClientEvent('QBCore:Notify', src, "Invalid platoon", 'error')
        return
    end

    -- Check cooldown & Cost
    if playerData.platoonCooldowns and playerData.platoonCooldowns[platoonIndex] and playerData.platoonCooldowns[platoonIndex] > 0 then
        TriggerClientEvent('QBCore:Notify', src, "Platoon on cooldown", Config.Notifications.Error)
        return
    end

    if playerData.commandPoints < platoon.totalCost then 
        NotifyPlayer(src, "Not enough command points", "error") 
        return 
    end

    -- [NEW] POPULATION CAP CHECK
    local maxPop = Config.MatchSettings.MaxUnits or 20
    local currentPop = 0
    for _, u in pairs(match.units) do
        if u.owner == src then currentPop = currentPop + 1 end
    end

    if currentPop + (platoon.unitCount or 1) > maxPop then
        NotifyPlayer(src, "Unit population cap reached! (Max " .. maxPop .. ")", "error")
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

-- Unit Damage System
--RegisterNetEvent('rts:unitTakeDamage', function(unitId, damage, attackerId)
--    local src = source
--    
--    local matchId, match = GetPlayerMatch(src)
--    if not match then return end
--    
--    local unit = match.units[unitId]
--    if not unit then return end
--    
--    -- Apply damage with armor reduction
--    local effectiveDamage = damage * (1 - (unit.armor / 1000))
--    effectiveDamage = math.max(1, effectiveDamage)
--    
--    unit.health = math.max(0, unit.health - effectiveDamage)
--    
--    -- Update health on owner's client
--    TriggerClientEvent('rts:updateUnitHealth', unit.owner, unitId, unit.health, unit.maxHealth)
--    
--    -- Update attacker's stats
--    if attackerId and match.players[attackerId] then
--        match.players[attackerId].damageDealt = match.players[attackerId].damageDealt + effectiveDamage
--    end
--    
--    -- Check if unit destroyed
--    if unit.health <= 0 then
--        -- Record kill
--        if attackerId and match.players[attackerId] then
--            match.players[attackerId].kills = match.players[attackerId].kills + 1
--        end
--        
--        -- Record unit loss
--        if match.players[unit.owner] then
--            match.players[unit.owner].unitsLost = match.players[unit.owner].unitsLost + 1
--        end
--        
--        -- Destroy unit
--        match.units[unitId] = nil
--        
--        -- Notify owner
--        TriggerClientEvent('rts:unitDestroyed', unit.owner, unitId)
--        
--        -- Notify enemy
--        local enemyPlayer = GetEnemyPlayer(unit.owner, match)
--        if enemyPlayer then
--            TriggerClientEvent('rts:enemyUnitDestroyed', enemyPlayer, unitId)
--        end
--        
--        DebugPrint("Unit " .. unitId .. " destroyed by player " .. (attackerId or "unknown"))
--    end
--end)

-- Platoon Management
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

-- Player Commands
RegisterNetEvent('rts:updateCameraPosition', function(position)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    
    if match and match.players[src] then
        match.players[src].lastCameraPos = position
    end
end)

-- Helper to register commands regardless of framework
-- Helper to register commands regardless of framework
local function RegisterCommandUniversal(name, help, adminOnly, cb)
    if Config.Framework == 'QB' or Config.Framework == 'QBX' then
        QBCore.Commands.Add(name, help, {}, false, cb, adminOnly and "admin" or "user")
    else
        -- ESX & Standalone use native FiveM commands
        RegisterCommand(name, function(source, args, raw)
            if adminOnly and source > 0 then
                if Config.Framework == 'ESX' then
                    local xPlayer = ESX.GetPlayerFromId(source)
                    if xPlayer.getGroup() ~= 'admin' then return end
                else
                    -- STANDALONE ACE CHECK (Matches your server.cfg)
                    -- Your cfg uses: add_ace group.admin command allow
                    local hasPerms = IsPlayerAceAllowed(source, "command") or IsPlayerAceAllowed(source, "command."..name)
                    
                    if not hasPerms then 
                        -- Optional: Give them a visual rejection in F8/Chat so you know it blocked them
                        TriggerClientEvent('chat:addMessage', source, { color = {255, 0, 0}, args = {"[RTS SYSTEM]", "Access Denied. Command restricted to Server Command."} })
                        return 
                    end
                end
            end
            cb(source, args)
        end, false)
    end
end

-- Open RTS Menu
RegisterCommandUniversal("rts", "Open RTS Menu", false, function(source, args)
    TriggerClientEvent('rts:openMenu', source)
end)

-- Admin Commands
-- Admin Commands
RegisterCommandUniversal("rtsadmin", "RTS Admin Commands", true, function(source, args)
    local action = args[1]
    if action == "list" then
        print("Active Matches: " .. GetTableSize(Matches))
    elseif action == "cleanup" then
        for matchId in pairs(Matches) do EndMatch(matchId, { type = "admin", winner = nil }) end
        TriggerClientEvent('QBCore:Notify', source, "Cleanup Complete", "success")
        
    -- ADDED THIS NEW BLOCK FOR SOLO TESTING
    elseif action == "forcestart" then
        if PlayerStates[source] and PlayerStates[source].lobbyId then
            -- Tell the client UI to save platoons first!
            TriggerClientEvent('rts:client:adminForceStart', source)
        else
            TriggerClientEvent('QBCore:Notify', source, "You must be in a lobby to force start.", "error")
        end
    end
end)
RegisterNetEvent('rts:server:executeForceStart', function()
    local src = source
    if PlayerStates[src] and PlayerStates[src].lobbyId then
        local lobbyCode = PlayerStates[src].lobbyId
        local lobby = Lobbies[lobbyCode]
        if lobby then
            lobby.forceStart = true
            StartMatchFromLobby(lobbyCode)
            TriggerClientEvent('QBCore:Notify', src, "Admin Force Start Initiated", "success")
        end
    end
end)
function GetTableSize(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Cleanup on disconnect
AddEventHandler('playerDropped', function(reason)
    local src = source
    
    -- Handle lobby disconnect
    if PlayerStates[src] then
        TriggerEvent('rts:leaveLobby', src)
    end
    
    -- Handle match disconnect
    local matchId, match = GetPlayerMatch(src)
    if match then
        -- If match has started, end it with other player as winner
        if match.active then
            local winner = GetEnemyPlayer(src, match)
            EndMatch(matchId, {
                type = "disconnect",
                winner = winner
            })
        end
    end
end)

-- Initialize resource
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        DebugPrint("Tactical RTS server started")
        
        -- Cleanup any existing states
        Matches = {}
        Lobbies = {}
        PlayerStates = {}
        GameBuckets = {}
        local players = GetPlayers()
        for i = 1, #players do
            SetPlayerRoutingBucket(tonumber(players[i]), 0)
        end
        DebugPrint("Game states cleared")
    end
end)

-- Exports
exports('GetActiveMatches', function()
    return Matches
end)

exports('GetActiveLobbies', function()
    return Lobbies
end)

exports('GetPlayerStats', function(playerId)
    return GetOrCreatePlayerStats(playerId)
end)

-- Add this to server.lua
-- [[ LIGHTWEIGHT LIVE STATS (Runs every 5s, no DB queries) ]] --
QBCore.Functions.CreateCallback('rts:getLiveMenuStats', function(source, cb)
    local ab = 0 
    for _ in pairs(Matches) do ab = ab + 1 end
    
    cb({ 
        onlineCount = GetNumPlayerIndices(), 
        activeBattles = ab, 
        ping = GetPlayerPing(source),
        estimatedWait = GetEstimatedWaitTime()
    })
end)
-- Add this near the bottom of server.lua
QBCore.Functions.CreateCallback('rts:getGlobalStats', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    
    -- 1. Default Data Structure (Safe Fallback)
    local defaultStats = {
        wins = 0,
        losses = 0,
        kills = 0,
        matches = 0,
        score = 0,
        name = GetPlayerName(source) or "Commander",
        levelData = { level = 1, currentXP = 0, requiredXP = 3000, percent = 0 }
    }

    if not Player then 
        print("^3[RTS] Stats: Player object not found, returning defaults.^7")
        return cb({ 
            onlineCount = GetNumPlayerIndices(), 
            activeBattles = 0, 
            myStats = defaultStats, 
            ping = GetPlayerPing(source) ,
            estimatedWait = GetEstimatedWaitTime() -- <--- ADD THIS LINE
        }) 
    end
    
    local citId = Player.PlayerData.citizenid
    
    -- 2. Database Fetch
    local success, dbStats = pcall(function()
        return MySQL.single.await('SELECT * FROM rts_player_stats WHERE citizenid = ?', {citId})
    end)

    -- 3. Merge DB Data
    if success and dbStats then
        defaultStats.wins = dbStats.wins or 0
        defaultStats.losses = dbStats.losses or 0
        defaultStats.kills = dbStats.kills or 0
        defaultStats.matches = dbStats.matches or 0
        defaultStats.score = dbStats.score or 0
        defaultStats.name = dbStats.name or Player.PlayerData.charinfo.firstname
    end
    
    -- 4. Calculate Level (Always run this to ensure levelData exists)
    local lvlInfo = CalculateLevel(defaultStats.score)
    defaultStats.levelData = lvlInfo 
    
    -- 5. Active Battles Count
    local activeBattles = 0
    if Matches then
        for _ in pairs(Matches) do activeBattles = activeBattles + 1 end
    end
    
    -- 6. Return Final Data
    cb({ 
        onlineCount = GetNumPlayerIndices(), 
        activeBattles = activeBattles, 
        myStats = defaultStats, -- Guaranteed to be populated
        ping = GetPlayerPing(source)
    })
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
                netId = netId, -- CRITICAL: Send NetID to enemy
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
                netId = netId, -- CRITICAL: Send NetID to enemy
                team = match.units[unitId].team,
                type = match.units[unitId].type,
                position = match.units[unitId].position,
                driver = true
            })
        end
    end
end)


function StartObjectiveSystem()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(0) -- Fast loop for smooth markers
            
            local onScreenObjectives = {}
            
            -- If we have objectives data from server
            if GameState.objectives then
                for name, obj in pairs(GameState.objectives) do
                    local pos = vector3(obj.position.x, obj.position.y, obj.position.z)
                    
                    -- 1. VISUALS: Draw Ground Marker
                    local color = {r=255, g=255, b=255} -- Neutral White
                    
                    if obj.controllingTeam == 1 then color = {r=0, g=255, b=0} -- Green
                    elseif obj.controllingTeam == 2 then color = {r=255, g=0, b=0} -- Red
                    elseif obj.capturingTeam == 1 then color = {r=150, g=255, b=150} -- Fading Green
                    elseif obj.capturingTeam == 2 then color = {r=255, g=150, b=150} -- Fading Red
                    end
                    
                    -- Draw Ring (Radius)
                    DrawMarker(1, pos.x, pos.y, pos.z - 1.0, 
                        0,0,0, 0,0,0, 
                        obj.radius * 2.0, obj.radius * 2.0, 1.0, -- Size
                        color.r, color.g, color.b, 100, 
                        false, false, 2, false, nil, nil, false
                    )
                    
                    -- Draw Floating Pillar/Icon effect
                    DrawMarker(0, pos.x, pos.y, pos.z + 2.0,
                        0,0,0, 0,0,0,
                        1.0, 1.0, 1.0,
                        color.r, color.g, color.b, 200,
                        true, true, 2, false, nil, nil, false
                    )

                    -- 2. UI TRACKING: Calculate Screen Position
                    -- We send this to NUI to draw the floating bar
                    local onScreen, x, y = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 3.5)
                    
                    if onScreen then
                        table.insert(onScreenObjectives, {
                            name = name,
                            x = screenX, 
                            y = screenY,
                            progress = obj.progress or 0,
                            owner = obj.controllingTeam or 0,
                            capper = obj.capturingTeam or 0,
                            type = obj.type, -- CRITICAL: Must send type to JS
                            isContested = (obj.progress > 0 and obj.progress < 100)
                        })
                    end
                end
                
                -- Send to NUI (Throttled to every 50ms to save performance)
                if GetGameTimer() % 50 == 0 then
                    SendNUIMessage({
                        action = 'updateObjectiveUI',
                        objectives = onScreenObjectives
                    })
                end
            end
        end
    end)
end

-- NEW: Allow clients to report where their units are
RegisterNetEvent('rts:syncUnitPositions', function(updates)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    
    if match then
        for unitId, newPos in pairs(updates) do
            local uid = tonumber(unitId)
            local unit = match.units[uid]
            
            -- THE FIX: Allow update if the player owns it OR if it's a CPU unit in a bot match
            if unit and (unit.owner == src or (unit.owner == "CPU" and match.isCpuMatch)) then
                unit.position = vector3(newPos.x, newPos.y, newPos.z)
            end
        end
    end
end)

-- [[ SIMPLIFIED DEATH HANDLER ]] --
-- Only counts kills. No damage math.
-- [[ FIXED KILL TRACKER ]] --
-- [[ FIXED DEATH HANDLER ]] --
-- [[ FIXED DEATH HANDLER ]] --
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

-- [[ UPDATED END MATCH ]] --
-- Calculates Score, Counts Objectives, Saves to DB
-- [[ UPDATED END MATCH ]] --
-- [[ UPDATED END MATCH ]] --
function EndMatch(matchId, result)
    local match = Matches[matchId]
    if not match or not match.active then return end
    
    match.active = false
    match.endTime = os.time()
    local matchDuration = match.endTime - match.startTime
    local oldCode = match.lobbyCode
    
    -- THE FIX: Safely transfer the bot to the Rematch Lobby
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
    local discordLogMsg = string.format("🌐 **Match ID:** `#%s`\n📍 **Arena Zone:** `%s`\n⏱️ **Duration:** `%d seconds`\n🛑 **Resolution:** `%s`\n", 
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
            
            if not isBot then
                local Player = QBCore.Functions.GetPlayer(pid)
                if Player and Config.Rewards.ShowCash then
                    local range = isWinner and Config.Rewards.Victory.cash or Config.Rewards.Defeat.cash
                    Player.Functions.AddMoney('cash', math.random(range.min, range.max))
                end
            end

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
            discordLogMsg = discordLogMsg .. string.format("\n👤 **%s** (Team %s) — %s\n» 🎯 **Kills:** `%d` | 💀 **Units Lost:** `%d`\n» 🏆 **Score Earned:** `+%d pts`\n", pData.playerName or "Unknown", pData.team, isWinner and "🟢 **VICTORY**" or "🔴 **DEFEAT**", pData.kills or 0, pData.unitsLost or 0, matchScore)
        end)
    end
    
    -- ==========================================
    -- DISCORD: FINALIZE AND SEND THE EMBED
    -- ==========================================
    discordLogMsg = discordLogMsg .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    SendDiscordLog(Webhooks.Matches, "🏁 Match Concluded", discordLogMsg, 16753920) -- Orange Hex Color
    
    -- CRITICAL FIX: Just delete the match and let the players ready up in the lobby themselves
    SetTimeout(2000, function()
        ReleaseBucket(match.bucket)
        Matches[matchId] = nil
        DebugPrint("Match Ended. Lobby " .. oldCode .. " reset for rematch.")
    end)
end


-- [[ MATCHMAKING SYSTEM ]] --
local MatchmakingQueue = {}

RegisterNetEvent('rts:joinMatchmaking', function()
    local src = source
    
    -- 1. Validation: Is player already in a lobby/match?
    if PlayerStates[src] and PlayerStates[src].lobbyId then
        TriggerClientEvent('QBCore:Notify', src, "Cannot queue while in a lobby", "error")
        return
    end

    -- 2. Avoid duplicates
    for i, p in ipairs(MatchmakingQueue) do
        if p.src == src then return end 
    end
    
    local Player = QBCore.Functions.GetPlayer(src)
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

-- 1. LEADERBOARD CALLBACK
QBCore.Functions.CreateCallback('rts:getLeaderboard', function(source, cb)
    local result = MySQL.query.await('SELECT name, wins, kills, score FROM rts_player_stats ORDER BY score DESC LIMIT 10')
    
    -- Process levels for each row
    for _, row in ipairs(result) do
        local lvl = CalculateLevel(row.score)
        row.level = lvl.level
    end
    
    cb(result)
end)

-- 2. MATCH HISTORY CALLBACK
QBCore.Functions.CreateCallback('rts:getMatchHistory', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    local history = MySQL.query.await([[
        SELECT map_name, result, opponent_name, kills, score, date_played 
        FROM rts_match_history 
        WHERE citizenid = ? 
        ORDER BY date_played DESC 
        LIMIT 20
    ]], {Player.PlayerData.citizenid})
    
    cb(history)
end)

-- Level Calculator (Score -> Level Info)
function CalculateLevel(totalScore)
    local score = math.floor(totalScore or 0)
    local level = 1

    -- TARGETS:
    -- Level 1 -> 2 = 3000 XP
    -- Level 60 at ~1,000,000 total XP
    local xpForNext = 3000
    local xpCurve = 1.048

    while true do
        if score < xpForNext then
            return {
                level = level,
                currentXP = score,
                requiredXP = xpForNext,
                percent = math.floor((score / xpForNext) * 100)
            }
        end

        score = score - xpForNext
        level = level + 1
        xpForNext = math.floor(xpForNext * xpCurve)
    end
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

RegisterNetEvent('rts:disconnectPlayer', function()
    local src = source
    DropPlayer(src, "Disconnected from WARFARE TACTICS V.")
end)

-- =======================================================================
-- ADMINISTRATIVE PIPELINES & MONITORING EXPORTS
-- =======================================================================
-- =======================================================================
-- ADMINISTRATIVE PIPELINES & MONITORING EXPORTS
-- =======================================================================

exports('GetServerOverview', function()
    local activeMatchCount, playersInMatches = 0, 0
    for _, match in pairs(Matches) do
        activeMatchCount = activeMatchCount + 1
        if match.players then
            for _ in pairs(match.players) do playersInMatches = playersInMatches + 1 end
        end
    end
    local queueCount = 0
    if MatchmakingQueue then
        for _ in pairs(MatchmakingQueue) do queueCount = queueCount + 1 end
    end
    return {
        totalOnline = GetNumPlayerIndices(),
        activeMatches = activeMatchCount,
        playersInQueue = queueCount,
        playersInGame = playersInMatches
    }
end)

exports('GetActiveMatches', function()
    local matchDetails = {}
    for matchId, match in pairs(Matches) do
        local playersList = {}
        if match.players then
            for src, pData in pairs(match.players) do
                local unitCount = 0
                if match.units and match.units[src] then
                    for _ in pairs(match.units[src]) do unitCount = unitCount + 1 end
                end
                table.insert(playersList, {
                    source = src, name = GetPlayerName(src) or "Unknown",
                    team = pData.team or 1, spawnedUnits = unitCount,
                    bucket = GetPlayerRoutingBucket(src)
                })
            end
        end
        table.insert(matchDetails, {
            matchId = matchId, mapName = match.map or "grapeseed",
            bucketId = match.bucketId or matchId, playerCount = #playersList, players = playersList
        })
    end
    return matchDetails
end)

exports('GetQueueStatus', function()
    local queueDetails = {}
    if MatchmakingQueue then
        for _, qData in ipairs(MatchmakingQueue) do
            table.insert(queueDetails, {
                source = qData.src, name = GetPlayerName(qData.src) or "Unknown",
                elapsedSeconds = os.time() - (qData.joinTime or os.time()), skillRating = qData.level or 1
            })
        end
    end
    return queueDetails
end)

RegisterNetEvent('enyo-rts:server:adminForceEnd', function(matchId)
    local src = source
    if Matches[matchId] then
        print(string.format("^1[RTS ADMIN] Match %s forcibly terminated by Admin ID: %s^7", matchId, src))
        
        -- THE FIX: Call the actual function directly!
        EndMatch(matchId, { type = "admin_terminated", winner = 0 }) 
    end
end)

-- =======================================================================
-- DISCORD LOGGING & WEBHOOK SYSTEM
-- =======================================================================


function SendDiscordLog(webhook, title, message, color)
    if webhook == nil or webhook == "" or string.find(webhook, "YOUR_") then return end
    
    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["color"] = color,
            ["footer"] = { ["text"] = "RTS Command Center • " .. os.date("%Y-%m-%d %H:%M:%S") }
        }
    }
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = "RTS Logs", embeds = embed}), { ['Content-Type'] = 'application/json' })
end

-- =======================================================================
-- 1. SYSTEM LOGS: JOINS & LEAVES
-- =======================================================================
-- =======================================================================
-- 1. SYSTEM LOGS: JOINS & LEAVES
-- =======================================================================
-- =======================================================================
-- SYSTEM JOIN/LEAVE DIAGNOSTIC LOGS
-- =======================================================================

local SystemWebhook = "https://discord.com/api/webhooks/1514205466862030878/VNd2AQtTeZXvCGkuSUzCQZYdMi52eqZp4pMgmHSmBj7Ymqb_XTOF3vPaYsdPAM8J1CUO" -- <-- PUT YOUR WEBHOOK URL HERE EXCLUSIVELY
local function SendSystemLog(title, message, color)
    if SystemWebhook == nil or SystemWebhook == "" or string.find(SystemWebhook, "YOUR_") then return end
    
    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["color"] = color,
            ["footer"] = { ["text"] = "RTS Operations Hub • " .. os.date("%Y-%m-%d %H:%M:%S") }
        }
    }
    PerformHttpRequest(SystemWebhook, function(err, text, headers) end, 'POST', json.encode({username = "RTS Core Logs", embeds = embed}), { ['Content-Type'] = 'application/json' })
end

-- HELPER FUNCTION: Extracts every piece of data available about the player
local function GetPlayerDetails(src)
    local ids = {
        license = "N/A",
        discord = "N/A",
        steam = "N/A"
    }
    
    -- Loop through all identifiers attached to this connection
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if string.match(id, '^license:') then ids.license = id end
        if string.match(id, '^steam:') then ids.steam = id end
        if string.match(id, '^discord:') then 
            -- Formats the Discord ID so it actually tags the user in the channel!
            ids.discord = string.gsub(id, "discord:", "<@") .. ">" 
        end
    end
    
    -- Fallback just in case the loop missed it during connection phase
    if ids.license == "N/A" then ids.license = GetPlayerIdentifierByType(src, 'license') or "N/A" end
    
    return ids
end

-- TARGET EVENT 1: CONNECTION INIT
RegisterServerEvent('playerConnecting')
AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    local pData = GetPlayerDetails(src)
    
    local messageStr = string.format(
        "👤 **Commander:** `%s`\n" ..
        "🔢 **Server ID:** `%s`\n" ..
        "🔑 **Rockstar:** `%s`\n" ..
        "🎮 **Steam:** `%s`\n" ..
        "💬 **Discord:** %s",
        playerName, src, pData.license, pData.steam, pData.discord
    )
    
    SendSystemLog("🔌 Commander Connecting", messageStr, 3066993) -- Green
end)

-- TARGET EVENT 2: DISCONNECT INIT
AddEventHandler('playerDropped', function(reason)
    local src = source
    local playerName = GetPlayerName(src) or "Unknown"
    local pData = GetPlayerDetails(src)
    
    local messageStr = string.format(
        "👤 **Commander:** `%s`\n" ..
        "🔢 **Server ID:** `%s`\n" ..
        "🔑 **Rockstar:** `%s`\n" ..
        "🎮 **Steam:** `%s`\n" ..
        "💬 **Discord:** %s\n\n" ..
        "🚪 **Reason:** *%s*",
        playerName, src, pData.license, pData.steam, pData.discord, reason
    )
    
    SendSystemLog("❌ Commander Disconnected", messageStr, 15158332) -- Red
end)

-- =======================================================================
-- 2. AUTOMATED GLOBAL SECURITY SCREENSHOTS
-- =======================================================================
CreateThread(function()
    while true do
        Wait(60000) -- Base 60 second timer
        
        if Webhooks.Screenshots and Webhooks.Screenshots ~= "YOUR_SCREENSHOTS_WEBHOOK_HERE" then
            local players = GetPlayers()
            
            for _, idStr in ipairs(players) do
                local src = tonumber(idStr)
                if src then
                    local pName = GetPlayerName(src) or "Unknown"
                    local pLicense = GetPlayerIdentifierByType(src, 'license') or "license:unknown"
                    
                    -- A. Determine what they are doing right now
                    local state = "Lobby / Menu"
                    if MatchmakingQueue and MatchmakingQueue[src] then state = "Waiting In Queue" end
                    for mId, match in pairs(Matches) do
                        if match.players and match.players[src] then state = "In Match (#" .. mId .. ")" end
                    end
                    
                    -- B. Get their physical server coordinates to catch escapees
                    local ped = GetPlayerPed(src)
                    local coords = GetEntityCoords(ped)
                    local locationStr = string.format("X: %.1f | Y: %.1f | Z: %.1f", coords.x, coords.y, coords.z)
                    
                    -- C. Send the text info to Discord FIRST
                    local msg = string.format("📸 **Target:** %s (ID: %s)\n**License:** `%s`\n**State:** %s\n**Location:** %s", pName, src, pLicense, state, locationStr)
                    SendDiscordLog(Webhooks.Screenshots, "Security Snap", msg, 10181046) -- Purple color

                    -- D. Tell the client to quietly snap and upload the image right under the text
                    TriggerClientEvent('enyo-rts:client:takeScreenshot', src, Webhooks.Screenshots)
                end
                
                -- CRITICAL ANTI-SPAM PROTECTON: Wait 2.5s between players so Discord doesn't ban the webhook.
                Wait(2500) 
            end
        end
    end
end)

-- =======================================================================
-- ANTI-CHEAT: UNAUTHORIZED MOVEMENT & ESCAPE DETECTION
-- =======================================================================
-- We keep track of flagged players so we don't spam the Discord every 10 seconds for the same hacker
local flaggedSpamFilter = {}

CreateThread(function()
    while true do
        Wait(10000) -- Run a fast sweep every 10 seconds
        
        if Webhooks.Alerts and Webhooks.Alerts ~= "YOUR_ALERTS_WEBHOOK_HERE" then
            local players = GetPlayers()
            local currentTime = os.time()
            
            for _, idStr in ipairs(players) do
                local src = tonumber(idStr)
                if src then
                    
                    -- 1. Check if they are a Server Admin (Admins are allowed to walk around)
                    local isAdmin = IsPlayerAceAllowed(idStr, "command.rtsadmin") or IsPlayerAceAllowed(idStr, "command")
                    
                    if not isAdmin then
                        -- 2. Check if they are legitimately fighting in a match
                        local isInMatch = false
                        for mId, match in pairs(Matches) do
                            if match.players and match.players[src] then
                                isInMatch = true
                                break
                            end
                        end
                        
                        -- 3. If they are NOT in a match, they MUST be at Z: 1000.0
                        if not isInMatch then
                            local ped = GetPlayerPed(src)
                            local coords = GetEntityCoords(ped)
                            local speed = GetEntitySpeed(ped) -- Measures how fast they are moving
                            
                            -- We check if Z is less than 500 (gives a buffer just in case of weird physics)
                            -- We also ignore exact 0.0, 0.0, 0.0 because that means their game is still loading
                            if coords.z < 500.0 and not (coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0) then
                                
                                -- 4. Only alert if we haven't alerted about this specific player in the last 60 seconds
                                if not flaggedSpamFilter[src] or (currentTime - flaggedSpamFilter[src]) > 60 then
                                    flaggedSpamFilter[src] = currentTime -- Mark them so we don't spam
                                    
                                    local pName = GetPlayerName(src) or "Unknown"
                                    local pLicense = GetPlayerIdentifierByType(src, 'license') or "license:unknown"
                                    
                                    -- Construct the High-Priority Alert
                                    local msg = string.format(
                                        "🚨 **UNAUTHORIZED ESCAPE DETECTED** 🚨\n\n" ..
                                        "👤 **Player:** %s (ID: %s)\n" ..
                                        "🔑 **License:** `%s`\n\n" ..
                                        "📍 **Location:** X: %.1f | Y: %.1f | Z: %.1f\n" ..
                                        "🏃‍♂️ **Movement Speed:** %.1f meters/sec\n\n" ..
                                        "*This player is NOT an admin and is NOT in a match, but was detected roaming the map. An automatic screenshot has been requested.*",
                                        pName, src, pLicense, coords.x, coords.y, coords.z, speed
                                    )
                                    
                                    -- Send the Red Alert
                                    SendDiscordLog(Webhooks.Alerts, "⚠️ WALL BREACH CAUGHT", msg, 16711680) -- Bright Red
                                    
                                    -- Instantly snap a picture of what they are looking at
                                    TriggerClientEvent('enyo-rts:client:takeScreenshot', src, Webhooks.Alerts)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Clean up the spam filter when a hacker leaves
AddEventHandler('playerDropped', function(reason)
    local src = source
    if flaggedSpamFilter[src] then
        flaggedSpamFilter[src] = nil
    end
end)

-- =======================================================================
-- GHOST DRIVER & UNIT SYNC FIXER THREAD
-- =======================================================================
CreateThread(function()
    while true do
        Wait(5000) -- Run a quick sweep every 2 seconds
        
        -- Only run this heavy logic if we are actively in a match
        if GameState and GameState.isInMatch then
            
            -- Loop through all units owned by this client
            if GameState.units then
                for unitId, unit in pairs(GameState.units) do
                    
                    -- Check if the unit entity physically exists in the world
                    if unit.entity and DoesEntityExist(unit.entity) then
                        
                        -- 1. Ensure the main entity (Vehicle or Ped) is forced to the network
                        if NetworkGetEntityIsNetworked(unit.entity) then
                            local netId = NetworkGetNetworkIdFromEntity(unit.entity)
                            SetNetworkIdExistsOnAllMachines(netId, true)
                            SetNetworkIdCanMigrate(netId, true)
                        end
                        
                        -- 2. If it is a Vehicle, specifically hunt down the driver!
                        if IsEntityAVehicle(unit.entity) then
                            local driverPed = GetPedInVehicleSeat(unit.entity, -1)
                            
                            if driverPed and driverPed ~= 0 and DoesEntityExist(driverPed) then
                                -- Stop the engine from deleting/culling the ped when players look away
                                SetEntityAsMissionEntity(driverPed, true, true)
                                
                                if NetworkGetEntityIsNetworked(driverPed) then
                                    local driverNetId = NetworkGetNetworkIdFromEntity(driverPed)
                                    
                                    -- FORCE FiveM to render this driver on the enemy's screen
                                    SetNetworkIdExistsOnAllMachines(driverNetId, true)
                                    SetNetworkIdCanMigrate(driverNetId, true)
                                    
                                    -- Re-link the driver to the server to prevent target lock-on failure
                                    if GameState.matchId then
                                        TriggerServerEvent('rts:registerUnitEntityDriver', GameState.matchId, unitId, driverNetId)
                                    end
                                end
                            end
                        end
                        
                    end
                end
            end
            
        end
    end
end)


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
-- CPU SPAWNER (Bulletproof Mirror Logic)
-- =======================================================================
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

    -- [[ THE FIX: SANITIZE NO-AI UNITS ON THE SERVER ]] --
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

-- =======================================================================
-- SERVER POPULATION CHECKER
-- =======================================================================
QBCore.Functions.CreateCallback('rts:getServerPlayerCount', function(source, cb)
    cb(#GetPlayers())
end)

-- =======================================================================
-- INSTANT A.I. MATCH FROM QUEUE (With Dramatic 1-Second Lobby Entry)
-- =======================================================================
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
        
        -- [[ THE FIX: Use Config.Bots just like your manual button ]] --
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