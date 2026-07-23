-- Discord Webhooks (set in config.lua)
Webhooks = Config.Webhooks or {}

function GetRTSName(source)
    return GetPlayerName(source)
end

-- Standalone Callback System
RTS = {}
RTS.Callbacks = {}

local ServerCallbacks = {}

RTS.RegisterCallback = function(name, cb)
    ServerCallbacks[name] = cb
end

RegisterNetEvent('rts:standalone:triggerCallback', function(name, requestId, ...)
    local src = source
    Citizen.CreateThread(function()
        if ServerCallbacks[name] then
            ServerCallbacks[name](src, function(...)
                TriggerClientEvent('rts:standalone:callbackResponse', src, requestId, ...)
            end, ...)
        else
            print("^1[RTS] Missing Callback: " .. name .. "^7")
        end
    end)
end)

RTS.GetPlayer = function(source)
    local name = GetPlayerName(source)
    if not name then return nil end
    local license = GetPlayerIdentifierByType(source, 'license')
    return {
        PlayerData = {
            source = source,
            citizenid = license or "",
            charinfo = { firstname = name, lastname = "" }
        },
        Functions = { AddMoney = function() end, RemoveMoney = function() end }
    }
end

math.randomseed(os.time())

-- Global State
Matches = {}
Lobbies = {}
PlayerStates = {}
GameBuckets = {}
PlayerStats = {}
MatchmakingQueue = {}

function DebugPrint(msg)
    if Config.DebugMode then print("^5[RTS]^7 " .. msg) end
end

function GetPlayerIdentifier(playerId)
    return tostring(playerId)
end

function GetOrCreatePlayerStats(playerId)
    local id = GetPlayerIdentifier(playerId)
    PlayerStats[id] = PlayerStats[id] or { wins = 0, losses = 0, kills = 0, matches = 0, totalDamage = 0, unitsDestroyed = 0 }
    return PlayerStats[id]
end

-- Disconnect handler
AddEventHandler('playerDropped', function(reason)
    local src = source
    if PlayerStates[src] then TriggerEvent('rts:leaveLobby', src) end
    local matchId, match = GetPlayerMatch(src)
    if match and match.active then
        EndMatch(matchId, { type = "disconnect", winner = GetEnemyPlayer(src, match) })
    end
end)

-- Resource start
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        DebugPrint("Tactical RTS server started")
        Matches, Lobbies, PlayerStates, GameBuckets = {}, {}, {}, {}
        for _, pid in ipairs(GetPlayers()) do SetPlayerRoutingBucket(tonumber(pid), 0) end
        DebugPrint("Game states cleared")
    end
end)

-- Exports
exports('GetActiveMatches', function() return Matches end)
exports('GetActiveLobbies', function() return Lobbies end)
exports('GetPlayerStats', function(pid) return GetOrCreatePlayerStats(pid) end)

