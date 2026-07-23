-- =============================================================================
--  COMMANDS MODULE - Admin commands
-- =============================================================================

RegisterCommand('rtsadmin', function(source, args, raw)
    if source > 0 then
        local hasPerms = IsPlayerAceAllowed(source, "command") or IsPlayerAceAllowed(source, "command.rtsadmin")
        if not hasPerms then return end
    end

    local action = args[1]
    if action == "list" then
        local count = 0
        for _ in pairs(Matches) do count = count + 1 end
        print("^2[RTS] Active Matches: " .. count .. "^7")
    elseif action == "cleanup" then
        for matchId in pairs(Matches) do
            EndMatch(matchId, { type = "admin", winner = nil })
        end
        print("^2[RTS] All matches terminated.^7")
    elseif action == "forcestart" then
        if PlayerStates[source] and PlayerStates[source].lobbyId then
            TriggerClientEvent('rts:client:adminForceStart', source)
        else
            print("^1[RTS] Source not in lobby.^7")
        end
    else
        print("^2[RTS Admin] Usage: /rtsadmin [list|cleanup|forcestart]^7")
    end
end, false)

RegisterNetEvent('rts:server:executeForceStart', function()
    local src = source
    if PlayerStates[src] and PlayerStates[src].lobbyId then
        local lobby = Lobbies[PlayerStates[src].lobbyId]
        if lobby then
            lobby.forceStart = true
            StartMatchFromLobby(PlayerStates[src].lobbyId)
        end
    end
end)

RegisterNetEvent('enyo-rts:server:adminForceEnd', function(matchId)
    local src = source
    if Matches[matchId] then
        print(string.format("^1[RTS ADMIN] Match %s terminated by Admin %s^7", matchId, src))
        EndMatch(matchId, { type = "admin_terminated", winner = 0 })
    end
end)
