-- =============================================================================
--  ANTICHEAT MODULE - Escape detection, UI integrity, forced containment
-- =============================================================================

local flaggedSpamFilter = {}
local heartbeats = {}

-- =============================================================================
--  SERVER: Escape detection (Z < 500 = player broke out of void container)
-- =============================================================================

CreateThread(function()
    while true do
        Wait(10000)
        local currentTime = os.time()

        for _, idStr in ipairs(GetPlayers()) do
            local src = tonumber(idStr)
            if not src then goto continue end

            local isAdmin = IsPlayerAceAllowed(idStr, "command.rtsadmin") or IsPlayerAceAllowed(idStr, "command")
            if isAdmin then goto continue end

            local isInMatch = false
            for _, match in pairs(Matches) do
                if match.players and match.players[src] then isInMatch = true break end
            end
            if isInMatch then goto continue end

            local ped = GetPlayerPed(src)
            local coords = GetEntityCoords(ped)
            local speed = GetEntitySpeed(ped)

            if coords.z < 500.0 and not (coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0) then
                if not flaggedSpamFilter[src] or (currentTime - flaggedSpamFilter[src]) > 60 then
                    flaggedSpamFilter[src] = currentTime

                    local pName = GetPlayerName(src) or "Unknown"
                    local pLicense = GetPlayerIdentifierByType(src, 'license') or "license:unknown"

                    local webhook = Config.DiscordWebhooks.Alerts
                    if webhook and webhook ~= "" then
                        SendDiscordLog(webhook, "Escape Caught",
                            string.format("**%s** (ID: %s)\nLicense: `%s`\nPos: %.1f, %.1f, %.1f | Speed: %.1f",
                                pName, src, pLicense, coords.x, coords.y, coords.z, speed), 16711680)
                        TriggerClientEvent('enyo-rts:client:takeScreenshot', src, webhook)
                    end

                    print("^1[RTS SECURITY] " .. pName .. " escaped containment. Kicking.^7")
                    DropPlayer(src, "Unauthorized escape from RTS containment")
                end
            end

            ::continue::
        end
    end
end)

-- =============================================================================
--  SERVER: UI integrity heartbeat (detect NUI-hide exploits)
-- =============================================================================

RegisterNetEvent('rts:anticheat:heartbeat', function()
    heartbeats[source] = 0
end)

CreateThread(function()
    while true do
        Wait(15000)

        for _, idStr in ipairs(GetPlayers()) do
            local src = tonumber(idStr)
            if not src then goto skip end

            local isAdmin = IsPlayerAceAllowed(idStr, "command.rtsadmin") or IsPlayerAceAllowed(idStr, "command")
            if isAdmin then goto skip end

            local isInMatch = false
            for _, match in pairs(Matches) do
                if match.players and match.players[src] then isInMatch = true break end
            end
            if isInMatch then goto skip end

            -- Increment miss counter, send challenge
            heartbeats[src] = (heartbeats[src] or 0) + 1
            TriggerClientEvent('rts:anticheat:requestHeartbeat', src)

            if heartbeats[src] >= 2 then
                local pName = GetPlayerName(src) or "Unknown"
                print("^1[RTS SECURITY] " .. pName .. " missed UI heartbeat (" .. heartbeats[src] .. "). Kicking.^7")

                local webhook = Config.DiscordWebhooks.Alerts
                if webhook and webhook ~= "" then
                    SendDiscordLog(webhook, "UI Tamper Detected",
                        string.format("**%s** (ID: %s)\nMissed %d heartbeat(s) - possible NUI hide exploit",
                            pName, src, heartbeats[src]), 16711680)
                    TriggerClientEvent('enyo-rts:client:takeScreenshot', src, webhook)
                end
                DropPlayer(src, "UI integrity check failed")
                heartbeats[src] = nil
            end

            ::skip::
        end
    end
end)

-- =============================================================================
--  CLEANUP
-- =============================================================================

AddEventHandler('playerDropped', function()
    local src = source
    flaggedSpamFilter[src] = nil
    heartbeats[src] = nil
end)

RegisterNetEvent('rts:disconnectPlayer', function()
    DropPlayer(source, "Disconnected from RTS WARFARE")
end)
