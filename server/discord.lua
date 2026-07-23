-- =============================================================================
--  DISCORD LOGGING MODULE - Configurable webhooks
-- =============================================================================

local Webhooks = Config.DiscordWebhooks or {}
local SystemWebhook = Config.DiscordWebhooks.System or ""

function SendDiscordLog(webhook, title, message, color)
    if not webhook or webhook == "" then return end

    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["color"] = color or 3447003,
            ["footer"] = { ["text"] = "RTS Command Center - " .. os.date("%Y-%m-%d %H:%M:%S") }
        }
    }
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST',
        json.encode({ username = "RTS Logs", embeds = embed }),
        { ['Content-Type'] = 'application/json' })
end

local function SendSystemLog(title, message, color)
    if not SystemWebhook or SystemWebhook == "" then return end
    SendDiscordLog(SystemWebhook, title, message, color or 3066993)
end

-- =============================================================================
--  PLAYER CONNECT/DISCONNECT LOGS
-- =============================================================================

local function GetPlayerDetails(src)
    local ids = { license = "N/A", discord = "N/A", steam = "N/A" }
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if string.match(id, '^license:') then ids.license = id end
        if string.match(id, '^steam:') then ids.steam = id end
        if string.match(id, '^discord:') then
            ids.discord = string.gsub(id, "discord:", "<@") .. ">"
        end
    end
    if ids.license == "N/A" then ids.license = GetPlayerIdentifierByType(src, 'license') or "N/A" end
    return ids
end

AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    if not SystemWebhook or SystemWebhook == "" then return end
    local pData = GetPlayerDetails(src)
    local msg = string.format(
        "**Commander:** `%s`\n**Server ID:** `%s`\n**Rockstar:** `%s`\n**Steam:** `%s`\n**Discord:** %s",
        playerName, src, pData.license, pData.steam, pData.discord
    )
    SendSystemLog("Commander Connecting", msg)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if not SystemWebhook or SystemWebhook == "" then return end
    local playerName = GetPlayerName(src) or "Unknown"
    local pData = GetPlayerDetails(src)
    local msg = string.format(
        "**Commander:** `%s`\n**Server ID:** `%s`\n**Rockstar:** `%s`\n**Steam:** `%s`\n**Discord:** %s\n\n**Reason:** *%s*",
        playerName, src, pData.license, pData.steam, pData.discord, reason
    )
    SendSystemLog("Commander Disconnected", msg, 15158332)
end)

-- =============================================================================
--  AUTOMATED SCREENSHOTS
-- =============================================================================

CreateThread(function()
    while true do
        Wait(60000)

        if Webhooks.Screenshots and Webhooks.Screenshots ~= "" then
            local players = GetPlayers()
            for _, idStr in ipairs(players) do
                local src = tonumber(idStr)
                if src then
                    local pName = GetPlayerName(src) or "Unknown"
                    local pLicense = GetPlayerIdentifierByType(src, 'license') or "license:unknown"

                    local state = "Lobby / Menu"
                    for mId, match in pairs(Matches) do
                        if match.players and match.players[src] then state = "In Match (#" .. mId .. ")" end
                    end

                    local ped = GetPlayerPed(src)
                    local coords = GetEntityCoords(ped)
                    local locationStr = string.format("X: %.1f | Y: %.1f | Z: %.1f", coords.x, coords.y, coords.z)

                    local msg = string.format("**Target:** %s (ID: %s)\n**License:** `%s`\n**State:** %s\n**Location:** %s",
                        pName, src, pLicense, state, locationStr)

                    SendDiscordLog(Webhooks.Screenshots, "Security Snap", msg, 10181046)
                    TriggerClientEvent('enyo-rts:client:takeScreenshot', src, Webhooks.Screenshots)

                    Wait(2500)
                end
            end
        end
    end
end)
