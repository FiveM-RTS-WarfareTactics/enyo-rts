-- ====================================================================================
--  COMMANDS MODULE: /rts, /rtsadmin, admin force-start/force-end events
-- ====================================================================================

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

RegisterNetEvent('enyo-rts:server:adminForceEnd', function(matchId)
    local src = source
    if Matches[matchId] then
        print(string.format("^1[RTS ADMIN] Match %s forcibly terminated by Admin ID: %s^7", matchId, src))
        
        -- THE FIX: Call the actual function directly!
        EndMatch(matchId, { type = "admin_terminated", winner = 0 }) 
    end
end)
