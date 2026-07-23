-- =============================================================================
--  LOBBY MODULE - Handles lobby creation, joining, ready system
-- =============================================================================

Lobbies = {}
PlayerStates = {}

local function GenerateLobbyCode()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local code = ""
    for _ = 1, Config.Lobby.CodeLength do
        code = code .. chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return code
end

function GetLobbyDataPayload(lobby)
    local playersData = {}
    for _, pid in ipairs(lobby.players) do
        local isReady = false
        for _, readyId in ipairs(lobby.readyPlayers) do
            if tostring(readyId) == tostring(pid) then isReady = true break end
        end

        local pName
        if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then
            pName = PlayerStates[pid] and PlayerStates[pid].playerName or "A.I. COMMANDER [AI]"
        else
            pName = GetPlayerName(pid)
        end

        table.insert(playersData, {
            name = pName,
            isReady = isReady,
            isHost = (tostring(pid) == tostring(lobby.host))
        })
    end

    return {
        lobbyCode = lobby.code,
        playersData = playersData,
        hostName = GetPlayerName(lobby.host),
        map = lobby.map,
        status = lobby.status
    }
end

local function BroadcastLobbyUpdate(lobby)
    local payload = GetLobbyDataPayload(lobby)
    for _, pid in ipairs(lobby.players) do
        if type(pid) == "number" then
            TriggerClientEvent('rts:updateLobby', pid, payload)
        end
    end
end

local function TriggerLaunchSequence(lobby)
    if lobby.status == "waiting"
        and #lobby.players == Config.MatchSettings.MaxPlayers
        and #lobby.readyPlayers == Config.MatchSettings.MaxPlayers
    then
        lobby.status = "starting"

        local token = math.random(10000, 99999)
        lobby.launchToken = token

        for _, pid in ipairs(lobby.players) do
            if type(pid) == "number" then
                TriggerClientEvent('rts:startCountdown', pid, Config.Lobby.ReadyCheckDuration)
            end
        end

        SetTimeout(Config.Lobby.ReadyCheckDuration * 1000, function()
            if lobby.launchToken == token then
                StartMatchFromLobby(lobby.code)
            end
        end)
    end
end

-- =============================================================================
--  SERVER CALLBACKS
-- =============================================================================

RegisterServerCallback('rts:createLobby', function(source, cb, mapName)
    local src = source
    local myName = GetRTSName(src)

    local lobbyCode = GenerateLobbyCode()
    local maxAttempts = 20
    local attempts = 0
    while Lobbies[lobbyCode] and attempts < maxAttempts do
        lobbyCode = GenerateLobbyCode()
        attempts = attempts + 1
    end

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
        maxPlayers = Config.MatchSettings.MaxPlayers
    }

    PlayerStates[src] = {
        lobbyId = lobbyCode,
        ready = false,
        platoons = {},
        isHost = true,
        playerName = myName
    }

    cb({
        success = true,
        code = lobbyCode,
        hostName = myName,
        playersData = { { name = myName, isReady = false, isHost = true } }
    })
end)

RegisterServerCallback('rts:joinLobby', function(source, cb, lobbyCode)
    local src = source
    local cleanCode = string.upper(lobbyCode or ""):gsub("%s+", "")
    local lobby = Lobbies[cleanCode]

    if not lobby then return cb({ success = false, message = "Lobby not found" }) end

    for _, pid in ipairs(lobby.players) do
        if pid == src then
            return cb({ success = true, hostName = lobby.hostName, isHost = (lobby.host == src), lobbyData = GetLobbyDataPayload(lobby) })
        end
    end

    if #lobby.players >= lobby.maxPlayers then
        return cb({ success = false, message = "Lobby is full" })
    end

    local isNewHost = false
    if not lobby.host then
        lobby.host = src
        lobby.hostName = GetPlayerName(src)
        isNewHost = true
        table.insert(lobby.players, 1, src)
    else
        table.insert(lobby.players, src)
    end

    PlayerStates[src] = {
        lobbyId = cleanCode,
        ready = false,
        platoons = {},
        isHost = isNewHost,
        playerName = GetPlayerName(src)
    }

    BroadcastLobbyUpdate(lobby)

    cb({ success = true, hostName = lobby.hostName, isHost = isNewHost, lobbyData = GetLobbyDataPayload(lobby) })
end)

