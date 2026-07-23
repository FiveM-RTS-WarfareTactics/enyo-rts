-- =============================================================================
--  RTS SERVER - ENTRY POINT
-- =============================================================================

-- Global state (accessed by modules)
Matches = {}
Lobbies = {}
PlayerStates = {}
GameBuckets = {}
ClientCallbacks = {}

-- =============================================================================
--  STANDALONE CALLBACK SYSTEM
-- =============================================================================

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

-- =============================================================================
--  INITIALIZATION
-- =============================================================================

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        DebugPrint("Tactical RTS Server started")

        -- Cleanup any existing states
        Matches = {}
        Lobbies = {}
        PlayerStates = {}
        GameBuckets = {}
        MatchmakingQueue = {}

        local players = GetPlayers()
        for i = 1, #players do
            SetPlayerRoutingBucket(tonumber(players[i]), 0)
        end
        DebugPrint("Game states cleared")
    end
end)

-- =============================================================================
--  DISCONNECT HANDLER
-- =============================================================================

AddEventHandler('playerDropped', function(reason)
    local src = source

    -- Handle lobby disconnect
    if PlayerStates[src] then
        TriggerEvent('rts:leaveLobby', src)
    end

    -- Handle match disconnect
    local matchId, match = GetPlayerMatch(src)
    if match and match.active then
        local winner = GetEnemyPlayer(src, match)
        EndMatch(matchId, { type = "disconnect", winner = winner })
    end
end)

-- =============================================================================
--  CAMERA POSITION TRACKING
-- =============================================================================

RegisterNetEvent('rts:updateCameraPosition', function(position)
    local src = source
    local matchId, match = GetPlayerMatch(src)
    if match and match.players[src] then
        match.players[src].lastCameraPos = position
    end
end)
