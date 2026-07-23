-- Discord Webhooks (set in config.lua)
Webhooks = Config.Webhooks or {}

-- 1. Safe Name Helper
function GetRTSName(source)
    return GetPlayerName(source)
end

-- 2. Standalone Initialization
RTS = {}
RTS.Callbacks = {}


local ServerCallbacks = {}

-- Standalone Callback Registry
RTS.RegisterCallback = function(name, cb)
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

-- Standalone Player Mock (Persistent Version)
RTS.GetPlayer = function(source)
    local nativeName = GetPlayerName(source)
    if not nativeName then return nil end
    
    local identifier = GetPlayerIdentifierByType(source, 'license')
    
    if not identifier then identifier = "rts_local_" .. GetPlayerName(source) end
    
    return {
        PlayerData = {
            source = source,
            citizenid = identifier,
            charinfo = { firstname = nativeName, lastname = "" }
        },
        Functions = {
            AddMoney = function() end,
            RemoveMoney = function() end
        }
    }
end
math.randomseed(os.time()) -- do this once, usually at script start
Config.MatchSettings.MaxPlayers = 2

-- ====================================================================================
--  GLOBAL STATE TABLES (shared across modules)
-- ====================================================================================
Matches = {}
Lobbies = {}
PlayerStates = {}
GameBuckets = {}
Config.MatchSettings.GameBucketStart =  math.random(100, 9000)
local currentBucket = Config.MatchSettings.GameBucketStart
PlayerStats = {}
MatchmakingQueue = {}

-- ====================================================================================
--  HELPER FUNCTIONS (used across modules)
-- ====================================================================================
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

RegisterNetEvent('rts:disconnectPlayer', function()
    local src = source
    DropPlayer(src, "Disconnected from WARFARE TACTICS V.")
end)

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

local function SendSystemLog(title, message, color)
    local webhook = Webhooks.System
    if not webhook or webhook == "" then return end
    
    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["color"] = color,
            ["footer"] = { ["text"] = "RTS Operations Hub • " .. os.date("%Y-%m-%d %H:%M:%S") }
        }
    }
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = "RTS Core Logs", embeds = embed}), { ['Content-Type'] = 'application/json' })
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
-- SERVER POPULATION CHECKER
-- =======================================================================
RTS.RegisterCallback('rts:getServerPlayerCount', function(source, cb)
    cb(#GetPlayers())
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