-- =============================================================================
--  NETWORK EVENTS
-- =============================================================================

RegisterNetEvent('rts:leaveLobby', function()
    local src = source
    local state = PlayerStates[src]
    if not state then return end

    local lobbyCode = state.lobbyId
    local lobby = Lobbies[lobbyCode]

    if lobby then
        for i, pid in ipairs(lobby.players) do
            if pid == src then table.remove(lobby.players, i) break end
        end
        for i, pid in ipairs(lobby.readyPlayers) do
            if pid == src then table.remove(lobby.readyPlayers, i) break end
        end

        if lobby.host == src then
            for _, pid in ipairs(lobby.players) do
                if type(pid) == "number" then
                    NotifyPlayer(pid, "Host left the lobby", "error")
                    PlayerStates[pid] = nil
                    TriggerClientEvent('rts:resetUI', pid)
                end
            end
            Lobbies[lobbyCode] = nil
        else
            BroadcastLobbyUpdate(lobby)
        end
    end

    PlayerStates[src] = nil
    TriggerClientEvent('rts:resetUI', src)
end)

RegisterNetEvent('rts:setReady', function(isReady)
    local src = source
    local state = PlayerStates[src]
    if not state then return end

    local lobby = Lobbies[state.lobbyId]
    if not lobby then return end

    state.ready = isReady

    if isReady then
        local found = false
        for _, p in ipairs(lobby.readyPlayers) do
            if p == src then found = true end
        end
        if not found then table.insert(lobby.readyPlayers, src) end
    else
        for i, pid in ipairs(lobby.readyPlayers) do
            if pid == src then table.remove(lobby.readyPlayers, i) break end
        end

        if lobby.status == "starting" then
            lobby.status = "waiting"
            lobby.launchToken = nil
            for _, pid in ipairs(lobby.players) do
                if type(pid) == "number" then
                    TriggerClientEvent('rts:abortCountdown', pid)
                end
            end
        end
    end

    BroadcastLobbyUpdate(lobby)
    TriggerLaunchSequence(lobby)
end)

-- =============================================================================
--  BOT TOGGLE SYSTEM
-- =============================================================================

RegisterNetEvent('rts:server:toggleBot', function(action)
    local src = source
    local state = PlayerStates[src]
    if not state or not state.lobbyId then return end

    local lobby = Lobbies[state.lobbyId]
    if not lobby or lobby.host ~= src then return end

    if state.ready then
        NotifyPlayer(src, "Unready before modifying the lobby.", "error")
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
            if type(pid) == "string" and string.sub(pid, 1, 4) == "bot_" then
                table.remove(lobby.readyPlayers, i)
                break
            end
        end
    end

    BroadcastLobbyUpdate(lobby)
    TriggerLaunchSequence(lobby)
end)

-- =============================================================================
--  PLATOON SAVING
-- =============================================================================

RegisterNetEvent('rts:savePlatoons', function(platoons)
    local src = source
    if not PlayerStates[src] then return end

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

    PlayerStates[src].platoons = formattedPlatoons

    -- Sync to active match (for CPU mirror)
    local matchId, match = GetPlayerMatch(src)
    if match then
        if match.players[src] then
            match.players[src].platoons = formattedPlatoons
        end
        if match.isCpuMatch and match.players["CPU"] then
            match.players["CPU"].platoons = formattedPlatoons
        end
    end
end)

return {
    Lobbies = Lobbies,
    PlayerStates = PlayerStates,
    GetLobbyDataPayload = GetLobbyDataPayload,
}