exports('GetServerOverview', function()
    local am, pim = 0, 0
    for _, m in pairs(Matches) do am = am + 1; pim = pim + (m.players and GetTableSize(m.players) or 0) end
    return { totalOnline = GetNumPlayerIndices(), activeMatches = am, playersInQueue = MatchmakingQueue and #MatchmakingQueue or 0, playersInGame = pim }
end)

exports('GetActiveMatchDetails', function()
    local details = {}
    for mid, m in pairs(Matches) do
        local pl = {}
        if m.players then
            for src, pd in pairs(m.players) do
                local uc = 0
                if m.units then for _, u in pairs(m.units) do if u.owner == src then uc = uc + 1 end end end
                table.insert(pl, { source = src, name = GetPlayerName(src) or "?", team = pd.team or 1, spawnedUnits = uc, bucket = GetPlayerRoutingBucket(src) })
            end
        end
        table.insert(details, { matchId = mid, mapName = m.map or "grapeseed", bucketId = m.bucket or mid, playerCount = #pl, players = pl })
    end
    return details
end)

exports('GetQueueStatus', function()
    local qd = {}
    if MatchmakingQueue then
        for _, q in ipairs(MatchmakingQueue) do
            table.insert(qd, { source = q.src, name = GetPlayerName(q.src) or "?", elapsed = os.time() - (q.joinTime or os.time()), level = q.level or 1 })
        end
    end
    return qd
end)

RegisterNetEvent('rts:disconnectPlayer', function()
    DropPlayer(source, "Disconnected from RTS Warfare")
end)

-- Discord Logging
function SendDiscordLog(webhook, title, message, color)
    if not webhook or webhook == "" then return end
    PerformHttpRequest(webhook, function() end, 'POST',
        json.encode({ username = "RTS Logs", embeds = {{ title = title, description = message, color = color, footer = { text = "RTS Command Center - " .. os.date("%Y-%m-%d %H:%M:%S") }} }}),
        { ['Content-Type'] = 'application/json' })
end

local function SendSystemLog(title, message, color)
    if not Webhooks.System or Webhooks.System == "" then return end
    PerformHttpRequest(Webhooks.System, function() end, 'POST',
        json.encode({ username = "RTS Core", embeds = {{ title = title, description = message, color = color, footer = { text = "RTS Operations - " .. os.date("%Y-%m-%d %H:%M:%S") }} }}),
        { ['Content-Type'] = 'application/json' })
end

local function GetPlayerDetails(src)
    local ids = { license = "N/A", discord = "N/A", steam = "N/A" }
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if string.match(id, '^license:') then ids.license = id end
        if string.match(id, '^steam:') then ids.steam = id end
        if string.match(id, '^discord:') then ids.discord = string.gsub(id, "discord:", "<@") .. ">" end
    end
    if ids.license == "N/A" then ids.license = GetPlayerIdentifierByType(src, 'license') or "N/A" end
    return ids
end

-- Join/Leave Logs
AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src, d = source, GetPlayerDetails(source)
    SendSystemLog("Connecting", string.format("Name: %s (ID: %s) | License: %s | Steam: %s | Discord: %s", playerName, src, d.license, d.steam, d.discord), 3066993)
end)

AddEventHandler('playerDropped', function(reason)
    local src, d = source, GetPlayerDetails(source)
    SendSystemLog("Disconnected", string.format("Name: %s (ID: %s) | License: %s | Steam: %s | Discord: %s | Reason: %s", GetPlayerName(src) or "?", src, d.license, d.steam, d.discord, reason), 15158332)
end)

-- Security Screenshots
CreateThread(function()
    while true do
        Wait(60000)
        if Webhooks.Screenshots and Webhooks.Screenshots ~= "" then
            for _, idStr in ipairs(GetPlayers()) do
                local src = tonumber(idStr)
                if src and GetPlayerName(src) then
                    local state = "Menu"
                    for _, m in pairs(Matches) do if m.players and m.players[src] then state = "In Match" end end
                    local c = GetEntityCoords(GetPlayerPed(src))
                    SendDiscordLog(Webhooks.Screenshots, "Security Snap", string.format("Target: %s (ID: %s) | State: %s | Loc: %.1f, %.1f, %.1f", GetPlayerName(src), src, state, c.x, c.y, c.z), 10181046)
                    TriggerClientEvent('enyo-rts:client:takeScreenshot', src, Webhooks.Screenshots)
                end
                Wait(2500)
            end
        end
    end
end)

-- Anti-Cheat: Escape Detection
local flagged = {}

CreateThread(function()
    while true do
        Wait(10000)
        if Webhooks.Alerts and Webhooks.Alerts ~= "" then
            local now = os.time()
            for _, idStr in ipairs(GetPlayers()) do
                local src = tonumber(idStr)
                if src and not IsPlayerAceAllowed(idStr, "command") then
                    local inMatch = false
                    for _, m in pairs(Matches) do if m.players and m.players[src] then inMatch = true break end end
                    if not inMatch then
                        local c = GetEntityCoords(GetPlayerPed(src))
                        if c.z < 500.0 and not (c.x == 0 and c.y == 0 and c.z == 0) then
                            if not flagged[src] or (now - flagged[src]) > 60 then
                                flagged[src] = now
                                local name = GetPlayerName(src) or "?"
                                SendDiscordLog(Webhooks.Alerts, "Escape Detected", string.format("Name: %s (ID: %s) | Loc: %.1f, %.1f, %.1f | Speed: %.1f", name, src, c.x, c.y, c.z, GetEntitySpeed(GetPlayerPed(src))), 16711680)
                                TriggerClientEvent('enyo-rts:client:takeScreenshot', src, Webhooks.Alerts)
                            end
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function() flagged[source] = nil end)

-- Player Count Callback
RTS.RegisterCallback('rts:getServerPlayerCount', function(source, cb)
    cb(#GetPlayers())
end)
