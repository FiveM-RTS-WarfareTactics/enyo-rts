-- ====================================================================================
--  COMMANDS MODULE: /rts, /rtsadmin, admin force-start/force-end events
-- ====================================================================================

RegisterCommand("rts", function(source, args, raw)
    TriggerClientEvent('rts:openMenu', source)
end, false)

RegisterCommand("rtsadmin", function(source, args, raw)
    if source > 0 then
        local hasPerms = IsPlayerAceAllowed(source, "command") or IsPlayerAceAllowed(source, "command.rtsadmin")
        if not hasPerms then
            TriggerClientEvent('chat:addMessage', source, { color = {255, 0, 0}, args = {"[RTS SYSTEM]", "Access Denied. Command restricted to Server Command."} })
            return
        end
    end

    local action = args[1]
    if action == "list" then
        print("Active Matches: " .. GetTableSize(Matches))
    elseif action == "cleanup" then
        for matchId in pairs(Matches) do EndMatch(matchId, { type = "admin", winner = nil }) end
        TriggerClientEvent('chat:addMessage', source, { color = {0, 255, 0}, args = {"[RTS]", "Cleanup Complete"} })
    elseif action == "forcestart" then
        if PlayerStates[source] and PlayerStates[source].lobbyId then
            TriggerClientEvent('rts:client:adminForceStart', source)
        else
            TriggerClientEvent('chat:addMessage', source, { color = {255, 0, 0}, args = {"[RTS]", "You must be in a lobby to force start."} })
        end
    end
end, true)

RegisterNetEvent('rts:server:executeForceStart', function()
    local src = source
    if PlayerStates[src] and PlayerStates[src].lobbyId then
        local lobbyCode = PlayerStates[src].lobbyId
        local lobby = Lobbies[lobbyCode]
        if lobby then
            lobby.forceStart = true
            StartMatchFromLobby(lobbyCode)
            TriggerClientEvent('chat:addMessage', src, { color = {0, 255, 0}, args = {"[RTS]", "Admin Force Start Initiated"} })
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

RegisterNetEvent('enyo-rts:server:adminForceEnd', function(matchId)
    local src = source
    if Matches[matchId] then
        print(string.format("^1[RTS ADMIN] Match %s forcibly terminated by Admin ID: %s^7", matchId, src))
        EndMatch(matchId, { type = "admin_terminated", winner = 0 })
    end
end)
